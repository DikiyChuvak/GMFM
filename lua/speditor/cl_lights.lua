--[[
SPeditor — light library (a0.2): soft light and a visible source.

Everything is done with stock engine means, GShader Library is not required:
  * Soft edge (EdgeSoft). A spot light mask is a regular texture, and
    ProjectedTexture:SetTexture also accepts a render target (verified in game).
    So the mask is drawn once into its own texture and multiplied by a smooth falloff
    from the centre to the edge; the texture is shared by all lights with the same
    "mask + softness" pair.
  * Source size (SourceSize) — a real penumbra. A point-like spot gives a
    sharp shadow; a lamp with a size gives a shadow that blurs with distance from the object.
    The final render shoots the scene several times, each time moving the source to
    a new point of its disc, and averages the frames (the same accumulator as depth of
    field, cl_render.lua). The engine takes a move of the source inside one game frame
    into account at once — verified in game pixel by pixel. Viewports show a single
    pass (a sharp shadow); the result is in the Render window preview and in the file.
  * Editor masks ("speditor_gen/…") — soft light shapes (softbox, window,
    blinds, leaves, ring…) drawn by the editor itself: see Lt.GEN.
  * Glow — a sprite of the source in the picture, as on headlights and beacons: brighter
    when the spot points at the camera; hidden if the source is occluded.
  * Beam (Vol) — a visible cone of light in the air ("dust in the beam").

API:
  Lights.Mask(tex, edge) -> texture | path, key       mask with a soft edge
  Lights.TextureList() / Lights.TextureName(path)     all masks for the interface
  Lights.DrawEffects(ent)                             glow and beam (called by the light entity)
  Lights.SoftSamples()                                how many passes soft shadows need (0 — none)
  Lights.Jitter(i, n) / Lights.Restore()              move the sources for pass i of n / put them back
]]
SPeditor = SPeditor or {}
SPeditor.Lights = SPeditor.Lights or {}
local Lt = SPeditor.Lights

local cvSoft = CreateClientConVar("speditor_softlight_samples", "24", true, false)   -- passes for soft shadows in the render

---------------------------------------------------------------------
-- Mask with a soft edge
---------------------------------------------------------------------
local MASK_SIZE, STEPS, SEGS = 512, 24, 48
local LEVELS = 20                      -- softness steps (at most this many textures per mask)
local masks = {}                       -- [key] = { rt, ready }
local pending = {}
local matSrc = CreateMaterial("speditor_lightmask_src", "UnlitGeneric", { ["$nolod"] = "1" })

local function smooth(t) return t * t * (3 - 2 * t) end

-- a ring between radii r0 and r1 (in pixels) with brightness v0 and v1
local function ring(c, r0, r1, v0, v1)
	mesh.Begin(MATERIAL_QUADS, SEGS)
	for i = 0, SEGS - 1 do
		local a0, a1 = (i / SEGS) * math.pi * 2, ((i + 1) / SEGS) * math.pi * 2
		local c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
		mesh.Position(Vector(c + c0 * r0, c + s0 * r0, 0)) mesh.Color(v0, v0, v0, 255) mesh.AdvanceVertex()
		mesh.Position(Vector(c + c0 * r1, c + s0 * r1, 0)) mesh.Color(v1, v1, v1, 255) mesh.AdvanceVertex()
		mesh.Position(Vector(c + c1 * r1, c + s1 * r1, 0)) mesh.Color(v1, v1, v1, 255) mesh.AdvanceVertex()
		mesh.Position(Vector(c + c1 * r0, c + s1 * r0, 0)) mesh.Color(v0, v0, v0, 255) mesh.AdvanceVertex()
	end
	mesh.End()
end

---------------------------------------------------------------------
-- Editor masks ("speditor_gen/<id>"): soft light shapes that are missing among the
-- game textures. Each is a brightness function f(x, y) on the square [-1, 1] (x right,
-- y down); it returns a number 0..1 or three numbers r, g, b (a colour gel).
-- Drawn once into its own texture as a grid of coloured vertices. At the edge of the
-- square the function must give 0: outside the mask the engine repeats its border pixels.
---------------------------------------------------------------------
local GEN_PREFIX, GRID = "speditor_gen/", 128
local abs, exp, cos, sqrt, pi = math.abs, math.exp, math.cos, math.sqrt, math.pi

