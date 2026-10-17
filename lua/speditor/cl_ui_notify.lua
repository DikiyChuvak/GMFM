--[[
SPeditor — its own notifications (the editor's pop-up messages).

While the editor is open, SPeditor.Notify messages are shown not as stock
GMod hints but as cards over all windows. A card: an icon and a colour by message
kind, text with line wrapping, a repeat counter. After a few seconds the card
leaves. Cards do not capture the mouse — you can work underneath them.

Kinds: 0 — info, 1 — error, 2 — success, 3 — saving (no sound).

The look is set in View → Interface settings → Notifications (cl_ui_settings.lua):
  style      speditor_notify_style  auto (follows the theme) / speditor / gmod / aero /
                                    flat / solid / vanilla / xp / console
  animation  speditor_notify_anim   auto / fade / slide / gmod (the stock spring with a
                                    swing before leaving) / drop / pop / none
  place      speditor_notify_pos    br / bl / tr / tl / bc / tc (corners and centres)
  speditor_notify_width (px), speditor_notify_max (cards at once), speditor_notify_opacity (%),
  speditor_notify_bar (a line showing the time left), speditor_notify_soundset
  (speditor / gmod / soft), speditor_notify (show), speditor_notify_sound (sound),
  speditor_notify_time (how many seconds a card stays).

All messages are written to a log (Windows → Notifications → Message log).

API:
  UI.Toast(text, kind)      show a card (called by SPeditor.Notify)
  UI.ClearToasts()          remove all cards
  UI.NotifyStyles / UI.NotifyAnims / UI.NotifyPlaces / UI.NotifySoundSets   choices (id lists)
  UI.NotifyLog              the log: { { time, text, kind }, … }
  UI.OpenNotifyLog()        the log window
  UI.BuildNotifyMenu(menu)  items of the "Notifications" menu
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI  = SPeditor.UI
local C   = SPeditor.Client
local L   = SPeditor.L
local COL = UI.PAL

local cvShow    = CreateClientConVar("speditor_notify", "1", true, false)
local cvSound   = CreateClientConVar("speditor_notify_sound", "1", true, false)
local cvTime    = CreateClientConVar("speditor_notify_time", "4", true, false)
local cvStyle   = CreateClientConVar("speditor_notify_style", "auto", true, false)
local cvAnim    = CreateClientConVar("speditor_notify_anim", "auto", true, false)
local cvPos     = CreateClientConVar("speditor_notify_pos", "br", true, false)
local cvWidth   = CreateClientConVar("speditor_notify_width", "380", true, false)
local cvMax     = CreateClientConVar("speditor_notify_max", "6", true, false)
local cvOpacity = CreateClientConVar("speditor_notify_opacity", "100", true, false)
local cvBar     = CreateClientConVar("speditor_notify_bar", "0", true, false)
local cvSndSet  = CreateClientConVar("speditor_notify_soundset", "speditor", true, false)

local MAX_LOG  = 200
local MARGIN   = 8          -- from the screen edge and between cards
local TOP_H    = 24         -- menu bar
local STATUS_H = 20
local function metrics() TOP_H, STATUS_H = SPeditor.UI.S(24), SPeditor.UI.S(20) end
metrics()
hook.Add("SPeditor_FontsCreated", "SPeditor.NotifyMetrics", metrics)
local IN_T, OUT_T = 0.25, 0.35

local KINDS = {
	[0] = { icon = "icon16/information.png", color = function() return COL.BLUE end,   gmod = "vgui/notices/generic" },
	[1] = { icon = "icon16/exclamation.png", color = function() return COL.RED end,    gmod = "vgui/notices/error", long = 1.5 },
	[2] = { icon = "icon16/accept.png",      color = function() return COL.GREEN end,  gmod = "vgui/notices/undo" },
	[3] = { icon = "icon16/disk.png",        color = function() return COL.ORANGE end, gmod = "vgui/notices/generic" },
}

-- Sound sets: id -> { name, [kind] = path }. A path is relative to sound/ (played by
-- surface.PlaySound) or starts with "data/" (a file in garrysmod/data, played by
-- sound.PlayFile). Kind 3 (saving) is silent unless a set has a sound for it.
-- More sets: UI.AddNotifySoundSet (packs in sound/speditor/notify/<id>/, sets in
-- data/speditor/sounds/<id>/, imported from installed addons — cl_ui_notify_custom.lua).
local SOUNDS = {
	speditor = { [0] = "buttons/button14.wav", [1] = "buttons/button10.wav", [2] = "buttons/button14.wav" },
	-- Sandbox: a drip for hints, the undo click, the error buzz
	gmod     = { [0] = "ambient/water/drip%d.wav", [1] = "buttons/button10.wav", [2] = "buttons/button15.wav" },
	soft     = { [0] = "garrysmod/ui_click.wav", [1] = "garrysmod/ui_return.wav", [2] = "garrysmod/ui_click.wav" },
}
UI.NotifySoundSets = { "speditor", "gmod", "soft" }
UI.NotifySoundSetDefs = SOUNDS

-- "custom": a sound chosen for every kind (speditor_notify_snd_0 … _3)
local cvSnd = {}
for k = 0, 3 do cvSnd[k] = CreateClientConVar("speditor_notify_snd_" .. k, "", true, false) end

function UI.AddNotifySoundSet(id, def)
	if not SOUNDS[id] then table.insert(UI.NotifySoundSets, id) end
	SOUNDS[id] = def
end

function UI.RemoveNotifySoundSet(id)
	SOUNDS[id] = nil
	table.RemoveByValue(UI.NotifySoundSets, id)
end

function UI.NotifySoundSetName(id)
	if id == "custom" then return L("nsnd_custom") end
	local key = "nsnd_" .. id
	local str = L(key)
	if str ~= key then return str end
	return (SOUNDS[id] and SOUNDS[id].name) or id
end

-- Play a sound path (see above); a "%d" in it is a random variant 1–4
function UI.PlayNotifyPath(path)
	if not isstring(path) or path == "" then return end
	if string.find(path, "%d", 1, true) then path = string.format(path, math.random(1, 4)) end
	if string.StartWith(path, "data/") then
		sound.PlayFile(path, "noblock", function(ch) if IsValid(ch) then ch:Play() end end)
	else
		surface.PlaySound(path)
	end
end

-- the sound of a kind in a set (setId: the chosen one by default)
function UI.NotifySoundPath(kind, setId)
	setId = setId or cvSndSet:GetString()
	if setId == "custom" then return cvSnd[kind] and cvSnd[kind]:GetString() or nil end
	local set = SOUNDS[setId] or SOUNDS.speditor
	return set[kind]
end

local function playSound(kind)
	if not cvSound:GetBool() then return end
	UI.PlayNotifyPath(UI.NotifySoundPath(kind))
end

UI.NotifyLog = UI.NotifyLog or {}
local toasts = {}

local mats = {}
local function mat(path)
	mats[path] = mats[path] or Material(path, "smooth")
	return mats[path]
end

-- the same height as the stock notifications (notification.lua)
local gmTextH = math.max(12, math.ceil(ScreenScaleH(9)))
surface.CreateFont("SPeditor.NotifyGM", { font = "Arial", size = gmTextH, weight = 500, extended = true })
surface.CreateFont("SPeditor.NotifyMono", { font = "Courier New", size = 14, weight = 600, extended = true })

---------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------
-- A one-pixel outline with rounded corners (anti-aliased by coverage)
local arcCache = {}
local function arcPixels(r)
	if arcCache[r] then return arcCache[r] end
	local list, n = {}, 6
	for py = 0, r - 1 do
		for px = 0, r - 1 do
			local hit = 0
			for sy = 0, n - 1 do
				for sx = 0, n - 1 do
					local dx, dy = r - (px + (sx + 0.5) / n), r - (py + (sy + 0.5) / n)
					local d = math.sqrt(dx * dx + dy * dy)
					if d <= r and d > r - 1 then hit = hit + 1 end
				end
			end
			if hit > 0 then list[#list + 1] = { px, py, hit / (n * n) } end
		end
	end
	arcCache[r] = list
	return list
end

local function outline(x, y, w, h, r, c)
	r = math.min(r, math.floor(w / 2), math.floor(h / 2))
	surface.SetDrawColor(c.r, c.g, c.b, c.a)
	surface.DrawRect(x + r, y, w - r * 2, 1)
	surface.DrawRect(x + r, y + h - 1, w - r * 2, 1)
	surface.DrawRect(x, y + r, 1, h - r * 2)
	surface.DrawRect(x + w - 1, y + r, 1, h - r * 2)
	if r <= 0 then return end
	local rx, by = x + w - 1, y + h - 1
	for _, p in ipairs(arcPixels(r)) do
		surface.SetDrawColor(c.r, c.g, c.b, c.a * p[3])
		surface.DrawRect(x + p[1], y + p[2], 1, 1)
		surface.DrawRect(rx - p[1], y + p[2], 1, 1)
		surface.DrawRect(x + p[1], by - p[2], 1, 1)
		surface.DrawRect(rx - p[1], by - p[2], 1, 1)
	end
end

local function withA(c, a)
	return Color(c.r, c.g, c.b, a)
end

local function mixC(a, b, t)
	return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 255)
end

-- the blurred screen behind the card (Aero glass)
local matBlur = Material("pp/blurscreen")
local function blurBehind(panel, amount)
	local x, y = panel:LocalToScreen(0, 0)
	surface.SetMaterial(matBlur)
	surface.SetDrawColor(255, 255, 255, 255)
	for i = 1, 3 do
		matBlur:SetFloat("$blur", amount * i / 3)
		matBlur:Recompute()
		render.UpdateScreenEffectTexture()
		surface.DrawTexturedRect(-x, -y, ScrW(), ScrH())
	end
end

local matGradDown = Material("gui/gradient_down")
local matGradUp   = Material("gui/gradient_up")

-- for styles of one's own (cl_ui_notify_custom.lua, lua/speditor_notify/*.lua)
UI.NotifyDraw = { outline = outline, blur = blurBehind, mix = mixC, withAlpha = withA,
	gradDown = matGradDown, gradUp = matGradUp }

---------------------------------------------------------------------
-- Styles. A style: the font and paddings of the card, how the background is
-- drawn (bg), the text colour; title = a header line "SPeditor", center = text in the middle,
-- autoWidth = the card is as wide as its text (up to the set width).
---------------------------------------------------------------------
local STYLES = {}

STYLES.speditor = {
	font = "SPeditor.Small", pad = 8, icon = 16,
	bg = function(p, w, h, kc)
		local r = UI.Corners and math.min(UI.Corners(), 6) or 0
		if r > 0 then
			draw.RoundedBox(r, 0, 0, w, h, COL.HEADER)
			outline(0, 0, w, h, r, COL.BORDER)
			draw.RoundedBoxEx(r, 0, 0, 3, h, kc, true, false, true, false)
			return
		end
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		surface.SetDrawColor(kc)
		surface.DrawRect(0, 0, 3, h)
	end,
	text = function() return COL.TEXT end,
}

-- as the stock GMod notices (notification.AddLegacy): a dark translucent plate,
-- a big notice icon, white text with a shadow
STYLES.gmod = {
	font = "SPeditor.NotifyGM", pad = 6, icon = math.ceil(gmTextH * 1.25), gmodIcons = true,
	center = true, autoWidth = true, shadow = true,
	bg = function(p, w, h)
		draw.RoundedBox(4, 0, 0, w, h, Color(20, 20, 20, 153))
	end,
	text = function() return color_white end,
}

-- Windows 7 Aero: the blurred screen under tinted glass, a sheen on the upper half,
-- a dark outer and a light inner edge
STYLES.aero = {
	font = "SPeditor.Bold", pad = 10, icon = 16, shadow = true,
	bg = function(p, w, h, kc)
		blurBehind(p, 5)
		local tint = mixC(Color(116, 170, 220), kc, 0.35)
		draw.RoundedBox(6, 0, 0, w, h, withA(tint, 95))
		surface.SetMaterial(matGradDown)
		surface.SetDrawColor(255, 255, 255, 70)
		surface.DrawTexturedRect(1, 1, w - 2, math.floor(h * 0.5))
		surface.SetMaterial(matGradUp)
		surface.SetDrawColor(255, 255, 255, 22)
		surface.DrawTexturedRect(1, math.floor(h * 0.5), w - 2, math.ceil(h * 0.5) - 1)
		outline(0, 0, w, h, 6, Color(0, 0, 0, 150))
		outline(1, 1, w - 2, h - 2, 5, Color(255, 255, 255, 110))
	end,
	text = function() return color_white end,
}

-- flat: a dark plate without frames, the icon in a coloured circle
STYLES.flat = {
	font = "SPeditor.Small", pad = 10, icon = 16, iconDisc = true,
	bg = function(p, w, h)
		draw.RoundedBox(6, 0, 0, w, h, Color(30, 32, 36, 240))
	end,
	text = function() return Color(235, 235, 235) end,
}

-- solid: the whole card in the colour of its kind
STYLES.solid = {
	font = "SPeditor.Bold", pad = 9, icon = 16, shadow = true,
	bg = function(p, w, h, kc)
		local c = mixC(kc, Color(0, 0, 0), 0.25)
		draw.RoundedBox(4, 0, 0, w, h, c)
		surface.SetMaterial(matGradDown)
		surface.SetDrawColor(255, 255, 255, 30)
		surface.DrawTexturedRect(0, 0, w, h)
	end,
	text = function() return color_white end,
}

-- Vanilla UI: a navy translucent plate with a soft edge and an accent bar
STYLES.vanilla = {
	font = "SPeditor.Small", pad = 10, icon = 16,
	bg = function(p, w, h, kc)
		draw.RoundedBox(8, 0, 0, w, h, Color(7, 8, 11, 240))
		outline(0, 0, w, h, 8, Color(255, 255, 255, 26))
		surface.SetDrawColor(kc)
		surface.DrawRect(0, 6, 2, h - 12)
	end,
	text = function() return Color(255, 255, 255) end,
}

-- Windows XP balloon: pale yellow, a black frame, a bold header line
STYLES.xp = {
	font = "SPeditor.Small", pad = 9, icon = 16, title = true,
	bg = function(p, w, h)
		draw.RoundedBox(7, 0, 0, w, h, Color(0, 0, 0, 255))
		draw.RoundedBox(6, 1, 1, w - 2, h - 2, Color(255, 255, 225, 255))
		-- the close cross of a balloon (decor: cards do not take the mouse)
		local cx, cy = w - 13, 12
		surface.SetDrawColor(120, 120, 110, 255)
		surface.DrawOutlinedRect(cx - 6, cy - 6, 13, 13, 1)
		surface.DrawLine(cx - 3, cy - 3, cx + 3, cy + 3)
		surface.DrawLine(cx + 3, cy - 3, cx - 3, cy + 3)
	end,
	text = function() return Color(0, 0, 0) end,
	titleCol = function() return Color(0, 0, 0) end,
}

-- console: monospace, a dark plate, a coloured [kind] prefix
STYLES.console = {
	font = "SPeditor.NotifyMono", pad = 7, icon = 0, prefix = true,
	bg = function(p, w, h, kc)
		surface.SetDrawColor(0, 0, 0, 225)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(kc.r, kc.g, kc.b, 120)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end,
	text = function() return Color(200, 255, 200) end,
}

UI.NotifyStyles = { "auto", "speditor", "gmod", "aero", "flat", "solid", "vanilla", "xp", "console" }
UI.NotifyStyleDefs = STYLES

-- A style of one's own (a lua file in lua/speditor_notify/, or a JSON style made in
-- the style editor — cl_ui_notify_custom.lua). def: the fields of the styles above
-- (font, pad, icon, bg, text, …) plus name; or paint(panel, w, h, kindColor, kind)
-- to draw the whole card alone.
function UI.AddNotifyStyle(id, def)
	def.pad = def.pad or 8
	def.font = def.font or "SPeditor.Small"
	def.icon = def.icon or 16
	def.bg = def.bg or STYLES.speditor.bg
	def.text = def.text or STYLES.speditor.text
	def.titleCol = def.titleCol or def.text
	if not STYLES[id] then table.insert(UI.NotifyStyles, id) end
	STYLES[id] = def
end

function UI.RemoveNotifyStyle(id)
	STYLES[id] = nil
	table.RemoveByValue(UI.NotifyStyles, id)
end

function UI.NotifyStyleName(id)
	local key = "nstyle_" .. id
	local str = L(key)
	if str ~= key then return str end
	return (STYLES[id] and STYLES[id].name) or id
end
UI.NotifyAnims  = { "auto", "fade", "slide", "gmod", "drop", "pop", "none" }
UI.NotifyPlaces = { "br", "bl", "tr", "tl", "bc", "tc" }

-- "auto": the style of the current interface theme
local function styleId()
	local id = cvStyle:GetString()
	if id == "auto" or not STYLES[id] then
		local t = UI.Theme and UI.Theme.id or ""
		if t == "gmodxp" then return "xp" end
		if string.StartWith(t, "vanillaui") then return "vanilla" end
		if t == "gmod" then return "gmod" end
		return "speditor"
	end
	return id
end

local function animId(style)
	local id = cvAnim:GetString()
	if id == "auto" or id == "" then
		if style == "gmod" then return "gmod" end
		if style == "xp" then return "pop" end
		return "slide"
	end
	return id
end

---------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------
-- Word-wrap text to the width w (the font is already chosen through surface.SetFont)
local function wrap(text, w)
	local lines = {}
	for _, para in ipairs(string.Explode("\n", text)) do
		local line = ""
		for _, word in ipairs(string.Explode(" ", para)) do
			local try = (line == "") and word or (line .. " " .. word)
			if surface.GetTextSize(try) <= w or line == "" then
				line = try
			else
				lines[#lines + 1] = line
				line = word
			end
			-- a word longer than the line (a file path): cut by characters
			while surface.GetTextSize(line) > w and utf8.len(line) > 1 do
				local cut = utf8.len(line) - 1
				while cut > 1 and surface.GetTextSize(utf8.sub(line, 1, cut)) > w do cut = cut - 1 end
				lines[#lines + 1] = utf8.sub(line, 1, cut)
				line = utf8.sub(line, cut + 1)
			end
		end
		lines[#lines + 1] = line
	end
	return lines
end

local function place()
	local p = cvPos:GetString()
	if not ({ br = 1, bl = 1, tr = 1, tl = 1, bc = 1, tc = 1 })[p] then p = "br" end
	return p
end

-- the direction a card leaves to (and comes from): towards its screen edge
local function outDir(pos)
	if pos == "br" or pos == "tr" then return 1, 0 end
	if pos == "bl" or pos == "tl" then return -1, 0 end
	if pos == "bc" then return 0, 1 end
	return 0, -1
end

local function homeX(pos, w)
	if pos == "bl" or pos == "tl" then return MARGIN end
	if pos == "bc" or pos == "tc" then return math.floor((ScrW() - w) / 2) end
	return ScrW() - w - MARGIN
end

-- stack: the newest card is nearest to the screen edge of its place
local function layout()
	local pos = place()
	local top = (pos == "tr" or pos == "tl" or pos == "tc")
	local y = top and (TOP_H + MARGIN) or (ScrH() - STATUS_H - MARGIN)
	for i = #toasts, 1, -1 do
		local t = toasts[i]
		if IsValid(t) then
			if top then
				t.targetY = y
				y = y + t:GetTall() + MARGIN / 2
			else
				y = y - t:GetTall()
				t.targetY = y
				y = y - MARGIN / 2
			end
			t.targetX = homeX(pos, t:GetWide())
		else
			table.remove(toasts, i)
		end
	end
end

function UI.ClearToasts()
	for _, t in ipairs(toasts) do
		if IsValid(t) then t:Remove() end
	end
	toasts = {}
end

local function lifetime(kind)
	return math.Clamp(cvTime:GetFloat(), 1, 30) * ((KINDS[kind] or KINDS[0]).long or 1)
end

local function easeOut(t) return 1 - (1 - t) ^ 3 end
local function easeOutBack(t)
	local c1 = 1.70158
	return 1 + (c1 + 1) * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

---------------------------------------------------------------------
-- Animations: each returns the offset of the card from its place, its alpha and scale
-- (inT: 0 → 1 while appearing, outT: 1 → 0 while leaving)
---------------------------------------------------------------------
local ANIMS = {}

function ANIMS.none() return 0, 0, 1, 1 end

function ANIMS.fade(_, inT, outT) return 0, 0, easeOut(inT) * outT, 1 end

function ANIMS.slide(p, inT, outT, dx, dy)
	local k = (1 - easeOut(inT)) + (1 - easeOut(outT))
	local dist = (dx ~= 0) and (p:GetWide() + MARGIN * 2) or (p:GetTall() + MARGIN * 2)
	return dx * k * dist, dy * k * dist, math.min(1, outT * 1.5), 1
end

function ANIMS.drop(p, inT, outT, _, dy, areaH)
	-- falls from the side opposite to its edge and settles with a small bounce
	local from = (dy ~= 0) and -dy or ((p.curY or 0) < (areaH or ScrH()) / 2 and -1 or 1)
	local off = (1 - easeOutBack(inT)) * 36 * from + (1 - outT) * 18 * -from
	return 0, off, easeOut(math.min(inT * 2, 1)) * outT, 1
end

function ANIMS.pop(_, inT, outT)
	local s = 0.6 + 0.4 * easeOutBack(inT)
	s = s * (0.85 + 0.15 * outT)
	return 0, 0, math.min(inT * 3, 1) * outT, math.min(s, 1.04)
end

---------------------------------------------------------------------
-- A card
---------------------------------------------------------------------
local function measure(p)
	local st = p.style
	surface.SetFont(st.font)
	local _, lineH = surface.GetTextSize("Ag")
	p.lineH = lineH + 2
	local W = math.Clamp(cvWidth:GetInt(), 240, 700)
	if p.maxW then W = math.min(W, p.maxW) end
	local icon = st.icon or 0
	local textX = st.pad + (icon > 0 and (icon + st.pad) or 0)
	if st.iconDisc then textX = textX + 6 end
	local prefix = st.prefix and ("[" .. string.lower(L("notify_kind_" .. p.kind)) .. "] ") or nil
	p.prefix = prefix
	p.prefixW = prefix and surface.GetTextSize(prefix) or 0
	local room = W - textX - st.pad - p.prefixW - 14
	p.lines = wrap(p.text, room)
	if st.autoWidth then
		local widest = 0
		for _, line in ipairs(p.lines) do widest = math.max(widest, (surface.GetTextSize(line))) end
		W = math.min(W, widest + textX + st.pad + 14)
	end
	p.textX = textX
	local titleH = 0
	if st.title then
		surface.SetFont("SPeditor.Bold")
		titleH = select(2, surface.GetTextSize("Ag")) + 6
	end
	p.titleH = titleH
	local h = math.max(#p.lines * p.lineH + titleH + st.pad * 2, icon + st.pad * 2)
	if cvBar:GetBool() then h = h + 4 end
	p:SetSize(W, h)
end

local function drawContent(p, w, h, def, kc)
	local st = p.style
	local tc = st.text(kc)
	local pad = st.pad
	local y0 = pad + p.titleH
	local icon = st.icon or 0

	if st.title then
		surface.SetMaterial(mat(def.icon))
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRect(pad, pad - 1, 16, 16)
		draw.SimpleText("SPeditor — " .. L("notify_kind_" .. p.kind), "SPeditor.Bold", pad + 22, pad + 7, st.titleCol(), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	elseif icon > 0 then
		-- one line: the icon in the middle; several: level with the first line
		local iy = math.floor((h - (cvBar:GetBool() and 4 or 0) - icon) / 2)
		if #p.lines > 1 and not st.gmodIcons then iy = pad + math.floor((p.lineH - icon) / 2) end
		if st.iconDisc then
			draw.RoundedBox(math.floor((icon + 8) / 2), pad - 1, iy - 4, icon + 8, icon + 8, withA(kc, 70))
		end
		surface.SetMaterial(mat(st.gmodIcons and def.gmod or def.icon))
		surface.SetDrawColor(255, 255, 255, 255)
		if st.gmodIcons then
			render.PushFilterMag(TEXFILTER.ANISOTROPIC)
			render.PushFilterMin(TEXFILTER.ANISOTROPIC)
		end
		surface.DrawTexturedRect(pad + (st.iconDisc and 3 or 0), iy, icon, icon)
		if st.gmodIcons then
			render.PopFilterMin()
			render.PopFilterMag()
		end
	end

	local x = p.textX
	local textW = w - x - pad
	for i, line in ipairs(p.lines) do
		local y = y0 + (i - 1) * p.lineH
		local lx = x
		if p.prefix then
			if i == 1 then draw.SimpleText(p.prefix, st.font, lx, y, kc) end
			lx = lx + p.prefixW
		end
		if st.center then
			if st.shadow then draw.SimpleText(line, st.font, x + textW / 2 + 1, y + 1, Color(0, 0, 0, 200), TEXT_ALIGN_CENTER) end
			draw.SimpleText(line, st.font, x + textW / 2, y, tc, TEXT_ALIGN_CENTER)
		else
			if st.shadow then draw.SimpleText(line, st.font, lx + 1, y + 1, Color(0, 0, 0, 160)) end
			draw.SimpleText(line, st.font, lx, y, tc)
		end
	end

	if p.count > 1 then
		local cc = st.title and Color(0, 0, 0) or kc
		draw.SimpleText("×" .. p.count, "SPeditor.Bold", w - 6, h - 4 - (cvBar:GetBool() and 4 or 0), cc, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
	end

	if cvBar:GetBool() then
		local life = math.max(p.dieAt - p.born, 0.01)
		local frac = math.Clamp((p.dieAt - RealTime()) / life, 0, 1)
		local inset = (st == STYLES.speditor) and 3 or 4
		surface.SetDrawColor(0, 0, 0, 60)
		surface.DrawRect(inset, h - 5, w - inset * 2, 2)
		surface.SetDrawColor(kc.r, kc.g, kc.b, 230)
		surface.DrawRect(inset, h - 5, math.floor((w - inset * 2) * frac), 2)
	end
end

-- A card panel (a toast on screen or the sample in the settings window).
-- opts = { style, anim, maxW, life } override the settings.
local function makeCard(parent, text, kind, opts)
	opts = opts or {}
	local def = KINDS[kind] or KINDS[0]
	local sid = opts.style or styleId()
	if not STYLES[sid] then sid = "speditor" end
	local p = vgui.Create("DPanel", parent)
	p:SetMouseInputEnabled(false)
	p:SetKeyboardInputEnabled(false)
	p.text, p.kind, p.count, p.def = text, kind, 1, def
	p.style, p.styleId = STYLES[sid], sid
	p.anim = opts.anim or animId(sid)
	if not ANIMS[p.anim] and p.anim ~= "gmod" then p.anim = "slide" end
	p.born = RealTime()
	p.dieAt = p.born + (opts.life or lifetime(kind))
	if p.anim == "gmod" then p.dieAt = math.max(p.dieAt, p.born + 1.2) end
	p.maxW = opts.maxW
	measure(p)

	p.Paint = function(s, w, h)
		local a = s.alpha or 1
		if a <= 0.003 then return end
		local kc = def.color()
		local op = math.Clamp(cvOpacity:GetInt(), 30, 100) / 100
		surface.SetAlphaMultiplier(a * op)
		local scale = s.scale or 1
		local pushed = false
		if scale < 0.999 or scale > 1.001 then
			local sx, sy = s:LocalToScreen(0, 0)
			local m = Matrix()
			m:Translate(Vector(sx + w / 2, sy + h / 2, 0))
			m:Scale(Vector(scale, scale, 1))
			m:Translate(Vector(-sx - w / 2, -sy - h / 2, 0))
			cam.PushModelMatrix(m, true)
			pushed = true
		end
		local ok, err = pcall(function()
			if s.style.paint then
				s.style.paint(s, w, h, kc, def)
			else
				s.style.bg(s, w, h, kc)
				drawContent(s, w, h, def, kc)
			end
		end)
		if pushed then cam.PopModelMatrix() end
		surface.SetAlphaMultiplier(1)
		if not ok and not UI._toastErr then
			UI._toastErr = true
			MsgC(Color(255, 120, 80), "[SPeditor] notification style '", s.styleId, "': ", tostring(err), "\n")
		end
	end
	return p
end

-- Put a card at its starting point: beyond the edge it comes from (dx, dy) of the
-- area areaW × areaH, its place being tx, ty
local function startCard(p, tx, ty, dx, dy, areaW, areaH)
	p.dx, p.dy = dx, dy
	p.fx = (dx ~= 0) and (tx + dx * (p:GetWide() + 200)) or tx
	p.fy = (dy ~= 0) and ((dy > 0) and areaH or -p:GetTall()) or ty
	p.vx, p.vy = -5 * dx, -5 * dy
	p.curY = nil
	p.alpha, p.scale = 0, 1
	p:SetPos(p.fx, p.fy)
end

-- One step of the card animation towards its place tx, ty inside an area areaW × areaH
local function stepCard(s, now, tx, ty, areaW, areaH)
	if s.anim == "gmod" then
		-- the stock spring (notification.lua): a swing back before leaving, then away
		local left = s.dieAt - now
		local ix, iy = tx, ty
		if left < 0.7 then
			ix = ix - s.dx * areaW * 0.04
			iy = iy - s.dy * areaH * 0.04
		end
		if left < 0.2 then
			ix = ix + s.dx * s:GetWide() * 2
			iy = iy + s.dy * s:GetTall() * 3
		end
		local spd = RealFrameTime() * 15
		s.fx = s.fx + s.vx * spd
		s.fy = s.fy + s.vy * spd
		s.vx = (s.vx + (ix - s.fx) * spd) * (0.95 - RealFrameTime() * 8)
		s.vy = (s.vy + (iy - s.fy) * spd) * (0.95 - RealFrameTime() * 8)
		s.alpha, s.scale = 1, 1
		s:SetPos(s.fx, s.fy)
		return
	end
	-- the card glides to its place in the stack
	s.curY = s.curY or ty
	if math.abs(ty - s.curY) > 0.5 then
		s.curY = s.curY + (ty - s.curY) * math.min(FrameTime() * 14, 1)
	else
		s.curY = ty
	end
	local inT = math.Clamp((now - s.born) / IN_T, 0, 1)
	local outT = math.Clamp((s.dieAt - now) / OUT_T, 0, 1)
	local ox, oy, a, sc = ANIMS[s.anim](s, inT, outT, s.dx, s.dy, areaH)
	s.alpha, s.scale = a, sc
	s:SetPos(math.Round(tx + ox), math.Round(s.curY + oy))
end

local function newToast(text, kind)
	local p = makeCard(nil, text, kind)
	p:SetDrawOnTop(true)
	local pos = place()
	local dx, dy = outDir(pos)
	local ty = (pos == "br" or pos == "bl" or pos == "bc") and (ScrH() - STATUS_H - p:GetTall()) or TOP_H
	startCard(p, homeX(pos, p:GetWide()), ty, dx, dy, ScrW(), ScrH())
	p.Think = function(s)
		local now = RealTime()
		if now >= s.dieAt or not C.active then
			s:Remove()
			layout()
			return
		end
		stepCard(s, now, s.targetX or homeX(place(), s:GetWide()), s.targetY or s.fy, ScrW(), ScrH())
	end
	return p
end

-- A sample card for the settings window: it plays its animation over and over inside
-- the panel area (anchored as on screen: corner or centre, top or bottom)
function UI.NotifySample(area, text, kind, opts)
	local holder = { card = nil }
	local function spawn()
		if IsValid(holder.card) then holder.card:Remove() end
		local W, H = area:GetWide(), area:GetTall()
		local o = table.Copy(opts or {})
		o.maxW = math.max(W - 24, 160)
		o.life = o.life or 2.6
		local p = makeCard(area, text, kind, o)
		local pos = place()
		local dx, dy = outDir(pos)
		local tx = (pos == "bl" or pos == "tl") and 12 or ((pos == "bc" or pos == "tc") and math.floor((W - p:GetWide()) / 2) or (W - p:GetWide() - 12))
		local ty = (pos == "br" or pos == "bl" or pos == "bc") and (H - p:GetTall() - 12) or 12
		startCard(p, tx, ty, dx, dy, W, H)
		p.Think = function(s)
			local now = RealTime()
			if now >= s.dieAt + 0.5 then
				spawn()
				return
			end
			if now >= s.dieAt then
				s.alpha = 0
				return
			end
			stepCard(s, now, tx, ty, W, H)
		end
		holder.card = p
	end
	holder.Restart = spawn
	spawn()
	return holder
end

-- Show a card. Returns false if cards are switched off or the editor is
-- closed (then SPeditor.Notify shows a stock GMod hint).
function UI.Toast(text, kind)
	kind = KINDS[kind] and kind or 0
	local log = UI.NotifyLog
	log[#log + 1] = { time = os.time(), text = text, kind = kind }
	if #log > MAX_LOG then table.remove(log, 1) end
	hook.Run("SPeditor_Notified", text, kind)

	if not C.active or not cvShow:GetBool() then return false end

	playSound(kind)

	-- the same message is still on screen: extend it and count the repeats
	local last = toasts[#toasts]
	if IsValid(last) and last.text == text and last.kind == kind and last.dieAt - RealTime() > 0.7 then
		last.count = last.count + 1
		last.dieAt = RealTime() + lifetime(kind)
		return true
	end

	toasts[#toasts + 1] = newToast(text, kind)
	local maxN = math.Clamp(cvMax:GetInt(), 1, 12)
	while #toasts > maxN do
		local old = table.remove(toasts, 1)
		if IsValid(old) then old:Remove() end
	end
	layout()
	return true
end

-- Changing the place or the look: cards on screen move to the new place
for _, cv in ipairs({ "speditor_notify_pos", "speditor_notify_width", "speditor_notify_bar" }) do
	cvars.AddChangeCallback(cv, function()
		for _, t in ipairs(toasts) do
			if IsValid(t) then measure(t) end
		end
		layout()
	end, "SPeditor.Toasts")
end

hook.Add("SPeditor_StateChanged", "SPeditor.Toasts", function(on)
	if not on then UI.ClearToasts() end
end)
hook.Add("OnScreenSizeChanged", "SPeditor.Toasts", layout)

-- A sample of every kind (Interface settings → Notifications → Show a test)
function UI.NotifyDemo()
	SPeditor.Notify(L("notify_test_text"), 0)
	timer.Simple(0.35, function() SPeditor.Notify(L("notify_demo_ok"), 2) end)
	timer.Simple(0.7, function() SPeditor.Notify(L("notify_demo_err"), 1) end)
end

---------------------------------------------------------------------
-- Message log
---------------------------------------------------------------------
function UI.OpenNotifyLog()
	local Dock = SPeditor.Dock
	if Dock.ShowPage("notifylog") then return end
	local W, H = 560, 380
	local win, body = Dock.Create({ key = "notifylog", id = "notifylog", title = L("notify_log"), w = W, h = H,
			x = math.floor(ScrW() / 2 - W / 2), y = 140, dockable = false, icon = "icon16/comments.png" })
	win.minW, win.minH = UI.S(320), UI.S(200)

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(34))
	foot.Paint = function() end

	local list = vgui.Create("DListView", body)

	UI.StyleListView(list)
	list:Dock(FILL)
	list:SetMultiSelect(false)
	list:AddColumn(L("notify_col_time")):SetFixedWidth(70)
	list:AddColumn(L("notify_col_kind")):SetFixedWidth(100)
	list:AddColumn(L("notify_col_text"))
	if list.SetBackgroundColor then list:SetBackgroundColor(COL.LIST_BG) end

	local function fill()
		if not IsValid(list) then return end
		list:Clear()
		for i = #UI.NotifyLog, 1, -1 do
			local e = UI.NotifyLog[i]
			local line = list:AddLine(os.date("%H:%M:%S", e.time), L("notify_kind_" .. e.kind), e.text)
			line:SetTooltip(e.text)
		end
	end
	fill()
	list.OnRowRightClick = function(_, _, line)
		local m = UI.Menu()
		m:AddOption(L("notify_copy"), function() SetClipboardText(line:GetColumnText(3)) end):SetIcon("icon16/page_copy.png")
		m:Open()
	end
	hook.Add("SPeditor_Notified", "SPeditor.NotifyLog", function()
		if not IsValid(list) then
			hook.Remove("SPeditor_Notified", "SPeditor.NotifyLog")
			return
		end
		-- the line is added to the log after the hook is called
		timer.Simple(0, fill)
	end)

	local clear = vgui.Create("DButton", foot)
	clear:Dock(LEFT)
	clear:DockMargin(8, 5, 4, 5)
	clear:SetWide(UI.S(150))
	clear:SetText(L("notify_clear"))
	UI.StyleButton(clear, nil, 3)
	clear.DoClick = function()
		UI.NotifyLog = {}
		fill()
	end
	local close = vgui.Create("DButton", foot)
	close:Dock(RIGHT)
	close:DockMargin(4, 5, 8, 5)
	close:SetWide(UI.S(110))
	close:SetText(L("about_close"))
	UI.StyleButton(close, nil, 3)
	close.DoClick = function() win:Close() end
end

-- Items of the "Windows → Notifications" menu
function UI.BuildNotifyMenu(m)
	m:AddOption(L("notify_show"), function()
		RunConsoleCommand("speditor_notify", cvShow:GetBool() and "0" or "1")
	end):SetChecked(cvShow:GetBool())
	m:AddOption(L("notify_sound"), function()
		RunConsoleCommand("speditor_notify_sound", cvSound:GetBool() and "0" or "1")
	end):SetChecked(cvSound:GetBool())
	local dur = m:AddSubMenu(L("notify_time"))
	local cur = math.Round(cvTime:GetFloat())
	for _, s in ipairs({ 2, 4, 6, 10 }) do
		dur:AddOption(string.format(L("notify_seconds"), s), function()
			RunConsoleCommand("speditor_notify_time", tostring(s))
		end):SetChecked(cur == s)
	end
	local function choice(title, cv, ids, name)
		local sub = m:AddSubMenu(L(title))
		local now = GetConVarString(cv)
		for _, id in ipairs(ids) do
			sub:AddOption(name(id), function() RunConsoleCommand(cv, id) end):SetChecked(now == id)
		end
	end
	choice("notify_style", "speditor_notify_style", UI.NotifyStyles, UI.NotifyStyleName)
	choice("notify_anim", "speditor_notify_anim", UI.NotifyAnims, function(id) return L("nanim_" .. id) end)
	choice("notify_pos", "speditor_notify_pos", UI.NotifyPlaces, function(id) return L("npos_" .. id) end)
	m:AddSpacer()
	m:AddOption(L("ui_settings") .. "…", function() UI.OpenSettings("notify") end):SetIcon("icon16/cog.png")
	m:AddOption(L("notify_log") .. "…", function() UI.OpenNotifyLog() end):SetIcon("icon16/comments.png")
	m:AddOption(L("notify_test"), function() UI.NotifyDemo() end)
end
