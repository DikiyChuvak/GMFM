-- GM:FM UI — the editor's own Derma skin: flat dark controls in the
-- colours of the SPeditor.UI.PAL palette (menus, lists, trees, text fields, scroll
-- bars). No textures are needed: everything is drawn with rectangles. Whatever is
-- missing here is taken from the copy of the stock GMod skin (skins/gmod.lua), not from
-- the shared Default skin: Workshop interfaces may replace that one.
local ARG = SPeditor.SkinArg or {}
local PAL = SPeditor.UI.PAL
local Default = SPeditor.UI.BaseSkin()

local WHITE = Color(255, 255, 255)
local CLOSE_HOT = Color(150, 60, 45)

local SKIN = {}

SKIN.PrintName    = "GM:FM UI"
SKIN.Author       = "GM:FM"
SKIN.DermaVersion = 1
SKIN.GwenTexture  = Default.GwenTexture

SKIN.colTextEntryText            = PAL.TEXT
SKIN.colTextEntryTextHighlight   = PAL.SEL
SKIN.colTextEntryTextCursor      = PAL.TEXT
SKIN.colTextEntryTextPlaceholder = PAL.DIM
SKIN.colNumSliderNotch           = Color(255, 255, 255, 50)

-- The colours are the same objects as in the palette: a theme change alters them in place.
local Colours = table.Copy(Default.Colours)
SKIN.Colours = Colours

Colours.Window.TitleActive   = PAL.TEXT
Colours.Window.TitleInactive = PAL.DIM

Colours.Button.Normal   = PAL.TEXT
Colours.Button.Hover    = WHITE
Colours.Button.Down     = WHITE
Colours.Button.Disabled = PAL.DIM

Colours.Tab.Active.Normal     = PAL.TEXT
Colours.Tab.Active.Hover      = WHITE
Colours.Tab.Active.Down       = WHITE
Colours.Tab.Active.Disabled   = PAL.DIM
Colours.Tab.Inactive.Normal   = PAL.DIM
Colours.Tab.Inactive.Hover    = PAL.TEXT
Colours.Tab.Inactive.Down     = PAL.TEXT
Colours.Tab.Inactive.Disabled = PAL.DIM

Colours.Label.Default   = PAL.TEXT
Colours.Label.Bright    = WHITE
Colours.Label.Dark      = PAL.TEXT
Colours.Label.Highlight = PAL.ORANGE

Colours.Tree.Lines    = PAL.CTRL
Colours.Tree.Normal   = PAL.TEXT
Colours.Tree.Hover    = WHITE
Colours.Tree.Selected = WHITE

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
	line.Text_Selected   = WHITE
	line.Text_Disabled   = PAL.DIM
	line.Button          = (key == "Line") and PAL.ROW_B or PAL.ROW_A
	line.Button_Hover    = PAL.FILL
	line.Button_Selected = PAL.SEL
	line.Button_Disabled = PAL.ROW_B
end

Colours.TooltipText = PAL.TEXT

---------------------------------------------------------------------
-- Primitives
---------------------------------------------------------------------
local function rect(c, x, y, w, h)
	surface.SetDrawColor(c.r, c.g, c.b, c.a)
	surface.DrawRect(x, y, w, h)
end

local function box(fill, border, w, h)
	rect(fill, 0, 0, w, h)
	surface.SetDrawColor(border.r, border.g, border.b, border.a)
	surface.DrawOutlinedRect(0, 0, w, h, 1)
end

-- A triangle arrow in the centre of a panel. dir: "u", "d", "l", "r"
local function arrow(c, w, h, dir, size)
	size = size or 3
	local cx, cy = math.floor(w / 2), math.floor(h / 2)
	surface.SetDrawColor(c.r, c.g, c.b, c.a)
	for i = 0, size do
		local len = (size - i) * 2 + 1
		if dir == "d" then surface.DrawRect(cx - (size - i), cy - 1 + i, len, 1)
		elseif dir == "u" then surface.DrawRect(cx - (size - i), cy + 1 - i, len, 1)
		elseif dir == "r" then surface.DrawRect(cx - 1 + i, cy - (size - i), 1, len)
		else surface.DrawRect(cx + 1 - i, cy - (size - i), 1, len) end
	end
end

local function buttonFill(panel)
	if panel.Depressed or (panel.IsSelected and panel:IsSelected()) or (panel.GetToggle and panel:GetToggle()) then
		return PAL.TAB_ON
	end
	if not panel:IsEnabled() then return PAL.ROW_B end
	if panel.Hovered then return PAL.HOVER end
	return PAL.CTRL
end

