--[[
SAeditor — the player (a0.6): "Watch in the game" shows the animation full screen with the
controls of Windows Media Player (11 / 12, "Now Playing"; b0.2 made it look like it): a dark
glass bar at the bottom with a thin blue seek bar across its top, and in its middle a glossy
capsule with repeat and the render look, stop, the previous / next shot on a joined lozenge
and the big blue glass play / pause orb standing out of it, the speaker and the volume. The
scene and the time are on the left, the camera list and "leave" on the right; the scene's
name and the camera are written big over the picture at the top left, as the title and the
artist of a song. The bar and the cursor hide when the mouse rests during playback and come
back when it moves. The cameras change as the animation's camera cuts say
(cl_saeditor_cuts.lua); a click on the camera name at the top picks another camera.
The pictures (materials/speditor/player) are drawn by tools/make_player_skin.py.

The render look (the button beside repeat, gmfm_show_look): the player shows the animation
as the render will make it — the frame proportions of the Render window (black bars around),
camera effects, exposure, fullbright, depth of field and soft shadows, the "engine frame" mode —
before anything is written to a video. While it plays, soft shadows take at most LOOK_PASSES
passes a frame and depth of field is left out (a few passes of it are ghosts, not a blur); on
pause the frame is shot with all of them.

Keys: Space — play / pause, ← → — 5 seconds back / on, Home / End — the start / the end,
↑ ↓ — volume, M — mute, R — repeat, V — the render look, PgUp / PgDn — the previous / next shot,
Backspace — leave the player.
]]
local COMP = SPeditor.Component("saeditor")
local SA  = COMP.SA
local C   = SPeditor.Client
local L   = SPeditor.L

local BAR_H = 92                   -- the bar at 1080 pixels of screen height (scaled with the screen)
local HIDE_AFTER = 2.5             -- seconds of a resting mouse before the bar hides (while playing)
local ORB = 30                     -- radius of the play orb at 1080 pixels
local LOOK_PASSES = 6              -- soft shadow passes a frame while playing (no depth of field then)

local cvLook = CreateClientConVar("gmfm_show_look", "0", true, false,
	"Player: show the animation as the render makes it (frame proportions, camera effects, depth of field)", 0, 1)

local matGrad = Material("vgui/gradient-u")
local matGradD = Material("vgui/gradient-d")

-- the pictures of the WMP look
local skin = {}
local function pic(name)
	skin[name] = skin[name] or Material("speditor/player/" .. name .. ".png", "smooth")
	return skin[name]
end

-- everything is laid out for a 1080-pixel screen and scaled with it
local K = 1
local function fonts()
	K = math.Clamp(ScrH() / 1080, 0.7, 2.2)
	local function f(name, size, weight)
		surface.CreateFont(name, { font = "Segoe UI", size = math.floor(size * K + 0.5), weight = weight, antialias = true, extended = true })
	end
	f("SAeditor.PlayerTime", 15, 500)
	f("SAeditor.PlayerTitle", 34, 300)
	f("SAeditor.PlayerSub", 19, 400)
	f("SAeditor.PlayerSmall", 14, 400)
end
fonts()

local function clock(frame)
	local s = math.max(frame, 0) / math.max(SA.fps, 1)
	return string.format("%02d:%02d", math.floor(s / 60), math.floor(s % 60))
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

