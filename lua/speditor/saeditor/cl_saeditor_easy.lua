--[[
SAeditor — animation in one click (a0.6).

Ready motions for characters: "walks", "waves", "dances"… — animations of the player models,
which fit every character with the Valve skeleton (citizens, combine, most addon characters).
A click bakes the motion from the playhead (SA.ImportSequence); motions that repeat (walking,
standing, dancing) fill the animation up to its end.

Ready camera moves: dolly in / out, orbit, pan, crane, shake. The path is worked out here from
where the camera stands and what it looks at, and its points become keys of the camera on the
server (net "Cam"), from the playhead to the end of the animation.
]]
local COMP = SPeditor.Component("saeditor")
local SA  = COMP.SA
local C   = SPeditor.Client
local UI  = SPeditor.UI
local L   = SPeditor.L

local ANIM_MODEL = "models/player/kleiner.mdl"

-- { language key, sequence, loop = repeats to the end of the animation }
SA.MOTIONS = {
	{ group = "sa_mg_stand", list = {
		{ "sa_mo_idle", "idle_all_01", loop = true },
		{ "sa_mo_scared", "idle_all_scared", loop = true },
		{ "sa_mo_angry", "idle_all_angry", loop = true },
		{ "sa_mo_crouch", "cidle_all", loop = true },
		{ "sa_mo_sit", "sit_zen", loop = true },
	} },
	{ group = "sa_mg_move", list = {
		{ "sa_mo_walk", "walk_all", loop = true },
		{ "sa_mo_run", "run_all_01", loop = true },
		{ "sa_mo_panic", "run_all_panicked_01", loop = true },
		{ "sa_mo_sneak", "cwalk_all", loop = true },
		{ "sa_mo_zombie", "zombie_walk_01", loop = true },
		{ "sa_mo_swim", "swimming_all", loop = true },
	} },
	{ group = "sa_mg_gesture", list = {
		{ "sa_mo_wave", "gesture_wave" },
		{ "sa_mo_yes", "gesture_agree" },
		{ "sa_mo_no", "gesture_disagree" },
		{ "sa_mo_bow", "gesture_bow" },
		{ "sa_mo_salute", "gesture_salute" },
		{ "sa_mo_come", "gesture_becon" },
		{ "sa_mo_halt", "gesture_signal_halt" },
		{ "sa_mo_forward", "gesture_signal_forward" },
	} },
	{ group = "sa_mg_fun", list = {
		{ "sa_mo_dance", "taunt_dance", loop = true },
		{ "sa_mo_laugh", "taunt_laugh" },
		{ "sa_mo_cheer", "taunt_cheer" },
		{ "sa_mo_robot", "taunt_robot" },
		{ "sa_mo_muscle", "taunt_muscle" },
	} },
	{ group = "sa_mg_action", list = {
		{ "sa_mo_throw", "seq_throw" },
		{ "sa_mo_land", "jump_land" },
		{ "sa_mo_flinch", "flinch_01" },
		{ "sa_mo_die", "death_01" },
		{ "sa_mo_die2", "death_04" },
	} },
}

-- the length of one cycle of a sequence of the animation model, seconds
local durations = {}
local function cycleLength(seq)
	if durations[seq] then return durations[seq] end
	local m = ClientsideModel(ANIM_MODEL, RENDERGROUP_OTHER)
	if not IsValid(m) then return 1 end
	m:SetNoDraw(true)
	local id = m:LookupSequence(seq)
	local d = 1
	if id and id >= 0 then
		m:ResetSequence(id)
		if m:GetPoseParameter("move_x") ~= nil then m:SetPoseParameter("move_x", 1) end
		d = m:SequenceDuration(id) or 1
	end
	m:Remove()
	durations[seq] = math.max(d, 0.1)
	return durations[seq]
end

local function seqId(seq)
	local m = ClientsideModel(ANIM_MODEL, RENDERGROUP_OTHER)
	if not IsValid(m) then return nil end
	local id = m:LookupSequence(seq)
	m:Remove()
	return (id and id >= 0) and id or nil
end

function SA.PlayMotion(ent, mo)
	if not SA.CanImport(ent) then
		SPeditor.Notify("#sa_need_ragdoll", 0)
		return
	end
	local id = seqId(mo[2])
	if not id then
		SPeditor.Notify("#sa_mo_missing", 1)
		return
	end
	local start = math.floor(SA.frame + 0.5)
	local loops = 1
	if mo.loop then
		-- a repeating motion fills the rest of the animation (at least one cycle, at most 16)
		local left = (SA.frames - start) / SA.fps
		if left < 1 then left = 4 end
		loops = math.Clamp(math.floor(left / cycleLength(mo[2]) + 0.5), 1, 16)
	end
	local n = SA.ImportSequence(ent, id, { model = ANIM_MODEL, start = start, step = 2, loops = loops, root = true })
	if n then SPeditor.Notify("#sa_imp_done|" .. L(mo[1]) .. "|" .. n, 2) end
end

-- the ready motions as a menu for ent
function SA.MotionMenu(m, ent)
	for _, g in ipairs(SA.MOTIONS) do
		local sub = m:AddSubMenu(L(g.group))
		for _, mo in ipairs(g.list) do
			sub:AddOption(L(mo[1]), function() SA.PlayMotion(ent, mo) end)
		end
	end
	m:AddSpacer()
	m:AddOption(L("sa_mo_more"), function() SA.OpenImport(ent) end):SetIcon("icon16/film_add.png")
end

