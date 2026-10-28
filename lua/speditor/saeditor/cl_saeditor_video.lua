--[[
SAeditor — animation render.

The editor's Render button shoots one frame. If the scene has animation (at least
one track or sound — whether playback is running does not matter), SAeditor takes over
the request (the SPeditor_RenderRequest hook) and renders the whole animation: timeline
frame -> the server sets the scene -> the objects reach the client -> the editor's
regular render -> the next frame.

The result is one AVI video file (MJPEG codec: JPEG frames inside, plus the sound track).
The editor writes the file itself; the game lets Lua create files with only a few
extensions, so it is called <name>.avi.dat — the ".dat" has to be removed. (Before a0.6
frames could also be saved one by one as JPEG / PNG pictures; a single picture of a frame
is the editor's own still render.)
The game cannot write MP4: it has no H.264 encoder, and the engine's built-in video
recording (video.Record) creates no files on Linux — verified in game.

Where the time of a frame goes (measured in game, 3840 x 2628): the JPEG encoder of the
game — 0.65 s at quality 100, 0.37 s at 90; the scene passes for soft shadows and depth
of field; the wait for the scene to arrive from the server. Hence:
  * a video has its own JPEG quality (gmfm_video_quality, 90) — a still keeps its own;
  * only a part of the soft shadow / depth of field passes is made (gmfm_render_samples);
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

WebM (a0.7, Windows): the engine's own video writer (video.Record — the one of the game's
gm_video and demo-to-video) makes garrysmod/videos/<name>.webm (VP8), a real video file
with no ".dat". It takes the SCREEN, not a texture: every finished frame is drawn at the
video's size into the top left corner of the screen and handed over as it is
(AddFrame(1 / fps, false) — the writer takes the top left width x height of the screen), so
the video is at most as big as the screen (the frame is scaled down to fit it). Measured in
game (2026-10-18, Windows build under Proton): with downsampling on, the writer does not
scale the screen to the video's proportions — a 1312 x 1080 video of a 1920 x 1080 screen
came out as the left part of the screen, cut off. The writer records
only the game's own live sound, not the editor's mix — the sound track goes next to the
video as data/speditor/renders/<name>.wav (put both into any video editor). lockfps is
left off: with it the engine keeps fps_max at the video rate after the recording. On Linux
the writer is there but writes no file (verified in game), so there it is AVI only.

Motion blur (a0.7), as in SFM: every video frame is the mean of several moments around it
(gmfm_render_mblur of them, spread over the shutter — gmfm_render_shutter, the part
of the frame's time it stays open: 0.5 = a 180° shutter, the film look). Each moment is a
scene of its own from the server (it poses the scene at fractional frames), so a frame
costs that many times more.

  SA.IsAnimated()                 the scene has animation
  SA.RenderSequence(opts)         render the animation       SA.StopRender()
]]
local COMP = SPeditor.Component("saeditor")
local SA  = COMP.SA
local C   = SPeditor.Client

local cvMode    = CreateClientConVar("gmfm_render_mode", "anim", true, false)     -- anim | frame (a still of the current frame)
local cvSettle  = CreateClientConVar("gmfm_render_settle", "0.3", true, false)    -- the longest wait for the scene, s
local cvQuality = CreateClientConVar("gmfm_video_quality", "90", true, false)    -- JPEG quality of a video
local cvSamples = CreateClientConVar("gmfm_render_samples", "50", true, false)    -- soft shadow / DoF passes, percent
local cvFps     = CreateClientConVar("gmfm_render_fps", "0", true, false)         -- frames a second of the video, 0 — as the animation
local cvBlur    = CreateClientConVar("gmfm_render_mblur", "0", true, false)       -- motion blur: moments a frame, 0 — off
local cvShutter = CreateClientConVar("gmfm_render_shutter", "0.5", true, false)   -- motion blur: the part of a frame the shutter is open
local cvFormat  = CreateClientConVar("gmfm_render_video", "avi", true, false)     -- avi | webm (Windows only) | png | jpeg (pictures)

