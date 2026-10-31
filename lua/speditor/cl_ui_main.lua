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
local K    = C.Keys
local L    = SPeditor.L
local Dock = SPeditor.Dock
local COL  = UI.PAL

local MENU_H, STATUS_H = 24, 20

-- "h:mm:ss:ff" of a time in seconds, frames at the animation's rate (SFM's timecode). Negative
-- times (before the animation's start) get a minus.
function UI.Timecode(t)
	local SA = SPeditor.Component and SPeditor.Component("saeditor").SA
	local fps = math.max(SA and SA.fps or 24, 1)
	local neg = t < 0
	local f = math.floor(math.abs(t) * fps + 0.5)
	local sec = math.floor(f / fps)
	return string.format("%s%d:%02d:%02d:%02d", neg and "-" or "", math.floor(sec / 3600), math.floor(sec / 60) % 60, sec % 60, f % fps)
end

local function metrics() MENU_H, STATUS_H = UI.S(24), UI.S(20) end
metrics()
SPeditor.Hook("SPeditor_FontsCreated", "SPeditor.MainMetrics", metrics)

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

SPeditor.Hook("OnTextEntryGetFocus", "SPeditor.TextFocus", function()
	if C.active then setKeyboardInput(true) end
end)
SPeditor.Hook("OnTextEntryLoseFocus", "SPeditor.TextFocus", function()
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

-- Opens a menu of the menu bar by its language key ("menu_view"), as if it was clicked (b0.2.5,
-- the links of About → What's new)
function UI.OpenTopMenu(key)
	local b = UI.TopMenus and UI.TopMenus[L(key)]
	if IsValid(b) then b:DoClick() return true end
	return false
end

function UI.PageShown(id)
	local pg = Dock.pages[id]
	return pg ~= nil and IsValid(pg.panel) and pg.panel:IsVisible() and IsValid(pg.win) and pg.win:IsVisible()
end

SPeditor.Hook("HUDPaintBackground", "SPeditor.Blackout", function()
	if not C.active or C.hideUI then return end
	if not UI.PageShown("primary") then return end
	surface.SetDrawColor(0, 0, 0, 255)
	surface.DrawRect(0, 0, ScrW(), ScrH())
end)

---------------------------------------------------------------------
-- How often the Secondary Viewport draws a new picture (b0.2): every frame, when the scene
-- changes, or once in so many seconds. Each picture is a whole render of the scene, so a
-- second view that only shows a camera's framing need not cost one every frame.
--   0 — every frame; -1 — when something changes; N > 0 — every N seconds
---------------------------------------------------------------------
local cvVp2 = CreateClientConVar("gmfm_vp2_refresh", "-1", true, false,
	"Secondary Viewport: 0 — a new picture every frame, -1 — when the scene changes, N — every N seconds")
UI.VP2_REFRESH = { 0, 0.0333, 0.0667, -1, 1, 5, 10, 30, 60 }

function UI.Vp2RefreshText(v)
	if v == 0 then return L("vp2_every_frame") end
	if v < 0 then return L("vp2_on_change") end
	if v < 1 then return string.format(L("vp2_per_second"), math.Round(1 / v)) end
	if v >= 60 then return string.format(L("vp2_every_min"), math.Round(v / 60)) end
	return string.format(L("vp2_every_sec"), v)
end

function UI.Vp2RefreshMenu(m)
	local sub = m:AddSubMenu(L("vp2_refresh"))
	local cur = cvVp2:GetFloat()
	for _, v in ipairs(UI.VP2_REFRESH) do
		sub:AddOption(UI.Vp2RefreshText(v), function() RunConsoleCommand("gmfm_vp2_refresh", tostring(v)) end)
			:SetChecked(math.abs(cur - v) < 0.001)
	end
	sub:AddSpacer()
	sub:AddOption(L("vp2_now"), function() UI.vp2Force = true end):SetIcon("icon16/arrow_refresh.png")
end

-- a cheap sum of what the picture shows: the objects' places, the lights, the bones of the
-- ragdolls, the camera of the view, the frame of the animation
local function sceneSig(src, pw, ph)
	local s, n = 0, 0
	local function v(x, k) s = s + (x.x * 1.31 + x.y * 1.73 + x.z * 2.17) * k end
	local function a(x, k) s = s + (x.p * 0.71 + x.y * 0.97 + x.r * 1.13) * k end
	for i, e in ipairs(C.Objects()) do
		if IsValid(e) then
			n = n + 1
			v(e:GetPos(), i)
			a(e:GetAngles(), i)
			if C.IsLight(e) then
				local c = e:GetLightColor()
				s = s + (e:GetLightBrightness() * 3.1 + e:GetLightRadius() * 0.37 + e:GetLightFOV() * 0.53 + c.x * 5 + c.y * 7 + c.z * 11) * i
			elseif C.IsRagdoll(e) then
				for b = 0, math.min(e:GetBoneCount(), 24) - 1 do
					local bp = e:GetBonePosition(b)
					if bp then v(bp, i + b * 0.01) end
				end
			end
		end
	end
	v(src.origin, 101)
	a(src.angles, 103)
	local SA = SPeditor.Component and SPeditor.Component("saeditor").SA
	return string.format("%d|%.3f|%.2f|%d|%d|%s|%.2f|%s", n, s, src.fov or 0, pw, ph, tostring(src.ent), SA and SA.frame or 0,
		tostring(C.fullbright))
end

local vp2 = { sig = nil, at = 0 }
SPeditor.Hook("SPeditor_HistoryPushed", "SPeditor.Vp2", function() vp2.sig = nil end)
SPeditor.Hook("SPeditor_HistoryStep", "SPeditor.Vp2", function() vp2.sig = nil end)

-- While something moves (playback, a drag) "on a change" draws a new picture this often, not every
-- frame (b0.2.2): each picture is a whole view of the map, and on a big map the second view of
-- every frame halved the frame rate of playback. "Every frame" (0) still draws every frame.
local VP2_BUSY = 0.125

-- b0.2.4: "the Secondary Viewport is laggy" (Workshop) — at 8 pictures a second it was, also
-- where the game had frames to spare. While the game keeps a good frame rate, moving pictures
-- (this viewport, the Render window preview) are drawn every frame; when it drops, they go back
-- to a few a second. The rate is smoothed and has two thresholds, so it does not flicker.
local smoothFT, fastNow = 1 / 60, true
SPeditor.Hook("Think", "SPeditor.FrameRate", function()
	smoothFT = smoothFT + (math.min(RealFrameTime(), 0.25) - smoothFT) * 0.05
	if fastNow and smoothFT > 1 / 35 then fastNow = false
	elseif not fastNow and smoothFT < 1 / 50 then fastNow = true end
end)
function UI.FrameRateGood() return fastNow end

-- true: the Secondary Viewport keeps its last picture this frame
local function vp2Frozen(src, pw, ph)
	local mode = cvVp2:GetFloat()
	if mode == 0 or UI.vp2Force then
		UI.vp2Force = nil
		vp2.sig, vp2.at = nil, RealTime()
		return false
	end
	local now = RealTime()
	if mode > 0 then
		-- another camera or another size of the window: at once
		local key = tostring(src.ent) .. "|" .. pw .. "x" .. ph
		if now - vp2.at < mode and key == vp2.key then return true end
		vp2.at, vp2.key = now, key
		return false
	end
	-- on a change: anything dragged (gizmo, slider, camera) counts as one, the rest is compared
	local SA = SPeditor.Component and SPeditor.Component("saeditor").SA
	if C.gizmo.drag or input.IsMouseDown(MOUSE_LEFT) or (SA and SA.playing) then
		vp2.sig = nil
		if not fastNow and now - vp2.at < VP2_BUSY then return true end
		vp2.at = now
		return false
	end
	local sig = sceneSig(src, pw, ph)
	if sig == vp2.sig then return true end
	vp2.sig = sig
	return false
end

---------------------------------------------------------------------
-- Viewport
---------------------------------------------------------------------
local function buildViewport(title, key, pass)
	local win, body = Dock.Create({ key = key, id = key, title = title, w = 600, h = 450, dockable = true,
			icon = "icon16/monitor.png" })
	win.minW, win.minH = UI.S(220), UI.S(160)
	-- the viewport state is kept on the page: the tab can be moved to another window
	local vp = body
	vp.pass = pass

	-- header: camera and FOV on the left, scene and frame in the centre, the timecode on the right
	-- (a0.9, as SFM: hours:minutes:seconds:frame of the scene time)
	local head = vgui.Create("DPanel", body)
	head:Dock(TOP)
	-- two lines of text in the centre: the strip is not lower than they are (fonts stop at 8 px)
	surface.SetFont("SPeditor.Small")
	local lineH = select(2, surface.GetTextSize("Ay"))
	head:SetTall(math.max(UI.S(34), lineH * 2 + 4))
	head.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
		local src = vp.GetSource and vp.GetSource() or nil
		local label = src and src.label or L("no_camera")
		draw.SimpleText(label, "SPeditor.Time", 8, h / 2, COL.TIMECODE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		surface.SetFont("SPeditor.Time")
		local x = 8 + surface.GetTextSize(label) + 12
		if src then
			local fov = string.format("FOV %d°", math.Round(src.fov or 75))
			draw.SimpleText(fov, "SPeditor.Small", x, h / 2, COL.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			surface.SetFont("SPeditor.Small")
			x = x + surface.GetTextSize(fov) + 12
		end
		-- a camera that records its own moves: a red REC beside its name
		if src and C.CameraRecords(src.ent) and math.floor(RealTime() * 2) % 2 == 0 then
			draw.SimpleText("● REC", "SPeditor.Time", x, h / 2, Color(230, 60, 50), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		local rw, rh = C.GetRenderSize()
		local scene = (C.sceneName and C.sceneName ~= "") and C.sceneName or L("untitled")
		local frame = string.format("%s  ·  %d×%d", SPeditor.LN("aspect_", C.GetAspectDef().name), rw, rh)
		local tc = UI.Timecode(C.SceneTime())
		surface.SetFont("SPeditor.Time")
		local tcW = surface.GetTextSize(tc)
		-- the scene and the frame stay in the middle, move right when the camera name reaches
		-- them (a big interface scale, a narrow viewport) and are left out when there is no room
		surface.SetFont("SPeditor.Small")
		local cw = math.max(surface.GetTextSize(scene), surface.GetTextSize(frame))
		local cx = math.max(w / 2, x + cw / 2)
		if cx + cw / 2 <= w - tcW - 20 then
			draw.SimpleText(scene, "SPeditor.Small", cx, h / 2 - lineH / 2, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			draw.SimpleText(frame, "SPeditor.Small", cx, h / 2 + lineH / 2, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		draw.SimpleText(tc, "SPeditor.Time", w - 8, h / 2, COL.TIMECODE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	-- toolbar at the bottom
	local bar = vgui.Create("DPanel", body)
	bar:Dock(BOTTOM)
	bar:SetTall(UI.S(28))
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
		C.SetIK(not C.gizmo.ik)
		if C.gizmo.ik then SPeditor.Notify(L("ik_hint"), 0) end
	end, function() return C.gizmo.ik end)
	-- the character rig (a0.9, cl_rig.lua)
	UI.IconButton(bar, "icon16/user_suit.png", L("rig_hint") .. " (" .. C.Keys.Text("rig") .. ")", function()
		C.SetRig(not C.RigOn())
		if C.RigOn() then SPeditor.Notify(L("rig_hint"), 0) end
	end, function() return C.RigOn() end)
	local stretchBtn = UI.IconButton(bar, "icon16/arrow_out.png", L("stretch_hint") .. " (" .. C.Keys.Text("stretch") .. ")", function()
		C.SetStretch(not C.gizmo.stretch)
		if C.gizmo.stretch then SPeditor.Notify(L("stretch_hint"), 0) end
	end, function() return C.gizmo.stretch end)
	stretchBtn.SPThemeKey = false          -- not the move picture of a theme

	local sep = vgui.Create("DPanel", bar)
	sep:Dock(LEFT)
	sep:DockMargin(6, 6, 4, 6)
	sep:SetWide(UI.S(1))
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
	if pass == "primary" then
		-- the frame as the render makes it (cl_render.lua, R.LookOn)
		UI.IconButton(bar, "icon16/photo.png", L("vp_look"), function()
			local R = SPeditor.Render
			local on = not R.LookOn()
			R.SetLook(on)
			SPeditor.Notify(on and "#vp_look_on_hint" or "#vp_look_off_hint", 0)
		end, function() return SPeditor.Render.LookOn() end)
		-- the camera looked through records its own moves (C.CameraRecords)
		UI.IconButton(bar, "icon16/bullet_red.png", L("cam_rec"), function()
			local cam = C.GetViewCamera() or (C.IsCamera(C.selected) and C.selected or nil)
			if not IsValid(cam) then SPeditor.Notify("#cam_rec_need", 0) return end
			C.SetCameraRecords(cam, not C.CameraRecords(cam))
		end, function()
			local cam = C.GetViewCamera() or (C.IsCamera(C.selected) and C.selected or nil)
			return C.CameraRecords(cam)
		end)
	end

	local gear = UI.IconButton(bar, "icon16/cog.png", L("col_settings"), function()
		local m = SPeditor.UI.Menu()
		m:AddOption(L("gear_focus"), function() C.FocusSelected() end)
		m:AddOption(L("cam_settings") .. "…", function() UI.OpenCameraSettings() end)
		m:AddOption(L("act_render") .. "…", function() UI.OpenRenderDialog() end)
		UI.ExposureMenu(m)
		if pass == "secondary" then UI.Vp2RefreshMenu(m) end
		local asp = m:AddSubMenu(L("menu_aspect"))
		if pass == "secondary" then
			-- its own proportions, or those of the Primary Viewport (the render's)
			local own = C.GetAspectDef2()
			asp:AddOption(L("aspect_same"), function() C.SetAspect2("") end):SetChecked(own == nil)
			asp:AddSpacer()
			for _, a in ipairs(SPeditor.Aspects) do
				asp:AddOption(SPeditor.LN("aspect_", a.name), function() C.SetAspect2(a.id) end):SetChecked(own ~= nil and own.id == a.id)
			end
		else
			for _, a in ipairs(SPeditor.Aspects) do
				asp:AddOption(SPeditor.LN("aspect_", a.name), function()
					RunConsoleCommand("gmfm_render_custom", "0")
					C.SetAspect(a.id)
				end):SetChecked(C.GetAspectDef().id == a.id)
			end
		end
		m:AddSpacer()
		m:AddOption(L("gear_hide"), function() local pg = Dock.pages[key] if pg and IsValid(pg.win) then pg.win:Close() end end)
		m:Open()
	end, nil, RIGHT)
	gear:DockMargin(2, 3, 4, 3)

	local combo = UI.StyleCombo(vgui.Create("DComboBox", bar))
	combo:Dock(RIGHT)
	combo:DockMargin(2, 4, 2, 4)
	combo:SetWide(UI.S(140))
	vp.combo = combo

	-- a narrow viewport (the Secondary one): the left buttons that would go under the camera
	-- list and the gear are hidden, from the end, instead of being drawn beneath them (b0.2:
	-- SFM's button shells made the row wider)
	bar.PerformLayout = function(s, w)
		local right = 0
		for _, c in ipairs(s:GetChildren()) do
			if c:GetDock() == RIGHT then
				local l, _, r = c:GetDockMargin()
				right = right + c:GetWide() + l + r
			end
		end
		local x, room = 0, w - right - 4
		for _, c in ipairs(s:GetChildren()) do
			if c:GetDock() == LEFT then
				local l, _, r = c:GetDockMargin()
				x = x + c:GetWide() + l + r
				local fits = x <= room
				if c:IsVisible() ~= fits then c:SetVisible(fits) end
			end
		end
	end

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
			-- the refresh setting of the Secondary Viewport (gmfm_vp2_refresh)
			if vp.pass == "secondary" and not frozen then frozen = vp2Frozen(src, pw, ph) end
			local ix, iy, iw, ih = SPeditor.Render.Viewport(src, pw, ph, vp.pass or "primary", frozen)
			if ix then C.DrawGuides(ix, iy, iw, ih) end
			-- the focal distance while it is changed (b0.2.6, as SFM; cl_camera.lua)
			if ix and C.DrawFocusLabel then C.DrawFocusLabel(src.ent, ix, iy, iw, ih) end
			-- the selection box (cl_gizmo.lua)
			if vp.pass == "primary" and C.DrawMarquee then C.DrawMarquee(vp.view:LocalToScreen(0, 0)) end
			-- labels and hints of other parts over the frame (b0.2.1: the NPCs of a take)
			if vp.pass == "primary" and ix then hook.Run("GMFM_ViewportOverlay", vp.view, ix, iy, iw, ih) end
			if ix and frozen and UI.PageShown("render") then
				draw.SimpleTextOutlined(L("vp_paused"), "SPeditor.Small", ix + 8, iy + 6, COL.ORANGE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
			end
		elseif not src then
			draw.SimpleText(L("no_camera"), "SPeditor.Time", pw / 2, ph / 2, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	-- wheel over the frame: move the work camera closer / farther (as in SFM)
	if pass == "primary" then
		view.OnMouseWheeled = function(_, delta)
			-- a placing tool turns what it places
			if C.placeTool and C.placeTool.wheel then
				C.placeTool.wheel(delta)
				return true
			end
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
	UI.StyleListView(list)
	list:Dock(FILL)
	list:AddColumn(L("help_key")):SetFixedWidth(230)
	list:AddColumn(L("help_action"))
	if list.SetBackgroundColor then list:SetBackgroundColor(COL.LIST_BG) end
	local function keys(...)
		local out = {}
		for _, id in ipairs({ ... }) do
			local t = K.Text(id)
			if t ~= "" then out[#out + 1] = t end
		end
		return #out > 0 and table.concat(out, " / ") or "—"
	end
	local function fill()
		list:Clear()
		local fly = keys("fly_forward", "fly_left", "fly_back", "fly_right")
		for _, row in ipairs({
					{ L("key_lmb"), "help_select" }, { L("key_rmb"), "help_rmb" },
					{ L("key_rmb") .. " + " .. fly .. " / " .. keys("fly_up", "fly_down"), "help_fly" },
					{ "Alt + " .. L("key_lmb"), "help_orbit" }, { L("key_wheel"), "help_dolly" }, { "Alt + " .. L("key_wheel"), "help_fov" },
					{ keys("gizmo_move", "gizmo_rotate", "gizmo_scale"), "help_move_rotate" }, { keys("gizmo_space"), "help_space" },
					{ keys("select_add", "select_add2"), "help_multi" }, { keys("ik"), "help_ik" }, { keys("stretch"), "help_stretch" },
					{ keys("focus"), "help_focus" }, { keys("camview"), "help_camview" }, { keys("skeleton"), "help_skeleton" }, { keys("delete"), "obj_delete" },
					{ keys("duplicate"), "obj_duplicate" }, { keys("list_select_all", "list_copy", "list_paste"), "help_list_keys" }, { keys("pose_copy", "pose_paste"), "help_pose_clip" }, { keys("undo", "redo", "redo2"), "help_undo" },
					{ "Shift + " .. L("key_drag"), "help_fine" },
					{ L("help_dock_key"), "help_dock" }, { L("help_max_key"), "dock_maximize" },
					{ L("help_props_key"), "dock_props" },
			}) do
			list:AddLine(row[1], L(row[2]))
		end
		-- component keys
		for _, h in ipairs(SPeditor.Components.hotkeys) do
			if h.desc then
				local b = K.Get("comp:" .. h.id)
				-- the component's own caption of its default key ("Space"), otherwise the key name
				local text = (h.label and K.Same(b, K.Default("comp:" .. h.id))) and h.label or K.BindText(b)
				list:AddLine(text ~= "" and text or "—", L(h.desc) .. "")
			end
		end
	end
	fill()
	-- keys changed in Interface settings: the list follows (the hook goes away with the list)
	SPeditor.Hook("SPeditor_KeysChanged", list, function() fill() end)
	-- the keys are changed in Interface settings
	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(32))
	foot.Paint = function() end
	local change = vgui.Create("DButton", foot)
	change:Dock(LEFT)
	change:DockMargin(6, 4, 4, 4)
	surface.SetFont("SPeditor.Small")
	change:SetWide(select(1, surface.GetTextSize(L("keys_change"))) + UI.S(40))
	change:SetText("  " .. L("keys_change"))
	change:SetIcon("icon16/keyboard.png")
	UI.StyleButton(change, nil, 3)
	change.DoClick = function()
		win:Close()
		UI.OpenSettings("keys")
	end
end

---------------------------------------------------------------------
-- Opening / closing
---------------------------------------------------------------------
function UI.Open()
	UI.Close()
	UI.ApplyTheme(GetConVar("gmfm_theme"):GetString(), true)
	UI.ScaleDermaFonts(true)
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
		b:SetWide(select(1, surface.GetTextSize(label)) + UI.S(18))
		b:SetText(label)
		b:SetFont("SPeditor.Small")
		b:SetTextColor(UI.ChromeText("MenuBar") or COL.TEXT)
		b.Paint = function(s, w, h) UI.PaintChrome("MenuButton", s, w, h) end
		UI.TopMenus = UI.TopMenus or {}
		UI.TopMenus[label] = b
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
		-- b0.2.6: SFM's Export Poster — a still refined pass by pass
		m:AddOption(L("poster_title") .. "…", function() UI.OpenPoster() end):SetIcon("icon16/picture.png")
		-- b0.2: SFM's Export Shot List
		local SAc = SPeditor.Component("saeditor").SA
		if SAc and SAc.ExportShotList then
			m:AddOption(L("sa_shots_export"), function() SAc.ExportShotList() end):SetIcon("icon16/page_white_text.png")
		end
		m:AddOption(L("adopt_title") .. "…", function() UI.OpenAdopt() end):SetIcon("icon16/world_add.png")
		m:AddOption(L("files_title") .. "…", function() UI.OpenFileLocations() end):SetIcon("icon16/folder_explore.png")
		m:AddOption(L("autosave"), function()
			RunConsoleCommand("gmfm_autosave", GetConVar("gmfm_autosave"):GetBool() and "0" or "1")
		end):SetChecked(GetConVar("gmfm_autosave"):GetBool())
		m:AddSpacer()
		m:AddOption(L("act_clear"), function()
			Derma_Query(L("clear_confirm"), "GM:FM", L("yes"), function() C.ClearScene() end, L("cancel"), function() end)
		end):SetIcon("icon16/bin.png")
		SPeditor.Components.RunMenu("file", m)
		m:AddSpacer()
		-- the GM:FM gamemode (b0.2.1): the editor is the game, there is nothing to exit to —
		-- another map or the main menu instead
		if SPeditor.FilmMode() then
			m:AddOption(L("mode_start") .. "…", function() UI.OpenModeStart() end):SetIcon("icon16/application_home.png")
			m:AddOption(L("mode_change_map") .. "…", function() UI.OpenMapPicker() end):SetIcon("icon16/world.png")
			m:AddOption(L("mode_disconnect"), function() RunConsoleCommand("disconnect") end):SetIcon("icon16/door_out.png")
		else
			m:AddOption(L("act_exit"), function() RunConsoleCommand("gmfm_toggle") end):SetIcon("icon16/door_out.png")
		end
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
		keyed(m, L("edit_undo"), K.Text("undo"), function() C.Undo() end):SetIcon("icon16/arrow_undo.png")
		keyed(m, L("edit_redo"), K.Text("redo"), function() C.Redo() end):SetIcon("icon16/arrow_redo.png")
		m:AddSpacer()
		keyed(m, L("obj_duplicate"), K.Text("duplicate"), function() C.DuplicateSelection() end)
		keyed(m, L("obj_delete"), K.Text("delete"), function() C.DeleteSelection() end)
		-- SFM's Delete Models Outside Camera Frustum, as a selection first (b0.2.1)
		m:AddOption(L("edit_select_outside"), function() C.SelectOutsideCameras() end):SetIcon("icon16/shape_square_select.png")
		m:AddOption(L("props_open"), function()
			if IsValid(C.selected) and not C.IsAux(C.selected) then UI.OpenObjectProps(C.selected) end
		end):SetIcon("icon16/wrench.png")
		m:AddSpacer()
		keyed(m, L("pose_copy"), K.Text("pose_copy"), function() C.CopyPose(C.selected) end)
		keyed(m, L("pose_paste"), K.Text("pose_paste"), function() C.PastePose(C.selected) end)
		m:AddOption(L("drop_floor"), function() if IsValid(C.selected) then C.SendDropToFloor(C.selected) end end)
		m:AddOption(L("reset_rotation"), function() C.ResetRotation() end):SetIcon("icon16/arrow_rotate_anticlockwise.png")
		m:AddSpacer()
		local cr = m:AddSubMenu(L("menu_create"))
		cr:AddOption(L("ase_add_model"), function() UI.ToggleBrowser() end)
		cr:AddOption(L("act_spawn_camera"), function() C.SendCameraSpawn(C.camera.pos, C.camera.ang) end)
		cr:AddOption(L("spawn_spot"), function() UI.SpawnLight(1) end)
		cr:AddOption(L("spawn_point"), function() UI.SpawnLight(0) end)
		UI.LightKindMenu(cr)
		cr:AddOption(L("eff_add"), function() UI.ToggleEffects() end)
		cr:AddOption(L("rig_make"), function() C.SpawnLightRig(C.selected) end)
		SPeditor.Components.RunMenu("create", cr)
		m:AddSpacer()
		keyed(m, L("edit_select_all"), K.Text("select_all"), function() C.SelectAll() end)
		keyed(m, L("keys_list_copy"), K.Text("list_copy"), function() C.CopyObjects() end)
		keyed(m, L("keys_list_paste"), K.Text("list_paste"), function() C.PasteObjects() end)
		m:AddOption(L("edit_deselect"), function() C.Select(nil) end)
		SPeditor.Components.RunMenu("edit", m)
	end)

	mbtn(L("menu_windows"), function(m)
		for _, id in ipairs({ "ase", "ev", "primary", "secondary", "scene", "shadows" }) do
			local page = Dock.pages[id]
			if page then m:AddOption(page.title, function() Dock.ShowPage(id) end) end
		end
		m:AddOption(L("win_browser"), function() UI.ToggleBrowser() end)
		m:AddOption(L("win_ref"), function() UI.OpenRef() end):SetIcon("icon16/film.png")
		m:AddOption(L("render_title"), function() UI.OpenRenderDialog() end)
		m:AddOption(L("shaders_title"), function() UI.OpenShaders() end):SetIcon("icon16/wand.png")
		m:AddOption(L("env_title"), function() UI.OpenEnvironment() end):SetIcon("icon16/weather_sun.png")
		-- component pages (COMP:AddPage)
		for _, pg in ipairs(SPeditor.Components.pages) do
			m:AddOption(SPeditor.Components.PageTitle(pg), function() UI.ShowCompPage(pg.id) end):SetIcon(pg.icon or "icon16/application.png")
		end
		SPeditor.Components.RunMenu("windows", m)
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
		-- b0.1: the gizmo and the rig can be made smaller and thinner (posing a face close up)
		local function sizeMenu(title, list, cvar, cur, names)
			local sm = m:AddSubMenu(L(title))
			for i, v in ipairs(list) do
				sm:AddOption(L(names .. i), function() RunConsoleCommand(cvar, tostring(v)) end):SetChecked(math.abs(cur() - v) < 0.01)
			end
			return sm
		end
		local WIDTHS = { 0.5, 1, 1.6 }
		local gs = sizeMenu("view_gizmo_size", C.GIZMO_SIZES, "gmfm_gizmo_size", C.GetGizmoSize, "gizmo_size_")
		gs:AddSpacer()
		for i, v in ipairs(WIDTHS) do
			gs:AddOption(L("line_width_" .. i), function() RunConsoleCommand("gmfm_gizmo_width", tostring(v)) end):SetChecked(math.abs(C.GetGizmoWidth() - v) < 0.01)
		end
		if C.RIG_SIZES then
			local rs = sizeMenu("view_rig_size", C.RIG_SIZES, "gmfm_rig_size", C.GetRigSize, "rig_size_")
			rs:AddSpacer()
			for i, v in ipairs(WIDTHS) do
				rs:AddOption(L("line_width_" .. i), function() RunConsoleCommand("gmfm_rig_width", tostring(v)) end):SetChecked(math.abs(C.GetRigWidth() - v) < 0.01)
			end
			rs:AddSpacer()
			rs:AddOption(L("rig_rings"), function() RunConsoleCommand("gmfm_rig_rings", C.RigRings() and "0" or "1") end):SetChecked(C.RigRings())
		end
		m:AddOption(L("view_camview"), function()
			if C.GetViewCamera() then C.StopViewCamera()
			elseif C.IsCamera(C.selected) then C.StartViewCamera(C.selected) end
		end)
		m:AddOption(L("view_space"), function() C.gizmo.space = (C.gizmo.space == "world") and "local" or "world" end)
		-- SFM's Auto Aim Work Camera (b0.2.1)
		m:AddOption(L("view_autoaim"), function() RunConsoleCommand("gmfm_autoaim", C.AutoAim() and "0" or "1") end)
			:SetChecked(C.AutoAim())
		-- the near clipping plane of the work camera (b0.2.2); a scene camera has its own (ASE)
		local zn = m:AddSubMenu(L("view_znear"))
		local cur = GetConVar("gmfm_znear"):GetFloat()
		for _, v in ipairs({ 0.5, 1, 2, 3, 4, 7, 16 }) do
			zn:AddOption(string.format(L("view_znear_n"), v), function() RunConsoleCommand("gmfm_znear", tostring(v)) end)
				:SetChecked(math.abs(cur - v) < 0.01)
		end
		-- steps of the gizmo while the snap key is held (b0.2.3)
		local sn = m:AddSubMenu(string.format(L("view_snap"), C.Keys.Text("snap")))
		-- b0.2.5: steps without holding the key; the key then frees the gizmo
		sn:AddOption(string.format(L("view_snap_always"), C.Keys.Text("snap")), function() C.SetSnapAlways(not C.SnapAlways()) end)
			:SetChecked(C.SnapAlways())
		sn:AddSpacer()
		local function steps(cv, list, fmt)
			local now = GetConVar(cv):GetFloat()
			for _, v in ipairs(list) do
				sn:AddOption(string.format(L(fmt), v), function() RunConsoleCommand(cv, tostring(v)) end)
					:SetChecked(math.abs(now - v) < 0.001)
			end
		end
		steps("gmfm_snap_move", { 1, 2, 4, 5, 8, 10, 16, 32, 64 }, "view_snap_move")
		sn:AddSpacer()
		steps("gmfm_snap_rot", { 5, 10, 15, 22.5, 30, 45, 90 }, "view_snap_rot")
		sn:AddSpacer()
		steps("gmfm_snap_scale", { 0.05, 0.1, 0.25, 0.5 }, "view_snap_scale")
		m:AddOption(L("ik_feet"), function() C.SetIKFeet(not C.gizmo.ikFeet) end):SetChecked(C.gizmo.ikFeet and true or false)
		m:AddOption(L("ik_hands"), function() C.SetIKHands(not C.gizmo.ikHands) end):SetChecked(C.gizmo.ikHands and true or false)
		-- ambient occlusion in the viewports (b0.2.6, gmfm_vp_ssao)
		local ao = m:AddSubMenu(L("view_vp_ao"))
		local cur = SPeditor.Render.ViewportAOMode and SPeditor.Render.ViewportAOMode() or 1
		for i = 0, 2 do
			ao:AddOption(L("view_vp_ao_" .. i), function() RunConsoleCommand("gmfm_vp_ssao", tostring(i)) end):SetChecked(cur == i)
		end
		local ul = m:AddOption(L("view_unlock"), function() UI.SetLimitsUnlocked(not UI.LimitsUnlocked()) end)
		ul:SetChecked(UI.LimitsUnlocked())
		ul:SetTooltip(L("view_unlock_tip"))
		m:AddSpacer()
		local gsub = m:AddSubMenu(L("view_guides"))
		for _, g in ipairs(C.GUIDE_LIST) do
			gsub:AddOption(L("guide_" .. g), function() C.ToggleGuide(g) end):SetChecked(C.HasGuide(g))
		end
		local asp = m:AddSubMenu(L("menu_aspect"))
		for _, a in ipairs(SPeditor.Aspects) do
			asp:AddOption(SPeditor.LN("aspect_", a.name), function()
				RunConsoleCommand("gmfm_render_custom", "0")
				C.SetAspect(a.id)
			end):SetChecked(C.GetAspectDef().id == a.id and not GetConVar("gmfm_render_custom"):GetBool())
		end
		SPeditor.Components.RunMenu("view", m)
		m:AddSpacer()
		UI.BuildThemeMenu(m:AddSubMenu(L("menu_theme")))
		m:AddOption(L("ui_settings") .. "…", function() UI.OpenSettings() end):SetIcon("icon16/cog.png")
	end)

	mbtn(L("menu_help"), function(m)
		m:AddOption(L("guide_title") .. "…", function() UI.OpenGuide() end):SetIcon("icon16/help.png")
		m:AddOption(L("help_hotkeys"), function() UI.OpenHotkeys() end):SetIcon("icon16/keyboard.png")
		m:AddOption(L("cam_settings") .. "…", function() UI.OpenCameraSettings() end):SetIcon("icon16/camera_edit.png")
		m:AddOption(L("files_title") .. "…", function() UI.OpenFileLocations() end):SetIcon("icon16/folder_explore.png")
		local nErr = #(SPeditor.Errors and SPeditor.Errors.list or {})
		m:AddOption(L("rep_title") .. (nErr > 0 and (" (" .. nErr .. ")") or "") .. "…", function() UI.OpenReport() end):SetIcon("icon16/bug.png")
		m:AddOption(L("st_menu"), function() SPeditor.SelfTest.Run() end):SetIcon("icon16/tick.png")
		-- the interface language: the editor is rebuilt in it at once
		local lang, lo = m:AddSubMenu(L("qmenu_language"))
		if lo and lo.SetIcon then lo:SetIcon("icon16/world.png") end
		UI.LanguageMenu(lang)
		SPeditor.Components.RunMenu("help", m)
		m:AddSpacer()
		m:AddOption(L("about_title"), function() UI.OpenAbout() end):SetIcon("icon16/information.png")
	end)

	local function rightBtn(text, icon, fn, hot)
		local b = vgui.Create("DButton", top)
		b:Dock(RIGHT)
		b:DockMargin(0, 2, 4, 2)
		surface.SetFont("SPeditor.Small")
		b:SetWide(select(1, surface.GetTextSize(text)) + UI.S(34))
		b:SetText("  " .. text)
		b:SetIcon(UI.ThemedIconPath(icon))
		UI.StyleButton(b, hot, 0)
		b.DoClick = fn
		return b
	end
	if SPeditor.FilmMode() then
		rightBtn(L("mode_change_map"), "icon16/world.png", function() UI.OpenMapPicker() end)
	else
		rightBtn(L("act_exit"), "icon16/door_out.png", function() RunConsoleCommand("gmfm_toggle") end, Color(150, 60, 45))
	end
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
	-- component pages: in the bottom window, next to the ASE, or in a window of their own (on demand)
	for _, pg in ipairs(SPeditor.Components.pages) do
		if pg.window == "bottom" or pg.window == "left" then
			UI.BuildCompPage(pg, pg.window == "left" and left or bottom)
		end
	end
	left:SelectPage("ase")
	bottom:SelectPage("scene")

	SPeditor.Hook("Think", "SPeditor.ComboRefresh", function()
		if not C.active then return end
		if IsValid(UI.PrimaryVP) then refreshCombo(UI.PrimaryVP, true) end
		if IsValid(UI.SecondaryVP) then refreshCombo(UI.SecondaryVP, false) end
	end)

	-----------------------------------------------------------------
	-- Status bar
	-----------------------------------------------------------------
	local status = UI.Skin(vgui.Create("DPanel"))
	UI.StatusBar = status
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
		local modText = SPeditor.Components.StatusText()
		draw.SimpleText(modText ~= "" and modText or L("hint_short"), "SPeditor.Small", 8, h / 2, modText ~= "" and txt or dim,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local rw, rh = C.GetRenderSize()
		local sel = IsValid(C.selected) and C.DisplayName(C.selected) or "—"
		if #C.multi > 0 then sel = sel .. " (+" .. #C.multi .. ")" end
		draw.SimpleText(string.format("[ %s: %d  |  %s: %s  |  %s  |  fps: %d  |  %d×%d %s ]",
				L("grp_models"), #C.Objects(), L("st_selected"), sel,
				string.upper(L("st_" .. C.gizmo.mode)) .. (C.gizmo.ik and " + IK" or "") .. (C.gizmo.stretch and (" + " .. string.upper(L("stretch_on"))) or ""),
				fps, rw, rh, SPeditor.LN("aspect_", C.GetAspectDef().name)), "SPeditor.Small", w - 8, h / 2, dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	UI.HintBar = status

	-----------------------------------------------------------------
	-- Every window closed: the screen is empty but for the menu bar, and people did not know
	-- how to get the windows back — a card in the middle says it and restores the layout.
	-----------------------------------------------------------------
	local empty = UI.Skin(vgui.Create("DPanel"))
	empty:SetSize(math.min(UI.S(480), scrW - 40), UI.S(132))
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
	msg:SetTall(UI.S(64))
	msg:SetContentAlignment(7)
	msg:SetText(L("empty_hint"))
	local restore = vgui.Create("DButton", empty)
	restore:Dock(BOTTOM)
	restore:DockMargin(14, 0, 14, 12)
	restore:SetTall(UI.S(26))
	restore:SetText(L("empty_restore"))
	restore:SetIcon("icon16/application_side_tree.png")
	UI.StyleButton(restore, true, 3)
	restore.DoClick = function() Dock.Reset("default") end
	UI.EmptyHint = empty
	SPeditor.Hook("Think", "SPeditor.EmptyHint", function()
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
	UI.builtScale = UI.Scale()
	hook.Run("SPeditor_UIBuilt")
end

---------------------------------------------------------------------
-- Component pages (COMP:AddPage, sh_component.lua)
---------------------------------------------------------------------
function UI.BuildCompPage(pg, host)
	local page = vgui.Create("DPanel")
	page.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
	end
	if host then
		host:AddSheet(SPeditor.Components.PageTitle(pg), page, pg.icon or "icon16/application.png", pg.id)
	end
	local ok, err = pcall(pg.build, page, host)
	if not ok then
		ErrorNoHalt("[GM:FM] " .. pg.comp.name .. ": page " .. pg.id .. ": " .. tostring(err) .. "\n")
		UI.Label(page, tostring(err), COL.ORANGE)
	end
	return page
end

-- Show a component page; a floating page is created on first use
function UI.ShowCompPage(id)
	if Dock.ShowPage(id) then return true end
	for _, pg in ipairs(SPeditor.Components.pages) do
		if pg.id == id then
			local w, h = pg.w or 520, pg.h or 400
			local win, body = Dock.Create({ key = "page_" .. id, id = id, title = SPeditor.Components.PageTitle(pg), w = w, h = h,
					x = math.floor(ScrW() / 2 - w / 2), y = 120, dockable = true, floating = true, icon = pg.icon or "icon16/application.png" })
			local ok, err = pcall(pg.build, body, win)
			if not ok then ErrorNoHalt("[GM:FM] " .. pg.comp.name .. ": page " .. id .. ": " .. tostring(err) .. "\n") end
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
	for _, name in ipairs({ "TopBar", "HintBar", "EmptyHint", "StatusBar" }) do
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
	env_win = function() UI.OpenEnvironment() end,
	notifylog = function() UI.OpenNotifyLog() end,
	uisettings = function(arg) UI.OpenSettings(arg) end,
	adopt = function() UI.OpenAdopt() end,
}

function UI.Rebuild()
	local fullbright = C.fullbright
	-- the scale changed: the windows opened by hand get the size they would have at the new one
	local k = UI.Scale() / (UI.builtScale or UI.Scale())
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
		if not ok then ErrorNoHalt("[GM:FM] reopen " .. e.key .. ": " .. tostring(err) .. "\n") end
		local w = Dock.ByKey(e.key)
		if IsValid(w) then
			local ww = math.min(math.max(math.Round(e.w * k), w.minW or 0), ScrW())
			local hh = math.min(math.max(math.Round(e.h * k), w.minH or 0), ScrH() - MENU_H - STATUS_H)
			w:SetSize(ww, hh)
			w:SetPos(math.Clamp(e.x, 0, ScrW() - ww), math.Clamp(e.y, MENU_H, math.max(ScrH() - STATUS_H - hh, MENU_H)))
		end
	end
end

-- (b0.2.6) The editor's windows are not drawn while a video renders (cl_saeditor_video.lua): every
-- game frame painted all of them, a few milliseconds each, and a video frame takes several game
-- frames. They stay where they are and keep working; only their drawing is skipped.
function UI.SetPaintedForRender(on)
	if not on then
		for _, p in ipairs(UI.renderHidden or {}) do
			if IsValid(p) then p:SetPaintedManually(false) end
		end
		UI.renderHidden = nil
		return
	end
	if UI.renderHidden then return end
	local list = {}
	for _, name in ipairs({ "TopBar", "HintBar", "EmptyHint", "StatusBar" }) do
		if IsValid(UI[name]) then list[#list + 1] = UI[name] end
	end
	for _, w in ipairs(Dock.windows) do
		if IsValid(w) then list[#list + 1] = w end
	end
	for _, p in ipairs(list) do p:SetPaintedManually(true) end
	UI.renderHidden = list
end

SPeditor.OpenUI  = function() UI.Open()  end
SPeditor.CloseUI = function() UI.Close() end
concommand.Add("speditor", function() UI.Open() end)
