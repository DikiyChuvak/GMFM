--[[
GM:FM — the lighting of the whole map, the client side (b0.2 round 6). SFM has a directional
light (DmeDirectionalLight: the sun, shadows over everything) and an ambient one
(DmeAmbientLight); the "CSM Editor" and "Light / Environment Editor" addons do the same for
GMod. This is GM:FM's own take, saved with the scene and edited in the Environment window
(cl_ui_env.lua):

  sun   — the sun with cascaded shadows: 1 … 3 orthographic projected textures along the
          sun's direction, centred on the view being drawn (every viewport, every render
          pass: the "GMFM_PreView" hook of cl_render.lua), each one a few times wider than the
          one before. Each cascade's texture is a mask made here: the inner cascade's square
          is cut out of the next one with a soft edge, so where two overlap the light adds up
          to exactly one sun. The direction is the map's (util.GetSunInfo) or its own.
  ambient — the brightness of the map's baked light (light style 0, server: sv_env.lua);
          staticSun = false turns the map's baked sun off where it can be (light_environment)
  sky   — the 2D skybox (sv_skyname) and the painted sky (env_skypaint, server)
  fog   — the fog of the world and of the 3D skybox, drawn by the client (SetupWorldFog)

Env.cur holds the settings; Env.Set(path, value) changes one and applies it.
]]
SPeditor.Env = SPeditor.Env or {}
local Env = SPeditor.Env
local C = SPeditor.Client
local R = SPeditor.Render

local function defaults()
	return {
		sun = { on = false, mapDir = true, pitch = 50, yaw = 306, color = Color(255, 236, 205), bright = 1.6,
			soft = 0.6, cascades = 3, reach = 1, staticSun = true },
		ambient = 13,
		mapSounds = true,
		sky = { name = nil, paint = nil },
		fog = { on = false, start = 300, finish = 6000, color = Color(190, 200, 215), density = 0.75, sky = true },
	}
end
Env.cur = Env.cur or defaults()
Env.info = Env.info or { hasLightEnv = false, sunDir = nil, sky = nil, hasPaint = false }

---------------------------------------------------------------------
-- The sun's direction (towards the sun)
---------------------------------------------------------------------
function Env.MapSunDir()
	-- what the server says the map had (the window may have moved env_sun since)
	if Env.info.sunDir and not Env.info.sunDir:IsZero() then return Env.info.sunDir end
	local si = util.GetSunInfo and util.GetSunInfo()
	if si and si.direction and not si.direction:IsZero() then return si.direction:GetNormalized() end
	return Angle(-50, 306, 0):Forward()
end

function Env.SunDir()
	local s = Env.cur.sun
	if s.mapDir then return Env.MapSunDir() end
	return Angle(-math.Clamp(s.pitch, 1, 90), s.yaw, 0):Forward()
end

