-- Flexes (facial expressions) and gaze direction
SPeditor.Client = SPeditor.Client or {}
local C = SPeditor.Client

-- (sfm-faces) the FACS names of Valve's HL2 / L4D faces (inner_raiser, lowerer, wrinkler,
-- corner_puller …) and of the L4D2 / TF2 animation faces (ScalpD, NostrilFlare, Platysmus) have
-- their groups too; they used to land in Other
local FLEX_GROUPS = {
	{ name = "Brows", patterns = { "brow", "inner_raiser", "outer_raiser", "lowerer", "scalp" } },
	{ name = "Eyes",  patterns = { "lid", "eye", "blink", "squint", "wink", "dilator" } },
	{ name = "Nose",  patterns = { "nose", "nostril", "sneer", "wrinkler" } },
	{ name = "Mouth", patterns = { "mouth", "lip", "smile", "frown", "jaw", "tongue", "teeth", "cheek", "puff", "dimple", "funnel", "pucker", "stretch",
		"corner", "chin", "bite", "presser", "tightener", "platysm", "part", "upper_raiser" } },
}

-- (sfm-faces) Faces built for SFM split a slider into a right and a left half (right_CloseLid /
-- left_CloseLid), sometimes with a third, multi_CloseLid; SFM shows the set as one slider with a
-- balance knob. Returns the side ("right" / "left" / "multi") and the shared name, or nil.
local SIDE_FORMS = {
	{ "^right_(.+)$", "right" }, { "^left_(.+)$", "left" }, { "^multi_(.+)$", "multi" },
	{ "^(.+)_right$", "right" }, { "^(.+)_left$", "left" },
	{ "^r_(.+)$", "right" }, { "^l_(.+)$", "left" }, { "^(.+)_r$", "right" }, { "^(.+)_l$", "left" },
}
function C.FlexSideOf(name)
	local lname = string.lower(name or "")
	for _, f in ipairs(SIDE_FORMS) do
		local base = string.match(lname, f[1])
		if base then
			-- the shared name as the model writes it (CloseLid, not closelid)
			local s, e = string.find(lname, base, 1, true)
			return f[2], string.sub(name, s, e), base
		end
	end
end

-- The sets of a flex list: [key] = { name, right = f, left = f, multi = f } for the names that have
-- BOTH a right and a left half (sneer_left alone is no set); setOf[flex id] = key
local SIDE_RANK = { right = 1, left = 2, multi = 3 }
C.FlexSideRank = SIDE_RANK
function C.FlexSets(list)
	local sets, setOf = {}, {}
	for _, f in ipairs(list) do
		local side, name, key = C.FlexSideOf(f.name)
		if side then
			sets[key] = sets[key] or { name = name }
			sets[key][side] = sets[key][side] or f
		end
	end
	for key, s in pairs(sets) do
		if s.right and s.left then
			for side in pairs(SIDE_RANK) do
				if s[side] then setOf[s[side].id] = key end
			end
		else
			sets[key] = nil
		end
	end
	return sets, setOf
end

function C.FlexGroupOf(name)
	local lname = string.lower(name)
	for _, g in ipairs(FLEX_GROUPS) do
		for _, pat in ipairs(g.patterns) do
			if string.find(lname, pat, 1, true) then return g.name end
		end
	end
	return "Other"
end

function C.GetFlexList(ent)
	local list = {}
	if not IsValid(ent) then return list end
	for i = 0, ent:GetFlexNum() - 1 do
		local name = ent:GetFlexName(i)
		if name then
			local mn, mx = ent:GetFlexBounds(i)
			list[#list + 1] = {
				id = i, name = name, min = mn or 0, max = mx or 1,
				weight = SPeditor.FlexGet(ent, i), group = C.FlexGroupOf(name),
			}
		end
	end
	return list
end

function C.EditFlex(ent, id, weight)
	if not IsValid(ent) then return end
	C.SendFlex(ent, id, weight)
	local ref = C.Ref(ent)
	-- (b0.2.6-misc.1) the sliders edited since the last auto key: it keys only them (SAeditor)
	C.editedFlex = C.editedFlex or {}
	C.editedFlex[ent] = C.editedFlex[ent] or {}
	C.editedFlex[ent][id] = true

	C.BurstEdit("fx" .. ent:EntIndex() .. "_" .. id, "flex",
		function() return SPeditor.FlexGet(ent, id) end,
	weight,
	function(w) local e = C.Deref(ref) if e then C.SendFlex(e, id, w, true) end end)
end

function C.ResetFlexes(ent)
	ent.SPeditor_EyeUI = nil
	C.SnapshotThen(ent, "reset face", function() C.SendReset(ent, 2) end)
end

---------------------------------------------------------------------
-- Eyes. Per the wiki on SetEyeTarget: for ragdolls the position is local to the
-- "eyes" attachment, for other entities it is in world space.
---------------------------------------------------------------------
local function eyeVector(ent, yaw, pitch, dist)
	local dir = Angle(pitch, yaw, 0):Forward() * dist
	if ent:GetClass() == "prop_ragdoll" then return dir end

	local idx = ent:LookupAttachment("eyes")
	if not idx or idx <= 0 then return nil end
	local att = ent:GetAttachment(idx)
	if not att then return nil end
	local world = LocalToWorld(dir, angle_zero, att.Pos, att.Ang)
	return world
end

local function applyEye(ent, st, now)
	ent.SPeditor_EyeUI = st
	local vec = st.on and eyeVector(ent, st.yaw, st.pitch, st.dist) or nil
	C.SendEye(ent, vec ~= nil, vec or vector_origin, now)
end

function C.GetEyeState(ent)
	local st = ent.SPeditor_EyeUI
	if st then return table.Copy(st) end
	return { on = false, yaw = 0, pitch = 0, dist = 100 }
end

-- The eye state that aims the eyes at a point of the world (b0.1: "look at the camera"),
-- or nil when the model has no "eyes" attachment
function C.EyeStateTowards(ent, point)
	local idx = IsValid(ent) and ent:LookupAttachment("eyes")
	local att = idx and idx > 0 and ent:GetAttachment(idx)
	if not att then return nil end
	local dir = WorldToLocal(point, angle_zero, att.Pos, att.Ang)
	local a = dir:Angle()
	return { on = true, yaw = math.NormalizeAngle(a.y), pitch = math.Clamp(math.NormalizeAngle(a.p), -90, 90),
		dist = math.Clamp(dir:Length(), 10, 500) }
end

-- st = { on, yaw, pitch, dist }; yaw/pitch in degrees
function C.EditEye(ent, st)
	if not IsValid(ent) then return end
	local before = C.GetEyeState(ent)
	local ref = C.Ref(ent)
	applyEye(ent, table.Copy(st))

	C.BurstEdit("ey" .. ent:EntIndex(), "eyes",
		function() return before end,
	table.Copy(st),
	function(s) local e = C.Deref(ref) if e then applyEye(e, table.Copy(s), true) end end)
end