-- The game's JPEG encoder has only five levels (measured in game on a 1280 x 876 frame):
-- 100 — 1148 KB, 71..99 — 158 KB, 51..70 — 96 KB, 31..50 — 56 KB, up to 30 — 28 KB.
SA.RENDER_QUALITIES = { 100, 90, 70, 50, 30 }
SA.RENDER_SAMPLES = { 100, 50, 25 }
-- Frames a second of the video. Above the animation's own rate the frames in between are
-- taken between the keys (the server poses the scene at fractional frames), as in SFM.
SA.RENDER_FPS = { 0, 24, 25, 30, 48, 50, 60, 120 }
function SA.RenderFps()
	local v = math.floor(cvFps:GetFloat())
	return v > 0 and math.Clamp(v, 1, 240) or SA.fps
end

SA.RENDER_BLUR = { 0, 4, 8, 16 }
SA.RENDER_SHUTTERS = { 0.25, 0.5, 1 }
function SA.RenderBlur() return math.Clamp(math.floor(cvBlur:GetFloat()), 0, 32) end
function SA.RenderShutter() return math.Clamp(cvShutter:GetFloat(), 0.05, 1) end

SA.WEBM_OK = system.IsWindows()
function SA.RenderVideoFormat()
	local f = cvFormat:GetString()
	if f == "png" or f == "jpeg" then return f end      -- a sequence of pictures (b0.2.4)
	return (SA.WEBM_OK and f == "webm") and "webm" or "avi"
end
-- the bit rate of a WebM video (kbit/s) for every "Video size" level
local WEBM_BITRATE = { [100] = 50000, [90] = 25000, [70] = 12000, [50] = 6000, [30] = 3000 }

function SA.IsAnimated() return next(SA.tracks) ~= nil or #(SA.sounds or {}) > 0 end
function SA.RenderMode() return cvMode:GetString() == "frame" and "frame" or "anim" end

-- the progress of a render job: frames done so far (counting the one in work) and their total
function SA.RenderProgress(job) return job.n + 1, job.total end
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
-- WAV (16-bit stereo): the sound track next to a WebM video
---------------------------------------------------------------------
local function wavOpen(path, rate)
	local f = file.Open(path, "wb", "DATA")
	if not f then return nil end
	f:Write("RIFF" .. u32(0) .. "WAVE" .. "fmt " .. u32(16) .. u16(1) .. u16(2) .. u32(rate) .. u32(rate * 4) .. u16(4) .. u16(16)
		.. "data" .. u32(0))
	return { f = f, size = 0 }
end

local function wavWrite(wav, pcm)
	if #pcm == 0 then return end
	wav.f:Write(pcm)
	wav.size = wav.size + #pcm
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

-- WebM: the engine's writer, at most the size of the screen. The width is a multiple of 16:
-- at any other width every row of the video came out shifted against the previous one — the
-- picture was smeared into slanted stripes (measured in game: 1314 broken, 1312 clean).
-- The height is even for VP8.
local function openWebm(job)
	local W, H = C.GetRenderSize()
	local k = math.min(1, ScrW() / W, ScrH() / H)
	local vw, vh = math.max(math.floor(W * k / 16) * 16, 16), math.max(math.floor(H * k / 2) * 2, 16)
	local q = job.quality
	local rate = WEBM_BITRATE[100]
	for _, v in ipairs(SA.RENDER_QUALITIES) do if q <= v then rate = WEBM_BITRATE[v] end end
	local writer, err = video.Record({
		name = job.name, container = "webm", video = "vp8", audio = "vorbis",
		quality = 1, bitrate = rate, width = vw, height = vh, fps = job.fps, lockfps = false,
	})
	if writer and err then writer:Finish() writer = nil end
	if not writer then
		ErrorNoHalt("[SAeditor] video.Record: " .. tostring(err) .. "\n")
		return false
	end
	writer:SetRecordSound(false)
	job.webm, job.webmW, job.webmH = writer, vw, vh
	job.path = "garrysmod/videos/" .. job.name .. ".webm"
	if job.mix then
		job.wavPath = RENDER_DIR .. "/" .. job.name .. ".wav"
		job.wav = wavOpen(job.wavPath, SA.Audio.RATE)
	end
	return true
