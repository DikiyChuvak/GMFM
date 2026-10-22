--[[
GM:FM — the gamemode of Garry's Mod Filmmaker (b0.2.1). A gamemode of its own, not Sandbox: no
spawn menu, no context menu, no tool gun, no Sandbox limits — the game IS the editor. After
joining any map the GM:FM interface opens and stays open; the player, walking around the scene
and gameplay takes leave it for their time only. Everything of the scene is made in the editor,
the weapons of a take are chosen before it. The editor itself is the GM:FM addon
(lua/speditor); SPeditor.FilmMode() tells it that it is the whole game.
]]
DeriveGamemode("base")

GM.Name    = "GM:FM"
GM.Author  = "DikiyChuvak"
GM.Website = "https://github.com/DikiyChuvak/GMFM"
GM.TeamBased = false

include("player_class/player_gmfm.lua")

-- noclip for the host and admins (walking a take into place, looking around the map)
function GM:PlayerNoClip(ply, on)
	if not on then return true end
	return IsValid(ply) and ply:Alive() and (game.SinglePlayer() or ply:IsAdmin())
end
