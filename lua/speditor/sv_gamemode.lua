--[[
GM:FM gamemode, the server's part (sh_gamemode.lua): another map from the editor (File →
Change map), and a player who is back in the editor is alive.
]]
local S = SPeditor.Server

util.AddNetworkString(SPeditor.Net.ChangeMap)

-- the map is changed by the host of the game (single player, a listen server's host) or an admin
net.Receive(SPeditor.Net.ChangeMap, function(_, ply)
	if not SPeditor.FilmMode() then return end
	local map = string.lower(net.ReadString() or "")
	if not IsValid(ply) or not (game.SinglePlayer() or ply:IsListenServerHost() or ply:IsAdmin()) then
		S.Notice(ply, "#mode_map_denied", 1)
		return
	end
	if not string.match(map, "^[%w_%-%.]+$") or not file.Exists("maps/" .. map .. ".bsp", "GAME") then
		S.Notice(ply, "#mode_map_missing", 1)
		return
	end
	PrintMessage(HUD_PRINTTALK, "GM:FM: " .. ply:Nick() .. " → " .. map)
	timer.Simple(0.2, function() RunConsoleCommand("changelevel", map) end)
end)

-- in the editor the player is never dead: a take that ended with a death opens the editor on
-- a living player (its body was left where it fell — in the take)
hook.Add("SPeditor_PlayerState", "GMFM.Mode", function(ply, on)
	if on and SPeditor.FilmMode() and IsValid(ply) and not ply:Alive() then ply:Spawn() end
end)
