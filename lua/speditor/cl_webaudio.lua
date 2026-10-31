--[[
The sound of the editor through the Web Audio API (b0.2.6). A hidden browser panel opens
data_static/speditor/webaudio.xml; the timeline's clips play there instead of in BASS channels:
starts land on the sample, volume, pan and speed glide without clicks, and the browser decodes
MP3 and OGG — so those go into the sound track of a video too (before, only uncompressed WAV did),
and lip sync measures them at once instead of listening to them in real time.
If the page cannot be opened (no browser in this build of the game), the editor keeps BASS.

  W.Ready()                       — the page is up
  W.Load(path, done(len | nil))   — the file is read and decoded; its length in seconds
  W.Update(list)                  — the clips that sound now (see webaudio.xml update())
  W.Play(path, vol) / W.StopPreview()
  W.Decode(path, done(wav | nil)) — the samples, as A.LoadWav gives them (16-bit)
  W.Envelope(path, step, done(levels | nil))
]]
SPeditor.WebAudio = SPeditor.WebAudio or {}
local W = SPeditor.WebAudio

local PAGE = "data_static/speditor/webaudio.xml"
local cvOn = CreateClientConVar("gmfm_webaudio", "1", true, false,
	"GM:FM: play and decode sounds through the Web Audio API (0 — the game's BASS channels)", 0, 1)

-- kept in the module table: a reloaded file keeps the requests the page has still to answer
W.waits = W.waits or { load = {}, pcm = {}, env = {}, len = {} }
local loadWait, pcmWait, envWait, lengths = W.waits.load, W.waits.pcm, W.waits.env, W.waits.len
W.nextReq = W.nextReq or 0

function W.Ready() return W.ready == true and IsValid(W.panel) and cvOn:GetBool() end

local function js(code)
	if IsValid(W.panel) then W.panel:QueueJavascript(code) end
end
local function quote(s) return "\"" .. string.JavascriptSafe(s) .. "\"" end

local function onReady(panel)
	panel:AddFunction("gmfm", "loaded", function(path, len)
		len = tonumber(len)
		lengths[path] = (len and len >= 0) and len or false
		local list = loadWait[path]
		loadWait[path] = nil
		for _, cb in ipairs(list or {}) do cb(lengths[path] or nil) end
	end)
	panel:AddFunction("gmfm", "pcm", function(req, piece, total, rate, ch, frames, data)
		local w = pcmWait[req]
		if not w then return end
		piece = tonumber(piece) or -1
		if piece < 0 then
			pcmWait[req] = nil
			w.done(nil)
			return
		end
		w.parts[piece + 1] = util.Base64Decode(data or "") or ""
		w.got = w.got + 1
		if w.got < (tonumber(total) or 1) then return end
		pcmWait[req] = nil
		local raw = table.concat(w.parts)
		ch = tonumber(ch) or 1
		w.done({ data = raw, at = 1, n = math.floor(#raw / (2 * ch)), ch = ch, rate = tonumber(rate) or 44100, wide = 2 })
	end)
	panel:AddFunction("gmfm", "envelope", function(req, text)
		local cb = envWait[req]
		envWait[req] = nil
		if not cb then return end
		if not isstring(text) or text == "" then cb(nil) return end
		local out, i = {}, 0
		for v in string.gmatch(text, "[^,]+") do
			out[i] = tonumber(v) or 0
			i = i + 1
		end
		cb(out)
	end)
	W.ready = true
	W.SetVolume()
	hook.Run("SPeditor_WebAudioReady")
end

function W.Open()
	if IsValid(W.panel) or not cvOn:GetBool() then return end
	if not file.Exists(PAGE, "GAME") then return end
	W.ready = false
	local p = vgui.Create("DHTML")
	W.panel = p
	-- out of sight and out of the way of the mouse; the page runs all the same
	p:SetSize(8, 8)
	p:SetPos(-64, -64)
	p:SetMouseInputEnabled(false)
	p:SetKeyboardInputEnabled(false)
	p:SetPaintedManually(true)
	p.OnDocumentReady = function(s)
		if W.ready then return end
		onReady(s)
	end
	p:OpenURL("asset://garrysmod/" .. PAGE)
end

function W.Close()
	if IsValid(W.panel) then W.panel:Remove() end
	W.panel, W.ready = nil, false
	-- whoever waits gets nothing
	for _, list in pairs(loadWait) do for _, cb in ipairs(list) do cb(nil) end end
	for _, w in pairs(pcmWait) do w.done(nil) end
	for _, cb in pairs(envWait) do cb(nil) end
	for _, t in pairs(W.waits) do table.Empty(t) end
end

cvars.AddChangeCallback("gmfm_webaudio", function(_, _, new)
	if tonumber(new) == 1 then W.Open() else W.Close() end
	hook.Run("SPeditor_WebAudioReady")
end, "SPeditor.WebAudio")

function W.Load(path, done)
	if not W.Ready() then done(nil) return end
	if lengths[path] ~= nil then done(lengths[path] or nil) return end
	if loadWait[path] then table.insert(loadWait[path], done) return end
	loadWait[path] = { done }
	js("load(" .. quote(path) .. ")")
end

-- the game's volume (and its silence while the window is not in front, as the game's own sound)
local lastVol
function W.SetVolume()
	local v = GetConVar("volume") and GetConVar("volume"):GetFloat() or 1
	local mute = GetConVar("snd_mute_losefocus")
	if mute and mute:GetBool() and not system.HasFocus() then v = 0 end
	if v ~= lastVol then
		lastVol = v
		js("setMaster(" .. string.format("%.3f", v) .. ")")
	end
end

local lastSent
function W.Update(list)
	if not W.Ready() then return end
	local json = util.TableToJSON(list) or "[]"
	-- nothing sounding and nothing was: no message
	if json == "[]" and lastSent == "[]" then return end
	lastSent = json
	js("update(" .. json .. ")")
end

function W.Play(path, vol)
	if not W.Ready() then return false end
	js("play(" .. quote(path) .. "," .. string.format("%.3f", vol or 1) .. ")")
	return true
end

function W.StopPreview() js("stopPreview()") end

function W.Decode(path, done)
	if not W.Ready() then done(nil) return end
	W.nextReq = W.nextReq + 1
	local req = tostring(W.nextReq)
	pcmWait[req] = { done = done, parts = {}, got = 0 }
	js("pcm(" .. quote(path) .. "," .. quote(req) .. ")")
end

function W.Envelope(path, step, done)
	if not W.Ready() then done(nil) return end
	W.nextReq = W.nextReq + 1
	local req = tostring(W.nextReq)
	envWait[req] = done
	js("envelope(" .. quote(path) .. "," .. step .. "," .. quote(req) .. ")")
end

-- a file changed on disk (the user's own sounds): read it again next time
function W.Forget(path)
	lengths[path] = nil
	js("forget(" .. quote(path) .. ")")
end

local nextVol = 0
SPeditor.Hook("Think", "SPeditor.WebAudio", function()
	if not W.ready or RealTime() < nextVol then return end
	nextVol = RealTime() + 0.25
	W.SetVolume()
end)

-- opened a moment after the game has started (the HUD and the browser are up by then); a
-- reloaded file binds the page's calls to its own functions again
if W.ready and IsValid(W.panel) then onReady(W.panel) else timer.Simple(1, function() W.Open() end) end
