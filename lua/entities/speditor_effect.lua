-- Effect object for SPeditor scenes: a particle system of the engine or a util.Effect effect.
-- The server only keeps what the effect is and its moment; the effect itself lives on the
-- client (SPeditor.Effects, cl_effects.lua).
AddCSLuaFile()

ENT.Type        = "anim"
ENT.Base        = "base_anim"
ENT.PrintName   = "SPeditor Effect"
ENT.Category    = "SPeditor"
ENT.Spawnable   = false
ENT.AdminOnly   = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
	self:NetworkVar("String", 0, "FxSource")     -- "pcf" | "tool" | "lua" (SPeditor.EffectSources)
	self:NetworkVar("String", 1, "FxName")       -- particle system or effect name
	self:NetworkVar("String", 2, "FxFile")       -- the .pcf file of a particle system from an addon
	self:NetworkVar("Float", 0, "FxTime")        -- the moment of the effect, seconds from its start (0 — not started)
	self:NetworkVar("Float", 1, "FxScale")
	self:NetworkVar("Float", 2, "FxLength")      -- distance to the second control point (0 — none)
end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/hunter/plates/plate025x025.mdl")
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_NONE)
		self:DrawShadow(false)
		self:SetFxSource("pcf")
		self:SetFxName("")
		self:SetFxFile("")
		self:SetFxTime(0.25)
		self:SetFxScale(1)
		self:SetFxLength(0)
	end

	function ENT:UpdateTransmitState()
		return TRANSMIT_ALWAYS
	end
end

if CLIENT then
	function ENT:Initialize()
		self:DrawShadow(false)
	end

	function ENT:Think()
		local Fx = SPeditor and SPeditor.Effects
		if Fx then Fx.Update(self) end
	end

	function ENT:OnRemove()
		local Fx = SPeditor and SPeditor.Effects
		if Fx then Fx.Drop(self) end
	end

	function ENT:Draw() end

	-- The marker is drawn only in the editor and not in the render / preview
	function ENT:DrawTranslucent()
		local C = SPeditor and SPeditor.Client
		if not C or not C.active or C.hideUI or C.vpPass == "secondary" or C.vpPass == "export" then return end

		local restore = SPeditor.Render.HelperLighting()
		local pos, ang = self:GetPos(), self:GetAngles()
		local sel = C.selected == self
		local col = sel and Color(255, 210, 90, 240) or Color(120, 220, 255, 150)
		local r = sel and 6 or 4
		for _, axis in ipairs({ ang:Forward(), ang:Right(), ang:Up() }) do
			render.DrawLine(pos - axis * r, pos + axis * r, col, true)
		end
		render.DrawWireframeSphere(pos, r * 0.6, 6, 3, col, true)
		local len = self:GetFxLength()
		if len > 0 then
			-- the second point of the effect (where a tracer or a beam goes)
			local tip = pos + ang:Forward() * len
			render.DrawLine(pos, tip, col, true)
			render.DrawWireframeSphere(tip, 2, 6, 3, col, true)
		elseif sel then
			render.DrawLine(pos, pos + ang:Forward() * 18, col, true)
		end
		restore()
	end
end