local function ss(a, b, t) return smooth(math.Clamp((t - a) / (b - a), 0, 1)) end
local function super(x, y, hw, hh) return ((abs(x) / hw) ^ 4 + (abs(y) / hh) ^ 4) ^ 0.25 end
local function radius(x, y) return sqrt(x * x + y * y) end
local function round(x, y, from) return 1 - ss(from or 0.6, 0.97, radius(x, y)) end

-- shadow blobs for "leaves": a fixed set (the same for every player)
local BLOBS = {}
do
	local seed = 7
	local function rnd()
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	for i = 1, 70 do BLOBS[i] = { rnd() * 2 - 1, rnd() * 2 - 1, 0.06 + rnd() * 0.13 } end
end

Lt.GEN = {
	{ id = "softbox", fn = function(x, y) return 1 - ss(0.45, 0.95, super(x, y, 1, 1)) end },
	{ id = "strip",   fn = function(x, y) return 1 - ss(0.5, 1, super(x, y, 0.4, 0.97)) end },
	{ id = "round",   fn = function(x, y) return exp(-(radius(x, y) * 1.75) ^ 2) * round(x, y, 0.8) end },
	{ id = "disc",    fn = function(x, y) return 1 - ss(0.84, 0.92, radius(x, y)) end },
	{ id = "ring",    fn = function(x, y) return exp(-((radius(x, y) - 0.6) / 0.17) ^ 2) * round(x, y, 0.85) end },
	{ id = "window",  fn = function(x, y)
		local frame = (1 - ss(0.66, 0.8, abs(x))) * (1 - ss(0.78, 0.92, abs(y)))
		return frame * ss(0.03, 0.09, abs(x)) * ss(0.03, 0.09, abs(y - 0.3)) * ss(0.03, 0.09, abs(y + 0.3))
	end },
	{ id = "blinds",  fn = function(x, y)
		return (1 - ss(0.7, 0.9, abs(x))) * (1 - ss(0.75, 0.93, abs(y))) * ss(0.3, 0.7, 0.5 + 0.5 * cos(y * pi * 8))
	end },
	{ id = "bars",    fn = function(x, y)
		return (1 - ss(0.75, 0.93, abs(x))) * (1 - ss(0.7, 0.9, abs(y))) * ss(0.25, 0.6, 0.5 + 0.5 * cos(x * pi * 6))
	end },
	{ id = "slit",    fn = function(x, y) return (1 - ss(0.45, 0.95, abs(x))) * (1 - ss(0.05, 0.22, abs(y))) end },
	{ id = "horizon", fn = function(x, y) return round(x, y, 0.5) * ((1 - y) * 0.5) ^ 1.6 end },
	{ id = "leaves",  fn = function(x, y)
		local shade = 1
		for _, b in ipairs(BLOBS) do
			shade = shade * (0.3 + 0.7 * ss(b[3] * 0.35, b[3], radius(x - b[1], y - b[2])))
		end
		return round(x, y, 0.55) * (0.06 + 0.94 * shade)
	end },
	{ id = "sunset",  fn = function(x, y)
		local v, t = round(x, y, 0.45), (1 - y) * 0.5        -- t: 0 at the bottom, 1 at the top
		return v, v * (0.42 + 0.45 * t), v * (0.16 + 0.5 * t * t)
	end },
	{ id = "split",   fn = function(x, y)
		local v, t = round(x, y, 0.5), ss(-0.25, 0.25, x)    -- red on the left, blue on the right
		return v * (1 - t), v * 0.12, v * t
	end },
}
local genById = {}
for _, g in ipairs(Lt.GEN) do genById[g.id] = g end

