-- SPeditor server logic: spawning, transforms, bones, flexes, lights, cameras
SPeditor.Server = SPeditor.Server or {}
local S   = SPeditor.Server
local Net = SPeditor.Net
local Cfg = SPeditor.Config

S.Owned  = S.Owned  or {}   -- [ply] = { ent, ... }
S.Active = S.Active or {}

local ONE = Vector(1, 1, 1)

function S.IsRagdoll(ent) return IsValid(ent) and ent:GetClass() == "prop_ragdoll" end
function S.IsLight(ent)   return IsValid(ent) and ent:GetClass() == "speditor_light" end
function S.IsCamera(ent)  return IsValid(ent) and ent:GetClass() == "speditor_camera" end
-- Auxiliary objects without bones, flexes or a pose
function S.IsEffect(ent)  return IsValid(ent) and ent:GetClass() == "speditor_effect" end
function S.IsAux(ent)     return S.IsLight(ent) or S.IsCamera(ent) or S.IsEffect(ent) end

local function kindOf(ent)
	if S.IsLight(ent) then return "light" end
	if S.IsCamera(ent) then return "camera" end
	if S.IsEffect(ent) then return "effect" end
	return "prop"
end

local LIMITS = {
	prop   = function() return Cfg.MaxProps end,
light  = function() return Cfg.MaxLights end,
camera = function() return Cfg.MaxCameras or 16 end,
	effect = function() return Cfg.MaxEffects or 64 end,
}

---------------------------------------------------------------------
-- Tracking the player's entities
---------------------------------------------------------------------
function S.List(ply)
	local list = S.Owned[ply]
	if not list then
		list = {}
		S.Owned[ply] = list
	end
	for i = #list, 1, -1 do
		if not IsValid(list[i]) then table.remove(list, i) end
	end
	return list
end

function S.CountKind(ply, kind)
	local n = 0
	for _, e in ipairs(S.List(ply)) do
		if kindOf(e) == kind then n = n + 1 end
	end
	return n
end

function S.AtLimit(ply, kind)
	return S.CountKind(ply, kind) >= LIMITS[kind]()
end

-- An object's UID is stable between deletion and restoring (undo/redo)
S.NextUID   = S.NextUID or {}
S.Graveyard = S.Graveyard or {}

function S.SetUID(ent, uid)
	ent.SPeditor_UID = uid
	ent:SetNW2Int("SPeditor_UID", uid)
end

-- Multiplayer (found by the a0.8 self-test on a listen server): an entity that gets the index of
-- an entity removed a moment ago (clearing and loading a scene, undo) does not send the NW2
-- values that equal the old entity's — the server takes them for sent, while the client starts
-- the new entity from defaults. The scene then lost "this is an editor object" and "whose it is",
-- so objects vanished from the editor after loading. Every SPeditor_* value of a new object is
-- therefore sent once more: first a different value, a moment later the real one.
local NW2_SET = { Bool = "SetNW2Bool", Int = "SetNW2Int", Float = "SetNW2Float", String = "SetNW2String",
	Entity = "SetNW2Entity", Vector = "SetNW2Vector", Angle = "SetNW2Angle" }
local function otherValue(kind, v)
	if kind == "Bool" then return not v end
	if kind == "Int" then return v + 1 end
	if kind == "Float" then return v + 0.001 end
	if kind == "String" then return v .. " " end
	if kind == "Entity" then return IsValid(v) and NULL or nil end
	if kind == "Vector" then return v + Vector(0.001, 0, 0) end
	if kind == "Angle" then return v + Angle(0.001, 0, 0) end
end

function S.ResendNW2(ent, delay)
	if game.SinglePlayer() then return end
	timer.Simple(delay or 0.1, function()
		if not IsValid(ent) then return end
		local real = {}
		for key, t in pairs(ent:GetNW2VarTable() or {}) do
			local set = istable(t) and NW2_SET[t.type]
			if set and isstring(key) and string.StartWith(key, "SPeditor_") then
				local other = otherValue(t.type, t.value)
				if other ~= nil then
					real[key] = { set = set, value = t.value, other = other }
					ent[set](ent, key, other)
				end
			end
		end
		timer.Simple(0.1, function()
			if not IsValid(ent) then return end
			for key, r in pairs(real) do
				-- changed meanwhile by the editor itself: that value stands
				local now = ent:GetNW2VarTable()[key]
				if now and now.value == r.other then ent[r.set](ent, key, r.value) end
			end
		end)
	end)
end

