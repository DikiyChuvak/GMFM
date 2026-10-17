--[[
SPeditor — mods (a0.2).

A mod is a folder lua/speditor_mods/<id>/ with a file mod.lua that returns a description:

  return {
      name = "My mod", version = "1.0", author = "me",
      description = { en = "…", ru = "…" },     -- or a single string
      api = 1,                                  -- the API version it is written for (SPeditor.API)
      net = { "Hello" },                        -- the mod's network messages
      shared = { "sh_x.lua" }, server = { "sv_x.lua" }, client = { "cl_x.lua" },
  }

The folder may live inside SPeditor itself (built-in mods) or in any other addon:
the game merges the lua folders of all addons, so your own mod is a separate addon with
the same folder lua/speditor_mods/<id>/. Folders whose name starts with "_"
are not loaded (a way to put a mod aside without deleting it).

Mod files get the mod object like this:   local MOD = SPeditor.Mod("id")

Object methods (in detail and with examples — mods/README_ru.md, mods/README_en.md):
  shared   MOD:Lang(lang, tbl)   MOD:L(key, ...)   MOD:Hook(event, fn)   MOD:Print(...)
           MOD:NetStart(name)    MOD:NetReceive(name, fn, noActive)   MOD:DataDir()
  server   MOD:SceneData(save, load)        mod data in the scene file
  client   MOD:AddPage{…}   MOD:AddMenu(where, fn)   MOD:AddHotkey{…}   MOD:AddStatus(fn)

Mods that are switched off: the server variable speditor_mods_off (ids separated by
commas); a change takes effect after the map restarts.
]]
SPeditor = SPeditor or {}
SPeditor.Mods = SPeditor.Mods or {}
local Mods = SPeditor.Mods

Mods.list   = Mods.list or {}     -- in load order
Mods.byId   = Mods.byId or {}
Mods.pages  = Mods.pages or {}    -- client: window pages
Mods.menus  = Mods.menus or {}    -- client: [where] = { { mod, fn }, … }
Mods.hotkeys = Mods.hotkeys or {}
Mods.status = Mods.status or {}
Mods.scene  = Mods.scene or {}    -- server: [id] = { save, load }

local ROOT = "speditor_mods/"

local cvOff = CreateConVar("speditor_mods_off", "", { FCVAR_REPLICATED, FCVAR_ARCHIVE },
	"SPeditor mods that are switched off (ids separated by commas); applied on map load")

local MOD = Mods.Class or {}
MOD.__index = MOD
Mods.Class = MOD

function Mods.Get(id) return Mods.byId[id] end
SPeditor.Mod = Mods.Get

local function warn(...)
	MsgC(Color(255, 200, 80), "[SPeditor mods] ", ...)
	MsgC("\n")
end

function Mods.IsOff(id)
	return string.find("," .. string.gsub(cvOff:GetString(), "%s", "") .. ",", "," .. id .. ",", 1, true) ~= nil
end

