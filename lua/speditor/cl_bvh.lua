--[[
GM:FM — BVH motion import (r1.0, Phase 2).

A BVH file (data/speditor/mocap/*.bvh) is read locally, its joint hierarchy and the
motion channels are converted into an SMH save in data/smh/, and then the existing
SMH import writes the keys onto the selected object. GMod Lua has no FBX/BVH API, but
the editor's SMH bridge already knows how to put flexes, bones and places into keys.

Only the rotation and offset channels of the joints are used; a model's bones are
matched by name (with the ValveBiped prefix removed) or by a short name.
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
	name = string.gsub(name, "[%.%s_%-]", "")
	return name
end

local function findBone(ent, name)
	local n = norm(name)
	if n == "" then return nil end
	for i = 0, ent:GetBoneCount() - 1 do
		if norm(ent:GetBoneName(i)) == n then return i end
	end
	for i = 0, ent:GetBoneCount() - 1 do
		local b = norm(ent:GetBoneName(i))
		if #b >= 4 and (#n >= 4 and (string.find(b, n, 1, true) or string.find(n, b, 1, true))) then return i end
	end
	return nil
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

function UI.ImportBVH(path, ent, start)
	start = math.floor(tonumber(start) or 0)
	local raw = file.Read(path, "DATA")
	local bvh, err = parseBVH(raw)
	if not bvh then SPeditor.Notify("#bvh_bad|" .. tostring(err), 1) return nil end
	if not IsValid(ent) then SPeditor.Notify("#sa_smh_no_target", 1) return nil end

	local model = string.GetFileFromFilename(ent:GetModel() or "")
	local out = { Map = game.GetMap(), Entities = { { Model = model, Frames = {} } } }
	local used = 0
	for i, vals in ipairs(bvh.frames) do
		local pos, ang = frameTransforms(bvh, vals)
		local bones = {}
		for j, jd in ipairs(bvh.joints) do
			local bi = findBone(ent, jd.name)
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
	bottom:SetTall(76)
	bottom.Paint = function() end
	local slider = UI.Slider(bottom, L("bvh_start"), 0, 200, 0, 0)
	slider:DockMargin(8, 4, 8, 2)
	local btn = vgui.Create("DButton", bottom)
	btn:Dock(BOTTOM)
	btn:DockMargin(8, 2, 8, 4)
	btn:SetText(L("bvh_do"))
	btn:SetFont("SPeditor.Bold")
	btn:SetTall(34)
	btn.DoClick = function()
		local _, line = list:GetSelectedLine()
		local ent = C.selected
		if not line or not IsValid(ent) then return end
		UI.ImportBVH("speditor/mocap/" .. (line:GetValue(1) or ""), ent, math.floor(slider:GetValue()))
		f:Close()
	end
end
