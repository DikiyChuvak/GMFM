--[[
SPeditor — objects made outside the editor ("Take objects from the map").

A scene often already stands on the map: ragdolls posed with Ragdoll Mover, models put
on with Advanced Bonemerge or Easy Bonemerge, Advanced Light Entities, Soft Lamps,
stock lamps and lights. They can be taken into the editor's scene as they are:

  * a prop or a ragdoll becomes an ordinary editor object (pose, bones, faces, keys —
    everything works as for a model spawned in the editor);
  * a light or another addon's entity becomes a "foreign" object: it can be selected, moved,
    rotated, hidden, deleted and duplicated, and it is saved in the scene with the data of its
    own addon (through the GMod duplicator — the same data Advanced Duplicator and saves keep);
  * what is parented to such an object (bone-merged clothing, hair, weapons of the bonemerge
    tools) comes along as its "extras": they follow it, are saved in the scene with their bone
    settings and the constraints of their tool, and go away and come back with it on delete / undo.

The addons themselves must be installed: SPeditor stores their data, the drawing is theirs.

Who may take what: in singleplayer — everything; on a server — the entities the player
spawned himself (GetCreator / CPPI); admins — everything.

API:
  S.AdoptCandidates(ply)        what can be taken: { { ent, kind, extras } }
  S.Adopt(ply, ent)             take one entity (with its extras)
  S.IsForeign(ent)              an entity of another addon kept as is
  S.ExtrasOf(root)              its parented descendants that are not scene objects
  S.CaptureExtras(root) / S.RestoreExtras(ply, root, data)
  S.SerializeForeign(ent) / S.RestoreForeign(ply, item, pos, ang)
]]
local S   = SPeditor.Server
local Net = SPeditor.Net

---------------------------------------------------------------------
-- What can be taken
---------------------------------------------------------------------
-- editor objects of their own kind
local PROP = { prop_physics = true, prop_physics_multiplayer = true, prop_ragdoll = true, prop_dynamic = true }

-- lights and lamps of other addons (shown in the list as lights)
local LIGHTS = {
	gmod_lamp = true, gmod_light = true, gmod_softlamp = true,
	cheap_light = true, expensive_light = true, expensive_light_new = true,
	projected_light = true, projected_light_new = true, spot_light = true,
}
local function isLightClass(c)
	return LIGHTS[c] or string.find(c, "advlights", 1, true) ~= nil or string.find(c, "light", 1, true) ~= nil
		or string.find(c, "lamp", 1, true) ~= nil
end

-- never: the player and his things, NPCs, vehicles, helpers of constraints and tools
local NEVER = {
	player = true, predicted_viewmodel = true, gmod_hands = true, physgun_beam = true, worldspawn = true,
	keyframe_rope = true, logic_collision_pair = true, phys_constraint = true, phys_constraintsystem = true,
	gmod_winch_controller = true, gmod_poly = true, rgm_axis = true, prop_effect = true,
	vtrace_scanner = true,   -- a helper of Soft Lamps
}

-- (b0.2.7, asked on the Workshop) an NPC of the map can be taken: it becomes a ragdoll of the scene
local function takableNPC(ent)
	return IsValid(ent) and ent:IsNPC() and not ent:IsNextBot() and ent:Health() > 0 and ent:GetModel() ~= nil
end

local function bad(ent)
	if not IsValid(ent) or ent:IsPlayer() or ent:IsWeapon() or (ent:IsNPC() and not takableNPC(ent)) or ent:IsNextBot() or ent:IsVehicle() then return true end
	local c = ent:GetClass()
	if NEVER[c] or string.StartWith(c, "phys_") or string.StartWith(c, "speditor_") or string.StartWith(c, "env_")
		or string.StartWith(c, "info_") or string.StartWith(c, "func_") or string.StartWith(c, "light_") or string.StartWith(c, "point_") or string.StartWith(c, "trigger_") then
		return true
	end
	return false
end

function S.IsForeign(ent)
	return IsValid(ent) and ent.SPeditor_Foreign ~= nil
