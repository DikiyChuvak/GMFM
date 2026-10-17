-- Bones: list, groups, editing manip values, pose library
SPeditor.Client = SPeditor.Client or {}
local C = SPeditor.Client

---------------------------------------------------------------------
-- Bone list
---------------------------------------------------------------------
function C.BoneGroupOf(name)
	local lname = string.lower(name)
	for _, g in ipairs(SPeditor.BoneGroups) do
		for _, pat in ipairs(g.patterns) do
			if string.find(lname, pat, 1, true) then return g.name end
		end
	end
	return "Other"
end

function C.GetBoneList(ent)
	local list = {}
	if not IsValid(ent) then return list end
	for b = 0, ent:GetBoneCount() - 1 do
		local name = ent:GetBoneName(b)
		if name and name ~= "__INVALIDBONE__" then
			list[#list + 1] = {
				id = b, name = name, parent = ent:GetBoneParent(b),
				phys = C.PhysIndexOfBone(ent, b) ~= nil,
				group = C.BoneGroupOf(name),
			}
		end
	end
	return list
end

function C.GetManip(ent, bone)
	return ent:GetManipulateBonePosition(bone), ent:GetManipulateBoneAngles(bone), ent:GetManipulateBoneScale(bone)
end

---------------------------------------------------------------------
-- Editing manip values (interface sliders)
---------------------------------------------------------------------
function C.EditManip(ent, bone, pos, ang, scale)
	if not IsValid(ent) then return end
	C.SendBoneManip(ent, bone, pos, ang, scale)
	local ref = C.Ref(ent)

	C.BurstEdit("bm" .. ent:EntIndex() .. "_" .. bone, "bone " .. bone,
		function()
		local p, a, s = C.GetManip(ent, bone)
		return { p = p, a = a, s = s }
	end,
	{ p = pos, a = ang, s = scale },
	function(st) local e = C.Deref(ref) if e then C.SendBoneManip(e, bone, st.p, st.a, st.s, true) end end)
end

function C.ResetBone(ent, bone)
	C.SnapshotThen(ent, "reset bone", function() C.SendReset(ent, 0, bone) end)
end

function C.ResetAllBones(ent)
	C.SnapshotThen(ent, "reset bones", function() C.SendReset(ent, 1) end)
end

-- Full reset: bones, flexes, eyes and the physical pose back to the original
function C.ResetPoseFull(ent)
	C.SnapshotThen(ent, "reset pose", function() C.SendReset(ent, 3) end)
end

---------------------------------------------------------------------
-- Pose library: data/speditor/poses/<name>.json (on the client)
---------------------------------------------------------------------
local POSE_DIR = SPeditor.Config.SaveDir .. "/poses"

local function ensurePoseDir()
	local acc = ""
	for part in string.gmatch(POSE_DIR, "[^/]+") do
		acc = (acc == "") and part or (acc .. "/" .. part)
		if not file.IsDir(acc, "DATA") then file.CreateDir(acc) end
	end
end

function C.SavePose(ent, name)
	name = SPeditor.SafeName(name)
	if name == "" or not IsValid(ent) then
		SPeditor.Notify("#err_pose_name", 1)
		return
	end
	C.RequestPose(ent, function(pose)
		if not pose then return end
		ensurePoseDir()
		file.Write(POSE_DIR .. "/" .. name .. ".json", util.TableToJSON({
					version = 1, model = IsValid(ent) and ent:GetModel() or "", pose = pose,
		}))
		SPeditor.Notify("#pose_saved|" .. name .. "|" .. name, 2)
		hook.Run("SPeditor_PoseListChanged")
	end)
end

function C.ListPoses()
	local files = file.Find(POSE_DIR .. "/*.json", "DATA", "datedesc") or {}
	local names = {}
	for i, f in ipairs(files) do names[i] = string.StripExtension(f) end
	return names
end

