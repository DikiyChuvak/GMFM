AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("player_class/player_gmfm.lua")
include("shared.lua")

function GM:PlayerSpawn(ply, transition)
	player_manager.SetPlayerClass(ply, "player_gmfm")
	self.BaseClass.PlayerSpawn(self, ply, transition)
end

-- the player who died in a take comes back by itself (the editor has no respawn button)
function GM:PlayerDeathThink(ply)
	if (ply.NextSpawnTime or 0) > CurTime() then return end
	if SPeditor and SPeditor.Server and SPeditor.Server.Active and SPeditor.Server.Active[ply] then
		ply:Spawn()
		return
	end
	return self.BaseClass.PlayerDeathThink(self, ply)
end
