--[[
SPeditor — theme and basic widgets in the style of Source Filmmaker.

The colours are taken from screenshots of the SFM interface: dark grey panels, light
active tabs, a black field outside the frame, an orange selection accent,
in the tree the right side of the body is red, the left one green.

Widgets:
  UI.Label / UI.Button / UI.Slider / UI.Section / UI.Check / UI.StyleCombo
  UI.StyleButton(button, hot, rounded) — button look: in a theme with its own Derma skin
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

surface.CreateFont("SPeditor.Small", { font = "Tahoma", size = 13, weight = 500, antialias = true })
surface.CreateFont("SPeditor.Bold",  { font = "Tahoma", size = 13, weight = 800, antialias = true })
surface.CreateFont("SPeditor.Time",  { font = "Tahoma", size = 21, weight = 400, antialias = true })

---------------------------------------------------------------------
-- Simple widgets
---------------------------------------------------------------------
-- Look of a button and a drop-down list. hot — the colour under the cursor, base — the regular one
-- (both optional), rounded — the corner radius.
function UI.StyleButton(b, hot, rounded, base)
	b:SetFont("SPeditor.Small")
	if UI.IsNative and UI.IsNative() then return b end
	b:SetTextColor(COL.TEXT)
	b.Paint = function(s, w, h)
		local fill = s:IsHovered() and (hot or COL.HOVER) or (base or COL.CTRL)
		if rounded then
			draw.RoundedBox(rounded, 0, 0, w, h, fill)
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
	b:SetTall(tall or 22)
	if icon then b:SetIcon(icon) end
	b:SetText((icon and "  " or "") .. (text or ""))
	UI.StyleButton(b)
	if fn then b.DoClick = fn end
	return b
end

function UI.Slider(parent, label, min, max, dec, val, onchg)
	local s = vgui.Create("DNumSlider", parent)
	s:Dock(TOP)
	s:DockMargin(4, 1, 4, 1)
	s:SetTall(22)
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
	b:SetWide(24)
	b:SetText("")
	b:SetIcon(icon)
	b:SetTooltip(tip)
	b.Paint = function(s, w, h)
		local on = isOn and isOn()
		surface.SetDrawColor(on and COL.TAB_ON or (s:IsHovered() and COL.HOVER or COL.HEADER))
		surface.DrawRect(0, 0, w, h)
		if on then
			surface.SetDrawColor(COL.ORANGE)
			surface.DrawRect(0, h - 2, w, 2)
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

function UI.StyleTree(tree)
	tree:SetIndentSize(12)
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
	self:SetTall(18)
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
	b:SetTall(18)
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
	b:SetTall(18)
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
