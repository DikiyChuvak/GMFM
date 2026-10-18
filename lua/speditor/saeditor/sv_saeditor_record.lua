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
0 = stop, 2 = a batch of view samples { { f, x, y, z, p, y, r, fov }, … }; the server answers with
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
	if rec.subjects[ent] or (kind == "npc" and rec.nNpc >= MAX_NPCS) or (kind == "shot" and rec.nShot >= MAX_SHOTS) then return end
	if kind == "npc" then rec.nNpc = rec.nNpc + 1 end
	if kind == "shot" then rec.nShot = rec.nShot + 1 end
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
				sub.samples[#sub.samples + 1] = { f = f, bones = bones }
			end
		elseif sub.kind == "shot" and IsValid(ent) and not sub.gone then
			-- a projectile: one rigid body, its place is the pose
			sub.samples[#sub.samples + 1] = { f = f, bones = { [0] = { ent:GetPos(), ent:GetAngles() } } }
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
			sub.samples[#sub.samples + 1] = { f = f, bones = bones }
			local wep = ent.GetActiveWeapon and ent:GetActiveWeapon()
			local wm = IsValid(wep) and string.lower(wep:GetModel() or "") or ""
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
				-- NPCs that came into the radius during the take
				if rec.npcs and CurTime() >= (rec.nextScan or 0) then
					rec.nextScan = CurTime() + 0.5
					for _, e in ipairs(ents.FindInSphere(ply:GetPos(), rec.radius)) do
						if isActor(e) then addSubject(rec, e, "npc") end
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

COMP:Hook("EntityEmitSound", function(t)
	for _, rec in pairs(R) do
		if rec.on and rec.sounds then
			local actor = actorOf(rec, t.Entity)
			if actor and #rec.sound < SA.MAX_SOUNDS then
				local path = string.lower(string.gsub(t.SoundName or "", "^[%^%)%(%#%*%$%<%>%!%?%@%&%~%%]+", ""))
				path = "sound/" .. string.gsub(path, "\\", "/")
				rec.sound[#rec.sound + 1] = { f = math.floor(frameNow(rec) + 0.5), path = path, actor = actor,
					vol = math.Clamp(t.Volume or 1, 0, 2), pitch = math.Clamp(t.Pitch or 100, 25, 400) }
			end
		end
	end
end, "record")

local function addEffect(rec, name, pos, ang, len)
	if not rec.effects or #rec.fx >= 2000 or not isstring(name) or not SPeditor.ValidVec(pos) then return end
	rec.fx[#rec.fx + 1] = { f = math.floor(frameNow(rec) + 0.5), name = name, pos = pos, ang = ang or angle_zero, len = len or 0 }
end

-- shots of the actors: a tracer from the gun to where the bullet hit
COMP:Hook("EntityFireBullets", function(ent, data)
	for _, rec in pairs(R) do
		if rec.on and rec.effects and actorOf(rec, ent) and data and data.Src and data.Dir then
			local tr = util.TraceLine({ start = data.Src, endpos = data.Src + data.Dir * 16384, filter = ent, mask = MASK_SHOT })
			local len = tr.HitPos:Distance(data.Src)
			if len > 32 then addEffect(rec, "Tracer", data.Src, data.Dir:Angle(), len) end
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

-- util.Effect of weapons and addons, while a take with effects is on
local realEffect
local function hookEffects(on)
	if on and not realEffect then
		realEffect = util.Effect
		util.Effect = function(name, data, ...)
			for ply, rec in pairs(R) do
				if rec.on and rec.effects and data and name ~= "Tracer" then
					local pos = data:GetOrigin()
					if pos:DistToSqr(ply:GetPos()) < rec.radius * rec.radius then
						local start = data:GetStart()
						local len = (start ~= vector_origin and start:Distance(pos) > 1) and start:Distance(pos) or 0
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
	}
	R[ply] = rec
	-- a setting of the whole server: on someone else's server only an admin may change it for a take
	if rec.npcs and opts.corpses ~= false and (game.SinglePlayer() or ply:IsListenServerHost() or ply:IsAdmin()) then corpsesOn(rec) end
	if rec.moversOn then addMovers(rec, ply:GetPos()) end
	if not opts.noPlayer then addSubject(rec, ply, "player") end
	-- scene objects whose physics is recorded: unfrozen for the take
	local nPhys = 0
	for _, uid in ipairs(istable(opts.phys) and opts.phys or {}) do
		local e = tonumber(uid) and S.FindUID(ply, tonumber(uid))
		if IsValid(e) and nPhys < MAX_PHYS and not S.IsAux(e) and not e.SPeditor_Attach and not rec.subjects[e]
			and e:GetPhysicsObjectCount() > 0 then
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
	if rec.npcs then
		for _, e in ipairs(ents.FindInSphere(ply:GetPos(), rec.radius)) do
			if isActor(e) then addSubject(rec, e, "npc") end
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
	-- a projectile flies on its keys, not on physics
	if sub.kind == "shot" then
		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
	end
	local name = sub.kind == "player" and (sub.name .. " (rec)") or sub.name
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
	local a = SA.Anim(ply)
	a.playing, a.show = false, nil
	local made = { actors = 0, keys = 0, sounds = 0, effects = 0, phys = 0 }
	local lastFrame = rec.lastF or rec.f0
	local uidOf = {}
	-- the animation grows to hold the take (a key past its end would be put on the last frame)
	if lastFrame + rec.step > a.frames then a.frames = math.min(lastFrame + rec.step, SA.MAX_FRAMES) end

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
			if sub.kind == "shot" and first.f > rec.f0 then
				pose(ent, first)
				visKey(ply, ent, rec.f0, false)
				ent:SetColor(color_white)
				ent:SetRenderMode(RENDERMODE_NORMAL)
			end
			for _, smp in ipairs(sub.samples) do
				pose(ent, smp)
				SA.SetKey(ply, ent, smp.f, "spline")
				made.keys = made.keys + 1
			end
			local last = sub.samples[#sub.samples].f
			-- gone before the end of the take (died, removed, exploded): hidden from the next frame on
			if sub.kind == "shot" and not sub.gone and not IsValid(sub.ent) then sub.gone = last + rec.step end
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
					local name = string.StripExtension(string.GetFileFromFilename(model))
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
			local uid = uidOf[c.actor]
			if uid and file.Exists(c.path, "GAME") then
				id = id + 1
				list[#list + 1] = { id = id, path = c.path, f = c.f, uid = uid, vol = c.vol, pitch = c.pitch, dist = 600 }
				made.sounds = made.sounds + 1
			end
		end
		a.sounds = SA.CleanSounds(list)
	end

	-- the effects: one object per kind, moved to every place it happened and fired there
	local byName = {}
	for _, e in ipairs(rec.fx) do
		byName[e.name] = byName[e.name] or {}
		table.insert(byName[e.name], e)
	end
	for name, list in pairs(byName) do
		local fx = S.SpawnEffect(ply, { src = "lua", name = name, pos = list[1].pos, ang = list[1].ang })
		if IsValid(fx) then
			local prev = -10
			for _, e in ipairs(list) do
				-- two firings one frame apart cannot both be shown: the effect restarts when its
				-- moment leaves zero, which takes a frame at zero before it
				if e.f >= prev + 2 then
					fx:SetPos(e.pos)
					fx:SetAngles(e.ang)
					fx:SetFxLength(e.len)
					fx:SetFxTime(0)
					SA.SetKey(ply, fx, e.f - 1, "hold")
					fx:SetFxTime(1 / rec.fps)
					SA.SetKey(ply, fx, e.f, "hold")
					prev = e.f
					made.effects = made.effects + 1
				end
			end
			fx:SetFxTime(0)
		end
	end

	-- the player's view: a camera keyed along the take
	local view = rec.view
	if view and #view >= 2 then
		local first = view[1]
		local cam = S.SpawnCamera(ply, { pos = first.pos, ang = first.ang, fov = first.fov })
		if IsValid(cam) then
			local name = ply:Nick() .. " view (rec)"
			cam.SPeditor_Name = name
			cam:SetNW2String("SPeditor_Name", name)
			for _, v in ipairs(view) do
				if v.f > lastFrame + rec.step then break end
				cam:SetPos(v.pos)
				cam:SetAngles(v.ang)
				cam:SetCameraFOV(v.fov)
				SA.SetKey(ply, cam, v.f, "spline")
				made.keys = made.keys + 1
			end
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

COMP:NetReceive("Rec", function(ply)
	local action = net.ReadUInt(2)
	if action == 2 then
		local rec = R[ply]
		if rec and rec.on then addView(rec, SPeditor.ReadTable()) end
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
