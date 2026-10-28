--[[
SPeditor — rendering the frame into viewports and into a file.

The frame is drawn into a render target with the needed aspect ratio (aspect gate) without
stretching. Viewports use a shared 1280x1024 RT, export uses
a separate RT sized exactly for the file.
Depth of field and soft shadows from lights with a size are computed in the final
frame by accumulating passes (R.RenderBase).

All passes go through PushRenderTarget/PopRenderTarget: per the wiki the viewport
then equals the RT size, so the code does not depend on where it is called from.

"Engine frame" (R.Engine) — a second way to shoot the scene, for Workshop shaders.
Addon effects (stock post-processing, shaders on GShader Library) draw
themselves in the main game frame and at its size; in our render targets they either do not
work or give a shifted picture. So in this mode the main game frame is
not cancelled but shot by the editor camera — with every enabled effect —
copied from the screen and cropped to the frame proportions. The price: resolution no higher
than the screen, and the editor's 2× smoothing and depth of field are unavailable.
]]
SPeditor = SPeditor or {}
SPeditor.Render = SPeditor.Render or {}
local R = SPeditor.Render
local C = SPeditor.Client
local L = SPeditor.L

-- The viewport frame is drawn into a texture as big as the screen (at least 1280 x 1024). A fixed
-- 1280 x 1024 one was stretched over big viewports on 1440p / 4K screens, and small far objects
-- came out blurry ("everything gets blurry a bit farther away").
local function vpSize()
	return math.Clamp(ScrW(), 1280, 4096), math.Clamp(ScrH(), 1024, 4096)
end

-- Frame exposure. In HDR the engine adjusts brightness to what the main
-- camera sees (auto exposure), and this adjustment is shared by all views:
-- bringing the work camera close to a lit object made both viewports and the
-- final render go dark within a couple of seconds. So before every pass
-- the exposure is fixed. 0 = auto (engine behaviour).
local cvExposure = CreateClientConVar("gmfm_exposure", "1", true, false)
R.EXPOSURES = { 0, 0.5, 0.75, 1, 1.25, 1.5, 2, 3 }

function R.GetExposure() return math.Clamp(cvExposure:GetFloat(), 0, 8) end
function R.SetExposure(v) RunConsoleCommand("gmfm_exposure", tostring(math.Clamp(v, 0, 8))) end

local targets = {}
local function getRT(name, w, h)
	local rt = targets[name]
	if not rt then
		rt = GetRenderTarget("speditor_" .. name, w, h)
		targets[name] = rt
	end
	return rt
end

-- A render target that stopped taking any drawing (found by the a0.9 self-test after a series of
-- extreme renders: exp_480x270 ignored even render.Clear and kept handing out a frame of another
-- scene, while a new target of the same size worked). Before a render the target of the frame is
-- checked — a clear to a test colour read back — at most every VERIFY_EVERY seconds per target;
-- a dead one is replaced by a new one under another name.
local VERIFY_EVERY = 2
local verified, renamed = {}, {}
local function liveRT(name, w, h)
	local key = renamed[name] or name
	local rt = getRT(key, w, h)
	local now = RealTime()
	if now - (verified[key] or -1e9) < VERIFY_EVERY then return rt end
	verified[key] = now
	render.PushRenderTarget(rt)
	render.Clear(3, 250, 7, 255, true, true)
	render.CapturePixels()
	local r, g, b = render.ReadPixel(0, 0)
	render.PopRenderTarget()
	if r == 3 and g == 250 and b == 7 then return rt end
	local n = 2
	while targets[name .. "_r" .. n] do n = n + 1 end
	key = name .. "_r" .. n
	renamed[name] = key
	-- a warning, not an error: the render goes on in the new target
	MsgC(Color(255, 190, 90), string.format("[GM:FM] render target %s stopped taking drawing; using %s\n", name, key))
	R.deadTargets = (R.deadTargets or 0) + 1
	R.deadLog = R.deadLog or {}
	local T = SPeditor.SelfTest
	table.insert(R.deadLog, { name = name, t = now, step = T and T.running and T.step or nil })
	return getRT(key, w, h)
end
R.LiveRT = liveRT

-- The material that shows the frame is OPAQUE (no $vertexalpha). The engine writes
-- depth into the alpha channel of the frame, and with alpha blending everything close to
-- the camera became translucent over the black panel: objects darkened
-- as the camera approached (even in fullbright).
local matShow = CreateMaterial("speditor_render_opaque", "UnlitGeneric", {
		["$nolod"] = "1",
})

-- GShader Library (Workshop shaders) builds its depth and normal buffers
-- in every view the game draws — including our viewports, the preview
-- and every depth-of-field pass. Its buffers are screen-sized and needed only
-- by effects of the main frame, so in the editor's own views this is wasted work
-- (measured in game: the rebuild ran in every viewport frame). For the duration of its own views
-- the editor answers the library "effects are not drawn here" through the library's own check,
-- shaderlib.CanDrawEffects; in the "engine frame" the library works as usual.
local function guardShaderLib()
	local lib = rawget(_G, "shaderlib")
	if not istable(lib) or lib.SPeditorGuard or not isfunction(lib.CanDrawEffects) then return end
	local orig = lib.CanDrawEffects
	lib.SPeditorGuard = true
	lib.CanDrawEffects = function(...)
		if R.ownView then return false end
		return orig(...)
	end
end

