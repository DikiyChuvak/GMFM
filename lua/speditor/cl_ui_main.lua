--[[
SPeditor — the main interface in the style of Source Filmmaker (for posters).

The default layout follows SFM:
  * on the left, full height — a window with the Animation Set Editor and Element Viewer tabs;
  * at the top — the Primary Viewport and the Secondary Viewport;
  * at the bottom, where the timeline would be — a window with the Scene and Shadows pages.
The windows are built by the SPeditor.Dock library (cl_ui_dock.lua): they can be moved,
resized by any edge, tabs can be dragged between windows, layouts can be
saved (Windows → Layouts), a window can be pinned on top (right click on the
tab strip → "Window properties").
Menus: File / Edit / Windows / View / Help, on the right — Render and Exit.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI   = SPeditor.UI
local C    = SPeditor.Client
local L    = SPeditor.L
local Dock = SPeditor.Dock
local COL  = UI.PAL

local MENU_H, STATUS_H = 24, 20

---------------------------------------------------------------------
-- Keyboard: windows receive input only while a text field is active
---------------------------------------------------------------------
local function setKeyboardInput(state)
	for _, w in ipairs(Dock.windows) do
		if IsValid(w) then w:SetKeyboardInputEnabled(state) end
	end
	if IsValid(UI.TopBar) then UI.TopBar:SetKeyboardInputEnabled(state) end
end

local function restoreCursor()
	local wp = vgui.GetWorldPanel()
	if IsValid(wp) then wp:SetCursor("arrow") end
end

hook.Add("OnTextEntryGetFocus", "SPeditor.TextFocus", function()
	if C.active then setKeyboardInput(true) end
end)
hook.Add("OnTextEntryLoseFocus", "SPeditor.TextFocus", function()
	if C.active then setKeyboardInput(false) end
end)

---------------------------------------------------------------------
-- Frame sources for the viewports
---------------------------------------------------------------------
local function workSource()
	local p, a, fov = C.GetWorkCamera()
	return { origin = p, angles = a, fov = fov, label = L("work_camera"), ent = nil }
end

local function camSource(e)
	local pos, ang = C.CameraPose(e)
	return { origin = pos, angles = ang, fov = e:GetCameraFOV(), label = C.DisplayName(e), ent = e }
end

local function primarySource()
	local ve = C.GetViewCamera()
	if IsValid(ve) then return camSource(ve) end
	return workSource()
end

local function secondarySource()
	local src = UI.secSrc or "auto"
	if src == "work" then return workSource() end
	if src == "none" then return nil end
	if IsValid(src) then return camSource(src) end
	if C.GetViewCamera() then return workSource() end
	if C.IsCamera(C.selected) then return camSource(C.selected) end
	return nil
end

-- the main game frame is not needed under the interface: cover it with black
-- the viewport page is visible (its tab is active and the window is shown)
-- "Exposure" submenu: fixed values and auto (engine auto exposure)
function UI.ExposureMenu(m)
	local R = SPeditor.Render
	local sub = m:AddSubMenu(L("view_exposure"))
	local cur = R.GetExposure()
	for _, v in ipairs(R.EXPOSURES) do
		sub:AddOption(v == 0 and L("exposure_auto") or tostring(v), function() R.SetExposure(v) end):SetChecked(math.abs(cur - v) < 0.001)
	end
end

function UI.PageShown(id)
	local pg = Dock.pages[id]
	return pg ~= nil and IsValid(pg.panel) and pg.panel:IsVisible() and IsValid(pg.win) and pg.win:IsVisible()
end

hook.Add("HUDPaintBackground", "SPeditor.Blackout", function()
	if not C.active or C.hideUI then return end
	if not UI.PageShown("primary") then return end
	surface.SetDrawColor(0, 0, 0, 255)
	surface.DrawRect(0, 0, ScrW(), ScrH())
end)

---------------------------------------------------------------------
-- Viewport
---------------------------------------------------------------------
local function buildViewport(title, key, pass)
	local win, body = Dock.Create({ key = key, id = key, title = title, w = 600, h = 450, dockable = true,
			icon = "icon16/monitor.png" })
	win.minW, win.minH = 220, 160
	-- the viewport state is kept on the page: the tab can be moved to another window
	local vp = body
	vp.pass = pass

	-- header: camera on the left, scene and frame in the centre, FOV on the right (where SFM has timecodes)
	local head = vgui.Create("DPanel", body)
	head:Dock(TOP)
	head:SetTall(34)
	head.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
		local src = vp.GetSource and vp.GetSource() or nil
		draw.SimpleText(src and src.label or L("no_camera"), "SPeditor.Time", 8, h / 2, COL.TIMECODE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local rw, rh = C.GetRenderSize()
		local scene = (C.sceneName and C.sceneName ~= "") and C.sceneName or L("untitled")
		draw.SimpleText(scene, "SPeditor.Small", w / 2, h / 2 - 7, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(string.format("%s  ·  %d×%d", SPeditor.LN("aspect_", C.GetAspectDef().name), rw, rh), "SPeditor.Small", w / 2, h / 2 + 7,
			COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		if src then
			draw.SimpleText(string.format("FOV %d°", math.Round(src.fov or 75)), "SPeditor.Time", w - 8, h / 2,
				COL.TIMECODE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
	end

	-- toolbar at the bottom
	local bar = vgui.Create("DPanel", body)
	bar:Dock(BOTTOM)
	bar:SetTall(28)
	bar.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(0, 0, w, 1)
	end

	UI.IconButton(bar, "icon16/arrow_out.png", L("act_move") .. " (1)", function() C.gizmo.mode = "move" end,
	function() return C.gizmo.mode == "move" end)
	UI.IconButton(bar, "icon16/arrow_rotate_clockwise.png", L("act_rotate") .. " (2)", function() C.gizmo.mode = "rotate" end,
	function() return C.gizmo.mode == "rotate" end)
	UI.IconButton(bar, "icon16/arrow_inout.png", L("act_scale") .. " (4)", function() C.gizmo.mode = "scale" end,
	function() return C.gizmo.mode == "scale" end)
	UI.IconButton(bar, "icon16/world.png", L("view_space"), function()
		C.gizmo.space = (C.gizmo.space == "world") and "local" or "world"
	end, function() return C.gizmo.space == "world" end)
	UI.IconButton(bar, "icon16/user_go.png", L("ik_hint") .. " (I)", function()
		C.gizmo.ik = not C.gizmo.ik
		if C.gizmo.ik then SPeditor.Notify(L("ik_hint"), 0) end
	end, function() return C.gizmo.ik end)

	local sep = vgui.Create("DPanel", bar)
	sep:Dock(LEFT)
	sep:DockMargin(6, 6, 4, 6)
	sep:SetWide(1)
	sep.Paint = function(_, w, h) surface.SetDrawColor(COL.BORDER) surface.DrawRect(0, 0, 1, h) end

	UI.IconButton(bar, "icon16/table.png", L("view_guides"), function()
		local m = SPeditor.UI.Menu()
		for _, g in ipairs(C.GUIDE_LIST) do
			m:AddOption(L("guide_" .. g), function() C.ToggleGuide(g) end):SetChecked(C.HasGuide(g))
		end
		m:Open()
	end)
	UI.IconButton(bar, "icon16/chart_line.png", L("view_skeleton"), function() C.showSkeleton = not C.showSkeleton end,
	function() return C.showSkeleton end)
	UI.IconButton(bar, "icon16/lightbulb.png", L("view_fullbright"), function() C.fullbright = not C.fullbright end,
	function() return C.fullbright end)

	local gear = UI.IconButton(bar, "icon16/cog.png", L("col_settings"), function()
		local m = SPeditor.UI.Menu()
		m:AddOption(L("gear_focus"), function() C.FocusSelected() end)
		m:AddOption(L("cam_settings") .. "…", function() UI.OpenCameraSettings() end)
		m:AddOption(L("act_render") .. "…", function() UI.OpenRenderDialog() end)
		UI.ExposureMenu(m)
		local asp = m:AddSubMenu(L("menu_aspect"))
		for _, a in ipairs(SPeditor.Aspects) do
			asp:AddOption(SPeditor.LN("aspect_", a.name), function()
				RunConsoleCommand("speditor_render_custom", "0")
				C.SetAspect(a.id)
			end):SetChecked(C.GetAspectDef().id == a.id)
		end
		m:AddSpacer()
		m:AddOption(L("gear_hide"), function() local pg = Dock.pages[key] if pg and IsValid(pg.win) then pg.win:Close() end end)
		m:Open()
	end, nil, RIGHT)
	gear:DockMargin(2, 3, 4, 3)

	local combo = UI.StyleCombo(vgui.Create("DComboBox", bar))
	combo:Dock(RIGHT)
	combo:DockMargin(2, 4, 2, 4)
	combo:SetWide(140)
	vp.combo = combo

	-- the frame itself (black bars outside the frame, as in SFM)
	local view = vgui.Create("DPanel", body)
	view:Dock(FILL)
	view.Paint = function(_, pw, ph)
		surface.SetDrawColor(COL.VIEW_BG)
		surface.DrawRect(0, 0, pw, ph)
		local src = vp.GetSource and vp.GetSource() or nil
		if src and C.active and not C.hideUI and SPeditor.Render then
			-- while Render is open, the Secondary Viewport stays on the last frame:
			-- the result with effects is watched in the preview, and the frame time is given to it
			local frozen = vp.pass == "secondary" and UI.PageShown("render")
			local ix, iy, iw, ih = SPeditor.Render.Viewport(src, pw, ph, vp.pass or "primary", frozen)
			if ix then C.DrawGuides(ix, iy, iw, ih) end
			if ix and frozen then
				draw.SimpleTextOutlined(L("vp_paused"), "SPeditor.Small", ix + 8, iy + 6, COL.ORANGE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
			end
		elseif not src then
			draw.SimpleText(L("no_camera"), "SPeditor.Time", pw / 2, ph / 2, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	-- wheel over the frame: move the work camera closer / farther (as in SFM)
	if pass == "primary" then
		view.OnMouseWheeled = function(_, delta)
			C.WheelZoom(delta)
			return true
		end
	end
	vp.view = view
	return vp
end

local function refreshCombo(vp, isPrimary)
	local combo = vp.combo
	if not IsValid(combo) then return end
	local cams = {}
	for _, e in ipairs(C.Objects()) do
		if C.IsCamera(e) then cams[#cams + 1] = e end
	end
	local secKey = UI.secSrc
	if secKey == nil or secKey == "work" or secKey == "none" or secKey == "auto" then
		secKey = tostring(secKey or "auto")
	else
		secKey = IsValid(secKey) and secKey:EntIndex() or "dead"
	end
	local cur = isPrimary and (C.GetViewCamera() and C.GetViewCamera():EntIndex() or 0) or secKey
	local sig = {}
	for _, e in ipairs(cams) do sig[#sig + 1] = e:EntIndex() .. C.DisplayName(e) end
	sig = table.concat(sig, ",") .. "|" .. tostring(cur)
	if vp._sig == sig then return end
	vp._sig = sig

	combo:Clear()
	if isPrimary then
		combo:AddChoice(L("work_camera"), 0)
		for _, e in ipairs(cams) do combo:AddChoice(C.DisplayName(e), e) end
		local ve = C.GetViewCamera()
		combo:SetText(ve and C.DisplayName(ve) or L("work_camera"))
	else
		combo:AddChoice(L("vp_auto"), "auto")
		combo:AddChoice(L("vp_none"), "none")
		combo:AddChoice(L("work_camera"), "work")
		for _, e in ipairs(cams) do combo:AddChoice(C.DisplayName(e), e) end
		local s = UI.secSrc or "auto"
		local txt = L("vp_auto")
		if s == "work" then txt = L("work_camera")
		elseif s == "none" then txt = L("vp_none")
		elseif IsValid(s) then txt = C.DisplayName(s) end
		combo:SetText(txt)
	end
end

---------------------------------------------------------------------
-- Hotkey reference (Help)
---------------------------------------------------------------------
function UI.OpenHotkeys()
	if Dock.ShowPage("hotkeys") then return end
	local win, body = Dock.Create({ key = "hotkeys", id = "hotkeys", title = L("help_hotkeys"), w = 560, h = 440,
			x = math.floor(ScrW() / 2 - 280), y = 120, dockable = false, icon = "icon16/keyboard.png" })
	local list = vgui.Create("DListView", body)
	list:Dock(FILL)
	list:AddColumn(L("help_key")):SetFixedWidth(230)
	list:AddColumn(L("help_action"))
	if list.SetBackgroundColor then list:SetBackgroundColor(COL.LIST_BG) end
	for _, row in ipairs({
				{ L("key_lmb"), "help_select" }, { L("key_rmb"), "help_rmb" }, { L("key_rmb") .. " + WASD / Q E", "help_fly" },
				{ "Alt + " .. L("key_lmb"), "help_orbit" }, { L("key_wheel"), "help_dolly" }, { "Alt + " .. L("key_wheel"), "help_fov" },
				{ "1 / 2 / 4", "help_move_rotate" }, { "3", "help_space" }, { "Ctrl + " .. L("key_lmb"), "help_multi" }, { "I", "help_ik" },
				{ "F", "help_focus" }, { "V", "help_camview" }, { "B", "help_skeleton" }, { "Del", "obj_delete" },
				{ "Ctrl + D", "obj_duplicate" }, { "Ctrl + C / Ctrl + V", "help_pose_clip" }, { "Ctrl + Z / Ctrl + Y", "help_undo" },
				{ "Shift + " .. L("key_drag"), "help_fine" },
				{ L("help_dock_key"), "help_dock" }, { L("help_max_key"), "dock_maximize" },
				{ L("help_props_key"), "dock_props" },
		}) do
		list:AddLine(row[1], L(row[2]))
	end
	-- mod keys
	for _, h in ipairs(SPeditor.Mods.hotkeys) do
		if h.desc then
			local key = h.label or string.upper(input.GetKeyName(h.key) or "?")
			list:AddLine((h.ctrl and "Ctrl + " or "") .. (h.shift and "Shift + " or "") .. key, L(h.desc) .. "   [" .. h.mod.name .. "]")
		end
	end
end

---------------------------------------------------------------------
-- Opening / closing
---------------------------------------------------------------------
function UI.Open()
	UI.Close()
	UI.ApplyTheme(GetConVar("speditor_theme"):GetString(), true)
	local scrW, scrH = ScrW(), ScrH()

	-----------------------------------------------------------------
	-- Menu bar
	-----------------------------------------------------------------
	local top = UI.Skin(vgui.Create("DPanel"))
	top:SetPos(0, 0)
	top:SetSize(scrW, MENU_H)
	top:MakePopup()
	top:SetKeyboardInputEnabled(false)
	top.Paint = function(s, w, h) UI.PaintChrome("MenuBar", s, w, h) end
	UI.TopBar = top

	local function mbtn(label, build)
		local b = vgui.Create("DButton", top)
		b:Dock(LEFT)
		surface.SetFont("SPeditor.Small")
		b:SetWide(select(1, surface.GetTextSize(label)) + 18)
		b:SetText(label)
		b:SetFont("SPeditor.Small")
		b:SetTextColor(UI.ChromeText("MenuBar") or COL.TEXT)
		b.Paint = function(s, w, h) UI.PaintChrome("MenuButton", s, w, h) end
		b.DoClick = function()
			local m = SPeditor.UI.Menu()
			build(m)
			local x, y = b:LocalToScreen(0, b:GetTall())
			m:Open(x, y)
			-- the button stays highlighted while its menu is open
			b._menuOpen = true
			local rm = m.OnRemove
			m.OnRemove = function(...)
				if IsValid(b) then b._menuOpen = false end
				if rm then return rm(...) end
			end
		end
		return b
	end

	mbtn(L("menu_file"), function(m)
		m:AddOption(L("save_scene") .. "…", function()
			Derma_StringRequest(L("save_name"), L("enter_name"), C.sceneName or "", function(name)
				C.SceneSave(name, C.GetSceneMeta())
			end)
		end):SetIcon("icon16/disk.png")
		m:AddOption(L("load_scene") .. "…", function() Dock.ShowPage("scene") end):SetIcon("icon16/folder_go.png")
		m:AddOption(L("act_render") .. "…", function() UI.OpenRenderDialog() end):SetIcon("icon16/picture_save.png")
		m:AddOption(L("adopt_title") .. "…", function() UI.OpenAdopt() end):SetIcon("icon16/world_add.png")
		m:AddOption(L("files_title") .. "…", function() UI.OpenFileLocations() end):SetIcon("icon16/folder_explore.png")
		m:AddOption(L("autosave"), function()
			RunConsoleCommand("speditor_autosave", GetConVar("speditor_autosave"):GetBool() and "0" or "1")
		end):SetChecked(GetConVar("speditor_autosave"):GetBool())
		m:AddSpacer()
		m:AddOption(L("act_clear"), function()
			Derma_Query(L("clear_confirm"), "SPeditor", L("yes"), function() C.SendCleanup() end, L("cancel"), function() end)
		end):SetIcon("icon16/bin.png")
		SPeditor.Mods.RunMenu("file", m)
		m:AddSpacer()
		m:AddOption(L("act_exit"), function() RunConsoleCommand("speditor_toggle") end):SetIcon("icon16/door_out.png")
	end)

	-- a menu item with its key on the right (Derma draws a tab character as a box)
	local function keyed(m, text, key, fn)
		local o = m:AddOption(text, fn)
		local lbl = vgui.Create("DLabel", o)
		lbl:SetText(key)
		lbl:SetFont(o:GetFont() or "DermaDefault")
		lbl:SetTextColor(COL.DIM)
		lbl:SizeToContents()
		local base = o.PerformLayout
		o.PerformLayout = function(s, w, h)
			if base then base(s, w, h) end
			local need = s:GetContentSize() + lbl:GetWide() + 64
			if s:GetWide() < need then s:SetWide(need) end
			lbl:SetPos(s:GetWide() - lbl:GetWide() - 12, (s:GetTall() - lbl:GetTall()) / 2)
		end
		return o
	end

	mbtn(L("menu_edit"), function(m)
		keyed(m, L("edit_undo"), "Ctrl+Z", function() C.Undo() end):SetIcon("icon16/arrow_undo.png")
		keyed(m, L("edit_redo"), "Ctrl+Y", function() C.Redo() end):SetIcon("icon16/arrow_redo.png")
		m:AddSpacer()
		keyed(m, L("obj_duplicate"), "Ctrl+D", function() if IsValid(C.selected) then C.SendDuplicate(C.selected) end end)
		keyed(m, L("obj_delete"), "Del", function() if IsValid(C.selected) then C.SendDelete(C.selected) C.Select(nil) end end)
		m:AddOption(L("props_open"), function()
			if IsValid(C.selected) and not C.IsAux(C.selected) then UI.OpenObjectProps(C.selected) end
		end):SetIcon("icon16/wrench.png")
		m:AddSpacer()
		keyed(m, L("pose_copy"), "Ctrl+C", function() C.CopyPose(C.selected) end)
		keyed(m, L("pose_paste"), "Ctrl+V", function() C.PastePose(C.selected) end)
		m:AddOption(L("drop_floor"), function() if IsValid(C.selected) then C.SendDropToFloor(C.selected) end end)
		m:AddSpacer()
		local cr = m:AddSubMenu(L("menu_create"))
		cr:AddOption(L("ase_add_model"), function() UI.ToggleBrowser() end)
		cr:AddOption(L("act_spawn_camera"), function() C.SendCameraSpawn(C.camera.pos, C.camera.ang) end)
		cr:AddOption(L("spawn_spot"), function() UI.SpawnLight(1) end)
		cr:AddOption(L("spawn_point"), function() UI.SpawnLight(0) end)
		UI.LightKindMenu(cr)
		cr:AddOption(L("eff_add"), function() UI.ToggleEffects() end)
		cr:AddOption(L("rig_make"), function() C.SpawnLightRig(C.selected) end)
		SPeditor.Mods.RunMenu("create", cr)
		m:AddSpacer()
		m:AddOption(L("edit_deselect"), function() C.Select(nil) end)
		SPeditor.Mods.RunMenu("edit", m)
	end)

	mbtn(L("menu_windows"), function(m)
		for _, id in ipairs({ "ase", "ev", "primary", "secondary", "scene", "shadows" }) do
			local page = Dock.pages[id]
			if page then m:AddOption(page.title, function() Dock.ShowPage(id) end) end
		end
		m:AddOption(L("win_browser"), function() UI.ToggleBrowser() end)
		m:AddOption(L("render_title"), function() UI.OpenRenderDialog() end)
		m:AddOption(L("shaders_title"), function() UI.OpenShaders() end):SetIcon("icon16/wand.png")
		m:AddOption(L("mods_title"), function() UI.OpenMods() end):SetIcon("icon16/plugin.png")
		-- mod pages (MOD:AddPage)
		for _, pg in ipairs(SPeditor.Mods.pages) do
			m:AddOption(SPeditor.Mods.PageTitle(pg), function() UI.ShowModPage(pg.id) end):SetIcon(pg.icon or "icon16/plugin.png")
		end
		SPeditor.Mods.RunMenu("windows", m)
		m:AddSpacer()
		UI.BuildNotifyMenu(m:AddSubMenu(L("menu_notify")))
		local lay = m:AddSubMenu(L("menu_layout"))
		Dock.BuildMenu(lay)
	end)

	mbtn(L("menu_view"), function(m)
		m:AddOption(L("view_fullbright"), function() C.fullbright = not C.fullbright end):SetChecked(C.fullbright and true or false)
		UI.ExposureMenu(m)
		m:AddOption(L("view_skeleton"), function() C.showSkeleton = not C.showSkeleton end):SetChecked(C.showSkeleton and true or false)
		local bs = m:AddSubMenu(L("view_bone_size"))
		for i, v in ipairs(C.BONE_SIZES) do
			bs:AddOption(L("bone_size_" .. i), function() C.SetBoneSize(v) end):SetChecked(math.abs(C.GetBoneSize() - v) < 0.01)
		end
		m:AddOption(L("view_camview"), function()
			if C.GetViewCamera() then C.StopViewCamera()
			elseif C.IsCamera(C.selected) then C.StartViewCamera(C.selected) end
		end)
		m:AddOption(L("view_space"), function() C.gizmo.space = (C.gizmo.space == "world") and "local" or "world" end)
		m:AddOption(L("ik_feet"), function() C.gizmo.ikFeet = not C.gizmo.ikFeet end):SetChecked(C.gizmo.ikFeet and true or false)
		m:AddSpacer()
		local gsub = m:AddSubMenu(L("view_guides"))
		for _, g in ipairs(C.GUIDE_LIST) do
			gsub:AddOption(L("guide_" .. g), function() C.ToggleGuide(g) end):SetChecked(C.HasGuide(g))
		end
		local asp = m:AddSubMenu(L("menu_aspect"))
		for _, a in ipairs(SPeditor.Aspects) do
			asp:AddOption(SPeditor.LN("aspect_", a.name), function()
				RunConsoleCommand("speditor_render_custom", "0")
				C.SetAspect(a.id)
			end):SetChecked(C.GetAspectDef().id == a.id and not GetConVar("speditor_render_custom"):GetBool())
		end
		SPeditor.Mods.RunMenu("view", m)
		m:AddSpacer()
		UI.BuildThemeMenu(m:AddSubMenu(L("menu_theme")))
		m:AddOption(L("ui_settings") .. "…", function() UI.OpenSettings() end):SetIcon("icon16/cog.png")
	end)

	mbtn(L("menu_help"), function(m)
		m:AddOption(L("help_hotkeys"), function() UI.OpenHotkeys() end):SetIcon("icon16/keyboard.png")
		m:AddOption(L("cam_settings") .. "…", function() UI.OpenCameraSettings() end):SetIcon("icon16/camera_edit.png")
		m:AddOption(L("files_title") .. "…", function() UI.OpenFileLocations() end):SetIcon("icon16/folder_explore.png")
		-- the interface language: the editor is rebuilt in it at once
		local lang, lo = m:AddSubMenu(L("qmenu_language"))
		if lo and lo.SetIcon then lo:SetIcon("icon16/world.png") end
		local cur = GetConVarString("speditor_language")
		for _, l in ipairs({ { "en", "English" }, { "ru", "Русский" } }) do
			lang:AddOption(l[2], function()
				if cur == l[1] then return end
				RunConsoleCommand("speditor_language", l[1])
				timer.Simple(0.1, function() if C.active then UI.Rebuild() end end)
			end):SetChecked(cur == l[1])
		end
		SPeditor.Mods.RunMenu("help", m)
		m:AddSpacer()
		m:AddOption(L("about_title"), function() UI.OpenAbout() end):SetIcon("icon16/information.png")
	end)

	local function rightBtn(text, icon, fn, hot)
		local b = vgui.Create("DButton", top)
		b:Dock(RIGHT)
		b:DockMargin(0, 2, 4, 2)
		surface.SetFont("SPeditor.Small")
		b:SetWide(select(1, surface.GetTextSize(text)) + 34)
		b:SetText("  " .. text)
		b:SetIcon(icon)
		UI.StyleButton(b, hot, 0)
		b.DoClick = fn
		return b
	end
	rightBtn(L("act_exit"), "icon16/door_out.png", function() RunConsoleCommand("speditor_toggle") end, Color(150, 60, 45))
	rightBtn(L("act_render"), "icon16/picture_save.png", function() UI.OpenRenderDialog() end)

	-----------------------------------------------------------------
	-- Windows
	-----------------------------------------------------------------
	-- left: Animation Set Editor + Element Viewer
	local left = Dock.NewWindow({ key = "left", w = 420, h = 600, dockable = true })
	left.minW = 300
	left:AddCloseButton()
	local aseBody = vgui.Create("DPanel")
	aseBody.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
	end
	left:AddPage("ase", L("win_ase"), aseBody, "icon16/application_view_list.png")
	UI.BuildASE(aseBody)
	UI.BuildElementViewer(left)
	left:SelectPage("ase")
	UI.LeftPanel = left

	-- viewports
	local prim = buildViewport(L("win_primary"), "primary", "primary")
	prim.GetSource = primarySource
	prim.combo.OnSelect = function(_, _, _, data)
		if data == 0 then C.StopViewCamera() elseif IsValid(data) then C.StartViewCamera(data) end
	end
	UI.PrimaryVP = prim

	local sec = buildViewport(L("win_secondary"), "secondary", "secondary")
	sec.GetSource = secondarySource
	sec.combo.OnSelect = function(_, _, _, data)
		UI.secSrc = data
		sec._sig = nil
	end
	UI.SecondaryVP = sec

	-- bottom (where the timeline would be): Scene + Shadows
	local bottom = Dock.NewWindow({ key = "bottom", w = 700, h = 240, dockable = true })
	bottom:AddCloseButton()
	UI.BuildScenePage(bottom)
	UI.BuildShadowsPage(bottom)
	UI.BottomWin = bottom
	-- mod pages: in the bottom window, next to the ASE, or in a window of their own (on demand)
	for _, pg in ipairs(SPeditor.Mods.pages) do
		if pg.window == "bottom" or pg.window == "left" then
			UI.BuildModPage(pg, pg.window == "left" and left or bottom)
		end
	end
	left:SelectPage("ase")
	bottom:SelectPage("scene")

	hook.Add("Think", "SPeditor.ComboRefresh", function()
		if not C.active then return end
		if IsValid(UI.PrimaryVP) then refreshCombo(UI.PrimaryVP, true) end
		if IsValid(UI.SecondaryVP) then refreshCombo(UI.SecondaryVP, false) end
	end)

	-----------------------------------------------------------------
	-- Status bar
	-----------------------------------------------------------------
	local status = UI.Skin(vgui.Create("DPanel"))
	status:SetPos(0, scrH - STATUS_H)
	status:SetSize(scrW, STATUS_H)
	status:MakePopup()
	status:SetKeyboardInputEnabled(false)
	local fps, fpsT = 0, 0
	status.Paint = function(s, w, h)
		UI.PaintChrome("StatusBar", s, w, h)
		local txt, dim = UI.ChromeText("StatusBar") or COL.TEXT, UI.ChromeText("StatusDim") or COL.DIM
		if RealTime() > fpsT then
			fpsT = RealTime() + 0.5
			fps = math.Round(1 / math.max(RealFrameTime(), 0.0001))
		end
		local modText = SPeditor.Mods.StatusText()
		draw.SimpleText(modText ~= "" and modText or L("hint_short"), "SPeditor.Small", 8, h / 2, modText ~= "" and txt or dim,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local rw, rh = C.GetRenderSize()
		local sel = IsValid(C.selected) and C.DisplayName(C.selected) or "—"
		if #C.multi > 0 then sel = sel .. " (+" .. #C.multi .. ")" end
		draw.SimpleText(string.format("[ %s: %d  |  %s: %s  |  %s  |  fps: %d  |  %d×%d %s ]",
				L("grp_models"), #C.Objects(), L("st_selected"), sel,
				string.upper(L("st_" .. C.gizmo.mode)) .. (C.gizmo.ik and " + IK" or ""),
				fps, rw, rh, SPeditor.LN("aspect_", C.GetAspectDef().name)), "SPeditor.Small", w - 8, h / 2, dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	UI.HintBar = status

	-----------------------------------------------------------------
	-- Every window closed: the screen is empty but for the menu bar, and people did not know
	-- how to get the windows back — a card in the middle says it and restores the layout.
	-----------------------------------------------------------------
	local empty = UI.Skin(vgui.Create("DPanel"))
	empty:SetSize(math.min(480, scrW - 40), 132)
	empty:SetPos(math.floor(scrW / 2 - empty:GetWide() / 2), math.floor(scrH / 2 - 66))
	empty:MakePopup()
	empty:SetKeyboardInputEnabled(false)
	empty:SetVisible(false)
	empty.Paint = function(_, w, h)
		draw.RoundedBox(4, 0, 0, w, h, COL.BORDER)
		draw.RoundedBox(4, 1, 1, w - 2, h - 2, COL.BG)
	end
	local msg = vgui.Create("DLabel", empty)
	msg:Dock(TOP)
	msg:DockMargin(14, 12, 14, 0)
	msg:SetFont("SPeditor.Small")
	msg:SetTextColor(COL.TEXT)
	msg:SetWrap(true)
	msg:SetTall(64)
	msg:SetContentAlignment(7)
	msg:SetText(L("empty_hint"))
	local restore = vgui.Create("DButton", empty)
	restore:Dock(BOTTOM)
	restore:DockMargin(14, 0, 14, 12)
	restore:SetTall(26)
	restore:SetText(L("empty_restore"))
	restore:SetIcon("icon16/application_side_tree.png")
	UI.StyleButton(restore, true, 3)
	restore.DoClick = function() Dock.Reset("default") end
	UI.EmptyHint = empty
	hook.Add("Think", "SPeditor.EmptyHint", function()
		if not IsValid(empty) then
			hook.Remove("Think", "SPeditor.EmptyHint")
			return
		end
		local any = false
		for _, w in ipairs(Dock.windows) do
			if IsValid(w) and w:IsVisible() and w.dockable then any = true break end
		end
		if any == empty:IsVisible() then
			empty:SetVisible(not any)
			if not any then empty:MoveToFront() end
		end
	end)

	-- layout: the SFM preset, then the last saved one
	Dock.Reset("default")
	Dock.RestoreLast()
	hook.Run("SPeditor_UIBuilt")
end

---------------------------------------------------------------------
-- Mod pages (MOD:AddPage, sh_mods.lua)
---------------------------------------------------------------------
function UI.BuildModPage(pg, host)
	local page = vgui.Create("DPanel")
	page.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
	end
	if host then
		host:AddSheet(SPeditor.Mods.PageTitle(pg), page, pg.icon or "icon16/plugin.png", pg.id)
	end
	local ok, err = pcall(pg.build, page, host)
	if not ok then
		ErrorNoHalt("[SPeditor mods] " .. pg.mod.id .. ": page " .. pg.id .. ": " .. tostring(err) .. "\n")
		UI.Label(page, tostring(err), COL.ORANGE)
	end
	return page
end

-- Show a mod page; a floating page is created on first use
function UI.ShowModPage(id)
	if Dock.ShowPage(id) then return true end
	for _, pg in ipairs(SPeditor.Mods.pages) do
		if pg.id == id then
			local w, h = pg.w or 520, pg.h or 400
			local win, body = Dock.Create({ key = "mod_" .. id, id = id, title = SPeditor.Mods.PageTitle(pg), w = w, h = h,
					x = math.floor(ScrW() / 2 - w / 2), y = 120, dockable = true, floating = true, icon = pg.icon or "icon16/plugin.png" })
			local ok, err = pcall(pg.build, body, win)
			if not ok then ErrorNoHalt("[SPeditor mods] " .. pg.mod.id .. ": page " .. id .. ": " .. tostring(err) .. "\n") end
			return true
		end
	end
	return false
end

function UI.Close()
	if #Dock.windows > 0 then Dock.SaveLast() end
	setKeyboardInput(false)
	Dock.Clear()
	if IsValid(UI.ColorPopup) then UI.ColorPopup:Remove() end
	for _, name in ipairs({ "TopBar", "HintBar", "EmptyHint" }) do
		if IsValid(UI[name]) then UI[name]:Remove() end
		UI[name] = nil
	end
	UI.LeftPanel, UI.BottomWin, UI.PrimaryVP, UI.SecondaryVP, UI.BrowserFrame, UI.RenderWin, UI.ObjectTree = nil, nil, nil, nil, nil, nil, nil
	gui.EnableScreenClicker(false)
	restoreCursor()
	hook.Remove("Think", "SPeditor.ComboRefresh")
	C.fullbright = false
end

-- Rebuild the interface without losing the editor state. Needed on a theme change:
-- widgets remember colours and the skin when created, so the windows are created anew,
-- but the modes (fullbright) and the open auxiliary windows stay as they were.
local REOPEN = {
	render  = function(arg) UI.OpenRenderDialog(arg) end,
	props   = function(arg) UI.OpenObjectProps(arg) end,
	about   = function() UI.OpenAbout() end,
	camset  = function() UI.OpenCameraSettings() end,
	hotkeys = function() UI.OpenHotkeys() end,
	browser = function() UI.BuildBrowser() end,
	shaders_win = function(arg) UI.OpenShaders(arg) end,
	mods    = function() UI.OpenMods() end,
	notifylog = function() UI.OpenNotifyLog() end,
	uisettings = function(arg) UI.OpenSettings(arg) end,
	adopt = function() UI.OpenAdopt() end,
}

function UI.Rebuild()
	local fullbright = C.fullbright
	local extra = {}
	for key in pairs(REOPEN) do
		local w = Dock.ByKey(key)
		if IsValid(w) and w:IsVisible() then
			local x, y = w:GetPos()
			extra[#extra + 1] = { key = key, x = x, y = y, w = w:GetWide(), h = w:GetTall(), arg = w.SPState and w.SPState() or nil }
		end
	end
	UI.Open()
	C.fullbright = fullbright
	for _, e in ipairs(extra) do
		local ok, err = pcall(REOPEN[e.key], e.arg)
		if not ok then ErrorNoHalt("[SPeditor] reopen " .. e.key .. ": " .. tostring(err) .. "\n") end
		local w = Dock.ByKey(e.key)
		if IsValid(w) then
			w:SetPos(e.x, e.y)
			w:SetSize(e.w, e.h)
		end
	end
end

SPeditor.OpenUI  = function() UI.Open()  end
SPeditor.CloseUI = function() UI.Close() end
concommand.Add("speditor", function() UI.Open() end)
