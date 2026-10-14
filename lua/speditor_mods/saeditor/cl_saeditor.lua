--[[
SAeditor — client: timeline state, commands to the server, auto key, hotkeys,
model animation import. The interface is cl_saeditor_ui.lua, rendering is cl_saeditor_video.lua,
sounds and voices are cl_saeditor_sound.lua.

  SA.frame            the current frame (fractional during playback)
  SA.tracks[uid]      table of contents of a track: { { f = frame, e = easing, pos = Vector }, … }
  SA.Seek(frame)  SA.Play(on)  SA.SetKey(ents)  SA.DeleteKey(uid, frame)  SA.MoveKey(…)
  SA.ImportSequence(ent, seq, opts)      SA.RenderSequence(opts)
]]
local MOD = SPeditor.Mod("saeditor")
local SA  = MOD.SA
local C   = SPeditor.Client
local OP  = SA.OP

SA.fps     = SA.fps or 24
SA.frames  = SA.frames or 96
SA.frame   = SA.frame or 0
SA.tracks  = SA.tracks or {}
SA.playing = SA.playing or false
if SA.loop == nil then SA.loop = true end
if SA.autokey == nil then SA.autokey = false end

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

function SA.HasKey(uid, frame)
	for _, k in ipairs(SA.tracks[uid] or {}) do
		if k.f == frame then return k end
	end
end

---------------------------------------------------------------------
-- Server -> client
---------------------------------------------------------------------
MOD:NetReceive("Summary", function()
	local t = SPeditor.ReadTable() or {}
	SA.fps    = tonumber(t.fps) or 24
	SA.frames = tonumber(t.frames) or 96
	SA.loop   = t.loop and true or false
	local tracks = {}
	for uid, list in pairs(istable(t.tracks) and t.tracks or {}) do
		local keys = {}
		for i, k in ipairs(list) do
			keys[i] = { f = k[1], e = k[2], pos = Vector(k[3] or 0, k[4] or 0, k[5] or 0) }
		end
		tracks[tonumber(uid)] = keys
	end
	SA.tracks = tracks
	if SA.ReceiveSounds then SA.ReceiveSounds(t.sounds) end
	SA.frame = math.min(SA.frame, SA.frames)
	hook.Run("SAeditor_Changed")
end)