local function toggleLook() RunConsoleCommand("gmfm_show_look", cvLook:GetBool() and "0" or "1") end

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
	-- on pause the full frame is built over several game frames (LOOK_PASSES passes each) and kept
	local still = not SA.playing and look.rt and look.frame == SA.frame and look.cam == cam and look.w == pw
	if still and look.prog and look.prog.done then return end
	if not still or not look.prog then look.prog = { key = "sa_look", step = LOOK_PASSES } end
	local src = SPeditor.Export.Source(cam)
	local fx = FX and FX.For(src.ent) or nil
	local opts = { fullbright = GetConVar("gmfm_render_fullbright"):GetBool(), aspect = aspect }
	local passes = SA.playing and LOOK_PASSES or nil
	if passes then look.prog = nil end
	if not SA.playing and GetConVar("gmfm_render_ss"):GetBool() then opts.ss = 2 end
	-- No depth of field in an animation (a0.9): while playing a few passes were sharp copies of
	-- the frame side by side (the "ghosts" of the test_machinima report), and the pause smeared
	-- the whole picture. The frames of the video are rendered without it as well.
	opts.softMax = passes
	opts.progress = not passes and look.prog or nil
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
	if R.EngineFor(GetConVar("gmfm_render_fullbright"):GetBool()) then
		-- the engine draws the frame (with addon shaders); PostRender takes it from the screen
		local exposure = R.CameraExposure(cam)
		if exposure > 0 then render.ResetToneMappingScale(exposure) end
		look.engine = true
		if GetConVar("gmfm_render_fullbright"):GetBool() then
			look.fullbright = true
			render.SetLightingMode(1)
			R.Fullbright(true)
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
	local fullbright = look.fullbright
	if look.fullbright then
		look.fullbright = nil
		render.SetLightingMode(0)
		SPeditor.Render.Fullbright(false)
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
		local fx = FX and FX.For(cam) or nil
		-- the editor's ambient occlusion, as over the engine frame of a render (R.EngineToRT): the
		-- player went without it, so SSAO showed in the editor and the video but not here
		local src = SPeditor.Export.Source(cam)
		if src and R.ApplySSAO and not fullbright then R.ApplySSAO(rt, R.FXSource(src, fx), pw, ph, aspect) end
		look.rt = R.ApplyFX(rt, fx, pw, ph, aspect)
		look.aspect, look.frame, look.cam, look.w, look.t = aspect, SA.frame, cam, pw, RealTime()
	end)
	if not ok then
		look.rt = nil
		ErrorNoHalt("[SAeditor] player render look: " .. tostring(err) .. "\n")
	end
end, "player_look")

local function toggleLoop()
	local on = not GetConVar("gmfm_show_loop"):GetBool()
	RunConsoleCommand("gmfm_show_loop", on and "1" or "0")
	-- the server needs the new setting too: it is sent with the next action
	timer.Simple(0, function() if SA.show then SA.ShowSend(4, SA.frame) end end)
end

