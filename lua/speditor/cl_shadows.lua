--[[
SPeditor — shadow library.

What the GMod API allows (checked against the wiki):
  * ProjectedTexture (spot) casts shadows: SetEnableShadows, SetShadowFilter
    (edge blur), SetShadowDepthBias, SetShadowSlopeScaleDepthBias; after a
    change :Update() is needed — the light entity does that.
  * A point light (DynamicLight) CANNOT cast shadows — an engine
    limitation. Use a spot for shadows.
  * The shadow map resolution is set by r_flashlightdepthres; the engine reads it at
    start-up, so after a change vid_restart may be needed (or the
    launch option +r_flashlightdepthres).
  * Every shadow-casting spot is an expensive extra draw of the scene, hence the limit
    "max lights with shadows": the N nearest to the camera get shadows.

Extended settings:
  * shadow draw distance: a light farther than the given distance from the camera
    casts no shadows (speditor_shadow_dist, 0 — unlimited);
  * global softness multiplier: multiplies the edge blur of every light;
  * per light: near limit (near Z), slope bias, falloff,
    parallel beam, light mask — see the speditor_light entity and SPeditor.LightFields.

Prop shadows from the map light (render-to-texture) are a different engine mechanism:
  * r_shadows, r_shadowrendertotexture, r_shadowmaxrendered — client
    variables (on / off, detailed / blobs, how many shadows to draw);
  * length, colour and direction are set by the map entity shadow_control — the
    server edits it on the ShadowCtl message (values are kept in speditor_mapshadow_*).

API:
  SPeditor.Shadows.WantsShadows(lightEnt) -> bool   (called by the light entity)
  SPeditor.Shadows.GetSlope() / GetSoftScale() / GetDistance()
  SPeditor.Shadows.SetQuality(i)  / GetQuality()
  SPeditor.Shadows.QUALITY        — resolution presets
  SPeditor.Shadows.Map            — prop shadows: Get / Set / Apply / Reset
]]
SPeditor = SPeditor or {}
SPeditor.Shadows = SPeditor.Shadows or {}
local Sh = SPeditor.Shadows

local cvEnabled = CreateClientConVar("speditor_shadows", "1", true, false)
local cvMax     = CreateClientConVar("speditor_shadow_max", "4", true, false)
local cvQuality = CreateClientConVar("speditor_shadow_quality", "2", true, false)
local cvSlope   = CreateClientConVar("speditor_shadow_slope", "2", true, false)
local cvDist    = CreateClientConVar("speditor_shadow_dist", "0", true, false)
local cvSoftMul = CreateClientConVar("speditor_shadow_softscale", "1", true, false)

Sh.QUALITY = {
	{ name = "Low",    res = 512 },
	{ name = "Medium", res = 1024 },
	{ name = "High",   res = 2048 },
	{ name = "Ultra",  res = 4096 },
}

function Sh.IsEnabled() return cvEnabled:GetBool() end
function Sh.SetEnabled(on) RunConsoleCommand("speditor_shadows", on and "1" or "0") end

function Sh.GetMax() return math.Clamp(cvMax:GetInt(), 1, 16) end
function Sh.SetMax(n) RunConsoleCommand("speditor_shadow_max", tostring(math.Clamp(math.floor(n), 1, 16))) end

function Sh.GetSlope() return math.Clamp(cvSlope:GetFloat(), 0, 8) end
function Sh.SetSlope(v) RunConsoleCommand("speditor_shadow_slope", tostring(math.Clamp(v, 0, 8))) end

-- Shadow draw distance from the camera; 0 — unlimited
Sh.MAX_DISTANCE = 8000
function Sh.GetDistance() return math.Clamp(cvDist:GetFloat(), 0, Sh.MAX_DISTANCE) end
function Sh.SetDistance(v) RunConsoleCommand("speditor_shadow_dist", tostring(math.Clamp(math.floor(v), 0, Sh.MAX_DISTANCE))) end

-- Global shadow softness multiplier
function Sh.GetSoftScale() return math.Clamp(cvSoftMul:GetFloat(), 0, 4) end
function Sh.SetSoftScale(v) RunConsoleCommand("speditor_shadow_softscale", tostring(math.Round(math.Clamp(v, 0, 4), 2))) end

