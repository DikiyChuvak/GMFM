--[[
GM:FM — the lighting of the whole map (b0.2 round 6, after the "Light / Environment Editor"
and "CSM Editor" addons and SFM's ambient / directional lights): what only the server can
change. The client's Environment window (cl_env.lua) sends the wanted state; the sun with
cascaded shadows and the fog are drawn by the client itself.

  ambient   1 … 26   the brightness of the map's baked light: light style 0 ("a" … "z",
                     the map's own is "m" = 13); clients reload their lightmaps
  staticSun bool     false — the map's light_environment is turned off (its baked sun goes,
                     the cascaded sun of the client takes its place; only maps where the
                     light_environment has a name keep it as an entity)
  sky       string   the 2D skybox (sv_skyname); "painted" — GMod's painted sky
  paint     table    the painted sky (env_skypaint, made when the map has none)
  sunDir    vector   the direction to the sun: env_sun's disc and the painted sky's sun

The map's own values are kept the first time they are changed, and "reset" puts them back.
Map-wide changes touch every player: single player, the listen server host or a superadmin.
]]
SPeditor.Server = SPeditor.Server or {}
local S = SPeditor.Server

S.Env = S.Env or { orig = {} }
local E = S.Env

local function allowed(ply)
	return game.SinglePlayer() or ply:IsListenServerHost() or ply:IsSuperAdmin()
end

local function redownload()
	net.Start(SPeditor.Net.EnvLightmaps)
	net.Broadcast()
end

-- the fields of env_skypaint (gamemodes/base/entities/entities/env_skypaint.lua) the window edits
local PAINT_VEC = { "TopColor", "BottomColor", "DuskColor", "SunColor", "SunNormal" }
local PAINT_NUM = { "FadeBias", "HDRScale", "DuskScale", "DuskIntensity", "SunSize", "StarScale", "StarFade", "StarSpeed" }

local function skyPaint(create)
	local e = ents.FindByClass("env_skypaint")[1]
	if not IsValid(e) and create then
		e = ents.Create("env_skypaint")
		if IsValid(e) then
			e:Spawn()
			e:Activate()
			E.madePaint = e
		end
	end
	return IsValid(e) and e or nil
end

local function readPaint(e)
	local t = {}
	for _, k in ipairs(PAINT_VEC) do t[k] = e["Get" .. k] and e["Get" .. k](e) end
	for _, k in ipairs(PAINT_NUM) do t[k] = e["Get" .. k] and e["Get" .. k](e) end
	t.DrawStars = e.GetDrawStars and e:GetDrawStars()
	return t
end

local function writePaint(e, t)
	for _, k in ipairs(PAINT_VEC) do
		if isvector(t[k]) and e["Set" .. k] then e["Set" .. k](e, t[k]) end
	end
	for _, k in ipairs(PAINT_NUM) do
		if isnumber(t[k]) and e["Set" .. k] then e["Set" .. k](e, math.Clamp(t[k], -100, 100)) end
	end
	if t.DrawStars ~= nil and e.SetDrawStars then e:SetDrawStars(t.DrawStars and true or false) end
end

-- the map's own value of key, kept once before the first change
local function keep(key, value)
	if E.orig[key] == nil then E.orig[key] = value end
end

local function setAmbient(level)
	level = math.Clamp(math.floor(level), 1, 26)
	keep("ambient", 13)
	if E.ambient == level then return end
	E.ambient = level
	engine.LightStyle(0, string.char(96 + level))
	-- the light style reaches the clients first, the lightmaps are built after it
	timer.Simple(0.3, redownload)
end

local function setStaticSun(on)
	local list = ents.FindByClass("light_environment")
	if #list == 0 then return end
	keep("staticSun", true)
	if E.staticSun == on then return end
	E.staticSun = on
	for _, v in ipairs(list) do v:Fire(on and "TurnOn" or "TurnOff") end
	timer.Simple(0.3, redownload)
end

local function setSky(name)
	if not isstring(name) or #name > 64 or not string.match(name, "^[%w_%-/%.]+$") then return end
	keep("sky", GetConVarString("sv_skyname"))
	if GetConVarString("sv_skyname") == name then return end
	RunConsoleCommand("sv_skyname", name)
end

local function setPaint(t)
	if not istable(t) then return end
	local e = skyPaint(true)
	if not e then return end
	keep("paint", readPaint(e))
	writePaint(e, t)
end

local function setSunDir(dir)
	if not isvector(dir) or dir:IsZero() then return end
	dir = dir:GetNormalized()
	local sun = ents.FindByClass("env_sun")[1]
	if IsValid(sun) then
		keep("sunDir", sun:GetInternalVariable("sun_dir"))
		sun:SetSaveValue("sun_dir", dir)
	end
	local e = skyPaint(false)
	if e and e.SetSunNormal then
		keep("paint", readPaint(e))
		e:SetSunNormal(dir)
	end
end

-- d — the table the client sent (fields may be missing: those stay as they are)
function S.EnvApply(d)
	if not istable(d) then return end
	if d.reset then
		local o = E.orig
		if o.ambient then setAmbient(o.ambient) end
		if o.staticSun ~= nil then setStaticSun(o.staticSun) end
		if o.sky then setSky(o.sky) end
		local e = skyPaint(false)
		if o.paint and e then writePaint(e, o.paint) end
		if o.sunDir then
			local sun = ents.FindByClass("env_sun")[1]
			if IsValid(sun) then sun:SetSaveValue("sun_dir", o.sunDir) end
		end
		if IsValid(E.madePaint) and not o.paint then E.madePaint:Remove() end
		E.orig, E.ambient, E.staticSun = {}, nil, nil
		return
	end
	if isnumber(d.ambient) then setAmbient(d.ambient) end
	if d.staticSun ~= nil then setStaticSun(d.staticSun and true or false) end
	if d.sky then setSky(d.sky) end
	if d.paint then setPaint(d.paint) end
	if d.sunDir then setSunDir(d.sunDir) end
end

-- What the map has, for the window: a light_environment to turn off, its sun, the sky
function S.EnvInfo(ply)
	local sun = ents.FindByClass("env_sun")[1]
	local paint = skyPaint(false)
	net.Start(SPeditor.Net.EnvInfo)
	net.WriteBool(#ents.FindByClass("light_environment") > 0)
	-- the map's own direction, also after the window has moved the sun
	net.WriteVector(E.orig.sunDir or (IsValid(sun) and sun:GetInternalVariable("sun_dir")) or vector_origin)
	net.WriteString(E.orig.sky or GetConVarString("sv_skyname"))
	net.WriteBool(paint ~= nil)
	net.Send(ply)
end

S.Receive("Env", function(ply)
	if not allowed(ply) then
		S.Notice(ply, "#env_not_allowed", 1)
		return
	end
	local d = SPeditor.ReadTable and SPeditor.ReadTable() or net.ReadTable()
	S.EnvApply(d)
end)

S.Receive("EnvInfo", function(ply) S.EnvInfo(ply) end)

-- a map cleanup puts the map back as it was (its light style stays otherwise)
hook.Add("PreCleanupMap", "GMFM.EnvReset", function() S.EnvApply({ reset = true }) end)
