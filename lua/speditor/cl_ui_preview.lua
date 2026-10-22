--[[
SPeditor — small previews for the browsers (a0.9), as in SFM: before a model or a particle system
is put into the scene, it is shown on its own.

  UI.ModelPreview(parent)      a panel: the model turns slowly in its idle animation; drag —
                               turn it yourself, wheel — closer / farther.  :SetModel(path)
  UI.ParticlePreview(parent)   a panel: the particle system plays over and over, the camera
                               widens to what it has emitted.  :SetEffect(item)  (item.src = "pcf")
                               Effects that play by themselves in the world (util.Effect, the
                               Emitter tool) cannot be drawn apart from it: the panel says so.

3D drawn from a panel's Paint does not show inside the editor's windows (measured in game: not
even a sphere), so every preview is drawn into its own render target in PostRender, the way the
render preview is, and the panel only shows that texture. The model is a ClientsideModel and the
particle system is made far above the player; neither is drawn in the world (SetNoDraw,
SetShouldDraw(false)) — the preview draws them itself (DrawModel, CNewParticleEffect:Render).
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI = SPeditor.UI
local L  = SPeditor.L
local COL = UI.PAL

local RT_SIZE = 512
local previews = setmetatable({}, { __mode = "k" })    -- [panel] = true
local serial = 0

local matShow = CreateMaterial("speditor_preview_show", "UnlitGeneric", { ["$nolod"] = "1" })

-- a preview panel: its texture, the size it is drawn at, and its own draw function (s:SPDraw())
local function newPreview(parent)
	local p = vgui.Create("DPanel", parent)
	serial = serial + 1
	p.SPRT = GetRenderTarget("speditor_preview_" .. serial, RT_SIZE, RT_SIZE)
	previews[p] = true
	p.SPShow = function(s, w, h)
		s.SPPainted = RealTime()
		local k = math.min(RT_SIZE / math.max(w, 1), RT_SIZE / math.max(h, 1), 1)
		s.SPW, s.SPH = math.max(math.floor(w * k), 8), math.max(math.floor(h * k), 8)
		if not s.SPReady then return end
		matShow:SetTexture("$basetexture", s.SPRT)
		surface.SetMaterial(matShow)
		surface.SetDrawColor(255, 255, 255, 255)
		SPeditor.Render.DrawTexturedUV(0, 0, w, h, s.SPW / RT_SIZE, s.SPH / RT_SIZE)
	end
	return p
end

SPeditor.Hook("PostRender", "SPeditor.Previews", function()
	local now = RealTime()
	for p in pairs(previews) do
		-- only what was on screen a moment ago
		if IsValid(p) and p.SPDraw and p.SPW and now - (p.SPPainted or 0) < 0.25 then
			render.PushRenderTarget(p.SPRT)
			render.Clear(20, 20, 24, 255, true, true)
			local ok, err = pcall(p.SPDraw, p, p.SPW, p.SPH)
			render.PopRenderTarget()
			if not ok then
				ErrorNoHalt("[GM:FM] preview: " .. tostring(err) .. "\n")
				p.SPDraw = nil
			end
			p.SPReady = true
		end
	end
end)

local function caption(w, h, text, col)
	draw.SimpleText(text, "SPeditor.Small", w / 2, h - 4, col or COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
end
local function middleText(w, h, a, b)
	draw.SimpleText(a, "SPeditor.Small", w / 2, h / 2 - (b and 8 or 0), COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if b then draw.SimpleText(b, "SPeditor.Small", w / 2, h / 2 + 8, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
end
local function frame(w, h)
	surface.SetDrawColor(COL.BORDER)
	surface.DrawOutlinedRect(0, 0, w, h, 1)
end

---------------------------------------------------------------------
-- Models
---------------------------------------------------------------------
local IDLE = { "idle_all_01", "idle_subtle", "idle01", "idle", "ragdoll", "reference" }

function UI.ModelPreview(parent)
	local mp = newPreview(parent)
	mp.SPYaw, mp.SPZoom = 30, 1

	local function drop(s)
		if IsValid(s.SPEnt) then s.SPEnt:Remove() end
		s.SPEnt = nil
	end

	function mp:SetModel(path)
		if not isstring(path) or path == self.SPPath then return end
		self.SPPath = path
		drop(self)
		local ent = ClientsideModel(path, RENDERGROUP_OPAQUE)
		if not IsValid(ent) then return end
		ent:SetNoDraw(true)
		ent:SetIK(false)
		for _, name in ipairs(IDLE) do
			local seq = ent:LookupSequence(name)
			if seq and seq > 0 then
				ent:ResetSequence(seq)
				break
			end
		end
		self.SPEnt = ent
		self.SPInfo = string.format("%s  ·  %d %s", string.GetFileFromFilename(path), ent:GetBoneCount(), L("pv_bones"))
	end

	mp.SPDraw = function(s, w, h)
		local ent = s.SPEnt
		if not IsValid(ent) then return end
		if s.SPDrag then
			local x = gui.MouseX()
			s.SPYaw = s.SPYaw + (x - s.SPDrag) * 0.6
			s.SPDrag = x
		elseif not s:IsHovered() then
			s.SPYaw = s.SPYaw + FrameTime() * 25
		end
		ent:SetAngles(Angle(0, s.SPYaw, 0))
		ent:FrameAdvance(FrameTime())
		ent:SetupBones()
		-- the camera looks at the middle of the model from as far as its size asks
		local mn, mx = ent:GetRenderBounds()
		local size = math.max((mx - mn):Length(), 8)
		local mid = ent:GetPos() + (mn + mx) * 0.5
		local dist = size * 1.5 * s.SPZoom
		local pos = mid + Vector(dist, 0, size * 0.2 * s.SPZoom)
		cam.Start3D(pos, (mid - pos):Angle(), 32, 0, 0, w, h, 1, dist * 4)
		render.SuppressEngineLighting(true)
		render.SetLightingOrigin(mid)
		render.ResetModelLighting(0.35, 0.35, 0.38)
		render.SetModelLighting(BOX_TOP, 1, 1, 1)
		render.SetModelLighting(BOX_FRONT, 0.9, 0.9, 0.9)
		render.SetModelLighting(BOX_RIGHT, 0.6, 0.6, 0.65)
		ent:DrawModel()
		render.SuppressEngineLighting(false)
		cam.End3D()
	end

	mp.Paint = function(s, w, h)
		surface.SetDrawColor(COL.VIEW_BG or COL.LIST_BG)
		surface.DrawRect(0, 0, w, h)
		if not s.SPPath then
			s.SPPainted = RealTime()
			middleText(w, h, L("pv_model_hint"))
		else
			s:SPShow(w, h)
			caption(w, h, s.SPInfo or s.SPPath)
		end
		frame(w, h)
	end
	mp.OnMousePressed = function(s, code)
		if code == MOUSE_LEFT then
			s.SPDrag = gui.MouseX()
			s:MouseCapture(true)
		end
	end
	mp.OnMouseReleased = function(s)
		s.SPDrag = nil
		s:MouseCapture(false)
	end
	mp.OnMouseWheeled = function(s, d)
		s.SPZoom = math.Clamp(s.SPZoom * (d > 0 and 0.88 or 1.14), 0.25, 4)
		return true
	end
	mp.OnRemove = drop
	return mp
end

---------------------------------------------------------------------
-- Particle systems
---------------------------------------------------------------------
local LOOP_MAX = 6          -- a system that keeps going is started over after this long, seconds
local REST     = 0.6        -- a pause between two plays, seconds
local MAX_R    = 500        -- the widest view: some systems have huge bounds (explosion_huge)

function UI.ParticlePreview(parent)
	local pp = newPreview(parent)
	pp.SPRadius = 16

	local function kill(s)
		if s.SPPS and s.SPPS:IsValid() then s.SPPS:StopEmissionAndDestroyImmediately() end
		s.SPPS = nil
	end
	local function start(s)
		kill(s)
		local it = s.SPItem
		if not it or it.src ~= "pcf" then return end
		if it.file and it.file ~= "" and not SPeditor.Effects.Stock()[string.lower(it.file)] and file.Exists(it.file, "GAME") then
			game.AddParticles(it.file)
		end
		PrecacheParticleSystem(it.name)
		local ply = LocalPlayer()
		s.SPOrg = (IsValid(ply) and ply:GetPos() or vector_origin) + Vector(0, 0, 4000)
		local ok, ps = pcall(CreateParticleSystemNoEntity, it.name, s.SPOrg, angle_zero)
		if not ok or not ps or not ps:IsValid() then
			s.SPBroken = true
			return
		end
		ps:SetShouldDraw(false)
		-- a second point a little ahead: beams and tracers have somewhere to go
		ps:SetControlPoint(1, s.SPOrg + Vector(96, 0, 0))
		s.SPPS, s.SPT0, s.SPBroken = ps, RealTime(), nil
	end

	function pp:SetEffect(item)
		if item == self.SPItem then return end
		self.SPItem = item
		self.SPRadius, self.SPWait, self.SPMid, self.SPMidGoal = 16, nil, nil, nil
		start(self)
	end

	pp.Think = function(s)
		if not s.SPItem or s.SPItem.src ~= "pcf" or s.SPBroken then return end
		local now = RealTime()
		-- not on screen (another tab of the dock, the window closed): nothing keeps running
		if now - (s.SPPainted or 0) > 0.5 then
			if s.SPPS then kill(s) s.SPWait = now end
			return
		end
		if s.SPWait then
			if now >= s.SPWait then
				s.SPWait = nil
				start(s)
			end
			return
		end
		local ps = s.SPPS
		if not ps or not ps:IsValid() or ps:IsFinished() or now - (s.SPT0 or now) > LOOP_MAX then
			kill(s)
			s.SPWait = now + REST
		end
	end
	pp.OnRemove = kill

	pp.SPDraw = function(s, w, h)
		local ps, org = s.SPPS, s.SPOrg
		if not ps or not ps:IsValid() then return end
		-- the camera widens (never narrows within a play) to everything emitted so far and follows its
		-- middle; the
		-- bounds are around the system's own point (measured in game)
		local mn, mx = ps:GetRenderBounds()
		if mn and mx and mx.x >= mn.x then
			s.SPRadius = math.max(s.SPRadius, math.Clamp((mx - mn):Length() * 0.5, 16, MAX_R))
			local c = (mn + mx) * 0.5
			if c:Length() > MAX_R then c = c:GetNormalized() * MAX_R end
			s.SPMidGoal = c
		end
		local goal = org + (s.SPMidGoal or vector_origin)
		s.SPMid = s.SPMid and LerpVector(math.min(FrameTime() * 4, 1), s.SPMid, goal) or goal
		local dist = s.SPRadius * 2.6
		cam.Start3D(s.SPMid + Vector(-dist, -dist * 0.35, dist * 0.25), Angle(12, 19, 0), 50, 0, 0, w, h, 1, dist * 6)
		ps:Render()
		cam.End3D()
	end

	pp.Paint = function(s, w, h)
		surface.SetDrawColor(20, 20, 24, 255)
		surface.DrawRect(0, 0, w, h)
		local it = s.SPItem
		if not it then
			s.SPPainted = RealTime()
			middleText(w, h, L("pv_fx_hint"))
		elseif it.src ~= "pcf" then
			s.SPPainted = RealTime()
			middleText(w, h, L("pv_fx_live"), L("pv_fx_live2"))
		elseif s.SPBroken then
			s.SPPainted = RealTime()
			middleText(w, h, L("pv_fx_broken"))
		else
			s:SPShow(w, h)
		end
		if it then caption(w, h, it.name, COL.TEXT) end
		frame(w, h)
	end
	return pp
end