function Sh.GetQuality() return math.Clamp(cvQuality:GetInt(), 1, #Sh.QUALITY) end

function Sh.SetQuality(i)
	i = math.Clamp(math.floor(i), 1, #Sh.QUALITY)
	RunConsoleCommand("speditor_shadow_quality", tostring(i))
	RunConsoleCommand("r_flashlightdepthres", tostring(Sh.QUALITY[i].res))
end

-- Which lights get shadows: the N nearest to the camera among the enabled ones
local allowed = {}
local skipped = 0          -- how many lights were cut off by the draw distance
local nextScan = 0

local function rescan()
	allowed = {}
	skipped = 0
	if not Sh.IsEnabled() then return end
	local C = SPeditor.Client
	local origin = (C and C.GetView and select(1, C.GetView())) or EyePos()
	local list = {}
	local limit = Sh.GetDistance()
	for _, e in ipairs(ents.FindByClass("speditor_light")) do
		if IsValid(e) and e:GetLightEnabled() and e:GetLightType() == 1 and e:GetLightShadows() then
			local d = e:GetPos():DistToSqr(origin)
			-- the distance is measured to the lit area: a light may stand far away and shine nearby
			local reach = math.max(math.sqrt(d) - e:GetLightRadius(), 0)
			if limit <= 0 or reach <= limit then
				list[#list + 1] = { ent = e, d = d }
			else
				skipped = skipped + 1
			end
		end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	for i = 1, math.min(#list, Sh.GetMax()) do
		allowed[list[i].ent] = true
	end
end

hook.Add("Think", "SPeditor.ShadowScan", function()
	if RealTime() < nextScan then return end
	nextScan = RealTime() + 0.25
	rescan()
end)

function Sh.WantsShadows(ent)
	return allowed[ent] == true
end

-- How many lights actually cast shadows now (for the interface)
function Sh.ActiveCount()
	local n = 0
	for _ in pairs(allowed) do n = n + 1 end
	return n
end

-- How many lights are without shadows now because of the draw distance
function Sh.SkippedCount() return skipped end

---------------------------------------------------------------------
-- Prop shadows from the map light (render-to-texture)
---------------------------------------------------------------------
Sh.Map = Sh.Map or {}
local Map = Sh.Map
local Lim = SPeditor.MapShadowLimits

local cvMapOn    = CreateClientConVar("speditor_mapshadow", "0", true, false)   -- own values instead of the map's
local cvMapDist  = CreateClientConVar("speditor_mapshadow_dist", tostring(Lim.dist.default), true, false)
local cvMapDark  = CreateClientConVar("speditor_mapshadow_dark", tostring(Lim.dark.default), true, false)
local cvMapPitch = CreateClientConVar("speditor_mapshadow_pitch", tostring(Lim.pitch.default), true, false)
local cvMapYaw   = CreateClientConVar("speditor_mapshadow_yaw", tostring(Lim.yaw.default), true, false)
local cvMapOff   = CreateClientConVar("speditor_mapshadow_off", "0", true, false)

local MAP_CVARS = { dist = cvMapDist, dark = cvMapDark, pitch = cvMapPitch, yaw = cvMapYaw }

function Map.IsCustom() return cvMapOn:GetBool() end
function Map.IsDisabled() return cvMapOff:GetBool() end
function Map.Get(key) return math.Clamp(MAP_CVARS[key]:GetFloat(), Lim[key].min, Lim[key].max) end

local function send(reset)
	local C = SPeditor.Client
	if not C or not C.active then return end
	net.Start(SPeditor.Net.ShadowCtl)
	net.WriteBool(reset and true or false)
	net.WriteFloat(Map.Get("dist"))
	net.WriteUInt(math.floor(Map.Get("dark")), 8)
	net.WriteFloat(Map.Get("pitch"))
	net.WriteFloat(Map.Get("yaw"))
	net.WriteBool(Map.IsDisabled())
	net.SendToServer()
end

-- Send the values to the server (no more than a few times a second: sliders)
function Map.Apply()
	if not Map.IsCustom() then return end
	timer.Create("SPeditor.MapShadow", 0.1, 1, function() send(false) end)
end

function Map.Set(key, v)
	local cv = MAP_CVARS[key]
	if not cv then return end
	RunConsoleCommand(cv:GetName(), tostring(math.Round(math.Clamp(v, Lim[key].min, Lim[key].max), 1)))
	Map.Apply()
end

function Map.SetDisabled(on)
	RunConsoleCommand("speditor_mapshadow_off", on and "1" or "0")
	Map.Apply()
end

-- Switch on own values or bring back the map's
function Map.SetCustom(on)
	RunConsoleCommand("speditor_mapshadow", on and "1" or "0")
	timer.Remove("SPeditor.MapShadow")
	-- the variable value changes in the next frame
	timer.Simple(0.05, function() send(not on) end)
end

-- Own values are in effect while the editor is open: they are applied again on entering
-- (after a map change the shadow_control entity is a different one)
hook.Add("SPeditor_StateChanged", "SPeditor.MapShadow", function(on)
	if on and Map.IsCustom() then timer.Simple(0.5, function() send(false) end) end
end)

-- Client engine variables for prop shadows
Map.ENGINE = {
	enabled  = "r_shadows",
	detailed = "r_shadowrendertotexture",
	max      = "r_shadowmaxrendered",
}

function Map.GetEngine(key)
	local cv = GetConVar(Map.ENGINE[key])
	return cv and cv:GetInt() or 0
end

function Map.SetEngine(key, v)
	local name = Map.ENGINE[key]
	if name and GetConVar(name) then RunConsoleCommand(name, tostring(math.floor(v))) end
end
