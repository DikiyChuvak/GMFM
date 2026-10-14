--[[
SAeditor — animation render.

The editor's Render button shoots one frame. If the scene has animation (at least
one track or sound — whether playback is running does not matter), SAeditor takes over
the request (the SPeditor_RenderRequest hook) and renders the whole animation: timeline
frame -> the server sets the scene -> the objects reach the client -> the editor's
regular render -> the next frame.

Formats:
  avi   one AVI video file (MJPEG codec: the same JPEG frames inside, plus the sound
        track). The editor writes the file itself; the game lets Lua create files with
        only a few extensions, so it is called <name>.avi.dat — the ".dat" has to be removed.
  jpeg  JPEG frames in the folder <name>/ (for building an MP4 with an external tool)
  png   PNG frames in the same place
        For frames the sound track is saved next to them as <name>.wav.
The game cannot write MP4: it has no H.264 encoder, and the engine's built-in video
recording (video.Record) creates no files on Linux — verified in game.

Where the time of a frame goes (measured in game, 3840 x 2628): the JPEG encoder of the
game — 0.65 s at quality 100, 0.37 s at 90; the scene passes for soft shadows and depth
of field; the wait for the scene to arrive from the server. Hence:
  * a video has its own JPEG quality (saeditor_render_quality, 90) — a still keeps its own;
  * only a part of the soft shadow / depth of field passes is made (saeditor_render_samples);
  * a frame is taken in the game frame after the server has confirmed it (on someone
    else's server — once the scene has stopped changing), not after a fixed pause; the next
    frame is asked for in the same game frame the previous one was shot in;
  * frames go straight into the video file, not through a temporary picture on disk;
  * the viewports are redrawn only twice a second and the preview of the Render window
    stands still while the render runs.

The size of the video. MJPEG keeps every frame as a separate JPEG picture, so the size
is frames x picture size; the game has no other encoder. What can be done here:
  * "Video size" in the Render window — the five levels of the game's JPEG encoder;
  * a frame that came out byte for byte equal to the previous one (nothing moves) is
    written as an empty piece: players repeat the previous frame, the file does not grow.
A still smaller file of the same quality needs an H.264 encoder: the ffmpeg command is
printed to the console after the render, tools/speditor_mp4.sh runs it for all videos
(measured: a 20 s, 1280 x 876 video — 87 MB at level 90, 36 MB as MP4).

  SA.IsAnimated()                 the scene has animation
  SA.RenderSequence(opts)         render the animation       SA.StopRender()
]]
local MOD = SPeditor.Mod("saeditor")
local SA  = MOD.SA
local C   = SPeditor.Client

local cvMode    = CreateClientConVar("saeditor_render_mode", "anim", true, false)     -- anim | frame
local cvFormat  = CreateClientConVar("saeditor_render_format", "avi", true, false)    -- avi | jpeg | png
local cvSettle  = CreateClientConVar("saeditor_render_settle", "0.3", true, false)    -- the longest wait for the scene, s
local cvQuality = CreateClientConVar("saeditor_render_quality", "90", true, false)    -- JPEG quality of a video
local cvSamples = CreateClientConVar("saeditor_render_samples", "50", true, false)    -- soft shadow / DoF passes, percent

SA.RENDER_FORMATS = { "avi", "jpeg", "png" }
-- The game's JPEG encoder has only five levels (measured in game on a 1280 x 876 frame):
-- 100 — 1148 KB, 71..99 — 158 KB, 51..70 — 96 KB, 31..50 — 56 KB, up to 30 — 28 KB.
SA.RENDER_QUALITIES = { 100, 90, 70, 50, 30 }
SA.RENDER_SAMPLES = { 100, 50, 25 }

function SA.IsAnimated() return next(SA.tracks) ~= nil or #(SA.sounds or {}) > 0 end
function SA.RenderMode() return cvMode:GetString() == "frame" and "frame" or "anim" end
function SA.RenderFormat()
	local f = cvFormat:GetString()
	return table.HasValue(SA.RENDER_FORMATS, f) and f or "avi"
end
function SA.RenderQuality() return math.Clamp(cvQuality:GetInt(), 10, 100) end
function SA.RenderSamples() return math.Clamp(cvSamples:GetInt(), 10, 100) end

local RENDER_DIR = SPeditor.Config.SaveDir .. "/renders"

