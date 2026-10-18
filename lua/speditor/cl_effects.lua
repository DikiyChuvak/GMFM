--[[
SPeditor — effects (the speditor_effect entity): explosions, fire, smoke, blood, muzzle flashes…

An effect object is one of three kinds (SPeditor.EffectSources):

  pcf   A particle system of the engine: the game's own files (particles_manifest.txt) and
        every particles/*.pcf of the addons from the Workshop. The engine plays particles in
        real time, but a system can be told not to simulate (SetShouldSimulate): its particles
        then hang in the air as they are. So the editor keeps every system stopped and lets it
        run only until its age equals the wanted moment (the "FxTime" of the entity):
          the moment grows  — the system runs until it has caught up;
          the moment is less than the age — the system is started over and run up to it.
        This gives a still its "moment of the effect", and an animation (SAeditor keys the
        moment like any other property) — exact frames in a frame-by-frame render: the render
        waits (Effects.Busy) until every system has reached the moment of the frame.
  tool  An effect of the sandbox Emitter tool (the "EffectType" list).
  lua   util.Effect: engine effects and Lua effects of the game and of addons.
        These two cannot be stopped or wound: they are started when the moment leaves zero
        and then play by themselves. A still waits for the moment after starting them over
        (Effects.Hold); in a frame-by-frame render of an animation they run at their own speed.

  Effects.Update(ent)        called by the entity every frame
  Effects.Preview(ent)       play the effect once from the start, then return to the moment
  Effects.Busy()             a particle system has not reached its moment yet
  Effects.Hold(job)          still render: true while the effects are not at their moments
  Effects.Files() / .Systems(file) / .ToolList() / .EngineList() / .LuaList()   what there is
]]
SPeditor.Effects = SPeditor.Effects or {}
local E = SPeditor.Effects
local C = SPeditor.Client

E.MAX_STEP    = 0.07     -- a game frame longer than this is not simulated: the step would be too coarse
E.MAX_WARM    = 10       -- a system is never run for longer than this to catch up, seconds
E.PREVIEW_MAX = 8        -- the longest preview, seconds
E.SHOW_LAG    = 0.1      -- a system further than this behind its moment is hidden while it catches up, seconds
E.MOVE_REST   = 0.2      -- a moved effect is started over after it has rested for this long

---------------------------------------------------------------------
-- What there is: particle files and the systems in them
---------------------------------------------------------------------
local stock
-- files the engine loads itself
function E.Stock()
	if stock then return stock end
	stock = {}
	local raw = file.Read("particles/particles_manifest.txt", "GAME") or ""
	for path in string.gmatch(raw, "\"file\"%s+\"!?([^\"]+)\"") do
		stock[string.lower(string.gsub(path, "\\", "/"))] = true
	end
	return stock
end

-- { { path = "particles/x.pcf", name = "x", stock = bool }, … }: the game's files first
function E.Files()
	local out = {}
	local st = E.Stock()
	for _, f in ipairs(file.Find("particles/*.pcf", "GAME") or {}) do
		local path = "particles/" .. f
		out[#out + 1] = { path = path, name = string.StripExtension(f), stock = st[string.lower(path)] or false }
	end
	table.sort(out, function(a, b)
		if a.stock ~= b.stock then return a.stock end
		return a.name < b.name
	end)
	return out
end

-- A .pcf file is a DMX document: a string dictionary, a list of elements (type, name, id)
-- and then the attributes of every element. A particle system is an element of the type
-- DmeParticleSystemDefinition; the systems another system is built from are listed in its
-- "children" attribute. Systems that are nobody's child come first; the rest are parts
-- (the "…_glow", "…_sparks" of an explosion) — they are listed after and marked.
local SIZES = { [2] = 4, [3] = 4, [4] = 1, [8] = 4, [9] = 8, [10] = 12, [11] = 16, [12] = 12, [13] = 16, [14] = 64 }

local function parsePCF(data)
	local nl = string.find(data, "\n", 1, true)
	if not nl then return {} end
	local ver = tonumber(string.match(string.sub(data, 1, nl), "encoding binary (%d+)"))
	if not ver or ver < 2 or ver > 5 then return {} end
	local p = nl + 2
	local byte, find, sub = string.byte, string.find, string.sub

	local function u16()
		local a, b = byte(data, p, p + 1)
		p = p + 2
		return a + b * 256
	end
	local function i32()
		local a, b, c, d = byte(data, p, p + 3)
		p = p + 4
		local n = a + b * 256 + c * 65536 + d * 16777216
		return n >= 2147483648 and n - 4294967296 or n
	end
	local function cstr()
		local e = find(data, "\0", p, true)
		local s = sub(data, p, e - 1)
		p = e + 1
		return s
	end

	local dict = {}
	local nStr = ver >= 4 and i32() or u16()
	for i = 0, nStr - 1 do dict[i] = cstr() end
	local function dictIndex() return ver >= 5 and i32() or u16() end

	local nEl = i32()
	local types, names = {}, {}
	for i = 0, nEl - 1 do
		types[i] = dict[dictIndex()]
		names[i] = ver >= 4 and dict[dictIndex()] or cstr()
		p = p + 16
	end

	-- attributes: only "children" of a system and "child" of a child link are read, the rest is skipped
	local isChild = {}
	local ok = pcall(function()
		local links, linkOf = {}, {}          -- [system] = { link elements }, [link] = child system
		for i = 0, nEl - 1 do
			for _ = 1, i32() do
				local name = dict[dictIndex()]
				local t = byte(data, p)
				p = p + 1
				local array = t > 14
				if array then t = t - 14 end
				local n = array and i32() or 1
				if t == 1 then
					for _ = 1, n do
						local ref = i32()
						if name == "children" and array then
							links[i] = links[i] or {}
							links[i][#links[i] + 1] = ref
						elseif name == "child" then
							linkOf[i] = ref
						end
					end
				elseif t == 5 then
					for _ = 1, n do
						if ver >= 5 and not array then p = p + 4 else p = find(data, "\0", p, true) + 1 end
					end
				elseif t == 6 then
					for _ = 1, n do p = p + i32() end
				elseif t == 7 then
					p = p + n * (ver >= 3 and 4 or 16)
				else
					p = p + n * (SIZES[t] or error("type"))
				end
			end
		end
		for _, list in pairs(links) do
			for _, link in ipairs(list) do
				if linkOf[link] then isChild[linkOf[link]] = true end
			end
		end
	end)
	if not ok then isChild = {} end        -- an unknown layout: every system is offered

	local out, seen, part = {}, {}, {}
	for i = 0, nEl - 1 do
		local name = names[i]
		if types[i] == "DmeParticleSystemDefinition" and name and name ~= "" and not seen[name] then
			seen[name] = true
			out[#out + 1] = name
			part[name] = isChild[i] or nil
		end
	end
	table.sort(out, function(a, b)
		if part[a] ~= part[b] then return not part[a] end
		return string.lower(a) < string.lower(b)
	end)
	return out, part
end

local systems, parts = {}, {}
-- Names of the particle systems in a file (read once): whole effects first, then their parts.
-- The second result tells the parts: { [name] = true }.
function E.Systems(path)
	if systems[path] then return systems[path], parts[path] end
	local list, part = {}, {}
	local data = file.Read(path, "GAME")
	if data and #data > 32 then
		local ok, res, resPart = pcall(parsePCF, data)
		if ok then list, part = res, resPart or {} end
	end
	systems[path], parts[path] = list, part
	return list, part
end

-- Effects of the Emitter tool: { { name = key, title = caption } }
function E.ToolList()
	local out = {}
	for key, def in pairs(list.Get("EffectType") or {}) do
		if isstring(key) and istable(def) and isfunction(def.func) and not string.find(key, "[^%w_%-%.]") then
			local title = isstring(def.print) and language.GetPhrase(string.gsub(def.print, "^#", "")) or key
			out[#out + 1] = { name = key, title = title }
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- Engine effects that need nothing but a place and a direction
local ENGINE = {
	"Explosion", "HelicopterMegaBomb", "AR2Explosion", "AR2Impact", "cball_explode", "cball_bounce",
	"Sparks", "ElectricSpark", "ManhackSparks", "StunstickImpact", "MetalSpark",
	"BloodImpact", "bloodspray", "StriderBlood", "AntlionGib",
	"GlassImpact", "WaterSplash", "watersplash", "gunshotsplash", "waterripple", "ThumperDust",
	"MuzzleEffect", "ChopperMuzzleFlash", "GunshipMuzzleFlash", "StriderMuzzleFlash", "AirboatMuzzleFlash",
	"ShellEject", "RifleShellEject", "ShotgunShellEject",
	"Tracer", "AR2Tracer", "GunshipTracer", "StriderTracer", "HelicopterTracer", "AirboatGunTracer", "GaussTracer",
	"ToolTracer", "LaserTracer", "RPGShotDown", "VortDispel", "BoltImpact", "Smoke", "WheelDust",
}
function E.EngineList()
	local out = {}
	for i, name in ipairs(ENGINE) do out[i] = { name = name, title = name } end
	return out
end

-- Lua effects registered by the game and by addons (lua/effects)
function E.LuaList()
	local out, seen = {}, {}
	for _, t in ipairs(effects.GetList and effects.GetList() or {}) do
		local name = istable(t) and isstring(t.Folder) and string.GetFileFromFilename(t.Folder) or nil
		if name and name ~= "" and not seen[name] and not string.find(name, "[^%w_%-%.]") then
			seen[name] = true
			out[#out + 1] = { name = name, title = name }
		end
	end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- an effect that plays by itself and cannot be stopped at a moment
function E.IsLive(ent) return IsValid(ent) and ent:GetFxSource() ~= "pcf" end

---------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------
local added = {}
local function ensureFile(path)
	if path == "" or added[path] then return end
	added[path] = true
	-- the game's own files are loaded by the engine; an addon's file may be not
	if not E.Stock()[string.lower(path)] and file.Exists(path, "GAME") then game.AddParticles(path) end
end

-- the moment the effect has to show now
function E.Time(ent)
	local st = ent.SPFx
	if st and st.preview then return RealTime() - st.preview end
	return math.max(ent:GetFxTime(), 0)
end

local function kill(st)
	local ps = st.ps
	if ps and ps:IsValid() then ps:StopEmissionAndDestroyImmediately() end
	st.ps, st.age, st.done, st.goal = nil, 0, false, 0
end

local function keyOf(ent)
	return ent:GetFxSource() .. "|" .. ent:GetFxName() .. "|" .. ent:GetFxFile() .. "|" .. ent:GetFxLength() .. "|" .. ent:GetFxScale()
end

function E.Fire(ent)
	local src, name = ent:GetFxSource(), ent:GetFxName()
	local pos, ang, scale, len = ent:GetPos(), ent:GetAngles(), ent:GetFxScale(), ent:GetFxLength()
	if src == "tool" then
		local def = list.GetEntry and list.GetEntry("EffectType", name) or (list.Get("EffectType") or {})[name]
		if def and isfunction(def.func) then
			local ok, err = pcall(def.func, ent, pos, ang, scale)
			if not ok then ErrorNoHalt("[SPeditor] effect " .. name .. ": " .. tostring(err) .. "\n") end
		end
	elseif src == "lua" and name ~= "" then
		local fwd = ang:Forward()
		local d = EffectData()
		-- a tracer flies from Start to Origin; everything else appears at Origin
		d:SetStart(pos)
		d:SetOrigin(len > 0 and pos + fwd * len or pos)
		d:SetAngles(ang)
		d:SetNormal(fwd)
		d:SetScale(scale)
		d:SetMagnitude(scale)
		d:SetRadius(scale * 32)
		d:SetFlags(0)
		local ok, err = pcall(util.Effect, name, d, true, true)
		if not ok then ErrorNoHalt("[SPeditor] effect " .. name .. ": " .. tostring(err) .. "\n") end
	end
end

local function updateParticles(ent, st, T, pos, ang, hidden, resim)
	if resim or T < (st.goal or 0) - 0.001 then kill(st) end
	st.goal = T
	local name = ent:GetFxName()
	if T <= 0 or name == "" then
		if st.ps then kill(st) end
		return
	end
	if st.done then return end
	if not st.ps or not st.ps:IsValid() then
		st.ps = nil
		-- a system that has played to its end removes itself
		if st.age > 0 then st.done = true return end
		ensureFile(ent:GetFxFile())
		PrecacheParticleSystem(name)
		local ok, ps = pcall(CreateParticleSystemNoEntity, name, pos, ang)
		if not ok or not ps or not ps:IsValid() then st.done = true return end
		ps:SetShouldSimulate(false)
		st.ps = ps
	end
	local ps = st.ps
	ps:SetControlPoint(0, pos)
	ps:SetControlPointOrientation(0, ang:Forward(), ang:Right(), ang:Up())
	local len = ent:GetFxLength()
	if len > 0 then ps:SetControlPoint(1, pos + ang:Forward() * len) end

	if T - st.age > E.MAX_WARM then st.age = T - E.MAX_WARM end
	local dt = FrameTime()
	local step = dt > 0 and dt <= E.MAX_STEP and (T - st.age) >= dt * 0.5
	ps:SetShouldSimulate(step)
	if step then st.age = st.age + dt end
	-- A system that is being run up to its moment is not shown until it gets there. After
	-- the playhead was moved back, an effect is started over and replayed from its start in
	-- real time: shown, it looked as if an explosion that had ended seconds ago went off again.
	ps:SetShouldDraw(not hidden and T - st.age <= math.max(dt * 2, E.SHOW_LAG))
end

function E.Update(ent)
	local st = ent.SPFx
	if not st then
		st = { age = 0, goal = 0 }
		ent.SPFx = st
	end
	local now = RealTime()
	if st.preview and (now - st.preview > E.PREVIEW_MAX or st.done) then st.preview = nil end

	local key = keyOf(ent)
	local changed = key ~= st.key
	if changed then
		st.key = key
		kill(st)
	end

	local pos, ang = ent:GetPos(), ent:GetAngles()
	local T = E.Time(ent)
	local live = ent:GetFxSource() ~= "pcf"
	-- An effect that was moved while its moment stood still is started over at the new place
	-- once it has come to rest: what it has already emitted stays where it was emitted.
	local moved = st.pos ~= nil and (pos:DistToSqr(st.pos) > 0.01 or math.abs(ang.p - st.ang.p) + math.abs(ang.y - st.ang.y) + math.abs(ang.r - st.ang.r) > 0.05)
	st.pos, st.ang = Vector(pos), Angle(ang)
	local advancing = st.lastT ~= nil and T > st.lastT + 0.0001
	st.lastT = T
	if moved and not advancing and (live or st.age > 0) then st.movedAt = now end
	local resim = false
	if st.movedAt and now - st.movedAt > E.MOVE_REST then
		st.movedAt = nil
		resim = true
	end

	if not live then
		updateParticles(ent, st, T, pos, ang, ent:GetNW2Bool("SPeditor_Hidden", false), resim)
		return
	end

	-- an effect that plays by itself: started when the moment leaves zero, when the effect
	-- was changed or moved, and at the time a still render asks for (Effects.Hold)
	local was = st.liveT or 0
	st.liveT = T
	local fire = T > 0.001 and (was <= 0.001 or changed or resim)
	if st.fireAt and now >= st.fireAt then
		st.fireAt = nil
		fire = true
	end
	if fire and not ent:GetNW2Bool("SPeditor_Hidden", false) then E.Fire(ent) end
end

function E.Drop(ent)
	local st = ent.SPFx
	if st then kill(st) end
	ent.SPFx = nil
end

-- Play the effect once from its start; a particle system then returns to its moment
function E.Preview(ent)
	if not IsValid(ent) then return end
	local st = ent.SPFx
	if not st then return end
	if ent:GetFxSource() == "pcf" then
		kill(st)
		st.preview = RealTime()
	else
		E.Fire(ent)
	end
end

function E.All()
	return ents.FindByClass("speditor_effect")
end

-- A particle system is not at its moment yet. Asked by the renders before every frame.
function E.Busy()
	-- the same measure as in the update: half a game frame. A frame too long to be simulated
	-- (the one after a frame of a render) is judged as a regular one, or the effect would be
	-- taken as "close enough" without having moved
	local dt = FrameTime()
	if dt > E.MAX_STEP then dt = 0.034 end
	for _, ent in ipairs(E.All()) do
		if ent:GetFxSource() == "pcf" and ent:GetFxName() ~= "" then
			local st = ent.SPFx
			local T = E.Time(ent)
			if not st or st.key ~= keyOf(ent) then
				if T > 0 then return true end
			elseif st.movedAt or st.preview then
				return true
			elseif T > 0 and not st.done and (T < (st.goal or 0) - 0.001 or T - st.age >= dt * 0.5) then
				return true
			end
		end
	end
	return false
end

-- Still render: the effects that play by themselves are started over so that each of them is
-- at its moment at the same time, and the particle systems are waited for. Returns true
-- while the frame must not be shot yet. job — any table that lives as long as the render.
local HOLD_MAX = 12
function E.Hold(job)
	local now = RealTime()
	if not job.fxHold then
		local longest = 0
		for _, ent in ipairs(E.All()) do
			if ent:GetFxSource() ~= "pcf" and ent.SPFx and not ent:GetNW2Bool("SPeditor_Hidden", false) then
				local T = math.min(E.Time(ent), HOLD_MAX - 2)
				if T > 0.001 then longest = math.max(longest, T) end
			end
		end
		job.fxHold = { t0 = now, shoot = now + longest }
		for _, ent in ipairs(E.All()) do
			if ent:GetFxSource() ~= "pcf" and ent.SPFx then
				local T = math.min(E.Time(ent), HOLD_MAX - 2)
				if T > 0.001 then ent.SPFx.fireAt = now + longest - T end
			end
		end
		if longest > 0 then return true end
	end
	local h = job.fxHold
	if now - h.t0 > HOLD_MAX then return false end
	return now < h.shoot or E.Busy()
end

-- the editor is closed or reloaded: nothing may be left running in a preview
SPeditor.Hook("SPeditor_StateChanged", "SPeditor.Effects", function()
	for _, ent in ipairs(E.All()) do
		if ent.SPFx then ent.SPFx.preview = nil end
	end
end)
