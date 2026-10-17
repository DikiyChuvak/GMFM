--[[
SAeditor — the player (a0.6): "Watch in the game" shows the animation full screen with the
controls of Windows Media Player (Windows 7, "Now Playing"): a glossy black bar at the bottom
over the picture, a round play / pause button in its middle, stop and the previous / next shot
beside it, a thin seek bar above it, the time and repeat on the left, the volume on the right.
The bar and the cursor hide when the mouse rests during playback and come back when it moves.
The cameras change as the animation's camera cuts say (cl_saeditor_cuts.lua); a click on the
camera name at the top picks another camera. The icons are the game's own (silkicons).

The render look (the button beside repeat, saeditor_show_look): the player shows the animation
as the render will make it — the frame proportions of the Render window (black bars around),
camera effects, exposure, fullbright, depth of field and soft shadows, the "engine frame" mode —
before anything is written to a video. While it plays, depth of field and soft shadows take at
most LOOK_PASSES passes a frame; on pause the frame is shot with all of them.

Keys: Space — play / pause, ← → — 5 seconds back / on, Home / End — the start / the end,
↑ ↓ — volume, M — mute, R — repeat, V — the render look, PgUp / PgDn — the previous / next shot,
Backspace — leave the player.
]]
local COMP = SPeditor.Component("saeditor")
local SA  = COMP.SA
local C   = SPeditor.Client
local L   = SPeditor.L

local BAR_H, SEEK_H = 70, 14
local HIDE_AFTER = 2.5             -- seconds of a resting mouse before the bar hides (while playing)
local ORB = 26                     -- radius of the play button
local LOOK_PASSES = 6              -- depth of field / soft shadow passes a frame while playing

local cvLook = CreateClientConVar("saeditor_show_look", "0", true, false,
	"Player: show the animation as the render makes it (frame proportions, camera effects, depth of field)", 0, 1)

local icons = {}
local function icon(name)
	icons[name] = icons[name] or Material("icon16/" .. name .. ".png")
	return icons[name]
end
local matGrad = Material("vgui/gradient-u")
local matGradD = Material("vgui/gradient-d")

surface.CreateFont("SAeditor.PlayerTime", { font = "Segoe UI", size = 15, weight = 500, antialias = true, extended = true })
surface.CreateFont("SAeditor.PlayerTitle", { font = "Segoe UI", size = 17, weight = 600, antialias = true, extended = true })

local function clock(frame)
	local s = math.max(frame, 0) / math.max(SA.fps, 1)
	return string.format("%02d:%02d", math.floor(s / 60), math.floor(s % 60))
end