---------------------------------------------------------------------
-- Camera moves
---------------------------------------------------------------------
-- what the camera looks at: the object of the scene nearest to its line of sight (within a
-- cone ahead), otherwise what the line hits, otherwise a point 200 units ahead. Client traces
-- pass through ragdolls, so the objects are checked by their centres.
local function target(cam)
	local pos, fwd = cam:GetPos(), cam:GetAngles():Forward()
	local best, bestScore
	for _, e in ipairs(C.Objects()) do
		if IsValid(e) and e ~= cam and not C.IsAux(e) then
			local c = C.CenterOf(e) or e:GetPos()
			local d = c - pos
			local along = d:Dot(fwd)
			if along > 8 then
				local off = (d - fwd * along):Length()
				-- inside a cone of about 25 degrees: the nearer the line, the better
				if off < along * 0.47 then
					local score = off / along
					if not bestScore or score < bestScore then best, bestScore = c, score end
				end
			end
		end
	end
	if best then return best end
	local tr = util.TraceLine({ start = pos, endpos = pos + fwd * 4000, filter = cam, mask = MASK_SOLID })
	return (tr.Hit and tr.Fraction * 4000 < 1500) and tr.HitPos or pos + fwd * 200
end

local function look(from, at)
	local a = (at - from):Angle()
	return Angle(a.p, a.y, 0)
end

-- moves: fn(cam, pos, ang, tgt, u) -> pos, ang, shake (u = 0..1 along the move); keys = how many points
SA.CAM_MOVES = {
	{ "sa_cm_in", keys = 2, fn = function(c, p, a, t, u) return p + (t - p) * 0.45 * u, a end },
	{ "sa_cm_out", keys = 2, fn = function(c, p, a, t, u) return p - (t - p):GetNormalized() * p:Distance(t) * 0.6 * u, a end },
	{ "sa_cm_orbit_l", keys = 5, ease = "linear", fn = function(c, p, a, t, u)
		local off = p - t
		off:Rotate(Angle(0, 90 * u, 0))
		return t + off, look(t + off, t)
	end },
	{ "sa_cm_orbit_r", keys = 5, ease = "linear", fn = function(c, p, a, t, u)
		local off = p - t
		off:Rotate(Angle(0, -90 * u, 0))
		return t + off, look(t + off, t)
	end },
	{ "sa_cm_pan_l", keys = 2, fn = function(c, p, a, t, u) return p, Angle(a.p, a.y + 35 * u, a.r) end },
	{ "sa_cm_pan_r", keys = 2, fn = function(c, p, a, t, u) return p, Angle(a.p, a.y - 35 * u, a.r) end },
	{ "sa_cm_crane", keys = 3, fn = function(c, p, a, t, u)
		local np = p + Vector(0, 0, p:Distance(t) * 0.4 * u)
		return np, look(np, t)
	end },
	{ "sa_cm_shake", keys = 2, fn = function(c, p, a, t, u) return p, a, (1 - u) * 4 end },
}

function SA.CameraMove(cam, mv)
	if not C.IsCamera(cam) then
		SPeditor.Notify("#sa_cm_need", 0)
		return
	end
	local start = math.floor(SA.frame + 0.5)
	local len = SA.frames - start
	if len < SA.fps then
		-- less than a second left: the move takes three, the animation grows
		len = SA.fps * 3
		SA.SetConfig(nil, start + len)
	end
	C.FlushQueue()
	local p0, a0 = cam:GetPos(), cam:GetAngles()
	local tgt = target(cam)
	local id = SA.NextOp()
	COMP:NetStart("Cam")
	net.WriteUInt(id, 32)
	net.WriteEntity(cam)
	net.WriteString(mv.ease or "ease")
	net.WriteUInt(mv.keys, 8)
	for i = 0, mv.keys - 1 do
		local u = i / (mv.keys - 1)
		local p, a, shake = mv.fn(cam, p0, a0, tgt, u)
		net.WriteUInt(start + math.floor(len * u + 0.5), 32)
		SPeditor.WriteVecF(p)
		SPeditor.WriteAngF(a)
		net.WriteFloat(shake or -1)
	end
	net.SendToServer()
	SA.PushOpHistory("sa camera move", id)
end

function SA.CameraMenu(m, cam)
	for _, mv in ipairs(SA.CAM_MOVES) do
		m:AddOption(L(mv[1]), function() SA.CameraMove(cam, mv) end)
	end
end

---------------------------------------------------------------------
-- The "Motion" button of the timeline and the object menu
---------------------------------------------------------------------
-- the menu for whatever is selected: a character gets motions, a camera gets moves
function SA.EasyMenu()
	local ent = C.selected
	local m = UI.Menu()
	if C.IsCamera(ent) then
		SA.CameraMenu(m, ent)
	elseif SA.CanImport(ent) then
		SA.MotionMenu(m, ent)
	else
		m:AddOption(L("sa_easy_need")):SetEnabled(false)
	end
	m:Open()
end

COMP:AddMenu("object", function(m, ent)
	if C.IsCamera(ent) then
		local sub, o = m:AddSubMenu(L("sa_cm_menu"))
		if o and o.SetIcon then o:SetIcon("icon16/camera_go.png") end
		SA.CameraMenu(sub, ent)
	elseif SA.CanImport(ent) then
		local sub, o = m:AddSubMenu(L("sa_mo_menu"))
		if o and o.SetIcon then o:SetIcon("icon16/user_go.png") end
		SA.MotionMenu(sub, ent)
	end
end)
