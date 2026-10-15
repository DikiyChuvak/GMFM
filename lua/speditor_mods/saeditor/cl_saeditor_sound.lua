--[[
SAeditor — sounds and voices on the timeline.

A sound clip starts at a frame and either comes from an object of the scene (a spatial
sound: quieter with distance from the camera, moving between the left and the right ear
as the object or the camera moves) or is heard everywhere (music, a narrator). A voice
is a spatial sound that comes from the character's head.

The game's own 3D sound is tied to the player's body, and in the editor the player stands
still while the picture is taken by the editor's cameras. So the editor works out the
volume and the left / right balance itself (SA.Spatial) from the camera of the Primary
Viewport — and, in the render, from the camera the animation is shot with. The same
numbers drive both the playback (sound.PlayFile channels) and the sound track of the video.

The sound track of the video is mixed here, in Lua, one video frame at a time while the
scene stands on that frame (SA.Audio.Mix): the file is read as bytes, so only uncompressed
WAV can be mixed in — MP3 and OGG are played in the editor but left out of the video.

  SA.sounds                       the clips (SA.CleanSound in sh_saeditor.lua)
  SA.AddSound(path, opts)   SA.ChangeSound(id, fields)   SA.RemoveSound(id)
  SA.SoundLength(clip)            length in timeline frames (nil while loading)
  SA.SplitSound(id, frame)        cut a clip in two at a frame
  SA.TrimSound(id, side, frame)   cut off the start ("in") or the end ("out") of a clip at a frame
  SA.OpenSounds()                 the "Sounds and voices" window
]]
local MOD  = SPeditor.Mod("saeditor")
local SA   = MOD.SA
local C    = SPeditor.Client
local UI   = SPeditor.UI
local Dock = SPeditor.Dock
local L    = SPeditor.L

SA.sounds = SA.sounds or {}
SA.Audio  = SA.Audio or {}
local A = SA.Audio
A.chans = A.chans or {}       -- [clip id] = { path, ch, failed }
A.len   = A.len or {}         -- [path] = length in seconds (false — the file does not load)
A.wavs  = A.wavs or {}        -- [path] = parsed WAV (false — cannot be mixed)

---------------------------------------------------------------------
-- The list. Every edit sends the whole list to the server (it is kept there to be
-- saved with the scene) and is one entry of the editor's history.
---------------------------------------------------------------------
local function copyList(list)
	local out = {}
	for i, c in ipairs(list) do out[i] = table.Copy(c) end
	return out
end

local function send(list)
	MOD:NetStart("Sounds")
	SPeditor.WriteTable(list)
	net.SendToServer()
end

local function apply(list)
	SA.sounds = list
	hook.Run("SAeditor_Changed")
end

local function commit(list)
	local before, after = copyList(SA.sounds), copyList(list)
	apply(list)
	send(list)
	C.PushHistory("sa sound", function()
		apply(copyList(before))
		send(before)
	end, function()
		apply(copyList(after))
		send(after)
	end)
end

function SA.SoundByID(id)
	for _, c in ipairs(SA.sounds) do
		if c.id == id then return c end
	end
end

