-- SPeditor work camera in the style of SFM.
SPeditor.Client = SPeditor.Client or {}
local C = SPeditor.Client

local SMOOTH_K   = 22
local MOUSE_SENS = 0.15

-- Work camera settings (the "Camera settings" window, cl_ui_about.lua). Kept
-- between game launches.
local cvSpeed  = CreateClientConVar("gmfm_cam_speed", "400", true, false)        -- keyboard flight, units/s
local cvWheel  = CreateClientConVar("gmfm_cam_wheel", "1", true, false)          -- wheel step multiplier
local cvSmooth = CreateClientConVar("gmfm_cam_wheel_smooth", "0.85", true, false) -- 0 — abrupt, 1 — very smooth
local cvFOV    = CreateClientConVar("gmfm_cam_fov", "75", true, false)

C.CAM_DEFAULTS = { speed = 400, wheel = 1, smooth = 0.85, fov = 75 }

function C.GetFlySpeed() return math.Clamp(cvSpeed:GetFloat(), 16, 8000) end
function C.SetFlySpeed(v) cvSpeed:SetFloat(math.Clamp(tonumber(v) or 400, 16, 8000)) end
function C.GetWheelScale() return math.Clamp(cvWheel:GetFloat(), 0.1, 8) end
function C.SetWheelScale(v) cvWheel:SetFloat(math.Clamp(tonumber(v) or 1, 0.1, 8)) end
function C.GetWheelSmooth() return math.Clamp(cvSmooth:GetFloat(), 0, 1) end
function C.SetWheelSmooth(v) cvSmooth:SetFloat(math.Clamp(tonumber(v) or 0.85, 0, 1)) end

C.camera.fov = SPeditor.Clamp(cvFOV:GetFloat(), 10, 120, 75)

function C.InitCamera()
	local cam = C.camera
	if cam.init then return end
	local a = LocalPlayer():EyeAngles()
	cam.pos          = LocalPlayer():EyePos()
	cam.target       = Vector(cam.pos.x, cam.pos.y, cam.pos.z)
	cam.angles       = Angle(a.p, a.y, 0)
	cam.targetAngles = Angle(a.p, a.y, 0)
	cam.ang          = cam.angles
	cam.init         = true
end

function C.GetView()
	local cam = C.camera
	local fov = cam.fov
	if IsValid(cam.viewEnt) then fov = cam.viewEnt:GetCameraFOV() end
	return cam.pos, cam.angles, fov
end

function C.GetWorkCamera()
	local cam = C.camera
	local s = cam.saved
	if s then return s.pos, s.angles, cam.fov end
	return cam.pos, cam.angles, cam.fov
end

function C.SetWorkFOV(fov)
	C.camera.fov = SPeditor.Clamp(fov, 10, 120, 75)
	if math.abs(cvFOV:GetFloat() - C.camera.fov) > 0.001 then cvFOV:SetFloat(C.camera.fov) end
	hook.Run("SPeditor_WorkFOVChanged", C.camera.fov)
end

-- The server has to know where the editor looks from: by this point it decides which
-- objects to send to the client (see "Visibility" in sv_speditor.lua).
local sentPos, nextSend = nil, 0
SPeditor.Hook("Think", "SPeditor.ViewPos", function()
	if not C.active then
		sentPos = nil
		return
	end
	local now = RealTime()
	if now < nextSend then return end
	local pos = C.camera.pos
	if sentPos and sentPos:DistToSqr(pos) < 24 * 24 and now < nextSend + 3 then return end
	nextSend = now + 0.25
	sentPos = Vector(pos)
	net.Start(SPeditor.Net.ViewPos)
	SPeditor.WriteVecF(pos)
	net.SendToServer()
end)

-- The particles of the engine's own effects (sparks, shells, tracers, the dust of bullet
-- hits: util.Effect, and every effect a take plays) are moved on only while the engine draws
-- its main frame, which the editor does not need (b0.1: the sparks of a take hung in the air
-- for good while the editor was open). So for a while after any such effect, and after the
-- editor opens, the main frame is drawn again. It has to be a whole one: the engine moves only
-- the particles its main frame sees (with a far plane of a few units they stayed — measured).
local PARTICLE_LIFE = 12        -- s: the longest the engine's effects live
local particlesUntil = 0
function C.KeepParticlesAlive(sec)
	particlesUntil = math.max(particlesUntil, RealTime() + (sec or PARTICLE_LIFE))
end
function C.ParticlesAlive() return RealTime() < particlesUntil end
C.realUtilEffect = C.realUtilEffect or util.Effect
local realUtilEffect = C.realUtilEffect
util.Effect = function(...)
	if C.active then C.KeepParticlesAlive() end
	return realUtilEffect(...)
end

local wasActive = false
SPeditor.Hook("CalcView", "SPeditor.CalcView", function()
	local R = SPeditor.Render
	if not C.active then
		wasActive = false
		return
	end
	if not wasActive then
		wasActive = true
		C.KeepParticlesAlive()          -- what was flying when the editor opened
	end
	local pos, ang, fov = C.GetView()
	local znear = R and R.ZNear and R.ZNear({ ent = C.camera.viewEnt }) or 4
	-- "engine frame": the main game frame is shot by the camera chosen in the Render window
	if R and R.EngineView then
		local p, a, f, z = R.EngineView()
		if p then pos, ang, fov, znear = p, a, f, z or znear end
	end
	return { origin = pos, angles = ang, fov = fov, drawviewer = false, znear = znear }
end)

