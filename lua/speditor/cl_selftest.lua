--[[
SPeditor — self-test (a0.8): gmfm_selftest goes through what a player does — spawning every
kind of object, moving, posing, faces, colours, attaching, undo, keys and playback, saving and
loading a scene, a picture and a short video, every window and guide — and after each step looks
at the result and at the errors the editor caught (sh_errors.lua). There are no beta testers:
this runs before every release, and a player can run it and send the result with the report.

It needs an empty scene (it makes its own objects and removes them at the end), saves a scene
named _selftest and renders _selftest files, and deletes them afterwards.

  SPeditor.SelfTest.Run()      start (console: gmfm_selftest)
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

-- a convar for the time of a step; the value it had goes back at the end of the test
local function setCvar(ctx, name, value)
	local cv = GetConVar(name)
	if not cv then return end
	if ctx.cvars[name] == nil then ctx.cvars[name] = cv:GetString() end
	RunConsoleCommand(name, tostring(value))
end

-- the brightness of a finished frame: mean and spread of a 24 x 24 grid of its pixels (0..255)
local function measure(rt, W, H)
	render.PushRenderTarget(rt)
	render.CapturePixels()
	local sum, sum2, n = 0, 0, 0
	for gx = 0, 23 do
		for gy = 0, 23 do
			local r, g, b = render.ReadPixel(math.floor((gx + 0.5) / 24 * W), math.floor((gy + 0.5) / 24 * H))
			local v = ((r or 0) + (g or 0) + (b or 0)) / 3
			sum, sum2, n = sum + v, sum2 + v * v, n + 1
		end
	end
	render.PopRenderTarget()
	local mean = sum / n
	return mean, math.sqrt(math.max(sum2 / n - mean * mean, 0))
end

-- one picture through a camera, measured instead of written: ctx.shots[key] = { ok, mean, sd, W, H, t }
local function shoot(ctx, key, cam, extra)
	ctx.shots = ctx.shots or {}
	local t0 = RealTime()
	local opts = { single = true, name = NAME .. "_" .. key, silent = true, camera = cam,
		rtCapture = function(rt, W, H)
			local mean, sd = measure(rt, W, H)
			ctx.shots[key] = { mean = mean, sd = sd, W = W, H = H, fb = GetConVarString("gmfm_render_fullbright"),
				exp = GetConVarString("gmfm_exposure"), eng = GetConVarString("gmfm_render_engine") }
			return true
		end,
		onDone = function(ok)
			ctx.shots[key] = ctx.shots[key] or {}
			ctx.shots[key].ok = ok and true or false
			ctx.shots[key].t = RealTime() - t0
		end }
	for k, v in pairs(extra or {}) do opts[k] = v end
	if not SPeditor.Export.Render(opts) then ctx.shots[key] = { ok = false, refused = true } end
end
local function shot(ctx, key) return ctx.shots and ctx.shots[key] end
-- what the pictures measured: "key 480x270 mean 92 sd 41 0.3 s; …"
local function shotInfo(ctx, keys)
	local out = {}
	for _, k in ipairs(keys) do
		local s = shot(ctx, k)
		if s and s.W then
			out[#out + 1] = string.format("%s %dx%d mean %.0f sd %.0f %.1f s (fb %s exp %s eng %s)", k, s.W, s.H, s.mean or 0, s.sd or 0, s.t or 0,
				s.fb, s.exp, s.eng)
		end
	end
	return table.concat(out, "; ")
end
local function shotDone(ctx, key) local s = shot(ctx, key) return s ~= nil and s.ok ~= nil end
-- a picture that is there and is neither black nor a flat colour
local function shotGood(ctx, key, what)
	local s = shot(ctx, key)
	if not s or s.ok == nil then return false, what .. ": the render did not finish" end
	if s.refused then return false, what .. ": the render was refused" end
	if not s.ok then return false, what .. ": the render failed" end
	if not s.mean then return false, what .. ": no picture" end
	if s.mean < 3 then return false, string.format("%s: black (mean %.1f)", what, s.mean) end
	if s.sd < 1.5 then return false, string.format("%s: one flat colour (mean %.0f)", what, s.mean) end
	return true
end
-- several renders one after another (the renderer takes one job at a time)
local function shootChain(ctx, list)
	local i = 0
	local function nextShot()
		i = i + 1
		local item = list[i]
		if not item then ctx.chainDone = true return end
		if item.cvars then for k, v in pairs(item.cvars) do setCvar(ctx, k, v) end end
		-- a convar takes effect in the next frame
		timer.Simple(0.3, function()
			shoot(ctx, item.key, item.cam or ctx.cam, item.opts)
			local id = "SPeditor.SelfTestChain"
			timer.Create(id, 0.1, 0, function()
				if shotDone(ctx, item.key) then
					timer.Remove(id)
					if item.after then item.after() end
					timer.Simple(0.2, nextShot)
				end
			end)
		end)
	end
	ctx.chainDone = false
	nextShot()
end

---------------------------------------------------------------------
-- The extended tests (a0.9): the render in its extreme settings, cameras, many objects and their
-- limits, animation edits at the edges, and the interface in every theme, scale and language.
-- Every picture is measured (not black, not one flat colour) rather than looked at.
---------------------------------------------------------------------
local EXTRA = {
	{ name = "render: 64 px and 3840 px with smoothing", wait = 60,
		run = function(ctx)
			shootChain(ctx, {
				{ key = "tiny", cvars = { gmfm_render_custom = 1, gmfm_render_w = 64, gmfm_render_h = 64 } },
				{ key = "huge", cvars = { gmfm_render_custom = 0, gmfm_aspect = "16:9", gmfm_render_side = 3840, gmfm_render_ss = 1 },
					after = function() RunConsoleCommand("gmfm_render_ss", "0") RunConsoleCommand("gmfm_render_side", "320") end },
			})
		end,
		done = function(ctx) return ctx.chainDone end,
		check = function(ctx)
			local ok, msg = shotGood(ctx, "tiny", "64 px")
			if not ok then return ok, msg end
			if shot(ctx, "tiny").W ~= 64 then return false, "64 px came out " .. tostring(shot(ctx, "tiny").W) end
			ok, msg = shotGood(ctx, "huge", "3840 px")
			if not ok then return ok, msg end
			local h = shot(ctx, "huge")
			if h.W ~= 3840 or h.H ~= 2160 then return false, string.format("3840 px came out %dx%d", h.W, h.H) end
			return true, nil, shotInfo(ctx, { "tiny", "huge" })
		end },

	{ name = "render: aspects 9:16, 21:9, A-series", wait = 40,
		run = function(ctx)
			shootChain(ctx, {
				{ key = "a916", cvars = { gmfm_aspect = "9:16", gmfm_render_side = 480 } },
				{ key = "a219", cvars = { gmfm_aspect = "21:9" } },
				{ key = "aA", cvars = { gmfm_aspect = "A" } },
			})
		end,
		done = function(ctx) return ctx.chainDone end,
		check = function(ctx)
			for _, k in ipairs({ { "a916", 9 / 16 }, { "a219", 21 / 9 }, { "aA", 1000 / 1414 } }) do
				local ok, msg = shotGood(ctx, k[1], k[1])
				if not ok then return ok, msg end
				local s = shot(ctx, k[1])
				if math.abs(s.W / s.H - k[2]) > 0.02 then return false, string.format("%s came out %dx%d", k[1], s.W, s.H) end
			end
			return true, nil, shotInfo(ctx, { "a916", "a219", "aA" })
		end },

	{ name = "render: fullbright, engine frame, exposure 0 and 8", wait = 60,
		run = function(ctx)
			shootChain(ctx, {
				{ key = "plain", cvars = { gmfm_aspect = "16:9", gmfm_render_side = 480, gmfm_render_engine = 0, gmfm_exposure = 1 } },
				{ key = "fb", cvars = { gmfm_render_fullbright = 1 } },
				{ key = "engine", cvars = { gmfm_render_fullbright = 0, gmfm_render_engine = 1 } },
				{ key = "exp0", cvars = { gmfm_render_engine = 0, gmfm_exposure = 0 } },
				{ key = "exp8", cvars = { gmfm_exposure = 8 }, after = function() RunConsoleCommand("gmfm_exposure", "1") end },
			})
		end,
		done = function(ctx) return ctx.chainDone end,
		check = function(ctx)
			for _, k in ipairs({ "plain", "fb", "engine", "exp0" }) do
				local ok, msg = shotGood(ctx, k, k)
				if not ok then return ok, msg end
			end
			-- a target that stopped taking drawing hands out the same old frame every time
			local p0, f0 = shot(ctx, "plain"), shot(ctx, "fb")
			if math.abs(p0.mean - f0.mean) < 0.05 and math.abs(p0.sd - f0.sd) < 0.05 then
				return false, "fullbright and plain are the very same picture (a stale frame)"
			end
			-- exposure 8 may burn the picture white, but it must be brighter than the plain one
			local p, e = shot(ctx, "plain"), shot(ctx, "exp8")
			if not (e and e.ok and e.mean) then return false, "exposure 8: the render failed" end
			if e.mean < p.mean then return false, string.format("exposure 8 is darker than 1 (%.0f < %.0f)", e.mean, p.mean) end
			return true, nil, shotInfo(ctx, { "plain", "fb", "engine", "exp0", "exp8" })
		end },

	{ name = "render: depth of field 64 passes, aperture 20", wait = 60,
		run = function(ctx)
			shootChain(ctx, {
				{ key = "dof", cvars = { gmfm_dof = 1, gmfm_dof_samples = 64, gmfm_dof_aperture = 20, gmfm_render_side = 480 },
					after = function() RunConsoleCommand("gmfm_dof", "0") end },
			})
		end,
		done = function(ctx) return ctx.chainDone end,
		check = function(ctx)
			local ok, msg = shotGood(ctx, "dof", "depth of field")
			if not ok then return ok, msg end
			return true, nil, shotInfo(ctx, { "dof" })
		end },

	{ name = "camera: every effect at its maximum", wait = 40,
		run = function(ctx)
			local fx = {}
			for _, def in ipairs(SPeditor.FX.Defs or {}) do
				local e = { on = true }
				for _, prm in ipairs(def.params or {}) do
					if isnumber(prm.max) then e[prm.key] = prm.max end
				end
				fx[def.id] = e
			end
			ctx.nFX = table.Count(fx)
			C.SendCameraFX(ctx.cam, fx, true)
			timer.Simple(1, function()
				shootChain(ctx, { { key = "fxall" } })
			end)
		end,
		done = function(ctx) return ctx.chainDone end,
		check = function(ctx)
			local s = shot(ctx, "fxall")
			C.SendCameraFX(ctx.cam, {}, true)
			if not s or not s.ok then return false, "the render with " .. tostring(ctx.nFX) .. " effects failed" end
			-- every effect on at once may well give a strange picture; it must not be black
			if (s.mean or 0) < 1 then return false, "black with every effect on" end
			return true, nil, ctx.nFX .. " effects; " .. shotInfo(ctx, { "fxall" })
		end },

	{ name = "camera: field of view below and above its range, look through it", wait = 4,
		run = function(ctx)
			C.SendCameraEdit(ctx.cam, "fov", 1, true)
			timer.Simple(0.8, function()
				ctx.fov1 = ctx.cam:GetCameraFOV()
				C.SendCameraEdit(ctx.cam, "fov", 170, true)
				timer.Simple(0.8, function()
					ctx.fov170 = ctx.cam:GetCameraFOV()
					C.StartViewCamera(ctx.cam)
					ctx.viewOK = C.GetViewCamera() == ctx.cam
					C.StopViewCamera()
					C.SendCameraEdit(ctx.cam, "fov", 70, true)
				end)
			end)
		end,
		check = function(ctx)
			-- the range of a camera is 10..120° (the same in its controls and on the server)
			if math.abs((ctx.fov1 or 0) - 10) > 0.5 then return false, "FOV 1 was not held at 10: " .. tostring(ctx.fov1) end
			if math.abs((ctx.fov170 or 0) - 120) > 0.5 then return false, "FOV 170 was not held at 120: " .. tostring(ctx.fov170) end
			if not ctx.viewOK then return false, "could not look through the camera" end
			return true
		end },

	{ name = "camera: keeps looking at a moving character", wait = 5,
		run = function(ctx)
			C.SendAim(ctx.cam, ctx.rag, -1)
			timer.Simple(1, function()
				C.SendTransform(ctx.rag, ctx.rag:GetPos() + C.camera.ang:Right() * 80, ctx.rag:GetAngles(), true)
			end)
		end,
		check = function(ctx)
			local to = (C.CenterOf(ctx.rag) - ctx.cam:GetPos()):GetNormalized()
			local dot = ctx.cam:GetAngles():Forward():Dot(to)
			C.SendAim(ctx.cam, nil)
			if dot < 0.97 then return false, string.format("the camera looks %.0f° away", math.deg(math.acos(math.Clamp(dot, -1, 1)))) end
			return true
		end },

	{ name = "camera: shake and smoothness at the maximum", wait = 30,
		run = function(ctx)
			C.SendCameraEdit(ctx.cam, "shake", 40, true)
			C.SendCameraEdit(ctx.cam, "shakerot", 15, true)
			C.SendCameraEdit(ctx.cam, "smooth", 3, true)
			timer.Simple(1, function() shootChain(ctx, { { key = "shake" } }) end)
		end,
		done = function(ctx) return ctx.chainDone end,
		check = function(ctx)
			C.SendCameraEdit(ctx.cam, "shake", 0, true)
			C.SendCameraEdit(ctx.cam, "shakerot", 0, true)
			C.SendCameraEdit(ctx.cam, "smooth", 0, true)
			return shotGood(ctx, "shake", "a shaking camera")
		end },

	{ name = "objects: 25 props at once, then all deleted", wait = 20,
		run = function(ctx)
			ctx.before = snapshot()
			ctx.n0 = #C.Objects()
			for i = 1, 25 do
				local p = front(260) + C.camera.ang:Right() * ((i % 5) - 2) * 40 + Vector(0, 0, math.floor(i / 5) * 30)
				C.SendSpawn("models/props_junk/PopCan01a.mdl", p, Angle(0, i * 14, 0))
			end
			ctx.spawnT = RealTime()
		end,
		done = function(ctx)
			if not ctx.deleted and #C.Objects() >= ctx.n0 + 25 then
				ctx.made = #C.Objects() - ctx.n0
				ctx.deleted = true
				for _, e in ipairs(C.Objects()) do
					if not ctx.before[e] then C.SendDelete(e, true) end
				end
			end
			return ctx.deleted and #C.Objects() <= ctx.n0
		end,
		check = function(ctx)
			if not ctx.made then return false, (#C.Objects() - ctx.n0) .. " of 25 props appeared" end
			if #C.Objects() > ctx.n0 then return false, (#C.Objects() - ctx.n0) .. " props were not deleted" end
			return true
		end },

	{ name = "objects: scale 0.05 and 10, far away and back", wait = 5,
		run = function(ctx)
			ctx.home = ctx.prop:GetPos()
			C.SendScale(ctx.prop, 0.01, true)
			timer.Simple(0.8, function()
				ctx.sMin = ctx.prop:GetModelScale()
				C.SendScale(ctx.prop, 100, true)
				timer.Simple(0.8, function()
					ctx.sMax = ctx.prop:GetModelScale()
					C.SendScale(ctx.prop, 1, true)
					C.SendTransform(ctx.prop, Vector(15000, 15000, 15000), ctx.prop:GetAngles(), true)
					timer.Simple(0.8, function()
						ctx.far = ctx.prop:GetPos()
						C.SendTransform(ctx.prop, ctx.home, ctx.prop:GetAngles(), true)
					end)
				end)
			end)
		end,
		check = function(ctx)
			if not IsValid(ctx.prop) then return false, "the prop is gone" end
			if math.abs((ctx.sMin or 0) - 0.05) > 0.01 then return false, "scale 0.01 was not held at 0.05: " .. tostring(ctx.sMin) end
			if math.abs((ctx.sMax or 0) - 10) > 0.1 then return false, "scale 100 was not held at 10: " .. tostring(ctx.sMax) end
			if ctx.prop:GetPos():Distance(ctx.home) > 2 then return false, "the prop did not come back from far away" end
			return true
		end },

	{ name = "objects: delete, undo brings it back", wait = 6,
		run = function(ctx)
			ctx.propName = C.DisplayName(ctx.prop)
			ctx.n0 = #C.Objects()
			C.SendDelete(ctx.prop)
			timer.Simple(1.5, function()
				ctx.afterDel = #C.Objects()
				C.Undo()
			end)
		end,
		done = function(ctx) return ctx.afterDel ~= nil and #C.Objects() >= ctx.n0 end,
		check = function(ctx)
			if ctx.afterDel ~= ctx.n0 - 1 then return false, "the prop was not deleted" end
			for _, e in ipairs(C.Objects()) do
				if e:GetClass() ~= "prop_ragdoll" and not C.IsAux(e) then ctx.prop = e end
			end
			if #C.Objects() < ctx.n0 then return false, "undo did not bring it back" end
			return true
		end },

	{ name = "objects: long name, hidden, locked", wait = 3,
		run = function(ctx)
			C.SendRename(ctx.prop, string.rep("Ёжик ", 60), true)
			C.SendFlags(ctx.prop, true, true, true)
		end,
		check = function(ctx)
			local name = ctx.prop:GetNW2String("SPeditor_Name", "")
			local hidden, locked = C.IsHidden(ctx.prop), C.IsLocked(ctx.prop)
			C.SendFlags(ctx.prop, false, false, true)
			C.SendRename(ctx.prop, "oildrum", true)
			if name == "" then return false, "the long name was dropped" end
			if #name > 400 then return false, "the name was not cut (" .. #name .. " bytes)" end
			if not hidden or not locked then return false, "hidden / locked did not hold" end
			return true
		end },

	{ name = "lights: brightness 0 and 50, black and white, huge range", wait = 40,
		run = function(ctx)
			local lt = ctx.light
			C.SendLightEdit(lt, SPOT, Color(0, 0, 0), 20000, 0, 170, nil, true, true)
			timer.Simple(1, function()
				shootChain(ctx, {
					{ key = "ldark", after = function() C.SendLightEdit(lt, SPOT, Color(255, 255, 255), 20000, 50, 170, nil, true, true) end },
					{ key = "lbright" },
				})
			end)
		end,
		done = function(ctx) return ctx.chainDone end,
		check = function(ctx)
			C.SendLightEdit(ctx.light, SPOT, Color(255, 240, 220), 600, 2, 60, nil, true, true)
			local a, b = shot(ctx, "ldark"), shot(ctx, "lbright")
			if not (a and a.ok and b and b.ok) then return false, "a render with an extreme light failed" end
			return true, nil, shotInfo(ctx, { "ldark", "lbright" })
		end },

	{ name = "effects: moment 600 s, scale 20, length 8000", wait = 4,
		run = function(ctx) C.SendEffectEdit(ctx.fx, { time = 600, scale = 20, length = 8000 }, true) end,
		check = function(ctx)
			local fx = ctx.fx
			local ok = IsValid(fx) and math.abs(fx:GetFxTime() - 600) < 1 and math.abs(fx:GetFxScale() - 20) < 0.1
			C.SendEffectEdit(fx, { time = 0.25, scale = 1, length = 0 }, true)
			return ok, "the effect did not take the extreme values"
		end },

	{ name = "animation: key before frame 0, key past the end", wait = 6,
		run = function(ctx)
			local A = SA()
			ctx.frames0 = A.frames
			ctx.keys0 = #(A.tracks[A.UID(ctx.rag)] or {})
			A.SetKey({ ctx.rag }, -12, true)
			timer.Simple(1.5, function() A.SetKey({ ctx.rag }, A.frames + 30, true) end)
		end,
		check = function(ctx)
			local A = SA()
			local keys = A.tracks[A.UID(ctx.rag)] or {}
			if #keys < ctx.keys0 + 2 then return false, (#keys - ctx.keys0) .. " of 2 new keys" end
			if A.frames < ctx.frames0 + 12 + 30 then return false, string.format("the animation is %d frames, not %d+", A.frames, ctx.frames0 + 42) end
			if keys[1].f ~= 0 then return false, "the first key is not at frame 0" end
			return true
		end },

	{ name = "animation: tracks, shots, speed of the film", wait = 6,
		run = function(ctx)
			local A = SA()
			ctx.g0 = #A.groups
			A.NewGroup("selftest", { ctx.rag, ctx.prop })
			A.AddCut(0, ctx.cam)
			timer.Simple(1.5, function()
				ctx.g1 = #A.groups
				ctx.inGroup = A.GroupOf(A.UID(ctx.rag)) ~= nil
				ctx.cuts = #A.cuts
				ctx.framesBefore = A.frames
				A.SpeedRange(0, 24, 2)
				timer.Simple(1.5, function()
					ctx.framesAfter = A.frames
					A.DeleteGroup(ctx.g1)
				end)
			end)
		end,
		check = function(ctx)
			if (ctx.g1 or 0) ~= ctx.g0 + 1 or not ctx.inGroup then return false, "the track was not made" end
			if (ctx.cuts or 0) < 1 then return false, "the shot was not added" end
			if not ctx.framesAfter or ctx.framesAfter >= ctx.framesBefore then return false, "x2 speed did not shorten the film" end
			if #SA().groups ~= ctx.g0 then return false, "the track was not deleted" end
			return true
		end },

	{ name = "animation: ghosts, the path, playback through cuts", wait = 5,
		run = function(ctx)
			local A = SA()
			setCvar(ctx, "gmfm_ghosts", 1)
			C.Select(ctx.rag)
			A.Seek(6)
			timer.Simple(1.5, function() A.Seek(0) A.Play(true) end)
			timer.Simple(3.5, function() A.Play(false) end)
		end,
		check = function() return true end },

	{ name = "interface: every theme", wait = 60,
		run = function(ctx)
			setCvar(ctx, "gmfm_theme", GetConVarString("gmfm_theme"))
			local list = {}
			for _, t in ipairs(UI.Themes or {}) do list[#list + 1] = t.id end
			ctx.themes, ctx.themeI = list, 0
			local function nextTheme()
				ctx.themeI = ctx.themeI + 1
				local id = list[ctx.themeI]
				if not id then ctx.themesDone = true return end
				UI.SetTheme(id)
				timer.Simple(1.2, nextTheme)
			end
			nextTheme()
		end,
		done = function(ctx) return ctx.themesDone end,
		check = function(ctx)
			RunConsoleCommand("gmfm_theme", ctx.cvars.gmfm_theme)
			if not ctx.themesDone then return false, "stopped at theme " .. tostring(ctx.themes[ctx.themeI]) end
			return #ctx.themes > 0, "no themes"
		end },

	{ name = "interface: scale 75 % and 200 %, both languages", wait = 16,
		run = function(ctx)
			setCvar(ctx, "gmfm_ui_scale", 75)
			timer.Simple(0.3, function() UI.Rebuild() end)
			timer.Simple(3, function() setCvar(ctx, "gmfm_ui_scale", 200) end)
			timer.Simple(3.3, function() UI.Rebuild() end)
			timer.Simple(6, function()
				RunConsoleCommand("gmfm_ui_scale", ctx.cvars.gmfm_ui_scale)
				setCvar(ctx, "gmfm_language", GetConVarString("gmfm_language") == "ru" and "en" or "ru")
			end)
			timer.Simple(6.3, function() UI.Rebuild() end)
			timer.Simple(9, function() RunConsoleCommand("gmfm_language", ctx.cvars.gmfm_language) end)
			timer.Simple(9.3, function() UI.Rebuild() ctx.uiDone = true end)
		end,
		done = function(ctx) return ctx.uiDone end,
		check = function() return C.active and IsValid(UI.PrimaryVP), "the editor did not come back" end },

	{ name = "interface: browsers and their previews", wait = 6,
		run = function(ctx)
			UI.BuildBrowser()
			UI.BuildEffects()
			timer.Simple(0.8, function()
				local function find(p, test)
					for _, c in ipairs(p:GetChildren()) do
						if test(c) then return c end
						local r = find(c, test)
						if r then return r end
					end
				end
				local mp = find(Dock.ByKey("browser"), function(c) return c.SetModel and c.SPDraw end)
				local pp = find(Dock.ByKey("effects"), function(c) return c.SetEffect end)
				ctx.mp, ctx.pp = mp, pp
				if mp then mp:SetModel("models/player/alyx.mdl") end
				if pp then pp:SetEffect({ src = "pcf", name = "explosion_turret_break", file = "" }) end
			end)
		end,
		check = function(ctx)
			if not IsValid(ctx.mp) then return false, "no model preview" end
			if not IsValid(ctx.pp) then return false, "no particle preview" end
			if not ctx.mp.SPReady then return false, "the model preview drew nothing" end
			if not ctx.pp.SPPS then return false, "the particle preview did not start" end
			for _, k in ipairs({ "browser", "effects" }) do
				local w = Dock.ByKey(k)
				if IsValid(w) then w:Remove() end
				Dock.pages[k] = nil
			end
			return true
		end },
	{ name = "render targets that stopped taking drawing", wait = 0.5,
		run = function() end,
		check = function()
			local n = SPeditor.Render.deadTargets or 0
			-- replaced on the fly (cl_render.lua liveRT): not a failure, but worth knowing
			return true, nil, n == 0 and "none" or (n .. " replaced by new ones")
		end },
}

---------------------------------------------------------------------
-- The steps: run(ctx) does the thing; after `wait` seconds (or as soon as `done(ctx)` is true,
-- at most `wait`) check(ctx) says whether it worked: true, or false + why.
---------------------------------------------------------------------
local STEPS = {
	{ name = "open the editor", wait = 3,
		run = function(ctx) if not C.active then ctx.opened = true RunConsoleCommand("gmfm_toggle") end end,
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
				if C.IsEffect(e) then ctx.fx = e end
				if C.IsLight(e) and e:GetLightType() == SPOT then ctx.light = e end
				if e:GetClass() ~= "prop_ragdoll" and not C.IsAux(e) then ctx.prop = e end
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

-- the extended tests go in before the windows are opened (the last step)
for i, st in ipairs(EXTRA) do table.insert(STEPS, #STEPS, st) end

---------------------------------------------------------------------
-- Running
---------------------------------------------------------------------
local CVARS = { gmfm_render_side = "320", gmfm_render_done_window = "0", gmfm_render_slowfx = "0",
	gmfm_render_ss = "0", gmfm_dof = "0" }

local function cleanup(ctx, done)
	local A = SA()
	timer.Remove("SPeditor.SelfTestChain")
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
			-- the themes, scales and languages rebuilt the interface: the windows go back where they were
			if ctx.layout and C.active then
				Dock.Apply(ctx.layout)
				Dock.SaveLast()
			end
			C.sceneName = nil
			if A then A.SetConfig(ctx.fps or 24, ctx.frames or 96, ctx.loop or false) end
			if ctx.opened and C.active then RunConsoleCommand("gmfm_toggle") end
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
	-- the layout of the windows, put back at the end (rebuilding the interface rewrites it)
	local raw = file.Read("speditor/layouts/_last.json", "DATA")
	ctx.layout = raw and util.JSONToTable(raw) or nil
	T.running = true
	local result = { ok = 0, fail = 0, steps = {}, started = os.date("%Y-%m-%d %H:%M") }
	print("[GM:FM] self-test started")
	SPeditor.Notify("#st_started", 0)

	local i = 0
	local function nextStep()
		i = i + 1
		local st = STEPS[i]
		if not st then
			cleanup(ctx, function()
				T.running = false
				T.last = result
				print(string.format("[GM:FM] self-test: %d passed, %d failed", result.ok, result.fail))
				SPeditor.Notify(string.format(L("st_done"), result.ok, result.fail), result.fail == 0 and 2 or 1)
				if UI.ShowSelfTest then UI.ShowSelfTest(result) end
			end)
			return
		end
		local errs0 = #SPeditor.Errors.list
		local t0 = RealTime()
		ctx.chainDone = nil
		T.step = st.name
		local okRun, errRun = pcall(st.run, ctx)
		local function finish()
			local ok, msg = false, nil
			if not okRun then
				msg = "error: " .. tostring(errRun)
			else
				local okC, r, m, info = pcall(st.check, ctx)
				if not okC then
					msg = "error: " .. tostring(r)
				else
					ok = r and true or false
					if ok then msg = info else msg = m end
				end
			end
			-- an error caught by the editor during the step fails it too
			local list = SPeditor.Errors.list
			if #list > errs0 then
				ok = false
				local e = list[errs0 + 1]
				msg = (msg and not ok and (msg .. "; ") or "") .. "[" .. e.realm .. "] " .. e.msg
			end
			if ok then result.ok = result.ok + 1 else result.fail = result.fail + 1 end
			-- a passed step may say what it measured (sizes, brightness, times of the renders)
			result.steps[#result.steps + 1] = { name = st.name, ok = ok, msg = (not ok) and (msg or "?") or msg, t = RealTime() - t0 }
			print(string.format("[GM:FM] self-test %2d. %-44s %s%s", i, st.name, ok and "OK" or "FAIL", msg and ("  " .. tostring(msg)) or ""))
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

concommand.Add("gmfm_selftest", function() T.Run() end)

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