local function arrowButton(dir)
	return function(self, panel, w, h)
		if not panel.m_bBackground then return end
		rect(buttonFill(panel), 0, 0, w, h)
		arrow(panel:IsEnabled() and PAL.TEXT or PAL.DIM, w, h, dir)
	end
end

local function tick(panel, x, y, s)
	rect(PAL.LIST_BG, x, y, s, s)
	surface.SetDrawColor(PAL.BORDER.r, PAL.BORDER.g, PAL.BORDER.b, 255)
	surface.DrawOutlinedRect(x, y, s, s, 1)
	if panel:GetChecked() then
		rect(panel:IsEnabled() and PAL.ORANGE or PAL.DIM, x + 3, y + 3, s - 6, s - 6)
	end
end

---------------------------------------------------------------------
-- Panels, windows, buttons
---------------------------------------------------------------------
function SKIN:PaintPanel(panel, w, h)
	if not panel.m_bBackground then return end
	rect(panel.m_bgColor or PAL.ROW_B, 0, 0, w, h)
end

function SKIN:PaintShadow() end

function SKIN:PaintFrame(panel, w, h)
	box(PAL.BG, panel:HasHierarchicalFocus() and PAL.HOVER or PAL.BORDER, w, h)
	rect(PAL.HEADER, 1, 1, w - 2, 23)
end

function SKIN:PaintButton(panel, w, h)
	if not panel.m_bBackground then return end
	box(buttonFill(panel), PAL.BORDER, w, h)
end

function SKIN:PaintWindowCloseButton(panel, w, h)
	if not panel.m_bBackground then return end
	if panel.Hovered then rect(CLOSE_HOT, 0, 2, w, h - 4) end
	local c = panel.Hovered and WHITE or PAL.DIM
	local cx, cy = math.floor(w / 2), math.floor(h / 2)
	surface.SetDrawColor(c.r, c.g, c.b, 255)
	for i = 0, 1 do
		surface.DrawLine(cx - 4 + i, cy - 4, cx + 4 + i, cy + 4)
		surface.DrawLine(cx + 3 + i, cy - 4, cx - 5 + i, cy + 4)
	end
end

function SKIN:PaintWindowMinimizeButton() end
function SKIN:PaintWindowMaximizeButton() end

---------------------------------------------------------------------
-- Checkboxes, trees, text fields
---------------------------------------------------------------------
function SKIN:PaintCheckBox(panel, w, h)
	tick(panel, 0, 0, math.min(w, h))
end
SKIN.PaintRadioButton = SKIN.PaintCheckBox

function SKIN:PaintTree(panel, w, h)
	if not panel.m_bBackground then return end
	rect(panel.m_bgColor or PAL.TREE_BG, 0, 0, w, h)
end

function SKIN:PaintExpandButton(panel, w, h)
	local x, y = math.floor(w / 2) - 4, math.floor(h / 2) - 4
	rect(PAL.ROW_B, x, y, 9, 9)
	surface.SetDrawColor(PAL.DIM.r, PAL.DIM.g, PAL.DIM.b, 255)
	surface.DrawOutlinedRect(x, y, 9, 9, 1)
	rect(PAL.TEXT, x + 2, y + 4, 5, 1)
	if not panel:GetExpanded() then rect(PAL.TEXT, x + 4, y + 2, 1, 5) end
end

function SKIN:PaintTreeNodeButton(panel, w, h)
	if not panel.m_bSelected then return end
	local tw = panel:GetTextSize()
	rect(PAL.SEL, 38, 0, tw + 6, h)
end

function SKIN:PaintSelection(panel, w, h)
	rect(PAL.SEL, 0, 0, w, h)
end

function SKIN:PaintTextEntry(panel, w, h)
	if panel.m_bBackground then
		if not panel:IsEnabled() then
			box(PAL.ROW_B, PAL.BORDER, w, h)
		else
			box(PAL.LIST_BG, panel:HasFocus() and PAL.ORANGE or PAL.BORDER, w, h)
		end
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
-- Menus
---------------------------------------------------------------------
function SKIN:PaintMenu(panel, w, h)
	box(PAL.HEADER, PAL.BORDER, w, h)
	if panel:GetDrawColumn() then rect(PAL.ROW_A, 1, 1, 24, h - 2) end
end

function SKIN:PaintMenuSpacer(panel, w, h)
	rect(PAL.BORDER, 0, 0, w, h)
end

function SKIN:PaintMenuOption(panel, w, h)
	if panel.m_bBackground and panel:IsEnabled() and (panel.Hovered or panel.Highlight) then
		rect(PAL.SEL, 1, 0, w - 2, h)
	end
	if panel:GetChecked() then
		rect(panel:IsEnabled() and PAL.ORANGE or PAL.DIM, 9, math.floor(h / 2) - 3, 7, 7)
	end
end

