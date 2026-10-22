--[[
SPeditor — two-link IK for ragdoll limbs (arm: shoulder-elbow-hand,
leg: thigh-knee-foot). Pure maths, no access to entities.

Solve(root, mid0, end0, target) -> mid, end
  root   — the fixed joint (shoulder / thigh)
  mid0   — position of the "elbow" at the start of the drag (defines the bend plane)
  end0   — position of the hand / foot at the start of the drag
  target — where the hand / foot is being pulled
Link lengths are kept; if the target is out of reach, the limb stretches
straight towards the target.

RotateAngle(ang, from, to) — rotates a bone orientation along the shortest
arc between the directions from -> to (the twist of the bone is kept).
]]
SPeditor = SPeditor or {}
SPeditor.IK = SPeditor.IK or {}
local IK = SPeditor.IK

local function rotateVec(v, k, deg)
	local th = math.rad(deg)
	local c, s = math.cos(th), math.sin(th)
	return v * c + k:Cross(v) * s + k * (k:Dot(v) * (1 - c))
end

function IK.Solve(root, mid0, end0, target)
	local l1 = root:Distance(mid0)
	local l2 = mid0:Distance(end0)
	local toT = target - root
	local dist = toT:Length()
	if dist < 1e-3 or l1 < 1e-3 or l2 < 1e-3 then return mid0, end0 end

	local dir = toT / dist
	local maxReach = (l1 + l2) * 0.9995
	local minReach = math.abs(l1 - l2) * 1.0005 + 0.01
	local d = math.min(math.max(dist, minReach), maxReach)
	local endPos = root + dir * d

	-- angle at the shoulder by the law of cosines
	local cosA = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
	cosA = math.min(math.max(cosA, -1), 1)
	local sinA = math.sqrt(1 - cosA * cosA)

	-- bend direction: the part of the original "elbow" perpendicular to the shoulder-target line
	local rel = mid0 - root
	local pole = rel - dir * rel:Dot(dir)
	if pole:LengthSqr() < 1e-4 then
		-- the limb was straight: bend in an arbitrary but stable plane
		local ref = (math.abs(dir.z) < 0.9) and Vector(0, 0, 1) or Vector(1, 0, 0)
		pole = ref - dir * ref:Dot(dir)
	end
	pole = pole:GetNormalized()

	local mid = root + dir * (l1 * cosA) + pole * (l1 * sinA)
	return mid, endPos
end

-- The bend of a two-link chain turned toward a point (the pole: where the knee / elbow points,
-- a0.9 rig): root and the end stay, the middle goes round the root-end line toward poleTarget.
-- Returns the new middle.
function IK.SolvePole(root, mid0, end0, poleTarget)
	local l1 = root:Distance(mid0)
	local toE = end0 - root
	local d = toE:Length()
	if d < 1e-3 or l1 < 1e-3 then return mid0 end
	local dir = toE / d
	-- how far along the root-end line the middle is and how far from it: kept
	local along = (mid0 - root):Dot(dir)
	local off = ((mid0 - root) - dir * along):Length()
	local rel = poleTarget - root
	local pole = rel - dir * rel:Dot(dir)
	if pole:LengthSqr() < 1e-4 then return mid0 end
	return root + dir * along + pole:GetNormalized() * off
end

function IK.RotateAngle(ang, from, to)
	local a, b = from:GetNormalized(), to:GetNormalized()
	local axis = a:Cross(b)
	local s = axis:Length()
	if s < 1e-6 then return ang end
	axis = axis / s
	local deg = math.deg(math.atan2(s, a:Dot(b)))
	local f = rotateVec(ang:Forward(), axis, deg)
	local u = rotateVec(ang:Up(), axis, deg)
	return f:AngleEx(u)
end

-- End links for which IK switches on (by bone name)
local END_PATTERNS = { "hand", "foot", "wrist", "ankle", "toe", "paw", "hoof" }
function IK.IsEndEffector(boneName)
	local n = string.lower(boneName or "")
	for _, p in ipairs(END_PATTERNS) do
		if string.find(n, p, 1, true) then return true end
	end
	return false
end
