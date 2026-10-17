-- Saving and loading scenes: data/speditor/scenes/<steamid64>/<name>.json
local S   = SPeditor.Server
local Net = SPeditor.Net
local Cfg = SPeditor.Config

local function sceneDir(ply)
	return Cfg.SaveDir .. "/scenes/" .. (ply:SteamID64() or "local")
end

local function ensureDir(path)
	local acc = ""
	for part in string.gmatch(path, "[^/]+") do
		acc = (acc == "") and part or (acc .. "/" .. part)
		if not file.IsDir(acc, "DATA") then file.CreateDir(acc) end
	end
end

local function scenePath(ply, name)
	return sceneDir(ply) .. "/" .. name .. ".json"
end

---------------------------------------------------------------------
-- Serialization
---------------------------------------------------------------------
local function withMeta(ent, d)
	-- attachment: UID of the parent (for undo of deletion) and the bone name
	local a = ent.SPeditor_Attach
	if a and IsValid(a.parent) then
		d.attachUID  = a.parent.SPeditor_UID
		d.attachBone = (a.bone >= 0) and a.parent:GetBoneName(a.bone) or ""
		d.attachWear = a.wear or nil
	end
	-- look-at (a0.7): UID of the target and the bone name
	local aim = ent.SPeditor_Aim
	if aim and IsValid(aim.target) then
		d.aimUID  = aim.target.SPeditor_UID
		d.aimBone = (aim.bone >= 0) and aim.target:GetBoneName(aim.bone) or ""
	end
	d.name   = ent.SPeditor_Name
	d.pac    = S.PACSave and S.PACSave(ent) or nil      -- PAC3 outfits (sv_pac.lua)
	d.hidden = ent:GetNW2Bool("SPeditor_Hidden", false)
	d.locked = ent:GetNW2Bool("SPeditor_Locked", false)
	return d
end

-- Duplicator modifiers of other tools (TF2 paint and crit glow, proxy colours…): saved with
-- the object and applied again when it is restored. The ones the editor keeps itself
-- (colour, material, bones) are left out, the editor's look would be overwritten by them.
local OWN_MODIFIERS = { colour = true, material = true, mass = true, physprops = true, gravity = true,
	bonemanipulate = true, submaterials = true }

local function plainData(v, depth)
	local t = type(v)
	if t == "number" or t == "string" or t == "boolean" or isvector(v) or isangle(v) then return true end
	if t ~= "table" or depth > 4 then return false end
	local n = 0
	for k, x in pairs(v) do
		n = n + 1
		if n > 64 or (type(k) ~= "string" and type(k) ~= "number") or not plainData(x, depth + 1) then return false end
	end
	return true
end

local function captureModifiers(ent)
	local out
	for k, v in pairs(istable(ent.EntityMods) and ent.EntityMods or {}) do
		if isstring(k) and not OWN_MODIFIERS[string.lower(k)] and plainData(v, 0) then
			out = out or {}
			out[k] = table.Copy(v)
		end
	end
	return out
end

function S.RestoreModifiers(ply, ent, mods)
	if not istable(mods) or not IsValid(ent) then return end
	for k, v in pairs(mods) do
		local fn = isstring(k) and not OWN_MODIFIERS[string.lower(k)] and duplicator.EntityModifiers[k]
		if fn and istable(v) then
			ent.EntityMods = ent.EntityMods or {}
			ent.EntityMods[k] = v
			ProtectedCall(function() fn(ply, ent, v) end)
		end
	end
end

