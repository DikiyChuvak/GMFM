--[[
SPeditor — its own notifications (the editor's pop-up messages).

While the editor is open, SPeditor.Notify messages are shown not as stock
GMod hints but as cards in the interface style: in the bottom right corner, above
the status bar, over all windows. A card: a colour stripe and an icon by message
kind, text with line wrapping, a repeat counter. After a few seconds
the card fades. Cards do not capture the mouse — you can work underneath them.

Kinds: 0 — info, 1 — error, 2 — success, 3 — saving (no sound).

All messages are written to a log (Windows → Notifications → Message log).
Settings: speditor_notify (show), speditor_notify_sound (sound),
speditor_notify_time (how many seconds a card stays).

API:
  UI.Toast(text, kind)      show a card (called by SPeditor.Notify)
  UI.ClearToasts()          remove all cards
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

local cvShow  = CreateClientConVar("speditor_notify", "1", true, false)
local cvSound = CreateClientConVar("speditor_notify_sound", "1", true, false)
local cvTime  = CreateClientConVar("speditor_notify_time", "4", true, false)

local MAX_TOASTS = 6
local MAX_LOG    = 200
local WIDTH      = 380
local PAD, ICON  = 8, 16
local MARGIN     = 8          -- from the screen edge and between cards
local STATUS_H   = 20
local FADE_IN, FADE_OUT = 0.15, 0.35

local KINDS = {
	[0] = { icon = "icon16/information.png", color = function() return COL.BLUE end,   sound = "buttons/button14.wav" },
	[1] = { icon = "icon16/exclamation.png", color = function() return COL.RED end,    sound = "buttons/button10.wav", long = 1.5 },
	[2] = { icon = "icon16/accept.png",      color = function() return COL.GREEN end,  sound = "buttons/button14.wav" },
	[3] = { icon = "icon16/disk.png",        color = function() return COL.ORANGE end },
}

UI.NotifyLog = UI.NotifyLog or {}
local toasts = {}

local icons = {}
local function iconMat(path)
	icons[path] = icons[path] or Material(path)
	return icons[path]
end

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
				local n = utf8.len(line)
				local cut = n - 1
				while cut > 1 and surface.GetTextSize(utf8.sub(line, 1, cut)) > w do cut = cut - 1 end
				lines[#lines + 1] = utf8.sub(line, 1, cut)
				line = utf8.sub(line, cut + 1)
			end
		end
		lines[#lines + 1] = line
	end
	return lines
end

local function layout()
	local y = ScrH() - STATUS_H - MARGIN
	for i = #toasts, 1, -1 do
		local t = toasts[i]
		if IsValid(t) then
			y = y - t:GetTall()
			t.targetY = y
			y = y - MARGIN / 2
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

local function newToast(text, kind)
	local def = KINDS[kind] or KINDS[0]
	local p = vgui.Create("DPanel")
	p:SetDrawOnTop(true)
	p:SetMouseInputEnabled(false)
	p:SetKeyboardInputEnabled(false)
	p.text, p.kind, p.count = text, kind, 1
	p.born, p.dieAt = RealTime(), RealTime() + lifetime(kind)

	surface.SetFont("SPeditor.Small")
	local _, lineH = surface.GetTextSize("Ag")
	p.lineH = lineH + 2
	p.lines = wrap(text, WIDTH - PAD * 3 - ICON - 4)
	p:SetSize(WIDTH, math.max(#p.lines * p.lineH + PAD * 2, ICON + PAD * 2))
	p:SetPos(ScrW() - WIDTH - MARGIN, ScrH())

	p.Paint = function(s, w, h)
		local now = RealTime()
		local a = math.Clamp((now - s.born) / FADE_IN, 0, 1) * math.Clamp((s.dieAt - now) / FADE_OUT, 0, 1)
		surface.SetAlphaMultiplier(a)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
		surface.SetDrawColor(def.color())
		surface.DrawRect(0, 0, 3, h)
		surface.SetMaterial(iconMat(def.icon))
		surface.SetDrawColor(255, 255, 255, 255)
		surface.DrawTexturedRect(PAD + 2, PAD, ICON, ICON)
		local tx = PAD * 2 + ICON + 2
		for i, line in ipairs(s.lines) do
			draw.SimpleText(line, "SPeditor.Small", tx, PAD + (i - 1) * s.lineH, COL.TEXT)
		end
		if s.count > 1 then
			draw.SimpleText("×" .. s.count, "SPeditor.Bold", w - 6, h - 4, def.color(), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
		end
		surface.SetAlphaMultiplier(1)
	end

	p.Think = function(s)
		if RealTime() >= s.dieAt or not C.active then
			s:Remove()
			layout()
			return
		end
		-- the card glides to its place in the stack
		local x, y = s:GetPos()
		local ty = s.targetY or y
		if math.abs(ty - y) > 0.5 then
			s:SetPos(ScrW() - WIDTH - MARGIN, y + (ty - y) * math.min(FrameTime() * 14, 1))
		elseif x ~= ScrW() - WIDTH - MARGIN then
			s:SetPos(ScrW() - WIDTH - MARGIN, ty)
		end
	end
	return p
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

	local def = KINDS[kind]
	if def.sound and cvSound:GetBool() then surface.PlaySound(def.sound) end

	-- the same message is still on screen: extend it and count the repeats
	local last = toasts[#toasts]
	if IsValid(last) and last.text == text and last.kind == kind and last.dieAt - RealTime() > FADE_OUT then
		last.count = last.count + 1
		last.dieAt = RealTime() + lifetime(kind)
		return true
	end

	toasts[#toasts + 1] = newToast(text, kind)
	while #toasts > MAX_TOASTS do
		local old = table.remove(toasts, 1)
		if IsValid(old) then old:Remove() end
	end
	layout()
	return true
end

hook.Add("SPeditor_StateChanged", "SPeditor.Toasts", function(on)
	if not on then UI.ClearToasts() end
end)
hook.Add("OnScreenSizeChanged", "SPeditor.Toasts", layout)

---------------------------------------------------------------------
-- Message log
---------------------------------------------------------------------
function UI.OpenNotifyLog()
	local Dock = SPeditor.Dock
	if Dock.ShowPage("notifylog") then return end
	local W, H = 560, 380
	local win, body = Dock.Create({ key = "notifylog", id = "notifylog", title = L("notify_log"), w = W, h = H,
			x = math.floor(ScrW() / 2 - W / 2), y = 140, dockable = false, icon = "icon16/comments.png" })
	win.minW, win.minH = 320, 200

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(34)
	foot.Paint = function() end

	local list = vgui.Create("DListView", body)
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
	clear:SetWide(150)
	clear:SetText(L("notify_clear"))
	UI.StyleButton(clear, nil, 3)
	clear.DoClick = function()
		UI.NotifyLog = {}
		fill()
	end
	local close = vgui.Create("DButton", foot)
	close:Dock(RIGHT)
	close:DockMargin(4, 5, 8, 5)
	close:SetWide(110)
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
	m:AddSpacer()
	m:AddOption(L("notify_log") .. "…", function() UI.OpenNotifyLog() end):SetIcon("icon16/comments.png")
	m:AddOption(L("notify_test"), function() SPeditor.Notify(L("notify_test_text"), 2) end)
end
