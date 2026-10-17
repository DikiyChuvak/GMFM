--[[
SAeditor — the action recorder, client side (a0.6; the take itself is on the server,
sv_saeditor_record.lua). The Record window says what to record; then the editor closes, a
countdown runs, and the game is recorded until Backspace (or saeditor_record_stop). The editor
opens again with the actors, their keys, sounds and effects in the scene.
Physics (a0.7): ragdolls and props of the scene (the selected ones or all) can be recorded too —
in a game take, or alone with the editor open (SA.StartPhysicsTake): they are unfrozen, fall and
collide, and get their own keys.
The view (a0.7): what the player sees during the take (the game's own view after every CalcView)
is sampled here every keyed frame and sent to the server in batches; it becomes a camera of the
scene. A character whose eyes a view is in is not drawn in that view (the recorded player in its
own first-person camera), as the game does not draw the player's own body.
]]
local COMP  = SPeditor.Component("saeditor")
local SA   = COMP.SA
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
local cvPhys    = CreateClientConVar("saeditor_rec_phys", "0", true, false,
	"Recorder: physics of scene ragdolls and props: 0 off, 1 the selected ones, 2 all", 0, 2)
local cvView    = CreateClientConVar("saeditor_rec_view", "1", true, false, "Recorder: record your view as a scene camera", 0, 1)

local COUNTDOWN = 3

local function send(action, t)
	COMP:NetStart("Rec")
	net.WriteUInt(action, 2)
	if action ~= 0 then SPeditor.WriteTable(t) end
	net.SendToServer()
end

-- the view samples not sent yet go to the server (before the stop, so the take has them all)
local function flushView()
	local r = SA.rec
	if not r or not r.view or #r.view.batch == 0 then return end
	send(2, r.view.batch)
	r.view.batch = {}
	r.view.sentAt = RealTime()
end

local function stopTake()
	flushView()
	send(0)
end

-- the scene objects whose physics a take records: the selected ragdolls and props, or all of them
local function physObjects(all)
	local out = {}
	for _, e in ipairs(all and C.Objects() or C.SelectionList()) do
		local cls = IsValid(e) and e:GetClass() or ""
		if (cls == "prop_ragdoll" or cls == "prop_physics") and not C.IsLocked(e) and not C.AttachParent(e) then
			out[#out + 1] = SA.UID(e)
		end
	end
	return out
end

function SA.StartRecording()
	local phys = cvPhys:GetInt()
	local opts = { step = cvStep:GetInt(), npcs = cvNpcs:GetBool(), radius = cvRadius:GetFloat(), sounds = cvSounds:GetBool(),
		effects = cvEffects:GetBool(), from = math.floor(SA.frame + 0.5), phys = phys > 0 and physObjects(phys == 2) or nil,
		view = cvView:GetBool() }
	SA.rec = { pending = opts }
	if C.active then C.SendToggle(false) else SA.rec.countFrom = RealTime() end
end

-- Physics only, with the editor open: the selected ragdolls and props (all of them when nothing
-- is selected) are let go from the current frame; Stop (or Backspace) writes their keys.
function SA.StartPhysicsTake()
	if SA.rec then return end
	local list = physObjects(false)
	if #list == 0 then list = physObjects(true) end
	if #list == 0 then
		SPeditor.Notify("#sa_rec_phys_none", 1)
		return
	end
	SA.rec = { inEditor = true }
	send(1, { step = cvStep:GetInt(), npcs = false, sounds = false, effects = false, noPlayer = true,
		from = math.floor(SA.frame + 0.5), phys = list })
end

function SA.StopRecording()
	if not SA.rec then return end
	if SA.rec.on then
		stopTake()
	else
		-- stopped during the countdown: back to the editor
		SA.rec = nil
		if not C.active then C.SendToggle(true) end
	end
end

-- the editor has closed: the countdown starts
COMP:Hook("SPeditor_StateChanged", function(on)
	local r = SA.rec
	if not on and r and r.pending and not r.countFrom then r.countFrom = RealTime() end
	-- the editor opened in the middle of a take (by hand): the take stops
	if on and r and r.on then stopTake() end
end, "record")

local backWas = false
COMP:Hook("Think", function()
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

COMP:NetReceive("Rec", function()
	local t = SPeditor.ReadTable() or {}
	if t.state == "started" then
		SA.rec = SA.rec or {}
		SA.rec.on, SA.rec.t0 = true, RealTime()
		if t.view then
			SA.rec.view = { t0 = tonumber(t.t0) or CurTime(), fps = tonumber(t.fps) or 24, step = tonumber(t.step) or 2,
				f0 = tonumber(t.f0) or 0, last = -1, batch = {}, sentAt = RealTime() }
		end
	elseif t.state == "stopped" then
		SA.rec = nil
		local m = t.made or {}
		if (m.phys or 0) > 0 and (m.actors or 0) == 0 then
			SPeditor.Notify(string.format(L("sa_rec_done_phys"), m.phys, m.keys or 0), 2)
		else
			SPeditor.Notify(string.format(L("sa_rec_done"), m.actors or 0, m.keys or 0, m.sounds or 0, m.effects or 0), 2)
			if (m.phys or 0) > 0 then SPeditor.Notify(string.format(L("sa_rec_done_phys"), m.phys, m.keys or 0), 2) end
		end
		if (m.movers or 0) > 0 then SPeditor.Notify(string.format(L("sa_rec_done_world"), m.movers), 2) end
		if m.view then SPeditor.Notify(string.format(L(m.viewCut and "sa_rec_done_view_cut" or "sa_rec_done_view"), tostring(m.view)), 2) end
		if not C.active then C.SendToggle(true) end
		-- the take starts where the playhead was
		timer.Simple(0.5, function() if C.active then SA.Seek(tonumber(t.f0) or 0) end end)
	end
end)

-- the view of the game frame, as the player sees it. RenderScene gets the field of view already
-- widened to the screen (fov_desired 90 on 16:9 comes as 106°, measured), which is what a
-- camera's FOV is: the true horizontal angle.
COMP:Hook("RenderScene", function(origin, angles, fov)
	local v = SA.rec and SA.rec.on and SA.rec.view
	if not v then return end
	local f = v.f0 + math.floor((CurTime() - v.t0) * v.fps / v.step) * v.step
	if f > v.last then
		v.last = f
		v.batch[#v.batch + 1] = { f, origin.x, origin.y, origin.z, angles.p, angles.y, angles.r, math.Round(fov, 2) }
	end
	if RealTime() - v.sentAt > 0.5 then flushView() end
end, "record_view")

concommand.Add("saeditor_record", function() SA.StartRecording() end)
concommand.Add("saeditor_record_stop", function() SA.StopRecording() end)

-- the countdown and the REC mark, over everything
COMP:Hook("DrawOverlay", function()
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
	local win, body = Dock.Create({ key = "sa_record", id = "sa_record", title = L("sa_rec_title"), w = 440, h = 400,
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
	UI.Check(body, L("sa_rec_view"), cvView:GetBool(), function(v) RunConsoleCommand("saeditor_rec_view", v and "1" or "0") end)
		:SetTooltip(L("sa_rec_view_tip"))
	UI.Slider(body, L("sa_rec_step"), 1, 6, 0, cvStep:GetInt(), function(v) RunConsoleCommand("saeditor_rec_step", tostring(math.floor(v + 0.5))) end)
	-- physics of the scene's ragdolls and props
	local pr = vgui.Create("DPanel", body)
	pr:Dock(TOP)
	pr:DockMargin(8, 4, 8, 0)
	pr:SetTall(UI.S(22))
	pr.Paint = function() end
	local pl = vgui.Create("DLabel", pr)
	pl:Dock(LEFT)
	pl:SetWide(UI.S(170))
	pl:SetFont("SPeditor.Small")
	pl:SetTextColor(COL.TEXT)
	pl:SetText(L("sa_rec_phys"))
	local pc = UI.StyleCombo(vgui.Create("DComboBox", pr))
	pc:Dock(FILL)
	pc:SetTooltip(L("sa_rec_phys_tip"))
	for i, k in ipairs({ "sa_rec_phys_off", "sa_rec_phys_sel", "sa_rec_phys_all" }) do pc:AddChoice(L(k), i - 1, cvPhys:GetInt() == i - 1) end
	pc.OnSelect = function(_, _, _, v) RunConsoleCommand("saeditor_rec_phys", tostring(v)) end
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
	-- physics alone, without leaving the editor
	local phys = UI.Button(body, L("sa_rec_phys_go"), "icon16/sport_soccer.png", function()
		if SA.rec and SA.rec.inEditor then SA.StopRecording() else SA.StartPhysicsTake() end
	end, 28)
	phys:DockMargin(8, 4, 8, 4)
	phys:SetTooltip(L("sa_rec_phys_go_tip"))
	phys.Think = function(s)
		local on = SA.rec and SA.rec.inEditor and true or false
		if s.SPOn ~= on then
			s.SPOn = on
			s:SetText((UI.ButtonPad or "  ") .. L(on and "sa_rec_phys_stop" or "sa_rec_phys_go"))
			s:SetIcon(on and "icon16/stop.png" or "icon16/sport_soccer.png")
		end
	end
	UI.Button(body, L("guide_open"), "icon16/help.png", function() UI.OpenGuide("sa_rec") end):DockMargin(8, 4, 8, 4)
	return win
end

---------------------------------------------------------------------
-- Player colour of recorded players (the PlayerColor material proxy asks the entity)
---------------------------------------------------------------------
local nextColor = 0
COMP:Hook("Think", function()
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

---------------------------------------------------------------------
-- A view from inside a character's head (its recorded first-person camera, or any camera put at
-- its eyes): the character and what it wears or holds (PAC3 outfits too) are not drawn in that
-- view, as the game does not draw the player's own body. The player standing where the take ended
-- counts too (the views of the editor draw the player). The other views of the frame (viewports, shadows of lights) see it as
-- usual. Hiding is done by the draw callback for the time of the view: by then the engine has
-- listed what it draws, so changing NoDraw or the bones would not work (tried in the game).
---------------------------------------------------------------------
local EYE_RADIUS = 10       -- units from the eyes (12 from the head bone of a model without "eyes")
local headOf = {}           -- [model] = { att = eyes attachment } | { bone = head bone } | false
local function eyesOf(ent)
	local mdl = ent:GetModel() or ""
	local h = headOf[mdl]
	if h == nil then
		h = false
		local att = ent:LookupAttachment("eyes")
		if att and att > 0 then
			h = { att = att }
		else
			local b = ent:LookupBone("ValveBiped.Bip01_Head1")
			if not b then
				for i = 0, ent:GetBoneCount() - 1 do
					if string.find(string.lower(ent:GetBoneName(i) or ""), "head", 1, true) then b = i break end
				end
			end
			if b then h = { bone = b } end
		end
		headOf[mdl] = h
	end
	if not h then return nil end
	if h.att then
		local a = ent:GetAttachment(h.att)
		return a and a.Pos, EYE_RADIUS
	end
	local m = ent:GetBoneMatrix(h.bone)
	return m and m:GetTranslation(), EYE_RADIUS + 2
end

local bodies = {}           -- [ragdoll] = { what it wears or holds } — rescanned twice a second
timer.Create("SAeditor.EyeHide", 0.5, 0, function()
	local list = {}
	for _, e in ipairs(ents.FindByClass("prop_ragdoll")) do
		if e:GetNW2Bool("SPeditor_Ent", false) then list[e] = {} end
	end
	for _, e in ipairs(C.Objects()) do
		local csm = IsValid(e) and e.SPWorn
		if IsValid(csm) and list[csm:GetParent()] then table.insert(list[csm:GetParent()], csm) end
	end
	bodies = list
end)

local function drawNothing() end
local hidden = nil          -- { [ent] = its own draw callback } while a view hides someone
local hiddenFrame = 0       -- a view cut short by an error does not block the next frames
local hidePlayer = false
-- PAC3 outfits are drawn by PAC3's own hooks after the opaque and translucent passes, for the
-- entities with pac_is_drawing: it is cleared for the view and given back before the next one
local pacKeep = {}

local function givePacBack()
	for e in pairs(pacKeep) do
		if IsValid(e) and e.pac_is_drawing == false then e.pac_is_drawing = true end
	end
	pacKeep = {}
end

local function hide(e)
	if IsValid(e) and not hidden[e] then
		hidden[e] = { e.RenderOverride }
		e.RenderOverride = drawNothing
		if e.pac_is_drawing then
			e.pac_is_drawing = false
			pacKeep[e] = true
		end
	end
end

local function inEyes(ent, eye)
	local at, radius = eyesOf(ent)
	return at and at:DistToSqr(eye) < radius * radius
end

COMP:Hook("PreDrawOpaqueRenderables", function(depth, skybox, sky3d)
	if skybox or sky3d then return end
	if hidden and hiddenFrame == FrameNumber() then return end
	if hidden then
		for e, keep in pairs(hidden) do
			if IsValid(e) and e.RenderOverride == drawNothing then e.RenderOverride = keep[1] end
		end
	end
	givePacBack()
	hidden, hidePlayer = {}, false
	local eye = EyePos()
	for rag, worn in pairs(bodies) do
		if IsValid(rag) and inEyes(rag, eye) then
			hide(rag)
			for _, csm in ipairs(worn) do hide(csm) end
		end
	end
	-- the player itself, standing where the take ended (the editor and the player of the
	-- animation draw it; its own first-person view does not)
	local me = LocalPlayer()
	if IsValid(me) and inEyes(me, eye) then
		hidePlayer = true
		if me.pac_is_drawing then
			me.pac_is_drawing = false
			pacKeep[me] = true
		end
		for _, w in ipairs(me:GetWeapons()) do hide(w) end
	end
	if next(hidden) == nil and not hidePlayer then hidden = nil return end
	hiddenFrame = FrameNumber()
end, "eye_hide")

COMP:Hook("PrePlayerDraw", function(p)
	if hidePlayer and p == LocalPlayer() then return true end
end, "eye_hide")

COMP:Hook("PostDrawTranslucentRenderables", function(depth, skybox, sky3d)
	if skybox or sky3d or not hidden then return end
	for e, keep in pairs(hidden) do
		if IsValid(e) and e.RenderOverride == drawNothing then e.RenderOverride = keep[1] end
	end
	hidden, hidePlayer = nil, false
end, "eye_hide")

COMP:Hook("PostRender", function()
	if next(pacKeep) ~= nil then givePacBack() end
end, "eye_hide")