local function serializeBase(ent)
	if S.IsLight(ent) then
		local d = S.LightData(ent)
		d.kind = "light"
		d.pos  = SPeditor.VecToTable(d.pos)
		d.ang  = SPeditor.AngToTable(d.ang)
		return withMeta(ent, d)
	end
	if S.IsCamera(ent) then
		local d = S.CameraData(ent)
		d.kind = "camera"
		d.pos  = SPeditor.VecToTable(d.pos)
		d.ang  = SPeditor.AngToTable(d.ang)
		return withMeta(ent, d)
	end
	if S.IsEffect(ent) then
		local d = S.EffectData(ent)
		d.kind = "effect"
		d.fxname = d.name          -- "name" is the object's name in the list (withMeta)
		d.pos  = SPeditor.VecToTable(d.pos)
		d.ang  = SPeditor.AngToTable(d.ang)
		return withMeta(ent, d)
	end
	local pos, ang = S.GetTransform(ent)
	local skin, groups = S.CaptureAppearance(ent)
	return withMeta(ent, {
			kind       = "prop",
			model      = ent:GetModel(),
			pos        = SPeditor.VecToTable(pos),
			ang        = SPeditor.AngToTable(ang),
			skin       = skin,
			bodygroups = groups,
			scale      = ent.SPeditor_Scale,
			look       = S.CaptureLook(ent),
			pose       = S.CapturePose(ent),
			dupemods   = captureModifiers(ent),
	})
end

-- An object as a scene item. Objects of other addons taken from the map (sv_adopt.lua)
-- keep their own data through the duplicator; models put on with bonemerge tools
-- come as "extras" of the object they are parented to.
function S.Serialize(ent)
	local it
	if S.IsForeign and S.IsForeign(ent) then
		local pos, ang = S.GetTransform(ent)
		it = withMeta(ent, S.SerializeForeign(ent))
		it.pos = SPeditor.VecToTable(pos)
		it.ang = SPeditor.AngToTable(ang)
	else
		it = serializeBase(ent)
	end
	if it and S.CaptureExtras and not S.IsAux(ent) then it.extras = S.CaptureExtras(ent) end
	return it
end

-- A ragdoll is spawned without rotation, then the appearance and the local
-- pose are applied, and only then the whole ragdoll is moved to the saved root transform
-- (see S.SpawnWithState in sv_speditor.lua).
function S.RestoreItem(ply, it)
	if type(it) ~= "table" then return nil end
	local pos = SPeditor.TableToVec(it.pos)
	local ang = SPeditor.TableToAng(it.ang)
	if not pos or not ang or not SPeditor.ValidVec(pos) or not SPeditor.ValidAng(ang) then
		return nil
	end

	local ent
	if it.kind == "light" then
		local d = {
			ltype = it.ltype, pos = pos, ang = ang, col = it.col,
			radius = it.radius, brightness = it.brightness,
			fov = it.fov, enabled = it.enabled,
			shadows = it.shadows, ortho = it.ortho, tex = it.tex,
		}
		-- extended settings (scenes of old versions lack them — the defaults stay)
		for _, f in ipairs(SPeditor.LightFields) do d[f.key] = it[f.key] end
		ent = S.SpawnLight(ply, d)
	elseif it.kind == "camera" then
		local d = { pos = pos, ang = ang, fov = it.fov, fx = it.fx }
		-- shake and smoothness (scenes of old versions lack them — the defaults stay)
		for _, f in ipairs(SPeditor.CameraFields) do d[f.key] = it[f.key] end
		ent = S.SpawnCamera(ply, d)
	elseif it.kind == "effect" then
		local d = { pos = pos, ang = ang, src = it.src, name = it.fxname, file = it.file }
		for _, f in ipairs(SPeditor.EffectFields) do d[f.key] = it[f.key] end
		ent = S.SpawnEffect(ply, d)
	elseif it.kind == "foreign" then
		ent = S.RestoreForeign and S.RestoreForeign(ply, it, pos, ang)
	elseif type(it.model) == "string" then
		ent = S.SpawnWithState(ply, it.model, pos, ang, it.skin, it.bodygroups, it.pose, tonumber(it.scale), it.look)
	end

	if ent then
		if type(it.name) == "string" and it.name ~= "" then
			ent.SPeditor_Name = it.name
			ent:SetNW2String("SPeditor_Name", it.name)
		end
		S.SetFlags(ent, it.hidden, it.locked)
		if it.pac and S.PACRestore then S.PACRestore(ent, it.pac) end
		if it.kind == "prop" then S.RestoreModifiers(ply, ent, it.dupemods) end
		-- bonemerged models of other tools come back onto their object
		if type(it.extras) == "table" and S.RestoreExtras then S.RestoreExtras(ply, ent, it.extras, it.extrasOff) end
	end

	-- a restored object keeps its former UID (the undo/redo history needs it)
	local uid = tonumber(it.uid)
	if ent and uid then
		S.SetUID(ent, uid)
		S.NextUID[ply] = math.max(S.NextUID[ply] or 0, uid)
		-- undo of deletion: bring the attachment back if the parent is still there
		local parent = tonumber(it.attachUID) and S.FindUID(ply, tonumber(it.attachUID))
		if parent then S.AttachByName(ent, parent, it.attachBone, it.attachWear) end
		local target = tonumber(it.aimUID) and S.FindUID(ply, tonumber(it.aimUID))
		if target then S.AimByName(ent, target, it.aimBone) end
	end
	return ent
