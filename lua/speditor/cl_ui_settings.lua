--[[
SPeditor — the "Interface settings" window (View → Interface settings…).

Two pages:
  * Appearance    — theme, accent colour, font and its size, window corners, how the active
                    tab is marked, animations, interface sounds;
  * Notifications — style, animation, place, width, number of cards, opacity,
                    the time line, sounds, display time (cl_ui_notify.lua).

Everything is kept in console variables (speditor_ui_*, speditor_notify_*), so it
stays between sessions. Corners, tab mark, accent and all notification settings take
effect at once; a new font rebuilds the interface (widgets measure text when created).

API:
  UI.OpenSettings(page)   open the window ("look" or "notify")
  UI.ResetUISettings()    all these settings back to their defaults
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI  = SPeditor.UI
local L   = SPeditor.L
local COL = UI.PAL

local DEFAULTS = {
	speditor_ui_font = "Tahoma", speditor_ui_fontsize = "13", speditor_ui_accent = "", speditor_ui_corners = "0",
	speditor_ui_tabstyle = "top", speditor_ui_anim = "1", speditor_ui_sounds = "1",
	speditor_notify = "1", speditor_notify_sound = "1", speditor_notify_time = "4", speditor_notify_style = "auto",
	speditor_notify_anim = "auto", speditor_notify_pos = "br", speditor_notify_width = "380", speditor_notify_max = "6",
	speditor_notify_opacity = "100", speditor_notify_bar = "0", speditor_notify_soundset = "speditor",
}

local ACCENTS = {
	Color(233, 145, 45), Color(230, 75, 75), Color(236, 98, 160), Color(170, 110, 240), Color(35, 135, 237),
	Color(40, 190, 220), Color(60, 200, 140), Color(125, 205, 60), Color(240, 200, 40), Color(200, 200, 200),
}

local CORNERS  = { 0, 3, 6, 10 }
local TABSTYLE = { "top", "bottom", "fill", "none" }

---------------------------------------------------------------------
-- Applying
---------------------------------------------------------------------
local function rebuildSoon()
	timer.Create("SPeditor.UISettingsRebuild", 0.05, 1, function()
		local C = SPeditor.Client
		if C and C.active and UI.Rebuild then UI.Rebuild() end
	end)
end

-- the font: new fonts, then the interface is built anew
for _, cv in ipairs({ "speditor_ui_font", "speditor_ui_fontsize" }) do
	cvars.AddChangeCallback(cv, function()
		UI.CreateFonts()
		rebuildSoon()
	end, "SPeditor.UISettings")
end

-- the accent: the palette colour is changed in place, the theme skin re-reads it
cvars.AddChangeCallback("speditor_ui_accent", function()
	local C = SPeditor.Client
	UI.ApplyTheme(GetConVarString("speditor_theme"), C and C.active)
end, "SPeditor.UISettings")

function UI.ResetUISettings()
	for cv, v in pairs(DEFAULTS) do
		if GetConVarString(cv) ~= v then RunConsoleCommand(cv, v) end
	end
end

---------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------
local function heading(parent, text)
	local l = vgui.Create("DLabel", parent)
	l:Dock(TOP)
	l:DockMargin(10, 10, 10, 2)
	l:SetFont("SPeditor.Bold")
	l:SetTextColor(COL.ORANGE)
	l:SetText(text)
	l:SizeToContents()
	return l
end

-- a row: the caption on the left, the control on the right
local function row(parent, text, h)
	local r = vgui.Create("DPanel", parent)
	r:Dock(TOP)
	r:DockMargin(10, 2, 10, 2)
	r:SetTall(h or 24)
	r.Paint = function() end
	local l = vgui.Create("DLabel", r)
	l:Dock(LEFT)
	l:SetWide(190)
	l:SetFont("SPeditor.Small")
	l:SetTextColor(COL.TEXT)
	l:SetText(text)
	return r
end

-- a drop-down list over a console variable: items = { { id, title } }
local function combo(parent, text, cv, items, onPick)
	local r = row(parent, text)
	local c = vgui.Create("DComboBox", r)
	c:Dock(FILL)
	c:SetSortItems(false)
	UI.StyleCombo(c)
	-- the list can be filled anew (after a rescan); items may be a function
	c.Refill = function(list)
		c:Clear()
		local cur = cv and GetConVarString(cv)
		for _, it in ipairs(isfunction(list) and list() or list) do
			c:AddChoice(it[2], it[1], cur ~= nil and tostring(it[1]) == cur)
		end
	end
	c.Refill(items)
	c.OnSelect = function(_, _, _, id)
		if cv then RunConsoleCommand(cv, tostring(id)) end
		if onPick then onPick(id) end
	end
	return c
end

local function check(parent, text, cv, onPick)
	local c = UI.Check(parent, text, GetConVar(cv):GetBool(), function(v)
		RunConsoleCommand(cv, v and "1" or "0")
		if onPick then onPick(v) end
	end)
	c:DockMargin(12, 4, 10, 4)
	return c
end

local function slider(parent, text, cv, min, max, onPick)
	local s = UI.Slider(parent, text, min, max, 0, GetConVar(cv):GetFloat(), nil)
	s:DockMargin(10, 2, 10, 2)
	-- the value is written when the mouse is let go, not on every step of the drag
	s.OnValueChanged = function(_, v)
		timer.Create("SPeditor.UISlider." .. cv, 0.2, 1, function()
			local n = tostring(math.Round(v))
			if GetConVarString(cv) ~= n then
				RunConsoleCommand(cv, n)
				if onPick then onPick() end
			end
		end)
	end
	return s
end

local function button(parent, text, icon, fn)
	local b = vgui.Create("DButton", parent)
	b:Dock(LEFT)
	b:DockMargin(0, 0, 6, 0)
	surface.SetFont("SPeditor.Small")
	b:SetWide(select(1, surface.GetTextSize(text)) + (icon and 40 or 24))
	b:SetText((icon and "  " or "") .. text)
	if icon then b:SetIcon(icon) end
	UI.StyleButton(b, nil, 3)
	b.DoClick = fn
	return b
end

---------------------------------------------------------------------
-- Appearance
---------------------------------------------------------------------
local function buildLook(page)
	heading(page, L("uis_theme"))
	-- themes of a family are shown as "Family: name"
	local items = {}
	for _, t in ipairs(UI.Themes) do
		local name = t.name
		if t.group and not string.StartWith(name, t.group) then name = t.group .. ": " .. name end
		items[#items + 1] = { t.id, name }
	end
	combo(page, L("menu_theme"), "speditor_theme", items)

	local tools = vgui.Create("DPanel", page)
	tools:Dock(TOP)
	tools:DockMargin(200, 2, 10, 4)
	tools:SetTall(24)
	tools.Paint = function() end
	button(tools, L("theme_rescan"), "icon16/arrow_refresh.png", function()
		local n = UI.ScanUserThemes and UI.ScanUserThemes() or 0
		SPeditor.Notify(string.format(L("theme_rescan_done"), n), 0)
	end)

	-- accent: the theme's own or one of the swatches, or any colour from the mixer
	heading(page, L("uis_accent"))
	local sw = row(page, L("uis_accent_pick"), 26)
	local mixer
	local function swatch(col, tip, onClick, isOn)
		local b = vgui.Create("DButton", sw)
		b:Dock(LEFT)
		b:DockMargin(0, 1, 4, 1)
		b:SetWide(24)
		b:SetText("")
		b:SetTooltip(tip)
		b.Paint = function(s, w, h)
			local on = isOn()
			draw.RoundedBox(4, 0, 0, w, h, on and COL.TEXT or (s:IsHovered() and COL.DIM or COL.BORDER))
			if col then
				draw.RoundedBox(3, 2, 2, w - 4, h - 4, col)
			else
				-- "theme": the half of the palette accent and the half of the background
				draw.RoundedBox(3, 2, 2, w - 4, h - 4, COL.BG)
				draw.SimpleText("T", "SPeditor.Bold", w / 2, h / 2, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end
		b.DoClick = onClick
		return b
	end
	swatch(nil, L("uis_accent_theme"), function() RunConsoleCommand("speditor_ui_accent", "") end,
		function() return GetConVarString("speditor_ui_accent") == "" end)
	for _, col in ipairs(ACCENTS) do
		local val = string.format("%d %d %d", col.r, col.g, col.b)
		swatch(col, val, function() RunConsoleCommand("speditor_ui_accent", val) end,
			function() return GetConVarString("speditor_ui_accent") == val end)
	end
	local more = swatch(nil, L("uis_accent_custom"), function()
		if IsValid(mixer) then mixer:SetVisible(not mixer:IsVisible()) mixer:GetParent():InvalidateLayout() end
	end, function() return IsValid(mixer) and mixer:IsVisible() end)
	more.Paint = function(s, w, h)
		draw.RoundedBox(4, 0, 0, w, h, (IsValid(mixer) and mixer:IsVisible()) and COL.TEXT or (s:IsHovered() and COL.DIM or COL.BORDER))
		draw.RoundedBox(3, 2, 2, w - 4, h - 4, COL.CTRL)
		draw.SimpleText("…", "SPeditor.Bold", w / 2, h / 2 - 2, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	mixer = vgui.Create("DColorMixer", page)
	mixer:Dock(TOP)
	mixer:DockMargin(200, 4, 10, 4)
	mixer:SetTall(150)
	mixer:SetPalette(false)
	mixer:SetAlphaBar(false)
	mixer:SetWangs(true)
	local acc = UI.AccentOverride and UI.AccentOverride()
	mixer:SetColor(acc or COL.ORANGE)
	mixer:SetVisible(false)
	mixer.ValueChanged = function(_, c)
		timer.Create("SPeditor.UIAccent", 0.15, 1, function()
			RunConsoleCommand("speditor_ui_accent", string.format("%d %d %d", c.r, c.g, c.b))
		end)
	end

	heading(page, L("uis_text"))
	local faces = {}
	for _, f in ipairs(UI.FONT_FACES) do faces[#faces + 1] = { f, f } end
	combo(page, L("uis_font"), "speditor_ui_font", faces)
	local sizes = {}
	for s = 11, 16 do sizes[#sizes + 1] = { s, s .. " px" } end
	combo(page, L("uis_font_size"), "speditor_ui_fontsize", sizes)
	UI.Label(page, L("uis_font_note")):DockMargin(200, 0, 10, 2)

	heading(page, L("uis_windows"))
	local corners = {}
	for _, r in ipairs(CORNERS) do corners[#corners + 1] = { r, L("corners_" .. r) } end
	combo(page, L("uis_corners"), "speditor_ui_corners", corners)
	local tabs = {}
	for _, s in ipairs(TABSTYLE) do tabs[#tabs + 1] = { s, L("tabs_" .. s) } end
	combo(page, L("uis_tabs"), "speditor_ui_tabstyle", tabs)
	check(page, L("uis_anim"), "speditor_ui_anim")
	check(page, L("uis_sounds"), "speditor_ui_sounds")
end

---------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------
-- a colour button: a swatch; a click opens a colour mixer in a menu
local function colorButton(parent, getC, setC, alpha)
	local b = vgui.Create("DButton", parent)
	b:Dock(LEFT)
	b:DockMargin(0, 1, 8, 1)
	b:SetWide(46)
	b:SetText("")
	b.Paint = function(s, w, h)
		draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and COL.TEXT or COL.BORDER)
		-- a checker under translucent colours
		for i = 0, 3 do
			surface.SetDrawColor((i % 2 == 0) and Color(200, 200, 200) or Color(120, 120, 120))
			surface.DrawRect(2 + i * (w - 4) / 4, 2, (w - 4) / 4, h - 4)
		end
		local c = getC()
		draw.RoundedBox(3, 2, 2, w - 4, h - 4, c)
	end
	b.DoClick = function()
		local m = UI.Menu()
		local mixer = vgui.Create("DColorMixer")
		mixer:SetSize(260, 190)
		mixer:SetPalette(false)
		mixer:SetAlphaBar(alpha and true or false)
		mixer:SetWangs(true)
		mixer:SetColor(getC())
		mixer.ValueChanged = function(_, c) setC(Color(c.r, c.g, c.b, alpha and c.a or 255)) end
		m:AddPanel(mixer)
		m:Open()
	end
	return b
end

local KIND_IDS = { 0, 2, 1, 3 }

local function buildNotify(page)
	local L2 = function(prefix) return function(id) return L(prefix .. id) end end
	local function list(ids, name)
		local out = {}
		for _, id in ipairs(ids) do out[#out + 1] = { id, name(id) } end
		return out
	end

	-----------------------------------------------------------------
	-- Preview: a small "screen" where a sample card plays its animation over and over
	-----------------------------------------------------------------
	heading(page, L("uis_preview"))
	local state = { kind = 0, style = nil }
	local box = vgui.Create("DPanel", page)
	box:Dock(TOP)
	box:DockMargin(10, 2, 10, 4)
	box:SetTall(170)
	box.Paint = function(_, w, h)
		draw.RoundedBox(4, 0, 0, w, h, COL.BORDER)
		surface.SetDrawColor(COL.VIEW_BG)
		surface.DrawRect(1, 1, w - 2, h - 2)
		-- the editor in miniature: menu bar, windows, status bar
		surface.SetDrawColor(COL.MENU)
		surface.DrawRect(1, 1, w - 2, 10)
		surface.SetDrawColor(COL.CHROME)
		surface.DrawRect(1, 12, math.floor(w * 0.2), h - 22)
		surface.DrawRect(math.floor(w * 0.2) + 3, 12, w - math.floor(w * 0.2) - 4, h - 22)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(1, h - 9, w - 2, 8)
	end
	local sample
	local function restart()
		if not IsValid(box) or box:GetWide() < 100 then return end
		if sample and IsValid(sample.card) then sample.card:Remove() end
		sample = UI.NotifySample(box, L("notify_kind_" .. state.kind) .. ": " .. L("notify_test_text"), state.kind,
			{ style = state.style })
	end
	box.PerformLayout = function(s, w)
		if s._w ~= w then
			s._w = w
			restart()
		end
	end
	local function restartSoon()
		timer.Create("SPeditor.NotifyPreview", 0.12, 1, function() if IsValid(box) then restart() end end)
	end
	for _, cv in ipairs({ "speditor_notify_style", "speditor_notify_anim", "speditor_notify_pos", "speditor_notify_width",
			"speditor_notify_bar", "speditor_notify_opacity", "speditor_ui_accent" }) do
		cvars.AddChangeCallback(cv, function() if IsValid(box) then restartSoon() end end, "SPeditor.NotifyPreview")
	end

	local kinds = vgui.Create("DPanel", page)
	kinds:Dock(TOP)
	kinds:DockMargin(10, 0, 10, 4)
	kinds:SetTall(24)
	kinds.Paint = function() end
	for _, k in ipairs(KIND_IDS) do
		local b = button(kinds, L("notify_kind_" .. k), ({ [0] = "icon16/information.png", "icon16/exclamation.png",
			"icon16/accept.png", "icon16/disk.png" })[k], function()
			state.kind = k
			restart()
			if GetConVar("speditor_notify_sound"):GetBool() then UI.PlayNotifyPath(UI.NotifySoundPath(k)) end
		end)
		local paint = b.Paint
		b.Paint = function(s, w, h)
			if paint then paint(s, w, h) end
			if state.kind == k then
				surface.SetDrawColor(COL.ORANGE)
				surface.DrawRect(2, h - 2, w - 4, 2)
			end
		end
	end
	local onScreen = button(kinds, L("uis_on_screen"), "icon16/monitor.png", function() UI.NotifyDemo() end)
	onScreen:Dock(RIGHT)
	onScreen:DockMargin(6, 0, 0, 0)

	-----------------------------------------------------------------
	-- Look
	-----------------------------------------------------------------
	heading(page, L("uis_notify_look"))
	local styleCombo = combo(page, L("notify_style"), "speditor_notify_style", function() return list(UI.NotifyStyles, UI.NotifyStyleName) end)
	combo(page, L("notify_anim"), "speditor_notify_anim", list(UI.NotifyAnims, L2("nanim_")))
	combo(page, L("notify_pos"), "speditor_notify_pos", list(UI.NotifyPlaces, L2("npos_")))
	slider(page, L("notify_width"), "speditor_notify_width", 240, 700)
	slider(page, L("notify_opacity"), "speditor_notify_opacity", 30, 100)
	check(page, L("notify_bar"), "speditor_notify_bar")

	-----------------------------------------------------------------
	-- Style editor: a style of one's own, kept as JSON in data/speditor/notify_styles
	-----------------------------------------------------------------
	local edToggle = vgui.Create("DPanel", page)
	edToggle:Dock(TOP)
	edToggle:DockMargin(10, 6, 10, 2)
	edToggle:SetTall(24)
	edToggle.Paint = function() end
	local ed = vgui.Create("DPanel", page)
	ed:Dock(TOP)
	ed:DockMargin(10, 0, 10, 4)
	ed:SetVisible(false)
	ed.Paint = function(_, w, h)
		surface.SetDrawColor(COL.ROW_B)
		surface.DrawRect(0, 0, w, h)
	end
	ed.PerformLayout = function(s) s:SizeToChildren(false, true) end

	local draft = table.Copy(UI.NotifyStyleDefaults)
	local editingId = nil
	local function applyDraft()
		timer.Create("SPeditor.NotifyDraft", 0.15, 1, function()
			local ok, def = pcall(UI.NotifyStyleFromTable, draft, "SPeditor.NS.draft")
			if ok then
				UI.NotifyStyleDefs.__draft = def
				state.style = ed:IsVisible() and "__draft" or nil
				if IsValid(box) then restart() end
			end
		end)
	end

	local fields = {}
	local function edRow(text, h)
		local r = row(ed, text, h)
		r:DockMargin(8, 2, 8, 2)
		return r
	end
	local function edSlider(text, key, min, max)
		local sl = UI.Slider(ed, text, min, max, 0, draft[key], function(v)
			draft[key] = math.Round(v)
			applyDraft()
		end)
		sl:DockMargin(8, 1, 8, 1)
		fields[#fields + 1] = function() sl:SetValue(draft[key]) end
	end
	local function edCombo(text, key, items)
		local r = edRow(text)
		local c = vgui.Create("DComboBox", r)
		c:Dock(FILL)
		c:SetSortItems(false)
		UI.StyleCombo(c)
		for _, it in ipairs(items) do c:AddChoice(it[2], it[1]) end
		c.OnSelect = function(_, _, _, v)
			draft[key] = v
			applyDraft()
		end
		fields[#fields + 1] = function()
			for i, it in ipairs(items) do if it[1] == draft[key] then c:ChooseOptionID(i) end end
		end
	end
	local function edCheck(text, key)
		local c = UI.Check(ed, text, draft[key], function(v)
			draft[key] = v and true or false
			applyDraft()
		end)
		c:DockMargin(10, 3, 8, 3)
		fields[#fields + 1] = function() c:SetValue(draft[key] and 1 or 0) end
	end

	-- which style is edited: a new one or a saved one
	local pickRow = edRow(L("nse_edit"))
	local pick = vgui.Create("DComboBox", pickRow)
	pick:Dock(FILL)
	pick:SetSortItems(false)
	UI.StyleCombo(pick)
	local function refillPick()
		pick:Clear()
		pick:AddChoice(L("nse_new"), "", editingId == nil)
		for id, t in SortedPairs(UI.NotifyStyleTables or {}) do
			pick:AddChoice(tostring(t.name or id), id, editingId == id)
		end
	end
	refillPick()

	local nameRow = edRow(L("nse_name"))
	local nameEntry = vgui.Create("DTextEntry", nameRow)
	nameEntry:Dock(FILL)
	nameEntry:SetValue(draft.name)
	nameEntry.OnChange = function(s) draft.name = s:GetValue() end
	fields[#fields + 1] = function() nameEntry:SetValue(draft.name or "") end

	local colors = edRow(L("nse_colors"), 26)
	local function tc(key)
		local t = draft[key] or { 255, 255, 255, 255 }
		return Color(t[1], t[2], t[3], t[4] or 255)
	end
	local function setTc(key)
		return function(c)
			draft[key] = { c.r, c.g, c.b, c.a }
			applyDraft()
		end
	end
	local swatches = vgui.Create("DPanel", colors)
	swatches:Dock(FILL)
	swatches.Paint = function() end
	for _, it in ipairs({ { "bg", "nse_bg", true }, { "border", "nse_border", true }, { "text", "nse_text", false } }) do
		local cb = colorButton(swatches, function() return tc(it[1]) end, setTc(it[1]), it[3])
		cb:SetTooltip(L(it[2]))
		local lbl = vgui.Create("DLabel", swatches)
		lbl:Dock(LEFT)
		lbl:DockMargin(0, 0, 14, 0)
		lbl:SetFont("SPeditor.Small")
		lbl:SetTextColor(COL.DIM)
		lbl:SetText(L(it[2]))
		lbl:SizeToContents()
	end

	edSlider(L("nse_radius"), "radius", 0, 16)
	edSlider(L("nse_border_w"), "borderWidth", 0, 3)
	edSlider(L("nse_pad"), "pad", 3, 20)
	edCombo(L("nse_accent"), "accent", { { "left", L("nse_acc_left") }, { "top", L("nse_acc_top") },
		{ "bottom", L("nse_acc_bottom") }, { "fill", L("nse_acc_fill") }, { "none", L("nse_acc_none") } })
	edSlider(L("nse_accent_size"), "accentSize", 1, 8)
	local faces = {}
	for _, f in ipairs(UI.FONT_FACES) do faces[#faces + 1] = { f, f } end
	edCombo(L("uis_font"), "font", faces)
	edSlider(L("uis_font_size"), "fontSize", 10, 24)
	edCheck(L("nse_bold"), "bold")
	edCheck(L("nse_shadow"), "shadow")
	edSlider(L("nse_blur"), "blur", 0, 10)
	edSlider(L("nse_sheen"), "sheen", 0, 100)
	edCombo(L("nse_icons"), "icons", { { "silk", L("nse_ic_silk") }, { "gmod", L("nse_ic_gmod") },
		{ "disc", L("nse_ic_disc") }, { "none", L("nse_ic_none") } })

	local function loadDraft(id)
		editingId = (id ~= "" and id) or nil
		draft = table.Copy(UI.NotifyStyleDefaults)
		draft.name = L("nse_default_name")
		if editingId and UI.NotifyStyleTables[editingId] then
			table.Merge(draft, table.Copy(UI.NotifyStyleTables[editingId]))
		end
		for _, f in ipairs(fields) do f() end
		applyDraft()
	end
	pick.OnSelect = function(_, _, _, id) loadDraft(id) end
	-- the fields show the new style from the start
	draft.name = L("nse_default_name")
	for _, f in ipairs(fields) do f() end

	local edTools = vgui.Create("DPanel", ed)
	edTools:Dock(TOP)
	edTools:DockMargin(8, 6, 8, 8)
	edTools:SetTall(24)
	edTools.Paint = function() end
	button(edTools, L("nse_save"), "icon16/disk.png", function()
		if string.Trim(draft.name or "") == "" then draft.name = UI.NotifyStyleDefaults.name end
		local id = UI.SaveNotifyStyle(draft)
		editingId = id
		refillPick()
		styleCombo.Refill(function() return list(UI.NotifyStyles, UI.NotifyStyleName) end)
		RunConsoleCommand("speditor_notify_style", id)
		SPeditor.Notify(string.format(L("nse_saved"), draft.name), 2)
	end)
	button(edTools, L("nse_delete"), "icon16/bin.png", function()
		if not editingId then return end
		local def = UI.NotifyStyleDefs[editingId]
		if def and def.static then
			SPeditor.Notify(L("nse_static"), 1)
			return
		end
		Derma_Query(string.format(L("nse_delete_q"), tostring(draft.name)), L("ui_settings"), L("yes"), function()
			UI.DeleteNotifyStyle(editingId)
			editingId = nil
			refillPick()
			styleCombo.Refill(function() return list(UI.NotifyStyles, UI.NotifyStyleName) end)
			loadDraft("")
		end, L("cancel"), function() end)
	end)
	UI.Label(ed, L("nse_where"), COL.DIM):DockMargin(8, 0, 8, 8)

	local edBtn = button(edToggle, L("nse_title"), "icon16/paintbrush.png", function()
		ed:SetVisible(not ed:IsVisible())
		state.style = ed:IsVisible() and "__draft" or nil
		page:InvalidateLayout()
		if ed:IsVisible() then applyDraft() else restart() end
	end)
	local edPaint = edBtn.Paint
	edBtn.Paint = function(s, w, h)
		if edPaint then edPaint(s, w, h) end
		if ed:IsVisible() then
			surface.SetDrawColor(COL.ORANGE)
			surface.DrawRect(2, h - 2, w - 4, 2)
		end
	end

	-----------------------------------------------------------------
	-- Behaviour and sounds
	-----------------------------------------------------------------
	heading(page, L("uis_notify_behaviour"))
	check(page, L("notify_show"), "speditor_notify")
	slider(page, L("notify_time_s"), "speditor_notify_time", 1, 30)
	slider(page, L("notify_max"), "speditor_notify_max", 1, 12)

	heading(page, L("uis_notify_sounds"))
	check(page, L("notify_sound"), "speditor_notify_sound")
	local customRows = {}
	local setCombo = combo(page, L("notify_soundset"), "speditor_notify_soundset",
		function() return list(UI.NotifySoundSets, UI.NotifySoundSetName) end, function(id)
			for _, r in ipairs(customRows) do r:SetVisible(id == "custom") end
			page:InvalidateLayout()
			UI.PlayNotifyPath(UI.NotifySoundPath(0, id))
		end)

	-- listen to the kinds of the chosen set
	local listen = row(page, L("nsnd_listen"))
	for _, k in ipairs(KIND_IDS) do
		local b = button(listen, L("notify_kind_" .. k), "icon16/sound.png", function()
			UI.PlayNotifyPath(UI.NotifySoundPath(k))
		end)
		b:SetWide(b:GetWide() - 6)
	end

	-- "Custom": a sound for every kind
	for _, k in ipairs(KIND_IDS) do
		local r = row(page, "   " .. L("notify_kind_" .. k))
		local e = vgui.Create("DTextEntry", r)
		e:Dock(FILL)
		e:SetValue(GetConVarString("speditor_notify_snd_" .. k))
		e:SetPlaceholderText(L("nsnd_path_hint"))
		e.OnEnter = function(s) RunConsoleCommand("speditor_notify_snd_" .. k, string.Trim(s:GetValue())) end
		e.OnLoseFocus = function(s) RunConsoleCommand("speditor_notify_snd_" .. k, string.Trim(s:GetValue())) end
		cvars.AddChangeCallback("speditor_notify_snd_" .. k, function(_, _, new)
			if IsValid(e) and not e:HasFocus() then e:SetValue(new) end
		end, "SPeditor.NotifyCustomRow")
		local play = vgui.Create("DButton", r)
		play:Dock(RIGHT)
		play:DockMargin(4, 0, 0, 0)
		play:SetWide(26)
		play:SetText("")
		play:SetIcon("icon16/sound.png")
		UI.StyleButton(play, nil, 3)
		play.DoClick = function() UI.PlayNotifyPath(GetConVarString("speditor_notify_snd_" .. k)) end
		-- pick one from the sets that are there
		local more = vgui.Create("DButton", r)
		more:Dock(RIGHT)
		more:DockMargin(4, 0, 0, 0)
		more:SetWide(26)
		more:SetText("…")
		UI.StyleButton(more, nil, 3)
		more.DoClick = function()
			local m = UI.Menu()
			for _, id in ipairs(UI.NotifySoundSets) do
				local def = UI.NotifySoundSetDefs[id]
				if def then
					local sub = m:AddSubMenu(UI.NotifySoundSetName(id))
					for _, kk in ipairs(KIND_IDS) do
						local path = def[kk]
						if path then
							sub:AddOption(L("notify_kind_" .. kk) .. "  —  " .. string.GetFileFromFilename(path), function()
								RunConsoleCommand("speditor_notify_snd_" .. k, path)
							end)
						end
					end
				end
			end
			m:AddSpacer()
			m:AddOption(L("nsa_title") .. "…", function() UI.OpenSoundAddons() end):SetIcon("icon16/plugin.png")
			m:Open()
		end
		r:SetVisible(GetConVarString("speditor_notify_soundset") == "custom")
		customRows[#customRows + 1] = r
	end

	local tools = vgui.Create("DPanel", page)
	tools:Dock(TOP)
	tools:DockMargin(10, 6, 10, 2)
	tools:SetTall(24)
	tools.Paint = function() end
	button(tools, L("nsa_title") .. "…", "icon16/plugin.png", function() UI.OpenSoundAddons() end)
	button(tools, L("nsnd_rescan"), "icon16/arrow_refresh.png", function()
		UI.ScanNotifySounds()
		UI.LoadNotifyStyles()
		setCombo.Refill(function() return list(UI.NotifySoundSets, UI.NotifySoundSetName) end)
		styleCombo.Refill(function() return list(UI.NotifyStyles, UI.NotifyStyleName) end)
		refillPick()
		SPeditor.Notify(string.format(L("nsnd_rescan_done"), #UI.NotifySoundSets, #UI.NotifyStyles - 1), 0)
	end)
	-- a set made in the "Sounds from addons" window shows up in the list
	cvars.AddChangeCallback("speditor_notify_soundset", function(_, _, new)
		if not IsValid(setCombo) then return end
		setCombo.Refill(function() return list(UI.NotifySoundSets, UI.NotifySoundSetName) end)
		for _, r in ipairs(customRows) do if IsValid(r) then r:SetVisible(new == "custom") end end
		if IsValid(page) then page:InvalidateLayout() end
	end, "SPeditor.NotifySetCombo")
	local note = UI.Label(page, L("nsnd_where"), COL.DIM)
	note:SetWrap(true)
	note:SetAutoStretchVertical(true)
	note:DockMargin(10, 4, 10, 4)

	local tools2 = vgui.Create("DPanel", page)
	tools2:Dock(TOP)
	tools2:DockMargin(10, 10, 10, 10)
	tools2:SetTall(24)
	tools2.Paint = function() end
	button(tools2, L("notify_test"), "icon16/comment.png", function() UI.NotifyDemo() end)
	button(tools2, L("notify_log") .. "…", "icon16/comments.png", function() UI.OpenNotifyLog() end)
end

---------------------------------------------------------------------
-- The window
---------------------------------------------------------------------
local PAGES = {
	{ id = "look",   title = "uis_appearance", icon = "icon16/palette.png", build = buildLook },
	{ id = "notify", title = "uis_notify",     icon = "icon16/comment.png", build = buildNotify },
}

function UI.OpenSettings(which)
	local Dock = SPeditor.Dock
	if Dock.ShowPage("uisettings") then
		local w = Dock.ByKey("uisettings")
		if which and IsValid(w) and w.SelectTab then w.SelectTab(which) end
		return
	end
	local W, H = 560, 620
	local win, body = Dock.Create({ key = "uisettings", id = "uisettings", title = L("ui_settings"), w = W,
			h = math.min(H, ScrH() - 120), x = math.floor(ScrW() / 2 - W / 2), y = 90, dockable = false, icon = "icon16/cog.png" })
	win.minW, win.minH = 460, 320

	-- a page switch on top (the window tab strip holds the window title)
	local bar = vgui.Create("DPanel", body)
	bar:Dock(TOP)
	bar:SetTall(30)
	bar.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(0, h - 1, w, 1)
	end

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(34)
	foot.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(0, 0, w, 1)
	end

	local scrolls, tabs = {}, {}
	local active = which or "look"
	local function choose(id)
		active = id
		for pid, sc in pairs(scrolls) do sc:SetVisible(pid == id) end
	end
	win.SelectTab = choose
	win.SPState = function() return active end

	for _, pg in ipairs(PAGES) do
		local scroll = vgui.Create("DScrollPanel", body)
		scroll:Dock(FILL)
		scroll:SetVisible(false)
		scrolls[pg.id] = scroll
		local ok, err = pcall(pg.build, scroll)
		if not ok then UI.Label(scroll, tostring(err), COL.RED) end

		local t = vgui.Create("DButton", bar)
		t:Dock(LEFT)
		t:DockMargin(6, 4, 0, 0)
		surface.SetFont("SPeditor.Small")
		t:SetWide(select(1, surface.GetTextSize(L(pg.title))) + 42)
		t:SetText("")
		local icon = Material(pg.icon)
		t.Paint = function(s, w, h)
			local on = active == pg.id
			local k = UI.Ease(s, "_hot", (s:IsHovered() or on) and 1 or 0, 18)
			local fill = UI.LerpColor(COL.TAB_OFF, COL.TAB_ON, on and 1 or k * 0.5)
			draw.RoundedBoxEx(UI.Corners() > 0 and 4 or 0, 0, 0, w, h, fill, true, true, false, false)
			if on then
				surface.SetDrawColor(COL.ORANGE)
				surface.DrawRect(0, 0, w, 2)
			end
			surface.SetMaterial(icon)
			surface.SetDrawColor(255, 255, 255, on and 255 or 170)
			surface.DrawTexturedRect(8, (h - 16) / 2, 16, 16)
			draw.SimpleText(L(pg.title), "SPeditor.Small", 30, h / 2, on and COL.TEXT or COL.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		t.DoClick = function() choose(pg.id) end
		tabs[pg.id] = t
	end
	choose(active)

	local reset = vgui.Create("DButton", foot)
	reset:Dock(LEFT)
	reset:DockMargin(8, 5, 4, 5)
	surface.SetFont("SPeditor.Small")
	reset:SetWide(select(1, surface.GetTextSize(L("uis_reset"))) + 40)
	reset:SetText("  " .. L("uis_reset"))
	reset:SetIcon("icon16/arrow_undo.png")
	UI.StyleButton(reset, nil, 3)
	reset.DoClick = function()
		Derma_Query(L("uis_reset_confirm"), L("ui_settings"), L("yes"), function() UI.ResetUISettings() end, L("cancel"), function() end)
	end

	local close = vgui.Create("DButton", foot)
	close:Dock(RIGHT)
	close:DockMargin(4, 5, 8, 5)
	close:SetWide(110)
	close:SetText(L("about_close"))
	UI.StyleButton(close, nil, 3)
	close.DoClick = function() win:Close() end
end
