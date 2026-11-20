--[[
SPeditor — a profiler of the editor's own work (b0.2.6-misc.1), for a scene that plays or scrubs
choppily. Off by default; while off it costs one boolean test per hook call.

  gmfm_prof 1 [seconds]   on, on the client and on the server (single player, the host of a listen
                          server or a superadmin); a report every 2 seconds (or the given number)
  gmfm_prof 0             off
  gmfm_prof_sv 1 / 0      the server alone (its console, a dedicated server)

A report goes to the console and is appended to data/speditor/prof_client.txt and prof_server.txt.
For each section of the window: milliseconds per frame (client) or per tick (server) on average,
the worst single frame, and how many times a frame it ran. Below: counters (bone / body / flex
sets of the server: how much is sent to the clients each tick), sizes (rows, keys, tracks) and the
net messages (per second, bytes).

What is measured: every hook of the editor (SPeditor.Hook, so every COMP:Hook too), every net
message received (time in its receiver, bytes) and sent (bytes), and the named sections
of the code (P.Add / P.Wrap: the server's playback and the timeline).

  P.on                         is it on
  P.Add(name, seconds)         time spent in a section
  P.Wrap(name, fn) -> fn       fn timed as the section name
  P.Count(name, n)             a counter (per frame / tick)
  P.Gauge(name, value)         a size (the last and the largest value of the window)
  P.Context[key] = fn          a line for the report's head (fn returns a string)
]]
SPeditor = SPeditor or {}
SPeditor.Prof = SPeditor.Prof or {}
local P = SPeditor.Prof
P.on = P.on or false
P.Context = P.Context or {}

local REALM = CLIENT and "client" or "server"
local UNIT = CLIENT and "frame" or "tick"
local FILE = "speditor/prof_" .. REALM .. ".txt"

local stats, counts, gauges, nets = {}, {}, {}, {}
local window = { frames = 0, t0 = SysTime(), ft = 0, ftMax = 0, last = nil }

local function frameNo() return CLIENT and FrameNumber() or engine.TickCount() end

local function bump(s, v)
	local f = frameNo()
	if s.frame ~= f then
		if s.cur > s.max then s.max = s.cur end
		s.cur, s.frame = 0, f
	end
	s.sum, s.n, s.cur = s.sum + v, s.n + 1, s.cur + v
end

function P.Add(name, dt)
	local s = stats[name]
	if not s then s = { sum = 0, n = 0, cur = 0, max = 0 } stats[name] = s end
	bump(s, dt)
end

function P.Count(name, n)
	local s = counts[name]
	if not s then s = { sum = 0, n = 0, cur = 0, max = 0 } counts[name] = s end
	bump(s, n or 1)
end

function P.Gauge(name, v)
	local s = gauges[name]
	if not s then s = { v = v, max = v } gauges[name] = s end
	s.v = v
	if v > s.max then s.max = v end
end

local function after(name, t, ...)
	P.Add(name, SysTime() - t)
	return ...
end
function P.Wrap(name, fn)
	return function(...)
		if not P.on then return fn(...) end
		local t = SysTime()
		return after(name, t, fn(...))
	end
end

---------------------------------------------------------------------
-- Net messages and the server's setters, wrapped only while it is on
---------------------------------------------------------------------
-- Lives on SPeditor.Prof: an autorefresh of this file must not leave the old wrappers in place
-- with a fresh (empty) `orig`, or turning the profiler off could never uninstall them.
local orig = P.orig or {}
P.orig = orig
local outName

local function netStat(key, bytes)
	local s = nets[key]
	if not s then s = { n = 0, bytes = 0 } nets[key] = s end
	s.n, s.bytes = s.n + 1, s.bytes + (bytes or 0)
end

local SENDS = SERVER and { "Send", "Broadcast", "SendOmit", "SendPAS", "SendPVS" } or { "SendToServer" }

local function install()
	if orig.installed then return end
	orig.installed = true
	orig.mine = {}
	orig.Start = net.Start
	net.Start = function(name, ...)
		outName = name
		return orig.Start(name, ...)
	end
	orig.mine.Start = net.Start
	for _, k in ipairs(SENDS) do
		local f = net[k]
		if f then
			orig[k] = f
			net[k] = function(...)
				netStat("out " .. tostring(outName), net.BytesWritten and net.BytesWritten() or 0)
				return f(...)
			end
			orig.mine[k] = net[k]
		end
	end
	-- as GMod's own net.Incoming (lua/includes/extensions/net.lua), with the receiver timed
	orig.Incoming = net.Incoming
	net.Incoming = function(len, client)
		local name = util.NetworkIDToString(net.ReadHeader())
		if not name then return end
		netStat("in " .. name, len / 8)
		local func = net.Receivers[string.lower(name)]
		if not func then return end
		local t = SysTime()
		func(len - 16, client)
		P.Add("net in " .. name, SysTime() - t)
	end
	orig.mine.Incoming = net.Incoming
	if SERVER then
		-- what the server sets each tick is what it sends to the clients (bone offsets, bodies, flexes):
		-- counted, and the bone offsets that really changed
		local E, PO = FindMetaTable("Entity"), FindMetaTable("PhysObj")
		orig.meta = {}
		local function wrap(meta, k, label, getter)
			local f = meta[k]
			if not f then return end
			local get = getter and meta[getter]
			local mine
			mine = function(self, a, b, ...)
				if P.on then
					P.Count(label, 1)
					if get and IsValid(self) then
						local cur = get(self, a)
						if cur ~= b then P.Count(label .. " (changed)", 1) end
					end
				end
				return f(self, a, b, ...)
			end
			meta[k] = mine
			orig.meta[#orig.meta + 1] = { meta, k, f, mine }
		end
		wrap(E, "ManipulateBonePosition", "sv set bone offset: position", "GetManipulateBonePosition")
		wrap(E, "ManipulateBoneAngles", "sv set bone offset: angles", "GetManipulateBoneAngles")
		wrap(E, "ManipulateBoneScale", "sv set bone offset: scale", "GetManipulateBoneScale")
		wrap(E, "SetFlexWeight", "sv set flex weight")
		wrap(PO, "SetPos", "sv set physics body place")
	end
end

local function uninstall()
	if not orig.installed then return end
	-- put back only what is still ours (an addon that wrapped it after us keeps its wrapper)
	for k, fn in pairs(orig.mine) do
		if net[k] == fn then net[k] = orig[k] end
	end
	for _, m in ipairs(orig.meta or {}) do
		if m[1][m[2]] == m[4] then m[1][m[2]] = m[3] end
	end
	-- clear in place: P.orig must stay the same table across autorefreshes
	for k in pairs(orig) do orig[k] = nil end
end

---------------------------------------------------------------------
-- The report
---------------------------------------------------------------------
local function reset()
	stats, counts, gauges, nets = {}, {}, {}, {}
	window = { frames = 0, t0 = SysTime(), ft = 0, ftMax = 0, last = nil }
end

local function sorted(t, key)
	local list = {}
	for name, s in pairs(t) do list[#list + 1] = { name = name, s = s } end
	table.sort(list, function(a, b) return key(a.s) > key(b.s) end)
	return list
end

function P.Report()
	local secs = math.max(SysTime() - window.t0, 1e-3)
	local fr = math.max(window.frames, 1)
	local out = {}
	local function line(s) out[#out + 1] = s end
	line(string.format("[GM:FM prof %s] %s  %.1f s, %d %ss, %s %.2f ms avg / %.2f ms worst",
		REALM, os.date("%H:%M:%S"), secs, window.frames, UNIT,
		CLIENT and "frame time" or "tick interval", window.ft / fr * 1000, window.ftMax * 1000))
	for key, fn in SortedPairs(P.Context) do
		local ok, s = pcall(fn)
		if ok and s then line("  " .. key .. ": " .. tostring(s)) end
	end
	line(string.format("  %9s %9s %8s  section", "ms/" .. UNIT, "worst", "calls"))
	for i, e in ipairs(sorted(stats, function(s) return s.sum end)) do
		if i > 30 then break end
		local s = e.s
		line(string.format("  %9.3f %9.3f %8.1f  %s", s.sum / fr * 1000, math.max(s.max, s.cur) * 1000, s.n / fr, e.name))
	end
	if next(counts) then
		line(string.format("  %9s %9s  counter (per %s)", "avg", "worst", UNIT))
		for _, e in ipairs(sorted(counts, function(s) return s.sum end)) do
			line(string.format("  %9.1f %9d  %s", e.s.sum / fr, math.max(e.s.max, e.s.cur), e.name))
		end
	end
	if next(gauges) then
		line(string.format("  %9s %9s  size", "now", "largest"))
		for _, e in ipairs(sorted(gauges, function(s) return s.max end)) do
			line(string.format("  %9d %9d  %s", e.s.v, e.s.max, e.name))
		end
	end
	if next(nets) then
		line(string.format("  %9s %9s  net message", "per s", "KB/s"))
		for _, e in ipairs(sorted(nets, function(s) return s.bytes end)) do
			line(string.format("  %9.1f %9.2f  %s", e.s.n / secs, e.s.bytes / secs / 1024, e.name))
		end
	end
	local text = table.concat(out, "\n") .. "\n"
	MsgC(Color(120, 200, 255), text)
	file.CreateDir("speditor")
	file.Append(FILE, text .. "\n")
	reset()
end

-- the frame (client) or the tick interval (server), as the game runs
hook.Add("Think", "SPeditor.Prof", function()
	if not P.on then return end
	window.frames = window.frames + 1
	local dt
	if CLIENT then
		dt = RealFrameTime()
	else
		local now = SysTime()
		dt = window.last and (now - window.last) or 0
		window.last = now
	end
	window.ft = window.ft + dt
	if dt > window.ftMax then window.ftMax = dt end
end)

function P.Set(on, interval)
	on = on and true or false
	interval = math.Clamp(tonumber(interval) or 2, 0.5, 60)
	timer.Remove("SPeditor.Prof")
	if on then
		install()
		reset()
		P.on = true
		file.CreateDir("speditor")
		file.Append(FILE, string.format("==== GM:FM profiler on, %s, %s, map %s, every %.1f s ====\n",
			os.date("%Y-%m-%d %H:%M:%S"), REALM, game.GetMap(), interval))
		timer.Create("SPeditor.Prof", interval, 0, P.Report)
		MsgC(Color(120, 200, 255), "[GM:FM prof " .. REALM .. "] on: a report every " .. interval .. " s, also in data/" .. FILE .. "\n")
	else
		if P.on and window.frames > 0 then P.Report() end
		P.on = false
		uninstall()
		MsgC(Color(120, 200, 255), "[GM:FM prof " .. REALM .. "] off\n")
	end
end

if CLIENT then
	concommand.Add("gmfm_prof", function(_, _, args)
		local v = tonumber(args[1])
		-- no argument toggles; `nil ~= 0` in Lua is true, so the second branch needs the parentheses
		local on = (v == nil and not P.on) or (v ~= 0)
		P.Set(on, args[2])
		-- the server's side (not defined on the client: the command goes to the server)
		RunConsoleCommand("gmfm_prof_sv", on and "1" or "0", args[2] or "2")
	end, nil, "GM:FM profiler: gmfm_prof 1 [seconds] / 0 (client and server)")
else
	concommand.Add("gmfm_prof_sv", function(ply, _, args)
		if IsValid(ply) and not (game.SinglePlayer() or ply:IsListenServerHost() or ply:IsSuperAdmin()) then return end
		P.Set((tonumber(args[1]) or 0) ~= 0, args[2])
	end, nil, "GM:FM profiler, server side: gmfm_prof_sv 1 [seconds] / 0")
end
