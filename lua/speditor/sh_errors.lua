--[[
SPeditor — errors (a0.8): hooks that cannot break each other, and a log for bug reports.

  SPeditor.Hook(event, id, fn)   hook.Add with a guard. An error in any hook of an event stops
                                 the rest of that event's hooks for the frame (PAC3 next to
                                 GShader Library once stopped the editor's Think hooks that way),
                                 so every hook of the editor runs inside xpcall: an error is logged
                                 and the other hooks — the editor's and other addons' — go on.
  SPeditor.LogError(msg, stack, realm)
                                 one error in the log: the same message is counted, not repeated.
  SPeditor.Errors.list           { { msg, realm, count, first, last, stack = "…" }, … }

Errors of the editor's files that happen outside its hooks (net messages, timers, panels) come
through OnLuaError. The server sends its errors to the players who may use the editor, so the
report of the host has both realms. The report window is cl_ui_report.lua.
]]
SPeditor = SPeditor or {}
SPeditor.Errors = SPeditor.Errors or { list = {}, byMsg = {} }
local E = SPeditor.Errors

E.MAX = 40                 -- different errors kept
local NET = "SPeditor_Error"

local function shortStack(tb)
	-- the lines of a traceback that point into files, without the guard itself
	local out = {}
	for line in string.gmatch(tb or "", "[^\n]+") do
		line = string.Trim(line)
		if string.find(line, "%.lua:%d+") and not string.find(line, "sh_errors.lua", 1, true) then
			out[#out + 1] = line
			if #out >= 6 then break end
		end
	end
	return table.concat(out, "\n")
end

function SPeditor.LogError(msg, stack, realm)
	msg = tostring(msg or "?")
	realm = realm or (SERVER and "server" or "client")
	local key = realm .. "|" .. msg
	local e = E.byMsg[key]
	local now = os.time()
	if e then
		e.count = e.count + 1
		e.last = now
		return e, false
	end
	if #E.list >= E.MAX then return nil, false end
	e = { msg = msg, realm = realm, count = 1, first = now, last = now, stack = stack or "" }
	E.byMsg[key] = e
	E.list[#E.list + 1] = e
	MsgC(Color(255, 120, 90), "[GM:FM] error (" .. realm .. "): ", msg, "\n", Color(200, 200, 200), e.stack ~= "" and (e.stack .. "\n") or "")
	if SERVER then
		-- to the players who may use the editor (the host in single player)
		local to = {}
		for _, ply in ipairs(player.GetHumans()) do
			if game.SinglePlayer() or ply:IsListenServerHost() or ply:IsSuperAdmin() then to[#to + 1] = ply end
		end
		if #to > 0 then
			net.Start(NET)
			net.WriteString(string.sub(msg, 1, 1000))
			net.WriteString(string.sub(e.stack, 1, 2000))
			net.Send(to)
		end
	elseif not E.running then
		-- an error inside a handler of this very event must not come back here
		E.running = true
		hook.Run("SPeditor_ErrorLogged", e)
		E.running = false
	end
	return e, true
end

function E.Clear()
	E.list, E.byMsg = {}, {}
end

local function onError(err)
	return { msg = tostring(err), stack = shortStack(debug.traceback("", 2)) }
end

-- hook.Add with a guard (see the top of the file). No tables per call: these run every frame.
function SPeditor.Hook(event, id, fn)
	if not isfunction(fn) then return hook.Add(event, id, fn) end
	local where = event .. " · " .. tostring(id)
	local function finish(ok, ...)
		if ok then return ... end
		local r = ...
		SPeditor.LogError(istable(r) and r.msg or tostring(r), ((istable(r) and r.stack) or "") .. "\n(hook " .. where .. ")")
	end
	hook.Add(event, id, function(...) return finish(xpcall(fn, onError, ...)) end)
end

-- Takes every hook of the events that is not the editor's off for a while (b0.2.1): a hook
-- that returns a value stops the rest of the event, and a map's own fog hook (gm_scrapland)
-- ran before the editor's depth fog — the SSAO depth came out empty and the frame black.
-- Returns the function that puts them back.
function SPeditor.MuteOtherHooks(events)
	local off = {}
	for _, event in ipairs(events) do
		for id, fn in pairs(hook.GetTable()[event] or {}) do
			local name = tostring(id)
			if not (isstring(id) and (string.StartWith(name, "SPeditor") or string.StartWith(name, "GMFM"))) then
				off[#off + 1] = { event, id, fn }
			end
		end
	end
	for _, h in ipairs(off) do hook.Remove(h[1], h[2]) end
	return function()
		for _, h in ipairs(off) do
			if not (hook.GetTable()[h[1]] or {})[h[2]] then hook.Add(h[1], h[2], h[3]) end
		end
	end
end

-- errors of the editor's files outside its hooks
local function ours(stack, err)
	if string.find(tostring(err or ""), "speditor", 1, true) then return true end
	for _, fr in ipairs(istable(stack) and stack or {}) do
		if string.find(string.lower(tostring(fr.File or "")), "speditor", 1, true) then return true end
	end
	return false
end

hook.Add("OnLuaError", "SPeditor.Errors", function(err, realm, stack)
	if not ours(stack, err) then return end
	local lines = {}
	for _, fr in ipairs(istable(stack) and stack or {}) do
		if #lines >= 6 then break end
		-- the C function that raised it (error, assert) says nothing
		if fr.File ~= "[C]" then lines[#lines + 1] = string.format("%s:%s %s", tostring(fr.File), tostring(fr.Line), tostring(fr.Function or "")) end
	end
	-- on a listen server the host sees the server's errors here too; the server sends them anyway
	local r = (realm == "server" or realm == "sv") and "server" or (SERVER and "server" or "client")
	if CLIENT and r == "server" then return end
	SPeditor.LogError(err, table.concat(lines, "\n"), r)
end)

if SERVER then
	util.AddNetworkString(NET)
else
	net.Receive(NET, function()
		SPeditor.LogError(net.ReadString(), net.ReadString(), "server")
	end)
end