-- elevation and yaw of a direction (for the window's sliders when "from the map" is turned off)
function Env.DirAngles(dir)
	local a = dir:Angle()
	return math.Clamp(-math.NormalizeAngle(a.p), 1, 90), (a.y % 360)
end

---------------------------------------------------------------------
-- Cascade masks
---------------------------------------------------------------------
local MASK = 256
local GRID = 64
local HEIGHT, NEAR_Z, FAR_Z = 32768, 25000, 49152
-- the half sizes of the cascades (units) by their number; times the "reach"
local SIZES = { { 4096 }, { 640, 4096 }, { 256, 1536, 8192 } }

local function ss(a, b, t)
	t = math.Clamp((t - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end
-- how much of the sun a cascade of half size s gives at a point d (square distance, units)
local function own(d, s) return 1 - ss(0.8, 0.97, d / s) end

local masks = {}          -- [key] = { rt, mat-less texture, ready }
local pendingMasks = {}

local function maskFor(sizes, i)
	local key = table.concat(sizes, "_") .. "#" .. i
	local m = masks[key]
	if m then return m end
	m = { key = key, rt = GetRenderTargetEx("gmfm_csm_" .. key, MASK, MASK, RT_SIZE_LITERAL,
		MATERIAL_RT_DEPTH_NONE, 4 + 8, 0, IMAGE_FORMAT_RGBA8888), sizes = sizes, i = i }
	masks[key] = m
	pendingMasks[#pendingMasks + 1] = m
	return m
end

-- the value of mask i at (x, y) in -1 … 1 of its own square
local function maskValue(sizes, i, x, y)
	local s = sizes[i]
	local d = math.max(math.abs(x), math.abs(y)) * s
	local v = own(d, s)
	-- what the cascades inside it already give is left out
	local inner = 0
	for j = 1, i - 1 do inner = inner + (1 - inner) * own(d, sizes[j]) end
	return v * (1 - inner)
end

local function buildMask(m)
	render.PushRenderTarget(m.rt)
	render.Clear(0, 0, 0, 255, true, true)
	cam.Start2D()
	local vals = {}
	for j = 0, GRID do
		vals[j] = {}
		for i = 0, GRID do
			vals[j][i] = math.Clamp(maskValue(m.sizes, m.i, i / GRID * 2 - 1, j / GRID * 2 - 1), 0, 1) * 255
		end
	end
	local cell = MASK / GRID
	local function vert(i, j)
		local v = vals[j][i]
		mesh.Position(Vector(i * cell, j * cell, 0))
		mesh.Color(v, v, v, 255)
		mesh.AdvanceVertex()
	end
	render.SetColorMaterial()
	for _, mode in ipairs({ MATERIAL_CULLMODE_CW, MATERIAL_CULLMODE_CCW }) do
		render.CullMode(mode)
		for j = 0, GRID - 1 do
			mesh.Begin(MATERIAL_QUADS, GRID)
			for i = 0, GRID - 1 do
				vert(i, j) vert(i + 1, j) vert(i + 1, j + 1) vert(i, j + 1)
			end
			mesh.End()
		end
	end
	render.CullMode(MATERIAL_CULLMODE_CCW)
	cam.End2D()
	render.PopRenderTarget()
	m.ready = true
end

---------------------------------------------------------------------
-- The cascades
---------------------------------------------------------------------
local cascades = {}       -- { pt, size, mask }
local layout = ""

local function clearCascades()
	for _, c in ipairs(cascades) do
		if IsValid(c.pt) then c.pt:Remove() end
	end
	cascades = {}
	layout = ""
end

function Env.SunActive()
	return Env.cur.sun.on and C.active and true or false
end

local function sizesNow()
	local s = Env.cur.sun
	local base = SIZES[math.Clamp(math.floor(s.cascades or 3), 1, 3)]
	local out = {}
	for i, v in ipairs(base) do out[i] = math.floor(v * math.Clamp(s.reach or 1, 0.25, 8)) end
	return out
end

local function ensureCascades()
	local sizes = sizesNow()
	local key = table.concat(sizes, "_")
	if key == layout then return end
	clearCascades()
	layout = key
	for i, s in ipairs(sizes) do
		local pt = ProjectedTexture()
		pt:SetEnableShadows(true)
		pt:SetOrthographic(true, s, s, s, s)
		pt:SetNearZ(NEAR_Z)
		pt:SetFarZ(FAR_Z)
		pt:SetConstantAttenuation(1)
		pt:SetLinearAttenuation(0)
		pt:SetQuadraticAttenuation(0)
		local m = maskFor(sizes, i)
		cascades[i] = { pt = pt, size = s, mask = m, masked = false }
		-- until the mask is drawn: a plain white texture of the game (no cut-outs yet)
		pt:SetTexture("effects/flashlight001")
	end
end

-- snapping a cascade to its own texel grid in the light's space: shadows do not crawl when
-- the camera moves
local function snap(pos, size, ang)
	local res = GetConVarNumber("r_flashlightdepthres")
	if not res or res <= 0 then res = 1024 end
	local step = size * 2 / res
	local right, up, fwd = ang:Right(), ang:Up(), ang:Forward()
	local x = math.floor(pos:Dot(right) / step + 0.5) * step
	local y = math.floor(pos:Dot(up) / step + 0.5) * step
	return right * x + up * y + fwd * pos:Dot(fwd)
end

-- Put the cascades around the view at origin (called before each view is drawn)
function Env.PlaceSun(origin)
	if not Env.SunActive() then
		if #cascades > 0 then clearCascades() end
		return
	end
	ensureCascades()
	local s = Env.cur.sun
	local dir = Env.SunDir()
	local ang = (-dir):Angle()
	local col = s.color or color_white
	-- the engine draws a projected texture at 1/4 with HDR and at 2x without (the flashlight
	-- scale of its shaders): the same "brightness" looks the same either way
	local hdrScale = render.GetHDREnabled() and 4 or 0.5
	local n = #cascades
	for i, c in ipairs(cascades) do
		local pt = c.pt
		if IsValid(pt) then
			if c.mask.ready and not c.masked then
				pt:SetTexture(c.mask.rt)
				c.masked = true
			end
			local center = snap(origin + dir * HEIGHT, c.size, ang)
			pt:SetPos(center)
			pt:SetAngles(ang)
			pt:SetColor(Color(col.r, col.g, col.b))
			pt:SetBrightness(math.Clamp(s.bright or 1, 0, 50) * hdrScale)
			pt:SetShadowDepthBias(0.00004 * i)
			pt:SetShadowSlopeScaleDepthBias(2)
			-- a softer edge on the wide cascades would smear them: the filter shrinks with the size
			pt:SetShadowFilter(math.Clamp(s.soft or 0.5, 0, 4) * 0.2 / (4 ^ (i - 1)))
			pt:SetEnableShadows(true)
			pt:Update()
		end
	end
	Env.lastOrigin = origin
	return n
end

SPeditor.Hook("PreRender", "GMFM.EnvMasks", function()
	if #pendingMasks == 0 then return end
	local list = pendingMasks
	pendingMasks = {}
	for _, m in ipairs(list) do
		local ok, err = pcall(buildMask, m)
		if not ok then ErrorNoHalt("[GM:FM] sun mask: " .. tostring(err) .. "\n") end
	end
end)

-- every view of the editor (viewports, renders) — the cascades go to its camera
SPeditor.Hook("GMFM_PreView", "GMFM.EnvSun", function(src)
	if src and src.origin then Env.PlaceSun(src.origin) end
end)
-- the game's own view (behind the editor, the "engine frame" render)
SPeditor.Hook("RenderScene", "GMFM.EnvSun", function(origin)
	if Env.SunActive() or #cascades > 0 then Env.PlaceSun(origin) end
end)

---------------------------------------------------------------------
-- Fog
---------------------------------------------------------------------
local function fogOn()
	local f = Env.cur.fog
	if not (f.on and C.active) then return false end
	-- the depth pass of the ambient occlusion draws its own fog
	if R and R.DepthPassActive and R.DepthPassActive() then return false end
	return true
end

local function applyFog(scale)
	local f = Env.cur.fog
	local col = f.color or color_white
	render.FogMode(MATERIAL_FOG_LINEAR)
	render.FogStart(math.max(f.start or 0, 0) * scale)
	render.FogEnd(math.max(f.finish or 1, (f.start or 0) + 1) * scale)
	render.FogMaxDensity(math.Clamp(f.density or 1, 0, 1))
	render.FogColor(col.r, col.g, col.b)
	return true
end

SPeditor.Hook("SetupWorldFog", "GMFM.EnvFog", function()
	if fogOn() then return applyFog(1) end
end)
SPeditor.Hook("SetupSkyboxFog", "GMFM.EnvFog", function(scale)
	if fogOn() and Env.cur.fog.sky then return applyFog(scale) end
end)
-- the scene's fog over a map's own fog hook (gm_scrapland has one, and it ran first): the
-- other fog hooks are off while the fog is on (b0.2.1), and back when it is off
local unmuteFog
SPeditor.Hook("PreRender", "GMFM.EnvFogFirst", function()
	local on = Env.cur.fog.on and C.active
	if on and not unmuteFog then
		unmuteFog = SPeditor.MuteOtherHooks({ "SetupWorldFog", "SetupSkyboxFog" })
	elseif not on and unmuteFog then
		unmuteFog()
		unmuteFog = nil
	end
end)

---------------------------------------------------------------------
-- The server's part: map brightness, the baked sun, the sky
---------------------------------------------------------------------
local pendingSend, sendAt = nil, 0

local function send(d)
	net.Start(SPeditor.Net.Env)
	SPeditor.WriteTable(d)
	net.SendToServer()
end

-- the fields go together after a short pause (a slider sends one message, not a hundred)
function Env.SendServer(d)
	pendingSend = pendingSend or {}
	for k, v in pairs(d) do pendingSend[k] = v end
	sendAt = RealTime() + 0.25
end

SPeditor.Hook("Think", "GMFM.EnvSend", function()
	if pendingSend and RealTime() >= sendAt then
		local d = pendingSend
		pendingSend = nil
		send(d)
	end
end)

function Env.ServerState()
	local cur = Env.cur
	local d = { ambient = cur.ambient, staticSun = not (cur.sun.on and cur.sun.staticSun == false) }
	if cur.sky.name then d.sky = cur.sky.name end
	if cur.sky.paint then d.paint = cur.sky.paint end
	if cur.sun.on or not cur.sun.mapDir then d.sunDir = Env.SunDir() end
	d.mapSounds = cur.mapSounds ~= false
	return d
end

net.Receive(SPeditor.Net.EnvLightmaps, function()
	render.RedownloadAllLightmaps(true, true)
end)

-- the map's sounds went quiet (sv_env.lua): the soundscape playing now fades out at once,
-- the server has turned off the ones that would start it again
net.Receive(SPeditor.Net.EnvMapSounds, function()
	if not net.ReadBool() then RunConsoleCommand("stopsoundscape") end
end)

net.Receive(SPeditor.Net.EnvInfo, function()
	Env.info.hasLightEnv = net.ReadBool()
	local dir = net.ReadVector()
	Env.info.sunDir = (not dir:IsZero()) and dir or nil
	Env.info.sky = net.ReadString()
	Env.info.hasPaint = net.ReadBool()
	hook.Run("GMFM_EnvInfo")
end)

function Env.RequestInfo()
	net.Start(SPeditor.Net.EnvInfo)
	net.SendToServer()
end

---------------------------------------------------------------------
-- Changing settings
---------------------------------------------------------------------
-- path: "sun.bright", "fog.on", "ambient"… value: the new value
function Env.Set(path, value)
	local t, last = Env.cur, nil
	local parts = string.Explode(".", path)
	for i = 1, #parts - 1 do
		t[parts[i]] = t[parts[i]] or {}
		t = t[parts[i]]
	end
	last = parts[#parts]
	t[last] = value
	local root = parts[1]
	if root == "ambient" then
		Env.SendServer({ ambient = Env.cur.ambient })
	elseif root == "mapSounds" then
		Env.SendServer({ mapSounds = Env.cur.mapSounds ~= false })
	elseif root == "sky" then
		local d = {}
		if last == "name" then d.sky = value else d.paint = Env.cur.sky.paint end
		Env.SendServer(d)
	elseif root == "sun" then
		if last == "on" or last == "staticSun" then
			Env.SendServer({ staticSun = not (Env.cur.sun.on and Env.cur.sun.staticSun == false) })
		end
		if last == "pitch" or last == "yaw" or last == "mapDir" or last == "on" then
			if not Env.cur.sun.mapDir then Env.SendServer({ sunDir = Env.SunDir() }) end
		end
		if not Env.SunActive() then clearCascades() end
	end
	hook.Run("GMFM_EnvChanged", path, value)
end

-- Back to the map as it is: the server undoes its changes, the client's sun and fog go off
function Env.Reset()
	Env.cur = defaults()
	clearCascades()
	pendingSend = nil
	send({ reset = true })
	hook.Run("GMFM_EnvChanged", "reset")
end

---------------------------------------------------------------------
-- Saved with the scene (cl_camera.lua: C.GetSceneMeta / SceneLoaded)
---------------------------------------------------------------------
local function colorOut(c) return c and { c.r, c.g, c.b } or nil end
local function colorIn(t, def)
	if istable(t) and tonumber(t[1]) then
		return Color(math.Clamp(tonumber(t[1]) or 0, 0, 255), math.Clamp(tonumber(t[2]) or 0, 0, 255), math.Clamp(tonumber(t[3]) or 0, 0, 255))
	end
	if istable(t) and tonumber(t.r) then return Color(t.r, t.g, t.b) end
	return def
end

function Env.Serialize()
	local c = Env.cur
	local paint
	if c.sky.paint then
		paint = {}
		for k, v in pairs(c.sky.paint) do paint[k] = isvector(v) and { v.x, v.y, v.z } or v end
	end
	return {
		sun = { on = c.sun.on, mapDir = c.sun.mapDir, pitch = c.sun.pitch, yaw = c.sun.yaw, color = colorOut(c.sun.color),
			bright = c.sun.bright, soft = c.sun.soft, cascades = c.sun.cascades, reach = c.sun.reach, staticSun = c.sun.staticSun },
		ambient = c.ambient,
		mapSounds = c.mapSounds == false and false or nil,
		sky = { name = c.sky.name, paint = paint },
		fog = { on = c.fog.on, start = c.fog.start, finish = c.fog.finish, color = colorOut(c.fog.color), density = c.fog.density, sky = c.fog.sky },
	}
end

-- t — what a scene file holds (external data: every field is checked)
function Env.Deserialize(t)
	local d = defaults()
	if istable(t) then
		local s = istable(t.sun) and t.sun or {}
		d.sun.on = s.on == true
		d.sun.mapDir = s.mapDir ~= false
		d.sun.pitch = math.Clamp(tonumber(s.pitch) or d.sun.pitch, 1, 90)
		d.sun.yaw = (tonumber(s.yaw) or d.sun.yaw) % 360
		d.sun.color = colorIn(s.color, d.sun.color)
		d.sun.bright = math.Clamp(tonumber(s.bright) or d.sun.bright, 0, 50)
		d.sun.soft = math.Clamp(tonumber(s.soft) or d.sun.soft, 0, 4)
		d.sun.cascades = math.Clamp(math.floor(tonumber(s.cascades) or 3), 1, 3)
		d.sun.reach = math.Clamp(tonumber(s.reach) or 1, 0.25, 8)
		d.sun.staticSun = s.staticSun ~= false
		d.ambient = math.Clamp(math.floor(tonumber(t.ambient) or 13), 1, 26)
		d.mapSounds = t.mapSounds ~= false
		local sk = istable(t.sky) and t.sky or {}
		if isstring(sk.name) and #sk.name <= 64 and string.match(sk.name, "^[%w_%-/%.]+$") then d.sky.name = sk.name end
		if istable(sk.paint) then
			local p = {}
			for k, v in pairs(sk.paint) do
				if isstring(k) and #k < 32 then
					if istable(v) and tonumber(v[1]) then p[k] = Vector(tonumber(v[1]), tonumber(v[2]) or 0, tonumber(v[3]) or 0)
					elseif isvector(v) then p[k] = v
					elseif isnumber(v) or isbool(v) then p[k] = v end
				end
			end
			d.sky.paint = p
		end
		local f = istable(t.fog) and t.fog or {}
		d.fog.on = f.on == true
		d.fog.start = math.Clamp(tonumber(f.start) or d.fog.start, 0, 100000)
		d.fog.finish = math.Clamp(tonumber(f.finish) or d.fog.finish, 1, 200000)
		d.fog.color = colorIn(f.color, d.fog.color)
		d.fog.density = math.Clamp(tonumber(f.density) or d.fog.density, 0, 1)
		d.fog.sky = f.sky ~= false
	end
	return d
end

-- A scene was loaded: its environment (a scene without one leaves the map as it is)
function Env.ApplyScene(t)
	if not istable(t) then return end
	Env.cur = Env.Deserialize(t)
	clearCascades()
	Env.SendServer(Env.ServerState())
	hook.Run("GMFM_EnvChanged", "scene")
end

-- the editor closed: the sun's lamps go (the map's own state stays until reset)
SPeditor.Hook("SPeditor_StateChanged", "GMFM.Env", function(active)
	if not active then clearCascades() end
end)
