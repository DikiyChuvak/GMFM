--[[
SAeditor — client: timeline state, commands to the server, auto key, hotkeys,
model animation import. The interface is cl_saeditor_ui.lua, rendering is cl_saeditor_video.lua,
sounds and voices are cl_saeditor_sound.lua.

  SA.frame            the current frame (fractional during playback)
  SA.tracks[uid]      table of contents of a track: { { f = frame, e = easing, pos = Vector,
                      only / skip = bone keys: { [part] = true } }, … } (sv_saeditor.lua)
                      (the face track of an object: SA.tracks[SA.FaceTrack(uid)])
  SA.Seek(frame)  SA.Play(on)  SA.SetKey(ents)  SA.SetFaceKey(ents)  SA.DeleteKey(uid, frame)  SA.MoveKey(…)
  SA.ImportSequence(ent, seq, opts)      SA.RenderSequence(opts)
]]
local COMP = SPeditor.Component("saeditor")
local SA  = COMP.SA
local C   = SPeditor.Client
local OP  = SA.OP

SA.fps     = SA.fps or 24
SA.frames  = SA.frames or 96
SA.frame   = SA.frame or 0
SA.tracks  = SA.tracks or {}
SA.playing = SA.playing or false
if SA.loop == nil then SA.loop = true end
if SA.autokey == nil then SA.autokey = false end

-- the editor's render look of the viewport (cl_render.lua) asks whether the scene moves
-- by itself and at which moment it is
function C.ScenePlaying() return SA.playing or SA.rendering or false end
function C.SceneTime() return math.floor(SA.frame * 100 + 0.5) / 100 end

local opSerial = SA.opSerial or (math.floor(SysTime() * 1000) % 100000) * 1000
local function nextOp()
	opSerial = opSerial + 1
	SA.opSerial = opSerial
	return opSerial
end

function SA.UID(ent) return IsValid(ent) and ent:GetNW2Int("SPeditor_UID", 0) or 0 end

function SA.EntByUID(uid)
	for _, e in ipairs(C.Objects()) do
		if IsValid(e) and e:GetNW2Int("SPeditor_UID", 0) == uid then return e end
	end
end

---------------------------------------------------------------------
-- Bone keys (a0.6): with the mode on, a key set while a bone is selected — by K or by auto key
-- after a drag — holds only that bone, and each bone moves between its own keys (as in SFM).
-- A part is "p<i>" — physics body i of a ragdoll ("p0" — its root, the whole ragdoll) — or
-- "b<i>" — the offset of bone i.
---------------------------------------------------------------------
local cvBoneKeys = CreateClientConVar("saeditor_bone_keys", "0", true, false, "SAeditor: keys of a selected bone hold only that bone", 0, 1)
function SA.BoneKeysOn() return cvBoneKeys:GetBool() end
function SA.ToggleBoneKeys() RunConsoleCommand("saeditor_bone_keys", cvBoneKeys:GetBool() and "0" or "1") end