-- The engine's own motion blur (mat_motion_blur_enabled, Options → Video → Motion blur) works
-- out the blur from how far the main view moved since its last frame. In the editor the main view
-- jumps between the work camera and the camera of an "engine frame", so a video rendered in that
-- mode came out smeared sideways in every frame (b0.2.6 round 7, shootout_construct at 60 fps).
-- It is off while the editor is open: the renders blur motion themselves (the shutter).
SPeditor.Hook("GetMotionBlurValues", "SPeditor.NoEngineBlur", function()
	if C.active then return 0, 0, 0, 0 end
end)

-- The main game frame is not needed in the editor: windows cover it entirely and the
-- viewports draw the scene. Without this hook the engine drew the scene once more, full screen.
-- Returning true cancels drawing of the world and the HUD; the interface (VGUI) is drawn as usual.
-- The exception is the "engine frame" (cl_render.lua): in that frame the engine draws the
-- scene, with all addon shaders, and the editor takes it from the screen.
SPeditor.Hook("RenderScene", "SPeditor.SkipMainScene", function()
	if not C.active then return end
	local R = SPeditor.Render
	if R and R.BeginEngineFrame and R.BeginEngineFrame() then return end
	local bg = SPeditor.UI and SPeditor.UI.PAL and SPeditor.UI.PAL.BORDER
	-- the engine's particles need its frame to move (C.ParticlesAlive above): the Primary
	-- Viewport is drawn here then, in the main frame's place (b0.2.2, R.EarlyPrimary), or else
	-- the engine draws its frame
	if C.ParticlesAlive() then
		if not (R and R.EarlyPrimary) then return end
		render.Clear(bg and bg.r or 34, bg and bg.g or 32, bg and bg.b or 33, 255, true, true)
		if not R.EarlyPrimary() then return end
		return true
	end
	render.Clear(bg and bg.r or 34, bg and bg.g or 32, bg and bg.b or 33, 255, true, true)
	return true
end)

SPeditor.Hook("CreateMove", "SPeditor.CreateMove", function(cmd)
	if not C.active then return end
	cmd:ClearMovement()
	cmd:ClearButtons()
	cmd:SetImpulse(0)
end)

SPeditor.Hook("InputMouseApply", "SPeditor.MouseLook", function(_, x, y)
	if not C.active or not C.camMode then return end
	C.navDx = (C.navDx or 0) + x
	C.navDy = (C.navDy or 0) + y
	return true
end)

local function setUIMouse(state)
	local UI = SPeditor.UI
	if not UI or not UI.Frames then return end
	for _, f in ipairs(UI.Frames) do
		if IsValid(f) then f:SetMouseInputEnabled(state) end
	end
end

local cvAutoAim = CreateClientConVar("gmfm_autoaim", "0", true, false, "Work camera: keep looking at the selected object (SFM's Auto Aim Work Camera)", 0, 1)
function C.AutoAim() return cvAutoAim:GetBool() end

local function beginNav(name, button)
	local cam = C.camera
	local mx, my = input.GetCursorPos()
	local m = { name = name, button = button, sx = mx, sy = my, lx = mx, ly = my, dist = 200, t0 = RealTime(), moved = 0 }
	if name == "orbit" then
		if IsValid(C.selected) then
			m.pivot = C.GetEntityTransform(C.selected)
		else
			m.pivot = cam.pos + cam.angles:Forward() * m.dist
		end
		m.distance = math.max(cam.pos:Distance(m.pivot), 24)
	end
	C.camMode = m
	C.navDx, C.navDy = 0, 0
	setUIMouse(false)
	gui.EnableScreenClicker(false)
end

local function endNav()
	local m = C.camMode
	C.camMode = nil
	setUIMouse(true)
	gui.EnableScreenClicker(true)
	if m then input.SetCursorPos(m.sx, m.sy) end
	-- a short RMB click without movement is not flight but the menu of the object under the cursor
	if m and m.name == "fly" and RealTime() - m.t0 < 0.3 and m.moved < 6 and not C.exporting then
		timer.Simple(0.03, function()
			if not C.active or C.camMode or not C.MouseInViewport() then return end
			local ent = C.PickEntity()
			if not IsValid(ent) then return end
			if not C.IsMulti(ent) and ent ~= C.selected then C.Select(ent, -1) end
			if SPeditor.UI.ObjectMenu then SPeditor.UI.ObjectMenu(ent) end
		end)
	end
end

