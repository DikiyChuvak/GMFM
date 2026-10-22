-- The player of GM:FM: the player model, skin, bodygroups and colours the player chose in the
-- game's settings (the same convars as Sandbox, so a recorded take looks like them), no weapons
-- of their own (they are chosen before a take).
AddCSLuaFile()
DEFINE_BASECLASS("player_default")

if CLIENT then
	CreateConVar("cl_playercolor", "0.24 0.34 0.41", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The value is a Vector - so between 0-1 - not between 0-255")
	CreateConVar("cl_weaponcolor", "0.30 1.80 2.10", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The value is a Vector - so between 0-1 - not between 0-255")
	CreateConVar("cl_playerskin", "0", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The skin to use, if the model has any")
	CreateConVar("cl_playerbodygroups", "0", { FCVAR_ARCHIVE, FCVAR_USERINFO, FCVAR_DONTRECORD }, "The bodygroups to use, if the model has any")
end

local PLAYER = {}
PLAYER.DisplayName   = "GM:FM Actor"
PLAYER.SlowWalkSpeed = 100
PLAYER.WalkSpeed     = 200
PLAYER.RunSpeed      = 400

function PLAYER:Loadout()
	self.Player:RemoveAllAmmo()
end

function PLAYER:SetModel()
	BaseClass.SetModel(self)
	self.Player:SetSkin(self.Player:GetInfoNum("cl_playerskin", 0))
	local groups = string.Explode(" ", self.Player:GetInfo("cl_playerbodygroups") or "")
	for k = 0, self.Player:GetNumBodyGroups() - 1 do
		self.Player:SetBodygroup(k, tonumber(groups[k + 1]) or 0)
	end
end

function PLAYER:Spawn()
	BaseClass.Spawn(self)
	self.Player:SetPlayerColor(Vector(self.Player:GetInfo("cl_playercolor")))
	local wc = Vector(self.Player:GetInfo("cl_weaponcolor"))
	if wc:Length() < 0.001 then wc = Vector(0.001, 0.001, 0.001) end
	self.Player:SetWeaponColor(wc)
end

player_manager.RegisterClass("player_gmfm", PLAYER, "player_default")