end

local function openVideo(job)
	if job.format == "webm" then
		if openWebm(job) then return true end
		-- (b0.2.5) the game's writer refused (a report: "Could not create the video file" with
		-- WebM on Windows): the video is written as AVI by the editor instead of failing
		SPeditor.Notify("#sa_rnd_webm_avi", 1)
		job.format = "avi"
	end
	-- a picture for every frame (b0.2.4, asked on the Workshop): data/speditor/renders/<name>/
	-- <name>_0001.png …, the sound as <name>.wav beside them — for a video editor
	if job.format == "png" or job.format == "jpeg" then
		job.seq = true
		ensureDir(RENDER_DIR .. "/" .. job.dir)
		job.path = RENDER_DIR .. "/" .. job.dir
		if job.mix then
			job.wavPath = RENDER_DIR .. "/" .. job.dir .. "/" .. job.name .. ".wav"
			job.wav = wavOpen(job.wavPath, SA.Audio.RATE)
		end
		return true
	end
	local W, H = C.GetRenderSize()
	local part = job.part or 1
	job.path = RENDER_DIR .. "/" .. job.name .. (part > 1 and ("_part" .. part) or "") .. ".avi.dat"
	local ok, avi = pcall(aviOpen, job.path, W, H, job.fps, job.mix and SA.Audio.RATE or nil)
	job.avi = ok and avi or nil
	return job.avi ~= nil
end

-- Ask the server for the frame job.cur. On the answer the scene is remembered as the
-- client sees it; the frame is shot once it is the same in the next game frame.
local function seek(job)
	job.state = "wait_ack"
	job.deadline = RealTime() + 3
	-- motion blur: the moment job.sub of job.blur, spread evenly over the open shutter around the frame
	local t = job.cur
	if job.blur > 1 then
		t = math.Clamp(job.cur + job.step * job.shutter * ((job.sub - 0.5) / job.blur - 0.5), 0, SA.frames)
	end
	SA.Seek(t, function()
		if SA.rendering == job and job.state == "wait_ack" then
			job.state = "settle"
			job.ackT, job.sig, job.sigFrame = RealTime(), sceneSignature(), FrameNumber()
		end
	end)
end

-- the camera of the frame being shot: "cuts" — the camera the animation's cuts give at it
local function frameCamera(job)
	if job.camera == "cuts" then return SA.CameraAt(job.cur) end
	return job.camera
end

-- opts = { camera = Entity | "work" | "cuts" | nil, from, to, name,
--          blur = motion blur moments a frame (nil — gmfm_render_mblur), shutter = 0..1,
--          settle = the longest wait for the scene in seconds, quality = JPEG quality,
--          samples = percent of soft shadow / depth of field passes,
--          fps = frames a second of the video (nil — gmfm_render_fps),
--          onDone = function(ok, path, count) }
---------------------------------------------------------------------
-- Slowed game time while the animation renders (a0.8). The engine runs a particle system
-- one game frame at a time; a frame of the unfocused game is 0.05 s, a frame of the video
-- 0.042 s (24 fps), so the moment of an effect in the video was off by up to half a game frame
-- and jumped back and forth (measured: ±0.025 s, some moments shown twice) — "the particles are
-- not stable". With the game slowed, a game frame is a few milliseconds of game time and the
-- system lands on the moment of every video frame; effects that play by themselves (Emitter
-- tool, Lua effects) also run at about the speed of the video instead of several times faster.
-- Single player only (it slows the whole server); the server puts the time back by itself if
-- the client stops asking (sv_saeditor.lua).
---------------------------------------------------------------------
local cvSlowFx = CreateClientConVar("gmfm_render_slowfx", "1", true, false, "SAeditor: slow the game down while an animation with effects renders", 0, 1)
-- b0.1: the depth of field of the camera (its keyed camera effect) in the video
CreateClientConVar("gmfm_render_dof", "1", true, false, "SAeditor: keep the camera's own depth of field in the video", 0, 1)
SA.SLOW_STEPS = 8          -- game frames per moment of the video
local function sendSlow(ts)
	COMP:NetStart("Slow")
	net.WriteFloat(ts)
	net.SendToServer()
