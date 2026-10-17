-- Move and rotate gizmo.
-- Hover is tested in viewport screen coordinates through C.ProjectToViewport
-- (point at an axis / ring and it lights up; the hit is exact).
-- Input only inside the Primary Viewport. A click on a bone selects the bone.
-- Halo is off in the nested viewport render (otherwise the frame darkens).
-- Move has plane handles too (the squares between two axes): they move in two
-- axes at once, e.g. along a diagonal on the floor.
-- Rotate has, besides the three axis rings, a ring around the line of sight (the outer one) and
-- a trackball (a0.6): drag anywhere inside the rings and the object turns freely in every
-- direction after the mouse, as in SFM and Blender; a click there without a drag still selects.
-- IK (I): a hand / foot pulls its limb; moving or turning the body keeps the feet
-- planted (C.gizmo.ikFeet). Bone locks (C.SetBoneLock): a physical bone of a ragdoll follows
-- another bone of the same ragdoll during a drag — e.g. the right hand holds on to the left one;
-- with IK on, the locked hand pulls its arm.
SPeditor.Client = SPeditor.Client or {}
local C = SPeditor.Client

local AXIS_COLORS = { Color(255, 80, 80), Color(80, 255, 80), Color(90, 150, 255) }
local HOVER_COLOR = Color(255, 230, 80)
local COL_LINE    = Color(255, 255, 255, 90)
local COL_PHYS    = Color(80, 220, 255)
local COL_MANIP   = Color(210, 210, 210)
local COL_SEL     = Color(255, 220, 60)
local COL_LOCK    = Color(255, 140, 40)
local COL_VIEWRING = Color(235, 235, 235)
local COL_BALL     = Color(255, 255, 255, 60)

C.gizmo = C.gizmo or {}
-- IK is on from the start (a0.7: people took a limb that would not bend as a bug) and the
-- choice is remembered
local cvIK = CreateClientConVar("speditor_ik", "1", true, false)
if C.gizmo.ik == nil then C.gizmo.ik = cvIK:GetBool() end
function C.SetIK(on)
	C.gizmo.ik = on and true or false
	RunConsoleCommand("speditor_ik", on and "1" or "0")
end
-- Stretch (T): Move takes a bone away from its parent — the bone's own offset (a manip
-- value), as in SFM — instead of moving its physics body; the limb grows longer or shifts
local cvStretch = CreateClientConVar("speditor_stretch", "0", true, false)
if C.gizmo.stretch == nil then C.gizmo.stretch = cvStretch:GetBool() end
function C.SetStretch(on)
	C.gizmo.stretch = on and true or false
	RunConsoleCommand("speditor_stretch", on and "1" or "0")
end
if C.gizmo.ikFeet == nil then C.gizmo.ikFeet = true end

-- plane handles: index 4 + i is the plane across axis i (spanned by the other two axes)
local PLANE_A, PLANE_B = 0.22, 0.42     -- where the square starts and ends, in gizmo sizes
local function planeAxes(i) return (i % 3) + 1, ((i + 1) % 3) + 1 end

local prepareLocks, postSolve        -- below, next to startDrag
local function IK_END(ent, bone) return SPeditor.IK.IsEndEffector(ent:GetBoneName(bone)) end

-- Size of bone markers in the frame (View → Bone size). Large markers cover the
-- fingers and make it hard to hit the right bone, so they are small by default.
local cvBoneSize = CreateClientConVar("speditor_bone_size", "0.6", true, false)
C.BONE_SIZES = { 0.3, 0.6, 1, 1.6 }
function C.GetBoneSize() return math.Clamp(cvBoneSize:GetFloat(), 0.1, 3) end
function C.SetBoneSize(v) RunConsoleCommand("speditor_bone_size", tostring(math.Clamp(tonumber(v) or 0.6, 0.1, 3))) end

local function rotateVec(v, k, deg)
	local th = math.rad(deg)
	local c, s = math.cos(th), math.sin(th)
	return v * c + k:Cross(v) * s + k * (k:Dot(v) * (1 - c))
end

-- a turn by deg degrees around the unit axis k, as a matrix
local function axisMatrix(k, deg)
	local x = rotateVec(Vector(1, 0, 0), k, deg)
	local y = rotateVec(Vector(0, 1, 0), k, deg)
	local z = rotateVec(Vector(0, 0, 1), k, deg)
	return Matrix({ { x.x, y.x, z.x, 0 }, { x.y, y.y, z.y, 0 }, { x.z, y.z, z.z, 0 }, { 0, 0, 0, 1 } })
end

local VIEW_RING = 1.18      -- radius of the ring around the line of sight, in ring radii
local BALL_SPEED = 0.5      -- trackball: degrees per pixel of the mouse

local function makeBasis(axis)
	local ref = (math.abs(axis.z) < 0.9) and Vector(0, 0, 1) or Vector(1, 0, 0)
	local u = axis:Cross(ref):GetNormalized()
	local v = axis:Cross(u)
	return u, v
end

local function axisParam(ro, rd, p0, ad)
	local w0 = p0 - ro
	local b  = ad:Dot(rd)
	local d  = ad:Dot(w0)
	local e  = rd:Dot(w0)
	local denom = 1 - b * b
	if denom < 1e-4 then return nil end
	return (b * e - d) / denom
end

local function getTarget()
	local ent = C.selected
	if not IsValid(ent) then return nil end
	if ent == C.camera.viewEnt or C.IsLocked(ent) then return nil end
	if C.selBone < 0 or C.IsAux(ent) then
		local p, a = C.GetEntityTransform(ent)
		return { kind = "entity", ent = ent, pos = p, ang = a }
	end
	local p, a = C.GetBoneWorld(ent, C.selBone)
	if not p then return nil end
	local physIdx = C.PhysIndexOfBone(ent, C.selBone)
	-- a physics object cannot change its size: the scale of any bone (a hand, the head)
	-- is a bone manip value, like for clavicles and fingers; so is a stretch
	if C.gizmo.mode == "scale" or (C.gizmo.stretch and C.gizmo.mode == "move") then physIdx = nil end
	return {
		kind = physIdx and "phys" or "manip",
		ent = ent, bone = C.selBone, physIdx = physIdx, pos = p, ang = a,
	}