function S.Track(ply, ent)
	ent.SPeditor_Owner = ply
	ent:SetNW2Bool("SPeditor_Ent", true)
	ent:SetNW2Entity("SPeditor_OwnerPly", ply)    -- for the client: whose object it is
	local uid = (S.NextUID[ply] or 0) + 1
	S.NextUID[ply] = uid
	S.SetUID(ent, uid)
	table.insert(S.List(ply), ent)
	-- twice: values set right after spawning (a loaded scene's names, looks, attachments) too
	S.ResendNW2(ent, 0.1)
	S.ResendNW2(ent, 1)
end

function S.FindUID(ply, uid)
	for _, e in ipairs(S.List(ply)) do
		if e.SPeditor_UID == uid then return e end
	end
end

-- The "bin": state of a deleted object for undo (the last 40)
local MAX_GRAVE = 40

function S.Bury(ply, ent)
	if not S.Serialize then return end
	local item = S.Serialize(ent)
	if not item or not ent.SPeditor_UID then return end
	item.uid = ent.SPeditor_UID
	local gy = S.Graveyard[ply]
	if not gy then
		gy = { order = {}, items = {} }
		S.Graveyard[ply] = gy
	end
	if not gy.items[item.uid] then table.insert(gy.order, item.uid) end
	gy.items[item.uid] = item
	while #gy.order > MAX_GRAVE do
		gy.items[table.remove(gy.order, 1)] = nil
	end
end

function S.RemoveWithRecord(ply, ent)
	S.Bury(ply, ent)
	if S.RemoveExtras then S.RemoveExtras(ent) end
	ent:Remove()
end

function S.CleanupPlayer(ply)
	for _, e in ipairs(S.List(ply)) do
		if IsValid(e) then
			if S.RemoveExtras then S.RemoveExtras(e) end
			e:Remove()
		end
	end
	S.Owned[ply] = {}
	S.Graveyard[ply] = nil
	hook.Run("SPeditor_PlayerCleanup", ply)      -- SAeditor resets its scene data
end

-- Tell the client the index of the new entity so that it gets selected
function S.SendSpawned(ply, ent, fromHistory)
	net.Start(Net.Spawned)
	net.WriteUInt(ent:EntIndex(), 16)
	net.WriteUInt(ent.SPeditor_UID or 0, 32)
	net.WriteBool(fromHistory and true or false)
	net.Send(ply)
end

-- The player and their weapon cast no shadow in editor mode.
-- PrePlayerDraw on the client hides only the model, and the shadow kept falling
-- from the player's real position — hence the "black blob" near the camera.
-- SetNoDraw is NOT used on the server: per the wiki such an entity stops
-- being transmitted to clients.
local function setPlayerGhost(ply, ghost)
	if not IsValid(ply) then return end
	ply:DrawShadow(not ghost)
	for _, w in ipairs(ply:GetWeapons()) do
		if IsValid(w) then w:DrawShadow(not ghost) end
	end
end

SPeditor.Hook("WeaponEquip", "SPeditor.GhostWeapon", function(wep, ply)
	if IsValid(ply) and S.Active[ply] then
		timer.Simple(0, function() if IsValid(wep) then wep:DrawShadow(false) end end)
	end
end)

SPeditor.Hook("PlayerSpawn", "SPeditor.GhostRespawn", function(ply)
	if S.Active[ply] then timer.Simple(0.1, function() setPlayerGhost(ply, true) end) end
end)

function S.SetActive(ply, on)
	S.Active[ply] = on and true or nil
	setPlayerGhost(ply, on and true or false)
	-- On opening, the ragdolls stay where they are now: with the editor closed they may have been
	-- posed by other tools (physgun, Ragdoll Mover), and the ragdoll guard below still kept the
	-- places from the last session — it put the bodies back there (b0.1, a Workshop report).
	if on then
		for _, e in ipairs(S.List(ply)) do
			if IsValid(e) and e.SPeditor_Guard then
				e.SPeditor_Guard = nil
				e.SPeditor_Placed = true
			end
		end
	end
	-- On leaving the editor the view flags of the cameras are reset
	if not on then
		for _, e in ipairs(S.List(ply)) do
			if S.IsCamera(e) then
				e:SetEnabled(false)
				e:SetViewOwner(NULL)
			end
		end
	end
	net.Start(Net.State)
	net.WriteBool(on and true or false)
	net.Send(ply)
	hook.Run("SPeditor_PlayerState", ply, on and true or false)
end

---------------------------------------------------------------------
-- Physics: freezing, the original pose, transforms
---------------------------------------------------------------------
function S.Freeze(ent)
	for i = 0, ent:GetPhysicsObjectCount() - 1 do
		local p = ent:GetPhysicsObjectNum(i)
		if IsValid(p) then p:EnableMotion(false) end
	end
end

-- The original ragdoll pose (local to physics object 0)
function S.StoreInit(ent)
	if not S.IsRagdoll(ent) then return end
	local root = ent:GetPhysicsObjectNum(0)
	if not IsValid(root) then return end
	local rp, ra = root:GetPos(), root:GetAngles()
	local init = {}
	for i = 0, ent:GetPhysicsObjectCount() - 1 do
		local p = ent:GetPhysicsObjectNum(i)
		if IsValid(p) then
			local lp, la = WorldToLocal(p:GetPos(), p:GetAngles(), rp, ra)
			init[i] = { pos = lp, ang = la }
		end
	end
	ent.SPeditor_Init = init
end

-- How the client draws a ragdoll. Of what the server sends about a body the client uses the
-- angle only (the pelvis is the exception: it gives the place of the whole ragdoll); the
-- place of every other bone it finds itself, going down the skeleton with the bone lengths
-- of the model. Measured in game on a pose taken from an animation: the chest was drawn
-- 5 units and the hands 7 units away from where the server kept their bodies — and a
-- weapon attached to the hand body hung beside the hand.
-- S.RigidLinks(ent)[i] = { parent = index of the parent body, lpos = the place of body i in
-- the parent's space } — from the pose the ragdoll was spawned in.
function S.RigidLinks(ent)
	if ent.SPeditor_Links ~= nil then return ent.SPeditor_Links end
	local init = ent.SPeditor_Init
	local links = false
	if init and S.IsRagdoll(ent) then
		links = {}
		for i = 1, ent:GetPhysicsObjectCount() - 1 do
			-- the nearest ancestor bone that has a body of its own
			local bone, parent, guard = ent:TranslatePhysBoneToBone(i), nil, 0
			while bone and bone >= 0 and guard < 128 do
				bone = ent:GetBoneParent(bone)
				guard = guard + 1
				if bone and bone >= 0 then
					local phys = SPeditor.PhysOfBone(ent, bone)
					if phys and phys ~= i then
						parent = phys
						break
					end
				end
			end
			if parent and init[i] and init[parent] then
				links[i] = { parent = parent, lpos = WorldToLocal(init[i].pos, init[i].ang, init[parent].pos, init[parent].ang) }
			end
		end
	end
	ent.SPeditor_Links = links
	return links
end

-- Puts the places in world = { [i] = { pos, ang } } where the client will draw the bones
function S.RigidPlaces(ent, world)
	local links = S.RigidLinks(ent)
	if not links then return world end
	local done = { [0] = true }
	local function place(i)
		if done[i] then return end
		done[i] = true
		local l = links[i]
		local parent = l and world[l.parent]
		if not parent or not world[i] then return end
		place(l.parent)
		world[i][1] = LocalToWorld(l.lpos, angle_zero, parent[1], parent[2])
	end
	for i in pairs(world) do place(i) end
	return world
end

-- The same for a ragdoll as it stands now: its bodies are moved to where the bones are drawn
function S.SnapRigid(ent)
	if not S.RigidLinks(ent) then return end
	local world = {}
	for i = 0, ent:GetPhysicsObjectCount() - 1 do
		local p = ent:GetPhysicsObjectNum(i)
		if IsValid(p) then world[i] = { p:GetPos(), p:GetAngles() } end
	end
	S.RigidPlaces(ent, world)
	ent.SPeditor_Placed = true
	for i, w in pairs(world) do
		local p = ent:GetPhysicsObjectNum(i)
		if i > 0 and SPeditor.ValidVec(w[1]) then
			p:SetPos(w[1])
			p:Wake()
		end
	end
end

function S.GetTransform(ent)
	if S.IsRagdoll(ent) then
		local root = ent:GetPhysicsObjectNum(0)
		if IsValid(root) then return root:GetPos(), root:GetAngles() end
	end
	return ent:GetPos(), ent:GetAngles()
end

function S.SetTransform(ent, pos, ang)
	if S.IsRagdoll(ent) then
		local root = ent:GetPhysicsObjectNum(0)
		if not IsValid(root) then return end
		local rp, ra = root:GetPos(), root:GetAngles()
		ent.SPeditor_Placed = true
		for i = 0, ent:GetPhysicsObjectCount() - 1 do
			local p = ent:GetPhysicsObjectNum(i)
			if IsValid(p) then
				local lp, la = WorldToLocal(p:GetPos(), p:GetAngles(), rp, ra)
				local np, na = LocalToWorld(lp, la, pos, ang)
				p:EnableMotion(false)
				p:SetPos(np)
				p:SetAngles(na)
				p:Wake()
			end
		end
	else
		ent:SetPos(pos)
		ent:SetAngles(ang)
	end
end

-- A posed ragdoll is put to sleep two ticks after its bodies were last placed.
-- The bodies are frozen, but the joints between them are not: while a body is awake, the
-- engine waits 15 ticks and then shifts whole limbs to close the gaps in the joints (a pose
-- taken from an animation never fits the ragdoll's joints exactly; measured in game: an arm
-- moved by 4 units). The client never sees that shift — it draws the bones where they were
-- placed — but everything the server computes from the bodies does: a weapon attached to a
-- hand slid away from it a quarter of a second after every edit, and in an animation it sat
-- in one place during playback and in another in a paused frame. Two ticks awake are enough
-- for the new pose to reach the client.
SPeditor.Hook("Think", "SPeditor.RagdollRest", function()
	for _, list in pairs(S.Owned) do
		for _, ent in ipairs(list) do
			if IsValid(ent) and ent:GetClass() == "prop_ragdoll" then
				local awake, frozen = false, true
				local count = ent:GetPhysicsObjectCount()
				for i = 0, count - 1 do
					local p = ent:GetPhysicsObjectNum(i)
					if IsValid(p) then
						if not p:IsAsleep() then awake = true end
						if p:IsMotionEnabled() then frozen = false end
					end
				end
				if awake and frozen then
					ent.SPeditor_Awake = (ent.SPeditor_Awake or 0) + 1
					if ent.SPeditor_Awake >= 2 then
						ent.SPeditor_Awake = 0
						for i = 0, count - 1 do
							local p = ent:GetPhysicsObjectNum(i)
							if IsValid(p) then p:Sleep() end
						end
					end
				else
					ent.SPeditor_Awake = 0
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- Attaching an object to another object or to a ragdoll bone (a weapon in a hand,
-- a hat on a head). The engine's SetParent is not used: a ragdoll on the server
-- has no bones as such, only physics objects. So every tick the server itself
-- moves the attached object after its "parent frame" — the bone's physics object
-- (or the object root), keeping the offset it had at the moment of attaching.
---------------------------------------------------------------------
S.Attached = S.Attached or {}   -- [ent] = true

-- Where the client draws body i of a ragdoll (b0.2.5): its turn as the body has it, its place
-- down the skeleton from the pelvis with the model's bone lengths (S.RigidLinks). A body that
-- was posed off those lengths (a hand dragged by IK, a pose of another model) is drawn up to
-- several units away from where it is, and a knife attached to the body of the hand crept out
-- of the drawn hand whenever the arm moved.
local function drawnBody(ent, i, depth)
	local p = ent:GetPhysicsObjectNum(i)
	if not IsValid(p) then return nil end
	local links = i > 0 and (depth or 0) < 32 and S.RigidLinks(ent)
	local l = links and links[i]
	if l then
		local pp, pa = drawnBody(ent, l.parent, (depth or 0) + 1)
		if pp then return (LocalToWorld(l.lpos, angle_zero, pp, pa)), p:GetAngles() end
	end
	return p:GetPos(), p:GetAngles()
end

-- parent frame: the position and angle the offset is stored relative to
local function attachFrame(a)
	local parent = a.parent
	if not IsValid(parent) then return nil end
	if a.phys >= 0 and S.IsRagdoll(parent) then
		local fp, fa = drawnBody(parent, a.phys)
		if fp then return fp, fa end
	end
	return S.GetTransform(parent)
end

-- recompute the offset from the object's current position (after a manual edit)
function S.RefreshAttach(ent)
	local a = ent.SPeditor_Attach
	if not a then return end
	local fp, fa = attachFrame(a)
	if not fp then return end
	local pos, ang = S.GetTransform(ent)
	a.lpos, a.lang = WorldToLocal(pos, ang, fp, fa)
	-- a point constraint keeps the offset in the world (the object does not swing round with the parent)
	a.woff = pos - fp
	a.fp, a.fa = fp, fa
	S.SendAttachOffset(ent)
end

-- The offset goes to the client too (b0.2.5): it draws the object at the parent's bone as the
-- bone is drawn in that very frame (SPeditor.LivePos), so the object neither trails a moving
-- hand nor shakes against it.
function S.SendAttachOffset(ent)
	local a = ent.SPeditor_Attach
	if not a or not a.lpos then return end
	ent:SetNW2Vector("SPeditor_AttP", a.lpos)
	ent:SetNW2Angle("SPeditor_AttA", a.lang)
	ent:SetNW2Bool("SPeditor_AttRel", a.phys >= 0 and not a.mode and not a.wear)
end

function S.Detach(ent)
	if not IsValid(ent) then return end
	ent.SPeditor_Attach = nil
	S.Attached[ent] = nil
	ent:SetNW2Entity("SPeditor_Parent", NULL)
	ent:SetNW2Int("SPeditor_ParentBone", -1)
	ent:SetNW2Bool("SPeditor_Merge", false)
	ent:SetNW2String("SPeditor_AttachMode", "")
	ent:SetNW2Bool("SPeditor_AttRel", false)
end

-- bone: bone index of the parent, -1 (the object root) or S.WEAR (-2): "wear" — clothing,
-- armour, hair made for the same skeleton bends with the parent's bones (the client draws
-- it bone-merged, cl_scene.lua); on the server it follows the root like a rigid attachment.
S.WEAR = -2
-- Constraints (b0.2, after SFM's point and orient constraints): the bone code carries the kind.
-- POINT: only the place follows (the offset is kept in the world), the object's own turn stays;
-- ORIENT: only the turn follows, the place stays. Code of bone b (-1 — the whole object):
-- S.POINT - (b + 1) and S.ORIENT - (b + 1).
S.POINT, S.ORIENT = -100, -1000
function S.AttachCode(bone, mode)
	if mode == "point" then return S.POINT - (bone + 1) end
	if mode == "orient" then return S.ORIENT - (bone + 1) end
	return bone
end

function S.Attach(ent, parent, bone)
	if not IsValid(ent) or not IsValid(parent) or ent == parent then return false end
	-- an object cannot be attached to its own descendant
	local p, guard = parent, 0
	while IsValid(p) and guard < 64 do
		if p == ent then return false end
		p = p.SPeditor_Attach and p.SPeditor_Attach.parent or nil
		guard = guard + 1
	end

	bone = math.floor(SPeditor.Num(bone, -1))
	local mode
	if bone <= S.ORIENT then
		mode, bone = "orient", S.ORIENT - bone - 1
	elseif bone <= S.POINT then
		mode, bone = "point", S.POINT - bone - 1
	end
	local wear = bone == S.WEAR and not S.IsAux(ent) and not S.IsAux(parent) and parent:GetBoneCount() > 1
	local phys = -1
	if S.IsRagdoll(parent) and bone >= 0 and bone < parent:GetBoneCount() then
		phys = SPeditor.PhysOfBoneUp(parent, bone) or -1
		if phys >= 0 then bone = parent:TranslatePhysBoneToBone(phys) end   -- the actual bone of the physics object
	else
		bone = -1
	end

	ent.SPeditor_Attach = { parent = parent, phys = phys, bone = bone, wear = wear or nil, mode = mode }
	S.Attached[ent] = true
	S.RefreshAttach(ent)
	ent:SetNW2Entity("SPeditor_Parent", parent)
	ent:SetNW2String("SPeditor_AttachMode", mode or "")
	ent:SetNW2Int("SPeditor_ParentBone", bone)
	ent:SetNW2Bool("SPeditor_Merge", wear and true or false)
	return true
end

-- (b0.2.5) Attached to a bone it is far from, an object is first put into that bone (a knife
-- picked from a table into the left hand): attaching keeps the offset, so before it stayed
-- where it lay and only followed the hand from afar — "it only goes into the right hand",
-- where it had been put by hand. Near the bone (within its own size) it is left as it is.
function S.SnapToBone(ent, parent, bone)
	if not IsValid(ent) or not S.IsRagdoll(parent) or S.IsRagdoll(ent) then return false end
	if not bone or bone < 0 or bone >= parent:GetBoneCount() then return false end
	local phys = SPeditor.PhysOfBoneUp(parent, bone)
	if not phys then return false end
	local fp, fa = drawnBody(parent, phys)
	if not fp then return false end
	local center = S.IsAux(ent) and ent:GetPos() or ent:LocalToWorld(ent:OBBCenter())
	if center:Distance(fp) <= math.max(ent:BoundingRadius(), 12) then return false end
	S.SetTransform(ent, fp, fa)
	return true
end

local function attachDepth(ent)
	local d, a = 0, ent.SPeditor_Attach
	while a and IsValid(a.parent) and d < 64 do
		d = d + 1
		a = a.parent.SPeditor_Attach
	end
	return d
end

-- Also called by SAeditor right after it has set a frame of the animation, so that a weapon
-- is in the hand in the same network update as the hand itself.
function S.AttachFollow()
	if next(S.Attached) == nil then
		S.AimFollow()
		return
	end
	local list = {}
	for ent in pairs(S.Attached) do
		if IsValid(ent) and ent.SPeditor_Attach and IsValid(ent.SPeditor_Attach.parent) then
			list[#list + 1] = ent
		else
			-- the parent was removed: the object stays where it was
			if IsValid(ent) then S.Detach(ent) else S.Attached[ent] = nil end
		end
	end
	-- chains: those closer to the root go first
	table.sort(list, function(p, q) return attachDepth(p) < attachDepth(q) end)
	for _, ent in ipairs(list) do
		local a = ent.SPeditor_Attach
		local fp, fa = attachFrame(a)
		if fp and (fp ~= a.fp or fa ~= a.fa) then
			a.fp, a.fa = fp, fa
			local pos, ang = LocalToWorld(a.lpos, a.lang, fp, fa)
			-- a constraint takes only the place or only the turn; the rest is the object's own now
			if a.mode == "point" then
				local _, own = S.GetTransform(ent)
				pos, ang = fp + (a.woff or vector_origin), own
			elseif a.mode == "orient" then
				local own = S.GetTransform(ent)
				pos = own
			end
			if SPeditor.ValidVec(pos) and SPeditor.ValidAng(ang) then S.SetTransform(ent, pos, ang) end
		end
	end
	S.AimFollow()
end
SPeditor.Hook("Think", "SPeditor.AttachFollow", function() S.AttachFollow() end)

---------------------------------------------------------------------
-- Look-at (a0.7): a camera or a light keeps turning to an object — the head of a character
-- or the middle of a prop — wherever either of them moves (an animation, a drag). Its own
-- turn is then ignored; its place stays its own (keys, attachment). Like SFM's aim constraint.
---------------------------------------------------------------------
S.Aimed = S.Aimed or {}     -- [ent] = true

-- the point an object is looked at: a bone of a ragdoll (its physics body), by default the
-- head; the middle of anything else
function S.AimPoint(target, bone)
	if not IsValid(target) then return nil end
	if S.IsRagdoll(target) then
		bone = (bone and bone >= 0) and bone or target:LookupBone("ValveBiped.Bip01_Head1")
		local phys = bone and SPeditor.PhysOfBoneUp(target, bone)
		local p = phys and target:GetPhysicsObjectNum(phys)
		if IsValid(p) then return p:GetPos() end
	end
	if S.IsAux(target) then return target:GetPos() end
	return target:LocalToWorld(target:OBBCenter())
end

function S.SetAim(ent, target, bone)
	if not IsValid(ent) or not S.IsAux(ent) or S.IsEffect(ent) then return false end
	if not IsValid(target) or target == ent then
		ent.SPeditor_Aim = nil
		S.Aimed[ent] = nil
		ent:SetNW2Entity("SPeditor_AimAt", NULL)
		return true
	end
	ent.SPeditor_Aim = { target = target, bone = math.floor(SPeditor.Num(bone, -1)) }
	S.Aimed[ent] = true
	ent:SetNW2Entity("SPeditor_AimAt", target)
	S.AimFollow()
	return true
end

function S.AimFollow()
	if next(S.Aimed) == nil then return end
	for ent in pairs(S.Aimed) do
		local a = IsValid(ent) and ent.SPeditor_Aim
		if not a or not IsValid(a.target) then
			-- the target is gone: the object keeps the direction it had
			if IsValid(ent) then S.SetAim(ent, nil) else S.Aimed[ent] = nil end
		else
			local point = S.AimPoint(a.target, a.bone)
			local pos, ang = ent:GetPos(), ent:GetAngles()
			if point and point:DistToSqr(pos) > 1 then
				local want = (point - pos):Angle()
				want.r = S.IsCamera(ent) and 0 or ang.r
				if math.abs(math.AngleDifference(want.p, ang.p)) > 0.01 or math.abs(math.AngleDifference(want.y, ang.y)) > 0.01
					or math.abs(math.AngleDifference(want.r, ang.r)) > 0.01 then
					S.SetTransform(ent, pos, want)
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- Ragdoll guard. Addons that drive ragdolls by themselves (active ragdolls such as Fedhoria,
-- euphoria-like and death-animation mods, twitching) take every prop_ragdoll they see:
-- they unfreeze its bodies and push them with motors and forces, so in the editor the limbs
-- went back to where the other addon wanted them and could not be posed. While the owner's
-- editor is open, an editor ragdoll keeps its bodies frozen: a body someone unfroze is
-- frozen again at the place it had (taken while it rested). Off: gmfm_ragdoll_guard 0.
-- Whatever places the bodies itself (an edit, a pose, playback) marks the ragdoll with
-- SPeditor_Placed: that place is the new one to keep, even if the other addon has already
-- unfrozen the bodies in the same tick (otherwise every edit was undone and the limbs of
-- such a ragdoll could not be moved at all).
---------------------------------------------------------------------
local cvGuard = CreateConVar("gmfm_ragdoll_guard", "1", FCVAR_ARCHIVE,
	"SPeditor: keep the bodies of editor ragdolls frozen when other addons unfreeze them")

SPeditor.Hook("Think", "SPeditor.RagdollGuard", function()
	if not cvGuard:GetBool() then return end
	for ply, list in pairs(S.Owned) do
		if S.Active[ply] then
			for _, ent in ipairs(list) do
				-- a ragdoll whose physics is being recorded (SAeditor) moves on purpose
				if IsValid(ent) and ent:GetClass() == "prop_ragdoll" and not ent.SPeditor_PhysRec then
					local g = ent.SPeditor_Guard
					if not g then
						g = { pos = {}, ang = {} }
						ent.SPeditor_Guard = g
					end
					local fixed, placed = false, ent.SPeditor_Placed
					ent.SPeditor_Placed = nil
					for i = 0, ent:GetPhysicsObjectCount() - 1 do
						local p = ent:GetPhysicsObjectNum(i)
						if IsValid(p) then
							if placed then
								g.pos[i], g.ang[i] = p:GetPos(), p:GetAngles()
								if p:IsMotionEnabled() then
									p:EnableMotion(false)
									p:Wake()
								end
							elseif p:IsMotionEnabled() then
								p:EnableMotion(false)
								if g.pos[i] then
									p:SetPos(g.pos[i])
									p:SetAngles(g.ang[i])
								end
								p:Wake()
								fixed = true
							elseif not p:IsAsleep() or not g.pos[i] then
								-- frozen by the editor: this is the place to keep
								g.pos[i], g.ang[i] = p:GetPos(), p:GetAngles()
							end
						end
					end
					if fixed then
						g.hits = (g.hits or 0) + 1
						-- a single unfreeze may be the player's own (physgun); a steady one is an addon
						if g.hits == 10 and IsValid(ply) then S.Notice(ply, "#rag_guard|" .. (ent.SPeditor_Name or string.GetFileFromFilename(ent:GetModel() or "")), 0) end
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------
-- Models
---------------------------------------------------------------------
function S.SpawnModel(ply, model, pos, ang)
	if S.AtLimit(ply, "prop") then return nil, "#err_limit_prop" end

	model = string.lower(tostring(model or ""))
	if #model > 200 or string.find(model, "..", 1, true) or not string.EndsWith(model, ".mdl")
		or not string.StartWith(model, "models/") then
		return nil, "#err_model_path"
	end
	if not util.IsValidModel(model) then
		return nil, "#err_model_missing|" .. model
	end

	local class = "prop_dynamic"
	if util.IsValidRagdoll(model) then
		class = "prop_ragdoll"
	elseif util.IsValidProp(model) then
		class = "prop_physics"
	end

	local ent = ents.Create(class)
	if not IsValid(ent) then return nil, "#err_create" end

	ent:SetModel(model)
	ent:SetPos(pos)
	ent:SetAngles(ang)
	ent:Spawn()
	ent:Activate()

	S.Freeze(ent)
	S.StoreInit(ent)
	-- the face at rest: a TF2 mercenary (HWM) came with every slider at -1 — a crooked, pursed mouth
	SPeditor.FlexRest(ent)
	-- a model without physics is a prop_dynamic, and it plays its first animation over and
	-- over: posed by bone offsets, it would sway under them. It stands still in the editor; the
	-- animation and its moment are a choice of the base pose (look.seq, S.ApplyLook).
	if class == "prop_dynamic" then
		ent:SetPlaybackRate(0)
		ent:SetCycle(0)
		ent:SetNW2Float("SPeditor_Cycle", 0)   -- it animates on the client (cl_scene.lua)
	end
	S.Track(ply, ent)
	return ent
end

-- Spawn with a full state. The order matters for ragdolls: spawn without rotation,
-- then the appearance and the local pose, and only then a rigid move of the whole
-- ragdoll to the needed root transform (otherwise the model's root orientation
-- is applied twice and the copy ends up rotated).
function S.SpawnWithState(ply, model, pos, ang, skin, groups, pose, scale, look)
	local ent, err = S.SpawnModel(ply, model, pos, angle_zero)
	if not ent then return nil, err end
	if scale then S.SetScale(ent, scale) end
	if look then S.ApplyLook(ent, look) end
	S.ApplyAppearance(ent, skin, groups)
	S.ApplyPose(ent, pose)
	S.SetTransform(ent, pos, ang)
	return ent
end

-- Uniform scale. Ragdolls are not scaled (they have a physical pose),
-- neither are lights and cameras.
function S.CanScale(ent)
	return IsValid(ent) and not S.IsAux(ent) and not S.IsRagdoll(ent)
end

function S.SetScale(ent, scale)
	if not S.CanScale(ent) then return end
	scale = SPeditor.Clamp(scale, 0.05, 10, 1)
	ent:SetModelScale(scale, 0)
	ent.SPeditor_Scale = (math.abs(scale - 1) > 0.001) and scale or nil
end

---------------------------------------------------------------------
-- Extended model properties: colour, material (whole and per slot), stretching
-- along axes, disabling the shadow. look — a table of plain numbers and strings (fit for
-- JSON), nil fields mean "default":
-- { color = { r, g, b, a }, material = "path", submats = { ["0"] = "path" },
--     stretch = { x, y, z }, noshadow = true }
-- Stretching is not a physical size: the client draws the model with a scale matrix
-- (cl_scene.lua), so only props have it, like regular scale.
---------------------------------------------------------------------
local MAX_SUBMATS = 256       -- material slots of a model (studio models have up to 256 materials)
local ENGINE_SUBMATS = 32     -- the engine's SetSubMaterial takes only slots 0..31; the client draws the rest

-- the materials of the Material tool, lower case (the list has "Models/effects/..." while paths
-- are compared lower case: on a server with players such materials were refused)
local overrideSet, overrideN
local function isOverrideMaterial(path)
	local list = list.Get("OverrideMaterials") or {}
	if overrideN ~= #list then
		overrideSet, overrideN = {}, #list
		for _, m in ipairs(list) do
			if isstring(m) then overrideSet[string.lower(m)] = true end
		end
	end
	return overrideSet[path] == true
end

-- On a server with players only materials from the list of the Material tool
-- are allowed (as for the tool itself), plus the white "no textures" material.
local function cleanMaterial(path)
	if type(path) ~= "string" then return "" end
	path = string.lower(string.Trim((string.gsub(path, "\\", "/"))))
	path = string.gsub(path, "%.vmt$", "")
	if path == "" or #path > 160 or string.find(path, "..", 1, true) or string.find(path, "[^%w_%-/%.]") then return "" end
	if not game.SinglePlayer() and path ~= SPeditor.WhiteMaterial and not isOverrideMaterial(path) then return "" end
	return path
end

function S.ApplyLook(ent, d)
	if not IsValid(ent) or S.IsAux(ent) then return end
	ent.SA_LookSig = nil   -- the materials a key applied last (sv_saeditor.lua) are no longer there
	d = type(d) == "table" and d or {}
	local look = {}

	local c = type(d.color) == "table" and d.color or {}
	local col = Color(
		math.Round(SPeditor.Clamp(c[1], 0, 255, 255)), math.Round(SPeditor.Clamp(c[2], 0, 255, 255)),
		math.Round(SPeditor.Clamp(c[3], 0, 255, 255)), math.Round(SPeditor.Clamp(c[4], 0, 255, 255)))
	ent:SetColor(col)
	ent:SetRenderMode(col.a < 255 and RENDERMODE_TRANSCOLOR or RENDERMODE_NORMAL)
	if col.r < 255 or col.g < 255 or col.b < 255 or col.a < 255 then look.color = { col.r, col.g, col.b, col.a } end

	local mat = cleanMaterial(d.material)
	ent:SetMaterial(mat)
	if mat ~= "" then look.material = mat end

	-- slots past the engine's 32 go to the client as "slot:path;…" and are drawn there
	-- (cl_scene.lua): a model with many materials (SFM ports) could not change them before
	-- slot by slot and guarded (b0.1): addons that wrap SetSubMaterial (Advanced Colour Tool)
	-- failed on the call without arguments, and the whole look of the object was lost
	local function sub(i, m)
		local ok, err = pcall(ent.SetSubMaterial, ent, i, m)
		if not ok then SPeditor.LogError("SetSubMaterial: " .. tostring(err)) end
	end
	for i = 0, math.min(#(ent:GetMaterials() or {}), ENGINE_SUBMATS) - 1 do
		if ent:GetSubMaterial(i) ~= "" then sub(i, "") end
	end
	local extra = {}
	if type(d.submats) == "table" then
		for k, v in pairs(d.submats) do
			local idx = math.floor(SPeditor.Num(k, -1))
			local m = cleanMaterial(v)
			if idx >= 0 and idx < MAX_SUBMATS and m ~= "" then
				if idx < ENGINE_SUBMATS then
					sub(idx, m)
				else
					extra[#extra + 1] = idx .. ":" .. m
				end
				look.submats = look.submats or {}
				look.submats[tostring(idx)] = m
			end
		end
	end
	ent:SetNW2String("SPeditor_SubMats", table.concat(extra, ";"))

	-- a colour per material slot (a0.8, as SFM's material colour): the client draws the slot
	-- with a tinted copy of its material (cl_scene.lua). The client reads "slot:r,g,b;…".
	local tints = {}
	if type(d.tints) == "table" then
		for k, v in pairs(d.tints) do
			local idx = math.floor(SPeditor.Num(k, -1))
			if idx >= 0 and idx < MAX_SUBMATS and type(v) == "table" then
				local r, g, b = math.Round(SPeditor.Clamp(v[1], 0, 255, 255)), math.Round(SPeditor.Clamp(v[2], 0, 255, 255)),
					math.Round(SPeditor.Clamp(v[3], 0, 255, 255))
				if r < 255 or g < 255 or b < 255 then
					look.tints = look.tints or {}
					look.tints[tostring(idx)] = { r, g, b }
					tints[#tints + 1] = string.format("%d:%d,%d,%d", idx, r, g, b)
				end
			end
		end
	end
	ent:SetNW2String("SPeditor_Tints", table.concat(tints, ";"))

	-- the Face Poser's flex scale (b0.2.3): every face slider goes this many times further
	local fs = (ent:GetFlexNum() or 0) > 0 and SPeditor.Clamp(d.flexscale, 0.1, 10, 1) or 1
	if math.abs(fs - 1) < 0.001 then fs = 1 end
	if ent:GetFlexScale() ~= fs then ent:SetFlexScale(fs) end
	ent:SetNW2Float("SPeditor_FlexScale", fs)
	if fs ~= 1 then look.flexscale = fs end

	local noshadow = d.noshadow and true or false
	ent:DrawShadow(not noshadow)
	ent:SetNW2Bool("SPeditor_NoShadow", noshadow)
	if noshadow then look.noshadow = true end

	local st = S.CanScale(ent) and SPeditor.TableToVec(d.stretch) or nil
	if st then
		st = Vector(SPeditor.Clamp(st.x, 0.05, 10, 1), SPeditor.Clamp(st.y, 0.05, 10, 1), SPeditor.Clamp(st.z, 0.05, 10, 1))
		if st:DistToSqr(ONE) < 1e-6 then st = nil end
	end
	ent:SetNW2Vector("SPeditor_Stretch", st or ONE)
	if st then look.stretch = SPeditor.VecToTable(st) end

	-- bone locks of a ragdoll (cl_gizmo.lua): { ["bone"] = bone it follows }, both physical.
	-- The client reads them from one string "bone:target;…".
	local locks, parts = {}, {}
	if S.IsRagdoll(ent) and type(d.locks) == "table" then
		local function phys(b)
			return SPeditor.PhysOfBone(ent, b) ~= nil
		end
		for k, v in pairs(d.locks) do
			local b, t = math.floor(SPeditor.Num(k, -1)), math.floor(SPeditor.Num(v, -1))
			if b >= 0 and t >= 0 and b ~= t and #parts < 64 and phys(b) and phys(t) then
				locks[tostring(b)] = t
				parts[#parts + 1] = b .. ":" .. t
			end
		end
	end
	ent:SetNW2String("SPeditor_Locks", table.concat(parts, ";"))
	if #parts > 0 then look.locks = locks end

	-- hidden bones (b0.2.5, as SFM hides controls): not drawn in the skeleton and not picked
	-- by a click, so the bones of one character do not get in the way of another's
	local hidden = {}
	if type(d.hidebones) == "table" then
		local nb = ent:GetBoneCount()
		for _, v in ipairs(d.hidebones) do
			local b = math.floor(SPeditor.Num(v, -1))
			if b >= 0 and b < nb and #hidden < 256 then hidden[#hidden + 1] = b end
		end
	end
	ent:SetNW2String("SPeditor_HideBones", table.concat(hidden, ","))
	if #hidden > 0 then look.hidebones = hidden end

	-- the base pose of a model without physics: an animation of the model held at one moment
	if ent:GetClass() == "prop_dynamic" and type(d.seq) == "string" and #d.seq < 128 then
		local id = ent:LookupSequence(d.seq)
		if id and id >= 0 then
			local cyc = SPeditor.Clamp(d.cycle, 0, 1, 0)
			if ent:GetSequence() ~= id then ent:ResetSequence(id) end
			ent:SetPlaybackRate(0)
			ent:SetCycle(cyc)
			ent:SetNW2Float("SPeditor_Cycle", cyc)
			look.seq, look.cycle = d.seq, cyc
		end
	end

	ent.SPeditor_Look = next(look) ~= nil and look or nil
end

function S.CaptureLook(ent)
	return ent.SPeditor_Look and table.Copy(ent.SPeditor_Look) or nil
end

---------------------------------------------------------------------
-- Lights
---------------------------------------------------------------------
function S.ApplyLight(ent, d)
	local c = type(d.col) == "table" and d.col or { 255, 244, 224 }
	ent:SetLightType(math.floor(SPeditor.Clamp(d.ltype, 0, 1, 1)))
	ent:SetLightColor(Vector(
			SPeditor.Clamp(c[1], 0, 255, 255) / 255,
			SPeditor.Clamp(c[2], 0, 255, 244) / 255,
			SPeditor.Clamp(c[3], 0, 255, 224) / 255))
	ent:SetLightRadius(SPeditor.Clamp(d.radius, 32, 4000, 400))
	ent:SetLightBrightness(SPeditor.Clamp(d.brightness, 0, 8, 2))
	ent:SetLightFOV(SPeditor.Clamp(d.fov, 5, 120, 60))
	if d.enabled ~= nil then ent:SetLightEnabled(d.enabled and true or false) end
	if d.shadows ~= nil then ent:SetLightShadows(d.shadows and true or false) end
	if d.ortho ~= nil then ent:SetLightOrtho(d.ortho and true or false) end
	-- light mask: a texture path (no special characters)
	if isstring(d.tex) and d.tex ~= "" and #d.tex <= 96 and not string.find(d.tex, "[^%w_%-/%.]") then
		ent:SetLightTexture(d.tex)
	end
	for _, f in ipairs(SPeditor.LightFields) do
		if d[f.key] ~= nil then ent["Set" .. f.nw](ent, SPeditor.Clamp(d[f.key], f.min, f.max, f.default)) end
	end
end

function S.SpawnLight(ply, d)
	if S.AtLimit(ply, "light") then return nil, "#err_limit_light" end
	local ent = ents.Create("speditor_light")
	if not IsValid(ent) then return nil, "#err_create" end
	ent:SetPos(d.pos)
	ent:SetAngles(d.ang)
	ent:Spawn()
	S.ApplyLight(ent, d)
	S.Track(ply, ent)
	return ent
end

function S.LightData(ent, pos)
	local c = ent:GetLightColor()
	local d = {
		ltype      = ent:GetLightType(),
		pos        = pos or ent:GetPos(),
		ang        = ent:GetAngles(),
		col        = { math.Round(c.x * 255), math.Round(c.y * 255), math.Round(c.z * 255) },
		radius     = ent:GetLightRadius(),
		brightness = ent:GetLightBrightness(),
		fov        = ent:GetLightFOV(),
		enabled    = ent:GetLightEnabled(),
		shadows    = ent:GetLightShadows(),
		ortho      = ent:GetLightOrtho(),
		tex        = ent:GetLightTexture(),
	}
	for _, f in ipairs(SPeditor.LightFields) do d[f.key] = ent["Get" .. f.nw](ent) end
	return d
end

---------------------------------------------------------------------
-- Scene cameras
---------------------------------------------------------------------
-- Camera effects (cl_postfx.lua): { [effect] = { [parameter] = number | bool | string } }.
-- The server only stores and hands them out: the JSON is cut into chunks for NW2String
-- (a single string has a small length limit).
local FX_CHUNK, FX_CHUNKS = 180, 32

local function cleanFX(fx)
	if type(fx) ~= "table" then return nil end
	local out, n = {}, 0
	for id, params in pairs(fx) do
		if type(id) == "string" and #id <= 24 and type(params) == "table" and n < 24 then
			local p, m = {}, 0
			for k, v in pairs(params) do
				if type(k) == "string" and #k <= 24 and m < 16 then
					if isnumber(v) then
						p[k] = math.Round(SPeditor.Clamp(v, -100000, 100000, 0), 4)
						m = m + 1
					elseif isbool(v) then
						p[k] = v
						m = m + 1
					elseif isstring(v) and #v <= 120 and not string.find(v, "[^%w_%-/%. ]") then
						p[k] = v
						m = m + 1
					end
				end
			end
			out[id] = p
			n = n + 1
		end
	end
	return next(out) ~= nil and out or nil
end

function S.SetCameraFX(ent, fx)
	fx = cleanFX(fx)
	local json = fx and util.TableToJSON(fx) or ""
	if #json > FX_CHUNK * FX_CHUNKS then return false end
	ent.SPeditor_FX = fx
	local n = math.ceil(#json / FX_CHUNK)
	for i = 1, n do
		ent:SetNW2String("SPeditor_FX" .. i, string.sub(json, (i - 1) * FX_CHUNK + 1, i * FX_CHUNK))
	end
	ent:SetNW2Int("SPeditor_FXN", n)
	return true
end

function S.ApplyCamera(ent, d)
	ent:SetCameraFOV(SPeditor.Clamp(d.fov, 10, 120, 75))
	for _, f in ipairs(SPeditor.CameraFields) do
		-- (a camera made before a field existed has no setter for it until the map is loaded again)
		if d[f.key] ~= nil and ent["Set" .. f.nw] then ent["Set" .. f.nw](ent, SPeditor.Clamp(d[f.key], f.min, f.max, f.default)) end
	end
	if d.fx ~= nil then S.SetCameraFX(ent, d.fx) end
	-- a camera without a model (a0.9): the view of a recorded character sits in its head, where
	-- the camera's model only got in the way of the editor's views
	if d.nomodel ~= nil then ent:SetNW2Bool("SPeditor_NoModel", d.nomodel and true or false) end
end

function S.SpawnCamera(ply, d)
	if S.AtLimit(ply, "camera") then return nil, "#err_limit_camera" end
	local ent = ents.Create("speditor_camera")
	if not IsValid(ent) then return nil, "#err_create" end
	ent:SetPos(d.pos)
	ent:SetAngles(d.ang)
	ent:Spawn()
	S.ApplyCamera(ent, d)
	S.Track(ply, ent)
	return ent
end

function S.CameraData(ent, pos)
	local d = {
		pos      = pos or ent:GetPos(),
		ang      = ent:GetAngles(),
		fov      = ent:GetCameraFOV(),
		fx       = ent.SPeditor_FX and table.Copy(ent.SPeditor_FX) or nil,
	}
	for _, f in ipairs(SPeditor.CameraFields) do
		if ent["Get" .. f.nw] then d[f.key] = ent["Get" .. f.nw](ent) end
	end
	if ent:GetNW2Bool("SPeditor_NoModel", false) then d.nomodel = true end
	return d
end

---------------------------------------------------------------------
-- Effects (the speditor_effect entity). d = { src, name, file, time, scale, length };
-- the fields d lacks keep their values.
---------------------------------------------------------------------
function S.ApplyEffect(ent, d)
	if d.name ~= nil then
		local fx = SPeditor.CleanEffect(d)
		if fx then
			ent:SetFxSource(fx.src)
			ent:SetFxName(fx.name)
			ent:SetFxFile(fx.file)
		end
	end
	for _, f in ipairs(SPeditor.EffectFields) do
		if d[f.key] ~= nil then ent["Set" .. f.nw](ent, SPeditor.Clamp(d[f.key], f.min, f.max, f.default)) end
	end
	-- fired from an attachment of another object (a0.9: the muzzle and the shell port of a
	-- weapon in a take): the UID of that object and the name of the attachment
	if d.att ~= nil then
		local att = isstring(d.att) and string.sub(d.att, 1, 32) or ""
		if string.find(att, "[^%w_%.%-]") then att = "" end
		ent:SetNW2String("SPeditor_FxAtt", att)
		ent:SetNW2Int("SPeditor_FxOn", att ~= "" and math.floor(SPeditor.Num(d.on, 0)) or 0)
	end
end

function S.SpawnEffect(ply, d)
	if S.AtLimit(ply, "effect") then return nil, "#err_limit_effect" end
	if not SPeditor.CleanEffect(d) then return nil, "#err_effect_name" end
	local ent = ents.Create("speditor_effect")
	if not IsValid(ent) then return nil, "#err_create" end
	ent:SetPos(d.pos)
	ent:SetAngles(d.ang)
	ent:Spawn()
	S.ApplyEffect(ent, d)
	S.Track(ply, ent)
	return ent
end

function S.EffectData(ent, pos)
	local d = { pos = pos or ent:GetPos(), ang = ent:GetAngles(), src = ent:GetFxSource(), name = ent:GetFxName(), file = ent:GetFxFile() }
	for _, f in ipairs(SPeditor.EffectFields) do d[f.key] = ent["Get" .. f.nw](ent) end
	local att = ent:GetNW2String("SPeditor_FxAtt", "")
	if att ~= "" then d.att, d.on = att, ent:GetNW2Int("SPeditor_FxOn", 0) end
	return d
end

---------------------------------------------------------------------
-- Appearance: skin and bodygroups
---------------------------------------------------------------------
function S.SetSkinSafe(ent, skin)
	skin = math.floor(SPeditor.Num(skin, 0))
	ent:SetSkin(math.Clamp(skin, 0, math.max(ent:SkinCount() - 1, 0)))
end

function S.SetBodygroupSafe(ent, id, val)
	id  = math.floor(SPeditor.Num(id, -1))
	val = math.floor(SPeditor.Num(val, 0))
	if id < 0 or id >= ent:GetNumBodyGroups() then return end
	ent:SetBodygroup(id, math.Clamp(val, 0, math.max(ent:GetBodygroupCount(id) - 1, 0)))
end

function S.CaptureAppearance(ent)
	local groups = {}
	for i = 0, ent:GetNumBodyGroups() - 1 do
		groups[tostring(i)] = ent:GetBodygroup(i)
	end
	return ent:GetSkin(), groups
end

function S.ApplyAppearance(ent, skin, groups)
	if skin ~= nil then S.SetSkinSafe(ent, skin) end
	if type(groups) == "table" then
		for k, v in pairs(groups) do
			S.SetBodygroupSafe(ent, tonumber(k), v)
		end
	end
end

---------------------------------------------------------------------
-- Bones, flexes, eyes
---------------------------------------------------------------------
function S.SetBoneManip(ent, bone, pos, ang, scale)
	bone = math.floor(SPeditor.Num(bone, -1))
	if bone < 0 or bone >= ent:GetBoneCount() then return end
	pos = Vector(
		SPeditor.Clamp(pos.x, -500, 500, 0),
		SPeditor.Clamp(pos.y, -500, 500, 0),
		SPeditor.Clamp(pos.z, -500, 500, 0))
	ang = Angle(SPeditor.Num(ang.p, 0), SPeditor.Num(ang.y, 0), SPeditor.Num(ang.r, 0))
	scale = Vector(
		SPeditor.Clamp(scale.x, 0.01, 20, 1),
		SPeditor.Clamp(scale.y, 0.01, 20, 1),
		SPeditor.Clamp(scale.z, 0.01, 20, 1))
	ent:ManipulateBonePosition(bone, pos)
	ent:ManipulateBoneAngles(bone, ang)
	ent:ManipulateBoneScale(bone, scale)
end

function S.SetFlex(ent, id, w)
	id = math.floor(SPeditor.Num(id, -1))
	if id < 0 or id >= ent:GetFlexNum() then return end
	-- (b0.2.5) up to ten ranges past the model's own ends: the game draws such faces (a jaw
	-- at 3 opens three times as wide), the sliders go there with their limits unlocked
	local mn, mx = ent:GetFlexBounds(id)
	mn, mx = mn or -1, mx or 1
	local r = math.max(mx - mn, 1)
	SPeditor.FlexSet(ent, id, SPeditor.Clamp(w, mn - r * 10, mx + r * 10, 0))
end

-- For ragdolls v is local to the "eyes" attachment (see the wiki on SetEyeTarget)
function S.SetEye(ent, v)
	if v and SPeditor.ValidVec(v) then
		if v:LengthSqr() < 0.0001 then v = Vector(1, 0, 0) end   -- (0,0,0) switches the override off
		if v:Length() > 2000 then v = v:GetNormalized() * 2000 end
		ent:SetEyeTarget(v)
		ent.SPeditor_Eye = v
	else
		ent:SetEyeTarget(vector_origin)
		ent.SPeditor_Eye = nil
	end
end

local function resetBones(ent)
	for b = 0, ent:GetBoneCount() - 1 do
		ent:ManipulateBonePosition(b, vector_origin)
		ent:ManipulateBoneAngles(b, angle_zero)
		ent:ManipulateBoneScale(b, ONE)
	end
end

local function resetFlex(ent)
	SPeditor.FlexRest(ent)
	S.SetEye(ent, nil)
end

local function resetPhys(ent)
	local init = ent.SPeditor_Init
	local root = ent:GetPhysicsObjectNum(0)
	if not init or not IsValid(root) then return end
	ent.SPeditor_Placed = true
	local rp, ra = root:GetPos(), root:GetAngles()
	for i, st in pairs(init) do
		local p = ent:GetPhysicsObjectNum(i)
		if IsValid(p) then
			local np, na = LocalToWorld(st.pos, st.ang, rp, ra)
			p:EnableMotion(false)
			p:SetPos(np)
			p:SetAngles(na)
			p:Wake()
		end
	end
end

-- kind: 0 = one bone, 1 = all bones, 2 = flexes and eyes, 3 = full reset
function S.Reset(ent, kind, bone)
	if kind == 0 then
		if bone >= 0 and bone < ent:GetBoneCount() then
			ent:ManipulateBonePosition(bone, vector_origin)
			ent:ManipulateBoneAngles(bone, angle_zero)
			ent:ManipulateBoneScale(bone, ONE)
		end
	elseif kind == 1 then
		resetBones(ent)
	elseif kind == 2 then
		resetFlex(ent)
	elseif kind == 3 then
		resetBones(ent)
		resetFlex(ent)
		resetPhys(ent)
	end
end

---------------------------------------------------------------------
-- Pose: capture and apply (plain numbers, fit for JSON)
---------------------------------------------------------------------
-- The bone a physics object belongs to, and the nearest ancestor physics object
local function physBoneName(ent, idx)
	local bone = ent:TranslatePhysBoneToBone(idx)
	return bone and bone >= 0 and ent:GetBoneName(bone) or nil
end

local function physParent(ent, idx)
	local bone = ent:TranslatePhysBoneToBone(idx)
	local b, guard = bone and ent:GetBoneParent(bone) or -1, 0
	while b and b >= 0 and guard < 256 do
		local pi = SPeditor.PhysOfBone(ent, b)
		if pi and pi ~= idx then return pi end
		b = ent:GetBoneParent(b)
		guard = guard + 1
	end
	return nil
end

-- Besides numbers a pose stores the NAMES of bones and flexes (names): with them a pose
-- can be applied to another model with the same skeleton where the numbers differ.
function S.CapturePose(ent)
	local pose = { phys = {}, bones = {}, flex = {}, model = ent:GetModel(), names = { phys = {}, bones = {}, flex = {} } }

	if S.IsRagdoll(ent) then
		local root = ent:GetPhysicsObjectNum(0)
		if IsValid(root) then
			local rp, ra = root:GetPos(), root:GetAngles()
			for i = 0, ent:GetPhysicsObjectCount() - 1 do
				local p = ent:GetPhysicsObjectNum(i)
				if IsValid(p) then
					local lp, la = WorldToLocal(p:GetPos(), p:GetAngles(), rp, ra)
					pose.phys[tostring(i)] = { p = SPeditor.VecToTable(lp), a = SPeditor.AngToTable(la) }
					pose.names.phys[tostring(i)] = physBoneName(ent, i)
				end
			end
		end
	end

	for b = 0, ent:GetBoneCount() - 1 do
		local mp = ent:GetManipulateBonePosition(b)
		local ma = ent:GetManipulateBoneAngles(b)
		local ms = ent:GetManipulateBoneScale(b)
		if mp ~= vector_origin or ma ~= angle_zero or ms ~= ONE then
			pose.bones[tostring(b)] = {
				p = SPeditor.VecToTable(mp), a = SPeditor.AngToTable(ma), s = SPeditor.VecToTable(ms),
			}
			pose.names.bones[tostring(b)] = ent:GetBoneName(b)
		end
	end

	for i = 0, ent:GetFlexNum() - 1 do
		local w = SPeditor.FlexGet(ent, i)
		if math.abs(w) > 0.001 then
			pose.flex[tostring(i)] = math.Round(w, 4)
			pose.names.flex[tostring(i)] = ent:GetFlexName(i)
		end
	end

	if ent.SPeditor_Eye then pose.eye = SPeditor.VecToTable(ent.SPeditor_Eye) end
	return pose
end

-- A pose from another model: bone numbers are translated by name, and the positions
-- of physics objects are recomputed from the proportions of THIS model (only the angles
-- are taken from the pose). Otherwise a model with other arm and leg lengths would have its joints "come apart".
local function applyForeignPhys(ent, pose)
	local root = ent:GetPhysicsObjectNum(0)
	local init = ent.SPeditor_Init
	if not IsValid(root) or not init then return end
	ent.SPeditor_Placed = true
	local rp, ra = root:GetPos(), root:GetAngles()
	local names = pose.names.phys

	-- the angle from the pose for each physics object of this model (if found by name)
	local wantAng = {}
	for k, d in pairs(pose.phys) do
		local bone = names[k] and ent:LookupBone(names[k])
		local idx = bone and SPeditor.PhysOfBone(ent, bone)
		if idx and type(d) == "table" then
			local la = SPeditor.TableToAng(d.a)
			if la then
				local _, wa = LocalToWorld(vector_origin, la, rp, ra)
				wantAng[idx] = wa
			end
		end
	end

	-- walk from the root: position = ancestor position + the original offset, rotated together with the ancestor
	local done = { [0] = { pos = rp, ang = ra } }
	local function solve(idx, guard)
		if done[idx] then return done[idx] end
		local st = init[idx]
		local par = physParent(ent, idx)
		local pst = par and init[par]
		if not st or not pst or guard > 64 then return nil end
		local pw = solve(par, guard + 1)
		if not pw then return nil end
		-- the original position of idx in the ancestor's space
		local lp, la = WorldToLocal(st.pos, st.ang, pst.pos, pst.ang)
		local pos, restAng = LocalToWorld(lp, la, pw.pos, pw.ang)
		done[idx] = { pos = pos, ang = wantAng[idx] or restAng }
		return done[idx]
	end

	for i = 1, ent:GetPhysicsObjectCount() - 1 do
		local w = solve(i, 0)
		local p = ent:GetPhysicsObjectNum(i)
		if w and IsValid(p) and SPeditor.ValidVec(w.pos) and SPeditor.ValidAng(w.ang) then
			p:EnableMotion(false)
			p:SetPos(w.pos)
			p:SetAngles(w.ang)
			p:Wake()
		end
	end
end

function S.ApplyPose(ent, pose)
	if type(pose) ~= "table" then return end
	local names = type(pose.names) == "table" and pose.names or nil
	local foreign = names ~= nil and type(pose.model) == "string" and pose.model ~= ent:GetModel()

	-- number from the pose -> number in this model (by name if the pose is from another model)
	local function mapBone(k)
		if not foreign then return tonumber(k) end
		local n = type(names.bones) == "table" and names.bones[k]
		return n and ent:LookupBone(n) or nil
	end
	local function mapFlex(k)
		if not foreign then return tonumber(k) end
		local n = type(names.flex) == "table" and names.flex[k]
		return n and ent:GetFlexIDByName(n) or nil
	end

	if S.IsRagdoll(ent) and type(pose.phys) == "table" then
		if foreign and type(names.phys) == "table" then
			applyForeignPhys(ent, pose)
		else
			local root = ent:GetPhysicsObjectNum(0)
			if IsValid(root) then
				ent.SPeditor_Placed = true
				local rp, ra = root:GetPos(), root:GetAngles()
				for k, d in pairs(pose.phys) do
					local idx = tonumber(k)
					if idx then idx = math.floor(idx) end
					local p = (idx and idx >= 0 and idx < ent:GetPhysicsObjectCount()) and ent:GetPhysicsObjectNum(idx) or nil
					if IsValid(p) and type(d) == "table" then
						local lp, la = SPeditor.TableToVec(d.p), SPeditor.TableToAng(d.a)
						if lp and la then
							local np, na = LocalToWorld(lp, la, rp, ra)
							if SPeditor.ValidVec(np) and SPeditor.ValidAng(na) then
								p:EnableMotion(false)
								p:SetPos(np)
								p:SetAngles(na)
								p:Wake()
							end
						end
					end
				end
			end
		end
	end

	if type(pose.bones) == "table" then
		resetBones(ent)
		for k, d in pairs(pose.bones) do
			local id = mapBone(k)
			if id and type(d) == "table" then
				S.SetBoneManip(ent, id,
					SPeditor.TableToVec(d.p) or vector_origin,
					SPeditor.TableToAng(d.a) or angle_zero,
					SPeditor.TableToVec(d.s) or ONE)
			end
		end
	end

	if type(pose.flex) == "table" then
		SPeditor.FlexRest(ent)
		for k, w in pairs(pose.flex) do
			local id = mapFlex(k)
			if id then S.SetFlex(ent, id, w) end
		end
	end

	S.SetEye(ent, SPeditor.TableToVec(pose.eye))
end

---------------------------------------------------------------------
-- Message receivers
---------------------------------------------------------------------
net.Receive(Net.Toggle, function(_, ply)
	if not SPeditor.CanUse(ply) then
		S.Notice(ply, "#no_permission", 1)
		return
	end
	S.SetActive(ply, net.ReadBool())
end)

S.Receive("Spawn", function(ply)
	local model = net.ReadString()
	local pos   = SPeditor.ReadVecF()
	local ang   = SPeditor.ReadAngF()
	if not SPeditor.ValidVec(pos) or not SPeditor.ValidAng(ang) then return end
	local ent, err = S.SpawnModel(ply, model, pos, ang)
	if not ent then
		S.Notice(ply, err or "#err_create", 1)
		return
	end
	S.SendSpawned(ply, ent)
end)

S.Receive("Delete", function(ply)
	local ent = S.ReadOwned(ply)
	if ent then S.RemoveWithRecord(ply, ent) end
end)

-- Undo of a spawn / redo of a deletion
S.Receive("ObjRemove", function(ply)
	local ent = S.FindUID(ply, net.ReadUInt(32))
	if ent then S.RemoveWithRecord(ply, ent) end
end)

-- Undo of a deletion / redo of a spawn
S.Receive("ObjRestore", function(ply)
	local uid = net.ReadUInt(32)
	if S.FindUID(ply, uid) then return end
	local gy = S.Graveyard[ply]
	local item = gy and gy.items[uid]
	if not item or not S.RestoreItem then
		S.Notice(ply, "#undo_gone", 1)
		return
	end
	local ent = S.RestoreItem(ply, item)
	if ent then
		S.SendSpawned(ply, ent, true)
	else
		S.Notice(ply, "#undo_gone", 1)
	end
end)

S.Receive("Duplicate", function(ply)
	local ent = S.ReadOwned(ply)
	if not ent then return end

	local off = Vector(Cfg.DuplicateOffset, 0, 0)
	local copy, err

	if S.IsLight(ent) then
		copy, err = S.SpawnLight(ply, S.LightData(ent, ent:GetPos() + off))
	elseif S.IsCamera(ent) then
		copy, err = S.SpawnCamera(ply, S.CameraData(ent, ent:GetPos() + off))
	elseif S.IsEffect(ent) then
		copy, err = S.SpawnEffect(ply, S.EffectData(ent, ent:GetPos() + off))
	elseif (S.IsForeign and S.IsForeign(ent)) or (S.ExtrasOf and #S.ExtrasOf(ent) > 0) then
		-- an object of another addon, or one with bonemerged models: through its scene item
		local it = S.Serialize(ent)
		it.pos = SPeditor.VecToTable(SPeditor.TableToVec(it.pos) + off)
		it.extrasOff = off
		copy = S.RestoreItem(ply, it)
		if not copy then err = "#err_create" end
	else
		local pos, ang = S.GetTransform(ent)
		local skin, groups = S.CaptureAppearance(ent)
		copy, err = S.SpawnWithState(ply, ent:GetModel(), pos + off, ang, skin, groups, S.CapturePose(ent), ent.SPeditor_Scale, S.CaptureLook(ent))
	end

	if not copy then
		S.Notice(ply, err or "#err_create", 1)
		return
	end
	local a = ent.SPeditor_Attach
	if a and IsValid(a.parent) then S.Attach(copy, a.parent, a.wear and S.WEAR or S.AttachCode(a.bone, a.mode)) end
	local aim = ent.SPeditor_Aim
	if aim and IsValid(aim.target) then S.SetAim(copy, aim.target, aim.bone) end
	S.SendSpawned(ply, copy)
end)

S.Receive("Transform", function(ply)
	local ent = S.ReadOwned(ply)
	local pos = SPeditor.ReadVecF()
	local ang = SPeditor.ReadAngF()
	if not ent or not SPeditor.ValidVec(pos) or not SPeditor.ValidAng(ang) then return end
	S.SetTransform(ent, pos, ang)
	S.RefreshAttach(ent)       -- an attached object was moved by hand: a new offset
end)

S.Receive("Attach", function(ply)
	local ent    = S.ReadOwned(ply)
	local parent = S.ReadOwned(ply)
	local bone   = net.ReadInt(16)
	if not ent then return end
	if not parent then
		S.Detach(ent)
		return
	end
	local old = ent.SPeditor_Attach
	local same = old and old.parent == parent
	if not same then S.SnapToBone(ent, parent, bone) end
	if not S.Attach(ent, parent, bone) then S.Notice(ply, "#err_attach", 1) end
end)

-- A saved outfit (cl_presets.lua, b0.2.4): every item is made where the character stands and worn
S.Receive("Outfit", function(ply)
	local parent = S.ReadOwned(ply)
	local items = SPeditor.ReadTable()
	if not parent or type(items) ~= "table" or S.IsAux(parent) or parent:GetBoneCount() <= 1 then return end
	local pos, ang = S.GetTransform(parent)
	local n = 0
	for i = 1, math.min(#items, 32) do
		local it = items[i]
		if type(it) == "table" and isstring(it.model) then
			local ent, err = S.SpawnWithState(ply, it.model, pos, ang, tonumber(it.skin), it.groups, nil, tonumber(it.scale),
				type(it.look) == "table" and it.look or nil)
			if ent then
				if isstring(it.name) and it.name ~= "" then
					ent.SPeditor_Name = string.sub(it.name, 1, 48)
					ent:SetNW2String("SPeditor_Name", ent.SPeditor_Name)
				end
				S.Attach(ent, parent, S.WEAR)
				S.SendSpawned(ply, ent)
				n = n + 1
			else
				S.Notice(ply, err or "#err_create", 1)
			end
		end
	end
	if n > 0 then S.Notice(ply, "#outfit_worn|" .. n, 2) end
end)

S.Receive("Aim", function(ply)
	local ent    = S.ReadOwned(ply)
	local target = S.ReadOwned(ply)
	local bone   = net.ReadInt(16)
	if ent then S.SetAim(ent, target, bone) end
end)

S.Receive("Scale", function(ply)
	local ent = S.ReadOwned(ply)
	local scale = net.ReadFloat()
	if ent then S.SetScale(ent, scale) end
end)

S.Receive("Look", function(ply)
	local ent  = S.ReadOwned(ply)
	local look = SPeditor.ReadTable()
	if ent then S.ApplyLook(ent, look) end
end)

S.Receive("CameraFX", function(ply)
	local ent = S.ReadOwned(ply)
	local fx  = SPeditor.ReadTable()
	if S.IsCamera(ent) and not S.SetCameraFX(ent, fx) then S.Notice(ply, "#fx_too_big", 1) end
end)

-- Physics bones of a ragdoll: a packet of several bones in world coordinates
S.Receive("PhysBone", function(ply)
	local ent = S.ReadOwned(ply)
	local count = net.ReadUInt(8)
	if not S.IsRagdoll(ent) then return end
	ent.SPeditor_Placed = true
	local max = ent:GetPhysicsObjectCount()
	for _ = 1, count do
		local idx = net.ReadUInt(8)
		local pos = SPeditor.ReadVecF()
		local ang = SPeditor.ReadAngF()
		if idx < max and SPeditor.ValidVec(pos) and SPeditor.ValidAng(ang) then
			local p = ent:GetPhysicsObjectNum(idx)
			if IsValid(p) then
				p:EnableMotion(false)
				p:SetPos(pos)
				p:SetAngles(ang)
				p:Wake()
			end
		end
	end
end)

S.Receive("BoneManip", function(ply)
	local ent   = S.ReadOwned(ply)
	local bone  = net.ReadUInt(16)
	local pos   = SPeditor.ReadVecF()
	local ang   = SPeditor.ReadAngF()
	local scale = SPeditor.ReadVecF()
	if not ent or S.IsAux(ent) then return end
	S.SetBoneManip(ent, bone, pos, ang, scale)
end)

S.Receive("Reset", function(ply)
	local ent  = S.ReadOwned(ply)
	local kind = net.ReadUInt(2)
	local bone = net.ReadInt(16)
	if not ent or S.IsAux(ent) then return end
	S.Reset(ent, kind, bone)
end)

S.Receive("Flex", function(ply)
	local ent = S.ReadOwned(ply)
	local id  = net.ReadUInt(16)
	local w   = net.ReadFloat()
	if not ent or S.IsAux(ent) then return end
	S.SetFlex(ent, id, w)
end)

S.Receive("EyeTarget", function(ply)
	local ent    = S.ReadOwned(ply)
	local enable = net.ReadBool()
	local vec    = SPeditor.ReadVecF()
	if not ent or S.IsAux(ent) then return end
	S.SetEye(ent, enable and vec or nil)
end)

S.Receive("Skin", function(ply)
	local ent  = S.ReadOwned(ply)
	local skin = net.ReadUInt(8)
	if ent and not S.IsAux(ent) then S.SetSkinSafe(ent, skin) end
end)

S.Receive("Bodygroup", function(ply)
	local ent = S.ReadOwned(ply)
	local id  = net.ReadUInt(8)
	local val = net.ReadUInt(8)
	if ent and not S.IsAux(ent) then S.SetBodygroupSafe(ent, id, val) end
end)

-- The name in the object list and the flags (hidden / locked) live on the entity itself:
-- this way they are saved in scenes, copied by duplicate and survive undo.
S.Receive("Rename", function(ply)
	local ent = S.ReadOwned(ply)
	local name = string.sub(string.Trim(net.ReadString()), 1, 48)
	if not ent then return end
	ent.SPeditor_Name = name
	ent:SetNW2String("SPeditor_Name", name)
end)

function S.SetFlags(ent, hidden, locked)
	ent:SetNW2Bool("SPeditor_Hidden", hidden and true or false)
	ent:SetNW2Bool("SPeditor_Locked", locked and true or false)
end

S.Receive("Flags", function(ply)
	local ent = S.ReadOwned(ply)
	local hidden, locked = net.ReadBool(), net.ReadBool()
	if ent then S.SetFlags(ent, hidden, locked) end
end)

-- "Drop to floor": the lowest point of the physics mesh is lowered onto the nearest
-- world surface under the object.
local function lowestZ(ent)
	local minZ
	for i = 0, ent:GetPhysicsObjectCount() - 1 do
		local p = ent:GetPhysicsObjectNum(i)
		if IsValid(p) then
			local mesh = p:GetMesh()
			if mesh and #mesh > 0 then
				for _, v in ipairs(mesh) do
					local z = p:LocalToWorld(v.pos).z
					if not minZ or z < minZ then minZ = z end
				end
			else
				local z = p:GetPos().z
				if not minZ or z < minZ then minZ = z end
			end
		end
	end
	if not minZ then
		local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
		for _, cx in ipairs({ mins.x, maxs.x }) do
			for _, cy in ipairs({ mins.y, maxs.y }) do
				for _, cz in ipairs({ mins.z, maxs.z }) do
					local z = ent:LocalToWorld(Vector(cx, cy, cz)).z
					if not minZ or z < minZ then minZ = z end
				end
			end
		end
	end
	return minZ
end

S.Receive("DropToFloor", function(ply)
	local ent = S.ReadOwned(ply)
	if not ent or S.IsLight(ent) or S.IsCamera(ent) then return end
	local pos, ang = S.GetTransform(ent)
	-- an effect is a point: it has no size of its own
	local minZ = S.IsEffect(ent) and pos.z or lowestZ(ent)
	if not minZ then return end
	local tr = util.TraceLine({
			start  = Vector(pos.x, pos.y, minZ + 8),
			endpos = Vector(pos.x, pos.y, minZ - 16384),
			filter = ent,
			mask   = MASK_SOLID_BRUSHONLY,
	})
	if not tr.Hit or tr.StartSolid then
		S.Notice(ply, "#drop_nofloor", 1)
		return
	end
	S.SetTransform(ent, pos + Vector(0, 0, tr.HitPos.z - minZ), ang)
	S.RefreshAttach(ent)
end)

S.Receive("LightSpawn", function(ply)
	local d = {}
	d.ltype      = net.ReadUInt(2)
	d.pos        = SPeditor.ReadVecF()
	d.ang        = SPeditor.ReadAngF()
	d.col        = { net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8) }
	d.radius     = net.ReadFloat()
	d.brightness = net.ReadFloat()
	d.fov        = net.ReadFloat()
	if not SPeditor.ValidVec(d.pos) or not SPeditor.ValidAng(d.ang) then return end
	local ent, err = S.SpawnLight(ply, d)
	if not ent then
		S.Notice(ply, err or "#err_create", 1)
		return
	end
	S.SendSpawned(ply, ent)
end)

S.Receive("LightEdit", function(ply)
	local ent = S.ReadOwned(ply)
	local d = {}
	d.ltype      = net.ReadUInt(2)
	d.col        = { net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8) }
	d.radius     = net.ReadFloat()
	d.brightness = net.ReadFloat()
	d.fov        = net.ReadFloat()
	d.shadows    = net.ReadBool()
	d.ortho      = net.ReadBool()
	d.tex        = net.ReadString()
	for _, f in ipairs(SPeditor.LightFields) do d[f.key] = net.ReadFloat() end
	if S.IsLight(ent) then S.ApplyLight(ent, d) end
end)

---------------------------------------------------------------------
-- Prop shadows from the map light (render-to-texture). Their length, colour and direction
-- are set by the map entity shadow_control; if the map has none, it is created.
-- The original values are remembered on the first edit and brought back by a reset.
---------------------------------------------------------------------
local function shadowControl(create)
	local e = ents.FindByClass("shadow_control")[1]
	if not IsValid(e) and create then
		e = ents.Create("shadow_control")
		if not IsValid(e) then return nil end
		e:Spawn()
		e.SPeditor_Made = true
	end
	if IsValid(e) and not e.SPeditor_Orig then
		local t = e:GetSaveTable() or {}
		-- the direction is stored as a vector (the entity angles do not affect it)
		local dir = e:GetInternalVariable("direction")
		e.SPeditor_Orig = {
			dist  = tonumber(t.distance) or 75,
			color = isstring(t.color) and t.color or "128 128 128",
			off   = t.disableallshadows and true or false,
			dir   = isvector(dir) and Vector(dir) or nil,
		}
	end
	return IsValid(e) and e or nil
end

S.Receive("ShadowCtl", function(ply)
	local reset = net.ReadBool()
	local dist  = net.ReadFloat()
	local dark  = net.ReadUInt(8)
	local pitch = net.ReadFloat()
	local yaw   = net.ReadFloat()
	local off   = net.ReadBool()
	local Lim = SPeditor.MapShadowLimits

	if reset then
		local e = shadowControl(false)
		if not e or not e.SPeditor_Orig then return end
		local o = e.SPeditor_Orig
		e:Fire("SetDistance", tostring(o.dist))
		e:Fire("color", string.match(o.color, "^%s*(%d+%s+%d+%s+%d+)") or "128 128 128")
		if o.dir then e:Fire("direction", string.format("%f %f %f", o.dir.x, o.dir.y, o.dir.z)) end
		e:Fire("SetShadowsDisabled", o.off and "1" or "0")
		return
	end

	local e = shadowControl(true)
	if not e then return end
	dark = math.floor(SPeditor.Clamp(dark, Lim.dark.min, Lim.dark.max, Lim.dark.default))
	e:Fire("SetDistance", tostring(SPeditor.Clamp(dist, Lim.dist.min, Lim.dist.max, Lim.dist.default)))
	e:Fire("color", dark .. " " .. dark .. " " .. dark)
	e:Fire("SetAngles", string.format("%g %g 0", SPeditor.Clamp(pitch, Lim.pitch.min, Lim.pitch.max, Lim.pitch.default),
			SPeditor.Clamp(yaw, Lim.yaw.min, Lim.yaw.max, Lim.yaw.default)))
	e:Fire("SetShadowsDisabled", off and "1" or "0")
end)

S.Receive("CameraSpawn", function(ply)
	local pos = SPeditor.ReadVecF()
	local ang = SPeditor.ReadAngF()
	if not SPeditor.ValidVec(pos) or not SPeditor.ValidAng(ang) then return end
	local ent, err = S.SpawnCamera(ply, { pos = pos, ang = ang })
	if not ent then
		S.Notice(ply, err or "#err_create", 1)
		return
	end
	S.SendSpawned(ply, ent)
end)

-- field: "fov" or a key of SPeditor.CameraFields
S.Receive("CameraEdit", function(ply)
	local ent   = S.ReadOwned(ply)
	local field = net.ReadString()
	local value = net.ReadFloat()
	if not S.IsCamera(ent) then return end
	if field == "fov" then
		ent:SetCameraFOV(SPeditor.Clamp(value, 10, 120, 75))
		return
	end
	for _, f in ipairs(SPeditor.CameraFields) do
		if f.key == field and ent["Set" .. f.nw] then ent["Set" .. f.nw](ent, SPeditor.Clamp(value, f.min, f.max, f.default)) end
	end
end)

S.Receive("CameraView", function(ply)
	local ent = S.ReadOwned(ply)
	local on  = net.ReadBool()
	if not S.IsCamera(ent) then return end
	if on then
		for _, e in ipairs(S.List(ply)) do
			if e ~= ent and S.IsCamera(e) then
				e:SetEnabled(false)
				e:SetViewOwner(NULL)
			end
		end
	end
	ent:SetEnabled(on)
	ent:SetViewOwner(on and ply or NULL)
end)

S.Receive("EffectSpawn", function(ply)
	local d = SPeditor.ReadTable() or {}
	d.pos, d.ang = SPeditor.ReadVecF(), SPeditor.ReadAngF()
	if not SPeditor.ValidVec(d.pos) or not SPeditor.ValidAng(d.ang) then return end
	local ent, err = S.SpawnEffect(ply, d)
	if not ent then
		S.Notice(ply, err or "#err_create", 1)
		return
	end
	S.SendSpawned(ply, ent)
end)

S.Receive("EffectEdit", function(ply)
	local ent = S.ReadOwned(ply)
	local d = SPeditor.ReadTable()
	if S.IsEffect(ent) and istable(d) then S.ApplyEffect(ent, d) end
end)

---------------------------------------------------------------------
-- Visibility. The engine sends the client only what is visible from the player's position
-- (PVS), while the editor camera flies apart from the body: once it went into another
-- room, models and ragdolls there stopped arriving at the client — they were neither
-- in the frame nor in the object list (lights and cameras are always sent). So the
-- client reports where the editor looks from, and that point — and all scene cameras —
-- are added to the player's visibility set.
---------------------------------------------------------------------
S.Receive("ViewPos", function(ply)
	local pos = SPeditor.ReadVecF()
	if SPeditor.ValidVec(pos) then ply.SPeditor_ViewPos = pos end
end)

SPeditor.Hook("SetupPlayerVisibility", "SPeditor.EditorPVS", function(ply)
	if not S.Active[ply] then return end
	if ply.SPeditor_ViewPos then AddOriginToPVS(ply.SPeditor_ViewPos) end
	local n = 0
	for _, e in ipairs(S.Owned[ply] or {}) do
		if IsValid(e) and e:GetClass() == "speditor_camera" and n < 8 then
			AddOriginToPVS(e:GetPos())
			n = n + 1
		end
	end
end)

S.Receive("Cleanup", function(ply)
	S.CleanupPlayer(ply)
end)

S.Receive("PoseGet", function(ply)
	local ent = S.ReadOwned(ply)
	if not ent or S.IsAux(ent) then return end
	net.Start(Net.PoseData)
	net.WriteUInt(ent:EntIndex(), 16)
	SPeditor.WriteTable(S.CapturePose(ent))
	net.Send(ply)
end)

S.Receive("PoseApply", function(ply)
	local ent  = S.ReadOwned(ply)
	local pose = SPeditor.ReadTable()
	if not ent or S.IsAux(ent) then return end
	S.ApplyPose(ent, pose)
end)

SPeditor.Hook("PlayerDisconnected", "SPeditor.Cleanup", function(ply)
	S.CleanupPlayer(ply)
	S.Owned[ply]  = nil
	S.Active[ply] = nil
end)

-- Other players cannot move or edit editor objects with the physgun / toolgun
SPeditor.Hook("PhysgunPickup", "SPeditor.NoPhysgun", function(ply, ent)
	if SPeditor.IsEditable(ent) and ent.SPeditor_Owner ~= ply then return false end
end)

SPeditor.Hook("CanTool", "SPeditor.NoTool", function(ply, tr)
	local ent = tr and tr.Entity
	if SPeditor.IsEditable(ent) and ent.SPeditor_Owner ~= ply then return false end
end)