end

local function hasEffects()
	for _, e in ipairs(C.Objects()) do
		if C.IsEffect(e) and SA.tracks[SA.UID(e)] then return true end
	end
	return false
end

local function updateSlow(job)
	if not job.slow then return end
	local now = RealTime()
	if now < (job.slowNext or 0) then return end
	job.slowNext = now + 0.5
	-- the real length of a game frame (RealFrameTime is not scaled), smoothed
	local real = math.Clamp(RealFrameTime(), 0.002, 0.25)
	job.realFt = job.realFt and (job.realFt * 0.7 + real * 0.3) or real
	local moment = 1 / job.fps / math.max(job.blur > 1 and job.blur or 1, 1)
	local want = math.Clamp(moment / (SA.SLOW_STEPS * job.realFt), 0.02, 1)
	want = math.Round(want, 3)
	if not job.ts or math.abs(want - job.ts) / job.ts > 0.15 or now > (job.slowSent or 0) + 5 then
		job.ts, job.slowSent = want, now
		sendSlow(want)
	end
end
SA.UpdateRenderSlow = updateSlow

function SA.RenderSlowOn() return cvSlowFx:GetBool() end

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
	-- video frame n shows animation frame from + n * step (a fraction when the video runs faster)
	local fps = math.Clamp(math.floor(opts.fps or SA.RenderFps()), 1, 240)
	local step = SA.fps / fps
	local job = {
		fps = fps, step = step, n = 0, total = math.floor((to - from) / step + 1e-6) + 1,
		camera = opts.camera, from = from, to = to, cur = from, name = name, dir = name,
		settle = math.Clamp(opts.settle or cvSettle:GetFloat(), 0.05, 3),
		-- on someone else's server the scene comes with a delay of its own
		minWait = opts.minWait or (game.SinglePlayer() and 0 or 0.1), seek = seek,
		trustAck = game.SinglePlayer() and not opts.minWait,
		quality = math.Clamp(math.floor(opts.quality or SA.RenderQuality()), 10, 100),
		sampleScale = math.Clamp(opts.samples or SA.RenderSamples(), 10, 100) / 100,
		onDone = opts.onDone, count = 0, state = "seek", wasFrame = SA.frame,
		blur = math.Clamp(math.floor(opts.blur or SA.RenderBlur()), 0, 32), sub = 1,
		shutter = math.Clamp(opts.shutter or SA.RenderShutter(), 0.05, 1),
		format = opts.format or SA.RenderVideoFormat(),
	}
	if #(SA.sounds or {}) > 0 then job.mix = SA.Audio.NewMix(SA.sounds, SA.fps, from, fps) end
	ensureDir(RENDER_DIR)
	if not openVideo(job) then
		SPeditor.Notify("#sa_rnd_failed", 1)
		return false
	end
	-- effects that cannot be stopped at a moment: say so once, before the render
	local nLive = 0
	for _, e in ipairs(C.Objects()) do
		if C.IsEffect(e) and SPeditor.Effects.IsLive(e) and SA.tracks[SA.UID(e)] then nLive = nLive + 1 end
	end
	job.slow = game.SinglePlayer() and cvSlowFx:GetBool() and hasEffects()
	if nLive > 0 and not job.slow then SPeditor.Notify("#sa_rnd_fx_live|" .. nLive, 0) end
	if job.slow then SPeditor.Notify("#sa_rnd_slow", 0) end
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
	if job.ts then sendSlow(1) end
	local path = "garrysmod/data/" .. RENDER_DIR .. "/" .. job.name
	if job.webm then
		pcall(job.webm.Finish, job.webm)
		job.webm = nil
		path = job.path
		if job.wav then
			pcall(wavClose, job.wav)
			job.wav = nil
			if job.count == 0 then file.Delete(job.wavPath) end
		end
	elseif job.seq then
		path = "garrysmod/data/" .. job.path
		if job.wav then
			pcall(wavClose, job.wav)
			job.wav = nil
			if job.count == 0 then file.Delete(job.wavPath) end
		end
	elseif job.avi then
		job.bytes = (job.bytes or 0) + job.avi.pos
		job.repeats = (job.repeats or 0) + (job.avi.repeats or 0)
		pcall(aviClose, job.avi)
		path = "garrysmod/data/" .. RENDER_DIR .. "/" .. job.name .. ".avi.dat"
		if job.count == 0 then file.Delete(job.path) end
	end
	if ok and job.format == "webm" then
		SPeditor.Notify("#sa_rnd_done_webm|" .. job.count .. "|" .. path .. "|" .. job.webmW .. "|" .. job.webmH, 2)
		if job.wavPath and job.count > 0 then SPeditor.Notify("#sa_rnd_webm_wav|garrysmod/data/" .. job.wavPath, 0) end
		if SPeditor.UI.ShowRenderDone then
			local notes = { COMP:L("sa_rdone_webm", job.count, job.webmW, job.webmH) }
			if job.wavPath and job.count > 0 then notes[2] = COMP:L("sa_rdone_wav", "garrysmod/data/" .. job.wavPath) end
			SPeditor.UI.ShowRenderDone({ path = path, notes = notes })
		end
		if job.mix and #job.mix.skipped > 0 then
			SPeditor.Notify("#sa_snd_skipped|" .. table.concat(job.mix.skipped, ", ", 1, math.min(#job.mix.skipped, 6)), 1)
		end
	elseif ok and job.seq then
		SPeditor.Notify("#sa_rnd_done_seq|" .. job.count .. "|" .. path, 2)
		if SPeditor.UI.ShowRenderDone then
			local notes = { COMP:L("sa_rdone_seq", job.count, job.fps) }
			if job.wavPath and job.count > 0 then notes[2] = COMP:L("sa_rdone_wav", "garrysmod/data/" .. job.wavPath) end
			SPeditor.UI.ShowRenderDone({ path = path, notes = notes })
		end
		if job.mix and #job.mix.skipped > 0 then
			SPeditor.Notify("#sa_snd_skipped|" .. table.concat(job.mix.skipped, ", ", 1, math.min(#job.mix.skipped, 6)), 1)
		end
	elseif ok then
		SPeditor.Notify("#sa_rnd_done_avi|" .. job.count .. "|" .. path, 2)
		local mb = (job.bytes or 0) / 1048576
		SPeditor.Notify("#sa_rnd_size|" .. string.format("%.1f", mb) .. "|" .. string.format("%.2f", mb / math.max(job.count / job.fps, 0.04))
			.. "|" .. (job.repeats or 0), 0)
		print("[SAeditor] " .. COMP:L("sa_rnd_mp4", job.name .. ".avi.dat", job.name))
		if SPeditor.UI.ShowRenderDone then
			local notes = { COMP:L("sa_rdone_avi", job.count), COMP:L("sa_rdone_dat") }
			if (job.part or 1) > 1 then notes[#notes + 1] = COMP:L("sa_rdone_parts", job.part) end
			SPeditor.UI.ShowRenderDone({ path = path, notes = notes })
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
	local src = SPeditor.Export.Source(frameCamera(job))
	if job.avi then aviSound(job.avi, SA.Audio.Mix(mix, job.n, src.origin, src.angles)) end
	if job.wav then wavWrite(job.wav, SA.Audio.Mix(mix, job.n, src.origin, src.angles)) end
end

local function frameDone(job, ok)
	if SA.rendering ~= job then return end
	if ok then ok = pcall(frameSound, job) end
	if not ok then
		SA.StopRender(false)
		return
	end
	job.count = job.count + 1
	if job.n + 1 >= job.total then
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
	job.n = job.n + 1
	job.cur = math.min(job.from + job.n * job.step, job.to)
	job.seek(job)         -- at once: waiting for the next Think would cost a game frame
end

COMP:Hook("Think", function()
	local job = SA.rendering
	if not job then return end
	if not C.active then
		SA.StopRender(false)
		return
	end
	updateSlow(job)
	if job.state == "seek" then
		seek(job)
	elseif job.state == "wait_ack" then
		if RealTime() > job.deadline then SA.StopRender(false) end
	elseif job.state == "render" then
		-- the frame was handed over and never came back (the export job was dropped without an
		-- answer): the render used to hang for good — the preview stood still and every next
		-- render said "busy" until the map was reloaded (b0.2.1). The frame is shot again.
		if not SPeditor.Export.pending and RealTime() - (job.renderT or 0) > 3 then
			job.lost = (job.lost or 0) + 1
			if job.lost > 3 then SA.StopRender(false) else job.state = "seek" end
		end
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
				single = true, camera = frameCamera(job), dir = job.dir,
				-- the depth of field: the camera's own (Camera effects) or, for a camera without
				-- it, the Render window's (b0.2.4: before it was left out of videos — "DoF does
				-- not work in the animation render", Workshop)
				nodof = not GetConVar("gmfm_render_dof"):GetBool(),
				camdof = GetConVar("gmfm_render_dof"):GetBool(),
				name = string.format("%s_%04d", job.name, job.n + 1),
				format = job.seq and job.format or "jpeg", quality = job.quality, sampleScale = job.sampleScale, silent = true,
				-- "engine frame": the effects are settled by the previous frame of the animation
				warmup = (job.count > 0) and 1 or nil,
				-- a video frame goes straight into the file
				capture = job.avi and function(data)
					if SA.rendering ~= job or #data == 0 then return false end
					aviFrame(job.avi, data)
				end or nil,
				-- WebM: the frame at the video's size in the top left corner of the screen, and
				-- the engine's writer takes that part of the screen
				rtCapture = job.webm and function(rt)
					if SA.rendering ~= job or not job.webm then return false end
					SPeditor.Render.DrawFull(rt, job.webmW, job.webmH)
					job.webm:AddFrame(1 / job.fps, false)
				end or nil,
				accum = job.blur > 1 and { i = job.sub, n = job.blur } or nil,
				onDone = function(ok)
					-- motion blur: the next moment of the same frame, the frame itself after the last
					if ok and job.blur > 1 and job.sub < job.blur and SA.rendering == job then
						job.sub = job.sub + 1
						job.seek(job)
						return
					end
					job.sub = 1
					frameDone(job, ok)
				end,
			})
			if accepted then job.state, job.renderT = "render", RealTime() end
		end
	end
end, "render")

---------------------------------------------------------------------
-- The editor's Render button: a scene with animation is rendered as a whole
---------------------------------------------------------------------
COMP:Hook("SPeditor_RenderRequest", function(opts)
	local mode = SA.RenderMode()
	if not SA.IsAnimated() or mode == "frame" then return end
	local camera = opts.camera
	if camera == "primary" then camera = nil end
	-- the Primary Viewport of an animation with camera cuts: the video follows the cuts
	if camera == nil and #SA.cuts > 0 then camera = "cuts" end
	-- only the cameras of the scene are rendered (cl_export.lua SceneCamera)
	if camera ~= "cuts" and not SPeditor.Export.SceneCamera(camera) then
		SPeditor.Notify("#render_need_camera", 1)
		return true
	end
	-- the frames of the Animation tab of the Render window (cl_saeditor_ui.lua)
	local from = SA.rdFrom and math.Clamp(SA.rdFrom, 0, SA.frames) or nil
	local to = SA.rdTo and math.Clamp(SA.rdTo, 0, SA.frames) or nil
	if from and to and to <= from then from, to = nil, nil end
	SA.RenderSequence({ camera = camera, name = opts.name, onDone = opts.onDone, from = from, to = to })
	return true
end, "render")