function SKIN:PaintMenuRightArrow(panel, w, h)
	arrow(PAL.TEXT, w, h, "r")
end

function SKIN:PaintMenuBar(panel, w, h)
	rect(PAL.MENU, 0, 0, w, h)
end

function SKIN:PaintTooltip(panel, w, h)
	box(PAL.HEADER, PAL.BORDER, w, h)
end

---------------------------------------------------------------------
-- Tabs, categories, lists
---------------------------------------------------------------------
function SKIN:PaintPropertySheet(panel, w, h)
	local tab = panel:GetActiveTab()
	local off = tab and (tab:GetTall() - 8) or 0
	box(PAL.BG, PAL.BORDER, w, h)
	rect(PAL.CHROME, 0, 0, w, off)
end

function SKIN:PaintTab(panel, w, h)
	if panel:IsActive() then return self:PaintActiveTab(panel, w, h) end
	rect(PAL.TAB_OFF, 0, 0, w, h)
end

function SKIN:PaintActiveTab(panel, w, h)
	rect(PAL.TAB_ON, 0, 0, w, h)
	rect(PAL.ORANGE, 0, 0, w, 1)
end

function SKIN:PaintCollapsibleCategory(panel, w, h)
	local hh = panel:GetHeaderHeight()
	if h > hh then rect(PAL.ROW_B, 0, hh, w, h - hh) end
	rect(PAL.HEADER, 0, 0, w, math.min(h, hh))
end

function SKIN:PaintCategoryList(panel, w, h)
	rect(panel:GetBackgroundColor() or PAL.BG, 0, 0, w, h)
end

function SKIN:PaintListBox(panel, w, h)
	box(PAL.LIST_BG, PAL.BORDER, w, h)
end

function SKIN:PaintListView(panel, w, h)
	if not panel.m_bBackground then return end
	box(PAL.LIST_BG, PAL.BORDER, w, h)
end

function SKIN:PaintListViewLine(panel, w, h)
	if panel:IsSelected() then
		rect(PAL.SEL, 0, 0, w, h)
	elseif panel.Hovered then
		rect(PAL.FILL, 0, 0, w, h)
	elseif panel.m_bAlt then
		rect(PAL.ROW_A, 0, 0, w, h)
	end
end

---------------------------------------------------------------------
-- Scroll bars, drop-down lists, numbers, sliders
---------------------------------------------------------------------
function SKIN:PaintVScrollBar(panel, w, h)
	rect(PAL.LIST_BG, 0, 0, w, h)
end
SKIN.PaintHScrollBar = SKIN.PaintVScrollBar

function SKIN:PaintScrollBarGrip(panel, w, h)
	local c = PAL.CTRL
	if panel.Depressed then c = PAL.TAB_ON elseif panel.Hovered then c = PAL.HOVER end
	rect(c, 2, 1, w - 4, h - 2)
end

SKIN.PaintButtonDown  = arrowButton("d")
SKIN.PaintButtonUp    = arrowButton("u")
SKIN.PaintButtonLeft  = arrowButton("l")
SKIN.PaintButtonRight = arrowButton("r")

function SKIN:PaintComboBox(panel, w, h)
	local fill = PAL.CTRL
	if not panel:IsEnabled() then fill = PAL.ROW_B
	elseif panel.Depressed or panel:IsMenuOpen() then fill = PAL.TAB_ON
	elseif panel.Hovered then fill = PAL.HOVER end
	box(fill, PAL.BORDER, w, h)
end

function SKIN:PaintComboDownArrow(panel, w, h)
	arrow(panel.ComboBox:IsEnabled() and PAL.TEXT or PAL.DIM, w, h, "d")
end

function SKIN:PaintNumberUp(panel, w, h)
	arrow((panel.Hovered or panel.Depressed) and WHITE or PAL.DIM, w, h, "u", 2)
end

function SKIN:PaintNumberDown(panel, w, h)
	arrow((panel.Hovered or panel.Depressed) and WHITE or PAL.DIM, w, h, "d", 2)
end

function SKIN:PaintSliderKnob(panel, w, h)
	local c = PAL.DIM
	if not panel:IsEnabled() then c = PAL.CTRL
	elseif panel.Depressed then c = PAL.ORANGE
	elseif panel.Hovered then c = PAL.TEXT end
	rect(c, math.floor(w / 2) - 3, 2, 6, h - 4)
end

function SKIN:PaintProgress(panel, w, h)
	box(PAL.LIST_BG, PAL.BORDER, w, h)
	rect(PAL.ORANGE, 1, 1, (w - 2) * panel:GetFraction(), h - 2)
end

derma.DefineSkin(ARG.name or "SPeditor.speditor", "GM:FM UI", SKIN)