end

local function gizmoAxes(tgt)
	-- a prop is stretched along its own axes
	local stretch = C.gizmo.mode == "scale" and tgt.kind == "entity" and C.CanScale(tgt.ent)
	if tgt.kind == "manip" or stretch or C.gizmo.space == "local" then
		local a = tgt.ang
		return { a:Forward(), -a:Right(), a:Up() }
	end
	return { Vector(1, 0, 0), Vector(0, 1, 0), Vector(0, 0, 1) }
end

local function effMode(tgt)
	local mode = C.gizmo.mode
	-- a bone without a physics object (clavicle, finger): move, rotate and scale go through manip values
	if tgt.kind == "manip" then return mode end
	-- only props have scale; for everything else the tool works as move
	if mode == "scale" and not (tgt.kind == "entity" and C.CanScale(tgt.ent)) then return "move" end
	return mode
end

local function gizmoSize(pos)
	local vp, _, fov = C.GetView()
	return math.max(pos:Distance(vp) * 0.14 * (fov / 75), 6)
end

local function segDist(ax, ay, bx, by, px, py)
	local abx, aby = bx - ax, by - ay
	local apx, apy = px - ax, py - ay
	local len2 = abx * abx + aby * aby
	local t = len2 > 0 and math.Clamp((apx * abx + apy * aby) / len2, 0, 1) or 0
	local cx, cy = ax + abx * t, ay + aby * t
	return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

-- a point inside a convex quad (screen corners in order, either winding)
local function pointInQuad(pts, x, y)
	local sign = 0
	for i = 1, 4 do
		local a, b = pts[i], pts[i % 4 + 1]
		local cr = (b[1] - a[1]) * (y - a[2]) - (b[2] - a[2]) * (x - a[1])
		if cr ~= 0 then
			local sg = cr > 0 and 1 or -1
			if sign ~= 0 and sg ~= sign then return false end
			sign = sg
		end
	end
	return true
end

