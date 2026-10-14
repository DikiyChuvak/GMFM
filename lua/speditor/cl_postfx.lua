--[[
SPeditor — scene camera effects (post-processing of the frame).

Effects are set for each scene camera separately (the work camera has none),
are stored on the camera itself and saved in scenes. They show in the Render window
preview and in the final render; viewports show the scene without effects.

The set: fisheye, vignette, colour curves and HDR (our own), stock GMod shaders —
bloom, sharpen, outlines (sobel), ToyTown, texturize and overlay —
and up to three "custom shaders": shader materials from the Workshop, addons
and the editor's shader folder (cl_shaders.lua finds them).

The stock GMod functions (DrawBloom, DrawSharpen, …) are not called here: they
copy the frame into a screen texture the size of the monitor and for a frame of another
size (a viewport, a 3840 px render) give a shifted or cropped picture. Instead
the same pp/* materials are fed our render target: the frame is bounced
between two textures of the same size (cur → other), so the result does not
depend on the screen resolution (verified in game on a 2560x1440 frame with a 1920x1080 screen).

API:
  FX.Defs / FX.ById            descriptions of the effects and their parameters
  FX.For(camera) -> fx | nil   enabled effects of a camera
  FX.Apply(rt, spare, w, h, fx, aspect) -> rt with the finished frame
  FX.SourceFOV(fx, fov)        field of view for shooting the scene (fisheye is wider)
  FX.Get(fx, id, key)          parameter value (or the default)
]]
SPeditor = SPeditor or {}
SPeditor.FX = SPeditor.FX or {}
local FX = SPeditor.FX
local C  = SPeditor.Client

---------------------------------------------------------------------
-- Drawing into the current render target
---------------------------------------------------------------------
-- $ignorez: effect quads are drawn over the frame and must not depend on
-- what was left in the depth buffer after the scene was drawn.
local matCopy = CreateMaterial("speditor_fx_copy2", "UnlitGeneric", { ["$nolod"] = "1", ["$ignorez"] = "1" })
local matTint = CreateMaterial("speditor_fx_tint2", "UnlitGeneric", {
		["$basetexture"] = "vgui/white", ["$vertexcolor"] = "1", ["$vertexalpha"] = "1", ["$nolod"] = "1", ["$ignorez"] = "1",
})

local function quad(x0, y0, x1, y1, u0, v0, u1, v1)
	mesh.Begin(MATERIAL_QUADS, 1)
	mesh.Position(Vector(x0, y0, 0)) mesh.TexCoord(0, u0, v0) mesh.Color(255, 255, 255, 255) mesh.AdvanceVertex()
	mesh.Position(Vector(x1, y0, 0)) mesh.TexCoord(0, u1, v0) mesh.Color(255, 255, 255, 255) mesh.AdvanceVertex()
	mesh.Position(Vector(x1, y1, 0)) mesh.TexCoord(0, u1, v1) mesh.Color(255, 255, 255, 255) mesh.AdvanceVertex()
	mesh.Position(Vector(x0, y1, 0)) mesh.TexCoord(0, u0, v1) mesh.Color(255, 255, 255, 255) mesh.AdvanceVertex()
	mesh.End()
end

-- ctx = { w, h, aspect, cur, other, extra }: cur — the texture with the current frame,
-- other and extra — work textures of the same size
local function swap(ctx) ctx.cur, ctx.other = ctx.other, ctx.cur end

-- Full-screen pass: draw(src) draws into other, reading cur
local function pass(ctx, draw)
	render.PushRenderTarget(ctx.other)
	local ok, err = pcall(draw, ctx.cur)
	render.PopRenderTarget()
	if not ok then error(err, 0) end
	swap(ctx)
end

-- A pass with a pp/* material that takes $fbtexture
local function shaderPass(ctx, mat)
	pass(ctx, function(src)
		mat:SetTexture("$fbtexture", src)
		render.SetMaterial(mat)
		render.DrawScreenQuad()
	end)
	mat:SetTexture("$fbtexture", render.GetScreenEffectTexture())
end

-- A copy of the frame into other (for effects that draw on top of the frame)
local function snapshot(ctx)
	render.PushRenderTarget(ctx.other)
	matCopy:SetTexture("$basetexture", ctx.cur)
	render.SetMaterial(matCopy)
	render.DrawScreenQuad()
	render.PopRenderTarget()
	return ctx.other
end

local materials = {}
local function material(path)
	local m = materials[path]
	if m == nil then
		m = Material(path)
		if m:IsError() then m = false end
		materials[path] = m
	end
	return m or nil
end

---------------------------------------------------------------------
-- Effects. A parameter: { key, min, max, default, decimals } — a slider;
-- { key, list = "…" } — a material picked from a GMod list.
---------------------------------------------------------------------
FX.Defs, FX.ById = {}, {}

local function define(d)
	FX.Defs[#FX.Defs + 1] = d
	FX.ById[d.id] = d
end

---------------------------------------------------------------------
-- Camera properties as in SFM: depth of field and exposure. They are not passes over the
-- finished frame: the renders ask for them (FX.DOF, FX.ToneScale) and shoot the scene
-- accordingly.
---------------------------------------------------------------------
-- focalDistance / aperture / depthOfFieldQuality of an SFM camera. Without this effect the
-- depth of field of the Render window is used (focus on the selected object).
define({ id = "dof", cat = "sfm", scene = true, params = {
			{ key = "focus", min = 8, max = 4000, default = 200, decimals = 0 },
			{ key = "aperture", min = 0.05, max = 20, default = 0.6 },
			{ key = "samples", min = 2, max = 128, default = 32, decimals = 0 },
} })

-- toneMapScale: brightness of this camera's picture (multiplies the editor's exposure)
define({ id = "tonemap", cat = "sfm", scene = true, params = { { key = "scale", min = 0.1, max = 4, default = 1 } } })

local GRID = 48

-- Fisheye: the frame is stretched over a grid whose points take the image from
-- closer to the centre — the centre bulges, the edges shrink (barrel distortion).
-- The radius is measured to the frame corner, so no black borders remain at the edges.
-- To keep the frame centre from "zooming in", the scene for such a camera is shot with
-- a wider field of view (FX.SourceFOV): the scale in the centre stays the same,
-- and more gets into the frame at the edges — as with a real wide-angle lens.
local FISH_K = 1.4          -- angle (rad) that corresponds to strength 1

local function fishK(strength) return math.Clamp(strength, 0, 1) * FISH_K end
define({ id = "fisheye", cat = "lens", params = { { key = "strength", min = 0, max = 1, default = 0.5 } },
		apply = function(ctx, p)
			local k = fishK(p.strength)
			if k < 0.01 then return end
			local a = ctx.aspect
			local norm = 1 / math.sqrt(a * a + 1)
			local tk = math.tan(k)
			local function warp(u, v)
				local dx, dy = (u - 0.5) * 2, (v - 0.5) * 2
				local r = math.sqrt((dx * a) ^ 2 + dy ^ 2) * norm
				local s = (r < 1e-4) and (k / tk) or (math.tan(r * k) / tk / r)
				return 0.5 + dx * 0.5 * s, 0.5 + dy * 0.5 * s
			end
			pass(ctx, function(src)
				matCopy:SetTexture("$basetexture", src)
				cam.Start2D()
				render.SetMaterial(matCopy)
				local w, h = ctx.w, ctx.h
				-- the grid is drawn row by row: a single dynamic mesh has a vertex limit
				local ok, err = true, nil
				for j = 0, GRID - 1 do
					local v0, v1 = j / GRID, (j + 1) / GRID
					mesh.Begin(MATERIAL_QUADS, GRID)
					ok, err = pcall(function()
						for i = 0, GRID - 1 do
							local u0, u1 = i / GRID, (i + 1) / GRID
							for _, c in ipairs({ { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } }) do
								local su, sv = warp(c[1], c[2])
								mesh.Position(Vector(c[1] * w, c[2] * h, 0))
								mesh.TexCoord(0, su, sv)
								mesh.Color(255, 255, 255, 255)
								mesh.AdvanceVertex()
							end
						end
					end)
					mesh.End()
					if not ok then break end
				end
				cam.End2D()
				if not ok then error(err, 0) end
			end)
		end })

---------------------------------------------------------------------
-- Tone curve. GMod has no custom pixel shaders, so the curve
-- y = f(x) is assembled from stock passes (the arithmetic was verified in game on a
-- gradient):
-- * pp/colour computes (x + brightness) * contrast clamped to 0..1 — this is
-- the "mask" of one curve segment: 0 before its start, 1 after its end;
-- * pp/bloom with colormul = 1 adds a texture to the frame, multiplied by a
-- level per channel, with no gamma conversion; with
-- render.OverrideBlend it subtracts.
-- Frame = f(0) + the sum of the masks multiplied by the curve gain on their segment.
-- Each channel has its own gain, so the R, G and B curves go through the same passes.
---------------------------------------------------------------------
local matColour = Material("pp/colour")
local matAdd = Material("pp/bloom")
local CURVE_STEPS = 16

local function colourPass(ctx, src, dst, contrast, brightness, saturation)
	matColour:SetFloat("$pp_colour_addr", 0)
	matColour:SetFloat("$pp_colour_addg", 0)
	matColour:SetFloat("$pp_colour_addb", 0)
	matColour:SetFloat("$pp_colour_brightness", brightness)
	matColour:SetFloat("$pp_colour_contrast", contrast)
	matColour:SetFloat("$pp_colour_colour", saturation or 1)
	matColour:SetFloat("$pp_colour_mulr", 0)
	matColour:SetFloat("$pp_colour_mulg", 0)
	matColour:SetFloat("$pp_colour_mulb", 0)
	matColour:SetFloat("$pp_colour_inv", 0)
	matColour:SetTexture("$fbtexture", src)
	render.PushRenderTarget(dst)
	render.SetMaterial(matColour)
	render.DrawScreenQuad()
	render.PopRenderTarget()
	matColour:SetTexture("$fbtexture", render.GetScreenEffectTexture())
end

-- Into the current render target: += tex * (r, g, b), and with subtract — -= tex * (r, g, b)
local function addScaled(tex, r, g, b, subtract)
	if r <= 0 and g <= 0 and b <= 0 then return end
	matAdd:SetFloat("$levelr", r)
	matAdd:SetFloat("$levelg", g)
	matAdd:SetFloat("$levelb", b)
	matAdd:SetFloat("$colormul", 1)
	matAdd:SetTexture("$basetexture", tex)
	if subtract then render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_REVERSE_SUBTRACT) end
	render.SetMaterial(matAdd)
	render.DrawScreenQuad()
	if subtract then render.OverrideBlend(false) end
end

-- lut = { r = {…}, g = {…}, b = {…} }: curve values at CURVE_STEPS + 1 points (0..1)
local function applyLUT(ctx, lut)
	local n = CURVE_STEPS
	local acc = ctx.extra
	render.PushRenderTarget(acc)
	render.Clear(math.Round(lut.r[1] * 255), math.Round(lut.g[1] * 255), math.Round(lut.b[1] * 255), 255)
	render.PopRenderTarget()
	for i = 1, n do
		local dr, dg, db = lut.r[i + 1] - lut.r[i], lut.g[i + 1] - lut.g[i], lut.b[i + 1] - lut.b[i]
		if math.abs(dr) + math.abs(dg) + math.abs(db) > 1e-4 then
			colourPass(ctx, ctx.cur, ctx.other, n, -(i - 1) / n)
			render.PushRenderTarget(acc)
			addScaled(ctx.other, math.max(dr, 0), math.max(dg, 0), math.max(db, 0), false)
			addScaled(ctx.other, math.max(-dr, 0), math.max(-dg, 0), math.max(-db, 0), true)
			render.PopRenderTarget()
		end
	end
	ctx.cur, ctx.extra = acc, ctx.cur
end

-- Curve points are stored as a string "x/y x/y …" (0..1). Between the points — a monotone
-- cubic spline: smooth and without overshooting the neighbouring points.
local DEFAULT_CURVE = "0/0 1/1"
FX.DEFAULT_CURVE = DEFAULT_CURVE
FX.MAX_CURVE_POINTS = 8

function FX.ParseCurve(str)
	local pts = {}
	for x, y in string.gmatch(isstring(str) and str or "", "([%d%.]+)/([%d%.]+)") do
		x, y = tonumber(x), tonumber(y)
		if x and y and #pts < FX.MAX_CURVE_POINTS then pts[#pts + 1] = { math.Clamp(x, 0, 1), math.Clamp(y, 0, 1) } end
	end
	table.sort(pts, function(a, b) return a[1] < b[1] end)
	for i = #pts, 2, -1 do
		if pts[i][1] - pts[i - 1][1] < 0.005 then table.remove(pts, i) end
	end
	if #pts < 2 then return { { 0, 0 }, { 1, 1 } } end
	return pts
end

function FX.FormatCurve(pts)
	local out = {}
	for i, p in ipairs(pts) do out[i] = string.format("%.3f/%.3f", p[1], p[2]) end
	return table.concat(out, " ")
end

-- Curve function from points
function FX.CurveFunction(pts)
	local n = #pts
	local d, m = {}, {}
	for i = 1, n - 1 do d[i] = (pts[i + 1][2] - pts[i][2]) / (pts[i + 1][1] - pts[i][1]) end
	m[1], m[n] = d[1], d[n - 1]
	for i = 2, n - 1 do
		m[i] = (d[i - 1] * d[i] <= 0) and 0 or (2 * d[i - 1] * d[i] / (d[i - 1] + d[i]))
	end
	return function(x)
		if x <= pts[1][1] then return pts[1][2] end
		if x >= pts[n][1] then return pts[n][2] end
		local i = 1
		while i < n - 1 and x > pts[i + 1][1] do i = i + 1 end
		local h = pts[i + 1][1] - pts[i][1]
		local t = (x - pts[i][1]) / h
		local t2, t3 = t * t, t * t * t
		local y = (2 * t3 - 3 * t2 + 1) * pts[i][2] + (t3 - 2 * t2 + t) * h * m[i]
			+ (-2 * t3 + 3 * t2) * pts[i + 1][2] + (t3 - t2) * h * m[i + 1]
		return math.Clamp(y, 0, 1)
	end
end

local curveCache = {}
local function curveFn(str)
	local f = curveCache[str]
	if not f then
		f = FX.CurveFunction(FX.ParseCurve(str))
		curveCache[str] = f
	end
	return f
end

local function buildLUT(fr, fg, fb)
	local lut = { r = {}, g = {}, b = {} }
	for i = 0, CURVE_STEPS do
		local x = i / CURVE_STEPS
		-- values are multiples of 1/255: segment gains then add up in the frame without accumulating rounding
		lut.r[i + 1], lut.g[i + 1], lut.b[i + 1] = math.Round(fr(x) * 255) / 255, math.Round(fg(x) * 255) / 255, math.Round(fb(x) * 255) / 255
	end
	return lut
end

-- Curves: the master (RGB) and per channel; a channel is applied on top of the master. Plus saturation.
define({ id = "curves", cat = "color", params = {
			{ key = "curve", curve = true },
			{ key = "saturation", min = 0, max = 3, default = 1 },
		},
		apply = function(ctx, p)
			if math.abs(p.saturation - 1) > 0.005 then
				colourPass(ctx, ctx.cur, ctx.other, 1, 0, p.saturation)
				swap(ctx)
			end
			local m, r, g, b = p.curve_m, p.curve_r, p.curve_g, p.curve_b
			if m == DEFAULT_CURVE and r == DEFAULT_CURVE and g == DEFAULT_CURVE and b == DEFAULT_CURVE then return end
			local fm, fr, fg, fb = curveFn(m), curveFn(r), curveFn(g), curveFn(b)
			applyLUT(ctx, buildLUT(function(x) return fr(fm(x)) end, function(x) return fg(fm(x)) end, function(x) return fb(fm(x)) end))
		end })

-- HDR: an "extended range" look on a regular frame. First the local
-- brightness differences are boosted (the frame minus its heavily blurred copy — the detail), then
-- a tone curve lifts the shadows and tames the highlights so that detail reads everywhere.
-- The detail is added separately: brighter than the background and darker than it — so no
-- intermediate result leaves 0..1 and gets clipped.
define({ id = "hdr", cat = "color", params = {
			{ key = "strength", min = 0, max = 1, default = 0.35 },
			{ key = "detail", min = 0, max = 1, default = 0.4 },
			{ key = "radius", min = 1, max = 20, default = 8, decimals = 1 },
		},
		apply = function(ctx, p)
			local k = math.Clamp(p.detail, 0, 1) * 1.5
			if k > 0.01 then
				local blur = render.GetBloomTex0()
				render.PushRenderTarget(blur)
				render.Clear(0, 0, 0, 255)
				addScaled(ctx.cur, 1, 1, 1, false)
				render.BlurRenderTarget(blur, p.radius, p.radius, 3)
				render.PopRenderTarget()

				local acc = ctx.extra
				-- brighter than the background: max(frame - blur, 0)
				render.PushRenderTarget(ctx.other)
				render.Clear(0, 0, 0, 255)
				addScaled(ctx.cur, 1, 1, 1, false)
				addScaled(blur, 1, 1, 1, true)
				render.PopRenderTarget()
				render.PushRenderTarget(acc)
				render.Clear(0, 0, 0, 255)
				addScaled(ctx.cur, 1, 1, 1, false)
				addScaled(ctx.other, k, k, k, false)
				render.PopRenderTarget()
				-- darker than the background: max(blur - frame, 0)
				render.PushRenderTarget(ctx.other)
				render.Clear(0, 0, 0, 255)
				addScaled(blur, 1, 1, 1, false)
				addScaled(ctx.cur, 1, 1, 1, true)
				render.PopRenderTarget()
				render.PushRenderTarget(acc)
				addScaled(ctx.other, k, k, k, true)
				render.PopRenderTarget()
				ctx.cur, ctx.extra = acc, ctx.cur
			end
			local a = math.Clamp(p.strength, 0, 1) * 3
			if a > 0.01 then
				local f = function(x) return x * (1 + a) / (1 + a * x) end
				applyLUT(ctx, buildLUT(f, f, f))
			end
		end })

local matDownsample, matBloom = Material("pp/downsample"), Material("pp/bloom")
define({ id = "bloom", cat = "shaders", params = {
			{ key = "darken", min = 0, max = 1, default = 0.65 },
			{ key = "multiply", min = 0, max = 5, default = 1 },
			{ key = "size", min = 0, max = 20, default = 4, decimals = 1 },
			{ key = "passes", min = 0, max = 10, default = 4, decimals = 0 },
			{ key = "color", min = 0, max = 5, default = 2 },
		},
		apply = function(ctx, p)
			local tex = render.GetBloomTex0()
			matDownsample:SetFloat("$darken", p.darken)
			matDownsample:SetFloat("$multiply", p.multiply)
			matDownsample:SetTexture("$fbtexture", ctx.cur)
			render.PushRenderTarget(tex)
			render.SetMaterial(matDownsample)
			render.DrawScreenQuad()
			render.BlurRenderTarget(tex, p.size, p.size, math.floor(p.passes))
			render.PopRenderTarget()
			matDownsample:SetTexture("$fbtexture", render.GetScreenEffectTexture())
			-- the bloom is added to the frame in place
			matBloom:SetFloat("$levelr", 1)
			matBloom:SetFloat("$levelg", 1)
			matBloom:SetFloat("$levelb", 1)
			matBloom:SetFloat("$colormul", p.color)
			matBloom:SetTexture("$basetexture", tex)
			render.PushRenderTarget(ctx.cur)
			render.SetMaterial(matBloom)
			render.DrawScreenQuad()
			render.PopRenderTarget()
		end })

local matSharpen = Material("pp/sharpen")
define({ id = "sharpen", cat = "shaders", params = {
			{ key = "contrast", min = 0, max = 10, default = 1 },
			{ key = "distance", min = 0, max = 5, default = 1 },
		},
		apply = function(ctx, p)
			matSharpen:SetFloat("$contrast", p.contrast)
			matSharpen:SetFloat("$distance", p.distance / ctx.w)
			shaderPass(ctx, matSharpen)
		end })

local matSobel = Material("pp/sobel")
define({ id = "sobel", cat = "shaders", params = { { key = "threshold", min = 0, max = 1, default = 0.11 } },
		apply = function(ctx, p)
			matSobel:SetFloat("$threshold", p.threshold)
			shaderPass(ctx, matSobel)
		end })

-- ToyTown: blur of the top and bottom bands of the frame ("miniature")
local matToyTown = Material("pp/toytown-top")
define({ id = "toytown", cat = "shaders", params = {
			{ key = "passes", min = 1, max = 10, default = 3, decimals = 0 },
			{ key = "size", min = 0, max = 1, default = 0.4 },
		},
		apply = function(ctx, p)
			local hh = math.floor(ctx.h * math.Clamp(p.size, 0, 1))
			if hh < 1 then return end
			for _ = 1, math.Clamp(math.floor(p.passes), 1, 10) do
				local src = snapshot(ctx)
				matToyTown:SetTexture("$basetexture", src)
				matToyTown:SetTexture("$fbtexture", src)
				render.PushRenderTarget(ctx.cur)
				cam.Start2D()
				render.SetMaterial(matToyTown)
				quad(0, 0, ctx.w, hh, 0, 0, 1, 1)
				quad(0, ctx.h - hh, ctx.w, ctx.h, 0, 1, 1, 0)
				cam.End2D()
				render.PopRenderTarget()
			end
			local fb = render.GetScreenEffectTexture()
			matToyTown:SetTexture("$basetexture", fb)
			matToyTown:SetTexture("$fbtexture", fb)
		end })

local matTexturize = Material("pp/texturize")
define({ id = "texturize", cat = "texturize", params = {
			{ key = "material", list = "TexturizeMaterials", default = "pp/texturize/plain.png" },
			{ key = "scale", min = 0.1, max = 8, default = 1 },
		},
		apply = function(ctx, p)
			local m = material(p.material)
			local tex = m and m:GetTexture("$basetexture")
			if not tex then return end
			matTexturize:SetFloat("$scalex", (ctx.w / 64) * p.scale)
			matTexturize:SetFloat("$scaley", (ctx.h / 64 / 8) * p.scale)
			matTexturize:SetTexture("$basetexture", tex)
			shaderPass(ctx, matTexturize)
		end })

-- Overlay: a material over the frame. Refracting materials (the Refract shader) get the
-- frame through $basetexture — that is what they distort.
define({ id = "overlay", cat = "overlay", params = {
			{ key = "material", list = "OverlayMaterials", default = "effects/combine_binocoverlay" },
			{ key = "refract", min = -1, max = 1, default = 0.3 },
		},
		apply = function(ctx, p)
			local m = material(p.material)
			if not m then return end
			local refract = string.find(string.lower(m:GetShader() or ""), "refract", 1, true) ~= nil
			local src = snapshot(ctx)
			m:SetFloat("$envmap", 0)
			m:SetFloat("$envmaptint", 0)
			m:SetFloat("$refractamount", p.refract)
			m:SetInt("$ignorez", 1)
			if refract then m:SetTexture("$basetexture", src) end
			render.PushRenderTarget(ctx.cur)
			render.SetMaterial(m)
			render.DrawScreenQuad()
			render.PopRenderTarget()
			if refract then m:SetTexture("$basetexture", render.GetScreenEffectTexture()) end
		end })

-- Custom shader: a screenspace_general material with its own pixel shader
-- (cl_shaders.lua). The frame is fed into those textures of the material where it expects
-- the frame (usually $basetexture = _rt_FullFrameFB), numbers — into $c0_x … $c3_w. Every
-- material has its own parameters, so the effect stores them as is (def.dynamic).
FX.SHADER_SLOTS = 3

local function applyShader(ctx, p)
	local Sd = SPeditor.Shaders
	local info = Sd and Sd.Get(p.material)
	local m = info and Sd.Material(info)
	if not m then return end
	for _, prm in ipairs(info.params) do
		m:SetFloat(prm.name, math.Clamp(tonumber(p[prm.key]) or prm.default, -100000, 100000))
	end
	-- the source frame lies under the shader: the shader may draw with transparency or not the whole frame
	render.PushRenderTarget(ctx.other)
	matCopy:SetTexture("$basetexture", ctx.cur)
	render.SetMaterial(matCopy)
	render.DrawScreenQuad()
	local ok, err = pcall(function()
		for _, slot in ipairs(info.inputs) do m:SetTexture(slot, ctx.cur) end
		render.SetMaterial(m)
		render.DrawScreenQuad()
	end)
	render.PopRenderTarget()
	local fb = render.GetScreenEffectTexture()
	for _, slot in ipairs(info.inputs) do m:SetTexture(slot, fb) end
	if not ok then error(err, 0) end
	swap(ctx)
end

for i = 1, FX.SHADER_SLOTS do
	define({ id = "shader" .. i, cat = "custom", dynamic = true, params = { { key = "material", shader = true, default = "" } },
			apply = applyShader })
end

-- Vignette: darkening towards the frame corners (a grid with alpha in the vertices)
define({ id = "vignette", cat = "lens", params = {
			{ key = "strength", min = 0, max = 1, default = 0.75 },
			{ key = "radius", min = 0, max = 1, default = 0.3 },
		},
		apply = function(ctx, p)
			local strength = math.Clamp(p.strength, 0, 1)
			if strength < 0.01 then return end
			local a = ctx.aspect
			local norm = 1 / math.sqrt(a * a + 1)
			local inner = math.Clamp(p.radius, 0, 0.98)
			local function alpha(u, v)
				local dx, dy = (u - 0.5) * 2, (v - 0.5) * 2
				local r = math.sqrt((dx * a) ^ 2 + dy ^ 2) * norm
				local t = math.Clamp((r - inner) / (1 - inner), 0, 1)
				return t * t * (3 - 2 * t) * strength * 255
			end
			local n = 32
			render.PushRenderTarget(ctx.cur)
			cam.Start2D()
			render.SetMaterial(matTint)
			mesh.Begin(MATERIAL_QUADS, n * n)
			local ok, err = pcall(function()
				for j = 0, n - 1 do
					for i = 0, n - 1 do
						for _, c in ipairs({ { i, j }, { i + 1, j }, { i + 1, j + 1 }, { i, j + 1 } }) do
							local u, v = c[1] / n, c[2] / n
							mesh.Position(Vector(u * ctx.w, v * ctx.h, 0))
							mesh.TexCoord(0, u, v)
							mesh.Color(0, 0, 0, alpha(u, v))
							mesh.AdvanceVertex()
						end
					end
				end
			end)
			mesh.End()
			cam.End2D()
			render.PopRenderTarget()
			if not ok then error(err, 0) end
		end })

FX.Cats = { "sfm", "lens", "color", "shaders", "custom", "texturize", "overlay" }

-- Order of application: geometry, tone and colour, then shaders (stock and custom),
-- overlay and vignette
local ORDER = { "fisheye", "hdr", "curves", "bloom", "sharpen", "sobel", "toytown", "shader1", "shader2", "shader3",
	"texturize", "overlay", "vignette" }
FX.Order = {}
for _, id in ipairs(ORDER) do
	if FX.ById[id] then FX.Order[#FX.Order + 1] = FX.ById[id] end
end

---------------------------------------------------------------------
-- Camera settings
---------------------------------------------------------------------
function FX.Get(fx, id, key)
	local def = FX.ById[id]
	local v = fx and fx[id] and fx[id][key]
	for _, prm in ipairs(def and def.params or {}) do
		-- a curve is four strings: curve_m (master), curve_r, curve_g, curve_b
		if prm.curve and string.sub(key, 1, #prm.key + 1) == prm.key .. "_" then
			return isstring(v) and v or DEFAULT_CURVE
		end
		if prm.key == key then
			if prm.list or prm.shader then return isstring(v) and v or prm.default end
			return math.Clamp(tonumber(v) or prm.default, prm.min, prm.max)
		end
	end
	return v
end

function FX.IsOn(fx, id)
	return fx ~= nil and istable(fx[id]) and fx[id].on == true
end

-- Enabled effects of a camera; nil — no effects (also for the work camera)
function FX.For(ent)
	local fx = IsValid(ent) and C.GetCameraFX(ent) or nil
	if not fx then return nil end
	for _, def in ipairs(FX.Defs) do
		if FX.IsOn(fx, def.id) then return fx end
	end
	return nil
end

-- Depth of field of a camera: { focus, aperture, samples }, or nil if the camera has none
function FX.DOF(fx)
	if not FX.IsOn(fx, "dof") then return nil end
	return { focus = FX.Get(fx, "dof", "focus"), aperture = FX.Get(fx, "dof", "aperture"),
		samples = math.floor(FX.Get(fx, "dof", "samples") + 0.5) }
end

-- Tone map scale of a camera, or nil
function FX.ToneScale(fx)
	if not FX.IsOn(fx, "tonemap") then return nil end
	return FX.Get(fx, "tonemap", "scale")
end

-- Field of view with which the scene must be shot for a camera with the effects fx
function FX.SourceFOV(fx, fov)
	if not FX.IsOn(fx, "fisheye") then return fov end
	local k = fishK(FX.Get(fx, "fisheye", "strength"))
	if k < 0.01 then return fov end
	local centre = k / math.tan(k)                    -- scale of the frame centre after the distortion
	return math.Clamp(math.deg(2 * math.atan(math.tan(math.rad(fov) / 2) / centre)), fov, 165)
end

local extras = {}
local function extraRT(w, h)
	local key = w .. "x" .. h
	local rt = extras[key]
	if not rt then
		rt = GetRenderTarget("speditor_fxx_" .. key, w, h)
		extras[key] = rt
	end
	return rt
end

-- rt and spare — two textures of size w x h; the frame is in rt (it will be destroyed).
-- Returns the texture with the finished frame. aspect — the real frame proportions
-- if the frame is stretched over the whole texture (preview).
function FX.Apply(rt, spare, w, h, fx, aspect)
	local ctx = { w = w, h = h, aspect = aspect or (w / h), cur = rt, other = spare, extra = extraRT(w, h) }
	for _, def in ipairs(FX.Order) do
		if FX.IsOn(fx, def.id) then
			local p = {}
			for _, prm in ipairs(def.params) do
				if prm.curve then
					for _, ch in ipairs({ "m", "r", "g", "b" }) do
						local key = prm.key .. "_" .. ch
						p[key] = FX.Get(fx, def.id, key)
					end
				else
					p[prm.key] = FX.Get(fx, def.id, prm.key)
				end
			end
			if def.dynamic then
				for k, v in pairs(fx[def.id]) do
					if p[k] == nil then p[k] = v end
				end
			end
			local ok, err = pcall(def.apply, ctx, p)
			if not ok and FX.lastError ~= err then
				FX.lastError = err
				ErrorNoHalt("[SPeditor] effect '" .. def.id .. "': " .. tostring(err) .. "\n")
			end
		end
	end
	return ctx.cur
end
