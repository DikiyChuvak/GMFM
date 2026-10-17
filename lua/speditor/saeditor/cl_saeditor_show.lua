--[[
SAeditor — playing the animation outside the editor (a0.6).

The scene stays on the map when the editor is closed. There are two ways to watch it there:

  the player       closes the editor and plays the animation full screen with the controls of a
                   video player (cl_saeditor_player.lua: play / pause, stop, the previous / next
                   shot, a seek bar, repeat, the render look, volume): through the cameras the
                   animation switches between (camera cuts, cl_saeditor_cuts.lua) or through one
                   chosen camera; with its sounds, without the editor's interface and the HUD;
  walking around   the animation plays while the player walks around the scene and watches it
                   with its own eyes: no player window, the HUD and the weapon stay, Backspace
                   stops it.

Console (can be bound to keys):
  saeditor_show [camera name | eyes | cuts]   play from the start (no argument: the camera cuts
                                       if the animation has them, else saeditor_show_camera;
                                       eyes — walking around the scene)
  saeditor_show_stop                    stop
  saeditor_show_toggle                  play / stop
  saeditor_show_loop 0/1                play in a loop
  saeditor_show_camera <name>           the camera by default ("" — the first camera of the scene)
]]
local COMP = SPeditor.Component("saeditor")
local SA  = COMP.SA
local C   = SPeditor.Client
local L   = SPeditor.L

local cvLoop   = CreateClientConVar("saeditor_show_loop", "0", true, false, "Play the animation outside the editor in a loop")
local cvCamera = CreateClientConVar("saeditor_show_camera", "", true, false, "Camera to watch the animation through outside the editor (empty — the first one, eyes — none)")

SA.show = SA.show or nil      -- { cam = camera entity or nil, t0 = RealTime() of the start }

