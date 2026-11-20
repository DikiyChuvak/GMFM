--[[
SPeditor — fingers (b0.2.6-misc.1): the hands of a model found by their bones, the Finger Poser of the
Animation Set Editor (as GMod's own tool: a dot per finger joint on a picture of the hand) and IK
for the fingers.

Hands are found by the bone names GMod's Finger Poser knows (HL2 / ValveBiped, TF2 and SFM, Zeno
Clash, Insurgency, Portal 1 and 2, and what addons add to the list "FingerPoserSkeletons"), else
by the bone tree: chains of bones under a bone named hand / wrist / paw.

A dot's two values (x: sideways, y: the curl; ±50 degrees, a negative y curls toward the palm, as
in GMod's presets) go into the bone's manip angle the way GMod's tool puts them, so a pose made
here matches the tool and its presets. For a hand found by the bone tree the axes are worked out
from where the fingers lie.

Finger IK (with IK or Auto pose on): the gizmo moving the last joint of a finger bends the whole
finger (the knuckle and the middle joint by two-link IK, the last joint curling along with the
middle one); moving the middle joint turns the knuckle. Several fingers selected bend together.

  F.Hands(ent) -> { L = hand, R = hand } (either may be missing); hand = { side, bone (the hand),
      fingers = { [1..5] = { bones = { b, b, b }, maps = { map, map, map } } }, of = { [bone] = { finger, joint } } };
      finger 1 is the thumb, a map = { x = { field, sign }, y = { field, sign } } (field "p" / "y" / "r")
  F.SideOf(ent, bone) -> "L" / "R" / nil      the hand bone or a finger bone
  F.Get(ent, bone, map) -> x, y               F.Set(ent, { { bone, map, x, y }, … }, final)
  F.ApplyPreset(ent, hand, id) / F.Mirror(ent, hand) / F.Curl(ent, hand) / F.SetCurl(ent, hand, v, final)
  F.BeginIK(ent, bone, bones) -> state or nil;  F.SolveIK(state, off)   (cl_gizmo.lua)
]]
SPeditor = SPeditor or {}
SPeditor.Fingers = SPeditor.Fingers or {}
local F = SPeditor.Fingers
local C = SPeditor.Client

F.MAX = 50      -- how far a dot turns a joint, degrees (GMod: ±0.5 × 100)

local cvRestrict = CreateClientConVar("gmfm_finger_restrict", "1", true, false,
	"Finger Poser: the middle and last joints of the fingers only curl (0/1)", 0, 1)
function F.Restricted() return cvRestrict:GetBool() end
function F.SetRestricted(on) RunConsoleCommand("gmfm_finger_restrict", on and "1" or "0") end