-- Switch a mod on or off (on a server — only a superadmin or the console)
function Mods.SetOff(id, off)
	local set, out = {}, {}
	for part in string.gmatch(cvOff:GetString(), "[^,%s]+") do set[part] = true end
	set[id] = off and true or nil
	for k in pairs(set) do out[#out + 1] = k end
	table.sort(out)
	RunConsoleCommand("speditor_mods_off", table.concat(out, ","))
end

---------------------------------------------------------------------
-- Shared methods
---------------------------------------------------------------------
function MOD:Print(...)
	MsgC(Color(120, 200, 255), "[" .. self.id .. "] ", ...)
	MsgC("\n")
end

-- Interface strings: added to the shared SPeditor dictionary. To avoid clashing with the
-- editor and other mods, start keys with the mod id ("mymod_title").
function MOD:Lang(lang, tbl)
	SPeditor.Lang[lang] = SPeditor.Lang[lang] or {}
	for k, v in pairs(tbl) do SPeditor.Lang[lang][k] = v end
end

function MOD:L(key, ...)
	local s = SPeditor.L(key)
	if select("#", ...) > 0 then
		local ok, res = pcall(string.format, s, ...)
		if ok then return res end
	end
	return s
end

-- hook.Add with a name unique to the mod: loading the file again replaces the handler
function MOD:Hook(event, fn, name)
	hook.Add(event, "SPeditorMod." .. self.id .. (name and ("." .. name) or ""), fn)
end

function MOD:NetName(name) return "SPeditorMod_" .. self.id .. "_" .. name end

function MOD:NetStart(name) net.Start(self:NetName(name)) end

-- Receiving a message. On the server fn(ply) is called only for a player with access to
-- the editor who has the editor open (noActive = true drops the second condition),
-- and with the shared rate limit — the same as for SPeditor's own messages.
function MOD:NetReceive(name, fn, noActive)
	local full = self:NetName(name)
	if SERVER then
		SPeditor.Server.ReceiveName(full, fn, noActive)
	else
		net.Receive(full, function() fn() end)
	end
end

-- The mod's folder in garrysmod/data: speditor/mods/<id>
function MOD:DataDir()
	local dir = SPeditor.Config.SaveDir .. "/mods/" .. self.id
	local acc = ""
	for part in string.gmatch(dir, "[^/]+") do
		acc = (acc == "") and part or (acc .. "/" .. part)
		if not file.IsDir(acc, "DATA") then file.CreateDir(acc) end
	end
	return dir
end

---------------------------------------------------------------------
-- Server
---------------------------------------------------------------------
if SERVER then
	-- Mod data in the scene file.
	-- save(ply, ctx) -> a table (only numbers, strings, bools, nested tables) or nil
	-- load(ply, data, ctx)      data = nil if the scene has no data of the mod
	-- ctx.ents[i] — the object with number i in the scene, ctx.indexOf[ent] — the object's number:
	-- a file refers to objects by number because a UID does not live between sessions.
	function MOD:SceneData(save, load)
		Mods.scene[self.id] = { save = save, load = load, mod = self }
	end

	function Mods.SaveScene(ply, ctx)
		local out
		for id, h in pairs(Mods.scene) do
			if h.save then
				local ok, res = pcall(h.save, ply, ctx)
				if not ok then
					warn(id, ": scene save: ", tostring(res))
				elseif istable(res) then
					out = out or {}
					out[id] = res
				end
			end
		end
		return out
	end

	function Mods.LoadScene(ply, data, ctx)
		data = istable(data) and data or {}
		for id, h in pairs(Mods.scene) do
			if h.load then
				local ok, err = pcall(h.load, ply, istable(data[id]) and data[id] or nil, ctx)
				if not ok then warn(id, ": scene load: ", tostring(err)) end
			end
		end
	end
end

---------------------------------------------------------------------
-- Client
---------------------------------------------------------------------
if CLIENT then
	-- A page in an editor window.
	--   o = { id, title | titleKey, icon, window = "bottom" | "left" | "float", w, h,
	--         build = function(panel, win) … end }
	-- titleKey — a dictionary key: the title then follows the interface language
	-- (title — a ready string that stays as it was when the mod was loaded).
	-- "bottom" — a tab of the bottom window (where SFM has the timeline), "left" — next to
	-- the Animation Set Editor, "float" — a floating window of its own (opened from the
	-- Windows menu, where the page gets by itself). build is called every time the editor
	-- opens and on a theme change: the panel is created anew.
	function MOD:AddPage(o)
		assert(istable(o) and isstring(o.id) and isfunction(o.build), "MOD:AddPage{ id, title, build }")
		o.mod = self
		for i, p in ipairs(Mods.pages) do
			if p.id == o.id then
				Mods.pages[i] = o
				return o
			end
		end
		Mods.pages[#Mods.pages + 1] = o
		return o
	end

	-- Items in the editor menus. where:
	-- "file" | "edit" | "windows" | "view" | "help"   menus of the top bar: fn(menu)
	-- "create"   the "+" menu in the Animation Set Editor and "Edit → Create": fn(menu)
	-- "object"   the object menu (right click): fn(menu, ent)
	-- menu — a regular DMenu: menu:AddOption(text, function), menu:AddSubMenu(text).
	function MOD:AddMenu(where, fn, name)
		local list = Mods.menus[where] or {}
		Mods.menus[where] = list
		local key = self.id .. "." .. (name or "main")
		for _, it in ipairs(list) do
			if it.key == key then
				it.fn = fn
				return
			end
		end
		list[#list + 1] = { key = key, mod = self, fn = fn }
	end

	-- An editor hotkey (works while no text is being typed and the camera is not flying).
	--   o = { key = KEY_SPACE, ctrl = false, shift = false, fn = function() end,
	-- label = "Space", desc = "a dictionary key or text for the help window" }
	function MOD:AddHotkey(o)
		assert(istable(o) and isnumber(o.key) and isfunction(o.fn), "MOD:AddHotkey{ key, fn }")
		o.mod = self
		o.id = self.id .. "." .. o.key .. (o.ctrl and "c" or "") .. (o.shift and "s" or "")
		for i, h in ipairs(Mods.hotkeys) do
			if h.id == o.id then
				Mods.hotkeys[i] = o
				return
			end
		end
		Mods.hotkeys[#Mods.hotkeys + 1] = o
	end

	-- Text in the status bar: fn() -> string or nil
	function MOD:AddStatus(fn)
		Mods.status[self.id] = fn
	end

	function Mods.PageTitle(pg)
		if isstring(pg.titleKey) then return SPeditor.L(pg.titleKey) end
		return isstring(pg.title) and pg.title or pg.id
	end

	-- Called by the editor when a menu is built
	function Mods.RunMenu(where, menu, ...)
		local list = Mods.menus[where]
		if not list or #list == 0 then return end
		local first = true
		for _, it in ipairs(list) do
			if first and menu.AddSpacer and menu:ChildCount() > 0 then menu:AddSpacer() end
			first = false
			local ok, err = pcall(it.fn, menu, ...)
			if not ok then warn(it.mod.id, ": menu ", where, ": ", tostring(err)) end
		end
	end

	-- Mod hotkeys: called from the shared handler (cl_speditor.lua)
	-- (the player may give them other keys in Interface settings → Keys: id "mod:" .. h.id)
	function Mods.RunHotkeys(blocked)
		local K = SPeditor.Client.Keys
		for _, h in ipairs(Mods.hotkeys) do
			if K.Fired("mod:" .. h.id) and not blocked then
				local ok, err = pcall(h.fn)
				if not ok then warn(h.mod.id, ": hotkey: ", tostring(err)) end
			end
		end
	end

	function Mods.StatusText()
		local parts = {}
		for id, fn in pairs(Mods.status) do
			local ok, text = pcall(fn)
			if ok and isstring(text) and text ~= "" then parts[#parts + 1] = text end
		end
		table.sort(parts)
		return table.concat(parts, "  |  ")
	end
end

---------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------
local function describe(def, dir)
	local mod = Mods.byId[dir] or setmetatable({}, MOD)
	mod.id          = dir
	mod.folder      = ROOT .. dir .. "/"
	mod.name        = isstring(def.name) and def.name or dir
	mod.version     = tostring(def.version or "")
	mod.author      = isstring(def.author) and def.author or ""
	mod.description = def.description
	mod.url         = isstring(def.url) and def.url or nil
	mod.api         = tonumber(def.api) or 1
	mod.def         = def
	mod.errors      = {}
	return mod
end

-- Mod description in the interface language
function Mods.Description(mod)
	local d = mod.description
	if istable(d) then
		local lang = CLIENT and GetConVarString("speditor_language") or "en"
		return d[lang] or d.en or select(2, next(d)) or ""
	end
	return isstring(d) and d or ""
end

local function fileList(def, key)
	local out = {}
	if istable(def[key]) then
		for _, f in ipairs(def[key]) do
			-- only file names inside the mod folder
			if isstring(f) and not string.find(f, "..", 1, true) and string.EndsWith(f, ".lua") then out[#out + 1] = f end
		end
	end
	return out
end

local function loadMod(dir)
	local manifest = ROOT .. dir .. "/mod.lua"
	if not file.Exists(manifest, "LUA") then return end
	if SERVER then AddCSLuaFile(manifest) end
	local def = include(manifest)
	if not istable(def) then
		warn(dir, ": mod.lua must return a table")
		return
	end

	local mod = describe(def, dir)
	if not Mods.byId[dir] then
		Mods.byId[dir] = mod
		Mods.list[#Mods.list + 1] = mod
	end

	local shared, server, client = fileList(def, "shared"), fileList(def, "server"), fileList(def, "client")

	mod.state = "loaded"
	if mod.api > (SPeditor.API or 1) then
		mod.state = "outdated"       -- the mod is written for a newer version of SPeditor
		warn(dir, ": needs SPeditor mod API ", tostring(mod.api), ", this version has ", tostring(SPeditor.API))
		return
	end
	if Mods.IsOff(dir) then
		mod.state = "off"
		return
	end
	-- a client on someone else's server: the server sent no files — so the mod is off there
	if CLIENT then
		local probe = client[1] or shared[1]
		if probe and not file.Exists(mod.folder .. probe, "LUA") then
			mod.state = "off"
			return
		end
	end

	if SERVER and istable(def.net) then
		for _, name in ipairs(def.net) do
			if isstring(name) then util.AddNetworkString(mod:NetName(name)) end
		end
	end

	Mods.loading = mod
	local function run(list, doInclude, send)
		for _, f in ipairs(list) do
			local path = mod.folder .. f
			if not file.Exists(path, "LUA") then
				mod.errors[#mod.errors + 1] = "missing file " .. f
				warn(dir, ": missing file ", f)
			else
				if SERVER and send then AddCSLuaFile(path) end
				if doInclude then include(path) end
			end
		end
	end
	run(shared, true, true)
	run(server, SERVER, false)
	run(client, CLIENT, true)
	Mods.loading = nil
	if #mod.errors > 0 then mod.state = "error" end
end

-- Lua errors during mod loading are remembered: the Mods window shows them
hook.Add("OnLuaError", "SPeditor.Mods", function(err)
	local mod = Mods.loading
	if mod then
		mod.errors[#mod.errors + 1] = tostring(err)
		mod.state = "error"
	end
end)

function Mods.LoadAll()
	local _, dirs = file.Find(ROOT .. "*", "LUA")
	dirs = dirs or {}
	table.sort(dirs)
	for _, dir in ipairs(dirs) do
		if string.sub(dir, 1, 1) ~= "_" and not string.find(dir, "[^%w_]") then
			loadMod(dir)
		end
	end
	hook.Run("SPeditor_ModsLoaded", Mods.list)
end
