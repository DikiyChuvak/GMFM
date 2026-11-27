AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("player_class/player_gmfm.lua")
include("shared.lua")

function GM:PlayerSpawn(ply, transition)
	player_manager.SetPlayerClass(ply, "player_gmfm")
	self.BaseClass.PlayerSpawn(self, ply, transition)
	-- the filmmaker is not a target while the editor is open (NPCs act for the scene)
	if IsValid(ply) and SPeditor and SPeditor.Server and SPeditor.Server.Active and SPeditor.Server.Active[ply] then
		ply:AddFlags(FL_NOTARGET)
	end
end

-- while the editor is open the filmmaker takes no damage (a stray shot or a fall would only
-- put the body on the floor; the scene is what is being made)
function GM:PlayerShouldTakeDamage(ply, attacker)
	if IsValid(ply) and SPeditor and SPeditor.Server and SPeditor.Server.Active and SPeditor.Server.Active[ply] then
		return false
	end
	return self.BaseClass.PlayerShouldTakeDamage(self, ply, attacker)
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
