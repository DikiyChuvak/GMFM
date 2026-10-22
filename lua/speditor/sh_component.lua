--[[
SPeditor — built-in components (a0.7; until a0.6 these were "mods").

A component is a part of the editor in its own folder lua/speditor/<id>/ with a file
component.lua that lists its files and network messages:

  return {
      name = "SAeditor",
      net = { "Seek" },                         -- the component's network messages
      shared = { "sh_x.lua" }, server = { "sv_x.lua" }, client = { "cl_x.lua" },
  }

Components are not loaded from other addons: SPeditor is extended by the community
with languages only (lua/speditor_lang/, sh_lang.lua).

Component files get their object like this:   local COMP = SPeditor.Component("id")

Object methods:
  shared   COMP:Lang(lang, tbl)   COMP:L(key, ...)   COMP:Hook(event, fn)   COMP:Print(...)
           COMP:NetStart(name)    COMP:NetReceive(name, fn, noActive)
  server   COMP:SceneData(save, load)       component data in the scene file
  client   COMP:AddPage{…}   COMP:AddMenu(where, fn)   COMP:AddHotkey{…}   COMP:AddStatus(fn)
]]
SPeditor = SPeditor or {}
SPeditor.Components = SPeditor.Components or {}
local Comps = SPeditor.Components

Comps.list    = Comps.list or {}     -- in load order
Comps.byId    = Comps.byId or {}
Comps.pages   = Comps.pages or {}    -- client: window pages
Comps.menus   = Comps.menus or {}    -- client: [where] = { { comp, fn }, … }
Comps.hotkeys = Comps.hotkeys or {}
Comps.status  = Comps.status or {}
Comps.scene   = Comps.scene or {}    -- server: [id] = { save, load }

local ROOT = "speditor/"

local COMP = Comps.Class or {}
COMP.__index = COMP
Comps.Class = COMP

local function warn(...)
	MsgC(Color(255, 200, 80), "[GM:FM] ", ...)
	MsgC("\n")
end

