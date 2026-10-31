-- GM:FM UI (b0.2) — the look of Source Filmmaker's Qt interface in Derma.
-- The colours, gradients and sizes follow SFM's own style sheets (game/platform/tools/
-- stylesheets/valve_base.qss and sfm.qss), the buttons, text fields, check boxes, tabs, tree
-- branches and arrows are SFM's own pictures (materials/speditor/skins/sfm/base, copied from
-- platform/tools/images/valve_base) drawn as nine-slice frames, as Qt draws its border-image.
-- Whatever is missing here is taken from the copy of the stock GMod skin (skins/gmod.lua).
-- SKIN.SPeditor draws the editor's own chrome: the menu bar, the tabbed windows (SFM's
-- CQTabbedWindowTabBar), the status bar and the tool buttons.
local ARG = SPeditor.SkinArg or {}
local UI  = SPeditor.UI
local PAL = UI.PAL
local Default = UI.BaseSkin()

local WHITE = Color(255, 255, 255)
local SEL_TEXT = Color(255, 251, 209)          -- QMenu / QTreeView selection-color

local SKIN = {}

SKIN.PrintName    = "GM:FM UI"
SKIN.Author       = "GM:FM (after Source Filmmaker's Qt style sheets)"
SKIN.DermaVersion = 1
SKIN.GwenTexture  = Default.GwenTexture

SKIN.colTextEntryText            = PAL.TEXT
SKIN.colTextEntryTextHighlight   = Color(93, 102, 125)       -- #5D667D
SKIN.colTextEntryTextCursor      = PAL.TEXT
SKIN.colTextEntryTextPlaceholder = PAL.DIM
SKIN.colNumSliderNotch           = Color(255, 255, 255, 40)

local Colours = table.Copy(Default.Colours)
SKIN.Colours = Colours

Colours.Window.TitleActive   = PAL.TEXT
Colours.Window.TitleInactive = PAL.DIM
Colours.Button.Normal   = Color(220, 220, 220)       -- QPushButton color
Colours.Button.Hover    = WHITE
Colours.Button.Down     = WHITE
Colours.Button.Disabled = Color(230, 230, 230, 94)
Colours.Tab.Active.Normal     = WHITE
Colours.Tab.Active.Hover      = WHITE
Colours.Tab.Active.Down       = WHITE
Colours.Tab.Active.Disabled   = PAL.DIM
Colours.Tab.Inactive.Normal   = Color(182, 182, 182, 178)
Colours.Tab.Inactive.Hover    = PAL.TEXT
Colours.Tab.Inactive.Down     = PAL.TEXT
Colours.Tab.Inactive.Disabled = PAL.DIM
Colours.Label.Default   = PAL.TEXT
Colours.Label.Bright    = WHITE
Colours.Label.Dark      = PAL.TEXT
Colours.Label.Highlight = PAL.ORANGE
Colours.Tree.Lines    = Color(70, 70, 70)
Colours.Tree.Normal   = PAL.TEXT
Colours.Tree.Hover    = WHITE
Colours.Tree.Selected = SEL_TEXT
Colours.Properties.Line_Normal     = PAL.ROW_B
Colours.Properties.Line_Selected   = PAL.SEL
Colours.Properties.Line_Hover      = PAL.ROW_A
Colours.Properties.Title           = PAL.TEXT
Colours.Properties.Column_Normal   = PAL.ROW_A
Colours.Properties.Column_Selected = PAL.FILL
Colours.Properties.Column_Hover    = PAL.ROW_A
Colours.Properties.Column_Disabled = PAL.ROW_B
Colours.Properties.Border          = PAL.BORDER
Colours.Properties.Label_Normal    = PAL.TEXT
Colours.Properties.Label_Selected  = WHITE
Colours.Properties.Label_Hover     = WHITE
Colours.Properties.Label_Disabled  = PAL.DIM
Colours.Category.Header        = PAL.TEXT
Colours.Category.Header_Closed = PAL.DIM
for _, key in ipairs({ "Line", "LineAlt" }) do
	local line = Colours.Category[key]
	line.Text            = PAL.TEXT
	line.Text_Hover      = WHITE
	line.Text_Selected   = SEL_TEXT
	line.Text_Disabled   = PAL.DIM
	line.Button          = (key == "Line") and PAL.ROW_B or PAL.ROW_A
	line.Button_Hover    = PAL.FILL
	line.Button_Selected = PAL.SEL
	line.Button_Disabled = PAL.ROW_B
