--[[
SAeditor — the groups of the bone rows of an opened-out model on the timeline (b0.2.6-misc.1).

A model opened out used to list every moving bone side by side: a posed hand alone made thirty rows.
Its bones now sit in groups by body part, as SFM's animation set groups them:

  Body · Left arm · Left hand (Thumb, Index, Middle, Ring, Pinky) · Right arm · Right hand ·
  Left leg · Right leg · Other

A group row holds the keys of all its bones, and a key dragged there takes only those bones along
(a group's row is a bone row with a longer list of parts). The groups come from the bone tree
alone, so a model's layout never changes as more bones get keys (cl_saeditor_ui.lua modelRows).

  * hands and fingers: SPeditor.Fingers.Hands (GMod's Finger Poser names, else the bone tree), or a
    bone named hand / wrist / paw with a side;
  * arms and legs: from the hand / foot up through the bones of the same side (clavicle, upper arm,
    forearm; thigh, calf), with whatever hangs under them (twist and helper bones, toes);
  * body: the bones from the root up to the head (or up to where the arms hang);
  * other: what hangs off the body without being a limb (hair, skirts, jiggle bones, holsters).

A model with neither hands nor feet (an animal, a prop) gets a group per branch of its skeleton where
it first splits; the bones before that split and lone bones stay rows of their own.
]]
local COMP = SPeditor.Component("saeditor")
local SA   = COMP.SA
local L    = SPeditor.L

local HAND, FOOT, SKIP = SPeditor.LimbNames.HAND, SPeditor.LimbNames.FOOT, SPeditor.LimbNames.SKIP

local function has(n, list)
	for _, p in ipairs(list) do
		if string.find(n, p, 1, true) then return true end
	end
	return false
end
-- "L" / "R" from a bone's name (as cl_fingers.lua): ValveBiped.Bip01_L_Hand, bip_hand_L, Bip01 L Hand
local function sideOf(name)
	local n = "_" .. name .. "_"
	if string.find(n, "[_%.%s]l[_%.%s]") or string.find(n, "left", 1, true) then return "L" end
	if string.find(n, "[_%.%s]r[_%.%s]") or string.find(n, "right", 1, true) then return "R" end
end
local function lname(ent, b) return string.lower(ent:GetBoneName(b) or "") end

local SIDES = { "L", "R" }

-- { top = { node… } (in order), nodes = { [id] = node }, of = { [bone] = id } (nil: a row of its
-- own under the model) }; node = { id, name, kids = { node… }, parent = node }
local function build(ent)
	local n = ent:GetBoneCount()
	local par, kids, roots = {}, {}, {}
	for b = 0, n - 1 do
		local p = ent:GetBoneParent(b)
		if p and p >= 0 and p < n and p ~= b then
			par[b] = p
			kids[p] = kids[p] or {}
			table.insert(kids[p], b)
		else
			roots[#roots + 1] = b
		end
	end
	local G = { top = {}, nodes = {}, of = {} }
	local function node(id, name, parent)
		local nd = { id = id, name = name, kids = {}, parent = parent }
		G.nodes[id] = nd
		table.insert(parent and parent.kids or G.top, nd)
		return nd
	end
	-- the group of a bone, and of what hangs under it unless that is marked itself
	local mark, onBody = {}, {}

	local F = SPeditor.Fingers
	local hands = (F and F.Hands) and F.Hands(ent) or {}
	local handBone, footBone = {}, {}
	for s, h in pairs(hands) do handBone[s] = h.bone end
	for b = 0, n - 1 do
		local nm = lname(ent, b)
		local s = sideOf(nm)
		if s and not has(nm, SKIP) then
			if not handBone[s] and has(nm, HAND) and not has(nm, FOOT) then handBone[s] = b end
			if not footBone[s] and has(nm, FOOT) then footBone[s] = b end
		end
	end

	if next(handBone) or next(footBone) then
		-- a limb: from its end up through the bones of the same side; returns the bones above the
		-- end (top first) and the bone the limb hangs from
		local function limb(e, s)
			local up, b = {}, par[e]
			while b and #up < 6 and sideOf(lname(ent, b)) == s do
				table.insert(up, 1, b)
				b = par[b]
			end
			return up, b
		end
		local arms, legs, limbTops = {}, {}, {}
		for _, s in ipairs(SIDES) do
			if handBone[s] then
				local up, above = limb(handBone[s], s)
				arms[s] = up
				limbTops[#limbTops + 1] = above
			end
			if footBone[s] then
				local up, above = limb(footBone[s], s)
				legs[s] = up
				limbTops[#limbTops + 1] = above
			end
		end
		for _, s in ipairs(SIDES) do
			for _, b in ipairs(arms[s] or {}) do mark[b] = "arm" .. s end
			for _, b in ipairs(legs[s] or {}) do mark[b] = "leg" .. s end
			if footBone[s] then mark[footBone[s]] = "leg" .. s end
			if handBone[s] then mark[handBone[s]] = "hand" .. s end
			for i, f in pairs((hands[s] or {}).fingers or {}) do
				for _, b in ipairs(f.bones) do mark[b] = "hand" .. s .. ".f" .. i end
			end
		end
		-- the body: from the head (a bone named head with no side, not on a limb) down to the root;
		-- without a head, from where the arms (else the legs) hang
		local function marked(b)
			while b do
				if mark[b] then return true end
				b = par[b]
			end
			return false
		end
		local head
		for b = 0, n - 1 do
			local nm = lname(ent, b)
			if string.find(nm, "head", 1, true) and not sideOf(nm) and not marked(b) then head = b break end
		end
		local b = head or limbTops[1]
		while b do
			onBody[b] = true
			b = par[b]
		end

		node("body", L("sa_grp_body"))
		for _, s in ipairs(SIDES) do
			if arms[s] and #arms[s] > 0 then node("arm" .. s, L("sa_grp_arm_" .. s)) end
			if handBone[s] then
				local h = node("hand" .. s, L("sa_grp_hand_" .. s))
				for i = 1, 5 do
					if ((hands[s] or {}).fingers or {})[i] then node("hand" .. s .. ".f" .. i, L("sa_grp_f" .. i), h) end
				end
			end
		end
		for _, s in ipairs(SIDES) do
			if footBone[s] then node("leg" .. s, L("sa_grp_leg_" .. s)) end
		end
		node("other", L("sa_grp_other"))
		for x = 0, n - 1 do
			local y, id = x, "other"
			while y do
				if mark[y] then id = mark[y] break end
				if onBody[y] then id = (y == x) and "body" or "other" break end
				y = par[y]
			end
			G.of[x] = id
		end
		return G
	end

	-- no hands, no feet: a group per branch where the skeleton first splits
	local hub = roots[1]
	while hub and kids[hub] and #kids[hub] == 1 do hub = kids[hub][1] end
	local function size(b)
		local c = 1
		for _, k in ipairs(kids[b] or {}) do c = c + size(k) end
		return c
	end
	for _, c in ipairs(hub and kids[hub] or {}) do
		if size(c) >= 2 then
			local id = "br" .. c
			node(id, (string.gsub(ent:GetBoneName(c) or ("#" .. c), "^ValveBiped%.Bip01_", "")))
			mark[c] = id
		end
	end
	for x = 0, n - 1 do
		local y = x
		while y do
			if mark[y] then G.of[x] = mark[y] break end
			y = par[y]
		end
	end
	return G
end

-- Built again whenever asked (a hundred bones, a few times a second at most): the hands found by the
-- bone tree need the bones in place, and the language may change
function SA.BoneGroups(ent)
	if not (IsValid(ent) and ent.GetBoneCount) or ent:GetBoneCount() < 1 then return { top = {}, nodes = {}, of = {} } end
	return build(ent)
end