end

-- the kind shown in the list: ragdoll / prop / light / other
local function kindOf(ent)
	local c = ent:GetClass()
	if ent:IsNPC() then return "npc" end
	if c == "prop_ragdoll" then return "ragdoll" end
	if PROP[c] then return "prop" end
	if isLightClass(c) then return "light" end
	return "other"
end

-- the player may take it: his own, or anything in singleplayer / for an admin
local function mayTake(ply, ent)
	if game.SinglePlayer() or ply:IsAdmin() then return true end
	local owner = ent.CPPIGetOwner and ent:CPPIGetOwner() or ent:GetCreator()
	return owner == ply
end

local function tracked(ent)
	return ent:GetNW2Bool("SPeditor_Ent", false)
end

-- Parented descendants of root that are not scene objects themselves (bonemerged models)
function S.ExtrasOf(root)
	local out, seen = {}, { [root] = true }
	local function walk(e, depth)
		if depth > 8 then return end
		for _, ch in ipairs(e:GetChildren() or {}) do
			-- engine helpers the object makes itself (light_dynamic of a lamp…) are not copied
			if IsValid(ch) and not seen[ch] and not tracked(ch) and not bad(ch) and (ch:GetModel() or "") ~= ""
				and duplicator.IsAllowed(ch:GetClass()) then
				seen[ch] = true
				out[#out + 1] = ch
				walk(ch, depth + 1)
			end
		end
	end
	walk(root, 0)
	return out
end

-- an entity of a scripted class with a model that the duplicator can recreate
local function dupable(ent)
	local c = ent:GetClass()
	if not duplicator.IsAllowed(c) or ent.DoNotDuplicate then return false end
	return scripted_ents.GetStored(c) ~= nil or duplicator.FindEntityClass(c) ~= nil or LIGHTS[c]
end

function S.AdoptCandidates(ply)
	local out = {}
	for _, ent in ipairs(ents.GetAll()) do
		if takableNPC(ent) and mayTake(ply, ent) then
			out[#out + 1] = { ent = ent, kind = "npc", extras = 0 }
		elseif not bad(ent) and not tracked(ent) and not ent:CreatedByMap() and not IsValid(ent:GetParent())
			and ent:GetModel() and mayTake(ply, ent) then
			local c = ent:GetClass()
			if PROP[c] or dupable(ent) then
				out[#out + 1] = { ent = ent, kind = kindOf(ent), extras = #S.ExtrasOf(ent) }
			end
		end
	end
	return out
end

---------------------------------------------------------------------
-- Duplicator tables without entities (a scene file is JSON)
---------------------------------------------------------------------
local function clean(v, depth)
	depth = depth or 0
	local t = type(v)
	if t == "table" then
		if depth > 12 then return nil end
		local out = {}
		for k, x in pairs(v) do
			local tk = type(k)
			if tk == "string" or tk == "number" then
				local cx = clean(x, depth + 1)
				if cx ~= nil then out[k] = cx end
			end
		end
		return out
	elseif t == "number" or t == "string" or t == "boolean" or t == "Vector" or t == "Angle" then
		return v
	end
	-- entities, players, functions, physics objects, materials: not kept
	return nil
end

-- JSON keeps no numeric keys of sparse tables reliably: maps by index are kept as lists
local function copyEnt(ent)
	local t = duplicator.CopyEntTable(ent)
	return clean(t)
end

---------------------------------------------------------------------
-- Extras: the descendants of a scene object, with the constraints between them and it
---------------------------------------------------------------------
function S.CaptureExtras(root)
	local list = S.ExtrasOf(root)
	if #list == 0 then return nil end
	local set = { [root] = true }
	for _, e in ipairs(list) do set[e] = true end
	local data = { root = root:EntIndex(), ents = {}, cons = {} }
	local seen = {}
	for _, e in ipairs(list) do
		local par = e:GetParent()
		data.ents[#data.ents + 1] = {
			idx = e:EntIndex(), parent = IsValid(par) and par:EntIndex() or nil,
			att = e:GetParentAttachment(), merge = e:IsEffectActive(EF_BONEMERGE) or nil,
			t = copyEnt(e),
		}
		for _, con in pairs(constraint.GetTable(e) or {}) do
			local id = IsValid(con.Constraint) and con.Constraint:GetCreationID() or tostring(con)
			local inside = true
			for _, ce in pairs(con.Entity or {}) do
				if not (ce.World or (IsValid(ce.Entity) and set[ce.Entity])) then inside = false end
			end
			if inside and not seen[id] then
				seen[id] = true
				data.cons[#data.cons + 1] = clean(con)
			end
		end
	end
	return data
end

-- Bring the extras back onto root. off — a shift of their saved places (a duplicate).
function S.RestoreExtras(ply, root, data, off)
	if type(data) ~= "table" or type(data.ents) ~= "table" then return end
	local map = { [tonumber(data.root) or -1] = root }
	local made = {}
	for _, e in ipairs(data.ents) do
		local t = istable(e.t) and table.Copy(e.t)
		if t and t.Class then
			if off and isvector(t.Pos) then t.Pos = t.Pos + off end
			local ent
			ProtectedCall(function() ent = duplicator.CreateEntityFromTable(ply, t) end)
			if IsValid(ent) then
				if ent.RestoreNetworkVars and t.DT then ent:RestoreNetworkVars(t.DT) end
				if ent.OnDuplicated then ProtectedCall(function() ent:OnDuplicated(t) end) end
				ent.BoneMods = table.Copy(t.BoneMods)
				ent.EntityMods = table.Copy(t.EntityMods)
				ent.PhysicsObjects = table.Copy(t.PhysicsObjects)
				map[tonumber(e.idx) or -1] = ent
				made[#made + 1] = { ent = ent, e = e }
			end
		end
	end
	for _, m in ipairs(made) do
		ProtectedCall(function()
			duplicator.ApplyEntityModifiers(ply, m.ent)
			duplicator.ApplyBoneModifiers(ply, m.ent)
			if m.ent.PostEntityPaste then m.ent:PostEntityPaste(ply, m.ent, map) end
		end)
	end
	-- the tools' own constraints (AdvBoneMerge, EasyBonemerge…) parent and set things up
	for _, con in ipairs(data.cons or {}) do
		ProtectedCall(function() duplicator.CreateConstraintFromTable(table.Copy(con), map, ply) end)
	end
	-- plain parenting where no constraint did it
	for _, m in ipairs(made) do
		local par = map[tonumber(m.e.parent) or -1]
		if IsValid(par) and m.ent:GetParent() ~= par then
			m.ent:SetParent(par, tonumber(m.e.att) or -1)
			if m.e.merge then m.ent:AddEffects(EF_BONEMERGE) end
		end
	end
end

-- remove the extras together with their object
function S.RemoveExtras(root)
	for _, e in ipairs(S.ExtrasOf(root)) do
		if IsValid(e) then e:Remove() end
	end
end

---------------------------------------------------------------------
-- Foreign objects (lights and entities of other addons)
---------------------------------------------------------------------
local function friendlyName(ent)
	local stored = scripted_ents.GetStored(ent:GetClass())
	local name = stored and stored.t and stored.t.PrintName
	if not name or name == "" then name = ent:GetClass() end
	return name
end

local function markForeign(ent)
	ent.SPeditor_Foreign = ent:GetClass()
	ent:SetNW2String("SPeditor_Foreign", ent:GetClass())
end

function S.SerializeForeign(ent)
	return { kind = "foreign", class = ent:GetClass(), dupe = copyEnt(ent) }
end

function S.RestoreForeign(ply, it, pos, ang)
	local t = istable(it.dupe) and table.Copy(it.dupe)
	if not t or not t.Class then return nil end
	t.Pos, t.Angle = pos, ang
	local ent
	ProtectedCall(function() ent = duplicator.CreateEntityFromTable(ply, t) end)
	if not IsValid(ent) then return nil end
	if ent.RestoreNetworkVars and t.DT then ent:RestoreNetworkVars(t.DT) end
	if ent.OnDuplicated then ProtectedCall(function() ent:OnDuplicated(t) end) end
	ent.BoneMods = table.Copy(t.BoneMods)
	ent.EntityMods = table.Copy(t.EntityMods)
	ent.PhysicsObjects = table.Copy(t.PhysicsObjects)
	ProtectedCall(function()
		duplicator.ApplyEntityModifiers(ply, ent)
		duplicator.ApplyBoneModifiers(ply, ent)
		if ent.PostEntityPaste then ent:PostEntityPaste(ply, ent, { ent }) end
	end)
	ent:SetPos(pos)
	ent:SetAngles(ang)
	S.Freeze(ent)
	markForeign(ent)
	S.Track(ply, ent)
	return ent
end

---------------------------------------------------------------------
-- Taking
---------------------------------------------------------------------
function S.Adopt(ply, ent)
	if takableNPC(ent) and mayTake(ply, ent) then
		-- (b0.2.7) the NPC becomes a ragdoll of the scene in its place (the posing copy of the model)
		if S.AtLimit(ply, "prop") then return nil, "#err_limit_prop" end
		local pos, ang, model, skin = ent:GetPos(), ent:GetAngles(), ent:GetModel(), ent:GetSkin()
		local rag, err = S.SpawnWithState(ply, model, pos, ang, skin, nil, nil, nil, nil)
		if not rag then return nil, err end
		ent:Remove()
		return rag
	end
	if not IsValid(ent) or bad(ent) or tracked(ent) or IsValid(ent:GetParent()) or not mayTake(ply, ent) then return nil end
	if S.AtLimit(ply, "prop") then return nil, "#err_limit_prop" end
	local c = ent:GetClass()
	if not PROP[c] then
		if not dupable(ent) then return nil end
		markForeign(ent)
		if not ent.SPeditor_Name then
			ent.SPeditor_Name = friendlyName(ent)
			ent:SetNW2String("SPeditor_Name", ent.SPeditor_Name)
		end
	end
	S.Freeze(ent)
	S.StoreInit(ent)
	S.Track(ply, ent)
	return ent
end

-- the list for the "Take objects from the map" window
S.Receive("AdoptList", function(ply)
	local list = S.AdoptCandidates(ply)
	local eye = ply:EyePos()
	table.sort(list, function(a, b) return a.ent:GetPos():DistToSqr(eye) < b.ent:GetPos():DistToSqr(eye) end)
	net.Start(Net.AdoptListData)
	local n = math.min(#list, 400)
	net.WriteUInt(n, 10)
	for i = 1, n do
		local it = list[i]
		net.WriteEntity(it.ent)
		net.WriteString(it.ent:GetClass())
		net.WriteString(string.sub(it.ent:GetModel() or "", 1, 200))
		net.WriteString(it.kind)
		net.WriteUInt(math.min(it.extras, 255), 8)
		net.WriteString(PROP[it.ent:GetClass()] and "" or friendlyName(it.ent))
	end
	net.Send(ply)
end)

---------------------------------------------------------------------
-- Import a duplicator file (b0.2.7, asked by jef and bob on the Workshop): the entities of a dupe
-- made with the game's duplicator (data/duplicator/…) appear where the player looks and become
-- scene objects, as the entities taken from the map do. Vectors in the file are plain tables.
---------------------------------------------------------------------
local DUPE_DIR = "duplicator/"

-- a file of the duplicator folder only, with no way out of it
function S.DupeFileOk(p)
	return isstring(p) and #p < 260 and string.sub(p, 1, #DUPE_DIR) == DUPE_DIR and string.sub(p, -4) == ".txt"
		and not string.find(p, "..", 1, true) and file.Exists(p, "DATA")
end

local function toVec(v)
	if isvector(v) then return Vector(v) end
	if istable(v) and tonumber(v.x) and tonumber(v.y) and tonumber(v.z) then return Vector(v.x, v.y, v.z) end
end

local function toAng(a)
	if isangle(a) then return Angle(a) end
	if istable(a) and tonumber(a.p) and tonumber(a.y) and tonumber(a.r) then return Angle(a.p, a.y, a.r) end
end

function S.ImportDupe(ply, p)
	if not IsValid(ply) or not S.DupeFileOk(p) then return "#dupe_bad" end
	local data = util.JSONToTable(file.Read(p, "DATA") or "")
	if not istable(data) or not istable(data.Entities) then return "#dupe_bad" end

	-- the dupe's origin goes where the player looks
	local origin = toVec(data.HitPos)
	if not origin then
		local sum, n = Vector(0, 0, 0), 0
		for _, t in pairs(data.Entities) do
			local v = istable(t) and toVec(t.Pos)
			if v then sum, n = sum + v, n + 1 end
		end
		origin = n > 0 and sum / n or Vector(0, 0, 0)
	end
	local aim = ply:GetEyeTrace().HitPos + Vector(0, 0, 8)
	local shift = aim - origin

	local made, map = {}, {}
	for idx, t in pairs(data.Entities) do
		if istable(t) and isstring(t.Class) and not S.AtLimit(ply, "prop") then
			t.Pos, t.Angle = (toVec(t.Pos) or origin) + shift, toAng(t.Angle) or Angle(0, 0, 0)
			if istable(t.PhysicsObjects) then
				for _, po in pairs(t.PhysicsObjects) do
					if istable(po) then
						po.Pos = toVec(po.Pos) and (toVec(po.Pos) + shift) or po.Pos
						po.Angle = toAng(po.Angle) or po.Angle
					end
				end
			end
			local ent
			ProtectedCall(function() ent = duplicator.CreateEntityFromTable(ply, t) end)
			if IsValid(ent) then
				if ent.RestoreNetworkVars and t.DT then ent:RestoreNetworkVars(t.DT) end
				if ent.OnDuplicated then ProtectedCall(function() ent:OnDuplicated(t) end) end
				ent.BoneMods = table.Copy(t.BoneMods)
				ent.EntityMods = table.Copy(t.EntityMods)
				ent.PhysicsObjects = table.Copy(t.PhysicsObjects)
				map[tonumber(idx) or idx] = ent
				made[#made + 1] = { ent = ent, c = t.Class }
			end
		end
	end
	for _, m in ipairs(made) do
		ProtectedCall(function()
			duplicator.ApplyEntityModifiers(ply, m.ent)
			duplicator.ApplyBoneModifiers(ply, m.ent)
			if m.ent.PostEntityPaste then m.ent:PostEntityPaste(ply, m.ent, map) end
		end)
	end
	for _, con in ipairs(istable(data.Constraints) and data.Constraints or {}) do
		ProtectedCall(function() duplicator.CreateConstraintFromTable(table.Copy(con), map, ply) end)
	end
	for _, m in ipairs(made) do
		local ent = m.ent
		if not PROP[m.c] then markForeign(ent) end
		S.Freeze(ent)
		if S.IsRagdoll(ent) then S.StoreInit(ent) end
		S.Track(ply, ent)
	end
	if #made == 0 then return "#dupe_none" end
	return nil, #made
end

S.Receive("ImportDupe", function(ply)
	local p = net.ReadString()
	local err, n = S.ImportDupe(ply, p)
	if err then S.Notice(ply, err, 1) return end
	S.Notice(ply, "#dupe_done|" .. n, 2)
end)

S.Receive("Adopt", function(ply)
	local n = net.ReadUInt(10)
	local got, extras = 0, 0
	for _ = 1, n do
		local ent = net.ReadEntity()
		local ok, err = S.Adopt(ply, ent)
		if ok then
			got = got + 1
			extras = extras + #S.ExtrasOf(ok)
		elseif err then
			S.Notice(ply, err, 1)
			break
		end
	end
	S.Notice(ply, "#adopt_done|" .. got .. "|" .. extras, got > 0 and 2 or 0)
end)