end
Colours.TooltipText = Color(20, 20, 20)

---------------------------------------------------------------------
-- SFM's pictures
---------------------------------------------------------------------
local DIR = "speditor/skins/sfm/base/"
local mats = {}
local function mat(name)
	local m = mats[name]
	if m == nil then
		m = Material(DIR .. name .. ".png")
		if m:IsError() then m = false end
		mats[name] = m
	end
	return m or nil
end

-- nine-slice frames, as Qt's "border-image: url(…) N"
local frames = {}
local function frame(name, border, x, y, w, h, col)
	local f = frames[name]
	if f == nil then
		local m = mat(name)
		if m then
			local t = m:GetTexture("$basetexture")
			f = GWEN.CreateTextureBorder(0, 0, t:Width(), t:Height(), border, border, border, border, m)
		end
		frames[name] = f or false
	end
	if f then f(x, y, w, h, col) end
	return f ~= false
end

local function image(name, x, y, w, h, alpha)
	local m = mat(name)
	if not m then return end
	surface.SetMaterial(m)
	surface.SetDrawColor(255, 255, 255, alpha or 255)
	surface.DrawTexturedRect(x, y, w, h)
end

-- a picture at its own size (or scaled with the interface) in the centre of w x h
local function centred(name, w, h, iw, ih, alpha)
	local k = math.max(UI.Scale(), 1)
	iw, ih = math.floor(iw * k), math.floor(ih * k)
	image(name, math.floor((w - iw) / 2), math.floor((h - ih) / 2), iw, ih, alpha)
end

---------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------
local matDown  = Material("gui/gradient_down")
local matRight = Material("gui/gradient")

local function rect(c, x, y, w, h, a)
	surface.SetDrawColor(c.r, c.g, c.b, a or c.a or 255)
	surface.DrawRect(x, y, w, h)
end

-- a vertical gradient from top (c1) to bottom (c2)
local function vgrad(x, y, w, h, c1, c2)
	rect(c2, x, y, w, h)
	surface.SetMaterial(matDown)
	surface.SetDrawColor(c1.r, c1.g, c1.b, c1.a or 255)
	surface.DrawTexturedRect(x, y, w, h)
end

-- a horizontal gradient from left (c1) to right (c2)
local function hgrad(x, y, w, h, c1, c2)
	rect(c2, x, y, w, h)
	surface.SetMaterial(matRight)
	surface.SetDrawColor(c1.r, c1.g, c1.b, c1.a or 255)
	surface.DrawTexturedRect(x, y, w, h)
end

local function outline(c, x, y, w, h)
	surface.SetDrawColor(c.r, c.g, c.b, c.a or 255)
	surface.DrawOutlinedRect(x, y, w, h, 1)
end

-- QMenuBar / QMenu selection: #5D667D → #464D60
local SEL_TOP, SEL_BOT = Color(93, 102, 125), Color(70, 77, 96)
local function selection(x, y, w, h)
	vgrad(x, y, w, h, SEL_TOP, SEL_BOT)
end

-- QAbstractItemView selection: rgba(69, 76, 87) with a lighter middle
local ITEM_SEL = Color(69, 76, 87)
local function itemSelection(x, y, w, h)
	rect(ITEM_SEL, x, y, w, h)
	rect(Color(255, 255, 255), x, y + math.floor(h * 0.55), w, h - math.floor(h * 0.55), 6)
end

local function pushState(panel, checked)
	if not panel:IsEnabled() then return "pushbutton_disabled" end
	local down = panel.Depressed or (panel.IsSelected and panel:IsSelected())
	if down then return "pushbutton_pressed" end
	if checked then return panel.Hovered and "pushbutton_checked_hover" or "pushbutton_checked" end
	if panel.Hovered then return "pushbutton_hover" end
	return "pushbutton_enabled"
end

---------------------------------------------------------------------
-- Panels, windows, buttons
---------------------------------------------------------------------
function SKIN:PaintPanel(panel, w, h)
	if not panel.m_bBackground then return end
	rect(panel.m_bgColor or PAL.BG, 0, 0, w, h)
