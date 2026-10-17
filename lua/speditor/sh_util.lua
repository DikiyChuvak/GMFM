-- Shared SPeditor utilities
SPeditor = SPeditor or {}

local MAX_COORD = 32768

-- Who may use the editor. The server variable speditor_access:
-- admin (default) | superadmin | all
-- Your own logic (groups, donators, a SteamID list) can be plugged in with a hook:
--   hook.Add("SPeditor_CanUse", "my", function(ply) return true / false end)
local cvAccess = CreateConVar("speditor_access", "admin", { FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY },
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
