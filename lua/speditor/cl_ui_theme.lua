--[[
SPeditor — theme and basic widgets in the style of Source Filmmaker.

The colours are taken from screenshots of the SFM interface: dark grey panels, light
active tabs, a black field outside the frame, an orange selection accent,
in the tree the right side of the body is red, the left one green.

Widgets:
  UI.Label / UI.Button / UI.Slider / UI.Section / UI.Check / UI.StyleCombo
  UI.StyleButton(button, hot, rounded, base) — button look (hot = true: emphasised): in a theme with its own Derma skin
      (UI.IsNative, see cl_ui_themes.lua) the skin draws the button, otherwise the editor does
  UI.IconButton(parent, icon, tip, fn, isOn)  — a toolbar button
  "SPeditorControl" — a slider control as in the Animation Set Editor:
      drag left / right with the mouse (Shift — finer, Ctrl — coarser),
      double click — the default value, right click — a menu (reset,
      enter a value). Follows the value from getter while it is not being dragged.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI = SPeditor.UI

local COL = {
	BG       = Color(58, 56, 57),    -- panel background
	CHROME   = Color(50, 48, 49),    -- window frame
	HEADER   = Color(71, 69, 70),    -- toolbars
	MENU     = Color(73, 72, 78),    -- menu bar
	TAB_ON   = Color(96, 99, 101),
	TAB_OFF  = Color(66, 64, 65),
	CTRL     = Color(83, 81, 82),    -- buttons
	HOVER    = Color(108, 108, 112),
	BORDER   = Color(34, 32, 33),
	TEXT     = Color(214, 214, 214),
	DIM      = Color(150, 150, 152),
	BLUE     = Color(130, 170, 220),
	ORANGE   = Color(233, 145, 45),
	GREEN    = Color(125, 205, 100),  -- left side of the body
	RED      = Color(228, 100, 88),   -- right side of the body
	VIEW_BG  = Color(0, 0, 0),        -- field outside the frame
	LIST_BG  = Color(48, 47, 48),
	TREE_BG  = Color(48, 47, 48),
	ROW_A    = Color(61, 59, 60),
	ROW_B    = Color(53, 51, 52),
	SEL      = Color(118, 124, 132),
	FILL     = Color(88, 92, 100),
	FILL_HOT = Color(122, 128, 140),
	TIMECODE = Color(186, 192, 188),
}
UI.PAL = COL

---------------------------------------------------------------------
-- Interface settings (the "Interface settings" window, cl_ui_settings.lua)
---------------------------------------------------------------------
local cvFont     = CreateClientConVar("gmfm_ui_font", "Tahoma", true, false)
local cvFontSize = CreateClientConVar("gmfm_ui_fontsize", "13", true, false)
CreateClientConVar("gmfm_ui_accent", "", true, false)        -- "r g b"; empty — the theme's own accent
local cvCorners  = CreateClientConVar("gmfm_ui_corners", "0", true, false)   -- window corner radius, px
local cvTabStyle = CreateClientConVar("gmfm_ui_tabstyle", "top", true, false) -- top / bottom / fill / none
local cvAnim     = CreateClientConVar("gmfm_ui_anim", "1", true, false)       -- fades and smooth hover
CreateClientConVar("gmfm_ui_sounds", "1", true, false)                        -- interface sounds of themes that have them

-- the size of the whole interface, percent; 0 — by the screen: 100 % up to 1080 lines, then in
-- steps of 25 % (1440 lines — 125 %, 2160 — 200 %)
-- (below 100 %: more room for the viewports on small screens and for those who like small text)
local cvScale    = CreateClientConVar("gmfm_ui_scale", "0", true, false, "Interface scale, percent (0 — by the screen resolution, 50 to 200)", 0, 200)

UI.FONT_FACES = { "Tahoma", "Verdana", "Arial", "Roboto", "Segoe UI", "Trebuchet MS", "Courier New" }

function UI.AutoScale()
	return math.Clamp(math.floor(ScrH() / 1080 * 4 + 0.15) / 4, 1, 2)
end

function UI.Scale()
	local pct = cvScale:GetInt()
	if pct <= 0 then return UI.AutoScale() end
	return math.Clamp(pct, 50, 200) / 100
end

-- a size in pixels of the interface at 100 %, scaled
function UI.S(px) return math.floor(px * UI.Scale() + 0.5) end

-- a 16 px icon drawn by hand inside a strip h px tall: smaller when the strip is
-- (interface scale below 100 %), so that it does not stick out of it
function UI.IconSize(h) return math.Clamp(math.floor(h) - 4, 8, 16) end

function UI.CreateFonts()
	local face = cvFont:GetString()
	if face == "" then face = "Tahoma" end
	-- a language pack may name a font that has its letters (Japanese, Chinese…); the
	-- player's own choice of a font wins
	local pack = SPeditor.LanguageInfo and SPeditor.LanguageInfo(GetConVarString("gmfm_language"))
	if pack and pack.font and (face == "Tahoma" or pack.forceFont) then face = pack.font end
	-- not below 8 px: at 50 % smaller text cannot be read at all
	local size = math.max(UI.S(math.Clamp(cvFontSize:GetInt(), 11, 16)), 8)
	surface.CreateFont("SPeditor.Small", { font = face, size = size, weight = 500, antialias = true, extended = true })
	surface.CreateFont("SPeditor.Bold",  { font = face, size = size, weight = 800, antialias = true, extended = true })
	surface.CreateFont("SPeditor.Time",  { font = face, size = size + UI.S(8), weight = 400, antialias = true, extended = true })
	UI.ScaleDermaFonts(SPeditor.Client and SPeditor.Client.active)
	hook.Run("SPeditor_FontsCreated")
end

-- Labels, buttons, text fields and menus without a font of their own use the game's
-- DermaDefault. While the editor is open it is made at the interface scale; when the editor
-- closes it is put back as the game makes it (lua/derma/init.lua), for the rest of the game.
local dermaScaled
function UI.ScaleDermaFonts(on)
	local k = on and UI.Scale() or 1
	if k == 1 and not dermaScaled then return end
	dermaScaled = k ~= 1
	local linux = system.IsLinux()
	local face, size = linux and "DejaVu Sans" or "Tahoma", linux and 14 or 13
	local px = math.max(math.floor(size * k + 0.5), 8)
	surface.CreateFont("DermaDefault", { font = face, size = px, weight = 500, extended = true })
	surface.CreateFont("DermaDefaultBold", { font = face, size = px, weight = 800, extended = true })
end
SPeditor.Hook("SPeditor_StateChanged", "SPeditor.DermaScale", function(on) UI.ScaleDermaFonts(on) end)
UI.CreateFonts()
-- the font of a language pack: once the packs are loaded and when the language changes
SPeditor.Hook("SPeditor_LanguagesLoaded", "SPeditor.Fonts", function() UI.CreateFonts() end)
cvars.AddChangeCallback("gmfm_language", function() UI.CreateFonts() end, "SPeditor.Fonts")

function UI.Animated() return cvAnim:GetBool() end

-- An eased value for hover transitions: panel[key] runs towards target (0..1)
function UI.Ease(panel, key, target, speed)
	if not cvAnim:GetBool() then
		panel[key] = target
		return target
	end
	local v = panel[key] or target
	v = v + (target - v) * math.min(FrameTime() * (speed or 16), 1)
	if math.abs(v - target) < 0.01 then v = target end
	panel[key] = v
	return v
end

local function lerpColor(a, b, t)
	if t <= 0 then return a end
	if t >= 1 then return b end
	return Color(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, (a.a or 255) + ((b.a or 255) - (a.a or 255)) * t)
end
UI.LerpColor = lerpColor

-- Fade a panel in when it appears (windows, menus)
function UI.FadeIn(panel, time)
	if not cvAnim:GetBool() or not IsValid(panel) then return end
	panel:SetAlpha(0)
	panel:AlphaTo(255, time or 0.12, 0)
end

---------------------------------------------------------------------
-- Chrome: the editor's own windows, tabs, menu bar and status bar.
-- A theme may draw them its own way: its Derma skin gets a table
-- SKIN.SPeditor = { Window, CloseButton, MenuBar, MenuButton, StatusBar, ToolButton }
-- (each a function(skin, panel, w, h, info)); what it lacks is drawn here.
---------------------------------------------------------------------
local CHROME = {}
-- the editor's own chrome: a theme's SKIN.SPeditor part may draw something and then call it
UI.DefaultChrome = CHROME
UI.ChromeDefault = CHROME

local iconCache = {}
local function iconMat(path)
	if iconCache[path] == nil then
		local m = Material(path)
		iconCache[path] = (m and not m:IsError()) and m or false
	end
	return iconCache[path] or nil
end

-- Icon and title of a window tab t = { page, x, w, on } inside the strip from y, height h
function UI.DrawTabLabel(t, y, h, col, iconAlpha)
	local tx = t.x + 10
	if t.page.icon then
		local m = UI.ThemeGlyph(t.page.icon) or iconMat(t.page.icon)
		if m then
			local is = UI.IconSize(h)
			surface.SetMaterial(m)
			surface.SetDrawColor(255, 255, 255, iconAlpha or (t.on and 255 or 150))
			surface.DrawTexturedRect(t.x + 6, y + math.floor((h - is) / 2), is, is)
			tx = t.x + 10 + is
		end
	end
	draw.SimpleText(t.page.title, "SPeditor.Small", tx, y + h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

function UI.Corners() return math.Clamp(cvCorners:GetInt(), 0, 10) end

-- info = { tiled, onTop, tabs = { {page, x, w, on, hot} }, edge, tabH }
function CHROME.Window(_, win, w, h, info)
	local c = COL
	local r = UI.Corners()
	local e, th = info.edge, info.tabH
	local frame = info.tiled and c.BORDER or c.HOVER
	if r > 0 then
		draw.RoundedBox(r, 0, 0, w, h, frame)
		draw.RoundedBox(math.max(r - 1, 0), 1, 1, w - 2, h - 2, c.CHROME)
	else
		surface.SetDrawColor(c.CHROME)
		surface.DrawRect(0, 0, w, h)
		-- a floating window is marked with a light frame
		surface.SetDrawColor(frame)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	-- an "always on top" window is marked with an accent stripe along the top edge
	if info.onTop then
		surface.SetDrawColor(c.ORANGE)
		surface.DrawRect(1 + r, 1, w - 2 - r * 2, 2)
	end
	surface.SetDrawColor(c.BG)
	surface.DrawRect(1, e, w - 2, th)

	local style = cvTabStyle:GetString()
	for _, t in ipairs(info.tabs) do
		local hot = UI.Ease(t.page, "_tabHot", (t.hot and not t.on) and 1 or 0, 18)
		local fill = t.on and c.TAB_ON or lerpColor(c.TAB_OFF, c.HOVER, hot * 0.6)
		if style == "fill" and t.on then fill = lerpColor(c.TAB_ON, c.ORANGE, 0.35) end
		if r > 0 then
			draw.RoundedBoxEx(math.min(r, 6), t.x, e + 1, t.w, th - 1, fill, true, true, false, false)
		else
			surface.SetDrawColor(fill)
			surface.DrawRect(t.x, e + 1, t.w, th - 1)
		end
		if t.on and style == "top" then
			surface.SetDrawColor(c.ORANGE)
			surface.DrawRect(t.x + (r > 0 and 2 or 0), e + 1, t.w - (r > 0 and 4 or 0), r > 0 and 2 or 1)
		elseif t.on and style == "bottom" then
			surface.SetDrawColor(c.ORANGE)
			surface.DrawRect(t.x, e + th - 2, t.w, 2)
		end
		UI.DrawTabLabel(t, e, th, t.on and c.TEXT or c.DIM)
	end
end

function CHROME.CloseButton(_, b, w, h)
	local hot = UI.Ease(b, "_hot", b:IsHovered() and 1 or 0, 20)
	if hot > 0 then
		local fill = Color(150, 60, 45, 255 * hot)
		if UI.Corners() > 0 then
			draw.RoundedBox(3, 0, 0, w, h, fill)
		else
			surface.SetDrawColor(fill)
			surface.DrawRect(0, 0, w, h)
		end
	end
	draw.SimpleText("r", "Marlett", w / 2, h / 2, lerpColor(COL.DIM, COL.TEXT, hot), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function CHROME.MenuBar(_, _, w, h)
	surface.SetDrawColor(COL.MENU)
	surface.DrawRect(0, 0, w, h)
	surface.SetDrawColor(COL.BORDER)
	surface.DrawRect(0, h - 1, w, 1)
end

-- a button of the menu bar (File, Edit, …): only the highlight, the text is the button's own
function CHROME.MenuButton(_, b, w, h)
	local hot = UI.Ease(b, "_hot", (b:IsHovered() or b._menuOpen) and 1 or 0, 20)
	if hot <= 0 then return end
	local c = COL.SEL
	local fill = Color(c.r, c.g, c.b, 255 * hot)
	if UI.Corners() > 0 then
		draw.RoundedBox(3, 1, 2, w - 2, h - 4, fill)
	else
		surface.SetDrawColor(fill)
		surface.DrawRect(0, 2, w, h - 4)
	end
end

-- a square tool button (viewport and ASE toolbars, UI.IconButton); info = { on }
function CHROME.ToolButton(_, b, w, h, info)
	local on = info and info.on
	surface.SetDrawColor(on and COL.TAB_ON or (b:IsHovered() and COL.HOVER or COL.HEADER))
	surface.DrawRect(0, 0, w, h)
	if on then
		surface.SetDrawColor(COL.ORANGE)
		surface.DrawRect(0, h - 2, w, 2)
	end
end

function CHROME.StatusBar(_, _, w, h)
	surface.SetDrawColor(COL.BG)
	surface.DrawRect(0, 0, w, h)
	surface.SetDrawColor(COL.BORDER)
	surface.DrawRect(0, 0, w, 1)
end

-- Draw a chrome part: the theme's painter if it has one, otherwise the default one
function UI.PaintChrome(part, panel, w, h, info)
	local skin = UI.SkinName and derma.GetNamedSkin(UI.SkinName)
	local own = skin and rawget(skin, "SPeditor")
	local fn = own and own[part]
	if fn then
		local ok, err = pcall(fn, skin, panel, w, h, info)
		if ok then return end
		if not UI._chromeErr then
			UI._chromeErr = true
			MsgC(Color(255, 120, 80), "[GM:FM] theme chrome '", part, "': ", tostring(err), "\n")
		end
	end
	CHROME[part](skin, panel, w, h, info)
end

-- A theme's own picture for a silkicon path or a name (SKIN.SPeditor.Icons[key] = { mat, on = mat, w, h }), or nil
function UI.ThemeIcon(path)
	local skin = UI.SkinName and derma.GetNamedSkin(UI.SkinName)
	local own = skin and rawget(skin, "SPeditor")
	return own and own.Icons and own.Icons[path] or nil
end

-- A button drawn as a whole picture of the theme (key in SKIN.SPeditor.Icons) when it has one:
-- its text and icon are hidden then, and it takes the picture's proportions
function UI.ThemeButton(b, key)
	local base = b.Paint
	b.Paint = function(s, w, h)
		local own = UI.ThemeIcon(key)
		if own then
			if s:GetText() ~= "" then s.SPThemeText = s:GetText() s:SetText("") end
			if IsValid(s.m_Image) then s.m_Image:SetVisible(false) end
			local want = UI.ThemeIconWide(own, h)
			if s.SPThemeW ~= want then
				s.SPThemeW = want
				s:SetWide(want)
				s:NoClipping(own.base ~= nil and own.h > own.base)
			end
			UI.DrawThemeIcon(own, w, h, s:IsHovered() or s:IsDown())
			return
		end
		if s.SPThemeText then s:SetText(s.SPThemeText) s.SPThemeText = nil end
		if IsValid(s.m_Image) then s.m_Image:SetVisible(true) end
		if base then return base(s, w, h) end
		derma.SkinHook("Paint", "Button", s, w, h)
	end
	return b
end

-- A theme's own small icon (a path) for a kind of object in the lists, or nil
-- (SKIN.SPeditor.ItemIcons = { ragdoll = "…png", camera = …, light = …, effect = … })
function UI.ThemeIconPath(kind)
	local skin = UI.SkinName and derma.GetNamedSkin(UI.SkinName)
	local own = skin and rawget(skin, "SPeditor")
	return own and own.ItemIcons and own.ItemIcons[kind] or nil
end

-- such a picture fitted into w x h (it is a whole button: SFM draws the frame in the picture).
-- A picture with a base is drawn at the scale of a button base pixels high and may stand out
-- of w x h (UI.ThemeIconWide gives the width it takes; its button draws without clipping).
function UI.DrawThemeIcon(icon, w, h, lit)
	local m = lit and icon.on or icon.mat
	if not m then return end
	surface.SetMaterial(m)
	surface.SetDrawColor(255, 255, 255, 255)
	if icon.base then
		local k = h / icon.base
		local iw, ih = math.floor(icon.w * k + 0.5), math.floor(icon.h * k + 0.5)
		surface.DrawTexturedRect(math.floor((w - iw) / 2), math.floor(h / 2 - (icon.cy or icon.h / 2) * k + 0.5), iw, ih)
		return
	end
	local k = math.min(w / icon.w, h / icon.h)
	local iw, ih = math.floor(icon.w * k + 0.5), math.floor(icon.h * k + 0.5)
	surface.DrawTexturedRect(math.floor((w - iw) / 2), math.floor((h - ih) / 2), iw, ih)
end

-- the width a theme picture takes on a button h pixels high
function UI.ThemeIconWide(icon, h)
	return math.floor(h * icon.w / (icon.base or icon.h) + 0.5)
end

-- The grey glyph of a silkicon in a theme that has them (SKIN.SPeditor.Glyphs = folder), or nil
local glyphs = {}
function UI.ThemeGlyph(path)
	if not isstring(path) or not string.StartWith(path, "icon16/") then return nil end
	local skin = UI.SkinName and derma.GetNamedSkin(UI.SkinName)
	local own = skin and rawget(skin, "SPeditor")
	local dir = own and own.Glyphs
	if not dir then return nil end
	local key = dir .. string.sub(path, 8)
	local g = glyphs[key]
	if g == nil then
		g = file.Exists("materials/" .. key, "GAME") and Material(key) or false
		glyphs[key] = g
	end
	return g or nil
end

-- the button shell a theme draws its glyphs in (SKIN.SPeditor.GlyphFrame, a picture like Icons), or nil
function UI.ThemeGlyphFrame()
	local skin = UI.SkinName and derma.GetNamedSkin(UI.SkinName)
	local own = skin and rawget(skin, "SPeditor")
	return own and own.GlyphFrame or nil
end

-- the path of that glyph (for DButton:SetIcon / DImage), or the silkicon itself
function UI.ThemedIconPath(path)
	if UI.ThemeGlyph(path) then
		local skin = derma.GetNamedSkin(UI.SkinName)
		return rawget(skin, "SPeditor").Glyphs .. string.sub(path, 8)
	end
	return path
end

-- Text colour on the menu bar / status bar (a theme may draw them light on a dark palette)
function UI.ChromeText(part)
	local skin = UI.SkinName and derma.GetNamedSkin(UI.SkinName)
	local own = skin and rawget(skin, "SPeditor")
	return own and own.TextColors and own.TextColors[part] or nil
end

---------------------------------------------------------------------
-- Simple widgets
---------------------------------------------------------------------
-- Look of a button and a drop-down list. hot — the colour under the cursor, base — the regular one
-- (both optional), rounded — the corner radius.
function UI.StyleButton(b, hot, rounded, base)
	-- hot = true: an emphasised button (lighter fill), not a colour
	if hot == true then base = base or COL.TAB_ON end
	if not IsColor(hot) and type(hot) ~= "table" then hot = nil end
	b:SetFont("SPeditor.Small")
	if UI.IsNative and UI.IsNative() then return b end
	b:SetTextColor(COL.TEXT)
	b.Paint = function(s, w, h)
		local k = UI.Ease(s, "_hot", s:IsHovered() and 1 or 0, 18)
		local fill = lerpColor(base or COL.CTRL, hot or COL.HOVER, k)
		local r = rounded or (UI.Corners() > 0 and math.min(UI.Corners(), 4) or nil)
		if r then
			draw.RoundedBox(r, 0, 0, w, h, fill)
			return
		end
		surface.SetDrawColor(fill)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	return b
end

function UI.Label(parent, text, col)
	local l = vgui.Create("DLabel", parent)
	l:Dock(TOP)
	l:DockMargin(4, 1, 4, 1)
	l:SetFont("SPeditor.Small")
	l:SetTextColor(col or COL.DIM)
	l:SetText(text or "")
	return l
end

function UI.Button(parent, text, icon, fn, tall)
	local b = vgui.Create("DButton", parent)
	b:Dock(TOP)
	b:DockMargin(2, 1, 2, 1)
	b:SetTall(UI.S(tall or 22))
	if icon then b:SetIcon(UI.ThemedIconPath(icon)) end
	b:SetText((icon and "  " or "") .. (text or ""))
	UI.StyleButton(b)
	if fn then b.DoClick = fn end
	return b
end

function UI.Slider(parent, label, min, max, dec, val, onchg)
	local s = vgui.Create("DNumSlider", parent)
	s:Dock(TOP)
	s:DockMargin(4, 1, 4, 1)
	s:SetTall(UI.S(22))
	s:SetText(label)
	s:SetMin(min)
	s:SetMax(max)
	s:SetDecimals(dec)
	if val then s:SetValue(val) end
	if IsValid(s.Label) then
		s.Label:SetTextColor(COL.TEXT)
		s.Label:SetFont("SPeditor.Small")
	end
	-- a number field has no background of its own: the skin's text colour may be unreadable on the panel
	if IsValid(s.TextArea) then s.TextArea:SetTextColor(COL.TEXT) end
	if onchg then s.OnValueChanged = function(_, v) onchg(v) end end
	return s
end

-- A section with a header in the style of SFM column headers
function UI.Section(parent, title)
	local f = vgui.Create("DForm", parent)
	f:Dock(TOP)
	f:DockMargin(2, 2, 2, 3)
	f:SetName(title)
	if IsValid(f.Header) then f.Header:SetFont("SPeditor.Bold") f.Header:SetTextColor(COL.TEXT) end
	f.Paint = function(s, w, h)
		surface.SetDrawColor(COL.ROW_B)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, 20)
	end
	return f
end

function UI.Check(parent, text, value, onchg)
	local c = vgui.Create("DCheckBoxLabel", parent)
	c:Dock(TOP)
	c:DockMargin(6, 3, 4, 3)
	c:SetText(text)
	c:SetFont("SPeditor.Small")
	c:SetTextColor(COL.TEXT)
	c:SetValue(value and 1 or 0)
	if onchg then c.OnChange = function(_, v) onchg(v) end end
	return c
end

function UI.StyleCombo(c)
	return UI.StyleButton(c)
end

-- A square icon button (viewport and ASE toolbars)
function UI.IconButton(parent, icon, tip, fn, isOn, dock)
	local b = vgui.Create("DButton", parent)
	b:Dock(dock or LEFT)
	b:DockMargin(2, 3, 0, 3)
	b:SetWide(UI.S(24))
	b:SetText("")
	b:SetIcon(icon)
	b:SetTooltip(tip)
	b.Paint = function(s, w, h)
		local on = isOn and isOn() or false
		-- a theme may draw the button with a picture of its own (GM:FM UI: SFM's transport buttons)
		-- (s.SPThemeKey names the picture itself; false — never one)
		local img = IsValid(s.m_Image) and s.m_Image:GetImage()
		local key = s.SPThemeKey
		local own = key ~= false and (key or img) and UI.ThemeIcon(key or img) or nil
		-- no picture of its own: the theme's grey glyph of the same silkicon, if it has one
		local glyph = not own and UI.ThemeGlyph(img) or nil
		if IsValid(s.m_Image) then s.m_Image:SetVisible(own == nil and glyph == nil) end
		if own then
			-- the picture keeps its proportions: the button takes its width from the bar's height
			local want = UI.ThemeIconWide(own, h)
			if s.SPThemeW ~= want then
				s.SPThemeW = want
				s:SetWide(want)
				-- the round play / record buttons stand out of the bar (SFM)
				s:NoClipping(own.base ~= nil and own.h > own.base)
			end
			UI.DrawThemeIcon(own, w, h, on or s:IsHovered())
			return
		end
		local frame = glyph and UI.ThemeGlyphFrame()
		if frame then
			-- the theme's own button shell around the glyph, as its pictured buttons have; lit,
			-- the shell is pressed and the glyph stays grey, only brighter
			local want = UI.ThemeIconWide(frame, h)
			if s.SPThemeW ~= want then
				s.SPThemeW = want
				s:SetWide(want)
			end
			local lit = on or s:IsHovered()
			UI.DrawThemeIcon(frame, w, h, lit)
			local k = h / frame.base
			local is = math.floor(16 * k + 0.5)
			surface.SetMaterial(glyph)
			surface.SetDrawColor(255, 255, 255, lit and 255 or 215)
			surface.DrawTexturedRect(math.floor((w - is) / 2), math.floor(h / 2 - is / 2 + 1.5 * k), is, is)
			return
		end
		UI.PaintChrome("ToolButton", s, w, h, { on = on })
		if glyph then
			local is = UI.IconSize(h)
			local lit = on or s:IsHovered()
			surface.SetMaterial(glyph)
			surface.SetDrawColor(255, 255, 255, lit and 255 or 200)
			surface.DrawTexturedRect(math.floor((w - is) / 2), math.floor((h - is) / 2), is, is)
		end
	end
	b.DoClick = fn
	return b
end

-- Text colour of a DTree node (SetTextColor of the DLabel takes priority over the scheme)
function UI.NodeColor(node, col)
	node.SPeditorColored = true
	if IsValid(node.Label) then
		node.Label:SetTextColor(col)
		node.Label:SetFont("SPeditor.Small")
	end
end

-- a list (DListView) at the interface scale: taller rows, the interface font
function UI.StyleListView(list)
	if UI.Scale() == 1 then return list end
	list:SetDataHeight(UI.S(17))
	list:SetHeaderHeight(UI.S(16))
	local addColumn, addLine = list.AddColumn, list.AddLine
	list.AddColumn = function(s, ...)
		local col = addColumn(s, ...)
		if IsValid(col) and IsValid(col.Header) then col.Header:SetFont("SPeditor.Small") end
		return col
	end
	list.AddLine = function(s, ...)
		local line = addLine(s, ...)
		for _, c in pairs(IsValid(line) and line.Columns or {}) do
			if IsValid(c) and c.SetFont then c:SetFont("SPeditor.Small") end
		end
		return line
	end
	return list
end

function UI.StyleTree(tree)
	-- the rows grow with the interface scale (a0.9: at 200 % the names of the object list
	-- overlapped — the text was scaled, the default 17 px row was not)
	tree:SetIndentSize(UI.S(12))
	tree:SetLineHeight(math.max(UI.S(17), 17))
	tree.Paint = function(_, w, h)
		surface.SetDrawColor(COL.TREE_BG)
		surface.DrawRect(0, 0, w, h)
	end
	return tree
end

---------------------------------------------------------------------
-- Slider control of the Animation Set Editor
---------------------------------------------------------------------
local CTRL = {}

function CTRL:Init()
	self:SetTall(UI.S(18))
	self:SetCursor("sizewe")
	self.min, self.max, self.value, self.default = 0, 1, 0, 0
	self.decimals = 2
	self.label = ""
	self.alt = false
	self:SetMouseInputEnabled(true)
end

-- o = { label, min, max, value, default, decimals, onChange(v, final), getter() }
function CTRL:Setup(o)
	self.label    = o.label or ""
	self.min      = o.min or 0
	self.max      = o.max or 1
	self.default  = o.default or 0
	self.decimals = o.decimals or 2
	self.onChange = o.onChange
	self.getter   = o.getter
	self.value    = math.Clamp(o.value or self.default, self.min, self.max)
	self:SetTooltip(o.tooltip)
	return self
end

function CTRL:SetValue(v, fire, final)
	v = math.Clamp(tonumber(v) or self.default, self.min, self.max)
	self.value = v
	if fire and self.onChange then self.onChange(v, final and true or false) end
end

function CTRL:GetValue() return self.value end

function CTRL:Paint(w, h)
	surface.SetDrawColor(self.alt and COL.ROW_B or COL.ROW_A)
	surface.DrawRect(0, 0, w, h)

	local range = self.max - self.min
	if range > 0 then
		local hot = self.drag or self:IsHovered()
		surface.SetDrawColor(hot and COL.FILL_HOT or COL.FILL)
		if self.min < 0 and self.max > 0 then
			-- two-sided control: fill from zero
			local zx = (0 - self.min) / range * w
			local vx = (self.value - self.min) / range * w
			surface.DrawRect(math.min(zx, vx), 1, math.abs(vx - zx), h - 2)
			surface.SetDrawColor(COL.BORDER)
			surface.DrawRect(zx, 0, 1, h)
		else
			surface.DrawRect(0, 1, (self.value - self.min) / range * w, h - 2)
		end
	end

	draw.SimpleText(self.label, "SPeditor.Small", w / 2, h / 2, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if self.drag or self:IsHovered() then
		draw.SimpleText(string.format("%." .. self.decimals .. "f", self.value), "SPeditor.Small", w - 4, h / 2,
			COL.ORANGE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
end

function CTRL:OnMousePressed(code)
	if code == MOUSE_RIGHT then
		self:OpenMenu()
		return
	end
	if code ~= MOUSE_LEFT then return end
	-- the base Panel has no double click: catch it by hand
	local now = SysTime()
	if self.lastClick and now - self.lastClick < 0.3 then
		self.lastClick = nil
		self:DoDoubleClick()
		return
	end
	self.lastClick = now
	self.drag = { x = gui.MouseX(), v = self.value }
	self:MouseCapture(true)
end

function CTRL:OnCursorMoved()
	local d = self.drag
	if not d then return end
	local w = math.max(self:GetWide(), 40)
	local per = (self.max - self.min) / w
	if input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT) then per = per * 0.1 end
	if input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL) then per = per * 4 end
	local v = d.v + (gui.MouseX() - d.x) * per
	if math.abs(v - self.value) > 1e-6 then self:SetValue(v, true, false) end
end

function CTRL:OnMouseReleased(code)
	if code ~= MOUSE_LEFT or not self.drag then return end
	self.drag = nil
	self:MouseCapture(false)
	if self.onChange then self.onChange(self.value, true) end
	self.lastEdit = RealTime()
end

function CTRL:DoDoubleClick()
	self:SetValue(self.default, true, true)
	self.lastEdit = RealTime()
end

function CTRL:OpenMenu()
	local L = SPeditor.L
	local m = SPeditor.UI.Menu()
	m:AddOption(L("ctrl_reset"), function() self:DoDoubleClick() end)
	m:AddOption(L("ctrl_enter"), function()
		Derma_StringRequest(self.label, L("enter_value"), string.format("%." .. self.decimals .. "f", self.value), function(txt)
			local v = tonumber((string.gsub(txt, ",", ".")))
			if v then
				self:SetValue(v, true, true)
				self.lastEdit = RealTime()
			end
		end)
	end)
	if self.extraMenu then self.extraMenu(m) end
	m:Open()
end

-- pull the value from the entity (after undo, presets, pose reset)
function CTRL:Think()
	if self.drag or not self.getter then return end
	if self.lastEdit and RealTime() - self.lastEdit < 0.8 then return end
	if (self.nextPoll or 0) > RealTime() then return end
	self.nextPoll = RealTime() + 0.25
	local v = self.getter()
	if v and math.abs(v - self.value) > 1e-3 then self.value = math.Clamp(v, self.min, self.max) end
end

vgui.Register("SPeditorControl", CTRL, "Panel")

function UI.Control(parent, o)
	local c = vgui.Create("SPeditorControl", parent)
	c:Dock(TOP)
	c:DockMargin(0, 0, 0, 1)
	c:Setup(o)
	return c
end

-- A toggle row in the control list (like SFM toggle controls)
function UI.ToggleRow(parent, label, getter, setter)
	local b = vgui.Create("DButton", parent)
	b:Dock(TOP)
	b:DockMargin(0, 0, 0, 1)
	b:SetTall(UI.S(18))
	b:SetText("")
	b.Paint = function(s, w, h)
		local on = getter()
		surface.SetDrawColor(s:IsHovered() and COL.ROW_A or COL.ROW_B)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(on and COL.ORANGE or COL.CTRL)
		surface.DrawRect(4, 4, 10, 10)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawOutlinedRect(4, 4, 10, 10, 1)
		draw.SimpleText(label, "SPeditor.Small", w / 2, h / 2, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	b.DoClick = function() setter(not getter()) end
	return b
end

-- A link row (a bone "- pos / - rot"): a click selects
function UI.LinkRow(parent, label, col, isSel, fn)
	local b = vgui.Create("DButton", parent)
	b:Dock(TOP)
	b:DockMargin(0, 0, 0, 1)
	b:SetTall(UI.S(18))
	b:SetText("")
	b.Paint = function(s, w, h)
		local sel = isSel and isSel()
		surface.SetDrawColor(sel and COL.SEL or (s:IsHovered() and COL.ROW_A or COL.ROW_B))
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText(label, "SPeditor.Small", w / 2, h / 2, col or COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	b.DoClick = fn
	return b
end