local function flyMove(cam, dt)
	local mult = 1
	local K = C.Keys
	if K.Down("fly_fast") then mult = 4
	elseif K.Down("fly_slow") then mult = 0.25 end
	local f, r = cam.targetAngles:Forward(), cam.targetAngles:Right()
	local up = Vector(0, 0, 1)
	local move = Vector(0, 0, 0)
	if K.Down("fly_forward") then move = move + f end
	if K.Down("fly_back") then move = move - f end
	if K.Down("fly_right") then move = move + r end
	if K.Down("fly_left") then move = move - r end
	if K.Down("fly_up") then move = move + up end
	if K.Down("fly_down") then move = move - up end
	if not move:IsZero() then
		if C.camMode then C.camMode.moved = C.camMode.moved + 100 end
		cam.target = cam.target + move:GetNormalized() * C.GetFlySpeed() * mult * dt
	end
end

local function anglesChanged(a, b)
	if not a or not b then return true end
	return math.abs(a.p - b.p) + math.abs(a.y - b.y) + math.abs(a.r - b.r) > 0.001
end

SPeditor.Hook("Think", "SPeditor.CameraUpdate", function()
	if not C.active then
		C.camMode = nil
		return
	end
	local cam = C.camera
	if not cam.init then return end
	local dt = math.min(RealFrameTime(), 0.05)
	if cam.viewEnt ~= nil and not IsValid(cam.viewEnt) then C.StopViewCamera() end

	local m = C.camMode
	-- The game window lost focus (Alt+Tab, minimized): the release of the button may never
	-- reach the game (on Windows it stays "down"), and the flight went on with the mouse of
	-- every editor window switched off — nothing could be clicked. The navigation ends here,
	-- and a new one starts only after the buttons are seen released.
	if not system.HasFocus() then
		if m then endNav() m = nil end
		C.navWaitUp = true
	elseif C.navWaitUp and not input.IsMouseDown(MOUSE_LEFT) and not input.IsMouseDown(MOUSE_MIDDLE)
		and not input.IsMouseDown(MOUSE_RIGHT) then
		C.navWaitUp = nil
	end
	-- FIXED: navigation only inside the Primary Viewport
	if not m and not C.exporting and not C.navWaitUp and C.MouseInViewport() then
		local alt = input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)
		local lmb = input.IsMouseDown(MOUSE_LEFT)
		local mmb = input.IsMouseDown(MOUSE_MIDDLE)
		local rmb = input.IsMouseDown(MOUSE_RIGHT)
		if alt then
			if lmb and not C.gizmo.drag then beginNav("orbit", MOUSE_LEFT)
			elseif mmb then beginNav("pan", MOUSE_MIDDLE)
			elseif rmb then beginNav("dolly", MOUSE_RIGHT) end
		elseif rmb then
			beginNav("fly", MOUSE_RIGHT)
		elseif mmb then
			beginNav("pan", MOUSE_MIDDLE)
		end
		m = C.camMode
	end
	if m and not input.IsMouseDown(m.button) then
		endNav()
		m = nil
	end
	-- SFM's Auto Aim Work Camera: while nothing moves the camera it keeps the selection in the
	-- middle of the frame — handy while the selected object is moved or played
	if not m and C.AutoAim() and not cam.viewEnt and IsValid(C.selected) and C.CenterOf then
		local c = C.CenterOf(C.selected)
		if c and c:DistToSqr(cam.target) > 1 then cam.targetAngles = (c - cam.target):Angle() end
	end
	if m then
		local dx, dy = C.navDx or 0, C.navDy or 0
		C.navDx, C.navDy = 0, 0
		if dx == 0 and dy == 0 then
			local mx, my = input.GetCursorPos()
			dx, dy = mx - m.lx, my - m.ly
			m.lx, m.ly = mx, my
		end
		m.moved = m.moved + math.abs(dx) + math.abs(dy)
		local _, _, fov = C.GetView()
		local ta = cam.targetAngles
		local sens = MOUSE_SENS * (fov / 75)
		if m.name == "fly" or m.name == "orbit" then
			ta.y = math.NormalizeAngle(ta.y - dx * sens)
			ta.p = math.Clamp(ta.p + dy * sens, -89, 89)
		end
		if m.name == "fly" then
			flyMove(cam, dt)
		elseif m.name == "pan" then
			local k = m.dist * 0.0015 * (fov / 75)
			cam.target = cam.target - ta:Right() * (dx * k) + ta:Up() * (dy * k)
		elseif m.name == "dolly" then
			cam.target = cam.target + ta:Forward() * (-dy * m.dist * 0.004)
		end
	end

	C.ApplyWheel(cam, m, dt)

	local amount = 1 - math.exp(-SMOOTH_K * dt)
	cam.angles = LerpAngle(amount, cam.angles, cam.targetAngles)
	cam.ang = cam.angles
	if m and m.name == "orbit" then
		cam.pos = m.pivot - cam.angles:Forward() * m.distance
		cam.target = Vector(cam.pos.x, cam.pos.y, cam.pos.z)
	else
		cam.pos = LerpVector(amount, cam.pos, cam.target)
	end

	if IsValid(cam.viewEnt) then
		-- The camera was moved by something other than this view — an animation (SAeditor),
		-- undo, a value typed into its properties: the view follows it. Before this the view
		-- kept its own copy of the place: an animated camera stood still in the viewport, and
		-- a render "from the Primary Viewport" was shot from where the camera had been when
		-- the view was switched to it. The view follows only while it is at rest itself, and
		-- not right after it has moved the camera (the answer is still on its way).
		local ep, ea = SPeditor.LivePos(cam.viewEnt)
		local atRest = not m and cam.sentPos ~= nil and RealTime() > (cam.sentT or 0) + 0.4
			and cam.sentPos:DistToSqr(cam.pos) <= 0.01 and not anglesChanged(cam.sentAng, cam.angles)
			and cam.pos:DistToSqr(cam.target) <= 0.01 and not anglesChanged(cam.angles, cam.targetAngles)
		if atRest and (ep:DistToSqr(cam.pos) > 0.01 or anglesChanged(ea, cam.angles)) then
			cam.pos, cam.target = Vector(ep.x, ep.y, ep.z), Vector(ep.x, ep.y, ep.z)
			cam.angles, cam.targetAngles = Angle(ea.p, ea.y, ea.r), Angle(ea.p, ea.y, ea.r)
			cam.ang = cam.angles
			cam.sentPos, cam.sentAng = Vector(ep.x, ep.y, ep.z), Angle(ea.p, ea.y, ea.r)
		elseif cam.sentPos == nil or cam.sentPos:DistToSqr(cam.pos) > 0.01
			or anglesChanged(cam.sentAng, cam.angles) then
			C.SendTransform(cam.viewEnt, cam.pos, cam.angles)
			cam.sentPos = Vector(cam.pos.x, cam.pos.y, cam.pos.z)
			cam.sentAng = Angle(cam.angles.p, cam.angles.y, cam.angles.r)
			cam.sentT = RealTime()
			-- flying a scene camera is not an edit of the history; animation tools (auto key)
			-- hear it from here
			hook.Run("SPeditor_ViewCameraMoved", cam.viewEnt)
		end
	end