-- The editor's helper graphics (gizmo, skeleton, selection frames, light and camera
-- wireframes) are drawn with the "colour" material, with colour in the vertices. In fullbright
-- (render.SetLightingMode(1)) the engine ignores vertex colour: the gizmo axes and bone
-- markers all turned the same white. So for such drawing the lighting mode
-- goes back to regular and is switched on again afterwards.
-- local restore = R.HelperLighting()   ...draw...   restore()
local function noop() end
function R.HelperLighting()
	if not R.fullbrightView then return noop end
	render.SetLightingMode(0)
	return function() render.SetLightingMode(1) end
end

-- Fullbright (a0.9): render.SetLightingMode(1) makes only the map flat — props and ragdolls
-- were still lit from one side, shaded and shiny, and the scene's lights still lit and shaded
-- them. For a fullbright view the models get the same light from every side and the lights of
-- the scene are put out (cl_lights.lua). R.Fullbright(true) before the view, (false) after it.
local flatModels = false
-- b0.1: the light set before the opaque pass did not reach the models on some maps (measured on
-- gm_bigcity_dusk: every character black, with or without other addons' hooks), while the same
-- light set right before a model's own draw did. So while a fullbright view may be drawn (the
-- editor's fullbright or the render's) every model without a draw of its own gets one that sets
-- the flat light first in a fullbright view and draws as usual in any other. It has to be in
-- place a frame ahead: a RenderOverride set right before a view is not used by that view.
local flatWrapped = {}
local function flatDraw(self, flags)
	if not flatModels then
		self:DrawModel(flags)
		return
	end
	render.SuppressEngineLighting(true)
	render.ResetModelLighting(1, 1, 1)
	render.SetLocalModelLights({})
	self:DrawModel(flags)
	render.SuppressEngineLighting(false)
end
local function unwrapAll()
	for e in pairs(flatWrapped) do
		local t = IsValid(e) and e:GetTable()
		if t and t.RenderOverride == flatDraw then e.RenderOverride = nil end
	end
	flatWrapped = {}
end
timer.Create("SPeditor.FlatModels", 0.5, 0, function()
	local want = C.active and (C.fullbright or GetConVar("gmfm_render_fullbright"):GetBool())
	if not want then
		if next(flatWrapped) then unwrapAll() end
		return
	end
	for _, e in ipairs(ents.GetAll()) do
		if IsValid(e) and not flatWrapped[e] and not e:IsWorld() then
			local t = e:GetTable()
			local m = e:GetModel()
			-- only models that draw themselves: an object hidden or drawn by someone else
			-- (a worn copy, a Lua entity) keeps its own draw
			-- (set through the entity: the engine learns of a RenderOverride only that way)
			if t and t.RenderOverride == nil and m and string.EndsWith(m, ".mdl") then
				e.RenderOverride = flatDraw
				flatWrapped[e] = true
			end
		end
	end
	for e in pairs(flatWrapped) do
		if not IsValid(e) then flatWrapped[e] = nil end
	end
end)
function R.Fullbright(on)
	flatModels = on and true or false
	if SPeditor.Lights and SPeditor.Lights.Dark then SPeditor.Lights.Dark(flatModels) end
end
local function flatLight()
	if not flatModels then return end
	render.SetLightingMode(0)
	render.SuppressEngineLighting(true)
	render.ResetModelLighting(1, 1, 1)
	render.SetLocalModelLights({})
end
SPeditor.Hook("PreDrawOpaqueRenderables", "SPeditor.Fullbright", flatLight)
SPeditor.Hook("PreDrawTranslucentRenderables", "SPeditor.Fullbright", flatLight)
SPeditor.Hook("PostDrawTranslucentRenderables", "SPeditor.Fullbright", function()
	if flatModels then
		render.SuppressEngineLighting(false)
		-- the mode is read back by the engine for the rest of the view (the world went dark without it)
		render.SetLightingMode(1)
	end
end)