end

function SKIN:PaintShadow() end

-- a dialog: QInputDialog — the popup frame
function SKIN:PaintFrame(panel, w, h)
	rect(PAL.BG, 0, 0, w, h)
	if not frame("frame_popupdialog", 4, 0, 0, w, h) then outline(PAL.BORDER, 0, 0, w, h) end
	vgrad(1, 1, w - 2, 23, Color(70, 71, 72), Color(42, 42, 42))
end

function SKIN:PaintButton(panel, w, h)
	if not panel.m_bBackground then return end
	frame(pushState(panel, panel.GetToggle and panel:GetToggle()), 3, 0, 0, w, h)
end

function SKIN:PaintWindowCloseButton(panel, w, h)
	if not panel.m_bBackground then return end
	centred(panel.Hovered and "tab-closebutton-hovered" or "tab-closebutton", w, h, 12, 12)
end

function SKIN:PaintWindowMinimizeButton() end
function SKIN:PaintWindowMaximizeButton() end

---------------------------------------------------------------------
-- Check boxes, trees, text fields
---------------------------------------------------------------------
function SKIN:PaintCheckBox(panel, w, h)
	local on = panel:GetChecked()
	local name = "checkbox_" .. (on and "checked" or "unchecked")
	if not panel:IsEnabled() then name = name .. "_disabled"
	elseif panel.Depressed then name = name .. "_pressed"
	elseif panel.Hovered then name = name .. "_hover" end
	local s = math.min(w, h)
	image(name, 0, math.floor((h - s) / 2), s, s)
end

function SKIN:PaintRadioButton(panel, w, h)
	local name = panel:GetChecked() and "radio_selected" or "radio_unselected"
	if not panel:IsEnabled() then name = name .. "_disabled"
	elseif not panel:GetChecked() and panel.Hovered then name = name .. "_hover" end
	local s = math.min(w, h)
	image(name, 0, math.floor((h - s) / 2), s, s)
end

function SKIN:PaintTree(panel, w, h)
	if not panel.m_bBackground then return end
	rect(panel.m_bgColor or PAL.TREE_BG, 0, 0, w, h)
end

function SKIN:PaintExpandButton(panel, w, h)
	centred(panel:GetExpanded() and "arrow_open" or "arrow_closed", w, h, 12, 12)
end

function SKIN:PaintTreeNodeButton(panel, w, h)
	if not panel.m_bSelected then return end
	rect(Color(79, 82, 89), 0, 0, w, h)            -- QTreeView::item:selected
end

function SKIN:PaintSelection(panel, w, h)
	itemSelection(0, 0, w, h)
end

function SKIN:PaintTextEntry(panel, w, h)
	if panel.m_bBackground then
		rect(PAL.LIST_BG, 1, 1, w - 2, h - 2)
		local name = "frame"
		if not panel:IsEnabled() then name = "frame_disabled"
		elseif panel:HasFocus() then name = "frame_focus"
		elseif panel:IsHovered() then name = "frame_hover" end
		frame(name, 3, 0, 0, w, h)
	end

	if panel.GetPlaceholderText and panel.GetPlaceholderColor and panel:GetPlaceholderText()
		and string.Trim(panel:GetPlaceholderText()) ~= "" and panel:GetPlaceholderColor()
		and (not panel:GetText() or panel:GetText() == "") then
		local oldText = panel:GetText()
		local str = panel:GetPlaceholderText()
		if string.StartsWith(str, "#") then str = string.sub(str, 2) end
		panel:SetText(language.GetPhrase(str))
		panel:DrawTextEntryText(panel:GetPlaceholderColor(), panel:GetHighlightColor(), panel:GetCursorColor())
		panel:SetText(oldText)
		return
	end
	panel:DrawTextEntryText(panel:GetTextColor(), panel:GetHighlightColor(), panel:GetCursorColor())
end

---------------------------------------------------------------------
-- Menus (QMenu: a diagonal grey gradient, a blue-grey selection, light yellow text on it)
---------------------------------------------------------------------
function SKIN:PaintMenu(panel, w, h)
	vgrad(0, 0, w, h, Color(70, 71, 72), Color(42, 42, 42))
	outline(Color(20, 20, 20, 102), 0, 0, w, h)
