-- SPeditor work camera in the style of SFM.
SPeditor.Client = SPeditor.Client or {}
local C = SPeditor.Client

local SMOOTH_K   = 22
local MOUSE_SENS = 0.15

-- Work camera settings (the "Camera settings" window, cl_ui_about.lua). Kept
-- between game launches.
local cvSpeed  = CreateClientConVar("speditor_cam_speed", "400", true, false)        -- keyboard flight, units/s
local cvWheel  = CreateClientConVar("speditor_cam_wheel", "1", true, false)          -- wheel step multiplier
local cvSmooth = CreateClientConVar("speditor_cam_wheel_smooth", "0.85", true, false) -- 0 — abrupt, 1 — very smooth
local cvFOV    = CreateClientConVar("speditor_cam_fov", "75", true, false)

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
hook.Add("Think", "SPeditor.ViewPos", function()
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

hook.Add("CalcView", "SPeditor.CalcView", function()
	if not C.active then return end
	local pos, ang, fov = C.GetView()
	-- "engine frame": the main game frame is shot by the camera chosen in the Render window
	local R = SPeditor.Render
	if R and R.EngineView then
		local p, a, f = R.EngineView()
		if p then pos, ang, fov = p, a, f end
	end
	return { origin = pos, angles = ang, fov = fov, drawviewer = false, znear = 4 }
end)

-- The main game frame is not needed in the editor: windows cover it entirely and the
-- viewports draw the scene. Without this hook the engine drew the scene once more, full screen.
-- Returning true cancels drawing of the world and the HUD; the interface (VGUI) is drawn as usual.
-- The exception is the "engine frame" (cl_render.lua): in that frame the engine draws the
-- scene, with all addon shaders, and the editor takes it from the screen.
hook.Add("RenderScene", "SPeditor.SkipMainScene", function()
	if not C.active then return end
	local R = SPeditor.Render
	if R and R.BeginEngineFrame and R.BeginEngineFrame() then return end
	local bg = SPeditor.UI and SPeditor.UI.PAL and SPeditor.UI.PAL.BORDER
	render.Clear(bg and bg.r or 34, bg and bg.g or 32, bg and bg.b or 33, 255, true, true)
	return true
end)

hook.Add("CreateMove", "SPeditor.CreateMove", function(cmd)
	if not C.active then return end
	cmd:ClearMovement()
	cmd:ClearButtons()
	cmd:SetImpulse(0)
end)

hook.Add("InputMouseApply", "SPeditor.MouseLook", function(_, x, y)
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

hook.Add("Think", "SPeditor.CameraUpdate", function()
	if not C.active then
		C.camMode = nil
		return
	end
	local cam = C.camera
	if not cam.init then return end
	local dt = math.min(RealFrameTime(), 0.05)
	if cam.viewEnt ~= nil and not IsValid(cam.viewEnt) then C.StopViewCamera() end

	local m = C.camMode
	-- FIXED: navigation only inside the Primary Viewport
	if not m and not C.exporting and C.MouseInViewport() then
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
		local ep, ea = cam.viewEnt:GetPos(), cam.viewEnt:GetAngles()
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
hook.Add("PlayerBindPress", "SPeditor.Wheel", function(_, bind, pressed)
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
-- draw it dozens of times). The time comes from a mod that has one (SAeditor: the
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
	local pos, ang = ent:GetPos(), ent:GetAngles()
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
	"speditor_exposure", "speditor_aspect", "speditor_render_side", "speditor_render_custom",
	"speditor_render_w", "speditor_render_h", "speditor_render_fullbright", "speditor_render_ss",
	"speditor_dof", "speditor_dof_aperture", "speditor_dof_samples",
}

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
	}) or ""
end

hook.Add("SPeditor_SceneLoaded", "SPeditor.CameraMeta", function(meta)
	C.StopViewCamera()
	C.Select(nil)
	local data = util.JSONToTable(meta or "")
	if type(data) ~= "table" then return end
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
	if type(data.frame) == "table" then
		for _, name in ipairs(FRAME_CVARS) do
			local v = data.frame[name]
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
		local sum, n = Vector(0, 0, 0), 0
		for b = 0, ent:GetBoneCount() - 1 do
			if C.PhysIndexOfBone(ent, b) then
				local p = C.GetBoneWorld(ent, b)
				if p then sum = sum + p n = n + 1 end
			end
		end
		if n > 0 then return sum / n end
	end
	if C.IsAux(ent) then return ent:GetPos() end
	return ent:LocalToWorld(ent:OBBCenter())
end
