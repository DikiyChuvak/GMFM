--[[
SPeditor — interface themes.

A theme = a Derma skin (menus, lists, trees, text fields, buttons) + a palette for
what the editor draws itself (windows, tabs, control rows).

  * GM:FM UI   — the default since b0.2: Source Filmmaker's Qt interface (skins/sfm.lua);
  * SPeditor UI (b0.1) — the editor's earlier flat look (skins/speditor.lua);
  * GMod          — a copy of the game's stock skin (skins/gmod.lua, own texture);
  * Dark UI (regular and transparent), Steam 2004, GMod 98, OneShot UI;
  * Lambda UI;
  * EcoUI         — a separate theme per colour variant (own textures);
  * custom themes — any Derma skins from the themes folder (cl_ui_userthemes.lua).

The skins live in lua/speditor/skins and are included when a theme is first chosen. They
are registered under the names "SPeditor.<id>" and are in effect only while the editor
is open: they do not affect the rest of the game interface.

The editor uses only its own skins. It neither touches nor takes the game's shared
"Default" skin: Workshop interfaces replace it (and the ForceDermaSkin hook), which
made editor windows draw mixed with a foreign theme. Therefore:
  * the "GMod" theme is our own copy of the stock skin;
  * whatever the theme skin lacks is taken from that copy (UI.BaseSkin), not from Default;
  * while the editor is open, the default skin for panels without a skin of their own
    (menus, tooltips, dialogs) is the theme skin, whatever foreign hooks return.

The palette is changed in place (the same Color objects in UI.PAL), so interface
files only need to take `local COL = UI.PAL` once.

API:
  UI.Themes / UI.ThemeById     list and lookup of themes
  UI.Theme                     the current theme
  UI.SetTheme(id)              choose a theme (saved in gmfm_theme)
  UI.IsNative()                buttons and lists are drawn by the theme skin, not by the editor
  UI.Skin(panel)               give a panel the theme skin
  UI.Menu()                    DermaMenu() with the theme skin
  UI.BuildThemeMenu(menu)      theme choice items
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI  = SPeditor.UI
local PAL = UI.PAL

local cvTheme = CreateClientConVar("gmfm_theme", "speditor", true, false)

---------------------------------------------------------------------
-- A palette from a few key colours of the theme
---------------------------------------------------------------------
local function mix(a, b, t)
	return Color(math.Round(a.r + (b.r - a.r) * t), math.Round(a.g + (b.g - a.g) * t), math.Round(a.b + (b.b - a.b) * t))
end

local function channel(v)
	v = v / 255
	return (v <= 0.03928) and (v / 12.92) or (((v + 0.055) / 1.055) ^ 2.4)
end

local function luminance(c)
	return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
end

local function contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

-- the accent is also used as a text colour: if it is unreadable on the background,
-- pull it towards the text colour
local function legible(c, bg, text, need)
	for _ = 1, 10 do
		if contrast(c, bg) >= need then break end
		c = mix(c, text, 0.2)
	end
	return c
end

local BLACK, WHITE = Color(0, 0, 0), Color(255, 255, 255)

-- b = { bg, text, accent, sel, ctrl, hover, menu }: only bg is required
local function derive(b)
	local bg = b.bg
	local dark = luminance(bg) < 0.3
	local text = b.text or (dark and Color(225, 225, 225) or Color(20, 20, 20))
	local accent = legible(b.accent or (dark and Color(233, 145, 45) or Color(170, 80, 0)), bg, text, 3)
	local ctrl = b.ctrl or (dark and mix(bg, WHITE, 0.13) or mix(bg, BLACK, 0.1))
	local rowA = dark and mix(bg, WHITE, 0.02) or mix(bg, WHITE, 0.25)
	local p = {
		BG       = bg,
		CHROME   = mix(bg, BLACK, 0.14),
		HEADER   = dark and mix(bg, WHITE, 0.07) or mix(bg, BLACK, 0.07),
		TAB_ON   = dark and mix(bg, WHITE, 0.2) or mix(bg, WHITE, 0.5),
		TAB_OFF  = dark and mix(bg, WHITE, 0.04) or mix(bg, BLACK, 0.1),
		CTRL     = ctrl,
		HOVER    = b.hover or mix(ctrl, text, 0.25),
		BORDER   = mix(bg, BLACK, 0.42),
		TEXT     = text,
		DIM      = mix(text, bg, 0.38),
		BLUE     = dark and Color(130, 170, 220) or Color(40, 90, 170),
		ORANGE   = accent,
		GREEN    = legible(dark and Color(125, 205, 100) or Color(20, 115, 30), bg, text, 3),
		RED      = legible(dark and Color(228, 100, 88) or Color(185, 45, 35), bg, text, 3),
		VIEW_BG  = Color(0, 0, 0),
		LIST_BG  = mix(bg, BLACK, 0.17),
		TREE_BG  = mix(bg, BLACK, 0.17),
		ROW_A    = rowA,
		ROW_B    = mix(bg, BLACK, 0.09),
		SEL      = b.sel and mix(bg, b.sel, 0.65) or mix(bg, text, 0.35),
		FILL     = mix(rowA, b.sel or text, 0.22),
		FILL_HOT = mix(rowA, b.sel or text, 0.4),
		TIMECODE = mix(text, bg, 0.14),
	}
	p.MENU = b.menu or p.HEADER
	return p
end

-- for themes from the themes folder (cl_ui_userthemes.lua)
UI.ThemeUtil = { mix = mix, luminance = luminance, contrast = contrast }

-- the editor's original palette (the "GM:FM UI" theme) — as set in cl_ui_theme.lua
UI.BasePAL = UI.BasePAL or table.Copy(PAL)

---------------------------------------------------------------------
-- Theme registry
---------------------------------------------------------------------
UI.Themes, UI.ThemeById = {}, {}

local function add(t)
	t.skin = t.skin or ("SPeditor." .. t.id)
	UI.Themes[#UI.Themes + 1] = t
	UI.ThemeById[t.id] = t
	return t
end
UI.AddTheme = add

local TEX = "speditor/skins/"

-- GM:FM UI (b0.2): Source Filmmaker's Qt interface — its colours (valve_base.qss, sfm.qss) and
-- its pictures (buttons, fields, tabs, check boxes) in Derma, skins/sfm.lua
add({ id = "speditor", name = "GM:FM UI", file = "sfm", native = true, propBG = Color(47, 47, 47), transportH = 36,
		pal = {
			BG = Color(54, 54, 54), CHROME = Color(38, 38, 39), HEADER = Color(62, 62, 63), MENU = Color(50, 50, 51),
			TAB_ON = Color(79, 79, 80), TAB_OFF = Color(44, 44, 44), CTRL = Color(70, 70, 71), HOVER = Color(92, 92, 94),
			BORDER = Color(24, 24, 25), TEXT = Color(196, 196, 196), DIM = Color(132, 132, 132),
			BLUE = Color(138, 149, 186), ORANGE = Color(233, 145, 45), GREEN = Color(67, 192, 60), RED = Color(214, 66, 79),
			VIEW_BG = Color(0, 0, 0), LIST_BG = Color(38, 38, 39), TREE_BG = Color(38, 38, 39),
			ROW_A = Color(47, 47, 47), ROW_B = Color(42, 42, 42), SEL = Color(79, 82, 89),
			FILL = Color(69, 76, 87), FILL_HOT = Color(93, 102, 125), TIMECODE = Color(200, 200, 200),
		} })

-- the editor's look up to b0.1 (it was called SPeditor UI, then GM:FM UI): flat grey, drawn by the editor
add({ id = "speditor_classic", name = "SPeditor UI (b0.1)", file = "speditor", skin = "SPeditor.speditor_classic", propBG = Color(61, 59, 60) })

add({ id = "gmod", name = "GMod", file = "gmod", tex = TEX .. "gmod.png", native = true,
		base = { bg = Color(108, 111, 114), text = Color(236, 236, 236), accent = Color(140, 190, 255), sel = Color(91, 140, 248),
			ctrl = Color(227, 227, 227), hover = Color(160, 164, 168) } })

-- Dark UI: two versions by the author — opaque and with a translucent background
local darkBase = { bg = Color(52, 54, 59), text = Color(230, 230, 230), accent = Color(111, 151, 250), sel = Color(111, 151, 250),
	ctrl = Color(82, 83, 85) }
add({ id = "darkui", name = "Dark UI", file = "darkui", tex = TEX .. "darkui.png", native = true,
		base = darkBase, propBG = Color(52, 54, 59) })
add({ id = "darkui_t", name = "Dark UI (Transparent)", file = "darkui", tex = TEX .. "darkui_t.png", native = true,
		base = darkBase, propBG = Color(52, 54, 59) })

add({ id = "steam2004", name = "Steam 2004", file = "steam2004", native = true,
		base = { bg = Color(76, 88, 68), text = Color(216, 222, 211), accent = Color(196, 181, 80), sel = Color(149, 136, 49),
			ctrl = Color(90, 106, 80) }, propBG = Color(62, 70, 55) })

add({ id = "gmod98", name = "GMod 98", file = "gmod98", native = true,
		base = { bg = Color(188, 191, 185), text = Color(10, 10, 10), accent = Color(20, 60, 160), sel = Color(55, 114, 223),
			ctrl = Color(188, 191, 185), hover = Color(120, 122, 118) } })

add({ id = "oneshot", name = "OneShot UI", file = "oneshot", native = true,
		base = { bg = Color(24, 12, 30), text = Color(255, 255, 255), accent = Color(255, 146, 30), sel = Color(97, 27, 52),
			ctrl = Color(48, 13, 26), hover = Color(97, 27, 52), menu = Color(38, 28, 42) }, propBG = Color(34, 20, 40) })

-- GMod XP: Windows XP Luna Blue; draws the editor windows and bars itself (SKIN.SPeditor)
add({ id = "gmodxp", name = "GMod XP", file = "gmodxp", native = true,
		base = { bg = Color(236, 233, 216), text = Color(0, 21, 66), accent = Color(0, 85, 234), sel = Color(49, 106, 197),
			ctrl = Color(244, 242, 232), hover = Color(193, 210, 238), menu = Color(236, 233, 216) }, propBG = Color(246, 245, 238) })

-- Vanilla UI+: translucent navy (or black) panels, a blue and a green accent, smooth hover
local vanillaBase = { bg = Color(16, 18, 27), text = Color(255, 255, 255), accent = Color(126, 200, 255), sel = Color(60, 200, 140),
	ctrl = Color(28, 31, 42), hover = Color(32, 74, 122), menu = Color(10, 12, 20) }
add({ id = "vanillaui", name = "Vanilla UI", group = "Vanilla UI", file = "vanillaui", native = true,
		base = vanillaBase, propBG = Color(13, 15, 23) })
add({ id = "vanillaui_black", name = "Vanilla UI (Black)", group = "Vanilla UI", file = "vanillaui", variant = "black", native = true,
		base = { bg = Color(8, 8, 8), text = vanillaBase.text, accent = vanillaBase.accent, sel = vanillaBase.sel,
			ctrl = Color(24, 24, 24), hover = Color(30, 64, 104), menu = Color(4, 4, 4) }, propBG = Color(10, 10, 10) })

add({ id = "lambdaui", name = "Lambda UI", file = "lambdaui", native = true,
		base = { bg = Color(64, 67, 68), text = Color(255, 255, 255), accent = Color(253, 118, 0), sel = Color(253, 118, 0),
			ctrl = Color(86, 81, 77), hover = Color(253, 118, 0) }, propBG = Color(52, 54, 59) })

-- a0.9: three more themes from the themes folder.
-- HL2 Media Player (author: 晦涩弗里曼): the skin of Lambda UI with its own glossy grey and orange
-- texture (the colours are taken from it)
add({ id = "hl2mp", name = "HL2 Media Player", file = "lambdaui", tex = TEX .. "hl2mp.png", native = true,
		base = { bg = Color(99, 99, 100), text = Color(255, 255, 255), accent = Color(236, 132, 39), sel = Color(236, 132, 39),
			ctrl = Color(113, 113, 113), hover = Color(255, 181, 53), menu = Color(88, 88, 90) }, propBG = Color(80, 80, 82) })
-- GMod Classic: the stock skin with the grey texture of the older GMod
add({ id = "gmodclassic", name = "GMod Classic", file = "gmod", tex = TEX .. "gmodclassic.png", native = true,
		base = { bg = Color(96, 96, 94), text = Color(240, 240, 240), accent = Color(120, 170, 255), sel = Color(100, 150, 250),
			ctrl = Color(130, 130, 128), hover = Color(150, 150, 148) }, propBG = Color(80, 80, 78) })
-- Aero Blur: dark glass — the windows are see-through and blur what is under them (skins/gmod.lua, variant "aero")
add({ id = "aeroblur", name = "Aero Blur", file = "gmod", tex = TEX .. "aeroblur.png", variant = "aero", native = true, glass = 205,
		base = { bg = Color(28, 30, 36), text = Color(236, 238, 242), accent = Color(90, 170, 255), sel = Color(60, 130, 220),
			ctrl = Color(52, 56, 64), hover = Color(66, 92, 130), menu = Color(22, 24, 30) }, propBG = Color(30, 32, 38) })

-- EcoUI: the original has one skin and a texture choice in a separate window. Here every
-- texture is a theme of its own with its own colours. { texture file, name, key colours }
local ECO_PROP = Color(52, 54, 59)
local function eco(file, name, base)
	add({ id = "ecoui_" .. file, name = name, group = "EcoUI", file = "ecoui", tex = TEX .. "ecoui/" .. file .. ".png",
			native = true, base = base, propBG = ECO_PROP })
end

eco("adef_ecoui", "EcoUI",
	{ bg = Color(125, 129, 94), text = WHITE, accent = Color(200, 255, 0), sel = Color(89, 155, 0), ctrl = Color(115, 164, 0) })
eco("ecoui_remaster", "EcoUI Remaster",
	{ bg = Color(203, 229, 126), text = Color(10, 10, 10), accent = Color(50, 110, 0), sel = Color(132, 221, 0), ctrl = Color(131, 221, 0) })
eco("er_ice", "EcoUI Remaster — Ice",
	{ bg = Color(180, 220, 237), text = Color(10, 10, 10), accent = Color(20, 90, 160), sel = Color(124, 191, 226), ctrl = Color(125, 191, 226) })
eco("er_dark", "EcoUI Remaster — Dark",
	{ bg = Color(78, 78, 78), text = Color(236, 240, 225), accent = Color(180, 210, 120), sel = Color(113, 134, 72), ctrl = Color(132, 132, 132) })
eco("er_dark_blue", "EcoUI Remaster — Dark Blue",
	{ bg = Color(78, 78, 78), text = Color(228, 240, 245), accent = Color(150, 190, 235), sel = Color(102, 128, 160), ctrl = Color(132, 132, 132) })
eco("er_dragon", "EcoUI Remaster — Dragon",
	{ bg = Color(51, 33, 33), text = Color(255, 236, 236), accent = Color(255, 90, 90), sel = Color(189, 15, 15), ctrl = Color(150, 12, 12) })
eco("dasea", "Dasea",
	{ bg = Color(106, 129, 150), text = WHITE, accent = Color(100, 243, 255), sel = Color(78, 133, 255), ctrl = Color(71, 150, 255) })
eco("amber", "Amber",
	{ bg = Color(149, 121, 104), text = WHITE, accent = Color(255, 195, 61), sel = Color(203, 120, 15), ctrl = Color(233, 126, 30) })
eco("clover", "Clover",
	{ bg = Color(107, 125, 91), text = WHITE, accent = Color(185, 255, 39), sel = Color(42, 165, 24), ctrl = Color(68, 184, 22) })
eco("roranged", "Roranged",
	{ bg = Color(154, 119, 112), text = WHITE, accent = Color(255, 200, 185), sel = Color(226, 111, 35), ctrl = Color(234, 115, 61) })
eco("sakura", "Sakura",
	{ bg = Color(157, 117, 123), text = WHITE, accent = Color(255, 200, 212), sel = Color(255, 98, 78), ctrl = Color(255, 104, 103) })
eco("sevensquared", "Seven Squared",
	{ bg = Color(127, 123, 158), text = WHITE, accent = Color(250, 195, 255), sel = Color(171, 105, 255), ctrl = Color(169, 120, 255) })
eco("ly_hydenpro", "HydenPro",
	{ bg = Color(104, 123, 155), text = WHITE, accent = Color(183, 214, 107), sel = Color(0, 139, 0), ctrl = Color(89, 163, 0) })
eco("ly_orange", "Ly Orange",
	{ bg = Color(122, 122, 122), text = WHITE, accent = Color(255, 184, 140), sel = Color(165, 85, 0), ctrl = Color(255, 107, 16) })
eco("ly_bluhydes", "Ly BlueHydes",
	{ bg = Color(88, 127, 166), text = WHITE, accent = Color(123, 217, 255), sel = Color(7, 99, 253), ctrl = Color(2, 161, 243) })
eco("ly_ecoui", "Ly EcoUI",
	{ bg = Color(87, 136, 77), text = WHITE, accent = Color(169, 218, 110), sel = Color(0, 143, 0), ctrl = Color(66, 169, 0) })

---------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------
local function writePalette(src)
	for key, c in pairs(src) do
		local dst = PAL[key]
		if dst then
			dst.r, dst.g, dst.b, dst.a = c.r, c.g, c.b, c.a or 255
		else
			PAL[key] = Color(c.r, c.g, c.b, c.a or 255)
		end
	end
end

-- A copy of the stock GMod skin: the "GMod" theme and the base of all other themes.
-- The skin table is complete, so the link to the shared Default (set by
-- derma.DefineSkin) is removed.
local BASE_SKIN = "SPeditor.gmod"

function UI.BaseSkin()
	local skin = derma.GetNamedSkin(BASE_SKIN)
	if skin then return skin end
	local saved = SPeditor.SkinArg
	SPeditor.SkinArg = { name = BASE_SKIN, tex = TEX .. "gmod.png" }
	local ok, err = pcall(include, "speditor/skins/gmod.lua")
	SPeditor.SkinArg = saved
	if not ok then MsgC(Color(255, 120, 80), "[GM:FM] base skin: ", tostring(err), "\n") end
	skin = derma.GetNamedSkin(BASE_SKIN)
	if skin then setmetatable(skin, nil) end
	return skin or derma.GetNamedSkin("Default")
end

local function isColor(c)
	return istable(c) and isnumber(c.r) and isnumber(c.g) and isnumber(c.b)
end

-- Colour groups of a skin (Colours.Properties, Colours.Tab.Active…) that are missing or
-- broken are filled from the base skin: stock panels read them without checks
-- (DProperties rows: "bad argument #3 to 'SetDrawColor'").
local function fillColours(dst, src)
	for k, v in pairs(src) do
		local cur = rawget(dst, k)
		if isColor(v) then
			if not isColor(cur) then
				dst[k] = Color(v.r, v.g, v.b, v.a or 255)
			elseif not isnumber(cur.a) then
				cur.a = 255
			end
		elseif istable(v) then
			if not istable(cur) or isColor(cur) then
				cur = {}
				dst[k] = cur
			end
			fillColours(cur, v)
		end
	end
end

-- Whatever the theme skin lacks is taken from our copy, not from the shared Default
local function rebase(name)
	local skin, base = derma.GetNamedSkin(name), UI.BaseSkin()
	if not (skin and base and skin ~= base) then return end
	setmetatable(skin, { __index = base })
	if istable(base.Colours) then
		local own = rawget(skin, "Colours")
		if not istable(own) then
			own = {}
			rawset(skin, "Colours", own)
		end
		pcall(fillColours, own, base.Colours)
	end
end

-- Include the theme skin if it is not registered yet. false — failed.
local function loadSkin(t)
	UI.BaseSkin()
	if derma.GetNamedSkin(t.skin) then
		rebase(t.skin)
		return true
	end
	if t.user then
		local ok = UI.LoadUserSkin ~= nil and UI.LoadUserSkin(t)
		if ok then rebase(t.skin) end
		return ok
	end
	if not t.file then return false end
	SPeditor.SkinArg = { name = t.skin, tex = t.tex, variant = t.variant }
	local ok, err = pcall(include, "speditor/skins/" .. t.file .. ".lua")
	SPeditor.SkinArg = nil
	if not ok then
		MsgC(Color(255, 120, 80), "[GM:FM] theme '", t.id, "': ", tostring(err), "\n")
		return false
	end
	rebase(t.skin)
	return derma.GetNamedSkin(t.skin) ~= nil
end

local function resolve(id)
	return UI.ThemeById[id] or UI.ThemeById.speditor
end

-- Set the palette and the skin. The skin is included only when Derma is ready
-- (when the editor opens and on a theme change), the palette — at once.
-- The accent chosen in Interface settings (gmfm_ui_accent "r g b"), or nil — the theme's own
function UI.AccentOverride()
	local r, g, b = string.match(GetConVarString("gmfm_ui_accent") or "", "^%s*(%d+)[%s,]+(%d+)[%s,]+(%d+)")
	if not r then return nil end
	return Color(math.Clamp(tonumber(r), 0, 255), math.Clamp(tonumber(g), 0, 255), math.Clamp(tonumber(b), 0, 255))
end

function UI.ApplyTheme(id, withSkin)
	local t = resolve(id)
	if withSkin and not loadSkin(t) and t.id ~= "speditor_classic" then
		t = UI.ThemeById.speditor_classic
		loadSkin(t)
	end
	UI.Theme = t
	-- a theme may give its whole palette (GM:FM UI: the colours of SFM's style sheets)
	writePalette(t.pal or (t.base and derive(t.base)) or UI.BasePAL)
	-- a glass theme: the backgrounds are see-through (the window chrome blurs what is under them)
	if t.glass then
		for _, key in ipairs({ "BG", "CHROME", "HEADER", "LIST_BG", "TREE_BG", "ROW_A", "ROW_B", "TAB_OFF", "MENU" }) do
			if PAL[key] then PAL[key].a = t.glass end
		end
	end
	local acc = UI.AccentOverride()
	if acc then
		local c = legible(acc, PAL.BG, PAL.TEXT, 3)
		PAL.ORANGE.r, PAL.ORANGE.g, PAL.ORANGE.b = c.r, c.g, c.b
	end
	if withSkin then
		UI.SkinName = derma.GetNamedSkin(t.skin) and t.skin or nil
		-- a skin with settings of its own (accent, animations) re-reads them
		local skin = UI.SkinName and derma.GetNamedSkin(UI.SkinName)
		local refresh = skin and rawget(skin, "SPeditorRefresh")
		if refresh then pcall(refresh, skin) end
		derma.RefreshSkins()
	end
	return t
end

function UI.IsNative()
	return UI.Theme ~= nil and UI.Theme.native == true
end

function UI.Skin(panel)
	if UI.SkinName and IsValid(panel) then panel:SetSkin(UI.SkinName) end
	return panel
end

function UI.Menu()
	local m = UI.Skin(DermaMenu())
	local open = m.Open
	m.Open = function(self, ...)
		open(self, ...)
		UI.FadeIn(self, 0.1)
	end
	return m
end

function UI.SetTheme(id)
	RunConsoleCommand("gmfm_theme", resolve(id).id)
end

-- Theme choice items: single themes as a list, families (EcoUI, packs from the
-- themes folder) as submenus; at the end — rescan the themes folder.
function UI.BuildThemeMenu(m)
	local L = SPeditor.L
	local cur = UI.Theme and UI.Theme.id
	local groups = {}
	local userMark = false
	for _, t in ipairs(UI.Themes) do
		if t.user and not userMark then
			userMark = true
			m:AddSpacer()
		end
		local target = m
		if t.group then
			if not groups[t.group] then groups[t.group] = m:AddSubMenu(t.group) end
			target = groups[t.group]
		end
		target:AddOption(t.name, function() UI.SetTheme(t.id) end):SetChecked(t.id == cur)
	end
	if not UI.ScanUserThemes then return end
	m:AddSpacer()
	-- folders a theme could not be taken from (no skin, or names not in lower case)
	for _, issue in ipairs(UI.ThemeIssues or {}) do
		local o = m:AddOption(issue.name .. ": " .. L(issue.reason))
		o:SetIcon("icon16/error.png")
		if o.SetEnabled then o:SetEnabled(false) end
	end
	m:AddOption(L("theme_rescan"), function()
		local n = UI.ScanUserThemes()
		SPeditor.Notify(string.format(L("theme_rescan_done"), n), 0)
	end):SetIcon("icon16/arrow_refresh.png")
end

UI.ApplyTheme(cvTheme:GetString(), false)

cvars.AddChangeCallback("gmfm_theme", function(_, _, new)
	local C = SPeditor.Client
	local active = C and C.active
	UI.ApplyTheme(new, active)
	-- the interface is rebuilt: widgets remember colours and the skin when created.
	-- UI.Rebuild keeps the editor state (fullbright, open windows).
	if active and UI.Open then
		timer.Simple(0, function()
			if C.active then (UI.Rebuild or UI.Open)() end
		end)
	end
end, "SPeditor.Theme")

-- Dialogs, tooltips and other parentless panels take the default skin:
-- while the editor is open, that is the theme skin.
SPeditor.Hook("ForceDermaSkin", "SPeditor.Theme", function()
	local C = SPeditor.Client
	if C and C.active and UI.SkinName then return UI.SkinName end
end)

-- Hooks are called in arbitrary order: a Workshop interface with its own
-- ForceDermaSkin could have answered first. So the default skin is also replaced
-- in derma itself — only while the editor is open.
UI.OrigDefaultSkin = UI.OrigDefaultSkin or derma.GetDefaultSkin
function derma.GetDefaultSkin()
	local C = SPeditor.Client
	if C and C.active and UI.SkinName then
		local skin = derma.GetNamedSkin(UI.SkinName)
		if skin then return skin end
	end
	return UI.OrigDefaultSkin()
end

SPeditor.Hook("SPeditor_StateChanged", "SPeditor.ThemeSkin", function(on)
	if not on then derma.RefreshSkins() end
end)
