--[[
SPeditor — PAC3 outfits on scene objects (server). PAC3 itself is a separate addon
(Workshop 104691717); the editor only keeps which outfits an object wears and hands them to
every client, where cl_pac.lua puts them on through PAC3's own API (pac.SetupENT,
ent:AttachPACPart). Nothing of PAC3 is copied into SPeditor.

An outfit is kept as it came from the client: the text of a PAC3 outfit file
(data/pac3/<name>.txt), compressed. Scenes save it with the object (base64), so a scene
keeps its outfits even where the file is missing.

  ent.SPeditor_PAC = { { name = "file name", data = compressed text }, ... }
  S.PACSave(ent) -> list for the scene file | nil      S.PACRestore(ent, list)
  S.PACSync(ent, ply)  send the outfits of ent to ply (nil — to everyone)
]]
local S = SPeditor.Server

S.PAC_MAX_OUTFITS = 8
S.PAC_MAX_BYTES = 60000          -- one net message carries one outfit

local function list(ent) return ent.SPeditor_PAC or {} end

-- Clients learn the outfits by entity index: an object may not have reached a client yet
-- (out of its PVS); the client puts them on when the entity appears.
function S.PACSync(ent, ply)
	if not IsValid(ent) then return end
	local items = list(ent)
	local function send(fn)
		fn()
		if ply then net.Send(ply) else net.Broadcast() end
	end
	send(function()
		net.Start(SPeditor.Net.PACSync)
		net.WriteUInt(ent:EntIndex(), 13)
		net.WriteUInt(0, 2)                -- 0: the list starts over
		net.WriteUInt(#items, 4)
	end)
	for _, it in ipairs(items) do
		send(function()
			net.Start(SPeditor.Net.PACSync)
			net.WriteUInt(ent:EntIndex(), 13)
			net.WriteUInt(1, 2)            -- 1: one more outfit
			net.WriteString(it.name)
			net.WriteUInt(#it.data, 16)
			net.WriteData(it.data, #it.data)
		end)
	end
end

local function cleanName(name)
	name = string.sub(tostring(name or ""), 1, 96)
	name = string.gsub(name, "[%c\"\\]", "")
	return name ~= "" and name or "outfit"
end

-- op: 0 add (name, data), 1 remove (index), 2 remove all
S.Receive("PAC", function(ply)
	local ent = S.ReadOwned(ply)
	local op = net.ReadUInt(2)
	if not IsValid(ent) then return end
	local items = ent.SPeditor_PAC or {}
	if op == 0 then
		local name = cleanName(net.ReadString())
		local len = net.ReadUInt(16)
		if len == 0 or len > S.PAC_MAX_BYTES then return end
		local data = net.ReadData(len)
		-- a valid compressed text; what it says is read by PAC3 on the clients
		local text = util.Decompress(data, 1048576)
		if not text or text == "" then
			S.Notice(ply, "#pac_bad", 1)
			return
		end
		if #items >= S.PAC_MAX_OUTFITS then
			S.Notice(ply, "#pac_too_many|" .. S.PAC_MAX_OUTFITS, 1)
			return
		end
		items[#items + 1] = { name = name, data = data }
	elseif op == 1 then
		local i = net.ReadUInt(4)
		if not items[i] then return end
		table.remove(items, i)
	else
		items = {}
	end
	ent.SPeditor_PAC = (#items > 0) and items or nil
	S.PACSync(ent)
end)

function S.PACSave(ent)
	local items = ent.SPeditor_PAC
	if not items or #items == 0 then return nil end
	local out = {}
	for i, it in ipairs(items) do out[i] = { name = it.name, data = util.Base64Encode(it.data, true) } end
	return out
end

function S.PACRestore(ent, saved)
	if type(saved) ~= "table" then return end
	local items = {}
	for _, it in ipairs(saved) do
		if type(it) == "table" and isstring(it.data) and #items < S.PAC_MAX_OUTFITS then
			local data = util.Base64Decode(it.data)
			if data and #data > 0 and #data <= S.PAC_MAX_BYTES then
				items[#items + 1] = { name = cleanName(it.name), data = data }
			end
		end
	end
	ent.SPeditor_PAC = (#items > 0) and items or nil
	-- the object has just been made: the clients get it a moment later
	timer.Simple(0.2, function() if IsValid(ent) then S.PACSync(ent) end end)
end

-- a player who joins later gets the outfits of every editor object
SPeditor.Hook("PlayerInitialSpawn", "SPeditor.PAC", function(ply)
	timer.Simple(5, function()
		if not IsValid(ply) then return end
		for _, objs in pairs(S.Owned) do
			for _, e in ipairs(objs) do
				if IsValid(e) and e.SPeditor_PAC then S.PACSync(e, ply) end
			end
		end
	end)
end)
