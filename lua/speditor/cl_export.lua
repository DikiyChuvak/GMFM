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

-- opts: { camera = Entity | "work" | nil (the Primary Viewport source), name = string,
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
	if SPeditor.Export.pending then
		if not opts.silent then SPeditor.Notify(L("render_busy"), 1) end
		return false
	end
	local fmt = opts.format or GetConVar("speditor_render_format"):GetString()
	SPeditor.Export.pending = {
		camera     = opts.camera,
		fullbright = GetConVar("speditor_render_fullbright"):GetBool(),
		ss         = GetConVar("speditor_render_ss"):GetBool() and 2 or 1,
		dof        = GetConVar("speditor_dof"):GetBool(),
		aperture   = math.Clamp(GetConVar("speditor_dof_aperture"):GetFloat(), 0.05, 20),
		samples    = math.Clamp(GetConVar("speditor_dof_samples"):GetInt(), 2, 128),
		engine     = SPeditor.Render.EngineMode(),
		single     = opts.single and true or false,
		format     = (fmt == "jpeg") and "jpeg" or "png",
		-- a Steam screenshot: the picture is kept as PNG, then shown and shot by the engine
		steam      = fmt == "steam" and not opts.capture and not opts.dir,
		quality    = math.Clamp(math.floor(tonumber(opts.quality) or GetConVar("speditor_render_quality"):GetInt()), 1, 100),
		capture    = isfunction(opts.capture) and opts.capture or nil,
		rtCapture  = isfunction(opts.rtCapture) and opts.rtCapture or nil,
		accum      = istable(opts.accum) and opts.accum or nil,
		warmup     = tonumber(opts.warmup) and math.Clamp(math.floor(opts.warmup), 1, 30) or nil,
		sampleScale = tonumber(opts.sampleScale),
		name       = (opts.name and opts.name ~= "") and SPeditor.SafeName(opts.name) or ("speditor_" .. os.date("%Y%m%d_%H%M%S")),
		dir        = (opts.dir and opts.dir ~= "") and SPeditor.SafeName(opts.dir) or nil,
		silent     = opts.silent and true or false,
		onDone     = isfunction(opts.onDone) and opts.onDone or nil,
	}
	return true
end

function SPeditor.Export.Screenshot(name)   -- compatibility
	SPeditor.Export.Render({ name = name })
end

local function sourceFor(job)
	if job.camera == "work" then
		local p, a, fov = C.GetWorkCamera()
		return { origin = p, angles = a, fov = fov }
	end
	if IsValid(job.camera) and C.IsCamera(job.camera) then
		local e = job.camera
		local pos, ang = C.CameraPose(e)
		return { origin = pos, angles = ang, fov = e:GetCameraFOV(), ent = e }
	end
	local pos, ang, fov = C.GetView()
	return { origin = pos, angles = ang, fov = fov, ent = C.GetViewCamera() }
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

-- "Engine frame": the engine itself shoots the scene (with all addon shaders), one game
-- frame per attempt. The first frames are skipped: effects that accumulate the picture
-- over time, and auto exposure, need a few frames to settle.
local ENGINE_WARMUP  = 6
local ENGINE_TIMEOUT = 5

-- Returns ok, rt; nil — the frame is not ready yet (the job stays in the queue)
local function engineFrame(job, src, W, H)
	local R = SPeditor.Render
	R.FinishEngineFrame()
	local E = R.Engine
	job.t0 = job.t0 or RealTime()
	if E.info and E.info.owner == job and E.serial ~= job.serial then
		job.serial = E.serial
		job.frames = (job.frames or 0) + 1
	end
	local fx = SPeditor.FX and SPeditor.FX.For(src.ent) or nil
	if (job.frames or 0) < (job.warmup or ENGINE_WARMUP) then
		if RealTime() - job.t0 > ENGINE_TIMEOUT then return false, "engine frame timeout" end
		R.RequestEngineFrame(R.FXSource(src, fx), { fullbright = job.fullbright, aspect = W / H, owner = job })
		return nil
	end
	return pcall(function()
		local rt = R.EngineToRT(W, H, W / H)
		return rt and R.ApplyFX(rt, fx, W, H) or nil
	end)
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
		local opts = { fullbright = job.fullbright, ss = job.ss, sampleScale = job.sampleScale }
		if job.dof then opts.dof = { aperture = job.aperture, samples = job.samples, focus = focusDistance(src) } end
		-- a camera with its own depth of field (camera effects) uses it instead
		local own = SPeditor.FX and SPeditor.FX.DOF(SPeditor.FX.For(src.ent))
		if own then opts.dof = own end

		-- the "export in progress" flags are set only for the render itself and must be
		-- cleared: while they are set, the viewports and the gizmo are not drawn
		local prevHide, prevExp = C.hideUI, C.exporting
		C.hideUI, C.exporting = true, true
		ok, rt = pcall(SPeditor.Render.RenderFinal, src, W, H, opts)
		C.hideUI, C.exporting = prevHide, prevExp
	end
	if not ok then ErrorNoHalt("[SPeditor] render: " .. tostring(rt) .. "\n") end

	local function done(success, path)
		if job.onDone then
			local okCb, err = pcall(job.onDone, success, path)
			if not okCb then ErrorNoHalt("[SPeditor] render callback: " .. tostring(err) .. "\n") end
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
			ErrorNoHalt("[SPeditor] render: " .. tostring(err) .. "\n")
			done(false)
			return
		end
		if job.accum.i < job.accum.n then
			done(true)
			return
		end
		rt = R.AccumulatedRT(W, H)
	end

	if job.rtCapture then
		local okCb, res = pcall(job.rtCapture, rt, W, H)
		if not okCb then ErrorNoHalt("[SPeditor] render capture: " .. tostring(res) .. "\n") end
		done(okCb and res ~= false)
		return
	end

	render.PushRenderTarget(rt)
	local data = render.Capture({ format = job.format, quality = job.quality, x = 0, y = 0, w = W, h = H, alpha = false })
	render.PopRenderTarget()

	if data and job.capture then
		local okCb, res = pcall(job.capture, data, W, H)
		if not okCb then ErrorNoHalt("[SPeditor] render capture: " .. tostring(res) .. "\n") end
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

concommand.Add("speditor_render", function()
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