-- Pose list with the model name, for the interface
function C.ListPoseInfos()
	local infos = {}
	for _, name in ipairs(C.ListPoses()) do
		local data = util.JSONToTable(file.Read(POSE_DIR .. "/" .. name .. ".json", "DATA") or "")
		infos[#infos + 1] = { name = name, model = type(data) == "table" and tostring(data.model or "") or "" }
	end
	return infos
end

function C.LoadPose(ent, name)
	name = SPeditor.SafeName(name)
	local path = POSE_DIR .. "/" .. name .. ".json"
	if not IsValid(ent) or not file.Exists(path, "DATA") then return end

	local data = util.JSONToTable(file.Read(path, "DATA") or "")
	if type(data) ~= "table" or type(data.pose) ~= "table" then
		SPeditor.Notify("#err_pose_damaged", 1)
		return
	end
	-- Bone numbers depend on the model; the server carries a pose from another model over by bone names
	-- (old pose files without bone names) — only onto the same model
	if data.model ~= ent:GetModel() and type(data.pose.names) ~= "table" then
		SPeditor.Notify("#pose_other_model", 1)
		return
	end
	C.SnapshotThen(ent, "load pose", function() C.SendPoseApply(ent, data.pose) end)
end

function C.DeletePose(name)
	name = SPeditor.SafeName(name)
	local path = POSE_DIR .. "/" .. name .. ".json"
	if file.Exists(path, "DATA") then
		file.Delete(path)
		hook.Run("SPeditor_PoseListChanged")
		SPeditor.Notify("#pose_deleted|" .. name, 0)
	end
end

---------------------------------------------------------------------
-- Stretch of a ragdoll's physical bones (a0.7). The engine draws a ragdoll's physical
-- bones from their physics bodies and ignores their manip offset (ManipulateBonePosition) —
-- measured in game: a head moved 25 units by it stayed in place, and a ragdoll gets no
-- BuildBonePositions callback. The offset is still kept (networked, saved with poses, keys
-- and scenes) and applied here, on every client, before the opaque things of a view are
-- drawn: the bone and everything below it move by the offset, given in the space of the
-- parent bone as for any other bone, so the limb grows longer or shifts.
---------------------------------------------------------------------
local stretchInfo = {}      -- [model] = { { bone, parent, subtree = { bones } }, … } — the physical bones

local function physBonesOf(ent)
	local mdl = ent:GetModel() or ""
	local info = stretchInfo[mdl]
	if info then return info end
	info = {}
	local n = ent:GetBoneCount()
	local children = {}
	for b = 0, n - 1 do
		local p = ent:GetBoneParent(b)
		if p and p >= 0 then
			children[p] = children[p] or {}
			table.insert(children[p], b)
		end
	end
	for b = 0, n - 1 do
		local parent = ent:GetBoneParent(b)
		-- the root body has no parent to stretch away from: it is moved as the object
		if parent and parent >= 0 and C.PhysIndexOfBone(ent, b) then
			local sub, stack = {}, { b }
			while #stack > 0 do
				local x = table.remove(stack)
				sub[#sub + 1] = x
				for _, c in ipairs(children[x] or {}) do stack[#stack + 1] = c end
			end
			info[#info + 1] = { bone = b, parent = parent, subtree = sub }
		end
	end
	stretchInfo[mdl] = info
	return info
end

local ragdolls = {}         -- the editor's ragdolls (rescanned twice a second)

timer.Create("SPeditor.Stretch", 0.5, 0, function()
	local list = {}
	for _, ent in ipairs(ents.FindByClass("prop_ragdoll")) do
		if ent:GetNW2Bool("SPeditor_Ent", false) then list[#list + 1] = ent end
	end
	ragdolls = list
end)

-- bones already set up this frame (C.GetBoneWorld, the view before)
local function applyStretch(ent)
	local any = false
	for _, it in ipairs(physBonesOf(ent)) do
		if not ent:GetManipulateBonePosition(it.bone):IsZero() then any = true break end
	end
	if not any then return end
	-- several views a frame (viewports, the render) share the bones of the frame: an offset
	-- already put on is not put on again
	local done = ent.SPeditor_StretchDone
	if done and done.frame == FrameNumber() then
		local m = ent:GetBoneMatrix(done.bone)
		if m and m:GetTranslation():DistToSqr(done.pos) < 1e-4 then return end
	end
	local mark
	for _, it in ipairs(physBonesOf(ent)) do
		local off = ent:GetManipulateBonePosition(it.bone)
		if not off:IsZero() then
			local pm = ent:GetBoneMatrix(it.parent)
			if pm then
				local world = LocalToWorld(off, angle_zero, vector_origin, pm:GetAngles())
				for _, b in ipairs(it.subtree) do
					local m = ent:GetBoneMatrix(b)
					if m then
						m:SetTranslation(m:GetTranslation() + world)
						ent:SetBoneMatrix(b, m)
					end
				end
				mark = it.bone
			end
		end
	end
	if mark then
		local m = ent:GetBoneMatrix(mark)
		ent.SPeditor_StretchDone = { frame = FrameNumber(), bone = mark, pos = m and m:GetTranslation() or vector_origin }
	end
end

hook.Add("PreDrawOpaqueRenderables", "SPeditor.Stretch", function()
	for _, ent in ipairs(ragdolls) do
		if IsValid(ent) then
			ent:SetupBones()
			applyStretch(ent)
		end
	end
end)

-- the gizmo, the skeleton and the bone picking read the bones where they are drawn
function C.ApplyStretch(ent)
	if C.IsRagdoll(ent) then applyStretch(ent) end
end