---------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------
function SA.OpenPlayer()
	if IsValid(SA.player) then SA.player:Remove() end
	fonts()
	local p = vgui.Create("DPanel")
	SA.player = p
	p:SetSize(ScrW(), ScrH())
	p:SetPos(0, 0)
	p:MakePopup()
	p:SetKeyboardInputEnabled(true)
	p.lastMove, p.alpha, p.mx, p.my = RealTime(), 1, -1, -1
	local btns = {}      -- { x, y, r, fn, tip } the hit areas of the frame being drawn

	local function addBtn(x, y, r, fn, tip) btns[#btns + 1] = { x = x, y = y, r = r, fn = fn, tip = tip } end
	local function barH() return math.floor(BAR_H * K) end

	p.Think = function(s)
		if not SA.show then s:Remove() return end
		local mx, my = gui.MousePos()
		if mx ~= s.mx or my ~= s.my or s.dragSeek or s.dragVol then
			s.mx, s.my = mx, my
			s.lastMove = RealTime()
		end
		local show = not SA.playing or RealTime() - s.lastMove < HIDE_AFTER or my > ScrH() - barH() - 20
		s.alpha = math.Approach(s.alpha, show and 1 or 0, FrameTime() * 4)
		s:SetCursor(s.alpha > 0.05 and "arrow" or "blank")
		-- dragging the seek bar / the volume
		local sa = s.seekArea
		if s.dragSeek and sa then
			local f = math.Clamp((mx - sa.x0) / (sa.x1 - sa.x0), 0, 1) * SA.frames
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

	-- a picture centred on x, y, size w x h
	local function pdraw(name, x, y, w, h, alpha)
		surface.SetMaterial(pic(name))
		surface.SetDrawColor(255, 255, 255, alpha or 255)
		surface.DrawTexturedRect(math.floor(x - w / 2 + 0.5), math.floor(y - h / 2 + 0.5), math.floor(w + 0.5), math.floor(h + 0.5))
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
		local function hotAt(x, y, r) return (s.mx - x) ^ 2 + (s.my - y) ^ 2 < r ^ 2 end

		-- a glyph button: a soft blue glow under the cursor (and when switched on), as in WMP
		local function glyphBtn(x, y, name, size, fn, tip, on)
			local r = size * 0.62
			local hot = hotAt(x, y, r)
			if hot or on then pdraw("glow", x, y, size * 2.2, size * 2.2, A(hot and 200 or 120)) end
			pdraw("g_" .. name, x, y, size, size, A((hot or on) and 255 or 215))
			addBtn(x, y, r, fn, tip)
			return hot
		end

		-- the title over the picture (top left): the scene big, the camera under it
		surface.SetMaterial(matGradD)
		surface.SetDrawColor(0, 0, 0, A(150))
		surface.DrawTexturedRect(0, 0, W, math.floor(110 * K))
		local cam = SA.ShowCamera()
		local title = (C.sceneName and C.sceneName ~= "") and C.sceneName or L("sa_pl_untitled")
		local tx, ty = math.floor(34 * K), math.floor(24 * K)
		draw.SimpleText(title, "SAeditor.PlayerTitle", tx + 1, ty + 2, Color(0, 0, 0, A(140)), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		draw.SimpleText(title, "SAeditor.PlayerTitle", tx, ty, Color(255, 255, 255, A(255)), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		surface.SetFont("SAeditor.PlayerTitle")
		local _, th = surface.GetTextSize("Ay")
		-- the camera: a click picks another one
		local camText = IsValid(cam) and (L("sa_pl_camera") .. ": " .. C.DisplayName(cam) .. (sh.cuts and ("  (" .. L("sa_show_cuts") .. ")") or ""))
			or L("sa_pl_eyes")
		surface.SetFont("SAeditor.PlayerSub")
		local ctw, cth = surface.GetTextSize(camText)
		local cy0 = ty + th + math.floor(2 * K)
		local arrowW = math.floor(12 * K)
		local hotCam = s.mx >= tx - 4 and s.mx <= tx + ctw + arrowW + 8 and s.my >= cy0 and s.my <= cy0 + cth
		draw.SimpleText(camText, "SAeditor.PlayerSub", tx, cy0, hotCam and Color(255, 255, 255, A(255)) or Color(215, 225, 240, A(235)),
			TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		-- a small arrow down after it
		local ax, ay = tx + ctw + math.floor(6 * K), cy0 + cth / 2
		draw.NoTexture()
		surface.SetDrawColor(215, 225, 240, A(hotCam and 255 or 200))
		surface.DrawPoly({ { x = ax, y = ay - 3 * K }, { x = ax + 8 * K, y = ay - 3 * K }, { x = ax + 4 * K, y = ay + 2 * K } })
		if hotCam then
			surface.SetDrawColor(255, 255, 255, A(160))
			surface.DrawRect(tx, cy0 + cth, ctw, 1)
			draw.SimpleTextOutlined(L("sa_pl_pick_cam"), "SAeditor.PlayerSmall", ax + 14 * K, ay, Color(255, 255, 255, A(255)), TEXT_ALIGN_LEFT,
				TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, A(200)))
		end
		s.camArea = { x0 = tx - 4, x1 = tx + ctw + arrowW + 8, y0 = cy0, y1 = cy0 + cth }
		-- "Show List" of WMP at the top right: the list of cameras
		surface.SetFont("SAeditor.PlayerSub")
		local lt = L("sa_pl_cameras")
		local ltw = surface.GetTextSize(lt)
		local lx1 = W - math.floor(30 * K)
		local lx0 = lx1 - ltw - math.floor(30 * K)
		local ly = math.floor(36 * K)
		local hotList = s.mx >= lx0 - 6 and s.mx <= lx1 + 6 and math.abs(s.my - ly) < 14 * K
		if hotList then pdraw("glow", lx0 + 10 * K, ly, 50 * K, 50 * K, A(150)) end
		pdraw("g_list", lx0 + 10 * K, ly, 22 * K, 22 * K, A(hotList and 255 or 215))
		draw.SimpleText(lt, "SAeditor.PlayerSub", lx1, ly, Color(255, 255, 255, A(hotList and 255 or 220)), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		s.listArea = { x0 = lx0 - 6, x1 = lx1 + 6, y = ly, h = 14 * K }

		-- the bar: dark glass, a light line along its top edge
		local bh = barH()
		local by = H - bh
		surface.SetMaterial(matGradD)
		surface.SetDrawColor(0, 0, 0, A(120))
		surface.DrawTexturedRect(0, by - math.floor(40 * K), W, math.floor(40 * K))
		surface.SetDrawColor(6, 8, 12, A(252))
		surface.DrawRect(0, by, W, bh)
		surface.SetMaterial(matGrad)
		surface.SetDrawColor(60, 78, 110, A(120))
		surface.DrawTexturedRect(0, by, W, math.floor(bh * 0.55))
		surface.SetDrawColor(120, 150, 200, A(110))
		surface.DrawRect(0, by, W, 1)

		-- the seek bar across the top of the bar: a dark groove, a blue fill with a light edge
		local sx0, sx1 = math.floor(14 * K), W - math.floor(14 * K)
		local sy = by + math.floor(11 * K)
		local u = SA.frames > 0 and math.Clamp(SA.frame / SA.frames, 0, 1) or 0
		local hotSeek = s.my >= sy - 8 * K and s.my <= sy + 8 * K and s.mx >= sx0 - 4 and s.mx <= sx1 + 4
		local gh = math.max(math.floor(((hotSeek or s.dragSeek) and 6 or 4) * K), 3)
		local gy = math.floor(sy - gh / 2)
		surface.SetDrawColor(0, 0, 0, A(220))
		surface.DrawRect(sx0 - 1, gy - 1, sx1 - sx0 + 2, gh + 2)
		surface.SetDrawColor(42, 46, 56, A(255))
		surface.DrawRect(sx0, gy, sx1 - sx0, gh)
		local fw = math.floor((sx1 - sx0) * u)
		surface.SetMaterial(matGrad)
		surface.SetDrawColor(40, 120, 235, A(255))
		surface.DrawRect(sx0, gy, fw, gh)
		surface.SetDrawColor(150, 210, 255, A(200))
		surface.DrawTexturedRect(sx0, gy, fw, math.ceil(gh / 2))
		-- the shots as ticks on it
		for _, f in ipairs(shotStarts()) do
			if f > 0 then
				surface.SetDrawColor(255, 255, 255, A(150))
				surface.DrawRect(sx0 + (sx1 - sx0) * f / math.max(SA.frames, 1), gy - 2, 1, gh + 4)
			end
		end
		if hotSeek or s.dragSeek then
			pdraw("orb_hot", sx0 + fw, sy, 18 * K, 18 * K, A(255))
			local hf = math.Clamp((s.mx - sx0) / (sx1 - sx0), 0, 1) * SA.frames
			draw.SimpleTextOutlined(clock(hf), "SAeditor.PlayerTime", s.mx, gy - 6 * K, Color(255, 255, 255, A(255)), TEXT_ALIGN_CENTER,
				TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, A(200)))
		end
		s.seekArea = { x0 = sx0, x1 = sx1, y = sy, h = 8 * K }

		-- the capsule in the middle
		local cx, cy = math.floor(W / 2), by + math.floor(54 * K)
		local capW, capH = math.floor(560 * K), math.floor(44 * K)
		local capX, capY = cx - capW / 2, cy - capH / 2
		local endW = math.floor(24 * K)
		surface.SetDrawColor(255, 255, 255, A(255))
		surface.SetMaterial(pic("cap_l"))
		surface.DrawTexturedRect(capX, capY, endW, capH)
		surface.SetMaterial(pic("cap_m"))
		surface.DrawTexturedRect(capX + endW, capY, capW - endW * 2, capH)
		surface.SetMaterial(pic("cap_r"))
		surface.DrawTexturedRect(capX + capW - endW, capY, endW, capH)

		-- left in the capsule: repeat and the render look, a line, stop
		local loop = GetConVar("gmfm_show_loop"):GetBool()
		glyphBtn(cx - 236 * K, cy, "repeat", 22 * K, toggleLoop, L(loop and "sa_pl_loop_on" or "sa_pl_loop_off"), loop)
		local lookOn = cvLook:GetBool()
		local lookTip = L(lookOn and "sa_pl_look_on" or "sa_pl_look_off")
		if lookOn and not IsValid(cam) then lookTip = L("sa_pl_look_nocam") end
		glyphBtn(cx - 196 * K, cy, "look", 22 * K, toggleLook, lookTip, lookOn)
		surface.SetDrawColor(0, 0, 0, A(200))
		surface.DrawRect(cx - 170 * K, cy - 12 * K, 1, 24 * K)
		surface.SetDrawColor(110, 120, 140, A(90))
		surface.DrawRect(cx - 169 * K, cy - 12 * K, 1, 24 * K)
		glyphBtn(cx - 142 * K, cy, "stop", 22 * K, function()
			SA.ShowPause(true)
			SA.ShowSeek(0)
		end, L("sa_pl_stop"))

		-- the previous / next lozenge under the orb
		local pw, ph = 156 * K, 32 * K
		local hotPrev = s.mx >= cx - pw / 2 and s.mx < cx - ORB * K and math.abs(s.my - cy) < ph / 2
		local hotNext = s.mx <= cx + pw / 2 and s.mx > cx + ORB * K and math.abs(s.my - cy) < ph / 2
		pdraw(hotPrev and "pair_l" or (hotNext and "pair_r" or "pair"), cx, cy, pw, ph, A(255))
		pdraw("g_prev", cx - 56 * K, cy, 22 * K, 22 * K, A(hotPrev and 255 or 225))
		pdraw("g_next", cx + 56 * K, cy, 22 * K, 22 * K, A(hotNext and 255 or 225))
		addBtn(cx - 56 * K, cy, 20 * K, prevShot, L("sa_pl_prev"))
		addBtn(cx + 56 * K, cy, 20 * K, nextShot, L("sa_pl_next"))

		-- the orb: blue glass, standing out of the capsule; it glows under the cursor
		local R = ORB * K
		local hotOrb = hotAt(cx, cy, R)
		if hotOrb then pdraw("glow", cx, cy, R * 3.6, R * 3.6, A(220)) end
		pdraw(input.IsMouseDown(MOUSE_LEFT) and hotOrb and "orb_down" or (hotOrb and "orb_hot" or "orb"), cx, cy, R * 2.53, R * 2.53, A(255))
		pdraw(SA.playing and "g_pause" or "g_play", cx + (SA.playing and 0 or 2 * K), cy, R * 1.25, R * 1.25, A(255))
		addBtn(cx, cy, R, function() SA.ShowPause(SA.playing) end, L(SA.playing and "sa_pl_pause" or "sa_pl_play"))

		-- right in the capsule: the speaker and the volume
		local vol = sh.mute and 0 or (sh.vol or 1)
		glyphBtn(cx + 134 * K, cy, vol <= 0 and "vol_mute" or (vol < 0.5 and "vol_low" or "vol"), 22 * K,
			function() sh.mute = not sh.mute end, L("sa_pl_mute"))
		local vx, vw = cx + 156 * K, 96 * K
		local vh = math.max(math.floor(3 * K), 2)
		surface.SetDrawColor(0, 0, 0, A(230))
		surface.DrawRect(vx - 1, cy - vh / 2 - 1, vw + 2, vh + 2)
		surface.SetDrawColor(50, 54, 64, A(255))
		surface.DrawRect(vx, cy - vh / 2, vw, vh)
		surface.SetDrawColor(70, 150, 240, A(255))
		surface.DrawRect(vx, cy - vh / 2, vw * vol, vh)
		pdraw(hotAt(vx + vw * vol, cy, 9 * K) and "orb_hot" or "orb", vx + vw * vol, cy, 16 * K, 16 * K, A(255))
		s.volArea = { x = vx, w = vw, y = cy, h = 9 * K }

		-- left of the capsule: the scene and the time
		local lx = math.floor(24 * K)
		local avail = capX - lx - 20 * K
		surface.SetFont("SAeditor.PlayerTime")
		local name = title
		if surface.GetTextSize(name) > avail * 0.55 then
			local cps = {}
			for _, c in utf8.codes(title) do cps[#cps + 1] = utf8.char(c) end
			while #cps > 1 and surface.GetTextSize(table.concat(cps) .. "…") > avail * 0.55 do table.remove(cps) end
			name = table.concat(cps) .. "…"
		end
		draw.SimpleText(name, "SAeditor.PlayerTime", lx, cy, Color(225, 232, 245, A(255)), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		local nw = surface.GetTextSize(name)
		draw.SimpleText(clock(SA.frame) .. " / " .. clock(SA.frames), "SAeditor.PlayerTime", lx + nw + 18 * K, cy, Color(170, 185, 210, A(255)),
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		-- right of the capsule: the cameras and leave
		glyphBtn(W - 74 * K, cy, "camera", 24 * K, cameraMenu, L("sa_pl_pick_cam"))
		local hotExit = glyphBtn(W - 34 * K, cy, "close", 22 * K, function() SA.StopShow() end, L("sa_pl_exit"))
		if hotExit then pdraw("g_close", W - 34 * K, cy, 22 * K, 22 * K, A(255)) end

		-- the tooltip of the button under the cursor
		for _, b in ipairs(btns) do
			if (s.mx - b.x) ^ 2 + (s.my - b.y) ^ 2 < b.r ^ 2 and b.tip then
				draw.SimpleTextOutlined(b.tip, "SAeditor.PlayerSmall", math.Clamp(b.x, 80 * K, W - 80 * K), b.y - b.r - 14 * K,
					Color(255, 255, 255, A(255)), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, A(220)))
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
		local la = s.listArea
		if la and mx >= la.x0 and mx <= la.x1 and math.abs(my - la.y) <= la.h then cameraMenu() return end
		local sa = s.seekArea
		if sa and math.abs(my - sa.y) <= sa.h and mx >= sa.x0 - 4 and mx <= sa.x1 + 4 then
			s.dragSeek = true
			s:MouseCapture(true)
			SA.ShowSeek(math.Clamp((mx - sa.x0) / (sa.x1 - sa.x0), 0, 1) * SA.frames)
			return
		end
		local va = s.volArea
		if va and math.abs(my - va.y) <= va.h and mx >= va.x - 6 and mx <= va.x + va.w + 6 then
			s.dragVol = va
			s:MouseCapture(true)
			setVolume((mx - va.x) / va.w)
			return
		end
		-- a click on the picture itself
		if my < ScrH() - barH() - 10 and my > 110 * K then SA.ShowPause(SA.playing) end
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
