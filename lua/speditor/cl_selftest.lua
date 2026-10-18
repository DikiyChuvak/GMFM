--[[
SPeditor — self-test (a0.8): speditor_selftest goes through what a player does — spawning every
kind of object, moving, posing, faces, colours, attaching, undo, keys and playback, saving and
loading a scene, a picture and a short video, every window and guide — and after each step looks
at the result and at the errors the editor caught (sh_errors.lua). There are no beta testers:
this runs before every release, and a player can run it and send the result with the report.

It needs an empty scene (it makes its own objects and removes them at the end), saves a scene
named _selftest and renders _selftest files, and deletes them afterwards.

  SPeditor.SelfTest.Run()      start (console: speditor_selftest)
  SPeditor.SelfTest.last       { ok = n, fail = n, steps = { { name, ok, msg, t }, … } }
]]
SPeditor = SPeditor or {}
SPeditor.SelfTest = SPeditor.SelfTest or {}
local T    = SPeditor.SelfTest
local C    = SPeditor.Client
local UI   = SPeditor.UI
local L    = SPeditor.L
local Dock = SPeditor.Dock

local NAME = "_selftest"
local SPOT, POINT = 1, 0

-- the scene object that appeared since the list "before" (the newest one of that kind)
local function newObject(before, test)
	local found
	for _, e in ipairs(C.Objects()) do
		if IsValid(e) and not before[e] and (not test or test(e)) then found = e end
	end
	return found
end

local function snapshot()
	local set = {}
	for _, e in ipairs(C.Objects()) do set[e] = true end
	return set
end

local function front(d)
	local cam = C.camera
	return cam.pos + Angle(0, cam.ang.y, 0):Forward() * (d or 150)
end

local function SA() return SPeditor.Component and SPeditor.Component("saeditor").SA end