local function genOf(tex)
	if string.sub(tex, 1, #GEN_PREFIX) ~= GEN_PREFIX then return nil end
	return genById[string.sub(tex, #GEN_PREFIX + 1)]
end

local function drawGen(fn)
	-- brightness at the grid nodes is computed once
	local vals = {}
	for j = 0, GRID do
		local row = {}
		for i = 0, GRID do
			local r, g, b = fn(i / GRID * 2 - 1, j / GRID * 2 - 1)
			g, b = g or r, b or r
			row[i] = { math.Clamp(r, 0, 1) * 255, math.Clamp(g, 0, 1) * 255, math.Clamp(b, 0, 1) * 255 }
		end
		vals[j] = row
	end
	local cell = MASK_SIZE / GRID
	local function vert(i, j)
		local c = vals[j][i]
		mesh.Position(Vector(i * cell, j * cell, 0))
		mesh.Color(c[1], c[2], c[3], 255)
		mesh.AdvanceVertex()
	end
	render.SetColorMaterial()
	-- one row per call: a single large grid (tens of thousands of vertices) is not drawn at all
	for j = 0, GRID - 1 do
		mesh.Begin(MATERIAL_QUADS, GRID)
		for i = 0, GRID - 1 do
			vert(i, j) vert(i + 1, j) vert(i + 1, j + 1) vert(i, j + 1)
		end
		mesh.End()
	end
end

local function build(m)
	render.PushRenderTarget(m.rt)
	render.Clear(0, 0, 0, 255, true, true)
	if not m.gen then
		matSrc:SetTexture("$basetexture", m.tex)
		render.SetMaterial(matSrc)
		render.DrawScreenQuad()
	end
	cam.Start2D()
	if m.gen then
		for _, mode in ipairs({ MATERIAL_CULLMODE_CW, MATERIAL_CULLMODE_CCW }) do
			render.CullMode(mode)
			drawGen(m.gen.fn)
		end
	end

	-- multiply by the falloff: inside the radius (1 - edge) the mask is unchanged, towards the edge it fades
	if m.edge > 0 then
		render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD)
		render.SetColorMaterial()
		local c = MASK_SIZE / 2
		local inner = 1 - m.edge
		for _, mode in ipairs({ MATERIAL_CULLMODE_CW, MATERIAL_CULLMODE_CCW }) do   -- whichever faces the engine culls
			render.CullMode(mode)
			for k = 0, STEPS - 1 do
				local t0, t1 = k / STEPS, (k + 1) / STEPS
				ring(c, c * (inner + (1 - inner) * t0), c * (inner + (1 - inner) * t1),
					math.floor(255 * (1 - smooth(t0))), math.floor(255 * (1 - smooth(t1))))
			end
			ring(c, c, c * 1.5, 0, 0)       -- corners of the square outside the circle
		end
		render.OverrideBlend(false)
	end
	render.CullMode(MATERIAL_CULLMODE_CCW)
	cam.End2D()
	render.PopRenderTarget()
	m.ready = true
end

-- Drawing outside a frame is not allowed: masks are built in the next PreRender
hook.Add("PreRender", "SPeditor.LightMasks", function()
	if #pending == 0 then return end
	local list = pending
	pending = {}
	for _, m in ipairs(list) do
		local ok, err = pcall(build, m)
		if not ok then ErrorNoHalt("[SPeditor] light mask: " .. tostring(err) .. "\n") end
	end
end)

local FALLBACK = "effects/flashlight/soft"

-- Returns what is passed to ProjectedTexture:SetTexture and a key for the
-- "did the mask change" comparison. Until the texture is built — the original mask (for editor
-- masks — a soft spot from the game).
function Lt.Mask(tex, edge)
	local level = math.floor(math.Clamp(edge or 0, 0, 1) * LEVELS + 0.5)
	local gen = genOf(tex)
	local plain = gen and FALLBACK or tex
	if level <= 0 and not gen then return tex, tex end
	local key = tex .. "|" .. level
	local m = masks[key]
	if not m then
		local name = "speditor_lmask_" .. string.gsub(tex, "[^%w]", "_") .. "_" .. level
		m = {
			tex = tex, edge = level / LEVELS, gen = gen,
			rt = GetRenderTargetEx(name, MASK_SIZE, MASK_SIZE, RT_SIZE_LITERAL, MATERIAL_RT_DEPTH_NONE, 4 + 8, 0, IMAGE_FORMAT_RGBA8888),
		}
		masks[key] = m
		pending[#pending + 1] = m
	end
	if not m.ready then return plain, plain end
	return m.rt, key
end

---------------------------------------------------------------------
-- Mask list for the interface: editor masks, textures of the Lamp tool
-- (other addons add to the same list) and all other light textures found in the
-- game and mounted addons.
---------------------------------------------------------------------
-- folder and words in the file name (nil — everything fits). The engine's search pattern with
-- several "*" returns the whole folder (verified in game), so the filtering is done here.
local SCAN = {
	{ "effects/flashlight" },
	{ "effects", { "flashlight", "gobo", "caustic", "projected", "lightmask" } },
	{ "effects/gobo" }, { "effects/gobos" }, { "effects/lightmasks" }, { "gobo" }, { "gobos" },
}
local texCache, texCacheAt = nil, 0

function Lt.IsGenerated(tex) return genOf(tex) ~= nil end

function Lt.TextureName(path)
	local gen = genOf(path)
	if gen then return SPeditor.L("lmask_" .. gen.id) end
	local item = list.Get("LampTextures")[path]
	local name = item and item.Name or nil
	if name and string.sub(name, 1, 1) == "#" then name = language.GetPhrase(string.sub(name, 2)) end
	return name or string.gsub(path, "^effects/", "")
end

-- { { title = dictionary key, items = { path, … } }, … }
function Lt.TextureList()
	if texCache and RealTime() - texCacheAt < 30 then return texCache end
	local gen, lamp, found, seen = {}, {}, {}, {}
	for _, g in ipairs(Lt.GEN) do gen[#gen + 1] = GEN_PREFIX .. g.id end
	for path in pairs(list.Get("LampTextures")) do
		lamp[#lamp + 1] = path
		seen[string.lower(path)] = true
	end
	for _, sc in ipairs(SCAN) do
		for _, f in ipairs(file.Find("materials/" .. sc[1] .. "/*.vtf", "GAME") or {}) do
			local path = string.lower(sc[1] .. "/" .. string.StripExtension(f))
			local fits = sc[2] == nil
			for _, word in ipairs(sc[2] or {}) do
				if string.find(string.lower(f), word, 1, true) then fits = true break end
			end
			-- only a plain path goes to the server (see S.ApplyLight)
			if fits and not seen[path] and #path <= 96 and not string.find(path, "[^%w_%-/%.]") then
				seen[path] = true
				found[#found + 1] = path
			end
		end
	end
	local function byName(a, b) return Lt.TextureName(a) < Lt.TextureName(b) end
	table.sort(lamp, byName)
	table.sort(found)
	texCache = {
		{ title = "lmask_group_gen", items = gen },
		{ title = "lmask_group_lamp", items = lamp },
		{ title = "lmask_group_game", items = found },
	}
	texCacheAt = RealTime()
	return texCache
end

---------------------------------------------------------------------
-- Glow and beam
---------------------------------------------------------------------
local matGlow = Material("sprites/light_ignorez")
local matBeam = Material("effects/lamp_beam")
local BEAM_SEGS = 10

local function visible(ent, from, pos)
	local tr = util.TraceLine({
			start = from, endpos = pos, mask = MASK_OPAQUE,
			filter = function(e) return e ~= ent and SPeditor.IsEditable(e) and e:GetClass() ~= "speditor_camera" end,
	})
	return not tr.Hit
end

function Lt.DrawEffects(ent)
	if not ent:GetLightEnabled() then return end
	local bri = ent:GetLightBrightness()
	if bri <= 0 then return end
	local glow, vol = ent:GetGlowSize(), ent:GetVolStrength()
	if glow <= 0 and vol <= 0 then return end
	local C = SPeditor.Client
	if C and C.IsHidden and C.IsHidden(ent) then return end

	local c = ent:GetLightColor()
	local pos, ang = ent:GetPos(), ent:GetAngles()
	local fwd = ang:Forward()
	local spot = ent:GetLightType() == 1
	local eye = EyePos()

	-- beam: a camera-facing ribbon that widens like a cone and fades towards the end
	if vol > 0 and spot then
		local len = ent:GetLightRadius() * math.Clamp(ent:GetVolLength(), 0.05, 1)
		local ortho = ent:GetLightOrtho()
		local w0 = ortho and math.Clamp(ent:GetOrthoSize(), 8, 4000) * 2 or math.max(ent:GetSourceSize() * 2, 6)
		local spread = ortho and 0 or 2 * math.tan(math.rad(math.Clamp(ent:GetLightFOV(), 5, 120) / 2))
		local k = math.Clamp(vol, 0, 1) * math.min(bri / 2, 2)
		render.SetMaterial(matBeam)
		render.StartBeam(BEAM_SEGS + 1)
		for i = 0, BEAM_SEGS do
			local t = i / BEAM_SEGS
			local a = k * (1 - t) ^ 1.6
			render.AddBeam(pos + fwd * (len * t), w0 + spread * len * t, t,
				Color(math.min(c.x * 255 * a, 255), math.min(c.y * 255 * a, 255), math.min(c.z * 255 * a, 255), 255))
		end
		render.EndBeam()
	end

	-- glow: a spot is brighter when it points at the camera; from the side and behind — a faint glow
	if glow > 0 then
		local toEye = eye - pos
		local dist = toEye:Length()
		if dist < 8 then return end           -- the camera sits inside the source (the view "from the light")
		toEye:Mul(1 / dist)
		local facing = 1
		if spot then
			local half = math.rad(math.Clamp(ent:GetLightFOV(), 5, 120) / 2)
			local d = fwd:Dot(toEye)
			-- inside the cone — full brightness, then a smooth falloff down to 12 %
			facing = 0.12 + 0.88 * math.Clamp((d - math.cos(math.min(half * 2.2, math.pi))) / math.max(math.cos(half) - math.cos(math.min(half * 2.2, math.pi)), 0.01), 0, 1) ^ 2
		end
		if not visible(ent, eye, pos) then return end
		local a = math.Clamp(ent:GetGlowBright() * facing * math.min(bri / 2, 2), 0, 4)
		local size = glow * (0.55 + 0.45 * facing)
		render.SetMaterial(matGlow)
		local function sprite(s, m)
			local v = math.min(a * m, 1)
			render.DrawSprite(pos, s, s, Color(c.x * 255 * v, c.y * 255 * v, c.z * 255 * v, 255))
		end
		sprite(size, 0.6)                    -- wide halo
		sprite(size * 0.4, 1)                -- core
		if a > 1 then
			-- overexposure: a white core
			local w = math.min((a - 1) / 3, 1) * 255
			render.DrawSprite(pos, size * 0.2, size * 0.2, Color(w, w, w, 255))
		end
	end
end

---------------------------------------------------------------------
-- Soft shadows in the final render
---------------------------------------------------------------------
local function softLights()
	local list = {}
	for _, e in ipairs(ents.FindByClass("speditor_light")) do
		if IsValid(e) and e.UpdateLight and e:GetLightEnabled() and e:GetLightType() == 1 and e:GetSourceSize() > 0 then
			list[#list + 1] = e
		end
	end
	return list
end

function Lt.GetSampleCount() return math.Clamp(cvSoft:GetInt(), 2, 128) end
function Lt.SetSampleCount(n) RunConsoleCommand("speditor_softlight_samples", tostring(math.Clamp(math.floor(n), 2, 128))) end

-- How many passes soft shadows need; 0 — the scene has no lights with a size
function Lt.SoftSamples()
	if #softLights() == 0 then return 0 end
	return Lt.GetSampleCount()
end

-- Disc point for pass i of n; every light has its own rotation of the pattern, otherwise
-- the penumbras of different lamps would add up into identical bands
local function diskPoint(i, n, rot)
	local r = math.sqrt((i - 0.5) / n)
	local a = i * 2.39996323 + rot
	return r * math.cos(a), r * math.sin(a)
end

function Lt.Jitter(i, n)
	for _, e in ipairs(softLights()) do
		local jx, jy = diskPoint(i, n, e:EntIndex() * 1.7)
		e:UpdateLight(jx, jy)
	end
end

function Lt.Restore()
	for _, e in ipairs(softLights()) do e:UpdateLight(0, 0) end
end