function SPeditor.Component(id)
	local c = Comps.byId[id]
	if not c then
		c = setmetatable({ id = id, name = id }, COMP)
		Comps.byId[id] = c
		Comps.list[#Comps.list + 1] = c
	end
	return c
end

---------------------------------------------------------------------
-- Shared methods
---------------------------------------------------------------------
function COMP:Print(...)
	MsgC(Color(120, 200, 255), "[" .. self.name .. "] ", ...)
	MsgC("\n")
end

-- Interface strings: added to the shared SPeditor dictionary
function COMP:Lang(lang, tbl)
	SPeditor.Lang[lang] = SPeditor.Lang[lang] or {}
	for k, v in pairs(tbl) do SPeditor.Lang[lang][k] = v end
end

function COMP:L(key, ...)
	local s = SPeditor.L(key)
	if select("#", ...) > 0 then
		local ok, res = pcall(string.format, s, ...)
		if ok then return res end
	end
	return s
end

-- hook.Add with a name unique to the component: loading the file again replaces the handler
function COMP:Hook(event, fn, name)
	SPeditor.Hook(event, "SPeditor." .. self.id .. (name and ("." .. name) or ""), fn)
end

function COMP:NetName(name) return "SPeditor_" .. self.id .. "_" .. name end

function COMP:NetStart(name) net.Start(self:NetName(name)) end

-- Receiving a message. On the server fn(ply) is called only for a player with access to
-- the editor who has the editor open (noActive = true drops the second condition),
-- and with the shared rate limit — the same as for the editor's own messages.
function COMP:NetReceive(name, fn, noActive)
	local full = self:NetName(name)
	if SERVER then
		SPeditor.Server.ReceiveName(full, fn, noActive)
	else
		net.Receive(full, function() fn() end)
	end
end

---------------------------------------------------------------------
-- Server
---------------------------------------------------------------------
if SERVER then
	-- Component data in the scene file.
	-- save(ply, ctx) -> a table (only numbers, strings, bools, nested tables) or nil
	-- load(ply, data, ctx)      data = nil if the scene has no data of the component
	-- ctx.ents[i] — the object with number i in the scene, ctx.indexOf[ent] — the object's number:
	-- a file refers to objects by number because a UID does not live between sessions.
	function COMP:SceneData(save, load)
		Comps.scene[self.id] = { save = save, load = load, comp = self }
	end

	function Comps.SaveScene(ply, ctx)
		local out
		for id, h in pairs(Comps.scene) do
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

	function Comps.LoadScene(ply, data, ctx)
		data = istable(data) and data or {}
		for id, h in pairs(Comps.scene) do
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
	--   o = { id, titleKey, icon, window = "bottom" | "left" | "float", w, h,
	--         build = function(panel, win) … end }
	-- "bottom" — a tab of the bottom window (where SFM has the timeline), "left" — next to
	-- the Animation Set Editor, "float" — a floating window of its own (opened from the
	-- Windows menu). build is called every time the editor opens and on a theme change.
	function COMP:AddPage(o)
		assert(istable(o) and isstring(o.id) and isfunction(o.build), "COMP:AddPage{ id, titleKey, build }")
		o.comp = self
		for i, p in ipairs(Comps.pages) do
			if p.id == o.id then
				Comps.pages[i] = o
				return o
			end
		end
		Comps.pages[#Comps.pages + 1] = o
		return o
	end

	-- Items in the editor menus. where:
	-- "file" | "edit" | "windows" | "view" | "help"   menus of the top bar: fn(menu)
	-- "create"   the "+" menu in the Animation Set Editor and "Edit → Create": fn(menu)
	-- "object"   the object menu (right click): fn(menu, ent)
	function COMP:AddMenu(where, fn, name)
		local list = Comps.menus[where] or {}
		Comps.menus[where] = list
		local key = self.id .. "." .. (name or "main")
		for _, it in ipairs(list) do
			if it.key == key then
				it.fn = fn
				return
			end
		end
		list[#list + 1] = { key = key, comp = self, fn = fn }
	end

	-- An editor hotkey (works while no text is being typed and the camera is not flying).
	--   o = { key = KEY_SPACE, ctrl = false, shift = false, fn = function() end,
	-- label = "Space", desc = "a dictionary key for the help window" }
	-- The player may give it another key in Interface settings → Keys (id "comp:" .. o.id).
	function COMP:AddHotkey(o)
		assert(istable(o) and isnumber(o.key) and isfunction(o.fn), "COMP:AddHotkey{ key, fn }")
		o.comp = self
		o.id = self.id .. "." .. o.key .. (o.ctrl and "c" or "") .. (o.shift and "s" or "")
		for i, h in ipairs(Comps.hotkeys) do
			if h.id == o.id then
				Comps.hotkeys[i] = o
				return
			end
		end
		Comps.hotkeys[#Comps.hotkeys + 1] = o
	end

	-- Text in the status bar: fn() -> string or nil
	function COMP:AddStatus(fn)
		Comps.status[self.id] = fn
	end

	function Comps.PageTitle(pg)
		if isstring(pg.titleKey) then return SPeditor.L(pg.titleKey) end
		return isstring(pg.title) and pg.title or pg.id
	end

	-- Called by the editor when a menu is built
	function Comps.RunMenu(where, menu, ...)
		local list = Comps.menus[where]
		if not list or #list == 0 then return end
		local first = true
		for _, it in ipairs(list) do
			if first and menu.AddSpacer and menu:ChildCount() > 0 then menu:AddSpacer() end
			first = false
			local ok, err = pcall(it.fn, menu, ...)
			if not ok then warn(it.comp.name, ": menu ", where, ": ", tostring(err)) end
		end
	end

	-- Component hotkeys: called from the shared handler (cl_speditor.lua)
	function Comps.RunHotkeys(blocked)
		local K = SPeditor.Client.Keys
		for _, h in ipairs(Comps.hotkeys) do
			if K.Fired("comp:" .. h.id) and not blocked then
				local ok, err = pcall(h.fn)
				if not ok then warn(h.comp.name, ": hotkey: ", tostring(err)) end
			end
		end
	end

	function Comps.StatusText()
		local parts = {}
		for _, fn in pairs(Comps.status) do
			local ok, text = pcall(fn)
			if ok and isstring(text) and text ~= "" then parts[#parts + 1] = text end
		end
		table.sort(parts)
		return table.concat(parts, "  |  ")
	end
end

---------------------------------------------------------------------
-- Loading (speditor_init.lua, after the editor core)
---------------------------------------------------------------------
local function fileList(def, key)
	local out = {}
	for _, f in ipairs(istable(def[key]) and def[key] or {}) do
		if isstring(f) and string.EndsWith(f, ".lua") then out[#out + 1] = f end
	end
	return out
end

function Comps.Load(id)
	local folder = ROOT .. id .. "/"
	local manifest = folder .. "component.lua"
	if not file.Exists(manifest, "LUA") then
		warn("missing file ", manifest)
		return
	end
	if SERVER then AddCSLuaFile(manifest) end
	local def = include(manifest)
	if not istable(def) then return end
	local comp = SPeditor.Component(id)
	comp.name = isstring(def.name) and def.name or id

	if SERVER then
		for _, name in ipairs(istable(def.net) and def.net or {}) do
			if isstring(name) then util.AddNetworkString(comp:NetName(name)) end
		end
	end

	local function run(list, doInclude, send)
		for _, f in ipairs(list) do
			local path = folder .. f
			if not file.Exists(path, "LUA") then
				warn(comp.name, ": missing file ", f)
			else
				if SERVER and send then AddCSLuaFile(path) end
				if doInclude then include(path) end
			end
		end
	end
	run(fileList(def, "shared"), true, true)
	run(fileList(def, "server"), SERVER, false)
	run(fileList(def, "client"), CLIENT, true)
end
