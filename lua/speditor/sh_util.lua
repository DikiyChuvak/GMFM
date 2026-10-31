-- Shared SPeditor utilities
SPeditor = SPeditor or {}

local MAX_COORD = 32768

-- Who may use the editor. The server variable gmfm_access:
-- admin (default) | superadmin | all
-- Your own logic (groups, donators, a SteamID list) can be plugged in with a hook:
--   hook.Add("SPeditor_CanUse", "my", function(ply) return true / false end)
local cvAccess = CreateConVar("gmfm_access", "admin", { FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY },
	"Who may use SPeditor: admin | superadmin | all")

function SPeditor.CanUse(ply)
	if not IsValid(ply) then return false end
	local res = hook.Run("SPeditor_CanUse", ply)
	if res ~= nil then return res and true or false end
	local mode = string.lower(cvAccess:GetString())
	if mode == "all" then return true end
	if mode == "superadmin" then return ply:IsSuperAdmin() end
	return ply:IsAdmin()
end

-- The entity was created by the editor (the flag is synced over the network)
function SPeditor.IsEditable(ent)
	return IsValid(ent) and ent:GetNW2Bool("SPeditor_Ent", false)
end

-- A number without NaN and inf, otherwise the default value
function SPeditor.Num(n, def)
	n = tonumber(n)
	if not n or n ~= n or n == math.huge or n == -math.huge then return def end
	return n
end

function SPeditor.Clamp(n, lo, hi, def)
	return math.Clamp(SPeditor.Num(n, def), lo, hi)
end

local function badCoord(n)
	return n ~= n or math.abs(n) > MAX_COORD
end

function SPeditor.ValidVec(v)
	if not isvector(v) then return false end
	return not (badCoord(v.x) or badCoord(v.y) or badCoord(v.z))
end

function SPeditor.ValidAng(a)
	if not isangle(a) then return false end
	return a.p == a.p and a.y == a.y and a.r == a.r
end

-- Vectors and angles are stored in JSON as number arrays
function SPeditor.VecToTable(v)
	return { math.Round(v.x, 3), math.Round(v.y, 3), math.Round(v.z, 3) }
end

function SPeditor.AngToTable(a)
	return { math.Round(a.p, 3), math.Round(a.y, 3), math.Round(a.r, 3) }
end

function SPeditor.TableToVec(t)
	if type(t) ~= "table" then return nil end
	local x, y, z = tonumber(t[1]), tonumber(t[2]), tonumber(t[3])
	if not (x and y and z) then return nil end
	return Vector(x, y, z)
end

function SPeditor.TableToAng(t)
	if type(t) ~= "table" then return nil end
	local p, y, r = tonumber(t[1]), tonumber(t[2]), tonumber(t[3])
	if not (p and y and r) then return nil end
	return Angle(p, y, r)
end

-- Physics bodies of a ragdoll by bone. On some models (Enhanced TF2 MvM bots)
-- TranslateBoneToPhysBone gives 0 for every bone on both realms, so the map is built from
-- TranslatePhysBoneToBone, which is right everywhere. Past the last body it gives 0 for a few
-- slots and then -1 (the client has no physics objects to count).
local physMaps = {}
local function physMap(ent)
	local mdl = ent:GetModel() or ""
	local m = physMaps[mdl]
	if m then return m end
	m = {}
	local count = SERVER and ent:GetPhysicsObjectCount() or 128
	for p = 0, math.min(count, 128) - 1 do
		local b = ent:TranslatePhysBoneToBone(p)
		if not b or b < 0 or m[b] or (p > 0 and b == 0) then break end
		m[b] = p
	end
	if next(m) then physMaps[mdl] = m end
	return m
end

-- Where an object is drawn (b0.2.4). The client smooths the moves of a light, a camera or
-- an effect over ~0.1 s, while its parent may not be smoothed at all (a ragdoll; a prop, at
-- times): an attached light trailed 20 units behind a parent moving at 200 u/s (measured in
-- game). Attached, it is put where the parent is drawn, at its offset from the parent as the
-- server last sent both.
function SPeditor.LivePos(ent)
	if CLIENT then
		local par = ent:GetNW2Entity("SPeditor_Parent")
		if IsValid(par) then
			local np, na = ent:GetNetworkOrigin(), ent:GetNetworkAngles()
			-- b0.2.5: at its offset from the bone of the hand as the hand is drawn now; (b0.2.6) the same
			-- for a bone of any model with a skeleton, and for a finger / hair of a ragdoll
			local bone = ent:GetNW2Int("SPeditor_ParentBone", -1)
			if bone >= 0 and ent:GetNW2Bool("SPeditor_AttRel", false) then
				if par.SPeditor_BonesAt ~= FrameNumber() then
					par.SPeditor_BonesAt = FrameNumber()
					par:SetupBones()
				end
				local m = par:GetBoneMatrix(bone)
				if m then return LocalToWorld(ent:GetNW2Vector("SPeditor_AttP"), ent:GetNW2Angle("SPeditor_AttA"), m:GetTranslation(), m:GetAngles()) end
			end
			-- a ragdoll is drawn at the places its bodies were sent with
			if par:GetClass() == "prop_ragdoll" then return np, na end
			local lp, la = WorldToLocal(np, na, par:GetNetworkOrigin(), par:GetNetworkAngles())
			return LocalToWorld(lp, la, par:GetPos(), par:GetAngles())
		end
	end
	return ent:GetPos(), ent:GetAngles()