-- the HUD is turned off for the show (other addons' HUDs too) and back on after it
-- (C.HideHUD in cl_speditor.lua keeps the player's own value)
local function hideHud(hide) C.HideHUD("show", hide) end

-- the camera by name: a scene camera, nil — the player's own eyes
local function findCamera(name)
	name = string.lower(name or "")
	if name == "eyes" then return nil end
	local first
	for _, e in ipairs(C.Objects()) do
		if IsValid(e) and C.IsCamera(e) then
			if name ~= "" and string.lower(C.DisplayName(e)) == name then return e end
			first = first or e
		end
	end
	return first
end

-- action: 0 stop, 1 play from the start, 2 pause, 3 play on from frame, 4 go to frame
local function send(action, frame)
	COMP:NetStart("Show")
	net.WriteUInt(action, 3)
	net.WriteBool(cvLoop:GetBool())
	net.WriteFloat(frame or 0)
	net.SendToServer()
end
SA.ShowSend = send

function SA.StartShow(camName)
	if not SA.IsAnimated() then
		SPeditor.Notify("#sa_show_empty", 1)
		return
	end
	if C.active then
		-- the editor closes first; the show starts when the server has let the player go
		SA.showPending = camName or cvCamera:GetString()
		C.SendToggle(false)
		return
	end
	-- the camera cuts of the animation, unless a camera is named
	local name = camName or ""
	local cuts = (name == "" or name == "cuts") and #SA.cuts > 0
	if name == "" or name == "cuts" then name = cvCamera:GetString() end
	-- "eyes": walking around the scene, no player and no camera
	local walk = not cuts and string.lower(name) == "eyes"
	SA.show = { cam = not cuts and not walk and findCamera(name) or nil, cuts = cuts, walk = walk,
		t0 = RealTime(), vol = SA.showVolume or 1 }
	SA.frame, SA.playing = 0, true
	SA.playT0, SA.playF0 = RealTime(), 0
	send(1)
	if walk then return end
	hideHud(true)
	if SA.OpenPlayer then SA.OpenPlayer() end
end

-- the player changes the camera it shows: "cuts", a camera entity, or nil (the player's view)
function SA.ShowSetCamera(cam)
	local sh = SA.show
	if not sh or sh.walk then return end
	sh.cuts = cam == "cuts" and #SA.cuts > 0
	sh.cam = not sh.cuts and IsValid(cam) and cam or nil
	if IsValid(sh.cam) then RunConsoleCommand("saeditor_show_camera", C.DisplayName(sh.cam)) end
end

-- the camera the show looks through at the moment (nil — the player's eyes)
function SA.ShowCamera()
	local sh = SA.show
	if not sh or sh.walk then return nil end
	if sh.cuts then return SA.CameraAt(SA.frame) end
	return IsValid(sh.cam) and sh.cam or nil
end

-- the player's buttons
function SA.ShowPause(pause)
	if not SA.show then return end
	if pause then
		SA.playing = false
		send(2, SA.frame)
	else
		if SA.frame >= SA.frames then SA.frame = 0 end
		SA.playing = true
		SA.playT0, SA.playF0 = RealTime(), SA.frame
		send(3, SA.frame)
	end
end

function SA.ShowSeek(frame)
	if not SA.show then return end
	SA.frame = math.Clamp(frame, 0, SA.frames)
	if SA.playing then SA.playT0, SA.playF0 = RealTime(), SA.frame end
	send(4, SA.frame)
end

function SA.StopShow()
	if not SA.show then return end
	SA.show = nil
	SA.playing = false
	hideHud(false)
	send(0)
	if SA.Audio and SA.Audio.StopAll then SA.Audio.StopAll() end
end

COMP:Hook("SPeditor_StateChanged", function(on)
	if on then
		-- the editor opened during the show: the show is over (the editor hides the HUD itself)
		SA.show, SA.showPending = nil, nil
		hideHud(false)
		return
	end
	local pending = SA.showPending
	SA.showPending = nil
	-- the editor drops the sound channels when it closes; they are loaded again for the show
	if pending then timer.Simple(0.1, function() SA.StartShow(pending) end) end
end, "show")


-- walking around: Backspace stops, the end of the animation (without repeat) too
local backWas
COMP:Hook("Think", function()
	local sh = SA.show
	if not sh or not sh.walk then backWas = nil return end
	local back = input.IsKeyDown(KEY_BACKSPACE) and not vgui.GetKeyboardFocus() and not gui.IsGameUIVisible()
	if back and backWas == false then SA.StopShow() return end
	backWas = back
	if not SA.playing and SA.frame >= SA.frames and RealTime() - sh.t0 > 0.5 then SA.StopShow() end
end, "show_walk")

-- walking around: a small line at the top says what plays and how to stop it
local playIcon = Material("icon16/control_play_blue.png")
COMP:Hook("DrawOverlay", function()
	local sh = SA.show
	if not sh or not sh.walk then return end
	local function clock(f)
		local t = math.max(f, 0) / math.max(SA.fps, 1)
		return string.format("%02d:%02d", math.floor(t / 60), math.floor(t % 60))
	end
	local text = clock(SA.frame) .. " / " .. clock(SA.frames) .. "   \xc2\xb7   " .. L("sa_walk_hint")
	surface.SetFont("SPeditor.Bold")
	local tw, th = surface.GetTextSize(text)
	local x, y = math.floor(ScrW() / 2 - tw / 2 + 10), 14
	draw.RoundedBox(4, x - 30, y - 4, tw + 40, th + 8, Color(0, 0, 0, 150))
	surface.SetDrawColor(255, 255, 255, 230)
	surface.SetMaterial(playIcon)
	surface.DrawTexturedRect(x - 24, math.floor(y + th / 2 - 8), 16, 16)
	draw.SimpleText(text, "SPeditor.Bold", x, y, Color(255, 255, 255, 230))
	local u = SA.frames > 0 and math.Clamp(SA.frame / SA.frames, 0, 1) or 0
	surface.SetDrawColor(60, 140, 230, 220)
	surface.DrawRect(x - 30, y + th + 3, (tw + 40) * u, 2)
end, "show_walk")

concommand.Add("saeditor_show", function(_, _, args) SA.StartShow(args[1]) end)
concommand.Add("saeditor_show_stop", function() SA.StopShow() end)
concommand.Add("saeditor_show_toggle", function(_, _, args)
	if SA.show then SA.StopShow() else SA.StartShow(args[1]) end
end)

---------------------------------------------------------------------
-- The view: through the camera, without the HUD, the weapon and the player's body
---------------------------------------------------------------------
COMP:Hook("CalcView", function(ply, origin, angles, fov)
	local cam = SA.ShowCamera()
	if not IsValid(cam) then return end
	local pos, ang, f = SA.ShowView(cam)
	if not pos then return end
	return { origin = pos, angles = ang, fov = f, drawviewer = false }
end, "show")

COMP:Hook("PreDrawViewModel", function()
	if IsValid(SA.ShowCamera()) then return true end
end, "show")

---------------------------------------------------------------------
-- Q menu → SPeditor → SAeditor: the same without the console
---------------------------------------------------------------------
COMP:Hook("PopulateToolMenu", function()
	-- the first call to name the tab creates it (with the wrench icon when none is given), and hooks
	-- run in no fixed order — so the tab is registered here with its own icon as well
	spawnmenu.AddToolTab("SPeditor", "SPeditor", "speditor/icon16.png")
	spawnmenu.AddToolMenuOption("SPeditor", "SAeditor", "SAeditor_Show", L("sa_show_menu"), "", "", function(p)
		p:Help(L("sa_show_qhelp"))
		p:Button(L("sa_show_player"), "saeditor_show")
		p:Button(L("sa_show_eyes"), "saeditor_show", "eyes")
		p:Button(L("sa_show_stop"), "saeditor_show_stop")
		p:CheckBox(L("sa_show_loop"), "saeditor_show_loop")
		p:TextEntry(L("sa_show_cam"), "saeditor_show_camera")
		p:ControlHelp(L("sa_show_cam_help"))
	end)
end, "show_qmenu")

-- the cameras of the scene and the camera cuts, for a menu: pick(value, label), value — "cuts"
-- or a camera entity
function SA.CameraChoices(pick)
	-- the camera cuts of the animation, when it has them, come first
	if #SA.cuts > 0 then pick("cuts", L("sa_show_cuts"), "icon16/film.png") end
	for _, e in ipairs(C.Objects()) do
		if IsValid(e) and C.IsCamera(e) then pick(e, C.DisplayName(e), "icon16/camera.png") end
	end
end

-- "Watch in the game" (File menu): the player through a camera, or walking around the scene
function SA.ShowMenu(m)
	local any = false
	SA.CameraChoices(function(v, label, icon)
		any = true
		m:AddOption(L("sa_show_player") .. ": " .. label, function() SA.StartShow(v == "cuts" and "cuts" or label) end):SetIcon(icon)
	end)
	if not any then m:AddOption(L("sa_show_player"), function() SA.StartShow() end):SetIcon("icon16/television.png") end
	m:AddSpacer()
	m:AddOption(L("sa_show_eyes"), function() SA.StartShow("eyes") end):SetIcon("icon16/eye.png")
	m:AddSpacer()
	m:AddOption(L("sa_show_loop"), function() RunConsoleCommand("saeditor_show_loop", cvLoop:GetBool() and "0" or "1") end):SetChecked(cvLoop:GetBool())
end
