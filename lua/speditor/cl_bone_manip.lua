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
		SPeditor.Notify("#pose_saved|" .. name, 2)
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
