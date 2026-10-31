--[[
Poster (b0.2.6, after SFM's File → Export → Poster). A still is not shot in one go: it is refined
pass by pass in front of you, as SFM's progressive renderer does — every pass moves the lens over
its aperture (depth of field), the lights with a size over their discs (soft shadows) and the view
by a part of a pixel (smoothing), and the window shows the mean of the passes so far. The game
keeps running meanwhile (a few passes a frame), the render can be stopped at any pass and saved
as it is, and it is saved by itself when all the passes are in.

  UI.OpenPoster()                   the window
  SPeditor.Poster.Busy()            a poster is being refined (the render guard keeps Esc and the
                                    console closed meanwhile, cl_export.lua)
]]
SPeditor.Poster = SPeditor.Poster or {}
local P  = SPeditor.Poster
local C  = SPeditor.Client
local UI = SPeditor.UI
local R  = SPeditor.Render
local L  = SPeditor.L
local Dock = SPeditor.Dock
local COL = UI.PAL

local cvSamples = CreateClientConVar("gmfm_poster_samples", "64", true, false, "Poster: passes of the progressive render", 4, 512)
local cvSide    = CreateClientConVar("gmfm_poster_side", "0", true, false, "Poster: the long side in pixels (0 — the render size of the scene)", 0, 3840)
local cvFormat  = CreateClientConVar("gmfm_poster_format", "png", true, false, "Poster: png or jpeg")
local cvAuto    = CreateClientConVar("gmfm_poster_autosave", "1", true, false, "Poster: save by itself when all passes are in", 0, 1)

local SAMPLES = { 16, 32, 64, 128, 256, 512 }
local SIDES = { 0, 1280, 1920, 2560, 3840 }

function P.Busy() return P.job ~= nil and not P.job.done end

-- the size of the poster: the scene's render size, or its proportions at the chosen long side
function P.Size()
	local W, H = C.GetRenderSize()
	local side = cvSide:GetInt()
	if side > 0 then
		local k = side / math.max(W, H)
		W, H = math.max(math.floor(W * k + 0.5), 16), math.max(math.floor(H * k + 0.5), 16)
	end
	return W, H
end

local function stop()
	if P.job and not P.job.done then P.job.stopped = true end
end

function P.Start()
	if SPeditor.Export.Busy() then
		SPeditor.Notify("#render_busy", 1)
		return
	end
	local SA = SPeditor.Component("saeditor").SA
	if SA and SA.playing then SA.Play(false) end
	local camera = SPeditor.Export.SceneCamera(nil)
	if not camera then SPeditor.Notify("#sa_rnd_workcam", 0) end
	-- the view is taken now: moving the work camera while the poster refines changes nothing
	local src = SPeditor.Export.Source(camera)
	local W, H = P.Size()
	local n = math.Clamp(cvSamples:GetInt(), 4, 512)
	local FX = SPeditor.FX
	local fx = FX and FX.For(src.ent) or nil
	local dof = FX and SPeditor.Export.TrackFocus(src, FX.DOF(fx))
	if not dof and GetConVar("gmfm_dof"):GetBool() then
		dof = { aperture = math.Clamp(GetConVar("gmfm_dof_aperture"):GetFloat(), 0.05, 20), focus = SPeditor.Export.FocusDistance(src) }
	end
	-- one budget of passes for everything, as SFM: the lens, the smoothing and the shadows share it
	if dof then dof = { aperture = dof.aperture, focus = dof.focus, samples = n } end
	P.job = {
		src = { origin = Vector(src.origin), angles = Angle(src.angles), fov = src.fov, ent = src.ent },
		W = W, H = H, n = n, fx = fx, started = RealTime(),
		opts = { fullbright = C.fullbright or GetConVar("gmfm_render_fullbright"):GetBool(), aspect = W / H, dof = dof, dofFull = true,
			aaSamples = n, progress = { key = "poster", step = 1 } },
	}
end

local function save(job)
	if not job.rt then return end
	local fmt = cvFormat:GetString() == "jpeg" and "jpeg" or "png"
	render.PushRenderTarget(job.rt)
	local data = render.Capture({ format = fmt, quality = 95, x = 0, y = 0, w = job.W, h = job.H, alpha = false })
	render.PopRenderTarget()
	if not data or #data == 0 then
		SPeditor.Notify(L("render_failed"), 1)
		return
	end
	file.CreateDir("speditor/renders")
	local base = SPeditor.SafeName(C.sceneName or "")
	if base == "" then base = "poster" end
	local path = "speditor/renders/" .. string.gsub(base, " ", "_") .. "_poster_" .. os.date("%Y%m%d_%H%M%S") .. (fmt == "jpeg" and ".jpg" or ".png")
	file.Write(path, data)
	job.saved = path
	SPeditor.Notify(string.format(L("render_saved"), path, job.W, job.H), 2)
	if UI.ShowRenderDone then
		UI.ShowRenderDone({ path = "garrysmod/data/" .. path, notes = { string.format(L("poster_done_note"), job.W, job.H, job.passes or job.n) } })
	end
end

-- a few passes every frame, as many as fit in about 40 ms
SPeditor.Hook("PostRender", "SPeditor.Poster", function()
	local job = P.job
	if not job or job.done then return end
	if job.stopped then
		job.done = true
		return
	end
	local pr = job.opts.progress
	local used = pr.step or 1
	local t0 = SysTime()
	local prevHide, prevExp = C.hideUI, C.exporting
	C.hideUI, C.exporting = true, true
	local ok, rt = pcall(function()
		local base = R.RenderBase(R.FXSource(job.src, job.fx), job.W, job.H, job.opts)
		return R.ApplyFX(base, job.fx, job.W, job.H, job.opts.aspect)
	end)
	C.hideUI, C.exporting = prevHide, prevExp
	if not ok or not rt then
		ErrorNoHalt("[GM:FM] poster: " .. tostring(rt) .. "\n")
		SPeditor.Notify(L("render_failed"), 1)
		job.done = true
		return
	end
	-- its own copy: the renders reuse the textures it was made in
	job.rt = R.GetRT("poster_" .. job.W .. "x" .. job.H, job.W, job.H)
	R.Copy(rt, job.rt)
	job.passes = pr.i or job.n
	-- the pace: one pass took dt — as many as fit in ~40 ms next time
	local dt = math.max(SysTime() - t0, 0.001)
	pr.step = math.Clamp(math.floor(0.04 / (dt / used)), 1, 16)
	if pr.done or not pr.i then
		job.done, job.passes = true, pr.i or job.n
		job.took = RealTime() - job.started
		if cvAuto:GetBool() then save(job) end
	end
end)

---------------------------------------------------------------------
-- The window
---------------------------------------------------------------------
function UI.OpenPoster()
	if Dock.ShowPage("poster") then return end
	local W0, H0 = 560, 520
	local win, body = Dock.Create({ key = "poster", id = "poster", title = L("poster_title"), w = W0, h = H0,
			x = math.floor(ScrW() / 2 - W0 / 2), y = 120, dockable = false, icon = "icon16/picture.png" })
	win.minW, win.minH = UI.S(380), UI.S(320)

	local top = vgui.Create("DPanel", body)
	top:Dock(TOP)
	top:SetTall(UI.S(26))
	top:DockMargin(6, 6, 6, 2)
	top.Paint = nil
	local function combo(parent, w, items, cur, onPick)
		local cb = vgui.Create("DComboBox", parent)
		cb:Dock(LEFT)
		cb:SetWide(UI.S(w))
		cb:DockMargin(0, 0, 6, 0)
		for _, it in ipairs(items) do cb:AddChoice(it[1], it[2], it[2] == cur) end
		cb.OnSelect = function(_, _, _, data) onPick(data) end
		UI.Skin(cb)
		return cb
	end
	local sides = {}
	for _, s in ipairs(SIDES) do
		sides[#sides + 1] = { s == 0 and L("poster_size_scene") or (L("poster_side") .. " " .. s), s }
	end
	combo(top, 170, sides, cvSide:GetInt(), function(v) RunConsoleCommand("gmfm_poster_side", tostring(v)) end)
	local samples = {}
	for _, s in ipairs(SAMPLES) do samples[#samples + 1] = { s .. " " .. L("poster_passes"), s } end
	combo(top, 120, samples, cvSamples:GetInt(), function(v) RunConsoleCommand("gmfm_poster_samples", tostring(v)) end)
	combo(top, 70, { { "PNG", "png" }, { "JPEG", "jpeg" } }, cvFormat:GetString(), function(v) RunConsoleCommand("gmfm_poster_format", v) end)

	local row = vgui.Create("DPanel", body)
	row:Dock(TOP)
	row:SetTall(UI.S(24))
	row:DockMargin(6, 2, 6, 4)
	row.Paint = nil
	local function btn(text, icon, fn, w)
		local b = UI.Button(row, text, icon, fn)
		b:Dock(LEFT)
		b:SetWide(UI.S(w))
		b:DockMargin(0, 0, 6, 0)
		return b
	end
	btn(L("poster_start"), "icon16/control_play.png", function() P.Start() end, 110)
	btn(L("poster_stop"), "icon16/control_stop.png", stop, 90)
	btn(L("poster_save"), "icon16/disk.png", function()
		if not P.job or not P.job.rt then return end
		-- saved in a render hook: the picture is read from its texture
		SPeditor.Hook("PostRender", "SPeditor.PosterSave", function()
			hook.Remove("PostRender", "SPeditor.PosterSave")
			save(P.job)
		end)
	end, 90)
	local auto = UI.Check(row, L("poster_autosave"), cvAuto:GetBool(), function(v) RunConsoleCommand("gmfm_poster_autosave", v and "1" or "0") end)
	auto:Dock(LEFT)

	local view = vgui.Create("DPanel", body)
	view:Dock(FILL)
	view:DockMargin(6, 0, 6, 6)
	view.Paint = function(s, w, h)
		surface.SetDrawColor(10, 10, 10, 255)
		surface.DrawRect(0, 0, w, h)
		local job = P.job
		local W, H = P.Size()
		if job and job.rt then W, H = job.W, job.H end
		local ix, iy, iw, ih = C.FitRect(w - 8, h - 30, W / H)
		ix, iy = ix + 4, iy + 4
		if job and job.rt then
			R.DrawRT(job.rt, ix, iy, iw, ih)
		else
			surface.SetDrawColor(COL.BORDER)
			surface.DrawOutlinedRect(ix, iy, iw, ih, 1)
			draw.SimpleText(L("poster_hint"), "SPeditor.Small", w / 2, iy + ih / 2, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		-- the progress: passes, the bar, the time
		local text
		if job then
			local done = job.passes or 0
			text = string.format(L("poster_progress"), job.W, job.H, done, job.n)
			if job.done then
				text = text .. "  ·  " .. (job.stopped and L("poster_stopped") or L("poster_finished"))
				if job.saved then text = text .. "  ·  " .. job.saved end
			end
			local bw = w - 8
			surface.SetDrawColor(COL.BORDER)
			surface.DrawRect(4, h - 22, bw, 4)
			surface.SetDrawColor(COL.ORANGE)
			surface.DrawRect(4, h - 22, math.floor(bw * math.Clamp(done / math.max(job.n, 1), 0, 1)), 4)
		else
			text = string.format(L("poster_size_now"), W, H)
		end
		draw.SimpleText(text, "SPeditor.Small", 6, h - 10, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end

concommand.Add("gmfm_poster", function() if UI.OpenPoster then UI.OpenPoster() end end)
