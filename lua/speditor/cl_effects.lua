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
  Effects.MainFrame()        the main game frame is drawn while particle systems run (gmfm_fx_mainframe)
  Effects.Files() / .Systems(file) / .ToolList() / .EngineList() / .LuaList()   what there is
]]
SPeditor.Effects = SPeditor.Effects or {}
local E = SPeditor.Effects
local C = SPeditor.Client

E.MAX_STEP    = 0.07     -- a game frame longer than this is not simulated: the step would be too coarse
E.MAX_WARM    = 10       -- a system is never run for longer than this to catch up, seconds
E.PREVIEW_MAX = 8        -- the longest preview, seconds
E.SHOW_LAG    = 0.1      -- a system further than this behind its moment is hidden while it catches up, seconds
E.PLAY_LAG    = 0.5      -- the same while the animation plays (long frames leave it a little behind)
E.MOVE_REST   = 0.2      -- a moved effect is started over after it has rested for this long

-- The engine moves on some particles only in its own main frame, which the editor skips (b0.1
-- measured it for util.Effect: sparks hung in the air), and the render — which draws the engine
-- frame — then shows an effect fuller than the timeline did. So while a particle system runs
-- and while the animation plays, the main frame is drawn too, behind the windows (b0.2). It
-- costs one more render of the scene a frame: 0 turns it off (lighter on a slow computer).
local cvMain = CreateClientConVar("gmfm_fx_mainframe", "1", true, false,
	"GM:FM: draw the main game frame while particle effects run, so that they play whole (as in the render)", 0, 1)
function E.MainFrame() return cvMain:GetBool() end

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