-- opts = { f, uid, voice, vol, pitch, dist, cin, cout }
function SA.AddSound(path, opts)
	opts = opts or {}
	if #SA.sounds >= SA.MAX_SOUNDS then
		SPeditor.Notify("#sa_snd_limit", 1)
		return nil
	end
	local id = 0
	for _, c in ipairs(SA.sounds) do id = math.max(id, c.id) end
	local clip = SA.CleanSound({
		id = id + 1, path = path, f = opts.f or math.floor(SA.frame + 0.5), uid = opts.uid or 0, voice = opts.voice,
		vol = opts.vol or 1, pitch = opts.pitch or 100, dist = opts.dist or (opts.voice and 150 or 300),
		cin = opts.cin, cout = opts.cout, fin = opts.fin, fout = opts.fout,
	})
	if not clip then return nil end
	local list = copyList(SA.sounds)
	list[#list + 1] = clip
	commit(list)
	return clip
end

function SA.ChangeSound(id, fields)
	local list = copyList(SA.sounds)
	for i, c in ipairs(list) do
		if c.id == id then
			for k, v in pairs(fields) do c[k] = v end
			local clean = SA.CleanSound(c)
			if not clean then return end
			list[i] = clean
			commit(list)
			return
		end
	end
end

function SA.RemoveSound(id)
	local list = {}
	for _, c in ipairs(SA.sounds) do
		if c.id ~= id then list[#list + 1] = table.Copy(c) end
	end
	if #list ~= #SA.sounds then commit(list) end
end

-- the server's copy (scene loaded, scene cleared, another edit confirmed)
function SA.ReceiveSounds(list)
	local out = {}
	for _, c in ipairs(istable(list) and list or {}) do
		local clip = SA.CleanSound(c)
		if clip then out[#out + 1] = clip end
	end
	SA.sounds = out
end

---------------------------------------------------------------------
-- Where a sound comes from and how it is heard
---------------------------------------------------------------------
local HEAD_BONES = { "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Head", "bip_head", "Head" }

function SA.EmitterPos(clip)
	if (clip.uid or 0) == 0 then return nil end
	local ent = SA.EntByUID(clip.uid)
	if not IsValid(ent) then return nil end
	if clip.voice then
		for _, name in ipairs({ "mouth", "eyes" }) do
			local id = ent:LookupAttachment(name)
			local att = id and id > 0 and ent:GetAttachment(id)
			if att then return att.Pos end
		end
		for _, name in ipairs(HEAD_BONES) do
			local bone = ent:LookupBone(name)
			local m = bone and ent:GetBoneMatrix(bone)
			if m then return m:GetTranslation() end
		end
	end
	return C.CenterOf(ent) or ent:GetPos()
end

-- Volume (0..2) and balance (-1 left .. 1 right) of a clip for a listener.
-- Up to the distance clip.dist the sound is at full volume, further it falls off as
-- 1 / distance; a sound behind the camera is a little quieter.
function SA.Spatial(clip, pos, ang)
	local vol = clip.vol or 1
	local from = SA.EmitterPos(clip)
	if not from then return vol, 0 end
	local d = from - pos
	local dist = d:Length()
	if dist < 1 then return vol, 0 end
	local dir = d / dist
	local ref = math.max(clip.dist or 300, 1)
	local gain = (dist <= ref) and 1 or (ref / dist)
	gain = gain * (0.8 + 0.1 * (dir:Dot(ang:Forward()) + 1))
	local pan = dir:Dot(ang:Right()) * math.min(dist / 48, 1) * 0.85
	return vol * gain, math.Clamp(pan, -1, 1)
end

-- gains of the left and the right channel
local function stereo(vol, pan)
	return vol * math.min(1, 1 - pan), vol * math.min(1, 1 + pan)
end

---------------------------------------------------------------------
-- Playback in the editor: one channel per clip, kept on the playhead
---------------------------------------------------------------------
local function dropChannel(id)
	local e = A.chans[id]
	if e and IsValid(e.ch) then e.ch:Stop() end
	A.chans[id] = nil
end

local function loadChannel(clip)
	local e = { path = clip.path }
	A.chans[clip.id] = e
	sound.PlayFile(clip.path, "noplay noblock", function(ch)
		-- the clip was removed or got another file while this one was loading
		if A.chans[clip.id] ~= e then
			if IsValid(ch) then ch:Stop() end
			return
		end
		if not IsValid(ch) then
			e.failed = true
			A.len[clip.path] = false
			SPeditor.Notify("#sa_snd_failed|" .. clip.path, 1)
			return
		end
		e.ch = ch
		A.len[clip.path] = ch:GetLength()
		hook.Run("SAeditor_SoundLoaded", clip)
	end)
end

function A.Sync()
	local alive = {}
	for _, c in ipairs(SA.sounds) do
		alive[c.id] = true
		local e = A.chans[c.id]
		if e and e.path ~= c.path then
			dropChannel(c.id)
			e = nil
		end
		if not e then loadChannel(c) end
	end
	for id in pairs(A.chans) do
		if not alive[id] then dropChannel(id) end
	end
end

function A.StopAll()
	for _, e in pairs(A.chans) do
		if IsValid(e.ch) and e.ch:GetState() == GMOD_CHANNEL_PLAYING then e.ch:Pause() end
	end
end

-- length of a clip in timeline frames, trimming included (nil — not known yet)
function SA.SoundLength(clip)
	local len = A.len[clip.path]
	if not len then return nil end
	return math.max(len - (clip.cin or 0) - (clip.cout or 0), 0) / (clip.pitch / 100) * SA.fps
end

-- The place in the file (seconds) that plays at a timeline frame
local function fileTime(clip, frame)
	return (clip.cin or 0) + (frame - clip.f) / SA.fps * (clip.pitch / 100)
end

-- the shortest piece a clip can be trimmed to, in seconds of the file
local MIN_PIECE = 0.05

-- Cut a clip in two at the frame: the first part ends there, the second starts there
function SA.SplitSound(id, frame)
	local len = A.len[(SA.SoundByID(id) or {}).path or ""]
	if not len then return false end
	local list = copyList(SA.sounds)
	for i, c in ipairs(list) do
		if c.id == id then
			local t = fileTime(c, frame)
			if t <= c.cin + MIN_PIECE or t >= len - c.cout - MIN_PIECE then return false end
			local nextId = 0
			for _, o in ipairs(list) do nextId = math.max(nextId, o.id) end
			local second = table.Copy(c)
			second.id, second.f, second.cin = nextId + 1, math.floor(frame + 0.5), t
			c.cout = len - t
			list[i] = SA.CleanSound(c)
			table.insert(list, i + 1, SA.CleanSound(second))
			commit(list)
			return true
		end
	end
	return false
end

-- side "in": the clip starts at the frame (the sound before it is cut off), "out": it ends there.
-- frame = nil puts the side back to the start / end of the file.
function SA.TrimSound(id, side, frame)
	local c = SA.SoundByID(id)
	local len = c and A.len[c.path]
	if not len then return false end
	if side == "in" then
		if not frame then
			-- the sound keeps its place in time: the clip start moves back by what was cut
			local back = c.cin / (c.pitch / 100) * SA.fps
			SA.ChangeSound(id, { cin = 0, f = math.max(math.floor(c.f - back + 0.5), 0) })
			return true
		end
		local t = fileTime(c, frame)
		if t >= len - c.cout - MIN_PIECE then return false end
		t = math.max(t, 0)
		SA.ChangeSound(id, { cin = t, f = math.floor(c.f + (t - c.cin) / (c.pitch / 100) * SA.fps + 0.5) })
		return true
	end
	if not frame then
		SA.ChangeSound(id, { cout = 0 })
		return true
	end
	local t = fileTime(c, frame)
	if t <= c.cin + MIN_PIECE then return false end
	SA.ChangeSound(id, { cout = math.max(len - t, 0) })
	return true
end

MOD:Hook("SAeditor_Changed", function() A.Sync() end, "sound")

MOD:Hook("SPeditor_StateChanged", function(on)
	if on then return end
	for id in pairs(A.chans) do dropChannel(id) end
	if IsValid(A.preview) then A.preview:Stop() end
end, "sound")

MOD:Hook("Think", function()
	if next(A.chans) == nil then return end
	local playing = SA.playing and C.active and not SA.rendering
	local pos, ang
	for _, c in ipairs(SA.sounds) do
		local e = A.chans[c.id]
		local ch = e and e.ch
		if IsValid(ch) then
			local rate = c.pitch / 100
			local t = fileTime(c, SA.frame)                    -- the place inside the file
			if playing and t >= c.cin and t < ch:GetLength() - c.cout - 0.03 then
				if not pos then pos, ang = C.GetView() end
				local vol, pan = SA.Spatial(c, pos, ang)
				-- fades: seconds of the clip played and left, at its speed
				vol = vol * SA.SoundFade(c, (t - c.cin) / rate, (ch:GetLength() - c.cout - t) / rate)
				ch:SetVolume(vol)
				ch:SetPan(pan)
				ch:SetPlaybackRate(rate)
				if ch:GetState() ~= GMOD_CHANNEL_PLAYING then
					ch:SetTime(t)
					ch:Play()
				elseif math.abs(ch:GetTime() - t) > 0.15 then
					-- the playhead jumped (loop, a slow frame): the sound follows it
					ch:SetTime(t)
				end
			elseif ch:GetState() == GMOD_CHANNEL_PLAYING then
				ch:Pause()
			end
		end
	end
end, "sound")

---------------------------------------------------------------------
-- Reading WAV files for the sound track of the video
---------------------------------------------------------------------
local byte = string.byte

local function le(data, at, n)
	local a, b, c, d = byte(data, at, at + n - 1)
	return a + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216
end

-- { data, at = index of the first sample byte, n = sample frames, ch, rate, wide = bytes per sample }
function A.LoadWav(path)
	local wav = A.wavs[path]
	if wav ~= nil then return wav end
	wav = false
	local data = string.lower(string.GetExtensionFromFilename(path) or "") == "wav" and file.Read(path, "GAME") or nil
	if data and #data > 44 and string.sub(data, 1, 4) == "RIFF" and string.sub(data, 9, 12) == "WAVE" then
		local at, fmt = 13, nil
		while at + 8 <= #data do
			local id, size = string.sub(data, at, at + 3), le(data, at + 4, 4)
			if id == "fmt " and size >= 16 then
				fmt = { tag = le(data, at + 8, 2), ch = le(data, at + 10, 2), rate = le(data, at + 12, 4), bits = le(data, at + 22, 2) }
			elseif id == "data" then
				-- uncompressed samples only, 8 or 16 bits, one or two channels
				if fmt and fmt.tag == 1 and (fmt.bits == 8 or fmt.bits == 16) and (fmt.ch == 1 or fmt.ch == 2) and fmt.rate >= 4000 then
					local wide = fmt.bits / 8
					size = math.min(size, #data - (at + 7))
					wav = { data = data, at = at + 8, n = math.floor(size / (wide * fmt.ch)), ch = fmt.ch, rate = fmt.rate, wide = wide }
				end
				break
			end
			at = at + 8 + size + size % 2
		end
	end
	A.wavs[path] = wav
	return wav
end

-- sample frame i (from 0) as left, right in -32768..32767
local function sampleAt(wav, i)
	local data, wide = wav.data, wav.wide
	local at = wav.at + i * wide * wav.ch
	if wide == 2 then
		local a, b, c, d = byte(data, at, at + 3)
		local l = a + b * 256
		if l >= 32768 then l = l - 65536 end
		if wav.ch == 1 then return l, l end
		local r = c + d * 256
		if r >= 32768 then r = r - 65536 end
		return l, r
	end
	local a, b = byte(data, at, at + 1)
	local l = (a - 128) * 256
	if wav.ch == 1 then return l, l end
	return l, (b - 128) * 256
end

A.RATE = 44100

-- A new sound track: mix = A.NewMix(clips, fps, firstFrame, videoFps)
-- fps — frames a second of the animation (clip start frames), videoFps — of the video
-- (the length of one piece; nil — the same)
function A.NewMix(clips, fps, first, vfps)
	local mix = { fps = fps, vfps = vfps or fps, first = first, clips = {}, skipped = {}, gains = {}, done = 0 }
	for _, c in ipairs(clips) do
		local wav = A.LoadWav(c.path)
		if wav then
			mix.clips[#mix.clips + 1] = { clip = c, wav = wav }
		else
			mix.skipped[#mix.skipped + 1] = string.GetFileFromFilename(c.path)
		end
	end
	return mix
end

-- The piece of the sound track for video frame number index (from 0), as heard from
-- pos / ang: 16-bit stereo, A.RATE samples a second. The scene must stand on that frame.
-- The volume of each clip glides from the previous frame's value to this one's over the
-- piece: a jump would be heard as a click.
function A.Mix(mix, index, pos, ang)
	local rate = A.RATE
	local n0 = math.floor(index * rate / mix.vfps + 0.5)
	local n1 = math.floor((index + 1) * rate / mix.vfps + 0.5)
	local n = n1 - n0
	local left, right = {}, {}
	for i = 1, n do left[i], right[i] = 0, 0 end

	for _, it in ipairs(mix.clips) do
		local c, wav = it.clip, it.wav
		local speed = wav.rate * (c.pitch / 100)                     -- file samples per second of video
		-- trimming: the clip plays the file from sample first to sample last
		local first = (c.cin or 0) * wav.rate
		local last = math.min(wav.n - 1, wav.n - (c.cout or 0) * wav.rate)
		local s0 = (n0 / rate - (c.f - mix.first) / mix.fps) * speed + first
		local step = speed / rate
		-- a few milliseconds of fade at a cut: a sound cut off mid-wave clicks
		local fade = ((c.cin or 0) > 0 or (c.cout or 0) > 0) and wav.rate * 0.004 or 0
		if s0 + n * step < first or s0 >= last then
			mix.gains[c.id] = nil
		else
			local vol, pan = SA.Spatial(c, pos, ang)
			local l1, r1 = stereo(vol, pan)
			-- a sound heard everywhere keeps its own stereo; a spatial one is placed as a whole
			local mono = (c.uid or 0) ~= 0 and wav.ch == 2
			local prev = mix.gains[c.id]
			local l0, r0 = prev and prev[1] or l1, prev and prev[2] or r1
			mix.gains[c.id] = { l1, r1 }
			for i = 0, n - 1 do
				local s = s0 + i * step
				if s >= first and s < last then
					local whole = math.floor(s)
					local frac = s - whole
					local al, ar = sampleAt(wav, whole)
					local bl, br = sampleAt(wav, whole + 1)
					local l, r = al + (bl - al) * frac, ar + (br - ar) * frac
					if mono then l = (l + r) * 0.5 r = l end
					if fade > 0 then
						local env = math.min((s - first) / fade, (last - s) / fade, 1)
						l, r = l * env, r * env
					end
					if c.fin > 0 or c.fout > 0 then
						local env = SA.SoundFade(c, (s - first) / speed, (last - s) / speed)
						l, r = l * env, r * env
					end
					local u = i / n
					left[i + 1] = left[i + 1] + l * (l0 + (l1 - l0) * u)
					right[i + 1] = right[i + 1] + r * (r0 + (r1 - r0) * u)
				end
			end
		end
	end

	-- Several loud sounds at once (a burst of shots) add up to more than a sample can hold.
	-- Above three quarters of the range the sum is bent smoothly towards the limit instead
	-- of being cut off flat: a flat cut is heard as crackle.
	local out, char, floor, tanh = {}, string.char, math.floor, math.tanh
	local KNEE, REST = 24576, 32767 - 24576
	local function limit(v)
		if v > KNEE then return KNEE + REST * tanh((v - KNEE) / REST) end
		if v < -KNEE then return -KNEE - REST * tanh((-v - KNEE) / REST) end
		return v
	end
	for i = 1, n do
		local l, r = floor(limit(left[i]) + 0.5), floor(limit(right[i]) + 0.5)
		if l > 32767 then l = 32767 elseif l < -32768 then l = -32768 end
		if r > 32767 then r = 32767 elseif r < -32768 then r = -32768 end
		if l < 0 then l = l + 65536 end
		if r < 0 then r = r + 65536 end
		out[i] = char(l % 256, floor(l / 256), r % 256, floor(r / 256))
	end
	mix.done = n1
	return table.concat(out)
end

---------------------------------------------------------------------
-- "Sounds and voices" window: the game's sound folders and the user's own files
---------------------------------------------------------------------
local function listen(path)
	if IsValid(A.preview) then A.preview:Stop() end
	A.preview = nil
	if not path then return end
	sound.PlayFile(path, "noblock", function(ch)
		if not IsValid(ch) then
			SPeditor.Notify("#sa_snd_failed|" .. path, 1)
			return
		end
		if IsValid(A.preview) then A.preview:Stop() end
		A.preview = ch
	end)
end
SA.ListenSound = listen

function SA.OpenSounds()
	if Dock.ShowPage("sa_sounds") then return end
	local COL = UI.PAL
	if not file.IsDir("speditor/sounds", "DATA") then file.CreateDir("speditor/sounds") end

	local W = 620
	local win, body = Dock.Create({ key = "sa_sounds", id = "sa_sounds", title = L("sa_snd_title"), w = W, h = math.min(600, ScrH() - 140),
			x = math.floor(ScrW() / 2 - W / 2), y = 110, dockable = false, icon = "icon16/sound.png" })
	win.minW, win.minH = 440, 380
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.sa_sounds = nil
		listen(nil)
	end

	local root = SA.soundRoot or "sound"

	local top = vgui.Create("DPanel", body)
	top:Dock(TOP)
	top:DockMargin(6, 6, 6, 2)
	top:SetTall(22)
	top.Paint = function() end
	local roots = UI.StyleCombo(vgui.Create("DComboBox", top))
	roots:Dock(LEFT)
	roots:SetWide(170)
	roots:AddChoice(L("sa_snd_root_game"), "sound", root == "sound")
	roots:AddChoice(L("sa_snd_root_user"), SA.SOUND_DIR, root ~= "sound")
	local count = vgui.Create("DLabel", top)
	count:Dock(FILL)
	count:DockMargin(8, 0, 0, 0)
	count:SetFont("SPeditor.Small")
	count:SetTextColor(COL.DIM)

	local opts = { attach = IsValid(C.selected), voice = false }
	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(176)
	foot.Paint = function() end
	local attach = UI.Check(foot, L("sa_snd_attach"), opts.attach, function(v) opts.attach = v end)
	local voice = UI.Check(foot, L("sa_snd_voice"), opts.voice, function(v) opts.voice = v end)
	local buttons = vgui.Create("DPanel", foot)
	buttons:Dock(TOP)
	buttons:DockMargin(4, 4, 4, 0)
	buttons:SetTall(28)
	buttons.Paint = function() end
	local hint = UI.Label(foot, L("sa_snd_hint"))
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:DockMargin(8, 6, 8, 4)

	-- The game's own file browser: folders on the left, the sounds of the folder on the right.
	-- A click plays a sound; several can be selected (Ctrl / Shift) and added at once.
	local browser
	local function selectedPaths()
		local out = {}
		if not IsValid(browser) or not IsValid(browser.Files) or not browser.Files.GetSelected then return out end
		local folder = browser:GetCurrentFolder() or ""
		for _, line in ipairs(browser.Files:GetSelected()) do
			out[#out + 1] = string.Trim(folder .. "/" .. line:GetColumnText(1), "/")
		end
		return out
	end
	-- Several sounds go one after another from the current frame: the length of each is
	-- learnt from the file before the next one is placed.
	local function addPaths(paths)
		local ent = opts.attach and C.selected or nil
		local uid = IsValid(ent) and SA.UID(ent) or 0
		local isVoice = opts.voice and uid ~= 0
		local f = math.floor(SA.frame + 0.5)
		local added, last = 0, nil
		local function finish()
			if added == 1 then
				SPeditor.Notify("#sa_snd_added|" .. string.GetFileFromFilename(last.path) .. "|" .. last.f, 2)
			elseif added > 1 then
				SPeditor.Notify(string.format(L("sa_snd_added_n"), added), 2)
			end
		end
		local function step(i)
			local path = paths[i]
			if not path then return finish() end
			local clip = SA.AddSound(path, { uid = uid, voice = isVoice, f = f })
			if not clip then return finish() end
			added, last = added + 1, clip
			if not paths[i + 1] then return finish() end
			sound.PlayFile(path, "noplay noblock", function(ch)
				local len = IsValid(ch) and ch:GetLength() or 0
				if IsValid(ch) then ch:Stop() end
				f = math.min(f + math.max(math.ceil(len * SA.fps), 1), SA.MAX_FRAMES)
				step(i + 1)
			end)
		end
		step(1)
	end
	local function build()
		if IsValid(browser) then browser:Remove() end
		SA.soundRoot = root
		browser = vgui.Create("DFileBrowser", body)
		browser:Dock(FILL)
		browser:DockMargin(6, 2, 6, 2)
		browser:SetPath("GAME")
		browser:SetBaseFolder(root)
		browser:SetName(root == "sound" and "sound" or L("sa_snd_root_user"))
		browser:SetFileTypes("*.wav *.mp3 *.ogg")
		browser:SetOpen(true)
		if SA.soundFolder and string.StartWith(SA.soundFolder, root) then browser:SetCurrentFolder(SA.soundFolder) end
		-- the file list allows several sounds at once
		local baseFiles = browser.SetupFiles
		browser.SetupFiles = function(b)
			local ok = baseFiles(b)
			if IsValid(b.Files) and b.Files.SetMultiSelect then b.Files:SetMultiSelect(true) end
			return ok
		end
		local baseShow = browser.ShowFolder
		browser.ShowFolder = function(b, path)
			baseShow(b, path)
			SA.soundFolder = path
			local n = IsValid(b.Files) and b.Files.GetLines and #b.Files:GetLines() or 0
			count:SetText(path and string.format(L("sa_snd_in_folder"), n) or "")
		end
		browser.OnSelect = function(_, path)
			listen(path)
			-- voice lines of the game live in sound/vo: the voice mark is offered by itself
			if string.find(path, "/vo/", 1, true) and not opts.voice then voice:SetValue(1) end
		end
		browser.OnDoubleClick = function(_, path) addPaths({ path }) end
		browser.OnRightClick = function(_, path)
			local m = UI.Menu()
			local sel = selectedPaths()
			if #sel < 2 then sel = { path } end
			m:AddOption(#sel > 1 and string.format(L("sa_snd_add_n"), #sel) or L("sa_snd_go"), function() addPaths(sel) end):SetIcon("icon16/sound_add.png")
			m:AddOption(L("sa_snd_preview"), function() listen(path) end):SetIcon("icon16/control_play_blue.png")
			m:AddOption(L("copy_path"), function() SetClipboardText(path) end)
			m:Open()
		end
	end
	roots.OnSelect = function(_, _, _, data)
		root = data
		SA.soundFolder = nil
		build()
	end
	build()

	local play = vgui.Create("DButton", buttons)
	play:Dock(LEFT)
	play:DockMargin(2, 2, 2, 2)
	play:SetWide(110)
	play:SetText("  " .. L("sa_snd_preview"))
	play:SetIcon("icon16/control_play_blue.png")
	UI.StyleButton(play, nil, 3)
	play.DoClick = function()
		local sel = selectedPaths()
		if sel[1] then listen(sel[1]) end
	end
	local stop = vgui.Create("DButton", buttons)
	stop:Dock(LEFT)
	stop:DockMargin(2, 2, 2, 2)
	stop:SetWide(70)
	stop:SetText("  " .. L("sa_snd_stop"))
	stop:SetIcon("icon16/control_stop_blue.png")
	UI.StyleButton(stop, nil, 3)
	stop.DoClick = function() listen(nil) end
	local go = vgui.Create("DButton", buttons)
	go:Dock(FILL)
	go:DockMargin(2, 2, 2, 2)
	go:SetText("  " .. L("sa_snd_go"))
	go:SetIcon("icon16/sound_add.png")
	UI.StyleButton(go, nil, 3)
	go.DoClick = function()
		local sel = selectedPaths()
		if #sel == 0 then SPeditor.Notify(L("sa_snd_pick"), 0) return end
		addPaths(sel)
	end
	go.Think = function(s)
		local n = IsValid(browser) and IsValid(browser.Files) and browser.Files.GetSelected and #browser.Files:GetSelected() or 0
		if n ~= s.SPN then
			s.SPN = n
			s:SetText("  " .. (n > 1 and string.format(L("sa_snd_add_n"), n) or L("sa_snd_go")))
		end
	end

	-- the mark follows the selection: no object — nothing to come from
	attach.Think = function(s)
		local has = IsValid(C.selected)
		if has ~= s.SPHas then
			s.SPHas = has
			s:SetEnabled(has)
			if not has then s:SetValue(0) end
		end
	end
	return win
end