end)

---------------------------------------------------------------------
-- Mouse wheel over the Primary Viewport (as in SFM)
---------------------------------------------------------------------
local ZOOM_STEP = 0.12    -- share of the distance to the point of interest per click
local ZOOM_MIN  = 14      -- units per click at the very least: the camera does not get "stuck" at a wall or an object
local ZOOM_MAX  = 320     -- and at the very most: looking into the distance does not carry the camera across the whole map
local FOV_STEP  = 2       -- degrees per click

-- Distance to what the camera looks at: the selected object if it is
-- ahead, otherwise the surface under the frame centre. The step depends on it: up close
-- the camera moves in small steps, from afar — in large ones.
local function focusDistance(cam)
	local fwd = cam.targetAngles:Forward()
	if IsValid(C.selected) then
		local center = C.CenterOf(C.selected)
		if center then
			local along = (center - cam.target):Dot(fwd)
			if along > 8 then return along end
		end
	end
	local tr = util.TraceLine({ start = cam.target, endpos = cam.target + fwd * 4000, filter = LocalPlayer() })
	return tr.Hit and math.max(tr.HitPos:Distance(cam.target), 8) or 400
end

-- The wheel does not jerk the camera: a click adds travel to a reserve (zoomPending,
-- fovPending), and the reserve is spent smoothly over frames — several clicks in a row
-- merge into one motion.
local FOV_SMOOTH = 12

-- rate of spending the reserve, 1/s: the higher, the faster the camera arrives
local function zoomRate()
	return 24 - 20 * C.GetWheelSmooth()
end

local function consume(pending, k, dt, eps)
	if math.abs(pending) <= eps then return pending, 0 end
	local step = pending * (1 - math.exp(-k * dt))
	return step, pending - step
end

-- called from the camera Think before the position is smoothed
function C.ApplyWheel(cam, m, dt)
	local z = cam.zoomPending
	if z and z ~= 0 then
		local step
		step, cam.zoomPending = consume(z, zoomRate(), dt, 0.05)
		if m and m.name == "orbit" then
			m.distance = math.Clamp(m.distance - step, 8, 16000)
		else
			cam.target = cam.target + cam.targetAngles:Forward() * step
		end
	end
	local f = cam.fovPending
	if f and f ~= 0 then
		local step
		step, cam.fovPending = consume(f, FOV_SMOOTH, dt, 0.02)
		C.SetWorkFOV(cam.fov + step)
	end
end

