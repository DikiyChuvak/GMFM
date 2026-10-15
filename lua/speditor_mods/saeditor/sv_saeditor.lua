--[[
SAeditor — server.

The animation is stored on the server, next to the objects it moves:
  A[ply] = { fps, frames, loop, cur, playing, tracks = { [uid] = track }, sounds = { clip, … } }
  track  = { keys = { [frame] = key }, order = { frames in ascending order } }
  key    = { e = "ease" | "linear" | "ease_in" | "ease_out" | "hold", st = object snapshot }
A key is a full snapshot of an object (position, pose, face, light, camera angle, the moment
of an effect) at a frame. A face track (id = UID + SA.FACE, sh_saeditor.lua) keys only the
flexes of its object; while it exists, the face part of the body keys is left out; between keys the state is interpolated. A key never changes after it is created
(an edit replaces it with a new one), so a copy of a track for undo is just a new
table with references to the same keys.

Why the server: a ragdoll pose (physics bones) can only be set there, and
during playback the state has to be set every tick — sending it over the network
from the client would be both slow and uneven. The client only gets a "table of contents"
(which frames have keys) for the timeline.

Sound clips (SA.CleanSound in sh_saeditor.lua) are played and mixed by the client; the
server only keeps the list, so that it is saved with the scene.
]]
local MOD = SPeditor.Mod("saeditor")
local SA  = MOD.SA
local S   = SPeditor.Server
local OP  = SA.OP

SA.Data = SA.Data or {}      -- [ply] = animation
SA.Ops  = SA.Ops or {}       -- [ply] = { [operation id] = { before = {[uid]=track|false}, after = {…} }, order = {…} }
local A = SA.Data

local ONE = Vector(1, 1, 1)
local MAX_OPS = 60

local function anim(ply)
	local a = A[ply]
	if not a then
		a = { fps = 24, frames = 96, loop = true, cur = 0, playing = false, tracks = {}, sounds = {} }
		A[ply] = a
	end
	return a
end
SA.Anim = anim

---------------------------------------------------------------------
-- Object snapshot
---------------------------------------------------------------------
local function capture(ent)
	if S.IsLight(ent) then
		local c = ent:GetLightColor()
		local st = {
			kind = "light", pos = ent:GetPos(), ang = ent:GetAngles(), col = Vector(c.x, c.y, c.z),
			radius = ent:GetLightRadius(), bri = ent:GetLightBrightness(), fov = ent:GetLightFOV(),
			on = ent:GetLightEnabled(), f = {},
		}
		for _, f in ipairs(SPeditor.LightFields) do st.f[f.key] = ent["Get" .. f.nw](ent) end
		return st
	end
	if S.IsCamera(ent) then
		-- the shake is keyed (a jolt at an explosion); the smoothness is a property of the
		-- whole path and is not
		return { kind = "camera", pos = ent:GetPos(), ang = ent:GetAngles(), fov = ent:GetCameraFOV(),
			shake = ent:GetShakeAmp(), shakerot = ent:GetShakeRot(), shakefreq = ent:GetShakeFreq() }
	end
	if S.IsEffect(ent) then
		-- the moment of the effect is its only animated property besides the place: two keys
		-- with moments 0 and N seconds, N seconds apart, play the effect at its own speed
		return { kind = "effect", pos = ent:GetPos(), ang = ent:GetAngles(), time = ent:GetFxTime(),
			scale = ent:GetFxScale(), length = ent:GetFxLength() }
	end

	local pos, ang = S.GetTransform(ent)
	local st = { kind = "prop", pos = Vector(pos), ang = Angle(ang), bones = {}, flex = {} }
	if S.IsRagdoll(ent) then
		st.phys = {}
		for i = 1, ent:GetPhysicsObjectCount() - 1 do
			local p = ent:GetPhysicsObjectNum(i)
			if IsValid(p) then
				local lp, la = WorldToLocal(p:GetPos(), p:GetAngles(), pos, ang)
				st.phys[i] = { p = lp, a = la }
			end
		end
	else
		st.scale = ent:GetModelScale() or 1
	end
	for b = 0, ent:GetBoneCount() - 1 do
		local mp, ma, ms = ent:GetManipulateBonePosition(b), ent:GetManipulateBoneAngles(b), ent:GetManipulateBoneScale(b)
		if mp ~= vector_origin or ma ~= angle_zero or ms ~= ONE then
			st.bones[b] = { p = Vector(mp), a = Angle(ma), s = Vector(ms) }
		end
	end
	for i = 0, ent:GetFlexNum() - 1 do
		local w = ent:GetFlexWeight(i)
		if math.abs(w) > 0.001 then st.flex[i] = w end
	end
	local c = ent:GetColor()
	st.col = { c.r, c.g, c.b, c.a }
	-- skin and bodygroups switch at a key (a helmet put on, a changed face texture)
	st.skin = ent:GetSkin()
	st.bg = {}
	for i = 0, ent:GetNumBodyGroups() - 1 do st.bg[i] = ent:GetBodygroup(i) end
	return st
end

-- a snapshot of the face only (a key of a face track)
local function captureFace(ent)
	local pos, ang = S.GetTransform(ent)
	local st = { kind = "face", pos = Vector(pos), ang = Angle(ang), flex = {} }
	for i = 0, ent:GetFlexNum() - 1 do
		local w = ent:GetFlexWeight(i)
		if math.abs(w) > 0.001 then st.flex[i] = w end
	end
	return st
end

---------------------------------------------------------------------
-- State between two snapshots -> object. u = 0..1 (easing already applied)
---------------------------------------------------------------------
local lerpN, slerp = SA.LerpNum, SA.SlerpAngle

local function lerpV(a, b, u) return a + (b - a) * u end

local function setPhys(p, pos, ang)
	if not IsValid(p) or not SPeditor.ValidVec(pos) or not SPeditor.ValidAng(ang) then return end
	p:EnableMotion(false)
	p:SetPos(pos)
	p:SetAngles(ang)
	p:Wake()
end

local ZERO_BONE = { p = vector_origin, a = angle_zero, s = ONE }

-- the face between two snapshots (both of a body key and of a face key). whole = true (a face
-- track): the track owns the whole face, so a flex missing from both keys goes back to zero
-- (a snapshot keeps only the flexes that are not zero)
local function applyFlex(ent, a, b, u, whole)
	local nf = ent:GetFlexNum()
	local fa, fb = a.flex or {}, b.flex or {}
	if whole then
		for id = 0, nf - 1 do
			local w = SA.LerpNum(fa[id] or 0, fb[id] or 0, u)
			if ent:GetFlexWeight(id) ~= w then ent:SetFlexWeight(id, w) end
		end
		return
	end
	for id, wa in pairs(fa) do
		if id < nf then ent:SetFlexWeight(id, SA.LerpNum(wa, fb[id] or 0, u)) end
	end
	for id, wb in pairs(fb) do
		if not fa[id] and id < nf then ent:SetFlexWeight(id, SA.LerpNum(0, wb, u)) end
	end
end

