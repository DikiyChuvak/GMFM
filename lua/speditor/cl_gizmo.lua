-- Move and rotate gizmo.
-- Hover is tested in viewport screen coordinates through C.ProjectToViewport
-- (point at an axis / ring and it lights up; the hit is exact).
-- Input only inside the Primary Viewport. A click on a bone selects the bone.
-- Halo is off in the nested viewport render (otherwise the frame darkens).
SPeditor.Client = SPeditor.Client or {}
local C = SPeditor.Client

local AXIS_COLORS = { Color(255, 80, 80), Color(80, 255, 80), Color(90, 150, 255) }
local HOVER_COLOR = Color(255, 230, 80)
local COL_LINE    = Color(255, 255, 255, 90)
local COL_PHYS    = Color(80, 220, 255)
local COL_MANIP   = Color(210, 210, 210)
local COL_SEL     = Color(255, 220, 60)

C.gizmo = C.gizmo or {}
if C.gizmo.ik == nil then C.gizmo.ik = false end

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
	-- is a bone manip value, like for clavicles and fingers
	if C.gizmo.mode == "scale" then physIdx = nil end
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
		end
	else
		local R = size * 0.85
		for i = 1, 3 do
			local u, v = makeBasis(axes[i])
			local prevx, prevy, prevv = nil, nil, false
			for s = 0, 40 do
				local a = (s / 40) * math.pi * 2
				local px, py, pvis = C.ProjectToViewport(tgt.pos + (u * math.cos(a) + v * math.sin(a)) * R)
				if pvis and prevv then
					local d = segDist(prevx, prevy, px, py, mx, my)
					if d < HIT_TOL and (not bestD or d < bestD) then best, bestD = i, d end
				end
				prevx, prevy, prevv = px, py, pvis
			end
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

local function startDrag(tgt, hit)
	local ro, rd = C.MouseRay()
	local free = (hit.index == 4)
	local axis = (not free) and gizmoAxes(tgt)[hit.index] or nil
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
	elseif hit.mode == "move" and free then
		local _, vang = C.GetView()
		d.free, d.camFwd = true, vang:Forward()
		d.h0 = util.IntersectRayWithPlane(ro, rd, tgt.pos, d.camFwd)
		if not d.h0 then return end
	elseif hit.mode == "move" then
		d.t0 = axisParam(ro, rd, tgt.pos, axis)
		if not d.t0 then return end
	else
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
	end
	d.items = d.items or buildItems(tgt)
	C.gizmo.drag = d
end

local function sendItems(d)
	if d.kind == "entity" then
		for _, it in ipairs(d.items) do
			if IsValid(it.ent) then C.SendTransform(it.ent, it.p1, it.a1) end
		end
	elseif d.kind == "phys" then
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
		it.p1, it.a1 = it.p0 + delta, it.a0
	end
	sendItems(d)
end

-- off — offset vector in the world (along an axis or in the screen plane)
local function applyMove(d, off)
	if d.ik then applyIK(d, off) return end
	if d.kind == "manip" then
		local it = d.items[1]
		it.m1pos = it.m0pos + WorldToLocal(off, angle_zero, vector_origin, it.parentAng)
		C.SendBoneManip(d.ent, d.bone, it.m1pos, it.m0ang, it.m0scale)
		return
	end
	for _, it in ipairs(d.items) do
		it.p1, it.a1 = it.p0 + off, it.a0
	end
	sendItems(d)
end

local function applyRotate(d, total)
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
		it.p1 = d.startPos + rotateVec(it.p0 - d.startPos, d.axis, total)
		local f = rotateVec(it.a0:Forward(), d.axis, total)
		local u = rotateVec(it.a0:Up(), d.axis, total)
		it.a1 = f:AngleEx(u)
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

local function endDrag()
	local d = C.gizmo.drag
	C.gizmo.drag = nil
	C.FlushQueue()
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
				C.SendBoneManip(ent, d.bone, useAfter and it.m1pos or it.m0pos, useAfter and it.m1ang or it.m0ang,
					useAfter and it.m1scale or it.m0scale, true)
			else
				C.SendTransform(ent, useAfter and it.p1 or it.p0, useAfter and it.a1 or it.a0, true)
			end
		end
	end
	C.PushHistory(d.mode,
		function() restore(false) end,
	function() restore(true) end)
end

local lmbPrev = false
local function onPress(tgt)
	if tgt then
		local hit = hitTest(tgt)
		if hit then
			startDrag(tgt, hit)
			return
		end
	end
	-- A click on a bone in the viewport: selects the bone (the gizmo goes onto the bone)
	local ent = C.selected
	local ctrlDown = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
	if IsValid(ent) and not C.IsAux(ent) and C.showSkeleton and not ctrlDown then
		local b = C.PickBone(ent, 16)
		if b then
			C.Select(ent, b)
			return
		end
	end
	local picked = C.PickEntity()
	if input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL) then
		-- Ctrl+click: add to / remove from the selection (a click on empty space resets nothing)
		if IsValid(picked) then C.ToggleMulti(picked) end
		return
	end
	C.Select(picked, -1)
end

hook.Add("Think", "SPeditor.GizmoInput", function()
	if not C.active or C.exporting then
		lmbPrev = false
		C.gizmo.drag = nil
		return
	end
	local g = C.gizmo
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
	else
		local R = size * 0.85
		for i = 1, 3 do
			local col = (hv and hv.mode == "rotate" and hv.index == i) and HOVER_COLOR or AXIS_COLORS[i]
			local u, v = makeBasis(axes[i])
			local prev
			for s = 0, 48 do
				local a = (s / 48) * math.pi * 2
				local p = tgt.pos + (u * math.cos(a) + v * math.sin(a)) * R
				if prev then render.DrawBeam(prev, p, w, 0, 1, col) end
				prev = p
			end
		end
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
hook.Add("PreDrawHalos", "SPeditor.Halo", function()
	if not C.active or C.hideUI or C.renderViewEnt or C.vpPass then return end
	local ent = C.selected
	if IsValid(ent) and not C.IsLight(ent) and not C.IsEffect(ent) and ent ~= C.camera.viewEnt then
		halo.Add({ ent }, Color(255, 200, 60), 2, 2, 1, true, true)
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