end

function S.AimByName(ent, target, boneName)
	local bone = -1
	if type(boneName) == "string" and boneName ~= "" then bone = target:LookupBone(boneName) or -1 end
	return S.SetAim(ent, target, bone)
end

function S.AttachByName(ent, parent, boneName, wear)
	if wear == true then return S.Attach(ent, parent, S.WEAR) end
	local bone = -1
	if type(boneName) == "string" and boneName ~= "" then bone = parent:LookupBone(boneName) or -1 end
	return S.Attach(ent, parent, bone)
end

---------------------------------------------------------------------
-- Autosaves: autosave is the newest, autosave_2 … autosave_N — the earlier ones.
-- There used to be one file, and a broken scene overwrote the good one within minutes.
---------------------------------------------------------------------
local AUTOSAVE = "autosave"

local function rotateAutosaves(ply)
	local keep = math.max(Cfg.AutosaveKeep or 5, 1)
	local function path(i) return scenePath(ply, i == 1 and AUTOSAVE or (AUTOSAVE .. "_" .. i)) end
	if file.Exists(path(keep), "DATA") then file.Delete(path(keep)) end
	for i = keep - 1, 1, -1 do
		if file.Exists(path(i), "DATA") then file.Rename(path(i), path(i + 1)) end
	end
end

---------------------------------------------------------------------
-- Example scenes that come with the addon (data_static/speditor/examples/<name>.json).
-- They are listed after the player's own scenes and loaded by the same name; a scene the
-- player saved under that name takes its place, and the example itself cannot be changed
-- or deleted.
---------------------------------------------------------------------
local EXAMPLE_DIR = "data_static/speditor/examples"

local function examplePath(name)
	local path = EXAMPLE_DIR .. "/" .. name .. ".json"
	return file.Exists(path, "GAME") and path or nil
end