end

function SKIN:PaintMenuSpacer(panel, w, h)
	rect(Color(99, 99, 99, 117), 10, math.floor(h / 2), w - 13, 1)
end

function SKIN:PaintMenuOption(panel, w, h)
	local hot = panel.m_bBackground and panel:IsEnabled() and (panel.Hovered or panel.Highlight)
	if hot then selection(2, 0, w - 4, h) end
	if panel.SPeditorTextHot == nil then panel.SPeditorTextHot = false end
	-- the text turns light yellow on the selection, as in SFM
	if hot ~= panel.SPeditorTextHot then
		panel.SPeditorTextHot = hot
		panel:SetTextColor(hot and SEL_TEXT or nil)
	end
	if panel:GetChecked() then
		local s = math.min(h, 19)
		image("check", 4, math.floor((h - s) / 2), s, s)
	end
end

function SKIN:PaintMenuRightArrow(panel, w, h)
	centred("arrow_right", w, h, 5, 7)
end

function SKIN:PaintMenuBar(panel, w, h)
	vgrad(0, 0, w, h, Color(70, 71, 72), Color(29, 29, 29))
end

-- QToolTip: a pale parchment with dark text
function SKIN:PaintTooltip(panel, w, h)
	vgrad(0, 0, w, h, Color(235, 234, 225, 235), Color(200, 198, 175, 235))
	outline(Color(0, 0, 0, 64), 0, 0, w, h)
end

---------------------------------------------------------------------
-- Tabs (QTabBar / QTabWidget), categories, lists
---------------------------------------------------------------------
function SKIN:PaintPropertySheet(panel, w, h)
	local tab = panel:GetActiveTab()
	local off = tab and (tab:GetTall() - 8) or 0
	vgrad(0, off, w, h - off, Color(57, 57, 57), Color(60, 59, 58))
	outline(Color(122, 122, 122, 51), 0, off, w, h - off)
end

function SKIN:PaintTab(panel, w, h)
	if panel:IsActive() then return self:PaintActiveTab(panel, w, h) end
	rect(Color(44, 44, 44, 102), 0, 2, w, h - 2)
	outline(Color(122, 122, 122, 51), 0, 2, w, h - 2)
end

function SKIN:PaintActiveTab(panel, w, h)
	rect(Color(57, 57, 57), 0, 0, w, h)
	outline(Color(122, 122, 122, 51), 0, 0, w, h + 1)
end

function SKIN:PaintCollapsibleCategory(panel, w, h)
	local hh = panel:GetHeaderHeight()
	if h > hh then rect(PAL.ROW_B, 0, hh, w, h - hh) end
	-- QHeaderView section: near-black gradient with bold light text
	vgrad(0, 0, w, math.min(h, hh), Color(23, 23, 24), Color(31, 31, 32))
end

function SKIN:PaintCategoryList(panel, w, h)
	rect(panel:GetBackgroundColor() or PAL.BG, 0, 0, w, h)
end

function SKIN:PaintListBox(panel, w, h)
	rect(PAL.LIST_BG, 0, 0, w, h)
	outline(Color(155, 153, 151, 64), 0, 0, w, h)
end

function SKIN:PaintListView(panel, w, h)
	if not panel.m_bBackground then return end
	rect(PAL.LIST_BG, 0, 0, w, h)
	outline(Color(155, 153, 151, 64), 0, 0, w, h)
end

function SKIN:PaintListViewLine(panel, w, h)
	if panel:IsSelected() then
		itemSelection(0, 0, w, h)
	elseif panel.Hovered then
		rect(Color(255, 255, 255), 0, 0, w, h, 10)
	elseif panel.m_bAlt then
		rect(Color(137, 136, 135), 0, 0, w, h, 15)      -- alternate-background-color 6%
	end
	rect(Color(38, 38, 39), 0, h - 1, w, 1)
end

---------------------------------------------------------------------
-- Scroll bars, drop-down lists, numbers, sliders
---------------------------------------------------------------------
function SKIN:PaintVScrollBar(panel, w, h)
	rect(PAL.LIST_BG, 0, 0, w, h)
	rect(Color(37, 36, 34), 0, 0, w, h, 64)
	rect(Color(22, 22, 22), 0, 0, 1, h, 153)
	rect(Color(22, 22, 22), w - 1, 0, 1, h, 153)
