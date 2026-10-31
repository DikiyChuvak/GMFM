-- Client state and network layer of SPeditor
SPeditor.Client = SPeditor.Client or {}
local C   = SPeditor.Client
local Net = SPeditor.Net

-- State (survives a reload of the file)
C.active    = C.active or false
C.selBone   = C.selBone or -1
C.sceneList = C.sceneList or {}
if C.showSkeleton == nil then C.showSkeleton = true end

C.gizmo = C.gizmo or {}
do
	local g = C.gizmo
	g.mode     = g.mode or "move"
	g.space    = g.space or "world"
	g.snapMove = g.snapMove or 0
	g.snapRot  = g.snapRot or 0
	if g.carryChildren == nil then g.carryChildren = true end
end

-- Work camera. IMPORTANT: the angles are called angles; ang is kept as an alias for old code.
C.camera = C.camera or {}
do
	local cam = C.camera
	cam.pos          = cam.pos or Vector(0, 0, 0)
	cam.angles       = cam.angles or cam.ang or Angle(0, 0, 0)
	cam.target       = cam.target or Vector(cam.pos.x, cam.pos.y, cam.pos.z)
	cam.targetAngles = cam.targetAngles or Angle(cam.angles.p, cam.angles.y, cam.angles.r)
	cam.ang          = cam.angles
	cam.fov          = cam.fov or 75
	cam.speed        = cam.speed or 400
	cam.init         = cam.init or false
end

---------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------
local function byte(v)
	return math.Clamp(math.floor((tonumber(v) or 0) + 0.5), 0, 255)
end

-- kind: 0 = info, 1 = error, 2 = success, 3 = saving (no sound)
local NOTIFY_MAP = { [0] = NOTIFY_GENERIC, [1] = NOTIFY_ERROR, [2] = NOTIFY_HINT, [3] = NOTIFY_HINT }

function SPeditor.Notify(text, kind)
	kind = kind or 0
	-- "#key" — a dictionary string; "#key|a|b" — the same used as a format with arguments
	-- (this is how the server sends messages and the client translates them into its language)
	if string.sub(text, 1, 1) == "#" then
		local parts = string.Explode("|", string.sub(text, 2))
		local fmt = SPeditor.L(parts[1])
		text = fmt
		if #parts > 1 then
			local ok, res = pcall(string.format, fmt, unpack(parts, 2))
			if ok then text = res end
		end
	end
	-- in the editor — its own card (cl_ui_notify.lua), outside it — a GMod hint
	local UI = SPeditor.UI
	if UI and UI.Toast and UI.Toast(text, kind) then return end
	local cv = GetConVar("gmfm_notify")
	if cv and not cv:GetBool() then return end
	notification.AddLegacy(text, NOTIFY_MAP[kind] or NOTIFY_GENERIC, 4)
	if kind ~= 3 then surface.PlaySound(kind == 1 and "buttons/button10.wav" or "buttons/button14.wav") end
end

---------------------------------------------------------------------
-- Throttled queue: only the latest value per key is sent
---------------------------------------------------------------------
local queue, lastSend = {}, 0
local INTERVAL = 0.04

function C.Queue(key, fn)
	queue[key] = fn
end

function C.FlushQueue()
	local q = queue
	queue = {}
	for _, fn in pairs(q) do fn() end
	lastSend = RealTime()
end

SPeditor.Hook("Think", "SPeditor.NetQueue", function()
	if next(queue) == nil then return end
	if RealTime() < lastSend + INTERVAL then return end
	C.FlushQueue()
end)

-- now = true: send at once and drop the stale value from the queue
local function dispatch(key, now, fn)
	if now then
		queue[key] = nil
		fn()
	else
		queue[key] = fn
	end
end

---------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------
function C.SendToggle(on)
	net.Start(Net.Toggle)
	net.WriteBool(on and true or false)
	net.SendToServer()
end

function C.SendSpawn(model, pos, ang)
	net.Start(Net.Spawn)
	net.WriteString(model)
	SPeditor.WriteVecF(pos)
	SPeditor.WriteAngF(ang)
	net.SendToServer()
end

function C.SendDelete(ent, noHist)
	if not IsValid(ent) then return end
	local uid = ent:GetNW2Int("SPeditor_UID", 0)
	net.Start(Net.Delete)
	net.WriteEntity(ent)
	net.SendToServer()
	if uid ~= 0 and not noHist then
		C.PushHistory("delete",
			function() C.SendObjRestore(uid) end,
		function() C.SendObjRemove(uid) end)
	end
end

-- For history: by object UID (it survives deletion; the object lies in the "bin" on the server)
function C.SendObjRemove(uid)
	net.Start(Net.ObjRemove)
	net.WriteUInt(uid, 32)
	net.SendToServer()