local seekWaiters = {}
MOD:NetReceive("Frame", function()
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
	MOD:NetStart("Sync")
	net.SendToServer()
end

-- the time of the scene for the editor (camera shake is a function of it)
MOD:Hook("SPeditor_SceneTime", function() return SA.frame / math.max(SA.fps, 1) end, "time")

MOD:Hook("SPeditor_StateChanged", function(on)
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
		MOD:NetStart("Seek")
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
	MOD:NetStart("Play")
	net.WriteBool(on)
	net.WriteFloat(SA.frame)
	net.SendToServer()
end

-- During playback the playhead runs on its own clock (the server plays on its own;
-- a difference of a fraction of a frame does not matter); the server reports the stop.
MOD:Hook("Think", function()
	if not SA.playing or not C.active then return end
	local f = SA.playF0 + (RealTime() - SA.playT0) * SA.fps
	if f >= SA.frames then
		if SA.loop then
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
	MOD:NetStart("Config")
	net.WriteUInt(SA.fps, 8)
	net.WriteUInt(SA.frames, 16)
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
		MOD:NetStart("Restore") net.WriteUInt(id, 32) net.WriteBool(false) net.SendToServer()
	end, function()
		MOD:NetStart("Restore") net.WriteUInt(id, 32) net.WriteBool(true) net.SendToServer()
	end)
end

local function sendKey(id, action, uid, frame, arg, str)
	MOD:NetStart("Key")
	net.WriteUInt(id, 32)
	net.WriteUInt(action, 4)
	net.WriteUInt(uid or 0, 32)
	net.WriteInt(frame or 0, 16)
	net.WriteInt(arg or 0, 16)
	net.WriteString(str or "")
	net.SendToServer()
end

-- ents — list of objects (the selection by default), frame — the current one by default
function SA.SetKey(ents, frame, quiet)
	ents = ents or C.SelectionList()
	if #ents == 0 then
		if not quiet then SPeditor.Notify("#sa_need_sel", 0) end
		return
	end
	frame = math.floor((frame or SA.frame) + 0.5)
	-- unsent edits (sliders go through the queue) must reach the server before the key
	C.FlushQueue()
	local id = nextOp()
	for _, e in ipairs(ents) do
		local uid = SA.UID(e)
		if uid ~= 0 then sendKey(id, OP.SET, uid, frame) end
	end
	pushHistory("sa key", id)
	if not quiet then SPeditor.Notify("#sa_key_set|" .. frame, 3) end
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
MOD:Hook("SPeditor_HistoryPushed", function(label)
	if not SA.autokey or SA.playing or SA.rendering then return end
	if string.sub(label, 1, 3) == "sa " or label == "spawn" or label == "delete" then return end
	timer.Create("SAeditor.AutoKey", 0.15, 1, function()
		if C.active and #C.SelectionList() > 0 then SA.SetKey(nil, nil, true) end
	end)
end, "autokey")

-- undo and redo of an edit move the object: with auto key the key at the frame is updated
MOD:Hook("SPeditor_HistoryStep", function(label)
	if not SA.autokey or SA.playing or string.sub(label, 1, 3) == "sa " then return end
	local frame = math.floor(SA.frame + 0.5)
	local list = {}
	for _, e in ipairs(C.SelectionList()) do
		if SA.HasKey(SA.UID(e), frame) then list[#list + 1] = e end
	end
	if #list > 0 then timer.Create("SAeditor.AutoKey", 0.15, 1, function() SA.SetKey(list, frame, true) end) end
end, "autokey")

---------------------------------------------------------------------
-- Hotkeys and the status bar
---------------------------------------------------------------------
local function step(d) SA.Seek(math.Clamp(math.floor(SA.frame + 0.5) + d, 0, SA.frames)) end

MOD:AddHotkey({ key = KEY_SPACE, fn = function() SA.Play() end, label = "Space", desc = "sa_hk_play" })
MOD:AddHotkey({ key = KEY_K, fn = function() SA.SetKey() end, desc = "sa_hk_key" })
MOD:AddHotkey({ key = KEY_COMMA, fn = function() step(-1) end, label = ",", desc = "sa_hk_prev" })
MOD:AddHotkey({ key = KEY_PERIOD, fn = function() step(1) end, label = ".", desc = "sa_hk_next" })
MOD:AddHotkey({ key = KEY_HOME, fn = function() SA.Seek(0) end, label = "Home", desc = "sa_hk_first" })
MOD:AddHotkey({ key = KEY_END, fn = function() SA.Seek(SA.frames) end, label = "End", desc = "sa_hk_last" })

MOD:AddStatus(function()
	if next(SA.tracks) == nil and #(SA.sounds or {}) == 0 and not SA.autokey then return nil end
	local state = MOD:L(SA.playing and "sa_status_play" or "sa_status_stop")
	if SA.autokey then state = state .. "  ·  " .. MOD:L("sa_status_auto") end
	return MOD:L("sa_status", math.floor(SA.frame + 0.5), SA.frames, state)
end)

---------------------------------------------------------------------
-- Object path: a line through the positions of its keys (in the primary viewport)
---------------------------------------------------------------------
local COL_PATH, COL_KEY, COL_CUR = Color(233, 145, 45, 200), Color(255, 255, 255, 230), Color(255, 90, 60, 255)

MOD:Hook("PostDrawTranslucentRenderables", function(bDepth, bSkybox)
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
function SA.ImportSequence(ent, seq, opts)
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
			if not C.PhysIndexOfBone(ent, b) and cb and cp then
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

		MOD:NetStart("Bake")
		net.WriteUInt(id, 32)
		net.WriteEntity(ent)
		net.WriteUInt(math.min(start + f, 65535), 16)
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
		net.SendToServer()
		count = count + 1
	end
	csm:Remove()
	pushHistory("sa import", id)
	return count, start + total, endPos, yaw
end
