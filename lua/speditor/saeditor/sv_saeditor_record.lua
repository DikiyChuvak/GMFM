--[[
SAeditor — the action recorder (a0.6), as in machinima: the player closes the editor, plays the
game — walks, shoots, the NPCs around live their lives — and everything is written into the
animation. On stop the scene gets copies of the actors as ragdolls keyed every few frames:

  the player       its player model with the skin, bodygroups and player colour, and the
                   weapon it held (bone-merged into the hand, shown only while it was held);
  NPCs             those within the radius at the start and those that came during the take,
                   with their skin and bodygroups; one that died or vanished is hidden after
                   its last frame (a death that leaves a server-side ragdoll goes on in it);
  sounds           what the actors and their weapons played go onto the timeline, from them;
  effects          util.Effect calls of weapons and addons, bullet tracers and explosions become
                   effect objects keyed to fire at their moments;
  projectiles      rockets, grenades, bolts, energy balls the actors fired (or that flew within
                   the radius) become models keyed along their flight, shown only while they flew;
  map movers (a0.7) doors, lifts, buttons and trains within the radius (of the map, or spawned
                   by door tools and addons): the ones
                   that moved get keys of their own (a.world in sv_saeditor.lua), so a door the
                   player opened opens in the animation at the same moment;
  the view (a0.7)  what the player saw — the place, the turn and the field of view of the game's
                   own view after every CalcView (first person, a vehicle, a third-person addon)
                   — is sampled on the client and sent here in small batches (Rec action 2); it
                   becomes a scene camera keyed along the take, so the video can be shot
                   through the player's eyes. With no camera cuts yet it is made the first one.
                   The actor whose head the view is in is not drawn in it (cl_saeditor_record.lua);
  physics (a0.7)   ragdolls and props of the scene chosen for it are unfrozen for the take — they
                   fall, collide, are thrown with the physics gun — and their own keys are
                   written from their bodies (no copies). A physics take can also run with the
                   editor open, without the player (opts.noPlayer).

The poses are taken on the server: the bones of the actor (SetupBones) give the places of the
ragdoll's bodies frame by frame. The existing animation plays during the take (from the frame
the take starts at), so a new actor can be recorded over it.

Messages: Rec (client -> server) action 1 = start { step, radius, npcs, sounds, effects, from, view },
0 = stop, 2 = a batch of view samples { { f, x, y, z, p, y, r, fov }, … }, 3 = poses of the killed
player's body { { f, { { bone, x, y, z, p, y, r }, … } }, … }, 4 = sounds only the client played
{ { f, path, vol, pitch, ui }, … } (3 bits since a0.9); the server answers with
Rec { state = "started" (t0, fps, step, f0) | "stopped", made = { … } }.
]]
local COMP = SPeditor.Component("saeditor")
local SA  = COMP.SA
local S   = SPeditor.Server

SA.Rec = SA.Rec or {}          -- [ply] = the take in progress
local R = SA.Rec

local MAX_SECONDS = 600        -- the longest take
local MAX_NPCS    = 24
local MAX_SHOTS   = 64           -- projectiles in one take
local MAX_PHYS    = 32           -- scene objects with recorded physics
local MAX_MOVERS  = 64           -- doors, lifts, buttons of the map
local MAX_VIEW    = 40000        -- view samples of one take

-- what flies out of a gun (or is thrown) and is worth seeing in the animation
local PROJECTILES = {
	rpg_missile = true, apc_missile = true, grenade_ar2 = true, npc_grenade_frag = true, crossbow_bolt = true,
	prop_combine_ball = true, grenade_helicopter = true, npc_satchel = true, npc_tripmine = true, grenade_spit = true,
	hunter_flechette = true, grenade = true,
}

local function notify(ply, t)
	COMP:NetStart("Rec")
	SPeditor.WriteTable(t)
	net.Send(ply)
end

local function isActor(e) return IsValid(e) and (e:IsNPC() or e:IsNextBot()) and (e:GetModel() or "") ~= "" end

-- Vehicles (b0.2.5): the game's cars and boats and those of simfphys, Glide, LVS and the like
-- near the player join the take — the body as a model keyed along its way, its bones (wheels,
-- steering, suspension) as bone offsets, so the wheels turn in the animation; the separate
-- wheel entities of simfphys and the parts parented to a car go in as models of their own.
-- Seats that are not drawn stay out.
local MAX_VEHICLES = 24
local VEHICLE_CLASSES = { "^gmod_sent_vehicle_fphysics", "^glide_", "^base_glide", "^lvs_", "^simfphys", "^wac_", "^sw_" }
local function vehicleClass(e)
	local c = e:GetClass() or ""
	for _, p in ipairs(VEHICLE_CLASSES) do
		if string.find(c, p) then return true end
	end
	local base = e.Base
	return isstring(base) and (string.find(base, "glide", 1, true) or string.find(base, "fphysics", 1, true)
		or string.find(base, "lvs", 1, true)) and true or false
end
local function isVehicle(e)
	if not IsValid(e) or e:IsPlayer() or e:IsNPC() or e:IsWeapon() or e:GetNW2Bool("SPeditor_Ent", false) then return false end
	local m = e:GetModel() or ""
	if m == "" or not string.find(string.lower(m), "^models/.+%.mdl$") or e:GetNoDraw() or e:GetColor().a == 0 then return false end
	if e:IsVehicle() or vehicleClass(e) then return true end
	-- a part of one: a wheel, a turret, a door parented to it
	local p = e:GetParent()
	return IsValid(p) and (p:IsVehicle() or vehicleClass(p))
end

-- the actor an entity stands for: a weapon -> its owner
local function actorOf(rec, ent)
	if not IsValid(ent) then return nil end
	if rec.subjects[ent] then return ent end
	local owner = ent.GetOwner and ent:GetOwner()
	if IsValid(owner) and rec.subjects[owner] then return owner end
	-- a server ragdoll a dead NPC turned into
	if rec.corpse[ent] then return rec.corpse[ent] end
end

local function addSubject(rec, ent, kind)
	if rec.subjects[ent] or (kind == "npc" and rec.nNpc >= MAX_NPCS) or (kind == "shot" and rec.nShot >= MAX_SHOTS)
		or (kind == "vehicle" and (rec.nVeh or 0) >= MAX_VEHICLES) then return end
	if kind == "npc" then rec.nNpc = rec.nNpc + 1 end
	if kind == "shot" then rec.nShot = rec.nShot + 1 end
	if kind == "vehicle" then rec.nVeh = (rec.nVeh or 0) + 1 end
	rec.subjects[ent] = {
		kind = kind, ent = ent, model = string.lower(ent:GetModel() or ""), samples = {}, weapons = {},
		skin = ent:GetSkin(), groups = {}, col = ent:GetColor(), mat = ent:GetMaterial(),
		pcol = kind == "player" and ent:GetPlayerColor() or nil,
		name = kind == "player" and ent:Nick() or (ent:GetClass() or "npc"),
	}
	for i = 0, ent:GetNumBodyGroups() - 1 do rec.subjects[ent].groups[i] = ent:GetBodygroup(i) end
	-- the game reads "Keep corpses" when an NPC spawns: one that was there before the take is told
	-- by itself (see corpsesOn below)
	if kind == "npc" and rec.corpsesOn and ent.SetShouldServerRagdoll then
		ent:SetShouldServerRagdoll(true)
		rec.serverRag = rec.serverRag or {}
		rec.serverRag[ent] = true
	end
end

local function frameNow(rec) return rec.f0 + (CurTime() - rec.t0) * rec.fps end

-- A name no other object of the player's scene has (a0.9): a second take made a second
-- "<nick> view (rec)" camera, and the Render window listed two cameras of the same name.
-- The copy gets a number: "<nick> view (rec) 2", "… 3".
local function freeName(ply, base, self)
	local used = {}
	for _, e in ipairs(S.List(ply)) do
		if IsValid(e) and e ~= self then
			local n = e.SPeditor_Name or e:GetNW2String("SPeditor_Name", "")
			if n ~= "" then used[n] = true end
		end
	end
	if not used[base] then return base end
	local i = 2
	while used[base .. " " .. i] do i = i + 1 end
	return base .. " " .. i
end

-- the doors, lifts, buttons of the map around a point join the take (each one once)
local function addMovers(rec, center)
	for _, e in ipairs(ents.FindInSphere(center, rec.radius)) do
		if rec.nMover >= MAX_MOVERS then return end
		-- doors of the map and doors spawned by tools and addons alike
		if not rec.movers[e] and SA.MOVERS[e:GetClass()] and not e:GetNW2Bool("SPeditor_Ent", false) then
			rec.nMover = rec.nMover + 1
			rec.movers[e] = { id = SA.WorldId(e), class = e:GetClass(), samples = {} }
			e.SPeditor_WorldRec = true
		end
	end
end