end

function C.SendObjRestore(uid)
	net.Start(Net.ObjRestore)
	net.WriteUInt(uid, 32)
	net.SendToServer()
end

-- Uniform model scale (props only: a ragdoll cannot be scaled physically)
function C.SendScale(ent, scale, now)
	dispatch("sc" .. ent:EntIndex(), now, function()
		if not IsValid(ent) then return end
		net.Start(Net.Scale)
		net.WriteEntity(ent)
		net.WriteFloat(scale)
		net.SendToServer()
	end)
end

---------------------------------------------------------------------
-- Extended model properties (colour, materials, stretching, shadow) — the look
-- table, see S.ApplyLook in sv_speditor.lua. The state is read from the entity itself;
-- what was just sent is kept in lookPending until it comes back over the network,
-- otherwise two quick edits of different fields would overwrite each other.
---------------------------------------------------------------------
local lookPending = {}
local ONE = Vector(1, 1, 1)

function C.GetStretch(ent)
	local p = lookPending[ent]
	if p and RealTime() < p.t and p.look.stretch then return Vector(p.look.stretch[1], p.look.stretch[2], p.look.stretch[3]) end
	return IsValid(ent) and ent:GetNW2Vector("SPeditor_Stretch", ONE) or Vector(1, 1, 1)
end

-- the colours of material slots (S.ApplyLook): { ["slot"] = { r, g, b } }
function C.GetTints(ent)
	local out = {}
	for idx, r, g, b in string.gmatch(ent:GetNW2String("SPeditor_Tints", ""), "(%d+):(%d+),(%d+),(%d+)") do
		out[idx] = { tonumber(r), tonumber(g), tonumber(b) }
	end
	return out
end

