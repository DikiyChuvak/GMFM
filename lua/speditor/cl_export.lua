--[[
SPeditor — frame export.

Rendering goes to an off-screen render target of the needed size, so the interface
does not have to be hidden and the resolution does not depend on the monitor. The
parameters come from the Render window (cl_ui_render.lua): camera, aspect ratio, size,
fullbright, format (PNG / JPEG / Steam screenshot).
Files: data/speditor/renders/<name>.png|jpg

Steam screenshot (a0.6): Lua cannot add a picture to the Steam screenshot library, but the
engine's "jpeg" command does (verified in game: the shot lands both in garrysmod/screenshots
and in Steam → Screenshots → Garry's Mod, where it can be published). So the finished render
is shown over the whole screen for a few frames — fitted into it, black bars if the aspect
differs — and the engine shoots the screen. The size of such a shot is the size of the screen.

Per the wiki, render.Capture shoots the CURRENT render target (hence PushRenderTarget)
and returns nil if the ESC menu is open.
]]
SPeditor = SPeditor or {}
SPeditor.Export = SPeditor.Export or {}
local C = SPeditor.Client
local L = SPeditor.L

local EXPORT_DIR = (SPeditor.Config and SPeditor.Config.SaveDir or "speditor") .. "/renders"

local function ensureDir(dir)
	local acc = ""
	for part in string.gmatch(dir or EXPORT_DIR, "[^/]+") do
		acc = (acc == "") and part or (acc .. "/" .. part)
		if not file.IsDir(acc, "DATA") then file.CreateDir(acc) end
	end
end

SPeditor.Export.pending = nil
local STALE_JOB = 20    -- s: the longest a job may wait (effects 12 s, engine frame 5 s)