-- noFace: the object has a face track, which drives the face instead
local function applyProp(ent, a, b, u, noFace)
	local pos, ang = lerpV(a.pos, b.pos, u), slerp(a.ang, b.ang, u)
	if S.IsRagdoll(ent) then
		-- an attached object is led by its parent (S.Attach), only the pose is animated
		if ent.SPeditor_Attach then pos, ang = S.GetTransform(ent) end
		local world = { [0] = { pos, ang } }
		local pa, pb = a.phys or {}, b.phys or {}
		for i = 1, ent:GetPhysicsObjectCount() - 1 do
			local ka, kb = pa[i] or pb[i], pb[i] or pa[i]
			if ka then
				local wp, wa = LocalToWorld(lerpV(ka.p, kb.p, u), slerp(ka.a, kb.a, u), pos, ang)
				world[i] = { wp, wa }
			end
		end
		-- the bodies go where the client draws the bones (S.RigidLinks): then whatever is
		-- attached to a hand stays in the hand
		S.RigidPlaces(ent, world)
		for i, w in pairs(world) do setPhys(ent:GetPhysicsObjectNum(i), w[1], w[2]) end
	else
		if not ent.SPeditor_Attach and SPeditor.ValidVec(pos) and SPeditor.ValidAng(ang) then
			ent:SetPos(pos)
			ent:SetAngles(ang)
		end
		local sa, sb = a.scale or 1, b.scale or 1
		if S.CanScale(ent) and (sa ~= 1 or sb ~= 1 or ent.SPeditor_Scale) then S.SetScale(ent, lerpN(sa, sb, u)) end
	end

	-- bones (offsets on top of the pose): only those present in at least one of the keys
	local n = ent:GetBoneCount()
	local function bone(id, ka, kb)
		if id >= n then return end
		ent:ManipulateBonePosition(id, lerpV(ka.p, kb.p, u))
		ent:ManipulateBoneAngles(id, LerpAngle(u, ka.a, kb.a))
		ent:ManipulateBoneScale(id, lerpV(ka.s, kb.s, u))
	end
	for id, ka in pairs(a.bones) do bone(id, ka, b.bones[id] or ZERO_BONE) end
	for id, kb in pairs(b.bones) do
		if not a.bones[id] then bone(id, ZERO_BONE, kb) end
	end

	-- skin and bodygroups cannot be blended: the value of the key before holds until the next key
	-- (keys made before this existed have none, and the object keeps what it has)
	if a.skin and ent:GetSkin() ~= a.skin then S.SetSkinSafe(ent, a.skin) end
	if a.bg then
		for id, v in pairs(a.bg) do
			if id < ent:GetNumBodyGroups() and ent:GetBodygroup(id) ~= v then S.SetBodygroupSafe(ent, id, v) end
		end
	end

	if not noFace then applyFlex(ent, a, b, u) end

	-- colour and opacity (fading in and out)
	local ca, cb = a.col, b.col
	if ca and cb and (ca[1] ~= cb[1] or ca[2] ~= cb[2] or ca[3] ~= cb[3] or ca[4] ~= cb[4]) then
		local col = Color(math.Round(lerpN(ca[1], cb[1], u)), math.Round(lerpN(ca[2], cb[2], u)),
			math.Round(lerpN(ca[3], cb[3], u)), math.Round(lerpN(ca[4], cb[4], u)))
		ent:SetColor(col)
		ent:SetRenderMode(col.a < 255 and RENDERMODE_TRANSCOLOR or RENDERMODE_NORMAL)
		-- the same value goes into the object properties so that it gets into the scene file
		local look = ent.SPeditor_Look or {}
		look.color = (col.r < 255 or col.g < 255 or col.b < 255 or col.a < 255) and { col.r, col.g, col.b, col.a } or nil
		ent.SPeditor_Look = next(look) ~= nil and look or nil
	end
end

local function applyLight(ent, a, b, u)
	if not ent.SPeditor_Attach then
		ent:SetPos(lerpV(a.pos, b.pos, u))
		ent:SetAngles(slerp(a.ang, b.ang, u))
	end
	ent:SetLightColor(lerpV(a.col, b.col, u))
	ent:SetLightRadius(lerpN(a.radius, b.radius, u))
	ent:SetLightBrightness(lerpN(a.bri, b.bri, u))
	ent:SetLightFOV(lerpN(a.fov, b.fov, u))
	ent:SetLightEnabled(a.on and true or false)
	for _, f in ipairs(SPeditor.LightFields) do
		local va, vb = a.f[f.key], b.f[f.key]
		if va and vb then ent["Set" .. f.nw](ent, lerpN(va, vb, u)) end
	end
end

local function applyCamera(ent, a, b, u)
	if not ent.SPeditor_Attach then
		ent:SetPos(lerpV(a.pos, b.pos, u))
		ent:SetAngles(slerp(a.ang, b.ang, u))
	end
	ent:SetCameraFOV(lerpN(a.fov, b.fov, u))
	-- keys made before the shake existed have none: the camera keeps what it has
	if a.shake and b.shake then ent:SetShakeAmp(lerpN(a.shake, b.shake, u)) end
	if a.shakerot and b.shakerot then ent:SetShakeRot(lerpN(a.shakerot, b.shakerot, u)) end
	if a.shakefreq and b.shakefreq then ent:SetShakeFreq(lerpN(a.shakefreq, b.shakefreq, u)) end
end

local function applyEffect(ent, a, b, u)
	if not ent.SPeditor_Attach then
		ent:SetPos(lerpV(a.pos, b.pos, u))
		ent:SetAngles(slerp(a.ang, b.ang, u))
	end
	ent:SetFxTime(math.max(lerpN(a.time, b.time, u), 0))
	ent:SetFxScale(lerpN(a.scale or 1, b.scale or 1, u))
	ent:SetFxLength(lerpN(a.length or 0, b.length or 0, u))
end

local function applyState(ent, a, b, u, noFace)
	if a.kind ~= b.kind then b = a end
	if a.kind == "face" then
		if not S.IsAux(ent) then applyFlex(ent, a, b, u, true) end
	elseif a.kind == "light" then
		if S.IsLight(ent) then applyLight(ent, a, b, u) end
	elseif a.kind == "camera" then
		if S.IsCamera(ent) then applyCamera(ent, a, b, u) end
	elseif a.kind == "effect" then
		if S.IsEffect(ent) then applyEffect(ent, a, b, u) end
	elseif not S.IsAux(ent) then
		applyProp(ent, a, b, u, noFace)
	end
end

-- The two snapshots a track gives at the frame frame and the share of the way between them
local function segment(tr, frame)
	local order = tr.order
	local n = #order
	if frame <= order[1] then
		local st = tr.keys[order[1]].st
		return st, st, 0
	end
	if frame >= order[n] then
		local st = tr.keys[order[n]].st
		return st, st, 0
	end
	-- binary search for the segment
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if order[mid] <= frame then lo = mid else hi = mid end
	end
	local fa, fb = order[lo], order[hi]
	local ka, kb = tr.keys[fa], tr.keys[fb]
	return ka.st, kb.st, SA.EaseValue(ka.e, (frame - fa) / (fb - fa), ka.bz)
end

