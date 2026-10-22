--[[
SAeditor — the action recorder, client side (a0.6; the take itself is on the server,
sv_saeditor_record.lua). The Record window says what to record; then the editor closes, a
countdown runs, and the game is recorded until Backspace (or gmfm_record_stop). The editor
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

local cvStep    = CreateClientConVar("gmfm_rec_step", "2", true, false, "Recorder: a key every N frames", 1, 12)
local cvNpcs    = CreateClientConVar("gmfm_rec_npcs", "1", true, false, "Recorder: record the NPCs around", 0, 1)
local cvRadius  = CreateClientConVar("gmfm_rec_radius", "1500", true, false, "Recorder: radius for NPCs and effects", 64, 16384)
local cvSounds  = CreateClientConVar("gmfm_rec_sounds", "1", true, false, "Recorder: record sounds", 0, 1)
local cvEffects = CreateClientConVar("gmfm_rec_effects", "1", true, false, "Recorder: record effects", 0, 1)
local cvUISnd   = CreateClientConVar("gmfm_rec_uisounds", "1", true, false, "Recorder: record the sounds of the interface (menus, HUD)", 0, 1)
local cvPhys    = CreateClientConVar("gmfm_rec_phys", "0", true, false,
	"Recorder: physics of scene ragdolls and props: 0 off, 1 the selected ones, 2 all", 0, 2)
local cvView    = CreateClientConVar("gmfm_rec_view", "1", true, false,
	"Recorder: 0 third person (no camera of the player), 1 first person (a camera in the player's eyes)", 0, 1)
local cvCorpses = CreateClientConVar("gmfm_rec_corpses", "1", true, false, "Recorder: killed NPCs fall as ragdolls (server corpses for the take)", 0, 1)

-- the take (b0.2.1): the countdown, a time limit, getting ready (weapons, health, god mode)
local cvCount   = CreateClientConVar("gmfm_rec_countdown", "3", true, false, "Recorder: seconds of the countdown before the take", 1, 10)
local cvLimit   = CreateClientConVar("gmfm_rec_limit", "0", true, false, "Recorder: the take stops by itself after this many seconds (0 = no limit)", 0, 600)
local cvAskWpn  = CreateClientConVar("gmfm_rec_weapons", "0", true, false, "Recorder: choose the weapons before the take (always in the GM:FM gamemode)", 0, 1)
local cvWpnList = CreateClientConVar("gmfm_rec_weaponlist", "weapon_pistol", true, false, "Recorder: the weapons chosen for the take (classes, comma separated)")
local cvStrip   = CreateClientConVar("gmfm_rec_strip", "1", true, false, "Recorder: take away the other weapons for the take", 0, 1)
local cvAmmo    = CreateClientConVar("gmfm_rec_ammo", "250", true, false, "Recorder: ammunition given with every chosen weapon", 0, 9999)
local cvHeal    = CreateClientConVar("gmfm_rec_heal", "1", true, false, "Recorder: full health before the take", 0, 1)
local cvGod     = CreateClientConVar("gmfm_rec_god", "0", true, false, "Recorder: god mode for the time of the take", 0, 1)

local function countdown() return math.Clamp(cvCount:GetInt(), 1, 10) end
-- the weapon step: asked in the GM:FM gamemode always (there is no Q menu to take weapons from)
function SA.RecAsksWeapons() return SPeditor.FilmMode() or cvAskWpn:GetBool() end
function SA.RecWeaponList()
	local out = {}
	for class in string.gmatch(cvWpnList:GetString(), "[^,%s]+") do out[#out + 1] = class end
	return out
end
function SA.RecSetWeaponList(list) RunConsoleCommand("gmfm_rec_weaponlist", table.concat(list, ",")) end

local function send(action, t)
	COMP:NetStart("Rec")
	net.WriteUInt(action, 3)
	if action ~= 0 then SPeditor.WriteTable(t) end
	net.SendToServer()
end

-- the view samples not sent yet go to the server (before the stop, so the take has them all)
local function flushView()
	local r = SA.rec
	if not r then return end
	-- the sounds only this client played (a0.9)
	if r.csnd and #r.csnd > 0 then
		send(4, r.csnd)
		r.csnd = {}
	end
	if r.cfx and #r.cfx > 0 then
		send(5, r.cfx)
		r.cfx = {}
	end
	if not r.view then return end
	if #r.view.batch > 0 then send(2, r.view.batch) end
	if #r.view.bodies > 0 then send(3, r.view.bodies) end
	r.view.batch, r.view.bodies = {}, {}
	r.view.sentAt = RealTime()
end

---------------------------------------------------------------------
-- Sounds of this client (a0.9, "as SFM records the game"): the server hears the sounds it
-- plays itself; what is played only here — a weapon of TFA / ARC9 shooting on the client, the
-- sounds of menus and of the HUD (surface.PlaySound) — is sent in small batches with the view.
-- Sounds of the player's own body and weapons go on the player's copy, the interface ones are
-- heard everywhere.
---------------------------------------------------------------------
local function takeFrame()
	local r = SA.rec
	if not r or not r.on or r.inEditor or not r.t0srv then return nil end
	return math.floor(r.f0 + (CurTime() - r.t0srv) * r.fps + 0.5)
end

local function soundPath(name)
	name = string.lower(string.gsub(tostring(name or ""), "^[%^%)%(%#%*%$%<%>%!%?%@%&%~%%]+", ""))
	if name == "" then return nil end
	return "sound/" .. string.gsub(name, "\\", "/")
end

COMP:Hook("EntityEmitSound", function(t)
	local f = takeFrame()
	local r = SA.rec
	if not f or not r.csnd or #r.csnd >= 2000 then return end
	local me = LocalPlayer()
	local e = t.Entity
	local mine = IsValid(e) and (e == me or (e.GetOwner and e:GetOwner() == me) or e == me:GetViewModel())
	if not mine then return end
	local path = soundPath(t.SoundName)
	if path then r.csnd[#r.csnd + 1] = { f, path, math.Round(t.Volume or 1, 2), t.Pitch or 100, 0 } end
end, "record_sounds")

-- sent twice a second even without the view (the view's own sending is in RenderScene)
local nextSnd = 0
COMP:Hook("Think", function()
	local r = SA.rec
	if not r or RealTime() < nextSnd then return end
	if (not r.csnd or #r.csnd == 0) and (not r.cfx or #r.cfx == 0) then return end
	nextSnd = RealTime() + 0.5
	if r.csnd and #r.csnd > 0 then
		send(4, r.csnd)
		r.csnd = {}
	end
	if r.cfx and #r.cfx > 0 then
		send(5, r.cfx)
		r.cfx = {}
	end
end, "record_sounds")

---------------------------------------------------------------------
-- Effects of this client (a0.9): weapon bases (ARC9, TFA, ArcCW, MW…) make their muzzle flashes,
-- impacts, smoke and sparks on the client — util.Effect and particle systems the server never
-- sees. While a take with effects is on they are written down here with their place and sent
-- in batches with the sounds (Rec action 5). Effects on the first-person view model (the gun in
-- front of the camera) are left out: their place is in front of the eyes, not in the world —
-- the take fires the muzzle flash from the weapon in the hand instead.
---------------------------------------------------------------------
local pcfFile
-- the .pcf file a particle system comes from: "" for the game's own (loaded by the engine)
function SA.PcfFileOf(name)
	if not pcfFile then
		pcfFile = {}
		local Fx = SPeditor.Effects
		for _, f in ipairs(Fx and Fx.Files() or {}) do
			for _, sys in ipairs((Fx.Systems(f.path))) do
				if pcfFile[sys] == nil or (f.stock and pcfFile[sys] ~= "") then pcfFile[sys] = f.stock and "" or f.path end
			end
		end
	end
	return pcfFile[name] or ""
end

local function viewModelish(ent)
	if not IsValid(ent) then return false end
	local me = LocalPlayer()
	local vm = me:GetViewModel()
	if ent == vm or ent:GetClass() == "viewmodel" then return true end
	-- the bases' own view models are client models parented to the view model or to the hands
	local p = ent:GetParent()
	if IsValid(p) and (p == vm or p:GetClass() == "viewmodel" or p == me:GetHands()) then return true end
	-- or held in front of the camera by the base itself
	return ent:EntIndex() == -1 and not me:ShouldDrawLocalPlayer() and ent:GetPos():DistToSqr(me:EyePos()) < 90 * 90
end

local function addFx(src, name, pos, ang, len)
	local f = takeFrame()
	local r = SA.rec
	if not f or not r.cfx or #r.cfx >= 2000 or not isstring(name) or name == "" or not isvector(pos) then return end
	local me = LocalPlayer()
	if pos:DistToSqr(me:GetPos()) > (r.radius or 1500) ^ 2 then return end
	ang = ang or angle_zero
	r.cfx[#r.cfx + 1] = { f, src, name, math.Round(pos.x, 1), math.Round(pos.y, 1), math.Round(pos.z, 1),
		math.Round(ang.p, 1), math.Round(ang.y, 1), math.Round(ang.r, 1), math.Round(len or 0), src == "pcf" and SA.PcfFileOf(name) or "" }
end

local function attachPlace(ent, att)
	if not IsValid(ent) then return nil end
	local a = (tonumber(att) or 0) > 0 and ent:GetAttachment(att) or nil
	if a then return a.Pos, a.Ang end
	return ent:GetPos(), ent:GetAngles()
end

SA.realFx = SA.realFx or { effect = util.Effect, pe = ParticleEffect, pea = ParticleEffectAttach, cps = CreateParticleSystem,
	cpe = FindMetaTable("Entity").CreateParticleEffect }
local real = SA.realFx

util.Effect = function(name, data, ...)
	if SA.rec and SA.rec.cfx and data then
		pcall(function()
			-- an EffectData nobody gave an entity answers GetEntity() with the view model on the
			-- client (measured in game), so the entity counts only for an effect without a place
			local ent = data:GetEntity()
			local pos, start = data:GetOrigin(), data:GetStart()
			if pos == vector_origin then
				-- fired from an attachment of an entity (muzzle flashes of the bases)
				if not IsValid(ent) or viewModelish(ent) then return end
				pos = attachPlace(ent, data:GetAttachment())
			else
				local me = LocalPlayer()
				if not me:ShouldDrawLocalPlayer() and pos:DistToSqr(me:EyePos()) < 40 * 40 and viewModelish(ent) then return end
			end
			-- the start point counts only for effects that fly somewhere: an EffectData keeps the
			-- fields of an earlier effect (measured in game), a leftover start gave a tail
			local low = string.lower(tostring(name))
			local flies = string.find(low, "tracer", 1, true) or string.find(low, "beam", 1, true) or string.find(low, "laser", 1, true)
			local len = (flies and start ~= vector_origin and start:Distance(pos) > 1) and start:Distance(pos) or 0
			addFx("lua", name, len > 0 and start or pos, len > 0 and (pos - start):Angle() or data:GetAngles(), len)
		end)
	end
	return real.effect(name, data, ...)
end

ParticleEffect = function(name, pos, ang, parent, ...)
	if SA.rec and SA.rec.cfx then pcall(function() if not viewModelish(parent) then addFx("pcf", name, pos, ang) end end) end
	return real.pe(name, pos, ang, parent, ...)
end

ParticleEffectAttach = function(name, attachType, ent, attId, ...)
	if SA.rec and SA.rec.cfx then
		pcall(function() if not viewModelish(ent) then addFx("pcf", name, attachPlace(ent, attId)) end end)
	end
	return real.pea(name, attachType, ent, attId, ...)
end

if real.cps then
	CreateParticleSystem = function(ent, name, attachType, attId, offset, ...)
		if SA.rec and SA.rec.cfx then
			pcall(function()
				if viewModelish(ent) then return end
				local pos, ang = attachPlace(ent, attId)
				if pos and isvector(offset) then pos = pos + offset end
				addFx("pcf", name, pos, ang)
			end)
		end
		return real.cps(ent, name, attachType, attId, offset, ...)
	end
end

if real.cpe then
	FindMetaTable("Entity").CreateParticleEffect = function(ent, name, att, ...)
		if SA.rec and SA.rec.cfx then
			pcall(function() if not viewModelish(ent) then addFx("pcf", name, attachPlace(ent, isnumber(att) and att or 0)) end end)
		end
		return real.cpe(ent, name, att, ...)
	end
end

if not SA.realPlaySound then SA.realPlaySound = surface.PlaySound end
surface.PlaySound = function(name, ...)
	local f = takeFrame()
	local r = SA.rec
	if f and r.csnd and r.uiSounds and #r.csnd < 2000 then
		local path = soundPath(name)
		if path then r.csnd[#r.csnd + 1] = { f, path, 1, 100, 1 } end
	end
	return SA.realPlaySound(name, ...)
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
	-- the player gets ready first: the weapons chosen, health, god mode (sv_saeditor_record.lua)
	-- and the NPCs put on their marks (cl_saeditor_recnpcs.lua)
	local npcs, npcCleanup, npcWait = SA.RecNPCsForTake()
	send(6, { weapons = SA.RecAsksWeapons() and SA.RecWeaponList() or nil, strip = cvStrip:GetBool(),
		ammo = cvAmmo:GetInt(), heal = cvHeal:GetBool(), armor = cvHeal:GetBool() and 100 or 0, god = cvGod:GetBool(),
		npcs = #npcs > 0 and npcs or nil, npcCleanup = npcCleanup, npcWait = npcWait })
	local phys = cvPhys:GetInt()
	-- the NPCs of the marks are always in the take: the radius reaches the farthest of them
	local radius = cvRadius:GetFloat()
	local me = LocalPlayer()
	for _, m in ipairs(npcs) do
		if IsValid(me) then radius = math.max(radius, me:GetPos():Distance(m.pos) + 300) end
	end
	local opts = { step = cvStep:GetInt(), npcs = cvNpcs:GetBool() or #npcs > 0, radius = math.min(radius, 16384), sounds = cvSounds:GetBool(),
		effects = cvEffects:GetBool(), from = math.floor(SA.frame + 0.5), phys = phys > 0 and physObjects(phys == 2) or nil,
		view = cvView:GetBool(), corpses = cvCorpses:GetBool() }
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
	if r.pending and r.countFrom and RealTime() - r.countFrom >= countdown() then
		local opts = r.pending
		r.pending = nil
		send(1, opts)
	end
	-- the time limit of the take
	local limit = cvLimit:GetInt()
	if r.on and not r.inEditor and limit > 0 and r.t0 and RealTime() - r.t0 >= limit then SA.StopRecording() end
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
		-- for the sounds of this client: the take's clock and the option of the interface sounds
		SA.rec.t0srv, SA.rec.f0, SA.rec.fps = tonumber(t.t0) or CurTime(), tonumber(t.f0) or 0, tonumber(t.fps) or 24
		if cvSounds:GetBool() and not SA.rec.inEditor then SA.rec.csnd, SA.rec.uiSounds = {}, cvUISnd:GetBool() end
		if cvEffects:GetBool() and not SA.rec.inEditor then
			SA.rec.cfx, SA.rec.radius = {}, cvRadius:GetFloat()
			SA.PcfFileOf("")      -- the map of particle systems to their files, built now and not mid-take
		end
		if t.view then
			SA.rec.view = { t0 = tonumber(t.t0) or CurTime(), fps = tonumber(t.fps) or 24, step = tonumber(t.step) or 2,
				f0 = tonumber(t.f0) or 0, last = -1, batch = {}, bodies = {}, sentAt = RealTime() }
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
		-- the player killed: its body falls on this client only (the server's corpse of a player
		-- has no physics), so its pose goes to the server with the view
		local me = LocalPlayer()
		local rag = IsValid(me) and not me:Alive() and me:GetRagdollEntity()
		if IsValid(rag) then
			rag:SetupBones()
			local bones = {}
			for b = 0, rag:GetBoneCount() - 1 do
				local m = rag:GetBoneMatrix(b)
				if m then
					local p, a = m:GetTranslation(), m:GetAngles()
					bones[#bones + 1] = { b, math.Round(p.x, 2), math.Round(p.y, 2), math.Round(p.z, 2),
						math.Round(a.p, 1), math.Round(a.y, 1), math.Round(a.r, 1) }
				end
			end
			v.bodies[#v.bodies + 1] = { f, bones }
		end
	end
	if RealTime() - v.sentAt > 0.5 then flushView() end
end, "record_view")

concommand.Add("gmfm_record", function() SA.StartRecording() end)
concommand.Add("gmfm_record_stop", function() SA.StopRecording() end)

-- the countdown and the REC mark, over everything
COMP:Hook("DrawOverlay", function()
	local r = SA.rec
	if not r then return end
	local W, H = ScrW(), ScrH()
	if r.pending and r.countFrom then
		local left = math.ceil(countdown() - (RealTime() - r.countFrom))
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
		local limit = cvLimit:GetInt()
		local shown = limit > 0 and math.max(limit - t, 0) or t
		draw.SimpleTextOutlined(string.format(limit > 0 and "REC  -%02d:%02d" or "REC  %02d:%02d", math.floor(shown / 60), math.floor(shown % 60)), "SPeditor.Bold", 46, 30,
			Color(255, 255, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
		draw.SimpleTextOutlined(L("sa_rec_stop_hint"), "SPeditor.Small", 22, 52, Color(230, 230, 230), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
	end
end, "record")

---------------------------------------------------------------------
-- The Record window
---------------------------------------------------------------------
function SA.OpenRecord()
	if Dock.ShowPage("sa_record") then return end
	local win, body = Dock.Create({ key = "sa_record", id = "sa_record", title = L("sa_rec_title"), w = 440, h = 640,
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
	UI.Check(body, L("sa_rec_npcs"), cvNpcs:GetBool(), function(v) RunConsoleCommand("gmfm_rec_npcs", v and "1" or "0") end)
	UI.Slider(body, L("sa_rec_radius"), 200, 6000, 0, cvRadius:GetFloat(), function(v) RunConsoleCommand("gmfm_rec_radius", tostring(math.floor(v))) end)
	UI.Check(body, L("sa_rec_corpses"), cvCorpses:GetBool(), function(v) RunConsoleCommand("gmfm_rec_corpses", v and "1" or "0") end)
		:SetTooltip(L("sa_rec_corpses_tip"))
	UI.Check(body, L("sa_rec_sounds"), cvSounds:GetBool(), function(v) RunConsoleCommand("gmfm_rec_sounds", v and "1" or "0") end)
	UI.Check(body, L("sa_rec_uisounds"), cvUISnd:GetBool(), function(v) RunConsoleCommand("gmfm_rec_uisounds", v and "1" or "0") end)
	UI.Check(body, L("sa_rec_effects"), cvEffects:GetBool(), function(v) RunConsoleCommand("gmfm_rec_effects", v and "1" or "0") end)
	-- the camera of the take (a0.9): third person — the scene is filmed by your own cameras, the
	-- player is an actor like the others; first person — a camera strictly in the player's eyes
	local vr = vgui.Create("DPanel", body)
	vr:Dock(TOP)
	vr:DockMargin(8, 4, 8, 0)
	vr:SetTall(UI.S(22))
	vr.Paint = function() end
	local vl = vgui.Create("DLabel", vr)
	vl:Dock(LEFT)
	vl:SetWide(UI.S(170))
	vl:SetFont("SPeditor.Small")
	vl:SetTextColor(COL.TEXT)
	vl:SetText(L("sa_rec_view"))
	local vc = UI.StyleCombo(vgui.Create("DComboBox", vr))
	vc:Dock(FILL)
	vc:SetTooltip(L("sa_rec_view_tip"))
	vc:AddChoice(L("sa_rec_view_3rd"), 0, not cvView:GetBool())
	vc:AddChoice(L("sa_rec_view_1st"), 1, cvView:GetBool())
	vc.OnSelect = function(_, _, _, v) RunConsoleCommand("gmfm_rec_view", tostring(v)) end
	UI.Slider(body, L("sa_rec_step"), 1, 6, 0, cvStep:GetInt(), function(v) RunConsoleCommand("gmfm_rec_step", tostring(math.floor(v + 0.5))) end)
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
	pc.OnSelect = function(_, _, _, v) RunConsoleCommand("gmfm_rec_phys", tostring(v)) end
	local from = UI.Label(body, "", COL.DIM)
	from:DockMargin(8, 6, 8, 2)
	from.Think = function(s)
		local text = string.format(L("sa_rec_from"), math.floor(SA.frame + 0.5))
		if s.SPText ~= text then
			s.SPText = text
			s:SetText(text)
		end
	end
	-- the take itself (b0.2.1): countdown, time limit, the player made ready
	local takeHead = UI.Label(body, L("sa_rec_take"), COL.ORANGE)
	takeHead:SetFont("SPeditor.Bold")
	takeHead:DockMargin(8, 10, 8, 2)
	UI.Slider(body, L("sa_rec_countdown"), 1, 10, 0, countdown(), function(v) RunConsoleCommand("gmfm_rec_countdown", tostring(math.floor(v + 0.5))) end)
	UI.Slider(body, L("sa_rec_limit"), 0, 300, 0, cvLimit:GetInt(), function(v) RunConsoleCommand("gmfm_rec_limit", tostring(math.floor(v + 0.5))) end)
		:SetTooltip(L("sa_rec_limit_tip"))
	UI.Check(body, L("sa_rec_heal"), cvHeal:GetBool(), function(v) RunConsoleCommand("gmfm_rec_heal", v and "1" or "0") end)
	UI.Check(body, L("sa_rec_god"), cvGod:GetBool(), function(v) RunConsoleCommand("gmfm_rec_god", v and "1" or "0") end)
	-- weapons: in the GM:FM gamemode the step is always there
	local wpn
	if not SPeditor.FilmMode() then
		UI.Check(body, L("sa_rec_ask_weapons"), cvAskWpn:GetBool(), function(v)
			RunConsoleCommand("gmfm_rec_weapons", v and "1" or "0")
			if IsValid(wpn) then
				wpn:SetVisible(v)
				body:InvalidateLayout()
			end
		end):SetTooltip(L("sa_rec_ask_weapons_tip"))
	end
	wpn = UI.Button(body, "", "icon16/gun.png", function() SA.OpenWeaponPicker() end, 24)
	wpn:DockMargin(8, 4, 8, 0)
	wpn:SetVisible(SA.RecAsksWeapons())
	wpn.Think = function(s2)
		local text = (UI.ButtonPad or "  ") .. string.format(L("sa_rec_weapons_btn"), #SA.RecWeaponList())
		if s2.SPText ~= text then
			s2.SPText = text
			s2:SetText(text)
		end
	end

	-- the NPCs of the take, each on its own mark (b0.2.1)
	local npcBtn = UI.Button(body, "", "icon16/group.png", function() SA.OpenNPCPicker() end, 24)
	npcBtn:DockMargin(8, 4, 8, 0)
	npcBtn.Think = function(s2)
		local text = (UI.ButtonPad or "  ") .. string.format(L("sa_rec_npcs_btn"), #SA.RecNPCList())
		if s2.SPText ~= text then
			s2.SPText = text
			s2:SetText(text)
		end
	end

	local go = UI.Button(body, L("sa_rec_go"), "icon16/webcam.png", function()
		win:Remove()
		-- the weapons are asked first; "Done" there starts the countdown
		if SA.RecAsksWeapons() then SA.OpenWeaponPicker(true) else SA.StartRecording() end
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
-- The game's view sits 8-15 units behind the model's eyes (measured on a walking take), so a view
-- is "inside the head" when it is that close to the eyes and not in front of the face: a close-up
-- of the face from the front still shows it.
local EYE_RADIUS = 24       -- units from the eyes (20 from the head bone of a model without "eyes")
local EYE_FRONT  = 3        -- a view more than this in front of the eyes is a close-up
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
		if a then return a.Pos, EYE_RADIUS, a.Ang:Forward() end
		return nil
	end
	local m = ent:GetBoneMatrix(h.bone)
	return m and m:GetTranslation(), EYE_RADIUS - 4
end

local inEyesAt              -- inEyes, set below
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

-- what a view from the place eye does not show (the characters it is in the head of, with what
-- they wear): the depth pass of SSAO hides them with NoDraw before its view (cl_ssao.lua) — the
-- draw callback did not keep them out of it, and their outline darkened the frame ("an invisible
-- silhouette" in the player)
function C.HiddenInView(eye)
	local out = {}
	for rag, worn in pairs(bodies) do
		if IsValid(rag) and inEyesAt and inEyesAt(rag, eye) then
			out[#out + 1] = rag
			for _, csm in ipairs(worn) do out[#out + 1] = csm end
			for _, e in ipairs(C.Objects()) do
				if IsValid(e) and C.AttachParent and C.AttachParent(e) == rag then out[#out + 1] = e end
			end
		end
	end
	return out
end

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
	local at, radius, fwd = eyesOf(ent)
	if not at or at:DistToSqr(eye) >= radius * radius then return false end
	return not fwd or (eye - at):Dot(fwd) < EYE_FRONT
end
inEyesAt = inEyes

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
	-- animation draw it; its own first-person view does not). The player of the animation does
	-- not show it at all: it watches the film, it is not in it
	local me = LocalPlayer()
	local sh = SA.show
	if IsValid(me) and (sh and not sh.walk or inEyes(me, eye)) then
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