---------------------------------------------------------------------
-- Skeletons
---------------------------------------------------------------------
-- which manip angle field each value of a dot goes to, and its sign (GMod's finger.lua)
local MAPS = {
	valve   = { thumb = { x = { "y", 1 }, y = { "p", 1 } }, finger = { x = { "p", 1 }, y = { "y", 1 } } },
	tf2     = { thumb = { x = { "r", 1 }, y = { "y", 1 } }, finger = { x = { "y", 1 }, y = { "r", -1 } } },
	portal2 = { thumb = { x = { "p", 1 }, y = { "y", 1 } }, finger = { x = { "y", 1 }, y = { "p", -1 } } },
}

local NAMES = { "thumb", "index", "middle", "ring", "pinky" }
local SHORT = { "thumb", "index", "mid", "ring", "pinky" }
local JOINT = { "base", "mid", "end" }
local function valveName(s, f, p) return "ValveBiped.Bip01_" .. s .. "_Finger" .. f .. (p > 0 and p or "") end
-- name(side "L"/"R", finger 0..4, joint 0..2): GMod's translation tables, written as patterns
local BUILTIN = {
	{ map = "valve",   name = valveName },
	{ map = "tf2",     name = function(s, f, p) return "bip_" .. NAMES[f + 1] .. "_" .. p .. "_" .. s end },
	{ map = "valve",   name = function(s, f, p) return "Bip01_" .. s .. "_Finger" .. f .. (p > 0 and p or "") end },
	{ map = "valve",   name = function(s, f, p) return "Bip01 " .. s .. " Finger" .. f .. (p > 0 and p or "") end },
	{ map = "valve",   name = function(s, f, p) return s .. " Finger" .. f .. (p > 0 and p or "") end },
	{ map = "valve",   name = function(s, f, p) return SHORT[f + 1] .. "_" .. JOINT[p + 1] .. "_" .. s end },
	{ map = "portal2", name = function(s, f, p) return SHORT[f + 1] .. "_" .. p .. "_" .. s end },
}

local function skeletons()
	local out = {}
	for _, s in ipairs(BUILTIN) do out[#out + 1] = s end
	-- what GMod's Finger Poser (Sandbox only: GM:FM derives from base) and other addons add
	local extra = (list and list.Get) and list.Get("FingerPoserSkeletons") or {}
	for _, v in SortedPairs(extra) do
		if istable(v) and istable(v.bones) then
			local map = (v.hand_type == "tf2" and "tf2") or (v.hand_type == "portal2" and "portal2") or "valve"
			out[#out + 1] = { map = map, name = function(s, f, p) return v.bones[valveName(s, f, p)] end }
		end
	end
	return out
end

local function byNames(ent, sk)
	local hands = {}
	for _, s in ipairs({ "L", "R" }) do
		local fingers, any = {}, false
		for f = 0, 4 do
			local bones = {}
			for p = 0, 2 do
				local name = sk.name(s, f, p)
				local b = name and ent:LookupBone(name)
				if not b then break end
				bones[#bones + 1] = b
			end
			if #bones > 0 then
				local m = MAPS[sk.map][f == 0 and "thumb" or "finger"]
				fingers[f + 1] = { bones = bones, maps = { m, m, m } }
				any = true
			end
		end
		if any then hands[s] = { side = s, fingers = fingers } end
	end
	return next(hands) and hands or nil
end

-- By the bone tree: a bone named hand / wrist / paw with a side, and the chains of bones under it
-- (or under a palm bone or two below it)
local HAND, FOOT, SKIP = SPeditor.LimbNames.HAND, SPeditor.LimbNames.FOOT, SPeditor.LimbNames.SKIP
local KEYS = { { "thumb" }, { "index", "point" }, { "middle", "mid" }, { "ring" }, { "pinky", "little", "small" } }
local function has(n, list)
	for _, p in ipairs(list) do
		if string.find(n, p, 1, true) then return true end
	end
	return false
end
local function sideOf(name)
	local n = "_" .. name .. "_"
	if string.find(n, "[_%.%s]l[_%.%s]") or string.find(n, "left", 1, true) then return "L" end
	if string.find(n, "[_%.%s]r[_%.%s]") or string.find(n, "right", 1, true) then return "R" end
end
local function lname(ent, b) return string.lower(ent:GetBoneName(b) or "") end
local function pos(ent, b) return (C.GetBoneWorld(ent, b)) end

local function byTree(ent)
	local kids = {}
	for b = 0, ent:GetBoneCount() - 1 do
		local p = ent:GetBoneParent(b)
		if p and p >= 0 then
			kids[p] = kids[p] or {}
			table.insert(kids[p], b)
		end
	end
	local function chainFrom(b)
		local out = { b }
		while kids[out[#out]] and #kids[out[#out]] == 1 and #out < 6 do out[#out + 1] = kids[out[#out]][1] end
		-- a tip marker of a 3ds Max export (…Nub) is no joint
		if #out > 1 and string.find(lname(ent, out[#out]), "nub", 1, true) then out[#out] = nil end
		-- a bone of the palm before the finger: the last three are the joints
		while #out > 3 do table.remove(out, 1) end
		return out
	end
	local hands = {}
	for b = 0, ent:GetBoneCount() - 1 do
		local n = lname(ent, b)
		local s = sideOf(n)
		if s and not hands[s] and has(n, HAND) and not has(n, FOOT) and not has(n, SKIP) then
			local at, chains = b, {}
			for _ = 1, 3 do
				chains = {}
				for _, c in ipairs(kids[at] or {}) do
					local ch = chainFrom(c)
					if #ch >= 2 and not has(lname(ent, c), SKIP) then chains[#chains + 1] = ch end
				end
				if #chains >= 2 or not kids[at] or #kids[at] ~= 1 then break end
				at = kids[at][1]
			end
			if #chains >= 2 then
				local slot, free = {}, {}
				for _, ch in ipairs(chains) do
					local cn, k = lname(ent, ch[1]), nil
					for i, keys in ipairs(KEYS) do
						if not slot[i] and has(cn, keys) then k = i break end
					end
					if k then slot[k] = ch else free[#free + 1] = ch end
				end
				-- no names to go by: the thumb is the one apart from the others, then the nearest
				-- to it is the index finger and so on
				if not slot[1] and #free > 1 then
					local best, bi = -1, nil
					for i, ch in ipairs(free) do
						local p, sum = pos(ent, ch[1]), 0
						for j, o in ipairs(free) do
							if j ~= i and p then sum = sum + p:Distance(pos(ent, o[1]) or p) end
						end
						if sum > best then best, bi = sum, i end
					end
					slot[1] = table.remove(free, bi)
				end
				local tp = slot[1] and pos(ent, slot[1][1])
				if tp then
					table.sort(free, function(a, c) return tp:DistToSqr(pos(ent, a[1]) or tp) < tp:DistToSqr(pos(ent, c[1]) or tp) end)
				end
				for i = 2, 5 do
					if not slot[i] and #free > 0 then slot[i] = table.remove(free, 1) end
				end
				local fingers = {}
				for i = 1, 5 do
					if slot[i] then fingers[i] = { bones = slot[i] } end
				end
				hands[s] = { side = s, fingers = fingers, bone = b, tree = true }
			end
		end
	end
	return next(hands) and hands or nil
end

-- the axes of a manip angle's fields in the world, for a bone at the world angle a: a turn by +
-- of the field turns the bone right-handedly round it (roll: forward, pitch: left, yaw: up)
local AXIS = {
	r = function(a) return a:Forward() end,
	p = function(a) return -a:Right() end,
	y = function(a) return a:Up() end,
}
local FIELDS = { "r", "p", "y" }
local function nearestField(a, v, skip)
	local best, bf, bs = -1, nil, 1
	for _, f in ipairs(FIELDS) do
		if f ~= skip then
			local d = AXIS[f](a):Dot(v)
			if math.abs(d) > best then best, bf, bs = math.abs(d), f, d >= 0 and 1 or -1 end
		end
	end
	return bf, bs
end

-- the palm of a hand in the world: its normal (out of the palm), across (from the index finger
-- toward the little one) and the way the fingers point
local function palmOf(ent, hand)
	local roots = {}
	for i = 2, 5 do
		local f = hand.fingers[i]
		local p = f and pos(ent, f.bones[1])
		if p then roots[#roots + 1] = p end
	end
	local hp = pos(ent, hand.bone)
	if not hp or #roots == 0 then return nil end
	local mid = Vector(0, 0, 0)
	for _, p in ipairs(roots) do mid = mid + p end
	mid = mid / #roots
	local d = (mid - hp):GetNormalized()
	local across
	if #roots >= 2 then
		across = roots[#roots] - roots[1]
	else
		local tp = hand.fingers[1] and pos(ent, hand.fingers[1].bones[1])
		if not tp then return nil end
		across = roots[1] - tp
	end
	across = across - d * across:Dot(d)
	if across:LengthSqr() < 1e-8 then return nil end
	across = across:GetNormalized()
	-- a right hand, palm down, fingers forward: the thumb is on the left, so index → little finger
	-- goes right and forward × right is down, into the palm's side
	local n = hand.side == "R" and d:Cross(across) or across:Cross(d)
	return n, across, d
end

-- the dot's axes of every joint of a hand found by the tree, from where its fingers lie
local function treeMaps(ent, hand)
	local n, across = palmOf(ent, hand)
	if not n then return false end
	for _, f in pairs(hand.fingers) do
		f.maps = {}
		for i, b in ipairs(f.bones) do
			local p, a = C.GetBoneWorld(ent, b)
			if not p or not a then return false end
			local nx = f.bones[i + 1] and pos(ent, f.bones[i + 1])
			local pv = f.bones[i - 1] and pos(ent, f.bones[i - 1])
			local d = (nx and (nx - p)) or (pv and (p - pv)) or a:Forward()
			d = d:GetNormalized()
			local curl = d:Cross(n)          -- a turn round it by + takes the finger toward the palm
			local side = d:Cross(across)     -- … toward the little finger
			local cf, cs = nearestField(a, curl)
			local sf, ss = nearestField(a, side, cf)
			-- y: negative curls (as GMod), so the field is -cs * y
			f.maps[i] = { x = { sf, ss }, y = { cf, -cs } }
		end
	end
	return true
end

local cache = {}
function F.Hands(ent)
	if not IsValid(ent) or (C.IsAux and C.IsAux(ent)) or ent:GetBoneCount() < 3 then return {} end
	local key = (ent:GetModel() or "") .. "|" .. ent:GetBoneCount()
	local h = cache[key]
	if h == nil then
		h = false
		for _, sk in ipairs(skeletons()) do
			h = byNames(ent, sk)
			if h then break end
		end
		local tree = false
		if not h then
			h = byTree(ent) or false
			tree = h and true
		end
		if h then
			for s, hand in pairs(h) do
				hand.of = {}
				for i, f in pairs(hand.fingers) do
					for j, b in ipairs(f.bones) do hand.of[b] = { i, j } end
					if not hand.bone then
						local p = ent:GetBoneParent(f.bones[1])
						if p and p >= 0 and i > 1 then hand.bone = p end
					end
				end
				if not hand.bone then
					local any = hand.fingers[1] or select(2, next(hand.fingers))
					hand.bone = ent:GetBoneParent(any.bones[1])
				end
				if hand.tree and not treeMaps(ent, hand) then h[s] = nil end
			end
			if not next(h) then h = false end
		end
		-- a hand found by the tree needs the bones in place: not kept while they are not
		if h or not tree then cache[key] = h end
	end
	return h or {}
end

function F.SideOf(ent, bone)
	if not bone or bone < 0 then return nil end
	for s, hand in pairs(F.Hands(ent)) do
		if bone == hand.bone or hand.of[bone] then return s end
	end
end

---------------------------------------------------------------------
-- The values of the dots
---------------------------------------------------------------------
local open = {}     -- [ent] = the series of edits not yet in the history: { before, after }

local function manipOf(ent, b)
	return { p = ent:GetManipulateBonePosition(b), a = ent:GetManipulateBoneAngles(b), s = ent:GetManipulateBoneScale(b) }
end

-- the manip angle of a bone: the one just sent while a series is open (the server's comes later)
function F.Angle(ent, bone)
	local o = open[ent]
	local v = o and o.after[bone]
	return v and v.a or ent:GetManipulateBoneAngles(bone)
end

function F.Get(ent, bone, map)
	local a = F.Angle(ent, bone)
	return map.x[2] * a[map.x[1]], map.y[2] * a[map.y[1]]
end

-- list = { { bone, map, x, y, whole }, … }; x or y nil — kept. The other field of the angle, the
-- offset and the scale stay as they are (a dot dragged on a finger turned by the gizmo or IK does
-- not snap back); whole = true (presets, as GMod): the angle is just x and y. One undo step per
-- series; auto key keys the bones that changed.
function F.Set(ent, list, final)
	if not IsValid(ent) then return end
	local o = open[ent]
	if not o then
		local before = {}
		for _, hand in pairs(F.Hands(ent)) do
			for b in pairs(hand.of) do before[b] = manipOf(ent, b) end
		end
		o = { before = before, after = table.Copy(before) }
		open[ent] = o
	end
	for _, e in ipairs(list) do
		local b, map = e[1], e[2]
		local cur = o.after[b] or manipOf(ent, b)
		local a = e[5] and Angle(0, 0, 0) or Angle(cur.a.p, cur.a.y, cur.a.r)
		if e[3] then a[map.x[1]] = map.x[2] * math.Clamp(e[3], -90, 90) end
		if e[4] then a[map.y[1]] = map.y[2] * math.Clamp(e[4], -90, 90) end
		o.after[b] = { p = cur.p, a = a, s = cur.s }
		C.SendBoneManip(ent, b, cur.p, a, cur.s, final)
	end
	local ref, changed = C.Ref(ent), {}
	C.BurstEdit("fingers" .. ent:EntIndex(), "fingers", function() return o.before end, table.Copy(o.after),
		function(st)
			local e2 = C.Deref(ref)
			if not e2 then return end
			for b in pairs(changed) do
				local v = st[b]
				if v then C.SendBoneManip(e2, b, v.p, v.a, v.s, true) end
			end
		end,
		function(before, after)
			if open[ent] == o then open[ent] = nil end
			local parts = {}
			for b, v in pairs(after) do
				local w = before[b]
				if not w or v.a ~= w.a or v.p ~= w.p or v.s ~= w.s then
					changed[b] = true
					parts[#parts + 1] = "b" .. b
				end
			end
			table.sort(parts)
			-- auto key: only these bones (cl_saeditor.lua reads it as for a gizmo drag)
			if #parts > 0 and IsValid(ent) then C.lastEditParts = { ent = ent, parts = table.concat(parts, ","), t = RealTime() } end
		end)
	if final then C.FlushBursts() end
end

-- GMod's presets (settings/presets/finger), the 15 dots in order: thumb, index … little finger,
-- each from the knuckle out. A dot is "x y".
local GMOD_POINT = { "31.3 -6.3", "0 14.6", "0 10.4", "8.3 22.9", "0 10.4", "0 4.2", "-16.7 -50", "0 -50", "0 -50",
	"-10.4 -50", "0 -50", "0 -50", "4.2 -50", "0 -50", "0 -50" }
F.PRESETS = {
	{ id = "reset" },
	{ id = "flat", v = { "-4.2 -29.2", "0 -2.1", "0 10.4", "6.3 31.3", "0 10.4", "0 4.2", "0 22.9", "0 35.4", "0 2.1",
		"-8.3 12.5", "0 39.6", "0 25", "-20.8 27.1", "0 8.3", "0 29.2" } },
	{ id = "point", v = GMOD_POINT },
	-- the point with the index finger curled too
	{ id = "fist", v = { GMOD_POINT[1], GMOD_POINT[2], GMOD_POINT[3], "8.3 -50", "0 -50", "0 -50", unpack(GMOD_POINT, 7) } },
	{ id = "thumbsup", v = { "2.1 -20.8", "-50 -14.6", "-6.3 6.3", "-25 -50", "0 -50", "0 -50", "-16.7 -50", "0 -50", "0 -50",
		"-10.4 -50", "0 -50", "0 -50", "4.2 -50", "0 -50", "0 -50" } },
}

local function joints(hand)
	local out = {}
	for i = 1, 5 do
		local f = hand.fingers[i]
		if f then
			for j, b in ipairs(f.bones) do out[#out + 1] = { b = b, map = f.maps[j], i = i, j = j } end
		end
	end
	return out
end
F.Joints = joints

function F.ApplyPreset(ent, hand, id)
	local pr
	for _, p in ipairs(F.PRESETS) do
		if p.id == id then pr = p end
	end
	if not pr then return end
	local list = {}
	for _, jt in ipairs(joints(hand)) do
		local v = pr.v and pr.v[(jt.i - 1) * 3 + jt.j]
		local x, y = 0, 0
		if v then
			local a, b = string.match(v, "^(%S+)%s+(%S+)$")
			x, y = tonumber(a) or 0, tonumber(b) or 0
		end
		list[#list + 1] = { jt.b, jt.map, x, y, true }
	end
	F.Set(ent, list, true)
end

-- the other hand takes this one's pose (the values are mirrored by the skeleton itself: GMod's
-- presets are the same for both hands)
function F.Mirror(ent, hand)
	local other = F.Hands(ent)[hand.side == "L" and "R" or "L"]
	if not other then return end
	local list = {}
	for _, jt in ipairs(joints(hand)) do
		local f = other.fingers[jt.i]
		local b = f and f.bones[jt.j]
		if b then
			local x, y = F.Get(ent, jt.b, jt.map)
			list[#list + 1] = { b, f.maps[jt.j], x, y, true }
		end
	end
	F.Set(ent, list, true)
end

-- how far the fingers (not the thumb) are curled: 1 — every joint at -50
function F.Curl(ent, hand)
	local sum, n = 0, 0
	for _, jt in ipairs(joints(hand)) do
		if jt.i > 1 then
			local _, y = F.Get(ent, jt.b, jt.map)
			sum, n = sum + y, n + 1
		end
	end
	return n > 0 and -sum / n / F.MAX or 0
end

function F.SetCurl(ent, hand, v, final)
	local list = {}
	for _, jt in ipairs(joints(hand)) do
		if jt.i > 1 then list[#list + 1] = { jt.b, jt.map, nil, -v * F.MAX } end
	end
	F.Set(ent, list, final)
end

---------------------------------------------------------------------
-- Finger IK
---------------------------------------------------------------------
local MAX_BEND = 110     -- the middle joint folds this far at most, degrees
local DIP = 2 / 3        -- the last joint curls by this share of the middle one's change
-- a straight finger pulled shorter bends as the square root of the pull: the first pixel snapped
-- the middle joint by ~10 degrees. Near straight the pull is eased in (cubic at first, caught up
-- within about this share of the finger's length)
local EASE = 0.08
local TIP_OPEN, TIP_CURL = -10, 90      -- the last joint's curl from rest, degrees

-- the axis a joint curls round in the world (a turn by + takes it toward the palm)
local function curlAxis(map, a) return AXIS[map.y[1]](a) * -map.y[2] end

local function angBetween(a, b)
	return math.deg(math.acos(math.Clamp(a:GetNormalized():Dot(b:GetNormalized()), -1, 1)))
end

local function item(ent, b)
	local p, a = C.GetBoneWorld(ent, b)
	local par = ent:GetBoneParent(b)
	if not p or not a or not par or par < 0 then return nil end
	local _, pa = C.GetBoneWorld(ent, par)
	if not pa then return nil end
	return { bone = b, p0 = p, a0 = a, parentAng = pa,
		m0pos = ent:GetManipulateBonePosition(b), m0ang = ent:GetManipulateBoneAngles(b), m0scale = ent:GetManipulateBoneScale(b) }
end

-- bone: the one the gizmo is on; bones: the selection. Nil unless every bone of the selection
-- that has no physics body is the middle or last joint of a finger (then it is a plain move).
function F.BeginIK(ent, bone, bones)
	local hands = F.Hands(ent)
	if not next(hands) then return nil end
	local picked = {}
	local list = (bones and #bones > 0) and bones or { bone }
	local mine = false
	for _, b in ipairs(list) do
		if b >= 0 and C.PhysIndexOfBone(ent, b) == nil then
			local found
			for _, hand in pairs(hands) do
				local at = hand.of[b]
				if at then found = { hand = hand, i = at[1], j = at[2] } end
			end
			if not found or found.j < 2 then return nil end
			local key = found.hand.side .. found.i
			if not picked[key] or picked[key].j < found.j then picked[key] = found end
			mine = mine or b == bone
		end
	end
	if not mine then return nil end
	local st = { ent = ent, items = {}, chains = {} }
	local have = {}
	local function add(b)
		if not have[b] then
			local it = item(ent, b)
			if not it then return nil end
			st.items[#st.items + 1] = it
			have[b] = it
		end
		return have[b]
	end
	for _, f in SortedPairs(picked) do
		local fb = f.hand.fingers[f.i]
		local r, m = add(fb.bones[1]), add(fb.bones[2])
		if not r or not m then return nil end
		if f.j == 3 and fb.bones[3] then
			local e = add(fb.bones[3])
			if not e then return nil end
			local ch = { kind = "tip", r = r, m = m, e = e, map = fb.maps[2], emap = fb.maps[3], thumb = f.i == 1 }
			ch.l1, ch.l2 = r.p0:Distance(m.p0), m.p0:Distance(e.p0)
			ch.c = curlAxis(ch.map, m.a0)
			-- the side the middle joint sticks out to: its own while the digit is visibly bent (a
			-- wrong guess of the axis must not flip it), else away from the palm. The fingers' axis
			-- is GMod's (its presets curl them by -y); the thumb's is not sure, so a straight thumb
			-- bends by the palm found from the hand
			local line = (e.p0 - r.p0):GetNormalized()
			local own = (m.p0 - r.p0) - line * (m.p0 - r.p0):Dot(line)
			if own:Length() > 0.1 * ch.l1 then ch.ownSide = own end
			if ch.thumb then ch.palm = palmOf(ent, f.hand) end
			-- the last joint's curl now, degrees from rest: a finger's by its dot (-y curls), the
			-- thumb's as if it went along with its middle joint
			if ch.thumb then
				ch.c0 = DIP * angBetween(m.p0 - r.p0, e.p0 - m.p0)
			else
				local _, y = F.Get(ent, e.bone, ch.emap)
				ch.c0 = -y
			end
			ch.d0 = r.p0:Distance(e.p0)
			ch.minD = math.min(math.sqrt(ch.l1 * ch.l1 + ch.l2 * ch.l2 - 2 * ch.l1 * ch.l2 * math.cos(math.rad(180 - MAX_BEND))),
				r.p0:Distance(e.p0))
			st.chains[#st.chains + 1] = ch
		else
			st.chains[#st.chains + 1] = { kind = "mid", r = r, m = m }
		end
	end
	return #st.chains > 0 and st or nil
end

local function solveTip(ch, target)
	local IK = SPeditor.IK
	local r, m, e = ch.r, ch.m, ch.e
	local l1, l2 = ch.l1, ch.l2
	local toT = target - r.p0
	local dist = toT:Length()
	if dist < 1e-3 or l1 < 1e-3 or l2 < 1e-3 then return end
	local dir = toT / dist
	-- how much shorter than straight the finger is pulled, eased in when it started near straight
	local L = l1 + l2
	local s0, s = L - ch.d0, L - dist
	local w = EASE * L
	local k = math.Clamp(1 - s0 / w, 0, 1)
	if k > 0 then
		local x = s - s0
		s = s0 + x * (1 - k * math.exp(-(x / w) ^ 2))
	end
	-- the side is given, so the finger may go fully straight (no bend to keep a plane by)
	local d = math.Clamp(L - s, ch.minD, L)
	local cosA = math.Clamp((l1 * l1 + d * d - l2 * l2) / (2 * l1 * d), -1, 1)
	local sinA = math.sqrt(1 - cosA * cosA)
	local side = ch.ownSide or (ch.palm and -ch.palm) or dir:Cross(ch.c)
	side = side - dir * side:Dot(dir)
	if side:LengthSqr() < 1e-8 then side = dir:Cross(ch.c) end
	side = side:GetNormalized()
	local midNew = r.p0 + dir * (l1 * cosA) + side * (l1 * sinA)
	local endNew = r.p0 + dir * d
	local rAng = IK.RotateAngle(r.a0, m.p0 - r.p0, midNew - r.p0)
	-- the middle bone carried by the knuckle's turn, then aimed at the new end
	local lp, la = WorldToLocal(m.p0, m.a0, r.p0, r.a0)
	local _, mCarry = LocalToWorld(lp, la, r.p0, rAng)
	local lpE, laE = WorldToLocal(e.p0, e.a0, m.p0, m.a0)
	local eCarry = LocalToWorld(lpE, angle_zero, midNew, mCarry)
	local mAng = IK.RotateAngle(mCarry, eCarry - midNew, endNew - midNew)
	-- the last joint keeps its turn on the middle one and curls along by DIP of its change, kept
	-- between a little past straight and 90 degrees (or where it already was): opening a bent
	-- finger whose tip was straight bent the tip backward
	local _, eAng = LocalToWorld(vector_origin, laE, vector_origin, mAng)
	local bend = angBetween(midNew - r.p0, endNew - midNew) - angBetween(m.p0 - r.p0, e.p0 - m.p0)
	local c0 = ch.c0
	local delta = math.Clamp(c0 + bend * DIP, math.min(TIP_OPEN, c0), math.max(TIP_CURL, c0)) - c0
	local hinge
	if ch.thumb then
		-- the thumb's own bend, else toward the palm (as the tree's axes: forward × palm)
		hinge = (midNew - r.p0):Cross(endNew - midNew)
		if hinge:LengthSqr() < 1e-8 then
			hinge = ch.palm and (endNew - midNew):Cross(ch.palm) or curlAxis(ch.emap, eAng)
		end
		hinge = hinge:GetNormalized()
	else
		hinge = curlAxis(ch.emap, eAng)
	end
	eAng = IK.RotateAround(eAng, hinge, delta)
	r.m1ang = IK.ManipFor(r, rAng, r.parentAng)
	m.m1ang = IK.ManipFor(m, mAng, rAng)
	e.m1ang = IK.ManipFor(e, eAng, mAng)
end

-- off: how far the gizmo moved the bone it is on (the same for every finger of the selection)
function F.SolveIK(st, off)
	local IK = SPeditor.IK
	for _, ch in ipairs(st.chains) do
		if ch.kind == "tip" then
			solveTip(ch, ch.e.p0 + off)
		else
			local r, m = ch.r, ch.m
			local rAng = IK.RotateAngle(r.a0, m.p0 - r.p0, m.p0 + off - r.p0)
			r.m1ang = IK.ManipFor(r, rAng, r.parentAng)
		end
	end
	for _, it in ipairs(st.items) do
		it.m1pos, it.m1scale = it.m0pos, it.m0scale
		it.m1ang = it.m1ang or it.m0ang
		if IsValid(st.ent) then C.SendBoneManip(st.ent, it.bone, it.m0pos, it.m1ang, it.m0scale) end
	end
end

if not CLIENT or not vgui then return end

---------------------------------------------------------------------
-- The Finger Poser panel (GMod's look: the picture of a hand, a dot per joint)
---------------------------------------------------------------------
-- where the joints are on the picture (GMod's fingerposer.lua: x / 310, y / 270 of its side)
local SPOTS = {
	{ 60, 215 }, { 50, 175 }, { 55, 130 },
	{ 117, 135 }, { 128, 85 }, { 149, 45 },
	{ 155, 145 }, { 172, 100 }, { 197, 60 },
	{ 185, 160 }, { 215, 115 }, { 235, 85 },
	{ 215, 175 }, { 245, 145 }, { 272, 120 },
}
local HAND_MAT = Material("gui/hand_human_left.png", "smooth")

local PANEL = {}

function PANEL:Init()
	self:SetMouseInputEnabled(true)
	self.pads = {}
end

function PANEL:Setup(ent, hand, maxSize)
	self.ent, self.hand, self.maxSize = ent, hand, maxSize or 300
	self.pads = {}
	for _, jt in ipairs(joints(hand)) do
		self.pads[#self.pads + 1] = { b = jt.b, map = jt.map, spot = SPOTS[(jt.i - 1) * 3 + jt.j],
			-- GMod: the middle and last joints of the fingers only curl (Restrict to the Y axis)
			restrict = jt.i > 1 and jt.j > 1 }
	end
	self:InvalidateLayout(true)
end

function PANEL:PerformLayout(w)
	local size = math.min(w, self.maxSize)
	self.size, self.ox = size, math.floor((w - size) / 2)
	self.ps = math.max(math.floor(size * 0.17), 14)
	if self:GetTall() ~= size then self:SetTall(size) end
end

function PANEL:PadCenter(p)
	local fx = p.spot[1] / 310
	if self.hand.side == "R" then fx = 1 - fx end     -- the picture is a left hand: mirrored for the right one
	return self.ox + fx * self.size, p.spot[2] / 270 * self.size
end

function PANEL:DotOf(p)
	local cx, cy = self:PadCenter(p)
	local x, y = F.Get(self.ent, p.b, p.map)
	return cx + math.Clamp(x / 100, -0.5, 0.5) * self.ps, cy + math.Clamp(y / 100, -0.5, 0.5) * self.ps
end

function PANEL:Nearest(mx, my)
	local best, bp = (self.ps * 0.9) ^ 2, nil
	for _, p in ipairs(self.pads) do
		local dx, dy = self:DotOf(p)
		local d = (dx - mx) ^ 2 + (dy - my) ^ 2
		if d < best then best, bp = d, p end
	end
	return bp
end

function PANEL:Think()
	if not IsValid(self.ent) then return end
	if self.drag then
		-- Shift pressed or let go without the mouse moving: the finer step changes the value
		if input.IsShiftDown() ~= self.drag.shift then self:OnCursorMoved(self:CursorPos()) end
		return
	end
	if self:IsHovered() then
		local mx, my = self:CursorPos()
		self.hover = self:Nearest(mx, my)
	else
		self.hover = nil
	end
end

function PANEL:OnMousePressed(code)
	if not IsValid(self.ent) then return end
	local mx, my = self:CursorPos()
	local p = self:Nearest(mx, my)
	if not p then return end
	if code == MOUSE_RIGHT or code == MOUSE_MIDDLE then
		local x = 0
		if p.restrict and F.Restricted() then x = nil end    -- a curl-only joint keeps its side turn
		F.Set(self.ent, { { p.b, p.map, x, 0 } }, true)
		return
	end
	if code ~= MOUSE_LEFT then return end
	self.drag = { pad = p }
	self:MouseCapture(true)
	self:OnCursorMoved(mx, my)
end

function PANEL:OnCursorMoved(mx, my)
	local dr = self.drag
	if not dr or not IsValid(self.ent) then return end
	local p = dr.pad
	local cx, cy = self:PadCenter(p)
	local ps = self.ps
	-- as GMod: the dot goes where the mouse is; Shift halves it (finer)
	local lx, ly = (mx - cx) / ps, (my - cy) / ps
	dr.shift = input.IsShiftDown()
	if dr.shift then lx, ly = lx / 2, ly / 2 end
	local x = math.Clamp(lx, -0.5, 0.5) * 100
	local y = math.Clamp(ly, -0.5, 0.5) * 100
	if p.restrict and F.Restricted() then x = nil end
	dr.x, dr.y = x, y
	F.Set(self.ent, { { p.b, p.map, x, y } })
end

function PANEL:OnMouseReleased()
	local dr = self.drag
	self.drag = nil
	self:MouseCapture(false)
	if dr and dr.y and IsValid(self.ent) then F.Set(self.ent, { { dr.pad.b, dr.pad.map, dr.x, dr.y } }, true) end
end

function PANEL:Paint(w, h)
	local UI = SPeditor.UI
	local COL = UI and UI.PAL or {}
	if not IsValid(self.ent) or not self.size then return true end
	local size, ox = self.size, self.ox
	surface.SetDrawColor(255, 255, 255, 255)
	surface.SetMaterial(HAND_MAT)
	if self.hand.side == "R" then
		surface.DrawTexturedRectUV(ox, 0, size, size, 1, 0, 0, 1)
	else
		surface.DrawTexturedRect(ox, 0, size, size)
	end
	local sel = {}
	if C.selected == self.ent then
		for _, b in ipairs(C.SelectedBones()) do sel[b] = true end
	end
	local half = self.ps / 2
	for _, p in ipairs(self.pads) do
		local cx, cy = self:PadCenter(p)
		local x, y = self:DotOf(p)
		x, y = math.Clamp(x, cx - half + 3, cx + half - 3), math.Clamp(y, cy - half + 3, cy + half - 3)
		if sel[p.b] then
			surface.SetDrawColor(COL.ORANGE or Color(255, 160, 40))
			surface.DrawOutlinedRect(cx - half, cy - half, self.ps, self.ps, 1)
		end
		local hot = self.hover == p or (self.drag and self.drag.pad == p)
		surface.SetDrawColor(hot and 255 or 0, hot and 255 or 0, hot and 255 or 0, 250)
		surface.DrawLine(x, y, cx, cy)
		surface.DrawRect(cx - 1, cy - 1, 2, 2)
		surface.DrawRect(x - 3, y - 3, 6, 6)
		if p.restrict and F.Restricted() then surface.SetDrawColor(30, 180, 255, 255) else surface.SetDrawColor(255, 255, 0, 255) end
		surface.DrawRect(x - 2, y - 2, 4, 4)
	end
	return true
end

vgui.Register("SPeditorFingerPoser", PANEL, "Panel")
