--[[
SAeditor — takes from demos (b0.2.6, asked on the Workshop: "an analogue of HLAE, so that
animations can be made from demos recorded on different servers").

No console is needed (b0.2.6): File -> Record a demo (or the bar's Demo button) runs the game's own
gm_demo, which writes garrysmod/demos/<map> <date>.dem with a picture, and the game's main menu
(Esc -> Demos) lists those demos with a Play button (playdemo itself cannot be run from Lua).
While a demo plays the editor itself cannot run — there is no server — but this part can. A bar at the top of the screen
(gmfm_demo shows and hides it) records what the demo shows into a take file:
  every player (its model, skin, bodygroups, colour, the weapon in its hands, its eyes; after a
  death the body that falls), every NPC and ragdoll — the places of the bones that have physics;
  props, vehicles and projectiles that move — their place (vehicles: their bones too);
  the demo's own view (what the recorded player saw) — place, turn and field of view;
  the sounds the client was told to play by entities.
Only what is within gmfm_demo_radius of the view when it is first seen joins, and what never moved
is left out of the file. The demo's time is the take's time: it can be played slowed down
(the bar's speed buttons) for a heavy scene, and paused.
Files: data/speditor/demotakes/<name>.dat (JSON, compressed).

Back in a game on the same map, File -> Import demo take: the file goes to the server in pieces and
becomes the scene there as a take of the recorder does (sv_saeditor_record.lua SA.ImportDemoTake):
ragdolls keyed along it with their weapons, keyed models, the view as a camera, the sounds as clips,
from the playhead on. The models must be installed on this computer (a server's own content too).
The bar also works in a live game (a server without GM:FM: record what this client sees).

  SA.DemoBar(on)              show / hide the bar          SA.DemoRecording()
  SA.OpenDemoImport()         the import window            SA.ImportDemoFile(path)
]]
local COMP  = SPeditor.Component("saeditor")
local SA   = COMP.SA
local C    = SPeditor.Client
local UI   = SPeditor.UI
local L    = SPeditor.L
local COL  = UI.PAL

local DIR = SPeditor.Config.SaveDir .. "/demotakes"
local cvRadius = CreateClientConVar("gmfm_demo_radius", "3000", true, false, "Demo takes: what is this close to the view joins the take", 64, 32768)
local cvFps    = CreateClientConVar("gmfm_demo_fps", "24", true, false, "Demo takes: samples a second", 6, 60)

local MAX_SECONDS = 600
local MAX_SUBJECTS = 160
local PROJECTILES = {
	rpg_missile = true, apc_missile = true, grenade_ar2 = true, npc_grenade_frag = true, crossbow_bolt = true,
	prop_combine_ball = true, grenade_helicopter = true, npc_satchel = true, npc_tripmine = true, grenade_spit = true,
	hunter_flechette = true, grenade = true,
}
local PROPS = { prop_physics = true, prop_physics_multiplayer = true, prop_physics_override = true, prop_dynamic = true }

local function ensureDir()
	local acc = ""
	for part in string.gmatch(DIR, "[^/]+") do
		acc = (acc == "") and part or (acc .. "/" .. part)
		if not file.IsDir(acc, "DATA") then file.CreateDir(acc) end
	end
end

---------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------
local D = SA.demoRec          -- the recording in progress (kept over a reload of the file)

function SA.DemoRecording() return D ~= nil end

-- the bones a ragdoll of the model has bodies on (the solids of its collision model), bone 0 first
local physCache = {}
local function physBones(ent)
	local model = string.lower(ent:GetModel() or "")
	local list = physCache[model]
	if list then return list end
	list = { 0 }
	local seen = { [0] = true }
	local info = util.GetModelInfo(model)
	if info and isstring(info.KeyValues) then
		for block in string.gmatch(info.KeyValues, '"solid"%s*(%b{})') do
			local name = string.match(block, '"name"%s*"([^"]+)"')
			local b = name and ent:LookupBone(name)
			if b and b >= 0 and not seen[b] then
				seen[b] = true
				list[#list + 1] = b
			end
		end
	end
	physCache[model] = list
	return list
end

local function fmtPA(p, a)
	return string.format("%.2f,%.2f,%.2f,%.1f,%.1f,%.1f", p.x, p.y, p.z, a.p, a.y, a.r)
end

-- what kind of subject an entity would be, or nil
local function kindOf(ent)
	if not IsValid(ent) or ent:IsWeapon() or ent == LocalPlayer():GetViewModel() then return nil end
	local class = ent:GetClass() or ""
	if string.StartWith(class, "speditor_") then return nil end
	local model = ent:GetModel() or ""
	if model == "" or not string.find(string.lower(model), "^models/.+%.mdl$") then return nil end
	if ent:IsPlayer() then return "player" end
	if ent:IsNPC() or ent:IsNextBot() then return "npc" end
	if ent:IsRagdoll() then
		-- a player's own body after a death goes on in that player
		for _, p in ipairs(player.GetAll()) do
			if p:GetRagdollEntity() == ent then return nil end
		end
		return "npc"
	end
	if ent:IsVehicle() then return "vehicle" end
	if PROJECTILES[class] then return "shot" end
	if PROPS[class] then return "shot" end
end

local function addSubject(ent, kind, f)
	if D.n >= MAX_SUBJECTS then return end
	D.n = D.n + 1
	local sub = { id = ent:EntIndex(), kind = kind, model = string.lower(ent:GetModel() or ""), skin = ent:GetSkin(), groups = {},
		name = kind == "player" and ent:Nick() or ent:GetClass(), s = {}, w = {}, late = (D.firstF and f > D.firstF) or nil,
		-- a living actor stays in the take even standing still; props and ragdolls only if they moved
		actor = kind == "player" or ent:IsNPC() or ent:IsNextBot() }
	for i = 0, ent:GetNumBodyGroups() - 1 do sub.groups[i] = ent:GetBodygroup(i) end
	local c = ent:GetColor()
	if c.r < 255 or c.g < 255 or c.b < 255 or c.a < 255 then sub.col = { c.r, c.g, c.b, c.a } end
	if kind == "player" then
		local pc = ent:GetPlayerColor()
		sub.pcol = { math.Round(pc.x, 3), math.Round(pc.y, 3), math.Round(pc.z, 3) }
	end
	D.subjects[ent] = sub
	D.list[#D.list + 1] = sub
end

local function sampleOne(ent, sub, tf, tft)
	-- a dead player: its body (the ragdoll the game made for it on this client) is the pose
	local src, dead = ent, nil
	if sub.kind == "player" and not ent:Alive() then
		dead = true
		local rag = ent:GetRagdollEntity()
		if IsValid(rag) then src = rag end
	end
	src:SetupBones()
	local bones = {}
	if sub.kind == "shot" then
		bones[1] = "0:" .. fmtPA(src:GetPos(), src:GetAngles())
	elseif sub.kind == "vehicle" then
		bones[1] = "0:" .. fmtPA(src:GetPos(), src:GetAngles())
	else
		for _, b in ipairs(physBones(src)) do
			local m = src:GetBoneMatrix(b)
			if m then bones[#bones + 1] = b .. ":" .. fmtPA(m:GetTranslation(), m:GetAngles()) end
		end
	end
	if #bones == 0 then return end
	-- a vehicle's bones in their parents' space (wheels, steering)
	local loc = ""
	if sub.kind == "vehicle" and src:GetBoneCount() > 1 then
		local out = {}
		for b = 0, src:GetBoneCount() - 1 do
			local m, pb = src:GetBoneMatrix(b), src:GetBoneParent(b)
			local pm = pb >= 0 and src:GetBoneMatrix(pb)
			if m and pm then
				local lp, la = WorldToLocal(m:GetTranslation(), m:GetAngles(), pm:GetTranslation(), pm:GetAngles())
				out[#out + 1] = b .. ":" .. fmtPA(lp, la)
			end
		end
		loc = table.concat(out, ";")
	end
	local eye = sub.kind == "player" and fmtPA(ent:EyePos(), ent:EyeAngles()) or ""
	sub.s[#sub.s + 1] = string.format("%d|%.3f|%s|%s|%s|%s", tf, tft, dead and "1" or "", eye, table.concat(bones, ";"), loc)
	sub.lastF = tf
	-- the weapon in the hands: written when it changes
	if sub.kind == "player" or sub.kind == "npc" then
		local wep = ent.GetActiveWeapon and ent:GetActiveWeapon()
		local wm = IsValid(wep) and string.lower(wep:GetModel() or "") or ""
		if IsValid(wep) and (wm == "" or not util.IsValidModel(wm)) and isstring(wep.WorldModel) then wm = string.lower(wep.WorldModel) end
		if dead then wm = "" end
		if wm ~= sub.wm then
			sub.wm = wm
			sub.w[#sub.w + 1] = tf .. "|" .. wm
		end
	end
end

-- the time of the demo (the game's time in a live game): it stands while the demo is paused and
-- goes slower when the demo does
local function now() return CurTime() end

local function sample(origin, angles, fov)
	local t = now() - D.t0
	if t < D.lastT - 0.01 then
		-- the demo went back (a jump to an earlier tick): the take ends where it was
		SA.StopDemoRecording()
		return
	end
	D.lastT = t
	if t > MAX_SECONDS then
		SA.StopDemoRecording()
		return
	end
	local tft = t * D.fps
	local tf = math.floor(tft)
	if tf <= D.lastF then return end
	D.lastF = tf
	D.firstF = D.firstF or tf
	-- the view of the demo
	D.view[#D.view + 1] = string.format("%d|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f", tf, origin.x, origin.y, origin.z, angles.p, angles.y, angles.r, fov)
	-- newcomers near the view, a few times a second
	if RealTime() >= D.scanAt then
		D.scanAt = RealTime() + 0.25
		local r2 = cvRadius:GetFloat() ^ 2
		for _, e in ipairs(ents.GetAll()) do
			if not D.subjects[e] and not e:IsDormant() and e:GetPos():DistToSqr(origin) <= r2 then
				local kind = kindOf(e)
				if kind then addSubject(e, kind, tf) end
			end
		end
	end
	for ent, sub in pairs(D.subjects) do
		if not IsValid(ent) then
			if not sub.gone and sub.lastF then sub.gone = sub.lastF + 1 end
			D.subjects[ent] = nil
		elseif not ent:IsDormant() and not ent:GetNoDraw() then
			sampleOne(ent, sub, tf, tft)
		end
	end
end

-- The view of the frame as the game shows it (RenderScene: the field of view is already the true
-- horizontal one); the sample is taken after the frame is drawn, when every body has its bones.
-- Another addon's RenderScene may answer first and keep this one from being asked: the eyes of
-- the frame are taken then.
local seen
COMP:Hook("RenderScene", function(origin, angles, fov)
	if D then seen = { Vector(origin), Angle(angles), fov, FrameNumber() } end
end, "demo_rec")
COMP:Hook("PostRender", function()
	if not D then return end
	local v = seen
	if not v or v[4] ~= FrameNumber() then
		local vs = render.GetViewSetup and render.GetViewSetup() or {}
		v = { EyePos(), EyeAngles(), vs.fov or 75 }
	end
	local ok, err = pcall(sample, v[1], v[2], v[3])
	if not ok then
		ErrorNoHalt("[GM:FM] demo take: " .. tostring(err) .. "\n")
		SA.StopDemoRecording()
	end
end, "demo_rec")

-- the sounds entities played on this client, from them (the demo's own sounds of the world, the
-- music and the voices the engine plays itself are not reported to Lua)
COMP:Hook("EntityEmitSound", function(t)
	if not D or #D.sounds >= 1500 then return end
	local name = string.lower(string.gsub(tostring(t.SoundName or ""), "^[%^%)%(%#%*%$%<%>%!%?%@%&%~%%]+", ""))
	if name == "" then return end
	local e = t.Entity
	local id = IsValid(e) and e:EntIndex() or -1
	-- a weapon's sound comes from the one who holds it
	if IsValid(e) and e:IsWeapon() and IsValid(e:GetOwner()) then id = e:GetOwner():EntIndex() end
	D.sounds[#D.sounds + 1] = { math.max(D.lastF, 0), "sound/" .. string.gsub(name, "\\", "/"), math.Round(t.Volume or 1, 2), t.Pitch or 100, id }
end, "demo_rec")

function SA.StartDemoRecording()
	if D then return end
	D = { t0 = now(), lastT = 0, lastF = -1, fps = math.Clamp(cvFps:GetInt(), 6, 60), subjects = {}, list = {}, n = 0, view = {},
		sounds = {}, scanAt = 0, map = game.GetMap(), started = os.date("%Y-%m-%d %H:%M"), tick = engine.IsPlayingDemo() and engine.GetDemoPlaybackTick() or nil }
	SA.demoRec = D
	SPeditor.Notify("#sa_dm_started", 0)
end

-- a subject that never moved is left out (the props and ragdolls lying around)
local function moved(sub)
	local first = sub.s[1]
	if not first then return false end
	local a = string.match(first, "^[^|]*|[^|]*|[^|]*|[^|]*|([^|]*)")
	for i = 2, #sub.s do
		local b = string.match(sub.s[i], "^[^|]*|[^|]*|[^|]*|[^|]*|([^|]*)")
		if b ~= a then return true end
	end
	return false
end

function SA.StopDemoRecording()
	if not D then return end
	local rec = D
	D, SA.demoRec = nil, nil
	local subjects = {}
	for _, sub in ipairs(rec.list) do
		if #sub.s > 0 and (sub.actor or moved(sub)) then
			subjects[#subjects + 1] = { id = sub.id, kind = sub.kind, model = sub.model, skin = sub.skin, groups = sub.groups, col = sub.col,
				pcol = sub.pcol, name = sub.name, s = sub.s, w = sub.w, gone = sub.gone, late = sub.late }
		end
	end
	if #subjects == 0 and #rec.view < 2 then
		SPeditor.Notify("#sa_dm_nothing", 1)
		return
	end
	local take = { v = 1, map = rec.map, fps = rec.fps, step = 1, frames = rec.lastF, started = rec.started, tick = rec.tick,
		subjects = subjects, view = rec.view, sounds = rec.sounds, viewName = "demo view" }
	local function save(name)
		name = SPeditor.SafeName(name or "")
		if name == "" then name = rec.map .. "_" .. os.date("%Y%m%d_%H%M%S") end
		name = string.gsub(name, " ", "_")
		ensureDir()
		local data = util.Compress(util.TableToJSON(take))
		if not data then
			SPeditor.Notify("#sa_dm_bad", 1)
			return
		end
		file.Write(DIR .. "/" .. name .. ".dat", data)
		SPeditor.Notify("#sa_dm_saved|garrysmod/data/" .. DIR .. "/" .. name .. ".dat|" .. #subjects .. "|" .. string.format("%.1f", rec.lastF / rec.fps), 2)
	end
	save(rec.map .. "_" .. os.date("%Y%m%d_%H%M%S"))
end

---------------------------------------------------------------------
-- The bar at the top while a demo plays (gmfm_demo shows / hides it anywhere)
---------------------------------------------------------------------
local bar
local function demoCmd(...) RunConsoleCommand(...) end

function SA.DemoBar(on)
	if on == nil then on = not IsValid(bar) end
	if not on then
		if IsValid(bar) then bar:Remove() end
		bar = nil
		return
	end
	if IsValid(bar) then return end
	bar = vgui.Create("DPanel")
	local h = UI.S(30)
	bar:SetSize(math.min(ScrW() - 40, UI.S(860)), h)
	bar:SetPos(math.floor((ScrW() - bar:GetWide()) / 2), UI.S(6))
	bar:MakePopup()
	bar:SetKeyboardInputEnabled(false)
	bar.Paint = function(s, w, hh)
		draw.RoundedBox(4, 0, 0, w, hh, Color(COL.BG.r, COL.BG.g, COL.BG.b, 235))
		local text
		if D then
			local blink = math.floor(RealTime() * 2) % 2 == 0
			text = string.format(L("sa_dm_rec_line"), (D.lastF + 1) / D.fps, D.n)
			if blink then
				surface.SetDrawColor(230, 60, 50)
				surface.DrawRect(w - UI.S(14), hh / 2 - 4, 8, 8)
			end
		elseif engine.IsPlayingDemo() then
			local t, n = engine.GetDemoPlaybackTick(), engine.GetDemoPlaybackTotalTicks()
			text = string.format(L("sa_dm_tick"), t, n, t * engine.TickInterval(), engine.GetDemoPlaybackTimeScale())
		else
			text = L("sa_dm_live")
		end
		draw.SimpleText(text, "SPeditor.Small", w - UI.S(20), hh / 2, COL.TEXT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	local function btn(text, tip, fn, wide)
		local b = vgui.Create("DButton", bar)
		b:Dock(LEFT)
		b:DockMargin(4, 4, 0, 4)
		b:SetText(text)
		b:SetFont("SPeditor.Small")
		surface.SetFont("SPeditor.Small")
		b:SetWide(wide or (select(1, surface.GetTextSize(text)) + UI.S(14)))
		if tip then b:SetTooltip(tip) end
		UI.StyleButton(b, nil, 3)
		b.DoClick = fn
		return b
	end
	local title = vgui.Create("DLabel", bar)
	title:Dock(LEFT)
	title:DockMargin(8, 0, 4, 0)
	title:SetFont("SPeditor.Bold")
	title:SetTextColor(COL.ORANGE)
	title:SetText("GM:FM")
	title:SizeToContents()
	local recBtn = btn(L("sa_dm_record"), L("sa_dm_record_tip"), function()
		if D then SA.StopDemoRecording() else SA.StartDemoRecording() end
	end, UI.S(110))
	recBtn.Think = function(s)
		local text = L(D and "sa_dm_stop" or "sa_dm_record")
		if s:GetText() ~= text then s:SetText(text) end
	end
	if engine.IsPlayingDemo() then
		btn(L("sa_dm_pause"), nil, function() demoCmd("demo_togglepause") end)
		btn("-5 s", nil, function() demoCmd("demo_gototick", tostring(-math.floor(5 / engine.TickInterval())), "1") end)
		btn("+5 s", nil, function() demoCmd("demo_gototick", tostring(math.floor(5 / engine.TickInterval())), "1") end)
		for _, k in ipairs({ 0.25, 0.5, 1 }) do
			btn(k .. "x", L("sa_dm_speed_tip"), function() demoCmd("demo_timescale", tostring(k)) end)
		end
	end
	if not engine.IsPlayingDemo() then
		-- the game's own demo of what happens now (gm_demo), to be played later from Esc -> Demos
		local demoBtn = btn(L("sa_dm_demo_start"), L("sa_dm_demo_tip"), function() SA.ToggleDemo() end, UI.S(120))
		demoBtn.Think = function(s)
			local text = L(engine.IsRecordingDemo() and "sa_dm_demo_stop" or "sa_dm_demo_start")
			if s:GetText() ~= text then s:SetText(text) end
		end
	end
	btn(L("sa_dm_folder"), nil, function()
		SPeditor.Notify("#sa_dm_where|garrysmod/data/" .. DIR, 0)
	end)
	btn(L("sa_dm_hide"), L("sa_dm_hide_tip"), function() SA.DemoBar(false) end)
end

concommand.Add("gmfm_demo", function() SA.DemoBar() end, nil, "GM:FM: the bar that records a take from a demo (or from the live game)")

---------------------------------------------------------------------
-- A demo without the console (b0.2.6): the game's own gm_demo writes it into garrysmod/demos, where
-- the main menu's Demos list (Esc -> Demos -> Play) finds it; playdemo cannot be run from Lua.
---------------------------------------------------------------------
function SA.ToggleDemo()
	if engine.IsPlayingDemo() then return end
	if not concommand.GetTable().gm_demo then
		SPeditor.Notify("#sa_dm_no_gmdemo", 1)
		return
	end
	RunConsoleCommand("gm_demo")
end

-- the main menu, where the Demos list is
function SA.OpenDemos()
	gui.ActivateGameUI()
	SPeditor.Notify("#sa_dm_menu_hint", 0)
end

local wasRec = engine.IsRecordingDemo()
COMP:Hook("Think", function()
	local rec = engine.IsRecordingDemo()
	if rec == wasRec then return end
	wasRec = rec
	if rec then
		SPeditor.Notify("#sa_dm_demo_on", 0)
		return
	end
	local list = file.Find("demos/*.dem", "MOD", "datedesc") or {}
	SPeditor.Notify("#sa_dm_demo_saved|" .. (list[1] and string.StripExtension(list[1]) or "garrysmod/demos"), 2)
end, "demo_rec_state")

-- the bar comes up by itself when a demo starts playing
local wasDemo = false
COMP:Hook("Think", function()
	local demo = engine.IsPlayingDemo()
	if demo and not wasDemo then
		timer.Simple(1, function() if engine.IsPlayingDemo() then SA.DemoBar(true) end end)
	end
	if not demo and wasDemo and D then SA.StopDemoRecording() end
	wasDemo = demo
end, "demo_bar")

---------------------------------------------------------------------
-- Import (File -> Import demo take): the file goes to the server in pieces
---------------------------------------------------------------------
local PIECE = 60000
local upSerial = 0

function SA.ImportDemoFile(path)
	local data = file.Read(path, "DATA")
	if not data or #data == 0 then
		SPeditor.Notify("#sa_dm_bad", 1)
		return false
	end
	local raw = util.Decompress(data)
	local take = raw and util.JSONToTable(raw)
	if not istable(take) then
		SPeditor.Notify("#sa_dm_bad", 1)
		return false
	end
	-- the take starts at the playhead: the number goes into the file the server gets
	take.at = math.max(math.floor(SA.frame + 0.5), 0)
	local packed = util.Compress(util.TableToJSON(take))
	upSerial = upSerial % 65000 + 1
	local serial = upSerial
	local parts = math.ceil(#packed / PIECE)
	for i = 1, parts do
		-- a piece a game frame: the network does not choke on a big take
		timer.Simple((i - 1) * 0.02, function()
			local piece = string.sub(packed, (i - 1) * PIECE + 1, i * PIECE)
			COMP:NetStart("Demo")
			net.WriteUInt(serial, 16)
			net.WriteUInt(i, 16)
			net.WriteUInt(parts, 16)
			net.WriteUInt(#piece, 32)
			net.WriteData(piece, #piece)
			net.SendToServer()
		end)
	end
	SPeditor.Notify("#sa_dm_importing|" .. #(take.subjects or {}), 0)
	return true
end

-- what a take file holds, read once per file and size
local infoCache = {}
local function takeInfo(path)
	local size = file.Size(path, "DATA") or 0
	local c = infoCache[path]
	if c and c.size == size then return c end
	local raw = util.Decompress(file.Read(path, "DATA") or "")
	local t = raw and util.JSONToTable(raw)
	c = { size = size, map = istable(t) and t.map or "?", len = istable(t) and (tonumber(t.frames) or 0) / math.max(tonumber(t.fps) or 24, 1) or 0,
		n = istable(t) and istable(t.subjects) and #t.subjects or 0, started = istable(t) and t.started or "" }
	infoCache[path] = c
	return c
end

function SA.OpenDemoImport()
	local Dock = SPeditor.Dock
	if Dock.ShowPage("sa_demo") then return end
	local win, body = Dock.Create({ key = "sa_demo", id = "sa_demo", title = L("sa_dm_title"), w = 640, h = 380,
		x = math.floor(ScrW() / 2 - 320), y = 160, dockable = false, icon = "icon16/film_go.png" })
	local hint = vgui.Create("DLabel", body)
	hint:Dock(TOP)
	hint:DockMargin(8, 6, 8, 4)
	hint:SetFont("SPeditor.Small")
	hint:SetTextColor(COL.DIM)
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:SetText(L("sa_dm_hint"))
	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(32))
	foot.Paint = function() end
	local list = vgui.Create("DListView", body)
	list:Dock(FILL)
	list:DockMargin(6, 4, 6, 4)
	list:SetMultiSelect(false)
	UI.StyleListView(list)
	list:AddColumn(L("sa_dm_col_name"))
	list:AddColumn(L("sa_dm_col_map")):SetFixedWidth(UI.S(130))
	list:AddColumn(L("sa_dm_col_len")):SetFixedWidth(UI.S(70))
	list:AddColumn(L("sa_dm_col_n")):SetFixedWidth(UI.S(70))
	local function fill()
		list:Clear()
		local files = file.Find(DIR .. "/*.dat", "DATA", "datedesc") or {}
		for _, f in ipairs(files) do
			local path = DIR .. "/" .. f
			local inf = takeInfo(path)
			local line = list:AddLine(string.StripExtension(f), inf.map, string.format("%.1f s", inf.len), tostring(inf.n))
			line.SPPath, line.SPInfo = path, inf
		end
	end
	fill()
	local function selected()
		local _, line = list:GetSelectedLine()
		return line
	end
	local function import(line)
		line = line or selected()
		if not line then return end
		local go = function()
			if SA.ImportDemoFile(line.SPPath) then win:Close() end
		end
		if line.SPInfo.map ~= game.GetMap() then
			Derma_Query(string.format(L("sa_dm_other_map"), line.SPInfo.map, game.GetMap()), "GM:FM", L("yes"), go, L("cancel"), function() end)
		else
			go()
		end
	end
	list.DoDoubleClick = function(_, _, line) import(line) end
	local go = UI.Button(foot, L("sa_dm_import"), "icon16/film_go.png", function() import() end, 26)
	go:Dock(LEFT)
	go:DockMargin(6, 3, 0, 3)
	go:SetWide(UI.S(220))
	local del = UI.Button(foot, L("sa_dm_delete"), "icon16/bin.png", function()
		local line = selected()
		if not line then return end
		Derma_Query(L("sa_dm_delete_q"), "GM:FM", L("yes"), function()
			file.Delete(line.SPPath)
			fill()
		end, L("cancel"), function() end)
	end, 26)
	del:Dock(LEFT)
	del:DockMargin(6, 3, 0, 3)
	del:SetWide(UI.S(120))
	local rf = UI.Button(foot, L("sa_dm_refresh"), "icon16/arrow_refresh.png", fill, 26)
	rf:Dock(RIGHT)
	rf:DockMargin(0, 3, 6, 3)
	rf:SetWide(UI.S(110))
end

-- File -> Import demo take
COMP:AddMenu("file", function(m)
	local sub, opt = m:AddSubMenu(L("sa_dm_menu"))
	if opt and opt.SetIcon then opt:SetIcon("icon16/film_go.png") end
	sub:AddOption(L(engine.IsRecordingDemo() and "sa_dm_demo_stop" or "sa_dm_demo_start"), function() SA.ToggleDemo() end)
		:SetIcon(engine.IsRecordingDemo() and "icon16/control_stop_blue.png" or "icon16/control_record_blue.png")
	sub:AddOption(L("sa_dm_open_demos"), function() SA.OpenDemos() end):SetIcon("icon16/control_play_blue.png")
	sub:AddOption(L("sa_dm_bar"), function() SA.DemoBar() end):SetIcon("icon16/application_view_columns.png")
	sub:AddSpacer()
	sub:AddOption(L("sa_dm_title") .. "…", function() SA.OpenDemoImport() end):SetIcon("icon16/film_go.png")
end)
