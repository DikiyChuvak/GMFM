-- Server network layer: message registration, protection, helpers
SPeditor.Server = SPeditor.Server or {}
local S = SPeditor.Server

S.Active = S.Active or {}   -- [ply] = true while the player is in editor mode

for _, name in pairs(SPeditor.Net) do
	util.AddNetworkString(name)
end

-- A simple per-player message rate limit
local MAX_RATE = 400
local buckets = {}

local function allow(ply)
	local now = CurTime()
	local b = buckets[ply]
	if not b or now - b.t > 1 then
		b = { t = now, n = 0 }
		buckets[ply] = b
	end
	b.n = b.n + 1
	return b.n <= MAX_RATE
end

-- Registering a receiver: checks access, editor mode and rate.
-- noActive = true: the message is allowed outside editor mode (for example Toggle).
function S.Receive(key, fn, noActive)
	local name = SPeditor.Net[key]
	assert(name, "SPeditor: unknown message key " .. tostring(key))
	S.ReceiveName(name, fn, noActive)
end

-- The same by the full message name (for mods: MOD:NetReceive, sh_mods.lua)
function S.ReceiveName(name, fn, noActive)
	net.Receive(name, function(_, ply)
		if not SPeditor.CanUse(ply) then return end
		if not noActive and not S.Active[ply] then return end
		if not allow(ply) then return end
		fn(ply)
	end)
end

-- A notification to the client: kind 0 = info, 1 = error, 2 = success, 3 = saving (no sound)
function S.Notice(ply, text, kind)
	net.Start(SPeditor.Net.Notice)
	net.WriteString(text)
	net.WriteUInt(kind or 0, 2)
	net.Send(ply)
end

-- Reading an entity: only the player's own and created by the editor
function S.ReadOwned(ply)
	local ent = net.ReadEntity()
	if not IsValid(ent) then return nil end
	if not SPeditor.IsEditable(ent) then return nil end
	if ent.SPeditor_Owner ~= ply then return nil end
	return ent
end

hook.Add("PlayerDisconnected", "SPeditor.NetCleanup", function(ply)
	buckets[ply] = nil
end)