---------------------------------------------------------------------
-- The steps: run(ctx) does the thing; after `wait` seconds (or as soon as `done(ctx)` is true,
-- at most `wait`) check(ctx) says whether it worked: true, or false + why.
---------------------------------------------------------------------
local STEPS = {
	{ name = "open the editor", wait = 3,
		run = function(ctx) if not C.active then ctx.opened = true RunConsoleCommand("speditor_toggle") end end,
		done = function() return C.active end,
		check = function() return C.active, "the editor did not open" end },

	{ name = "spawn a character", wait = 4,
		run = function(ctx) ctx.before = snapshot() C.SendSpawn("models/player/alyx.mdl", front(), Angle(0, C.camera.ang.y + 180, 0)) end,
		done = function(ctx) ctx.rag = newObject(ctx.before, function(e) return e:GetClass() == "prop_ragdoll" end) return IsValid(ctx.rag) end,
		check = function(ctx) return IsValid(ctx.rag), "no ragdoll appeared" end },

	{ name = "spawn a prop", wait = 4,
		run = function(ctx) ctx.before = snapshot() C.SendSpawn("models/props_c17/oildrum001.mdl", front(120) + C.camera.ang:Right() * 60, Angle(0, 0, 0)) end,
		done = function(ctx) ctx.prop = newObject(ctx.before, function(e) return e:GetClass() ~= "prop_ragdoll" and not C.IsAux(e) end) return IsValid(ctx.prop) end,
		check = function(ctx) return IsValid(ctx.prop), "no prop appeared" end },

	{ name = "spawn a spot light and a point light", wait = 4,
		run = function(ctx)
			ctx.before = snapshot()
			local p = front(100) + Vector(0, 0, 80)
			C.SendLightSpawn(SPOT, p, (front() - p):Angle(), Color(255, 240, 220), 600, 2, 60)
			C.SendLightSpawn(POINT, p + C.camera.ang:Right() * 80, Angle(0, 0, 0), Color(220, 230, 255), 400, 1, 90)
		end,
		done = function(ctx)
			local n = 0
			for _, e in ipairs(C.Objects()) do if not ctx.before[e] and C.IsLight(e) then n = n + 1 ctx.light = e end end
			return n >= 2
		end,
		check = function(ctx)
			local n = 0
			for _, e in ipairs(C.Objects()) do if not ctx.before[e] and C.IsLight(e) then n = n + 1 end end
			return n >= 2, n .. " of 2 lights appeared"
		end },

	{ name = "spawn a camera", wait = 4,
		run = function(ctx) ctx.before = snapshot() C.SendCameraSpawn(C.camera.pos, C.camera.ang) end,
		done = function(ctx) ctx.cam = newObject(ctx.before, function(e) return C.IsCamera(e) end) return IsValid(ctx.cam) end,
		check = function(ctx) return IsValid(ctx.cam), "no camera appeared" end },

	{ name = "spawn a particle effect", wait = 4,
		run = function(ctx) ctx.before = snapshot() C.SendEffectSpawn({ src = "pcf", name = "explosion_turret_break", file = "" }, front(200)) end,
		done = function(ctx) ctx.fx = newObject(ctx.before, function(e) return C.IsEffect(e) end) return IsValid(ctx.fx) end,
		check = function(ctx) return IsValid(ctx.fx), "no effect appeared" end },

	{ name = "move an object", wait = 2,
		run = function(ctx)
			C.Select(ctx.prop)
			ctx.p0 = ctx.prop:GetPos()
			C.SendTransform(ctx.prop, ctx.p0 + Vector(0, 0, 30), ctx.prop:GetAngles(), true)
		end,
		check = function(ctx) return IsValid(ctx.prop) and ctx.prop:GetPos().z > ctx.p0.z + 20, "the prop did not move" end },

	-- a ragdoll is drawn from the turns of its bodies: turning the upper arm must carry the hand
	{ name = "pose bones (a physical one and a plain one)", wait = 2,
		run = function(ctx)
			local rag = ctx.rag
			C.Select(rag)
			local arm = rag:LookupBone("ValveBiped.Bip01_R_UpperArm")
			local hand = rag:LookupBone("ValveBiped.Bip01_R_Hand")
			local phys = arm and C.PhysIndexOfBone(rag, arm)
			local m, mh = arm and rag:GetBoneMatrix(arm), hand and rag:GetBoneMatrix(hand)
			if phys and m and mh then
				ctx.h0 = mh:GetTranslation()
				local a = m:GetAngles()
				a:RotateAroundAxis(m:GetAngles():Right(), 60)     -- swings the arm: the hand travels far
				C.SendPhysBone(rag, phys, m:GetTranslation(), a, true)
			end
			local finger = rag:LookupBone("ValveBiped.Bip01_R_Finger1")
			if finger then C.SendBoneManip(rag, finger, Vector(0, 0, 0), Angle(0, 40, 0), Vector(1, 1, 1), true) end
			ctx.finger = finger
		end,
		check = function(ctx)
			local rag = ctx.rag
			local hand = rag:LookupBone("ValveBiped.Bip01_R_Hand")
			local m = hand and rag:GetBoneMatrix(hand)
			if not (m and ctx.h0) then return false, "no arm bones" end
			if m:GetTranslation():Distance(ctx.h0) < 8 then return false, "the arm did not turn" end
			if ctx.finger and rag:GetManipulateBoneAngles(ctx.finger).y < 30 then return false, "the finger did not turn" end
			return true
		end },

	{ name = "face, colour of a material, scale", wait = 2,
		run = function(ctx)
			if ctx.rag:GetFlexNum() > 0 then C.EditFlex(ctx.rag, 0, 0.8) end
			C.EditLook(ctx.rag, { tints = { ["5"] = { 200, 60, 60 } } }, true)
			C.SendScale(ctx.prop, 1.5, true)
		end,
		check = function(ctx)
			if ctx.rag:GetNW2String("SPeditor_Tints", "") == "" then return false, "the material colour was not kept" end
			if math.abs((ctx.prop:GetModelScale() or 1) - 1.5) > 0.05 then return false, "the scale did not change" end
			return true
		end },

	{ name = "attach a prop to a hand, then detach", wait = 2,
		run = function(ctx) C.SendAttach(ctx.prop, ctx.rag, ctx.rag:LookupBone("ValveBiped.Bip01_R_Hand") or -1) end,
		check = function(ctx)
			if ctx.prop:GetNW2Entity("SPeditor_Parent") ~= ctx.rag then return false, "the prop is not attached" end
			C.SendAttach(ctx.prop, nil, -1)
			return true
		end },

	{ name = "undo and redo", wait = 3,
		run = function(ctx)
			for i = 1, 4 do C.Undo() end
			timer.Simple(1, function() for i = 1, 4 do C.Redo() end end)
		end,
		check = function(ctx) return IsValid(ctx.rag) and IsValid(ctx.prop), "objects were lost" end },

	{ name = "duplicate", wait = 3,
		run = function(ctx) ctx.n = #C.Objects() C.SendDuplicate(ctx.cam) end,
		done = function(ctx) return #C.Objects() > ctx.n end,
		check = function(ctx) return #C.Objects() > ctx.n, "no copy appeared" end },

	{ name = "keys, smooth motion, playback", wait = 6,
		run = function(ctx)
			local A = SA()
			ctx.uid = A.UID(ctx.rag)
			A.SetKey({ ctx.rag }, 0, true)
			A.Seek(12, function()
				C.SendTransform(ctx.rag, ctx.rag:GetPos() + Vector(40, 0, 0), ctx.rag:GetAngles(), true)
				timer.Simple(0.5, function()
					A.SetKey({ ctx.rag }, 12, true)
					timer.Simple(0.5, function()
						A.SmoothAll()
						A.Seek(0)
						A.Play(true)
						timer.Simple(1.5, function() A.Play(false) end)
					end)
				end)
			end)
		end,
		check = function(ctx)
			local keys = SA().tracks[ctx.uid] or {}
			return #keys >= 2, #keys .. " keys instead of 2"
		end },

	{ name = "save, clear and load the scene", wait = 14,
		run = function(ctx)
			ctx.saved = #C.Objects()
			C.SceneSave(NAME, C.GetSceneMeta())
			timer.Simple(2, function() C.SendCleanup() end)
			timer.Simple(4, function() ctx.cleared = #C.Objects() C.SceneLoad(NAME) end)
		end,
		done = function(ctx) return ctx.cleared ~= nil and #C.Objects() >= ctx.saved end,
		check = function(ctx)
			if ctx.cleared ~= 0 then return false, "clearing left " .. tostring(ctx.cleared) .. " objects" end
			if #C.Objects() < ctx.saved then return false, #C.Objects() .. " of " .. ctx.saved .. " objects came back" end
			-- the objects are new entities after loading
			for _, e in ipairs(C.Objects()) do
				if e:GetClass() == "prop_ragdoll" then ctx.rag = e end
				if C.IsCamera(e) then ctx.cam = e end
			end
			return true
		end },

	{ name = "render a picture", wait = 40,
		run = function(ctx)
			SPeditor.Export.Render({ single = true, name = NAME, format = "jpeg", silent = true, camera = ctx.cam,
				onDone = function(ok) ctx.pic = ok and true or false end })
		end,
		done = function(ctx) return ctx.pic ~= nil end,
		check = function(ctx) return ctx.pic == true, ctx.pic == nil and "the render did not finish" or "the render failed" end },

	{ name = "render a short video", wait = 90,
		run = function(ctx)
			local A = SA()
			if not A.RenderSequence({ from = 0, to = 6, name = NAME .. "_anim", camera = ctx.cam,
				onDone = function(ok) ctx.vid = ok and true or false end }) then ctx.vid = false end
		end,
		done = function(ctx) return ctx.vid ~= nil end,
		check = function(ctx) return ctx.vid == true, ctx.vid == nil and "the video did not finish" or "the video failed" end },

	{ name = "open every window and guide", wait = 4,
		run = function(ctx)
			local A = SA()
			ctx.winFail = {}
			ctx.winBefore = {}
			for _, w in ipairs(Dock.windows) do ctx.winBefore[w] = true end
			local list = {
				{ "render", function() UI.OpenRenderDialog() end },
				{ "properties", function() UI.OpenObjectProps(ctx.rag) end },
				{ "settings", function() UI.OpenSettings() end },
				{ "about", function() UI.OpenAbout() end },
				{ "files", function() UI.OpenFileLocations() end },
				{ "work camera", function() UI.OpenCameraSettings() end },
				{ "hotkeys", function() UI.OpenHotkeys() end },
				{ "report", function() UI.OpenReport() end },
				{ "shaders", function() UI.OpenShaders() end },
				{ "notifications", function() UI.OpenNotifyLog() end },
				{ "adopt", function() UI.OpenAdopt() end },
				{ "curves", function() A.OpenCurves() end },
				{ "record", function() A.OpenRecord() end },
				{ "sounds", function() A.OpenSounds() end },
				{ "procedural", function() A.OpenProc(ctx.rag) end },
				{ "SMH", function() A.OpenSMH() end },
			}
			for id in pairs(UI.Guides or {}) do
				list[#list + 1] = { "guide " .. id, function() UI.OpenGuide(id) end }
			end
			for _, item in ipairs(list) do
				local ok, err = pcall(item[2])
				if not ok then ctx.winFail[#ctx.winFail + 1] = item[1] .. ": " .. tostring(err) end
			end
		end,
		-- the windows have been drawn for a few seconds by now (their errors are counted); closed
		check = function(ctx)
			for _, w in ipairs(table.Copy(Dock.windows)) do
				if not ctx.winBefore[w] and IsValid(w) then w:Remove() end
			end
			if #ctx.winFail > 0 then return false, table.concat(ctx.winFail, "; ") end
			return true
		end },
}

---------------------------------------------------------------------
-- Running
---------------------------------------------------------------------
local CVARS = { speditor_render_side = "320", speditor_render_done_window = "0", saeditor_render_slowfx = "0",
	speditor_render_ss = "0", speditor_dof = "0" }

local function cleanup(ctx, done)
	local A = SA()
	if A and A.rendering then A.StopRender(false) end
	if A then A.ClearAll() end
	timer.Simple(0.5, function()
		C.SendCleanup()
		C.SceneDelete(NAME)
		for _, f in ipairs(file.Find("speditor/renders/" .. NAME .. "*", "DATA") or {}) do file.Delete("speditor/renders/" .. f) end
		for _, d in ipairs(select(2, file.Find("speditor/renders/*", "DATA")) or {}) do
			if string.StartWith(d, NAME) then
				for _, f in ipairs(file.Find("speditor/renders/" .. d .. "/*", "DATA") or {}) do file.Delete("speditor/renders/" .. d .. "/" .. f) end
				file.Delete("speditor/renders/" .. d)
			end
		end
		for k, v in pairs(ctx.cvars or {}) do RunConsoleCommand(k, v) end
		timer.Simple(1.5, function()
			C.sceneName = nil
			if A then A.SetConfig(ctx.fps or 24, ctx.frames or 96, ctx.loop or false) end
			if ctx.opened and C.active then RunConsoleCommand("speditor_toggle") end
			done()
		end)
	end)
end

function T.Run()
	if T.running then return end
	if C.active and #C.Objects() > 0 or (not C.active and #ents.FindByClass("speditor_*") > 0) then
		SPeditor.Notify("#st_need_empty", 1)
		return
	end
	local A = SA()
	local ctx = { cvars = {}, fps = A and A.fps, frames = A and A.frames, loop = A and A.loop }
	for k, v in pairs(CVARS) do
		local cv = GetConVar(k)
		if cv then ctx.cvars[k] = cv:GetString() RunConsoleCommand(k, v) end
	end
	T.running = true
	local result = { ok = 0, fail = 0, steps = {}, started = os.date("%Y-%m-%d %H:%M") }
	print("[SPeditor] self-test started")
	SPeditor.Notify("#st_started", 0)

	local i = 0
	local function nextStep()
		i = i + 1
		local st = STEPS[i]
		if not st then
			cleanup(ctx, function()
				T.running = false
				T.last = result
				print(string.format("[SPeditor] self-test: %d passed, %d failed", result.ok, result.fail))
				SPeditor.Notify(string.format(L("st_done"), result.ok, result.fail), result.fail == 0 and 2 or 1)
				if UI.ShowSelfTest then UI.ShowSelfTest(result) end
			end)
			return
		end
		local errs0 = #SPeditor.Errors.list
		local t0 = RealTime()
		local okRun, errRun = pcall(st.run, ctx)
		local function finish()
			local ok, msg = false, nil
			if not okRun then
				msg = "error: " .. tostring(errRun)
			else
				local okC, r, m = pcall(st.check, ctx)
				if not okC then msg = "error: " .. tostring(r) else ok, msg = r and true or false, m end
			end
			-- an error caught by the editor during the step fails it too
			local list = SPeditor.Errors.list
			if #list > errs0 then
				ok = false
				local e = list[errs0 + 1]
				msg = (msg and not ok and (msg .. "; ") or "") .. "[" .. e.realm .. "] " .. e.msg
			end
			if ok then result.ok = result.ok + 1 else result.fail = result.fail + 1 end
			result.steps[#result.steps + 1] = { name = st.name, ok = ok, msg = (not ok) and (msg or "?") or nil, t = RealTime() - t0 }
			print(string.format("[SPeditor] self-test %2d. %-44s %s%s", i, st.name, ok and "OK" or "FAIL", ok and "" or ("  " .. tostring(msg))))
			-- a step that lost the objects the next ones need ends the test
			if not ok and i <= 6 then i = #STEPS end
			timer.Simple(0.3, nextStep)
		end
		if not okRun then finish() return end
		local id = "SPeditor.SelfTest"
		timer.Create(id, 0.1, 0, function()
			local waited = RealTime() - t0
			local ready = st.done and select(2, pcall(st.done, ctx)) == true
			if waited >= st.wait or (ready and waited >= 0.5) then
				timer.Remove(id)
				finish()
			end
		end)
	end
	nextStep()
end

concommand.Add("speditor_selftest", function() T.Run() end)

---------------------------------------------------------------------
-- The result window
---------------------------------------------------------------------
function UI.ShowSelfTest(result)
	local old = Dock.ByKey("selftest")
	if IsValid(old) then old:Remove() end
	local COL = UI.PAL
	local W = 600
	local win, body = Dock.Create({ key = "selftest", id = "selftest", title = L("st_title"), w = W, h = 520,
			x = math.floor(ScrW() / 2 - W / 2), y = 110, dockable = false, icon = "icon16/tick.png" })
	win.minW, win.minH = UI.S(420), UI.S(300)
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.selftest = nil
	end
	local head = UI.Label(body, string.format(L("st_done"), result.ok, result.fail), result.fail == 0 and Color(140, 220, 140) or Color(240, 150, 120))
	head:SetFont("SPeditor.Bold")
	head:DockMargin(10, 8, 10, 4)
	local list = vgui.Create("DListView", body)
	UI.StyleListView(list)
	list:Dock(FILL)
	list:DockMargin(10, 2, 10, 6)
	list:AddColumn(L("st_col_step"))
	list:AddColumn(L("st_col_result")):SetFixedWidth(UI.S(60))
	list:AddColumn(L("st_col_time")):SetFixedWidth(UI.S(50))
	for _, s in ipairs(result.steps) do
		local line = list:AddLine(s.name, s.ok and "OK" or "FAIL", string.format("%.1f", s.t))
		if s.msg then line:SetTooltip(s.msg) end
	end
	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(34))
	foot.Paint = function() end
	local rep = vgui.Create("DButton", foot)
	rep:Dock(LEFT)
	rep:DockMargin(8, 5, 4, 5)
	rep:SetWide(UI.S(200))
	rep:SetText(L("rep_title") .. "…")
	UI.StyleButton(rep, nil, 3)
	rep.DoClick = function() UI.OpenReport() end
	local close = vgui.Create("DButton", foot)
	close:Dock(RIGHT)
	close:DockMargin(4, 5, 8, 5)
	close:SetWide(UI.S(100))
	close:SetText(L("about_close"))
	UI.StyleButton(close, nil, 3)
	close.DoClick = function() win:Remove() end
	return win
end