-- delta > 0 — wheel away from you (closer). Shift — faster, Ctrl — finer.
-- wheel           move the camera closer / farther; also works with a mouse button
-- held: in flight (RMB), while panning, on the orbit (orbit radius)
-- Alt + wheel     field of view (FOV) of the work camera or of the scene camera being looked through
function C.WheelZoom(delta)
	local cam = C.camera
	if not C.active or not cam.init or C.exporting or delta == 0 then return end
	local dir = delta > 0 and 1 or -1
	local mult = 1
	if input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT) then mult = 4
	elseif input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL) then mult = 0.25 end

	local m = C.camMode
	local orbit = m and m.name == "orbit"
	-- on the orbit Alt is always held (Alt+LMB), so there the wheel is the radius only
	if not orbit and (input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT)) then
		local ve = C.GetViewCamera()
		if ve then
			C.SendCameraEdit(ve, "fov", math.Clamp(ve:GetCameraFOV() - dir * FOV_STEP * mult, 10, 120))
		else
			local want = math.Clamp(cam.fov + (cam.fovPending or 0) - dir * FOV_STEP * mult, 10, 120)
			cam.fovPending = want - cam.fov
		end
		return
	end

	-- a change of direction cancels the unspent travel at once: the camera does not keep
	-- "arriving" forward when the wheel is already turned back
	local pending = cam.zoomPending or 0
	if pending * dir < 0 then pending = 0 end

	-- the distance is counted from the point where the camera will arrive with the reserve; the
	-- backward step is slightly larger, so that a click forward and a click back return to the same place
	mult = mult * C.GetWheelScale()
	local dist = math.max((orbit and m.distance or focusDistance(cam)) - pending, 8)
	local k = math.min(ZOOM_STEP * mult, 0.6)
	local step = (dir > 0) and (dist * k) or (dist * k / (1 - k))
	if orbit then
		-- the orbit radius changes only by a share: we approach the pivot but never pass through it
		step = math.min(step, 1200)
	else
		step = math.Clamp(step, ZOOM_MIN * mult, ZOOM_MAX * mult)
	end
	cam.zoomPending = pending + dir * step
end

-- While a navigation button is held (flight, pan, orbit), the mouse is off for the
-- interface and the wheel arrives as a bind; over the viewport the frame panel gets it
-- (cl_ui_main.lua).
SPeditor.Hook("PlayerBindPress", "SPeditor.Wheel", function(_, bind, pressed)
	if not C.active then return end
	if bind ~= "invnext" and bind ~= "invprev" then return end
	if pressed and (C.camMode or C.MouseInViewport()) then
		C.WheelZoom((bind == "invprev") and 1 or -1)
	end
	return true
end)

---------------------------------------------------------------------
-- Where a scene camera looks from: its place and angles with the shake added.
-- The shake is a function of the scene time, not of the clock: a frame of an animation
-- shows the same throw however many times it is drawn (depth of field and soft shadows
-- draw it dozens of times). The time comes from SAeditor when it has one (SAeditor: the
-- playhead); without it the camera stands still.
---------------------------------------------------------------------
local TAU = math.pi * 2
-- smooth noise -1..1: three sines whose periods never line up; seed moves it along
local function wobble(t, seed)
	return math.sin(TAU * (t + seed * 0.37)) * 0.55 + math.sin(TAU * (t * 2.17 + seed * 1.13)) * 0.3
		+ math.sin(TAU * (t * 4.31 + seed * 2.71)) * 0.15
end

function C.SceneTime()
	return tonumber(hook.Run("SPeditor_SceneTime")) or 0
end

function C.CameraPose(ent)
	local pos, ang = SPeditor.LivePos(ent)
	local amp, rot = ent:GetShakeAmp(), ent:GetShakeRot()
	if amp <= 0 and rot <= 0 then return pos, ang end
	local t = C.SceneTime() * math.max(ent:GetShakeFreq(), 0.2)
	if amp > 0 then
		pos = pos + ang:Right() * (wobble(t, 1) * amp) + ang:Up() * (wobble(t, 2) * amp) + ang:Forward() * (wobble(t, 3) * amp * 0.4)
	end
	if rot > 0 then
		ang = Angle(ang.p + wobble(t, 4) * rot, ang.y + wobble(t, 5) * rot, ang.r + wobble(t, 6) * rot * 0.6)
	end
	return pos, ang
end

---------------------------------------------------------------------
-- View through a scene camera
---------------------------------------------------------------------
function C.GetViewCamera()
	local v = C.camera.viewEnt
	return IsValid(v) and v or nil
end

function C.StartViewCamera(ent)
	if not C.IsCamera(ent) then return end
	local cam = C.camera
	if IsValid(cam.viewEnt) and cam.viewEnt ~= ent then
		C.FlushQueue()
		C.SendCameraView(cam.viewEnt, false)
	end
	if not cam.viewEnt then
		cam.saved = {
			pos = Vector(cam.pos.x, cam.pos.y, cam.pos.z),
			target = Vector(cam.target.x, cam.target.y, cam.target.z),
			angles = Angle(cam.angles.p, cam.angles.y, cam.angles.r),
			targetAngles = Angle(cam.targetAngles.p, cam.targetAngles.y, cam.targetAngles.r),
		}
	end
	local p, a = ent:GetPos(), ent:GetAngles()
	cam.viewEnt = ent
	cam.pos = Vector(p.x, p.y, p.z)
	cam.target = Vector(p.x, p.y, p.z)
	cam.angles = Angle(a.p, a.y, a.r)
	cam.targetAngles = Angle(a.p, a.y, a.r)
	cam.ang = cam.angles
	cam.sentPos, cam.sentAng = nil, nil
	cam.zoomPending = nil
	C.SendCameraView(ent, true)
	hook.Run("SPeditor_ViewChanged", ent)
end

