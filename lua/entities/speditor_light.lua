-- Light entity for SPeditor scenes: point (DynamicLight) and spot (ProjectedTexture)
AddCSLuaFile()

ENT.Type        = "anim"
ENT.Base        = "base_anim"
ENT.PrintName   = "SPeditor Light"
ENT.Category    = "SPeditor"
ENT.Spawnable   = false
ENT.AdminOnly   = true
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
	self:NetworkVar("Vector", 0, "LightColor")
	self:NetworkVar("Float", 0, "LightRadius")
	self:NetworkVar("Float", 1, "LightBrightness")
	self:NetworkVar("Float", 2, "LightFOV")
	self:NetworkVar("Float", 3, "ShadowSoft")      -- shadow edge blur (filter size)
	self:NetworkVar("Float", 4, "ShadowBias")      -- depth bias
	self:NetworkVar("Float", 5, "ShadowNear")      -- near limit of the light and of the shadow map (near Z)
	self:NetworkVar("Float", 6, "ShadowSlope")     -- slope bias of this light; 0 = the shared one (Shadows tab)
	self:NetworkVar("Float", 7, "AttConst")        -- falloff: constant
	self:NetworkVar("Float", 8, "AttLinear")       -- linear
	self:NetworkVar("Float", 9, "AttQuad")         -- quadratic
	self:NetworkVar("Float", 10, "OrthoSize")      -- half side of the parallel beam
	self:NetworkVar("Float", 11, "EdgeSoft")       -- a0.2: softness of the spot edge (0 — the mask as is, 1 — fades from the centre)
	self:NetworkVar("Float", 12, "SourceSize")     -- source size: soft shadows in the final render
	self:NetworkVar("Float", 13, "GlowSize")       -- glow of the source in the picture, units (0 — none)
	self:NetworkVar("Float", 14, "GlowBright")
	self:NetworkVar("Float", 15, "VolStrength")    -- visible beam in the air (0 — none)
	self:NetworkVar("Float", 16, "VolLength")      -- its length as a share of the light distance
	self:NetworkVar("Bool", 2, "LightOrtho")       -- parallel beam ("sun") instead of a cone
	self:NetworkVar("String", 0, "LightTexture")   -- light mask (the LampTextures list)
	self:NetworkVar("Bool", 0, "LightEnabled")
	self:NetworkVar("Bool", 1, "LightShadows")     -- the spot casts shadows
	self:NetworkVar("Int", 0, "LightType")   -- 0 = point, 1 = spot
end

if SERVER then
	function ENT:Initialize()
		self:SetModel("models/hunter/plates/plate025x025.mdl")
		self:SetMoveType(MOVETYPE_NONE)
		self:SetSolid(SOLID_NONE)
		self:DrawShadow(false)
		self:SetLightColor(Vector(1, 0.96, 0.88))
		self:SetLightRadius(400)
		self:SetLightBrightness(2)
		self:SetLightFOV(60)
		self:SetLightEnabled(true)
		self:SetLightType(1)
		self:SetLightShadows(true)
		self:SetShadowSoft(0.2)
		self:SetShadowBias(0.0001)
		self:SetShadowNear(10)
		self:SetShadowSlope(0)
		self:SetAttConst(0)
		self:SetAttLinear(100)
		self:SetAttQuad(0)
		self:SetOrthoSize(200)
		self:SetLightOrtho(false)
		self:SetLightTexture("effects/flashlight001")
		self:SetEdgeSoft(0)
		self:SetSourceSize(0)
		self:SetGlowSize(0)
		self:SetGlowBright(1)
		self:SetVolStrength(0)
		self:SetVolLength(0.5)
	end

	function ENT:UpdateTransmitState()
		return TRANSMIT_ALWAYS
	end
end

