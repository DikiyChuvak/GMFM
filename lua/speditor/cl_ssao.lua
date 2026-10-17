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

R.RenderBase (renders, the preview, the viewport render look, video) and the engine frame
call R.ApplySSAO when it is on. Settings (Render window, saved with the scene):
  speditor_ssao 0/1, speditor_ssao_radius (units), speditor_ssao_strength.
The shaders are compiled from shaders_src/*.hlsl and packed by shaders_src/build_vcs.py into
shaders/fxc/*.vcs.
]]
SPeditor.Render = SPeditor.Render or {}
local R = SPeditor.Render
local C = SPeditor.Client

local cvOn       = CreateClientConVar("speditor_ssao", "0", true, false)
local cvRadius   = CreateClientConVar("speditor_ssao_radius", "24", true, false)
local cvStrength = CreateClientConVar("speditor_ssao_strength", "1.5", true, false)

local SSAO_FAR = 8192            -- the far end of the depth pass, units

function R.SSAOOn() return cvOn:GetBool() end

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
-- "2": the shaders were fixed (a NaN made the whole frame lose its AO) — a new name, so a
-- game that has loaded the old ones in this session or keeps them cached takes the new ones
local matAO   = screenMat("speditor_ao2_main", "speditor_ao2_ps20b")
local matBlur = screenMat("speditor_ao2_blur", "speditor_ao2_blur_ps20b")
local matShow = CreateMaterial("speditor_ssao_show", "UnlitGeneric", { ["$nolod"] = "1" })

local depthRTs, aoRTs = {}, {}
-- 32-bit float, one channel: in a 16-bit one the depth of a flat surface went in steps, each
-- step read as an edge, and a big render (3840 x 3152) was crossed by dark stripes and bands
-- (measured in game: 46% of the frame darkened against 8% — the real contacts — with R32F)
local function depthRT(w, h)
	local key = w .. "x" .. h
	depthRTs[key] = depthRTs[key] or GetRenderTargetEx("speditor_aodepth32_" .. key, w, h, RT_SIZE_LITERAL,
		MATERIAL_RT_DEPTH_SEPARATE, 4 + 8, 0, IMAGE_FORMAT_R32F)
	return depthRTs[key]
end
local function aoRT(i, w, h)
	local key = i .. "_" .. w .. "x" .. h
	aoRTs[key] = aoRTs[key] or GetRenderTargetEx("speditor_ao" .. key, w, h, RT_SIZE_LITERAL,
		MATERIAL_RT_DEPTH_NONE, 4 + 8, 0, IMAGE_FORMAT_RGBA8888)
	return aoRTs[key]
end

---------------------------------------------------------------------
-- The depth pass
---------------------------------------------------------------------
local depthPass = false

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
hook.Add("SetupWorldFog", "SPeditor.SSAO", depthFog)
hook.Add("SetupSkyboxFog", "SPeditor.SSAO", function(scale)
	if not depthPass then return end
	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(0)
	render.FogEnd(SSAO_FAR * scale)
	render.FogMaxDensity(1)
	render.FogColor(255, 255, 255)
	return true
end)
-- the model override must be set inside the view (one set before RenderView is dropped)
hook.Add("PreDrawOpaqueRenderables", "SPeditor.SSAO", function()
	if depthPass then render.MaterialOverride(matDepthModel) end
end)
hook.Add("PreDrawTranslucentRenderables", "SPeditor.SSAO", function()
	if depthPass then return true end
end)
hook.Add("PreDrawSkyBox", "SPeditor.SSAO", function()
	if depthPass then return true end
end)
hook.Add("PreDrawEffects", "SPeditor.SSAO", function()
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
	-- inside a 2D context, as the editor's other passes (renderScene): without it the view
	-- came out with another field of view than the frame
	cam.Start2D()
	local ok, err = pcall(render.RenderView, {
		origin = src.origin, angles = src.angles, fov = src.fov,
		x = 0, y = 0, w = W, h = H, aspect = aspect or (W / H),
		drawviewer = true, drawhud = false, drawviewmodel = false, dopostprocess = false, drawmonitors = false,
	})
	cam.End2D()
	R.ownView = false
	depthPass = false
	render.MaterialOverride()
	render.WorldMaterialOverride()
	render.BrushMaterialOverride()
	render.PopRenderTarget()
	C.hideUI, C.vpPass, C.renderViewEnt = prevHide, prevPass, prevEnt
	if not ok then ErrorNoHalt("[SPeditor] SSAO depth: " .. tostring(err) .. "\n") return nil end
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

-- rt — the frame (W x H) of the view src; it is darkened in place. Returns rt.
function R.ApplySSAO(rt, src, W, H, aspect)
	if not cvOn:GetBool() or not rt or not src then return rt end
	aspect = aspect or (W / H)
	local depth = R.RenderDepth(src, W, H, aspect)
	if not depth then return rt end
	local a, b = aoRT(1, W, H), aoRT(2, W, H)
	local radius = math.Clamp(cvRadius:GetFloat(), 2, 256)
	local tx = math.tan(math.rad(math.Clamp(src.fov, 1, 170)) / 2)

	matAO:SetTexture("$basetexture", depth)
	matAO:SetFloat("$c0_x", radius)
	matAO:SetFloat("$c0_y", math.Clamp(cvStrength:GetFloat(), 0, 4))
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

	-- the frame times the visibility
	render.PushRenderTarget(rt)
	render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
	matShow:SetTexture("$basetexture", a)
	render.SetMaterial(matShow)
	render.DrawScreenQuad()
	render.OverrideBlend(false)
	render.PopRenderTarget()
	R.lastAO, R.lastDepth = a, depth
	return rt
end