function C.GetLook(ent)
	local p = lookPending[ent]
	if p and RealTime() < p.t then
		local l = table.Copy(p.look)
		l.color, l.material, l.submats = l.color or { 255, 255, 255, 255 }, l.material or "", l.submats or {}
		l.stretch, l.noshadow = l.stretch or { 1, 1, 1 }, l.noshadow or false
		l.locks, l.tints = l.locks or {}, l.tints or {}
		l.flexscale = l.flexscale or 1
		if not l.vmfov and ent:GetNW2Float("SPeditor_VMFov", 0) > 0 then l.vmfov = ent:GetNW2Float("SPeditor_VMFov", 0) end
		return l
	end
	local c = ent:GetColor()
	local st = ent:GetNW2Vector("SPeditor_Stretch", ONE)
	local look = {
		color = { c.r, c.g, c.b, c.a }, material = ent:GetMaterial() or "", submats = {},
		noshadow = ent:GetNW2Bool("SPeditor_NoShadow", false),
		stretch = { st.x, st.y, st.z }, locks = {},
	}
	for b, t in string.gmatch(ent:GetNW2String("SPeditor_Locks", ""), "(%d+):(%d+)") do look.locks[b] = tonumber(t) end
	local hb = {}
	for b in string.gmatch(ent:GetNW2String("SPeditor_HideBones", ""), "%d+") do hb[#hb + 1] = tonumber(b) end
	if #hb > 0 then look.hidebones = hb end
	look.tints = C.GetTints(ent)
	look.flexscale = ent:GetNW2Float("SPeditor_FlexScale", 1)
	local vmf = ent:GetNW2Float("SPeditor_VMFov", 0)
	if vmf > 0 then look.vmfov = vmf end
	-- the base pose of a model without physics (prop_dynamic): its animation and moment
	if ent:GetClass() == "prop_dynamic" then
		look.seq, look.cycle = ent:GetSequenceName(ent:GetSequence()), math.max(ent:GetNW2Float("SPeditor_Cycle", 0), 0)
	end
	for i = 0, math.min(#(ent:GetMaterials() or {}), 32) - 1 do
		local m = ent:GetSubMaterial(i)
		if m and m ~= "" then look.submats[tostring(i)] = m end
	end
	-- slots past the engine's 32, drawn by the client (cl_scene.lua)
	for i, m in string.gmatch(ent:GetNW2String("SPeditor_SubMats", ""), "(%d+):([^;]+)") do look.submats[i] = m end
	return look
end

-- now = true — at once (otherwise through the queue); noHist = true — no history entry
function C.SendLook(ent, look, now, noHist)
	if not IsValid(ent) or C.IsAux(ent) then return end
	if not noHist then
		local ref = C.Ref(ent)
		C.BurstEdit("lk" .. ent:EntIndex(), "look", function() return C.GetLook(ent) end, table.Copy(look), function(st)
			local e = C.Deref(ref)
			if e then C.SendLook(e, st, true, true) end
		end)
	end
	lookPending[ent] = { look = table.Copy(look), t = RealTime() + 1 }
	dispatch("lk" .. ent:EntIndex(), now, function()
		if not IsValid(ent) then return end
		net.Start(Net.Look)
		net.WriteEntity(ent)
		SPeditor.WriteTable(look)
		net.SendToServer()
	end)
end

-- Change some of the properties: patch = { color = …, material = …, … }
function C.EditLook(ent, patch, now, noHist)
	if not IsValid(ent) or C.IsAux(ent) then return end
	local look = C.GetLook(ent)
	for k, v in pairs(patch) do look[k] = v end
	C.SendLook(ent, look, now, noHist)
end

---------------------------------------------------------------------
-- Scene camera effects (cl_postfx.lua). The server hands out their JSON in chunks through NW2String.
---------------------------------------------------------------------
local fxCache = setmetatable({}, { __mode = "k" })
local fxPending = {}

function C.GetCameraFX(ent)
	if not C.IsCamera(ent) then return nil end
	local p = fxPending[ent]
	if p and RealTime() < p.t then return p.fx end
	local n = ent:GetNW2Int("SPeditor_FXN", 0)
	if n <= 0 then return nil end
	local parts = {}
	for i = 1, n do parts[i] = ent:GetNW2String("SPeditor_FX" .. i, "") end
	local json = table.concat(parts)
	local c = fxCache[ent]
	if not c or c.json ~= json then
		c = { json = json, fx = util.JSONToTable(json) }
		fxCache[ent] = c
	end
	return c.fx
end

function C.SendCameraFX(ent, fx, now, noHist)
	if not C.IsCamera(ent) then return end
	fx = table.Copy(fx or {})
	if not noHist then
		C.lastCameraEdit = ent      -- auto key (SAeditor) keys this camera even when it is not selected
		local ref = C.Ref(ent)
		C.BurstEdit("fx" .. ent:EntIndex(), "camera fx", function() return table.Copy(C.GetCameraFX(ent) or {}) end, fx, function(st)
			local e = C.Deref(ref)
			if e then C.SendCameraFX(e, st, true, true) end
		end)
	end
	fxPending[ent] = { fx = fx, t = RealTime() + 1 }
	dispatch("fx" .. ent:EntIndex(), now, function()
		if not IsValid(ent) then return end
		net.Start(Net.CameraFX)
		net.WriteEntity(ent)
		SPeditor.WriteTable(fx)
		net.SendToServer()
	end)
end

-- (b0.2.6) Where an object (at pos, ang as it is drawn) sits in a bone the client draws itself: the
-- offset the server keeps (S.DrawnBone). A bone of a model with a skeleton, or a bone with no body of
-- its own (a finger, hair) of a ragdoll; nil for the others (the server works those out from bodies).
function C.DrawnOffset(parent, bone, pos, ang)
	if not (IsValid(parent) and bone and bone >= 0) then return nil end
	if C.IsRagdoll(parent) and C.PhysIndexOfBone(parent, bone) ~= nil then return nil end
	parent:SetupBones()
	local m = parent:GetBoneMatrix(bone)
	if not m then return nil end
	local p, a = WorldToLocal(pos, ang, m:GetTranslation(), m:GetAngles())
	return { p = p, a = a }
end

-- Attach ent to parent (bone: a bone index of the parent, or -1 — to the object itself);
-- parent = nil — detach.
function C.SendAttach(ent, parent, bone, noHist)
	if not IsValid(ent) then return end
	-- a cycle (the target is itself attached to this object) is rejected at once, with no history entry
	local p, guard = parent, 0
	while IsValid(p) and guard < 64 do
		if p == ent then
			SPeditor.Notify("#err_attach", 1)
			return
		end
		p = p:GetNW2Entity("SPeditor_Parent")
		guard = guard + 1
	end
	if not noHist then
		local p0, b0 = ent:GetNW2Entity("SPeditor_Parent"), ent:GetNW2Int("SPeditor_ParentBone", -1)
		if ent:GetNW2Bool("SPeditor_Merge", false) then b0 = -2 end      -- worn (S.WEAR)
		-- a constraint (b0.2): the code carries its kind (S.AttachCode on the server)
		local mode0 = ent:GetNW2String("SPeditor_AttachMode", "")
		if mode0 == "point" then b0 = -100 - (b0 + 1) elseif mode0 == "orient" then b0 = -1000 - (b0 + 1) end
		local ref, pref0 = C.Ref(ent), IsValid(p0) and C.Ref(p0) or nil
		local pref1 = IsValid(parent) and C.Ref(parent) or nil
		local b1 = bone or -1
		local function apply(pref, b)
			local e = C.Deref(ref)
			if e then C.SendAttach(e, pref and C.Deref(pref) or nil, b, true) end
		end
		-- the server may put the object into the bone (S.SnapToBone): undo puts it back too
		local pos0, ang0 = C.GetEntityTransform(ent)
		C.PushHistory(IsValid(parent) and "attach" or "detach",
			function()
				apply(pref0, b0)
				local e = C.Deref(ref)
				if e and not pref0 then C.SendTransform(e, pos0, ang0, true) end
			end,
		function() apply(pref1, b1) end)
	end
	net.Start(Net.Attach)
	net.WriteEntity(ent)
	net.WriteEntity(IsValid(parent) and parent or NULL)
	net.WriteInt(bone or -1, 16)
	-- (b0.2.6) where the object sits in the bone as it is drawn now: the server keeps that offset.
	-- Far from a ragdoll's bone the object is put into it, as S.SnapToBone does (zero offset)
	local pos, ang = SPeditor.LivePos(ent)
	local off = IsValid(parent) and C.DrawnOffset(parent, bone, pos, ang) or nil
	if off and C.IsRagdoll(parent) then
		local bm = parent:GetBoneMatrix(bone)
		local center = LocalToWorld(ent:OBBCenter(), angle_zero, pos, ang)
		if bm and center:Distance(bm:GetTranslation()) > math.max(ent:BoundingRadius(), 12) then
			off = { p = vector_origin, a = angle_zero }
		end
	end
	net.WriteBool(off ~= nil)
	if off then
		SPeditor.WriteVecF(off.p)
		SPeditor.WriteAngF(off.a)
	end
	net.SendToServer()
end

-- Look-at (a0.7): the camera / light ent keeps turning to target (bone: a ragdoll bone, -1 —
-- the head of a character or the middle of a prop); target = nil — it stops.
-- (b0.2.6) keep the camera's focus on an object (nil — off)
function C.SendFocusOn(cam, target)
	if not IsValid(cam) then return end
	net.Start(Net.FocusOn)
	net.WriteEntity(cam)
	net.WriteEntity(IsValid(target) and target or NULL)
	net.SendToServer()
end

function C.SendAim(ent, target, bone, noHist)
	if not IsValid(ent) then return end
	if not noHist then
		local t0, ref = ent:GetNW2Entity("SPeditor_AimAt"), C.Ref(ent)
		local tref0 = IsValid(t0) and C.Ref(t0) or nil
		local tref1 = IsValid(target) and C.Ref(target) or nil
		local ang0 = ent:GetAngles()
		local function apply(tref, b)
			local e = C.Deref(ref)
			if e then C.SendAim(e, tref and C.Deref(tref) or nil, b, true) end
		end
		C.PushHistory(IsValid(target) and "aim follow" or "aim stop",
			function()
				apply(tref0, -1)
				local e = C.Deref(ref)
				if e and not tref0 then C.SendTransform(e, e:GetPos(), ang0, true) end
			end,
		function() apply(tref1, bone or -1) end)
	end
	net.Start(Net.Aim)
	net.WriteEntity(ent)
	net.WriteEntity(IsValid(target) and target or NULL)
	net.WriteInt(bone or -1, 16)
	net.SendToServer()
end

function C.SendDuplicate(ent)
	if not IsValid(ent) then return end
	net.Start(Net.Duplicate)
	net.WriteEntity(ent)
	net.SendToServer()
end

function C.SendTransform(ent, pos, ang, now)
	-- (b0.2.6) an object held at a bone the client draws: its offset from that bone goes with the place
	local par = ent:GetNW2Entity("SPeditor_Parent")
	local off = nil
	if ent:GetNW2Bool("SPeditor_AttDrawn", false) and IsValid(par) then
		off = C.DrawnOffset(par, ent:GetNW2Int("SPeditor_ParentBone", -1), pos, ang)
	else
		pos, ang = SPeditor.LiveToNet(ent, pos, ang)
	end
	dispatch("tr" .. ent:EntIndex(), now, function()
		if not IsValid(ent) then return end
		net.Start(Net.Transform)
		net.WriteEntity(ent)
		SPeditor.WriteVecF(pos)
		SPeditor.WriteAngF(ang)
		net.WriteBool(off ~= nil)
		if off then
			SPeditor.WriteVecF(off.p)
			SPeditor.WriteAngF(off.a)
		end
		net.SendToServer()
	end)
end

-- items = { { physIdx = n, p1 = Vector, a1 = Angle }, ... } — one packet per tick.
-- Each bone used to go as a separate message: when the root was moved with its children
-- this hit the server rate limit and the bones "lagged behind".
function C.SendPhysBones(ent, items, now)
	dispatch("pb" .. ent:EntIndex(), now, function()
		if not IsValid(ent) then return end
		local count = math.min(#items, 255)
		net.Start(Net.PhysBone)
		net.WriteEntity(ent)
		net.WriteUInt(count, 8)
		for i = 1, count do
			local it = items[i]
			net.WriteUInt(it.physIdx, 8)
			SPeditor.WriteVecF(it.p1)
			SPeditor.WriteAngF(it.a1)
		end
		net.SendToServer()
	end)
end

function C.SendPhysBone(ent, physIdx, pos, ang, now)
	C.SendPhysBones(ent, { { physIdx = physIdx, p1 = pos, a1 = ang } }, now)
end

function C.SendBoneManip(ent, bone, pos, ang, scale, now)
	dispatch("bm" .. ent:EntIndex() .. "_" .. bone, now, function()
		if not IsValid(ent) then return end
		net.Start(Net.BoneManip)
		net.WriteEntity(ent)
		net.WriteUInt(bone, 16)
		SPeditor.WriteVecF(pos)
		SPeditor.WriteAngF(ang)
		SPeditor.WriteVecF(scale)
		net.SendToServer()
	end)
end

-- kind: 0 = one bone, 1 = all bones, 2 = flexes and eyes, 3 = full reset
function C.SendReset(ent, kind, bone)
	if not IsValid(ent) then return end
	net.Start(Net.Reset)
	net.WriteEntity(ent)
	net.WriteUInt(kind, 2)
	net.WriteInt(bone or -1, 16)
	net.SendToServer()
end

function C.SendFlex(ent, id, weight, now)
	dispatch("fx" .. ent:EntIndex() .. "_" .. id, now, function()
		if not IsValid(ent) then return end
		net.Start(Net.Flex)
		net.WriteEntity(ent)
		net.WriteUInt(id, 16)
		net.WriteFloat(weight)
		net.SendToServer()
	end)
end

function C.SendEye(ent, enabled, vec, now)
	dispatch("ey" .. ent:EntIndex(), now, function()
		if not IsValid(ent) then return end
		net.Start(Net.EyeTarget)
		net.WriteEntity(ent)
		net.WriteBool(enabled)
		SPeditor.WriteVecF(vec)
		net.SendToServer()
	end)
end

-- The edits below write themselves into history (undo/redo), so they can be called from
-- anywhere in the interface. noHist = true — an internal send without an entry
-- (the undo handlers themselves use it).
local function histEdit(label, ent, before, after, apply)
	local ref = C.Ref(ent)
	C.PushHistory(label,
		function() local e = C.Deref(ref) if e then apply(e, before) end end,
	function() local e = C.Deref(ref) if e then apply(e, after) end end)
end

function C.SendSkin(ent, skin, noHist)
	if not IsValid(ent) then return end
	local before = ent:GetSkin() or 0
	if not noHist and before ~= skin then
		histEdit("skin", ent, before, skin, function(e, v) C.SendSkin(e, v, true) end)
	end
	net.Start(Net.Skin)
	net.WriteEntity(ent)
	net.WriteUInt(skin, 8)
	net.SendToServer()
end

function C.SendBodygroup(ent, id, value, noHist)
	if not IsValid(ent) then return end
	local before = ent:GetBodygroup(id) or 0
	if not noHist and before ~= value then
		histEdit("bodygroup", ent, before, value, function(e, v) C.SendBodygroup(e, id, v, true) end)
	end
	net.Start(Net.Bodygroup)
	net.WriteEntity(ent)
	net.WriteUInt(id, 8)
	net.WriteUInt(value, 8)
	net.SendToServer()
end

function C.SendRename(ent, name, noHist)
	if not IsValid(ent) then return end
	name = string.sub(name or "", 1, 48)
	local before = ent:GetNW2String("SPeditor_Name", "")
	if not noHist and before ~= name then
		histEdit("rename", ent, before, name, function(e, v) C.SendRename(e, v, true) end)
	end
	net.Start(Net.Rename)
	net.WriteEntity(ent)
	net.WriteString(string.sub(name or "", 1, 48))
	net.SendToServer()
end

function C.SendFlags(ent, hidden, locked, noHist)
	if not IsValid(ent) then return end
	hidden, locked = hidden and true or false, locked and true or false
	local before = { ent:GetNW2Bool("SPeditor_Hidden", false), ent:GetNW2Bool("SPeditor_Locked", false) }
	if not noHist and (before[1] ~= hidden or before[2] ~= locked) then
		histEdit("visibility", ent, before, { hidden, locked }, function(e, v) C.SendFlags(e, v[1], v[2], true) end)
	end
	net.Start(Net.Flags)
	net.WriteEntity(ent)
	net.WriteBool(hidden and true or false)
	net.WriteBool(locked and true or false)
	net.SendToServer()
end

-- The server computes the new position, so the history entry is made after
-- it has reached the client.
function C.SendDropToFloor(ent)
	if not IsValid(ent) then return end
	local p0, a0 = C.GetEntityTransform(ent)
	p0, a0 = Vector(p0), Angle(a0)
	net.Start(Net.DropToFloor)
	net.WriteEntity(ent)
	net.SendToServer()
	timer.Simple(0.3, function()
		if not IsValid(ent) then return end
		local p1, a1 = C.GetEntityTransform(ent)
		if p1:DistToSqr(p0) < 0.01 then return end
		p1, a1 = Vector(p1), Angle(a1)
		histEdit("drop to floor", ent, { p0, a0 }, { p1, a1 }, function(e, v) C.SendTransform(e, v[1], v[2], true) end)
	end)
end

-- Reset rotation (b0.2.3): the selected objects stand straight (turn 0, 0, 0) where they are
function C.ResetRotation(list)
	local items = {}
	for _, e in ipairs(list or C.SelectionList()) do
		if IsValid(e) and not IsValid(C.AttachParent(e)) then
			local p, a = C.GetEntityTransform(e)
			if p and a and (a.p ~= 0 or a.y ~= 0 or a.r ~= 0) then
				items[#items + 1] = { ref = C.Ref(e), p = Vector(p), a = Angle(a) }
				C.SendTransform(e, Vector(p), Angle(0, 0, 0), true)
			end
		end
	end
	if #items == 0 then return end
	local function each(fn)
		for _, it in ipairs(items) do
			local e = C.Deref(it.ref)
			if e then fn(e, it) end
		end
	end
	C.PushHistory("reset rotation",
		function() each(function(e, it) C.SendTransform(e, it.p, it.a, true) end) end,
		function() each(function(e, it) C.SendTransform(e, it.p, Angle(0, 0, 0), true) end) end)
end

function C.SendLightSpawn(ltype, pos, ang, col, radius, brightness, fov)
	net.Start(Net.LightSpawn)
	net.WriteUInt(ltype, 2)
	SPeditor.WriteVecF(pos)
	SPeditor.WriteAngF(ang)
	net.WriteUInt(byte(col.r), 8)
	net.WriteUInt(byte(col.g), 8)
	net.WriteUInt(byte(col.b), 8)
	net.WriteFloat(radius)
	net.WriteFloat(brightness)
	net.WriteFloat(fov)
	net.SendToServer()
end

-- Full light state (for history)
local function lightState(ent)
	local c = ent:GetLightColor()
	return {
		ltype = ent:GetLightType(), col = Color(c.x * 255, c.y * 255, c.z * 255),
		radius = ent:GetLightRadius(), brightness = ent:GetLightBrightness(), fov = ent:GetLightFOV(),
		sh = C.LightExtras(ent),
	}
end

-- Extended light settings as one table: { shadows, ortho, tex, soft, bias, near, … }
-- (numeric fields follow the SPeditor.LightFields list)
function C.LightExtras(ent)
	local sh = { shadows = ent:GetLightShadows(), ortho = ent:GetLightOrtho(), tex = ent:GetLightTexture() }
	for _, f in ipairs(SPeditor.LightFields) do sh[f.key] = ent["Get" .. f.nw](ent) end
	return sh
end

-- sh — the extended settings being changed (see C.LightExtras); whatever is missing from
-- the table is taken from the current light state
function C.SendLightEdit(ent, ltype, col, radius, brightness, fov, sh, now, noHist)
	if not IsValid(ent) then return end
	if not noHist then
		local cur = lightState(ent)
		local shAfter = table.Copy(cur.sh)
		for k, v in pairs(sh or {}) do shAfter[k] = v end
		local after = {
			ltype = ltype, col = Color(col.r, col.g, col.b), radius = radius, brightness = brightness, fov = fov,
			sh = shAfter,
		}
		local ref = C.Ref(ent)
		-- a series of slider edits is merged into one entry
		C.BurstEdit("le" .. ent:EntIndex(), "light", function() return cur end, after, function(st)
			local e = C.Deref(ref)
			if e then C.SendLightEdit(e, st.ltype, st.col, st.radius, st.brightness, st.fov, st.sh, true, true) end
		end)
	end

	dispatch("le" .. ent:EntIndex(), now, function()
		if not IsValid(ent) then return end
		net.Start(Net.LightEdit)
		net.WriteEntity(ent)
		net.WriteUInt(ltype, 2)
		net.WriteUInt(byte(col.r), 8)
		net.WriteUInt(byte(col.g), 8)
		net.WriteUInt(byte(col.b), 8)
		net.WriteFloat(radius)
		net.WriteFloat(brightness)
		net.WriteFloat(fov)
		local full = C.LightExtras(ent)
		for k, v in pairs(sh or {}) do full[k] = v end
		net.WriteBool(full.shadows and true or false)
		net.WriteBool(full.ortho and true or false)
		net.WriteString(isstring(full.tex) and full.tex or "")
		for _, f in ipairs(SPeditor.LightFields) do net.WriteFloat(tonumber(full[f.key]) or f.default) end
		net.SendToServer()
	end)
end

-- Light kind (SPeditor.LightKinds) -> the selected light. A kind sets every setting:
-- whatever it lacks is reset to the defaults, otherwise the result would depend
-- on what the light had before.
function C.ApplyLightKind(ent, kind, noHist)
	if not C.IsLight(ent) or not istable(kind) then return end
	local sh = { shadows = true, ortho = false, tex = SPeditor.DefaultLightTexture }
	for _, f in ipairs(SPeditor.LightFields) do sh[f.key] = f.default end
	for k, v in pairs(kind.sh or {}) do sh[k] = v end
	C.SendLightEdit(ent, kind.ltype or ent:GetLightType(), Color(kind.r, kind.g, kind.b), kind.radius, kind.brightness, kind.fov,
		sh, true, noHist)
end

-- Create a light of the needed kind right away, in front of the work camera
local pendingKind
function C.SpawnLightKind(kind)
	local cam = C.camera
	pendingKind = { kind = kind, t = RealTime() + 3 }
	C.SendLightSpawn(kind.ltype or 1, cam.pos + cam.ang:Forward() * 150, cam.ang, Color(kind.r, kind.g, kind.b),
		kind.radius, kind.brightness, kind.fov)
end

SPeditor.Hook("SPeditor_ObjectSpawned", "SPeditor.LightKind", function(ent)
	local p = pendingKind
	if not p or not C.IsLight(ent) then return end
	pendingKind = nil
	if RealTime() < p.t then C.ApplyLightKind(ent, p.kind, true) end
end)

---------------------------------------------------------------------
-- Effects (the speditor_effect entity, cl_effects.lua)
---------------------------------------------------------------------
-- fx = { src, name, file, time, scale, length }; in front of the work camera by default
function C.SendEffectSpawn(fx, pos, ang)
	local cam = C.camera
	net.Start(Net.EffectSpawn)
	SPeditor.WriteTable(fx)
	SPeditor.WriteVecF(pos or (cam.pos + cam.ang:Forward() * 150))
	SPeditor.WriteAngF(ang or Angle(0, cam.ang.y, 0))
	net.SendToServer()
end

-- the whole state of an effect (for history)
function C.EffectState(ent)
	local st = { src = ent:GetFxSource(), name = ent:GetFxName(), file = ent:GetFxFile() }
	for _, f in ipairs(SPeditor.EffectFields) do st[f.key] = ent["Get" .. f.nw](ent) end
	return st
end

-- patch — the fields being changed (see C.EffectState)
function C.SendEffectEdit(ent, patch, now, noHist)
	if not C.IsEffect(ent) then return end
	local key = "ee" .. ent:EntIndex()
	if not noHist then
		local before = C.EffectState(ent)
		local after = table.Copy(before)
		for k, v in pairs(patch) do after[k] = v end
		local ref = C.Ref(ent)
		C.BurstEdit(key, "effect", function() return before end, after, function(st)
			local e = C.Deref(ref)
			if e then C.SendEffectEdit(e, st, true, true) end
		end)
	end
	-- several sliders share one queue slot: what was not sent yet is kept
	local pend = ent.SPFxPending
	if not pend then
		pend = {}
		ent.SPFxPending = pend
	end
	for k, v in pairs(patch) do pend[k] = v end
	dispatch(key, now, function()
		if not IsValid(ent) then return end
		ent.SPFxPending = nil
		net.Start(Net.EffectEdit)
		net.WriteEntity(ent)
		SPeditor.WriteTable(pend)
		net.SendToServer()
	end)
end

function C.SendCameraSpawn(pos, ang)
	net.Start(Net.CameraSpawn)
	SPeditor.WriteVecF(pos)
	SPeditor.WriteAngF(ang)
	net.SendToServer()
end

-- current value of a camera field: "fov" or a key of SPeditor.CameraFields
function C.CameraField(ent, field)
	if field == "fov" then return ent:GetCameraFOV() end
	for _, f in ipairs(SPeditor.CameraFields) do
		if f.key == field and ent["Get" .. f.nw] then return ent["Get" .. f.nw](ent) end
	end
end

-- field: "fov" or a key of SPeditor.CameraFields
function C.SendCameraEdit(ent, field, value, now, noHist)
	if not IsValid(ent) then return end
	if not noHist then
		C.lastCameraEdit = ent
		local before = C.CameraField(ent, field) or value
		local ref = C.Ref(ent)
		C.BurstEdit("ce" .. ent:EntIndex() .. field, field == "fov" and "camera fov" or "camera motion", function() return before end, value, function(v)
			local e = C.Deref(ref)
			if e then C.SendCameraEdit(e, field, v, true, true) end
		end)
	end
	dispatch("ce" .. ent:EntIndex() .. field, now, function()
		if not IsValid(ent) then return end
		net.Start(Net.CameraEdit)
		net.WriteEntity(ent)
		net.WriteString(field)
		net.WriteFloat(value)
		net.SendToServer()
	end)
end

function C.SendCameraView(ent, on)
	if not IsValid(ent) then return end
	net.Start(Net.CameraView)
	net.WriteEntity(ent)
	net.WriteBool(on and true or false)
	net.SendToServer()
end

function C.SendCleanup()
	net.Start(Net.Cleanup)
	net.SendToServer()
end

-- "Clear the scene" of the menus (b0.2.6): the objects and whatever else belongs to the scene on
-- this client — the NPC marks of a take (they stayed and had to be removed in the Record window)
function C.ClearScene()
	C.SendCleanup()
	hook.Run("SPeditor_ClearScene")
end

function C.SendPoseApply(ent, pose)
	if not IsValid(ent) or type(pose) ~= "table" then return end
	net.Start(Net.PoseApply)
	net.WriteEntity(ent)
	SPeditor.WriteTable(pose)
	net.SendToServer()
end

-- Pose request: the answer arrives asynchronously in callback(pose)
local poseCallbacks = {}

function C.RequestPose(ent, callback)
	if not IsValid(ent) then return end
	poseCallbacks[ent:EntIndex()] = callback
	net.Start(Net.PoseGet)
	net.WriteEntity(ent)
	net.SendToServer()
end

-- Scenes
function C.SceneSave(name, meta)
	if name ~= "autosave" then C.sceneName = SPeditor.SafeName(name) end
	net.Start(Net.SceneSave)
	net.WriteString(name)
	net.WriteString(meta or "")
	net.SendToServer()
end

function C.SceneLoad(name)
	C.sceneName = name
	net.Start(Net.SceneLoad)
	net.WriteString(name)
	net.SendToServer()
end

function C.SceneDelete(name)
	net.Start(Net.SceneDelete)
	net.WriteString(name)
	net.SendToServer()
end

function C.SceneRequestList()
	net.Start(Net.SceneList)
	net.SendToServer()
end

---------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------
net.Receive(Net.State, function()
	C.active = net.ReadBool()
	C.stateAt = RealTime()
	hook.Run("SPeditor_StateChanged", C.active)
end)

net.Receive(Net.Notice, function()
	local text = net.ReadString()
	local kind = net.ReadUInt(2)
	SPeditor.Notify(text, kind)
end)

-- The server reports the index of the new entity; select it once it reaches the client
net.Receive(Net.Spawned, function()
	local idx         = net.ReadUInt(16)
	local uid         = net.ReadUInt(32)
	local fromHistory = net.ReadBool()
	-- a copy of several selected objects: one history step and one new selection (cl_scene.lua)
	local batch = C.dupBatch
	if batch and not fromHistory and uid ~= 0 and RealTime() < batch.untilT then
		batch.uids[#batch.uids + 1] = uid
		batch.idx[#batch.idx + 1] = idx
		if #batch.uids >= batch.n then C.FinishDuplicate() end
		return
	end
	C.pendingSelect = idx
	C.pendingUntil  = RealTime() + 3
	-- creating / duplicating is a history step; restoring from undo/redo is not
	if not fromHistory and uid ~= 0 then
		C.PushHistory("spawn",
			function() C.SendObjRemove(uid) end,
		function() C.SendObjRestore(uid) end)
	end
end)

net.Receive(Net.PoseData, function()
	local idx  = net.ReadUInt(16)
	local pose = SPeditor.ReadTable()
	local cb = poseCallbacks[idx]
	if cb then
		poseCallbacks[idx] = nil
		cb(pose)
	end
end)

net.Receive(Net.SceneLoaded, function()
	local meta = net.ReadString()
	-- open windows (Render) compare it to drop what they took from the previous scene
	C.sceneSerial = (C.sceneSerial or 0) + 1
	hook.Run("SPeditor_SceneLoaded", meta)
end)

net.Receive(Net.SceneListData, function()
	local count = net.ReadUInt(8)
	local list = {}
	for i = 1, count do
		list[i] = net.ReadString()
	end
	C.sceneList = list
	hook.Run("SPeditor_SceneList", list)
end)