end

-- The other way round (b0.2.6): a place in the drawn world of an object held at a hand -> the
-- place to send to the server, so that its offset from the server's bone is the offset from the
-- bone as drawn here. On some characters the two bones are a little apart (bones between the
-- physics bodies drawn otherwise than the server works them out): the object was moved from where
-- it is drawn but kept the server's offset, and jumped aside at every touch of the gizmo.
function SPeditor.LiveToNet(ent, pos, ang)
	if not CLIENT or not IsValid(ent) then return pos, ang end
	local par = ent:GetNW2Entity("SPeditor_Parent")
	local bone = ent:GetNW2Int("SPeditor_ParentBone", -1)
	if not IsValid(par) or bone < 0 or not ent:GetNW2Bool("SPeditor_AttRel", false) then return pos, ang end
	if par.SPeditor_BonesAt ~= FrameNumber() then
		par.SPeditor_BonesAt = FrameNumber()
		par:SetupBones()
	end
	local m = par:GetBoneMatrix(bone)
	if not m then return pos, ang end
	-- the server's frame of the bone: where the object is there, less its offset
	local ip, ia = WorldToLocal(vector_origin, angle_zero, ent:GetNW2Vector("SPeditor_AttP"), ent:GetNW2Angle("SPeditor_AttA"))
	local fp, fa = LocalToWorld(ip, ia, ent:GetNetworkOrigin(), ent:GetNetworkAngles())
	local lp, la = WorldToLocal(pos, ang, m:GetTranslation(), m:GetAngles())
	return LocalToWorld(lp, la, fp, fa)
end

-- Face sliders (b0.2.5). The game takes a flex weight as a share of the controller's range
-- (0 … 1, verified in game): for a slider that goes from -1 to 1 — the faces of the TF2
-- mercenaries for animation (HWM) — the weight 0 is the slider at -1 and the weight 0.5 is the
-- slider at zero. The editor keeps and shows the slider's own value (what Faceposer and SFM
-- show, what the phonemes of the game are written in), and these two turn it into the weight
-- and back. For the usual 0 … 1 sliders of Valve faces both are the same.
function SPeditor.FlexGet(ent, i)
	local mn, mx = ent:GetFlexBounds(i)
	local w = ent:GetFlexWeight(i)
	if not mn or not mx or mx <= mn then return w end
	return mn + w * (mx - mn)
end

function SPeditor.FlexSet(ent, i, v)
	local mn, mx = ent:GetFlexBounds(i)
	if mn and mx and mx > mn then v = (v - mn) / (mx - mn) end
	ent:SetFlexWeight(i, v)
end

-- a face at rest: every slider at zero (sliders from -1 to 1 at their middle)
function SPeditor.FlexRest(ent)
	for i = 0, (ent:GetFlexNum() or 0) - 1 do SPeditor.FlexSet(ent, i, 0) end
end

local function twoSided(ent, i)
	local mn, mx = ent:GetFlexBounds(i)
	return mn and mx and mn < 0 and mx > 0, mn
end

-- A face nobody has set (b0.2.6): every two-sided slider at the bottom of its range — the engine's
-- weight 0. A TF2 mercenary (HWM) spawned from the Q menu and taken into the scene comes like that:
-- lids, brows, the jaw pushed sideways — and lip sync then kept that crooked face in every key.
-- Such a face is put at rest (the one-sided sliders, already at zero, are left alone).
function SPeditor.FlexRestIfUnset(ent)
	if not IsValid(ent) then return false end
	local n, any = ent:GetFlexNum() or 0, false
	for i = 0, n - 1 do
		if twoSided(ent, i) then
			if ent:GetFlexWeight(i) ~= 0 then return false end
			any = true
		end
	end
	if not any then return false end
	for i = 0, n - 1 do
		if twoSided(ent, i) then SPeditor.FlexSet(ent, i, 0) end
	end
	return true