-- the parts of a bone, as the list the server takes: "p3,b14" (nil — not a bone of a model)
function SA.BoneParts(ent, bone)
	if not IsValid(ent) or C.IsAux(ent) or not bone or bone < 0 then return nil end
	local pi = C.PhysIndexOfBone(ent, bone)
	if pi == 0 then
		-- the root body: the other bodies are kept relative to it, so its key holds them all
		-- (the pose stays as it is seen; the gizmo keys a dragged root the same way)
		local list = {}
		for b = 0, ent:GetBoneCount() - 1 do
			local i = C.PhysIndexOfBone(ent, b)
			if i then list[#list + 1] = "p" .. i end
		end
		return table.concat(list, ",")
	end
	if pi then return "p" .. pi .. ",b" .. bone end
	return "b" .. bone
end

-- the key k (of SA.tracks) holds a part of the list "p3,b14"
function SA.KeyHasParts(k, parts)
	for part in string.gmatch(parts, "[pb]%d+") do
		if k.only then
			if k.only[part] then return true end
		elseif not (k.skip and k.skip[part]) then
			return true
		end
	end
	return false
end

function SA.HasKey(uid, frame)
	for _, k in ipairs(SA.tracks[uid] or {}) do
		if k.f == frame then return k end
	end
end

---------------------------------------------------------------------
-- Server -> client
---------------------------------------------------------------------
SA.ReceiveParts("Summary", function(t)
	t = t or {}
	SA.fps    = tonumber(t.fps) or 24
	SA.frames = tonumber(t.frames) or 96
	SA.loop   = t.loop and true or false
	local tracks = {}
	for uid, list in pairs(istable(t.tracks) and t.tracks or {}) do
		local keys = {}
		local function set(str)
			if not isstring(str) or str == "" then return nil end
			local out = {}
			for part in string.gmatch(str, "[pb]%d+") do out[part] = true end
			return next(out) and out or nil
		end
		for i, k in ipairs(SA.FromPages(list)) do
			keys[i] = { f = k[1], e = k[2], pos = Vector(k[3] or 0, k[4] or 0, k[5] or 0), only = set(k[6]), skip = set(k[7]) }
		end
		tracks[tonumber(uid)] = keys
	end
	SA.tracks = tracks
	-- procedural motion of objects: { [uid] = settings } (sv_saeditor.lua, SA.CleanProc)
	local proc = {}
	for uid, pr in pairs(istable(t.proc) and t.proc or {}) do proc[tonumber(uid)] = pr end
	SA.proc = proc
	if SA.ReceiveSounds then SA.ReceiveSounds(t.sounds) end
	-- camera cuts: { { f, uid }, … } in frame order (cl_saeditor_cuts.lua)
	local cuts = {}
	for _, c in ipairs(istable(t.cuts) and t.cuts or {}) do
		if tonumber(c.f) and tonumber(c.uid) then cuts[#cuts + 1] = { f = tonumber(c.f), uid = tonumber(c.uid) } end
	end
	table.sort(cuts, function(a, b) return a.f < b.f end)
	SA.cuts = cuts
	SA.frame = math.min(SA.frame, SA.frames)
	hook.Run("SAeditor_Changed")
end)

local seekWaiters = {}
COMP:NetReceive("Frame", function()
	local frame   = net.ReadFloat()
	local playing = net.ReadBool()
	local serial  = net.ReadUInt(16)
	if serial ~= 0 then
		local cb = seekWaiters[serial]
		seekWaiters[serial] = nil
		if cb then cb(frame) end
		return
	end
	SA.playing = playing
	SA.frame = frame
	if playing then SA.playT0, SA.playF0 = RealTime(), frame end
end)

function SA.Sync()
	COMP:NetStart("Sync")
	net.SendToServer()
end

-- the time of the scene for the editor (camera shake is a function of it)
COMP:Hook("SPeditor_SceneTime", function() return SA.frame / math.max(SA.fps, 1) end, "time")

COMP:Hook("SPeditor_StateChanged", function(on)
	SA.playing = false
	if on then SA.Sync() end
end)

---------------------------------------------------------------------
-- Playhead and playback
---------------------------------------------------------------------
local seekSerial = 0

-- onDone(frame) is called when the server has confirmed that the scene stands on the frame
function SA.Seek(frame, onDone)
	frame = math.Clamp(frame, 0, SA.frames)
	SA.frame, SA.playing = frame, false
	local serial = 0
	if onDone then
		seekSerial = seekSerial % 65000 + 1
		serial = seekSerial
		seekWaiters[serial] = onDone
	end
	local function send()
		COMP:NetStart("Seek")
		net.WriteFloat(frame)
		net.WriteUInt(serial, 16)
		net.SendToServer()
	end
	-- dragging the playhead: no more often than the editor's shared queue; with a confirmation — at once
	if onDone then send() else C.Queue("sa_seek", send) end
end

function SA.Play(on)
	if on == nil then on = not SA.playing end
	if on and SA.frame >= SA.frames then SA.frame = 0 end
	SA.playing = on
	SA.playT0, SA.playF0 = RealTime(), SA.frame
	COMP:NetStart("Play")
	net.WriteBool(on)
	net.WriteFloat(SA.frame)
	net.SendToServer()
end

-- During playback the playhead runs on its own clock (the server plays on its own;
-- a difference of a fraction of a frame does not matter); the server reports the stop.
COMP:Hook("Think", function()
	if not SA.playing or not (C.active or SA.show) then return end
	local f = SA.playF0 + (RealTime() - SA.playT0) * SA.fps
	if f >= SA.frames then
		local loop = SA.loop
		if SA.show then loop = GetConVar("saeditor_show_loop"):GetBool() end
		if loop then
			SA.playT0, SA.playF0 = RealTime(), 0
			f = 0
		else
			f = SA.frames
		end
	end
	SA.frame = f
end, "playhead")

function SA.SetConfig(fps, frames, loop)
	SA.fps    = math.Clamp(math.floor(fps or SA.fps), 1, 120)
	SA.frames = math.Clamp(math.floor(frames or SA.frames), 1, SA.MAX_FRAMES)
	if loop ~= nil then SA.loop = loop and true or false end
	COMP:NetStart("Config")
	net.WriteUInt(SA.fps, 8)
	net.WriteUInt(SA.frames, 32)
	net.WriteBool(SA.loop)
	net.SendToServer()
end

-- the nearest key on the left (dir = -1) or right (dir = 1) among the tracks uids (or all)
function SA.NeighbourKey(dir, uids)
	local cur = math.floor(SA.frame + 0.5)
	local best
	for uid, keys in pairs(SA.tracks) do
		if not uids or uids[uid] then
			for _, k in ipairs(keys) do
				if dir < 0 and k.f < cur and (not best or k.f > best) then best = k.f end
				if dir > 0 and k.f > cur and (not best or k.f < best) then best = k.f end
			end
		end
	end
	return best
end

---------------------------------------------------------------------
-- Keys. Every edit is one entry of the editor's history: undo asks the server
-- to bring the tracks back to what they were before the operation with this number.
---------------------------------------------------------------------
local function pushHistory(label, id)
	C.PushHistory(label, function()
		COMP:NetStart("Restore") net.WriteUInt(id, 32) net.WriteBool(false) net.SendToServer()
	end, function()
		COMP:NetStart("Restore") net.WriteUInt(id, 32) net.WriteBool(true) net.SendToServer()
	end)
end

local function sendKey(id, action, uid, frame, arg, str)
	COMP:NetStart("Key")
	net.WriteUInt(id, 32)
	net.WriteUInt(action, 4)
	net.WriteUInt(uid or 0, 32)
	net.WriteInt(frame or 0, 32)
	net.WriteInt(arg or 0, 32)
	net.WriteString(str or "")
	net.SendToServer()
end

-- The Motion Editor's time selection (a0.7, SA.TimeSelWeight): nil, or { a0, a1, b0, b1, shape }.
-- While it holds the frame, a key (K, auto key) puts the edit over the whole selection.
SA.timeSel = SA.timeSel or nil

function SA.SetTimeSel(t)
	if t then
		table.sort(t)
		for i = 1, 4 do t[i] = math.Clamp(math.floor(t[i] + 0.5), 0, SA.frames) end
		t.shape = t.shape or (SA.timeSel and SA.timeSel.shape) or "smooth"
		if t[4] <= t[1] then t = nil end
	end
	SA.timeSel = t
	hook.Run("SAeditor_TimeSelChanged", t)
end

-- the selection that an edit at frame goes over (nil: a plain key)
local function motionSel(frame)
	local t = SA.timeSel
	if t and frame >= t[1] and frame <= t[4] and t[4] > t[1] then return t end
end
SA.MotionSel = motionSel

-- ents — list of objects (the selection by default), frame — the current one by default;
-- parts — a bone key of these parts ("p3,b14", SA.BoneParts) for every object of the list
function SA.SetKey(ents, frame, quiet, parts)
	-- K with the bone keys on and a bone selected: a key of that bone
	if not ents and not parts and SA.BoneKeysOn() then
		parts = SA.BoneParts(C.selected, C.selBone)
		if parts then ents = { C.selected } end
	end
	ents = ents or C.SelectionList()
	if #ents == 0 then
		if not quiet then SPeditor.Notify("#sa_need_sel", 0) end
		return
	end
	frame = math.floor((frame or SA.frame) + 0.5)
	-- unsent edits (sliders go through the queue) must reach the server before the key
	C.FlushQueue()
	local id = nextOp()
	local ts = motionSel(frame)
	for _, e in ipairs(ents) do
		local uid = SA.UID(e)
		if uid ~= 0 and ts and not parts then
			sendKey(id, OP.MOTION, uid, frame, 0, SA.TimeSelString(ts))
		elseif uid ~= 0 then
			sendKey(id, OP.SET, uid, frame, 0, parts and ("parts:" .. parts) or nil)
		end
	end
	pushHistory("sa key", id)
	if ts and not parts then
		if not quiet then SPeditor.Notify("#sa_motion_set|" .. ts[1] .. "|" .. ts[4], 3) end
		return
	end
	if not quiet then SPeditor.Notify(parts and ("#sa_bone_key_set|" .. frame) or ("#sa_key_set|" .. frame), 3) end
end

-- A key of the face only (Shift+K). The first one starts the object's face track: from then
-- on its face is animated by these keys alone, and the body keys leave the face as it is —
-- the face can get its own rhythm (a blink, a line of speech) over a slow body motion.
function SA.SetFaceKey(ents, frame, quiet)
	ents = ents or C.SelectionList()
	local list = {}
	for _, e in ipairs(ents) do
		if IsValid(e) and not C.IsAux(e) and e:GetFlexNum() > 0 then list[#list + 1] = e end
	end
	if #list == 0 then
		if not quiet then SPeditor.Notify("#sa_need_face", 0) end
		return
	end
	frame = math.floor((frame or SA.frame) + 0.5)
	C.FlushQueue()
	local id = nextOp()
	local ts = motionSel(frame)
	for _, e in ipairs(list) do
		local uid = SA.UID(e)
		if uid ~= 0 and ts then
			sendKey(id, OP.MOTION, SA.FaceTrack(uid), frame, 0, SA.TimeSelString(ts))
		elseif uid ~= 0 then
			sendKey(id, OP.SET, SA.FaceTrack(uid), frame)
		end
	end
	pushHistory("sa face key", id)
	if not quiet then SPeditor.Notify("#sa_face_key_set|" .. frame, 3) end
end

function SA.HasFaceTrack(ent)
	return SA.tracks[SA.FaceTrack(SA.UID(ent))] ~= nil
end

-- Play an effect object from the frame `frame` (the current one by default). The moment of
-- an effect is a keyed property: a key with the moment 0 at the start and a key with the
-- moment N seconds N seconds later make it run at its own speed. seconds = nil — until the
-- end of the timeline; with a number the effect is switched off one frame after it has
-- played for that long, so that it can be played again later.
function SA.PlayEffect(ent, seconds, frame)
	if not C.IsEffect(ent) then return end
	local uid = SA.UID(ent)
	if uid == 0 then return end
	local f0 = math.Clamp(math.floor((frame or SA.frame) + 0.5), 0, SA.frames - 1)
	local f1 = seconds and math.min(f0 + math.max(math.floor(seconds * SA.fps + 0.5), 1), SA.frames) or SA.frames
	local was = ent:GetFxTime()
	C.FlushQueue()
	local id = nextOp()
	C.SendEffectEdit(ent, { time = 0 }, true, true)
	sendKey(id, OP.SET, uid, f0, 0, "linear")
	C.SendEffectEdit(ent, { time = (f1 - f0) / SA.fps }, true, true)
	sendKey(id, OP.SET, uid, f1, 0, seconds and "hold" or "linear")
	if seconds and f1 < SA.frames then
		C.SendEffectEdit(ent, { time = 0 }, true, true)
		sendKey(id, OP.SET, uid, f1 + 1, 0, "hold")
	end
	C.SendEffectEdit(ent, { time = was }, true, true)
	pushHistory("sa effect", id)
	SA.Seek(SA.frame)
end

-- for the other client files of SAeditor (the curve editor): an operation number, its undo
-- entry and the Key message
SA.NextOp, SA.PushOpHistory, SA.SendKeyOp = nextOp, pushHistory, sendKey

function SA.DeleteKey(uid, frame)
	local id = nextOp()
	sendKey(id, OP.DELETE, uid, frame)
	pushHistory("sa key delete", id)
end

function SA.MoveKey(uid, from, to, copy)
	if from == to then return end
	local id = nextOp()
	sendKey(id, copy and OP.COPY or OP.MOVE, uid, from, to)
	pushHistory(copy and "sa paste" or "sa key move", id)
end

-- Several keys at once (the keys selected on the timeline): list = { { uid, f }, … }. One
-- operation, one entry of the history.
-- A key of the list may stand for a bone only (k.parts = "p3,b14", a row of a bone): then the
-- operation moves or deletes that bone's part of the key and leaves the rest of it.
local function byTrack(list)
	local out = {}
	for _, k in ipairs(list) do
		local id = k.uid .. "|" .. (k.parts or "")
		out[id] = out[id] or { uid = k.uid, parts = k.parts, frames = {} }
		table.insert(out[id].frames, k.f)
	end
	return out
end
local function withParts(g, str) return g.parts and ("parts:" .. g.parts .. "|" .. str) or str end

-- by — frames to move them by; copy — the keys stay where they are and copies are made
function SA.MoveKeys(list, by, copy)
	if by == 0 or #list == 0 then return end
	local id = nextOp()
	for _, g in pairs(byTrack(list)) do
		sendKey(id, OP.SHIFT, g.uid, copy and 1 or 0, by, withParts(g, table.concat(g.frames, ",")))
	end
	pushHistory(copy and "sa paste" or "sa key move", id)
end

function SA.DeleteKeys(list)
	if #list == 0 then return end
	local id = nextOp()
	for _, g in pairs(byTrack(list)) do sendKey(id, OP.DELETE, g.uid, 0, 0, withParts(g, table.concat(g.frames, ","))) end
	pushHistory("sa key delete", id)
end

-- the motion is a property of the whole key, also when it is picked on a bone's row
function SA.SetEaseMany(list, ease)
	if #list == 0 then return end
	local id = nextOp()
	for _, g in pairs(byTrack(list)) do sendKey(id, OP.EASE, g.uid, 0, 0, ease .. "|" .. table.concat(g.frames, ",")) end
	pushHistory("sa ease", id)
end

function SA.SetEase(uid, frame, ease)
	local id = nextOp()
	sendKey(id, OP.EASE, uid, frame, 0, ease)
	pushHistory("sa ease", id)
end

function SA.ClearTrack(uid)
	local id = nextOp()
	sendKey(id, OP.CLEAR, uid)
	pushHistory("sa clear", id)
end

function SA.ClearAll()
	local id = nextOp()
	sendKey(id, OP.CLEAR_ALL)
	pushHistory("sa clear", id)
end

---------------------------------------------------------------------
-- Auto key: any edit of the scene (everything that gets into the editor's history) sets
-- a key for the selected objects at the current frame.
---------------------------------------------------------------------
-- An edit of the face of an object that has a face track sets a face key, not a body key.
local FACE_EDITS = { flex = true, ["face preset"] = true }
-- edits of a camera made from the Render window or while looking through it: the camera may
-- not be selected, and it is keyed all the same
local CAMERA_EDITS = { ["camera fx"] = true, ["camera fov"] = true, ["camera motion"] = true }

COMP:Hook("SPeditor_HistoryPushed", function(label)
	if SA.playing or SA.rendering then return end
	if string.sub(label, 1, 3) == "sa " or label == "spawn" or label == "delete" then return end
	local cam = CAMERA_EDITS[label] and C.lastCameraEdit or nil
	-- without Auto key only the cameras that record their own moves are keyed (C.CameraRecords)
	if not SA.autokey then
		local rec = {}
		for _, e in ipairs(C.SelectionList()) do
			if C.CameraRecords(e) then rec[#rec + 1] = e end
		end
		if C.CameraRecords(cam) and not table.HasValue(rec, cam) then rec[#rec + 1] = cam end
		if #rec > 0 then
			timer.Create("SAeditor.AutoKeyRec", 0.15, 1, function()
				if C.active then SA.SetKey(rec, nil, true) end
			end)
		end
		return
	end
	-- a drag of bones with the bone keys on: a key of the bones that moved (the gizmo tells which)
	local moved = C.lastEditParts
	if not (SA.BoneKeysOn() and moved and RealTime() - moved.t < 0.5 and IsValid(moved.ent) and moved.parts ~= "") then moved = nil end
	timer.Create("SAeditor.AutoKey", 0.15, 1, function()
		if not C.active then return end
		local body, face, seen = {}, {}, {}
		for _, e in ipairs(C.SelectionList()) do
			seen[e] = true
			if moved and e == moved.ent then
				-- keyed by its parts below
			elseif FACE_EDITS[label] and SA.HasFaceTrack(e) then face[#face + 1] = e else body[#body + 1] = e end
		end
		if IsValid(cam) and not seen[cam] then body[#body + 1] = cam end
		if moved and IsValid(moved.ent) then SA.SetKey({ moved.ent }, nil, true, moved.parts) end
		if #body > 0 then SA.SetKey(body, nil, true) end
		if #face > 0 then SA.SetFaceKey(face, nil, true) end
	end)
end, "autokey")

-- Without auto key an edit of an animated object at a frame without a key is lost as soon as
-- the playhead moves (the keys put the object back) — players took it for bones that "won't
-- move". The first few times this happens, the editor says so.
local warned, warnedAt = 0, 0
COMP:Hook("SPeditor_HistoryPushed", function(label)
	if SA.autokey or SA.playing or SA.rendering or warned >= 3 or RealTime() - warnedAt < 90 then return end
	if string.sub(label, 1, 3) == "sa " or label == "spawn" or label == "delete" then return end
	local frame = math.floor(SA.frame + 0.5)
	for _, e in ipairs(C.SelectionList()) do
		local uid = SA.UID(e)
		if SA.tracks[uid] and not SA.HasKey(uid, frame) then
			warned, warnedAt = warned + 1, RealTime()
			SPeditor.Notify("#sa_hint_moved", 0)
			return
		end
	end
end, "unkeyed")

-- Flying a scene camera while looking through it (WASD, the mouse) records it: a key at the
-- current frame once the camera stops. Switching the view to a camera is not a move.
local viewSince = 0
COMP:Hook("SPeditor_ViewChanged", function() viewSince = RealTime() end, "autokey")
COMP:Hook("SPeditor_ViewCameraMoved", function(cam)
	if not (SA.autokey or C.CameraRecords(cam)) or SA.playing or SA.rendering or RealTime() - viewSince < 0.5 then return end
	timer.Create("SAeditor.AutoKeyCam", 0.4, 1, function()
		if C.active and IsValid(cam) and C.GetViewCamera() == cam and not SA.playing then SA.SetKey({ cam }, nil, true) end
	end)
end, "autokey")

-- undo and redo of an edit move the object: with auto key the key at the frame is updated
COMP:Hook("SPeditor_HistoryStep", function(label)
	if SA.playing or string.sub(label, 1, 3) == "sa " then return end
	local frame = math.floor(SA.frame + 0.5)
	local list = {}
	for _, e in ipairs(C.SelectionList()) do
		if (SA.autokey or C.CameraRecords(e)) and SA.HasKey(SA.UID(e), frame) then list[#list + 1] = e end
	end
	if #list > 0 then timer.Create("SAeditor.AutoKey", 0.15, 1, function() SA.SetKey(list, frame, true) end) end
end, "autokey")

---------------------------------------------------------------------
-- Hotkeys and the status bar
---------------------------------------------------------------------
local function step(d) SA.Seek(math.Clamp(math.floor(SA.frame + 0.5) + d, 0, SA.frames)) end

COMP:AddHotkey({ key = KEY_SPACE, fn = function() SA.Play() end, label = "Space", desc = "sa_hk_play" })
COMP:AddHotkey({ key = KEY_K, fn = function() SA.SetKey() end, desc = "sa_hk_key" })
COMP:AddHotkey({ key = KEY_K, shift = true, fn = function() SA.SetFaceKey() end, desc = "sa_hk_face_key" })
COMP:AddHotkey({ key = KEY_COMMA, fn = function() step(-1) end, label = ",", desc = "sa_hk_prev" })
COMP:AddHotkey({ key = KEY_PERIOD, fn = function() step(1) end, label = ".", desc = "sa_hk_next" })
COMP:AddHotkey({ key = KEY_HOME, fn = function() SA.Seek(0) end, label = "Home", desc = "sa_hk_first" })
COMP:AddHotkey({ key = KEY_END, fn = function() SA.Seek(SA.frames) end, label = "End", desc = "sa_hk_last" })

COMP:AddStatus(function()
	if next(SA.tracks) == nil and #(SA.sounds or {}) == 0 and not SA.autokey and not SA.timeSel then return nil end
	local state = COMP:L(SA.playing and "sa_status_play" or "sa_status_stop")
	if SA.autokey then state = state .. "  ·  " .. COMP:L("sa_status_auto") end
	if SA.timeSel then state = state .. "  ·  " .. COMP:L("sa_status_tsel", SA.timeSel[1], SA.timeSel[4]) end
	return COMP:L("sa_status", math.floor(SA.frame + 0.5), SA.frames, state)
end)

---------------------------------------------------------------------
-- Object path: a line through the positions of its keys (in the primary viewport)
---------------------------------------------------------------------
local COL_PATH, COL_KEY, COL_CUR = Color(233, 145, 45, 200), Color(255, 255, 255, 230), Color(255, 90, 60, 255)

COMP:Hook("PostDrawTranslucentRenderables", function(bDepth, bSkybox)
	if bDepth or bSkybox or not C.active or C.hideUI or C.vpPass ~= "primary" then return end
	local keys = SA.tracks[SA.UID(C.selected)]
	if not keys or #keys < 2 then return end
	local restore = SPeditor.Render.HelperLighting()
	local cur = math.floor(SA.frame + 0.5)
	for i, k in ipairs(keys) do
		if keys[i + 1] then render.DrawLine(k.pos, keys[i + 1].pos, COL_PATH, false) end
		render.DrawWireframeSphere(k.pos, 1.2, 4, 4, k.f == cur and COL_CUR or COL_KEY, false)
	end
	restore()
end, "path")

---------------------------------------------------------------------
-- Importing a model animation onto a ragdoll.
-- A ragdoll has no "animations": its pose is the positions of its physics bones. So the
-- animation is played on an invisible copy of the model on the client, and the bone positions
-- from it go to the server frame by frame; the server applies them to the ragdoll and takes a key.
---------------------------------------------------------------------
-- model — take the animations of another model (nil — the character's own). A character
-- has only the animations its model was built with, but any model with the same skeleton
-- can lend its own: a citizen can dance the dance of a player model or of an animation
-- pack made for players.
function SA.SequenceList(ent, model)
	local src, temp = ent, nil
	if model and model ~= "" and model ~= ent:GetModel() then
		temp = ClientsideModel(model, RENDERGROUP_OTHER)
		if not IsValid(temp) then return {} end
		temp:SetNoDraw(true)
		src = temp
	end
	local out = {}
	for id, name in pairs(src:GetSequenceList() or {}) do
		local dur = src:SequenceDuration(id) or 0
		if dur > 0.05 then out[#out + 1] = { id = id, name = name, dur = dur } end
	end
	if temp then temp:Remove() end
	table.sort(out, function(a, b) return a.name < b.name end)
	return out
end

-- opts = { step = a key every N frames, loops = repeats, root = move the character, speed = speed,
--          start = the first frame (the current one by default),
--          pos, yaw = where the character stands and looks (by default — where the ragdoll is),
--          cycle0, cycle1 = the part of the animation to take (0..1),
--          frames = the exact length in timeline frames (instead of speed),
--          params = { pose parameter = value } (aim_yaw, aim_pitch, move_yaw …),
--          model = the model whose animation seq is (by default the character's own): its
--          bones are matched to the character's by name }
-- Returns the number of keys, the last frame, the place and the yaw of the character at the end.
-- A model without physics (prop_dynamic, e.g. a model ported from SFM with no ragdoll): every
-- bone gets the turn it has in the animation relative to the model's base pose as a bone
-- offset; the root bone also gets its shift. The model itself stays where it is.
local function importOnProp(ent, seq, opts)
	opts = opts or {}
	local stepN  = math.Clamp(math.floor(opts.step or 2), 1, 12)
	local loops  = math.Clamp(math.floor(opts.loops or 1), 1, 16)
	local speed  = math.Clamp(opts.speed or 1, 0.1, 4)
	local start  = math.Clamp(math.floor((opts.start or SA.frame) + 0.5), 0, SA.MAX_FRAMES - 1)
	local c0     = math.Clamp(opts.cycle0 or 0, 0, 0.99)
	local c1     = math.Clamp(opts.cycle1 or 1, c0 + 0.01, 1)
	local foreign = opts.model and opts.model ~= "" and opts.model ~= ent:GetModel()
	local function make(model)
		local m = ClientsideModel(model, RENDERGROUP_OTHER)
		if not IsValid(m) then return nil end
		m:SetNoDraw(true)
		m:SetIK(false)
		m:SetPos(ent:GetPos())
		m:SetAngles(ent:GetAngles())
		return m
	end
	local csm, rest = make(foreign and opts.model or ent:GetModel()), make(ent:GetModel())
	if not csm or not rest then
		if csm then csm:Remove() end
		if rest then rest:Remove() end
		return false
	end
	csm:ResetSequence(seq)
	csm:SetPlaybackRate(0)
	if csm:GetPoseParameter("move_x") ~= nil then csm:SetPoseParameter("move_x", 1) end
	for name, value in pairs(opts.params or {}) do csm:SetPoseParameter(name, value) end
	rest:ResetSequence(ent:GetSequence())
	rest:SetCycle(ent:GetCycle())
	rest:SetupBones()

	local dur   = (csm:SequenceDuration(seq) or 1) * (c1 - c0) / speed
	local total = math.max(math.floor(dur * loops * SA.fps + 0.5), 1)
	if opts.frames then total = math.max(math.floor(opts.frames), 1) end
	if start + total > SA.frames then
		total = math.min(total, SA.MAX_FRAMES - start)
		SA.SetConfig(nil, start + total)
		SPeditor.Notify("#sa_imp_extend", 0)
	end
	local function copyBone(b)
		if not foreign then return b end
		local cb = csm:LookupBone(ent:GetBoneName(b) or "")
		return cb
	end
	local epos, eang = ent:GetPos(), ent:GetAngles()
	local function localOf(m, b, pb)
		local mb = m:GetBoneMatrix(b)
		if not mb then return nil end
		if pb then
			local mp = m:GetBoneMatrix(pb)
			if not mp then return nil end
			return WorldToLocal(mb:GetTranslation(), mb:GetAngles(), mp:GetTranslation(), mp:GetAngles())
		end
		return WorldToLocal(mb:GetTranslation(), mb:GetAngles(), epos, eang)
	end
	local bones = {}
	for b = 0, math.min(ent:GetBoneCount(), 255) - 1 do
		local par = ent:GetBoneParent(b)
		local cb = copyBone(b)
		local cp = par and par >= 0 and copyBone(par) or nil
		if cb and (par < 0 or cp) then
			local rp, ra = localOf(rest, b, par >= 0 and par or nil)
			if rp then bones[#bones + 1] = { bone = b, cb = cb, cp = cp, root = par < 0, rp = rp, ra = ra } end
		end
	end
	if #bones < 2 then
		csm:Remove() rest:Remove()
		SPeditor.Notify("#sa_imp_skeleton", 1)
		return false
	end

	local id = nextOp()
	local count = 0
	local frames = {}
	for f = 0, total, stepN do frames[#frames + 1] = f end
	if frames[#frames] ~= total then frames[#frames + 1] = total end
	for i, f in ipairs(frames) do
		local t = (f / total) * loops
		local part = t % 1
		if i == #frames and part == 0 then part = 0.9999 end
		csm:SetCycle(math.min(c0 + part * (c1 - c0), 0.9999))
		csm:InvalidateBoneCache()
		csm:SetupBones()
		COMP:NetStart("Bake")
		net.WriteUInt(id, 32)
		net.WriteEntity(ent)
		net.WriteUInt(math.min(start + f, SA.MAX_FRAMES), 32)
		net.WriteUInt(0, 8)                     -- no physical bones
		net.WriteUInt(#bones, 16)
		local shifts = {}
		for _, bd in ipairs(bones) do
			local ap, aa = localOf(csm, bd.cb, bd.cp)
			local d = angle_zero
			if ap then
				local _, dd = WorldToLocal(vector_origin, aa, vector_origin, bd.ra)
				d = dd
				-- the root bone also moves (a model has no physics to carry it)
				if bd.root then shifts[#shifts + 1] = { bd.bone, ap - bd.rp } end
			end
			net.WriteUInt(bd.bone, 16)
			SPeditor.WriteAngF(d)
		end
		net.WriteBool(i == #frames)
		net.WriteUInt(#shifts, 8)
		for _, sh in ipairs(shifts) do
			net.WriteUInt(sh[1], 16)
			SPeditor.WriteVecF(sh[2])
		end
		net.SendToServer()
		count = count + 1
	end
	csm:Remove()
	rest:Remove()
	pushHistory("sa import", id)
	return count, start + total, ent:GetPos(), ent:GetAngles().y
end

function SA.ImportSequence(ent, seq, opts)
	if IsValid(ent) and not C.IsRagdoll(ent) and not C.IsAux(ent) and (ent:GetBoneCount() or 0) > 1 then
		return importOnProp(ent, seq, opts)
	end
	if not C.IsRagdoll(ent) then
		SPeditor.Notify("#sa_need_ragdoll", 0)
		return false
	end
	opts = opts or {}
	local stepN  = math.Clamp(math.floor(opts.step or 2), 1, 12)
	local loops  = math.Clamp(math.floor(opts.loops or 1), 1, 16)
	local speed  = math.Clamp(opts.speed or 1, 0.1, 4)
	local start  = math.Clamp(math.floor((opts.start or SA.frame) + 0.5), 0, SA.MAX_FRAMES - 1)
	local c0     = math.Clamp(opts.cycle0 or 0, 0, 0.99)
	local c1     = math.Clamp(opts.cycle1 or 1, c0 + 0.01, 1)

	local foreign = opts.model and opts.model ~= "" and opts.model ~= ent:GetModel()
	local csm = ClientsideModel(foreign and opts.model or ent:GetModel(), RENDERGROUP_OTHER)
	if not IsValid(csm) then return false end
	csm:SetNoDraw(true)
	-- No leg IK: the copy is posed at the map origin first and only then put in its place,
	-- and the engine keeps pulling the feet to the floor height it found there — aiming and
	-- crouching animations (they have foot rules) came out with the legs lifted into the air.
	csm:SetIK(false)
	csm:ResetSequence(seq)
	csm:SetPlaybackRate(0)
	-- walk and run animations are blended from nine directions; without this parameter you get a "stance"
	if csm:GetPoseParameter("move_x") ~= nil then csm:SetPoseParameter("move_x", 1) end
	for name, value in pairs(opts.params or {}) do csm:SetPoseParameter(name, value) end

	local dur    = (csm:SequenceDuration(seq) or 1) * (c1 - c0) / speed
	local total  = math.max(math.floor(dur * loops * SA.fps + 0.5), 1)      -- timeline frames for the whole animation
	if opts.frames then total = math.max(math.floor(opts.frames), 1) end   -- an exact length: the animation is stretched over it
	-- the animation does not fit the timeline — it is lengthened (the server clips keys by the length)
	if start + total > SA.frames then
		total = math.min(total, SA.MAX_FRAMES - start)
		SA.SetConfig(nil, start + total)
		SPeditor.Notify("#sa_imp_extend", 0)
	end
	-- the bone of the animated copy for a bone of the character: the same number in its own
	-- model, the bone with the same name in another one
	local function copyBone(b)
		if not foreign then return b end
		return csm:LookupBone(ent:GetBoneName(b) or "")
	end
	local phys   = {}
	for b = 0, ent:GetBoneCount() - 1 do
		local pi = C.PhysIndexOfBone(ent, b)
		local cb = pi and copyBone(b)
		if cb then phys[#phys + 1] = { pi = pi, bone = cb } end
	end
	local rootBone = copyBone(ent:TranslatePhysBoneToBone(0))
	-- another skeleton: nothing to move the character with
	if not rootBone or #phys < 3 then
		csm:Remove()
		SPeditor.Notify("#sa_imp_skeleton", 1)
		return false
	end

	-- Bones without a physics object (fingers, toes, clavicles) are not moved by the physics
	-- pose: the ragdoll draws them in their rest place relative to the parent bone. Their turn
	-- relative to the parent in the animation becomes a bone offset (manip angles) on top of that
	-- rest place. The rest place is taken from a copy of the character in its own sequence.
	--
	-- Only bones with no physical bone below them (fingers, toes). The ragdoll puts a physical
	-- bone at its physical parent's place plus the rest-pose offset, whatever the bones between
	-- them do: turning the spine top and the neck (or a clavicle) moved the end of the neck away
	-- from the head by 1.5 units and the shoulder away from the upper arm by 2 — the neck looked
	-- broken. The head and the upper arm still turn as in the animation: they are physical.
	local physBelow = {}
	for b = 0, ent:GetBoneCount() - 1 do
		if C.PhysIndexOfBone(ent, b) then
			local p = ent:GetBoneParent(b)
			while p and p >= 0 and not physBelow[p] do
				physBelow[p] = true
				p = ent:GetBoneParent(p)
			end
		end
	end
	local soft = {}
	local rest = ClientsideModel(ent:GetModel(), RENDERGROUP_OTHER)
	if IsValid(rest) then
		rest:SetNoDraw(true)
		rest:SetIK(false)
		rest:ResetSequence(ent:GetSequence())
		rest:SetCycle(ent:GetCycle())
		rest:SetupBones()
		for b = 0, math.min(ent:GetBoneCount(), 65535) - 1 do
			local par = ent:GetBoneParent(b)
			local cb, cp = copyBone(b), par and par >= 0 and copyBone(par)
			if not C.PhysIndexOfBone(ent, b) and not physBelow[b] and cb and cp then
				local mb, mp = rest:GetBoneMatrix(b), rest:GetBoneMatrix(par)
				if mb and mp then
					local _, restLocal = WorldToLocal(vector_origin, mb:GetAngles(), vector_origin, mp:GetAngles())
					soft[#soft + 1] = { bone = b, cb = cb, cp = cp, rest = restLocal }
				end
			end
		end
		rest:Remove()
	end
	local function softAngle(s)
		local mb, mp = csm:GetBoneMatrix(s.cb), csm:GetBoneMatrix(s.cp)
		if not mb or not mp then return angle_zero end
		local _, animLocal = WorldToLocal(vector_origin, mb:GetAngles(), vector_origin, mp:GetAngles())
		local _, d = WorldToLocal(vector_origin, animLocal, vector_origin, s.rest)
		-- tiny differences stay zero: the key then has no entry for the bone
		if math.abs(d.p) < 0.05 and math.abs(d.y) < 0.05 and math.abs(d.r) < 0.05 then return angle_zero end
		return d
	end

	local function pose(part)
		csm:SetCycle(math.min(c0 + part * (c1 - c0), 0.9999))
		csm:InvalidateBoneCache()
		csm:SetupBones()
	end

	-- the copy is put on the floor under the character and turned the way the character stands
	local rp, ra = C.GetEntityTransform(ent)
	if opts.pos then rp = opts.pos + Vector(0, 0, 48) end
	local tr = util.TraceLine({ start = rp, endpos = rp - Vector(0, 0, 4096), mask = MASK_SOLID_BRUSHONLY })
	local ground = tr.Hit and tr.HitPos or (rp - Vector(0, 0, 36))
	csm:SetPos(vector_origin)
	csm:SetAngles(angle_zero)
	pose(0)
	local yaw = 0
	local m0 = csm:GetBoneMatrix(rootBone)
	if opts.yaw then
		yaw = opts.yaw
	elseif m0 then
		local a0 = m0:GetAngles()
		-- the pelvis bone axis that lies closest to horizontal is compared between the copy and the character
		local best, bestLen
		for _, axis in ipairs({ "Forward", "Right", "Up" }) do
			local v = a0[axis](a0)
			local len = Vector(v.x, v.y, 0):Length()
			if not best or len > bestLen then best, bestLen = axis, len end
		end
		local v0, v1 = a0[best](a0), ra[best](ra)
		if Vector(v1.x, v1.y, 0):Length() > 0.3 then
			yaw = math.deg(math.atan2(v1.y, v1.x) - math.atan2(v0.y, v0.x))
		end
	end
	local baseAng = Angle(0, yaw, 0)
	csm:SetAngles(baseAng)
	pose(0)
	m0 = csm:GetBoneMatrix(rootBone)
	local off = m0 and m0:GetTranslation() or vector_origin
	if opts.pos then off = vector_origin end        -- an explicit place is where the feet stand
	local basePos = Vector(rp.x - off.x, rp.y - off.y, ground.z)

	-- offset of the character over one full animation cycle (none if it "walks in place")
	local cycleMove = vector_origin
	if opts.root then
		local ok, delta = csm:GetSequenceMovement(seq, c0, c1)
		if ok and delta then cycleMove = delta end
	end

	local id = nextOp()
	local count = 0
	local endPos = basePos
	local frames = {}
	for f = 0, total, stepN do frames[#frames + 1] = f end
	if frames[#frames] ~= total then frames[#frames + 1] = total end

	for i, f in ipairs(frames) do
		local t = (f / total) * loops                    -- how many cycles have passed
		local whole, part = math.floor(t), t % 1
		if i == #frames and part == 0 then whole, part = loops - 1, 0.9999 end
		local move = cycleMove * whole
		if opts.root and part > 0 then
			local ok, delta = csm:GetSequenceMovement(seq, c0, c0 + part * (c1 - c0))
			if ok and delta then move = move + delta end
		end
		move:Rotate(baseAng)
		endPos = basePos + move
		csm:SetPos(endPos)
		pose(part)

		COMP:NetStart("Bake")
		net.WriteUInt(id, 32)
		net.WriteEntity(ent)
		net.WriteUInt(math.min(start + f, SA.MAX_FRAMES), 32)
		net.WriteUInt(#phys, 8)
		for _, p in ipairs(phys) do
			local m = csm:GetBoneMatrix(p.bone)
			net.WriteUInt(p.pi, 8)
			SPeditor.WriteVecF(m and m:GetTranslation() or basePos)
			SPeditor.WriteAngF(m and m:GetAngles() or angle_zero)
		end
		net.WriteUInt(#soft, 16)
		for _, s in ipairs(soft) do
			net.WriteUInt(s.bone, 16)
			SPeditor.WriteAngF(softAngle(s))
		end
		net.WriteBool(i == #frames)
		net.WriteUInt(0, 8)                     -- no bone shifts (the bodies carry the bones)
		net.SendToServer()
		count = count + 1
	end
	csm:Remove()
	pushHistory("sa import", id)
	return count, start + total, endPos, yaw
end
