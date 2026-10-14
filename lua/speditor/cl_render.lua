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

local VP_W, VP_H = 1280, 1024

-- Frame exposure. In HDR the engine adjusts brightness to what the main
-- camera sees (auto exposure), and this adjustment is shared by all views:
-- bringing the work camera close to a lit object made both viewports and the
-- final render go dark within a couple of seconds. So before every pass
-- the exposure is fixed. 0 = auto (engine behaviour).
local cvExposure = CreateClientConVar("speditor_exposure", "1", true, false)
R.EXPOSURES = { 0, 0.5, 0.75, 1, 1.25, 1.5, 2, 3 }

function R.GetExposure() return math.Clamp(cvExposure:GetFloat(), 0, 8) end
function R.SetExposure(v) RunConsoleCommand("speditor_exposure", tostring(math.Clamp(v, 0, 8))) end

local targets = {}
local function getRT(name, w, h)
	local rt = targets[name]
	if not rt then
		rt = GetRenderTarget("speditor_" .. name, w, h)
		targets[name] = rt
	end
	return rt
end

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

-- Draws the scene into rt (area 0,0,rw,rh). pass: "primary" | "secondary" | "export".
-- aspect — frame proportions if they differ from rw / rh (the frame is stretched over the whole texture).
local function renderScene(rt, src, rw, rh, pass, wrap2D, fullbright, aspect)
	local oldPass, oldEnt = C.vpPass, C.renderViewEnt
	C.vpPass, C.renderViewEnt = pass, src.ent
	render.PushRenderTarget(rt)
	render.Clear(16, 16, 16, 255, true, true)
	if wrap2D then cam.Start2D() end
	local exposure = R.CameraExposure(src.ent)
	if exposure > 0 then render.ResetToneMappingScale(exposure) end
	-- fullbright only for this render (per the wiki the mode must be put back to 0)
	if fullbright then render.SetLightingMode(1) end
	R.fullbrightView = fullbright and true or false
	guardShaderLib()
	R.ownView = true
	local ok, err = pcall(render.RenderView, {
			origin = src.origin, angles = src.angles, fov = src.fov,
			x = 0, y = 0, w = rw, h = rh, aspect = aspect or (rw / rh),
			drawviewer = true,
	})
	R.ownView = false
	R.fullbrightView = false
	if fullbright then render.SetLightingMode(0) end
	if not ok then ErrorNoHalt("[SPeditor] RenderView: " .. tostring(err) .. "\n") end
	if wrap2D then cam.End2D() end
	render.PopRenderTarget()
	C.vpPass, C.renderViewEnt = oldPass, oldEnt
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
local vpFrames = {}   -- [pass] = { rw, rh }

-- R.busy = true (a frame sequence is being rendered, SAeditor): the viewports are redrawn
-- twice a second, the frame time goes to the render.
local BUSY_INTERVAL = 0.5

function R.Viewport(src, w, h, pass, frozen)
	local ix, iy, iw, ih = C.FitRect(w, h, C.GetAspect())
	if iw < 4 or ih < 4 then return end

	pass = pass or "primary"
	local rt = getRT("vp_" .. pass, VP_W, VP_H)
	local st = vpFrames[pass] or {}
	vpFrames[pass] = st
	if R.busy and st.rw and RealTime() < (st.busyNext or 0) then frozen = true end
	if not (frozen and st.rw) then
		st.busyNext = RealTime() + BUSY_INTERVAL
		local s = math.min(1, VP_W / iw, VP_H / ih)
		st.rw, st.rh = math.max(math.floor(iw * s), 16), math.max(math.floor(ih * s), 16)
		renderScene(rt, src, st.rw, st.rh, pass, false, C.fullbright)
	end

	matShow:SetTexture("$basetexture", rt)
	surface.SetMaterial(matShow)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRectUV(ix, iy, iw, ih, 0, 0, st.rw / VP_W, st.rh / VP_H)
	return ix, iy, iw, ih
end

-- Show a finished frame (rt of size rw x rh) in a rectangle of the panel
function R.DrawRT(rt, x, y, w, h)
	matShow:SetTexture("$basetexture", rt)
	surface.SetMaterial(matShow)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRect(x, y, w, h)
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
		rt = GetRenderTargetEx("speditor_" .. name, w, h, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 4 + 8, 0, IMAGE_FORMAT_RGBA16161616F)
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

---------------------------------------------------------------------
-- Engine frame
-- R.RequestEngineFrame(src, opts)  order a frame: it is shot in the NEXT game frame
-- R.FinishEngineFrame()            (PostRender) take the frame from the screen
-- R.EngineToRT(W, H, aspect)       cut a frame of the needed proportions into a W x H texture
-- R.Engine.serial grows with every shot frame, R.Engine.info is its order.
---------------------------------------------------------------------
local cvEngine = CreateClientConVar("speditor_render_engine", "0", true, false)
R.Engine = R.Engine or { serial = 0 }
local E = R.Engine

