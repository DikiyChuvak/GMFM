--[[
GM:FM gamemode (b0.2.1, gamemodes/gmfm): the game is the editor. SPeditor.FilmMode() is true
there; the editor then opens by itself after joining and cannot be left — only the player, a
walk around the scene and a gameplay take take it away for their time (cl_gamemode.lua). The
gamemode is its own (derived from base, not Sandbox): no spawn menu, context menu or tool gun.
In Sandbox the editor is what it always was: a tool that opens and closes.
]]
SPeditor = SPeditor or {}

function SPeditor.FilmMode()
	return engine.ActiveGamemode() == "gmfm"
end

SPeditor.Net = SPeditor.Net or {}
SPeditor.Net.ChangeMap = "GMFM_ChangeMap"