local function circle(x, y, r, col)
	draw.NoTexture()
	surface.SetDrawColor(col)
	local poly = {}
	for i = 0, 31 do
		local a = i / 32 * math.pi * 2
		poly[#poly + 1] = { x = x + math.cos(a) * r, y = y + math.sin(a) * r }
	end
	surface.DrawPoly(poly)
end

local function drawIcon(name, x, y, size, alpha)
	surface.SetDrawColor(255, 255, 255, alpha or 255)
	surface.SetMaterial(icon(name))
	surface.DrawTexturedRect(math.floor(x - size / 2), math.floor(y - size / 2), size, size)
end

-- the shots: the frame each camera cut starts at (frame 0 too)
local function shotStarts()
	local out = { 0 }
	for _, c in ipairs(SA.cuts) do
		if c.f > 0 then out[#out + 1] = c.f end
	end
	return out
end

local function prevShot()
	local f = SA.frame
	local starts = shotStarts()
	local target = 0
	-- a second into a shot "previous" goes back to its start, as in a player
	for i = #starts, 1, -1 do
		if starts[i] < f - SA.fps * 1 then target = starts[i] break end
	end
	if #starts == 1 then target = math.max(f - SA.fps * 5, 0) end
	SA.ShowSeek(target)
end

local function nextShot()
	local f = SA.frame
	if #SA.cuts == 0 then SA.ShowSeek(math.min(f + SA.fps * 5, SA.frames)) return end
	for _, s in ipairs(shotStarts()) do
		if s > f + 0.5 then SA.ShowSeek(s) return end
	end
	SA.ShowSeek(SA.frames)
end

local function setVolume(v)
	local sh = SA.show
	if not sh then return end
	sh.vol = math.Clamp(v, 0, 1)
	sh.mute = false
	SA.showVolume = sh.vol
end

local function toggleLook() RunConsoleCommand("saeditor_show_look", cvLook:GetBool() and "0" or "1") end

-- the camera menu (a click on the camera name)
local function cameraMenu()
	local m = DermaMenu()
	SA.CameraChoices(function(v, label, iconPath)
		local cur = (v == "cuts" and SA.show.cuts) or (v ~= "cuts" and not SA.show.cuts and SA.show.cam == v)
		local o = m:AddOption(label, function() SA.ShowSetCamera(v) end)
		o:SetIcon(iconPath)
		if cur then o:SetChecked(true) end
	end)
	m:Open()
end

---------------------------------------------------------------------
-- The render look
---------------------------------------------------------------------
SA.look = SA.look or {}      -- { rt, aspect, frame, t } the last frame shot
local look = SA.look

function SA.ShowLookOn()
	local sh = SA.show
	return (sh and not sh.walk and cvLook:GetBool() and IsValid(SA.ShowCamera())) and true or false
end

-- the frame size on screen: the render's proportions fitted into the screen, never more pixels
-- than the render itself has
local function lookSize()
	local W, H = C.GetRenderSize()
	local aspect = W / H
	local _, _, iw, ih = C.FitRect(ScrW(), ScrH(), aspect)
	local k = math.min(1, W / iw)
	return math.max(math.floor(iw * k), 16), math.max(math.floor(ih * k), 16), aspect
end

-- the view of the camera for the main game frame: the field of view of a camera is horizontal
-- for the frame proportions, the one of the main view is set for 4:3 and widened by the engine
-- (as R.EngineView in cl_render.lua)
function SA.ShowView(cam)
	local R, FX = SPeditor.Render, SPeditor.FX
	local src = SPeditor.Export.Source(cam)
	if not src then return nil end
	local screen = ScrW() / ScrH()
	local aspect = screen
	if SA.ShowLookOn() then
		local W, H = C.GetRenderSize()
		aspect = W / H
		-- lens effects need a wider shot (R.FXSource)
		src = R.FXSource(src, FX and FX.For(src.ent) or nil)
	end
	local t = math.tan(math.rad(math.Clamp(src.fov, 1, 170)) / 2) / (0.75 * math.min(aspect, screen))
	return src.origin, src.angles, math.Clamp(math.deg(2 * math.atan(t)), 1, 175)
end

-- shooting the frame with the render settings (not the engine frame): instead of the game frame
local function shootLook(cam)
	local R, FX = SPeditor.Render, SPeditor.FX
	local pw, ph, aspect = lookSize()
	-- on pause one full frame is shot and kept
	if not SA.playing and look.rt and look.frame == SA.frame and look.cam == cam and look.w == pw
		and RealTime() - (look.t or 0) < 1 then return end
	local src = SPeditor.Export.Source(cam)
	local fx = FX and FX.For(src.ent) or nil
	local opts = { fullbright = GetConVar("speditor_render_fullbright"):GetBool(), aspect = aspect }
	local passes = SA.playing and LOOK_PASSES or nil
	if not SA.playing and GetConVar("speditor_render_ss"):GetBool() then opts.ss = 2 end
	if GetConVar("speditor_dof"):GetBool() then
		opts.dof = { aperture = math.Clamp(GetConVar("speditor_dof_aperture"):GetFloat(), 0.05, 20),
			samples = math.Clamp(GetConVar("speditor_dof_samples"):GetInt(), 2, 128), focus = SPeditor.Export.FocusDistance(src) }
	end
	local own = FX and FX.DOF(fx)
	if own then opts.dof = table.Copy(own) end
	if opts.dof and passes then opts.dof.samples = math.min(opts.dof.samples or 32, passes) end
	opts.softMax = passes
	local prevHide, prevExp = C.hideUI, C.exporting
	C.hideUI, C.exporting = true, true
	local ok, rt = pcall(R.RenderBase, R.FXSource(src, fx), pw, ph, opts)
	C.hideUI, C.exporting = prevHide, prevExp
	if not ok then
		ErrorNoHalt("[SAeditor] player render look: " .. tostring(rt) .. "\n")
		look.rt = nil
		return
	end
	look.rt = R.ApplyFX(rt, fx, pw, ph, aspect)
	look.aspect, look.frame, look.cam, look.w, look.t = aspect, SA.frame, cam, pw, RealTime()
end

COMP:Hook("RenderScene", function()
	if not SA.ShowLookOn() then look.rt = nil return end
	local R = SPeditor.Render
	local cam = SA.ShowCamera()
	if R.EngineMode() then
		-- the engine draws the frame (with addon shaders); PostRender takes it from the screen
		local exposure = R.CameraExposure(cam)
		if exposure > 0 then render.ResetToneMappingScale(exposure) end
		look.engine = true
		if GetConVar("speditor_render_fullbright"):GetBool() then
			look.fullbright = true
			render.SetLightingMode(1)
		end
		return
	end
	look.engine = nil
	shootLook(cam)
	render.Clear(0, 0, 0, 255, true, true)
	return true
end, "player_look")

COMP:Hook("PostRender", function()
	if not look.engine then return end
	look.engine = nil
	if look.fullbright then
		look.fullbright = nil
		render.SetLightingMode(0)
	end
	if not SA.ShowLookOn() then return end
	local R, FX = SPeditor.Render, SPeditor.FX
	local ok, err = pcall(function()
		local sw, sh = ScrW(), ScrH()
		local pw, ph, aspect = lookSize()
		local scr = R.GetRT("sa_look_scr_" .. sw .. "x" .. sh, sw, sh)
		render.CopyRenderTargetToTexture(scr)
		local rt = R.CropToRT(scr, sw, sh, pw, ph, aspect, "sa_look_")
		local cam = SA.ShowCamera()
		look.rt = R.ApplyFX(rt, FX and FX.For(cam) or nil, pw, ph, aspect)
		look.aspect, look.frame, look.cam, look.w, look.t = aspect, SA.frame, cam, pw, RealTime()
	end)
	if not ok then
		look.rt = nil
		ErrorNoHalt("[SAeditor] player render look: " .. tostring(err) .. "\n")
	end
end, "player_look")

local function toggleLoop()
	local on = not GetConVar("saeditor_show_loop"):GetBool()
	RunConsoleCommand("saeditor_show_loop", on and "1" or "0")
	-- the server needs the new setting too: it is sent with the next action
	timer.Simple(0, function() if SA.show then SA.ShowSend(4, SA.frame) end end)
end

---------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------
function SA.OpenPlayer()
	if IsValid(SA.player) then SA.player:Remove() end
	local p = vgui.Create("DPanel")
	SA.player = p
	p:SetSize(ScrW(), ScrH())
	p:SetPos(0, 0)
	p:MakePopup()
	p:SetKeyboardInputEnabled(true)
	p.lastMove, p.alpha, p.mx, p.my = RealTime(), 1, -1, -1
	local btns = {}      -- { x, y, r, fn, tip } the hit areas of the frame being drawn

	local function addBtn(x, y, r, fn, tip) btns[#btns + 1] = { x = x, y = y, r = r, fn = fn, tip = tip } end

	p.Think = function(s)
		if not SA.show then s:Remove() return end
		local mx, my = gui.MousePos()
		if mx ~= s.mx or my ~= s.my or s.dragSeek or s.dragVol then
			s.mx, s.my = mx, my
			s.lastMove = RealTime()
		end
		local show = not SA.playing or RealTime() - s.lastMove < HIDE_AFTER or my > ScrH() - BAR_H - SEEK_H - 20
		s.alpha = math.Approach(s.alpha, show and 1 or 0, FrameTime() * 4)
		s:SetCursor(s.alpha > 0.05 and "arrow" or "blank")
		-- dragging the seek bar / the volume
		local W, H = s:GetSize()
		if s.dragSeek then
			local f = math.Clamp((mx - 12) / (W - 24), 0, 1) * SA.frames
			if math.abs(f - SA.frame) > 0.4 and RealTime() > (s.nextSeek or 0) then
				s.nextSeek = RealTime() + 0.05
				SA.ShowSeek(f)
			end
		end
		if s.dragVol then
			local v = s.dragVol
			setVolume((mx - v.x) / v.w)
		end
	end

	p.Paint = function(s, W, H)
		btns = {}
		-- the render look: the shot frame over the game frame, black bars around it
		if SA.ShowLookOn() and look.rt then
			surface.SetDrawColor(0, 0, 0, 255)
			surface.DrawRect(0, 0, W, H)
			local ix, iy, iw, ih = C.FitRect(W, H, look.aspect)
			SPeditor.Render.DrawRT(look.rt, math.floor(ix), math.floor(iy), math.floor(iw), math.floor(ih))
		end
		local a = s.alpha
		local sh = SA.show
		if not sh or a <= 0.01 then return end
		local A = function(v) return math.floor(v * a) end

		-- the title at the top: the scene and the camera
		surface.SetMaterial(matGradD)
		surface.SetDrawColor(0, 0, 0, A(200))
		surface.DrawTexturedRect(0, 0, W, 56)
		local cam = SA.ShowCamera()
		local title = (C.sceneName and C.sceneName ~= "") and C.sceneName or L("sa_pl_untitled")
		draw.SimpleText(title, "SAeditor.PlayerTitle", 16, 16, Color(255, 255, 255, A(255)), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		-- the camera: a click picks another one
		local camText = IsValid(cam) and (L("sa_pl_camera") .. ": " .. C.DisplayName(cam) .. (sh.cuts and ("  (" .. L("sa_show_cuts") .. ")") or ""))
			or L("sa_pl_eyes")
		surface.SetFont("SAeditor.PlayerTime")
		local ctw = surface.GetTextSize(camText) + 18
		local hotCam = s.mx >= 10 and s.mx <= 16 + ctw and s.my >= 27 and s.my <= 45
		if hotCam then draw.RoundedBox(3, 10, 27, ctw + 6, 18, Color(90, 130, 190, A(110))) end
		draw.SimpleText(camText, "SAeditor.PlayerTime", 16, 36, Color(190, 210, 235, A(230)), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		drawIcon("bullet_arrow_down", 16 + ctw - 8, 36, 16, A(230))
		if hotCam then
			draw.SimpleTextOutlined(L("sa_pl_pick_cam"), "SAeditor.PlayerTime", 16 + ctw + 12, 36, Color(255, 255, 255, A(255)), TEXT_ALIGN_LEFT,
				TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, A(220)))
		end
		s.camArea = { x0 = 10, x1 = 16 + ctw, y0 = 27, y1 = 45 }
		-- leave (top right)
		local ex, ey = W - 24, 22
		local hot = (s.mx - ex) ^ 2 + (s.my - ey) ^ 2 < 14 ^ 2
		circle(ex, ey, 13, hot and Color(200, 60, 50, A(230)) or Color(40, 40, 40, A(180)))
		drawIcon("cross", ex, ey, 16, A(255))
		addBtn(ex, ey, 14, function() SA.StopShow() end, L("sa_pl_exit"))

		-- the bar: black glass, lighter at the top edge
		local by = H - BAR_H
		surface.SetDrawColor(10, 12, 16, A(225))
		surface.DrawRect(0, by, W, BAR_H)
		surface.SetMaterial(matGrad)
		surface.SetDrawColor(120, 140, 170, A(70))
		surface.DrawTexturedRect(0, by, W, BAR_H / 2)
		surface.SetDrawColor(150, 170, 200, A(90))
		surface.DrawRect(0, by, W, 1)

		-- the seek bar above it
		local sy = by - SEEK_H / 2
		local sx0, sx1 = 12, W - 12
		local u = SA.frames > 0 and math.Clamp(SA.frame / SA.frames, 0, 1) or 0
		local hotSeek = s.my >= sy - 8 and s.my <= sy + 8 and s.mx >= sx0 - 4 and s.mx <= sx1 + 4
		local th = (hotSeek or s.dragSeek) and 6 or 4
		surface.SetDrawColor(40, 44, 52, A(230))
		surface.DrawRect(sx0, sy - th / 2, sx1 - sx0, th)
		surface.SetDrawColor(60, 140, 230, A(255))
		surface.DrawRect(sx0, sy - th / 2, (sx1 - sx0) * u, th)
		surface.SetDrawColor(160, 210, 255, A(160))
		surface.DrawRect(sx0, sy - th / 2, (sx1 - sx0) * u, 1)
		-- the shots as ticks on it
		for _, f in ipairs(shotStarts()) do
			if f > 0 then
				surface.SetDrawColor(255, 255, 255, A(140))
				surface.DrawRect(sx0 + (sx1 - sx0) * f / math.max(SA.frames, 1), sy - th / 2 - 2, 1, th + 4)
			end
		end
		if hotSeek or s.dragSeek then
			circle(sx0 + (sx1 - sx0) * u, sy, 7, Color(220, 235, 255, A(255)))
			local hf = math.Clamp((s.mx - sx0) / (sx1 - sx0), 0, 1) * SA.frames
			draw.SimpleTextOutlined(clock(hf), "SAeditor.PlayerTime", s.mx, sy - 16, Color(255, 255, 255, A(255)), TEXT_ALIGN_CENTER,
				TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, A(200)))
		end
		s.seekArea = { x0 = sx0, x1 = sx1, y = sy }

		-- the middle: stop, previous, PLAY, next
		local cx, cy = W / 2, by + BAR_H / 2 + 2
		-- the small buttons: dark glass circles with a light rim, lit up under the cursor
		local function small(x, name, fn, tip)
			local hotB = (s.mx - x) ^ 2 + (s.my - cy) ^ 2 < 17 ^ 2
			circle(x, cy, 17, Color(150, 170, 200, A(hotB and 160 or 70)))
			circle(x, cy, 16, hotB and Color(40, 90, 160, A(240)) or Color(18, 22, 30, A(240)))
			drawIcon(name, x, cy, 20, A(255))
			addBtn(x, cy, 17, fn, tip)
		end
		small(cx - 110, "control_stop_blue", function()
			SA.ShowPause(true)
			SA.ShowSeek(0)
		end, L("sa_pl_stop"))
		small(cx - 66, "control_start_blue", prevShot, L("sa_pl_prev"))
		small(cx + 66, "control_end_blue", nextShot, L("sa_pl_next"))
		-- the orb: dark blue glass with a light top
		local hotOrb = (s.mx - cx) ^ 2 + (s.my - cy) ^ 2 < ORB ^ 2
		circle(cx, cy, ORB + 2, Color(0, 0, 0, A(200)))
		circle(cx, cy, ORB, hotOrb and Color(40, 110, 200, A(255)) or Color(22, 70, 140, A(255)))
		circle(cx, cy + 4, ORB - 6, Color(10, 40, 90, A(160)))
		surface.SetDrawColor(255, 255, 255, A(55))
		draw.NoTexture()
		local gloss = {}
		for i = 0, 16 do
			local ang = math.pi + i / 16 * math.pi
			gloss[#gloss + 1] = { x = cx + math.cos(ang) * (ORB - 3), y = cy - 2 + math.sin(ang) * (ORB - 5) }
		end
		surface.DrawPoly(gloss)
		drawIcon(SA.playing and "control_pause" or "control_play", cx, cy, 28, A(255))
		addBtn(cx, cy, ORB, function() SA.ShowPause(SA.playing) end, L(SA.playing and "sa_pl_pause" or "sa_pl_play"))

		-- left: time and repeat
		draw.SimpleText(clock(SA.frame) .. " / " .. clock(SA.frames), "SAeditor.PlayerTime", 16, cy, Color(220, 230, 245, A(255)),
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local loop = GetConVar("saeditor_show_loop"):GetBool()
		local lx = 140
		local hotL = (s.mx - lx) ^ 2 + (s.my - cy) ^ 2 < 14 ^ 2
		if loop or hotL then circle(lx, cy, 14, loop and Color(60, 140, 230, A(170)) or Color(90, 130, 190, A(110))) end
		drawIcon("arrow_refresh", lx, cy, 16, A(loop and 255 or 170))
		addBtn(lx, cy, 14, toggleLoop, L(loop and "sa_pl_loop_on" or "sa_pl_loop_off"))
		-- the render look, beside repeat
		local lookOn = cvLook:GetBool()
		local kx = lx + 32
		local hotK = (s.mx - kx) ^ 2 + (s.my - cy) ^ 2 < 14 ^ 2
		if lookOn or hotK then circle(kx, cy, 14, lookOn and Color(60, 140, 230, A(170)) or Color(90, 130, 190, A(110))) end
		drawIcon("photo", kx, cy, 16, A(lookOn and 255 or 170))
		local lookTip = L(lookOn and "sa_pl_look_on" or "sa_pl_look_off")
		if lookOn and not IsValid(cam) then lookTip = L("sa_pl_look_nocam") end
		addBtn(kx, cy, 14, toggleLook, lookTip)

		-- right: mute and volume
		local vol = sh.mute and 0 or (sh.vol or 1)
		local vx, vw = W - 140, 90
		local mx0 = vx - 22
		local hotM = (s.mx - mx0) ^ 2 + (s.my - cy) ^ 2 < 13 ^ 2
		if hotM then circle(mx0, cy, 13, Color(90, 130, 190, A(110))) end
		drawIcon(vol <= 0 and "sound_mute" or (vol < 0.5 and "sound_low" or "sound"), mx0, cy, 16, A(255))
		addBtn(mx0, cy, 13, function() sh.mute = not sh.mute end, L("sa_pl_mute"))
		surface.SetDrawColor(40, 44, 52, A(230))
		surface.DrawRect(vx, cy - 2, vw, 4)
		surface.SetDrawColor(60, 140, 230, A(255))
		surface.DrawRect(vx, cy - 2, vw * vol, 4)
		circle(vx + vw * vol, cy, 6, Color(220, 235, 255, A(255)))
		s.volArea = { x = vx, w = vw, y = cy }

		-- the tooltip of the button under the cursor
		for _, b in ipairs(btns) do
			if (s.mx - b.x) ^ 2 + (s.my - b.y) ^ 2 < b.r ^ 2 and b.tip then
				draw.SimpleTextOutlined(b.tip, "SAeditor.PlayerTime", b.x, b.y - b.r - 10, Color(255, 255, 255, A(255)), TEXT_ALIGN_CENTER,
					TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, A(220)))
			end
		end
	end

	p.OnMousePressed = function(s, code)
		s.lastMove = RealTime()
		if code ~= MOUSE_LEFT then return end
		local mx, my = gui.MousePos()
		if s.alpha < 0.3 then
			-- a click on the picture with the bar hidden: pause / play, as in the player
			SA.ShowPause(SA.playing)
			return
		end
		for _, b in ipairs(btns) do
			if (mx - b.x) ^ 2 + (my - b.y) ^ 2 < b.r ^ 2 then b.fn() return end
		end
		local ca = s.camArea
		if ca and mx >= ca.x0 and mx <= ca.x1 and my >= ca.y0 and my <= ca.y1 then cameraMenu() return end
		local sa = s.seekArea
		if sa and math.abs(my - sa.y) <= 8 and mx >= sa.x0 - 4 and mx <= sa.x1 + 4 then
			s.dragSeek = true
			s:MouseCapture(true)
			SA.ShowSeek(math.Clamp((mx - sa.x0) / (sa.x1 - sa.x0), 0, 1) * SA.frames)
			return
		end
		local va = s.volArea
		if va and math.abs(my - va.y) <= 8 and mx >= va.x - 6 and mx <= va.x + va.w + 6 then
			s.dragVol = va
			s:MouseCapture(true)
			setVolume((mx - va.x) / va.w)
			return
		end
		-- a click on the picture itself
		if my < ScrH() - BAR_H - SEEK_H - 10 and my > 60 then SA.ShowPause(SA.playing) end
	end

	p.OnMouseReleased = function(s)
		s.dragSeek, s.dragVol = nil, nil
		s:MouseCapture(false)
	end

	p.OnKeyCodePressed = function(s, key)
		s.lastMove = RealTime()
		if key == KEY_SPACE then SA.ShowPause(SA.playing)
		elseif key == KEY_LEFT then SA.ShowSeek(SA.frame - SA.fps * 5)
		elseif key == KEY_RIGHT then SA.ShowSeek(SA.frame + SA.fps * 5)
		elseif key == KEY_HOME then SA.ShowSeek(0)
		elseif key == KEY_END then SA.ShowSeek(SA.frames)
		elseif key == KEY_UP then setVolume((SA.show.vol or 1) + 0.1)
		elseif key == KEY_DOWN then setVolume((SA.show.vol or 1) - 0.1)
		elseif key == KEY_M then SA.show.mute = not SA.show.mute
		elseif key == KEY_R then toggleLoop()
		elseif key == KEY_V then toggleLook()
		elseif key == KEY_PAGEUP then prevShot()
		elseif key == KEY_PAGEDOWN then nextShot()
		elseif key == KEY_BACKSPACE then SA.StopShow()
		end
	end
	return p
end

COMP:Hook("SPeditor_StateChanged", function(on)
	if on and IsValid(SA.player) then SA.player:Remove() end
end, "player")