function C.StopViewCamera()
	local cam = C.camera
	local ent = cam.viewEnt
	if ent == nil then return end
	C.FlushQueue()
	cam.viewEnt = nil
	local s = cam.saved
	if s then
		cam.pos, cam.target = s.pos, s.target
		cam.angles, cam.targetAngles = s.angles, s.targetAngles
		cam.ang = cam.angles
		cam.saved = nil
	end
	cam.sentPos, cam.sentAng = nil, nil
	cam.zoomPending = nil
	if IsValid(ent) then C.SendCameraView(ent, false) end
	hook.Run("SPeditor_ViewChanged", nil)
end

function C.MatchCameraToWork(ent)
	if not C.IsCamera(ent) then return end
	local pos, ang = C.GetWorkCamera()
	local p0, a0 = ent:GetPos(), ent:GetAngles()
	local p1, a1 = Vector(pos), Angle(ang)
	local ref = C.Ref(ent)
	C.SendTransform(ent, pos, ang, true)
	C.PushHistory("match camera",
		function() local e = C.Deref(ref) if e then C.SendTransform(e, p0, a0, true) end end,
	function() local e = C.Deref(ref) if e then C.SendTransform(e, p1, a1, true) end end)
	C.SendCameraEdit(ent, "fov", C.camera.fov, true)
end

function C.MatchWorkToCamera(ent)
	if not C.IsCamera(ent) then return end
	C.StopViewCamera()
	local cam = C.camera
	local p, a = ent:GetPos(), ent:GetAngles()
	cam.pos, cam.target = Vector(p.x, p.y, p.z), Vector(p.x, p.y, p.z)
	cam.angles, cam.targetAngles = Angle(a.p, a.y, a.r), Angle(a.p, a.y, a.r)
	cam.ang = cam.angles
	C.SetWorkFOV(ent:GetCameraFOV())
end

function C.FocusSelected()
	local ent = C.selected
	if not IsValid(ent) then return end
	local pos
	if C.selBone >= 0 then pos = C.GetBoneWorld(ent, C.selBone) end
	pos = pos or C.GetEntityTransform(ent)
	local radius = C.IsAux(ent) and 60 or math.max(ent:BoundingRadius(), 20)
	if C.selBone >= 0 then radius = math.max(radius * 0.35, 20) end
	C.camera.target = pos - C.camera.targetAngles:Forward() * (radius * 2.4)
end

-- Frame settings that belong to the scene rather than to the editor as a whole:
-- exposure, aspect ratio, render size and quality. Saved together
-- with the scene and restored when it is loaded.
local FRAME_CVARS = {
	"gmfm_exposure", "gmfm_aspect", "gmfm_render_side", "gmfm_render_custom",
	"gmfm_render_w", "gmfm_render_h", "gmfm_render_fullbright", "gmfm_render_ss",
	"gmfm_dof", "gmfm_dof_aperture", "gmfm_dof_samples",
	"gmfm_ssao", "gmfm_ssao_radius", "gmfm_ssao_strength", "gmfm_ssao_mode", "gmfm_ssao_passes", "gmfm_ssao_bias",
}

-- Cameras that record their own moves (a0.7): every move, turn or field of view change of
-- such a camera sets a key at the current frame, with or without Auto key (SAeditor reads
-- it). By UID; saved with the scene.
C.camRecord = C.camRecord or {}

function C.CameraRecords(ent)
	return IsValid(ent) and C.IsCamera(ent) and C.camRecord[ent:GetNW2Int("SPeditor_UID", 0)] == true
end

function C.SetCameraRecords(ent, on)
	if not IsValid(ent) or not C.IsCamera(ent) then return end
	local uid = ent:GetNW2Int("SPeditor_UID", 0)
	if uid == 0 then return end
	C.camRecord[uid] = on and true or nil
	SPeditor.Notify(on and "#cam_rec_on" or "#cam_rec_off", 0)
	hook.Run("SPeditor_CameraRecordChanged", ent, on)
end

function C.GetSceneMeta()
	local w = C.camera.saved or C.camera
	local frame = {}
	for _, name in ipairs(FRAME_CVARS) do
		local cv = GetConVar(name)
		if cv then frame[name] = cv:GetString() end
	end
	return util.TableToJSON({
			camera = { pos = SPeditor.VecToTable(w.pos), ang = SPeditor.AngToTable(w.angles), fov = C.camera.fov },
			frame = frame,
			camrec = table.GetKeys(C.camRecord),
			-- the lighting of the map (b0.2 round 6, cl_env.lua)
			env = SPeditor.Env and SPeditor.Env.Serialize() or nil,
	}) or ""
end

