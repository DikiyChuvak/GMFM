--[[
SAeditor — the action recorder, client side (a0.6; the take itself is on the server,
sv_saeditor_record.lua). The Record window says what to record; then the editor closes, a
countdown runs, and the game is recorded until Backspace (or saeditor_record_stop). The editor
opens again with the actors, their keys, sounds and effects in the scene.
]]
local MOD  = SPeditor.Mod("saeditor")
local SA   = MOD.SA
local C    = SPeditor.Client
local UI   = SPeditor.UI
local Dock = SPeditor.Dock
local L    = SPeditor.L
local COL  = UI.PAL

local cvStep    = CreateClientConVar("saeditor_rec_step", "2", true, false, "Recorder: a key every N frames", 1, 12)
local cvNpcs    = CreateClientConVar("saeditor_rec_npcs", "1", true, false, "Recorder: record the NPCs around", 0, 1)
local cvRadius  = CreateClientConVar("saeditor_rec_radius", "1500", true, false, "Recorder: radius for NPCs and effects", 64, 16384)
local cvSounds  = CreateClientConVar("saeditor_rec_sounds", "1", true, false, "Recorder: record sounds", 0, 1)
local cvEffects = CreateClientConVar("saeditor_rec_effects", "1", true, false, "Recorder: record effects", 0, 1)

local COUNTDOWN = 3

local function send(action, t)
	MOD:NetStart("Rec")
	net.WriteUInt(action, 2)
	if action == 1 then SPeditor.WriteTable(t) end
	net.SendToServer()
end

function SA.StartRecording()
	local opts = { step = cvStep:GetInt(), npcs = cvNpcs:GetBool(), radius = cvRadius:GetFloat(), sounds = cvSounds:GetBool(),
		effects = cvEffects:GetBool(), from = math.floor(SA.frame + 0.5) }
	SA.rec = { pending = opts }
	if C.active then C.SendToggle(false) else SA.rec.countFrom = RealTime() end
end

function SA.StopRecording()
	if not SA.rec then return end
	if SA.rec.on then
		send(0)
	else
		-- stopped during the countdown: back to the editor
		SA.rec = nil
		if not C.active then C.SendToggle(true) end
	end
end

-- the editor has closed: the countdown starts
MOD:Hook("SPeditor_StateChanged", function(on)
	local r = SA.rec
	if not on and r and r.pending and not r.countFrom then r.countFrom = RealTime() end
	-- the editor opened in the middle of a take (by hand): the take stops
	if on and r and r.on then send(0) end
end, "record")

local backWas = false
MOD:Hook("Think", function()
	local r = SA.rec
	if not r then return end
	if r.pending and r.countFrom and RealTime() - r.countFrom >= COUNTDOWN then
		local opts = r.pending
		r.pending = nil
		send(1, opts)
	end
	-- Backspace stops the take (not while typing into something)
	local back = input.IsKeyDown(KEY_BACKSPACE) and not vgui.GetKeyboardFocus() and not gui.IsGameUIVisible()
	if back and not backWas and (r.on or r.pending) then SA.StopRecording() end
	backWas = back
end, "record")

MOD:NetReceive("Rec", function()
	local t = SPeditor.ReadTable() or {}
	if t.state == "started" then
		SA.rec = SA.rec or {}
		SA.rec.on, SA.rec.t0 = true, RealTime()
	elseif t.state == "stopped" then
		SA.rec = nil
		local m = t.made or {}
		SPeditor.Notify(string.format(L("sa_rec_done"), m.actors or 0, m.keys or 0, m.sounds or 0, m.effects or 0), 2)
		if not C.active then C.SendToggle(true) end
		-- the take starts where the playhead was
		timer.Simple(0.5, function() if C.active then SA.Seek(tonumber(t.f0) or 0) end end)
	end
end)

concommand.Add("saeditor_record", function() SA.StartRecording() end)
concommand.Add("saeditor_record_stop", function() SA.StopRecording() end)