if CLIENT then
	function ENT:Initialize()
		self:DrawShadow(false)
	end

	local function killProjected(self)
		if IsValid(self.PT) then self.PT:Remove() end
		self.PT = nil
	end

	-- Light state -> engine. jx, jy — offset of the source in shares of its size
	-- (SourceSize) along the "right" and "up" axes: the final render shoots the scene
	-- several times with the source at different points of its disc and averages the
	-- frames — that gives a real penumbra (see SPeditor.Lights in cl_lights.lua).
	function ENT:UpdateLight(jx, jy)
		local enabled = self:GetLightEnabled() and self:GetLightBrightness() > 0
		local ltype   = self:GetLightType()
		local c       = self:GetLightColor()

		-- Point
		if enabled and ltype == 0 then
			local d = DynamicLight(self:EntIndex())
			if d then
				d.pos        = self:GetPos()
				d.r          = c.x * 255
				d.g          = c.y * 255
				d.b          = c.z * 255
				d.brightness = self:GetLightBrightness()
				d.size       = self:GetLightRadius()
				d.decay      = 0
				d.dietime    = CurTime() + 0.25
				d.style      = 0
			end
			self.SPDynLight = true
		elseif self.SPDynLight then
			-- switched off: the engine keeps a dynamic light until its time runs out (0.25 s) —
			-- a muzzle flash keyed for one frame shone for six, and in a frame-by-frame
			-- render it leaked into the following frames. Put out at once.
			self.SPDynLight = nil
			local d = DynamicLight(self:EntIndex())
			if d then
				d.brightness = 0
				d.size       = 0
				d.dietime    = CurTime()
			end
		end

		-- Spot
		if enabled and ltype == 1 then
			if not IsValid(self.PT) then
				local pt = ProjectedTexture()
				pt:SetEnableShadows(false)
				pt:SetShadowSlopeScaleDepthBias(2)
				self.PT, self.PTTexture = pt, nil
			end
			local pt = self.PT
			local radius = self:GetLightRadius()
			local ang = self:GetAngles()
			local pos = self:GetPos() + ang:Forward() * 4
			local area = self:GetSourceSize()
			if area > 0 and jx and (jx ~= 0 or jy ~= 0) then
				pos = pos + ang:Right() * (jx * area) + ang:Up() * (jy * area)
			end
			pt:SetPos(pos)
			pt:SetAngles(ang)
			pt:SetFarZ(radius)
			-- near limit: closer than this the light does not shine and casts no shadows
			local near = self:GetShadowNear()
			pt:SetNearZ(math.Clamp(near > 0 and near or 10, 1, math.max(radius - 8, 1)))
			pt:SetFOV(math.Clamp(self:GetLightFOV(), 5, 120))
			-- parallel beam: shadows do not spread from the source (as from the sun)
			if self:GetLightOrtho() then
				local s = math.Clamp(self:GetOrthoSize(), 8, 4000)
				pt:SetOrthographic(true, s, s, s, s)
			else
				pt:SetOrthographic(false)
			end
			-- falloff; all three zeros (the light was made before the setting existed) — same as the engine default
			local ac, al, aq = self:GetAttConst(), self:GetAttLinear(), self:GetAttQuad()
			if ac + al + aq <= 0 then al = 100 end
			pt:SetConstantAttenuation(ac)
			pt:SetLinearAttenuation(al)
			pt:SetQuadraticAttenuation(aq)
			local tex = self:GetLightTexture()
			if tex == "" then tex = "effects/flashlight001" end
			-- soft edge: the mask is multiplied by a smooth falloff towards the edge (one texture per "mask + softness" pair)
			local Lt = SPeditor and SPeditor.Lights
			local mask, key = tex, tex
			if Lt then mask, key = Lt.Mask(tex, self:GetEdgeSoft()) end
			if key ~= self.PTTexture then
				self.PTTexture = key
				pt:SetTexture(mask)
			end
			pt:SetBrightness(self:GetLightBrightness())
			pt:SetColor(Color(c.x * 255, c.y * 255, c.z * 255))
			-- shadows: the SPeditor.Shadows library decides which lights get shadows
			local Sh = SPeditor and SPeditor.Shadows
			local shadowsOn = Sh and Sh.WantsShadows(self) or false
			pt:SetEnableShadows(shadowsOn)
			if shadowsOn then
				local slope = self:GetShadowSlope()
				pt:SetShadowFilter(self:GetShadowSoft() * Sh.GetSoftScale())
				pt:SetShadowDepthBias(self:GetShadowBias())
				pt:SetShadowSlopeScaleDepthBias(slope > 0 and slope or Sh.GetSlope())
			end
			pt:Update()
		else
			killProjected(self)
		end
	end

	function ENT:Think()
		self:UpdateLight(0, 0)
		-- the glow and the beam are drawn far outside the placeholder model: widen the render bounds
		local reach = math.max(self:GetGlowSize(), self:GetVolStrength() > 0 and self:GetLightRadius() * self:GetVolLength() or 0)
		if reach ~= self.SPReach then
			self.SPReach = reach
			local r = math.max(reach, 16)
			self:SetRenderBounds(Vector(-r, -r, -r), Vector(r, r, r))
		end
	end

	function ENT:OnRemove()
		killProjected(self)
	end

	function ENT:Draw() end

	-- The wireframe is drawn only in the editor and not in the render / preview
	function ENT:DrawTranslucent()
		-- the glow and the beam are part of the picture: drawn in every view, in the render and outside the editor
		local Lt = SPeditor and SPeditor.Lights
		if Lt then Lt.DrawEffects(self) end

		local C = SPeditor and SPeditor.Client
		if not C or not C.active or C.hideUI or C.vpPass == "secondary" then return end

		-- fullbright ignores the wireframe colour: draw it with regular lighting
		local restore = SPeditor.Render.HelperLighting()
		self:DrawHelpers(C)
		restore()
	end

	function ENT:DrawHelpers(C)
		local c      = self:GetLightColor()
		local pos    = self:GetPos()
		local radius = self:GetLightRadius()
		local ang    = self:GetAngles()

		if C.selected ~= self then
			local small = Color(c.x * 255, c.y * 255, c.z * 255, 120)
			render.DrawWireframeSphere(pos, 6, 6, 3, small, true)
			render.DrawLine(pos, pos + ang:Forward() * 12, small, true)
			return
		end

		local col   = Color(255, 210, 90, 240)
		local faint = Color(255, 210, 90, 60)
		render.DrawWireframeSphere(pos, 8, 8, 4, col, true)

		if self:GetLightType() == 0 then
			render.DrawWireframeSphere(pos, radius, 20, 8, faint, false)
		else
			local dir, up, right = ang:Forward(), ang:Up(), ang:Right()
			local center = pos + dir * radius
			if self:GetLightOrtho() then
				-- parallel beam: a rectangular "tube"
				local s = math.Clamp(self:GetOrthoSize(), 8, 4000)
				local prevA, prevB
				for i = 0, 4 do
					local sx = (i == 1 or i == 2) and 1 or -1
					local sy = (i == 2 or i == 3) and 1 or -1
					local off = right * (sx * s) + up * (sy * s)
					local a, b = pos + off, center + off
					if prevA then
						render.DrawLine(prevA, a, faint, false)
						render.DrawLine(prevB, b, faint, false)
					end
					if i < 4 then render.DrawLine(a, b, faint, false) end
					prevA, prevB = a, b
				end
			else
				local half   = math.rad(math.Clamp(self:GetLightFOV(), 5, 120) / 2)
				local baseR  = radius * math.tan(half)
				local prev
				for i = 0, 32 do
					local a = (i / 32) * math.pi * 2
					local v = center + right * (math.cos(a) * baseR) + up * (math.sin(a) * baseR)
					if prev then render.DrawLine(prev, v, faint, false) end
					prev = v
					if i % 4 == 0 then render.DrawLine(pos, v, faint, false) end
				end
			end
			render.DrawLine(pos, center, col, true)
			render.DrawWireframeSphere(center, 6, 8, 4, col, true)
		end
	end
end