-- Screen-space hit test through projection into the viewport: stable at any angle
local HIT_TOL = 8
local function hitTest(tgt)
	local mx, my = gui.MousePos()
	local axes = gizmoAxes(tgt)
	local size = gizmoSize(tgt.pos)
	local mode = effMode(tgt)
	local best, bestD

	if mode == "move" or mode == "scale" then
		local x0, y0, v0 = C.ProjectToViewport(tgt.pos)
		if v0 then
			if math.sqrt((mx - x0) ^ 2 + (my - y0) ^ 2) < 10 then best, bestD = 4, 0 end
			for i = 1, 3 do
				local x1, y1, v1 = C.ProjectToViewport(tgt.pos + axes[i] * size)
				if v1 then
					local d = segDist(x0, y0, x1, y1, mx, my)
					if d < HIT_TOL and (not bestD or d < bestD) then best, bestD = i, d end
				end
			end
			-- the plane squares (move only): the cursor inside the projected square
			if not best and mode == "move" then
				for i = 1, 3 do
					local j, k = planeAxes(i)
					local pts, ok = {}, true
					for _, c in ipairs({ { PLANE_A, PLANE_A }, { PLANE_B, PLANE_A }, { PLANE_B, PLANE_B }, { PLANE_A, PLANE_B } }) do
						local x, y, v = C.ProjectToViewport(tgt.pos + (axes[j] * c[1] + axes[k] * c[2]) * size)
						if not v then ok = false break end
						pts[#pts + 1] = { x, y }
					end
					if ok and pointInQuad(pts, mx, my) then best = 4 + i break end
				end
			end
		end
	else
		local R = size * 0.85
		local _, vang = C.GetView()
		-- index 5: the ring around the line of sight
		local rings = { axes[1], axes[2], axes[3], vang:Forward() }
		for i, axis in ipairs(rings) do
			local u, v = makeBasis(axis)
			local r = (i == 4) and R * VIEW_RING or R
			local prevx, prevy, prevv = nil, nil, false
			for s = 0, 40 do
				local a = (s / 40) * math.pi * 2
				local px, py, pvis = C.ProjectToViewport(tgt.pos + (u * math.cos(a) + v * math.sin(a)) * r)
				if pvis and prevv then
					local d = segDist(prevx, prevy, px, py, mx, my)
					if d < HIT_TOL and (not bestD or d < bestD) then best, bestD = (i == 4) and 5 or i, d end
				end
				prevx, prevy, prevv = px, py, pvis
			end
		end
		-- index 4: the trackball, anywhere inside the rings
		if not best then
			local x0, y0, v0 = C.ProjectToViewport(tgt.pos)
			local xr, yr, vr = C.ProjectToViewport(tgt.pos + vang:Up() * R)
			if v0 and vr and (mx - x0) ^ 2 + (my - y0) ^ 2 < (xr - x0) ^ 2 + (yr - y0) ^ 2 then best = 4 end
		end
	end
	if best then return { mode = mode, index = best } end
end

local function isDescendant(ent, bone, ancestor)
	local b, guard = bone, 0
	while b and b >= 0 and guard < 256 do
		if b == ancestor then return true end
		b = ent:GetBoneParent(b)
		guard = guard + 1
	end
	return false
end

-- The nearest ancestor of the bone that has a physics object
local function nextPhysAncestor(ent, bone)
	local b, guard = ent:GetBoneParent(bone), 0
	while b and b >= 0 and guard < 256 do
		if C.PhysIndexOfBone(ent, b) then return b end
		b = ent:GetBoneParent(b)
		guard = guard + 1
	end
end

-- IK is available for a hand / foot with two physics ancestors (shoulder-elbow / thigh-knee)
local function ikChain(tgt)
	if not C.gizmo.ik or tgt.kind ~= "phys" then return nil end
	if not SPeditor.IK.IsEndEffector(tgt.ent:GetBoneName(tgt.bone)) then return nil end
	local mid = nextPhysAncestor(tgt.ent, tgt.bone)
	local root = mid and nextPhysAncestor(tgt.ent, mid)
	if mid and root then return root, mid end
end

-- IK without physics: a model with no ragdoll (a prop, a model ported without a physics
-- model) is posed by bone offsets. A hand / foot pulls its two parent bones; their new turns
-- become manip angles (the bone's own turn on top of the animation pose: local = rest * manip).
local function manipIKChain(tgt)
	if not C.gizmo.ik or C.gizmo.stretch or tgt.kind ~= "manip" or C.IsRagdoll(tgt.ent) then return nil end
	if not SPeditor.IK.IsEndEffector(tgt.ent:GetBoneName(tgt.bone)) then return nil end
	local mid = tgt.ent:GetBoneParent(tgt.bone)
	local root = mid and mid >= 0 and tgt.ent:GetBoneParent(mid)
	if root and root >= 0 then return root, mid end
end

local function buildManipIKItems(tgt, root, mid)
	local ent, items = tgt.ent, {}
	for _, b in ipairs({ root, mid, tgt.bone }) do
		local p, a = C.GetBoneWorld(ent, b)
		local par = ent:GetBoneParent(b)
		local _, pa = C.GetBoneWorld(ent, par)
		if not p or not pa then return nil end
		items[#items + 1] = { bone = b, p0 = p, a0 = a, parentAng = pa,
			m0pos = ent:GetManipulateBonePosition(b), m0ang = ent:GetManipulateBoneAngles(b), m0scale = ent:GetManipulateBoneScale(b) }
	end
	return items
end

-- the manip angle that turns a bone to the world angle want, its parent being at parentNew
local function manipFor(it, want, parentNew)
	local _, cur = WorldToLocal(vector_origin, it.a0, vector_origin, it.parentAng)     -- rest * m0
	local _, inv = WorldToLocal(vector_origin, angle_zero, vector_origin, it.m0ang)     -- m0^-1
	local _, rest = LocalToWorld(vector_origin, inv, vector_origin, cur)                 -- rest
	local _, loc = WorldToLocal(vector_origin, want, vector_origin, parentNew)           -- wanted local
	local _, m = WorldToLocal(vector_origin, loc, vector_origin, rest)                   -- rest^-1 * local
	return m
end

local function applyManipIK(d, off)
	local r, m, e = d.items[1], d.items[2], d.items[3]
	local IK = SPeditor.IK
	local midNew, endNew = IK.Solve(r.p0, m.p0, e.p0, e.p0 + off)
	local rAng = IK.RotateAngle(r.a0, m.p0 - r.p0, midNew - r.p0)
	local mAng = IK.RotateAngle(m.a0, e.p0 - m.p0, endNew - midNew)
	r.m1ang = manipFor(r, rAng, r.parentAng)
	m.m1ang = manipFor(m, mAng, rAng)
	e.m1ang = manipFor(e, e.a0, mAng)              -- the hand keeps its turn in the world
	for _, it in ipairs(d.items) do
		it.m1pos, it.m1scale = it.m0pos, it.m0scale
		C.SendBoneManip(d.ent, it.bone, it.m0pos, it.m1ang, it.m0scale)
	end
end

local function buildIKItems(tgt, root, mid)
	local ent, items = tgt.ent, {}
	local function add(b)
		local pi = C.PhysIndexOfBone(ent, b)
		local p, a = C.GetBoneWorld(ent, b)
		if pi and p then items[#items + 1] = { physIdx = pi, p0 = p, a0 = a } end
	end
	add(root) add(mid) add(tgt.bone)               -- the order matters: shoulder, elbow, hand
	if #items < 3 then return nil end
	for b = 0, ent:GetBoneCount() - 1 do           -- fingers and everything below the hand travel with it
		if b ~= tgt.bone and isDescendant(ent, b, tgt.bone) then add(b) end
	end
	return items
end

local function buildItems(tgt)
	local ent = tgt.ent
	if tgt.kind == "entity" then
		-- the main object and all additionally selected ones
		local items = { { ent = ent, p0 = tgt.pos, a0 = tgt.ang, s0 = ent:GetModelScale() or 1, st0 = C.GetStretch(ent) } }
		for _, e in ipairs(C.multi) do
			local par = IsValid(e) and C.AttachParent(e) or nil
			local follows = par and (par == ent or C.IsMulti(par))   -- will follow its parent by itself
			if IsValid(e) and e ~= ent and not C.IsLocked(e) and e ~= C.camera.viewEnt and not follows then
				local p, a = C.GetEntityTransform(e)
				items[#items + 1] = { ent = e, p0 = p, a0 = a, s0 = e:GetModelScale() or 1, st0 = C.GetStretch(e) }
			end
		end
		return items
	end
	if tgt.kind == "manip" then
		-- a bone offset is given in the space of the parent bone
		local par, pa = ent:GetBoneParent(tgt.bone), nil
		if par and par >= 0 then pa = select(2, C.GetBoneWorld(ent, par)) end
		return { {
				m0pos = ent:GetManipulateBonePosition(tgt.bone),
				m0ang = ent:GetManipulateBoneAngles(tgt.bone),
				m0scale = ent:GetManipulateBoneScale(tgt.bone),
				parentAng = pa or ent:GetAngles(),
		} }
	end
	local items = {}
	for b = 0, ent:GetBoneCount() - 1 do
		local pi = C.PhysIndexOfBone(ent, b)
		if pi and (b == tgt.bone or (C.gizmo.carryChildren and isDescendant(ent, b, tgt.bone))) then
			local p, a = C.GetBoneWorld(ent, b)
			if p then items[#items + 1] = { physIdx = pi, p0 = p, a0 = a } end
		end
	end
	return items
end

---------------------------------------------------------------------
-- Planted feet and bone locks: worked out after the dragged bones got their new places
---------------------------------------------------------------------
local FOOT_PATTERNS = { "foot", "ankle", "hoof" }
local function isFoot(name)
	local n = string.lower(name or "")
	for _, p in ipairs(FOOT_PATTERNS) do
		if string.find(n, p, 1, true) then return true end
	end
	return false
end

-- The locks of a ragdoll: { [bone] = { to = bone it follows } }. They are a part of the
-- object's look (S.ApplyLook): saved with the scene, undone with Ctrl+Z.
function C.GetBoneLocks(ent)
	local out = {}
	if not IsValid(ent) or not C.IsRagdoll(ent) then return out end
	for b, t in pairs(C.GetLook(ent).locks or {}) do out[tonumber(b)] = { to = t } end
	return out
end

function C.GetBoneLock(ent, bone)
	return C.GetBoneLocks(ent)[bone]
end

local function sendLocks(ent, locks)
	local t = {}
	for b, l in pairs(locks) do t[tostring(b)] = l.to end
	C.EditLook(ent, { locks = t }, true)
end

-- Lock bone to the bone target of the same ragdoll (target nil — unlock). Both must be
-- physical; the place of bone relative to target is the one it has when a drag starts, so
-- the lock never pulls a bone back to an old pose.
function C.SetBoneLock(ent, bone, target)
	if not IsValid(ent) then return false end
	local locks = C.GetBoneLocks(ent)
	if target == nil then
		locks[bone] = nil
		sendLocks(ent, locks)
		return true
	end
	if bone == target or not C.PhysIndexOfBone(ent, bone) or not C.PhysIndexOfBone(ent, target) then return false end
	-- a bone cannot hold on to its own child, and two bones cannot hold on to each other
	if isDescendant(ent, target, bone) then return false end
	local back = locks[target]
	if back and back.to == bone then return false end
	locks[bone] = { to = target }
	sendLocks(ent, locks)
	return true
end

function C.ClearBoneLocks(ent)
	if IsValid(ent) and next(C.GetBoneLocks(ent)) then sendLocks(ent, {}) end
end

local function physDescendants(ent, bone)
	local out = {}
	for b = 0, ent:GetBoneCount() - 1 do
		if b ~= bone and C.PhysIndexOfBone(ent, b) and isDescendant(ent, b, bone) then out[#out + 1] = b end
	end
	return out
end

-- d.post: what postSolve does after every step of a physics drag
prepareLocks = function(d, tgt)
	if d.kind ~= "phys" or d.mode == "scale" then return end
	local ent = d.ent
	local byPhys = {}
	for _, it in ipairs(d.items) do byPhys[it.physIdx] = it end
	local moving = table.Copy(byPhys)          -- bones the drag itself moves
	-- the item of a bone; a bone the drag does not move is added as an "extra" item that stays put
	local function item(b)
		local pi = C.PhysIndexOfBone(ent, b)
		if not pi then return nil end
		if not byPhys[pi] then
			local p, a = C.GetBoneWorld(ent, b)
			if not p then return nil end
			byPhys[pi] = { physIdx = pi, p0 = p, a0 = a, extra = true }
			d.items[#d.items + 1] = byPhys[pi]
		end
		return byPhys[pi]
	end
	local function items(list)
		local out = {}
		for _, b in ipairs(list) do
			local it = item(b)
			if it then out[#out + 1] = it end
		end
		return out
	end
	local post = {}

	-- planted feet: the body moves, a leg whose thigh is carried along bends so that the foot stays
	if C.gizmo.ik and C.gizmo.ikFeet and not d.ik then
		for b = 0, ent:GetBoneCount() - 1 do
			if b ~= tgt.bone and isFoot(ent:GetBoneName(b)) and C.PhysIndexOfBone(ent, b) then
				local mid = nextPhysAncestor(ent, b)
				local root = mid and nextPhysAncestor(ent, mid)
				if root and mid ~= tgt.bone and root ~= tgt.bone and moving[C.PhysIndexOfBone(ent, root)]
					and isDescendant(ent, root, tgt.bone) then
					post[#post + 1] = { foot = true, chain = items({ root, mid, b }), tail = items(physDescendants(ent, b)) }
				end
			end
		end
	end

	-- bone locks
	for bone, lock in pairs(C.GetBoneLocks(ent)) do
		local T = (bone ~= tgt.bone) and item(lock.to)
		local B = T and item(bone)
		if B then
			local c = { target = T, tail = items(physDescendants(ent, bone)) }
			c.lp, c.la = WorldToLocal(B.p0, B.a0, T.p0, T.a0)
			local mid = C.gizmo.ik and IK_END(ent, bone) and nextPhysAncestor(ent, bone)
			local root = mid and nextPhysAncestor(ent, mid)
			if root and root ~= lock.to and mid ~= lock.to then
				c.chain = items({ root, mid, bone })
			else
				c.chain = { B }
			end
			post[#post + 1] = c
		end
	end
	if #post > 0 then d.post = post end
end

local function moved(it)
	if (it.p1 - it.p0):LengthSqr() > 1e-6 then return true end
	local a, b = it.a1, it.a0
	return math.abs(math.AngleDifference(a.p, b.p)) + math.abs(math.AngleDifference(a.y, b.y))
		+ math.abs(math.AngleDifference(a.r, b.r)) > 1e-3
end

-- move the tail (bones below the end of a chain) rigidly with it: from (p, a) to (np, na)
local function carryTail(tail, p, a, np, na)
	for _, t in ipairs(tail) do
		local lp, la = WorldToLocal(t.p1, t.a1, p, a)
		t.p1, t.a1 = LocalToWorld(lp, la, np, na)
	end
end

-- the end of a three-bone chain to (endPos, endAng); the two upper bones bend (IK)
local function solveChain(chain, tail, endPos, endAng)
	local r, m, e = chain[1], chain[2], chain[3]
	local IK = SPeditor.IK
	local midNew, endNew = IK.Solve(r.p1, m.p1, e.p1, endPos)
	r.a1 = IK.RotateAngle(r.a1, m.p1 - r.p1, midNew - r.p1)
	m.a1 = IK.RotateAngle(m.a1, e.p1 - m.p1, endNew - midNew)
	m.p1 = midNew
	carryTail(tail, e.p1, e.a1, endNew, endAng)
	e.p1, e.a1 = endNew, endAng
end

postSolve = function(d)
	for _, it in ipairs(d.items) do
		if it.extra or not it.p1 then it.p1, it.a1 = it.p0, it.a0 end
	end
	for _, c in ipairs(d.post or {}) do
		if c.foot then
			local e = c.chain[3]
			if #c.chain == 3 and moved(c.chain[1]) then solveChain(c.chain, c.tail, e.p0, e.a0) end
		elseif moved(c.target) then
			local wp, wa = LocalToWorld(c.lp, c.la, c.target.p1, c.target.a1)
			if #c.chain == 3 then
				solveChain(c.chain, c.tail, wp, wa)
			else
				local B = c.chain[1]
				carryTail(c.tail, B.p1, B.a1, wp, wa)
				B.p1, B.a1 = wp, wa
			end
		end
	end
end

local function startDrag(tgt, hit)
	local ro, rd = C.MouseRay()
	local turnFree = hit.mode == "rotate" and hit.index >= 4       -- the trackball or the view ring
	local free = (hit.index == 4) and not turnFree
	local plane = (hit.index > 4 and not turnFree) and hit.index - 4 or nil
	local axis = (not free and not plane and not turnFree) and gizmoAxes(tgt)[hit.index] or nil
	if turnFree and hit.index == 5 then axis = select(2, C.GetView()):Forward() end
	local d = {
		kind = tgt.kind, ent = tgt.ent, bone = tgt.bone, physIdx = tgt.physIdx,
		mode = hit.mode, axisIndex = hit.index, axis = axis,
		startPos = tgt.pos, startAng = tgt.ang, total = 0,
	}
	if hit.mode == "scale" then
		d.size = gizmoSize(tgt.pos)
		if free then
			d.free, d.mx0 = true, gui.MouseX()
		else
			d.t0 = axisParam(ro, rd, tgt.pos, axis)
			if not d.t0 then return end
		end
	elseif hit.mode == "move" and plane then
		local axes = gizmoAxes(tgt)
		local j, k = planeAxes(plane)
		d.plane, d.planeN, d.planeU, d.planeV = plane, axes[plane], axes[j], axes[k]
		d.h0 = util.IntersectRayWithPlane(ro, rd, tgt.pos, d.planeN)
		if not d.h0 then return end
	elseif hit.mode == "move" and free then
		local _, vang = C.GetView()
		d.free, d.camFwd = true, vang:Forward()
		d.h0 = util.IntersectRayWithPlane(ro, rd, tgt.pos, d.camFwd)
		if not d.h0 then return end
	elseif hit.mode == "move" then
		d.t0 = axisParam(ro, rd, tgt.pos, axis)
		if not d.t0 then return end
	elseif turnFree and hit.index == 4 then
		local _, vang = C.GetView()
		d.ball, d.M = true, Matrix()
		d.mx, d.my = gui.MousePos()
		d.camRight, d.camUp = vang:Right(), vang:Up()
	else
		d.viewRing = turnFree
		local h = util.IntersectRayWithPlane(ro, rd, tgt.pos, axis)
		if not h then return end
		d.U, d.V = makeBasis(axis)
		local v = h - tgt.pos
		d.lastA = math.deg(math.atan2(v:Dot(d.V), v:Dot(d.U)))
		d.raw = 0
	end
	local root, mid = nil, nil
	if hit.mode == "move" then root, mid = ikChain(tgt) end
	if root then
		d.items = buildIKItems(tgt, root, mid)
		d.ik = d.items ~= nil
	elseif hit.mode == "move" then
		root, mid = manipIKChain(tgt)
		if root then
			d.items = buildManipIKItems(tgt, root, mid)
			d.mik = d.items ~= nil
		end
	end
	d.items = d.items or buildItems(tgt)
	prepareLocks(d, tgt)
	C.gizmo.drag = d
end

local function sendItems(d)
	if d.kind == "entity" then
		for _, it in ipairs(d.items) do
			if IsValid(it.ent) then C.SendTransform(it.ent, it.p1, it.a1) end
		end
	elseif d.kind == "phys" then
		postSolve(d)
		C.SendPhysBones(d.ent, d.items)
	end
end

local function applyIK(d, off)
	local g, m, e = d.items[1], d.items[2], d.items[3]
	local midNew, endNew = SPeditor.IK.Solve(g.p0, m.p0, e.p0, e.p0 + off)
	g.p1, g.a1 = g.p0, SPeditor.IK.RotateAngle(g.a0, m.p0 - g.p0, midNew - g.p0)
	m.p1, m.a1 = midNew, SPeditor.IK.RotateAngle(m.a0, e.p0 - m.p0, endNew - midNew)
	e.p1, e.a1 = endNew, e.a0
	local delta = endNew - e.p0
	for i = 4, #d.items do
		local it = d.items[i]
		if not it.extra then it.p1, it.a1 = it.p0 + delta, it.a0 end
	end
	sendItems(d)
end

-- off — offset vector in the world (along an axis or in the screen plane)
local function applyMove(d, off)
	if d.ik then applyIK(d, off) return end
	if d.mik then applyManipIK(d, off) return end
	if d.kind == "manip" then
		local it = d.items[1]
		it.m1pos = it.m0pos + WorldToLocal(off, angle_zero, vector_origin, it.parentAng)
		C.SendBoneManip(d.ent, d.bone, it.m1pos, it.m0ang, it.m0scale)
		return
	end
	for _, it in ipairs(d.items) do
		if not it.extra then it.p1, it.a1 = it.p0 + off, it.a0 end
	end
	sendItems(d)
end

-- A turn of any kind, as a matrix M around the gizmo centre (the trackball, the view ring)
local function applyTurn(d, M)
	if d.kind == "manip" then
		-- the bone in the world = base * manip (the manip turn is the bone's own, applied
		-- last), so the new manip turn is base⁻¹ * M * the bone at the start
		local it = d.items[1]
		if not it.w0 then
			it.w0 = Matrix()
			it.w0:SetAngles(d.startAng)
			local m0 = Matrix()
			m0:SetAngles(it.m0ang)
			it.baseInv = (it.w0 * m0:GetInverseTR()):GetInverseTR()
		end
		it.m1ang = (it.baseInv * (M * it.w0)):GetAngles()
		C.SendBoneManip(d.ent, d.bone, it.m0pos, it.m1ang, it.m0scale)
		return
	end
	for _, it in ipairs(d.items) do
		if not it.extra then
			it.p1 = d.startPos + M * (it.p0 - d.startPos)
			it.a1 = (M * it.a0:Forward()):AngleEx(M * it.a0:Up())
		end
	end
	sendItems(d)
end

local function applyRotate(d, total)
	if d.viewRing then
		applyTurn(d, axisMatrix(d.axis, total))
		return
	end
	if d.kind == "manip" then
		local it = d.items[1]
		local a = Angle(it.m0ang.p, it.m0ang.y, it.m0ang.r)
		if d.axisIndex == 1 then a.r = a.r + total
		elseif d.axisIndex == 2 then a.p = a.p + total
		else a.y = a.y + total end
		it.m1ang = a
		C.SendBoneManip(d.ent, d.bone, it.m0pos, a, it.m0scale)
		return
	end
	for _, it in ipairs(d.items) do
		if not it.extra then
			it.p1 = d.startPos + rotateVec(it.p0 - d.startPos, d.axis, total)
			local f = rotateVec(it.a0:Forward(), d.axis, total)
			local u = rotateVec(it.a0:Up(), d.axis, total)
			it.a1 = f:AngleEx(u)
		end
	end
	sendItems(d)
end

-- factor — how many times to change the scale relative to the start of the drag
-- The gizmo centre is uniform scale, an axis is stretching along it (length, width, height).
local function applyScale(d, factor)
	local axis = (not d.free) and d.axisIndex or nil
	if d.kind == "manip" then
		local it = d.items[1]
		local s = Vector(it.m0scale.x, it.m0scale.y, it.m0scale.z)
		if axis then s[axis] = s[axis] * factor else s = s * factor end
		it.m1scale = Vector(math.Clamp(s.x, 0.01, 20), math.Clamp(s.y, 0.01, 20), math.Clamp(s.z, 0.01, 20))
		C.SendBoneManip(d.ent, d.bone, it.m0pos, it.m0ang, it.m1scale)
		return
	end
	for _, it in ipairs(d.items) do
		if C.CanScale(it.ent) then
			if axis then
				local st = Vector(it.st0.x, it.st0.y, it.st0.z)
				st[axis] = math.Clamp(st[axis] * factor, 0.05, 10)
				it.st1 = st
				C.EditLook(it.ent, { stretch = { st.x, st.y, st.z } }, false, true)
			else
				it.s1 = math.Clamp(it.s0 * factor, 0.05, 10)
				C.SendScale(it.ent, it.s1)
			end
		end
	end
end

local function updateDrag()
	local d = C.gizmo.drag
	if not IsValid(d.ent) then
		C.gizmo.drag = nil
		return
	end
	local ro, rd = C.MouseRay()
	if d.mode == "scale" then
		local factor
		if d.free then
			factor = 1 + (gui.MouseX() - d.mx0) / 150
		else
			local t = axisParam(ro, rd, d.startPos, d.axis)
			if not t then return end
			factor = 1 + (t - d.t0) / math.max(d.size, 1)
		end
		factor = math.max(factor, 0.01)
		d.total = factor - 1
		applyScale(d, factor)
	elseif d.mode == "move" and d.plane then
		local h = util.IntersectRayWithPlane(ro, rd, d.startPos, d.planeN)
		if not h then return end
		local off = h - d.h0
		local a, b = off:Dot(d.planeU), off:Dot(d.planeV)
		local snap = C.gizmo.snapMove
		if snap > 0 then a, b = math.Round(a / snap) * snap, math.Round(b / snap) * snap end
		off = d.planeU * a + d.planeV * b
		d.total = off:Length()
		applyMove(d, off)
	elseif d.mode == "move" and d.free then
		local h = util.IntersectRayWithPlane(ro, rd, d.startPos, d.camFwd)
		if not h then return end
		local off = h - d.h0
		d.total = off:Length()
		applyMove(d, off)
	elseif d.mode == "move" then
		local t = axisParam(ro, rd, d.startPos, d.axis)
		if not t then return end
		local delta = t - d.t0
		local snap = C.gizmo.snapMove
		if snap > 0 then delta = math.Round(delta / snap) * snap end
		d.total = delta
		applyMove(d, d.axis * delta)
	elseif d.ball then
		-- the trackball: the object turns after the mouse, as if a ball in front of it was rolled
		local mx, my = gui.MousePos()
		local dx, dy = mx - d.mx, my - d.my
		if dx == 0 and dy == 0 then return end
		d.mx, d.my = mx, my
		local axis = d.camUp * dx + d.camRight * dy
		local deg = axis:Length() * BALL_SPEED
		d.M = axisMatrix(axis:GetNormalized(), deg) * d.M
		d.total = d.total + deg
		applyTurn(d, d.M)
	else
		local h = util.IntersectRayWithPlane(ro, rd, d.startPos, d.axis)
		if not h then return end
		local v = h - d.startPos
		local a = math.deg(math.atan2(v:Dot(d.V), v:Dot(d.U)))
		d.raw = d.raw + math.NormalizeAngle(a - d.lastA)
		d.lastA = a
		local total = d.raw
		local snap = C.gizmo.snapRot
		if snap > 0 then total = math.Round(total / snap) * snap end
		d.total = total
		applyRotate(d, total)
	end
end

local pickClick          -- below, next to onPress

local function endDrag()
	local d = C.gizmo.drag
	C.gizmo.drag = nil
	C.FlushQueue()
	-- a click inside the rotate rings without a drag is an ordinary click: it selects a bone
	if d and d.ball and d.total == 0 then
		pickClick()
		return
	end
	if not d or d.total == 0 or not IsValid(d.ent) then return end
	local ref = C.Ref(d.ent)
	for _, it in ipairs(d.items) do
		if it.ent then it.ref = C.Ref(it.ent) end
	end
	local function restore(useAfter)
		local ent = C.Deref(ref)
		if d.kind == "entity" then
			-- every selected object has its own reference
			for _, it in ipairs(d.items) do
				local e = it.ref and C.Deref(it.ref)
				if e then
					if d.mode == "scale" then
						if it.s1 then C.SendScale(e, useAfter and it.s1 or it.s0, true) end
						if it.st1 then
							local st = useAfter and it.st1 or it.st0
							C.EditLook(e, { stretch = { st.x, st.y, st.z } }, true, true)
						end
					else
						C.SendTransform(e, useAfter and it.p1 or it.p0, useAfter and it.a1 or it.a0, true)
					end
				end
			end
			return
		end
		if not ent then return end
		if d.kind == "phys" then
			local list = {}
			for _, it in ipairs(d.items) do
				list[#list + 1] = {
					physIdx = it.physIdx,
					p1 = useAfter and it.p1 or it.p0,
					a1 = useAfter and it.a1 or it.a0,
				}
			end
			C.SendPhysBones(ent, list, true)
			return
		end
		for _, it in ipairs(d.items) do
			if d.kind == "manip" then
				C.SendBoneManip(ent, it.bone or d.bone, useAfter and it.m1pos or it.m0pos, useAfter and it.m1ang or it.m0ang,
					useAfter and it.m1scale or it.m0scale, true)
			else
				C.SendTransform(ent, useAfter and it.p1 or it.p0, useAfter and it.a1 or it.a0, true)
			end
		end
	end
	-- which parts of the model the drag changed: the bone keys of SAeditor key only those
	local parts = {}
	if d.kind == "phys" then
		local root = false
		for _, it in ipairs(d.items) do
			if it.physIdx then parts[#parts + 1] = "p" .. it.physIdx end
			root = root or it.physIdx == 0
		end
		-- the other bodies are kept relative to the root body: when it moves alone, all of
		-- them changed in that sense, and the key holds the whole pose
		if root and IsValid(d.ent) then
			parts = {}
			for b = 0, d.ent:GetBoneCount() - 1 do
				local pi = C.PhysIndexOfBone(d.ent, b)
				if pi then parts[#parts + 1] = "p" .. pi end
			end
		end
	elseif d.kind == "manip" then
		parts[1] = "b" .. d.bone
	end
	C.lastEditParts = { ent = d.ent, parts = table.concat(parts, ","), t = RealTime() }
	C.PushHistory(d.mode,
		function() restore(false) end,
	function() restore(true) end)
end

local lmbPrev = false
-- A click on a bone in the viewport: selects the bone (the gizmo goes onto the bone)
function pickClick()
	local ent = C.selected
	-- Shift / Ctrl + click (Interface settings → Keys): add to / remove from the selection
	local adding = C.Keys.ClickAny(C.MULTI_CLICK)
	if IsValid(ent) and not C.IsAux(ent) and C.showSkeleton and not adding then
		local b = C.PickBone(ent, 16)
		-- a click on the body of the selected ragdoll away from the markers: the body part under
		-- the cursor (the markers are small and hard to hit while animating)
		if not b and C.IsRagdoll(ent) and C.PickEntity() == ent then b = C.PickBodyBone(ent) end
		if b then
			C.Select(ent, b)
			return
		end
	end
	local picked = C.PickEntity()
	if adding then
		-- a click on empty space resets nothing
		if IsValid(picked) then C.ToggleMulti(picked) end
		return
	end
	C.Select(picked, -1)
end

local function onPress(tgt)
	if tgt then
		local hit = hitTest(tgt)
		if hit then
			startDrag(tgt, hit)
			return
		end
	end
	pickClick()
end

hook.Add("Think", "SPeditor.GizmoInput", function()
	if not C.active or C.exporting then
		lmbPrev = false
		C.gizmo.drag = nil
		return
	end
	local g = C.gizmo
	-- the window lost focus (Alt+Tab, minimized): the drag ends where it is (the release may
	-- never reach the game), and a new press counts only after the button is seen released
	if not system.HasFocus() then
		if g.drag then
			if g.drag.ball and g.drag.total == 0 then g.drag = nil else endDrag() end
		end
		lmbPrev = true
		return
	end
	local lmb = input.IsMouseDown(MOUSE_LEFT)
	local alt = input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)
	local hovering = C.MouseInViewport() and not C.camMode
	local tgt = getTarget()
	if not g.drag then
		g.hover = (tgt and hovering) and hitTest(tgt) or nil
	end
	if lmb and not lmbPrev then
		if hovering and not alt then onPress(tgt) end
	elseif lmb and g.drag then
		updateDrag()
	elseif not lmb and lmbPrev and g.drag then
		endDrag()
	end
	lmbPrev = lmb
end)

local function drawGizmo(tgt)
	local g = C.gizmo
	local axes = gizmoAxes(tgt)
	local size = gizmoSize(tgt.pos)
	local w    = size * 0.025
	local mode = effMode(tgt)
	local hv   = g.drag and { mode = g.drag.mode, index = g.drag.axisIndex } or g.hover
	render.SetColorMaterialIgnoreZ()
	if mode == "move" or mode == "scale" then
		local half = Vector(w * 2, w * 2, w * 2)
		for i = 1, 3 do
			local col = (hv and hv.mode == mode and hv.index == i) and HOVER_COLOR or AXIS_COLORS[i]
			local tip = tgt.pos + axes[i] * size
			render.DrawBeam(tgt.pos, tip, w, 0, 1, col)
			if mode == "scale" then
				render.DrawBox(tip, tgt.ang, -half, half, col)     -- scale has cubes at the ends
			else
				render.DrawSphere(tip, w * 2.2, 8, 8, col)
			end
		end
		if mode == "move" then
			for i = 1, 3 do
				local j, k = planeAxes(i)
				local hot = hv and hv.mode == "move" and hv.index == 4 + i
				local c = hot and HOVER_COLOR or AXIS_COLORS[i]
				local fill = Color(c.r, c.g, c.b, hot and 150 or 70)
				local function at(u, v) return tgt.pos + (axes[j] * u + axes[k] * v) * size end
				local p1, p2, p3, p4 = at(PLANE_A, PLANE_A), at(PLANE_B, PLANE_A), at(PLANE_B, PLANE_B), at(PLANE_A, PLANE_B)
				render.DrawQuad(p1, p2, p3, p4, fill)
				render.DrawQuad(p4, p3, p2, p1, fill)      -- seen from the other side too
				render.DrawLine(p1, p2, c, false) render.DrawLine(p2, p3, c, false)
				render.DrawLine(p3, p4, c, false) render.DrawLine(p4, p1, c, false)
			end
		end
	else
		local R = size * 0.85
		local function ring(axis, r, col, width)
			local u, v = makeBasis(axis)
			local prev
			for s = 0, 48 do
				local a = (s / 48) * math.pi * 2
				local p = tgt.pos + (u * math.cos(a) + v * math.sin(a)) * r
				if prev then render.DrawBeam(prev, p, width, 0, 1, col) end
				prev = p
			end
		end
		for i = 1, 3 do
			ring(axes[i], R, (hv and hv.mode == "rotate" and hv.index == i) and HOVER_COLOR or AXIS_COLORS[i], w)
		end
		local fwd = select(2, C.GetView()):Forward()
		-- the ring around the line of sight, and the outline of the trackball
		ring(fwd, R * VIEW_RING, (hv and hv.mode == "rotate" and hv.index == 5) and HOVER_COLOR or COL_VIEWRING, w)
		ring(fwd, R, (hv and hv.mode == "rotate" and hv.index == 4) and HOVER_COLOR or COL_BALL, w * 0.5)
	end
	render.DrawSphere(tgt.pos, w * 2, 8, 8, (hv and hv.index == 4) and HOVER_COLOR or color_white)
end

local function drawSkeleton(ent)
	if not C.showSkeleton then return end
	render.SetColorMaterialIgnoreZ()
	local vp = C.GetView()
	local size = C.GetBoneSize()
	for b = 0, ent:GetBoneCount() - 1 do
		if ent:GetBoneName(b) ~= "__INVALIDBONE__" then
			local p = C.GetBoneWorld(ent, b)
			if p then
				local par = ent:GetBoneParent(b)
				if par and par >= 0 then
					local pp = C.GetBoneWorld(ent, par)
					if pp then render.DrawBeam(pp, p, math.Clamp(p:Distance(vp) * 0.0012 * size, 0.02, 0.35), 0, 1, COL_LINE) end
				end
				local isSel = (b == C.selBone)
				local phys  = C.PhysIndexOfBone(ent, b) ~= nil
				local col   = isSel and COL_SEL or (phys and COL_PHYS or COL_MANIP)
				local r     = math.max(p:Distance(vp) * 0.004 * size, 0.04) * (isSel and 1.8 or (phys and 1.3 or 0.9))
				render.DrawSphere(p, r, 6, 6, col)
			end
		end
	end
	-- bone locks: a line from the locked bone to the bone it holds on to
	for bone, lock in pairs(C.GetBoneLocks(ent)) do
		local p, q = C.GetBoneWorld(ent, bone), C.GetBoneWorld(ent, lock.to)
		if p and q then render.DrawBeam(p, q, math.Clamp(p:Distance(vp) * 0.002, 0.05, 0.5), 0, 1, COL_LOCK) end
	end
end

-- The lock menu of a bone (the object menu, when a physical bone of a ragdoll is selected)
function C.BoneLockMenu(m, ent, bone)
	local L = SPeditor.L
	if not IsValid(ent) or not C.PhysIndexOfBone(ent, bone) then return end
	local short = function(b) return (string.gsub(ent:GetBoneName(b) or "", "^ValveBiped%.Bip01_", "")) end
	local lock = C.GetBoneLock(ent, bone)
	local sub = m:AddSubMenu(string.format(L("lock_bone_to"), short(bone)))
	for b = 0, ent:GetBoneCount() - 1 do
		if b ~= bone and C.PhysIndexOfBone(ent, b) then
			sub:AddOption(short(b), function()
				if C.SetBoneLock(ent, bone, b) then
					SPeditor.Notify(string.format(L("lock_bone_done"), short(bone), short(b)), 0)
				else
					SPeditor.Notify(L("lock_bone_bad"), 1)
				end
			end):SetChecked(lock ~= nil and lock.to == b)
		end
	end
	if lock then
		m:AddOption(string.format(L("lock_bone_off"), short(bone)), function() C.SetBoneLock(ent, bone, nil) end):SetIcon("icon16/lock_break.png")
	end
	if next(C.GetBoneLocks(ent)) then
		m:AddOption(L("lock_bone_clear"), function() C.ClearBoneLocks(ent) end)
	end
end

hook.Add("PostDrawTranslucentRenderables", "SPeditor.Gizmo", function(bDepth, bSkybox)
	if bDepth or bSkybox or not C.active or C.hideUI or C.vpPass == "secondary" then return end
	local ent = C.selected
	-- fullbright ignores vertex colour: helpers are drawn with regular lighting
	local restore = SPeditor.Render.HelperLighting()
	local ok, err = pcall(function()
	if IsValid(ent) and not C.IsAux(ent) then drawSkeleton(ent) end
	-- frames of the additionally selected objects
	for _, e in ipairs(C.multi) do
		if IsValid(e) and e ~= ent then
			if C.IsRagdoll(e) then
				local mins, maxs = e:WorldSpaceAABB()
				render.DrawWireframeBox(vector_origin, angle_zero, mins, maxs, COL_SEL, false)
			else
				local sc = C.ScaleVec(e)
				render.DrawWireframeBox(e:GetPos(), e:GetAngles(), e:OBBMins() * sc, e:OBBMaxs() * sc, COL_SEL, false)
			end
		end
	end
	local tgt = getTarget()
	if tgt then drawGizmo(tgt) end
	end)
	restore()
	if not ok then ErrorNoHalt("[SPeditor] gizmo: " .. tostring(err) .. "\n") end
end)

-- Halo only in the main pass: in the nested viewport render it darkens the frame
local HALO_COL, haloList = Color(255, 200, 60), {}
hook.Add("PreDrawHalos", "SPeditor.Halo", function()
	if not C.active or C.hideUI or C.renderViewEnt or C.vpPass then return end
	local ent = C.selected
	if IsValid(ent) and not C.IsLight(ent) and not C.IsEffect(ent) and ent ~= C.camera.viewEnt then
		haloList[1] = ent
		halo.Add(haloList, HALO_COL, 2, 2, 1, true, true)
	end
end)

hook.Add("PostRenderVGUI", "SPeditor.GizmoHUD", function()
	local d = C.gizmo.drag
	if not C.active or not d or C.hideUI then return end
	local mx, my = gui.MousePos()
	local text
	if d.mode == "scale" then
		text = string.format("x%.2f", 1 + d.total)
	else
		text = string.format("%.1f %s", d.total, SPeditor.L(d.mode == "move" and "unit_units" or "unit_deg"))
	end
	draw.SimpleTextOutlined(text, "DermaDefaultBold", mx + 18, my + 18, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
end)