---------------------------------------------------------------------
-- Scene list
---------------------------------------------------------------------
function S.SendSceneList(ply)
	local names, seen = {}, {}
	for _, f in ipairs(file.Find(sceneDir(ply) .. "/*.json", "DATA", "datedesc") or {}) do
		local name = string.StripExtension(f)
		names[#names + 1] = name
		seen[name] = true
	end
	for _, f in ipairs(file.Find(EXAMPLE_DIR .. "/*.json", "GAME") or {}) do
		local name = string.StripExtension(f)
		if not seen[name] and SPeditor.SafeName(name) == name then names[#names + 1] = name end
	end
	local count = math.min(#names, 200)
	net.Start(Net.SceneListData)
	net.WriteUInt(count, 8)
	for i = 1, count do
		net.WriteString(names[i])
	end
	net.Send(ply)
end

---------------------------------------------------------------------
-- Receivers
---------------------------------------------------------------------
S.Receive("SceneList", function(ply)
	S.SendSceneList(ply)
end)

S.Receive("SceneSave", function(ply)
	local name = SPeditor.SafeName(net.ReadString())
	local meta = net.ReadString()
	if name == "" then
		S.Notice(ply, "#err_scene_name", 1)
		return
	end
	if #meta > Cfg.MaxMetaLen then meta = "" end
	local items, indexOf = {}, {}
	local list = S.List(ply)
	for i, ent in ipairs(list) do indexOf[ent] = i end
	for i, ent in ipairs(list) do
		local it = S.Serialize(ent)
		-- in a scene file the parent is given by the object's number in the list (a UID does not live between sessions)
		local a = ent.SPeditor_Attach
		it.attachUID = nil
		it.attachTo = a and IsValid(a.parent) and indexOf[a.parent] or nil
		local aim = ent.SPeditor_Aim
		it.aimUID = nil
		it.aimTo = aim and IsValid(aim.target) and indexOf[aim.target] or nil
		items[i] = it
	end
	ensureDir(sceneDir(ply))
	local auto = (name == AUTOSAVE)
	if auto then rotateAutosaves(ply) end
	-- the map is recorded so that loading on another map can warn:
	-- object coordinates would end up in random places there
	local data = { version = 2, name = name, map = game.GetMap(), meta = meta, items = items }
	-- component data (COMP:SceneData): it refers to objects by their number in the items list
	-- (the field is still called "mods": a0.6 and older read their SAeditor data from it)
	data.mods = SPeditor.Components.SaveScene(ply, { ents = list, indexOf = indexOf })
	file.Write(scenePath(ply, name), util.TableToJSON(data))
	if auto then
		S.Notice(ply, "#scene_autosaved|" .. #items, 3)
	else
		-- the folder is in the message: people kept asking where the scenes are on the disk
		S.Notice(ply, "#scene_saved|" .. name .. "|" .. #items .. "|garrysmod/data/" .. scenePath(ply, name), 2)
	end
	S.SendSceneList(ply)
end)

S.Receive("SceneLoad", function(ply)
	local name = SPeditor.SafeName(net.ReadString())
	local path = scenePath(ply, name)
	local raw
	if name ~= "" and file.Exists(path, "DATA") then
		raw = file.Read(path, "DATA")
	elseif name ~= "" and examplePath(name) then
		raw = file.Read(examplePath(name), "GAME")
	else
		S.Notice(ply, "#err_scene_missing", 1)
		return
	end
	local data = util.JSONToTable(raw or "")
	if type(data) ~= "table" or type(data.items) ~= "table" then
		S.Notice(ply, "#err_scene_damaged", 1)
		return
	end
	S.CleanupPlayer(ply)
	local ok, bad = 0, 0
	local spawned = {}
	for i, it in ipairs(data.items) do
		local success, res = pcall(S.RestoreItem, ply, it)
		if success and res then
			ok = ok + 1
			spawned[i] = res
		else
			bad = bad + 1
		end
	end
	-- attachments are restored once all objects have been created
	for i, it in ipairs(data.items) do
		local parent = type(it) == "table" and tonumber(it.attachTo) and spawned[tonumber(it.attachTo)]
		if spawned[i] and parent then S.AttachByName(spawned[i], parent, it.attachBone, it.attachWear) end
		local target = type(it) == "table" and tonumber(it.aimTo) and spawned[tonumber(it.aimTo)]
		if spawned[i] and target then S.AimByName(spawned[i], target, it.aimBone) end
	end
	local indexOf = {}
	for i, ent in pairs(spawned) do indexOf[ent] = i end
	SPeditor.Components.LoadScene(ply, data.mods, { ents = spawned, indexOf = indexOf })
	net.Start(Net.SceneLoaded)
	net.WriteString(type(data.meta) == "string" and data.meta or "")
	net.Send(ply)
	if bad > 0 then
		S.Notice(ply, "#scene_loaded_skip|" .. ok .. "|" .. bad, 0)
	else
		S.Notice(ply, "#scene_loaded|" .. ok, 2)
	end
	if type(data.map) == "string" and data.map ~= "" and data.map ~= game.GetMap() then
		S.Notice(ply, "#scene_other_map|" .. data.map, 1)
	end
end)

S.Receive("SceneDelete", function(ply)
	local name = SPeditor.SafeName(net.ReadString())
	local path = scenePath(ply, name)
	if name ~= "" and file.Exists(path, "DATA") then
		file.Delete(path)
		S.SendSceneList(ply)
		S.Notice(ply, "#scene_deleted|" .. name, 0)
	elseif name ~= "" and examplePath(name) then
		S.Notice(ply, "#scene_example", 0)
	end
end)