-- Draws the scene into rt (area 0,0,rw,rh). pass: "primary" | "secondary" | "export".
-- aspect — frame proportions if they differ from rw / rh (the frame is stretched over the whole texture).
-- The near clipping plane of a view (b0.2.2, SFM's znear): a scene camera has its own, the work
-- camera takes gmfm_znear. It was the engine's 4 units: a camera brought up to a face cut it away.
local cvZNear = CreateClientConVar("gmfm_znear", "3", true, false, "GM:FM: near clipping plane of the work camera, units", 0.1, 100)
function R.ZNear(src)
	local e = src and src.ent
	if IsValid(e) and e.GetZNear then
		local z = e:GetZNear()
		if z and z > 0 then return z end
	end
	return math.Clamp(cvZNear:GetFloat(), 0.1, 100)
end

local function renderScene(rt, src, rw, rh, pass, wrap2D, fullbright, aspect)
	-- Fullscreen on Windows: after Alt+Tab the Direct3D device is lost until the game is back,
	-- and drawing into render targets then is a known way to crash the game (a report of a
	-- crash on Alt+Tab). The viewports keep their last frame; a render (export) still goes on.
	if not C.exporting and system.IsWindows() and not system.HasFocus() and not system.IsWindowed() then return end
	local oldPass, oldEnt = C.vpPass, C.renderViewEnt
	C.vpPass, C.renderViewEnt = pass, src.ent
	render.PushRenderTarget(rt)
	render.Clear(16, 16, 16, 255, true, true)
	if wrap2D then cam.Start2D() end
	local exposure = R.CameraExposure(src.ent)
	if exposure > 0 then render.ResetToneMappingScale(exposure) end
	-- fullbright only for this render (per the wiki the mode must be put back to 0)
	if fullbright then
		render.SetLightingMode(1)
		R.Fullbright(true)
	end
	R.fullbrightView = fullbright and true or false
	guardShaderLib()
	-- whatever follows the view (the sun's cascades, cl_env.lua) goes to this camera first
	hook.Run("GMFM_PreView", src, pass)
	R.ownView = true
	local ok, err = pcall(render.RenderView, {
			origin = src.origin, angles = src.angles, fov = src.fov,
			x = 0, y = 0, w = rw, h = rh, aspect = aspect or (rw / rh),
			drawviewer = true, znear = R.ZNear(src),
	})
	R.ownView = false
	R.fullbrightView = false
	if fullbright then
		render.SetLightingMode(0)
		R.Fullbright(false)
	end
	if not ok then ErrorNoHalt("[GM:FM] RenderView: " .. tostring(err) .. "\n") end
	if pass == "primary" then R.DrawHelpers(src, rw, rh) end
	if wrap2D then cam.End2D() end
	render.PopRenderTarget()
	C.vpPass, C.renderViewEnt = oldPass, oldEnt
end

-- The gizmo, skeleton and rig over a finished picture in the pushed render target (0,0,w,h):
-- a 3D view of the same camera (its fov is the horizontal one, as the picking assumes —
-- measured in game), the depth of the scene is left as the view wrote it
function R.DrawHelpers(src, w, h)
	if not C.DrawHelpers3D or not C.active or C.hideUI then return end
	cam.Start3D(src.origin, src.angles, src.fov, 0, 0, w, h)
	C.DrawHelpers3D()
	cam.End3D()
end

-- Exposure for a view through the camera ent: the shared exposure of the editor multiplied
-- by the camera's own tone map scale (camera effects, cl_postfx.lua). 0 — leave it to the game.
function R.CameraExposure(ent)
	local exposure = R.GetExposure()
	local FX = SPeditor.FX
	local scale = FX and FX.ToneScale and FX.ToneScale(FX.For(ent)) or nil
	if scale then exposure = (exposure > 0 and exposure or 1) * scale end
	return exposure
end

-- Viewport (called from the panel's Paint, coordinates are LOCAL).
-- The frame is fitted into the panel by the chosen aspect ratio. Camera effects
-- are not applied here: they show in the Render window preview and in the render.
-- Every viewport has its own texture. frozen = true — the scene is not redrawn,
-- the last shot frame is shown (the Secondary Viewport while Render is open:
-- the frame time is given to the preview).
local vpFrames = {}   -- [pass] = { rw, rh, w, h (the panel) }
local primaryAt = 0   -- RealTime of the last frame the Primary Viewport was painted

-- R.busy = true (a frame sequence is being rendered, SAeditor): the viewports are redrawn
-- twice a second, the frame time goes to the render.
local BUSY_INTERVAL = 0.5

-- The render look of the Primary Viewport (a0.7, as in SFM): the frame as the render makes it —
-- depth of field, soft shadows, smoothing and the camera effects (bloom, curves, vignette…).
-- While the view or the scene moves (flying, dragging, playback) a light version is shot
-- every frame; once everything rests, one full frame is shot and kept. The frames are shot
-- in PostRender (R.Viewport only asks for them and shows the last one); the helper graphics
-- (gizmo, skeleton) are not in them.
local cvLook = CreateClientConVar("gmfm_vp_look", "0", true, false)
local LOOK_FAST_PASSES = 4       -- depth of field / soft shadow passes of the light version
local LOOK_REST = 0.3            -- s without changes before the full frame
local look = { }

function R.LookOn() return cvLook:GetBool() end
function R.SetLook(on)
	RunConsoleCommand("gmfm_vp_look", on and "1" or "0")
	look.rt, look.full = nil, nil
end

-- anything that changes the picture without moving the view: edits, undo, keys, the frame
local function lookDirty() look.changed = RealTime() end
SPeditor.Hook("SPeditor_HistoryPushed", "SPeditor.ViewportLook", lookDirty)
SPeditor.Hook("SPeditor_HistoryStep", "SPeditor.ViewportLook", lookDirty)
SPeditor.Hook("SAeditor_Changed", "SPeditor.ViewportLook", lookDirty)

local function shootLook()
	local req = look.req
	look.req = nil
	if not req or not cvLook:GetBool() or not C.active or C.hideUI or C.exporting or R.busy then return end
	if SPeditor.Export and SPeditor.Export.pending then return end
	local FX = SPeditor.FX
	local src = req.src
	local W, H = C.GetRenderSize()
	local aspect = W / H
	local VP_W, VP_H = vpSize()
	local pw = math.Clamp(math.floor(math.min(req.iw, W)), 16, VP_W)
	local ph = math.Clamp(math.floor(pw / aspect), 16, VP_H)
	local fx = FX and FX.For(src.ent) or nil
	local now = RealTime()
	local o, a = src.origin, src.angles
	local sig = string.format("%.1f %.1f %.1f %.2f %.2f %.2f %.2f %d %s %s", o.x, o.y, o.z, a.p, a.y, a.r, src.fov, pw,
		tostring(C.SceneTime and C.SceneTime() or 0), tostring(src.ent))
	if sig ~= look.sig then look.sig, look.changed = sig, now end
	local busy = (C.ScenePlaying and C.ScenePlaying()) or input.IsMouseDown(MOUSE_LEFT) or input.IsMouseDown(MOUSE_RIGHT)
	if busy then look.changed = now end
	local resting = now - (look.changed or 0) >= LOOK_REST
	-- the full frame is shot once per rest
	if resting and look.full and look.fullAt and look.fullAt >= look.changed then return end

	-- "Engine frame": the engine shoots the view with the addon shaders (SSAO / HBAO of
	-- GShader Library, bloom, SMAA…), as the render does in this mode; no depth of field then
	local fullbright = C.fullbright or GetConVar("gmfm_render_fullbright"):GetBool()
	if R.EngineFor(fullbright) then
		R.FinishEngineFrame()
		local E = R.Engine
		if E.info and E.info.owner == look and E.serial ~= look.engSerial then
			look.engSerial = E.serial
			local ok, rt = pcall(function()
				local base = R.EngineToRT(pw, ph, aspect)
				return base and R.ApplyFX(base, fx, pw, ph, aspect)
			end)
			if ok and rt then
				local own_rt = getRT("vplook_" .. pw .. "x" .. ph, pw, ph)
				R.Copy(rt, own_rt)
				look.rt, look.w, look.h = own_rt, pw, ph
				-- a few frames after the rest: effects that settle over frames have settled
				look.engRest = E.info.rest and (look.engRest or 0) + 1 or 0
				look.full = look.engRest >= 3
				if look.full then look.fullAt = now end
			end
		end
		if not E.want and not E.cur then
			R.RequestEngineFrame(R.FXSource(src, fx), { fullbright = C.fullbright or GetConVar("gmfm_render_fullbright"):GetBool(),
				aspect = aspect, owner = look })
			E.want.rest = resting
		end
		return
	end

	local opts = { fullbright = C.fullbright or GetConVar("gmfm_render_fullbright"):GetBool(), aspect = aspect }
	if GetConVar("gmfm_dof"):GetBool() then
		opts.dof = { aperture = math.Clamp(GetConVar("gmfm_dof_aperture"):GetFloat(), 0.05, 20),
			samples = math.Clamp(GetConVar("gmfm_dof_samples"):GetInt(), 2, 128), focus = SPeditor.Export.FocusDistance(src) }
	end
	local own = FX and FX.DOF(fx)
	if own then opts.dof = table.Copy(own) end
	if resting then
		if GetConVar("gmfm_render_ss"):GetBool() and pw <= 960 then opts.ss = 2 end
	else
		-- a few depth of field passes are a few sharp copies of the frame side by side (ghosts),
		-- not a blur: the light version is sharp, the full frame at rest has the depth of field
		opts.dof = nil
		opts.softMax = LOOK_FAST_PASSES
	end
	local prevHide, prevExp = C.hideUI, C.exporting
	C.hideUI, C.exporting = true, true
	local ok, rt = pcall(function()
		local base = R.RenderBase(R.FXSource(src, fx), pw, ph, opts)
		return R.ApplyFX(base, fx, pw, ph, aspect)
	end)
	C.hideUI, C.exporting = prevHide, prevExp
	if not ok then
		ErrorNoHalt("[GM:FM] render look: " .. tostring(rt) .. "\n")
		look.rt = nil
		return
	end
	-- its own texture: the render and the preview reuse the ones it was shot in
	local own_rt = getRT("vplook_" .. pw .. "x" .. ph, pw, ph)
	R.Copy(rt, own_rt)
	look.rt, look.w, look.h = own_rt, pw, ph
	look.full = resting
	if resting then look.fullAt = now end
	return true
end

SPeditor.Hook("PostRender", "SPeditor.ViewportLook", function()
	-- already shot in this frame's RenderScene (R.EarlyPrimary below)
	if look.early then
		look.early = nil
		return
	end
	shootLook()
end)

function R.Viewport(src, w, h, pass, frozen)
	local ix, iy, iw, ih = C.FitRect(w, h, C.GetAspect(pass))
	if iw < 4 or ih < 4 then return end

	pass = pass or "primary"
	if pass == "primary" then primaryAt = RealTime() end
	if pass == "primary" and cvLook:GetBool() and not R.busy then
		look.req = { src = src, iw = iw }
		if look.rt then
			-- the finished frame has no helpers: they are drawn over a copy of it
			local over = getRT("vplookh_" .. look.w .. "x" .. look.h, look.w, look.h)
			R.Copy(look.rt, over)
			render.PushRenderTarget(over)
			render.ClearDepth()
			local oldPass = C.vpPass
			C.vpPass = "primary"
			R.DrawHelpers(src, look.w, look.h)
			C.vpPass = oldPass
			render.PopRenderTarget()
			R.DrawRT(over, ix, iy, iw, ih)
			draw.SimpleTextOutlined(L(look.full and "vp_look_full" or "vp_look_fast"), "SPeditor.Small", ix + iw - 8, iy + 6,
				look.full and Color(140, 220, 140) or Color(230, 190, 90), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, 1, color_black)
			return ix, iy, iw, ih
		end
	end
	local VP_W, VP_H = vpSize()
	local rt = getRT("vp_" .. pass .. "_" .. VP_W .. "x" .. VP_H, VP_W, VP_H)
	local st = vpFrames[pass] or {}
	vpFrames[pass] = st
	if R.busy and st.rw and RealTime() < (st.busyNext or 0) then frozen = true end
	-- drawn already in this frame's RenderScene (R.EarlyPrimary)
	if st.early then
		st.early = nil
		if st.rw then frozen = true end
	end
	st.w, st.h = w, h
	if not (frozen and st.rw) then
		st.busyNext = RealTime() + BUSY_INTERVAL
		local s = math.min(1, VP_W / iw, VP_H / ih)
		st.rw, st.rh = math.max(math.floor(iw * s), 16), math.max(math.floor(ih * s), 16)
		renderScene(rt, src, st.rw, st.rh, pass, false, C.fullbright)
	end

	matShow:SetTexture("$basetexture", rt)
	surface.SetMaterial(matShow)
	surface.SetDrawColor(255, 255, 255, 255)
	R.DrawTexturedUV(ix, iy, iw, ih, st.rw / VP_W, st.rh / VP_H)
	return ix, iy, iw, ih
end

-- The Primary Viewport drawn in RenderScene instead of the main game frame (b0.2.2). While the
-- engine's own particles live (util.Effect: tracers, shells, sparks, the dust of hits — every
-- shot of a recorded take makes them) the main frame has to be drawn for them to move
-- (cl_camera.lua C.ParticlesAlive), and that was a second whole view of the map in every frame:
-- measured on gm_scrapland with a recorded shoot-out, 42 ms a frame against 12 without it — the
-- views of one frame wait for each other, whatever their size. A view drawn from RenderScene
-- moves the particles just as the main frame does (measured: sparks of util.Effect fall and die
-- the same), so the viewport's own picture takes the main frame's place, and its panel shows it.
-- Returns true when it has drawn (the caller then cancels the main frame).
local EARLY_STALE = 0.25   -- s: a viewport not painted for this long (closed, hidden) is not drawn
function R.EarlyPrimary()
	if not C.active or C.hideUI or C.exporting or R.busy then return false end
	if SPeditor.Export and SPeditor.Export.pending then return false end
	if RealTime() - primaryAt > EARLY_STALE then return false end
	local UI = SPeditor.UI
	local vp = UI and UI.PrimaryVP
	if not IsValid(vp) or not vp.GetSource then return false end
	local src = vp.GetSource()
	if not src then return false end
	if cvLook:GetBool() then
		-- the render look shoots its frames itself; the engine frame mode takes the main frame
		local fullbright = C.fullbright or GetConVar("gmfm_render_fullbright"):GetBool()
		if R.EngineFor(fullbright) or not look.req then return false end
		-- nothing shot (the full frame of a rest is kept): the main frame moves the particles
		if not shootLook() then return false end
		look.early = true
		return true
	end
	local st = vpFrames.primary
	if not st or not st.w then return false end
	local _, _, iw, ih = C.FitRect(st.w, st.h, C.GetAspect())
	if iw < 4 or ih < 4 then return false end
	local VP_W, VP_H = vpSize()
	local rt = getRT("vp_primary_" .. VP_W .. "x" .. VP_H, VP_W, VP_H)
	local s = math.min(1, VP_W / iw, VP_H / ih)
	st.rw, st.rh = math.max(math.floor(iw * s), 16), math.max(math.floor(ih * s), 16)
	renderScene(rt, src, st.rw, st.rh, "primary", false, C.fullbright)
	st.early = true
	return true
end

-- surface.DrawTexturedRect(UV) moves the texture coordinates in by half a texel of a 32-pixel
-- texture (the size it assumes for a material whose texture was swapped), whatever the real
-- size: a viewport picture came out 3% larger and 30 px off to the top left (measured in game,
-- a0.9), so the gizmo and the bones were picked where they were not drawn. The coordinates
-- are moved out by the same amount first.
local UV_HALF = 0.5 / 32
local function uvFix(u) return (u - UV_HALF) / (1 - 2 * UV_HALF) end
function R.DrawTexturedUV(x, y, w, h, u1, v1)
	surface.DrawTexturedRectUV(x, y, w, h, uvFix(0), uvFix(0), uvFix(u1 or 1), uvFix(v1 or 1))
end

-- Show a finished frame (rt of size rw x rh) in a rectangle of the panel
function R.DrawRT(rt, x, y, w, h)
	matShow:SetTexture("$basetexture", rt)
	surface.SetMaterial(matShow)
	surface.SetDrawColor(255, 255, 255, 255)
	R.DrawTexturedUV(x, y, w, h, 1, 1)
end

-- Render at a given resolution (export). Call from PostRender.
function R.RenderToRT(src, W, H, fullbright)
	local rt = getRT("exp_" .. W .. "x" .. H, W, H)
	renderScene(rt, src, W, H, "export", true, fullbright)
	return rt
end

---------------------------------------------------------------------
-- The final frame with quality improvements.
-- ss  — smoothing: the frame is drawn 2 times larger and scaled down;
-- dof — depth of field: the scene is drawn many times with the camera moved around
-- the "aperture" circle and aimed at the focus point; the frames are averaged.
-- Everything at the focus distance stays sharp, the rest blurs.
-- The averaging is a running mean: the i-th frame is laid on with opacity 1/i.
-- It accumulates in a floating-point RT: a regular 8-bit one would show banding after
-- dozens of frames. (Frame brightness cannot be changed through $color — the engine
-- applies gamma to it and the sum comes out darker; verified in game.)
---------------------------------------------------------------------
local floatTargets = {}
local function getFloatRT(name, w, h)
	local rt = floatTargets[name]
	if not rt then
		rt = GetRenderTargetEx("speditor_" .. name, w, h, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 4 + 8, 0, IMAGE_FORMAT_RGBA16161616F or 24)
		floatTargets[name] = rt
	end
	return rt
end

local matBlend = CreateMaterial("speditor_render_blend", "UnlitGeneric", {
		["$nolod"] = "1", ["$translucent"] = "1",
})
local matWhite = Material("vgui/white")

-- Draw rt over the whole current render target; alpha — opacity (0..1).
-- Only render.DrawScreenQuad: it transfers the frame pixel for pixel.
-- surface.DrawTexturedRect inside cam.Start2D stretches the picture here
-- (verified in game by a per-pixel comparison) and is no good for copying frames.
local function drawFull(mat, rt, alpha)
	mat:SetTexture("$basetexture", rt)
	if alpha then mat:SetFloat("$alpha", alpha) end
	render.SetMaterial(mat)
	render.DrawScreenQuad()
end

-- The alpha channel of a frame may hold depth; make it opaque before blending
local function opaqueAlpha(rt)
	render.PushRenderTarget(rt)
	render.OverrideColorWriteEnable(true, false)
	render.OverrideAlphaWriteEnable(true, true)
	render.SetMaterial(matWhite)
	render.DrawScreenQuad()
	render.OverrideColorWriteEnable(false)
	render.OverrideAlphaWriteEnable(false)
	render.PopRenderTarget()
end

-- points on the aperture circle: an even spiral (golden angle)
local function diskPoint(i, n)
	local r = math.sqrt((i - 0.5) / n)
	local a = i * 2.39996323
	return r * math.cos(a), r * math.sin(a)
end

-- Frame source for a camera with effects: fisheye shoots the scene wider
function R.FXSource(src, fx)
	if not fx then return src end
	local fov = SPeditor.FX.SourceFOV(fx, src.fov)
	if fov == src.fov then return src end
	return { origin = src.origin, angles = src.angles, fov = fov, ent = src.ent }
end

R.GetRT = getRT

-- Motion blur (a0.7, SAeditor): the finished frames of several moments inside one video
-- frame (the shutter) are averaged the same way — a running mean in a floating-point RT.
-- R.Accumulate(rt, i, W, H) lays the i-th of them on (i = 1 starts anew);
-- R.AccumulatedRT(W, H) — the mean as an ordinary RT, ready to be captured.
function R.Accumulate(rt, i, W, H)
	opaqueAlpha(rt)
	local acc = getFloatRT("mblur_" .. W .. "x" .. H, W, H)
	render.PushRenderTarget(acc)
	if i <= 1 then render.Clear(0, 0, 0, 255) end
	drawFull(matBlend, rt, 1 / math.max(i, 1))
	render.PopRenderTarget()
end

function R.AccumulatedRT(W, H)
	local acc = getFloatRT("mblur_" .. W .. "x" .. H, W, H)
	local out = getRT("mblur_out_" .. W .. "x" .. H, W, H)
	render.PushRenderTarget(out)
	render.Clear(0, 0, 0, 255, true, true)
	drawFull(matShow, acc)
	render.PopRenderTarget()
	return out
end

---------------------------------------------------------------------
-- Engine frame
-- R.RequestEngineFrame(src, opts)  order a frame: it is shot in the NEXT game frame
-- R.FinishEngineFrame()            (PostRender) take the frame from the screen
-- R.EngineToRT(W, H, aspect)       cut a frame of the needed proportions into a W x H texture
-- R.Engine.serial grows with every shot frame, R.Engine.info is its order.
---------------------------------------------------------------------
local cvEngine = CreateClientConVar("gmfm_render_engine", "0", true, false)
R.Engine = R.Engine or { serial = 0 }
local E = R.Engine

function R.EngineMode() return cvEngine:GetBool() end
-- The engine frame for a shot with or without fullbright: a fullbright shot is always made by the
-- editor's own pass. In the game's own frame the fullbright mode drew the heads of characters
-- with facial flexes black (Barney) and did not keep the models flat; the own pass does both.
function R.EngineFor(fullbright) return cvEngine:GetBool() and not fullbright end
function R.SetEngineMode(on) RunConsoleCommand("gmfm_render_engine", on and "1" or "0") end

-- opts = { fullbright, aspect, owner }; owner — who ordered it (so as not to take someone else's frame)
function R.RequestEngineFrame(src, opts)
	E.want = { src = src, fullbright = opts.fullbright and true or false, aspect = opts.aspect or (ScrW() / ScrH()), owner = opts.owner }
end

-- The main camera view for the engine frame (for CalcView). In RenderView the field of
-- view is horizontal for the given proportions, while for the main view it is set
-- for 4:3 and widened by the engine (measured in game). The angle is chosen so that
-- a rectangle with the frame proportions inscribed in the screen shows the same thing.
--
-- The engine asks for the view (CalcView) before PreRender happens (the hook order was
-- verified in game), so the answer is already given by the order for the next frame (E.want).
function R.EngineView()
	local c = E.cur or E.want
	if not c then return nil end
	local screen = ScrW() / ScrH()
	local t = math.tan(math.rad(math.Clamp(c.src.fov, 1, 170)) / 2) / (0.75 * math.min(c.aspect, screen))
	return c.src.origin, c.src.angles, math.Clamp(math.deg(2 * math.atan(t)), 1, 175), R.ZNear(c.src)
end

SPeditor.Hook("PreRender", "SPeditor.EngineFrame", function()
	if not C.active then
		E.want, E.cur = nil, nil
		return
	end
	if E.want and not E.cur then
		E.cur, E.want = E.want, nil
	end
end)

-- Called from RenderScene (cl_camera.lua): true — this game frame is drawn by the engine
function R.BeginEngineFrame()
	local c = E.cur
	if not c then return false end
	-- as in export: the gizmo, light wireframes and camera models do not get into the frame.
	-- The previous flags are remembered once: if the frame could not be taken (PostRender
	-- was cut short by an error in another addon's hook), it is shot again, and remembering
	-- again would store the flags already set — the viewports would stay black.
	if not c.began then
		c.prev = { C.hideUI, C.vpPass, C.renderViewEnt }
		-- the addon effects keyed with this camera (cl_shaders.lua), only for this frame
		local Sd = SPeditor.Shaders
		if Sd and Sd.ApplyKeyed and IsValid(c.src.ent) then c.cvBack = Sd.ApplyKeyed(C.GetCameraFX(c.src.ent)) end
	end
	C.hideUI, C.vpPass, C.renderViewEnt = true, "export", c.src.ent
	local exposure = R.CameraExposure(c.src.ent)
	if exposure > 0 then render.ResetToneMappingScale(exposure) end
	if c.fullbright then
		render.SetLightingMode(1)
		R.Fullbright(true)
	end
	c.began = true
	return true
end

local function endLighting(c)
	if c and c.fullbright and not c.lightReset then
		c.lightReset = true
		render.SetLightingMode(0)
		R.Fullbright(false)
	end
end
SPeditor.Hook("PreDrawHUD", "SPeditor.EngineFrame", function() endLighting(E.cur) end)

-- Take the shot frame from the screen. Called from PostRender (before the interface is drawn)
-- by everyone who uses the frame; a repeated call in the same frame does nothing.
function R.FinishEngineFrame()
	local c = E.cur
	if not c then return end
	E.cur = nil
	endLighting(c)
	if c.prev then C.hideUI, C.vpPass, C.renderViewEnt = c.prev[1], c.prev[2], c.prev[3] end
	if c.cvBack then
		SPeditor.Shaders.RestoreKeyed(c.cvBack)
		c.cvBack = nil
	end
	if not c.began then return end

	local sw, sh = ScrW(), ScrH()
	E.tex = getRT("engine_" .. sw .. "x" .. sh, sw, sh)
	render.CopyRenderTargetToTexture(E.tex)
	E.w, E.h, E.info = sw, sh, c
	E.serial = E.serial + 1

	-- the scene is not needed on screen: under the editor windows — the regular background
	local bg = SPeditor.UI and SPeditor.UI.PAL and SPeditor.UI.PAL.BORDER
	render.Clear(bg and bg.r or 34, bg and bg.g or 32, bg and bg.b or 33, 255, true, true)
end
SPeditor.Hook("PostRender", "SPeditor.EngineFrame", function() R.FinishEngineFrame() end)

-- Size of the screen part from which a frame with the proportions aspect is taken
function R.EngineCropSize(aspect)
	local _, _, iw, ih = C.FitRect(ScrW(), ScrH(), aspect)
	return math.floor(iw), math.floor(ih)
end

-- Cut a rectangle with the proportions aspect out of the shot frame and stretch it over
-- a W x H texture. Returns the texture, or nil if there is no frame yet.
function R.EngineToRT(W, H, aspect)
	if not E.tex then return nil end
	local rt = R.CropToRT(E.tex, E.w, E.h, W, H, aspect, "eng_")
	-- the editor's ambient occlusion over the engine's frame (a depth pass of the same view)
	if R.ApplySSAO and E.info and E.info.src and not E.info.fullbright then R.ApplySSAO(rt, E.info.src, W, H, aspect, R.SSAOPasses()) end
	return rt
end

-- The same for any texture tex of tw x th pixels (SAeditor's player takes the screen this way)
function R.CropToRT(tex, tw, th, W, H, aspect, prefix)
	local ix, iy, iw, ih = C.FitRect(tw, th, aspect or (W / H))
	local u0, v0, u1, v1 = ix / tw, iy / th, (ix + iw) / tw, (iy + ih) / th
	local out = getRT((prefix or "crop_") .. W .. "x" .. H, W, H)
	render.PushRenderTarget(out)
	render.Clear(0, 0, 0, 255, true, true)
	cam.Start2D()
	matShow:SetTexture("$basetexture", tex)
	render.SetMaterial(matShow)
	mesh.Begin(MATERIAL_QUADS, 1)
	mesh.Position(Vector(0, 0, 0)) mesh.TexCoord(0, u0, v0) mesh.Color(255, 255, 255, 255) mesh.AdvanceVertex()
	mesh.Position(Vector(W, 0, 0)) mesh.TexCoord(0, u1, v0) mesh.Color(255, 255, 255, 255) mesh.AdvanceVertex()
	mesh.Position(Vector(W, H, 0)) mesh.TexCoord(0, u1, v1) mesh.Color(255, 255, 255, 255) mesh.AdvanceVertex()
	mesh.Position(Vector(0, H, 0)) mesh.TexCoord(0, u0, v1) mesh.Color(255, 255, 255, 255) mesh.AdvanceVertex()
	mesh.End()
	cam.End2D()
	render.PopRenderTarget()
	return out
end

-- Camera effects over a finished frame rt of size W x H
function R.ApplyFX(rt, fx, W, H, aspect)
	local FX = SPeditor.FX
	if fx and FX then rt = FX.Apply(rt, getRT("fx_" .. W .. "x" .. H, W, H), W, H, fx, aspect) end
	-- the FX clips of the timeline at the current frame (b0.2 round 6, cl_saeditor_fxclips.lua)
	if R.ApplyClips then rt = R.ApplyClips(rt, W, H) end
	return rt
end

-- A finished frame stretched over the whole current target, or over its top left w x h
-- (the screen, for the WebM writer)
function R.DrawFull(rt, w, h)
	render.Clear(0, 0, 0, 255, true, true)
	matShow:SetTexture("$basetexture", rt)
	render.SetMaterial(matShow)
	if w and h then render.DrawScreenQuadEx(0, 0, w, h) else render.DrawScreenQuad() end
end

-- A copy of the frame from one texture into another of the same size
function R.Copy(from, to)
	render.PushRenderTarget(to)
	render.Clear(0, 0, 0, 255, true, true)
	matShow:SetTexture("$basetexture", from)
	render.SetMaterial(matShow)
	render.DrawScreenQuad()
	render.PopRenderTarget()
end

-- The final frame: the scene (smoothing, depth of field) and camera effects on top.
-- opts = { fullbright, ss = 1|2, dof = { aperture, samples, focus } | nil,
-- aspect = frame proportions if it is stretched over the whole W x H texture }
function R.RenderFinal(src, W, H, opts)
	opts = opts or {}
	local FX = SPeditor.FX
	local fx = FX and FX.For(src.ent) or nil
	local rt = R.RenderBase(R.FXSource(src, fx), W, H, opts)
	return R.ApplyFX(rt, fx, W, H, opts.aspect)
end

-- The frame without camera effects (FX.Apply lays them on separately).
-- The frame accumulator is shared by depth of field and soft shadows (lights
-- with a size, cl_lights.lua): in every pass both the camera moves over the aperture
-- and each such light over its own disc. opts.softMax limits the number
-- of passes for soft shadows (preview), opts.soft = false switches them off;
-- opts.sampleScale (0..1) makes only a part of the passes of both (frame sequences).
function R.RenderBase(src, W, H, opts)
	opts = opts or {}
	local ss = (opts.ss == 2) and 2 or 1
	local sw, sh = W * ss, H * ss
	local dof = opts.dof
	local Lt = SPeditor.Lights
	local soft = (Lt and opts.soft ~= false and not opts.fullbright) and Lt.SoftSamples() or 0
	if soft > 0 and opts.softMax then soft = math.min(soft, opts.softMax) end
	-- a part of the passes, but no fewer than 12: below that the penumbra shows steps
	local scale = math.Clamp(tonumber(opts.sampleScale) or 1, 0.05, 1)
	local function scaled(n)
		if scale >= 1 or n <= 0 then return n end
		return math.max(math.floor(n * scale + 0.5), math.min(n, 12))
	end
	soft = scaled(soft)
	-- the occlusion's passes (cl_ssao.lua): fewer in the live views (preview, render look)
	local aoPasses = R.SSAOPasses and R.SSAOPasses(opts.softMax ~= nil) or 1

	if ss == 1 and not dof and soft == 0 then
		local rt = liveRT("exp_" .. W .. "x" .. H, W, H)
		renderScene(rt, src, W, H, "export", true, opts.fullbright, opts.aspect)
		-- ambient occlusion (cl_ssao.lua) from the centre of the view
		if R.ApplySSAO and not opts.fullbright then R.ApplySSAO(rt, src, W, H, opts.aspect, aoPasses) end
		return rt
	end

	local frame = liveRT("exp_" .. sw .. "x" .. sh, sw, sh)
	local result = frame

	if dof or soft > 0 then
		local dn = dof and math.Clamp(math.floor(dof.samples or 32), 2, 128) or 0
		local n = math.max(opts.dofFull and dn or scaled(dn), soft)
		-- opts.progress = { key, step } (a0.9): the passes are spread over calls — each call adds
		-- step more to an accumulator of its own and returns the frame so far; progress.done when
		-- all n are in. The player's pause shot all 96 depth of field passes in one game frame and
		-- froze the game for seconds.
		local pr = opts.progress
		local acc = getFloatRT((pr and ("accp_" .. tostring(pr.key or "p") .. "_") or "acc_") .. sw .. "x" .. sh, sw, sh)
		local from, to = 1, n
		if pr then
			if not pr.i or pr.n ~= n then pr.i, pr.n = 0, n end
			from, to = pr.i + 1, math.min(n, pr.i + math.max(pr.step or 4, 1))
		end
		if from == 1 then
			render.PushRenderTarget(acc)
			render.Clear(0, 0, 0, 255)
			render.PopRenderTarget()
		end

		local fwd, right, up = src.angles:Forward(), src.angles:Right(), src.angles:Up()
		local focus = dof and (src.origin + fwd * math.max(dof.focus or 200, 4))
		-- with depth of field the occlusion goes into every pass, so that it is blurred with the
		-- picture: laid over the finished blur it drew sharp dark outlines (the player's pause)
		local aoMask = dof and not opts.fullbright and R.SSAOMask and R.SSAOMask(src, W, H, opts.aspect, aoPasses)
		local ok, err = pcall(function()
			for i = from, to do
				local s = src
				if dof then
					local dx, dy = diskPoint(i, n)
					local origin = src.origin + right * (dx * dof.aperture) + up * (dy * dof.aperture)
					s = { origin = origin, angles = (focus - origin):AngleEx(up), fov = src.fov, ent = src.ent }
				end
				if soft > 0 then Lt.Jitter(i, n) end
				renderScene(frame, s, sw, sh, "export", true, opts.fullbright, opts.aspect)
				if aoMask then R.MultiplyAO(frame, aoMask) end
				opaqueAlpha(frame)

				render.PushRenderTarget(acc)
				drawFull(matBlend, frame, 1 / i)
				render.PopRenderTarget()
			end
		end)
		-- the lights are always put back, even if the pass was cut short by an error
		if soft > 0 then Lt.Restore() end
		if not ok then error(err, 0) end
		if pr then pr.i, pr.done = to, to >= n end
		result = acc
		if aoMask then opts.aoDone = true end
	else
		renderScene(frame, src, sw, sh, "export", true, opts.fullbright, opts.aspect)
	end

	-- into an 8-bit RT of the final size (also the downscale when smoothing)
	local out = liveRT("out_" .. W .. "x" .. H, W, H)
	render.PushRenderTarget(out)
	render.Clear(0, 0, 0, 255, true, true)
	drawFull(matShow, result)
	render.PopRenderTarget()
	if R.ApplySSAO and not opts.fullbright and not opts.aoDone then R.ApplySSAO(out, src, W, H, opts.aspect, aoPasses) end
	opts.aoDone = nil
	return out
end