function R.EngineMode() return cvEngine:GetBool() end
function R.SetEngineMode(on) RunConsoleCommand("speditor_render_engine", on and "1" or "0") end

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
	return c.src.origin, c.src.angles, math.Clamp(math.deg(2 * math.atan(t)), 1, 175)
end

hook.Add("PreRender", "SPeditor.EngineFrame", function()
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
	if not c.began then c.prev = { C.hideUI, C.vpPass, C.renderViewEnt } end
	C.hideUI, C.vpPass, C.renderViewEnt = true, "export", c.src.ent
	local exposure = R.CameraExposure(c.src.ent)
	if exposure > 0 then render.ResetToneMappingScale(exposure) end
	if c.fullbright then render.SetLightingMode(1) end
	c.began = true
	return true
end

local function endLighting(c)
	if c and c.fullbright and not c.lightReset then
		c.lightReset = true
		render.SetLightingMode(0)
	end
end
hook.Add("PreDrawHUD", "SPeditor.EngineFrame", function() endLighting(E.cur) end)

-- Take the shot frame from the screen. Called from PostRender (before the interface is drawn)
-- by everyone who uses the frame; a repeated call in the same frame does nothing.
function R.FinishEngineFrame()
	local c = E.cur
	if not c then return end
	E.cur = nil
	endLighting(c)
	if c.prev then C.hideUI, C.vpPass, C.renderViewEnt = c.prev[1], c.prev[2], c.prev[3] end
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
hook.Add("PostRender", "SPeditor.EngineFrame", function() R.FinishEngineFrame() end)

-- Size of the screen part from which a frame with the proportions aspect is taken
function R.EngineCropSize(aspect)
	local _, _, iw, ih = C.FitRect(ScrW(), ScrH(), aspect)
	return math.floor(iw), math.floor(ih)
end

-- Cut a rectangle with the proportions aspect out of the shot frame and stretch it over
-- a W x H texture. Returns the texture, or nil if there is no frame yet.
function R.EngineToRT(W, H, aspect)
	if not E.tex then return nil end
	local ix, iy, iw, ih = C.FitRect(E.w, E.h, aspect or (W / H))
	local u0, v0, u1, v1 = ix / E.w, iy / E.h, (ix + iw) / E.w, (iy + ih) / E.h
	local out = getRT("eng_" .. W .. "x" .. H, W, H)
	render.PushRenderTarget(out)
	render.Clear(0, 0, 0, 255, true, true)
	cam.Start2D()
	matShow:SetTexture("$basetexture", E.tex)
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
	if not fx or not FX then return rt end
	return FX.Apply(rt, getRT("fx_" .. W .. "x" .. H, W, H), W, H, fx, aspect)
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

	if ss == 1 and not dof and soft == 0 then
		local rt = getRT("exp_" .. W .. "x" .. H, W, H)
		renderScene(rt, src, W, H, "export", true, opts.fullbright, opts.aspect)
		return rt
	end

	local frame = getRT("exp_" .. sw .. "x" .. sh, sw, sh)
	local result = frame

	if dof or soft > 0 then
		local n = math.max(dof and scaled(math.Clamp(math.floor(dof.samples or 32), 2, 128)) or 0, soft)
		local acc = getFloatRT("acc_" .. sw .. "x" .. sh, sw, sh)
		render.PushRenderTarget(acc)
		render.Clear(0, 0, 0, 255)
		render.PopRenderTarget()

		local fwd, right, up = src.angles:Forward(), src.angles:Right(), src.angles:Up()
		local focus = dof and (src.origin + fwd * math.max(dof.focus or 200, 4))
		local ok, err = pcall(function()
			for i = 1, n do
				local s = src
				if dof then
					local dx, dy = diskPoint(i, n)
					local origin = src.origin + right * (dx * dof.aperture) + up * (dy * dof.aperture)
					s = { origin = origin, angles = (focus - origin):AngleEx(up), fov = src.fov, ent = src.ent }
				end
				if soft > 0 then Lt.Jitter(i, n) end
				renderScene(frame, s, sw, sh, "export", true, opts.fullbright, opts.aspect)
				opaqueAlpha(frame)

				render.PushRenderTarget(acc)
				drawFull(matBlend, frame, 1 / i)
				render.PopRenderTarget()
			end
		end)
		-- the lights are always put back, even if the pass was cut short by an error
		if soft > 0 then Lt.Restore() end
		if not ok then error(err, 0) end
		result = acc
	else
		renderScene(frame, src, sw, sh, "export", true, opts.fullbright, opts.aspect)
	end

	-- into an 8-bit RT of the final size (also the downscale when smoothing)
	local out = getRT("out_" .. W .. "x" .. H, W, H)
	render.PushRenderTarget(out)
	render.Clear(0, 0, 0, 255, true, true)
	drawFull(matShow, result)
	render.PopRenderTarget()
	return out
end
