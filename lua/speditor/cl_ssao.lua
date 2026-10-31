--[[
SPeditor — ambient occlusion (SSAO, a0.7): soft contact shadows in corners, folds and under
objects, as in SFM. It is the editor's own: no other addon is needed.

  1. Depth pass: the view is drawn once more into a 32-bit float texture — every surface
     black with white linear fog from the camera to SSAO_FAR, no sky, no translucent things —
     so each pixel holds its distance from the camera: (distance / SSAO_FAR)^2 — the fog is
     blended in gamma space (measured in game), the shaders take the square root.
  2. speditor_ao2_ps20b (shaders_src/speditor_ao2.hlsl): from the depth it rebuilds the
     place and the normal of every pixel and counts how much of the hemisphere above it is
     covered by what is around, within the radius.
  3. speditor_ao2_blur_ps20b: a blur that does not cross depth edges, twice (across, down).
  4. The result multiplies the frame.

b0.2: steps 2 and 3 are Source Filmmaker's own ambient occlusion by default (gmfm_ssao_mode
"sfm"): SFM's ssao_ps30 / sfm_ao_blur_ps30 read out of its shaders and written again for this
depth (shaders_src/gmfm_sfmao*.hlsl; b0.2.1: Shader Model 2, gmfm_sfmao2b / gmfm_sfmaoblur2b, so
that DirectX level 90 runs them too): a hemisphere of 25 fixed points around
the normal, turned by a 4 x 4 pattern that does not change from frame to frame, SFM's range
check, and a 16-point Poisson-disc blur that stops at depth edges. "classic" is the a0.7 one.

b0.2.6 (round 7): the SFM mode redone after SFM's real one — sfm_ambientocclusion_ps30 and the
code of its material in stdshader_dx9.dll (gmfm_sfmao4b / gmfm_sfmaoblur4b): SFM's camera
settings SSAORadius / SSAOStrength / SSAOBias with their meaning and defaults (15, 1, 0.0005;
strength is how deep the occluders reach, not a darkness), 16 directions of SFM's kernel, a new
noise in every pass, (1 - occluded / 16)^2. A camera has its own (Render → Camera effects →
"SSAO of this camera", or the Animation Set Editor).

R.RenderBase (renders, the preview, the viewport render look, video) and the engine frame
call R.ApplySSAO when it is on; with depth of field every pass of the frame takes the occlusion
of its own view. Settings (Render window, saved with the scene):
  gmfm_ssao 0/1, gmfm_ssao_radius (units), gmfm_ssao_strength, gmfm_ssao_bias, gmfm_ssao_passes
  (round 6: SFM's progressive occlusion — that many passes with new noise averaged in renders).
The shaders are compiled from shaders_src/*.hlsl and packed by shaders_src/build_vcs.py into
shaders/fxc/*.vcs.
]]
SPeditor.Render = SPeditor.Render or {}
local R = SPeditor.Render
local C = SPeditor.Client

local cvOn       = CreateClientConVar("gmfm_ssao", "0", true, false)
-- SFM's defaults of a camera (SSAORadius 15, SSAOStrength 1, SSAOBias 0.0005)
local cvRadius   = CreateClientConVar("gmfm_ssao_radius", "15", true, false)
local cvStrength = CreateClientConVar("gmfm_ssao_strength", "1", true, false)
local cvBias     = CreateClientConVar("gmfm_ssao_bias", "0.0005", true, false, "Ambient occlusion (SFM): the start point off the surface, a part of its distance", 0, 0.05)
local cvMode     = CreateClientConVar("gmfm_ssao_mode", "sfm", true, false, "Ambient occlusion: sfm (Source Filmmaker's) or classic (a0.7)")
local cvPasses   = CreateClientConVar("gmfm_ssao_passes", "16", true, false,
	"Progressive ambient occlusion of renders (SFM's mode): passes with new directions, averaged (1 = one pass)", 1, 64)

local SSAO_FAR = 8192            -- the far end of the depth pass, units

function R.SSAOOn() return cvOn:GetBool() end

-- (b0.2.6) The occlusion of a view: on?, radius, strength, bias — the camera's own settings over
-- the scene's (Render window). A camera's: its "SSAO of this camera" (camera effects, as SFM's
-- SSAORadius / SSAOStrength / SSAOBias) turns it on with those; the mode of the Animation Set
-- Editor (0 as the scene, 1 on, 2 off) — 1 with the older radius / strength fields.
function R.SSAOParams(src)
	local cam = src and src.ent
	local mode = IsValid(cam) and cam.GetCamAO and math.floor(cam:GetCamAO() + 0.5) or 0
	local radius, strength, bias = cvRadius:GetFloat(), cvStrength:GetFloat(), cvBias:GetFloat()
	if mode == 2 then return false, radius, strength, bias end
	local FX = SPeditor.FX
	local fx = IsValid(cam) and FX and C.GetCameraFX and C.GetCameraFX(cam) or nil
	if fx and FX.IsOn(fx, "ssao") then
		return true, FX.Get(fx, "ssao", "radius"), FX.Get(fx, "ssao", "strength"), FX.Get(fx, "ssao", "bias")
	end
	if mode == 1 then
		if cam:GetAORadius() > 0 then radius = cam:GetAORadius() end
		if cam:GetAOStrength() > 0 then strength = cam:GetAOStrength() end
		return true, radius, strength, bias
	end
	return cvOn:GetBool(), radius, strength, bias
end

-- Occlusion in the viewports (b0.2.6, SFM shows it while you work): gmfm_vp_ssao 0 — none,
-- 1 — when the viewport looks through a camera of the scene, 2 — in every view
local cvVp = CreateClientConVar("gmfm_vp_ssao", "1", true, false,
	"Ambient occlusion in the viewports: 0 off, 1 through the cameras of the scene, 2 always", 0, 2)
function R.ViewportAOMode() return cvVp:GetInt() end
function R.ViewportAO(src, fullbright)
	if fullbright or not src then return false end
	local m = cvVp:GetInt()
	if m == 0 then return false end
	local cam = IsValid(src.ent) and src.ent:GetClass() == "speditor_camera"
	if m == 1 and not cam then return false end
	return (R.SSAOParams(src))
end

local matDepthWorld = CreateMaterial("speditor_ao_depth_world", "UnlitGeneric", {
	["$basetexture"] = "vgui/white", ["$color"] = "[0 0 0]",
})
local matDepthModel = CreateMaterial("speditor_ao_depth_model", "UnlitGeneric", {
	["$basetexture"] = "vgui/white", ["$model"] = "1", ["$color2"] = "[0 0 0]",
})
local function screenMat(name, ps)
	return CreateMaterial(name, "screenspace_general", {
		["$pixshader"] = ps,
		["$basetexture"] = "vgui/white", ["$texture1"] = "vgui/white",
		-- screenspace_general's own vertex shader; vertextransform: the quad of DrawScreenQuad
		-- in the pushed render target (a custom vs20 put it off the target)
		["$ignorez"] = "1", ["$vertextransform"] = "1", ["$copyalpha"] = "0",
		["$linearread_basetexture"] = "1", ["$linearread_texture1"] = "1", ["$linearwrite"] = "1",
		["$alpha_blend"] = "0", ["$alpha_blend_color_overlay"] = "0",
	})
end
-- The shader materials are made on the first use, not when the addon loads: made while the
-- game was still starting, they did not get the editor's shaders and drew nothing (white, no
-- occlusion) for the whole session, in both modes (b0.2 round 6)
local matAO, matBlur, matSfmAO, matSfmBlur
local function ensureMats()
	if matAO then return end
	-- "2": the shaders were fixed (a NaN made the whole frame lose its AO) — a new name, so a
	-- game that has loaded the old ones in this session or keeps them cached takes the new ones
	matAO   = screenMat("speditor_ao2_main", "speditor_ao2_ps20b")
	matBlur = screenMat("speditor_ao2_blur", "speditor_ao2_blur_ps20b")
	-- SFM's, Shader Model 2 (b0.2.1): the ps_3_0 ones of b0.2 are not run at all in a game at
	-- DirectX level 90 (the Linux build) — the frame came out black, the preview "stopped working".
	-- "4b" (b0.2.6 round 7): SFM's own math, read out of SFM's shader and its material's code
	matSfmAO   = screenMat("gmfm_sfmao4b_main", "gmfm_sfmao4b_ps20b")
	matSfmBlur = screenMat("gmfm_sfmaoblur4b", "gmfm_sfmaoblur4b_ps20b")
end
local matShow = CreateMaterial("speditor_ssao_show", "UnlitGeneric", { ["$nolod"] = "1" })

function R.SSAOMode() return cvMode:GetString() == "classic" and "classic" or "sfm" end
-- how many passes a render's occlusion takes (the live views take fewer: R.SSAOPasses(true))
function R.SSAOPasses(live)
	local n = math.Clamp(cvPasses:GetInt(), 1, 64)
	return live and math.min(n, 4) or n
end

local depthRTs, aoRTs = {}, {}
-- Some builds of the game have no IMAGE_FORMAT_R32F (b0.2.2: a Windows report, "bad argument #8
-- to 'GetRenderTargetEx'" every frame and no preview); the engine knows the format by its number
local FORMAT_R32F = IMAGE_FORMAT_R32F or 27
-- 32-bit float, one channel: in a 16-bit one the depth of a flat surface went in steps, each
-- step read as an edge, and a big render (3840 x 3152) was crossed by dark stripes and bands
-- (measured in game: 46% of the frame darkened against 8% — the real contacts — with R32F)
local function depthRT(w, h)
	local key = w .. "x" .. h
	depthRTs[key] = depthRTs[key] or GetRenderTargetEx("speditor_aodepth32_" .. key, w, h, RT_SIZE_LITERAL,
		MATERIAL_RT_DEPTH_SEPARATE, 4 + 8, 0, FORMAT_R32F)
	return depthRTs[key]
end
local function aoRT(i, w, h)
	local key = i .. "_" .. w .. "x" .. h
	aoRTs[key] = aoRTs[key] or GetRenderTargetEx("speditor_ao" .. key, w, h, RT_SIZE_LITERAL,
		MATERIAL_RT_DEPTH_NONE, 4 + 8, 0, IMAGE_FORMAT_RGBA8888)
	return aoRTs[key]
end
-- the running mean of the passes of a progressive occlusion
local accRTs = {}
local function accRT(w, h)
	local key = w .. "x" .. h
	accRTs[key] = accRTs[key] or GetRenderTargetEx("gmfm_aoacc_" .. key, w, h, RT_SIZE_LITERAL,
		MATERIAL_RT_DEPTH_NONE, 4 + 8, 0, IMAGE_FORMAT_RGBA16161616F or 24)
	return accRTs[key]
end
local matWhite = Material("vgui/white")
local matAccum = CreateMaterial("gmfm_ao_accum", "UnlitGeneric", { ["$nolod"] = "1", ["$translucent"] = "1" })

---------------------------------------------------------------------
-- The depth pass
---------------------------------------------------------------------
local depthPass = false
function R.DepthPassActive() return depthPass end

local function depthFog()
	if not depthPass then return end
	-- set again inside the view; brushes (floors, walls) need their own override, the world
	-- one covers only displacements
	render.WorldMaterialOverride(matDepthWorld)
	render.BrushMaterialOverride(matDepthWorld)
	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(0)
	render.FogEnd(SSAO_FAR)
	render.FogMaxDensity(1)
	render.FogColor(255, 255, 255)
	return true
end
SPeditor.Hook("SetupWorldFog", "SPeditor.SSAO", depthFog)
SPeditor.Hook("SetupSkyboxFog", "SPeditor.SSAO", function(scale)
	if not depthPass then return end
	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(0)
	render.FogEnd(SSAO_FAR * scale)
	render.FogMaxDensity(1)
	render.FogColor(255, 255, 255)
	return true
end)
-- the model override must be set inside the view (one set before RenderView is dropped)
SPeditor.Hook("PreDrawOpaqueRenderables", "SPeditor.SSAO", function()
	if depthPass then render.MaterialOverride(matDepthModel) end
end)
SPeditor.Hook("PreDrawTranslucentRenderables", "SPeditor.SSAO", function()
	if depthPass then return true end
end)
SPeditor.Hook("PreDrawSkyBox", "SPeditor.SSAO", function()
	if depthPass then return true end
end)
SPeditor.Hook("PreDrawEffects", "SPeditor.SSAO", function()
	if depthPass then return true end
end)

-- The depth of the view src (origin, angles, fov — horizontal for aspect) into a W x H texture
function R.RenderDepth(src, W, H, aspect)
	local rt = depthRT(W, H)
	local prevHide, prevPass, prevEnt = C.hideUI, C.vpPass, C.renderViewEnt
	C.hideUI, C.vpPass, C.renderViewEnt = true, "export", src.ent
	render.PushRenderTarget(rt)
	render.Clear(255, 255, 255, 255, true, true)
	render.WorldMaterialOverride(matDepthWorld)
	render.BrushMaterialOverride(matDepthWorld)
	depthPass = true
	R.ownView = true
	-- the characters the view is in the head of are not in the depth either
	local off = C.HiddenInView and C.HiddenInView(src.origin, src.ent) or {}
	for i, e in ipairs(off) do
		if e:GetNoDraw() then off[i] = false else e:SetNoDraw(true) end
	end
	-- inside a 2D context, as the editor's other passes (renderScene): without it the view
	-- came out with another field of view than the frame
	-- the fog of the depth must be the editor's: other fog hooks (a map's own) are off meanwhile
	local unmute = SPeditor.MuteOtherHooks({ "SetupWorldFog", "SetupSkyboxFog" })
	cam.Start2D()
	local ok, err = pcall(render.RenderView, {
		origin = src.origin, angles = src.angles, fov = src.fov,
		x = 0, y = 0, w = W, h = H, aspect = aspect or (W / H),
		drawviewer = true, drawhud = false, drawviewmodel = false, dopostprocess = false, drawmonitors = false,
		znear = R.ZNear and R.ZNear(src) or nil,
		-- the lens and the smoothing of the pass (cl_render.lua): the depth of the same view
		offcenter = R.OffCenter and R.OffCenter(src, W, H, aspect or (W / H)) or nil,
	})
	cam.End2D()
	unmute()
	for _, e in ipairs(off) do
		if e and IsValid(e) then e:SetNoDraw(false) end
	end
	R.ownView = false
	depthPass = false
	render.MaterialOverride()
	render.WorldMaterialOverride()
	render.BrushMaterialOverride()
	render.PopRenderTarget()
	C.hideUI, C.vpPass, C.renderViewEnt = prevHide, prevPass, prevEnt
	if not ok then ErrorNoHalt("[GM:FM] SSAO depth: " .. tostring(err) .. "\n") return nil end
	return rt
end

---------------------------------------------------------------------
-- Occlusion over a finished frame
---------------------------------------------------------------------
local function pass(target, mat)
	render.PushRenderTarget(target)
	render.Clear(255, 255, 255, 255)
	render.SetMaterial(mat)
	render.DrawScreenQuad()
	render.PopRenderTarget()
end

-- The visibility of the view src as a W x H texture (white — open, dark — occluded), or nil
-- when SSAO is off. R.MultiplyAO(rt, mask) darkens a frame of any size with it.
-- passes (b0.2 round 6, SFM mode): as SFM's progressive render, the occlusion is taken that many
-- times, every time with a new noise (the seed of the pass), and averaged — the noise of one
-- pass goes. 1 — one pass; seed — which pass of a progressive frame it is (b0.2.6 round 7: a
-- frame with depth of field takes one pass of its own view in each of its passes).
local SFM_DISC = 0.00416      -- SFM's blur: the disc's radius, a part of the frame's height

-- the seed of the i-th pass: a golden-ratio step, the first one is the stable pattern
local function seedOf(i)
	if not i or i <= 1 then return 0, 0 end
	return (i * 0.618034) % 1 * 97.13, (i * 0.754878) % 1 * 53.71
end

function R.SSAOMask(src, W, H, aspect, passes, seed)
	local on, rad, str, bias = R.SSAOParams(src)
	if not on or not src then return nil end
	ensureMats()
	aspect = aspect or (W / H)
	local depth = R.RenderDepth(src, W, H, aspect)
	if not depth then return nil end
	local a, b = aoRT(1, W, H), aoRT(2, W, H)
	local tx = math.tan(math.rad(math.Clamp(src.fov, 1, 170)) / 2)

	if R.SSAOMode() == "sfm" then
		local radius = math.Clamp(rad, 0.5, 512)
		local m = matSfmAO
		m:SetTexture("$basetexture", depth)
		m:SetFloat("$c0_x", radius)
		m:SetFloat("$c0_y", 1 / (radius * math.Clamp(str, 0.05, 20)))
		m:SetFloat("$c0_z", SSAO_FAR)
		m:SetFloat("$c0_w", math.Clamp(bias or 0.0005, 0, 0.05))
		m:SetFloat("$c1_x", tx)
		m:SetFloat("$c1_y", tx / aspect)
		m:SetFloat("$c1_z", 1 / W)
		m:SetFloat("$c1_w", 1 / H)
		passes = math.Clamp(math.floor(passes or 1), 1, 64)
		local sx, sy = seedOf(seed)
		if passes <= 1 then
			m:SetFloat("$c2_x", sx)
			m:SetFloat("$c2_y", sy)
			pass(b, m)
		else
			local acc = accRT(W, H)
			render.PushRenderTarget(acc)
			render.Clear(255, 255, 255, 255)
			render.PopRenderTarget()
			for i = 1, passes do
				local px, py = seedOf(i)
				m:SetFloat("$c2_x", px)
				m:SetFloat("$c2_y", py)
				pass(b, m)
				-- the alpha of the pass is not 1 (the engine keeps depth there): opaque before blending
				render.PushRenderTarget(b)
				render.OverrideColorWriteEnable(true, false)
				render.OverrideAlphaWriteEnable(true, true)
				render.SetMaterial(matWhite)
				render.DrawScreenQuad()
				render.OverrideColorWriteEnable(false)
				render.OverrideAlphaWriteEnable(false)
				render.PopRenderTarget()
				render.PushRenderTarget(acc)
				matAccum:SetTexture("$basetexture", b)
				matAccum:SetFloat("$alpha", 1 / i)
				render.SetMaterial(matAccum)
				render.DrawScreenQuad()
				render.PopRenderTarget()
			end
			-- back into the 8-bit target: the blur reads that one (read straight from the float
			-- target it gave black)
			render.PushRenderTarget(b)
			render.Clear(255, 255, 255, 255)
			matShow:SetTexture("$basetexture", acc)
			render.SetMaterial(matShow)
			render.DrawScreenQuad()
			render.PopRenderTarget()
		end
		-- one blur, SFM's disc: the average of blurred passes is the blur of their average
		matSfmBlur:SetTexture("$basetexture", b)
		matSfmBlur:SetTexture("$texture1", depth)
		matSfmBlur:SetFloat("$c0_x", 1 / W)
		matSfmBlur:SetFloat("$c0_y", 1 / H)
		matSfmBlur:SetFloat("$c0_z", SSAO_FAR)
		matSfmBlur:SetFloat("$c0_w", math.max(H * SFM_DISC, 1.5))
		matSfmBlur:SetFloat("$c1_x", 0.02)
		matSfmBlur:SetFloat("$c1_y", sx)
		matSfmBlur:SetFloat("$c1_z", sy)
		pass(a, matSfmBlur)
		R.lastAO, R.lastDepth = a, depth
		return a
	end

	local radius = math.Clamp(rad, 2, 256)
	matAO:SetTexture("$basetexture", depth)
	matAO:SetFloat("$c0_x", radius)
	matAO:SetFloat("$c0_y", math.Clamp(str, 0, 4))
	matAO:SetFloat("$c0_z", SSAO_FAR)
	matAO:SetFloat("$c0_w", 0.1)
	matAO:SetFloat("$c1_x", tx)
	matAO:SetFloat("$c1_y", tx / aspect)
	matAO:SetFloat("$c1_z", 1 / W)
	matAO:SetFloat("$c1_w", 1 / H)
	pass(a, matAO)

	matBlur:SetTexture("$texture1", depth)
	matBlur:SetFloat("$c0_z", SSAO_FAR)
	matBlur:SetFloat("$c0_w", radius)
	matBlur:SetTexture("$basetexture", a)
	matBlur:SetFloat("$c0_x", 1 / W) matBlur:SetFloat("$c0_y", 0)
	pass(b, matBlur)
	matBlur:SetTexture("$basetexture", b)
	matBlur:SetFloat("$c0_x", 0) matBlur:SetFloat("$c0_y", 1 / H)
	pass(a, matBlur)

	R.lastAO, R.lastDepth = a, depth
	return a
end

-- the picture in the pushed render target (its rectangle 0, 0, w, h) times the visibility
function R.MultiplyAORect(mask, w, h)
	if not mask then return end
	render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
	matShow:SetTexture("$basetexture", mask)
	render.SetMaterial(matShow)
	render.DrawScreenQuadEx(0, 0, w, h)
	render.OverrideBlend(false)
end

-- the frame times the visibility
function R.MultiplyAO(rt, mask)
	if not rt or not mask then return rt end
	render.PushRenderTarget(rt)
	render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
	matShow:SetTexture("$basetexture", mask)
	render.SetMaterial(matShow)
	render.DrawScreenQuad()
	render.OverrideBlend(false)
	render.PopRenderTarget()
	return rt
end

-- rt — the frame (W x H) of the view src; it is darkened in place. Returns rt.
function R.ApplySSAO(rt, src, W, H, aspect, passes)
	if not rt then return rt end
	return R.MultiplyAO(rt, R.SSAOMask(src, W, H, aspect, passes))
end

