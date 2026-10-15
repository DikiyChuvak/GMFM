-- GMod XP — Windows XP Luna Blue Derma skin from "Windows XP Classic UI & HUD" by w4da
-- (https://steamcommunity.com/sharedfiles/filedetails/?id=3816955790).
-- Adapted for SPeditor: the skin is registered under its own name and is active
-- only inside the editor. Left out of the original: the Start menu, taskbar HUD, logon
-- screen, sounds on every click, the global derma_skin switch and the ForceDermaSkin hook.
-- Added: SKIN.SPeditor — how the editor's own windows, tabs, menu bar and status bar look.
local ARG = SPeditor.SkinArg or {}

-- ============================================================================
-- LOCALIZED GLUA GLOBALS (Zero overhead in Paint hooks)
-- ============================================================================
local surface = surface
local draw = draw
local derma = derma
local math = math
local ipairs = ipairs
local pairs = pairs
local tostring = tostring
local IsValid = IsValid
local Color = Color

local surface_SetDrawColor = surface.SetDrawColor
local surface_DrawRect = surface.DrawRect
local surface_DrawOutlinedRect = surface.DrawOutlinedRect
local surface_DrawLine = surface.DrawLine
local draw_RoundedBox = draw.RoundedBox
local draw_RoundedBoxEx = draw.RoundedBoxEx
local draw_SimpleText = draw.SimpleText
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_Clamp = math.Clamp
local utf8_len = (utf8 and utf8.len) or string.len
local utf8_sub = (utf8 and utf8.sub) or string.sub

-- ============================================================================
-- CACHED FONTS TABLE
-- ============================================================================
local FONTS = {
    Title       = "SPeditor.XP.TitleBold",
    Default     = "SPeditor.XP.TahomaDefault",
    Bold        = "SPeditor.XP.TahomaBold",
    Small       = "SPeditor.XP.TahomaSmall",
    MarlettLike = "SPeditor.XP.SymbolBold",
}

surface.CreateFont(FONTS.Title, {
    font      = "Tahoma",
    size      = 13,
    weight    = 700,
    antialias = true,
    extended  = true,
})

surface.CreateFont(FONTS.Default, {
    font      = "Tahoma",
    size      = 13,
    weight    = 500,
    antialias = true,
    extended  = true,
})

surface.CreateFont(FONTS.Bold, {
    font      = "Tahoma",
    size      = 13,
    weight    = 700,
    antialias = true,
    extended  = true,
})

surface.CreateFont(FONTS.Small, {
    font      = "Tahoma",
    size      = 11,
    weight    = 500,
    antialias = true,
    extended  = true,
})

surface.CreateFont(FONTS.MarlettLike, {
    font      = "Tahoma",
    size      = 12,
    weight    = 800,
    antialias = true,
    extended  = true,
})

-- ============================================================================
-- CACHED COLOR PALETTE (Luna Blue Official Hex Codes)
-- ============================================================================
local PALETTE = {
    -- Titlebar colors (#0055EA -> #002D96)
    TitleTopBright      = Color(68, 152, 255, 255),
    TitleStart          = Color(0, 85, 234, 255),     -- #0055EA
    TitleEnd            = Color(0, 45, 150, 255),     -- #002D96
    TitleBottomLine     = Color(0, 30, 110, 255),
    TitleInactiveStart  = Color(122, 150, 223, 255),
    TitleInactiveEnd    = Color(82, 108, 185, 255),
    TitleShadow         = Color(10, 24, 80, 180),

    -- Classic 16x16 Window Icon Colors (Monitor / App Window)
    IconFrameDark       = Color(0, 35, 110, 255),
    IconScreenBlue      = Color(56, 172, 255, 255),
    IconScreenDeep      = Color(18, 108, 215, 255),
    IconScreenGlint     = Color(175, 230, 255, 255),
    IconStandSilver     = Color(220, 224, 232, 255),
    IconMiniHeader      = Color(224, 67, 67, 255),

    -- Frame & Window body (#ECE9D8)
    FrameOuterBorder    = Color(0, 25, 100, 255),
    FrameBorderBlue     = Color(0, 68, 204, 255),
    FrameInnerHighlight = Color(58, 130, 255, 180),
    WindowBody          = Color(236, 233, 216, 255),  -- #ECE9D8
    WindowBodyLight     = Color(247, 245, 236, 255),
    WindowBodyDark      = Color(214, 210, 194, 255),
    WindowBevelLight    = Color(255, 255, 255, 230),
    WindowBevelShadow   = Color(172, 168, 153, 255),  -- #ACA899
    WindowBevelDeep     = Color(113, 111, 100, 255),
    DropShadow          = Color(0, 0, 0, 75),

    -- Window Control Buttons (Close #E04343, Minimize/Maximize Blue)
    CloseBase           = Color(224, 67, 67, 255),    -- #E04343
    CloseHover          = Color(244, 96, 96, 255),
    CloseDown           = Color(176, 38, 38, 255),
    CloseTopGlint       = Color(255, 185, 175, 210),
    CloseBorder         = Color(255, 255, 255, 235),
    CloseOuterShadow    = Color(95, 15, 15, 220),

    WinBtnBase          = Color(38, 106, 235, 255),
    WinBtnHover         = Color(72, 140, 255, 255),
    WinBtnDown          = Color(18, 68, 178, 255),
    WinBtnTopGlint      = Color(155, 200, 255, 210),
    WinBtnBorder        = Color(240, 246, 255, 235),
    WinBtnOuterShadow   = Color(0, 28, 105, 220),
    WinBtnDisabled      = Color(110, 135, 190, 160),

    -- DButton (#003C74 border, silver/green highlights)
    BtnBorder           = Color(0, 60, 116, 255),     -- #003C74
    BtnBorderDisabled   = Color(161, 161, 146, 255),
    BtnTopGlint         = Color(255, 255, 255, 230),
    BtnBottomShade      = Color(208, 204, 188, 255),
    BtnHoverGlowTop     = Color(255, 240, 185, 235),
    BtnHoverGlowBottom  = Color(230, 165, 50, 235),
    BtnDisabledBody     = Color(240, 238, 226, 255),

    -- Green XP Primary / Action Button & Slider Cap
    GreenBorder         = Color(24, 92, 20, 255),
    GreenTopGlint       = Color(185, 245, 180, 210),
    SliderGreenTop      = Color(56, 180, 51, 255),    -- #38B433
    SliderGreenDark     = Color(34, 132, 30, 255),
    SliderBody          = Color(244, 242, 232, 255),
    SliderBorder        = Color(118, 114, 102, 255),
    SliderTrackDark     = Color(158, 154, 140, 255),
    SliderTick          = Color(148, 144, 132, 255),

    -- DTextEntry
    EntryBG             = Color(255, 255, 255, 255),
    EntryDisabledBG     = Color(236, 233, 216, 255),
    EntryBorder         = Color(127, 157, 185, 255),  -- #7F9DB9
    EntryInnerShadow    = Color(220, 228, 238, 255),
    EntryFocusBorder    = Color(0, 85, 234, 255),     -- #0055EA
    EntryFocusGlow1     = Color(0, 102, 255, 85),
    EntryFocusGlow2     = Color(61, 149, 255, 45),
    EntryText           = Color(0, 0, 0, 255),
    EntryHighlight      = Color(49, 106, 197, 255),   -- #316AC5
    EntryCursor         = Color(0, 0, 0, 255),
    EntryPlaceholder    = Color(140, 140, 132, 255),

    -- DVScrollBar (Soft Luna Blue scrollbar like Reference Screenshot 3)
    ScrollTrack         = Color(245, 243, 234, 255),
    ScrollTrackBorder   = Color(216, 212, 196, 255),
    ScrollGripBase      = Color(178, 206, 252, 255),
    ScrollGripHover     = Color(198, 220, 255, 255),
    ScrollGripDown      = Color(138, 176, 245, 255),
    ScrollGripBorder    = Color(104, 142, 208, 255),
    ScrollGripGlint     = Color(235, 244, 255, 235),
    ScrollGripLines     = Color(82, 122, 192, 220),
    ScrollGripLinesHi   = Color(235, 244, 255, 220),
    ScrollArrowGlyph    = Color(28, 62, 128, 255),

    -- DPropertySheet & DTab (Explorer tabs)
    SheetBG             = Color(248, 247, 241, 255),
    SheetBorder         = Color(145, 155, 156, 255),  -- #919B9C
    TabActiveBG         = Color(248, 247, 241, 255),
    TabInactiveBG       = Color(230, 227, 210, 255),
    TabHoverBG          = Color(242, 240, 228, 255),
    TabOrangeTop        = Color(255, 199, 60, 255),   -- #FFC73C
    TabOrangeSub        = Color(230, 139, 44, 255),   -- #E68B2C

    -- DMenu (Classic XP Dropdown / Context Menu)
    MenuBG              = Color(255, 255, 255, 255),
    MenuBorder          = Color(138, 134, 122, 255),
    MenuGutterLeft      = Color(236, 233, 216, 255),
    MenuGutterRight     = Color(214, 210, 194, 255),
    MenuGutterLine      = Color(194, 190, 174, 255),
    MenuDivider         = Color(172, 168, 153, 255),
    MenuDividerHi       = Color(255, 255, 255, 255),
    MenuHoverBG         = Color(49, 106, 197, 255),   -- #316AC5
    MenuHoverBorder     = Color(18, 64, 148, 255),

    -- DListView & DTree (#ECE9D8 classic grey tree with dotted lines & #6375D6 Task Pane accent)
    ListBG              = Color(255, 255, 255, 255),
    ListRowAlt          = Color(246, 245, 238, 255),
    ListRowHover        = Color(222, 234, 252, 255),
    ListRowSelected     = Color(49, 106, 197, 255),   -- #316AC5
    TreeBG              = Color(236, 233, 216, 255),  -- #ECE9D8 (Classic XP grey/beige tree)
    TreeTaskPaneStripe  = Color(99, 117, 214, 255),   -- #6375D6 (XP Task Pane accent)
    TreeDotLine         = Color(120, 116, 104, 255),  -- Classic dotted line color
    TreeRowDivider      = Color(224, 220, 202, 255),

    -- Category / Explorer Task Pane (#215DC6 soft header & warm gold tool highlight)
    CatHeaderStart      = Color(33, 93, 198, 255),    -- #215DC6
    CatHeaderEnd        = Color(68, 126, 226, 255),
    CatHeaderClosedStart= Color(62, 112, 208, 255),
    CatHeaderClosedEnd  = Color(99, 117, 214, 255),   -- #6375D6
    CatHeaderTopGlint   = Color(130, 178, 255, 145),
    CatBodyBG           = Color(245, 243, 232, 255),
    CatBodyBorder       = Color(204, 200, 184, 255),
    CatLineGold         = Color(230, 184, 76, 255),
    CatLineGoldBorder   = Color(198, 148, 40, 255),
    CatLineHover        = Color(224, 234, 252, 255),

    -- DCheckBox & Progress & Tooltip
    CheckBorder         = Color(28, 81, 128, 255),    -- #1C5180
    CheckGreen          = Color(33, 161, 33, 255),    -- #21A121
    CheckHoverGlow      = Color(248, 179, 48, 180),
    ProgressBG          = Color(255, 255, 255, 255),
    ProgressChunk       = Color(40, 210, 40, 255),
    ProgressChunkHi     = Color(120, 245, 120, 255),
    TooltipBG           = Color(255, 255, 225, 255),  -- #FFFFE1
    TooltipBorder       = Color(0, 0, 0, 255),

    -- Standard Colors
    White               = Color(255, 255, 255, 255),
    Black               = Color(0, 0, 0, 255),
    TextDark            = Color(0, 21, 66, 255),
    TextMuted           = Color(120, 118, 108, 255),
}

-- ============================================================================
-- PRE-COMPUTED GRADIENT TABLES (Zero runtime allocations)
-- ============================================================================
local function BuildGradientTable(c1, c2, steps)
    local tbl = {}
    for i = 1, steps do
        local t = (i - 1) / math_max(steps - 1, 1)
        tbl[i] = Color(
            math_floor(c1.r + (c2.r - c1.r) * t + 0.5),
            math_floor(c1.g + (c2.g - c1.g) * t + 0.5),
            math_floor(c1.b + (c2.b - c1.b) * t + 0.5),
            math_floor(c1.a + (c2.a - c1.a) * t + 0.5)
        )
    end
    return tbl
end

local GRADIENTS = {
    -- Titlebar vertical gradient (#0055EA -> #002D96)
    TitleActive      = BuildGradientTable(PALETTE.TitleStart, PALETTE.TitleEnd, 12),
    TitleInactive    = BuildGradientTable(PALETTE.TitleInactiveStart, PALETTE.TitleInactiveEnd, 12),

    -- Caption buttons vertical gradients (matching Reference Screenshot 3)
    CloseBtnNormal   = BuildGradientTable(Color(242, 120, 106), PALETTE.CloseBase, 6),
    CloseBtnHover    = BuildGradientTable(Color(255, 145, 132), PALETTE.CloseHover, 6),
    WinBtnNormal     = BuildGradientTable(Color(92, 152, 248), PALETTE.WinBtnBase, 6),
    WinBtnHover      = BuildGradientTable(Color(122, 175, 255), PALETTE.WinBtnHover, 6),

    -- Classic Silver/Cream Luna Button
    ButtonNormal     = BuildGradientTable(Color(253, 253, 251), Color(218, 214, 198), 8),
    ButtonHover      = BuildGradientTable(Color(255, 254, 248), Color(226, 222, 206), 8),
    ButtonDown       = BuildGradientTable(Color(212, 208, 192), Color(242, 240, 230), 8),

    -- Classic Green XP Button (for highlighted / primary buttons)
    ButtonGreen      = BuildGradientTable(Color(92, 190, 84), Color(36, 124, 30), 8),
    ButtonGreenHover = BuildGradientTable(Color(115, 212, 106), Color(46, 148, 38), 8),
    ButtonGreenDown  = BuildGradientTable(Color(32, 110, 26), Color(78, 168, 70), 8),

    -- Explorer Task Pane Header (#215DC6 -> #447EE2 soft gradient)
    CategoryHeader   = BuildGradientTable(PALETTE.CatHeaderStart, PALETTE.CatHeaderEnd, 12),
    CategoryClosed   = BuildGradientTable(PALETTE.CatHeaderClosedStart, PALETTE.CatHeaderClosedEnd, 12),

    -- Menu left gutter horizontal gradient
    MenuGutter       = BuildGradientTable(PALETTE.MenuGutterLeft, PALETTE.MenuGutterRight, 6),
}

local function DrawVerticalGradient(x, y, w, h, grad)
    if w <= 0 or h <= 0 then return end
    local count = #grad
    local stepH = h / count
    for i = 1, count do
        local sy = y + math_floor((i - 1) * stepH)
        local ey = (i == count) and (y + h) or (y + math_floor(i * stepH))
        local bh = ey - sy
        if bh > 0 then
            surface_SetDrawColor(grad[i])
            surface_DrawRect(x, sy, w, bh)
        end
    end
end

local function DrawHorizontalGradient(x, y, w, h, grad)
    if w <= 0 or h <= 0 then return end
    local count = #grad
    local stepW = w / count
    for i = 1, count do
        local sx = x + math_floor((i - 1) * stepW)
        local ex = (i == count) and (x + w) or (x + math_floor(i * stepW))
        local bw = ex - sx
        if bw > 0 then
            surface_SetDrawColor(grad[i])
            surface_DrawRect(sx, y, bw, h)
        end
    end
end

local function DrawArrowGlyph(dir, cx, cy, col)
    surface_SetDrawColor(col)
    if dir == "up" then
        surface_DrawRect(cx,     cy - 2, 1, 1)
        surface_DrawRect(cx - 1, cy - 1, 3, 1)
        surface_DrawRect(cx - 2, cy,     5, 1)
        surface_DrawRect(cx - 3, cy + 1, 7, 1)
    elseif dir == "down" then
        surface_DrawRect(cx - 3, cy - 1, 7, 1)
        surface_DrawRect(cx - 2, cy,     5, 1)
        surface_DrawRect(cx - 1, cy + 1, 3, 1)
        surface_DrawRect(cx,     cy + 2, 1, 1)
    elseif dir == "left" then
        surface_DrawRect(cx - 2, cy,     1, 1)
        surface_DrawRect(cx - 1, cy - 1, 1, 3)
        surface_DrawRect(cx,     cy - 2, 1, 5)
        surface_DrawRect(cx + 1, cy - 3, 1, 7)
    elseif dir == "right" then
        surface_DrawRect(cx - 1, cy - 3, 1, 7)
        surface_DrawRect(cx,     cy - 2, 1, 5)
        surface_DrawRect(cx + 1, cy - 1, 1, 3)
        surface_DrawRect(cx + 2, cy,     1, 1)
    end
end

-- Helper to draw classic 16x16 Windows XP Window / Computer icon in DFrame titlebar
local function DrawXPWindowIcon(x, y)
    surface_SetDrawColor(PALETTE.IconFrameDark)
    surface_DrawRect(x + 1, y + 1, 13, 10)
    surface_SetDrawColor(PALETTE.White)
    surface_DrawOutlinedRect(x + 1, y + 1, 13, 10)

    surface_SetDrawColor(PALETTE.IconScreenDeep)
    surface_DrawRect(x + 2, y + 2, 11, 8)
    surface_SetDrawColor(PALETTE.IconScreenBlue)
    surface_DrawRect(x + 2, y + 4, 11, 6)

    surface_SetDrawColor(PALETTE.IconMiniHeader)
    surface_DrawRect(x + 11, y + 2, 2, 2)

    surface_SetDrawColor(PALETTE.IconScreenGlint)
    surface_DrawRect(x + 3, y + 5, 4, 2)
    surface_DrawRect(x + 3, y + 7, 2, 1)

    surface_SetDrawColor(PALETTE.IconStandSilver)
    surface_DrawRect(x + 6, y + 11, 3, 2)
    surface_DrawRect(x + 4, y + 13, 7, 2)
    surface_SetDrawColor(PALETTE.IconFrameDark)
    surface_DrawLine(x + 4, y + 14, x + 11, y + 14)
end

-- ============================================================================
-- SKIN DEFINITION TABLE
-- ============================================================================
local SKIN = {}

SKIN.PrintName   = "Windows XP Classic UI & Derma Skin (Luna Blue)"
SKIN.Author      = "Windows XP UI Addon"
SKIN.Description = "Classic Windows XP Luna Blue UI & Derma Skin"
-- whatever this skin does not draw is drawn by SPeditor's copy of the stock skin
local defaultSkin = SPeditor.UI.BaseSkin and SPeditor.UI.BaseSkin()
SKIN.GwenTexture = defaultSkin and defaultSkin.GwenTexture or Material("gwenskin/GModDefault.png")
if defaultSkin then
    for k, v in pairs(defaultSkin) do
        if k ~= "Colours" then
            SKIN[k] = v
        end
    end
end

SKIN.fontFrame          = FONTS.Title
SKIN.fontTab            = FONTS.Default
SKIN.fontButton         = FONTS.Default
SKIN.fontCategoryHeader = FONTS.Bold

SKIN.bg_color                   = PALETTE.WindowBody
SKIN.bg_color_sleep             = PALETTE.WindowBodyDark
SKIN.bg_color_dark              = PALETTE.WindowBodyDark
SKIN.bg_color_bright            = PALETTE.WindowBodyLight
SKIN.frame_border               = PALETTE.FrameOuterBorder
SKIN.frame_title                = PALETTE.TitleStart

SKIN.control_color              = PALETTE.WindowBody
SKIN.control_color_highlight    = PALETTE.WindowBodyLight
SKIN.control_color_active       = PALETTE.EntryHighlight
SKIN.control_color_bright       = PALETTE.White
SKIN.control_color_dark         = PALETTE.WindowBevelShadow

SKIN.colPropertySheet           = PALETTE.SheetBG
SKIN.colTab                     = PALETTE.TabActiveBG
SKIN.colTabInactive             = PALETTE.TabInactiveBG
SKIN.colTabShadow               = PALETTE.WindowBevelShadow
SKIN.colTabText                 = PALETTE.TextDark
SKIN.colTabTextInactive         = PALETTE.TextMuted

SKIN.colButtonText              = PALETTE.TextDark
SKIN.colButtonTextDisabled      = PALETTE.BtnBorderDisabled
SKIN.colButtonBorder            = PALETTE.BtnBorder
SKIN.colButtonBorderHighlight   = PALETTE.White
SKIN.colButtonBorderShadow      = PALETTE.WindowBevelShadow

SKIN.colTextEntryBG             = PALETTE.EntryBG
SKIN.colTextEntryBorder         = PALETTE.EntryBorder
SKIN.colTextEntryText           = PALETTE.EntryText
SKIN.colTextEntryTextHighlight  = PALETTE.EntryHighlight
SKIN.colTextEntryTextCursor     = PALETTE.EntryCursor
SKIN.colTextEntryTextPlaceholder= PALETTE.EntryPlaceholder

SKIN.colMenuBG                  = PALETTE.MenuBG
SKIN.colMenuBorder              = PALETTE.MenuBorder

SKIN.colCategoryText            = PALETTE.White
SKIN.colCategoryTextInactive    = Color(225, 236, 255)
SKIN.colNumberWangBG            = PALETTE.EntryBG

SKIN.Colours = {
    Window = {
        TitleActive   = Color(255, 255, 255),
        TitleInactive = Color(215, 228, 252),
    },
    Button = {
        Normal   = Color(0, 21, 66),
        Hover    = Color(0, 45, 150),
        Down     = Color(0, 15, 45),
        Disabled = Color(161, 161, 146),
    },
    Tab = {
        Active = {
            Normal   = Color(0, 21, 66),
            Hover    = Color(0, 45, 150),
            Down     = Color(0, 21, 66),
            Disabled = Color(161, 161, 146),
        },
        Inactive = {
            Normal   = Color(55, 62, 74),
            Hover    = Color(0, 45, 150),
            Down     = Color(0, 21, 66),
            Disabled = Color(161, 161, 146),
        },
    },
    Label = {
        Default   = Color(20, 20, 20),
        Bright    = Color(255, 255, 255),
        Dark      = Color(0, 0, 0),
        Highlight = Color(0, 85, 234),
    },
    Tree = {
        Lines    = Color(120, 116, 104),
        Normal   = Color(15, 15, 15),
        Hover    = Color(0, 85, 234),
        Selected = Color(255, 255, 255),
    },
    Properties = {
        Line_Normal     = Color(212, 208, 200),
        Line_Selected   = Color(49, 106, 197),
        Line_Hover      = Color(193, 210, 238),
        Title           = Color(255, 255, 255),
        Column_Normal   = Color(255, 255, 255),
        Column_Selected = Color(232, 242, 254),
        Column_Hover    = Color(242, 247, 255),
        Column_Disabled = Color(236, 233, 216),
        Border          = Color(127, 157, 185),
        Label_Normal    = Color(0, 0, 0),
        Label_Selected  = Color(0, 21, 66),
        Label_Hover     = Color(0, 51, 153),
        Label_Disabled  = Color(161, 161, 146),
    },
    Category = {
        Header        = Color(255, 255, 255),
        Header_Closed = Color(235, 242, 255),
        Line = {
            Text            = Color(20, 25, 35),
            Text_Hover      = Color(0, 51, 165),
            Text_Selected   = Color(0, 0, 0),
            Button          = Color(245, 243, 232),
            Button_Hover    = Color(224, 234, 252),
            Button_Selected = Color(230, 184, 76),
        },
        LineAlt = {
            Text            = Color(20, 25, 35),
            Text_Hover      = Color(0, 51, 165),
            Text_Selected   = Color(0, 0, 0),
            Button          = Color(238, 235, 222),
            Button_Hover    = Color(224, 234, 252),
            Button_Selected = Color(230, 184, 76),
        },
    },
    TooltipText = Color(0, 0, 0),
    TooltipDown = Color(0, 0, 0),
}

if defaultSkin and defaultSkin.Colours then
    for k, v in pairs(defaultSkin.Colours) do
        if SKIN.Colours[k] == nil then
            SKIN.Colours[k] = v
        end
    end
end

-- ============================================================================
-- 1. WINDOW FRAMES & CAPTION BUTTONS (Luna Blue #0055EA -> #002D96 & #ECE9D8)
-- ============================================================================
function SKIN:LayoutFrame(panel)
    if not IsValid(panel) then return end

    local rightX = panel:GetWide() - 5
    if IsValid(panel.btnClose) and panel.btnClose:IsVisible() then
        panel.btnClose:SetPos(rightX - 21, 3)
        panel.btnClose:SetSize(21, 20)
        rightX = rightX - 23
    end
    if IsValid(panel.btnMaxim) and panel.btnMaxim:IsVisible() then
        panel.btnMaxim:SetPos(rightX - 21, 3)
        panel.btnMaxim:SetSize(21, 20)
        rightX = rightX - 23
    end
    if IsValid(panel.btnMinim) and panel.btnMinim:IsVisible() then
        panel.btnMinim:SetPos(rightX - 21, 3)
        panel.btnMinim:SetSize(21, 20)
        rightX = rightX - 23
    end

    if IsValid(panel.imgIcon) and panel.imgIcon:IsVisible() then
        panel.imgIcon:SetPos(6, 5)
        panel.imgIcon:SetSize(16, 16)
    end

    -- Neutralize lblTitle so it never paints duplicate text or overlaps caption buttons!
    if IsValid(panel.lblTitle) then
        panel.lblTitle:SetPos(0, 0)
        panel.lblTitle:SetSize(0, 0)
        panel.lblTitle:SetVisible(false)
        panel.lblTitle:SetAlpha(0)
        panel.lblTitle.Paint = function() end
    end
end

function SKIN:PaintFrame(panel, w, h)
    local titleH = 26

    -- Permanently mute child lblTitle so it can never double-render over the titlebar
    if IsValid(panel.lblTitle) then
        if panel.lblTitle:IsVisible() then panel.lblTitle:SetVisible(false) end
        if panel.lblTitle:GetWide() > 0 then panel.lblTitle:SetSize(0, 0) end
        if not panel.lblTitle._winxpMuted then
            panel.lblTitle._winxpMuted = true
            panel.lblTitle.Paint = function() end
        end
    end

    if panel.m_bPaintShadow then
        surface_SetDrawColor(PALETTE.DropShadow)
        surface_DrawRect(2, 2, w, h)
    end

    draw_RoundedBoxEx(6, 0, 0, w, titleH, PALETTE.FrameOuterBorder, true, true, false, false)

    surface_SetDrawColor(PALETTE.FrameOuterBorder)
    surface_DrawRect(0, titleH, w, h - titleH)

    surface_SetDrawColor(PALETTE.FrameBorderBlue)
    surface_DrawRect(1, titleH, w - 2, h - titleH - 1)

    if h > titleH + 4 and w > 6 then
        surface_SetDrawColor(PALETTE.WindowBody)
        surface_DrawRect(3, titleH, w - 6, h - titleH - 3)

        surface_SetDrawColor(PALETTE.WindowBevelLight)
        surface_DrawLine(3, titleH, w - 4, titleH)
        surface_DrawLine(3, titleH, 3, h - 4)

        surface_SetDrawColor(PALETTE.WindowBevelShadow)
        surface_DrawLine(3, h - 4, w - 4, h - 4)
        surface_DrawLine(w - 4, titleH, w - 4, h - 4)
    end

    local isActive = panel:HasHierarchicalFocus()
    local grad = isActive and GRADIENTS.TitleActive or GRADIENTS.TitleInactive
    DrawVerticalGradient(2, 2, w - 4, titleH - 2, grad)

    surface_SetDrawColor(PALETTE.TitleTopBright)
    surface_DrawLine(4, 2, w - 5, 2)
    surface_SetDrawColor(PALETTE.FrameInnerHighlight)
    surface_DrawLine(3, 3, w - 4, 3)

    surface_SetDrawColor(PALETTE.TitleBottomLine)
    surface_DrawLine(1, titleH - 1, w - 2, titleH - 1)

    -- Draw 16x16 icon
    if not (IsValid(panel.imgIcon) and panel.imgIcon:IsVisible()) then
        DrawXPWindowIcon(6, 5)
    end

    -- Draw single crisp Titlebar text with right-boundary calculation to prevent clipping buttons
    local titleText = (panel.GetTitle and panel:GetTitle())
    if not titleText or titleText == "" then
        titleText = (IsValid(panel.lblTitle) and panel.lblTitle:GetText()) or ""
    end

    if titleText and titleText ~= "" then
        local btnSpace = 0
        if IsValid(panel.btnClose) and panel.btnClose:IsVisible() then btnSpace = btnSpace + 24 end
        if IsValid(panel.btnMaxim) and panel.btnMaxim:IsVisible() then btnSpace = btnSpace + 23 end
        if IsValid(panel.btnMinim) and panel.btnMinim:IsVisible() then btnSpace = btnSpace + 23 end
        local maxTextW = math_max(10, w - 30 - btnSpace)

        surface.SetFont(FONTS.Title)
        local tw = surface.GetTextSize(titleText)
        if tw > maxTextW then
            local ulen = utf8_len(titleText) or #titleText
            while ulen > 3 and surface.GetTextSize(titleText .. "..") > maxTextW do
                ulen = ulen - 1
                titleText = utf8_sub(titleText, 1, ulen)
            end
            titleText = titleText .. ".."
        end

        draw_SimpleText(titleText, FONTS.Title, 27, 13, PALETTE.TitleShadow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw_SimpleText(titleText, FONTS.Title, 26, 12, PALETTE.White, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end



function SKIN:PaintWindowCloseButton(panel, w, h)
    if not panel:GetPaintBackground() then return end

    local bw = math_Clamp(w - 1, 15, 21)
    local bh = math_Clamp(h - 2, 15, 19)
    local bx = math_floor((w - bw) * 0.5)
    local by = math_floor((h - bh) * 0.5)

    local offset = 0
    local isDown = panel.Depressed or panel:IsSelected()
    if isDown then
        offset = 1
    end

    draw_RoundedBox(3, bx, by, bw, bh, PALETTE.CloseOuterShadow)
    draw_RoundedBox(3, bx, by, bw - 1, bh - 1, PALETTE.CloseBorder)

    if isDown then
        draw_RoundedBox(2, bx + 1, by + 1, bw - 3, bh - 3, PALETTE.CloseDown)
    else
        local grad = panel.Hovered and GRADIENTS.CloseBtnHover or GRADIENTS.CloseBtnNormal
        DrawVerticalGradient(bx + 1, by + 1, bw - 3, bh - 3, grad)
        surface_SetDrawColor(PALETTE.CloseTopGlint)
        surface_DrawLine(bx + 2, by + 1, bx + bw - 4, by + 1)
    end

    local cx = math_floor(bx + bw * 0.5) + offset
    local cy = math_floor(by + bh * 0.5) + offset
    local r = 4

    surface_SetDrawColor(PALETTE.White)
    surface_DrawLine(cx - r,     cy - r, cx + r,     cy + r)
    surface_DrawLine(cx - r + 1, cy - r, cx + r,     cy + r - 1)
    surface_DrawLine(cx - r,     cy - r + 1, cx + r - 1, cy + r)

    surface_DrawLine(cx + r,     cy - r, cx - r,     cy + r)
    surface_DrawLine(cx + r - 1, cy - r, cx - r,     cy + r - 1)
    surface_DrawLine(cx + r,     cy - r + 1, cx - r + 1, cy + r)
end

local function PaintBlueCaptionSquare(panel, w, h)
    local bw = math_Clamp(w - 1, 15, 21)
    local bh = math_Clamp(h - 2, 15, 19)
    local bx = math_floor((w - bw) * 0.5)
    local by = math_floor((h - bh) * 0.5)

    local offset = 0
    local isDown = panel.Depressed or panel:IsSelected()
    if isDown then
        offset = 1
    end

    draw_RoundedBox(3, bx, by, bw, bh, PALETTE.WinBtnOuterShadow)
    draw_RoundedBox(3, bx, by, bw - 1, bh - 1, PALETTE.WinBtnBorder)

    if isDown then
        draw_RoundedBox(2, bx + 1, by + 1, bw - 3, bh - 3, PALETTE.WinBtnDown)
    else
        local grad = (panel.Hovered and panel:IsEnabled()) and GRADIENTS.WinBtnHover or GRADIENTS.WinBtnNormal
        DrawVerticalGradient(bx + 1, by + 1, bw - 3, bh - 3, grad)
        surface_SetDrawColor(PALETTE.WinBtnTopGlint)
        surface_DrawLine(bx + 2, by + 1, bx + bw - 4, by + 1)
    end

    return bx, by, bw, bh, offset
end

function SKIN:PaintWindowMinimizeButton(panel, w, h)
    if not panel:GetPaintBackground() then return end
    local bx, by, bw, bh, offset = PaintBlueCaptionSquare(panel, w, h)

    surface_SetDrawColor(PALETTE.White)
    surface_DrawRect(bx + 4 + offset, by + bh - 6 + offset, math_max(bw - 10, 6), 2)
end

function SKIN:PaintWindowMaximizeButton(panel, w, h)
    if not panel:GetPaintBackground() then return end
    local bx, by, bw, bh, offset = PaintBlueCaptionSquare(panel, w, h)

    local gx = bx + 4 + offset
    local gy = by + 4 + offset
    local gw = math_max(bw - 9, 8)
    local gh = math_max(bh - 9, 7)

    surface_SetDrawColor(PALETTE.White)
    surface_DrawRect(gx, gy, gw, 2)
    surface_DrawOutlinedRect(gx, gy, gw, gh)
end

-- ============================================================================
-- 2. PANELS, BUTTONS & SLIDERS (Rounded XP Buttons & Green-Capped Sliders)
-- ============================================================================
function SKIN:PaintPanel(panel, w, h)
    if not panel.m_bBackground then return end

    local bg = panel.m_bgColor or PALETTE.WindowBody
    surface_SetDrawColor(bg)
    surface_DrawRect(0, 0, w, h)

    surface_SetDrawColor(PALETTE.WindowBevelShadow)
    surface_DrawOutlinedRect(0, 0, w, h)
end

function SKIN:PaintShadow(panel, w, h)
    surface_SetDrawColor(PALETTE.DropShadow)
    surface_DrawRect(0, 0, w, h)
end

function SKIN:PaintButton(panel, w, h)
    if not panel.m_bBackground then return end

    if not panel._winxpFontApplied then
        panel._winxpFontApplied = true
        panel:SetFont(FONTS.Default)
    end

    local isDown = panel.Depressed or panel:IsSelected() or panel:GetToggle()
    local isHovered = panel.Hovered
    local isDisabled = not panel:IsEnabled()
    local isGreen = panel.WinXPGreen

    local borderCol = isDisabled and PALETTE.BtnBorderDisabled
        or (isGreen and PALETTE.GreenBorder or PALETTE.BtnBorder)
    draw_RoundedBox(4, 0, 0, w, h, borderCol)

    if isDisabled then
        draw_RoundedBox(3, 1, 1, w - 2, h - 2, PALETTE.BtnDisabledBody)
        return
    end

    local grad
    if isGreen then
        grad = isDown and GRADIENTS.ButtonGreenDown
            or (isHovered and GRADIENTS.ButtonGreenHover or GRADIENTS.ButtonGreen)
    else
        grad = isDown and GRADIENTS.ButtonDown
            or (isHovered and GRADIENTS.ButtonHover or GRADIENTS.ButtonNormal)
    end

    local insetY = isDown and 2 or 1
    DrawVerticalGradient(1, insetY, w - 2, h - 2, grad)

    if isDown then
        surface_SetDrawColor(PALETTE.WindowBevelShadow)
        surface_DrawLine(1, 1, w - 2, 1)
        surface_DrawLine(1, 1, 1, h - 2)
    else
        surface_SetDrawColor(isGreen and PALETTE.GreenTopGlint or PALETTE.BtnTopGlint)
        surface_DrawLine(2, 1, w - 3, 1)
        surface_DrawLine(2, 2, w - 3, 2)

        surface_SetDrawColor(PALETTE.BtnBottomShade)
        surface_DrawLine(2, h - 2, w - 3, h - 2)

        if isHovered then
            surface_SetDrawColor(PALETTE.BtnHoverGlowTop)
            surface_DrawLine(2, 2, w - 3, 2)
            surface_SetDrawColor(PALETTE.BtnHoverGlowBottom)
            surface_DrawLine(2, h - 2, w - 3, h - 2)
            surface_DrawLine(2, h - 3, w - 3, h - 3)
        end
    end
end

local function PaintXPSliderTrack(slider, w, h)
    local cy = math_floor(h * 0.5) - 2
    local tx = 6
    local tw = math_max(w - 12, 10)

    surface_SetDrawColor(PALETTE.SliderTrackDark)
    surface_DrawRect(tx, cy, tw, 4)
    surface_SetDrawColor(PALETTE.WindowBevelDeep)
    surface_DrawLine(tx, cy, tx + tw - 1, cy)
    surface_DrawLine(tx, cy, tx, cy + 3)
    surface_SetDrawColor(PALETTE.White)
    surface_DrawLine(tx, cy + 3, tx + tw, cy + 3)
    surface_DrawLine(tx + tw - 1, cy, tx + tw - 1, cy + 3)

    local ticks = 10
    local tickY = cy + 7
    surface_SetDrawColor(PALETTE.SliderTick)
    for i = 0, ticks do
        local x = tx + math_floor((i / ticks) * (tw - 1))
        local tickH = (i == 0 or i == 5 or i == ticks) and 4 or 3
        surface_DrawLine(x, tickY, x, tickY + tickH)
    end
end

function SKIN:PaintSliderKnob(panel, w, h)
    local slider = panel:GetParent()
    if IsValid(slider) and not slider._winxpTrackHooked then
        slider._winxpTrackHooked = true
        slider.Paint = PaintXPSliderTrack
    end

    local cx = math_floor(w * 0.5)
    local kw = 11
    local lx = cx - 5
    local ty = 1
    local rectH = math_max(h - 7, 7)

    surface_SetDrawColor(PALETTE.SliderBorder)
    surface_DrawOutlinedRect(lx, ty, kw, rectH)
    surface_SetDrawColor(PALETTE.SliderBody)
    surface_DrawRect(lx + 1, ty + 1, kw - 2, rectH - 2)

    surface_SetDrawColor(PALETTE.White)
    surface_DrawLine(lx + 1, ty + 3, lx + 1, ty + rectH - 1)

    surface_SetDrawColor(PALETTE.SliderGreenDark)
    surface_DrawRect(lx, ty, kw, 3)
    surface_SetDrawColor(PALETTE.SliderGreenTop)
    surface_DrawRect(lx + 1, ty + 1, kw - 2, 2)

    local py = ty + rectH
    for i = 0, 4 do
        local span = kw - (i * 2)
        local sx = lx + i
        surface_SetDrawColor(PALETTE.SliderBody)
        surface_DrawRect(sx, py + i, span, 1)
        surface_SetDrawColor(PALETTE.SliderBorder)
        surface_DrawRect(sx, py + i, 1, 1)
        surface_DrawRect(sx + span - 1, py + i, 1, 1)
    end
end

-- ============================================================================
-- 3. TEXT ENTRY (White background, crisp dark border, blue focus glow)
-- ============================================================================
function SKIN:PaintTextEntry(panel, w, h)
    if panel.m_bBackground then
        local hasFocus = panel:HasFocus()

        if hasFocus then
            surface_SetDrawColor(PALETTE.EntryFocusGlow2)
            surface_DrawRect(0, 0, w, h)
            surface_SetDrawColor(PALETTE.EntryFocusGlow1)
            surface_DrawOutlinedRect(0, 0, w, h)
        end

        if not panel:IsEnabled() then
            surface_SetDrawColor(PALETTE.EntryDisabledBG)
        else
            surface_SetDrawColor(panel.m_bgColor or PALETTE.EntryBG)
        end
        surface_DrawRect(1, 1, w - 2, h - 2)

        surface_SetDrawColor(PALETTE.EntryInnerShadow)
        surface_DrawLine(1, 1, w - 2, 1)
        surface_DrawLine(1, 1, 1, h - 2)

        if hasFocus then
            surface_SetDrawColor(PALETTE.EntryFocusBorder)
            surface_DrawOutlinedRect(0, 0, w, h)
            surface_SetDrawColor(PALETTE.EntryFocusGlow1)
            surface_DrawOutlinedRect(1, 1, w - 2, h - 2)
        else
            surface_SetDrawColor(PALETTE.EntryBorder)
            surface_DrawOutlinedRect(0, 0, w, h)
        end
    end

    if panel.GetPlaceholderText and panel.GetPlaceholderColor and panel:GetPlaceholderText()
        and panel:GetPlaceholderText():Trim() ~= "" and panel:GetText() == "" and not panel:IsEditing() then
        local oldText = panel:GetText()
        local str = panel:GetPlaceholderText()
        if str:StartWith("#") then str = str:sub(2) end
        str = language.GetPhrase(str)

        panel:SetText(str)
        panel:DrawTextEntryText(PALETTE.EntryPlaceholder, PALETTE.EntryHighlight, PALETTE.EntryCursor)
        panel:SetText(oldText)
        return
    end

    panel:DrawTextEntryText(
        panel:GetTextColor() or PALETTE.EntryText,
        panel:GetHighlightColor() or PALETTE.EntryHighlight,
        panel:GetCursorColor() or PALETTE.EntryCursor
    )
end

-- ============================================================================
-- 4. SCROLLBARS (DVScrollBar: soft Luna Blue grip & arrows)
-- ============================================================================
function SKIN:PaintVScrollBar(panel, w, h)
    surface_SetDrawColor(PALETTE.ScrollTrack)
    surface_DrawRect(0, 0, w, h)

    surface_SetDrawColor(PALETTE.ScrollTrackBorder)
    surface_DrawOutlinedRect(0, 0, w, h)
end

function SKIN:PaintScrollBarGrip(panel, w, h)
    local bg = PALETTE.ScrollGripBase
    if panel.Depressed then
        bg = PALETTE.ScrollGripDown
    elseif panel.Hovered then
        bg = PALETTE.ScrollGripHover
    end

    draw_RoundedBox(3, 1, 0, math_max(w - 2, 4), h, PALETTE.ScrollGripBorder)
    draw_RoundedBox(2, 2, 1, math_max(w - 4, 2), math_max(h - 2, 2), bg)

    surface_SetDrawColor(PALETTE.ScrollGripGlint)
    surface_DrawLine(2, 1, w - 3, 1)
    surface_DrawLine(2, 1, 2, h - 2)

    if h >= 18 and w >= 10 then
        local cy = math_floor(h * 0.5)
        local lx = 4
        local lw = w - 8
        for i = -1, 1 do
            local ly = cy + i * 3
            surface_SetDrawColor(PALETTE.ScrollGripLinesHi)
            surface_DrawLine(lx, ly, lx + lw, ly)
            surface_SetDrawColor(PALETTE.ScrollGripLines)
            surface_DrawLine(lx, ly + 1, lx + lw, ly + 1)
        end
    end
end

local function PaintScrollArrowButton(panel, w, h, dir)
    local bg = PALETTE.ScrollGripBase
    local offset = 0
    if panel.Depressed then
        bg = PALETTE.ScrollGripDown
        offset = 1
    elseif panel.Hovered then
        bg = PALETTE.ScrollGripHover
    end

    draw_RoundedBox(3, 1, 0, math_max(w - 2, 4), h, PALETTE.ScrollGripBorder)
    draw_RoundedBox(2, 2, 1, math_max(w - 4, 2), math_max(h - 2, 2), bg)

    if offset == 0 then
        surface_SetDrawColor(PALETTE.ScrollGripGlint)
        surface_DrawLine(2, 1, w - 3, 1)
        surface_DrawLine(2, 1, 2, h - 2)
    end

    DrawArrowGlyph(dir, math_floor(w * 0.5) + offset, math_floor(h * 0.5) + offset, PALETTE.ScrollArrowGlyph)
end

function SKIN:PaintButtonUp(panel, w, h)
    PaintScrollArrowButton(panel, w, h, "up")
end

function SKIN:PaintButtonDown(panel, w, h)
    PaintScrollArrowButton(panel, w, h, "down")
end

function SKIN:PaintButtonLeft(panel, w, h)
    PaintScrollArrowButton(panel, w, h, "left")
end

function SKIN:PaintButtonRight(panel, w, h)
    PaintScrollArrowButton(panel, w, h, "right")
end

-- ============================================================================
-- 5. PROPERTY SHEET & EXPLORER TABS (DPropertySheet & DTab)
-- ============================================================================
function SKIN:PaintPropertySheet(panel, w, h)
    local activeTab = panel.GetActiveTab and panel:GetActiveTab()
    local offset = IsValid(activeTab) and (activeTab:GetTall() - 8) or 0

    surface_SetDrawColor(PALETTE.SheetBG)
    surface_DrawRect(0, offset, w, h - offset)

    surface_SetDrawColor(PALETTE.SheetBorder)
    surface_DrawOutlinedRect(0, offset, w, h - offset)

    surface_SetDrawColor(PALETTE.White)
    surface_DrawLine(1, offset + 1, w - 2, offset + 1)
    surface_DrawLine(1, offset + 1, 1, h - 2)
end

function SKIN:PaintTab(panel, w, h)
    if panel:IsActive() then
        return self:PaintActiveTab(panel, w, h)
    end

    local tabH = math_max(h - 3, 14)
    local bg = panel.Hovered and PALETTE.TabHoverBG or PALETTE.TabInactiveBG

    draw_RoundedBoxEx(4, 0, 2, w - 1, tabH, PALETTE.SheetBorder, true, true, false, false)
    draw_RoundedBoxEx(3, 1, 3, w - 3, tabH - 1, bg, true, true, false, false)

    if panel.Hovered then
        surface_SetDrawColor(PALETTE.TabOrangeTop)
        surface_DrawRect(2, 2, w - 5, 2)
    else
        surface_SetDrawColor(PALETTE.White)
        surface_DrawLine(2, 3, w - 4, 3)
    end
end

function SKIN:PaintActiveTab(panel, w, h)
    local tabH = math_max(h - 5, 16)

    draw_RoundedBoxEx(4, 0, 0, w, tabH, PALETTE.SheetBorder, true, true, false, false)
    draw_RoundedBoxEx(3, 1, 1, w - 2, tabH, PALETTE.TabActiveBG, true, true, false, false)

    surface_SetDrawColor(PALETTE.TabOrangeTop)
    surface_DrawRect(2, 1, w - 4, 2)
    surface_SetDrawColor(PALETTE.TabOrangeSub)
    surface_DrawRect(1, 3, w - 2, 1)
end

-- ============================================================================
-- 6. CLASSIC WINDOWS XP DROPDOWN & CONTEXT MENU (DMenu, DMenuOption, Spacer)
-- ============================================================================
function SKIN:PaintMenu(panel, w, h)
    surface_SetDrawColor(PALETTE.DropShadow)
    surface_DrawRect(2, 2, w, h)

    surface_SetDrawColor(PALETTE.MenuBG)
    surface_DrawRect(0, 0, w, h)

    local gutterW = math_min(24, math_floor(w * 0.35))
    DrawHorizontalGradient(1, 1, gutterW, h - 2, GRADIENTS.MenuGutter)

    surface_SetDrawColor(PALETTE.MenuGutterLine)
    surface_DrawLine(gutterW + 1, 1, gutterW + 1, h - 2)
    surface_SetDrawColor(PALETTE.White)
    surface_DrawLine(gutterW + 2, 1, gutterW + 2, h - 2)

    surface_SetDrawColor(PALETTE.MenuBorder)
    surface_DrawOutlinedRect(0, 0, w, h)
end

function SKIN:PaintMenuSpacer(panel, w, h)
    local startX = (w > 36) and 26 or 4
    local y = math_floor(h * 0.5)

    surface_SetDrawColor(PALETTE.MenuDivider)
    surface_DrawLine(startX, y, w - 3, y)
    surface_SetDrawColor(PALETTE.MenuDividerHi)
    surface_DrawLine(startX, y + 1, w - 3, y + 1)
end

function SKIN:PaintMenuOption(panel, w, h)
    if panel.m_bBackground and (panel.Hovered or panel.Highlight) then
        surface_SetDrawColor(PALETTE.MenuHoverBG)
        surface_DrawRect(2, 1, w - 4, h - 2)
        surface_SetDrawColor(PALETTE.MenuHoverBorder)
        surface_DrawOutlinedRect(2, 1, w - 4, h - 2)

        if not panel._winxpHoverColorSet then
            panel._winxpHoverColorSet = true
            panel:SetTextColor(PALETTE.White)
        end
    else
        if panel._winxpHoverColorSet then
            panel._winxpHoverColorSet = false
            panel:SetTextColor(PALETTE.TextDark)
        end
    end

    if panel:GetChecked() then
        local cx, cy = 12, math_floor(h * 0.5)
        surface_SetDrawColor(PALETTE.EntryFocusBorder)
        surface_DrawOutlinedRect(4, cy - 7, 16, 14)

        surface_SetDrawColor(PALETTE.CheckGreen)
        surface_DrawLine(cx - 3, cy,     cx - 1, cy + 3)
        surface_DrawLine(cx - 3, cy + 1, cx - 1, cy + 4)
        surface_DrawLine(cx - 1, cy + 3, cx + 4, cy - 3)
        surface_DrawLine(cx - 1, cy + 4, cx + 4, cy - 2)
    end
end

function SKIN:PaintMenuRightArrow(panel, w, h)
    local parent = panel:GetParent()
    local col = (IsValid(parent) and parent.Hovered) and PALETTE.White or PALETTE.TextDark
    DrawArrowGlyph("right", math_floor(w * 0.5), math_floor(h * 0.5), col)
end

function SKIN:PaintMenuBar(panel, w, h)
    surface_SetDrawColor(PALETTE.WindowBody)
    surface_DrawRect(0, 0, w, h)

    surface_SetDrawColor(PALETTE.WindowBevelShadow)
    surface_DrawLine(0, h - 1, w, h - 1)
    surface_SetDrawColor(PALETTE.White)
    surface_DrawLine(0, 0, w, 0)
end

-- ============================================================================
-- 7. LIST VIEW, CLASSIC #ECE9D8 DOTTED TREE & EXPLORER TASK PANE (#215DC6)
-- ============================================================================
function SKIN:PaintListView(panel, w, h)
    if not panel.m_bBackground then return end

    surface_SetDrawColor(PALETTE.ListBG)
    surface_DrawRect(0, 0, w, h)

    surface_SetDrawColor(PALETTE.EntryBorder)
    surface_DrawOutlinedRect(0, 0, w, h)
end

function SKIN:PaintListViewLine(panel, w, h)
    if panel:IsSelected() then
        surface_SetDrawColor(PALETTE.ListRowSelected)
        surface_DrawRect(0, 0, w, h)
    elseif panel.Hovered then
        surface_SetDrawColor(PALETTE.ListRowHover)
        surface_DrawRect(0, 0, w, h)
    elseif panel.m_bAlt then
        surface_SetDrawColor(PALETTE.ListRowAlt)
        surface_DrawRect(0, 0, w, h)
    end
end

function SKIN:PaintTree(panel, w, h)
    surface_SetDrawColor(PALETTE.TreeBG)
    surface_DrawRect(0, 0, w, h)

    surface_SetDrawColor(PALETTE.TreeTaskPaneStripe)
    surface_DrawRect(1, 1, w - 2, 2)

    surface_SetDrawColor(PALETTE.WindowBevelShadow)
    surface_DrawOutlinedRect(0, 0, w, h)
    surface_SetDrawColor(PALETTE.WindowBevelDeep)
    surface_DrawLine(1, 1, w - 2, 1)
    surface_DrawLine(1, 1, 1, h - 2)
    surface_SetDrawColor(PALETTE.White)
    surface_DrawLine(1, h - 2, w - 2, h - 2)
    surface_DrawLine(w - 2, 1, w - 2, h - 2)
end

function SKIN:PaintTreeNode(panel, w, h)
    if panel.GetRoot and panel:GetParentNode() == panel:GetRoot() and h > 20 then
        surface_SetDrawColor(PALETTE.TreeRowDivider)
        surface_DrawLine(4, h - 1, w - 4, h - 1)
    end

    surface_SetDrawColor(PALETTE.TreeDotLine)
    local vEnd = panel.m_bLastChild and 9 or h

    for y = 0, vEnd - 1, 2 do
        surface_DrawRect(9, y, 1, 1)
    end

    for x = 9, 17, 2 do
        surface_DrawRect(x, 8, 1, 1)
    end
end

function SKIN:PaintTreeNodeButton(panel, w, h)
    if not panel.m_bSelected and not panel.Hovered then
        if panel._winxpSelTextSet then
            panel._winxpSelTextSet = false
            panel:SetTextColor(PALETTE.TextDark)
        end
        return
    end

    local textW, _ = panel:GetTextSize()
    local bx = 36
    local bw = textW + 8

    if panel.m_bSelected then
        surface_SetDrawColor(PALETTE.ListRowSelected)
        surface_DrawRect(bx, 1, bw, h - 2)
        surface_SetDrawColor(PALETTE.TabOrangeTop)
        surface_DrawOutlinedRect(bx, 1, bw, h - 2)
        if not panel._winxpSelTextSet then
            panel._winxpSelTextSet = true
            panel:SetTextColor(PALETTE.White)
        end
    elseif panel.Hovered then
        surface_SetDrawColor(PALETTE.ListRowHover)
        surface_DrawRect(bx, 1, bw, h - 2)
        surface_SetDrawColor(PALETTE.EntryBorder)
        surface_DrawOutlinedRect(bx, 1, bw, h - 2)
        if panel._winxpSelTextSet then
            panel._winxpSelTextSet = false
            panel:SetTextColor(PALETTE.TextDark)
        end
    end
end

function SKIN:PaintExpandButton(panel, w, h)
    local size = 9
    local bx = math_floor((w - size) * 0.5)
    local by = math_floor((h - size) * 0.5)

    surface_SetDrawColor(PALETTE.White)
    surface_DrawRect(bx, by, size, size)
    surface_SetDrawColor(PALETTE.WindowBevelDeep)
    surface_DrawOutlinedRect(bx, by, size, size)

    local cx = bx + 4
    local cy = by + 4
    surface_SetDrawColor(PALETTE.TextDark)
    surface_DrawLine(bx + 2, cy, bx + size - 3, cy)
    if not panel:GetExpanded() then
        surface_DrawLine(cx, by + 2, cx, by + size - 3)
    end
end

function SKIN:PaintCollapsibleCategory(panel, w, h)
    local headerH = (panel.GetHeaderHeight and panel:GetHeaderHeight()) or 20

    if panel.Header and not panel.Header._winxpHeaderStyled then
        panel.Header._winxpHeaderStyled = true
        panel.Header:SetFont(FONTS.Bold)
        panel.Header:SetTextInset(8, 0)
    end

    if IsValid(panel.Contents) and not panel.Contents._winxpContentsPadded then
        panel.Contents._winxpContentsPadded = true
        panel.Contents:DockPadding(8, 6, 8, 8)
    end

    if h > headerH then
        surface_SetDrawColor(PALETTE.CatBodyBG)
        surface_DrawRect(0, headerH, w, h - headerH)
        surface_SetDrawColor(PALETTE.CatBodyBorder)
        surface_DrawOutlinedRect(0, headerH, w, h - headerH)
    end

    local isExpanded = panel:GetExpanded()
    local grad = isExpanded and GRADIENTS.CategoryHeader or GRADIENTS.CategoryClosed

    draw_RoundedBoxEx(4, 0, 0, w, headerH, PALETTE.CatHeaderStart, true, true, not isExpanded, not isExpanded)
    DrawHorizontalGradient(1, 1, w - 2, headerH - 2, grad)

    surface_SetDrawColor(PALETTE.CatHeaderTopGlint)
    surface_DrawLine(2, 1, w - 3, 1)

    local cx = w - 13
    local cy = math_floor(headerH * 0.5)
    draw_RoundedBox(8, cx - 7, cy - 7, 15, 15, PALETTE.CatHeaderTopGlint)
    draw_RoundedBox(7, cx - 6, cy - 6, 13, 13, PALETTE.CatHeaderStart)
    DrawArrowGlyph(isExpanded and "up" or "down", cx, cy - 2, PALETTE.White)
    DrawArrowGlyph(isExpanded and "up" or "down", cx, cy + 2, PALETTE.White)
end

function SKIN:PaintCategoryList(panel, w, h)
    surface_SetDrawColor(PALETTE.WindowBody)
    surface_DrawRect(0, 0, w, h)
    surface_SetDrawColor(PALETTE.WindowBevelShadow)
    surface_DrawOutlinedRect(0, 0, w, h)
end

function SKIN:PaintCategoryButton(panel, w, h)
    if panel.Depressed or panel.m_bSelected then
        surface_SetDrawColor(PALETTE.CatLineGold)
        surface_DrawRect(1, 0, w - 2, h)
        surface_SetDrawColor(PALETTE.CatLineGoldBorder)
        surface_DrawOutlinedRect(1, 0, w - 2, h)
    elseif panel.Hovered then
        surface_SetDrawColor(PALETTE.CatLineHover)
        surface_DrawRect(1, 0, w - 2, h)
    elseif panel.AltLine then
        surface_SetDrawColor(SKIN.Colours.Category.LineAlt.Button)
        surface_DrawRect(1, 0, w - 2, h)
    else
        surface_SetDrawColor(SKIN.Colours.Category.Line.Button)
        surface_DrawRect(1, 0, w - 2, h)
    end
end

-- ============================================================================
-- 8. CHECKBOX, COMBOBOX, TOOLTIP, PROGRESS BAR
-- ============================================================================
function SKIN:PaintCheckBox(panel, w, h)
    surface_SetDrawColor(panel:IsEnabled() and PALETTE.White or PALETTE.EntryDisabledBG)
    surface_DrawRect(0, 0, w, h)

    surface_SetDrawColor(PALETTE.CheckBorder)
    surface_DrawOutlinedRect(0, 0, w, h)

    if panel.Hovered and panel:IsEnabled() then
        surface_SetDrawColor(PALETTE.CheckHoverGlow)
        surface_DrawOutlinedRect(1, 1, w - 2, h - 2)
    end

    if panel:GetChecked() then
        local cx = math_floor(w * 0.5)
        local cy = math_floor(h * 0.5)
        surface_SetDrawColor(PALETTE.CheckGreen)
        surface_DrawLine(cx - 4, cy,     cx - 1, cy + 3)
        surface_DrawLine(cx - 4, cy - 1, cx - 1, cy + 2)
        surface_DrawLine(cx - 1, cy + 3, cx + 4, cy - 3)
        surface_DrawLine(cx - 1, cy + 2, cx + 4, cy - 4)
    end
end

function SKIN:PaintComboBox(panel, w, h)
    if not panel:IsEnabled() then
        surface_SetDrawColor(PALETTE.EntryDisabledBG)
    else
        surface_SetDrawColor(PALETTE.EntryBG)
    end
    surface_DrawRect(0, 0, w, h)

    local borderCol = (panel.Hovered or panel.Depressed or panel:IsMenuOpen())
        and PALETTE.EntryFocusBorder or PALETTE.EntryBorder
    surface_SetDrawColor(borderCol)
    surface_DrawOutlinedRect(0, 0, w, h)
end

function SKIN:PaintComboDownArrow(panel, w, h)
    local parent = panel.ComboBox
    local isHovered = parent and (parent.Hovered or parent:IsMenuOpen())
    local isDown = parent and parent.Depressed

    local bg = isDown and PALETTE.ScrollGripDown
        or (isHovered and PALETTE.ScrollGripHover or PALETTE.ScrollGripBase)

    draw_RoundedBox(2, 1, 1, math_max(w - 2, 4), math_max(h - 2, 4), PALETTE.ScrollGripBorder)
    draw_RoundedBox(2, 2, 2, math_max(w - 4, 2), math_max(h - 4, 2), bg)

    DrawArrowGlyph("down", math_floor(w * 0.5), math_floor(h * 0.5), PALETTE.ScrollArrowGlyph)
end

function SKIN:PaintTooltip(panel, w, h)
    surface_SetDrawColor(PALETTE.DropShadow)
    surface_DrawRect(2, 2, w, h)

    surface_SetDrawColor(PALETTE.TooltipBG)
    surface_DrawRect(0, 0, w, h)

    surface_SetDrawColor(PALETTE.TooltipBorder)
    surface_DrawOutlinedRect(0, 0, w, h)
end

function SKIN:PaintProgress(panel, w, h)
    surface_SetDrawColor(PALETTE.ProgressBG)
    surface_DrawRect(0, 0, w, h)

    surface_SetDrawColor(PALETTE.WindowBevelDeep)
    surface_DrawOutlinedRect(0, 0, w, h)

    local frac = math_Clamp(panel:GetFraction() or 0, 0, 1)
    local fillW = math_floor((w - 6) * frac)
    if fillW > 0 then
        local chunkW = 8
        local gap = 2
        local x = 3
        local maxX = 3 + fillW
        while x < maxX do
            local cw = math_min(chunkW, maxX - x)
            surface_SetDrawColor(PALETTE.ProgressChunk)
            surface_DrawRect(x, 3, cw, h - 6)
            surface_SetDrawColor(PALETTE.ProgressChunkHi)
            surface_DrawRect(x, 3, cw, math_max(math_floor((h - 6) * 0.35), 2))
            x = x + chunkW + gap
        end
    end
end

-- ============================================================================
-- SPEDITOR CHROME (cl_ui_theme.lua, UI.PaintChrome): the editor's own windows
-- get a Luna title strip with XP tabs, the menu and status bars are XP bars
-- ============================================================================
local XP_TAB_OFF     = Color(255, 255, 255, 34)
local XP_TAB_HOT     = Color(255, 255, 255, 70)
local XP_TAB_TEXT    = Color(255, 255, 255, 255)
local XP_STATUS_DIM  = Color(70, 70, 64, 255)
local XP_MENU_HOT    = Color(49, 106, 197, 255)

SKIN.SPeditor = {
    TextColors = { MenuBar = PALETTE.TextDark, StatusBar = PALETTE.Black, StatusDim = XP_STATUS_DIM },
}

function SKIN.SPeditor.Window(skin, win, w, h, info)
    local e, th = info.edge, info.tabH
    local stripH = e + th
    local floating = not info.tiled

    -- frame: dark blue outline, Luna blue border, beige body
    if floating then
        draw_RoundedBoxEx(6, 0, 0, w, stripH + 2, PALETTE.FrameOuterBorder, true, true, false, false)
        surface_SetDrawColor(PALETTE.FrameOuterBorder)
        surface_DrawRect(0, stripH, w, h - stripH)
    else
        surface_SetDrawColor(PALETTE.FrameOuterBorder)
        surface_DrawRect(0, 0, w, h)
    end
    surface_SetDrawColor(PALETTE.FrameBorderBlue)
    surface_DrawRect(1, stripH, w - 2, h - stripH - 1)
    surface_SetDrawColor(PALETTE.WindowBody)
    surface_DrawRect(e - 1, stripH, w - (e - 1) * 2, h - stripH - e + 1)

    -- title strip: the Luna gradient
    DrawVerticalGradient(1, 1, w - 2, stripH - 1, GRADIENTS.TitleActive)
    surface_SetDrawColor(PALETTE.TitleTopBright)
    surface_DrawLine(floating and 4 or 1, 1, w - (floating and 5 or 2), 1)
    surface_SetDrawColor(PALETTE.TitleBottomLine)
    surface_DrawLine(1, stripH - 1, w - 2, stripH - 1)
    if info.onTop then
        surface_SetDrawColor(PALETTE.TabOrangeTop)
        surface_DrawRect(floating and 5 or 1, 2, w - (floating and 10 or 2), 1)
    end

    -- tabs: the active one is an XP property-sheet tab (beige, orange top edge)
    for _, t in ipairs(info.tabs) do
        local x, tw = t.x, t.w
        if t.on then
            draw_RoundedBoxEx(4, x, e, tw, th, PALETTE.SheetBorder, true, true, false, false)
            draw_RoundedBoxEx(3, x + 1, e + 1, tw - 2, th - 1, PALETTE.WindowBody, true, true, false, false)
            surface_SetDrawColor(PALETTE.TabOrangeTop)
            surface_DrawRect(x + 2, e + 1, tw - 4, 2)
            surface_SetDrawColor(PALETTE.TabOrangeSub)
            surface_DrawRect(x + 1, e + 3, tw - 2, 1)
            SPeditor.UI.DrawTabLabel(t, e + 2, th - 2, PALETTE.TextDark, 255)
        else
            draw_RoundedBoxEx(3, x, e + 2, tw, th - 3, t.hot and XP_TAB_HOT or XP_TAB_OFF, true, true, false, false)
            SPeditor.UI.DrawTabLabel(t, e + 2, th - 2, XP_TAB_TEXT, 220)
        end
    end
end

function SKIN.SPeditor.CloseButton(skin, b, w, h)
    skin:PaintWindowCloseButton(b, w, h)
end

function SKIN.SPeditor.MenuBar(skin, bar, w, h)
    surface_SetDrawColor(PALETTE.WindowBody)
    surface_DrawRect(0, 0, w, h)
    surface_SetDrawColor(PALETTE.White)
    surface_DrawLine(0, 0, w, 0)
    surface_SetDrawColor(PALETTE.WindowBevelShadow)
    surface_DrawLine(0, h - 1, w, h - 1)
end

-- a menu bar item: the XP blue highlight with white text
function SKIN.SPeditor.MenuButton(skin, b, w, h)
    local hot = b:IsHovered() or b._menuOpen
    if hot then
        surface_SetDrawColor(XP_MENU_HOT)
        surface_DrawRect(0, 2, w, h - 4)
    end
    if b._xpHot ~= hot then
        b._xpHot = hot
        b:SetTextColor(hot and PALETTE.White or PALETTE.TextDark)
    end
end

function SKIN.SPeditor.StatusBar(skin, bar, w, h)
    surface_SetDrawColor(PALETTE.WindowBody)
    surface_DrawRect(0, 0, w, h)
    surface_SetDrawColor(PALETTE.WindowBevelShadow)
    surface_DrawLine(0, 0, w, 0)
    surface_SetDrawColor(PALETTE.White)
    surface_DrawLine(0, 1, w, 1)
end

-- ============================================================================
-- REGISTER
-- ============================================================================
derma.DefineSkin(ARG.name or "SPeditor.gmodxp", "GMod XP", SKIN)
