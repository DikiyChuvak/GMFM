--[[
SPeditor — auto pose (b0.2.6-misc.1, after Cascadeur's AutoPosing, as a plain solver: no neural net).

With Auto pose on (View → Auto pose), a part pulled by the gizmo takes the body along:

  a hand    past the arm's reach: the chest bends and turns toward it, then the hips, then the
            body steps over (any ragdoll with an arm's IK chain)
  a foot    past the leg's reach: the hips turn and shift toward it, the chest stays upright
  the hips  moved: the body goes along, the planted feet stay and the hips stop where the legs
            no longer reach; the upper body leans the other way (balance). Turned: the chest
            turns back part of the way (a twist at the waist)
  the chest, neck or head  moved: the spine and hips bend toward it, the hips go back the other
            way (balance). Turned: the bodies below take a share of the turn
  (feet, hips, chest and head: only on a biped, see AP.Biped)

The feet stay planted (View → IK: keep the feet planted), the hands too when the hands are
planted; the knees and elbows keep bending the way they did, and the head keeps most of its
turn in the world (it looks where it looked).

It works on the physics bodies of a ragdoll, found by the bone tree, so it is not tied to the
Valve skeleton.

  AP.Biped(ent)                         { root, hips, upper, top, head, spine, feet, hands } or nil
  AP.Wants(ent, bone)                   a hand, or a foot of a biped: a limb drag of auto pose
  AP.Begin(ent, end, root, mid)         a limb drag: state (state.items are the gizmo drag's items) or nil
  AP.BeginBody(ent, bone)               a drag of the hips, the chest, the neck or the head: state or nil
  AP.Solve(state, target)               the pose for the dragged part at target (fills it.p1 / it.a1)
  AP.SolveTurn(state, axis, deg)        the pose for the dragged body turned (BeginBody only)
  C.AutoPoseOn() / C.SetAutoPose(on)
  gmfm_autopose_follow 0..1             how much the body follows (0 — plain IK)
]]
SPeditor = SPeditor or {}
SPeditor.AutoPose = SPeditor.AutoPose or {}
local AP = SPeditor.AutoPose
local C  = SPeditor.Client

local cvAuto   = CreateClientConVar("gmfm_autopose", "0", true, false, "Auto pose: a dragged hand, foot, the hips, chest or head take the body along (0/1)", 0, 1)
local cvFollow = CreateClientConVar("gmfm_autopose_follow", "1", true, false, "Auto pose: how much the body follows (0..1)", 0, 1)
function C.AutoPoseOn() return cvAuto:GetBool() end
-- (b0.2.6-misc.1) Auto pose works through IK (a hand's chain): turning it on turns IK on too
function C.SetAutoPose(on)
	RunConsoleCommand("gmfm_autopose", on and "1" or "0")
	if on and C.SetIK and not (C.gizmo and C.gizmo.ik) then C.SetIK(true) end
end
-- what the viewport shows: Auto pose that will act (IK or the rig is on)
function C.AutoPoseActive() return cvAuto:GetBool() and C.gizmo and (C.gizmo.ik or (C.RigOn and C.RigOn())) or false end

-- the share of the arm's full length where the body starts to help (a straight arm looks stiff);
-- a leg: a standing leg is nearly straight, and a kick reaches far
local COMFORT, COMFORT_LEG = 0.88, 0.95
-- how far each body of the torso may turn in one drag, degrees: the one nearest the shoulder
-- (the chest), the ones between, the root (the hips)
local MAX_NEAR, MAX_MID, MAX_ROOT = 40, 30, 25
-- the chest, neck or head pulled: the hips may bend further (a bow at the hips)
local MAX_HIPS = 60
-- how far the root may step toward the hand, in lengths of a leg: along the floor, down (a
-- crouch: the knees bend), up
local MAX_STEP, MAX_CROUCH, MAX_RISE = 0.35, 0.6, 0.1
local ITERATIONS = 8
-- the share of the arm's length where the hand starts to ease in (soft IK)
local SOFT = 0.1
-- (b0.2.6-misc.1) how much of its turn in the world the head keeps while the chest bends under it (the
-- eyes stay on what they looked at, as a person reaching does; 0 — it turns with the chest)
local HEAD_KEEP = 0.6
-- a turn of the head against the chest, at most (a head turned 180° with the hips stops there)
local MAX_HEAD = 70
-- balance, with a foot planted: the hips moved, the upper body leans back by this share of the hips'
-- move along the floor; the chest or head pulled, the hips go the other way by this share
local BALANCE_ROOT, BALANCE_SPINE = 0.5, 0.3
-- the hips turned or tilted: the chest turns back by this share, at most MAX_UPRIGHT degrees
local UPRIGHT, MAX_UPRIGHT = 0.6, 35
-- the chest, neck or head turned: each body between it and the hips takes this share of the turn
-- (at most MAX_SPREAD degrees), the hips SPREAD_ROOT (at most MAX_SPREAD_ROOT)
local SPREAD, MAX_SPREAD, SPREAD_ROOT, MAX_SPREAD_ROOT = 0.3, 30, 0.15, 20

local FOOT = { "foot", "ankle", "hoof" }
local HAND = { "hand", "wrist", "paw" }
local function named(ent, bone, list)
	local n = string.lower(ent:GetBoneName(bone) or "")
	for _, p in ipairs(list) do
		if string.find(n, p, 1, true) then return true end
	end
	return false
end
function AP.IsHand(ent, bone) return not named(ent, bone, FOOT) and named(ent, bone, HAND) end
function AP.IsFoot(ent, bone) return named(ent, bone, FOOT) end

local function physParent(ent, bone)
	local b, guard = ent:GetBoneParent(bone), 0
	while b and b >= 0 and guard < 256 do
		if C.PhysIndexOfBone(ent, b) then return b end
		b = ent:GetBoneParent(b)
		guard = guard + 1
	end
end

local function isBelow(ent, bone, ancestor)
	local b, guard = bone, 0
	while b and b >= 0 and guard < 256 do
		if b == ancestor then return true end
		b = ent:GetBoneParent(b)
		guard = guard + 1
	end
	return false
end

local function rotateVec(v, k, deg)
	local th = math.rad(deg)
	local c, s = math.cos(th), math.sin(th)
	return v * c + k:Cross(v) * s + k * (k:Dot(v) * (1 - c))
end

-- the bodies in list turn by deg around axis k through pivot
local function turnAround(list, pivot, k, deg)
	for _, it in ipairs(list) do
		it.p1 = pivot + rotateVec(it.p1 - pivot, k, deg)
		it.a1 = rotateVec(it.a1:Forward(), k, deg):AngleEx(rotateVec(it.a1:Up(), k, deg))
	end
end

-- only the places of the bodies in list (their turns are set later)
local function turnPoints(list, pivot, k, deg)
	for _, it in ipairs(list) do it.p1 = pivot + rotateVec(it.p1 - pivot, k, deg) end
end

-- the turn that takes angle a to angle b: a unit axis and degrees (0..180), nil when there is none
local function turnBetween(a, b)
	local f0, u0, f1, u1 = a:Forward(), a:Up(), b:Forward(), b:Up()
	local l0, l1 = u0:Cross(f0), u1:Cross(f1)
	local ax = f0:Cross(f1) + l0:Cross(l1) + u0:Cross(u1)
	local tr = f0:Dot(f1) + l0:Dot(l1) + u0:Dot(u1)
	local s = ax:Length()
	if s < 1e-6 then return nil end
	return ax / s, math.deg(math.atan2(s, tr - 1))
end

-- a body (with what hangs below it, list) turns back toward its turn at the start, by share of it
local function keepTurn(it, list, share, maxDeg)
	local ax, deg = turnBetween(it.a1, it.a0)
	if not ax then return end
	deg = deg * share
	if maxDeg then deg = math.min(deg, maxDeg) end
	turnAround(list, it.p1, ax, deg)
end

-- the way a two-link limb bends (root, mid, end places): the middle's offset from the root-end
-- line, as a direction; nil when the limb is straight
local function bendOf(r, m, e)
	local d = (e - r):GetNormalized()
	local off = (m - r) - d * (m - r):Dot(d)
	if off:LengthSqr() < 1e-6 then return nil end
	return off:GetNormalized()
end

-- the middle of a two-link limb of lengths l1, l2 from root toward target, bent toward pole (a
-- direction; as SPeditor.IK.Solve, but the bend comes from the given direction, not from where
-- the middle happens to be: a knee carried round by the hips can end up behind the hip-foot line,
-- and an elbow on the shoulder-hand line has no side at all)
local function solveLimb(root, l1, l2, target, pole)
	local toT = target - root
	local dist = toT:Length()
	if dist < 1e-3 then return nil end
	local dir = toT / dist
	local d = math.min(math.max(dist, math.abs(l1 - l2) * 1.0005 + 0.01), (l1 + l2) * 0.9995)
	local cosA = math.Clamp((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local side = pole - dir * pole:Dot(dir)
	if side:LengthSqr() < 1e-6 then
		local ref = (math.abs(dir.z) < 0.9) and Vector(0, 0, 1) or Vector(1, 0, 0)
		side = ref - dir * ref:Dot(dir)
	end
	return root + dir * (l1 * cosA) + side:GetNormalized() * (l1 * sinA), root + dir * d
end

-- a two-link chain (root, mid, end items) bent so that the end is at endPos with the turn
-- endAng; what hangs below the end goes along rigidly (as cl_gizmo.lua's solveChain). pole: the
-- bend direction (nil — the middle's own side, as plain IK)
local function solveChain(r, m, e, tail, endPos, endAng, pole)
	local IK = SPeditor.IK
	local midNew, endNew
	if pole then
		midNew, endNew = solveLimb(r.p1, r.p0:Distance(m.p0), m.p0:Distance(e.p0), endPos, pole)
	end
	if not midNew then midNew, endNew = IK.Solve(r.p1, m.p1, e.p1, endPos) end
	r.a1 = IK.RotateAngle(r.a1, m.p1 - r.p1, midNew - r.p1)
	m.a1 = IK.RotateAngle(m.a1, e.p1 - m.p1, endNew - midNew)
	m.p1 = midNew
	for _, t in ipairs(tail) do
		local lp, la = WorldToLocal(t.p1, t.a1, e.p1, e.a1)
		t.p1, t.a1 = LocalToWorld(lp, la, endNew, endAng)
	end
	e.p1, e.a1 = endNew, endAng
end

---------------------------------------------------------------------
-- The body: physics bodies and the biped's parts
---------------------------------------------------------------------
local function collect(ent)
	local items, byBone = {}, {}
	for b = 0, ent:GetBoneCount() - 1 do
		local pi = C.PhysIndexOfBone(ent, b)
		local p, a
		if pi then p, a = C.GetBoneWorld(ent, b) end
		if p and a then
			local it = { physIdx = pi, bone = b, p0 = p, a0 = a, p1 = p, a1 = a }
			items[#items + 1] = it
			byBone[b] = it
		end
	end
	return items, byBone
end

-- the body of bone and every body below it
local function subtree(ent, byBone, bone)
	local list = {}
	for b, it in pairs(byBone) do
		if isBelow(ent, b, bone) then list[#list + 1] = it end
	end
	return list
end

-- the bodies from bone's physics parent down to the root (or to stop, not included), the nearest
-- first, each with its turn limit and what turns with it
local function pathDown(ent, byBone, bone, stop, maxNear, maxMid, maxRoot)
	local path, j = {}, physParent(ent, bone)
	while j and j ~= stop and byBone[j] do
		path[#path + 1] = { it = byBone[j], bone = j }
		j = physParent(ent, j)
	end
	for i, t in ipairs(path) do
		t.max = (i == #path) and maxRoot or (i == 1 and maxNear or maxMid)
		t.list = subtree(ent, byBone, t.bone)
	end
	return path
end

-- the other limbs of the body that stay where they are: { root, mid, end, tail }
local function plantedLimbs(ent, byBone, skipEnd, feet, hands)
	local out = {}
	local locks = C.GetBoneLocks and C.GetBoneLocks(ent) or {}
	for b, it in pairs(byBone) do
		-- a locked bone follows its lock (cl_gizmo.lua postSolve), not the floor
		if b ~= skipEnd and not locks[b] and ((feet and named(ent, b, FOOT)) or (hands and AP.IsHand(ent, b))) then
			local mid = physParent(ent, b)
			local root = mid and physParent(ent, mid)
			if root and byBone[mid] and byBone[root] then
				local tail = {}
				for b2, it2 in pairs(byBone) do
					if b2 ~= b and isBelow(ent, b2, b) then tail[#tail + 1] = it2 end
				end
				-- a planted limb keeps bending the way it did (the knee points where it pointed);
				-- straight at the start: the way the root faces
				local pole = bendOf(byBone[root].p0, byBone[mid].p0, it.p0) or byBone[root].a0:Forward()
				out[#out + 1] = { byBone[root], byBone[mid], it, tail, pole = pole, foot = named(ent, b, FOOT) }
			end
		end
	end
	return out
end

-- (b0.2.6-misc.1) A biped: two legs (IK chains ending at a foot, own chains too) on the same body
-- (the hips), and a spine from the hips up to a head (or, without one, to where the arms hang).
-- Bone numbers only: cached with the rig's controls (an own IK chain set on the model drops it).
local function findBiped(ent)
	local Rig = SPeditor.Rig
	if not (Rig and Rig.ChainFor) then return nil end
	local feet, hands = {}, {}
	for b = 0, ent:GetBoneCount() - 1 do
		if C.PhysIndexOfBone(ent, b) then
			local root, mid = Rig.ChainFor(ent, b, true)
			if root then
				if named(ent, b, FOOT) then feet[#feet + 1] = { bone = b, root = root, mid = mid }
				elseif AP.IsHand(ent, b) then hands[#hands + 1] = { bone = b, root = root, mid = mid } end
			end
		end
	end
	-- two feet, not four (a horse, a spider): a body with more legs is posed limb by limb
	if #feet ~= 2 then return nil end
	local hips = physParent(ent, feet[1].root)
	if not hips or hips ~= physParent(ent, feet[2].root) then return nil end
	local root, guard = hips, 0
	while physParent(ent, root) and guard < 256 do
		root = physParent(ent, root)
		guard = guard + 1
	end
	local function onLimb(b)
		for _, l in ipairs(feet) do if isBelow(ent, b, l.root) then return true end end
		for _, l in ipairs(hands) do if isBelow(ent, b, l.root) then return true end end
		return false
	end
	local head
	for b = 0, ent:GetBoneCount() - 1 do
		if not head and C.PhysIndexOfBone(ent, b) and named(ent, b, { "head" }) and b ~= hips
			and isBelow(ent, b, hips) and not onLimb(b) then
			head = b
		end
	end
	local top = head or (hands[1] and physParent(ent, hands[1].root))
	if not top or top == hips or not isBelow(ent, top, hips) then return nil end
	-- the spine: the bodies from the one above the hips up to the top
	local spine, j = { [top] = true }, top
	guard = 0
	while physParent(ent, j) ~= hips and guard < 256 do
		j = physParent(ent, j)
		if not j then return nil end
		spine[j] = true
		guard = guard + 1
	end
	return { root = root, hips = hips, upper = j, top = top, head = head, spine = spine, feet = feet, hands = hands }
end

function AP.Biped(ent)
	if not (IsValid(ent) and C.IsRagdoll(ent)) then return nil end
	local Rig = SPeditor.Rig
	local cache = Rig and Rig.cache or {}
	local key = "autopose|" .. (ent:GetModel() or "") .. "|" .. ent:GetBoneCount()
	local hit = cache[key]
	if hit == nil then
		hit = findBiped(ent) or false
		cache[key] = hit
	end
	return hit or nil
end

-- a limb drag of auto pose: a hand (any ragdoll), a foot (a biped)
function AP.Wants(ent, bone)
	if AP.IsHand(ent, bone) then return true end
	return AP.IsFoot(ent, bone) and AP.Biped(ent) ~= nil
end

-- a leg's length (thigh to foot) from the start places of the items: a planted one's, else the biped's
local function legLength(ent, byBone, info, planted)
	for _, l in ipairs(planted) do
		if l.foot then return l[1].p0:Distance(l[2].p0) + l[2].p0:Distance(l[3].p0) end
	end
	info = info or AP.Biped(ent)
	local f = info and info.feet[1]
	if f and byBone[f.root] and byBone[f.mid] and byBone[f.bone] then
		return byBone[f.root].p0:Distance(byBone[f.mid].p0) + byBone[f.mid].p0:Distance(byBone[f.bone].p0)
	end
	return 40
end

local function anyFoot(planted)
	for _, l in ipairs(planted) do if l.foot then return true end end
	return false
end

-- the upper body above the hips (it stays upright while the hips turn), unless that is the head
local function uprightOf(ent, byBone, info, head)
	if not info or not byBone[info.upper] or (head and head.it == byBone[info.upper]) then return nil end
	return { it = byBone[info.upper], list = subtree(ent, byBone, info.upper) }
end

-- the hips bend round the hip joints, not round their own centre (that would lift the hip joints
-- off straight planted legs): round the stance hip when a foot is dragged and the feet are planted,
-- else round the middle of the two
local function hipsPivot(path, byBone, info, dragFoot)
	if not info then return end
	local thighs = {}
	for _, f in ipairs(info.feet) do
		if byBone[f.root] and f.bone ~= dragFoot then thighs[#thighs + 1] = byBone[f.root] end
	end
	if #thighs == 0 then return end
	if dragFoot and not C.gizmo.ikFeet then
		thighs = {}
		for _, f in ipairs(info.feet) do if byBone[f.root] then thighs[#thighs + 1] = byBone[f.root] end end
	end
	for _, t in ipairs(path) do
		if t.bone == info.hips then
			t.pivot = function()
				local p = Vector(0, 0, 0)
				for _, th in ipairs(thighs) do p = p + th.p1 end
				return p / #thighs
			end
		end
	end
end

---------------------------------------------------------------------
-- Drags
---------------------------------------------------------------------
-- a limb: the end (hand / foot) pulled through its two-link chain root - mid - end
function AP.Begin(ent, hand, shoulder, elbow)
	if not (IsValid(ent) and C.IsRagdoll(ent)) then return nil end
	local items, byBone = collect(ent)
	local S, F, H = byBone[shoulder], byBone[elbow], byBone[hand]
	if not (S and F and H) then return nil end
	local isLeg = named(ent, hand, FOOT)
	local info = isLeg and AP.Biped(ent) or nil
	if isLeg and not info then return nil end
	-- the torso: from the body the shoulder (the thigh) hangs on down to the root
	local torso = pathDown(ent, byBone, shoulder, nil, MAX_NEAR, MAX_MID, MAX_ROOT)
	if #torso == 0 then return nil end
	-- the head (a body named head on the torso, not on the limb): it keeps its turn, with what is below it
	local head
	for b, it in pairs(byBone) do
		if not head and named(ent, b, { "head" }) and isBelow(ent, b, torso[#torso].bone)
			and not isBelow(ent, b, shoulder) and not isBelow(ent, shoulder, b) then
			head = { it = it, list = subtree(ent, byBone, b) }
		end
	end
	-- what hangs below the hand (rare: a weapon body) goes with it
	local below = {}
	for b, it in pairs(byBone) do
		if b ~= hand and isBelow(ent, b, hand) then below[#below + 1] = it end
	end
	-- the elbow's way of bending, in the shoulder's frame: it turns with the chest
	local bend = bendOf(S.p0, F.p0, H.p0)
	local elbowPole = bend and WorldToLocal(bend, angle_zero, vector_origin, S.a0) or nil
	local st = { kind = "limb", ent = ent, items = items, S = S, F = F, H = H, E = H, torso = torso, below = below,
		elbowPole = elbowPole, head = head,
		l1 = S.p0:Distance(F.p0), l2 = F.p0:Distance(H.p0),
		planted = plantedLimbs(ent, byBone, hand, C.gizmo.ikFeet, C.gizmo.ikHands) }
	-- a leg pulled: the chest stays upright while the hips turn toward the foot
	if isLeg then
		st.upright = uprightOf(ent, byBone, info, head)
		hipsPivot(torso, byBone, info, hand)
	end
	-- a leg's length (the step of the root)
	st.leg = legLength(ent, byBone, info, st.planted)
	-- the limb's comfortable reach, but never less than the end already is (no jump at the start)
	st.reach = math.max((st.l1 + st.l2) * (isLeg and COMFORT_LEG or COMFORT), S.p0:Distance(H.p0))
	return st
end

-- the hips (the root) or a body of the spine (chest, neck, head) of a biped, moved or turned
function AP.BeginBody(ent, bone)
	if cvFollow:GetFloat() <= 0 then return nil end
	local info = AP.Biped(ent)
	if not info then return nil end
	local kind = (bone == info.hips or bone == info.root) and "root" or (info.spine[bone] and "spine") or nil
	if not kind then return nil end
	local items, byBone = collect(ent)
	local E = byBone[bone]
	if not E then return nil end
	local st = { kind = kind, ent = ent, items = items, E = E, Elist = subtree(ent, byBone, bone),
		planted = plantedLimbs(ent, byBone, nil, C.gizmo.ikFeet, C.gizmo.ikHands) }
	st.leg = legLength(ent, byBone, info, st.planted)
	st.feet = anyFoot(st.planted)
	-- the head keeps its turn in the world (the dragged head keeps all of it)
	if info.head and byBone[info.head] then
		if bone == info.head then
			st.keepE = true
		else
			st.head = { it = byBone[info.head], list = subtree(ent, byBone, info.head) }
		end
	end
	if kind == "root" then
		st.upright = uprightOf(ent, byBone, info, st.head)
		-- the upper body leans by its spine bodies (not the hips): the top is brought over
		st.top = byBone[info.top]
		st.upperPath = st.top and pathDown(ent, byBone, info.top, bone, MAX_MID, MAX_MID, MAX_MID) or {}
		if bone ~= info.hips then st.upperPath = {} end
	else
		st.torso = pathDown(ent, byBone, bone, nil, MAX_NEAR, MAX_MID, MAX_HIPS)
		hipsPivot(st.torso, byBone, info, nil)
		for _, t in ipairs(st.torso) do if t.pivot then st.hipsPath = t end end
		-- the bend is solved on a few bodies only (the path, the dragged one, the thighs and the roots
		-- of the planted limbs); every other body then goes along with its group rigidly: a frame of
		-- the drag stays as cheap as a hand's
		local isProxy, proxies = { [E] = true }, { E }
		local function addProxy(it)
			if it and not isProxy[it] then isProxy[it] = true proxies[#proxies + 1] = it end
		end
		for _, t in ipairs(st.torso) do addProxy(t.it) end
		for _, f in ipairs(info.feet) do addProxy(byBone[f.root]) end
		for _, l in ipairs(st.planted) do addProxy(l[1]) end
		st.proxies = proxies
		st.ptorso = {}
		-- the path bodies and the dragged one turn whole (the others go along with them); the thighs
		-- and the planted limbs' roots only need their places (the hips' pivot, the planted reach)
		local group = { [E] = true }
		for _, t in ipairs(st.torso) do group[t.it] = true end
		for i, t in ipairs(st.torso) do
			local pl, pts = {}, {}
			for _, it in ipairs(t.list) do
				if group[it] then pl[#pl + 1] = it elseif isProxy[it] then pts[#pts + 1] = it end
			end
			st.ptorso[i] = { it = t.it, bone = t.bone, max = t.max, pivot = t.pivot, list = pl, points = pts }
		end
		-- each body's group: the dragged body if it hangs below it, else the nearest path body above it
		local below = {}
		for _, it in ipairs(st.Elist) do below[it] = true end
		st.carry = {}
		for _, it in ipairs(items) do
			local g = below[it] and E or nil
			if not g then
				for _, t in ipairs(st.torso) do
					if isBelow(ent, it.bone, t.bone) then g = t.it break end
				end
			end
			if g and g ~= it then
				local lp, la = WorldToLocal(it.p0, it.a0, g.p0, g.a0)
				st.carry[#st.carry + 1] = { it = it, g = g, lp = lp, la = la }
			end
		end
	end
	return st
end

---------------------------------------------------------------------
-- Solving
---------------------------------------------------------------------
-- the bodies of chain (the nearest the point first) turn so that the item pt comes within reach of
-- target: cyclic coordinate descent, each body taking half of what is left, up to its own limit
local function ccd(chain, pt, target, reach, follow, used, fixed)
	for _ = 1, fixed or ITERATIONS do
		local toT = target - pt.p1
		local dist = toT:Length()
		-- fixed: every pass runs (the pose is then a smooth function of the target: a spine drag has no
		-- soft IK after it to hide where an early stop left the body)
		if (not fixed and dist - reach < 0.05) or dist < 1e-3 then break end
		for i, t in ipairs(chain) do
			local want = target - toT:GetNormalized() * reach      -- where the point should be
			local pivot = t.pivot and t.pivot() or t.it.p1
			local from, to = pt.p1 - pivot, want - pivot
			local axis = from:Cross(to)
			local s = axis:Length()
			if s > 1e-6 and from:LengthSqr() > 1e-4 then
				local deg = math.deg(math.atan2(s, from:Dot(to))) * 0.5 * follow
				local room = t.max * follow - (used[i] or 0)
				deg = math.min(deg, math.max(room, 0))
				if deg > 1e-3 then
					turnAround(t.list, pivot, axis / s, deg)
					if t.points then turnPoints(t.points, pivot, axis / s, deg) end
					used[i] = (used[i] or 0) + deg
				end
			end
			toT = target - pt.p1
		end
	end
end

-- the head turns back toward where it looked (round its own joint: the neck keeps its length)
local function keepHead(st, follow)
	local hd = st.head
	if hd and HEAD_KEEP > 0 then keepTurn(hd.it, hd.list, HEAD_KEEP * follow) end
end

local function shiftAll(st, v)
	for _, it in ipairs(st.items) do it.p1 = it.p1 + v end
end

-- a move of the whole body as a step: along the floor up to MAX_STEP of a leg, down to MAX_CROUCH,
-- up to MAX_RISE
local function stepLimit(st, v, follow)
	local flat = Vector(v.x, v.y, 0)
	local fl = flat:Length()
	local maxFlat = st.leg * MAX_STEP * follow
	if fl > maxFlat then flat = flat * (maxFlat / fl) end
	local z = math.Clamp(v.z, -st.leg * MAX_CROUCH * follow, st.leg * MAX_RISE * follow)
	return flat + Vector(0, 0, z)
end

-- the planted feet and hands: the body is pulled back toward the one that is furthest out (a
-- straight leg cannot follow the hips up); then they go back to where they were
local function pullBack(st)
	for _ = 1, 4 do
		local worst, dir
		for _, l in ipairs(st.planted) do
			-- never less than the limb is at the start: a standing leg is nearly straight already
			local len = math.max((l[1].p0:Distance(l[2].p0) + l[2].p0:Distance(l[3].p0)) * 0.995, l[1].p0:Distance(l[3].p0))
			local toE = l[3].p0 - l[1].p1
			local ex = toE:Length() - len
			if ex > 1e-3 and (not worst or ex > worst) then worst, dir = ex, toE:GetNormalized() end
		end
		if not worst then break end
		shiftAll(st, dir * worst)
	end
end

local function holdPlanted(st)
	pullBack(st)
	for _, l in ipairs(st.planted) do
		solveChain(l[1], l[2], l[3], l[4], l[3].p0, l[3].a0, l.pole)
	end
end

local function reset(st)
	for _, it in ipairs(st.items) do it.p1, it.a1 = it.p0, it.a0 end
end

local function solveLimbDrag(st, target, follow)
	local S = st.S
	if follow > 0 then
		-- the torso bends toward the hand (the hips toward the foot), the body nearest first
		ccd(st.torso, S, target, st.reach, follow, {})
		-- a foot: the chest turns back over the hips
		if st.upright then keepTurn(st.upright.it, st.upright.list, UPRIGHT * follow, MAX_UPRIGHT) end
		keepHead(st, follow)
		-- still out of reach: the whole body steps toward the hand (the feet stay, the legs bend):
		-- along the floor, down into a crouch, hardly up (the feet would have to leave the floor)
		local toT = target - S.p1
		local gap = toT:Length() - st.reach
		if gap > 0 then shiftAll(st, stepLimit(st, toT:GetNormalized() * gap * follow, follow)) end
	end
	holdPlanted(st)
	-- the limb reaches the end, which keeps its turn in the world (as plain IK)
	-- soft IK: in the last tenth of the arm's length the hand eases toward the target instead of
	-- snapping the elbow straight (near a straight arm the elbow swings fast for a little pull)
	local L = st.l1 + st.l2
	local toT = target - S.p1
	local dist = toT:Length()
	local soft = L * SOFT
	local ds = math.max(L - soft, st.S.p0:Distance(st.H.p0))
	if dist > ds and dist > 1e-3 and L - ds > 1e-3 then
		local room = L - ds
		target = S.p1 + toT * ((ds + room * (1 - math.exp(-(dist - ds) / room))) / dist)
	end
	local pole = st.elbowPole and LocalToWorld(st.elbowPole, angle_zero, vector_origin, S.a1) or nil
	solveChain(S, st.F, st.H, st.below, target, st.H.a0, pole)
end

-- the hips moved: the body goes along; with a foot planted the upper body leans the other way
local function solveRootDrag(st, target, follow)
	local shift = target - st.E.p0
	shiftAll(st, shift)
	if st.feet and st.top and #st.upperPath > 0 then
		local flat = Vector(shift.x, shift.y, 0)
		ccd(st.upperPath, st.top, st.top.p0 + shift - flat * (BALANCE_ROOT * follow), 0, 1, {})
	end
	keepHead(st, follow)
	holdPlanted(st)
end

-- the chest, neck or head moved: the hips go the other way (balance), the spine and the hips bend
-- toward it, what is left the body steps
local function solveSpineDrag(st, target, follow)
	local E = st.E
	local used = {}
	local all = st.items
	st.items = st.proxies
	-- the hips go back by up to BALANCE_SPINE of the drag along the floor, but only as far as the bent
	-- spine still reaches the target from the hip joints: the largest s in 0..1 with
	-- |target - (pivot + back * s)| <= the spine's radius (in closed form: smooth, and cheap per frame)
	if st.feet and st.hipsPath then
		local d = target - E.p0
		local back = stepLimit(st, Vector(d.x, d.y, 0) * (-BALANCE_SPINE * follow), follow)
		local a = back:LengthSqr()
		if a > 1e-6 then
			local pivot = st.hipsPath.pivot()
			local T = target - pivot
			-- (a spine of several bodies: a little short of straight, where the bend has no side)
			local R = E.p0:Distance(pivot) * (#st.torso > 1 and 0.97 or 1)
			local b, c = T:Dot(back), T:LengthSqr() - R * R
			local sh = 0
			if c <= 0 then
				sh = math.min(1, (b + math.sqrt(math.max(b * b - a * c, 0))) / a)
			end
			if sh > 0 then
				shiftAll(st, back * sh)
				pullBack(st)
			end
		end
	end
	ccd(st.ptorso, E, target, 0, follow, used, ITERATIONS * 2)
	-- the bend alone does not reach (a spine of one body moves the chest on a sphere round the hips):
	-- the body steps (crouches) toward it, the planted legs pull it back, the spine bends again
	local stepped = Vector(0, 0, 0)
	for _ = 1, 6 do
		local want = stepLimit(st, stepped + (target - E.p1) * follow, follow)
		shiftAll(st, want - stepped)
		stepped = want
		pullBack(st)
		ccd(st.ptorso, E, target, 0, follow, used, ITERATIONS)
	end
	-- every other body goes along with its group
	st.items = all
	for _, c in ipairs(st.carry) do
		c.it.p1, c.it.a1 = LocalToWorld(c.lp, c.la, c.g.p1, c.g.a1)
	end
	keepHead(st, follow)
	if st.keepE then keepTurn(E, st.Elist, 1) end
	holdPlanted(st)
end

function AP.Solve(st, target)
	reset(st)
	local follow = math.Clamp(cvFollow:GetFloat(), 0, 1)
	if st.kind == "root" then return solveRootDrag(st, target, follow) end
	if st.kind == "spine" then return solveSpineDrag(st, target, follow) end
	solveLimbDrag(st, target, follow)
end

-- the head turned by turn (degrees round axis, with the bodies under it) turns back by its share
local function keepHeadTurn(st, axis, turn, follow)
	local hd = st.head
	if not hd then return end
	turnAround(hd.list, hd.it.p1, axis, math.Clamp(-turn * HEAD_KEEP * follow, -MAX_HEAD, MAX_HEAD))
end

-- the dragged body turned by deg round axis (the gizmo's own: a turn past 180° stays smooth)
function AP.SolveTurn(st, axis, deg)
	reset(st)
	if st.kind == "limb" then return end
	local follow = math.Clamp(cvFollow:GetFloat(), 0, 1)
	local E = st.E
	if st.kind == "root" then
		turnAround(st.Elist, E.p1, axis, deg)
		local headTurn = deg
		-- the chest turns back part of the way (a twist at the waist)
		if st.upright then
			local c = math.Clamp(-deg * UPRIGHT * follow, -MAX_UPRIGHT, MAX_UPRIGHT)
			turnAround(st.upright.list, st.upright.it.p1, axis, c)
			headTurn = headTurn + c
		end
		keepHeadTurn(st, axis, headTurn, follow)
	else
		-- the bodies below, from the hips up, take their shares; the dragged body the rest
		local rest = deg
		for i = #st.torso, 1, -1 do
			local t = st.torso[i]
			local share, cap = SPREAD, MAX_SPREAD
			if i == #st.torso then share, cap = SPREAD_ROOT, MAX_SPREAD_ROOT end
			local d = math.Clamp(deg * share * follow, -cap, cap)
			turnAround(t.list, t.it.p1, axis, d)
			rest = rest - d
		end
		turnAround(st.Elist, E.p1, axis, rest)
		keepHeadTurn(st, axis, deg, follow)
	end
	-- the feet stay (the knees follow the hips round; where the legs no longer reach, the body comes down)
	holdPlanted(st)
end