end

-- The same face written into a scene ({ [flex id] = slider value }, a pose or a key): many
-- two-sided sliders exactly at their bottom. Those are dropped (= at rest); true — it was such a face.
function SPeditor.FlexFixUnset(ent, flex)
	if not IsValid(ent) or not istable(flex) then return false end
	local n, total, low = ent:GetFlexNum() or 0, 0, {}
	for i = 0, n - 1 do
		local two, mn = twoSided(ent, i)
		if two then
			total = total + 1
			local v = tonumber(flex[i])
			if v and math.abs(v - mn) < 1e-4 then low[#low + 1] = i end
		end
	end
	if #low < 4 or #low < total * 0.4 then return false end
	for _, i in ipairs(low) do flex[i] = nil end
	return true
end

-- The physics body of exactly this bone, or nil (a finger, a toe)
function SPeditor.PhysOfBone(ent, bone)
	if not IsValid(ent) or ent:GetClass() ~= "prop_ragdoll" or not bone then return nil end
	return physMap(ent)[bone]
end

-- The body of the bone or of the nearest bone above it that has one (a finger → the hand)
function SPeditor.PhysOfBoneUp(ent, bone)
	if not IsValid(ent) or ent:GetClass() ~= "prop_ragdoll" or not bone then return nil end
	local m, guard = physMap(ent), 0
	while bone and bone >= 0 and guard < 256 do
		if m[bone] then return m[bone] end
		bone = ent:GetBoneParent(bone)
		guard = guard + 1
	end
	return nil
end

-- Transliteration of Cyrillic (file names are Latin only)
local RU_LOWER = {
	"a", "b", "v", "g", "d", "e", "zh", "z", "i", "y", "k", "l", "m", "n", "o", "p",
	"r", "s", "t", "u", "f", "h", "ts", "ch", "sh", "sch", "", "y", "", "e", "yu", "ya",
}

local function translit(name)
	local out = {}
	local ok = pcall(function()
		for _, cp in utf8.codes(name) do
			if cp == 0x401 then cp = 0x451
			elseif cp >= 0x410 and cp <= 0x42F then cp = cp + 32 end
			if cp >= 0x430 and cp <= 0x44F then
				out[#out + 1] = RU_LOWER[cp - 0x42F]
			elseif cp == 0x451 then
				out[#out + 1] = "e"
			elseif cp < 128 then
				out[#out + 1] = string.char(cp)
			end
		end
	end)
	if not ok then return name end
	return table.concat(out)
end

-- Scene / pose file name: Latin letters, digits, space, _ and - (Cyrillic is transliterated)
function SPeditor.SafeName(name)
	name = tostring(name or "")
	local clean = string.gsub(translit(name), "[^%w_%- ]", "")
	clean = string.Trim(clean)
	if clean == "" and string.Trim(name) ~= "" then
		clean = "scene_" .. os.date("%Y%m%d_%H%M%S")
	end
	return string.sub(clean, 1, SPeditor.Config.MaxSceneName)
end

-- A table over the network: JSON + compression (one packet is limited to ~64 KB)
function SPeditor.WriteTable(tbl)
	local comp = util.Compress(util.TableToJSON(tbl) or "{}") or ""
	if #comp > 65000 then comp = "" end
	net.WriteUInt(#comp, 16)
	net.WriteData(comp, #comp)
end

function SPeditor.ReadTable()
	local len = net.ReadUInt(16)
	if len == 0 then return nil end
	-- a cap on the unpacked size: 64 KB of compressed zeros would otherwise unpack into gigabytes
	-- and hang the server (a real table is a few hundred KB at most)
	local raw = util.Decompress(net.ReadData(len), 16 * 1024 * 1024)
	if not raw then return nil end
	return util.JSONToTable(raw)
end
-- Exact transfer of vectors and angles (net.WriteVector compresses values)
function SPeditor.WriteVecF(v)
	net.WriteFloat(v.x)
	net.WriteFloat(v.y)
	net.WriteFloat(v.z)
end

function SPeditor.ReadVecF()
	local x = net.ReadFloat()
	local y = net.ReadFloat()
	local z = net.ReadFloat()
	return Vector(x, y, z)
end

function SPeditor.WriteAngF(a)
	net.WriteFloat(a.p)
	net.WriteFloat(a.y)
	net.WriteFloat(a.r)
end

function SPeditor.ReadAngF()
	local p = net.ReadFloat()
	local y = net.ReadFloat()
	local r = net.ReadFloat()
	return Angle(p, y, r)
end
