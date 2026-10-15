--[[
SPeditor — notification sounds and styles of one's own (the core is cl_ui_notify.lua).

Sound sets — every folder becomes a set; inside it the files info, success, error, save
(.wav / .mp3 / .ogg; a missing one is silent):
  * sound/speditor/notify/<id>/     in any addon — this one (Half-Life, Windows XP, and
                                    Aero7UI: Windows 7 sounds that do not come from the
                                    Workshop — the example of a pack of one's own), a
                                    local folder addon or a Workshop addon;
  * garrysmod/data/speditor/sounds/<id>/   files put there by hand or imported;
  * imported from an installed addon (Workshop UI sound packs replace the game's
    sounds, e.g. garrysmod/ui_click.wav): the window "Sounds from addons" lists the
    mounted addons that have sounds, plays them, and either puts one sound on a kind
    of the "Custom" set or makes a whole set (the files are copied to data/speditor/sounds).
    The engine reads an addon's file only through the shared game path, so when two
    mounted addons replace the same sound, the copy is the one the game itself uses;
  * "Custom": a sound chosen for every kind (speditor_notify_snd_0 … _3).

Styles:
  * JSON, made in the style editor (Interface settings → Notifications → Style editor):
    data/speditor/notify_styles/<name>.json; a Workshop addon can ship them as
    data_static/speditor/notify_styles/<name>.json;
  * Lua: any addon may put files into lua/speditor_notify/*.lua; they are run on the
    client after the editor and call SPeditor.UI.AddNotifyStyle(id, def) and/or
    SPeditor.UI.AddNotifySoundSet(id, { name = "…", [0] = "path", [1] = …, [2] = …, [3] = … }).

API:
  UI.ScanNotifySounds()          rebuild the list of sound sets from the folders
  UI.LoadNotifyStyles()          rebuild the list of JSON styles
  UI.NotifyStyleFromTable(t)     a style definition from a JSON table
  UI.SaveNotifyStyle(t)          save a JSON style (returns its id)   UI.DeleteNotifyStyle(id)
  UI.OpenSoundAddons()           the "Sounds from addons" window
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI  = SPeditor.UI
local L   = SPeditor.L
local COL = UI.PAL

local PACK_ROOT  = "sound/speditor/notify/"
local DATA_ROOT  = "speditor/sounds/"
local STYLE_DIR  = "speditor/notify_styles/"
local STATIC_DIR = "data_static/speditor/notify_styles/"
local KIND_FILE  = { [0] = "info", [1] = "error", [2] = "success", [3] = "save" }
local EXTS       = { ".wav", ".mp3", ".ogg" }
local BUILTIN    = { speditor = true, gmod = true, soft = true, custom = true }

-- names of the packs that come with the addon (with the Workshop pages of their sounds — About)
local PACK_NAMES = { halflife = "Half-Life", winxp = "Windows XP", aero7ui = "Aero7UI (Windows 7)" }

local function slug(s)
	s = string.Trim(string.gsub(string.lower(s or ""), "[^%w]+", "_"), "_")
	return s ~= "" and s or "set"
end

local function findKindFile(dir, base, where)
	for _, ext in ipairs(EXTS) do
		if file.Exists(dir .. base .. ext, where) then return base .. ext end
	end
end

---------------------------------------------------------------------
-- Sound sets from folders
---------------------------------------------------------------------
function UI.ScanNotifySounds()
	for _, id in ipairs(table.Copy(UI.NotifySoundSets)) do
		local def = UI.NotifySoundSetDefs[id]
		if def and def.scanned then UI.RemoveNotifySoundSet(id) end
	end
	table.RemoveByValue(UI.NotifySoundSets, "custom")

	-- packs inside addons: played by their game path
	local _, packs = file.Find(PACK_ROOT .. "*", "GAME")
	table.sort(packs or {})
	for _, folder in ipairs(packs or {}) do
		local def = { scanned = true, name = PACK_NAMES[string.lower(folder)] or folder }
		local any = false
		for k, base in pairs(KIND_FILE) do
			local f = findKindFile(PACK_ROOT .. folder .. "/", base, "GAME")
			if f then
				def[k] = "speditor/notify/" .. folder .. "/" .. f
				any = true
			end
		end
		local id = slug(folder)
		if BUILTIN[id] then id = "pack_" .. id end
		if any then UI.AddNotifySoundSet(id, def) end
	end

	-- sets in garrysmod/data: played from the file (folders starting with "_" are service ones)
	local _, sets = file.Find(DATA_ROOT .. "*", "DATA")
	table.sort(sets or {})
	for _, folder in ipairs(sets or {}) do
		if string.sub(folder, 1, 1) ~= "_" then
			local def = { scanned = true, name = folder }
			local any = false
			for k, base in pairs(KIND_FILE) do
				local f = findKindFile(DATA_ROOT .. folder .. "/", base, "DATA")
				if f then
					def[k] = "data/" .. DATA_ROOT .. folder .. "/" .. f
					any = true
				end
			end
			if any then UI.AddNotifySoundSet("data_" .. slug(folder), def) end
		end
	end
	UI.NotifySoundSets[#UI.NotifySoundSets + 1] = "custom"
	return #UI.NotifySoundSets
end

---------------------------------------------------------------------
-- Sounds of installed addons
---------------------------------------------------------------------
-- mounted addons that have a sound/ folder: { { title, wsid } }
function UI.SoundAddons()
	local out = {}
	for _, a in ipairs(engine.GetAddons() or {}) do
		if a.mounted and a.title then
			local files, dirs = file.Find("sound/*", a.title)
			if (files and #files > 0) or (dirs and #dirs > 0) then
				out[#out + 1] = { title = a.title, wsid = a.wsid }
			end
		end
	end
	table.sort(out, function(x, y) return string.lower(x.title) < string.lower(y.title) end)
	return out
end

-- every sound file of an addon (paths from the game root, at most 600)
function UI.AddonSounds(title)
	local out = {}
	local function walk(dir, depth)
		if #out >= 600 then return end
		local files, dirs = file.Find(dir .. "*", title)
		for _, f in ipairs(files or {}) do
			local low = string.lower(f)
			for _, ext in ipairs(EXTS) do
				if string.EndsWith(low, ext) then out[#out + 1] = dir .. f break end
			end
		end
		if depth >= 6 then return end
		for _, d in ipairs(dirs or {}) do walk(dir .. d .. "/", depth + 1) end
	end
	walk("sound/", 0)
	table.sort(out)
	return out
end

-- Copy a sound of an addon into garrysmod/data (dest without extension). Returns the
-- "data/…" path to play, or nil.
local function copySound(title, path, dest)
	-- the engine finds files by an addon title but reads only through the shared game path:
	-- that is this addon's file unless another mounted addon has the same path
	local data = file.Read(path, title) or file.Read(path, "GAME")
	if not data or #data == 0 then return nil end
	local ext = string.lower(string.GetExtensionFromFilename(path) or "wav")
	local target = dest .. "." .. ext
	file.CreateDir(string.GetPathFromFilename(target))
	local f = file.Open(target, "wb", "DATA")
	if not f then return nil end
	f:Write(data)
	f:Close()
	return "data/" .. target
end

-- play an addon's own file (copied first: the game path may belong to another addon)
function UI.PlayAddonSound(title, path)
	-- two names in turn: the previous sample may still be playing from its file
	UI._previewN = ((UI._previewN or 0) + 1) % 2
	local p = copySound(title, path, DATA_ROOT .. "_preview/sample" .. UI._previewN)
	if p then UI.PlayNotifyPath(p) end
end

-- a sound of an addon for a kind of the "Custom" set
function UI.UseAddonSound(title, path, kind)
	local name = slug(title) .. "_" .. slug(string.StripExtension(string.GetFileFromFilename(path)))
	local p = copySound(title, path, DATA_ROOT .. "_picked/" .. name)
	if not p then return false end
	RunConsoleCommand("speditor_notify_snd_" .. kind, p)
	RunConsoleCommand("speditor_notify_soundset", "custom")
	return true
end

-- guess which sound of a UI pack fits which kind (by the names the packs replace)
local GUESS = {
	[0] = { "drip3", "drip1", "hint", "notify", "balloon", "info", "ui_hover", "button14", "ding" },
	[2] = { "buttonclickrelease", "button15", "success", "done", "accept", "ok", "ui_click", "confirm" },
	[1] = { "error", "fail", "deny", "critical", "chord", "exclamation", "ui_return", "button10", "buttonclick", "wpn_denyselect" },
	[3] = { "save", "wpn_moveselect", "wpn_hudoff", "button9" },
}

function UI.GuessKinds(files)
	local out, used = {}, {}
	for kind = 0, 3 do
		for _, key in ipairs(GUESS[kind]) do
			for _, f in ipairs(files) do
				local base = string.lower(string.StripExtension(string.GetFileFromFilename(f)))
				if not used[f] and (base == key or string.find(base, key, 1, true)) then
					out[kind] = f
					used[f] = true
					break
				end
			end
			if out[kind] then break end
		end
	end
	return out
end

-- make a data set from an addon: map = { [kind] = path in the addon }
function UI.MakeSoundSet(title, map)
	local folder = slug(title)
	local any = false
	for kind, path in pairs(map) do
		-- the old files of the set are replaced
		for _, ext in ipairs(EXTS) do file.Delete(DATA_ROOT .. folder .. "/" .. KIND_FILE[kind] .. ext) end
		if copySound(title, path, DATA_ROOT .. folder .. "/" .. KIND_FILE[kind]) then any = true end
	end
	if not any then return nil end
	UI.ScanNotifySounds()
	return "data_" .. folder
end

---------------------------------------------------------------------
-- JSON styles
---------------------------------------------------------------------
UI.NotifyStyleDefaults = {
	name = "My style", bg = { 30, 32, 38, 235 }, border = { 255, 255, 255, 40 }, borderWidth = 1, radius = 6,
	text = { 235, 235, 235 }, accent = "left", accentSize = 3, font = "Tahoma", fontSize = 13, bold = false,
	blur = 0, sheen = 0, shadow = false, icons = "silk", pad = 9,
}

local function col(t, a)
	t = istable(t) and t or {}
	return Color(tonumber(t[1] or t.r) or 255, tonumber(t[2] or t.g) or 255, tonumber(t[3] or t.b) or 255, tonumber(t[4] or t.a) or a or 255)
end

local fontN = 0
-- fontName: reuse a font name (the style editor rebuilds its draft on every change)
function UI.NotifyStyleFromTable(t, fontName)
	local D = UI.NotifyStyleDefaults
	local function get(k) if t[k] == nil then return D[k] end return t[k] end
	local draw2 = UI.NotifyDraw
	local font = fontName
	if not font then
		fontN = fontN + 1
		font = "SPeditor.NS." .. fontN
	end
	surface.CreateFont(font, { font = tostring(get("font")), size = math.Clamp(tonumber(get("fontSize")) or 13, 10, 32),
		weight = get("bold") and 800 or 500, antialias = true, extended = true })
	local bg, border, text = col(get("bg")), col(get("border")), col(get("text"))
	local r = math.Clamp(tonumber(get("radius")) or 0, 0, 16)
	local bw = math.Clamp(tonumber(get("borderWidth")) or 0, 0, 3)
	local accent, asz = get("accent"), math.Clamp(tonumber(get("accentSize")) or 3, 1, 8)
	local blur = math.Clamp(tonumber(get("blur")) or 0, 0, 10)
	local sheen = math.Clamp(tonumber(get("sheen")) or 0, 0, 100)
	local icons = get("icons")
	return {
		name = tostring(get("name")), font = font, pad = math.Clamp(tonumber(get("pad")) or 9, 3, 20),
		icon = (icons == "none") and 0 or ((icons == "gmod") and 24 or 16),
		gmodIcons = icons == "gmod", iconDisc = icons == "disc", shadow = get("shadow") and true or false,
		bg = function(p, w, h, kc)
			if blur > 0 then draw2.blur(p, blur) end
			local fill = (accent == "fill") and draw2.mix(bg, kc, 0.55) or bg
			fill = Color(fill.r, fill.g, fill.b, bg.a)
			draw.RoundedBox(r, 0, 0, w, h, fill)
			if sheen > 0 then
				surface.SetMaterial(draw2.gradDown)
				surface.SetDrawColor(255, 255, 255, sheen * 2.55)
				surface.DrawTexturedRect(1, 1, w - 2, math.floor(h * 0.55))
			end
			for i = 0, bw - 1 do draw2.outline(i, i, w - i * 2, h - i * 2, math.max(r - i, 0), border) end
			surface.SetDrawColor(kc)
			if accent == "left" then
				draw.RoundedBoxEx(math.min(r, asz), 0, 0, asz, h, kc, true, false, true, false)
			elseif accent == "top" then
				draw.RoundedBoxEx(math.min(r, asz), 0, 0, w, asz, kc, true, true, false, false)
			elseif accent == "bottom" then
				draw.RoundedBoxEx(math.min(r, asz), 0, h - asz, w, asz, kc, false, false, true, true)
			end
		end,
		text = function() return text end,
	}
end

local function readJSON(path, where)
	local raw = file.Read(path, where)
	local t = raw and util.JSONToTable(raw)
	return istable(t) and t or nil
end

UI.NotifyStyleTables = UI.NotifyStyleTables or {}

function UI.LoadNotifyStyles()
	for _, id in ipairs(table.Copy(UI.NotifyStyles)) do
		local def = UI.NotifyStyleDefs[id]
		if def and def.json then UI.RemoveNotifyStyle(id) end
	end
	UI.NotifyStyleTables = {}
	local function add(path, where, file_, static)
		local t = readJSON(path, where)
		if not t then return end
		local id = "json_" .. slug(string.StripExtension(file_))
		if UI.NotifyStyleDefs[id] then return end
		local ok, def = pcall(UI.NotifyStyleFromTable, t)
		if not ok then
			MsgC(Color(255, 120, 80), "[SPeditor] notification style ", file_, ": ", tostring(def), "\n")
			return
		end
		def.json, def.static = true, static
		UI.NotifyStyleTables[id] = t
		UI.AddNotifyStyle(id, def)
	end
	for _, f in ipairs(file.Find(STYLE_DIR .. "*.json", "DATA") or {}) do add(STYLE_DIR .. f, "DATA", f, false) end
	for _, f in ipairs(file.Find(STATIC_DIR .. "*.json", "GAME") or {}) do add(STATIC_DIR .. f, "GAME", f, true) end
end

function UI.SaveNotifyStyle(t)
	file.CreateDir(STYLE_DIR)
	local name = slug(t.name)
	file.Write(STYLE_DIR .. name .. ".json", util.TableToJSON(t, true))
	UI.LoadNotifyStyles()
	return "json_" .. name
end

function UI.DeleteNotifyStyle(id)
	local def = UI.NotifyStyleDefs[id]
	if not def or not def.json or def.static then return false end
	file.Delete(STYLE_DIR .. string.sub(id, 6) .. ".json")
	UI.LoadNotifyStyles()
	if GetConVarString("speditor_notify_style") == id then RunConsoleCommand("speditor_notify_style", "auto") end
	return true
end

---------------------------------------------------------------------
-- The "Sounds from addons" window
---------------------------------------------------------------------
function UI.OpenSoundAddons()
	local Dock = SPeditor.Dock
	if Dock.ShowPage("soundaddons") then return end
	local W, H = 760, 480
	local win, body = Dock.Create({ key = "soundaddons", id = "soundaddons", title = L("nsa_title"), w = W, h = H,
			x = math.floor(ScrW() / 2 - W / 2), y = 120, dockable = false, icon = "icon16/sound.png" })
	win.minW, win.minH = 520, 300

	local hint = UI.Label(body, L("nsa_hint"), COL.DIM)
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:DockMargin(8, 6, 8, 4)

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(34)
	foot.Paint = function() end

	local addons = vgui.Create("DListView", body)
	addons:Dock(LEFT)
	addons:SetWide(260)
	addons:DockMargin(6, 0, 3, 0)
	addons:SetMultiSelect(false)
	addons:AddColumn(L("nsa_addons"))
	local sounds = vgui.Create("DListView", body)
	sounds:Dock(FILL)
	sounds:DockMargin(3, 0, 6, 0)
	sounds:SetMultiSelect(false)
	sounds:AddColumn(L("nsa_sounds"))
	sounds:AddColumn(L("nsa_guess")):SetFixedWidth(110)

	local cur = { title = nil, files = {} }
	local list = UI.SoundAddons()
	for _, a in ipairs(list) do addons:AddLine(a.title).addon = a end
	if #list == 0 then addons:AddLine(L("nsa_none")) end

	addons.OnRowSelected = function(_, _, line)
		if not line.addon then return end
		cur.title = line.addon.title
		cur.files = UI.AddonSounds(cur.title)
		cur.guess = UI.GuessKinds(cur.files)
		local kindOf = {}
		for k, f in pairs(cur.guess) do kindOf[f] = k end
		sounds:Clear()
		for _, f in ipairs(cur.files) do
			local k = kindOf[f]
			sounds:AddLine(string.sub(f, 7), k and L("notify_kind_" .. k) or "").path = f
		end
	end

	local function selected()
		local _, line = sounds:GetSelectedLine()
		return line and line.path
	end
	sounds.DoDoubleClick = function(_, _, line) if cur.title then UI.PlayAddonSound(cur.title, line.path) end end
	sounds.OnRowRightClick = function(_, _, line)
		local m = UI.Menu()
		m:AddOption(L("nsa_play"), function() UI.PlayAddonSound(cur.title, line.path) end):SetIcon("icon16/sound.png")
		m:AddSpacer()
		for k = 0, 3 do
			m:AddOption(string.format(L("nsa_use_for"), L("notify_kind_" .. k)), function()
				if UI.UseAddonSound(cur.title, line.path, k) then
					SPeditor.Notify(string.format(L("nsa_used"), L("notify_kind_" .. k)), 2)
				end
			end)
		end
		m:Open()
	end

	local function btn(text, icon, fn, dock)
		local b = vgui.Create("DButton", foot)
		b:Dock(dock or LEFT)
		b:DockMargin(dock == RIGHT and 4 or 8, 5, dock == RIGHT and 8 or 0, 5)
		surface.SetFont("SPeditor.Small")
		b:SetWide(select(1, surface.GetTextSize(text)) + 40)
		b:SetText("  " .. text)
		b:SetIcon(icon)
		UI.StyleButton(b, nil, 3)
		b.DoClick = fn
		return b
	end
	btn(L("nsa_play"), "icon16/sound.png", function()
		local p = selected()
		if p and cur.title then UI.PlayAddonSound(cur.title, p) end
	end)
	btn(L("nsa_use") .. "…", "icon16/tick.png", function()
		local p = selected()
		if not (p and cur.title) then return end
		local m = UI.Menu()
		for k = 0, 3 do
			m:AddOption(L("notify_kind_" .. k), function()
				if UI.UseAddonSound(cur.title, p, k) then SPeditor.Notify(string.format(L("nsa_used"), L("notify_kind_" .. k)), 2) end
			end)
		end
		m:Open()
	end)
	btn(L("nsa_make_set"), "icon16/sound_add.png", function()
		if not cur.title then return end
		local id = UI.MakeSoundSet(cur.title, cur.guess or {})
		if id then
			RunConsoleCommand("speditor_notify_soundset", id)
			SPeditor.Notify(string.format(L("nsa_set_made"), cur.title), 2)
		else
			SPeditor.Notify(L("nsa_set_fail"), 1)
		end
	end)
	btn(L("about_close"), "icon16/door_out.png", function() win:Close() end, RIGHT)
end

---------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------
UI.ScanNotifySounds()
UI.LoadNotifyStyles()

-- styles and sound sets in lua files of any addon
for _, f in ipairs(file.Find("speditor_notify/*.lua", "LUA") or {}) do
	local ok, err = pcall(include, "speditor_notify/" .. f)
	if not ok then MsgC(Color(255, 120, 80), "[SPeditor] speditor_notify/", f, ": ", tostring(err), "\n") end
end