-- Particle files of the Workshop (a0.9): addons keep them in subfolders of particles/ too
-- (particles/fx/…), and each file is told by the addon it comes from. The Workshop addons are
-- asked for their own particles/ (an addon title works as a path for file.Find); files of
-- legacy folder addons stay without a name.
local PCF_DEPTH = 3
local function findPCF(dir, path, depth, out)
	local files, dirs = file.Find(dir .. "*", path)
	for _, f in ipairs(files or {}) do
		if string.lower(string.GetExtensionFromFilename(f) or "") == "pcf" then out[#out + 1] = dir .. f end
	end
	if depth < PCF_DEPTH then
		for _, d in ipairs(dirs or {}) do findPCF(dir .. d .. "/", path, depth + 1, out) end
	end
	return out
end

local filesCache
-- { { path = "particles/x.pcf", name = "x" | "fx/x", stock = bool, addon = title | nil }, … }:
-- the game's files first
function E.Files()
	if filesCache then return filesCache end
	local out = {}
	local st = E.Stock()
	local addonOf = {}
	for _, a in ipairs(engine.GetAddons() or {}) do
		if a.mounted and isstring(a.title) then
			for _, path in ipairs(findPCF("particles/", a.title, 1, {})) do
				addonOf[string.lower(path)] = addonOf[string.lower(path)] or a.title
			end
		end
	end
	for _, path in ipairs(findPCF("particles/", "GAME", 1, {})) do
		local low = string.lower(path)
		out[#out + 1] = { path = path, name = string.StripExtension(string.sub(path, 11)), stock = st[low] or false,
			addon = not st[low] and addonOf[low] or nil }
	end
	table.sort(out, function(a, b)
		if a.stock ~= b.stock then return a.stock end
		if (a.addon or "") ~= (b.addon or "") then return (a.addon or "\255") < (b.addon or "\255") end
		return a.name < b.name
	end)
	filesCache = out
	return out
end
-- addons mounted later (a new subscription) show up when the browser is opened again
function E.RescanFiles() filesCache = nil end

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
	"BloodImpact", "bloodspray", "StriderBlood", "AntlionGib", "Impact",
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

-- every system an effect object has made, with its object (b0.1): a system whose object is
-- gone without saying so (a map cleanup, a lost update) is put out by the sweep below, or a
-- stopped system would hang in the air until the map is loaded again
local owned = setmetatable({}, { __mode = "k" })

local function destroy(ps)
	if not ps then return end
	if ps:IsValid() then
		ps:SetShouldDraw(false)
		ps:StopEmissionAndDestroyImmediately()
	end
	owned[ps] = nil
end

local function kill(st)
	destroy(st.ps)
	st.ps, st.age, st.done, st.goal = nil, 0, false, 0
end

local function sweep(all)
	for ps, ent in pairs(owned) do
		if all or not IsValid(ent) or not ent.SPFx or ent.SPFx.ps ~= ps then destroy(ps) end
	end
end
timer.Create("SPeditor.EffectsSweep", 1, 0, function() sweep(false) end)
SPeditor.Hook("PostCleanupMap", "SPeditor.Effects", function()
	sweep(true)
	for _, ent in ipairs(E.All()) do ent.SPFx = nil end
end)

local function keyOf(ent)
	return ent:GetFxSource() .. "|" .. ent:GetFxName() .. "|" .. ent:GetFxFile() .. "|" .. ent:GetFxLength() .. "|" .. ent:GetFxScale()
end

-- An effect fired from an attachment of another object (a0.9, the takes of the recorder: the
-- muzzle and the shell port of the weapon in the hand). The server cannot tell where a held
-- weapon's muzzle is (it gave a place half a body lower), and a worn weapon is drawn by its
-- bone-merged copy, so the point is taken here from what is drawn. Returns pos, ang or nil.
function E.Mount(ent)
	local att = ent:GetNW2String("SPeditor_FxAtt", "")
	if att == "" then return nil end
	-- once a frame (b0.2.2): a recorded take has dozens of muzzle effects, each set up the bones
	-- of its weapon for every question
	local frame = FrameNumber()
	if ent.SPMountAt == frame then return ent.SPMountPos, ent.SPMountAng end
	ent.SPMountAt, ent.SPMountPos, ent.SPMountAng = frame, nil, nil
	local uid = ent:GetNW2Int("SPeditor_FxOn", 0)
	local st = ent.SPFx
	local on = st and st.on
	if not IsValid(on) or on:GetNW2Int("SPeditor_UID", 0) ~= uid then
		on = nil
		for _, e in ipairs(C.Objects()) do
			if IsValid(e) and e:GetNW2Int("SPeditor_UID", 0) == uid then on = e break end
		end
		if st then st.on = on end
		if not on then return nil end
	end
	local drawn = IsValid(on.SPWorn) and on.SPWorn or on
	local id = drawn:LookupAttachment(att)
	if not id or id <= 0 then return nil end
	drawn:SetupBones()
	local a = drawn:GetAttachment(id)
	if not a then return nil end
	ent.SPMountPos, ent.SPMountAng = a.Pos, a.Ang
	return a.Pos, a.Ang
end

local TRACER_SPEED = 6000     -- units a second, the speed of a bullet's tracer in HL2

function E.Fire(ent)
	if not IsValid(ent) or not ent.GetFxSource then return end
	-- the engine moves the particles of these effects only in its main frame (cl_camera.lua)
	if C.KeepParticlesAlive then C.KeepParticlesAlive() end
	local src, name = ent:GetFxSource(), ent:GetFxName()
	local pos, ang = SPeditor.LivePos(ent)
	local scale, len = ent:GetFxScale(), ent:GetFxLength()
	local mpos, mang = E.Mount(ent)
	if mpos then
		-- a tracer keeps the end it was keyed with (where the bullet hit) and starts at the muzzle
		if len > 0 then
			local tip = pos + ang:Forward() * len
			ang = (tip - mpos):Angle()
			len = tip:Distance(mpos)
		else
			ang = mang
		end
		pos = mpos
	end
	if src == "tool" then
		local def = list.GetEntry and list.GetEntry("EffectType", name) or (list.Get("EffectType") or {})[name]
		if def and isfunction(def.func) then
			local ok, err = pcall(def.func, ent, pos, ang, scale)
			if not ok then ErrorNoHalt("[GM:FM] effect " .. name .. ": " .. tostring(err) .. "\n") end
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
		-- for a tracer Scale is the speed of the bullet, units a second (b0.1): with the size
		-- (1) in it a tracer crawled out of the muzzle at 1 unit a second and hung in the air for
		-- hours — even a map cleanup did not take it away
		if len > 0 and string.find(string.lower(name), "tracer", 1, true) then d:SetScale(TRACER_SPEED * scale) end
		-- a bullet hit (a0.9, the recorder makes them): the effect stands a little before the
		-- surface looking at it; the engine needs the surface itself to raise its dust and sparks
		if name == "Impact" then
			local tr = util.TraceLine({ start = pos, endpos = pos + fwd * 24, mask = MASK_SHOT })
			if not tr.Hit or tr.HitSky then return end
			d:SetOrigin(tr.HitPos)
			d:SetNormal(tr.HitNormal)
			d:SetSurfaceProp(tr.SurfaceProps)
			d:SetHitBox(tr.HitBox)
			d:SetDamageType(DMG_BULLET)
			d:SetEntity(IsValid(tr.Entity) and tr.Entity or game.GetWorld())
		elseif name == "BloodImpact" then
			d:SetOrigin(pos + fwd * 4)
			d:SetNormal(-fwd)
			d:SetColor(BLOOD_COLOR_RED)
		end
		local ok, err = pcall(util.Effect, name, d, true, true)
		if not ok then ErrorNoHalt("[GM:FM] effect " .. name .. ": " .. tostring(err) .. "\n") end
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
		owned[ps] = ent
	end
	local ps = st.ps
	ps:SetControlPoint(0, pos)
	ps:SetControlPointOrientation(0, ang:Forward(), ang:Right(), ang:Up())
	local len = ent:GetFxLength()
	if len > 0 then ps:SetControlPoint(1, pos + ang:Forward() * len) end

	if T - st.age > E.MAX_WARM then st.age = T - E.MAX_WARM end
	local dt = FrameTime()
	-- While the animation plays, a long frame is simulated too (b0.2): at under ~14 frames a
	-- second (two viewports, a heavy scene) every frame was too long, and the effects stood
	-- frozen or hidden on the timeline while the render — which waits for them — had them whole.
	-- A coarse step is what the game itself does at such a rate.
	local SA = SPeditor.Component and SPeditor.Component("saeditor").SA
	local playing = SA and SA.playing and not C.exporting
	local step = dt > 0 and (dt <= E.MAX_STEP or playing) and (T - st.age) >= math.min(dt, E.MAX_STEP) * 0.5
	ps:SetShouldSimulate(step)
	if step then
		st.age = st.age + dt
		if C.KeepParticlesAlive and cvMain:GetBool() then C.KeepParticlesAlive(1) end
	end
	-- A system that is being run up to its moment is not shown until it gets there. After
	-- the playhead was moved back, an effect is started over and replayed from its start in
	-- real time: shown, it looked as if an explosion that had ended seconds ago went off again.
	-- (while it plays, a few frames behind are not seen in motion: it is shown up to PLAY_LAG)
	ps:SetShouldDraw(not hidden and T - st.age <= math.max(dt * 2, playing and E.PLAY_LAG or E.SHOW_LAG))
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

	local pos, ang = SPeditor.LivePos(ent)
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
	-- (b0.2.6) a video renders without the rest: an effect that follows a moving weapon at a
	-- moment that stands still waited 0.2 s of every frame for it, and was started over anyway
	-- (a particle system only: an effect that plays by itself would be fired again every frame)
	local rest = (not live and SPeditor.Render and SPeditor.Render.busy) and 0 or E.MOVE_REST
	if st.movedAt and now - st.movedAt >= rest then
		st.movedAt = nil
		resim = true
	end

	if not live then
		-- the game frame has to be there from the very first step of a system: the debris of an
		-- explosion is thrown in its first moments (with the frame turned on by the first step
		-- itself it was missed). So it is drawn all the time the animation plays.
		if cvMain:GetBool() and C.KeepParticlesAlive and ent:GetFxName() ~= "" then
			local SA = SPeditor.Component and SPeditor.Component("saeditor").SA
			if (SA and SA.playing) or advancing then C.KeepParticlesAlive(1) end
		end
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
