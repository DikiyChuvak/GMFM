--[[
SAeditor — server.

The animation is stored on the server, next to the objects it moves:
  A[ply] = { fps, frames, loop, cur, playing, tracks = { [uid] = track }, sounds = { clip, … } }
  track  = { keys = { [frame] = key }, order = { frames in ascending order } }
  key    = { e = "ease" | "linear" | "ease_in" | "ease_out" | "hold", st = object snapshot }
A key is a full snapshot of an object (position, pose, face, light, camera angle, the moment
of an effect) at a frame. Bone keys (a0.6): a key of a model may instead hold only some of its
parts — st.only = { [part] = true } — and a full key may leave some out — st.skip; a part is
"p<i>" (physics body i of a ragdoll, "p0" — the object itself / the root body) or "b<i>" (the
offset of bone i). Every part keyed that way moves between its own keys, the rest of the object
between the full keys, so each bone can have keys of its own, as in SFM. A face track (id = UID + SA.FACE, sh_saeditor.lua) keys only the
flexes of its object; while it exists, the face part of the body keys is left out; between keys the state is interpolated. A key never changes after it is created
(an edit replaces it with a new one), so a copy of a track for undo is just a new
table with references to the same keys.

Why the server: a ragdoll pose (physics bones) can only be set there, and
during playback the state has to be set every tick — sending it over the network
from the client would be both slow and uneven. The client only gets a "table of contents"
(which frames have keys) for the timeline.

Sound clips (SA.CleanSound in sh_saeditor.lua) are played and mixed by the client; the
server only keeps the list, so that it is saved with the scene. Camera cuts (a0.6) — which
scene camera the animation is watched through from which frame — are kept the same way:
a.cuts = { { f = frame, uid = camera }, … } (the player outside the editor and the video
render follow them).

Map movers (a0.7): doors, lifts, buttons and trains of the MAP that moved during a recorded
take (sv_saeditor_record.lua). They are not scene objects, so they have no track of their own:
a.world = { [MapCreationID] = { c = class, keys = { { f, pos, ang }, … } } } (local place, by
frame) moves them in playback, seeking and the render. Saved with the scene for its map.
Doors and lifts that were spawned (door tools, addons) have no map id: they are kept under
"e<entity index>" and found again only while an entity of the same class has that index.
]]
local COMP = SPeditor.Component("saeditor")
local SA  = COMP.SA
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
		a = { fps = 24, frames = 96, loop = true, cur = 0, playing = false, tracks = {}, sounds = {}, cuts = {}, world = {} }
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
		-- camera effects (depth of field, exposure, vignette…) are keyed too: the focus can be
		-- pulled from one actor to another
		return { kind = "camera", pos = ent:GetPos(), ang = ent:GetAngles(), fov = ent:GetCameraFOV(),
			shake = ent:GetShakeAmp(), shakerot = ent:GetShakeRot(), shakefreq = ent:GetShakeFreq(),
			fx = ent.SPeditor_FX and table.Copy(ent.SPeditor_FX) or nil }
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
	-- where the eyes look (b0.1): the point set in the face window (for a ragdoll local to its
	-- "eyes" attachment); a key without it lets the eyes look ahead by themselves
	if ent.SPeditor_Eye then st.eye = Vector(ent.SPeditor_Eye) end
	-- the material (whole and per slot), slot colours and stretching (b0.2.3): before, they were
	-- not keyed and one change showed over the whole timeline
	local look = ent.SPeditor_Look or {}
	st.mat = look.material or ""
	st.sub = look.submats and table.Copy(look.submats) or {}
	st.tints = look.tints and table.Copy(look.tints) or {}
	if S.CanScale(ent) then st.stretch = look.stretch and SPeditor.TableToVec(look.stretch) or Vector(1, 1, 1) end
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
	local ent = p:GetEntity()
	if IsValid(ent) then ent.SPeditor_Placed = true end   -- the editor's ragdoll guard keeps this place
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

	-- materials switch at a key like the skin, stretching moves (keys made before b0.2.3 have
	-- neither, and the object keeps what it has)
	if a.mat or a.stretch then
		local look = ent.SPeditor_Look or {}
		local sig = a.mat and (a.mat .. util.TableToJSON(a.sub or {}) .. util.TableToJSON(a.tints or {})) or nil
		local sa, sb = a.stretch, b.stretch or a.stretch
		local stv = sa and S.CanScale(ent) and lerpV(sa, sb, u) or nil
		if sig and sig ~= ent.SA_LookSig then
			look = table.Copy(look)
			look.material = a.mat ~= "" and a.mat or nil
			look.submats = next(a.sub or {}) and table.Copy(a.sub) or nil
			look.tints = next(a.tints or {}) and table.Copy(a.tints) or nil
			if stv then look.stretch = SPeditor.VecToTable(stv) end
			S.ApplyLook(ent, look)
			ent.SA_LookSig = sig
		elseif stv and stv:DistToSqr(ent:GetNW2Vector("SPeditor_Stretch", ONE)) > 1e-8 then
			local same = stv:DistToSqr(ONE) < 1e-6
			ent:SetNW2Vector("SPeditor_Stretch", same and ONE or stv)
			look.stretch = not same and SPeditor.VecToTable(stv) or nil
			ent.SPeditor_Look = next(look) ~= nil and look or nil
		end
	end

	-- the eyes: between two keys that both aim them the point moves over; a key without an
	-- aim takes the eyes back to looking ahead (when it is reached)
	local ea, eb = a.eye, b.eye
	local eye
	if ea and eb then eye = lerpV(ea, eb, u)
	elseif ea then eye = u < 1 and ea or nil
	elseif eb then eye = u >= 1 and eb or nil end
	if eye then
		if not ent.SPeditor_Eye or ent.SPeditor_Eye:DistToSqr(eye) > 0.0001 then S.SetEye(ent, eye) end
	elseif (ea or eb) and ent.SPeditor_Eye then
		S.SetEye(ent, nil)
	end

	-- colour and opacity (fading in and out)
	-- the keyed colour is applied whenever the object has another one: two hidden keys in a row
	-- keep a weapon hidden even when it was shown in the segment before (the recorder's weapons)
	local ca, cb = a.col, b.col or a.col
	local col = ca and Color(math.Round(lerpN(ca[1], cb[1], u)), math.Round(lerpN(ca[2], cb[2], u)),
		math.Round(lerpN(ca[3], cb[3], u)), math.Round(lerpN(ca[4], cb[4], u)))
	local now = col and ent:GetColor()
	if col and (now.r ~= col.r or now.g ~= col.g or now.b ~= col.b or now.a ~= col.a) then
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

-- Camera effects between two keys: numbers are blended, switches and materials are taken
-- from the key before. A key made before effects were keyed has none: the camera keeps its own.
local function applyCameraFX(ent, fa, fb, u)
	if not istable(fa) then return end
	fb = istable(fb) and fb or fa
	local fx = {}
	for id, pa in pairs(fa) do
		if istable(pa) then
			local pb = istable(fb[id]) and fb[id] or pa
			local p = {}
			for k, v in pairs(pa) do
				if isnumber(v) and isnumber(pb[k]) then p[k] = lerpN(v, pb[k], u) else p[k] = v end
			end
			fx[id] = p
		end
	end
	-- the effects travel as networked strings: they are sent only when they change
	if util.TableToJSON(fx) == util.TableToJSON(ent.SPeditor_FX or {}) then return end
	S.SetCameraFX(ent, fx)
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
	applyCameraFX(ent, a.fx, b.fx, u)
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

---------------------------------------------------------------------
-- Bone keys: which keys define which part
---------------------------------------------------------------------
local function defines(st, part)
	if st.only then return st.only[part] == true end
	return not (st.skip and st.skip[part])
end

local function partIndex(part) return string.sub(part, 1, 1), tonumber(string.sub(part, 2)) end

-- The frames of the full keys, and for every part named by some bone key the frames of the
-- keys that define it. Worked out again when the track changes (its order, its size or its
-- stamp, which setKey and the part operations bump).
local function cacheOf(tr)
	local c = tr.cache
	if c and c.order == tr.order and c.n == #tr.order and c.stamp == tr.stamp then return c end
	c = { order = tr.order, n = #tr.order, stamp = tr.stamp, full = {}, parts = {} }
	local special = {}
	for _, f in ipairs(tr.order) do
		local st = tr.keys[f].st
		if st.only then
			for p in pairs(st.only) do special[p] = true end
		else
			c.full[#c.full + 1] = f
			for p in pairs(st.skip or {}) do special[p] = true end
		end
	end
	c.has = next(special) ~= nil
	for p in pairs(special) do
		local list = {}
		for _, f in ipairs(tr.order) do
			if defines(tr.keys[f].st, p) then list[#list + 1] = f end
		end
		c.parts[p] = list
	end
	tr.cache = c
	return c
end
SA.TrackParts = cacheOf

---------------------------------------------------------------------
-- Spline (a0.6): a key of the kind "spline" makes the stretch to the next key a curve through
-- the keys around it, so the object passes a key without stopping. The state is a weighted sum
-- of four snapshots (SA.SplineWeights): numbers and vectors are added, turns are added as
-- quaternions (SA.BlendAngles). A value one of the snapshots lacks is taken from its neighbour
-- (a bone offset or a flex it lacks is zero, as everywhere).
---------------------------------------------------------------------
local COPY_FIELDS = { kind = true, only = true, skip = true, bg = true, skin = true, on = true,
	mat = true, sub = true, tints = true }
local ZERO_DEFAULT = { bones = ZERO_BONE, flex = 0 }

local function mix(vals, ws, def)
	local base = vals[2]
	if base == nil then base = vals[3] end
	if base == nil then return nil end
	local v = {}
	for i = 1, 4 do
		local x = vals[i]
		if x == nil or type(x) ~= type(base) then
			x = def
			if x == nil or type(x) ~= type(base) then x = (i <= 2) and (vals[2] or vals[3]) or (vals[3] or vals[2]) end
		end
		v[i] = x
	end
	if isnumber(base) then
		return v[1] * ws[1] + v[2] * ws[2] + v[3] * ws[3] + v[4] * ws[4]
	elseif isvector(base) then
		return v[1] * ws[1] + v[2] * ws[2] + v[3] * ws[3] + v[4] * ws[4]
	elseif isangle(base) then
		return SA.BlendAngles(v, ws, vals[2] ~= nil and 2 or 3)
	elseif istable(base) then
		local out, seen = {}, {}
		for _, t in ipairs({ v[2], v[3] }) do
			for k in pairs(t) do
				if not seen[k] then
					seen[k] = true
					if COPY_FIELDS[k] then
						out[k] = v[2][k]
						if out[k] == nil then out[k] = v[3][k] end
					else
						out[k] = mix({ v[1][k], v[2][k], v[3][k], v[4][k] }, ws, ZERO_DEFAULT[k])
					end
				end
			end
		end
		return out
	end
	return vals[2] ~= nil and vals[2] or vals[3]
end

-- children of "bones" / "flex" default to zero: mix passes the field's own default down one level
local function mixState(sts, ws)
	local out = {}
	local seen = {}
	for _, st in ipairs({ sts[2], sts[3] }) do
		for k in pairs(st) do
			if not seen[k] then
				seen[k] = true
				if COPY_FIELDS[k] then
					out[k] = sts[2][k]
					if out[k] == nil then out[k] = sts[3][k] end
				elseif ZERO_DEFAULT[k] ~= nil then
					local sub, ks = {}, {}
					for i = 1, 4 do
						for id in pairs(istable(sts[i][k]) and sts[i][k] or {}) do ks[id] = true end
					end
					for id in pairs(ks) do
						local vals = {}
						for i = 1, 4 do vals[i] = istable(sts[i][k]) and sts[i][k][id] or nil end
						-- a value missing from every key of the stretch keeps the old meaning: zero
						for i = 1, 4 do if vals[i] == nil then vals[i] = ZERO_DEFAULT[k] end end
						sub[id] = mix(vals, ws)
					end
					out[k] = sub
				else
					out[k] = mix({ sts[1][k], sts[2][k], sts[3][k], sts[4][k] }, ws)
				end
			end
		end
	end
	out.resolved = true
	return out
end

-- The two snapshots a track gives at the frame frame and the share of the way between them.
-- order — the frames to look at: the full keys by default (bone keys are left to the parts
-- they hold); nil when there are none. A spline stretch gives one worked-out snapshot twice.
local function segment(tr, frame, order)
	order = order or cacheOf(tr).full
	local n = #order
	if n == 0 then return nil end
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
	if ka.e == "spline" and ka.st.kind == kb.st.kind then
		local f0, f3 = order[lo - 1], order[hi + 1]
		local s0 = f0 and tr.keys[f0].st or ka.st
		local s3 = f3 and tr.keys[f3].st or kb.st
		if s0.kind ~= ka.st.kind then s0, f0 = ka.st, nil end
		if s3.kind ~= kb.st.kind then s3, f3 = kb.st, nil end
		local w0, w1, w2, w3 = SA.SplineWeights(f0 or (2 * fa - fb), fa, fb, f3 or (2 * fb - fa), (frame - fa) / (fb - fa))
		local st = mixState({ s0, ka.st, kb.st, s3 }, { w0, w1, w2, w3 })
		return st, st, 0
	end
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

-- one bone offset between two keys
local function lerpBone(ka, kb, u)
	return { p = lerpV(ka.p, kb.p, u), a = LerpAngle(u, ka.a, kb.a), s = lerpV(ka.s, kb.s, u) }
end

-- the state of a model between two snapshots, as one snapshot (what applyProp would set)
local function blendProp(a, b, u)
	local st = { kind = "prop", pos = lerpV(a.pos, b.pos, u), ang = slerp(a.ang, b.ang, u), bones = {}, flex = {},
		skin = a.skin, bg = a.bg, mat = a.mat, sub = a.sub, tints = a.tints }
	if a.stretch then st.stretch = lerpV(a.stretch, b.stretch or a.stretch, u) end
	if a.phys or b.phys then
		st.phys = {}
		local pa, pb = a.phys or {}, b.phys or {}
		for i, ka in pairs(pa) do
			local kb = pb[i] or ka
			st.phys[i] = { p = lerpV(ka.p, kb.p, u), a = slerp(ka.a, kb.a, u) }
		end
		for i, kb in pairs(pb) do
			if not pa[i] then st.phys[i] = kb end
		end
	end
	local ba, bb = a.bones or {}, b.bones or {}
	for id, ka in pairs(ba) do st.bones[id] = lerpBone(ka, bb[id] or ZERO_BONE, u) end
	for id, kb in pairs(bb) do
		if not ba[id] then st.bones[id] = lerpBone(ZERO_BONE, kb, u) end
	end
	local fa, fb = a.flex or {}, b.flex or {}
	for id, w in pairs(fa) do st.flex[id] = lerpN(w, fb[id] or 0, u) end
	for id, w in pairs(fb) do
		if not fa[id] then st.flex[id] = lerpN(0, w, u) end
	end
	if a.scale or b.scale then st.scale = lerpN(a.scale or 1, b.scale or 1, u) end
	if a.eye and b.eye then st.eye = lerpV(a.eye, b.eye, u) else st.eye = a.eye or (u >= 1 and b.eye) or nil end
	local ca, cb = a.col, b.col or a.col
	if ca then
		st.col = { math.Round(lerpN(ca[1], cb[1], u)), math.Round(lerpN(ca[2], cb[2], u)),
			math.Round(lerpN(ca[3], cb[3], u)), math.Round(lerpN(ca[4], cb[4], u)) }
	end
	return st
end

-- the value of a part in a snapshot that defines it
local function partValue(st, part)
	local kind, idx = partIndex(part)
	if idx == 0 and kind == "p" then return { p = st.pos, a = st.ang } end
	if kind == "p" then return st.phys and st.phys[idx] end
	if kind == "b" then return (st.bones or {})[idx] or ZERO_BONE end
end

-- A model whose track has bone keys, at a frame: the full keys give the base (or the object as
-- it is, when there are none), and every keyed part is worked out between its own keys.
local function resolveProp(ent, tr, frame)
	local c = cacheOf(tr)
	local a, b, u = segment(tr, frame, c.full)
	local st
	if a and a.kind == "prop" then
		st = blendProp(a, b, u)
	elseif not a then
		st = capture(ent)
		if st.kind ~= "prop" then return nil end
	else
		return nil
	end
	for part, list in pairs(c.parts) do
		local pa, pb, pu = segment(tr, frame, list)
		local va = pa and partValue(pa, part)
		local vb = pb and partValue(pb, part) or va
		va = va or vb
		if va then
			local kind, idx = partIndex(part)
			if kind == "p" and idx == 0 then
				st.pos, st.ang = lerpV(va.p, vb.p, pu), slerp(va.a, vb.a, pu)
			elseif kind == "p" then
				st.phys = st.phys or {}
				st.phys[idx] = { p = lerpV(va.p, vb.p, pu), a = slerp(va.a, vb.a, pu) }
			elseif kind == "b" then
				st.bones[idx] = lerpBone(va, vb, pu)
			end
		end
	end
	st.resolved = true
	return st
end

-- The state of a track at a frame as a single snapshot (the ghosts of the timeline)
function SA.StateAt(ent, tr, frame)
	if #tr.order == 0 then return nil end
	if cacheOf(tr).has and not S.IsAux(ent) then return resolveProp(ent, tr, frame) end
	local a, b, u = segment(tr, frame)
	if not a then return nil end
	if a.kind == "prop" and b.kind == "prop" then return blendProp(a, b, u) end
	return a
end

-- A track at the frame frame -> object
local function applyTrack(ent, tr, frame, noFace)
	if #tr.order == 0 then return end
	if cacheOf(tr).has and not S.IsAux(ent) then
		local st = resolveProp(ent, tr, frame)
		if st then applyProp(ent, st, st, 0, noFace) end
		return
	end
	local a, b, u = segment(tr, frame)
	if not a then return end
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
	if next(a.world or {}) ~= nil then SA.ApplyWorld(a, frame) end
end

---------------------------------------------------------------------
-- Map movers (doors, lifts, buttons): see the top of the file
---------------------------------------------------------------------
SA.MOVERS = { func_door = true, func_door_rotating = true, prop_door_rotating = true, func_movelinear = true,
	func_tracktrain = true, func_plat = true, func_platrot = true, func_rotating = true, func_button = true,
	func_rot_button = true, momentary_rot_button = true, func_water_analog = true }

-- the entity of a.world[id]: a map mover by its map id, a spawned one by "e<index>" + its class
function SA.WorldEnt(id, class)
	if isnumber(id) then return ents.GetMapCreatedEntity(id) end
	local idx = isstring(id) and tonumber(string.match(id, "^e(%d+)$"))
	local ent = idx and Entity(idx)
	if IsValid(ent) and ent:GetClass() == class then return ent end
	return nil
end

-- the id a mover is kept under in a.world
function SA.WorldId(ent)
	local id = ent:MapCreationID()
	if id and id > 0 then return id end
	return "e" .. ent:EntIndex()
end

-- the place of a mover at a frame: linear between the recorded samples, held before and after
local function worldAt(w, frame)
	local keys = w.keys
	local n = #keys
	if n == 0 then return nil end
	if frame <= keys[1].f then return keys[1].pos, keys[1].ang end
	if frame >= keys[n].f then return keys[n].pos, keys[n].ang end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if keys[mid].f <= frame then lo = mid else hi = mid end
	end
	local ka, kb = keys[lo], keys[hi]
	local u = (frame - ka.f) / math.max(kb.f - ka.f, 1e-6)
	return LerpVector(u, ka.pos, kb.pos), LerpAngle(u, ka.ang, kb.ang)
end

function SA.ApplyWorld(a, frame)
	for id, w in pairs(a.world or {}) do
		local ent = SA.WorldEnt(id, w.c)
		-- a mover being recorded right now moves by itself
		if IsValid(ent) and not ent.SPeditor_WorldRec then
			local pos, ang = worldAt(w, frame)
			if pos then
				ent:SetLocalPos(pos)
				ent:SetLocalAngles(ang)
			end
		end
	end
end

-- the movers back where the take found them (the animation of them is being removed)
local function worldRest(a)
	SA.ApplyWorld(a, -1)
end

function SA.ApplyTracks(a, map, frame)
	for id, tr in pairs(a.tracks) do
		local face = SA.IsFaceTrack(id)
		local ent = map[face and (id - SA.FACE) or id]
		-- an object whose physics is being recorded (sv_saeditor_record.lua) moves by itself
		if IsValid(ent) and not ent.SPeditor_PhysRec then
			local ok, err = pcall(applyTrack, ent, tr, frame, not face and a.tracks[SA.FaceTrack(id)] ~= nil)
			if not ok then COMP:Print("apply: ", tostring(err)) end
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
			-- bone keys: the parts a key holds ("p3,b17"), or those a full key leaves out
			local only = k.st.only and table.concat(table.GetKeys(k.st.only), ",") or ""
			local skip = k.st.skip and table.concat(table.GetKeys(k.st.skip), ",") or ""
			list[i] = { f, k.e, math.Round(p.x, 1), math.Round(p.y, 1), math.Round(p.z, 1), only, skip }
		end
		tracks[tostring(uid)] = SA.ToPages(list)
	end
	local proc = {}
	for uid, pr in pairs(a.proc or {}) do proc[tostring(uid)] = pr end
	SA.SendParts(ply, "Summary", { fps = a.fps, frames = a.frames, loop = a.loop, bounce = a.bounce, tracks = tracks, sounds = a.sounds or {}, proc = proc,
		cuts = a.cuts or {}, groups = a.groups or {}, marks = a.marks or {}, clips = a.clips or {} })
end

local function sendFrame(ply, serial)
	local a = anim(ply)
	COMP:NetStart("Frame")
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

-- a part takes the value v (partValue of another snapshot) in the snapshot st (a copy being built)
local function putPart(st, part, v)
	local kind, idx = partIndex(part)
	if not v then return end
	if kind == "p" and idx == 0 then
		st.pos, st.ang = v.p, v.a
	elseif kind == "p" then
		st.phys = st.phys or {}
		st.phys[idx] = v
	elseif kind == "b" then
		st.bones[idx] = (v ~= ZERO_BONE) and v or nil
	end
	if st.only then
		st.only[part] = true
	elseif st.skip then
		st.skip[part] = nil
		if next(st.skip) == nil then st.skip = nil end
	end
end

-- the part leaves the snapshot st (a copy); false — a bone key has nothing left
local function dropPart(st, part)
	if st.only then
		local kind, idx = partIndex(part)
		st.only[part] = nil
		if kind == "p" and idx > 0 and st.phys then st.phys[idx] = nil end
		if kind == "b" then st.bones[idx] = nil end
		return next(st.only) ~= nil
	end
	st.skip = st.skip or {}
	st.skip[part] = true
	return true
end

-- "p3,b17" -> { p3 = true, b17 = true } (only parts the object has); nil — none
local function parseParts(ent, list)
	if not IsValid(ent) or S.IsAux(ent) then return nil end
	local out, nb = {}, ent:GetBoneCount()
	local np = S.IsRagdoll(ent) and ent:GetPhysicsObjectCount() or 1
	for kind, idx in string.gmatch(list or "", "([pb])(%d+)") do
		idx = tonumber(idx)
		if (kind == "p" and idx < np) or (kind == "b" and idx < nb) then out[kind .. idx] = true end
	end
	return next(out) and out or nil
end
-- "parts:p3,b17|rest" -> parts list, rest; anything else -> nil, the string itself
local function splitParts(str)
	local list, rest = string.match(str, "^parts:([^|]*)|?(.*)$")
	if list then return list, rest end
	return nil, str
end

-- a bone key: an empty snapshot that names parts only (its place is kept for the path line)
local function emptyPart(pos, ang)
	return { kind = "prop", pos = pos, ang = ang, bones = {}, flex = {}, only = {} }
end

-- face = true: a key of the object's face track; parts — a bone key: only these parts of the
-- object are keyed (a key already at the frame gets them, the rest of it stays)
local function setKey(ply, ent, frame, ease, face, parts, def)
	local a = anim(ply)
	local uid = ent.SPeditor_UID
	if not uid then return false end
	if face then
		if S.IsAux(ent) then return false end
		uid = SA.FaceTrack(uid)
	end
	-- a key past the end makes the animation longer (a0.9, the endless timeline)
	frame = math.Clamp(math.floor(frame + 0.5), 0, SA.MAX_FRAMES)
	if frame > a.frames then a.frames = frame end
	local tr = a.tracks[uid]
	if not tr then
		tr = { keys = {}, order = {} }
		a.tracks[uid] = tr
	end
	if not tr.keys[frame] and #tr.order >= SA.MAX_KEYS then return false end
	local old = tr.keys[frame]
	local e = ease or (old and old.e) or def or "spline"
	local st
	if face then
		st = captureFace(ent)
	elseif parts and not S.IsAux(ent) then
		local now = capture(ent)
		st = (old and old.st.kind == "prop") and table.Copy(old.st) or emptyPart(now.pos, now.ang)
		for part in pairs(parts) do putPart(st, part, partValue(now, part)) end
	else
		st = capture(ent)
	end
	tr.keys[frame] = { e = e, bz = old and old.e == e and old.bz or nil, st = st }
	tr.stamp = (tr.stamp or 0) + 1
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

-- the body keys of ent from frame f0 to f1 (a recorded take replaces what was there)
function SA.ClearKeysIn(ply, ent, f0, f1)
	local tr = ent.SPeditor_UID and anim(ply).tracks[ent.SPeditor_UID]
	if not tr then return end
	local n = 0
	for f in pairs(tr.keys) do
		if f >= f0 and f <= f1 then
			tr.keys[f] = nil
			n = n + 1
		end
	end
	if n > 0 then
		reorder(tr)
		tr.stamp = (tr.stamp or 0) + 1
	end
end
SA.SetPhys = setPhys       -- for the recorder (sv_saeditor_record.lua)

local function dropEmpty(a, uid)
	local tr = a.tracks[uid]
	if tr and next(tr.keys) == nil then a.tracks[uid] = nil end
end

---------------------------------------------------------------------
-- Motion Editor (a0.7), as in SFM: an edit made at the current frame goes over a time
-- selection (SA.TimeSelWeight). The difference between the object now and what its
-- animation gives at that frame is added to every key in the selection, in full between
-- its inner edges and less and less over the falloff, so a whole stretch of motion is
-- changed with one edit and stays smooth at both ends. Keys are added at the edges of the
-- selection (and at the frame itself) first, so that nothing outside it changes.
---------------------------------------------------------------------
local MOTION_SKIP = { kind = true, pos = true, ang = true, phys = true, bones = true, flex = true,
	only = true, skip = true, resolved = true }
-- values that switch rather than move: taken over once the weight is past the half
local MOTION_SWITCH = { skin = true, bg = true, on = true, mat = true, sub = true, tints = true }

local function nearAng(x, y)
	return math.abs(math.AngleDifference(x.p, y.p)) < 0.001 and math.abs(math.AngleDifference(x.y, y.y)) < 0.001
		and math.abs(math.AngleDifference(x.r, y.r)) < 0.001
end

-- old turned by the turn that takes base to now, w of the way
local function turnBy(old, now, base, w)
	if nearAng(now, base) then return old end
	local mb, mn, mo = Matrix(), Matrix(), Matrix()
	mb:SetAngles(base)
	mn:SetAngles(now)
	mo:SetAngles(old)
	local target = (mn * mb:GetInverseTR() * mo):GetAngles()
	if w >= 0.999 then return target end
	return slerp(old, target, w)
end

local function angAdd(old, now, base, w)
	return Angle(old.p + math.AngleDifference(now.p, base.p) * w, old.y + math.AngleDifference(now.y, base.y) * w,
		old.r + math.AngleDifference(now.r, base.r) * w)
end

-- numbers, vectors and tables of them (colours, light fields, camera effects) move by the difference
local function motionOther(dst, now, base, w)
	for k, nv in pairs(now) do
		local bv, dv = base[k], dst[k]
		if MOTION_SKIP[k] or bv == nil or dv == nil then
			-- not a plain value, or the key does not hold it
		elseif MOTION_SWITCH[k] then
			if w >= 0.5 and util.TableToJSON({ nv }) ~= util.TableToJSON({ bv }) then dst[k] = istable(nv) and table.Copy(nv) or nv end
		elseif isnumber(nv) and isnumber(bv) and isnumber(dv) then
			if nv ~= bv then dst[k] = dv + (nv - bv) * w end
		elseif isvector(nv) and isvector(bv) and isvector(dv) then
			if nv ~= bv then dst[k] = dv + (nv - bv) * w end
		elseif istable(nv) and istable(bv) and istable(dv) then
			motionOther(dv, nv, bv, w)
		elseif nv ~= bv and w >= 0.5 and not istable(nv) then
			dst[k] = nv
		end
	end
end

-- the snapshot st (a copy) takes the edit now - base, w of it. noFlex: the face belongs to the
-- object's face track
local function motionApply(st, now, base, w, noFlex)
	if w <= 0 then return end
	if st.pos and now.pos and base.pos and defines(st, "p0") and st.kind ~= "face" then
		st.pos = st.pos + (now.pos - base.pos) * w
		st.ang = turnBy(st.ang, now.ang, base.ang, w)
	end
	if st.phys and now.phys and base.phys then
		for i, n in pairs(now.phys) do
			local b, o = base.phys[i], st.phys[i]
			if b and o and defines(st, "p" .. i) then
				st.phys[i] = { p = o.p + (n.p - b.p) * w, a = turnBy(o.a, n.a, b.a, w) }
			end
		end
	end
	if st.bones and now.bones and base.bones then
		local ids = {}
		for id in pairs(now.bones) do ids[id] = true end
		for id in pairs(base.bones) do ids[id] = true end
		for id in pairs(ids) do
			local n, b = now.bones[id] or ZERO_BONE, base.bones[id] or ZERO_BONE
			if defines(st, "b" .. id) and (n.p ~= b.p or n.s ~= b.s or not nearAng(n.a, b.a)) then
				local o = st.bones[id] or ZERO_BONE
				local nb = { p = o.p + (n.p - b.p) * w, a = angAdd(o.a, n.a, b.a, w), s = o.s + (n.s - b.s) * w }
				local zero = nb.p:IsZero() and nearAng(nb.a, angle_zero) and nb.s == ONE
				st.bones[id] = (not zero) and nb or nil
			end
		end
	end
	if st.only then return end      -- a bone key holds its parts only
	if st.flex and now.flex and base.flex and not noFlex then
		local ids = {}
		for id in pairs(now.flex) do ids[id] = true end
		for id in pairs(base.flex) do ids[id] = true end
		for id in pairs(ids) do
			local d = (now.flex[id] or 0) - (base.flex[id] or 0)
			if math.abs(d) > 0.0001 then
				local v = (st.flex[id] or 0) + d * w
				st.flex[id] = math.abs(v) > 0.001 and v or nil
			end
		end
	end
	if st.kind ~= "face" then motionOther(st, now, base, w) end
	if istable(st.col) then
		for i = 1, 4 do if isnumber(st.col[i]) then st.col[i] = math.Clamp(math.Round(st.col[i]), 0, 255) end end
	end
end

-- face = true: the object's face track (uid = its id). Returns false when the track has no
-- keys yet: then a plain key is set instead.
---------------------------------------------------------------------
-- The Motion Editor's procedural presets (b0.2, after SFM's Smooth, Sharp, Jitter, Hold,
-- Default): every key of a track inside the time selection is changed as much as the selection
-- weighs at its frame, times the strength. The values of a key are walked through: numbers,
-- vectors and turns; switches, materials and the like are left alone.
--   smooth  — half way towards the middle of the keys before and after it (removes bumps)
--   sharp   — away from that middle (makes the moves stronger)
--   jitter  — a random shake (place 1 unit, turn 1.5°, face 5 %; repeatable for the same key)
--   hold    — towards the first key of the selection (the pose stays)
--   default — bone offsets and faces towards zero (the model's own pose)
-- (round 6, the rest of SFM's list; SFM gives only the names, the behaviour is GM:FM's reading)
--   zero / half / one — face sliders to 0, 0.5, 1
--   in / out — towards the value entering / leaving the selection (at its outer edges)
--   ramp / spline / drop / release — from the value entering to the one leaving: straight,
--            smooth, speeding up, slowing down
--   round   — face sliders to off / on, places and turns to whole units / degrees
--   steady  — the smoothing four times over (removes a shake)
--   stagger — every next selected object plays the same motion 2 frames later
--   paste / playhead — towards the values of a copied frame / of the frame under the playhead
---------------------------------------------------------------------
local PRESET_SKIP = { time = true, scale = true, col = true, radius = true, bri = true, fov = true, frames = true, cycle = true }
local JITTER = { pos = 1, p = 1, ang = 1.5, a = 1.5, flex = 0.05 }   -- the shake of a field at full strength

-- section: the field of the snapshot the value is in (bones, phys, flex…), key: its own name
local function presetValue(v, prev, nxt, first, fn, key, section)
	if isnumber(v) then
		local function num(x) return isnumber(x) and x or v end
		return fn(v, num(prev), num(nxt), num(first), key, section)
	elseif isvector(v) then
		local function vec(x) return isvector(x) and x or v end
		local a, b, c = vec(prev), vec(nxt), vec(first)
		return Vector(fn(v.x, a.x, b.x, c.x, key, section, 1), fn(v.y, a.y, b.y, c.y, key, section, 2), fn(v.z, a.z, b.z, c.z, key, section, 3))
	elseif isangle(v) then
		-- the neighbours are taken the short way round from this key
		local function ang(x)
			if not isangle(x) then return v end
			return Angle(v.p + math.AngleDifference(x.p, v.p), v.y + math.AngleDifference(x.y, v.y), v.r + math.AngleDifference(x.r, v.r))
		end
		local a, b, c = ang(prev), ang(nxt), ang(first)
		return Angle(fn(v.p, a.p, b.p, c.p, key, section, 1), fn(v.y, a.y, b.y, c.y, key, section, 2), fn(v.r, a.r, b.r, c.r, key, section, 3))
	elseif istable(v) then
		local out = {}
		for k, x in pairs(v) do
			if COPY_FIELDS[k] or PRESET_SKIP[k] then
				out[k] = x
			else
				local function at(t) return istable(t) and t[k] or nil end
				out[k] = presetValue(x, at(prev), at(nxt), at(first), fn, k, section or k)
			end
		end
		return out
	end
	return v
end

-- The value of the track at frame t between its keys (orig: frame -> snapshot), lerped value by
-- value; before the first key / after the last one — that key
local function lerpState(a, b, u)
	return presetValue(a, b, nil, nil, function(v, x) return v + (x - v) * u end)
end
local function presetValueAt(order, orig, t)
	local n = #order
	if t <= order[1] then return orig[order[1]] end
	if t >= order[n] then return orig[order[n]] end
	for i = 1, n - 1 do
		local f0, f1 = order[i], order[i + 1]
		if t >= f0 and t <= f1 then
			if t == f0 or f1 == f0 then return orig[f0] end
			return lerpState(orig[f0], orig[f1], (t - f0) / (f1 - f0))
		end
	end
	return orig[order[n]]
end

-- the presets that pull a key towards a target value (the "first" argument of fn), and how
-- the target goes from the value entering the selection to the one leaving it (u: 0 … 1)
local TARGET_CURVES = {
	ramp = function(u) return u end,
	spline = function(u) return u * u * (3 - 2 * u) end,
	drop = function(u) return u * u end,
	release = function(u) return 1 - (1 - u) * (1 - u) end,
}
local FACE_VALUE = { zero = 0, half = 0.5, one = 1 }

-- extra: stagger — the object's place in the selection (0, 1, …); paste / playhead — the frame
-- whose values are taken
local function presetTrack(tr, preset, sel, strength, seed, extra)
	if not tr or #tr.order == 0 then return false end
	-- steady: the smoothing several times over
	local passes = preset == "steady" and 4 or 1
	local changed = false
	for _ = 1, passes do
		local orig, firstF = {}, nil
		for _, f in ipairs(tr.order) do
			orig[f] = tr.keys[f].st
			if not firstF and f >= sel[1] and f <= sel[4] then firstF = f end
		end
		if not firstF then return changed end
		local order = table.Copy(tr.order)
		local inV, outV = presetValueAt(order, orig, sel[1]), presetValueAt(order, orig, sel[4])
		local refV = (preset == "paste" or preset == "playhead") and presetValueAt(order, orig, extra or 0) or nil
		for i, f in ipairs(order) do
			local w = SA.TimeSelWeight(f, sel) * strength
			if w > 0 then
				local k = tr.keys[f]
				local prev = orig[order[i - 1] or -1]
				local nxt = orig[order[i + 1] or -1]
				local fn, first = nil, orig[firstF]
				local toward = function(v, _, _, c) return v + (c - v) * w end
				if preset == "smooth" or preset == "sharp" or preset == "steady" then
					-- at full strength a key goes half way to the middle of its neighbours (or as far away)
					local sign = preset == "sharp" and -0.5 or 0.5
					fn = function(v, a, b) return v + ((a + b) / 2 - v) * w * sign end
				elseif preset == "hold" then
					fn = toward
				elseif preset == "in" or preset == "out" then
					first = preset == "in" and inV or outV
					fn = toward
				elseif TARGET_CURVES[preset] then
					local u = math.Clamp((f - sel[1]) / math.max(sel[4] - sel[1], 1), 0, 1)
					first = lerpState(inV, outV, TARGET_CURVES[preset](u))
					fn = toward
				elseif preset == "paste" or preset == "playhead" then
					first = refV
					fn = toward
				elseif preset == "stagger" then
					-- each next object of the selection runs the same motion later (2 frames per
					-- object at full strength)
					local d = (extra or 0) * 2 * strength
					if d > 0 then
						first = presetValueAt(order, orig, f - d)
						local ws = SA.TimeSelWeight(f, sel)
						fn = function(v, _, _, c) return v + (c - v) * ws end
					end
				elseif FACE_VALUE[preset] then
					local x = FACE_VALUE[preset]
					fn = function(v, _, _, _, _, section)
						if section == "flex" then return v + (x - v) * w end
						return v
					end
				elseif preset == "round" then
					fn = function(v, _, _, _, key, section)
						-- face sliders to off / on, turns to whole degrees, places to whole units
						if section == "flex" then return v + (math.Round(v) - v) * w end
						if section == "bones" and key == "s" then return v end
						return v + (math.Round(v) - v) * w
					end
				elseif preset == "default" then
					fn = function(v, _, _, _, key, section)
						-- bone offsets and turns go to zero, sizes to one; faces to zero; the place of
						-- the object and a ragdoll's bodies stay
						if section == "flex" then return v - v * w end
						if section ~= "bones" then return v end
						if key == "s" then return v + (1 - v) * w end
						if key == "p" or key == "a" then return v - v * w end
						return v
					end
				elseif preset == "jitter" then
					fn = function(v, _, _, _, key, section, comp)
						local amp = section == "flex" and JITTER.flex or (JITTER[key] or 0)
						-- a ragdoll's bodies keep their distances: only their turns shake
						if section == "phys" and key == "p" then amp = 0 end
						if section == "bones" and key == "s" then amp = 0 end
						if amp == 0 then return v end
						local r = util.SharedRandom("gmfm_jitter", -1, 1, seed + f * 7 + (comp or 0) * 131 + #tostring(key) * 17)
						return v + r * amp * w
					end
				end
				if fn and first then
					tr.keys[f] = { e = k.e, bz = k.bz, st = presetValue(k.st, prev, nxt, first, fn) }
					changed = true
				end
			end
		end
	end
	if changed then
		tr.stamp = (tr.stamp or 0) + 1
		reorder(tr)
	end
	return changed
end

local function motionKey(ply, ent, uid, frame, sel, face)
	local a = anim(ply)
	local tr = a.tracks[uid]
	if not tr or #tr.order == 0 then return false end
	local noFace = not face and a.tracks[SA.FaceTrack(uid)] ~= nil
	local grab = face and captureFace or capture
	-- what the object is now, then what the animation gives at the frames that matter
	local now = grab(ent)
	local function stateAt(f)
		applyTrack(ent, tr, f, noFace)
		local st = grab(ent)
		st.resolved = nil
		return st
	end
	local base = stateAt(frame)
	local anchors = {}
	for _, f in ipairs({ sel[1], sel[2], frame, sel[3], sel[4] }) do
		f = math.Clamp(math.floor(f + 0.5), 0, a.frames)
		if not tr.keys[f] and not anchors[f] then anchors[f] = stateAt(f) end
	end
	-- the anchors become keys with the easing of the key before them
	for f, st in SortedPairs(anchors) do
		if #tr.order >= SA.MAX_KEYS then break end
		local e = "spline"
		for _, kf in ipairs(tr.order) do
			if kf < f then e = tr.keys[kf].e else break end
		end
		tr.keys[f] = { e = e == "bezier" and "spline" or e, st = st }
		reorder(tr)
	end
	for _, f in ipairs(tr.order) do
		local w = SA.TimeSelWeight(f, sel)
		local k = tr.keys[f]
		if w > 0 and k then
			local st = table.Copy(k.st)
			motionApply(st, now, base, w, noFace)
			tr.keys[f] = { e = k.e, bz = k.bz, st = st }
		end
	end
	tr.stamp = (tr.stamp or 0) + 1
	return true
end

---------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------
COMP:NetReceive("Sync", function(ply)
	SA.SendSummary(ply)
	sendFrame(ply)
end)

COMP:NetReceive("Config", function(ply)
	local a = anim(ply)
	a.fps    = math.Clamp(net.ReadUInt(8), 1, 120)
	a.frames = math.Clamp(net.ReadUInt(32), 1, SA.MAX_FRAMES)
	a.loop   = net.ReadBool()
	a.bounce = net.ReadBool() or nil
	a.cur    = math.min(a.cur, a.frames)
	SA.SendSummary(ply)
end)

COMP:NetReceive("Seek", function(ply)
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

SA.CleanSounds = cleanSounds

COMP:NetReceive("Sounds", function(ply)
	anim(ply).sounds = cleanSounds(SPeditor.ReadTable())
	SA.SendSummary(ply)
end)

-- Camera cuts, as a whole list (the client edits it and sends the result)
local function cleanCuts(list, frames)
	local out, seen = {}, {}
	for _, c in ipairs(istable(list) and list or {}) do
		local f, uid = tonumber(istable(c) and c.f), tonumber(istable(c) and c.uid)
		if f and uid and #out < 1000 then
			f = math.Clamp(math.floor(f + 0.5), 0, frames or SA.MAX_FRAMES)
			if not seen[f] then
				seen[f] = true
				out[#out + 1] = { f = f, uid = math.floor(uid) }
			end
		end
	end
	table.sort(out, function(x, y) return x.f < y.f end)
	return out
end

COMP:NetReceive("Cuts", function(ply)
	local a = anim(ply)
	a.cuts = cleanCuts(SPeditor.ReadTable(), a.frames)
	SA.SendSummary(ply)
end)

-- Tracks (a0.9, the track groups of SFM's clip editor): named groups of objects under the film
-- strip of the timeline. { { name, uids = { uid, … }, open }, … } — the client edits the whole
-- list; an object is in one track at most.
local MAX_GROUPS = 64
local function cleanGroups(list)
	local out, taken = {}, {}
	for _, g in ipairs(istable(list) and list or {}) do
		if #out >= MAX_GROUPS then break end
		if istable(g) then
			local name = isstring(g.name) and string.sub(string.gsub(g.name, "[%c]", ""), 1, 64) or ""
			local uids = {}
			for _, u in ipairs(istable(g.uids) and g.uids or {}) do
				u = tonumber(u)
				if u and u > 0 and not taken[u] and #uids < 512 then
					taken[u] = true
					uids[#uids + 1] = math.floor(u)
				end
			end
			out[#out + 1] = { name = name ~= "" and name or ("Track " .. (#out + 1)), uids = uids, open = g.open ~= false }
		end
	end
	return out
end

-- Bookmarks (b0.2, SFM's timeline bookmarks): { { f = frame, name }, … } sorted by frame, the
-- client edits the whole list
local MAX_MARKS = 256
local function cleanMarks(list)
	local out, seen = {}, {}
	for _, m in ipairs(istable(list) and list or {}) do
		if #out >= MAX_MARKS then break end
		local f = istable(m) and tonumber(m.f)
		if f and f == f then
			f = math.Clamp(math.floor(f + 0.5), 0, SA.MAX_FRAMES)
			if not seen[f] then
				seen[f] = true
				local name = isstring(m.name) and string.sub(string.gsub(m.name, "[%c]", ""), 1, 64) or ""
				out[#out + 1] = { f = f, name = name }
			end
		end
	end
	table.sort(out, function(x, y) return x.f < y.f end)
	return out
end
SA.CleanMarks = cleanMarks

COMP:NetReceive("Marks", function(ply)
	anim(ply).marks = cleanMarks(SPeditor.ReadTable())
	SA.SendSummary(ply)
end)

-- FX clips of the timeline (b0.2 round 6, cl_saeditor_fxclips.lua): { { k = kind, a = from,
-- b = to, fi, fo = fades in frames, p = parameters }, … }. A scene file and the client are
-- external data: kinds are checked, numbers clamped, texts cut, at most 64 clips.
local MAX_CLIPS = 64
local function cleanParams(p)
	local out, n = {}, 0
	for k, v in pairs(istable(p) and p or {}) do
		if n >= 24 then break end
		if isstring(k) and #k <= 24 then
			if isnumber(v) and v == v then
				out[k] = math.Clamp(v, -100000, 100000) n = n + 1
			elseif isbool(v) then
				out[k] = v n = n + 1
			elseif isstring(v) then
				out[k] = string.sub((string.gsub(v, "[%z\1-\8\11\12\14-\31]", "")), 1, 300) n = n + 1
			elseif istable(v) and tonumber(v.r or v[1]) then
				out[k] = { r = math.Clamp(tonumber(v.r or v[1]) or 0, 0, 255), g = math.Clamp(tonumber(v.g or v[2]) or 0, 0, 255),
					b = math.Clamp(tonumber(v.b or v[3]) or 0, 0, 255) }
				n = n + 1
			end
		end
	end
	return out
end
local function cleanClips(list)
	local out = {}
	for _, c in ipairs(istable(list) and list or {}) do
		if #out >= MAX_CLIPS then break end
		local a, b = istable(c) and tonumber(c.a), istable(c) and tonumber(c.b)
		if a and b and a == a and b == b and SA.CLIP_KINDS[c.k] then
			a = math.Clamp(math.floor(a + 0.5), 0, SA.MAX_FRAMES)
			b = math.Clamp(math.floor(b + 0.5), 0, SA.MAX_FRAMES)
			if b > a then
				out[#out + 1] = { k = c.k, a = a, b = b, fi = math.Clamp(math.floor(tonumber(c.fi) or 0), 0, b - a),
					fo = math.Clamp(math.floor(tonumber(c.fo) or 0), 0, b - a), p = cleanParams(c.p) }
			end
		end
	end
	table.sort(out, function(x, y) return x.a < y.a end)
	return out
end
SA.CleanClips = cleanClips

COMP:NetReceive("Clips", function(ply)
	anim(ply).clips = cleanClips(SPeditor.ReadTable())
	SA.SendSummary(ply)
end)

COMP:NetReceive("Groups", function(ply)
	anim(ply).groups = cleanGroups(SPeditor.ReadTable())
	SA.SendSummary(ply)
end)

COMP:NetReceive("Play", function(ply)
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

---------------------------------------------------------------------
-- Breaking a prop into its pieces (b0.2.4, asked on the Workshop: a crate that falls apart).
-- The gibs the model names in its "break" sections are made as scene props in their places
-- (a gib model shares the origin of the whole one); at the frame the prop vanishes and the
-- pieces appear (opacity keys, a hold key before it), and the client lets them fall with a
-- physics take from that frame (cl_saeditor_record.lua). One undo step on the client.
---------------------------------------------------------------------
function SA.GibModels(model)
	local info = util.GetModelInfo(model or "")
	local kv = info and info.KeyValues
	local out = {}
	if not isstring(kv) then return out end
	for m in string.gmatch(kv, '"break"%s*{[^}]-"model"%s*"([^"]+)"') do
		m = string.lower(string.gsub(m, "\\", "/"))
		if not string.StartWith(m, "models/") then m = "models/" .. m end
		if not string.EndsWith(m, ".mdl") then m = m .. ".mdl" end
		if util.IsValidModel(m) then out[#out + 1] = m end
	end
	return out
end

COMP:NetReceive("Break", function(ply)
	local id = net.ReadUInt(32)
	local ent = S.ReadOwned(ply)
	local frame = math.max(math.floor(net.ReadFloat() + 0.5), 1)
	if not ent or S.IsAux(ent) or S.IsRagdoll(ent) then return end
	local gibs = SA.GibModels(ent:GetModel())
	if #gibs == 0 then
		S.Notice(ply, "#brk_none", 1)
		return
	end
	local pos, ang = S.GetTransform(ent)
	local col = ent:GetColor()
	local function alpha(e, a)
		local c = Color(col.r, col.g, col.b, a)
		e:SetColor(c)
		e:SetRenderMode(a < 255 and RENDERMODE_TRANSCOLOR or RENDERMODE_NORMAL)
		local look = e.SPeditor_Look or {}
		look.color = (c.r < 255 or c.g < 255 or c.b < 255 or c.a < 255) and { c.r, c.g, c.b, c.a } or nil
		e.SPeditor_Look = next(look) ~= nil and look or nil
	end
	-- the prop is there up to the frame before, gone from the frame on
	local op = opBefore(ply, id, ent.SPeditor_UID)
	setKey(ply, ent, frame - 1, "hold")
	alpha(ent, 0)
	setKey(ply, ent, frame, "hold")
	opAfter(ply, op, ent.SPeditor_UID)
	-- the pieces: hidden before the frame, there from it on
	local uids = {}
	for i = 1, math.min(#gibs, 32) do
		local g = S.SpawnModel(ply, gibs[i], pos, ang)
		if IsValid(g) then
			if ent:GetModelScale() ~= 1 then S.SetScale(g, ent:GetModelScale()) end
			S.SetTransform(g, pos, ang)
			opBefore(ply, id, g.SPeditor_UID)
			alpha(g, 0)
			setKey(ply, g, frame - 1, "hold")
			alpha(g, col.a)
			setKey(ply, g, frame, "hold")
			opAfter(ply, op, g.SPeditor_UID)
			uids[#uids + 1] = g.SPeditor_UID
		end
	end
	SA.SendSummary(ply)
	COMP:NetStart("Break")
	net.WriteUInt(id, 32)
	net.WriteUInt(frame, 32)
	net.WriteUInt(#uids, 8)
	for _, u in ipairs(uids) do net.WriteUInt(u, 32) end
	net.Send(ply)
end)

COMP:NetReceive("Key", function(ply)
	local id     = net.ReadUInt(32)
	local action = net.ReadUInt(4)
	local uid    = net.ReadUInt(32)
	local frame  = net.ReadInt(32)
	local arg    = net.ReadInt(32)
	local str    = net.ReadString()
	local a = anim(ply)

	if action == OP.CLEAR_ALL then
		-- "Remove all animation" takes the sounds and the camera cuts too: else the player and
		-- the render go on playing the sounds of an animation that is not there any more
		local op = opBefore(ply, id, 0)
		for u in pairs(a.tracks) do opBefore(ply, id, u) end
		a.tracks = {}
		for u in pairs(op.before) do op.after[u] = false end
		op.sounds = { before = table.Copy(a.sounds or {}), after = {} }
		op.cuts = { before = table.Copy(a.cuts or {}), after = {} }
		-- and the doors of the map recorded in takes
		op.world = { before = table.Copy(a.world or {}), after = {} }
		worldRest(a)
		a.sounds, a.cuts, a.world = {}, {}, {}
		SA.SendSummary(ply)
		return
	end

	if action == OP.TIME or action == OP.SPEED then
		-- Editing the time of the whole animation (a0.9: the endless timeline and the film strip):
		--   TIME, arg > 0   arg frames inserted at `frame` — what is there and after moves later;
		--   TIME, arg < 0   frames `frame` … frame - arg - 1 cut out — what is after moves earlier;
		--   SPEED           frames `frame` … arg play at the speed in str (2 — twice as fast): the
		--                   keys between them close up or spread out, what is after follows.
		-- Keys of all tracks, sounds (by their start), camera cuts and recorded doors move alike.
		local map, newFrames
		if action == OP.TIME and arg > 0 then
			local at, n = math.max(frame, 0), math.min(arg, SA.MAX_FRAMES - a.frames)
			if n < 1 then return end
			map = function(f) return f >= at and f + n or f end
			newFrames = a.frames + n
		elseif action == OP.TIME then
			local at = math.Clamp(frame, 0, a.frames)
			local n = math.min(-arg, a.frames - at)
			if n < 1 or a.frames - n < 1 then return end
			map = function(f, keep)
				if f < at then return f end
				if f >= at + n then return f - n end
				return keep and at or nil
			end
			newFrames = a.frames - n
		else
			local f0, f1 = math.Clamp(frame, 0, a.frames), math.Clamp(arg, 0, a.frames)
			local k = math.Clamp(tonumber(str) or 1, 0.05, 20)
			if f1 <= f0 then return end
			local len = math.max(math.floor((f1 - f0) / k + 0.5), 1)
			local d = len - (f1 - f0)
			if a.frames + d > SA.MAX_FRAMES or a.frames + d < 1 then return end
			map = function(f)
				if f < f0 then return f end
				if f > f1 then return f + d end
				return f0 + math.floor((f - f0) / k + 0.5)
			end
			newFrames = a.frames + d
		end
		local op = opBefore(ply, id, 0)
		for u in pairs(a.tracks) do opBefore(ply, id, u) end
		op.sounds = { before = table.Copy(a.sounds or {}) }
		op.cuts = { before = table.Copy(a.cuts or {}) }
		op.world = { before = table.Copy(a.world or {}) }
		op.frames = { before = a.frames }
		for u, tr in pairs(a.tracks) do
			local keys = {}
			for _, f in ipairs(tr.order) do
				local to = map(f)
				if to then keys[to] = tr.keys[f] end
			end
			local moved = { keys = keys }
			reorder(moved)
			a.tracks[u] = next(keys) and moved or nil
			op.after[u] = a.tracks[u] and copyTrack(moved) or false
		end
		local sounds = {}
		for _, c in ipairs(a.sounds or {}) do
			local to = map(c.f)
			if to then c.f = to sounds[#sounds + 1] = c end
		end
		a.sounds = sounds
		-- a cut inside a cut-out stretch: the last one stays, at its start (the shot goes on)
		local cuts, byF = {}, {}
		for _, c in ipairs(a.cuts or {}) do
			local to = map(c.f, true)
			if to then
				if byF[to] then byF[to].uid = c.uid else
					local n = { f = to, uid = c.uid }
					byF[to] = n
					cuts[#cuts + 1] = n
				end
			end
		end
		a.cuts = cuts
		local marks = {}
		for _, mk in ipairs(a.marks or {}) do
			local to = map(mk.f, true)
			if to then marks[#marks + 1] = { f = to, name = mk.name } end
		end
		a.marks = cleanMarks(marks)
		-- an FX clip keeps its ends; one that is wholly cut out goes
		local clips = {}
		for _, c in ipairs(a.clips or {}) do
			local ca, cb = map(c.a, true), map(c.b, true)
			if ca and cb and cb > ca then
				c.a, c.b = ca, cb
				clips[#clips + 1] = c
			end
		end
		a.clips = cleanClips(clips)
		for _, w in pairs(a.world or {}) do
			local keys = {}
			for _, k in ipairs(w.keys or {}) do
				local to = map(k.f)
				if to then k.f = to keys[#keys + 1] = k end
			end
			w.keys = keys
		end
		a.frames = math.Clamp(newFrames, 1, SA.MAX_FRAMES)
		op.sounds.after, op.cuts.after, op.world.after = table.Copy(a.sounds), table.Copy(a.cuts), table.Copy(a.world or {})
		op.frames.after = a.frames
		SA.SendSummary(ply)
		SA.ApplyAll(ply, math.Clamp(map(a.cur or 0, true) or 0, 0, a.frames))
		return
	end

	local op = opBefore(ply, id, uid)
	local tr = a.tracks[uid]
	-- "parts:p3,b17|…": the operation is about these parts of the keys only (bone keys)
	local partList
	partList, str = splitParts(str)
	local owner = not SA.IsFaceTrack(uid) and S.FindUID(ply, uid) or nil
	local parts = partList and parseParts(owner, partList)
	if partList and not parts then
		opAfter(ply, op, uid)
		return
	end

	if action == OP.SET then
		local face = SA.IsFaceTrack(uid)
		local ent = S.FindUID(ply, face and (uid - SA.FACE) or uid)
		-- str — the easing of the new key (the client asks for "linear" when it plays an effect)
		local ease = (str ~= "bezier" and SA.ValidEase(str)) and str or nil
		-- "def:<ease>": what a NEW key gets (the client's choice, a0.8); a key there keeps its own
		local def = string.match(str, "^def:(.+)$")
		def = (def and def ~= "bezier" and SA.ValidEase(def)) and def or nil
		if IsValid(ent) and not setKey(ply, ent, frame, ease, face, parts, def) then S.Notice(ply, "#sa_keys_limit", 1) end
	elseif action == OP.MOTION then
		local face = SA.IsFaceTrack(uid)
		local ent = S.FindUID(ply, face and (uid - SA.FACE) or uid)
		local sel = SA.ParseTimeSel(str, a.frames)
		if IsValid(ent) and sel then
			frame = math.Clamp(frame, 0, a.frames)
			if not motionKey(ply, ent, uid, frame, sel, face) and not setKey(ply, ent, frame, nil, face) then
				S.Notice(ply, "#sa_keys_limit", 1)
			end
		end
	elseif parts and (action == OP.DELETE or action == OP.SHIFT) then
		-- bone keys of the listed frames: deleted, or moved / copied by arg frames
		if tr then
			local frames = {}
			for f in string.gmatch(str, "%d+") do frames[#frames + 1] = tonumber(f) end
			if #frames == 0 then frames[1] = frame end
			local moving = {}
			for _, f in ipairs(frames) do
				local k = tr.keys[f]
				if k and k.st.kind == "prop" then
					local vals = {}
					for part in pairs(parts) do
						if defines(k.st, part) then vals[part] = partValue(k.st, part) end
					end
					if next(vals) then
						moving[#moving + 1] = { f = f, k = k, vals = vals }
						if action == OP.DELETE or frame ~= 1 then
							local st, left = table.Copy(k.st), true
							for part in pairs(vals) do left = dropPart(st, part) end
							tr.keys[f] = left and { e = k.e, bz = k.bz, st = st } or nil
						end
					end
				end
			end
			if action == OP.SHIFT then
				for _, m in ipairs(moving) do
					local to = m.f + arg
					if to >= 0 and to <= a.frames then
						local dest = tr.keys[to]
						local st = (dest and dest.st.kind == "prop") and table.Copy(dest.st) or emptyPart(m.k.st.pos, m.k.st.ang)
						for part, v in pairs(m.vals) do putPart(st, part, v) end
						tr.keys[to] = { e = dest and dest.e or m.k.e, bz = dest and dest.bz or m.k.bz, st = st }
					end
				end
			end
			tr.stamp = (tr.stamp or 0) + 1
			reorder(tr)
			dropEmpty(a, uid)
		end
	elseif action == OP.DELETE then
		-- str = "f1,f2,…": several keys of the track at once
		if tr and str ~= "" then
			for f in string.gmatch(str, "%d+") do tr.keys[tonumber(f)] = nil end
			reorder(tr)
			dropEmpty(a, uid)
		elseif tr and tr.keys[frame] then
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
	elseif action == OP.SHIFT then
		if tr then
			local moving = {}
			for f in string.gmatch(str, "%d+") do
				f = tonumber(f)
				if tr.keys[f] then moving[f] = tr.keys[f] end
			end
			if frame ~= 1 then
				for f in pairs(moving) do tr.keys[f] = nil end
			end
			for f, k in pairs(moving) do
				local to = f + arg
				if to >= 0 and to <= a.frames then tr.keys[to] = k end
			end
			reorder(tr)
			dropEmpty(a, uid)
		end
	elseif action == OP.BAKE then
		-- (b0.2, as SFM's reparenting "maintain world" and "transfer motion to children") an attached
		-- object gets keys of where its parent takes it at every frame, then it is detached:
		-- it keeps moving the same way, and the parent can be changed on its own
		local ent = S.FindUID(ply, uid)
		if IsValid(ent) and ent.SPeditor_Attach then
			local step = math.max(math.ceil(a.frames / 600), 1)
			local frames = {}
			for f = 0, a.frames, step do frames[#frames + 1] = f end
			if frames[#frames] ~= a.frames then frames[#frames + 1] = a.frames end
			local places = {}
			for _, f in ipairs(frames) do
				SA.ApplyAll(ply, f)
				S.AttachFollow()
				local p, an = S.GetTransform(ent)
				places[#places + 1] = { f = f, pos = p, ang = an }
			end
			S.Detach(ent)
			for _, pl in ipairs(places) do
				SA.ApplyAll(ply, pl.f)
				S.SetTransform(ent, pl.pos, pl.ang)
				setKey(ply, ent, pl.f, "linear")
			end
			tr = a.tracks[uid]
		end
	elseif action == OP.PRESET then
		-- "preset|a0,a1,b0,b1,shape[|extra]": arg — the strength, percent; extra — the object's
		-- place (stagger) or the frame whose values are taken (paste, playhead)
		local preset, selStr, extra = string.match(str, "^(%a+)|([^|]+)|?(%-?%d*)$")
		local sel = selStr and SA.ParseTimeSel(selStr, a.frames)
		if sel and table.HasValue(SA.PRESETS, preset) then
			presetTrack(tr, preset, sel, math.Clamp(arg, 1, 200) / 100, uid % 9973, tonumber(extra))
		end
	elseif action == OP.EASE then
		-- "ease|f1,f2,…": one kind for several keys of the track
		local list = string.match(str, "|(.*)$")
		local frames = { frame }
		if list then
			str = string.match(str, "^[^|]*")
			frames = {}
			for f in string.gmatch(list, "%d+") do frames[#frames + 1] = tonumber(f) end
		end
		-- "bezier:x1,y1,x2,y2" — a curve of its own (the curve editor)
		local bz = string.sub(str, 1, 7) == "bezier:" and SA.ParseBezier(string.sub(str, 8)) or nil
		for _, f in ipairs(frames) do
			local k = tr and tr.keys[f]
			if k and bz then
				tr.keys[f] = { e = "bezier", bz = bz, st = k.st }
			elseif k and table.HasValue(SA.EASES, str) then
				tr.keys[f] = { e = str, st = k.st }
			end
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
COMP:NetReceive("Restore", function(ply)
	local id    = net.ReadUInt(32)
	local after = net.ReadBool()
	local ops = SA.Ops[ply]
	local op = ops and ops.items[id]
	if not op then return end
	local a = anim(ply)
	for uid, tr in pairs(after and op.after or op.before) do
		a.tracks[uid] = copyTrack(tr) or nil
	end
	if op.sounds then a.sounds = table.Copy(after and op.sounds.after or op.sounds.before) end
	if op.cuts then a.cuts = table.Copy(after and op.cuts.after or op.cuts.before) end
	if op.world then
		if after then worldRest(a) end
		a.world = table.Copy(after and op.world.after or op.world.before)
	end
	if op.frames then a.frames = after and op.frames.after or op.frames.before end
	SA.SendSummary(ply)
	SA.ApplyAll(ply, a.cur)
end)

-- Baking a model animation: the client computes bones on its copy of the model and
-- sends them one frame per message; the server applies the bones and takes a key at once.
COMP:NetReceive("Bake", function(ply)
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
-- Lip sync (a0.6): the client works out how the mouth moves in a voice clip (phonemes written
-- into the WAV as Faceposer / SFM write them, or the loudness) and sends mouth shapes by frame
-- (SA.LIP_CH channels, 0..1); here they become keys of the object's face track. Only the mouth
-- flexes (SA.MouthMap) change: the rest of the face keeps what the animation gives it there.
---------------------------------------------------------------------
-- flexes of a track at a frame: { [flex id] = weight } (body and face keys both carry them)
local function flexAt(tr, frame)
	local a, b, u = segment(tr, frame)
	if not a then return {} end
	local fa, fb, out = a.flex or {}, b.flex or {}, {}
	for id, w in pairs(fa) do out[id] = lerpN(w, fb[id] or 0, u) end
	for id, w in pairs(fb) do
		if not fa[id] then out[id] = lerpN(0, w, u) end
	end
	return out
end

COMP:NetReceive("Lip", function(ply)
	local id  = net.ReadUInt(32)
	local uid = net.ReadUInt(32)
	local n   = net.ReadUInt(16)
	local nch = #SA.LIP_CH
	local shapes = {}
	for i = 1, math.min(n, 20000) do
		local sh = { f = net.ReadUInt(32), c = {} }
		for j = 1, nch do sh.c[j] = net.ReadUInt(8) / 255 end
		shapes[i] = sh
	end
	local ent = S.FindUID(ply, uid)
	if not IsValid(ent) or S.IsAux(ent) or #shapes == 0 then return end
	local map = SA.MouthMap(ent)
	if not map then S.Notice(ply, "#sa_lip_noface", 1) return end
	local a = anim(ply)
	local fid = SA.FaceTrack(uid)
	local op = opBefore(ply, id, fid)
	local old, body = a.tracks[fid], a.tracks[uid]
	local face = ent:GetFlexNum() > 0 and captureFace(ent)
	if not face then return end

	-- the track the face comes from until now: the face track, or the face part of the body keys
	-- (a new face track takes the face of every body key, or the body keys would stop moving it)
	local tr = { keys = {}, order = {} }
	if old then
		for f, k in pairs(old.keys) do tr.keys[f] = k end
	elseif body and #body.order > 0 then
		for _, f in ipairs(body.order) do
			local st = body.keys[f].st
			if st.kind == "prop" and not st.only then
				tr.keys[f] = { e = body.keys[f].e, bz = body.keys[f].bz, st = { kind = "face", pos = st.pos, ang = st.ang, flex = table.Copy(st.flex or {}) } }
			end
		end
	end
	reorder(tr)
	local src = #tr.order > 0 and copyTrack(tr) or nil

	table.sort(shapes, function(x, y) return x.f < y.f end)
	-- the mouth of the lip sync at any frame of its span (between two shapes: in a straight line)
	local function mouthAt(frame)
		local lo, hi = shapes[1], shapes[#shapes]
		for i = 1, #shapes - 1 do
			if shapes[i].f <= frame and shapes[i + 1].f >= frame then lo, hi = shapes[i], shapes[i + 1] break end
		end
		local u = hi.f > lo.f and math.Clamp((frame - lo.f) / (hi.f - lo.f), 0, 1) or 0
		local out = {}
		for j = 1, nch do out[j] = lerpN(lo.c[j], hi.c[j], u) end
		return out
	end
	local function stateAt(frame, ch)
		local flex = src and flexAt(src, frame) or table.Copy(face.flex)
		for fl, wts in pairs(map) do
			local w = 0
			for j = 1, nch do w = w + (ch[j] or 0) * (wts[j] or 0) end
			local mn, mx = ent:GetFlexBounds(fl)
			w = math.Clamp(w, math.max(mn or 0, 0), mx or 1)
			flex[fl] = math.abs(w) > 0.001 and w or nil
		end
		return { kind = "face", pos = face.pos, ang = face.ang, flex = flex }
	end

	local f0, f1 = shapes[1].f, shapes[#shapes].f
	-- keys already inside the span keep the rest of their face, the mouth is that of the lip sync
	for f, k in pairs(tr.keys) do
		if f > f0 and f < f1 then tr.keys[f] = { e = k.e, bz = k.bz, st = stateAt(f, mouthAt(f)) } end
	end
	for _, sh in ipairs(shapes) do
		local f = sh.f
		-- the part of the sound past the end of the animation is not heard: no keys there
		if f > a.frames then break end
		if not tr.keys[f] and #tr.order >= SA.MAX_KEYS then break end
		tr.keys[f] = { e = "ease", st = stateAt(f, sh.c) }
		tr.order[#tr.order + 1] = f
	end
	reorder(tr)
	a.tracks[fid] = tr
	opAfter(ply, op, fid)
	SA.SendSummary(ply)
	SA.ApplyAll(ply, a.cur)
	S.Notice(ply, "#sa_lip_done|" .. #shapes, 2)
end)

---------------------------------------------------------------------
-- Ready camera moves (a0.6, cl_saeditor_easy.lua): the client works out the path (a dolly,
-- an orbit, a pan…) and sends its points; each becomes a key of the camera, with the rest of
-- the camera (its field of view, shake) as it is now unless the point sets it.
---------------------------------------------------------------------
COMP:NetReceive("Cam", function(ply)
	local id   = net.ReadUInt(32)
	local ent  = S.ReadOwned(ply)
	local ease = net.ReadString()
	local n    = math.min(net.ReadUInt(8), 64)
	local pts = {}
	for i = 1, n do
		pts[i] = { f = net.ReadUInt(32), pos = SPeditor.ReadVecF(), ang = SPeditor.ReadAngF(), shake = net.ReadFloat() }
	end
	if not IsValid(ent) or not S.IsCamera(ent) or n == 0 or not SA.ValidEase(ease) or ease == "bezier" then return end
	local a = anim(ply)
	local uid = ent.SPeditor_UID
	local op = opBefore(ply, id, uid)
	local tr = a.tracks[uid]
	if not tr then
		tr = { keys = {}, order = {} }
		a.tracks[uid] = tr
	end
	local base = capture(ent)
	for _, p in ipairs(pts) do
		if p.f <= a.frames and SPeditor.ValidVec(p.pos) and SPeditor.ValidAng(p.ang) and (tr.keys[p.f] or #tr.order < SA.MAX_KEYS) then
			local st = table.Copy(base)
			st.pos, st.ang = p.pos, p.ang
			-- a negative shake: the camera keeps its own
			if p.shake >= 0 then st.shake = p.shake end
			tr.keys[p.f] = { e = ease, st = st }
			reorder(tr)
		end
	end
	opAfter(ply, op, uid)
	SA.SendSummary(ply)
	SA.ApplyAll(ply, a.cur)
end)

---------------------------------------------------------------------
-- Ghosts (a0.6, cl_saeditor_ghost.lua): the client asks for the pose of an object at a few
-- frames (the keys around the playhead) and draws it see-through, as onion skin.
---------------------------------------------------------------------
COMP:NetReceive("Ghost", function(ply)
	local uid = net.ReadUInt(32)
	local n   = math.min(net.ReadUInt(4), 4)
	local frames = {}
	for i = 1, n do frames[i] = net.ReadUInt(32) end
	local ent = S.FindUID(ply, uid)
	local tr = anim(ply).tracks[uid]
	local out = { uid = uid, states = {} }
	if IsValid(ent) and tr and not S.IsAux(ent) then
		for _, f in ipairs(frames) do
			local ok, st = pcall(SA.StateAt, ent, tr, f)
			if ok and st and st.kind == "prop" then
				out.states[#out.states + 1] = { f = f, pos = st.pos, ang = st.ang, phys = st.phys, scale = st.scale }
			end
		end
	end
	COMP:NetStart("Ghost")
	SPeditor.WriteTable(out)
	net.Send(ply)
end)

---------------------------------------------------------------------
-- Playback
---------------------------------------------------------------------
COMP:Hook("Think", function()
	for ply, a in pairs(A) do
		if not IsValid(ply) then
			A[ply], SA.Ops[ply] = nil, nil
		elseif a.playing then
			local f = a.f0 + (CurTime() - a.t0) * a.fps
			if a.bounce and not a.show then
				f = SA.BounceFrame(f, a.frames)
			elseif f >= a.frames then
				-- outside the editor the show has its own loop setting
				local loop = a.loop
				if a.show then loop = a.showLoop end
				if loop then
					a.t0, a.f0 = CurTime(), 0
					f = 0
				else
					f = a.frames
					a.playing = false
				end
			end
			SA.ApplyAll(ply, f, a.playing)
			-- the end: the player outside the editor stays open at the last frame
			if not a.playing then sendFrame(ply) end
		end
	end
end, "play")

-- the editor is closed — playback stops; opened — a show outside the editor stops
COMP:Hook("SPeditor_PlayerState", function(ply, on)
	local a = A[ply]
	if a then
		a.playing, a.show = false, nil
		if a.procOn then SA.ApplyAll(ply, a.cur, false) end
	end
end)

-- Playing the animation outside the editor (a0.6, cl_saeditor_show.lua): the scene stays
-- on the map when the editor is closed, and the player watches it play in the game itself.
-- Works with the editor closed (noActive). on = false stops it.
-- action: 0 — stop the show, 1 — play from the start, 2 — pause, 3 — play on from frame,
-- 4 — go to frame (the player's seek bar and buttons)
COMP:NetReceive("Show", function(ply)
	local action = net.ReadUInt(3)
	local loop   = net.ReadBool()
	local frame  = net.ReadFloat()
	local a = A[ply]
	if not a or frame ~= frame then return end
	frame = math.Clamp(frame, 0, a.frames)
	a.showLoop = loop
	if action == 1 then
		if next(a.tracks) == nil and #(a.sounds or {}) == 0 then
			S.Notice(ply, "#sa_show_empty", 1)
			return
		end
		a.show = true
		a.playing = true
		a.cur = 0
		a.t0, a.f0 = CurTime(), 0
		SA.SendSummary(ply)
		SA.ApplyAll(ply, 0, true)
	elseif action == 0 then
		if not a.show then return end
		a.show, a.playing = nil, false
		SA.ApplyAll(ply, a.cur, false)
	elseif not a.show then
		return
	elseif action == 2 then
		a.playing = false
		SA.ApplyAll(ply, a.cur, false)
	elseif action == 3 then
		if frame >= a.frames then frame = 0 end
		a.playing, a.cur = true, frame
		a.t0, a.f0 = CurTime(), frame
		SA.ApplyAll(ply, frame, true)
	elseif action == 4 then
		a.cur = frame
		if a.playing then a.t0, a.f0 = CurTime(), frame end
		SA.ApplyAll(ply, frame, a.playing)
	end
	sendFrame(ply)
end, true)

-- "Clear scene" and loading another scene
COMP:Hook("SPeditor_PlayerCleanup", function(ply)
	if not A[ply] then return end
	local a = anim(ply)
	worldRest(a)
	a.tracks, a.sounds, a.playing, a.cur, a.proc, a.procOn, a.cuts, a.world, a.groups = {}, {}, false, 0, {}, nil, {}, {}, {}
	a.marks, a.clips = {}, {}
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
		-- bone keys: the sets of parts a key holds / leaves out
		local hadOnly = st.only ~= nil
		for _, field in ipairs({ "only", "skip" }) do
			if st[field] ~= nil then
				local set = {}
				for part, on in pairs(istable(st[field]) and st[field] or {}) do
					if on == true and isstring(part) and string.match(part, "^[pb]%d+$") then set[part] = true end
				end
				st[field] = next(set) and set or nil
			end
		end
		-- a bone key with nothing left in it would turn into a full key of nothing
		if hadOnly and not st.only then return false end
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
		if st.eye ~= nil and not SPeditor.ValidVec(st.eye) then st.eye = nil end
		if not isstring(st.mat) or #st.mat > 160 then st.mat, st.sub, st.tints = nil, nil, nil end
		if st.mat then
			st.sub = istable(st.sub) and st.sub or {}
			st.tints = istable(st.tints) and st.tints or {}
		end
		if st.stretch ~= nil and not SPeditor.ValidVec(st.stretch) then st.stretch = nil end
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

COMP:SceneData(function(ply, ctx)
	local a = A[ply]
	if not a or (next(a.tracks) == nil and #(a.sounds or {}) == 0 and #(a.cuts or {}) == 0 and next(a.world or {}) == nil
		and #(a.groups or {}) == 0) then return nil end
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
	-- camera cuts refer to their camera by its number in the scene
	local cuts = {}
	for _, c in ipairs(a.cuts or {}) do
		local ent = S.FindUID(ply, c.uid)
		local index = ent and ctx.indexOf[ent]
		if index then cuts[#cuts + 1] = { f = c.f, obj = index } end
	end
	-- tracks: their objects by their numbers in the scene
	local groups = {}
	for _, g in ipairs(a.groups or {}) do
		local objs = {}
		for _, u in ipairs(g.uids) do
			local ent = S.FindUID(ply, u)
			local index = ent and ctx.indexOf[ent]
			if index then objs[#objs + 1] = index end
		end
		groups[#groups + 1] = { name = g.name, objs = objs, open = g.open }
	end
	-- map movers: by their map id, valid on this map only
	local world
	if next(a.world or {}) ~= nil then
		world = { map = game.GetMap(), items = {} }
		for id, w in pairs(a.world) do
			local k = {}
			for i, key in ipairs(w.keys) do
				k[i] = { key.f, math.Round(key.pos.x, 2), math.Round(key.pos.y, 2), math.Round(key.pos.z, 2),
					math.Round(key.ang.p, 2), math.Round(key.ang.y, 2), math.Round(key.ang.r, 2) }
			end
			world.items[tostring(id)] = { c = w.c, k = k }
		end
	end
	return { version = 1, cuts = next(cuts) and cuts or nil, groups = next(groups) and groups or nil, marks = a.marks and #a.marks > 0 and a.marks or nil, clips = a.clips and #a.clips > 0 and a.clips or nil, fps = a.fps, frames = a.frames, loop = a.loop, bounce = a.bounce, tracks = tracks, faces = next(faces) and faces or nil,
		sounds = sounds, proc = next(proc) and proc or nil, world = world }
end, function(ply, data, ctx)
	local a = anim(ply)
	worldRest(a)
	a.tracks, a.sounds, a.playing, a.cur, a.proc, a.procOn, a.cuts, a.world, a.groups = {}, {}, false, 0, {}, nil, {}, {}, {}
	a.marks, a.clips = {}, {}
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
		a.bounce = data.bounce and true or nil
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
		local cuts = {}
		for _, c in ipairs(istable(data.cuts) and data.cuts or {}) do
			local ent = istable(c) and ctx.ents[tonumber(c.obj) or 0]
			if IsValid(ent) and ent.SPeditor_UID then cuts[#cuts + 1] = { f = c.f, uid = ent.SPeditor_UID } end
		end
		a.cuts = cleanCuts(cuts, a.frames)
		a.marks = cleanMarks(data.marks)
		a.clips = cleanClips(data.clips)
		local groups = {}
		for _, g in ipairs(istable(data.groups) and data.groups or {}) do
			if istable(g) then
				local uids = {}
				for _, index in ipairs(istable(g.objs) and g.objs or {}) do
					local ent = ctx.ents[tonumber(index) or 0]
					if IsValid(ent) and ent.SPeditor_UID then uids[#uids + 1] = ent.SPeditor_UID end
				end
				groups[#groups + 1] = { name = g.name, uids = uids, open = g.open }
			end
		end
		a.groups = cleanGroups(groups)
		-- map movers: only on the map the scene was made on, and only movers that are there
		local world = istable(data.world) and data.world or nil
		if world and world.map == game.GetMap() and istable(world.items) then
			for id, w in pairs(world.items) do
				id = tonumber(id) or (isstring(id) and string.match(id, "^e%d+$")) or nil
				local ent = id and istable(w) and SA.WorldEnt(id, w.c)
				if IsValid(ent) and istable(w.k) and SA.MOVERS[ent:GetClass()] then
					local keys = {}
					for _, k in ipairs(w.k) do
						if istable(k) and #k == 7 and #keys < SA.MAX_FRAMES then
							local f = tonumber(k[1])
							local pos = Vector(tonumber(k[2]) or 0, tonumber(k[3]) or 0, tonumber(k[4]) or 0)
							local ang = Angle(tonumber(k[5]) or 0, tonumber(k[6]) or 0, tonumber(k[7]) or 0)
							if f and SPeditor.ValidVec(pos) and SPeditor.ValidAng(ang) then keys[#keys + 1] = { f = f, pos = pos, ang = ang } end
						end
					end
					table.sort(keys, function(x, y) return x.f < y.f end)
					if #keys > 0 then a.world[id] = { c = ent:GetClass(), keys = keys } end
				end
			end
		end
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
--   noise  — (b0.1, as the Noise modifier of Blender's curves) a random but repeatable shake on
--            top of the keys: npos units and nrot degrees for the whole object (a camera held
--            in the hand, a car on a bumpy road, a ragdoll as one body), nbones = { [bone name] =
--            degrees } for single bones (a trembling hand, a head that is never quite still);
--            nfreq — how fast it changes, Hz; nseed — another pattern of the same noise
--   spin   — (b0.2, as SFM's "Create rotator") the object turns round one of its own axes all the
--            time: a wheel, a fan, a propeller, a turntable; degrees a second (minus — the other
--            way), spinax — the axis: 1 pitch (across), 2 yaw (up), 3 roll (forward)
local PROC_FIELDS = { breath = { 0, 1, 0 }, rate = { 4, 40, 14 }, blink = { 0, 1, 0 }, head = { 0, 1, 0 },
	sway = { 0, 64, 0 }, freq = { 0.02, 4, 0.3 }, flicker = { 0, 1, 0 },
	npos = { 0, 128, 0 }, nrot = { 0, 90, 0 }, nfreq = { 0.05, 8, 0.5 }, nseed = { 0, 999, 0 },
	spin = { -1440, 1440, 0 }, spinax = { 1, 3, 2 } }
local NOISE_BONES_MAX = 16

function SA.CleanProc(t)
	if not istable(t) then return nil end
	local out, any = {}, false
	for k, r in pairs(PROC_FIELDS) do
		out[k] = math.Clamp(tonumber(t[k]) or r[3], r[1], r[2])
	end
	if istable(t.nbones) then
		local nb, n = {}, 0
		for name, deg in pairs(t.nbones) do
			deg = tonumber(deg)
			if isstring(name) and #name < 128 and deg and deg > 0 and n < NOISE_BONES_MAX then
				nb[name] = math.min(deg, 90)
				n = n + 1
			end
		end
		out.nbones = n > 0 and nb or nil
	end
	any = out.breath > 0 or out.blink > 0 or out.head > 0 or out.sway > 0 or out.flicker > 0
		or out.npos > 0 or out.nrot > 0 or out.nbones ~= nil or out.spin ~= 0
	out.spinax = math.floor(out.spinax + 0.5)
	return any and out or nil
end

-- smooth noise -1..1 from sines of unrelated frequencies (the same for the same time and seed)
local function noise(t, seed)
	return (math.sin(t * 1.31 + seed) + 0.6 * math.sin(t * 2.71 + seed * 1.7) + 0.35 * math.sin(t * 5.13 + seed * 2.3)) / 1.95
end

-- value noise -1..1 (the noise modifier): random heights at whole t, smoothly joined, two
-- octaves — it never repeats the way the sines do
local function hash(i, seed)
	local r = math.sin(i * 127.1 + seed * 311.7) * 43758.5453
	return (r - math.floor(r)) * 2 - 1
end
local function vnoise(t, seed)
	local i = math.floor(t)
	local f = t - i
	local u = f * f * (3 - 2 * f)
	return hash(i, seed) + (hash(i + 1, seed) - hash(i, seed)) * u
end
local function fnoise(t, seed)
	return (vnoise(t, seed) + 0.5 * vnoise(t * 2.13 + 17.7, seed + 5.1)) / 1.5
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
			if s.bri then ent:SetLightBrightness(s.bri) end
			for _, it in ipairs(s.phys or {}) do
				local p = ent:GetPhysicsObjectNum(it[1])
				if IsValid(p) then setPhys(p, it[2], it[3]) end
			end
			for b, base in pairs(s.bones or {}) do ent:ManipulateBoneAngles(b, base) end
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
				local pi = hb and SPeditor.PhysOfBoneUp(ent, hb)
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
			-- a light that flickers (a0.9): a fire, a candle, a broken lamp — the brightness goes down
			-- and back in uneven jumps; more flicker — deeper and more often
			if pr.flicker > 0 and S.IsLight(ent) then
				local base = ent:GetLightBrightness()
				local ft = t * (2 + pr.freq * 6)
				local n = 0.5 + 0.5 * noise(ft * 3.7, seed + 9.3)
				local drop = pr.flicker * (0.35 * n + 0.65 * math.max(noise(ft * 7.9, seed + 2.2), 0) ^ 2)
				s.bri = base
				ent:SetLightBrightness(base * math.max(1 - drop, 0))
			end
			-- the noise modifier (b0.1)
			local np, nr = pr.npos or 0, pr.nrot or 0
			local nt = t * (pr.nfreq or 0.5)
			local ns = seed + (pr.nseed or 0) * 1.37
			if (np > 0 or nr > 0) and not ent.SPeditor_Attach then
				local off = Vector(fnoise(nt, ns), fnoise(nt, ns + 11.3), fnoise(nt, ns + 23.9)) * np
				local turn = Angle(fnoise(nt, ns + 31.1) * nr, fnoise(nt, ns + 41.7) * nr, fnoise(nt, ns + 53.3) * nr * 0.5)
				if S.IsRagdoll(ent) then
					-- the whole body as one: every physics body keeps its place relative to the
					-- root, and the root is shaken
					local root = ent:GetPhysicsObjectNum(0)
					if IsValid(root) then
						local rp, ra = root:GetPos(), root:GetAngles()
						local _, nra = LocalToWorld(vector_origin, turn, vector_origin, ra)
						local list = {}
						for i = 0, ent:GetPhysicsObjectCount() - 1 do
							local p = ent:GetPhysicsObjectNum(i)
							if IsValid(p) then list[#list + 1] = { i, p:GetPos(), p:GetAngles() } end
						end
						for _, it in ipairs(list) do
							local lp, la = WorldToLocal(it[2], it[3], rp, ra)
							local wp, wa = LocalToWorld(lp, la, rp + off, nra)
							setPhys(ent:GetPhysicsObjectNum(it[1]), wp, wa)
						end
						s.phys = list
					end
				else
					local pos, ang = ent:GetPos(), ent:GetAngles()
					if not s.pos then s.pos, s.ang = pos, ang end
					local _, na = LocalToWorld(vector_origin, turn, vector_origin, ang)
					ent:SetPos(pos + off)
					ent:SetAngles(na)
				end
			end
			-- the rotator (b0.2): a turn round the object's own axis, growing with the time
			local spin = pr.spin or 0
			if spin ~= 0 and not ent.SPeditor_Attach then
				local deg = (spin * t) % 360
				local ax = pr.spinax or 2
				local turn = Angle(ax == 1 and deg or 0, ax == 2 and deg or 0, ax == 3 and deg or 0)
				if S.IsRagdoll(ent) then
					local root = ent:GetPhysicsObjectNum(0)
					if IsValid(root) then
						local rp, ra = root:GetPos(), root:GetAngles()
						local _, nra = LocalToWorld(vector_origin, turn, vector_origin, ra)
						local list = {}
						for i = 0, ent:GetPhysicsObjectCount() - 1 do
							local p = ent:GetPhysicsObjectNum(i)
							if IsValid(p) then list[#list + 1] = { i, p:GetPos(), p:GetAngles() } end
						end
						for _, it in ipairs(list) do
							local lp, la = WorldToLocal(it[2], it[3], rp, ra)
							local wp, wa = LocalToWorld(lp, la, rp, nra)
							setPhys(ent:GetPhysicsObjectNum(it[1]), wp, wa)
						end
						if not s.phys then s.phys = list end
					end
				else
					local pos, ang = ent:GetPos(), ent:GetAngles()
					if not s.pos then s.pos, s.ang = pos, ang end
					-- round the middle of the model, not its origin (a wheel turns round its hub)
					local centre = S.IsAux(ent) and pos or ent:LocalToWorld(ent:OBBCenter())
					local _, na = LocalToWorld(vector_origin, turn, vector_origin, ang)
					local lc = WorldToLocal(centre, angle_zero, pos, ang)
					ent:SetAngles(na)
					ent:SetPos(centre - LocalToWorld(lc, angle_zero, vector_origin, na))
				end
			end
			if pr.nbones and not S.IsAux(ent) then
				for name, deg in pairs(pr.nbones) do
					local b = ent:LookupBone(name)
					if b then
						local base = ent:GetManipulateBoneAngles(b)
						local bs = ns + b * 7.31
						s.bones = s.bones or {}
						s.bones[b] = base
						ent:ManipulateBoneAngles(b, base + Angle(fnoise(nt, bs) * deg, fnoise(nt, bs + 3.3) * deg, fnoise(nt, bs + 6.6) * deg * 0.5))
					end
				end
			end
			ent.SA_Proc = next(s) and s or nil
		end
	end
end

COMP:NetReceive("Proc", function(ply)
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
		local pi = SPeditor.PhysOfBone(ent, part)
		if pi then
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
		-- bone keys: only the keys that hold this part are its keys
		local pid = (kind == "root") and "p0" or ((kind == "phys") and ("p" .. idx) or ("b" .. idx))
		for _, f in ipairs(tr.order) do
			local k = tr.keys[f]
			if defines(k.st, pid) then
				out.chans = out.chans or channels(k.st, kind)
				local vals = {}
				for c, ch in ipairs(out.chans) do vals[c] = chanGet(k.st, kind, idx, ch) or 0 end
				out.keys[#out.keys + 1] = { f = f, e = k.e, bz = k.bz, v = vals }
			end
		end
	end
	out.keys = SA.ToPages(out.keys)
	SA.SendParts(ply, "CurveData", out)
end

COMP:NetReceive("Curve", function(ply)
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

-- Where SMH saves are found: the game's own data/smh, the data_static/smh of addons (any
-- installed addon may ship saves there) and data/smh inside legacy addons (folders in
-- garrysmod/addons, whose data/ the game does not mount). Returns { { file = the name shown,
-- read = path, pathId } }; saves of addons are shown as "folder/name" or "[static] name".
local function smhSources()
	local out, seen = {}, {}
	local function add(shown, read, pathId)
		if #out >= 400 or seen[shown] then return end
		seen[shown] = true
		out[#out + 1] = { file = shown, read = read, pathId = pathId }
	end
	for _, f in ipairs(file.Find(SMH_DIR .. "*.txt", "DATA") or {}) do add(string.StripExtension(f), SMH_DIR .. f, "DATA") end
	-- saves kept in folders of their own (a0.9: data/smh/<folder>/<name>.txt, as downloads are often put)
	local _, sub = file.Find(SMH_DIR .. "*", "DATA")
	for _, d in ipairs(sub or {}) do
		for _, f in ipairs(file.Find(SMH_DIR .. d .. "/*.txt", "DATA") or {}) do
			add(d .. "/" .. string.StripExtension(f), SMH_DIR .. d .. "/" .. f, "DATA")
		end
	end
	for _, f in ipairs(file.Find("data_static/smh/*.txt", "GAME") or {}) do
		add("[static] " .. string.StripExtension(f), "data_static/smh/" .. f, "GAME")
	end
	local _, dirs = file.Find("addons/*", "MOD")
	for _, d in ipairs(dirs or {}) do
		for _, f in ipairs(file.Find("addons/" .. d .. "/data/smh/*.txt", "MOD") or {}) do
			add(d .. "/" .. string.StripExtension(f), "addons/" .. d .. "/data/smh/" .. f, "MOD")
		end
	end
	return out
end

local function smhFiles()
	local out = {}
	for _, src in ipairs(smhSources()) do
		if #out >= 200 then break end
		local data = util.JSONToTable(file.Read(src.read, src.pathId) or "")
		if istable(data) and istable(data.Entities) then
			local list = {}
			for _, e in pairs(data.Entities) do
				if istable(e) and istable(e.Frames) then
					local name = istable(e.Properties) and e.Properties.Name or e.Model
					list[#list + 1] = { name = tostring(name or "?"), model = tostring(e.Model or ""), frames = #e.Frames,
						world = istable(e.Properties) and e.Properties.IsWorld or nil }
				end
			end
			out[#out + 1] = { file = src.file, map = tostring(data.Map or ""), ents = list }
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
local function smhImport(ply, id, src, entName, ent, opts)
	local data = util.JSONToTable(file.Read(src.read, src.pathId) or "")
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
		local p = SPeditor.PhysOfBone(ent, b)
		if p then return p end
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

COMP:NetReceive("SMH", function(ply)
	local action = net.ReadUInt(2)          -- 0 — list, 1 — import, 2 — export
	if action == 0 then
		COMP:NetStart("SMH")
		SPeditor.WriteTable({ files = smhFiles() })
		net.Send(ply)
		return
	end
	local t = SPeditor.ReadTable() or {}
	local fileName = tostring(t.file or "")
	if action == 1 then
		-- an existing save only (its name as the list shows it)
		local src
		for _, f in ipairs(smhSources()) do
			if f.file == fileName then src = f break end
		end
		if not src then return end
		local ent = S.FindUID(ply, math.floor(tonumber(t.uid) or 0))
		if not IsValid(ent) then return end
		local err, n = smhImport(ply, math.floor(tonumber(t.op) or 0), src, tostring(t.ent or ""), ent,
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

---------------------------------------------------------------------
-- Slowed game time while an animation with effects renders (a0.8, cl_saeditor_video.lua).
-- Single player only. The client repeats its request every few seconds; when it stops asking
-- (the render ended badly, the game lost the client) the time goes back to what it was.
---------------------------------------------------------------------
local slow = { base = nil, untilT = 0 }
COMP:NetReceive("Slow", function(ply)
	local ts = net.ReadFloat()
	if not game.SinglePlayer() or ts ~= ts then return end
	ts = math.Clamp(ts, 0.02, 1)
	if ts >= 1 then
		if slow.base then game.SetTimeScale(slow.base) end
		slow.base = nil
		return
	end
	slow.base = slow.base or game.GetTimeScale()
	slow.untilT = RealTime() + 30       -- a heavy frame (4K, many passes) may take long
	game.SetTimeScale(ts)
end)

SPeditor.Hook("Think", "SPeditor.saeditor.Slow", function()
	if slow.base and RealTime() > slow.untilT then
		game.SetTimeScale(slow.base)
		slow.base = nil
	end
end)
SPeditor.Hook("ShutDown", "SPeditor.saeditor.Slow", function()
	if slow.base then game.SetTimeScale(slow.base) end
end)

---------------------------------------------------------------------
-- Physics on / off for a character (a0.9). A ragdoll's bones are its physics bodies: they keep
-- together and the ragdoll cannot be scaled. "Physics off" puts in its place the same model
-- without physics, posed by bone offsets — a limb can then be pulled off the body (Stretch) and
-- the whole model scaled; "physics on" goes back. The client works out the pose at the current
-- frame and at every key (cl_saeditor_extra.lua) and bakes it onto the new object; here:
--   Phys action 1 (rag/model) — the counterpart is made with the same look, name and place;
--   Phys action 2 (old, new)  — what was attached to the old one goes to the new one, the
--                               sounds and looks-at follow, the old one is removed.
---------------------------------------------------------------------
local function makeCounterpart(ply, ent)
	local toRag = not S.IsRagdoll(ent)
	local model = ent:GetModel()
	if toRag and not util.IsValidRagdoll(model) then return nil end
	local pos = S.GetTransform(ent)
	local new = ents.Create(toRag and "prop_ragdoll" or "prop_dynamic")
	if not IsValid(new) then return nil end
	new:SetModel(model)
	new:SetPos(toRag and ent:GetPos() or pos)
	new:SetAngles(toRag and ent:GetAngles() or angle_zero)
	new:Spawn()
	new:Activate()
	S.Freeze(new)
	S.StoreInit(new)
	if not toRag then
		new:SetPlaybackRate(0)
		new:SetCycle(0)
		new:SetNW2Float("SPeditor_Cycle", 0)
	end
	local skin, groups = S.CaptureAppearance(ent)
	S.ApplyAppearance(new, skin, groups)
	S.ApplyLook(new, S.CaptureLook(ent))
	for i = 0, math.min(ent:GetFlexNum(), new:GetFlexNum()) - 1 do new:SetFlexWeight(i, ent:GetFlexWeight(i)) end
	S.Track(ply, new)
	local name = ent.SPeditor_Name
	if name then
		new.SPeditor_Name = name
		new:SetNW2String("SPeditor_Name", name)
	end
	return new
end

COMP:NetReceive("Phys", function(ply)
	local action = net.ReadUInt(2)
	local old = S.ReadOwned(ply)
	if not IsValid(old) or S.IsAux(old) or old:GetBoneCount() < 2 then return end
	if action == 1 then
		local new = makeCounterpart(ply, old)
		COMP:NetStart("Phys")
		net.WriteEntity(old)
		net.WriteEntity(IsValid(new) and new or NULL)
		net.Send(ply)
		return
	end
	local new = S.ReadOwned(ply)
	if not IsValid(new) or new == old then return end
	-- what hangs on the old one: rigid attachments go to the root (a model without physics has
	-- no bodies to hold them), worn ones stay worn
	for e in pairs(S.Attached) do
		local at = IsValid(e) and e.SPeditor_Attach
		if at and at.parent == old then
			local bone = at.wear and S.WEAR or -1
			if not at.wear and at.bone >= 0 and S.IsRagdoll(new) then bone = new:LookupBone(old:GetBoneName(at.bone) or "") or -1 end
			S.Attach(e, new, bone)
		end
	end
	for e in pairs(S.Aimed) do
		local aim = IsValid(e) and e.SPeditor_Aim
		if aim and aim.target == old then S.SetAim(e, new, aim.bone >= 0 and new:LookupBone(old:GetBoneName(aim.bone) or "") or -1) end
	end
	local a = anim(ply)
	local ou, nu = old.SPeditor_UID, new.SPeditor_UID
	for _, c in ipairs(a.sounds or {}) do
		if c.uid == ou then c.uid = nu end
	end
	a.tracks[ou] = nil
	-- the face is animated the same way on both
	a.tracks[SA.FaceTrack(nu)] = a.tracks[SA.FaceTrack(ou)]
	a.tracks[SA.FaceTrack(ou)] = nil
	S.RemoveWithRecord(ply, old)
	SA.SendSummary(ply)
	SA.ApplyAll(ply, a.cur)
end)
