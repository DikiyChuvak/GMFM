--[[
GM:FM — BVH motion import (r1.0, Phase 2).

A BVH file (data/speditor/mocap/*.bvh) is read locally, its joint hierarchy and the
motion channels are converted into an SMH save in data/smh/, and then the existing
SMH import writes the keys onto the selected object. GMod Lua has no FBX/BVH API, but
the editor's SMH bridge already knows how to put flexes, bones and places into keys.

Only the rotation and offset channels of the joints are used; a model's bones are
matched by name (with the ValveBiped and Mixamo prefixes removed) and by the part the
name means (thigh/leg, forearm/elbow), or by a map kept for a foreign skeleton
(the Bones… window, data/speditor/bvhmaps/).
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI, C = SPeditor.UI, SPeditor.Client
local L = SPeditor.L

local function trim(s) return string.match(s or "", "^%s*(.-)%s*$") end

local function parseBVH(text)
	if not isstring(text) then return nil, "no text" end
	local lines, inMotion = {}, false
	for line in text:gmatch("[^\r\n]+") do
		line = trim(line)
		if line ~= "" then
			if line == "MOTION" then inMotion = true end
			lines[#lines + 1] = { text = line, motion = inMotion }
		end
	end
	local joints, stack = {}, {}
	local cur
	for _, ln in ipairs(lines) do
		if ln.motion then break end
		local w = {}
		for word in ln.text:gmatch("%S+") do w[#w + 1] = word end
		if w[1] == "ROOT" or w[1] == "JOINT" then
			-- a joint name may contain spaces ("Bip01 Pelvis"), and the opening brace follows it
			local name = trim((ln.text:match("^%S+%s+(.-)%s*{%s*$") or ln.text:match("^%S+%s+(.+)$") or w[2] or ""))
			cur = { name = name, parent = #stack > 0 and stack[#stack] or nil, offset = Vector(0, 0, 0), channels = {} }
			joints[#joints + 1] = cur
			stack[#stack + 1] = cur
		elseif w[1] == "End" then
			-- the end site has no keys of its own
		elseif w[1] == "{" then
			-- opened
		elseif w[1] == "}" then
			if #stack > 0 then stack[#stack] = nil end
		elseif w[1] == "OFFSET" and cur then
			cur.offset = Vector(tonumber(w[2]) or 0, tonumber(w[3]) or 0, tonumber(w[4]) or 0)
		elseif w[1] == "CHANNELS" and cur then
			for i = 3, #w do cur.channels[#cur.channels + 1] = w[i] end
		end
	end
	local frames, frameTime = {}, 1 / 24
	for _, ln in ipairs(lines) do
		local w = {}
		for word in ln.text:gmatch("%S+") do w[#w + 1] = word end
		if w[1] == "Frame" and w[2] == "Time:" then
			frameTime = tonumber(w[3]) or frameTime
		elseif ln.motion and w[1] ~= "MOTION" and w[1] ~= "Frames:" then
			local vals = {}
			for v in ln.text:gmatch("%S+") do vals[#vals + 1] = tonumber(v) or 0 end
			if #vals > 0 then frames[#frames + 1] = vals end
		end
	end
	if #joints == 0 or #frames == 0 then return nil, "empty BVH" end
	return { joints = joints, frames = frames, frameTime = math.max(frameTime, 1 / 240) }
end

local function norm(name)
	name = string.lower(name or "")
	name = string.gsub(name, "^valvebiped%.bip01_", "")
	name = string.gsub(name, "[%.%s_%-:]", "")
	return name
end

-- The parts of a skeleton, by the words mocap files use for them: Mixamo's LeftUpLeg, a BVH's
-- LeftLeg, ValveBiped's Bip01 L Thigh. The first word found wins, so the longer names come first.
-- A bare "arm" or "leg" is ambiguous (an upper arm and a forearm, a thigh and a calf): both are
-- offered and the free bone decides.
local PARTS = {
	{ "pelvis", "pelvis" }, { "hips", "pelvis" }, { "hip", "pelvis" }, { "root", "pelvis" },
	{ "spine", "spine" }, { "chest", "spine" }, { "torso", "spine" }, { "abdomen", "spine" },
	{ "neck", "neck" }, { "head", "head" },
	{ "clavicle", "clavicle" }, { "shoulder", "clavicle" },
	{ "upperarm", "upperarm" }, { "humerus", "upperarm" },
	{ "forearm", "forearm" }, { "lowerarm", "forearm" }, { "elbow", "forearm" },
	{ "arm", { "upperarm", "forearm" } },
	{ "thumb", "thumb" }, { "finger", "finger" }, { "index", "finger" }, { "middle", "finger" },
	{ "ring", "finger" }, { "pinky", "finger" },
	{ "hand", "hand" }, { "wrist", "hand" },
	{ "thigh", "thigh" }, { "upleg", "thigh" }, { "femur", "thigh" },
	{ "calf", "calf" }, { "shin", "calf" }, { "lowleg", "calf" }, { "lowerleg", "calf" }, { "knee", "calf" },
	{ "leg", { "thigh", "calf" } },
	{ "foot", "foot" }, { "ankle", "foot" },
	{ "toe", "toe" }, { "ball", "toe" },
}

local function partsOf(name)
	local s = string.lower(name or "")
	-- the prefixes mocap files and ValveBiped put in front (Mixamo: "mixamorig:LeftUpLeg")
	s = string.gsub(s, "^mixamorig", "")
	s = string.gsub(s, "^valvebiped%.bip0?1", "")
	s = string.gsub(s, "^valvebiped%.", "")
	s = string.gsub(s, "^bip0?1", "")
	s = string.gsub(s, "^bip", "")
	s = string.gsub(s, "^[%._%-%s:]+", "")
	-- the side is a word (LeftUpLeg, RightArm) or one letter before a separator (L_Thigh, R Calf);
	-- without a separator "leg" and "ring" would lose their first letter to it
	local side, rest = "", s
	if string.sub(s, 1, 4) == "left" then side, rest = "l", string.sub(s, 5)
	elseif string.sub(s, 1, 5) == "right" then side, rest = "r", string.sub(s, 6)
	elseif string.match(string.sub(s, 1, 2), "^[lr][%._%-%s]") then side, rest = string.sub(s, 1, 1), string.sub(s, 3) end
	rest = string.gsub(rest, "[%._%-%s:]", "")
	if rest == "" then return nil end
	for _, p in ipairs(PARTS) do
		if string.find(rest, p[1], 1, true) then
			return type(p[2]) == "table" and p[2] or { p[2] }, side, rest
		end
	end
end

-- how well a BVH joint name fits a bone: the same part (thigh/leg, forearm/elbow), the same
-- side, and the same number (spine 1 — spine 1)
local function boneScore(joint, bone)
	local jn, bn = norm(joint), norm(bone)
	if jn == "" or bn == "" then return 0 end
	if jn == bn then return 10000 end
	local jp, js, jb = partsOf(joint)
	local bp, bs, bb = partsOf(bone)
	if not jp or not bp then return 0 end
	local ji = tonumber(string.match(jb, "(%d+)$")) or 0
	local bi = tonumber(string.match(bb, "(%d+)$")) or 0
	local best = 0
	for _, a in ipairs(jp) do
		for _, b in ipairs(bp) do
			if a == b then
				local score = 100
				if js ~= "" and bs ~= "" then
					if js ~= bs then score = 0
					else score = score + 50 end
				elseif js ~= "" or bs ~= "" then
					score = score + 5       -- only one name says the side: possible, but weaker
				else
					score = score + 20
				end
				if score > 0 then
					if ji == bi then score = score + 10
					else score = score - math.min(math.abs(ji - bi) * 3, 20) end
					if score > best then best = score end
				end
			end
		end
	end
	return best
end

-- [joint name] = bone index, each bone used once
function UI.BVHAutoMap(bvh, ent)
	local out, used = {}, {}
	local bones = ent:GetBoneCount()
	for _, j in ipairs(bvh.joints) do
		local best, bestScore = nil, 0
		for i = 0, bones - 1 do
			if not used[i] then
				local sc = boneScore(j.name, ent:GetBoneName(i))
				if sc > bestScore then best, bestScore = i, sc end
			end
		end
		if best and bestScore >= 100 then out[j.name] = best; used[best] = true end
	end
	return out
end

local function findBone(ent, name, map)
	if map and map[name] ~= nil then return map[name] end
	local n = norm(name)
	if n == "" then return nil end
	local best, bestScore = nil, 0
	for i = 0, ent:GetBoneCount() - 1 do
		local sc = boneScore(name, ent:GetBoneName(i))
		if sc > bestScore then best, bestScore = i, sc end
	end
	if best and bestScore >= 100 then return best end
	return nil
end

-- A mapping kept per model (bone names, not indices: the model may get another skeleton)
local function mapPath(ent)
	local model = string.lower(ent:GetModel() or "model")
	model = string.gsub(model, "[^%w_%-%.]", "_")
	return "speditor/bvhmaps/" .. model .. ".json"
end

function UI.BVHLoadMap(ent)
	local raw = file.Read(mapPath(ent), "DATA")
	local t = raw and util.JSONToTable(raw)
	return istable(t) and t or {}
end

function UI.BVHSaveMap(ent, map)
	if not file.IsDir("speditor/bvhmaps", "DATA") then file.CreateDir("speditor/bvhmaps") end
	file.Write(mapPath(ent), util.TableToJSON(map))
end

local function resolveMap(ent, map)
	local out = {}
	for jname, v in pairs(map or {}) do
		if isstring(v) then
			for i = 0, ent:GetBoneCount() - 1 do
				if norm(ent:GetBoneName(i)) == norm(v) then out[jname] = i; break end
			end
		elseif isnumber(v) then
			out[jname] = v
		end
	end
	return out
end

-- world transforms of the joints at one frame: local offset + the rotation channels applied
local function frameTransforms(bvh, vals)
	local pos, ang = {}, {}
	local vi = 1
	for _, j in ipairs(bvh.joints) do
		local px, py, pz, rx, ry, rz = 0, 0, 0, 0, 0, 0
		for _, ch in ipairs(j.channels) do
			local v = tonumber(vals[vi]) or 0; vi = vi + 1
			if ch == "Xposition" then px = v elseif ch == "Yposition" then py = v elseif ch == "Zposition" then pz = v
			elseif ch == "Xrotation" then rx = v elseif ch == "Yrotation" then ry = v elseif ch == "Zrotation" then rz = v end
		end
		local localPos = Vector(px + j.offset.x, py + j.offset.y, pz + j.offset.z)
		local localAng = Angle(rx, ry, rz)
		if j.parent then
			local pp, pa = pos[j.parent] or vector_origin, ang[j.parent] or angle_zero
			local wp, wa = LocalToWorld(localPos, localAng, pp, pa)
			pos[j], ang[j] = wp, wa
		else
			pos[j], ang[j] = localPos, localAng
		end
	end
	return pos, ang
end

function UI.ImportBVH(path, ent, start, mapping)
	start = math.floor(tonumber(start) or 0)
	local raw = file.Read(path, "DATA")
	local bvh, err = parseBVH(raw)
	if not bvh then SPeditor.Notify("#bvh_bad|" .. tostring(err), 1) return nil end
	if not IsValid(ent) then SPeditor.Notify("#sa_smh_no_target", 1) return nil end
	local map = mapping and resolveMap(ent, mapping) or nil

	local model = string.GetFileFromFilename(ent:GetModel() or "")
	local out = { Map = game.GetMap(), Entities = { { Model = model, Frames = {} } } }
	local used = 0
	for i, vals in ipairs(bvh.frames) do
		local pos, ang = frameTransforms(bvh, vals)
		local bones = {}
		for j, jd in ipairs(bvh.joints) do
			local bi = findBone(ent, jd.name, map)
			if bi then
				bones[bi] = { Pos = pos[j], Ang = ang[j], Scale = Vector(1, 1, 1) }
				used = used + 1
			end
		end
		out.Entities[1].Frames[#out.Entities[1].Frames + 1] = {
			Position = i, EntityData = { bones = bones },
			EaseIn = 0, EaseOut = 0,
		}
	end
	if used == 0 then SPeditor.Notify("#bvh_nobones", 1) return nil end
	if not file.IsDir("smh", "DATA") then file.CreateDir("smh") end
	local smhName = "bvh_" .. os.date("%Y%m%d_%H%M%S")
	file.Write("smh/" .. smhName .. ".txt", util.TableToJSON(out))

	local SA = SPeditor.Component("saeditor").SA
	SPeditor.Component("saeditor"):NetStart("SMH")
	net.WriteUInt(1, 2)
	SPeditor.WriteTable({ op = SA.NextOp(), file = smhName, ent = model, uid = SA.UID(ent),
		start = start, fps = math.floor(1 / bvh.frameTime + 0.5), world = false })
	net.SendToServer()
	return smhName, used, #bvh.frames
end

function UI.OpenBVH()
	local f = vgui.Create("DFrame")
	f:SetTitle(L("bvh_import"))
	f:SetSize(480, 380)
	f:Center()
	f:SetPos(math.max(8, f:GetX() + 80), math.max(8, f:GetY() + 60))
	f:MakePopup()
	if f.GetTitleLabel and IsValid(f:GetTitleLabel()) then f:GetTitleLabel():SetFont("SPeditor.Bold") end
	local list = vgui.Create("DListView", f)
	list:Dock(FILL)
	list:DockMargin(8, 8, 8, 8)
	list:AddColumn(L("sa_smh_file"))
	if list.SetFont then list:SetFont("SPeditor.Small") end
	local files = file.Find("speditor/mocap/*.bvh", "DATA") or {}
	for _, name in ipairs(files) do list:AddLine(name) end
	if #files == 0 then
		local l = vgui.Create("DLabel", f)
		l:Dock(TOP)
		l:SetText(L("bvh_none"))
		l:SetTextColor(UI.PAL and UI.PAL.DIM or color_white)
		l:SetFont("SPeditor.Small")
		l:SetSize(400, 24)
		l:SizeToContents()
		l:DockMargin(10, 4, 10, 0)
	end
	local bottom = vgui.Create("DPanel", f)
	bottom:Dock(BOTTOM)
	bottom:SetTall(110)
	bottom.Paint = function() end
	local slider = UI.Slider(bottom, L("bvh_start"), 0, 200, 0, 0)
	slider:DockMargin(8, 4, 8, 2)
	local row = vgui.Create("DPanel", bottom)
	row:Dock(BOTTOM)
	row:SetTall(38)
	row:DockMargin(8, 2, 8, 4)
	row.Paint = function() end
	local function picked()
		local _, line = list:GetSelectedLine()
		return line and ("speditor/mocap/" .. (line:GetValue(1) or "")) or nil
	end
	local mapBtn = vgui.Create("DButton", row)
	mapBtn:Dock(LEFT)
	mapBtn:SetWide(150)
	mapBtn:SetText(L("bvh_map"))
	mapBtn:SetFont("SPeditor.Bold")
	mapBtn.DoClick = function()
		local path = picked()
		local ent = C.selected
		if not path or not IsValid(ent) then SPeditor.Notify("#sa_smh_no_target", 1) return end
		UI.OpenBVHMap(path, ent, math.floor(slider:GetValue()))
	end
	local btn = vgui.Create("DButton", row)
	btn:Dock(FILL)
	btn:DockMargin(6, 0, 0, 0)
	btn:SetText(L("bvh_do"))
	btn:SetFont("SPeditor.Bold")
	btn.DoClick = function()
		local path = picked()
		local ent = C.selected
		if not path or not IsValid(ent) then return end
		UI.ImportBVH(path, ent, math.floor(slider:GetValue()), UI.BVHLoadMap(ent))
		f:Close()
	end
end

-- Bones of another skeleton: a BVH made for Mixamo or a rig of another game does not share the
-- names of the model. Two lists — the joints and the model's bones — with a search; the map is
-- kept per model in data/speditor/bvhmaps/ and is used by Import onto the selected object.
function UI.OpenBVHMap(path, ent, start)
	local raw = file.Read(path, "DATA")
	local bvh, err = parseBVH(raw)
	if not bvh then SPeditor.Notify("#bvh_bad|" .. tostring(err), 1) return end
	if not IsValid(ent) then SPeditor.Notify("#sa_smh_no_target", 1) return end

	local f = vgui.Create("DFrame")
	f:SetTitle(L("bvh_map_title"))
	f:SetSize(760, 580)
	f:Center()
	f:MakePopup()
	if f.GetTitleLabel and IsValid(f:GetTitleLabel()) then f:GetTitleLabel():SetFont("SPeditor.Bold") end

	local hint = vgui.Create("DLabel", f)
	hint:Dock(TOP)
	hint:DockMargin(8, 6, 8, 2)
	hint:SetFont("SPeditor.Small")
	hint:SetTextColor(UI.PAL and UI.PAL.DIM or color_white)
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:SetText(string.format(L("bvh_map_hint"), ent:GetModel() or ""))

	local foot = vgui.Create("DPanel", f)
	foot:Dock(BOTTOM)
	foot:SetTall(38)
	foot:DockMargin(8, 2, 8, 6)
	foot.Paint = function() end
	local body = vgui.Create("DPanel", f)
	body:Dock(FILL)
	body:DockMargin(8, 4, 8, 4)
	body.Paint = function() end

	local left = vgui.Create("DListView", body)
	left:Dock(LEFT)
	left:SetWide(360)
	left:AddColumn(L("bvh_map_joint"))
	left:AddColumn(L("bvh_map_bone")):SetFixedWidth(170)
	if left.SetFont then left:SetFont("SPeditor.Small") end

	local right = vgui.Create("DPanel", body)
	right:Dock(FILL)
	right:DockMargin(6, 0, 0, 0)
	right.Paint = function() end
	local search = vgui.Create("DTextEntry", right)
	search:Dock(TOP)
	search:DockMargin(0, 0, 0, 4)
	search:SetFont("SPeditor.Small")
	search:SetPlaceholderText(L("bvh_map_search"))
	local bones = vgui.Create("DListView", right)
	bones:Dock(FILL)
	bones:AddColumn(L("bvh_map_bone"))
	if bones.SetFont then bones:SetFont("SPeditor.Small") end

	local map = UI.BVHLoadMap(ent)
	local function boneIndex(name)
		for i = 0, ent:GetBoneCount() - 1 do
			if norm(ent:GetBoneName(i)) == norm(name) then return i end
		end
	end
	local function mappedName(jname)
		local v = map[jname]
		if isnumber(v) then v = ent:GetBoneName(v) end
		if isstring(v) and v ~= "" and boneIndex(v) then return v end
	end
	local function fillJoints(sel)
		left:Clear()
		for _, j in ipairs(bvh.joints) do
			local line = left:AddLine(j.name, mappedName(j.name) or L("bvh_map_none"))
			line.SPJoint = j.name
			if j.name == sel then line:SetSelected(true) end
		end
	end
	local function fillBones(filter)
		bones:Clear()
		filter = string.lower(filter or "")
		for i = 0, ent:GetBoneCount() - 1 do
			local name = ent:GetBoneName(i)
			if filter == "" or string.find(string.lower(name), filter, 1, true) then
				local line = bones:AddLine(name)
				line.SPBone = name
			end
		end
	end
	fillJoints()
	fillBones("")
	search.OnValueChanged = function(_, text) fillBones(text) end

	bones.DoDoubleClick = function(_, _, line)
		local _, jl = left:GetSelectedLine()
		if not jl or not line or not line.SPBone then return end
		map[jl.SPJoint] = line.SPBone
		fillJoints(jl.SPJoint)
	end

	local auto = vgui.Create("DButton", foot)
	auto:Dock(LEFT)
	auto:SetWide(140)
	auto:SetText(L("bvh_map_auto"))
	auto:SetFont("SPeditor.Bold")
	auto.DoClick = function()
		local a = UI.BVHAutoMap(bvh, ent)
		map = {}
		for jname, bi in pairs(a) do map[jname] = ent:GetBoneName(bi) end
		fillJoints()
	end

	local save = vgui.Create("DButton", foot)
	save:Dock(LEFT)
	save:SetWide(200)
	save:DockMargin(6, 0, 0, 0)
	save:SetText(L("bvh_map_save"))
	save:SetFont("SPeditor.Bold")
	save.DoClick = function()
		UI.BVHSaveMap(ent, map)
		SPeditor.Notify(L("bvh_map_saved"), 0)
		f:Close()
	end

	local go = vgui.Create("DButton", foot)
	go:Dock(FILL)
	go:DockMargin(6, 0, 0, 0)
	go:SetText(L("bvh_map_import"))
	go:SetFont("SPeditor.Bold")
	go.DoClick = function()
		UI.BVHSaveMap(ent, map)
		UI.ImportBVH(path, ent, start, map)
		f:Close()
	end
end
