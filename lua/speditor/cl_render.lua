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
--
-- (b0.2.6, Workshop: "65 GB of RAM, a crash") A target is never freed by the game, and where the
-- check itself fails — the read back does not see the clear on some machines or under a render
-- state another addon left behind — every target of every render was "dead" every two seconds,
-- and a new one of the full size was made each time, without end. A name is replaced at most
-- MAX_RENAMES times, and a new target that fails the check at once means the check cannot be
-- trusted here: it is switched off for good (R.rtCheckOff).
local VERIFY_EVERY = 2
local MAX_RENAMES = 2
local verified, renamed, renames = {}, {}, {}
local function rtTakesClear(rt)
	render.PushRenderTarget(rt)
	render.Clear(3, 250, 7, 255, true, true)
	render.CapturePixels()
	local r, g, b = render.ReadPixel(0, 0)
	render.PopRenderTarget()
	return r == 3 and g == 250 and b == 7
end
local function liveRT(name, w, h)
	local key = renamed[name] or name
	local rt = getRT(key, w, h)
	if R.rtCheckOff or (renames[name] or 0) >= MAX_RENAMES then return rt end
	local now = RealTime()
	if now - (verified[key] or -1e9) < VERIFY_EVERY then return rt end
	verified[key] = now
	if rtTakesClear(rt) then return rt end
	local n = 2
	while targets[name .. "_r" .. n] do n = n + 1 end
	key = name .. "_r" .. n
	local fresh = getRT(key, w, h)
	if not rtTakesClear(fresh) then
		R.rtCheckOff = true
		MsgC(Color(255, 190, 90), "[GM:FM] the render target check fails on this computer: it is switched off\n")
		return rt
	end
	renames[name] = (renames[name] or 0) + 1
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
			-- the lens of a depth of field pass and the smoothing's sub-pixel shift (R.OffCenter)
			offcenter = R.OffCenter(src, rw, rh, aspect or (rw / rh)),
	})
	R.ownView = false
	R.fullbrightView = false
	if fullbright then
		render.SetLightingMode(0)
		R.Fullbright(false)
	end
	if not ok then ErrorNoHalt("[GM:FM] RenderView: " .. tostring(err) .. "\n") end
	-- ambient occlusion over the viewport's picture (b0.2.6), worked out at a size rounded to 64
	-- pixels (a texture is made for every size and the game never frees one) and stretched over it.
	-- Only in the viewports: a render's passes ("export") take theirs in R.RenderBase at the
	-- frame's own size — laid on them here as well, the stretched mask drew dark copies of the
	-- objects beside them (round 7: a car and a soldier "drawn" on a wall in the preview)
	if ok and pass ~= "export" and R.ViewportAO and R.ViewportAO(src, fullbright) then
		local aw, ah = math.max(math.floor(rw / 64) * 64, 64), math.max(math.floor(rh / 64) * 64, 64)
		local okAO, mask = pcall(R.SSAOMask, src, aw, ah, aspect or (rw / rh), 1)
		if okAO and mask then R.MultiplyAORect(mask, rw, rh) end
	end
	-- the camera's bloom (SFM's bloomScale, round 8): a viewport through a scene camera shows it as
	-- SFM's does — it was only in the preview and the render, and changing it "did nothing"
	local FX = SPeditor.FX
	if ok and pass ~= "export" and not fullbright and FX and FX.ViewBloom and IsValid(src.ent) and src.ent:GetClass() == "speditor_camera" then
		local fx = C.GetCameraFX(src.ent)
		if FX.IsOn(fx, "sfmbloom") then
			local tw, th = rt:Width(), rt:Height()
			local out = FX.ViewBloom(rt, getRT("vpbloom_" .. tw .. "x" .. th, tw, th), tw, th, fx, rh)
			if out ~= rt then R.Copy(out, rt) end
		end
	end
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
-- (b0.2.6 round 7, as SFM) the Clip Editor of the timeline shows the Primary Viewport as the render
-- makes it and refines it at rest (C.ClipEditor, cl_saeditor_ui.lua: nothing is moved there); the
-- Motion and Graph editors show the quick picture (one pass of the occlusion: grainy)
local function lookOn() return cvLook:GetBool() or (C.ClipEditor ~= nil and C.ClipEditor()) end
R.LookActive = lookOn
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
	if not req or not lookOn() or not C.active or C.hideUI or C.exporting or R.busy then return end
	if SPeditor.Export and SPeditor.Export.pending then return end
	local FX = SPeditor.FX
	local src = req.src
	local W, H = C.GetRenderSize()
	local aspect = W / H
	local VP_W, VP_H = vpSize()
	-- (b0.2.6) in steps of 64 pixels: the game never frees a render target, and every width the
	-- viewport passed through while a splitter was dragged made a set of them for itself
	local pw = math.Clamp(math.max(math.floor(math.min(req.iw, W) / 64) * 64, 64), 16, VP_W)
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
		-- (round 10) at rest, with depth of field: one engine frame a pass of the lens, cut out shifted
		-- and averaged as the render does (R.EngineLens) — the engine frame had no depth of field
		local dof
		if resting then
			if GetConVar("gmfm_dof"):GetBool() then
				dof = { aperture = math.Clamp(GetConVar("gmfm_dof_aperture"):GetFloat(), 0.05, 20),
					samples = math.Clamp(GetConVar("gmfm_dof_samples"):GetInt(), 2, 128), focus = SPeditor.Export.FocusDistance(src) }
			end
			local own = FX and SPeditor.Export.TrackFocus(src, FX.DOF(fx))
			if own then dof = own end
		end
		local lkey = dof and string.format("%s|%d|%.2f|%.1f", tostring(look.changed), pw, dof.aperture, dof.focus) or nil
		local lens = E.info and E.info.owner == look and E.serial ~= look.engSerial and E.info.lens
		if lens then
			look.engSerial = E.serial
			if look.lens and lens.key == look.lens.key and lens.pass == look.lens.done + 1 then
				local ok, rt = pcall(function()
					local cut = R.EngineLensToRT(pw, ph, aspect)
					if not cut then return nil end
					R.LensAccumulate(cut, lens.pass, pw, ph)
					return R.ApplyFX(R.LensAccumulated(pw, ph), fx, pw, ph, aspect)
				end)
				if ok and rt then
					look.lens.done = lens.pass
					local own_rt = getRT("vplook_" .. pw .. "x" .. ph, pw, ph)
					R.Copy(rt, own_rt)
					look.rt, look.w, look.h = own_rt, pw, ph
					look.full = look.lens.done >= look.lens.n
					if look.full then look.fullAt = now end
				end
			end
		elseif E.info and E.info.owner == look and E.serial ~= look.engSerial then
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
		if dof then
			if not look.lens or look.lens.key ~= lkey then
				look.lens = { key = lkey, done = 0, n = math.min(math.floor(dof.samples or 32), 64), dof = dof }
			end
			if look.lens.done < look.lens.n and not E.want and not E.cur then
				local base = R.FXSource(src, fx)
				local l = R.EngineLens(look.lens.dof, look.lens.done + 1, look.lens.n, pw, ph, base.fov)
				l.pass, l.key = look.lens.done + 1, lkey
				R.RequestEngineFrame(R.EngineLensSource(base, l), { fullbright = C.fullbright or GetConVar("gmfm_render_fullbright"):GetBool(),
					aspect = aspect, owner = look, lens = l })
			end
			return
		end
		look.lens = nil
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
	local own = FX and SPeditor.Export.TrackFocus(src, FX.DOF(fx))
	if own then opts.dof = table.Copy(own) end
	if resting then
		if GetConVar("gmfm_render_ss"):GetBool() and pw <= 960 then opts.ss = 2 end
		-- refined pass by pass while it rests, as SFM's viewport (b0.2.6): before, the whole
		-- frame was shot in one game frame and the editor stood still for it
		if not look.prog or look.prog.at ~= look.changed or look.prog.w ~= pw then
			look.prog = { key = "look", step = 4, at = look.changed, w = pw }
		end
		opts.progress = look.prog
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
	-- full once every pass is in (a frame without passes is full at once)
	local pr = opts.progress
	look.full = resting and (not pr or not pr.i or pr.done) or false
	if look.full then look.fullAt = now end
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
	-- a free frame wider than 16:9 widens the view (Hor+, C.FrameFOV)
	src = C.FrameSource(src, iw / ih, pass)
	if pass == "primary" then primaryAt = RealTime() end
	if pass == "primary" and lookOn() and not R.busy then
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
	if lookOn() then
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
	src = C.FrameSource(src, iw / ih, "primary")
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
-- the "aperture" circle, its window shifted so that the plane at the focus distance stays in
-- place (round 7, a real lens as SFM's: R.OffCenter); the frames are averaged.
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
R.DiskPoint = diskPoint

-- (b0.2.6, after SFM) Smoothing by samples: every pass of the accumulator shifts the view by a
-- part of a pixel (a Halton pattern), so that the passes that blur the depth of field and soften
-- the shadows smooth the edges as well — SFM's anti-aliasing. Before, smoothing shot the frame at
-- twice the size (four times the pixels, and no frame past half of the largest texture).
-- gmfm_render_aa: "sfm" (samples) or "ss" (the old doubled frame); gmfm_render_aa_samples — the
-- passes a frame takes at least for smoothing alone.
local cvAA = CreateClientConVar("gmfm_render_aa", "sfm", true, false, "Render smoothing: sfm (jittered samples, as SFM) or ss (a doubled frame)")
local cvAASamples = CreateClientConVar("gmfm_render_aa_samples", "8", true, false, "Render smoothing (sfm): passes a frame takes at least", 1, 64)
function R.AAMode() return cvAA:GetString() == "ss" and "ss" or "sfm" end
function R.AASamples() return math.Clamp(cvAASamples:GetInt(), 1, 64) end

local function halton(i, b)
	local f, r = 1, 0
	while i > 0 do
		f = f / b
		r = r + f * (i % b)
		i = math.floor(i / b)
	end
	return r
end

-- the view of pass i turned by a part of a pixel (W x H frame, horizontal fov)
-- (round 7) the shift is a part of a pixel of the window (R.OffCenter), not a turn of the camera:
-- the same for every pixel of the frame, and it keeps the lens of a depth of field pass
local function jittered(s, i)
	local out = {}
	for k, v in pairs(s) do out[k] = v end
	out.shift = { halton(i, 2) - 0.5, halton(i, 3) - 0.5 }
	return out
end

-- (b0.2.6 round 7) The off-centre window of a pass: render.RenderView's offcenter, in pixels of the
-- view (measured in game: a larger left / right moves the window right, a larger top / bottom up).
--   src.shift = { x, y } — a shift in pixels (the smoothing's sub-pixel jitter);
--   src.lens = { x, y, focus } — the camera moved x right and y up (units) over the lens, with the
--   picture at the focus distance kept in place: SFM's depth of field, a real lens. Before, the
--   moved camera was turned to look at the focus point, and only the middle of the focal plane
--   stayed sharp — its edges blurred more the wider the frame and the aperture.
-- nil — a plain view.
function R.OffCenter(src, w, h, aspect)
	if not src or not (src.shift or src.lens) then return nil end
	local sx, sy = 0, 0
	if src.shift then sx, sy = src.shift[1], src.shift[2] end
	local lens = src.lens
	if lens then
		local tx = math.tan(math.rad(math.Clamp(src.fov, 1, 170)) / 2)
		-- pixels per unit across at the distance of one unit; down the same, for a frame that
		-- may be stretched over the texture (aspect differs from w / h)
		local px = (w / 2) / tx
		local py = (h / 2) * (aspect or (w / h)) / tx
		local f = math.max(lens[3], 1)
		sx = sx - lens[1] * px / f
		sy = sy - lens[2] * py / f
	end
	return { left = sx, right = w + sx, top = sy, bottom = h + sy }
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

-- (round 10) the passes of the lens of an engine frame are averaged the same way, in a target of
-- their own (the moments of motion blur average the finished frames above)
function R.LensAccumulate(rt, i, W, H)
	opaqueAlpha(rt)
	local acc = getFloatRT("lens_" .. W .. "x" .. H, W, H)
	render.PushRenderTarget(acc)
	if i <= 1 then render.Clear(0, 0, 0, 255) end
	drawFull(matBlend, rt, 1 / math.max(i, 1))
	render.PopRenderTarget()
end
function R.LensAccumulated(W, H)
	local acc = getFloatRT("lens_" .. W .. "x" .. H, W, H)
	local out = getRT("lens_out_" .. W .. "x" .. H, W, H)
	render.PushRenderTarget(out)
	render.Clear(0, 0, 0, 255, true, true)
	drawFull(matShow, acc)
	render.PopRenderTarget()
	return out
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

-- opts = { fullbright, aspect, owner, lens }; owner — who ordered it (so as not to take someone else's
-- frame); lens — a pass of the depth of field (R.EngineLens below), kept with the shot frame
function R.RequestEngineFrame(src, opts)
	E.want = { src = src, fullbright = opts.fullbright and true or false, aspect = opts.aspect or (ScrW() / ScrH()), owner = opts.owner,
		lens = opts.lens }
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

---------------------------------------------------------------------
-- (b0.2.6 round 10) Depth of field in the engine frame. The engine draws its frame once a game frame,
-- with one camera, so the frame is shot once for every point of the lens: the camera moved over the
-- aperture and looking the same way, its view a little wider — and every shot is cut out shifted, so
-- that the focal plane stays where it is (the window shift of SFM's lens, R.OffCenter, done on the
-- picture: a shifted window is the same picture moved), then they are averaged (R.LensAccumulate).
-- Before, the engine frame had no depth of field at all.
--   R.EngineLens(dof, i, n, W, H)  -> the pass i of n: { ox, oy, k (how much wider), rx, ry }
--   R.EngineLensSource(src, lens)  -> the view to shoot (moved, wider)
--   R.EngineLensToRT(W, H, aspect) -> the shot frame cut out for its pass, with its own occlusion
---------------------------------------------------------------------
function R.EngineLens(dof, i, n, W, H, fov)
	local aspect = W / H
	local tx = math.tan(math.rad(math.Clamp(fov, 1, 170)) / 2)
	local focus = math.max(dof.focus or 200, 4)
	local a = math.max(dof.aperture or 0, 0)
	-- the widest shift of the window, a part of half the frame (down it is the aspect times more)
	local k = 1 + math.min(a * math.max(aspect, 1) / (focus * tx) + 0.01, 1)
	local dx, dy = diskPoint(i, n)
	local ox, oy = dx * a, dy * a
	return { ox = ox, oy = oy, k = k, rx = ox / (focus * tx), ry = oy * aspect / (focus * tx), focus = focus, i = i, n = n }
end

function R.EngineLensSource(src, lens)
	local right, up = src.angles:Right(), src.angles:Up()
	local tx = math.tan(math.rad(math.Clamp(src.fov, 1, 170)) / 2)
	return { origin = src.origin + right * lens.ox + up * lens.oy, angles = src.angles,
		fov = math.deg(2 * math.atan(tx * lens.k)), ent = src.ent }
end

function R.EngineLensToRT(W, H, aspect)
	local c = E.info
	local lens = c and c.lens
	if not E.tex or not lens then return nil end
	aspect = aspect or (W / H)
	local ix, iy, iw, ih = C.FitRect(E.w, E.h, aspect)
	local cw, ch = iw / lens.k, ih / lens.k
	-- the window of a lens moved right by ox shifts left on the picture (R.OffCenter: sx = -rx)
	local cx = ix + iw / 2 - lens.rx * cw / 2
	local cy = iy + ih / 2 + lens.ry * ch / 2
	local rt = R.CropRectToRT(E.tex, E.w, E.h, W, H, cx - cw / 2, cy - ch / 2, cw, ch, "englens_")
	-- the occlusion of this pass's own view: the same window shift for its depth pass
	if R.ApplySSAO and c.src and not c.fullbright then
		local fov = math.deg(2 * math.atan(math.tan(math.rad(math.Clamp(c.src.fov, 1, 170)) / 2) / lens.k))
		local s = { origin = c.src.origin, angles = c.src.angles, fov = fov, ent = c.src.ent, lens = { lens.ox, lens.oy, lens.focus } }
		-- one pass of it, with the noise of this lens pass: the passes average it out
		local mask = R.SSAOMask and R.SSAOMask(s, W, H, aspect, 1, lens.i)
		if mask then R.MultiplyAO(rt, mask) end
	end
	return rt
end

-- The same for any texture tex of tw x th pixels (SAeditor's player takes the screen this way)
function R.CropToRT(tex, tw, th, W, H, aspect, prefix)
	local ix, iy, iw, ih = C.FitRect(tw, th, aspect or (W / H))
	return R.CropRectToRT(tex, tw, th, W, H, ix, iy, iw, ih, prefix)
end

-- the rectangle x, y, w, h (pixels of tex) stretched over a W x H texture
function R.CropRectToRT(tex, tw, th, W, H, ix, iy, iw, ih, prefix)
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
	-- smoothing as SFM does it: by the passes, at the frame's own size
	local aaN = 0
	if ss == 2 and R.AAMode() == "sfm" then
		ss = 1
		aaN = opts.aaSamples or R.AASamples()
	elseif opts.aaSamples then
		aaN = opts.aaSamples
	end
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
	-- (b0.2.6) the smoothing passes take the same part (a video at "half" smoothed every frame with
	-- all 8 passes — 8 renders of the scene a frame at the default settings); 2 at least
	if aaN > 1 and scale < 1 then aaN = math.max(math.floor(aaN * scale + 0.5), 2) end
	-- the occlusion's passes (cl_ssao.lua): fewer in the live views (preview, render look)
	local aoPasses = R.SSAOPasses and R.SSAOPasses(opts.softMax ~= nil) or 1

	if ss == 1 and not dof and soft == 0 and aaN <= 1 then
		local rt = liveRT("exp_" .. W .. "x" .. H, W, H)
		renderScene(rt, src, W, H, "export", true, opts.fullbright, opts.aspect)
		-- ambient occlusion (cl_ssao.lua) from the centre of the view
		if R.ApplySSAO and not opts.fullbright then R.ApplySSAO(rt, src, W, H, opts.aspect, aoPasses) end
		return rt
	end

	local frame = liveRT("exp_" .. sw .. "x" .. sh, sw, sh)
	local result = frame

	if dof or soft > 0 or aaN > 1 then
		local dn = dof and math.Clamp(math.floor(dof.samples or 32), 2, 256) or 0
		local n = math.max(opts.dofFull and dn or scaled(dn), soft, aaN > 1 and aaN or 0)
		-- motion blur (opts.slice = { moment, moments }, b0.2.6 after SFM): the passes of a frame
		-- are shared out among its moments — each takes every m-th point of the lens, of the lights
		-- and of the smoothing, and together they make the whole set once (each moment shot all of
		-- them before: the cost was moments x passes)
		local slice = istable(opts.slice) and opts.slice[2] > 1 and opts.slice or nil
		local sStart, sStep = 1, 1
		if slice then
			sStep = math.floor(slice[2])
			sStart = math.Clamp(math.floor(slice[1]), 1, sStep)
			n = math.max(n, sStep)
		end
		local count = math.max(math.ceil((n - sStart + 1) / sStep), 1)      -- passes of this call's set
		-- opts.progress = { key, step } (a0.9): the passes are spread over calls — each call adds
		-- step more to an accumulator of its own and returns the frame so far; progress.done when
		-- all n are in. The player's pause shot all 96 depth of field passes in one game frame and
		-- froze the game for seconds.
		local pr = opts.progress
		local acc = getFloatRT((pr and ("accp_" .. tostring(pr.key or "p") .. "_") or "acc_") .. sw .. "x" .. sh, sw, sh)
		local from, to = 1, count
		if pr then
			if not pr.i or pr.n ~= count then pr.i, pr.n = 0, count end
			from, to = pr.i + 1, math.min(count, pr.i + math.max(pr.step or 4, 1))
		end
		if from == 1 then
			render.PushRenderTarget(acc)
			render.Clear(0, 0, 0, 255)
			render.PopRenderTarget()
		end

		local right, up = src.angles:Right(), src.angles:Up()
		local focus = dof and math.max(dof.focus or 200, 4)
		-- (round 7) with depth of field every pass takes the occlusion of its own view, one pass of
		-- it with the noise of this pass (SFM's progressive render): one mask of the middle view
		-- laid on every pass is the same as one laid on the finished blur — sharp dark outlines
		-- of things that are out of focus
		local passAO = dof and not opts.fullbright and R.SSAOMask and R.SSAOParams and (R.SSAOParams(src))
		local ok, err = pcall(function()
			for k = from, to do
				local i = sStart + (k - 1) * sStep        -- the point of the whole set this pass takes
				local s = src
				if dof then
					-- the camera moves over the lens and keeps looking the same way; the window
					-- shifts so that the focal plane stays where it is (R.OffCenter)
					local dx, dy = diskPoint(i, n)
					local ox, oy = dx * dof.aperture, dy * dof.aperture
					s = { origin = src.origin + right * ox + up * oy, angles = src.angles, fov = src.fov, ent = src.ent,
						lens = { ox, oy, focus } }
				end
				if aaN > 1 then s = jittered(s, i) end
				if soft > 0 then Lt.Jitter(i, n) end
				renderScene(frame, s, sw, sh, "export", true, opts.fullbright, opts.aspect)
				if passAO then
					local mask = R.SSAOMask(s, sw, sh, opts.aspect, 1, i)
					if mask then R.MultiplyAO(frame, mask) end
				end
				opaqueAlpha(frame)

				render.PushRenderTarget(acc)
				drawFull(matBlend, frame, 1 / k)
				render.PopRenderTarget()
			end
		end)
		-- the lights are always put back, even if the pass was cut short by an error
		if soft > 0 then Lt.Restore() end
		if not ok then error(err, 0) end
		if pr then pr.i, pr.done = to, to >= count end
		result = acc
		if passAO then opts.aoDone = true end
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
