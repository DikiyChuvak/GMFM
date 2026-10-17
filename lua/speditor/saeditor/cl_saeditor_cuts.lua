--[[
SAeditor — camera cuts (a0.6): which scene camera the animation is watched through, from which
frame on, as the shots of SFM. A cut at frame F says "from F, through this camera" — until the
next cut; before the first cut the first cut's camera is used. The timeline shows them as the
"Cameras" row at the top (cl_saeditor_ui.lua); the player outside the editor
(cl_saeditor_player.lua) and the video render follow them.

  SA.cuts                      { { f = frame, uid = camera UID }, … } in frame order (from the server)
  SA.CameraAt(frame)           the camera entity at the frame, or nil (no cuts / the camera is gone)
  SA.CutIndexAt(frame)         the index of the cut in effect at the frame
  SA.AddCut(frame, cam)  SA.RemoveCut(frame)  SA.MoveCut(from, to)  — one undo step each
]]
local COMP = SPeditor.Component("saeditor")
local SA  = COMP.SA
local C   = SPeditor.Client

SA.cuts = SA.cuts or {}

function SA.CutIndexAt(frame)
	local idx
	for i, c in ipairs(SA.cuts) do
		if c.f <= frame + 1e-3 then idx = i else break end
	end
	if not idx and #SA.cuts > 0 then idx = 1 end
	return idx
end

function SA.CameraAt(frame)
	local i = SA.CutIndexAt(frame)
	if not i then return nil end
	local e = SA.EntByUID(SA.cuts[i].uid)
	return C.IsCamera(e) and e or nil
end

local function copyCuts(list)
	local out = {}
	for i, c in ipairs(list) do out[i] = { f = c.f, uid = c.uid } end
	return out
end

local function send(list)
	COMP:NetStart("Cuts")
	SPeditor.WriteTable(list)
	net.SendToServer()
end

local function commit(list)
	table.sort(list, function(a, b) return a.f < b.f end)
	local before, after = copyCuts(SA.cuts), copyCuts(list)
	SA.cuts = copyCuts(list)
	send(after)
	hook.Run("SAeditor_Changed")
	C.PushHistory("sa cut", function() send(before) end, function() send(after) end)
end

function SA.AddCut(frame, cam)
	local uid = SA.UID(cam)
	if uid == 0 then return end
	frame = math.Clamp(math.floor(frame + 0.5), 0, SA.frames)
	local list = {}
	for _, c in ipairs(SA.cuts) do
		if c.f ~= frame then list[#list + 1] = { f = c.f, uid = c.uid } end
	end
	list[#list + 1] = { f = frame, uid = uid }
	commit(list)
end

function SA.RemoveCut(frame)
	local list = {}
	for _, c in ipairs(SA.cuts) do
		if c.f ~= frame then list[#list + 1] = { f = c.f, uid = c.uid } end
	end
	if #list ~= #SA.cuts then commit(list) end
end

function SA.MoveCut(from, to)
	to = math.Clamp(math.floor(to + 0.5), 0, SA.frames)
	if from == to then return end
	local list, moved = {}, nil
	for _, c in ipairs(SA.cuts) do
		if c.f == from then moved = c.uid elseif c.f ~= to then list[#list + 1] = { f = c.f, uid = c.uid } end
	end
	if not moved then return end
	list[#list + 1] = { f = to, uid = moved }
	commit(list)
end

-- the cameras of the scene, in the order of the object list
function SA.SceneCameras()
	local out = {}
	for _, obj in ipairs(C.BuildEntityList()) do
		if C.IsCamera(obj.ent) then out[#out + 1] = obj.ent end
	end
	return out
end