end

function SKIN:PaintHScrollBar(panel, w, h)
	rect(PAL.LIST_BG, 0, 0, w, h)
	rect(Color(37, 36, 34), 0, 0, w, h, 64)
	rect(Color(22, 22, 22), 0, 0, w, 1, 153)
	rect(Color(22, 22, 22), 0, h - 1, w, 1, 153)
end

-- the grip: grey with a light band at 55 % across, as SFM's handle gradient
function SKIN:PaintScrollBarGrip(panel, w, h)
	local a = panel.Depressed and 204 or (panel.Hovered and 150 or 128)
	local horiz = w > h
	local edge, mid = Color(98, 98, 98, a), Color(150, 150, 150, a)
	if horiz then
		vgrad(1, 1, w - 2, math.floor(h * 0.55), edge, mid)
		vgrad(1, 1 + math.floor(h * 0.55), w - 2, h - 2 - math.floor(h * 0.55), mid, edge)
	else
		hgrad(1, 1, math.floor(w * 0.55), h - 2, edge, mid)
		hgrad(1 + math.floor(w * 0.55), 1, w - 2 - math.floor(w * 0.55), h - 2, mid, edge)
	end
	outline(Color(79, 78, 77, 64), 1, 1, w - 2, h - 2)
end

local function scrollButton(arrow, aw, ah)
	return function(self, panel, w, h)
		if not panel.m_bBackground then return end
		rect(Color(98, 98, 98), 0, 0, w, h, panel.Depressed and 30 or (panel.Hovered and 102 or 51))
		outline(Color(22, 22, 22, 153), 0, 0, w, h)
		centred(panel:IsEnabled() and arrow or (arrow .. "_disabled"), w, h, aw, ah)
	end
end

SKIN.PaintButtonDown  = scrollButton("arrow_down", 7, 5)
SKIN.PaintButtonUp    = scrollButton("arrow_up", 7, 5)
SKIN.PaintButtonLeft  = scrollButton("arrow_left", 5, 7)
SKIN.PaintButtonRight = scrollButton("arrow_right", 5, 7)

function SKIN:PaintComboBox(panel, w, h)
	local name = pushState(panel, false)
	if panel:IsEnabled() and panel:IsMenuOpen() then name = "pushbutton_pressed" end
	frame(name, 4, 0, 0, w, h)
	-- the drop-down part: a thin line to its left
	rect(Color(220, 220, 220), w - 17, 4, 1, h - 8, 38)
end

function SKIN:PaintComboDownArrow(panel, w, h)
	centred(panel.ComboBox:IsEnabled() and "arrow_down" or "arrow_down_disabled", w, h, 7, 5)
end

function SKIN:PaintNumberUp(panel, w, h)
	image(panel.Depressed and "spinup_pressed" or (panel.Hovered and "spinup_hover" or "spinup"), 0, 0, w, h)
end

function SKIN:PaintNumberDown(panel, w, h)
	image(panel.Depressed and "spindown_pressed" or (panel.Hovered and "spindown_hover" or "spindown"), 0, 0, w, h)
end

-- QSlider::handle: a 5 px wide grey lozenge
function SKIN:PaintSliderKnob(panel, w, h)
	local x = math.floor(w / 2) - 3
	if not panel:IsEnabled() then
		rect(Color(74, 74, 74), x, 2, 6, h - 4)
		outline(Color(75, 72, 69), x, 2, 6, h - 4)
		return
	end
	local top = panel.Depressed and Color(170, 170, 170) or (panel.Hovered and Color(160, 160, 160) or Color(143, 143, 143))
	vgrad(x, 2, 6, h - 4, top, Color(91, 88, 85))
	outline(Color(92, 92, 92), x, 2, 6, h - 4)
end

function SKIN:PaintNumSlider(panel, w, h)
	local y = math.floor(h / 2) - 2
	rect(Color(23, 23, 23), 8, y, w - 16, 4, 102)
	outline(Color(32, 32, 32, 128), 8, y, w - 16, 4)
end

