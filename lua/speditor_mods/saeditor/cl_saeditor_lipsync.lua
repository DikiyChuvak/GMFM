--[[
SAeditor — lip sync (a0.6): the mouth of a character follows a voice clip of the timeline.

Where the mouth shapes come from:
  * phonemes written into the WAV file (the VDAT chunk Faceposer and Source Filmmaker write
    when they extract phonemes; the voices of Half-Life 2, TF2 and other Valve games have it):
    every phoneme gives the shape of the mouth that says it;
  * otherwise the loudness of the sound: the louder, the more open the mouth. An uncompressed
    WAV is read as bytes at once; MP3 / OGG and compressed WAV are listened to silently in real
    time (as long as the clip lasts).
The shapes go to the server (net "Lip"), which turns them into keys of the face track and moves
only the mouth flexes (SA.MouthMap); the rest of the face keeps its keys.
]]
local MOD = SPeditor.Mod("saeditor")
local SA  = MOD.SA
local C   = SPeditor.Client
local A   = SA.Audio
local L   = SPeditor.L

local cvStrength = CreateClientConVar("saeditor_lip_strength", "1", true, false, "Lip sync: how wide the mouth opens (0.2 .. 2)", 0.2, 2)

-- phoneme -> { open, wide, round, close, bite } (SA.LIP_CH)
local VISEME = {}
local function vis(list, shape) for _, p in ipairs(list) do VISEME[p] = shape end end
vis({ "aa", "ao", "ah", "aw", "ay", "a" }, { 0.9, 0.1, 0, 0, 0 })
vis({ "ae", "eh", "ey", "e" }, { 0.65, 0.4, 0, 0, 0 })
vis({ "iy", "ih", "y", "ix", "i" }, { 0.3, 0.7, 0, 0, 0 })
vis({ "uw", "uh", "w", "ow", "oy", "o", "u" }, { 0.4, 0, 0.8, 0, 0 })
vis({ "er", "r", "axr" }, { 0.25, 0, 0.4, 0, 0 })
vis({ "sh", "ch", "jh", "zh" }, { 0.15, 0.2, 0.5, 0, 0 })
vis({ "m", "b", "p", "em" }, { 0, 0, 0, 1, 0 })
vis({ "f", "v" }, { 0.1, 0, 0, 0, 1 })
vis({ "th", "dh" }, { 0.25, 0.1, 0, 0, 0 })
local CONSONANT = { 0.35, 0.25, 0, 0, 0 }      -- s z t d n k g ng l hh x and the rest
local SILENT = { 0, 0, 0, 0, 0 }

---------------------------------------------------------------------
-- Phonemes of a WAV file: { { t0, t1, name, vol } }, words: { { t0, t1 } }; nil — none
---------------------------------------------------------------------
local function le(data, at, n)
	local a, b, c, d = string.byte(data, at, at + n - 1)
	return a + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216
end