SPeditor.Hook("SPeditor_SceneLoaded", "SPeditor.CameraMeta", function(meta)
	C.StopViewCamera()
	C.Select(nil)
	C.camRecord = {}
	local data = util.JSONToTable(meta or "")
	if type(data) ~= "table" then return end
	for _, uid in ipairs(istable(data.camrec) and data.camrec or {}) do
		if tonumber(uid) then C.camRecord[math.floor(tonumber(uid))] = true end
	end
	local c = data.camera
	if type(c) == "table" then
		local pos, ang = SPeditor.TableToVec(c.pos), SPeditor.TableToAng(c.ang)
		if pos and ang then
			local cam = C.camera
			cam.pos, cam.target = pos, Vector(pos.x, pos.y, pos.z)
			cam.angles, cam.targetAngles = ang, Angle(ang.p, ang.y, ang.r)
			cam.ang = cam.angles
			C.SetWorkFOV(c.fov)
		end
	end
	-- only known variables and only short values (a scene file is external data)
	if SPeditor.Env and type(data.env) == "table" then SPeditor.Env.ApplyScene(data.env) end
	if type(data.frame) == "table" then
		for _, name in ipairs(FRAME_CVARS) do
			local v = data.frame[name]
			if v == nil and SPeditor.OldCvar then v = data.frame[SPeditor.OldCvar(name) or ""] end   -- a scene made before b0.1
			if (type(v) == "string" or type(v) == "number") and #tostring(v) <= 16 and GetConVar(name) then
				RunConsoleCommand(name, tostring(v))
			end
		end
	end
end)

---------------------------------------------------------------------
-- Aiming the camera at an object ("focusing" without DoF)
---------------------------------------------------------------------
-- Centre of the object in the world. For a ragdoll — the mean of its physics bones (its OBB
-- stays in the original pose and does not reflect the current one).
function C.CenterOf(ent)
	if not IsValid(ent) then return nil end
	if C.IsRagdoll(ent) then
		-- worked out once a frame (b0.2.2): the sounds of a recorded take asked for the centres
		-- of the same ragdolls every frame for every playing clip — ~1 ms of a frame
		local frame = FrameNumber()
		if ent.SPCenterAt == frame and ent.SPCenter then return Vector(ent.SPCenter) end
		local sum, n = Vector(0, 0, 0), 0
		for b = 0, ent:GetBoneCount() - 1 do
			if C.PhysIndexOfBone(ent, b) then
				local p = C.GetBoneWorld(ent, b)
				if p then sum = sum + p n = n + 1 end
			end
		end
		if n > 0 then
			sum = sum / n
			ent.SPCenterAt, ent.SPCenter = frame, sum
			return Vector(sum)
		end
	end
	if C.IsAux(ent) then return ent:GetPos() end
	return ent:LocalToWorld(ent:OBBCenter())
end