function SKIN:PaintProgress(panel, w, h)
	outline(Color(99, 99, 99, 128), 0, 0, w, h)
	local fw = math.floor((w - 4) * panel:GetFraction())
	if fw > 0 then
		local hh = h - 4
		vgrad(2, 2, fw, math.floor(hh * 0.35), Color(138, 136, 133, 153), Color(116, 115, 112))
		rect(Color(116, 115, 112), 2, 2 + math.floor(hh * 0.35), fw, math.floor(hh * 0.3))
		vgrad(2, 2 + math.floor(hh * 0.65), fw, hh - math.floor(hh * 0.65), Color(116, 115, 112), Color(114, 112, 110, 153))
	end
end

---------------------------------------------------------------------
-- The editor's own chrome (cl_ui_theme.lua UI.PaintChrome)
---------------------------------------------------------------------
local TAB_BAR    = Color(38, 38, 39)           -- CQTabbedWindowTabBar / CQTabbedWindow
local TAB_TEXT   = Color(220, 220, 220)        -- normalSelectedTextColor
local TAB_LINE   = Color(111, 110, 110)        -- lineColor
local STATUS_BG  = Color(38, 38, 39)

SKIN.SPeditor = {
	TextColors = { MenuBar = Color(200, 200, 200), StatusBar = Color(182, 182, 182) },
}

-- A tabbed window: SFM draws its tabs with tab-selected / tab-deselected pictures on a near-black bar
function SKIN.SPeditor.Window(_, win, w, h, info)
	local e, th = info.edge, info.tabH
	rect(PAL.BG, 0, 0, w, h)
	rect(TAB_BAR, 0, 0, w, e + th)
	outline(info.tiled and TAB_BAR or Color(90, 90, 92), 0, 0, w, h)
	if info.onTop then rect(PAL.ORANGE, 1, 1, w - 2, 2) end
	for _, t in ipairs(info.tabs) do
		local name = t.on and "tab-selected" or "tab-deselected"
		local a = t.on and 255 or (t.hot and 255 or 210)
		if not frame(name, 6, t.x, e + 1, t.w, th - 1, Color(255, 255, 255, a)) then
			rect(t.on and PAL.TAB_ON or PAL.TAB_OFF, t.x, e + 1, t.w, th - 1)
		end
		UI.DrawTabLabel(t, e, th, t.on and TAB_TEXT or Color(182, 182, 182, t.hot and 230 or 160))
	end
	-- the line under the tabs that joins the selected tab with the window
	rect(TAB_LINE, 0, e + th - 1, w, 1, 90)
end

function SKIN.SPeditor.CloseButton(_, b, w, h)
	centred(b:IsHovered() and "tab-closebutton-selected-hovered" or "tab-closebutton", w, h, 12, 12)
end

function SKIN.SPeditor.MenuBar(_, _, w, h)
	vgrad(0, 0, w, h, Color(70, 71, 72), Color(29, 29, 29))
	rect(Color(20, 20, 20), 0, h - 2, w, 2, 128)
end

function SKIN.SPeditor.MenuButton(_, b, w, h)
	if b:IsHovered() or b._menuOpen then selection(0, 2, w, h - 5) end
end

function SKIN.SPeditor.StatusBar(_, _, w, h)
	rect(STATUS_BG, 0, 0, w, h)
	rect(Color(20, 20, 20), 0, 0, w, 1)
end

-- QToolButton: flat; on hover a rounded grey glow with a frame; checked — a grey fill
function SKIN.SPeditor.ToolButton(_, b, w, h, info)
	if info and info.on then
		draw.RoundedBox(4, 0, 0, w, h, Color(90, 90, 90, 128))
		return
	end
	if b:IsHovered() then
		draw.RoundedBox(4, 0, 0, w, h, Color(90, 90, 90, 178))
		draw.RoundedBox(4, 1, 1, w - 2, h - 2, Color(64, 64, 64))
	end
end