---------------------------------------------------------------------
-- Sampling
---------------------------------------------------------------------
local function sample(rec, f)
	local ft = frameNow(rec)
	-- map movers: their local place (a door on a train moves with the train); new ones near
	-- the player join about once a second
	rec.scanAt = rec.scanAt or 0
	if rec.moversOn and CurTime() >= rec.scanAt and IsValid(rec.ply) then
		rec.scanAt = CurTime() + 1
		addMovers(rec, rec.ply:GetPos())
	end
	for e, m in pairs(rec.movers) do
		if IsValid(e) then m.samples[#m.samples + 1] = { f = f, pos = e:GetLocalPos(), ang = e:GetLocalAngles() } end
	end
	for key, sub in pairs(rec.subjects) do
		local ent = sub.follow or sub.ent
		-- a killed NPC stays on the server for a while, invisible and still: it is gone already
		-- (unless the game left a server ragdoll of it, which sub.follow then is)
		if not sub.follow and sub.kind == "npc" and IsValid(ent) and ent:Health() <= 0 then ent = nil end
		if sub.kind == "phys" then
			-- a scene object on physics: its bodies are the pose
			if IsValid(ent) then
				local bones = {}
				if S.IsRagdoll(ent) then
					for i = 0, ent:GetPhysicsObjectCount() - 1 do
						local p = ent:GetPhysicsObjectNum(i)
						local b = ent:TranslatePhysBoneToBone(i)
						if IsValid(p) and b then bones[b] = { p:GetPos(), p:GetAngles() } end
					end
				else
					bones[0] = { ent:GetPos(), ent:GetAngles() }
				end
				sub.samples[#sub.samples + 1] = { f = f, ft = ft, bones = bones }
			end
		elseif sub.kind == "shot" and IsValid(ent) and not sub.gone then
			-- a projectile: one rigid body, its place is the pose
			sub.samples[#sub.samples + 1] = { f = f, ft = ft, bones = { [0] = { ent:GetPos(), ent:GetAngles() } } }
		elseif sub.kind == "vehicle" and IsValid(ent) and not sub.gone then
			-- a vehicle: its place, and every bone in its parent's space (wheels, steering)
			local smp = { f = f, ft = ft, bones = { [0] = { ent:GetPos(), ent:GetAngles() } } }
			local n = ent:GetBoneCount()
			if n > 1 then
				ent:GetBonePosition(0)
				local loc = {}
				for b = 0, n - 1 do
					local m, pb = ent:GetBoneMatrix(b), ent:GetBoneParent(b)
					local pm = pb >= 0 and ent:GetBoneMatrix(pb)
					if m and pm then
						local lp, la = WorldToLocal(m:GetTranslation(), m:GetAngles(), pm:GetTranslation(), pm:GetAngles())
						loc[b] = { lp, la }
					end
				end
				smp.loc = loc
			end
			sub.samples[#sub.samples + 1] = smp
		elseif IsValid(ent) and not sub.gone then
			-- on the server bone positions are worked out on demand: asking for one brings the
			-- whole skeleton up to this tick
			ent:GetBonePosition(0)
			local bones = {}
			for b = 0, ent:GetBoneCount() - 1 do
				local m = ent:GetBoneMatrix(b)
				if m then bones[b] = { m:GetTranslation(), m:GetAngles() } end
			end
			-- a server ragdoll (a dead NPC): its bodies are the pose
			if sub.follow then
				for i = 0, ent:GetPhysicsObjectCount() - 1 do
					local p = ent:GetPhysicsObjectNum(i)
					local b = ent:TranslatePhysBoneToBone(i)
					if IsValid(p) and b then bones[b] = { p:GetPos(), p:GetAngles() } end
				end
			end
			-- the player killed: its view is the game's death camera, which stays where it died
			-- the player's eyes and aim (a0.9): the first-person camera of the take is put here, also
			-- when the game showed the player from behind (a third-person view of an addon)
			local eye = sub.kind == "player" and { ent:EyePos(), ent:EyeAngles() } or nil
			sub.samples[#sub.samples + 1] = { f = f, ft = ft, bones = bones, eye = eye, dead = sub.kind == "player" and not ent:Alive() or nil }
			local wep = ent.GetActiveWeapon and ent:GetActiveWeapon()
			local wm = IsValid(wep) and string.lower(wep:GetModel() or "") or ""
			-- weapon bases (ARC9, TFA, ArcCW…) may leave the entity without a model and draw
			-- their gun themselves: the world model of the weapon's table is taken then (a0.9)
			if IsValid(wep) and (wm == "" or not util.IsValidModel(wm)) and isstring(wep.WorldModel) then
				wm = string.lower(wep.WorldModel)
			end
			sub.weapons[#sub.weapons + 1] = { f = f, model = wm }
		elseif not sub.gone then
			sub.gone = f
		end
	end
end

COMP:Hook("Think", function()
	for ply, rec in pairs(R) do
		if not IsValid(ply) then
			R[ply] = nil
		elseif rec.on then
			local f = frameNow(rec)
			if CurTime() - rec.t0 > MAX_SECONDS or f >= SA.MAX_FRAMES - rec.step then
				SA.StopRecord(ply)
			else
				-- NPCs (and vehicles) that came into the radius during the take
				if (rec.npcs or rec.vehicles) and CurTime() >= (rec.nextScan or 0) then
					rec.nextScan = CurTime() + 0.5
					for _, e in ipairs(ents.FindInSphere(ply:GetPos(), rec.radius)) do
						if rec.npcs and isActor(e) then addSubject(rec, e, "npc")
						elseif rec.vehicles and isVehicle(e) then addSubject(rec, e, "vehicle") end
					end
				end
				local kf = rec.f0 + math.floor((f - rec.f0) / rec.step) * rec.step
				if kf > (rec.lastF or -1) then
					rec.lastF = kf
					sample(rec, kf)
				end
			end
		end
	end
end, "record")

-- a projectile: fired by an actor, or flying within the radius of the take. The owner and the
-- model are set after the entity is created, so it is looked at a tick later.
COMP:Hook("OnEntityCreated", function(ent)
	if next(R) == nil then return end
	timer.Simple(0, function()
		if not IsValid(ent) or ent:IsWeapon() or ent:IsNPC() or ent:IsPlayer() then return end
		local model = ent:GetModel() or ""
		if model == "" or not string.find(string.lower(model), "^models/") then return end
		for ply, rec in pairs(R) do
			if rec.on and IsValid(ply) and (actorOf(rec, ent) and not ent:IsRagdoll()
				or PROJECTILES[ent:GetClass()] and ent:GetPos():DistToSqr(ply:GetPos()) < rec.radius * rec.radius) then
				addSubject(rec, ent, "shot")
				-- sampled at once: a fast rocket is far from the gun by the next sample
				rec.subjects[ent].samples[1] = { f = frameNow(rec), bones = { [0] = { ent:GetPos(), ent:GetAngles() } } }
			end
		end
	end)
end, "record")

-- a dead NPC whose ragdoll stays on the server: the take goes on in that ragdoll
COMP:Hook("CreateEntityRagdoll", function(owner, rag)
	for _, rec in pairs(R) do
		local sub = rec.on and rec.subjects[owner]
		if sub and IsValid(rag) then
			sub.follow = rag
			rec.corpse[rag] = owner
		end
	end
end, "record")

-- Looping sounds (a body scraping along the ground, an engine) are started once and then only
-- changed (volume, pitch) or stopped by the game: every change comes here as a new sound. They
-- are kept as one clip each, cut where the game stopped them or stopped changing them (a 7 s
-- scrape played whole after the body had stopped was heard at the end of a take).
local PCF_RUN = 3               -- a particle system of a take plays this long, seconds
local LOOP_IDLE = 0.6          -- seconds without a change: the loop is over
-- a looped sound: a WAV with loop points (a "cue " chunk). By name before b0.2.6 — the shots
-- of the EFT weapons for ARC9 are called "…_close_loop1.wav" (fired in a row) and a burst became
-- one clip of its first shot.
local loopFiles = {}
local function isLoop(path)
	local v = loopFiles[path]
	if v ~= nil then return v end
	v = false
	if string.lower(string.GetExtensionFromFilename(path) or "") == "wav" then
		local data = file.Read(path, "GAME")
		if data and string.sub(data, 1, 4) == "RIFF" then
			local at = 13
			while at + 8 <= #data do
				local id = string.sub(data, at, at + 3)
				local a, b, c, d = string.byte(data, at + 4, at + 7)
				if id == "cue " then v = true break end
				local size = a + b * 256 + c * 65536 + d * 16777216
				at = at + 8 + size + size % 2
			end
		end
	end
	loopFiles[path] = v
	return v
end

COMP:Hook("EntityEmitSound", function(t)
	for _, rec in pairs(R) do
		if rec.on and rec.sounds then
			local actor = actorOf(rec, t.Entity)
			if actor and #rec.sound < SA.MAX_SOUNDS then
				local path = string.lower(string.gsub(t.SoundName or "", "^[%^%)%(%#%*%$%<%>%!%?%@%&%~%%]+", ""))
				path = "sound/" .. string.gsub(path, "\\", "/")
				local f = math.floor(frameNow(rec) + 0.5)
				local flags = t.Flags or 0
				local change = bit.band(flags, SND_CHANGE_VOL + SND_CHANGE_PITCH) ~= 0
				local stop = bit.band(flags, SND_STOP) ~= 0
				rec.loops = rec.loops or {}
				local key = tostring(actor) .. path
				local open = rec.loops[key]
				if open and CurTime() - open.t > LOOP_IDLE then open, rec.loops[key] = nil, nil end
				local vol = math.Clamp(t.Volume or 1, 0, 2)
				if stop then
					if open then open.last, rec.loops[key] = f, nil end
				elseif open and (change or isLoop(path)) then
					-- the same sound going on
					open.last, open.t = f, CurTime()
					open.vol = math.max(open.vol, vol)
				else
					local last = rec.sound[#rec.sound]
					-- the same sound twice in one frame (two bodies of one ragdoll) is heard once
					if not (last and last.f == f and last.path == path and last.actor == actor) then
						local c = { f = f, path = path, actor = actor, vol = vol, pitch = math.Clamp(t.Pitch or 100, 25, 400) }
						rec.sound[#rec.sound + 1] = c
						if change or isLoop(path) then
							c.last, c.t = f, CurTime()
							rec.loops[key] = c
						end
					end
				end
			end
		end
	end
end, "record")

-- mount = { actor, model, att }: fired from an attachment of the weapon the actor held;
-- src = "lua" (util.Effect, the default) | "pcf" (a particle system, file — its .pcf), f — the frame
local function addEffect(rec, name, pos, ang, len, mount, src, file, f)
	if not rec.effects or #rec.fx >= 2000 or not isstring(name) or not SPeditor.ValidVec(pos) then return end
	rec.fx[#rec.fx + 1] = { f = f or math.floor(frameNow(rec) + 0.5), name = name, pos = pos, ang = ang or angle_zero, len = len or 0,
		mount = mount, src = src or "lua", file = file or "" }
end

-- shots of the actors (a0.9 adds what the gun throws out): the flash at the muzzle, the spent
-- shell, a tracer from the muzzle and the hit of every bullet (dust and sparks of the surface,
-- blood on a body). The HL2 weapons make these on the clients from the engine, past Lua, so
-- the take puts them in by itself. The bullets of a shotgun fly within the spread of the shot.
local MUZZLE = { "muzzle", "muzzle_flash", "muzzleflash" }
local SHELL  = { "shell", "eject", "ejectbrass", "shelleject", "1" }
local function attachmentOf(ent, names)
	if not IsValid(ent) or not ent.LookupAttachment then return nil end
	for _, n in ipairs(names) do
		local id = ent:LookupAttachment(n)
		if id and id > 0 then
			local a = ent:GetAttachment(id)
			if a then return a, n end
		end
	end
end

local function isBody(e) return IsValid(e) and (e:IsNPC() or e:IsPlayer() or e:IsNextBot() or e:IsRagdoll()) end

COMP:Hook("EntityFireBullets", function(ent, data)
	for _, rec in pairs(R) do
		if rec.on and rec.effects and actorOf(rec, ent) and data and data.Src and data.Dir then
			local wep = ent.GetActiveWeapon and ent:GetActiveWeapon()
			local dir = data.Dir:GetNormalized()
			local mz, mzName = attachmentOf(wep, MUZZLE)
			local from = mz and mz.Pos or data.Src
			-- The server's muzzle of a held weapon is far from the drawn one (half a body lower in
			-- test scenes), so these effects are fired from the weapon of the take by its
			-- attachment, on the client (cl_effects.lua Effects.Mount); the place is a fallback.
			local actor = actorOf(rec, ent)
			local model = IsValid(wep) and string.lower(wep:GetModel() or "") or ""
			local function mount(att) return att and model ~= "" and { actor = actor, model = model, att = att } or nil end
			-- one flash and one shell a shot, however many bullets it has
			if not rec.lastShot or rec.lastShot.ent ~= ent or CurTime() - rec.lastShot.t > 0.02 then
				rec.lastShot = { ent = ent, t = CurTime() }
				addEffect(rec, "MuzzleEffect", from, dir:Angle(), 0, mount(mzName))
				local sh, shName
				if mz then sh, shName = attachmentOf(wep, SHELL) end
				if sh then
					local class = IsValid(wep) and wep:GetClass() or ""
					local shotgun = (data.Num or 1) > 1 or string.find(class, "shotgun", 1, true)
					addEffect(rec, shotgun and "ShotgunShellEject" or "ShellEject", sh.Pos, sh.Ang, 0, mount(shName))
				end
			end
			local right, up = dir:Angle():Right(), dir:Angle():Up()
			local spread = data.Spread or vector_origin
			for i = 1, math.Clamp(data.Num or 1, 1, 8) do
				local d = dir
				if i > 1 or (data.Num or 1) > 1 then
					d = (dir + right * spread.x * math.Rand(-1, 1) + up * spread.y * math.Rand(-1, 1)):GetNormalized()
				end
				local tr = util.TraceLine({ start = data.Src, endpos = data.Src + d * (data.Distance or 16384), filter = { ent, wep }, mask = MASK_SHOT })
				if tr.Hit and not tr.HitSky then
					if i == 1 then
						local len = tr.HitPos:Distance(from)
						if len > 32 then addEffect(rec, "Tracer", from, (tr.HitPos - from):Angle(), len, mount(mzName)) end
					end
					-- the hit: a little before the surface, looking at it (cl_effects.lua finds it again)
					addEffect(rec, isBody(tr.Entity) and "BloodImpact" or "Impact", tr.HitPos - d * 4, d:Angle(), 0)
				end
			end
		end
	end
end, "record")

-- explosions near the player
COMP:Hook("EntityTakeDamage", function(target, dmg)
	if not dmg:IsExplosionDamage() then return end
	for ply, rec in pairs(R) do
		if rec.on and rec.effects then
			local pos = dmg:GetDamagePosition()
			if pos:DistToSqr(ply:GetPos()) < rec.radius * rec.radius
				and (not rec.lastBoom or CurTime() - rec.lastBoom.t > 0.3 or rec.lastBoom.pos:DistToSqr(pos) > 128 * 128) then
				rec.lastBoom = { t = CurTime(), pos = pos }
				addEffect(rec, "Explosion", pos, angle_zero, 0)
			end
		end
	end
end, "record")

-- util.Effect of weapons and addons, while a take with effects is on; since a0.9 also the particle
-- systems the server starts (ParticleEffect, ParticleEffectAttach: NPCs, addons). The addon
-- that loaded a particle file has loaded it on the clients too, so the file is left empty.
local realEffect, realPE, realPEA
local function nearTakes(pos)
	local out = {}
	for ply, rec in pairs(R) do
		if rec.on and rec.effects and SPeditor.ValidVec(pos) and pos:DistToSqr(ply:GetPos()) < rec.radius * rec.radius then out[#out + 1] = rec end
	end
	return out
end
local function particleAt(name, pos, ang)
	if not isstring(name) or name == "" then return end
	for _, rec in ipairs(nearTakes(pos)) do addEffect(rec, name, pos, ang or angle_zero, 0, nil, "pcf", "") end
end
local function hookEffects(on)
	if on and not realPE then
		realPE, realPEA = ParticleEffect, ParticleEffectAttach
		ParticleEffect = function(name, pos, ang, parent, ...)
			pcall(particleAt, name, pos, ang)
			return realPE(name, pos, ang, parent, ...)
		end
		ParticleEffectAttach = function(name, attachType, ent, attId, ...)
			pcall(function()
				if not IsValid(ent) then return end
				local a = (tonumber(attId) or 0) > 0 and ent:GetAttachment(attId) or nil
				particleAt(name, a and a.Pos or ent:GetPos(), a and a.Ang or ent:GetAngles())
			end)
			return realPEA(name, attachType, ent, attId, ...)
		end
	end
	if on and not realEffect then
		realEffect = util.Effect
		util.Effect = function(name, data, ...)
			for ply, rec in pairs(R) do
				if rec.on and rec.effects and data and name ~= "Tracer" then
					local pos = data:GetOrigin()
					if pos:DistToSqr(ply:GetPos()) < rec.radius * rec.radius then
						local start = data:GetStart()
						-- only what flies somewhere has a second point (an EffectData may keep an
						-- earlier effect's start)
						local low = string.lower(name)
						local flies = string.find(low, "tracer", 1, true) or string.find(low, "beam", 1, true) or string.find(low, "laser", 1, true)
						local len = (flies and start ~= vector_origin and start:Distance(pos) > 1) and start:Distance(pos) or 0
						addEffect(rec, name, len > 0 and start or pos, len > 0 and (pos - start):Angle() or data:GetAngles(), len)
					end
				end
			end
			return realEffect(name, data, ...)
		end
	elseif not on and realEffect then
		local anyOn = false
		for _, rec in pairs(R) do anyOn = anyOn or (rec.on and rec.effects) end
		if not anyOn then
			util.Effect = realEffect
			realEffect = nil
			if realPE then ParticleEffect, ParticleEffectAttach, realPE, realPEA = realPE, realPEA, nil, nil end
		end
	end
end

---------------------------------------------------------------------
-- Killed NPCs as ragdolls (a0.8). By default the game makes the body of a killed NPC on the
-- clients only: the server never sees it, so the take could only hide the NPC after its death.
-- For the take the recorder turns ai_serverragdolls ("Keep corpses") on: the body is a server
-- ragdoll, CreateEntityRagdoll hands it over, and the fall goes on in the animation. Afterwards
-- the setting goes back, and the corpses that exist only because of it are removed (the scene
-- has its own keyed copies of them).
---------------------------------------------------------------------
local corpses = { set = false, users = 0 }
local function corpsesOn(rec)
	local cv = GetConVar("ai_serverragdolls")
	if not cv then return end
	corpses.users = corpses.users + 1
	rec.corpsesOn = true
	if cv:GetInt() == 0 and not corpses.set then
		corpses.set = true
		RunConsoleCommand("ai_serverragdolls", "1")
	end
end
local function corpsesOff(rec)
	if not rec.corpsesOn then return end
	rec.corpsesOn = nil
	corpses.users = math.max(corpses.users - 1, 0)
	if corpses.set then
		-- bodies that are there only because of the take; the NPCs that lived through it go back
		-- to bodies on the clients
		for rag in pairs(rec.corpse or {}) do
			if IsValid(rag) then rag:Remove() end
		end
		for npc in pairs(rec.serverRag or {}) do
			if IsValid(npc) and npc.SetShouldServerRagdoll then npc:SetShouldServerRagdoll(false) end
		end
		if corpses.users == 0 then
			corpses.set = false
			RunConsoleCommand("ai_serverragdolls", "0")
		end
	end
end
SPeditor.Hook("ShutDown", "SPeditor.saeditor.Corpses", function()
	if corpses.set then RunConsoleCommand("ai_serverragdolls", "0") end
end)

---------------------------------------------------------------------
-- Start and stop
-- where the eyes are from the head bone ({ bone, pos, ang } in the bone's space): the view of
-- a killed player is put there, so that it goes with the falling head
local function eyeOffset(ent)
	local att = ent:LookupAttachment("eyes")
	local b = ent:LookupBone("ValveBiped.Bip01_Head1")
	if not att or att <= 0 or not b then return nil end
	ent:GetBonePosition(0)
	local a, m = ent:GetAttachment(att), ent:GetBoneMatrix(b)
	if not a or not m then return nil end
	local pos, ang = WorldToLocal(a.Pos, a.Ang, m:GetTranslation(), m:GetAngles())
	return { bone = b, pos = pos, ang = ang }
end

---------------------------------------------------------------------
function SA.StartRecord(ply, opts)
	if R[ply] and R[ply].on then return end
	local a = SA.Anim(ply)
	local rec = {
		on = true, t0 = CurTime(), fps = a.fps, f0 = math.Clamp(math.floor(tonumber(opts.from) or 0), 0, a.frames),
		step = math.Clamp(math.floor(tonumber(opts.step) or 2), 1, 12),
		radius = math.Clamp(tonumber(opts.radius) or 1500, 64, 16384),
		npcs = opts.npcs ~= false, sounds = opts.sounds ~= false, effects = opts.effects ~= false,
		subjects = {}, nNpc = 0, nShot = 0, corpse = {}, sound = {}, fx = {},
		movers = {}, nMover = 0, moversOn = not opts.noPlayer, ply = ply,
		view = (opts.view and not opts.noPlayer) and {} or nil,
		vehicles = not opts.noPlayer and opts.vehicles ~= false,
	}
	R[ply] = rec
	-- the NPCs of the marks come to life with the recording
	if SA.WakeTakeNPCs then SA.WakeTakeNPCs(ply) end
	-- a setting of the whole server: on someone else's server only an admin may change it for a take
	if rec.npcs and opts.corpses ~= false and (game.SinglePlayer() or ply:IsListenServerHost() or ply:IsAdmin()) then corpsesOn(rec) end
	if rec.moversOn then addMovers(rec, ply:GetPos()) end
	if not opts.noPlayer then
		addSubject(rec, ply, "player")
		rec.eyes = eyeOffset(ply)
	end
	-- scene objects whose physics is recorded: unfrozen for the take
	local nPhys = 0
	for _, uid in ipairs(istable(opts.phys) and opts.phys or {}) do
		local e = tonumber(uid) and S.FindUID(ply, tonumber(uid))
		-- an object with keys plays along in a gameplay take: letting it go dropped the actor of
		-- the take before as a limp ragdoll (b0.2.3)
		if IsValid(e) and nPhys < MAX_PHYS and not S.IsAux(e) and not e.SPeditor_Attach and not rec.subjects[e]
			and e:GetPhysicsObjectCount() > 0 and (opts.noPlayer or not a.tracks[e.SPeditor_UID]) then
			nPhys = nPhys + 1
			rec.subjects[e] = { kind = "phys", ent = e, samples = {}, weapons = {} }
			e.SPeditor_PhysRec = true
			for i = 0, e:GetPhysicsObjectCount() - 1 do
				local p = e:GetPhysicsObjectNum(i)
				if IsValid(p) then
					p:EnableMotion(true)
					p:Wake()
				end
			end
		end
	end
	if rec.npcs or rec.vehicles then
		for _, e in ipairs(ents.FindInSphere(ply:GetPos(), rec.radius)) do
			if rec.npcs and isActor(e) then addSubject(rec, e, "npc")
			elseif rec.vehicles and isVehicle(e) then addSubject(rec, e, "vehicle") end
		end
	end
	hookEffects(true)
	-- the existing animation plays along from the frame the take starts at (in the game; a take
	-- with the editor open plays it without the in-game player)
	if next(a.tracks) ~= nil then
		a.show, a.showLoop = not opts.noPlayer or nil, false
		a.playing, a.cur = true, rec.f0
		a.t0, a.f0 = CurTime(), rec.f0
		SA.ApplyAll(ply, rec.f0, true)
	end
	notify(ply, { state = "started", f0 = rec.f0, t0 = rec.t0, fps = rec.fps, step = rec.step, view = rec.view and true or nil })
end

-- view samples from the client: whole frames inside the take, in order, a sane place and FOV
local function addView(rec, list)
	if not rec.view or not istable(list) then return end
	local last = rec.view[#rec.view]
	for _, v in ipairs(list) do
		if #rec.view >= MAX_VIEW then return end
		local f = istable(v) and tonumber(v[1])
		-- the gun in front of the eyes at frame f (b0.2.6, cl_saeditor_record.lua "record_vm")
		local vm = istable(v) and v[2] == "vm" and istable(v[3]) and v[3]
		if vm then
			if f and f >= rec.f0 and f < SA.MAX_FRAMES and isstring(vm.model) and #vm.model < 200
				and string.find(vm.model, "^models/.+%.mdl$") and istable(vm.root) and istable(vm.bones) then
				rec.vm = rec.vm or { n = 0 }
				if rec.vm.n < MAX_VIEW then
					rec.vm[math.floor(f)] = vm
					rec.vm.n = rec.vm.n + 1
				end
			end
			f = nil
		end
		local fov = f and tonumber(v[8])
		if fov and f >= rec.f0 and f < SA.MAX_FRAMES and (not last or f > last.f) then
			local x, y, z = tonumber(v[2]), tonumber(v[3]), tonumber(v[4])
			local p, yw, r = tonumber(v[5]), tonumber(v[6]), tonumber(v[7])
			if x and y and z and p and yw and r and math.abs(x) < 65536 and math.abs(y) < 65536 and math.abs(z) < 65536 then
				last = { f = math.floor(f), pos = Vector(x, y, z), ang = Angle(p, yw, r), fov = math.Clamp(fov, 5, 170) }
				rec.view[#rec.view + 1] = last
			end
		end
	end
end

-- sounds only the client played (Rec action 4): { { f, path, vol, pitch, ui }, … } — on the
-- player's copy, or heard everywhere (ui = 1); one the server heard too (the same file within
-- two frames) is not taken twice
local function addClientSounds(rec, ply, list)
	if not rec.sounds or not istable(list) then return end
	for _, v in ipairs(list) do
		if #rec.sound >= SA.MAX_SOUNDS then return end
		local f, path = istable(v) and tonumber(v[1]), istable(v) and v[2]
		if f and isstring(path) and #path < 200 and string.StartWith(path, "sound/") and not string.find(path, "..", 1, true)
			and f >= rec.f0 and f < SA.MAX_FRAMES then
			local ui = tonumber(v[5]) == 1
			local actor = not ui and ply or nil
			local dup = false
			for i = #rec.sound, math.max(#rec.sound - 40, 1), -1 do
				local c = rec.sound[i]
				if c.path == path and math.abs(c.f - f) <= 2 and (c.actor == actor or ui) then dup = true break end
			end
			if not dup then
				rec.sound[#rec.sound + 1] = { f = math.floor(f), path = path, actor = actor, ui = ui or nil,
					vol = math.Clamp(tonumber(v[3]) or 1, 0, 2), pitch = math.Clamp(tonumber(v[4]) or 100, 25, 400) }
			end
		end
	end
end

-- sounds the game kept playing and changing (Rec action 7, b0.2.6): { { f, path, len, loop,
-- ofs, owner entity index, env }, … } — the engine of the vehicle the player rode goes on its copy
local function addClientStreams(rec, ply, list)
	if not rec.sounds or not istable(list) then return end
	for _, v in ipairs(list) do
		if #rec.sound >= SA.MAX_SOUNDS then return end
		local f, path, len = istable(v) and tonumber(v[1]), istable(v) and v[2], istable(v) and tonumber(v[3])
		if f and len and isstring(path) and #path < 200 and (string.StartWith(path, "sound/") or string.StartWith(path, "data/"))
			and not string.find(path, "..", 1, true) and f >= rec.f0 and f < SA.MAX_FRAMES and istable(v[7]) then
			-- the owner, or what it is parented to (a wheel of Glide -> its vehicle)
			local owner = Entity(math.floor(tonumber(v[6]) or 0))
			for _ = 1, 4 do
				if not IsValid(owner) or rec.subjects[owner] then break end
				owner = owner:GetParent()
			end
			local actor = (IsValid(owner) and rec.subjects[owner]) and owner or ply
			rec.sound[#rec.sound + 1] = { f = math.floor(f), path = path, actor = actor, vol = 1, pitch = 100,
				long = { len = math.floor(len), loop = tonumber(v[4]) == 1, ofs = tonumber(v[5]) or 0, env = v[7] } }
		end
	end
end

-- effects only the client made (Rec action 5, a0.9): weapon bases (ARC9, TFA, ArcCW…) make their
-- muzzle flashes, impacts and smoke on the client, with util.Effect and particle systems, so the
-- server never sees them. { { f, src, name, x, y, z, p, yaw, r, len, file }, … }; one the server
-- has already (the same effect within two frames and 24 units) is not taken twice
local function addClientEffects(rec, ply, list)
	if not rec.effects or not istable(list) then return end
	for _, v in ipairs(list) do
		if #rec.fx >= 2000 then return end
		local f = istable(v) and tonumber(v[1])
		local src, name, file = v[2], v[3], v[11]
		local x, y, z = tonumber(v[4]), tonumber(v[5]), tonumber(v[6])
		local p, yw, r = tonumber(v[7]) or 0, tonumber(v[8]) or 0, tonumber(v[9]) or 0
		if f and (src == "lua" or src == "pcf") and isstring(name) and x and y and z and f >= rec.f0 and f < SA.MAX_FRAMES then
			local fx = SPeditor.CleanEffect({ src = src, name = name, file = isstring(file) and file or "" })
			local pos = Vector(x, y, z)
			if fx and SPeditor.ValidVec(pos) and pos:DistToSqr(ply:GetPos()) < rec.radius * rec.radius then
				local dup = false
				for i = #rec.fx, math.max(#rec.fx - 60, 1), -1 do
					local e = rec.fx[i]
					if e.name == fx.name and math.abs(e.f - f) <= 2 and e.pos:DistToSqr(pos) < 24 * 24 then dup = true break end
				end
				if not dup then
					addEffect(rec, fx.name, pos, Angle(p, yw, r), math.Clamp(tonumber(v[10]) or 0, 0, 8000), nil, fx.src, fx.file, math.floor(f))
				end
			end
		end
	end
end

-- the poses of the killed player's body from its client (Rec action 3): { [frame] = bones }
local MAX_BODIES = 4000
local function readBones(list)
	local bones = {}
	for _, b in ipairs(list) do
		local i = istable(b) and tonumber(b[1])
		local x, y, z = tonumber(b[2]), tonumber(b[3]), tonumber(b[4])
		local p, yw, r = tonumber(b[5]), tonumber(b[6]), tonumber(b[7])
		if i and x and y and z and p and yw and r and i >= 0 and i < 256 then
			bones[math.floor(i)] = { Vector(x, y, z), Angle(p, yw, r) }
		end
	end
	return bones
end

local function addBodies(rec, list)
	if not istable(list) then return end
	rec.body = rec.body or { n = 0 }
	rec.ride = rec.ride or { n = 0 }
	for _, v in ipairs(list) do
		local f = istable(v) and tonumber(v[1])
		local vi = istable(v) and tonumber(v[3])
		if f and istable(v[2]) and f >= rec.f0 and f < SA.MAX_FRAMES then
			if vi then
				-- the rider's pose (b0.2.6): bones in the space of the vehicle v[3]
				local veh = Entity(math.floor(vi))
				if IsValid(veh) and rec.ride.n < MAX_BODIES * 4 then
					rec.ride[math.floor(f)] = { veh = veh, bones = readBones(v[2]) }
					rec.ride.n = rec.ride.n + 1
				end
			elseif rec.view and rec.body.n < MAX_BODIES then
				local bones = readBones(v[2])
				if next(bones) ~= nil then
					rec.body[math.floor(f)] = bones
					rec.body.n = rec.body.n + 1
				end
			end
		end
	end
end

-- the samples of the dead player take the poses of its falling body (the nearest one sent
-- before the sample; the server's own are of a body standing invisible where it died)
local function deadPoses(rec, sub)
	local body = rec.body
	if not body or not sub then return end
	local frames = {}
	for f in pairs(body) do
		if isnumber(f) then frames[#frames + 1] = f end
	end
	if #frames == 0 then return end
	table.sort(frames)
	local j = 1
	for _, smp in ipairs(sub.samples) do
		if smp.dead then
			while frames[j + 1] and frames[j + 1] <= smp.f do j = j + 1 end
			if frames[j] <= smp.f + rec.step then smp.bones = body[frames[j]] end
		end
	end
end

-- A sample is taken at the first server tick past its frame — up to a tick (15 ms of the 83 ms
-- between two keys) late, and late by a different amount every time: at speed the keys stepped
-- unevenly (a motorbike went 12, 10, 12, 10 units a frame and shook). Each sample is put back
-- onto its whole frame, between itself and the one before (b0.2.6).
local function lerpPair(p, s, u)
	if not p then return s end
	return { LerpVector(u, p[1], s[1]), SA.SlerpAngle(p[2], s[2], u) }
end
local function lerpBones(pb, sb, u)
	if not pb or not sb then return sb end
	local out = {}
	for b, v in pairs(sb) do out[b] = lerpPair(pb[b], v, u) end
	return out
end
local function onFrames(samples)
	local out = {}
	for i, s in ipairs(samples) do
		local p = samples[i - 1]
		out[i] = s
		if p and p.ft and s.ft and s.ft - s.f > 0.001 and s.ft > p.ft and not s.dead and not p.dead then
			local u = math.Clamp((s.f - p.ft) / (s.ft - p.ft), 0, 1)
			out[i] = { f = s.f, bones = lerpBones(p.bones, s.bones, u), eye = s.eye and lerpPair(p.eye, s.eye, u),
				loc = s.loc and lerpBones(p.loc, s.loc, u), dead = s.dead }
		end
	end
	for i, s in ipairs(out) do samples[i] = s end
end

-- the rider's own pose (b0.2.6): the bones drawn on the player's client while it rode, put on
-- the place the vehicle had at the same frame of the take
local function ridePoses(rec, sub)
	local ride = rec.ride
	if not ride or (ride.n or 0) == 0 or not sub then return end
	local frames = {}
	for f in pairs(ride) do
		if isnumber(f) then frames[#frames + 1] = f end
	end
	table.sort(frames)
	local placeOf = {}
	local function vehicleAt(veh, f)
		local vs = rec.subjects[veh]
		if not vs then return nil end
		local m = placeOf[veh]
		if not m then
			m = {}
			for _, s in ipairs(vs.samples) do m[s.f] = s.bones[0] end
			placeOf[veh] = m
		end
		return m[f]
	end
	local j = 1
	for _, smp in ipairs(sub.samples) do
		while frames[j + 1] and frames[j + 1] <= smp.f do j = j + 1 end
		local rf = frames[j]
		local r = rf and rf <= smp.f and smp.f - rf <= rec.step and not smp.dead and ride[rf]
		local place = r and vehicleAt(r.veh, smp.f)
		if place then
			local bones = {}
			for b, v in pairs(smp.bones) do bones[b] = v end
			for b, v in pairs(r.bones) do bones[b] = { LocalToWorld(v[1], v[2], place[1], place[2]) } end
			smp.bones = bones
		end
	end
end

-- the ragdoll (or model) standing for an actor, with its look
local function makeActor(ply, sub)
	local first = sub.samples[1]
	if not first or sub.model == "" then return nil end
	local root = first.bones[0]
	local ent = S.SpawnModel(ply, sub.model, root and root[1] or ply:GetPos(), angle_zero)
	if not IsValid(ent) then return nil end
	S.ApplyAppearance(ent, sub.skin, (function()
		local g = {}
		for i, v in pairs(sub.groups) do g[tostring(i)] = v end
		return g
	end)())
	if sub.col and (sub.col.r < 255 or sub.col.g < 255 or sub.col.b < 255 or sub.col.a < 255) then
		S.ApplyLook(ent, { color = { sub.col.r, sub.col.g, sub.col.b, sub.col.a } })
	end
	if sub.pcol then ent:SetNW2Vector("SPeditor_PlayerColor", sub.pcol) end
	-- a projectile or a vehicle goes on its keys, not on physics
	if sub.kind == "shot" or sub.kind == "vehicle" then
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
	end
	local name = freeName(ply, sub.kind == "player" and (sub.name .. " (rec)") or sub.name, ent)
	ent.SPeditor_Name = name
	ent:SetNW2String("SPeditor_Name", name)
	return ent
end

-- put the ragdoll into the pose of a sample: every body at the place of its bone
local function pose(ent, smp)
	if S.IsRagdoll(ent) then
		for i = 0, ent:GetPhysicsObjectCount() - 1 do
			local b = ent:TranslatePhysBoneToBone(i)
			local m = b and smp.bones[b]
			if m then SA.SetPhys(ent:GetPhysicsObjectNum(i), m[1], m[2]) end
		end
		S.SnapRigid(ent)
	else
		local m = smp.bones[0]
		if m then S.SetTransform(ent, m[1], m[2]) end
	end
end

-- the bones of a recorded vehicle at a sample: offsets that take the copy's rest pose to the
-- pose the vehicle had (bone offsets are in the parent bone's space)
local function vehicleBones(ent, rest, loc)
	for b, r in pairs(rest) do
		local s = loc[b]
		if s then
			local dp = s[1] - r[1]
			local _, da = WorldToLocal(vector_origin, s[2], vector_origin, r[2])
			if dp:LengthSqr() < 1e-4 then dp = vector_origin end
			if math.abs(da.p) + math.abs(da.y) + math.abs(da.r) < 0.05 then da = angle_zero end
			ent:ManipulateBonePosition(b, dp)
			ent:ManipulateBoneAngles(b, da)
		end
	end
end

-- The gun in front of the eyes of a first-person take (b0.2.6): one model a gun held, hanging on the
-- view camera, keyed where it was in the view (camPlace: the camera's place at its keys) with every
-- bone as an offset from the model's rest pose; its hands are worn on it. Not held — not shown.
local function vmBones(e, s)
	local loc = {}
	for _, b in ipairs(istable(s.bones) and s.bones or {}) do
		local i = istable(b) and tonumber(b[1])
		local x, y, z, p, yw, r = tonumber(b[2]), tonumber(b[3]), tonumber(b[4]), tonumber(b[5]), tonumber(b[6]), tonumber(b[7])
		if i and x and y and z and p and yw and r and i >= 0 and i < e:GetBoneCount() then
			loc[math.floor(i)] = { Vector(x, y, z), Angle(p, yw, r), tonumber(b[8]) or 1 }
		end
	end
	return loc
end

-- one view object (the gun, or the hands): a model hanging on the camera, keyed at the frames
-- where get(sample) gives its part of the sample ({ root, bones }); hidden where it gives none
local function keyViewObject(ply, rec, cam, made, frames, placeAt, model, name, get, k)
	local first
	for _, f in ipairs(frames) do
		first = get(rec.vm[f])
		if first then break end
	end
	if not first then return nil end
	local p0 = placeAt(frames[1])
	local ent = S.SpawnModel(ply, model, p0[1], p0[2])
	if not IsValid(ent) then return nil end
	made.actors = made.actors + 1
	name = freeName(ply, name, ent)
	ent.SPeditor_Name = name
	ent:SetNW2String("SPeditor_Name", name)
	S.ApplyLook(ent, { vmfov = k, noshadow = true })
	if tonumber(first.skin) then ent:SetSkin(math.floor(first.skin)) end
	if isvector(first.col) then ent:SetNW2Vector("SPeditor_PlayerColor", first.col) end
	-- the rest pose the bone offsets are taken from: the client's, drawn in the model's first
	-- animation (the server's own is the bind pose); any sample of this model may carry it
	local restC
	for _, f in ipairs(frames) do
		local part = get(rec.vm[f])
		if part and istable(part.rest) then restC = part.rest break end
	end
	if not restC then
		for _, f in ipairs(frames) do
			local smp = rec.vm[f]
			for _, part in ipairs({ smp, smp.hands }) do
				if istable(part) and part.model == model and istable(part.rest) then restC = part.rest break end
			end
			if restC then break end
		end
	end
	local rest = restC and vmBones(ent, { bones = restC }) or {}
	S.Attach(ent, cam, -1)
	local was
	for _, f in ipairs(frames) do
		local part = get(rec.vm[f])
		local held = part ~= nil
		local place = placeAt(f)
		local r = part and part.root
		if held and place and istable(r) and tonumber(r[1]) then
			cam:SetPos(place[1])
			cam:SetAngles(place[2])
			local pos, ang = LocalToWorld(Vector(tonumber(r[1]) or 0, tonumber(r[2]) or 0, tonumber(r[3]) or 0),
				Angle(tonumber(r[4]) or 0, tonumber(r[5]) or 0, tonumber(r[6]) or 0), place[1], place[2])
			ent:SetPos(pos)
			ent:SetAngles(ang)
			S.RefreshAttach(ent)
			local loc = vmBones(ent, part)
			vehicleBones(ent, rest, loc)
			-- the parts the weapon base showed and hid (bodygroups) as they were at this frame
			for i = 0, ent:GetNumBodyGroups() - 1 do
				local bg = istable(part.bg) and tonumber(part.bg[tostring(i)] or part.bg[i]) or 0
				if ent:GetBodygroup(i) ~= bg then ent:SetBodygroup(i, bg) end
			end
			-- parts hidden by the weapon base (bones scaled to nothing) stay hidden
			for b, v in pairs(loc) do
				local sc = v[3] or 1
				if ent:GetManipulateBoneScale(b).x ~= sc then ent:ManipulateBoneScale(b, Vector(sc, sc, sc)) end
			end
		end
		-- a key at every frame it is shown and where it is taken out or put away
		if held ~= was or held then
			if held ~= was then
				ent:SetColor(Color(255, 255, 255, held and 255 or 0))
				ent:SetRenderMode(held and RENDERMODE_NORMAL or RENDERMODE_TRANSCOLOR)
				was = held
			end
			SA.SetKey(ply, ent, f, held and "spline" or "hold")
			made.keys = made.keys + 1
		end
	end
	ent:SetColor(color_white)
	ent:SetRenderMode(RENDERMODE_NORMAL)
	return ent
end

local function makeViewModels(ply, rec, cam, camPlace, made)
	local frames = {}
	for f in pairs(rec.vm) do
		if isnumber(f) then frames[#frames + 1] = f end
	end
	table.sort(frames)
	-- the camera's place at a frame: its key there, or the nearest one before
	local camFrames = {}
	for f in pairs(camPlace) do camFrames[#camFrames + 1] = f end
	table.sort(camFrames)
	if #camFrames == 0 or #frames == 0 then return end
	local function placeAt(f)
		local best
		for _, cf in ipairs(camFrames) do
			if cf > f then break end
			best = cf
		end
		return camPlace[best or camFrames[1]]
	end
	local cp0, ca0 = cam:GetPos(), cam:GetAngles()
	-- the guns: one model a gun held; the hands: one model for all of them, keyed by their own bones
	local guns, order, handModels, handOrder = {}, {}, {}, {}
	for _, f in ipairs(frames) do
		local smp = rec.vm[f]
		if not guns[smp.model] and util.IsValidModel(smp.model) then
			guns[smp.model] = tonumber(smp.k) or 1
			order[#order + 1] = smp.model
		end
		local h = istable(smp.hands) and smp.hands
		if h and isstring(h.model) and not handModels[h.model] and util.IsValidModel(h.model) then
			handModels[h.model] = tonumber(smp.k) or 1
			handOrder[#handOrder + 1] = h.model
		end
	end
	for _, model in ipairs(order) do
		keyViewObject(ply, rec, cam, made, frames, placeAt, model,
			string.StripExtension(string.GetFileFromFilename(model)) .. " (view)",
			function(smp) return smp.model == model and smp or nil end, guns[model])
	end
	for _, model in ipairs(handOrder) do
		keyViewObject(ply, rec, cam, made, frames, placeAt, model,
			string.StripExtension(string.GetFileFromFilename(model)) .. " (view hands)",
			function(smp) return istable(smp.hands) and smp.hands.model == model and smp.hands or nil end, handModels[model])
	end
	cam:SetPos(cp0)
	cam:SetAngles(ca0)
end

-- a model key of an attached object at the frame: visible or not (its colour's alpha)
local function visKey(ply, ent, f, visible)
	ent:SetColor(Color(255, 255, 255, visible and 255 or 0))
	ent:SetRenderMode(visible and RENDERMODE_NORMAL or RENDERMODE_TRANSCOLOR)
	SA.SetKey(ply, ent, f, "hold")
end

function SA.StopRecord(ply)
	local rec = R[ply]
	if not rec or not rec.on then return end
	rec.on = false
	hookEffects(false)
	SA.FinishTake(ply, rec)
end

-- The scene of a finished take: the actors keyed along it, their weapons, the sounds, the
-- effects, the view camera. Also for takes that come from a demo (SA.ImportDemoTake below).
function SA.FinishTake(ply, rec)
	local a = SA.Anim(ply)
	a.playing, a.show = false, nil
	local made = { actors = 0, keys = 0, sounds = 0, effects = 0, phys = 0 }
	local lastFrame = rec.lastF or rec.f0
	local uidOf = {}
	-- the animation grows to hold the take (a key past its end would be put on the last frame)
	if lastFrame + rec.step > a.frames then a.frames = math.min(lastFrame + rec.step, SA.MAX_FRAMES) end

	for _, sub in pairs(rec.subjects) do onFrames(sub.samples) end
	ridePoses(rec, rec.subjects[ply])

	-- map movers that moved: their samples become keys (the stretch of the take is replaced);
	-- a sample is kept where the motion starts, stops or changes, the rest is linear between
	a.world = a.world or {}
	made.movers = 0
	local function same(x, y)
		return x.pos:DistToSqr(y.pos) < 0.01 and math.abs(math.AngleDifference(x.ang.p, y.ang.p)) < 0.05
			and math.abs(math.AngleDifference(x.ang.y, y.ang.y)) < 0.05 and math.abs(math.AngleDifference(x.ang.r, y.ang.r)) < 0.05
	end
	for e, m in pairs(rec.movers) do
		if IsValid(e) then e.SPeditor_WorldRec = nil end
		local smp = m.samples
		local moved = false
		for i = 2, #smp do
			if not same(smp[i], smp[1]) then moved = true break end
		end
		if moved then
			local keep = {}
			for i, s in ipairs(smp) do
				if i == 1 or i == #smp or not same(s, smp[i - 1]) or not same(s, smp[i + 1]) then keep[#keep + 1] = s end
			end
			local w = a.world[m.id] or { c = m.class, keys = {} }
			local f0, f1 = smp[1].f, smp[#smp].f
			local keys = {}
			for _, k in ipairs(w.keys) do
				if k.f < f0 or k.f > f1 then keys[#keys + 1] = k end
			end
			for _, s in ipairs(keep) do keys[#keys + 1] = { f = s.f, pos = s.pos, ang = s.ang } end
			table.sort(keys, function(x, y) return x.f < y.f end)
			w.keys = keys
			a.world[m.id] = w
			made.movers = made.movers + 1
		end
	end

	-- the physics of scene objects: keys on the objects themselves, then they are frozen again
	for key, sub in pairs(rec.subjects) do
		if sub.kind == "phys" then
			rec.subjects[key] = nil
			local ent = sub.ent
			if IsValid(ent) then
				ent.SPeditor_PhysRec = nil
				ent.SPeditor_Guard = nil          -- the editor's guard takes the new place as the one to keep
				S.Freeze(ent)
				if #sub.samples > 0 then
					SA.ClearKeysIn(ply, ent, sub.samples[1].f, sub.samples[#sub.samples].f)
					for _, smp in ipairs(sub.samples) do
						pose(ent, smp)
						SA.SetKey(ply, ent, smp.f, "spline")
						made.keys = made.keys + 1
					end
					made.phys = made.phys + 1
					pose(ent, sub.samples[1])
				end
			end
		end
	end

	deadPoses(rec, rec.subjects[ply])
	for key, sub in pairs(rec.subjects) do
		if sub.kind == "shot" and sub.samples[1] then
			-- the moment it was fired, on a whole frame; the next sample may fall on the same one
			local s1, s2 = sub.samples[1], sub.samples[2]
			s1.f = math.floor(s1.f + 0.5)
			if s2 and s2.f <= s1.f then table.remove(sub.samples, 1) end
		end
		local ent = (#sub.samples > 1 or sub.kind == "shot" and #sub.samples == 1) and makeActor(ply, sub) or nil
		if IsValid(ent) then
			made.actors = made.actors + 1
			uidOf[key] = ent.SPeditor_UID
			-- a projectile is not there before it was fired: hidden from the start of the take
			local first = sub.samples[1]
			-- (b0.2.6) so is anything of a demo take that came later (sub.late)
			if (sub.kind == "shot" or sub.late) and first.f > rec.f0 then
				pose(ent, first)
				visKey(ply, ent, rec.f0, false)
				ent:SetColor(color_white)
				ent:SetRenderMode(RENDERMODE_NORMAL)
			end
			-- a vehicle's bones: the copy's own rest pose is the base the offsets are taken from
			local rest
			if sub.kind == "vehicle" and first.loc then
				rest = {}
				ent:GetBonePosition(0)
				for b in pairs(first.loc) do
					local m, pm = ent:GetBoneMatrix(b), ent:GetBoneMatrix(ent:GetBoneParent(b))
					if m and pm then rest[b] = { WorldToLocal(m:GetTranslation(), m:GetAngles(), pm:GetTranslation(), pm:GetAngles()) } end
				end
			end
			for _, smp in ipairs(sub.samples) do
				pose(ent, smp)
				if rest and smp.loc then vehicleBones(ent, rest, smp.loc) end
				SA.SetKey(ply, ent, smp.f, "spline")
				made.keys = made.keys + 1
			end
			local last = sub.samples[#sub.samples].f
			-- gone before the end of the take (died, removed, exploded): hidden from the next frame on
			if (sub.kind == "shot" or sub.kind == "vehicle") and not sub.gone and not IsValid(sub.ent) then sub.gone = last + rec.step end
			if sub.gone and sub.gone > last then
				pose(ent, sub.samples[#sub.samples])
				ent:SetColor(Color(255, 255, 255, 0))
				ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
				SA.SetKey(ply, ent, last + 1, "hold")
			end
			-- the weapons: one bone-merged model each, shown while it was held
			local byModel = {}
			for _, w in ipairs(sub.weapons) do
				if w.model ~= "" and string.find(w.model, "^models/") and util.IsValidModel(w.model) then byModel[w.model] = true end
			end
			for model in pairs(byModel) do
				local wep = S.SpawnModel(ply, model, ent:GetPos(), ent:GetAngles())
				if IsValid(wep) then
					S.Attach(wep, ent, S.WEAR)
					rec.worn = rec.worn or {}
					rec.worn[key] = rec.worn[key] or {}
					rec.worn[key][model] = wep
					local name = freeName(ply, string.StripExtension(string.GetFileFromFilename(model)), wep)
					wep.SPeditor_Name = name
					wep:SetNW2String("SPeditor_Name", name)
					local was
					for _, w in ipairs(sub.weapons) do
						local held = w.model == model
						if held ~= was then
							visKey(ply, wep, w.f, held)
							was = held
						end
					end
				end
			end
			pose(ent, sub.samples[1])
		end
	end

	-- the sounds, from the actors that made them
	if #rec.sound > 0 then
		local list = table.Copy(a.sounds or {})
		local id = 0
		for _, c in ipairs(list) do id = math.max(id, c.id or 0) end
		for _, c in ipairs(rec.sound) do
			local uid = c.ui and 0 or uidOf[c.actor]
			if uid and file.Exists(c.path, "GAME") then
				id = id + 1
				local clip = { id = id, path = c.path, f = c.f, uid = uid, vol = c.vol, pitch = c.pitch, dist = 600 }
				if c.long then
					-- played and changed by the game (an engine): its length and volume / pitch line
					clip.len, clip.loop, clip.env, clip.dist = c.long.len, c.long.loop, c.long.env, 1200
					if c.long.loop then clip.ofs = c.long.ofs else clip.cin = c.long.ofs end
					clip.fin, clip.fout = 0.05, 0.1
				-- a loop is cut a little after its last change, with a short fade
				elseif c.last then
					local len = SoundDuration(string.sub(c.path, 7)) or 0
					local played = ((c.last - c.f) / rec.fps + LOOP_IDLE * 0.5) * c.pitch / 100
					if len > played then
						clip.cout = len - played
						clip.fout = math.min(0.25, played)
					end
				end
				list[#list + 1] = clip
				made.sounds = made.sounds + 1
			end
		end
		a.sounds = SA.CleanSounds(list)
	end

	-- the effects: one object per kind, moved to every place it happened and fired there
	-- (one per kind and weapon for the effects fired from a weapon's attachment)
	local byName = {}
	for _, e in ipairs(rec.fx) do
		local m = e.mount
		local wep = m and rec.worn and rec.worn[m.actor] and rec.worn[m.actor][m.model]
		e.on = IsValid(wep) and wep.SPeditor_UID or nil
		local k = e.src .. "|" .. e.name .. "|" .. e.file .. "|" .. (e.on and (e.on .. "|" .. m.att) or "")
		byName[k] = byName[k] or {}
		table.insert(byName[k], e)
	end
	for _, list in pairs(byName) do
		local name, src, file = list[1].name, list[1].src, list[1].file
		local pcf = src == "pcf"
		-- one object fires again two frames after its last firing at the soonest (the effect
		-- restarts when its moment leaves zero, which takes a frame at zero before it): firings
		-- closer than that (the bullets of one shotgun shot) go to more objects of the kind
		local pool = {}
		for _, e in ipairs(list) do
			local slot
			for _, o in ipairs(pool) do
				if e.f >= o.prev + 2 then slot = o break end
			end
			if not slot and #pool < 8 then
				local fx = S.SpawnEffect(ply, { src = src, name = name, file = file, pos = e.pos, ang = e.ang, att = e.on and e.mount.att, on = e.on })
				if IsValid(fx) then
					slot = { fx = fx, prev = -10 }
					pool[#pool + 1] = slot
				end
			end
			if slot then
				local fx = slot.fx
				fx:SetPos(e.pos)
				fx:SetAngles(e.ang)
				fx:SetFxLength(e.len)
				fx:SetFxTime(0)
				SA.SetKey(ply, fx, e.f - 1, "hold")
				if pcf then
					-- a particle system shows the moment it is keyed at: it runs from 0 at the frame
					-- it was made up to PCF_RUN seconds later, linearly (the time of the video)
					local n = math.floor(PCF_RUN * rec.fps + 0.5)
					fx:SetFxTime(0.001)
					SA.SetKey(ply, fx, e.f, "linear")
					fx:SetFxTime(n / rec.fps)
					SA.SetKey(ply, fx, e.f + n, "hold")
					-- and is put out right after: a system held at its last moment stops
					-- simulating and its particles hung in the air for good (b0.1, the bullet
					-- smoke and sparks that stayed on the map after a take)
					fx:SetFxTime(0)
					SA.SetKey(ply, fx, e.f + n + 1, "hold")
					slot.prev = e.f + n + 1
				else
					fx:SetFxTime(1 / rec.fps)
					SA.SetKey(ply, fx, e.f, "hold")
					slot.prev = e.f
				end
				made.effects = made.effects + 1
			end
		end
		for _, o in ipairs(pool) do o.fx:SetFxTime(0) end
	end

	-- the player's view: a camera keyed along the take
	local view = rec.view
	-- The view camera sits in the eyes of the recorded character (a0.9): its place is taken from
	-- the character's own head at every sample of the take — the same frames as the character's
	-- keys, so it follows the head exactly, without the lag of the client's view (it was 4-10
	-- units behind and a tick late) — and it looks where the player looked. After the player's
	-- death the view turns with the falling head. A model without "eyes" keeps the client's view.
	local body = rec.subjects[ply]
	local function eyesOf(smp)
		local eyes = rec.eyes
		local h = eyes and smp.bones[eyes.bone]
		if not h then return nil end
		return LocalToWorld(eyes.pos, eyes.ang, h[1], h[2])
	end
	-- the player's view at frame f, between its samples
	local vi = 1
	local function viewAt(f)
		while view[vi + 1] and view[vi + 1].f <= f do vi = vi + 1 end
		local v0, v1 = view[vi], view[vi + 1] or view[vi]
		local t = v1.f > v0.f and math.Clamp((f - v0.f) / (v1.f - v0.f), 0, 1) or 0
		return LerpVector(t, v0.pos, v1.pos), LerpAngle(t, v0.ang, v1.ang), Lerp(t, v0.fov, v1.fov)
	end
	if view and #view >= 2 then
		local first = view[1]
		local cam = S.SpawnCamera(ply, { pos = first.pos, ang = first.ang, fov = first.fov, nomodel = true })
		if IsValid(cam) then
			local name = freeName(ply, rec.viewName or (ply:Nick() .. " view (rec)"), cam)
			cam.SPeditor_Name = name
			cam:SetNW2String("SPeditor_Name", name)
			local inHead = rec.eyes and body and #body.samples >= 2
			-- the camera of the take is the player's own eyes: its views do not draw the body at
			-- all, as the game does not (cl_saeditor_record.lua, b0.2.5)
			cam:SetNW2Bool("SPeditor_RecEyes", true)
			local camPlace = {}
			if inHead then
				for _, smp in ipairs(body.samples) do
					if smp.f >= view[1].f then
						local vp, va, fov = viewAt(smp.f)
						local ep, ea = eyesOf(smp)
						-- strictly first person: the player's own eyes and where it aimed, not the game's
						-- camera (it may have been a third-person one). Not the head of the model (b0.2.6):
						-- it bobs with the walk (2-4 units a step, out of step with the keys) and sits
						-- lower than the game's eyes — the take's view wobbled. The head is followed only
						-- after a death, as the body falls.
						local eye = smp.eye
						cam:SetPos((smp.dead and ep) or (eye and eye[1]) or ep or vp)
						cam:SetAngles(smp.dead and ea or (eye and eye[2]) or va)
						cam:SetCameraFOV(fov)
						SA.SetKey(ply, cam, smp.f, "spline")
						camPlace[smp.f] = { cam:GetPos(), cam:GetAngles() }
						made.keys = made.keys + 1
					end
				end
			else
				for _, v in ipairs(view) do
					if v.f > lastFrame + rec.step then break end
					cam:SetPos(v.pos)
					cam:SetAngles(v.ang)
					cam:SetCameraFOV(v.fov)
					SA.SetKey(ply, cam, v.f, "spline")
					camPlace[v.f] = { cam:GetPos(), cam:GetAngles() }
					made.keys = made.keys + 1
				end
			end
			if rec.vm and rec.vm.n > 0 then makeViewModels(ply, rec, cam, camPlace, made) end
			cam:SetPos(first.pos)
			cam:SetAngles(first.ang)
			cam:SetCameraFOV(first.fov)
			made.view = name
			-- no camera cuts yet: the video and the player go through the player's eyes
			if not a.cuts or #a.cuts == 0 then
				a.cuts = { { f = rec.f0, uid = cam.SPeditor_UID } }
				made.viewCut = true
			end
		end
	end

	corpsesOff(rec)
	R[ply] = nil
	SA.SendSummary(ply)
	SA.ApplyAll(ply, rec.f0)
	notify(ply, { state = "stopped", made = made, f0 = rec.f0 })
end

---------------------------------------------------------------------
-- Getting ready for a take (b0.2.1): the weapons the player chose in the Record window, health
-- and armour, god mode and ammunition for the time of the take. The weapons are checked against
-- the spawn menu's list and asked of the gamemode (PlayerGiveSWEP), as the Q menu does.
---------------------------------------------------------------------
local PREP_MAX_WEAPONS = 32

local function canGive(ply, class)
	local swep = list.Get("Weapon")[class]
	if not swep or (not swep.Spawnable and not ply:IsAdmin()) then return false end
	if swep.AdminOnly and not ply:IsAdmin() then return false end
	return hook.Run("PlayerGiveSWEP", ply, class, swep) ~= false
end

function SA.PrepareTake(ply, t)
	if not IsValid(ply) or not istable(t) then return end
	if not ply:Alive() then ply:Spawn() end
	local given = {}
	if istable(t.weapons) then
		if t.strip then ply:StripWeapons() end
		for i, class in ipairs(t.weapons) do
			if i > PREP_MAX_WEAPONS then break end
			if isstring(class) and canGive(ply, class) then
				local w = ply:HasWeapon(class) and ply:GetWeapon(class) or ply:Give(class)
				if IsValid(w) then
					given[#given + 1] = class
					local ammo = math.Clamp(math.floor(tonumber(t.ammo) or 0), 0, 9999)
					if ammo > 0 then
						if w:GetPrimaryAmmoType() >= 0 then ply:GiveAmmo(ammo, w:GetPrimaryAmmoType(), true) end
						if w:GetSecondaryAmmoType() >= 0 then ply:GiveAmmo(math.ceil(ammo / 10), w:GetSecondaryAmmoType(), true) end
					end
				end
			end
		end
		if given[1] then ply:SelectWeapon(given[1]) end
	end
	if t.heal then
		ply:SetHealth(ply:GetMaxHealth())
		ply:SetArmor(math.max(ply:Armor(), tonumber(t.armor) or 0))
	end
	if t.god then
		ply:GodEnable()
		ply.GMFM_TakeGod = true
	end
	if istable(t.npcs) then SA.SpawnTakeNPCs(ply, t.npcs, t.npcCleanup, t.npcWait) end
end

---------------------------------------------------------------------
-- The NPCs of a take on their marks (cl_saeditor_recnpcs.lua): spawned as the spawn menu does it
-- (its list "NPC": class, model, key values, spawn flags, weapons, skin, health), turned the way
-- the mark faces, with the weapon and the attitude to the player the mark asks for.
---------------------------------------------------------------------
local TAKE_NPCS_MAX = 64

local function removeTakeNPCs(ply)
	for _, e in ipairs(ply.GMFM_TakeNPCs or {}) do
		if IsValid(e) then e:Remove() end
	end
	ply.GMFM_TakeNPCs = nil
end

function SA.SpawnTakeNPCs(ply, marks, cleanup, wait)
	removeTakeNPCs(ply)
	local out = {}
	local defs = list.Get("NPC")
	for i, m in ipairs(marks) do
		if i > TAKE_NPCS_MAX then break end
		local d = isstring(m.class) and defs[m.class]
		local pos = isvector(m.pos) and m.pos
		if d and pos and (not d.AdminOnly or ply:IsAdmin()) and hook.Run("PlayerSpawnNPC", ply, m.class, m.weapon or "") ~= false then
			local npc = ents.Create(d.Class or m.class)
			if IsValid(npc) then
				npc:SetPos(pos + Vector(0, 0, tonumber(d.Offset) or 0))
				npc:SetAngles(Angle(0, tonumber(m.yaw) or 0, 0))
				if d.Model then npc:SetModel(d.Model) end
				if d.Material then npc:SetMaterial(d.Material) end
				local flags = bit.bor(SF_NPC_FADE_CORPSE, SF_NPC_ALWAYSTHINK)
				if d.SpawnFlags then flags = bit.bor(flags, d.SpawnFlags) end
				if d.TotalSpawnFlags then flags = d.TotalSpawnFlags end
				npc:SetKeyValue("spawnflags", tostring(flags))
				for k, v in pairs(d.KeyValues or {}) do npc:SetKeyValue(k, tostring(v)) end
				-- the weapon: the mark's, none, or one of the NPC's own (as the spawn menu by default)
				local wpn = m.weapon
				if wpn == nil or wpn == "" then
					wpn = istable(d.Weapons) and #d.Weapons > 0 and d.Weapons[math.random(#d.Weapons)] or nil
				end
				if isstring(wpn) and wpn ~= "" and wpn ~= "none" then npc:SetKeyValue("additionalequipment", wpn) end
				if d.Skin then npc:SetSkin(d.Skin) end
				npc:Spawn()
				npc:Activate()
				if d.Health then
					npc:SetHealth(d.Health)
					npc:SetMaxHealth(d.Health)
				end
				for k, v in pairs(d.BodyGroups or {}) do npc:SetBodygroup(k, v) end
				if m.att == 1 then npc:AddEntityRelationship(ply, D_HT, 99)
				elseif m.att == 2 then npc:AddEntityRelationship(ply, D_LI, 99) end
				out[#out + 1] = npc
			end
		end
	end
	ply.GMFM_TakeNPCs = out
	ply.GMFM_TakeNPCsCleanup = cleanup and true or false
	-- AI from the take on (b0.2.1): until the take really starts (after the countdown) they stand
	-- still — no thinking, nobody targets them — so nothing happens before the recording
	if wait then
		for _, npc in ipairs(out) do
			npc:AddEFlags(EFL_NO_THINK_FUNCTION)
			npc:AddFlags(FL_NOTARGET)
		end
		ply.GMFM_TakeNPCsWaiting = true
	end
end

-- the NPCs of the marks start thinking (the take has started, or the player is back in the editor)
function SA.WakeTakeNPCs(ply)
	if not ply.GMFM_TakeNPCsWaiting then return end
	ply.GMFM_TakeNPCsWaiting = nil
	for _, npc in ipairs(ply.GMFM_TakeNPCs or {}) do
		if IsValid(npc) then
			npc:RemoveEFlags(EFL_NO_THINK_FUNCTION)
			npc:RemoveFlags(FL_NOTARGET)
			npc:NextThink(CurTime())
		end
	end
end

local function takeGodOff(ply)
	if IsValid(ply) and ply.GMFM_TakeGod then
		ply.GMFM_TakeGod = nil
		ply:GodDisable()
	end
end
COMP:Hook("SPeditor_PlayerState", function(ply, on)
	-- back in the editor: the take's god mode ends with it, its NPCs go (they are in the scene as
	-- recorded actors) unless the player keeps them
	if on and not (R[ply] and R[ply].on) then
		takeGodOff(ply)
		SA.WakeTakeNPCs(ply)
		if ply.GMFM_TakeNPCsCleanup then removeTakeNPCs(ply) end
	end
end, "record_prep")

COMP:NetReceive("Rec", function(ply)
	local action = net.ReadUInt(3)
	if action == 6 then
		SA.PrepareTake(ply, SPeditor.ReadTable())
	elseif action == 4 then
		local rec = R[ply]
		if rec and rec.on then addClientSounds(rec, ply, SPeditor.ReadTable()) end
	elseif action == 5 then
		local rec = R[ply]
		if rec and rec.on then addClientEffects(rec, ply, SPeditor.ReadTable()) end
	elseif action == 7 then
		local rec = R[ply]
		if rec and rec.on then addClientStreams(rec, ply, SPeditor.ReadTable()) end
	elseif action == 2 or action == 3 then
		local rec = R[ply]
		if rec and rec.on then (action == 2 and addView or addBodies)(rec, SPeditor.ReadTable()) end
	elseif action == 1 then
		SA.StartRecord(ply, SPeditor.ReadTable() or {})
	else
		SA.StopRecord(ply)
	end
end, true)

COMP:Hook("PlayerDisconnected", function(ply)
	if R[ply] then
		for _, sub in pairs(R[ply].subjects) do
			if sub.kind == "phys" and IsValid(sub.ent) then sub.ent.SPeditor_PhysRec = nil end
		end
		for e in pairs(R[ply].movers or {}) do
			if IsValid(e) then e.SPeditor_WorldRec = nil end
		end
		corpsesOff(R[ply])
		R[ply] = nil
		hookEffects(false)
	end
end, "record")

---------------------------------------------------------------------
-- Takes from demos (b0.2.6, asked on the Workshop: "an analogue of HLAE — animations from demos
-- recorded on any server"). While a demo plays, the client records what is in it into a take file
-- (cl_saeditor_demo.lua); here such a file, sent in pieces, becomes the scene exactly as a take of
-- the recorder does (SA.FinishTake): players, NPCs and ragdolls as ragdolls keyed along it with
-- their weapons, props, vehicles and projectiles as keyed models, the demo's view as a camera,
-- the sounds as clips. It starts at the playhead; the frames are those of the animation.
---------------------------------------------------------------------
local DEMO_MAX = 32 * 1024 * 1024      -- the largest take file, compressed
local DEMO_UNPACKED = 512 * 1024 * 1024
local demoUp = {}

local function nums(str)
	local out = {}
	for v in string.gmatch(str or "", "[^,]+") do out[#out + 1] = tonumber(v) end
	return out
end
local function vecAng(t, i)
	local x, y, z, p, yw, r = t[i], t[i + 1], t[i + 2], t[i + 3], t[i + 4], t[i + 5]
	if not (x and y and z and p and yw and r) or math.abs(x) > 65536 or math.abs(y) > 65536 or math.abs(z) > 65536 then return nil end
	return { Vector(x, y, z), Angle(p, yw, r) }
end

-- a sample "f|ft|dead|eye x,y,z,p,y,r|b:x,y,z,p,y,r;…|loc b:…;…" of the take's own frames
local function demoSample(str, k, f0)
	local parts = string.Explode("|", str)
	local tf, tft = tonumber(parts[1]), tonumber(parts[2])
	if not tf then return nil end
	local smp = { f = f0 + tf * k, ft = f0 + (tft or tf) * k, dead = parts[3] == "1" or nil, bones = {} }
	if parts[4] and parts[4] ~= "" then smp.eye = vecAng(nums(parts[4]), 1) end
	for b, v in string.gmatch(parts[5] or "", "(%d+):([^;]+)") do
		local pa = vecAng(nums(v), 1)
		if pa and tonumber(b) < 256 then smp.bones[tonumber(b)] = pa end
	end
	if parts[6] and parts[6] ~= "" then
		smp.loc = {}
		for b, v in string.gmatch(parts[6], "(%d+):([^;]+)") do
			local pa = vecAng(nums(v), 1)
			if pa and tonumber(b) < 256 then smp.loc[tonumber(b)] = pa end
		end
	end
	if not smp.bones[0] then return nil end
	return smp
end

local KINDS = { player = true, npc = true, shot = true, vehicle = true }
function SA.ImportDemoTake(ply, take)
	if R[ply] and R[ply].on then
		S.Notice(ply, "#sa_dm_busy", 1)
		return
	end
	if not istable(take) or not istable(take.subjects) then
		S.Notice(ply, "#sa_dm_bad", 1)
		return
	end
	local a = SA.Anim(ply)
	local f0 = math.Clamp(math.floor(tonumber(take.at) or a.cur or 0), 0, SA.MAX_FRAMES - 1)
	-- the take's frames (its own rate) on the animation's frames
	local k = a.fps / math.Clamp(tonumber(take.fps) or a.fps, 1, 240)
	local rec = {
		on = true, t0 = CurTime(), fps = a.fps, f0 = f0, step = math.max(math.floor((tonumber(take.step) or 1) * k + 0.5), 1),
		radius = 1e6, npcs = true, sounds = true, effects = true,
		subjects = {}, nNpc = 0, nShot = 0, corpse = {}, sound = {}, fx = {}, movers = {}, nMover = 0, ply = ply,
		view = {}, viewName = isstring(take.viewName) and string.sub(take.viewName, 1, 60) or "demo view",
	}
	local last = f0
	local keyOf = {}
	for i, t in ipairs(take.subjects) do
		if istable(t) and KINDS[t.kind] and isstring(t.model) and string.find(t.model, "^models/.+%.mdl$") and #t.model < 200
			and util.IsValidModel(t.model) and istable(t.s) then
			local key = { demo = i }
			local sub = { kind = t.kind, model = string.lower(t.model), samples = {}, weapons = {},
				skin = math.floor(tonumber(t.skin) or 0), groups = {}, name = isstring(t.name) and string.sub(t.name, 1, 60) or t.kind,
				late = t.late and true or nil }
			for gi, gv in pairs(istable(t.groups) and t.groups or {}) do
				if tonumber(gi) and tonumber(gv) then sub.groups[math.floor(tonumber(gi))] = math.floor(tonumber(gv)) end
			end
			if istable(t.col) and #t.col == 4 then sub.col = Color(tonumber(t.col[1]) or 255, tonumber(t.col[2]) or 255, tonumber(t.col[3]) or 255, tonumber(t.col[4]) or 255) end
			if istable(t.pcol) and #t.pcol == 3 then sub.pcol = Vector(tonumber(t.pcol[1]) or 0, tonumber(t.pcol[2]) or 0, tonumber(t.pcol[3]) or 0) end
			for _, str in ipairs(t.s) do
				local smp = isstring(str) and demoSample(str, k, f0)
				if smp and smp.f < SA.MAX_FRAMES then
					smp.f = math.floor(smp.f + 0.5)
					local prev = sub.samples[#sub.samples]
					if not prev or smp.f > prev.f then sub.samples[#sub.samples + 1] = smp end
				end
			end
			for _, str in ipairs(istable(t.w) and t.w or {}) do
				local wf, wm = string.match(isstring(str) and str or "", "^([%d%.]+)|(.*)$")
				if wf and #wm < 200 then sub.weapons[#sub.weapons + 1] = { f = math.floor(f0 + tonumber(wf) * k + 0.5), model = string.lower(wm) } end
			end
			if tonumber(t.gone) then sub.gone = math.floor(f0 + tonumber(t.gone) * k + 0.5) end
			if #sub.samples > 0 then
				rec.subjects[key] = sub
				keyOf[tonumber(t.id) or -i] = key
				last = math.max(last, sub.samples[#sub.samples].f)
			end
		end
	end
	for _, str in ipairs(istable(take.view) and take.view or {}) do
		local v = nums(isstring(str) and string.gsub(str, "|", ",") or "")
		local f, pa = tonumber(v[1]), vecAng(v, 2)
		if f and pa and v[8] then
			f = math.floor(f0 + f * k + 0.5)
			local prev = rec.view[#rec.view]
			if f < SA.MAX_FRAMES and (not prev or f > prev.f) then
				rec.view[#rec.view + 1] = { f = f, pos = pa[1], ang = pa[2], fov = math.Clamp(v[8], 5, 170) }
			end
		end
	end
	for _, c in ipairs(istable(take.sounds) and take.sounds or {}) do
		local f, path = istable(c) and tonumber(c[1]), istable(c) and c[2]
		if f and isstring(path) and #path < 200 and string.StartWith(path, "sound/") and not string.find(path, "..", 1, true)
			and #rec.sound < SA.MAX_SOUNDS then
			local actor = keyOf[tonumber(c[5]) or -1]
			rec.sound[#rec.sound + 1] = { f = math.floor(f0 + f * k + 0.5), path = path, actor = actor, ui = not actor or nil,
				vol = math.Clamp(tonumber(c[3]) or 1, 0, 2), pitch = math.Clamp(tonumber(c[4]) or 100, 25, 400) }
		end
	end
	if next(rec.subjects) == nil and #rec.view < 2 then
		S.Notice(ply, "#sa_dm_empty", 1)
		return
	end
	rec.lastF = last
	rec.on = false
	R[ply] = rec
	SA.FinishTake(ply, rec)
end

COMP:NetReceive("Demo", function(ply)
	local serial, part, parts = net.ReadUInt(16), net.ReadUInt(16), net.ReadUInt(16)
	local len = net.ReadUInt(32)
	if parts == 0 or part == 0 or part > parts or len > 65000 or parts * 64000 > DEMO_MAX then return end
	local up = demoUp[ply]
	if not up or up.serial ~= serial then
		up = { serial = serial, parts = parts, got = 0, data = {} }
		demoUp[ply] = up
	end
	if up.data[part] then return end
	up.data[part] = net.ReadData(len)
	up.got = up.got + 1
	if up.got < up.parts then return end
	demoUp[ply] = nil
	local raw = util.Decompress(table.concat(up.data), DEMO_UNPACKED)
	local take = raw and util.JSONToTable(raw)
	if not take then
		S.Notice(ply, "#sa_dm_bad", 1)
		return
	end
	local ok, err = pcall(SA.ImportDemoTake, ply, take)
	if not ok then
		R[ply] = nil
		ErrorNoHalt("[GM:FM] demo take: " .. tostring(err) .. "\n")
		S.Notice(ply, "#sa_dm_bad", 1)
	end
end)

COMP:Hook("PlayerDisconnected", function(ply) demoUp[ply] = nil end, "demo")