-- Smoothness of a camera (its CamSmooth, seconds): the place, the direction and the field
-- of view are averaged over the path around the frame, nearer moments counting more. The
-- camera then does not stop at a key and start again but passes through it; a jump cut
-- (a "hold" key) is left as it is — the average never reaches across it.
local SMOOTH_STEPS = 10
local function smoothCamera(ent, tr, frame, half)
	local order = tr.order
	-- The stretch of the path the frame belongs to. A "hold" key keeps its value until the
	-- next key and jumps there: that next key is where another shot begins.
	local lo, hi = order[1], order[#order]
	for i, f in ipairs(order) do
		local g = order[i + 1]
		if g and tr.keys[f].e == "hold" then
			if frame >= g then lo = g else hi = math.min(hi, g - 0.01) end
		end
	end
	if frame < lo or frame > hi then return end
	local pos, fwd, up, fov, sum = Vector(0, 0, 0), Vector(0, 0, 0), Vector(0, 0, 0), 0, 0
	for i = -SMOOTH_STEPS, SMOOTH_STEPS do
		local w = 1 - math.abs(i) / (SMOOTH_STEPS + 1)
		local a, b, u = segment(tr, math.Clamp(frame + i / SMOOTH_STEPS * half, lo, hi))
		local ang = slerp(a.ang, b.ang, u)
		pos:Add(lerpV(a.pos, b.pos, u) * w)
		fwd:Add(ang:Forward() * w)
		up:Add(ang:Up() * w)
		fov = fov + lerpN(a.fov, b.fov, u) * w
		sum = sum + w
	end
	if fwd:LengthSqr() < 1e-6 then return end
	if not ent.SPeditor_Attach then
		ent:SetPos(pos / sum)
		ent:SetAngles(fwd:AngleEx(up))
	end
	ent:SetCameraFOV(fov / sum)
end

-- A track at the frame frame -> object
local function applyTrack(ent, tr, frame, noFace)
	if #tr.order == 0 then return end
	local a, b, u = segment(tr, frame)
	applyState(ent, a, b, u, noFace)
	if a.kind == "camera" and S.IsCamera(ent) and #tr.order > 1 then
		local smooth = ent:GetCamSmooth()
		if smooth > 0.01 then smoothCamera(ent, tr, frame, smooth * anim(ent.SPeditor_Owner).fps) end
	end
end

local function entMap(ply)
	local map = {}
	for _, e in ipairs(S.List(ply)) do
		if e.SPeditor_UID then map[e.SPeditor_UID] = e end
	end
	return map
end

-- proc = true: put procedural motion on top (playback and the render; while editing the
-- objects stay as their keys make them, so that a key never takes the motion in)
function SA.ApplyAll(ply, frame, proc)
	local a = anim(ply)
	a.cur = frame
	local map
	-- the procedural motion of the previous frame is taken off first: the keys below set the
	-- state it goes on top of
	if a.procOn then
		map = entMap(ply)
		SA.ProcRevert(map)
		a.procOn = nil
	end
	if next(a.tracks) ~= nil then
		map = map or entMap(ply)
		SA.ApplyTracks(a, map, frame)
	end
	if proc and next(a.proc or {}) ~= nil then
		map = map or entMap(ply)
		SA.ProcApply(a, map, frame)
		a.procOn = true
	end
end

function SA.ApplyTracks(a, map, frame)
	for id, tr in pairs(a.tracks) do
		local face = SA.IsFaceTrack(id)
		local ent = map[face and (id - SA.FACE) or id]
		if IsValid(ent) then
			local ok, err = pcall(applyTrack, ent, tr, frame, not face and a.tracks[SA.FaceTrack(id)] ~= nil)
			if not ok then MOD:Print("apply: ", tostring(err)) end
		end
	end
end

---------------------------------------------------------------------
-- Tracks
---------------------------------------------------------------------
local function reorder(tr)
	local order = {}
	for f in pairs(tr.keys) do order[#order + 1] = f end
	table.sort(order)
	tr.order = order
end

local function copyTrack(tr)
	if not tr then return false end
	local keys = {}
	for f, k in pairs(tr.keys) do keys[f] = k end
	-- the order is already sorted: copied, not sorted again (a baked track has thousands of keys)
	local order = {}
	for i, f in ipairs(tr.order) do order[i] = f end
	return { keys = keys, order = order }
end

-- Table of contents for the client: key frames, easing and root position (the path line)
function SA.SendSummary(ply)
	local a = anim(ply)
	local tracks = {}
	for uid, tr in pairs(a.tracks) do
		local list = {}
		for i, f in ipairs(tr.order) do
			local k = tr.keys[f]
			local p = k.st.pos
			list[i] = { f, k.e, math.Round(p.x, 1), math.Round(p.y, 1), math.Round(p.z, 1) }
		end
		tracks[tostring(uid)] = SA.ToPages(list)
	end
	local proc = {}
	for uid, pr in pairs(a.proc or {}) do proc[tostring(uid)] = pr end
	SA.SendParts(ply, "Summary", { fps = a.fps, frames = a.frames, loop = a.loop, tracks = tracks, sounds = a.sounds or {}, proc = proc })
end

local function sendFrame(ply, serial)
	local a = anim(ply)
	MOD:NetStart("Frame")
	net.WriteFloat(a.cur)
	net.WriteBool(a.playing)
	net.WriteUInt(serial or 0, 16)
	net.Send(ply)
end

-- Remember the track before an edit (once per operation and object)
local function opBefore(ply, id, uid)
	local ops = SA.Ops[ply]
	if not ops then
		ops = { items = {}, order = {} }
		SA.Ops[ply] = ops
	end
	local op = ops.items[id]
	if not op then
		op = { before = {}, after = {} }
		ops.items[id] = op
		ops.order[#ops.order + 1] = id
		while #ops.order > MAX_OPS do ops.items[table.remove(ops.order, 1)] = nil end
	end
	if op.before[uid] == nil then op.before[uid] = copyTrack(anim(ply).tracks[uid]) end
	return op
end

local function opAfter(ply, op, uid)
	op.after[uid] = copyTrack(anim(ply).tracks[uid])
end

-- face = true: a key of the object's face track
local function setKey(ply, ent, frame, ease, face)
	local a = anim(ply)
	local uid = ent.SPeditor_UID
	if not uid then return false end
	if face then
		if S.IsAux(ent) then return false end
		uid = SA.FaceTrack(uid)
	end
	frame = math.Clamp(math.floor(frame + 0.5), 0, a.frames)
	local tr = a.tracks[uid]
	if not tr then
		tr = { keys = {}, order = {} }
		a.tracks[uid] = tr
	end
	if not tr.keys[frame] and #tr.order >= SA.MAX_KEYS then return false end
	local old = tr.keys[frame]
	local e = ease or (old and old.e) or "ease"
	tr.keys[frame] = { e = e, bz = old and old.e == e and old.bz or nil, st = face and captureFace(ent) or capture(ent) }
	if not old then
		-- a new frame goes into its place in the sorted order (binary search)
		local order = tr.order
		local lo, hi = 1, #order + 1
		while lo < hi do
			local mid = math.floor((lo + hi) / 2)
			if order[mid] < frame then lo = mid + 1 else hi = mid end
		end
		table.insert(order, lo, frame)
	end
	return true
end
SA.SetKey = setKey

local function dropEmpty(a, uid)
	local tr = a.tracks[uid]
	if tr and next(tr.keys) == nil then a.tracks[uid] = nil end
end

---------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------
MOD:NetReceive("Sync", function(ply)
	SA.SendSummary(ply)
	sendFrame(ply)
end)

MOD:NetReceive("Config", function(ply)
	local a = anim(ply)
	a.fps    = math.Clamp(net.ReadUInt(8), 1, 120)
	a.frames = math.Clamp(net.ReadUInt(32), 1, SA.MAX_FRAMES)
	a.loop   = net.ReadBool()
	a.cur    = math.min(a.cur, a.frames)
	SA.SendSummary(ply)
end)

MOD:NetReceive("Seek", function(ply)
	local frame  = net.ReadFloat()
	local serial = net.ReadUInt(16)
	local a = anim(ply)
	if frame ~= frame then return end
	a.playing = false
	-- a seek with a confirmation is the render: the procedural motion is on
	SA.ApplyAll(ply, math.Clamp(frame, 0, a.frames), serial ~= 0)
	S.AttachFollow()          -- attached objects (a weapon in a hand) move in the same tick
	if serial ~= 0 then
		-- a seek with a confirmation is the animation render: the objects must jump to the frame
		-- on the client at once, without the smoothing of movement between network updates.
		-- The game does not clear the flag by itself (verified in game), so it is taken off a
		-- quarter of a second after the last such seek.
		for _, ent in ipairs(S.List(ply)) do
			if IsValid(ent) then ent:AddEffects(EF_NOINTERP) end
		end
		timer.Create("SAeditor.NoInterp" .. ply:EntIndex(), 0.25, 1, function()
			if not IsValid(ply) then return end
			for _, e in ipairs(S.List(ply)) do
				if IsValid(e) and e:IsEffectActive(EF_NOINTERP) then e:RemoveEffects(EF_NOINTERP) end
			end
		end)
		-- The confirmation leaves two ticks later: by then physics has passed the new places of
		-- the bodies to the network, and the client gets them no later than the confirmation.
		-- So the client may shoot the frame as soon as it has the answer, without a pause.
		timer.Simple(0, function()
			timer.Simple(0, function()
				if IsValid(ply) then sendFrame(ply, serial) end
			end)
		end)
	end
end)

-- The list of sound clips, as a whole (the client edits it and sends the result)
local function cleanSounds(list)
	local out, seen = {}, {}
	for _, c in ipairs(istable(list) and list or {}) do
		if #out >= SA.MAX_SOUNDS then break end
		local clip = SA.CleanSound(c)
		if clip and clip.id > 0 and not seen[clip.id] then
			seen[clip.id] = true
			out[#out + 1] = clip
		end
	end
	return out
end

MOD:NetReceive("Sounds", function(ply)
	anim(ply).sounds = cleanSounds(SPeditor.ReadTable())
	SA.SendSummary(ply)
end)

MOD:NetReceive("Play", function(ply)
	local on    = net.ReadBool()
	local frame = net.ReadFloat()
	local a = anim(ply)
	if frame ~= frame then return end
	a.playing = on
	a.cur = math.Clamp(frame, 0, a.frames)
	if on then
		if a.cur >= a.frames then a.cur = 0 end
		a.t0, a.f0 = CurTime(), a.cur
	end
	SA.ApplyAll(ply, a.cur, on)
	sendFrame(ply)
end)

MOD:NetReceive("Key", function(ply)
	local id     = net.ReadUInt(32)
	local action = net.ReadUInt(4)
	local uid    = net.ReadUInt(32)
	local frame  = net.ReadInt(32)
	local arg    = net.ReadInt(32)
	local str    = net.ReadString()
	local a = anim(ply)

	if action == OP.CLEAR_ALL then
		for u in pairs(a.tracks) do opBefore(ply, id, u) end
		local op = SA.Ops[ply] and SA.Ops[ply].items[id]
		a.tracks = {}
		if op then
			for u in pairs(op.before) do op.after[u] = false end
		end
		SA.SendSummary(ply)
		return
	end

	local op = opBefore(ply, id, uid)
	local tr = a.tracks[uid]
	if action == OP.SET then
		local face = SA.IsFaceTrack(uid)
		local ent = S.FindUID(ply, face and (uid - SA.FACE) or uid)
		-- str — the easing of the new key (the client asks for "linear" when it plays an effect)
		local ease = (str ~= "bezier" and SA.ValidEase(str)) and str or nil
		if IsValid(ent) and not setKey(ply, ent, frame, ease, face) then S.Notice(ply, "#sa_keys_limit", 1) end
	elseif action == OP.DELETE then
		if tr and tr.keys[frame] then
			tr.keys[frame] = nil
			reorder(tr)
			dropEmpty(a, uid)
		end
	elseif action == OP.MOVE or action == OP.COPY then
		-- arg — the destination frame; the key there is replaced
		local to = math.Clamp(arg, 0, a.frames)
		if tr and tr.keys[frame] and to ~= frame then
			tr.keys[to] = tr.keys[frame]
			if action == OP.MOVE then tr.keys[frame] = nil end
			reorder(tr)
		end
	elseif action == OP.EASE then
		local k = tr and tr.keys[frame]
		-- "bezier:x1,y1,x2,y2" — a curve of its own (the curve editor)
		local bz = string.sub(str, 1, 7) == "bezier:" and SA.ParseBezier(string.sub(str, 8)) or nil
		if k and bz then
			tr.keys[frame] = { e = "bezier", bz = bz, st = k.st }
		elseif k and table.HasValue(SA.EASES, str) then
			tr.keys[frame] = { e = str, st = k.st }
		end
	elseif action == OP.CLEAR then
		a.tracks[uid] = nil
	end
	opAfter(ply, op, uid)
	SA.SendSummary(ply)
	-- the object at once takes the state the track gives at the current frame
	if action ~= OP.SET then SA.ApplyAll(ply, a.cur) end
end)

-- Undo and redo: bring the tracks back to what they were before the operation or after it
MOD:NetReceive("Restore", function(ply)
	local id    = net.ReadUInt(32)
	local after = net.ReadBool()
	local ops = SA.Ops[ply]
	local op = ops and ops.items[id]
	if not op then return end
	local a = anim(ply)
	for uid, tr in pairs(after and op.after or op.before) do
		a.tracks[uid] = copyTrack(tr) or nil
	end
	SA.SendSummary(ply)
	SA.ApplyAll(ply, a.cur)
end)

-- Baking a model animation: the client computes bones on its copy of the model and
-- sends them one frame per message; the server applies the bones and takes a key at once.
MOD:NetReceive("Bake", function(ply)
	local id    = net.ReadUInt(32)
	local ent   = S.ReadOwned(ply)
	local frame = net.ReadUInt(32)
	local count = net.ReadUInt(8)
	local bones = {}
	for i = 1, count do
		bones[i] = { net.ReadUInt(8), SPeditor.ReadVecF(), SPeditor.ReadAngF() }
	end
	-- bones without physics (fingers): their turn as a bone offset
	local soft, nSoft = {}, net.ReadUInt(16)
	if nSoft > 512 then return end
	for i = 1, nSoft do
		soft[i] = { net.ReadUInt(16), SPeditor.ReadAngF() }
	end
	local last = net.ReadBool()       -- the last frame of the series
	-- shifts of root bones (a model without physics: nothing else moves it)
	local shifts = {}
	for i = 1, net.ReadUInt(8) do shifts[i] = { net.ReadUInt(16), SPeditor.ReadVecF() } end
	if not IsValid(ent) or S.IsAux(ent) then return end
	local rag = S.IsRagdoll(ent)
	if not rag and ent:GetBoneCount() < 2 then return end
	local a = anim(ply)
	local uid = ent.SPeditor_UID
	local op = opBefore(ply, id, uid)
	local max = ent:GetPhysicsObjectCount()
	if rag then
		for _, b in ipairs(bones) do
			if b[1] < max then setPhys(ent:GetPhysicsObjectNum(b[1]), b[2], b[3]) end
		end
	end
	local nb = ent:GetBoneCount()
	for _, b in ipairs(soft) do
		if b[1] < nb and SPeditor.ValidAng(b[2]) then ent:ManipulateBoneAngles(b[1], b[2]) end
	end
	if not rag then
		for _, sh in ipairs(shifts) do
			if sh[1] < nb and SPeditor.ValidVec(sh[2]) and sh[2]:Length() < 4096 then ent:ManipulateBonePosition(sh[1], sh[2]) end
		end
	end
	if rag then S.SnapRigid(ent) end
	setKey(ply, ent, math.min(frame, a.frames), "linear")
	-- the track after the edit: copied now and then, not for every frame of a long bake
	op.bakes = (op.bakes or 0) + 1
	if last or op.bakes % 32 == 1 then opAfter(ply, op, uid) end
	if last then
		SA.SendSummary(ply)
		SA.ApplyAll(ply, a.cur)
	end
end)

---------------------------------------------------------------------
-- Playback
---------------------------------------------------------------------
MOD:Hook("Think", function()
	for ply, a in pairs(A) do
		if not IsValid(ply) then
			A[ply], SA.Ops[ply] = nil, nil
		elseif a.playing then
			local f = a.f0 + (CurTime() - a.t0) * a.fps
			if f >= a.frames then
				if a.loop then
					a.t0, a.f0 = CurTime(), 0
					f = 0
				else
					f = a.frames
					a.playing = false
				end
			end
			SA.ApplyAll(ply, f, a.playing)
			if not a.playing then sendFrame(ply) end
		end
	end
end, "play")

-- the editor is closed — playback stops
MOD:Hook("SPeditor_PlayerState", function(ply, on)
	local a = A[ply]
	if a and not on then
		a.playing = false
		if a.procOn then SA.ApplyAll(ply, a.cur, false) end
	end
end)

-- "Clear scene" and loading another scene
MOD:Hook("SPeditor_PlayerCleanup", function(ply)
	if not A[ply] then return end
	local a = anim(ply)
	a.tracks, a.sounds, a.playing, a.cur, a.proc, a.procOn = {}, {}, false, 0, {}, nil
	SA.Ops[ply] = nil
	if IsValid(ply) then SA.SendSummary(ply) end
end)

---------------------------------------------------------------------
-- Scene file. Vectors and angles as number arrays, objects by their number in the scene.
---------------------------------------------------------------------
local function enc(v)
	if isvector(v) then return { _v = { math.Round(v.x, 3), math.Round(v.y, 3), math.Round(v.z, 3) } } end
	if isangle(v) then return { _a = { math.Round(v.p, 3), math.Round(v.y, 3), math.Round(v.r, 3) } } end
	if istable(v) then
		local out = {}
		for k, x in pairs(v) do out[tostring(k)] = enc(x) end
		return out
	end
	if isnumber(v) then return math.Round(v, 4) end
	return v
end

local function dec(v)
	if not istable(v) then return v end
	if istable(v._v) then return SPeditor.TableToVec(v._v) or Vector(0, 0, 0) end
	if istable(v._a) then return SPeditor.TableToAng(v._a) or Angle(0, 0, 0) end
	local out = {}
	for k, x in pairs(v) do out[tonumber(k) or k] = dec(x) end
	return out
end

-- a snapshot from a file is external data: a key without the required fields is dropped
local function validState(st)
	if not istable(st) or not isvector(st.pos) or not isangle(st.ang) then return false end
	if st.kind == "light" then
		return isvector(st.col) and isnumber(st.radius) and isnumber(st.bri) and isnumber(st.fov) and istable(st.f)
	elseif st.kind == "camera" then
		return isnumber(st.fov)
	elseif st.kind == "effect" then
		return isnumber(st.time)
	elseif st.kind == "face" then
		st.flex = istable(st.flex) and st.flex or {}
		for id, w in pairs(st.flex) do
			if not isnumber(w) then st.flex[id] = nil end
		end
		return true
	elseif st.kind == "prop" then
		st.bones = istable(st.bones) and st.bones or {}
		st.flex = istable(st.flex) and st.flex or {}
		for id, b in pairs(st.bones) do
			if not (istable(b) and isvector(b.p) and isangle(b.a) and isvector(b.s)) then st.bones[id] = nil end
		end
		for id, w in pairs(st.flex) do
			if not isnumber(w) then st.flex[id] = nil end
		end
		if st.phys ~= nil then
			if not istable(st.phys) then return false end
			for id, p in pairs(st.phys) do
				if not (istable(p) and isvector(p.p) and isangle(p.a)) then st.phys[id] = nil end
			end
		end
		if st.col ~= nil and not (istable(st.col) and isnumber(st.col[1]) and isnumber(st.col[2]) and isnumber(st.col[3]) and isnumber(st.col[4])) then
			st.col = nil
		end
		if not isnumber(st.skin) then st.skin = nil end
		if st.bg ~= nil then
			if not istable(st.bg) then
				st.bg = nil
			else
				for id, v in pairs(st.bg) do
					if not isnumber(id) or not isnumber(v) then st.bg[id] = nil end
				end
			end
		end
		return true
	end
	return false
end

MOD:SceneData(function(ply, ctx)
	local a = A[ply]
	if not a or (next(a.tracks) == nil and #(a.sounds or {}) == 0) then return nil end
	local tracks, faces = {}, {}
	for id, tr in pairs(a.tracks) do
		local face = SA.IsFaceTrack(id)
		local ent = S.FindUID(ply, face and (id - SA.FACE) or id)
		local index = ent and ctx.indexOf[ent]
		if index then
			local keys = {}
			for f, k in pairs(tr.keys) do keys[tostring(f)] = { e = k.e, bz = k.bz, st = enc(k.st) } end
			keys = SA.MapToPages(keys)
			if face then faces[tostring(index)] = keys else tracks[tostring(index)] = keys end
		end
	end
	-- sounds refer to their object by its number in the scene too (0 — no object)
	local sounds = {}
	for i, c in ipairs(a.sounds or {}) do
		local ent = c.uid ~= 0 and S.FindUID(ply, c.uid) or nil
		sounds[i] = { id = c.id, path = c.path, f = c.f, obj = ent and ctx.indexOf[ent] or 0, voice = c.voice, vol = c.vol,
			pitch = c.pitch, dist = c.dist, cin = c.cin, cout = c.cout, fin = c.fin, fout = c.fout }
	end
	local proc = {}
	for uid, pr in pairs(a.proc or {}) do
		local ent = S.FindUID(ply, uid)
		local index = ent and ctx.indexOf[ent]
		if index then proc[tostring(index)] = pr end
	end
	return { version = 1, fps = a.fps, frames = a.frames, loop = a.loop, tracks = tracks, faces = next(faces) and faces or nil,
		sounds = sounds, proc = next(proc) and proc or nil }
end, function(ply, data, ctx)
	local a = anim(ply)
	a.tracks, a.sounds, a.playing, a.cur, a.proc, a.procOn = {}, {}, false, 0, {}, nil
	SA.Ops[ply] = nil
	if data then
		for index, pr in pairs(istable(data.proc) and data.proc or {}) do
			local ent = ctx.ents[tonumber(index)]
			local clean = SA.CleanProc(pr)
			if IsValid(ent) and ent.SPeditor_UID and clean then a.proc[ent.SPeditor_UID] = clean end
		end
		a.fps    = math.Clamp(math.floor(SPeditor.Num(data.fps, 24)), 1, 120)
		a.frames = math.Clamp(math.floor(SPeditor.Num(data.frames, 96)), 1, SA.MAX_FRAMES)
		a.loop   = data.loop and true or false
		local function loadTracks(list, face)
			for index, keys in pairs(istable(list) and list or {}) do
				keys = SA.MapFromPages(keys)
				local ent = ctx.ents[tonumber(index)]
				if IsValid(ent) and ent.SPeditor_UID and istable(keys) then
					local tr = { keys = {}, order = {} }
					local n = 0
					for f, k in pairs(keys) do
						f = tonumber(f)
						local st = istable(k) and dec(k.st)
						if f and f >= 0 and f <= a.frames and n < SA.MAX_KEYS and validState(st) then
							local bz = k.e == "bezier" and istable(k.bz) and SA.ParseBezier(table.concat(k.bz, ",")) or nil
							local e = (k.e == "bezier" and not bz) and "ease" or (SA.ValidEase(k.e) and k.e or "ease")
							tr.keys[math.floor(f)] = { e = e, bz = bz, st = st }
							n = n + 1
						end
					end
					if n > 0 then
						reorder(tr)
						a.tracks[face and SA.FaceTrack(ent.SPeditor_UID) or ent.SPeditor_UID] = tr
					end
				end
			end
		end
		loadTracks(data.tracks, false)
		loadTracks(data.faces, true)
		local sounds = {}
		for _, c in ipairs(istable(data.sounds) and data.sounds or {}) do
			if istable(c) then
				local ent = ctx.ents[tonumber(c.obj) or 0]
				c.uid = IsValid(ent) and ent.SPeditor_UID or 0
				sounds[#sounds + 1] = c
			end
		end
		a.sounds = cleanSounds(sounds)
	end
	SA.SendSummary(ply)
end)

---------------------------------------------------------------------
-- Procedural motion (a0.5): life on top of the keys, worked out from the time of the frame,
-- so that the render gets exactly what playback shows.
--   breath — the chest of a character rises and falls (scale of the chest bone), rate — breaths a minute
--   blink  — the eyes close now and then (a flex named like "blink"), 0..1 = how often
--   head   — the head of a ragdoll turns a little by itself (its body), 0..1 = how much
--   sway   — a prop, light or effect drifts and turns slowly (a hanging lamp, a boat), units
--   freq   — how fast the head and the sway move, Hz
-- It is on only during playback and the render; while editing it is taken off, so that a key
-- never takes it in. Kept per object in a.proc[uid], saved with the scene.
---------------------------------------------------------------------
local PROC_FIELDS = { breath = { 0, 1, 0 }, rate = { 4, 40, 14 }, blink = { 0, 1, 0 }, head = { 0, 1, 0 },
	sway = { 0, 64, 0 }, freq = { 0.02, 4, 0.3 } }

function SA.CleanProc(t)
	if not istable(t) then return nil end
	local out, any = {}, false
	for k, r in pairs(PROC_FIELDS) do
		out[k] = math.Clamp(tonumber(t[k]) or r[3], r[1], r[2])
	end
	any = out.breath > 0 or out.blink > 0 or out.head > 0 or out.sway > 0
	return any and out or nil
end

-- smooth noise -1..1 from sines of unrelated frequencies (the same for the same time and seed)
local function noise(t, seed)
	return (math.sin(t * 1.31 + seed) + 0.6 * math.sin(t * 2.71 + seed * 1.7) + 0.35 * math.sin(t * 5.13 + seed * 2.3)) / 1.95
end

local CHEST = { "valvebiped.bip01_spine4", "valvebiped.bip01_spine2", "chest", "spine2", "spine_2", "spine1", "spine" }
local function chestBone(ent)
	if ent.SA_Chest ~= nil then return ent.SA_Chest or nil end
	local found = false
	for _, want in ipairs(CHEST) do
		for b = 0, ent:GetBoneCount() - 1 do
			local n = string.lower(ent:GetBoneName(b) or "")
			if n == want or (not string.find(want, ".", 1, true) and string.find(n, want, 1, true)) then found = b break end
		end
		if found then break end
	end
	ent.SA_Chest = found
	return found or nil
end

local function blinkFlex(ent)
	if ent.SA_Blink ~= nil then return ent.SA_Blink or nil end
	local found = false
	for i = 0, ent:GetFlexNum() - 1 do
		local n = string.lower(ent:GetFlexName(i) or "")
		if string.find(n, "blink", 1, true) or string.find(n, "eyes_closed", 1, true) or string.find(n, "eye_close", 1, true)
			or string.find(n, "eyeclose", 1, true) or string.find(n, "close_eyes", 1, true) then
			found = i
			break
		end
	end
	ent.SA_Blink = found
	return found or nil
end

-- 0..1: how closed the eyes are at the time t (a blink every period seconds, at a moment
-- that varies from blink to blink)
local function blinkAt(t, period, seed)
	local k0 = math.floor(t / period)
	local w = 0
	for k = k0 - 1, k0 do
		local r = math.sin(k * 12.9898 + seed * 78.233) * 43758.5453
		local tk = (k + 0.15 + 0.6 * (r - math.floor(r))) * period
		local d = t - tk
		if d >= 0 then
			if d < 0.07 then w = math.max(w, d / 0.07)
			elseif d < 0.11 then w = 1
			elseif d < 0.26 then w = math.max(w, 1 - (d - 0.11) / 0.15) end
		end
	end
	return w
end

function SA.ProcRevert(map)
	for _, ent in pairs(map) do
		local s = IsValid(ent) and ent.SA_Proc
		if s then
			if s.chest then ent:ManipulateBoneScale(s.chest, s.chestBase) end
			if s.flex then ent:SetFlexWeight(s.flex, s.flexBase) end
			if s.head then
				local p = ent:GetPhysicsObjectNum(s.head)
				if IsValid(p) then setPhys(p, p:GetPos(), s.headBase) end
			end
			if s.pos then
				ent:SetPos(s.pos)
				ent:SetAngles(s.ang)
			end
			ent.SA_Proc = nil
		end
	end
end

function SA.ProcApply(a, map, frame)
	local t = frame / math.max(a.fps, 1)
	for uid, pr in pairs(a.proc) do
		local ent = map[uid]
		if IsValid(ent) and not ent.SA_Proc then
			local s, seed = {}, (uid % 97) * 0.731
			if pr.breath > 0 and not S.IsAux(ent) then
				local b = chestBone(ent)
				if b then
					local base = ent:GetManipulateBoneScale(b)
					local k = 1 + 0.04 * pr.breath * (0.5 - 0.5 * math.cos(t * pr.rate / 60 * math.pi * 2))
					s.chest, s.chestBase = b, base
					ent:ManipulateBoneScale(b, base * k)
				end
			end
			if pr.blink > 0 and not S.IsAux(ent) then
				local f = blinkFlex(ent)
				if f then
					local base = ent:GetFlexWeight(f)
					s.flex, s.flexBase = f, base
					ent:SetFlexWeight(f, math.max(base, blinkAt(t, 1.5 + 5 * (1 - pr.blink), seed)))
				end
			end
			if pr.head > 0 and S.IsRagdoll(ent) then
				local hb = ent:LookupBone("ValveBiped.Bip01_Head1")
				local pi = hb and ent:TranslateBoneToPhysBone(hb)
				local p = pi and pi > 0 and ent:GetPhysicsObjectNum(pi)
				if IsValid(p) then
					local base = p:GetAngles()
					local ft = t * pr.freq * 2
					local amp = 7 * pr.head
					local _, na = LocalToWorld(vector_origin, Angle(noise(ft, seed) * amp, noise(ft, seed + 3.1) * amp, noise(ft, seed + 5.7) * amp * 0.4),
						vector_origin, base)
					s.head, s.headBase = pi, base
					setPhys(p, p:GetPos(), na)
				end
			end
			if pr.sway > 0 and not S.IsRagdoll(ent) and not S.IsCamera(ent) and not ent.SPeditor_Attach then
				local pos, ang = ent:GetPos(), ent:GetAngles()
				local ft = t * pr.freq * 2
				local off = Vector(noise(ft, seed), noise(ft, seed + 1.9), noise(ft, seed + 4.4) * 0.5) * pr.sway
				local turn = Angle(noise(ft, seed + 2.6), noise(ft, seed + 6.2), noise(ft, seed + 8.8)) * (pr.sway * 0.3)
				s.pos, s.ang = pos, ang
				ent:SetPos(pos + off)
				ent:SetAngles(ang + turn)
			end
			ent.SA_Proc = next(s) and s or nil
		end
	end
end

MOD:NetReceive("Proc", function(ply)
	local uid = net.ReadUInt(32)
	local t = SPeditor.ReadTable()
	local a = anim(ply)
	if not IsValid(S.FindUID(ply, uid)) then return end
	a.proc = a.proc or {}
	a.proc[uid] = SA.CleanProc(t)
	SA.SendSummary(ply)
	-- playing: the change shows at once
	if a.playing then SA.ApplyAll(ply, a.cur, true) end
end)

---------------------------------------------------------------------
-- Curve editor (a0.5). The client asks for the values of one part of an object over its keys
-- and edits a value of a key; the easing between keys goes through OP.EASE ("bezier:…").
--   part -1 — the object itself: place, turn (+ FOV of a camera, brightness / radius / cone of a
--   light, moment / size of an effect, scale of a prop); part >= 0 — a bone: a physical bone
--   of a ragdoll is its place and turn relative to the ragdoll's root, any other bone — its offset.
---------------------------------------------------------------------
local CH_XYZ = { "x", "y", "z", "pitch", "yaw", "roll" }

local function partOf(ent, part)
	if part < 0 then return "root" end
	if S.IsRagdoll(ent) then
		local pi = ent:TranslateBoneToPhysBone(part)
		if pi and pi >= 0 and ent:TranslatePhysBoneToBone(pi) == part then
			return pi == 0 and "root" or "phys", pi
		end
	end
	return "bone", part
end

local function channels(st, kind)
	local list = table.Copy(CH_XYZ)
	if kind == "root" then
		if st.kind == "camera" then list[#list + 1] = "fov"
		elseif st.kind == "light" then
			list[#list + 1] = "bri" list[#list + 1] = "radius" list[#list + 1] = "lfov"
		elseif st.kind == "effect" then
			list[#list + 1] = "time" list[#list + 1] = "fxscale"
		elseif st.kind == "prop" and st.scale then list[#list + 1] = "scale" end
	end
	return list
end

local ZB = { p = vector_origin, a = angle_zero, s = ONE }
-- the place and turn of a part in a snapshot
local function partPA(st, kind, idx)
	if kind == "root" then return st.pos, st.ang end
	if kind == "phys" then
		local ph = st.phys and st.phys[idx]
		if ph then return ph.p, ph.a end
		return nil
	end
	local b = (st.bones and st.bones[idx]) or ZB
	return b.p, b.a
end

local function chanGet(st, kind, idx, ch)
	local p, an = partPA(st, kind, idx)
	if not p then return nil end
	if ch == "x" then return p.x elseif ch == "y" then return p.y elseif ch == "z" then return p.z
	elseif ch == "pitch" then return an.p elseif ch == "yaw" then return an.y elseif ch == "roll" then return an.r
	elseif ch == "fov" then return st.fov elseif ch == "bri" then return st.bri elseif ch == "radius" then return st.radius
	elseif ch == "lfov" then return st.fov elseif ch == "time" then return st.time elseif ch == "fxscale" then return st.scale
	elseif ch == "scale" then return st.scale end
end

-- a new snapshot with one channel changed (keys never change: an edit makes a new one)
local function chanSet(st, kind, idx, ch, v)
	local n = table.Copy(st)
	local function edit(p, an)
		p, an = Vector(p.x, p.y, p.z), Angle(an.p, an.y, an.r)
		if ch == "x" then p.x = v elseif ch == "y" then p.y = v elseif ch == "z" then p.z = v
		elseif ch == "pitch" then an.p = v elseif ch == "yaw" then an.y = v elseif ch == "roll" then an.r = v end
		return p, an
	end
	if ch == "fov" or ch == "lfov" then n.fov = math.Clamp(v, 1, 179)
	elseif ch == "bri" then n.bri = math.max(v, 0)
	elseif ch == "radius" then n.radius = math.max(v, 1)
	elseif ch == "time" then n.time = math.max(v, 0)
	elseif ch == "fxscale" then n.scale = math.Clamp(v, 0.01, 50)
	elseif ch == "scale" then n.scale = math.Clamp(v, 0.05, 10)
	elseif kind == "root" then n.pos, n.ang = edit(n.pos, n.ang)
	elseif kind == "phys" then
		local ph = n.phys and n.phys[idx]
		if not ph then return nil end
		ph.p, ph.a = edit(ph.p, ph.a)
	else
		n.bones = n.bones or {}
		local b = n.bones[idx] or { p = Vector(0, 0, 0), a = Angle(0, 0, 0), s = Vector(1, 1, 1) }
		b.p, b.a = edit(b.p, b.a)
		n.bones[idx] = b
	end
	return n
end

local function sendCurve(ply, uid, part)
	local a = anim(ply)
	local tr = a.tracks[uid]
	local ent = S.FindUID(ply, uid)
	local out = { uid = uid, part = part, keys = {} }
	if tr and IsValid(ent) and #tr.order > 0 then
		local kind, idx = partOf(ent, part)
		out.chans = channels(tr.keys[tr.order[1]].st, kind)
		for i, f in ipairs(tr.order) do
			local k = tr.keys[f]
			local vals = {}
			for c, ch in ipairs(out.chans) do vals[c] = chanGet(k.st, kind, idx, ch) or 0 end
			out.keys[i] = { f = f, e = k.e, bz = k.bz, v = vals }
		end
	end
	out.keys = SA.ToPages(out.keys)
	SA.SendParts(ply, "CurveData", out)
end

MOD:NetReceive("Curve", function(ply)
	local action = net.ReadUInt(2)            -- 0 — ask, 1 — set a value
	local uid    = net.ReadUInt(32)
	local part   = net.ReadInt(16)
	if action == 1 then
		local id, frame, ch, v = net.ReadUInt(32), net.ReadUInt(32), net.ReadString(), net.ReadFloat()
		local a = anim(ply)
		local tr = a.tracks[uid]
		local ent = S.FindUID(ply, uid)
		if tr and tr.keys[frame] and IsValid(ent) and v == v and math.abs(v) < 1e6 then
			local kind, idx = partOf(ent, part)
			local k = tr.keys[frame]
			local st = chanSet(k.st, kind, idx, ch, v)
			if st then
				local op = opBefore(ply, id, uid)
				tr.keys[frame] = { e = k.e, bz = k.bz, st = st }
				opAfter(ply, op, uid)
				SA.ApplyAll(ply, a.cur)
				SA.SendSummary(ply)
			end
		end
	end
	sendCurve(ply, uid, part)
end)

---------------------------------------------------------------------
-- Stop Motion Helper (a0.5): its saves (garrysmod/data/smh/<name>.txt) can be taken into the
-- timeline, and the animation of objects can be written as such a save for SMH to load.
-- An SMH key holds "modifiers" — physbones (world place of each body), position, bones (bone
-- offsets), flex, skin, bodygroup, color, modelscale — each on keys of its own, with
-- EaseIn / EaseOut. Here every frame that has any of them becomes one key: what the frame has
-- not is worked out between that modifier's own keys (or taken from the object as it is).
---------------------------------------------------------------------
local SMH_DIR = "smh/"

local function smhFiles()
	local out = {}
	for _, f in ipairs(file.Find(SMH_DIR .. "*.txt", "DATA") or {}) do
		if #out >= 200 then break end
		local data = util.JSONToTable(file.Read(SMH_DIR .. f, "DATA") or "")
		if istable(data) and istable(data.Entities) then
			local list = {}
			for _, e in pairs(data.Entities) do
				if istable(e) and istable(e.Frames) then
					local name = istable(e.Properties) and e.Properties.Name or e.Model
					list[#list + 1] = { name = tostring(name or "?"), model = tostring(e.Model or ""), frames = #e.Frames,
						world = istable(e.Properties) and e.Properties.IsWorld or nil }
				end
			end
			out[#out + 1] = { file = string.StripExtension(f), map = tostring(data.Map or ""), ents = list }
		end
	end
	return out
end

local function num(v) return tonumber(v) end
local function vec(v) return isvector(v) and v or nil end
local function ang(v) return isangle(v) and v or nil end

-- the value of one modifier at the frame pos, from that modifier's own keys
local function modAt(list, pos)
	local prev, nxt
	for _, k in ipairs(list) do
		if k.pos <= pos then prev = k end
		if k.pos >= pos and not nxt then nxt = k end
	end
	if not prev then return nxt and nxt.data end
	if not nxt or nxt == prev then return prev.data, prev, nil, 0 end
	local u = (pos - prev.pos) / (nxt.pos - prev.pos)
	u = math.EaseInOut(u, prev.out or 0, nxt.inn or 0)
	return prev.data, prev, nxt, u
end

local function lerpTable(name, d1, d2, u)
	if not d2 or u == 0 then return d1 end
	if name == "physbones" or name == "bones" then
		local out = {}
		for i, a in pairs(d1) do
			local b = d2[i]
			if istable(a) and istable(b) then
				local o = {}
				if vec(a.Pos) and vec(b.Pos) then o.Pos = LerpVector(u, a.Pos, b.Pos) end
				if ang(a.Ang) and ang(b.Ang) then o.Ang = SA.SlerpAngle(a.Ang, b.Ang, u) end
				if vec(a.Scale) and vec(b.Scale) then o.Scale = LerpVector(u, a.Scale, b.Scale) end
				out[i] = o
			else
				out[i] = a
			end
		end
		return out
	elseif name == "position" then
		if vec(d1.Pos) and vec(d2.Pos) and ang(d1.Ang) and ang(d2.Ang) then
			return { Pos = LerpVector(u, d1.Pos, d2.Pos), Ang = SA.SlerpAngle(d1.Ang, d2.Ang, u) }
		end
	elseif name == "flex" and istable(d1.Weights) and istable(d2.Weights) then
		local w = {}
		for i, x in pairs(d1.Weights) do w[i] = Lerp(u, num(x) or 0, num(d2.Weights[i]) or 0) end
		return { Weights = w, Scale = d1.Scale }
	elseif name == "modelscale" and num(d1.ModelScale) and num(d2.ModelScale) then
		return { ModelScale = Lerp(u, d1.ModelScale, d2.ModelScale) }
	end
	return d1           -- skin, bodygroup, color: the key before holds
end

-- keys 0, 1, 2 … of a JSON table may come back as strings
local function numKeys(t)
	local out = {}
	for k, v in pairs(istable(t) and t or {}) do
		local n = tonumber(k)
		if n then out[n] = v end
	end
	return out
end

-- opts = { start = first frame, fps = SMH frames a second (0 — frame numbers as they are),
--          world = keep the places of the save (false — move it to where the object stands) }
local function smhImport(ply, id, fileName, entName, ent, opts)
	local data = util.JSONToTable(file.Read(SMH_DIR .. fileName .. ".txt", "DATA") or "")
	if not istable(data) or not istable(data.Entities) then return "#sa_smh_bad" end
	local src
	for _, e in pairs(data.Entities) do
		local name = istable(e) and (istable(e.Properties) and e.Properties.Name or e.Model)
		if name == entName and istable(e.Frames) then src = e break end
	end
	if not src then return "#sa_smh_bad" end

	-- the keys of every modifier, sorted
	local mods, positions, seen = {}, {}, {}
	for _, fr in pairs(src.Frames) do
		local pos = num(fr.Position)
		if pos and istable(fr.EntityData) then
			for name, d in pairs(fr.EntityData) do
				mods[name] = mods[name] or {}
				local dd = d
				if name == "physbones" or name == "bones" then dd = numKeys(d) end
				if name == "flex" and istable(d) then dd = { Weights = numKeys(d.Weights), Scale = d.Scale } end
				if name == "bodygroup" then dd = numKeys(d) end
				table.insert(mods[name], { pos = pos, data = dd, inn = num(fr.EaseIn) or 0, out = num(fr.EaseOut) or 0 })
			end
			if not seen[pos] then
				seen[pos] = { inn = 0, out = 0 }
				positions[#positions + 1] = pos
			end
			seen[pos].inn = math.max(seen[pos].inn, num(fr.EaseIn) or 0)
			seen[pos].out = math.max(seen[pos].out, num(fr.EaseOut) or 0)
		end
	end
	if #positions == 0 then return "#sa_smh_bad" end
	table.sort(positions)
	for _, l in pairs(mods) do table.sort(l, function(x, y) return x.pos < y.pos end) end

	local a = anim(ply)
	local rag = S.IsRagdoll(ent)
	local base = capture(ent)
	if base.kind ~= "prop" then return "#sa_smh_kind" end
	local conv = (opts.fps and opts.fps > 0) and (a.fps / opts.fps) or 1
	local p0 = positions[1]
	local start = math.Clamp(math.floor(opts.start or 0), 0, SA.MAX_FRAMES - 1)
	local last = start + math.floor((positions[#positions] - p0) * conv + 0.5)
	if last > a.frames then a.frames = math.min(last, SA.MAX_FRAMES) end

	-- moving the save to the object: the shift and turn of its first root place
	local shiftPos, shiftYaw, pivot = vector_origin, 0, nil
	if not opts.world then
		local first
		if rag and mods.physbones then
			local d = modAt(mods.physbones, p0)
			first = d and d[0]
		elseif mods.position then
			first = modAt(mods.position, p0)
		end
		if first and vec(first.Pos) and ang(first.Ang) then
			local rp, ra = S.GetTransform(ent)
			pivot = first.Pos
			shiftPos = rp - first.Pos
			shiftYaw = math.NormalizeAngle(ra.y - first.Ang.y)
		end
	end
	local function place(p, an)
		if not pivot then return p, an end
		local lp = p - pivot
		lp:Rotate(Angle(0, shiftYaw, 0))
		return pivot + lp + shiftPos, Angle(an.p, an.y + shiftYaw, an.r)
	end

	local op = opBefore(ply, id, ent.SPeditor_UID)
	local uid = ent.SPeditor_UID
	local tr = a.tracks[uid] or { keys = {}, order = {} }
	a.tracks[uid] = tr
	local count = 0
	for i, pos in ipairs(positions) do
		local frame = start + math.floor((pos - p0) * conv + 0.5)
		if frame > a.frames or count >= SA.MAX_KEYS then break end
		local st = table.Copy(base)
		local function get(name)
			local l = mods[name]
			if not l then return nil end
			local d1, _, n2, u = modAt(l, pos)
			if n2 then return lerpTable(name, d1, n2.data, u) end
			return d1
		end
		local pb = rag and get("physbones")
		if pb and istable(pb[0]) and vec(pb[0].Pos) and ang(pb[0].Ang) then
			local rp, ra = place(pb[0].Pos, pb[0].Ang)
			st.pos, st.ang, st.phys = rp, ra, {}
			for pi = 1, ent:GetPhysicsObjectCount() - 1 do
				local d = pb[pi]
				if istable(d) and vec(d.Pos) and ang(d.Ang) then
					local wp, wa = place(d.Pos, d.Ang)
					local lp, la = WorldToLocal(wp, wa, rp, ra)
					st.phys[pi] = { p = lp, a = la }
				else
					st.phys[pi] = base.phys and base.phys[pi]
				end
			end
		elseif not rag then
			local ps = get("position")
			if istable(ps) and vec(ps.Pos) and ang(ps.Ang) then st.pos, st.ang = place(ps.Pos, ps.Ang) end
			local ms = get("modelscale")
			if istable(ms) and num(ms.ModelScale) then st.scale = math.Clamp(ms.ModelScale, 0.05, 10) end
		end
		local bones = get("bones")
		if istable(bones) then
			st.bones = {}
			for b, d in pairs(bones) do
				if istable(d) and b < ent:GetBoneCount() then
					local bp, ba, bs = vec(d.Pos) or Vector(0, 0, 0), ang(d.Ang) or Angle(0, 0, 0), vec(d.Scale) or Vector(1, 1, 1)
					if bp ~= vector_origin or ba ~= angle_zero or bs ~= ONE then st.bones[b] = { p = bp, a = ba, s = bs } end
				end
			end
		end
		local fx = get("flex")
		if istable(fx) and istable(fx.Weights) then
			st.flex = {}
			for f, w in pairs(fx.Weights) do
				w = num(w)
				if w and math.abs(w) > 0.001 and f < ent:GetFlexNum() then st.flex[f] = w end
			end
		end
		local sk = num(get("skin"))
		if sk then st.skin = math.floor(sk) end
		local bg = get("bodygroup")
		if istable(bg) then
			st.bg = {}
			for b, v in pairs(bg) do if num(v) then st.bg[b] = math.floor(v) end end
		end
		local col = get("color")
		if istable(col) and istable(col.Color) then
			local c = col.Color
			st.col = { num(c.r) or 255, num(c.g) or 255, num(c.b) or 255, num(c.a) or 255 }
		end
		-- easing: SMH eases a key's leaving (EaseOut) and the next key's arrival (EaseIn)
		local nextPos = positions[i + 1]
		local out, inn = seen[pos].out, nextPos and seen[nextPos].inn or 0
		local e = (out > 0 and inn > 0) and "ease" or (out > 0 and "ease_in") or (inn > 0 and "ease_out") or "linear"
		tr.keys[frame] = { e = e, st = st }
		count = count + 1
	end
	reorder(tr)
	opAfter(ply, op, uid)
	SA.SendSummary(ply)
	SA.ApplyAll(ply, a.cur)
	return nil, count
end

-- the parent body of a physics body (the nearest bone above with a body of its own)
local function physParent(ent, pi)
	local b = ent:GetBoneParent(ent:TranslatePhysBoneToBone(pi))
	while b and b >= 0 do
		local p = ent:TranslateBoneToPhysBone(b)
		if p and p >= 0 and ent:TranslatePhysBoneToBone(p) == b then return p end
		b = ent:GetBoneParent(b)
	end
end

-- An SMH save of the objects (old SMH format: every modifier gets keys of its own in SMH)
local function smhExport(ply, fileName, ents)
	local a = anim(ply)
	local out = { Map = game.GetMap(), Entities = {} }
	for _, ent in ipairs(ents) do
		local tr = a.tracks[ent.SPeditor_UID]
		if tr and #tr.order > 0 and not S.IsAux(ent) then
			local rag = S.IsRagdoll(ent)
			local frames = {}
			for i, f in ipairs(tr.order) do
				local k = tr.keys[f]
				local st = k.st
				local d = {}
				if rag and st.phys then
					local world = { [0] = { st.pos, st.ang } }
					for pi = 1, ent:GetPhysicsObjectCount() - 1 do
						local ph = st.phys[pi]
						if ph then world[pi] = { LocalToWorld(ph.p, ph.a, st.pos, st.ang) } end
					end
					local pb = {}
					for pi, w in pairs(world) do
						local e = { Pos = w[1], Ang = w[2], Moveable = false }
						local par = physParent(ent, pi)
						if par and world[par] then e.LocalPos, e.LocalAng = WorldToLocal(w[1], w[2], world[par][1], world[par][2]) end
						pb[pi] = e
					end
					d.physbones = pb
				end
				d.position = { Pos = st.pos, Ang = st.ang }
				local bones = {}
				for b = 0, ent:GetBoneCount() - 1 do
					local bb = st.bones and st.bones[b] or ZB
					bones[b] = { Pos = bb.p, Ang = bb.a, Scale = bb.s }
				end
				d.bones = bones
				if ent:GetFlexNum() > 0 then
					local w = {}
					for fi = 0, ent:GetFlexNum() - 1 do w[fi] = st.flex and st.flex[fi] or 0 end
					d.flex = { Scale = 1, Weights = w }
				end
				if st.skin then d.skin = st.skin end
				if st.bg then d.bodygroup = st.bg end
				if st.col then d.color = { Color = Color(st.col[1], st.col[2], st.col[3], st.col[4]) } end
				if not rag then d.modelscale = { ModelScale = st.scale or 1 } end
				local prevKey = i > 1 and tr.keys[tr.order[i - 1]]
				local e, pe = k.e, prevKey and prevKey.e
				frames[#frames + 1] = {
					Position = f,
					EaseOut = (e == "ease" or e == "ease_in" or e == "bezier") and 1 or 0,
					EaseIn = (pe == "ease" or pe == "ease_out" or pe == "bezier") and 1 or 0,
					EntityData = d,
				}
			end
			out.Entities[#out.Entities + 1] = { Model = string.GetFileFromFilename(ent:GetModel() or ""), Frames = frames }
		end
	end
	if #out.Entities == 0 then return "#sa_smh_nothing" end
	if not file.IsDir("smh", "DATA") then file.CreateDir("smh") end
	file.Write(SMH_DIR .. fileName .. ".txt", util.TableToJSON(out))
	return nil, #out.Entities
end

MOD:NetReceive("SMH", function(ply)
	local action = net.ReadUInt(2)          -- 0 — list, 1 — import, 2 — export
	if action == 0 then
		MOD:NetStart("SMH")
		SPeditor.WriteTable({ files = smhFiles() })
		net.Send(ply)
		return
	end
	local t = SPeditor.ReadTable() or {}
	local fileName = tostring(t.file or "")
	if action == 1 then
		-- an existing save only (its name as the folder lists it)
		local ok = false
		for _, f in ipairs(file.Find(SMH_DIR .. "*.txt", "DATA") or {}) do
			if string.StripExtension(f) == fileName then ok = true break end
		end
		if not ok then return end
		local ent = S.FindUID(ply, math.floor(tonumber(t.uid) or 0))
		if not IsValid(ent) then return end
		local err, n = smhImport(ply, math.floor(tonumber(t.op) or 0), fileName, tostring(t.ent or ""), ent,
			{ start = tonumber(t.start) or 0, fps = tonumber(t.fps) or 0, world = t.world and true or false })
		S.Notice(ply, err or ("#sa_smh_imported|" .. n), err and 1 or 2)
	elseif action == 2 then
		fileName = SPeditor.SafeName(fileName)
		if fileName == "" then return end
		local ents = {}
		for _, uid in ipairs(istable(t.uids) and t.uids or {}) do
			local e = S.FindUID(ply, math.floor(tonumber(uid) or 0))
			if IsValid(e) then ents[#ents + 1] = e end
		end
		local err, n = smhExport(ply, fileName, ents)
		S.Notice(ply, err or ("#sa_smh_exported|" .. n .. "|garrysmod/data/smh/" .. fileName .. ".txt"), err and 1 or 2)
	end
end)