-- SFM's own pictures for the editor's tool buttons (UI.IconButton): the transport of the
-- timeline, the gizmo modes, the settings gear. Each is a whole button with its frame.
-- They are all drawn at the scale of a 32-pixel button (base); the round play and record
-- buttons are taller and stand out of the bar above and below, as in SFM. cy — the middle of
-- the drawn button inside its picture (the 32-pixel ones have 3 empty rows at the top), so
-- that the middles line up (b0.2: play stood lower and smaller than its neighbours).
-- (onName — the picture of the switched-on button; the viewport's manipulators take the grey
-- copies of SFM's blue ones, tools/make_grey_active.py)
local function sfmIcon(name, w, h, cy, onName)
	local m = Material("speditor/skins/sfm/sfm/" .. name .. ".png")
	local on = Material("speditor/skins/sfm/sfm/" .. (onName or name .. "_activated") .. ".png")
	if m:IsError() then return nil end
	return { mat = m, on = on:IsError() and m or on, w = w, h = h, base = 32, cy = cy or 17.5 }
end
SKIN.SPeditor.Icons = {
	["icon16/control_start_blue.png"]       = sfmIcon("icon_cp_firstframe", 32, 32),
	["icon16/control_rewind_blue.png"]      = sfmIcon("icon_cp_prevframe", 32, 32),
	["icon16/control_play_blue.png"]        = sfmIcon("icon_cp_play", 34, 38, 18.5),
	["icon16/control_pause_blue.png"]       = sfmIcon("icon_cp_pause", 34, 38, 18.5),
	["icon16/control_fastforward_blue.png"] = sfmIcon("icon_cp_nextframe", 32, 32),
	["icon16/control_end_blue.png"]         = sfmIcon("icon_cp_lastframe", 32, 32),
	["icon16/bullet_red.png"]               = sfmIcon("icon_cp_record", 36, 38, 18.5),
	play_once                               = sfmIcon("icon_cp_play_once", 32, 32),
	bookmark                                = sfmIcon("icon_bookmark", 40, 32),
	ase_add                                 = sfmIcon("icon_cp_plus_menu", 40, 32),
	ase_gear                                = sfmIcon("icon_gear_dd", 40, 32),
	play_loop                               = sfmIcon("icon_cp_play_loop", 32, 32),
	play_bounce                             = sfmIcon("icon_cp_play_bounce", 32, 32),
	-- the timeline's three editors (b0.2.6): Clip, Motion, Graph
	mode_clip                               = sfmIcon("icon_mode_timeline", 32, 32),
	mode_motion                             = sfmIcon("icon_mode_motioneditor", 32, 32),
	mode_graph                              = sfmIcon("icon_mode_grapheditor", 32, 32),
	["icon16/cog.png"]                      = sfmIcon("icon_gear", 40, 32),
	["icon16/arrow_out.png"]                = sfmIcon("icon_manipulator_move", 32, 32, nil, "icon_manipulator_move_activated_grey"),
	["icon16/arrow_rotate_clockwise.png"]   = sfmIcon("icon_manipulator_rotate", 32, 32, nil, "icon_manipulator_rotate_activated_grey"),
	["icon16/world.png"]                    = sfmIcon("icon_manipulator_move", 32, 32, nil, "icon_manipulator_move_global_grey"),
	["icon16/time.png"]                     = sfmIcon("icon_timeselectionmode", 32, 32),
	["icon16/arrow_inout.png"]              = sfmIcon("icon_fullscreen", 32, 32, nil, "icon_fullscreen_activated_grey"),
}

-- every other silkicon of a tool button: the same picture in SFM's grey (tools/make_glyphs.py)
SKIN.SPeditor.Glyphs = "speditor/skins/sfm/glyph/"
-- and the frame they sit in: SFM's own button, its picture emptied (made from icon_snap), so
-- every tool button has the same shell as move, scale and the transport (b0.2)
SKIN.SPeditor.GlyphFrame = sfmIcon("frame_button", 32, 32)

-- the Animation Set Editor's own item icons (14 x 14)
SKIN.SPeditor.ItemIcons = {
	ragdoll = "speditor/skins/sfm/sfm/icon_model_item.png", prop = "speditor/skins/sfm/sfm/icon_model_item.png",
	camera = "speditor/skins/sfm/sfm/icon_camera_item.png", light = "speditor/skins/sfm/sfm/icon_light_item.png",
	effect = "speditor/skins/sfm/sfm/icon_particle_item.png",
}

derma.DefineSkin(ARG.name or "SPeditor.speditor", "GM:FM UI", SKIN)