-- opts: { camera = Entity | nil (SceneCamera: the Primary Viewport's camera or the first one), name = string,
-- nodof = true — without depth of field (the frames of an animation),
-- dir = subfolder in renders (frame sequences), silent = no success notification,
-- format = "png" | "jpeg" | "steam" (otherwise from the settings), onDone = function(ok, path),
-- single = true — exactly one frame, without asking SAeditor,
-- quality = JPEG quality (otherwise from the settings),
-- capture = function(data, W, H) — the encoded frame is handed over instead of being written
-- rtCapture = function(rt, W, H) — the finished frame itself (a texture), nothing is encoded
--   (the WebM video: the engine's writer takes the screen, cl_saeditor_video.lua)
-- to a file (return false on failure); onDone then gets no path,
-- warmup = game frames skipped in "engine frame" mode (for frame sequences: the effects are
-- already settled by the previous frame), sampleScale = 0..1 — part of the depth of field and
-- soft shadow passes to make (frame sequences: neighbouring frames hide the difference),
-- accum = { i, n } — motion blur (SAeditor): the frame is the i-th of n moments of one video
-- frame; it is averaged with the ones before, and only the n-th is captured (onDone(true) for the rest) }
-- Returns true if the job was accepted.
-- Before rendering SAeditor is asked (the SPeditor_RenderRequest hook): when it knows
-- the scene is more than one frame (SAeditor: the scene has animation) renders it itself and
-- returns true. It makes its own per-frame calls with single = true.
function SPeditor.Export.Render(opts)
	opts = opts or {}
	if not opts.single and hook.Run("SPeditor_RenderRequest", opts) == true then return true end
	-- a job that has not been taken for long (its PostRender hook did not run: another addon's
	-- PostRender hook returned a value and cut the event short) is dropped instead of keeping
	-- the Render button dead until the map is reloaded (b0.2.1)
	local stale = SPeditor.Export.pending
	if stale and RealTime() - (stale.queued or 0) > STALE_JOB then
		SPeditor.Export.pending = nil
		if stale.onDone then pcall(stale.onDone, false) end
	end
	if SPeditor.Export.pending then
		if not opts.silent then SPeditor.Notify(L("render_busy"), 1) end
		return false
	end
	-- (b0.2.6) without a camera in the scene the picture is shot through the work camera
	if not SPeditor.Export.SceneCamera(opts.camera) and not opts.silent then SPeditor.Notify("#sa_rnd_workcam", 0) end
	local fmt = opts.format or GetConVar("gmfm_render_format"):GetString()
	SPeditor.Export.pending = {
		camera     = opts.camera,
		fullbright = GetConVar("gmfm_render_fullbright"):GetBool(),
		ss         = GetConVar("gmfm_render_ss"):GetBool() and 2 or 1,
		-- no depth of field in the frames of an animation (a0.9): the few passes per frame gave
		-- ghost copies and a smeared picture
		nodof      = opts.nodof and true or nil,
		dof        = not opts.nodof and GetConVar("gmfm_dof"):GetBool(),
		-- camdof = true (b0.1): the frames of an animation keep the depth of field of the
		-- camera itself (its keyed camera effect, the focus pulled from key to key), with all
		-- of its passes
		camdof     = opts.camdof and true or nil,
		aperture   = math.Clamp(GetConVar("gmfm_dof_aperture"):GetFloat(), 0.05, 20),
		samples    = math.Clamp(GetConVar("gmfm_dof_samples"):GetInt(), 2, 128),
		engine     = SPeditor.Render.EngineFor(GetConVar("gmfm_render_fullbright"):GetBool()),
		single     = opts.single and true or false,
		format     = (fmt == "jpeg") and "jpeg" or "png",
		-- a Steam screenshot: the picture is kept as PNG, then shown and shot by the engine
		steam      = fmt == "steam" and not opts.capture and not opts.dir,
		quality    = math.Clamp(math.floor(tonumber(opts.quality) or GetConVar("gmfm_render_quality"):GetInt()), 1, 100),
		capture    = isfunction(opts.capture) and opts.capture or nil,
		rtCapture  = isfunction(opts.rtCapture) and opts.rtCapture or nil,
		accum      = istable(opts.accum) and opts.accum or nil,
		warmup     = tonumber(opts.warmup) and math.Clamp(math.floor(opts.warmup), 1, 30) or nil,
		sampleScale = tonumber(opts.sampleScale),
		name       = (opts.name and opts.name ~= "") and SPeditor.SafeName(opts.name) or ("gmfm_" .. os.date("%Y%m%d_%H%M%S")),
		dir        = (opts.dir and opts.dir ~= "") and SPeditor.SafeName(opts.dir) or nil,
		silent     = opts.silent and true or false,
		onDone     = isfunction(opts.onDone) and opts.onDone or nil,
		queued     = RealTime(),
	}
	return true
end

function SPeditor.Export.Screenshot(name)   -- compatibility
	SPeditor.Export.Render({ name = name })
end

-- The camera a render shoots through (a0.9): only the cameras of the scene are rendered, never
-- the work camera — it is the editor's eye, not part of the film. A given camera; otherwise the
-- one the Primary Viewport looks through; otherwise the first camera of the scene; nil if the
-- scene has none.
function SPeditor.Export.SceneCamera(camera)
	if IsValid(camera) and C.IsCamera(camera) then return camera end
	local v = C.GetViewCamera()
	if IsValid(v) and C.IsCamera(v) then return v end
	for _, obj in ipairs(C.BuildEntityList()) do
		if obj.kind == "camera" and IsValid(obj.ent) then return obj.ent end
	end
end

local function sourceFor(job)
	-- a free frame wider than 16:9 is shot wider (Hor+, C.FrameFOV in cl_scene.lua)
	local W, H = C.GetRenderSize()
	local e = SPeditor.Export.SceneCamera(job.camera)
	if e then
		local pos, ang = C.CameraPose(e)
		return { origin = pos, angles = ang, fov = C.FrameFOV(e:GetCameraFOV(), W / H), ent = e }
	end
	local pos, ang, fov = C.GetView()
	return { origin = pos, angles = ang, fov = C.FrameFOV(fov, W / H), ent = C.GetViewCamera() }
end

SPeditor.Export.Source = function(camera) return sourceFor({ camera = camera }) end

-- Focus distance: to the selected object, and if nothing is selected —
-- to whatever is in the centre of the frame.
local function focusDistance(src)
	local fwd = src.angles:Forward()
	local sel = C.selected
	if IsValid(sel) and sel ~= src.ent then
		local center = C.CenterOf(sel)
		if center then
			local d = (center - src.origin):Dot(fwd)
			if d > 4 then return d end
		end
	end
	local tr = util.TraceLine({
			start = src.origin, endpos = src.origin + fwd * 16384,
			filter = function(e) return SPeditor.IsEditable(e) and e ~= src.ent end,
	})
	return tr.Hit and math.max(src.origin:Distance(tr.HitPos), 4) or 400
end
SPeditor.Export.FocusDistance = focusDistance

-- A camera's own depth of field. (b0.2.6 round 8) The focus is the camera's focal distance only, as in
-- SFM: there is no "focus kept on an object" there — the focus is set by hand and keyed. A focus
-- object set earlier (NW2 SPeditor_FocusOn, still read from old scenes) no longer moves it.
function SPeditor.Export.TrackFocus(src, dof)
	return dof
end

-- "Engine frame": the engine itself shoots the scene (with all addon shaders), one game
-- frame per attempt. The first frames are skipped: effects that accumulate the picture
-- over time, and auto exposure, need a few frames to settle.
local ENGINE_WARMUP  = 6
local ENGINE_TIMEOUT = 5

-- (b0.2.6 round 10) the depth of field an engine frame takes: the same choice as the editor's own
-- pass (the Render window's, or the camera's own), its passes scaled as RenderBase scales them;
-- nil — none
local function engineDOF(job, src)
	local dof
	if job.dof then dof = { aperture = job.aperture, samples = job.samples, focus = focusDistance(src) } end
	local own = (not job.nodof or job.camdof) and SPeditor.FX and SPeditor.Export.TrackFocus(src, SPeditor.FX.DOF(SPeditor.FX.For(src.ent)))
	if own then dof = own end
	if not dof or (dof.aperture or 0) <= 0 then return nil end
	local n = math.Clamp(math.floor(dof.samples or 32), 2, 256)
	local scale = math.Clamp(tonumber(job.sampleScale) or 1, 0.05, 1)
	if scale < 1 and not (own and job.camdof) then n = math.max(math.floor(n * scale + 0.5), math.min(n, 12)) end
	return { aperture = dof.aperture, focus = dof.focus, n = n }
end

-- Returns ok, rt; nil — the frame is not ready yet (the job stays in the queue)
local function engineFrame(job, src, W, H)
	local R = SPeditor.Render
	R.FinishEngineFrame()
	local E = R.Engine
	job.t0 = job.t0 or RealTime()
	local fresh = E.info and E.info.owner == job and E.serial ~= job.serial
	if fresh then
		job.serial = E.serial
		job.frames = (job.frames or 0) + 1
	end
	local fx = SPeditor.FX and SPeditor.FX.For(src.ent) or nil
	local base = R.FXSource(src, fx)
	if (job.frames or 0) < (job.warmup or ENGINE_WARMUP) then
		if RealTime() - job.t0 > ENGINE_TIMEOUT then return false, "engine frame timeout" end
		R.RequestEngineFrame(base, { fullbright = job.fullbright, aspect = W / H, owner = job })
		return nil
	end
	-- (round 10) depth of field: one engine frame for every point of the lens, cut out shifted and
	-- averaged (cl_render.lua R.EngineLens). A moment of motion blur takes its share of the points
	-- (every m-th, as RenderBase does), so the moments together make the whole lens once.
	if job.lens == nil then
		local dof = engineDOF(job, src)
		if dof then
			local list = {}
			local m = job.accum and math.max(job.accum.n, 1) or 1
			local first = job.accum and math.Clamp(job.accum.i, 1, m) or 1
			for i = first, math.max(dof.n, m), m do list[#list + 1] = i end
			job.lens = { dof = dof, list = list, n = math.max(dof.n, m), done = 0, t0 = RealTime() }
		else
			job.lens = false
		end
	end
	local L = job.lens
	if L then
		if fresh and E.info.lens and E.info.lens.pass == L.done + 1 then
			local ok, err = pcall(function()
				local rt = R.EngineLensToRT(W, H, W / H)
				if rt then R.LensAccumulate(rt, L.done + 1, W, H) end
			end)
			if not ok then return false, err end
			L.done = L.done + 1
		end
		if L.done < #L.list then
			if RealTime() - L.t0 > ENGINE_TIMEOUT + #L.list * 0.5 then return false, "engine frame timeout (depth of field)" end
			local lens = R.EngineLens(L.dof, L.list[L.done + 1], L.n, W, H, base.fov)
			lens.pass = L.done + 1
			R.RequestEngineFrame(R.EngineLensSource(base, lens), { fullbright = job.fullbright, aspect = W / H, owner = job, lens = lens })
			return nil
		end
		return pcall(function()
			return R.ApplyFX(R.LensAccumulated(W, H), fx, W, H)
		end)
	end
	return pcall(function()
		local rt = R.EngineToRT(W, H, W / H)
		return rt and R.ApplyFX(rt, fx, W, H) or nil
	end)
end

-- (b0.2.6) Order the engine frame of the waiting job at once. Called before the game frame's
-- view (the server's answer, Think): the engine draws the frame in this very game frame and its
-- PostRender takes it — a frame of a video no longer waits a game frame for the order.
function SPeditor.Export.Prime()
	local job = SPeditor.Export.pending
	if not job or not job.engine or job.primed or not C.active then return end
	job.primed = true
	local W, H = C.GetRenderSize()
	local src = sourceFor(job)
	local fx = SPeditor.FX and SPeditor.FX.For(src.ent) or nil
	job.t0 = job.t0 or RealTime()
	SPeditor.Render.RequestEngineFrame(SPeditor.Render.FXSource(src, fx), { fullbright = job.fullbright, aspect = W / H, owner = job })
end

SPeditor.Hook("PostRender", "SPeditor.Export", function()
	local job = SPeditor.Export.pending
	if not job then return end
	if not C.active then
		SPeditor.Export.pending = nil
		return
	end

	-- effects must stand at their moments (SPeditor.Effects): particle systems are run up
	-- to them, the effects that play by themselves are started over. A frame of an
	-- animation (single) only waits for the particles — its effects are started by the keys.
	local Fx = SPeditor.Effects
	if Fx then
		if job.single then
			job.fxT0 = job.fxT0 or RealTime()
			if RealTime() - job.fxT0 < 12 and Fx.Busy() then return end
		elseif Fx.Hold(job) then
			return
		end
	end

	local W, H = C.GetRenderSize()
	local src = sourceFor(job)
	local ok, rt

	if job.engine then
		ok, rt = engineFrame(job, src, W, H)
		if ok == nil then return end
		SPeditor.Export.pending = nil
	else
		SPeditor.Export.pending = nil
		local opts = { fullbright = job.fullbright, ss = job.ss, sampleScale = job.sampleScale,
			-- motion blur: this moment takes its share of the frame's passes (b0.2.6, as SFM)
			slice = job.accum and { job.accum.i, job.accum.n } or nil }
		if job.dof then opts.dof = { aperture = job.aperture, samples = job.samples, focus = focusDistance(src) } end
		-- a camera with its own depth of field (camera effects) uses it instead
		local own = (not job.nodof or job.camdof) and SPeditor.FX and SPeditor.Export.TrackFocus(src, SPeditor.FX.DOF(SPeditor.FX.For(src.ent)))
		if own then
			opts.dof = own
			if job.camdof then opts.dofFull = true end
		end

		-- the "export in progress" flags are set only for the render itself and must be
		-- cleared: while they are set, the viewports and the gizmo are not drawn
		local prevHide, prevExp = C.hideUI, C.exporting
		C.hideUI, C.exporting = true, true
		ok, rt = pcall(SPeditor.Render.RenderFinal, src, W, H, opts)
		C.hideUI, C.exporting = prevHide, prevExp
	end
	if not ok then ErrorNoHalt("[GM:FM] render: " .. tostring(rt) .. "\n") end

	local function done(success, path)
		if job.onDone then
			local okCb, err = pcall(job.onDone, success, path)
			if not okCb then ErrorNoHalt("[GM:FM] render callback: " .. tostring(err) .. "\n") end
		end
	end

	if not ok or not rt then
		SPeditor.Notify(L("render_failed"), 1)
		done(false)
		return
	end

	if job.accum then
		local R = SPeditor.Render
		local okAcc, err = pcall(R.Accumulate, rt, job.accum.i, W, H)
		if not okAcc then
			ErrorNoHalt("[GM:FM] render: " .. tostring(err) .. "\n")
			done(false)
			return
		end
		if job.accum.i < job.accum.n then
			done(true)
			return
		end
		rt = R.AccumulatedRT(W, H)
	end
	-- the finished frame for whoever shows it (the progress window of a video, b0.2.6)
	hook.Run("GMFM_RenderedFrame", rt, W, H)

	if job.rtCapture then
		local okCb, res = pcall(job.rtCapture, rt, W, H)
		if not okCb then ErrorNoHalt("[GM:FM] render capture: " .. tostring(res) .. "\n") end
		done(okCb and res ~= false)
		return
	end

	render.PushRenderTarget(rt)
	local data = render.Capture({ format = job.format, quality = job.quality, x = 0, y = 0, w = W, h = H, alpha = false })
	render.PopRenderTarget()

	if data and job.capture then
		local okCb, res = pcall(job.capture, data, W, H)
		if not okCb then ErrorNoHalt("[GM:FM] render capture: " .. tostring(res) .. "\n") end
		done(okCb and res ~= false)
	elseif data then
		local dir = job.dir and (EXPORT_DIR .. "/" .. job.dir) or EXPORT_DIR
		ensureDir(dir)
		local path = dir .. "/" .. job.name .. ((job.format == "jpeg") and ".jpg" or ".png")
		file.Write(path, data)
		if not job.silent then
			SPeditor.Notify(string.format(L("render_saved"), path, W, H), 2)
			if SPeditor.UI.ShowRenderDone and not job.steam then
				SPeditor.UI.ShowRenderDone({ path = "garrysmod/data/" .. path, notes = { string.format(L("rdone_picture"), W, H) } })
			end
		end
		if job.steam then SPeditor.Export.ToSteam(path) end
		done(true, path)
	else
		SPeditor.Notify(L("render_failed"), 1)
		done(false)
	end
end)

concommand.Add("gmfm_render", function()
	SPeditor.Export.Render({})
end)

---------------------------------------------------------------------
-- A picture from data/ into the Steam screenshot library (see the top of the file)
---------------------------------------------------------------------
local STEAM_SHOOT, STEAM_HOLD = 3, 10      -- the frame the engine is asked to shoot, the frames shown

function SPeditor.Export.ToSteam(path)
	local mat = Material("../data/" .. path, "smooth")
	if not mat or mat:IsError() then
		SPeditor.Notify(L("render_steam_failed"), 1)
		return false
	end
	local tex = mat:GetTexture("$basetexture")
	local iw, ih = tex and tex:Width() or ScrW(), tex and tex:Height() or ScrH()
	local n = 0
	SPeditor.Hook("PostRenderVGUI", "SPeditor.SteamShot", function()
		n = n + 1
		local sw, sh = ScrW(), ScrH()
		local k = math.min(sw / iw, sh / ih)
		local w, h = math.floor(iw * k), math.floor(ih * k)
		surface.SetDrawColor(0, 0, 0, 255)
		surface.DrawRect(0, 0, sw, sh)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.SetMaterial(mat)
		surface.DrawTexturedRect(math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
		if n == STEAM_SHOOT then RunConsoleCommand("jpeg") end
		if n >= STEAM_HOLD then
			hook.Remove("PostRenderVGUI", "SPeditor.SteamShot")
			SPeditor.Notify(L("render_steam_done"), 2)
		end
	end)
	return true
end

---------------------------------------------------------------------
-- (b0.2.6) A render is not broken off by the keyboard: while a video or a picture is being shot,
-- Esc does not open the game's menu and the console (~ / Ё) is closed at once — the game paused
-- under them and the render stopped half way.
---------------------------------------------------------------------
function SPeditor.Export.Busy()
	local comp = SPeditor.Component and SPeditor.Component("saeditor")
	return SPeditor.Export.pending ~= nil or (comp and comp.SA and comp.SA.rendering ~= nil)
		or (SPeditor.Poster and SPeditor.Poster.Busy and SPeditor.Poster.Busy()) or false
end

SPeditor.Hook("OnPauseMenuShow", "SPeditor.RenderGuard", function()
	if SPeditor.Export.Busy() then return false end
end)

-- drawn every frame also while the game is paused under the menu (Think is not)
local warned = 0
SPeditor.Hook("PostRenderVGUI", "SPeditor.RenderGuard", function()
	if not SPeditor.Export.Busy() or not gui.IsGameUIVisible() then return end
	gui.HideGameUI()
	if RealTime() > warned then
		warned = RealTime() + 5
		SPeditor.Notify("#render_guard", 0)
	end
end)
