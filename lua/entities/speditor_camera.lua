-- Scene camera: FOV.
-- Overlays (frustum, focal plane) are drawn only in the main pass:
-- in the nested viewport render (renderViewEnt) they are off, so that they do
-- not break the render state or flood the frame.
AddCSLuaFile()
ENT.Type        = "anim"
ENT.Base        = "base_anim"
ENT.PrintName   = "GM:FM Camera"
ENT.Category    = "GM:FM"
ENT.Spawnable   = false
ENT.AdminOnly   = true
ENT.RenderGroup = RENDERGROUP_BOTH

local CAMERA_MODEL = "models/dav0r/camera.mdl"

function ENT:SetupDataTables()
	self:NetworkVar("Float", 0, "CameraFOV")
	self:NetworkVar("Float", 1, "ShakeAmp")      -- camera shake: position, units (SPeditor.CameraFields)
	self:NetworkVar("Float", 2, "ShakeRot")      -- rotation, degrees
	self:NetworkVar("Float", 3, "ShakeFreq")     -- shakes per second
	self:NetworkVar("Float", 4, "CamSmooth")     -- smoothing of the animated path, seconds
	self:NetworkVar("Float", 5, "ZNear")         -- the near clipping plane, units (0: the editor's own)
	self:NetworkVar("Float", 6, "CamAO")         -- ambient occlusion: 0 as the scene, 1 on, 2 off (b0.2.6)
	self:NetworkVar("Float", 7, "AORadius")      -- its radius, units (0: the scene's)
	self:NetworkVar("Float", 8, "AOStrength")    -- its strength (0: the scene's)
	self:NetworkVar("Bool", 0, "Enabled")
	self:NetworkVar("Entity", 0, "ViewOwner")
end

if SERVER then
	function ENT:Initialize()
		self:SetModel(CAMERA_MODEL)
		self:PhysicsInit(SOLID_VPHYSICS)
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_VPHYSICS)
		self:DrawShadow(false)
		self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
		self:SetCameraFOV(75)
		self:SetShakeFreq(3)
		self:SetZNear(3)
		self:SetEnabled(false)
		local phys = self:GetPhysicsObject()
		if IsValid(phys) then phys:EnableMotion(false) end
	end
	function ENT:UpdateTransmitState()
		return TRANSMIT_ALWAYS
	end
end

if CLIENT then
	function ENT:Initialize()
		self:DrawShadow(false)
	end

	local NEAR_HIDE = 28
	local function modelHidden(self)
		local C = SPeditor and SPeditor.Client
		if not C or not C.active or C.hideUI then return true end
		if self:GetNW2Bool("SPeditor_NoModel", false) then return true end
		if C.camera and C.camera.viewEnt == self then return true end
		if C.renderViewEnt == self then return true end
		if C.GetView then
			local vp = C.GetView()
			if vp and vp:DistToSqr(self:GetPos()) < NEAR_HIDE * NEAR_HIDE then return true end
		end
		return false
	end

	function ENT:Draw()
		if modelHidden(self) then return end
		self:DrawModel()
	end

	-- The camera being looked through (or the editor is closed): NoDraw on the client
	-- removes both the model and its shadow from ALL render passes. Otherwise the model
	-- at the lens darkens the frame. (No NoDraw on the server: the entity would stop being transmitted.)
	function ENT:Think()
		local C = SPeditor and SPeditor.Client
		local hide = (not C) or (not C.active) or (C.camera and C.camera.viewEnt == self) or false
		if hide ~= self.SPNoDraw then
			self.SPNoDraw = hide
			self:SetNoDraw(hide)
		end
	end

	-- the half width and height of the frame `dist` in front: the field of view is the horizontal
	-- one of the render's frame (b0.2.6: the 4:3 rule of the game's own view and a fixed 16:9
	-- drew a frustum of other proportions than the render; a wide free frame is Hor+)
	local function planeHalfSize(fov, dist)
		local C = SPeditor.Client
		local W, H = C.GetRenderSize()
		local aspect = W / math.max(H, 1)
		local hw = dist * math.tan(math.rad(math.Clamp(C.FrameFOV and C.FrameFOV(fov, aspect) or fov, 1, 170)) / 2)
		return hw, hw / aspect
	end

	function ENT:DrawTranslucent()
		local C = SPeditor and SPeditor.Client
		if not C or not C.active or C.hideUI then return end
		if C.camera and C.camera.viewEnt == self then return end
		-- No overlays in the nested viewport render
		if C.renderViewEnt or C.vpPass == "secondary" or C.vpPass == "export" then return end

		local selected = (C.selected == self)
		local pos, ang = SPeditor.LivePos(self)
		local fwd, right, up = ang:Forward(), ang:Right(), ang:Up()
		local fov   = self:GetCameraFOV()
		local dist = selected and 150 or 100
		local hw, hh = planeHalfSize(fov, dist)
		local center = pos + fwd * dist
		local c1 = center + right * hw + up * hh
		local c2 = center - right * hw + up * hh
		local c3 = center - right * hw - up * hh
		local c4 = center + right * hw - up * hh
		local col = selected and Color(255, 210, 90, 230) or Color(200, 200, 200, 120)
		local restore = SPeditor.Render.HelperLighting()
		render.SetColorMaterialIgnoreZ()
		local w = 0.35
		render.DrawBeam(pos, c1, w, 0, 1, col)
		render.DrawBeam(pos, c2, w, 0, 1, col)
		render.DrawBeam(pos, c3, w, 0, 1, col)
		render.DrawBeam(pos, c4, w, 0, 1, col)
		render.DrawBeam(c1, c2, w, 0, 1, col)
		render.DrawBeam(c2, c3, w, 0, 1, col)
		render.DrawBeam(c3, c4, w, 0, 1, col)
		render.DrawBeam(c4, c1, w, 0, 1, col)
		restore()
	end
end
