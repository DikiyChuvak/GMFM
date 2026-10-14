--[[
SAeditor — server.

The animation is stored on the server, next to the objects it moves:
  A[ply] = { fps, frames, loop, cur, playing, tracks = { [uid] = track }, sounds = { clip, … } }
  track  = { keys = { [frame] = key }, order = { frames in ascending order } }
  key    = { e = "ease" | "linear" | "hold", st = object snapshot }
A key is a full snapshot of an object (position, pose, face, light, camera angle, the moment
of an effect) at a frame; between keys the state is interpolated. A key never changes after it is created
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

local function applyProp(ent, a, b, u)
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

	local nf = ent:GetFlexNum()
	for id, wa in pairs(a.flex) do
		if id < nf then ent:SetFlexWeight(id, lerpN(wa, b.flex[id] or 0, u)) end
	end
	for id, wb in pairs(b.flex) do
		if not a.flex[id] and id < nf then ent:SetFlexWeight(id, lerpN(0, wb, u)) end
	end

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

local function applyState(ent, a, b, u)
	if a.kind ~= b.kind then b = a end
	if a.kind == "light" then
		if S.IsLight(ent) then applyLight(ent, a, b, u) end
	elseif a.kind == "camera" then
		if S.IsCamera(ent) then applyCamera(ent, a, b, u) end
	elseif a.kind == "effect" then
		if S.IsEffect(ent) then applyEffect(ent, a, b, u) end
	elseif not S.IsAux(ent) then
		applyProp(ent, a, b, u)
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
	return ka.st, kb.st, SA.EaseValue(ka.e, (frame - fa) / (fb - fa))
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
local function applyTrack(ent, tr, frame)
	if #tr.order == 0 then return end
	local a, b, u = segment(tr, frame)
	applyState(ent, a, b, u)
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

function SA.ApplyAll(ply, frame)
	local a = anim(ply)
	a.cur = frame
	if next(a.tracks) == nil then return end
	local map = entMap(ply)
	for uid, tr in pairs(a.tracks) do
		local ent = map[uid]
		if IsValid(ent) then
			local ok, err = pcall(applyTrack, ent, tr, frame)
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
	local c = { keys = keys }
	reorder(c)
	return c
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
		tracks[tostring(uid)] = list
	end
	MOD:NetStart("Summary")
	SPeditor.WriteTable({ fps = a.fps, frames = a.frames, loop = a.loop, tracks = tracks, sounds = a.sounds or {} })
	net.Send(ply)
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

local function setKey(ply, ent, frame, ease)
	local a = anim(ply)
	local uid = ent.SPeditor_UID
	if not uid then return false end
	frame = math.Clamp(math.floor(frame + 0.5), 0, a.frames)
	local tr = a.tracks[uid]
	if not tr then
		tr = { keys = {}, order = {} }
		a.tracks[uid] = tr
	end
	if not tr.keys[frame] and #tr.order >= SA.MAX_KEYS then return false end
	local old = tr.keys[frame]
	tr.keys[frame] = { e = ease or (old and old.e) or "ease", st = capture(ent) }
	if not old then reorder(tr) end
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
	a.frames = math.Clamp(net.ReadUInt(16), 1, SA.MAX_FRAMES)
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
	SA.ApplyAll(ply, math.Clamp(frame, 0, a.frames))
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
	SA.ApplyAll(ply, a.cur)
	sendFrame(ply)
end)

MOD:NetReceive("Key", function(ply)
	local id     = net.ReadUInt(32)
	local action = net.ReadUInt(4)
	local uid    = net.ReadUInt(32)
	local frame  = net.ReadInt(16)
	local arg    = net.ReadInt(16)
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
		local ent = S.FindUID(ply, uid)
		-- str — the easing of the new key (the client asks for "linear" when it plays an effect)
		local ease = table.HasValue(SA.EASES, str) and str or nil
		if IsValid(ent) and not setKey(ply, ent, frame, ease) then S.Notice(ply, "#sa_keys_limit", 1) end
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
		if k and table.HasValue(SA.EASES, str) then tr.keys[frame] = { e = str, st = k.st } end
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
	local frame = net.ReadUInt(16)
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
	if not S.IsRagdoll(ent) then return end
	local a = anim(ply)
	local uid = ent.SPeditor_UID
	local op = opBefore(ply, id, uid)
	local max = ent:GetPhysicsObjectCount()
	for _, b in ipairs(bones) do
		if b[1] < max then setPhys(ent:GetPhysicsObjectNum(b[1]), b[2], b[3]) end
	end
	local nb = ent:GetBoneCount()
	for _, b in ipairs(soft) do
		if b[1] < nb and SPeditor.ValidAng(b[2]) then ent:ManipulateBoneAngles(b[1], b[2]) end
	end
	S.SnapRigid(ent)
	setKey(ply, ent, math.min(frame, a.frames), "linear")
	opAfter(ply, op, uid)
	if net.ReadBool() then           -- the last frame of the series
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
			SA.ApplyAll(ply, f)
			if not a.playing then sendFrame(ply) end
		end
	end
end, "play")

-- the editor is closed — playback stops
MOD:Hook("SPeditor_PlayerState", function(ply, on)
	local a = A[ply]
	if a and not on then a.playing = false end
end)

-- "Clear scene" and loading another scene
MOD:Hook("SPeditor_PlayerCleanup", function(ply)
	if not A[ply] then return end
	local a = anim(ply)
	a.tracks, a.sounds, a.playing, a.cur = {}, {}, false, 0
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
	local tracks = {}
	for uid, tr in pairs(a.tracks) do
		local ent = S.FindUID(ply, uid)
		local index = ent and ctx.indexOf[ent]
		if index then
			local keys = {}
			for f, k in pairs(tr.keys) do keys[tostring(f)] = { e = k.e, st = enc(k.st) } end
			tracks[tostring(index)] = keys
		end
	end
	-- sounds refer to their object by its number in the scene too (0 — no object)
	local sounds = {}
	for i, c in ipairs(a.sounds or {}) do
		local ent = c.uid ~= 0 and S.FindUID(ply, c.uid) or nil
		sounds[i] = { id = c.id, path = c.path, f = c.f, obj = ent and ctx.indexOf[ent] or 0, voice = c.voice, vol = c.vol,
			pitch = c.pitch, dist = c.dist, cin = c.cin, cout = c.cout }
	end
	return { version = 1, fps = a.fps, frames = a.frames, loop = a.loop, tracks = tracks, sounds = sounds }
end, function(ply, data, ctx)
	local a = anim(ply)
	a.tracks, a.sounds, a.playing, a.cur = {}, {}, false, 0
	SA.Ops[ply] = nil
	if data then
		a.fps    = math.Clamp(math.floor(SPeditor.Num(data.fps, 24)), 1, 120)
		a.frames = math.Clamp(math.floor(SPeditor.Num(data.frames, 96)), 1, SA.MAX_FRAMES)
		a.loop   = data.loop and true or false
		for index, keys in pairs(istable(data.tracks) and data.tracks or {}) do
			local ent = ctx.ents[tonumber(index)]
			if IsValid(ent) and ent.SPeditor_UID and istable(keys) then
				local tr = { keys = {}, order = {} }
				local n = 0
				for f, k in pairs(keys) do
					f = tonumber(f)
					local st = istable(k) and dec(k.st)
					if f and f >= 0 and f <= a.frames and n < SA.MAX_KEYS and validState(st) then
						tr.keys[math.floor(f)] = { e = table.HasValue(SA.EASES, k.e) and k.e or "ease", st = st }
						n = n + 1
					end
				end
				if n > 0 then
					reorder(tr)
					a.tracks[ent.SPeditor_UID] = tr
				end
			end
		end
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