-- the countdown and the REC mark, over everything
MOD:Hook("DrawOverlay", function()
	local r = SA.rec
	if not r then return end
	local W, H = ScrW(), ScrH()
	if r.pending and r.countFrom then
		local left = math.ceil(COUNTDOWN - (RealTime() - r.countFrom))
		draw.SimpleTextOutlined(tostring(math.max(left, 1)), "SPeditor.Time", W / 2, H / 2 - 20, Color(255, 80, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, color_black)
		draw.SimpleTextOutlined(L("sa_rec_get_ready"), "SPeditor.Bold", W / 2, H / 2 + 14, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
	elseif r.on then
		local t = RealTime() - r.t0
		local blink = (RealTime() % 1) < 0.6
		draw.NoTexture()
		if blink then
			surface.SetDrawColor(230, 40, 40, 255)
			local poly = {}
			for i = 0, 15 do
				local a = i / 16 * math.pi * 2
				poly[#poly + 1] = { x = 30 + math.cos(a) * 8, y = 30 + math.sin(a) * 8 }
			end
			surface.DrawPoly(poly)
		end
		draw.SimpleTextOutlined(string.format("REC  %02d:%02d", math.floor(t / 60), math.floor(t % 60)), "SPeditor.Bold", 46, 30,
			Color(255, 255, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
		draw.SimpleTextOutlined(L("sa_rec_stop_hint"), "SPeditor.Small", 22, 52, Color(230, 230, 230), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
	end
end, "record")

---------------------------------------------------------------------
-- The Record window
---------------------------------------------------------------------
function SA.OpenRecord()
	if Dock.ShowPage("sa_record") then return end
	local win, body = Dock.Create({ key = "sa_record", id = "sa_record", title = L("sa_rec_title"), w = 440, h = 360,
			x = math.floor(ScrW() / 2 - 210), y = 140, dockable = false, icon = "icon16/webcam.png" })
	win.minW, win.minH = UI.S(360), UI.S(320)
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.sa_record = nil
	end
	local hint = UI.Label(body, L("sa_rec_hint"), COL.TEXT)
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:DockMargin(8, 8, 8, 6)
	UI.Check(body, L("sa_rec_npcs"), cvNpcs:GetBool(), function(v) RunConsoleCommand("saeditor_rec_npcs", v and "1" or "0") end)
	UI.Slider(body, L("sa_rec_radius"), 200, 6000, 0, cvRadius:GetFloat(), function(v) RunConsoleCommand("saeditor_rec_radius", tostring(math.floor(v))) end)
	UI.Check(body, L("sa_rec_sounds"), cvSounds:GetBool(), function(v) RunConsoleCommand("saeditor_rec_sounds", v and "1" or "0") end)
	UI.Check(body, L("sa_rec_effects"), cvEffects:GetBool(), function(v) RunConsoleCommand("saeditor_rec_effects", v and "1" or "0") end)
	UI.Slider(body, L("sa_rec_step"), 1, 6, 0, cvStep:GetInt(), function(v) RunConsoleCommand("saeditor_rec_step", tostring(math.floor(v + 0.5))) end)
	local from = UI.Label(body, "", COL.DIM)
	from:DockMargin(8, 6, 8, 2)
	from.Think = function(s)
		local text = string.format(L("sa_rec_from"), math.floor(SA.frame + 0.5))
		if s.SPText ~= text then
			s.SPText = text
			s:SetText(text)
		end
	end
	local go = UI.Button(body, L("sa_rec_go"), "icon16/webcam.png", function()
		win:Remove()
		SA.StartRecording()
	end, 30)
	go:DockMargin(8, 10, 8, 4)
	UI.StyleButton(go, true)
	UI.Button(body, L("guide_open"), "icon16/help.png", function() UI.OpenGuide("sa_rec") end):DockMargin(8, 4, 8, 4)
	return win
end

---------------------------------------------------------------------
-- Player colour of recorded players (the PlayerColor material proxy asks the entity)
---------------------------------------------------------------------
local nextColor = 0
MOD:Hook("Think", function()
	if RealTime() < nextColor then return end
	nextColor = RealTime() + 1
	for _, e in ipairs(C.Objects()) do
		if IsValid(e) and not e.GetPlayerColor then
			local v = e:GetNW2Vector("SPeditor_PlayerColor", vector_origin)
			if v ~= vector_origin then
				e.GetPlayerColor = function(s) return s:GetNW2Vector("SPeditor_PlayerColor", vector_origin) end
			end
		end
	end
end, "playercolor")