function SA.ReadPhonemes(path)
	if string.lower(string.GetExtensionFromFilename(path) or "") ~= "wav" then return nil end
	local data = file.Read(path, "GAME")
	if not data or #data < 12 or string.sub(data, 1, 4) ~= "RIFF" then return nil end
	local at, text = 13, nil
	while at + 8 <= #data do
		local id, size = string.sub(data, at, at + 3), le(data, at + 4, 4)
		if id == "VDAT" then
			text = string.sub(data, at + 8, at + 7 + size)
			break
		end
		at = at + 8 + size + size % 2
	end
	if not text then return nil end
	local phonemes, words = {}, {}
	local inWords = false
	for line in string.gmatch(text, "[^\r\n]+") do
		line = string.Trim(line)
		if line == "WORDS" then
			inWords = true
		elseif line == "EMPHASIS" or line == "OPTIONS" or line == "PLAINTEXT" then
			inWords = false
		elseif inWords then
			-- WORD <text> <start> <end>
			local w0, w1 = string.match(line, "^WORD%s+.-%s+([%d%.]+)%s+([%d%.]+)$")
			if w0 then
				words[#words + 1] = { tonumber(w0), tonumber(w1) }
			else
				-- <code> <name> <start> <end> <volume>
				local name, p0, p1, vol = string.match(line, "^%d+%s+(%S+)%s+([%d%.]+)%s+([%d%.]+)%s*([%d%.]*)$")
				if name then phonemes[#phonemes + 1] = { tonumber(p0), tonumber(p1), string.lower(name), tonumber(vol) or 1 } end
			end
		end
	end
	if #phonemes == 0 then return nil end
	return phonemes, words
end

---------------------------------------------------------------------
-- Loudness of a sound: done({ [i] = level 0..1 at i * STEP seconds }) — or nil
---------------------------------------------------------------------
local STEP = 0.02

local function envelopeWav(path)
	local wav = A.LoadWav(path)
	if not wav then return nil end
	local out, byte = {}, string.byte
	local per = math.max(math.floor(wav.rate * STEP), 1)
	local stride = math.max(math.floor(per / 64), 1)    -- 64 samples a step are enough for a level
	local data, wide, ch = wav.data, wav.wide, wav.ch
	for i = 0, math.floor(wav.n / per) - 1 do
		local sum, cnt = 0, 0
		for s = i * per, (i + 1) * per - 1, stride do
			local at = wav.at + s * wide * ch
			local v
			if wide == 2 then
				local a, b = byte(data, at, at + 1)
				v = a + b * 256
				if v >= 32768 then v = v - 65536 end
				v = v / 32768
			else
				v = (byte(data, at) - 128) / 128
			end
			sum = sum + v * v
			cnt = cnt + 1
		end
		out[i] = math.sqrt(sum / math.max(cnt, 1))
	end
	return out
end

-- MP3, OGG, compressed WAV: played silently and measured as it plays (BASS measures the
-- level before the volume, verified in game)
local function envelopeListen(path, t0, t1, done)
	sound.PlayFile(path, "noplay noblock", function(ch)
		if not IsValid(ch) then done(nil) return end
		local out = {}
		ch:SetVolume(0)
		ch:SetTime(t0)
		ch:Play()
		local id = "SAeditor.LipListen" .. path
		hook.Add("Think", id, function()
			if not IsValid(ch) then hook.Remove("Think", id) done(nil) return end
			local t = ch:GetTime()
			local l, r = ch:GetLevel()
			out[math.floor(t / STEP + 0.5)] = math.max(l or 0, r or 0)
			if t >= t1 - 0.01 or ch:GetState() ~= GMOD_CHANNEL_PLAYING then
				hook.Remove("Think", id)
				ch:Stop()
				-- holes between measurements take the level before them
				local last = 0
				for i = 0, math.floor(t1 / STEP) do
					if out[i] then last = out[i] else out[i] = last end
				end
				done(out)
			end
		end)
	end)
end

---------------------------------------------------------------------
-- Shapes -> server
---------------------------------------------------------------------
local function send(ent, shapes, how)
	local id = SA.NextOp()
	MOD:NetStart("Lip")
	net.WriteUInt(id, 32)
	net.WriteUInt(SA.UID(ent), 32)
	net.WriteUInt(#shapes, 16)
	for _, sh in ipairs(shapes) do
		net.WriteUInt(sh.f, 32)
		for j = 1, #SA.LIP_CH do net.WriteUInt(math.Clamp(math.floor((sh.c[j] or 0) * 255 + 0.5), 0, 255), 8) end
	end
	net.SendToServer()
	SA.PushOpHistory("sa lipsync", id)
	SPeditor.Notify("#" .. how, 0)
end

-- one shape a frame: of two in the same frame a closed mouth wins (lips must meet on m, b, p),
-- otherwise the more open one
local function put(byFrame, f, c)
	local old = byFrame[f]
	if old then
		if (old[4] or 0) > 0.5 and (c[4] or 0) <= 0.5 then return end
		if (c[4] or 0) <= 0.5 and (old[1] or 0) >= (c[1] or 0) then return end
	end
	byFrame[f] = c
end

local function sorted(byFrame)
	local out = {}
	for f, c in pairs(byFrame) do out[#out + 1] = { f = f, c = c } end
	table.sort(out, function(x, y) return x.f < y.f end)
	return out
end

local function scaled(shape, k)
	local out = {}
	for j = 1, #SA.LIP_CH do out[j] = math.Clamp((shape[j] or 0) * k, 0, 1) end
	return out
end

-- SA.LipSync(clip, ent): the mouth of ent follows the clip
function SA.LipSync(clip, ent)
	if not IsValid(ent) or not SA.MouthMap(ent) then
		SPeditor.Notify("#sa_lip_noface", 1)
		return
	end
	local len = A.len[clip.path]
	if not len then
		SPeditor.Notify("#sa_lip_wait", 0)
		return
	end
	local rate = clip.pitch / 100
	local t0, t1 = clip.cin or 0, len - (clip.cout or 0)
	local strength = cvStrength:GetFloat()
	-- the timeline frame at which the place t (seconds of the file) is heard
	local function frameOf(t) return math.floor(clip.f + (t - t0) / rate * SA.fps + 0.5) end
	local first, last = frameOf(t0), frameOf(t1)

	local phonemes, words = SA.ReadPhonemes(clip.path)
	if phonemes then
		local byFrame = {}
		put(byFrame, first, SILENT)
		for _, p in ipairs(phonemes) do
			local t = (p[1] + p[2]) * 0.5
			if t >= t0 and t <= t1 then
				put(byFrame, frameOf(t), scaled(VISEME[p[3]] or CONSONANT, strength * math.Clamp(p[4], 0, 1.5)))
			end
		end
		-- pauses between words: the mouth closes
		for i, w in ipairs(words) do
			local nxt = words[i + 1]
			if w[2] >= t0 and w[2] <= t1 and (not nxt or nxt[1] - w[2] > 0.15) then
				put(byFrame, frameOf(math.min(w[2] + 0.04, t1)), SILENT)
				if nxt and nxt[1] - 0.04 <= t1 then put(byFrame, frameOf(nxt[1] - 0.04), SILENT) end
			end
		end
		put(byFrame, last, SILENT)
		send(ent, sorted(byFrame), "sa_lip_phonemes")
		return
	end

	local function fromEnvelope(env)
		if not env then
			SPeditor.Notify("#sa_lip_failed", 1)
			return
		end
		-- the reference loudness: a loud part of the speech, not the single loudest peak
		local vals = {}
		for i = math.floor(t0 / STEP), math.floor(t1 / STEP) do
			if env[i] and env[i] > 0.005 then vals[#vals + 1] = env[i] end
		end
		if #vals == 0 then
			SPeditor.Notify("#sa_lip_silent", 1)
			return
		end
		table.sort(vals)
		local ref = vals[math.max(math.floor(#vals * 0.9), 1)]
		-- a shape every frame, but only where the mouth changes noticeably
		local shapes, prev = {}, nil
		for f = first, last do
			local t = t0 + (f - clip.f) / SA.fps * rate
			-- the loudest step within the frame
			local lvl = 0
			for i = math.floor(t / STEP), math.floor((t + rate / SA.fps) / STEP) do lvl = math.max(lvl, env[i] or 0) end
			local open = lvl < ref * 0.1 and 0 or math.Clamp((lvl / ref) ^ 0.7, 0, 1) * 0.9 * strength
			open = math.Clamp(open, 0, 1)
			if f == first or f == last then open = 0 end
			if not prev or math.abs(open - prev) > 0.08 or f == last then
				shapes[#shapes + 1] = { f = f, c = { open, open * 0.3, 0, 0, 0 } }
				prev = open
			end
		end
		send(ent, shapes, "sa_lip_loudness")
	end

	local env = envelopeWav(clip.path)
	if env then
		fromEnvelope(env)
	else
		SPeditor.Notify(string.format(L("sa_lip_listening"), math.max(math.ceil(t1 - t0), 1)), 0)
		envelopeListen(clip.path, t0, t1, fromEnvelope)
	end
end