---------------------------------------------------------------------
-- AVI (MJPEG video, 16-bit stereo sound). The fixed-length header is written first,
-- frames and pieces of sound are appended one by one, the index goes at the end; sizes
-- and counts in the header are fixed up on close.
---------------------------------------------------------------------
local function u32(n)
	n = math.floor(n)
	return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end
local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end

-- A file is closed before it reaches 2 GB (many players and the game's own file
-- functions count sizes in 31 bits); the video then continues in the next part.
local AVI_LIMIT = 1.9 * 1024 * 1024 * 1024

-- places of the fields fixed up on close (from the start of the file)
local AVIH_AT, VSTRH_AT = 32, 108

-- audio = sample rate of the sound track, nil — a video without sound
local function aviOpen(path, w, h, fps, audio)
	local f = file.Open(path, "wb", "DATA")
	if not f then return nil end
	local strf = u32(40) .. u32(w) .. u32(h) .. u16(1) .. u16(24) .. "MJPG" .. u32(w * h * 3) .. u32(0) .. u32(0) .. u32(0) .. u32(0)
	local strh = "vids" .. "MJPG" .. u32(0) .. u32(0) .. u32(0) .. u32(1) .. u32(fps) .. u32(0) .. u32(0) .. u32(0)
		.. u32(10000) .. u32(0) .. u16(0) .. u16(0) .. u16(w) .. u16(h)
	local strl = "strl" .. "strh" .. u32(#strh) .. strh .. "strf" .. u32(#strf) .. strf
	local avih = u32(1000000 / fps) .. u32(0) .. u32(0) .. u32(audio and 0x110 or 0x10) .. u32(0) .. u32(0) .. u32(audio and 2 or 1)
		.. u32(0) .. u32(w) .. u32(h) .. u32(0) .. u32(0) .. u32(0) .. u32(0)
	local hdrl = "hdrl" .. "avih" .. u32(#avih) .. avih .. "LIST" .. u32(#strl) .. strl
	local astrhAt
	if audio then
		-- one block is a left and a right 16-bit sample
		local afmt = u16(1) .. u16(2) .. u32(audio) .. u32(audio * 4) .. u16(4) .. u16(16)
		local astrh = "auds" .. u32(0) .. u32(0) .. u32(0) .. u32(0) .. u32(4) .. u32(audio * 4) .. u32(0) .. u32(0)
			.. u32(audio * 4) .. u32(0) .. u32(4) .. u16(0) .. u16(0) .. u16(0) .. u16(0)
		local astrl = "strl" .. "strh" .. u32(#astrh) .. astrh .. "strf" .. u32(#afmt) .. afmt
		astrhAt = 12 + 8 + #hdrl + 8 + 4 + 8
		hdrl = hdrl .. "LIST" .. u32(#astrl) .. astrl
	end
	local head = "RIFF" .. u32(0) .. "AVI " .. "LIST" .. u32(#hdrl) .. hdrl
	f:Write(head .. "LIST" .. u32(0) .. "movi")
	local movi = #head + 8          -- where the content of the movi list starts (index offsets count from here)
	assert(f:Tell() == movi + 4 and string.sub(head, VSTRH_AT + 1, VSTRH_AT + 4) == "vids", "SAeditor: AVI header layout")
	return { f = f, index = {}, count = 0, maxSize = 0, pos = movi + 4, movi = movi, astrh = astrhAt, blocks = 0 }
end

local function aviChunk(avi, id, data)
	local size = #data
	avi.index[#avi.index + 1] = id .. u32(0x10) .. u32(avi.pos - avi.movi) .. u32(size)
	avi.f:Write(id .. u32(size))
	avi.f:Write(data)
	if size % 2 == 1 then avi.f:Write("\0") end
	avi.pos = avi.pos + 8 + size + size % 2
end

-- A frame equal to the previous one is an empty piece: "show the previous frame again"
local function aviFrame(avi, jpeg)
	if jpeg == avi.last then
		avi.index[#avi.index + 1] = "00dc" .. u32(0) .. u32(avi.pos - avi.movi) .. u32(0)
		avi.f:Write("00dc" .. u32(0))
		avi.pos = avi.pos + 8
		avi.repeats = (avi.repeats or 0) + 1
	else
		aviChunk(avi, "00dc", jpeg)
		avi.last = jpeg
		avi.maxSize = math.max(avi.maxSize, #jpeg)
	end
	avi.count = avi.count + 1
end

local function aviSound(avi, pcm)
	if not avi.astrh or #pcm == 0 then return end
	aviChunk(avi, "01wb", pcm)
	avi.blocks = avi.blocks + #pcm / 4
end

local function aviClose(avi)
	local f = avi.f
	local moviEnd = avi.pos
	local idx = table.concat(avi.index)
	f:Write("idx1" .. u32(#idx) .. idx)
	local total = moviEnd + 8 + #idx
	local function put(at, value) f:Seek(at) f:Write(u32(value)) end
	put(4, total - 8)                        -- RIFF
	put(avi.movi - 4, moviEnd - avi.movi)    -- LIST movi
	put(AVIH_AT + 16, avi.count) put(VSTRH_AT + 32, avi.count)     -- number of frames: avih and strh
	put(AVIH_AT + 28, avi.maxSize) put(VSTRH_AT + 36, avi.maxSize)
	if avi.astrh then put(avi.astrh + 32, avi.blocks) end          -- length of the sound track
	f:Close()
end

---------------------------------------------------------------------
-- WAV: the sound track next to a frame sequence
---------------------------------------------------------------------
local function wavOpen(path, rate)
	local f = file.Open(path, "wb", "DATA")
	if not f then return nil end
	f:Write("RIFF" .. u32(0) .. "WAVE" .. "fmt " .. u32(16) .. u16(1) .. u16(2) .. u32(rate) .. u32(rate * 4) .. u16(4) .. u16(16)
		.. "data" .. u32(0))
	return { f = f, size = 0, path = path }
end

local function wavClose(wav)
	local f = wav.f
	f:Seek(4) f:Write(u32(36 + wav.size))
	f:Seek(40) f:Write(u32(wav.size))
	f:Close()
end

---------------------------------------------------------------------
-- Render
---------------------------------------------------------------------
local function ensureDir(dir)
	local acc = ""
	for part in string.gmatch(dir, "[^/]+") do
		acc = (acc == "") and part or (acc .. "/" .. part)
		if not file.IsDir(acc, "DATA") then file.CreateDir(acc) end
	end
end

-- The scene as the client sees it, folded into one string: positions and angles of all
-- objects and the bones of characters. Two frames in a row with the same string — the
-- scene has arrived from the server and stands still.
local FX_WAIT = 12       -- the longest wait for the particle effects of one frame, s

local function sceneSignature()
	local x, y, z = 0, 0, 0
	for i, e in ipairs(C.Objects()) do
		if IsValid(e) then
			local p, a = e:GetPos(), e:GetAngles()
			x = x + p.x * i + a.p * 0.37
			y = y + p.y * i + a.y * 0.71
			z = z + p.z * i + a.r * 1.13
			if C.IsRagdoll(e) then
				e:SetupBones()
				for b = 0, e:GetBoneCount() - 1, 2 do
					local m = e:GetBoneMatrix(b)
					if m then
						local t = m:GetTranslation()
						x, y, z = x + t.x * (b + 2), y + t.y * (b + 2), z + t.z * (b + 2)
					end
				end
			end
		end
	end
	return string.format("%.2f %.2f %.2f", x, y, z)
end

local function openVideo(job)
	local W, H = C.GetRenderSize()
	local part = job.part or 1
	job.path = RENDER_DIR .. "/" .. job.name .. (part > 1 and ("_part" .. part) or "") .. ".avi.dat"
	local ok, avi = pcall(aviOpen, job.path, W, H, SA.fps, job.mix and SA.Audio.RATE or nil)
	job.avi = ok and avi or nil
	return job.avi ~= nil
end

-- Ask the server for the frame job.cur. On the answer the scene is remembered as the
-- client sees it; the frame is shot once it is the same in the next game frame.
local function seek(job)
	job.state = "wait_ack"
	job.deadline = RealTime() + 3
	SA.Seek(job.cur, function()
		if SA.rendering == job and job.state == "wait_ack" then
			job.state = "settle"
			job.ackT, job.sig, job.sigFrame = RealTime(), sceneSignature(), FrameNumber()
		end
	end)
end

-- opts = { camera = Entity | "work" | nil, from, to, name, format = "avi" | "jpeg" | "png",
--          settle = the longest wait for the scene in seconds, quality = JPEG quality,
--          samples = percent of soft shadow / depth of field passes,
--          onDone = function(ok, path, count) }
function SA.RenderSequence(opts)
	if SA.rendering then
		SPeditor.Notify("#sa_rnd_busy", 1)
		return false
	end
	opts = opts or {}
	local from = math.Clamp(math.floor(opts.from or 0), 0, SA.frames)
	local to   = math.Clamp(math.floor(opts.to or SA.frames), from, SA.frames)
	local name = SPeditor.SafeName(opts.name or "")
	if name == "" then name = SPeditor.SafeName(C.sceneName or "") end
	if name == "" then name = "anim_" .. os.date("%Y%m%d_%H%M%S") end
	name = string.gsub(name, " ", "_")
	local format = table.HasValue(SA.RENDER_FORMATS, opts.format) and opts.format or SA.RenderFormat()
	local job = {
		camera = opts.camera, from = from, to = to, cur = from, name = name, format = format,
		frameFormat = (format == "png") and "png" or "jpeg", dir = name,
		settle = math.Clamp(opts.settle or cvSettle:GetFloat(), 0.05, 3),
		-- on someone else's server the scene comes with a delay of its own
		minWait = opts.minWait or (game.SinglePlayer() and 0 or 0.1), seek = seek,
		trustAck = game.SinglePlayer() and not opts.minWait,
		quality = math.Clamp(math.floor(opts.quality or SA.RenderQuality()), 10, 100),
		sampleScale = math.Clamp(opts.samples or SA.RenderSamples(), 10, 100) / 100,
		onDone = opts.onDone, count = 0, state = "seek", wasFrame = SA.frame,
	}
	if #(SA.sounds or {}) > 0 then job.mix = SA.Audio.NewMix(SA.sounds, SA.fps, from) end
	ensureDir(RENDER_DIR)
	if format == "avi" then
		if not openVideo(job) then
			SPeditor.Notify("#sa_rnd_failed", 1)
			return false
		end
	elseif job.mix and #job.mix.clips > 0 then
		ensureDir(RENDER_DIR .. "/" .. job.dir)
		local ok, wav = pcall(wavOpen, RENDER_DIR .. "/" .. job.dir .. "/" .. name .. ".wav", SA.Audio.RATE)
		job.wav = ok and wav or nil
	end
	-- effects that cannot be stopped at a moment: say so once, before the render
	local nLive = 0
	for _, e in ipairs(C.Objects()) do
		if C.IsEffect(e) and SPeditor.Effects.IsLive(e) and SA.tracks[SA.UID(e)] then nLive = nLive + 1 end
	end
	if nLive > 0 then SPeditor.Notify("#sa_rnd_fx_live|" .. nLive, 0) end
	SA.rendering = job
	SA.playing = false
	SA.Audio.StopAll()
	SPeditor.Render.busy = true
	return true
end

function SA.StopRender(ok)
	local job = SA.rendering
	if not job then return end
	SA.rendering = nil
	SPeditor.Render.busy = false
	local path = "garrysmod/data/" .. RENDER_DIR .. "/" .. job.name
	if job.avi then
		job.bytes = (job.bytes or 0) + job.avi.pos
		job.repeats = (job.repeats or 0) + (job.avi.repeats or 0)
		pcall(aviClose, job.avi)
		path = "garrysmod/data/" .. RENDER_DIR .. "/" .. job.name .. ".avi.dat"
		if job.count == 0 then file.Delete(job.path) end
	end
	if job.wav then
		pcall(wavClose, job.wav)
		if job.count == 0 then file.Delete(job.wav.path) end
	end
	if ok then
		if job.avi then
			SPeditor.Notify("#sa_rnd_done_avi|" .. job.count .. "|" .. path, 2)
			local mb = job.bytes / 1048576
			SPeditor.Notify("#sa_rnd_size|" .. string.format("%.1f", mb) .. "|" .. string.format("%.2f", mb / math.max(job.count / SA.fps, 0.04))
				.. "|" .. job.repeats, 0)
			print("[SAeditor] " .. MOD:L("sa_rnd_mp4", job.name .. ".avi.dat", job.name))
		else
			SPeditor.Notify("#sa_rnd_done|" .. job.count .. "|" .. path, 2)
			local ext = job.format == "jpeg" and "jpg" or "png"
			print("[SAeditor] " .. MOD:L("sa_rnd_video", SA.fps, job.name, ext, job.wav and (" -i " .. job.name .. ".wav") or "", job.name))
			if job.wav then SPeditor.Notify("#sa_snd_wav|" .. job.name .. ".wav", 0) end
		end
		if job.mix and #job.mix.skipped > 0 then
			SPeditor.Notify("#sa_snd_skipped|" .. table.concat(job.mix.skipped, ", ", 1, math.min(#job.mix.skipped, 6)), 1)
		end
	else
		SPeditor.Notify("#sa_rnd_stopped", 1)
	end
	SA.Seek(math.floor(job.wasFrame + 0.5))
	if job.onDone then job.onDone(ok and true or false, path, job.count) end
end

-- The piece of the sound track for the frame that has just been shot (the scene still stands on it)
local function frameSound(job)
	local mix = job.mix
	if not mix or #mix.clips == 0 then return end
	local src = SPeditor.Export.Source(job.camera)
	local pcm = SA.Audio.Mix(mix, job.cur - job.from, src.origin, src.angles)
	if job.avi then
		aviSound(job.avi, pcm)
	elseif job.wav then
		job.wav.f:Write(pcm)
		job.wav.size = job.wav.size + #pcm
	end
end

local function frameDone(job, ok)
	if SA.rendering ~= job then return end
	if ok then ok = pcall(frameSound, job) end
	if not ok then
		SA.StopRender(false)
		return
	end
	job.count = job.count + 1
	if job.cur >= job.to then
		SA.StopRender(true)
		return
	end
	-- the video file is close to its size limit: the rest goes into the next part
	if job.avi and job.avi.pos > AVI_LIMIT then
		job.bytes = (job.bytes or 0) + job.avi.pos
		job.repeats = (job.repeats or 0) + (job.avi.repeats or 0)
		pcall(aviClose, job.avi)
		job.part = (job.part or 1) + 1
		if not openVideo(job) then
			SA.StopRender(false)
			return
		end
		SPeditor.Notify("#sa_rnd_part|" .. string.GetFileFromFilename(job.path), 0)
	end
	job.cur = job.cur + 1
	job.seek(job)         -- at once: waiting for the next Think would cost a game frame
end

MOD:Hook("Think", function()
	local job = SA.rendering
	if not job then return end
	if not C.active then
		SA.StopRender(false)
		return
	end
	if job.state == "seek" then
		seek(job)
	elseif job.state == "wait_ack" then
		if RealTime() > job.deadline then SA.StopRender(false) end
	elseif job.state == "settle" then
		if FrameNumber() == job.sigFrame then return end          -- the answer came in this very frame
		local waited = RealTime() - job.ackT
		local stable
		if job.trustAck then
			-- Single player: the server answers two ticks after it has set the frame, and by the
			-- game frame after the answer everything is in its place on the client — bodies,
			-- what is attached to them, lights (verified in game object by object).
			stable = true
		else
			local sig = sceneSignature()
			stable = sig == job.sig
			job.sig, job.sigFrame = sig, FrameNumber()
		end
		-- particle effects are run up to the moment of this frame (SPeditor.Effects); the
		-- frame waits for them, but not forever
		local Fx = SPeditor.Effects
		if Fx and waited < FX_WAIT and Fx.Busy() then return end
		if (stable and waited >= job.minWait) or waited >= job.settle then
			local accepted = SPeditor.Export.Render({
				single = true, camera = job.camera, dir = job.dir, name = string.format("%s_%04d", job.name, job.cur - job.from + 1),
				format = job.frameFormat, quality = job.quality, sampleScale = job.sampleScale, silent = true,
				-- "engine frame": the effects are settled by the previous frame of the animation
				warmup = (job.count > 0) and 1 or nil,
				-- a video frame goes straight into the file
				capture = job.avi and function(data)
					if SA.rendering ~= job or #data == 0 then return false end
					aviFrame(job.avi, data)
				end or nil,
				onDone = function(ok) frameDone(job, ok) end,
			})
			if accepted then job.state = "render" end
		end
	end
end, "render")

---------------------------------------------------------------------
-- The editor's Render button: a scene with animation is rendered as a whole
---------------------------------------------------------------------
MOD:Hook("SPeditor_RenderRequest", function(opts)
	if not SA.IsAnimated() or SA.RenderMode() ~= "anim" then return end
	local camera = opts.camera
	if camera == "primary" then camera = nil end
	SA.RenderSequence({ camera = camera, name = opts.name, onDone = opts.onDone })
	return true
end, "render")
