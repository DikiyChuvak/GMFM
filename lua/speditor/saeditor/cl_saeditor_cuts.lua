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

Tracks (a0.9, the track groups of SFM's clip editor): named groups of objects shown under the film
strip; a track folds its objects into one row that shows all their keys.
  SA.groups                    { { name, uids = { uid, … }, open }, … } (from the server, saved with the scene)
  SA.GroupOf(uid)              the index of the track an object is in, or nil
  SA.NewGroup(name, ents)  SA.MoveToGroup(i, ents)  SA.UngroupEnts(ents)
  SA.RenameGroup(i, name)  SA.DeleteGroup(i)  SA.MoveGroup(i, d)  SA.ToggleGroup(i)  — one undo step each
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

---------------------------------------------------------------------
-- Tracks
---------------------------------------------------------------------
SA.groups = SA.groups or {}

local function copyGroups(list)
	local out = {}
	for i, g in ipairs(list) do out[i] = { name = g.name, uids = table.Copy(g.uids), open = g.open ~= false } end
	return out
end

local function sendGroups(list)
	COMP:NetStart("Groups")
	SPeditor.WriteTable(list)
	net.SendToServer()
end

-- folding is not an edit: no undo step for it
local function commitGroups(list, noHistory)
	local before, after = copyGroups(SA.groups), copyGroups(list)
	SA.groups = copyGroups(list)
	sendGroups(after)
	hook.Run("SAeditor_Changed")
	if not noHistory then C.PushHistory("sa track", function() sendGroups(before) end, function() sendGroups(after) end) end
end

function SA.GroupOf(uid)
	for i, g in ipairs(SA.groups) do
		for _, u in ipairs(g.uids) do
			if u == uid then return i end
		end
	end
end

local function uidsOf(ents)
	local out = {}
	for _, e in ipairs(ents) do
		local u = SA.UID(e)
		if u ~= 0 then out[#out + 1] = u end
	end
	return out
end

-- the objects leave the tracks they were in
local function without(list, uids)
	local drop = {}
	for _, u in ipairs(uids) do drop[u] = true end
	for _, g in ipairs(list) do
		local keep = {}
		for _, u in ipairs(g.uids) do if not drop[u] then keep[#keep + 1] = u end end
		g.uids = keep
	end
	return list
end

function SA.NewGroup(name, ents)
	local list = without(copyGroups(SA.groups), uidsOf(ents or {}))
	if #list >= 64 then return end
	list[#list + 1] = { name = name ~= "" and name or string.format(SPeditor.L("sa_grp_default"), #list + 1), uids = uidsOf(ents or {}), open = true }
	commitGroups(list)
	return #list
end

function SA.MoveToGroup(i, ents)
	local uids = uidsOf(ents)
	local list = without(copyGroups(SA.groups), uids)
	if not list[i] then return end
	for _, u in ipairs(uids) do table.insert(list[i].uids, u) end
	commitGroups(list)
end

function SA.UngroupEnts(ents)
	commitGroups(without(copyGroups(SA.groups), uidsOf(ents)))
end

function SA.RenameGroup(i, name)
	local list = copyGroups(SA.groups)
	if not list[i] or name == "" then return end
	list[i].name = name
	commitGroups(list)
end

function SA.DeleteGroup(i)
	local list = copyGroups(SA.groups)
	if not list[i] then return end
	table.remove(list, i)
	commitGroups(list)
end

function SA.MoveGroup(i, d)
	local list = copyGroups(SA.groups)
	local j = i + d
	if not list[i] or not list[j] then return end
	list[i], list[j] = list[j], list[i]
	commitGroups(list)
end

function SA.ToggleGroup(i, open)
	local list = copyGroups(SA.groups)
	if not list[i] then return end
	if open == nil then open = not list[i].open end
	list[i].open = open
	commitGroups(list, true)
end

---------------------------------------------------------------------
-- Bookmarks (b0.2, as SFM's timeline bookmarks): named marks on the frame ruler to come back
-- to — a beat of the music, the start of a move. { { f, name }, … } in frame order; the server
-- keeps them with the scene and moves them when time is inserted or cut out.
---------------------------------------------------------------------
SA.marks = SA.marks or {}

local function copyMarks(list)
	local out = {}
	for i, m in ipairs(list) do out[i] = { f = m.f, name = m.name } end
	table.sort(out, function(x, y) return x.f < y.f end)
	return out
end

local function sendMarks(list)
	COMP:NetStart("Marks")
	SPeditor.WriteTable(list)
	net.SendToServer()
end

local function commitMarks(list, label)
	local before, after = copyMarks(SA.marks), copyMarks(list)
	SA.marks = copyMarks(list)
	sendMarks(after)
	hook.Run("SAeditor_Changed")
	C.PushHistory(label or "sa bookmark", function() sendMarks(before) end, function() sendMarks(after) end)
end

function SA.MarkAt(f)
	for i, m in ipairs(SA.marks) do
		if m.f == f then return i, m end
	end
end

-- a bookmark at frame f (the playhead's by default); one per frame
function SA.AddMark(f, name)
	f = math.floor((f or SA.frame) + 0.5)
	if SA.MarkAt(f) then return end
	local list = copyMarks(SA.marks)
	list[#list + 1] = { f = f, name = name or "" }
	commitMarks(list, "sa bookmark add")
end

function SA.RemoveMark(f)
	local i = SA.MarkAt(f)
	if not i then return end
	local list = copyMarks(SA.marks)
	table.remove(list, i)
	commitMarks(list, "sa bookmark delete")
end

function SA.RenameMark(f, name)
	local i = SA.MarkAt(f)
	if not i then return end
	local list = copyMarks(SA.marks)
	list[i].name = string.sub(name or "", 1, 64)
	commitMarks(list, "sa bookmark rename")
end

function SA.MoveMark(from, to)
	to = math.floor(to + 0.5)
	local i = SA.MarkAt(from)
	if not i or from == to or SA.MarkAt(to) then return end
	local list = copyMarks(SA.marks)
	list[i].f = to
	commitMarks(list, "sa bookmark move")
end

function SA.ClearMarks()
	if #SA.marks == 0 then return end
	commitMarks({}, "sa bookmarks clear")
end

-- the nearest bookmark left (dir = -1) or right (dir = 1) of the playhead
function SA.NeighbourMark(dir)
	local cur = math.floor(SA.frame + 0.5)
	local best
	for _, m in ipairs(SA.marks) do
		if dir < 0 and m.f < cur and (not best or m.f > best) then best = m.f end
		if dir > 0 and m.f > cur and (not best or m.f < best) then best = m.f end
	end
	return best
end

function SA.MarkMenu(f)
	local L = SPeditor.L
	local m = SPeditor.UI.Menu()
	local i, mk = SA.MarkAt(f)
	if mk then
		m:AddOption(string.format(L("sa_mark_title"), mk.name ~= "" and mk.name or tostring(mk.f))):SetEnabled(false)
		m:AddSpacer()
		m:AddOption(L("sa_mark_go"), function() SA.Seek(mk.f) end):SetIcon("icon16/arrow_right.png")
		m:AddOption(L("sa_mark_rename"), function()
			Derma_StringRequest(L("sa_mark_rename"), L("enter_name"), mk.name, function(name) SA.RenameMark(mk.f, string.Trim(name)) end)
		end):SetIcon("icon16/textfield_rename.png")
		m:AddOption(L("sa_mark_delete"), function() SA.RemoveMark(mk.f) end):SetIcon("icon16/delete.png")
	else
		m:AddOption(L("sa_mark_add"), function() SA.AddMark(f) end):SetIcon("icon16/flag_blue.png")
	end
	if #SA.marks > 0 then
		m:AddSpacer()
		local go = m:AddSubMenu(L("sa_mark_list"))
		for _, b in ipairs(SA.marks) do
			go:AddOption(string.format("%d  %s", b.f, b.name), function() SA.Seek(b.f) end)
		end
		m:AddOption(L("sa_mark_clear"), function() SA.ClearMarks() end):SetIcon("icon16/cross.png")
	end
	m:Open()
	return m
end

---------------------------------------------------------------------
-- Shot list (b0.2, as SFM's Export_Shot_List script): every shot of the film strip with its
-- camera, frames, length and timecodes, as text — a file in data/speditor/shotlists/ and the
-- clipboard, for a storyboard, an edit or the people making the film with you.
---------------------------------------------------------------------
function SA.ShotList()
	local L = SPeditor.L
	local UI = SPeditor.UI
	local fps = math.max(SA.fps, 1)
	local shots = {}
	if #SA.cuts == 0 then
		shots[1] = { f0 = 0, f1 = SA.frames, cam = nil }
	else
		for i, c in ipairs(SA.cuts) do
			local f0 = i == 1 and 0 or c.f
			local f1 = SA.cuts[i + 1] and SA.cuts[i + 1].f or SA.frames
			if f1 > f0 then shots[#shots + 1] = { f0 = f0, f1 = f1, uid = c.uid } end
		end
	end
	local scene = C.sceneName and C.sceneName ~= "" and C.sceneName or L("sa_shots_untitled")
	-- columns padded by letters, not bytes (Cyrillic names and headers)
	local function pad(str, n, right)
		str = tostring(str)
		local len = utf8.len(str) or #str
		local fill = string.rep(" ", math.max(n - len, 0))
		return right and (fill .. str) or (str .. fill)
	end
	local function row(c)
		return pad(c[1], 4) .. " " .. pad(c[2], 28) .. " " .. pad(c[3], 8, true) .. " " .. pad(c[4], 8, true) .. " " .. pad(c[5], 8, true)
			.. " " .. pad(c[6], 8, true) .. "   " .. pad(c[7], 12) .. " " .. c[8]
	end
	local lines = {
		string.format(L("sa_shots_title"), scene, game.GetMap(), os.date("%Y-%m-%d %H:%M")),
		string.format(L("sa_shots_total"), #shots, SA.frames, SA.frames / fps, fps),
		"",
		row({ "#", L("sa_shots_cam"), L("sa_shots_in"), L("sa_shots_out"), L("sa_shots_frames"), L("sa_shots_sec"), L("sa_shots_tcin"), L("sa_shots_tcout") }),
	}
	for i, s in ipairs(shots) do
		local cam = s.uid and SA.EntByUID and SA.EntByUID(s.uid)
		local name = IsValid(cam) and C.DisplayName(cam) or (s.uid and ("#" .. s.uid) or "—")
		if (utf8.len(name) or #name) > 28 then name = utf8.sub and utf8.sub(name, 1, 28) or string.sub(name, 1, 28) end
		lines[#lines + 1] = row({ i, name, s.f0, s.f1, s.f1 - s.f0, string.format("%.2f", (s.f1 - s.f0) / fps), UI.Timecode(s.f0 / fps), UI.Timecode(s.f1 / fps) })
	end
	return table.concat(lines, "\n"), #shots
end

function SA.ExportShotList()
	local text, n = SA.ShotList()
	local dir = (SPeditor.Config and SPeditor.Config.SaveDir or "speditor") .. "/shotlists"
	if not file.IsDir(dir, "DATA") then file.CreateDir(dir) end
	local name = SPeditor.SafeName((C.sceneName and C.sceneName ~= "") and C.sceneName or "untitled") .. "_" .. os.date("%Y%m%d_%H%M%S")
	file.Write(dir .. "/" .. name .. ".txt", text)
	SetClipboardText(text)
	SPeditor.Notify(string.format(SPeditor.L("sa_shots_done"), n, "garrysmod/data/" .. dir .. "/" .. name .. ".txt"), 2)
	return text
end