---------------------------------------------------------------------
-- (b0.2.6, as SFM) The focus of a scene camera made visible. While its focal distance or aperture
-- is changed (and for a moment after) the views draw the plane that is in focus: a view through
-- that camera tints what is BEHIND the plane inside a lilac square (what is in front of it stays
-- clear) and shows the distance under the frame; any other view draws the camera's frustum out
-- to that plane with the square's outline. A selected camera with its own depth of field keeps
-- the outline in the other views.
---------------------------------------------------------------------
-- (b0.2.6 round 8) drawn as SFM draws it (the user's SFM screenshot): a small lilac SQUARE at the
-- focal distance in the middle of the frame — through the camera it is a translucent square that
-- tints what is behind the plane (what is in front stays clear), in the other views its outline at
-- the end of the camera's frustum lines. Before, the whole frame was tinted. Round 9: the square
-- has one size in the world (SFM's: about 36 units, 0.86 of the frame at 39 units in the
-- screenshot), so through the camera it grows as the plane comes nearer and shrinks as it goes —
-- of a constant size on the screen it did not seem to move at all.
local FOCUS_COL = Color(200, 120, 235)
local FOCUS_SIDE = 36       -- the square's side, units
C.focusEdit = C.focusEdit or nil

-- the focus distance of a camera's own depth of field (camera effects, cl_postfx.lua) and its
-- aperture, or nil when the camera has no depth of field
function C.CameraFocus(ent)
	local FX = SPeditor.FX
	if not C.IsCamera(ent) or not FX then return nil end
	local dof = FX.DOF(C.GetCameraFX(ent))
	if not dof then return nil end
	return dof.focus, dof.aperture
end

-- show the focus of ent for `sec` seconds (an edit of the focus calls it on every change)
function C.ShowFocus(ent, sec)
	C.focusEdit = { ent = ent, untilT = RealTime() + (sec or 1.5) }
end

local function editingFocus()
	local fe = C.focusEdit
	if fe and IsValid(fe.ent) and RealTime() < fe.untilT then return fe.ent end
end
C.FocusEditing = editingFocus

-- the half size of the frame `dist` in front of the camera (across, down)
local function frameHalf(fov, dist)
	local W, H = C.GetRenderSize()
	fov = C.FrameFOV(fov, W / math.max(H, 1))
	local hw = dist * math.tan(math.rad(math.Clamp(fov, 1, 170)) / 2)
	return hw, hw * H / math.max(W, 1)
end

-- the corners of SFM's focus square `dist` in front of the camera
local function focusSquare(pos, ang, fov, dist)
	local half = FOCUS_SIDE / 2
	local c = pos + ang:Forward() * dist
	local r, u = ang:Right() * half, ang:Up() * half
	return c + r + u, c - r + u, c - r - u, c + r - u
end

SPeditor.Hook("PostDrawTranslucentRenderables", "GMFM.FocusPlane", function(depth, sky)
	if depth or sky or not C.active or C.hideUI or C.exporting or C.vpPass == "export" then return end
	-- not into the depth picture of the viewport's occlusion (cl_ssao.lua)
	local R = SPeditor.Render
	if R and R.DepthPassActive and R.DepthPassActive() then return end
	local edit = editingFocus()
	local sel = C.selected
	local list = {}
	if edit then list[1] = edit end
	if IsValid(sel) and sel ~= edit and C.IsCamera(sel) then list[#list + 1] = sel end
	for _, cam in ipairs(list) do
		local focus = C.CameraFocus(cam)
		if focus then
			local pos, ang = C.CameraPose(cam)
			local fov = cam:GetCameraFOV()
			local a, b, c, d = focusSquare(pos, ang, fov, focus)
			if C.renderViewEnt == cam then
				-- the view through the camera: the square itself, depth-tested, while it is changed
				if cam == edit then
					render.SetColorMaterial()
					local col = Color(FOCUS_COL.r, FOCUS_COL.g, FOCUS_COL.b, 90)
					render.DrawQuad(a, b, c, d, col)
					render.DrawQuad(d, c, b, a, col)
				end
			else
				-- other views: the frustum out to the plane (the frame's corners) and the square
				local hw, hh = frameHalf(fov, focus)
				local fc = pos + ang:Forward() * focus
				local r, u = ang:Right() * hw, ang:Up() * hh
				local restore = SPeditor.Render.HelperLighting()
				render.SetColorMaterialIgnoreZ()
				local col = Color(FOCUS_COL.r, FOCUS_COL.g, FOCUS_COL.b, cam == edit and 230 or 160)
				local thin = Color(255, 255, 255, 50)
				for _, p in ipairs({ fc + r + u, fc - r + u, fc - r - u, fc + r - u }) do render.DrawBeam(pos, p, 0.15, 0, 1, thin) end
				local w = 0.35
				render.DrawBeam(a, b, w, 0, 1, col)
				render.DrawBeam(b, c, w, 0, 1, col)
				render.DrawBeam(c, d, w, 0, 1, col)
				render.DrawBeam(d, a, w, 0, 1, col)
				restore()
				if cam == edit then
					render.SetColorMaterial()
					local fill = Color(FOCUS_COL.r, FOCUS_COL.g, FOCUS_COL.b, 50)
					render.DrawQuad(a, b, c, d, fill)
					render.DrawQuad(d, c, b, a, fill)
				end
			end
		end
	end
end)

-- (round 9, SFM's "Set Camera Focal Distance") The next click in the Primary Viewport puts the focal
-- plane of the camera ent on what is under the cursor: the world and props by a trace, characters
-- by their bones (a client trace goes through ragdolls) — the nearest along the ray.
local function pointUnderCursor()
	local o, dir = C.MouseRay()
	local best
	local tr = util.TraceLine({ start = o, endpos = o + dir * 32768, mask = MASK_SOLID,
		filter = function(e) return e ~= LocalPlayer() and not C.IsCamera(e) and not C.IsLight(e) end })
	if tr.Hit then best = tr.HitPos end
	local bestAlong = best and (best - o):Dot(dir) or math.huge
	for _, e in ipairs(C.Objects()) do
		if IsValid(e) and not C.IsCamera(e) and not C.IsLight(e) and e:GetBoneCount() > 1 and not e:GetNoDraw() then
			e:SetupBones()
			for b = 0, e:GetBoneCount() - 1 do
				local m = e:GetBoneMatrix(b)
				if m then
					local p = m:GetTranslation()
					local along = (p - o):Dot(dir)
					if along > 1 and along < bestAlong then
						local off = (p - o - dir * along):Length()
						if off < math.max(3, along * 0.015) then best, bestAlong = p, along end
					end
				end
			end
		end
	end
	return best
end

function C.PickFocus(ent)
	if not C.IsCamera(ent) then return end
	SPeditor.Notify("#cam_focus_pick_hint", 0)
	local tool
	-- not taken for 20 s: the click goes back to selecting
	timer.Create("GMFM.PickFocus", 20, 1, function() if C.placeTool == tool then C.placeTool = nil end end)
	tool = {
		click = function()
			C.placeTool = nil
			if not IsValid(ent) then return end
			local p = pointUnderCursor()
			if not p then return end
			local pos, ang = C.CameraPose(ent)
			local d = math.Clamp((p - pos):Dot(ang:Forward()), 8, 4000)
			local fx = table.Copy(C.GetCameraFX(ent) or {})
			fx.dof = istable(fx.dof) and fx.dof or {}
			fx.dof.on = true
			fx.dof.focus = math.Round(d, 1)
			C.SendCameraFX(ent, fx, true)
			C.ShowFocus(ent, 2.5)
			surface.PlaySound("garrysmod/ui_click.wav")
		end,
	}
	C.placeTool = tool
end

-- the distance under the frame of a view through the camera whose focus is being changed
function C.DrawFocusLabel(ent, ix, iy, iw, ih)
	if not IsValid(ent) or ent ~= editingFocus() then return end
	local focus = C.CameraFocus(ent)
	if not focus then return end
	draw.SimpleTextOutlined(string.format("%.1f", focus), "SPeditor.Time", ix + iw / 2, iy + ih - 6,
		color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
end
