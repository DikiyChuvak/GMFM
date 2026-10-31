--[[
SPeditor — third-party shaders: from the Steam Workshop, from addons and from its own folder.

Third-party shaders in GMod come in two kinds and are hooked up differently.

1. SHADER MATERIAL. A material (.vmt) on the screenspace_general shader with its own
   pixel shader ($pixshader, a compiled file shaders/fxc/*.vcs).
   It gets the frame through $basetexture (_rt_FullFrameFB), numbers — through
   $c0_x … $c3_w. The editor applies such a material itself, as the camera effect
   "Custom shader" (cl_postfx.lua): it works in the preview and in a render of any
   size. Materials are looked for in materials/pp, materials/effects/shaders,
   materials/shaders (where addons and the Workshop put them) and in packs from the
   editor's shader folder.

2. HOOK-BASED EFFECT. The addon draws the effect itself in the main game frame and is
   switched on by a console variable; stock GMod post-processing and shaders on
   GShader Library work this way (they need depth and normal buffers that the library
   builds only for the main frame). For them there is the "Engine frame" mode
   (cl_render.lua): the engine itself shoots the frame with all enabled effects, and
   the editor takes the finished picture. The list of such effects is list "PostProcess",
   each has its own settings panel (as in the Q menu); see cl_ui_shaders.lua.

SHADER FOLDER: garrysmod/addons/speditor/shaders/<pack>/
  A pack is a folder downloaded from the Workshop or GitHub, with the addon structure:
      materials/...            materials (.vmt) and textures (.vtf, .png)
      shaders/fxc/*.vcs        compiled shaders
  (one extra nested folder is fine, as in GitHub archives: pack/pack-main/...),
  or just loose .vcs and .vmt files.
  The engine reads materials/ and shaders/fxc/ only from an addon root, so a pack
  is packed into a .gma (data/speditor/shaderpacks/<pack>.dat) and mounted
  through game.MountGMA — without restarting the game (verified in game).
  Lua from a pack is NOT run: an addon with Lua (hook-based effects, GShader
  Library itself) is installed the usual way — a Workshop subscription or a folder in
  garrysmod/addons — and works through "Engine frame".

API:
  Sd.Scan(force) -> number of packs, number of shaders     rescan everything
  Sd.List / Sd.Get(path)        shader materials found
  Sd.Packs / Sd.Issues          packs from the folder and remarks on them
  Sd.Material(info)             the shader's material (or nil)
  Sd.PostProcess()              effects from list "PostProcess"
]]
SPeditor = SPeditor or {}
SPeditor.Shaders = SPeditor.Shaders or {}
local Sd = SPeditor.Shaders

Sd.ROOT  = "shaders/"
Sd.CACHE = (SPeditor.Config and SPeditor.Config.SaveDir or "speditor") .. "/shaderpacks"

Sd.Packs  = Sd.Packs or {}
Sd.Issues = Sd.Issues or {}
Sd.List   = Sd.List or {}
Sd.ByPath = Sd.ByPath or {}

local MAX_PACK_FILES = 4000
local MAX_PACK_BYTES = 256 * 1024 * 1024
local MAX_PARAMS     = 12          -- sliders per shader (the server keeps up to 16 values per effect)
local ENGINE_DIRS    = { fxc = true, psh = true, vsh = true }      -- these are engine directories, not packs
local PACK_EXT       = { vmt = true, vtf = true, png = true, jpg = true, jpeg = true, vcs = true }

-- where addons keep screen shader materials
local MATERIAL_DIRS = { "materials/pp/", "materials/effects/shaders/", "materials/shaders/" }

local mounted = Sd.mounted or {}   -- [slug] = signature of the mounted content
Sd.mounted = mounted

local function slug(s)
	return (string.gsub(string.lower(s), "[^%w]+", "_"))
end

local function ext(name)
	return string.lower(string.match(name, "%.([%w]+)$") or "")
end

---------------------------------------------------------------------
-- Parsing a .vmt
---------------------------------------------------------------------
local TEXTURE_SLOTS = { "$basetexture", "$texture1", "$texture2", "$texture3" }

-- Returns a shader material description, or nil if it is not a screen shader
local function parseVMT(text)
	text = string.gsub(text, "//[^\n]*", "")
	local shader = string.lower(string.match(text, "^%s*\"?([%w_]+)\"?") or "")
	local lower = string.lower(text)
	if not string.find(lower, "$pixshader", 1, true) then return nil end
	if not string.find(shader, "screenspace", 1, true) then return nil end

	local info = { shader = shader, params = {}, inputs = {}, buffers = false }

	local function value(key)
		return string.match(lower, "\"?%" .. key .. "\"?%s+\"?([^\"%s]+)\"?")
	end

	-- what the frame is fed into; other textures (depth, normals, custom) are left alone
	local anyTexture = false
	for _, slot in ipairs(TEXTURE_SLOTS) do
		local tex = value(slot)
		if tex then
			anyTexture = true
			if string.find(tex, "fullframefb", 1, true) or string.find(tex, "poweroftwofb", 1, true) then
				info.inputs[#info.inputs + 1] = slot
			elseif string.find(tex, "depth", 1, true) or string.find(tex, "normals", 1, true) or string.find(tex, "_rt_bump", 1, true) then
				info.buffers = true
			end
		end
	end
	if not anyTexture or (#info.inputs == 0 and not value("$basetexture")) then info.inputs[#info.inputs + 1] = "$basetexture" end

	-- numeric parameters $c0_x … $c3_w set in the material
	local seen = {}
	for reg, comp, num in string.gmatch(lower, "\"?%$c(%d)_([xyzw])\"?%s+\"?([%-%d%.e]+)\"?") do
		local key = "c" .. reg .. "_" .. comp
		local v = tonumber(num)
		if v and not seen[key] and tonumber(reg) <= 3 then
			seen[key] = true
			info.params[#info.params + 1] = { key = key, name = "$" .. key, default = v }
		end
	end
	table.sort(info.params, function(a, b) return a.key < b.key end)
	while #info.params > MAX_PARAMS do table.remove(info.params) end
	for _, p in ipairs(info.params) do
		-- the slider range is unknown: take a generous one around the value from the material
		local m = math.max(math.abs(p.default) * 4, 1)
		p.min, p.max = (p.default < 0) and -m or 0, m
	end
	return info
end
Sd.ParseVMT = parseVMT

local function addShader(vmtPath, source)
	-- vmtPath: materials/a/b.vmt -> material path a/b
	local path = string.lower(string.sub(vmtPath, #"materials/" + 1, -5))
	if Sd.ByPath[path] or #path > 120 or string.find(path, "[^%w_%-/%. ]") then return false end
	local text = file.Read(vmtPath, "GAME")
	if not text or #text > 65536 then return false end
	local info = parseVMT(text)
	if not info then return false end
	info.path, info.source = path, source
	info.name = string.GetFileFromFilename(path)
	Sd.List[#Sd.List + 1] = info
	Sd.ByPath[path] = info
	return true
end

local function scanMaterialDir(dir, source, depth, budget)
	local files, dirs = file.Find(dir .. "*", "GAME")
	for _, f in ipairs(files or {}) do
		if budget.left <= 0 then return end
		if ext(f) == "vmt" then
			budget.left = budget.left - 1
			addShader(dir .. f, source)
		end
	end
	if depth >= 3 then return end
	for _, d in ipairs(dirs or {}) do scanMaterialDir(dir .. d .. "/", source, depth + 1, budget) end
end

---------------------------------------------------------------------
-- Packs from the shader folder: packing into a .gma and mounting
---------------------------------------------------------------------
local function u32(n)
	return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

-- The pack directory that holds materials/ or shaders/ (the pack itself or a nested
-- folder, as in a GitHub archive). nil — the files are loose.
local function findBase(root, depth)
	local _, dirs = file.Find(root .. "*", "GAME")
	local has = {}
	for _, d in ipairs(dirs or {}) do has[string.lower(d)] = d end
	if has.materials or has.shaders then return root, has end
	if depth >= 3 then return nil end
	for _, d in ipairs(dirs or {}) do
		local base, h = findBase(root .. d .. "/", depth + 1)
		if base then return base, h end
	end
	return nil
end

local function collect(dir, rel, out, state)
	local files, dirs = file.Find(dir .. "*", "GAME")
	for _, f in ipairs(files or {}) do
		if PACK_EXT[ext(f)] and #out < MAX_PACK_FILES then
			local size = file.Size(dir .. f, "GAME") or 0
			state.bytes = state.bytes + size
			out[#out + 1] = { src = dir .. f, dst = string.lower(rel .. f), size = size, time = file.Time(dir .. f, "GAME") or 0 }
		end
	end
	for _, d in ipairs(dirs or {}) do collect(dir .. d .. "/", rel .. d .. "/", out, state) end
end

local function readBinary(path)
	local f = file.Open(path, "rb", "GAME")
	if not f then return nil end
	local data = f:Read(f:Size()) or ""
	f:Close()
	return data
end

-- Build a .gma from a file list. Returns the string and the number of skipped files.
local function buildGMA(name, files)
	local head = { "GMAD", string.char(3), string.rep("\0", 16), "\0", name, "\0", "SPeditor shader pack", "\0", "SPeditor", "\0", u32(1) }
	local body, n, skipped = {}, 0, 0
	for _, f in ipairs(files) do
		local data = readBinary(f.src)
		if data then
			n = n + 1
			head[#head + 1] = u32(n) .. f.dst .. "\0" .. u32(#data) .. u32(0) .. u32(tonumber(util.CRC(data)) or 0)
			body[#body + 1] = data
		else
			skipped = skipped + 1
		end
	end
	head[#head + 1] = u32(0)
	return table.concat(head) .. table.concat(body) .. u32(0), skipped
end

local function ensureCacheDir()
	local acc = ""
	for part in string.gmatch(Sd.CACHE, "[^/]+") do
		acc = (acc == "") and part or (acc .. "/" .. part)
		if not file.IsDir(acc, "DATA") then file.CreateDir(acc) end
	end
end

local function scanPack(folder)
	local root = Sd.ROOT .. folder .. "/"
	local pack = { name = folder, slug = slug(folder), root = root, shaders = 0, files = 0 }
	local inside, insideDirs = file.Find(root .. "*", "GAME")
	if #(inside or {}) == 0 and #(insideDirs or {}) == 0 then
		-- the folder is visible but its content is not: on Linux the engine does not enter folders with capital letters
		pack.issue = "shader_pack_case"
		return pack
	end

	local files, state = {}, { bytes = 0 }
	local base, has = findBase(root, 0)
	if base then
		if has.materials then collect(base .. has.materials .. "/", "materials/", files, state) end
		if has.shaders then collect(base .. has.shaders .. "/", "shaders/", files, state) end
		pack.hasLua = has.lua ~= nil
	else
		-- loose files: shaders go to shaders/fxc, materials and textures — to their own materials folder
		local loose = {}
		collect(root, "", loose, state)
		for _, f in ipairs(loose) do
			local fname = string.GetFileFromFilename(f.dst)
			f.dst = (ext(fname) == "vcs") and ("shaders/fxc/" .. fname) or ("materials/speditor_packs/" .. pack.slug .. "/" .. fname)
			files[#files + 1] = f
		end
	end
	-- only compiled files are needed from the shaders directory
	for i = #files, 1, -1 do
		local f = files[i]
		if string.sub(f.dst, 1, 8) == "shaders/" and (ext(f.dst) ~= "vcs" or string.sub(f.dst, 1, 12) ~= "shaders/fxc/") then
			table.remove(files, i)
		end
	end
	pack.files, pack.bytes = #files, state.bytes
	if #files == 0 then
		pack.issue = pack.hasLua and "shader_pack_lua_only" or "shader_pack_empty"
		return pack
	end
	if state.bytes > MAX_PACK_BYTES then
		pack.issue = "shader_pack_big"
		return pack
	end

	table.sort(files, function(a, b) return a.dst < b.dst end)
	local sigParts = {}
	for i, f in ipairs(files) do sigParts[i] = f.dst .. ":" .. f.size .. ":" .. f.time end
	local sig = util.CRC(table.concat(sigParts, "|"))

	-- packing: only if the pack content has changed
	local gmaPath = Sd.CACHE .. "/" .. pack.slug .. ".dat"
	local sigPath = Sd.CACHE .. "/" .. pack.slug .. ".txt"
	if file.Read(sigPath, "DATA") ~= sig or not file.Exists(gmaPath, "DATA") then
		ensureCacheDir()
		local gma, skipped = buildGMA(folder, files)
		file.Write(gmaPath, gma)
		file.Write(sigPath, sig)
		pack.skipped = skipped
	end

	if mounted[pack.slug] ~= sig then
		-- the pack was already mounted in this game with different content: the engine will
		-- not re-read materials that are already loaded
		pack.stale = mounted[pack.slug] ~= nil
		local ok = game.MountGMA("data/" .. gmaPath)
		if not ok then
			pack.issue = "shader_pack_mount"
			return pack
		end
		mounted[pack.slug] = sig
	end
	pack.mounted = true

	for _, f in ipairs(files) do
		if ext(f.dst) == "vmt" and addShader(f.dst, folder) then pack.shaders = pack.shaders + 1 end
	end
	return pack
end

-- Rescan the shader folder and the addon materials.
-- force = false — only if not scanned yet in this game.
function Sd.Scan(force)
	if Sd.scanned and not force then return #Sd.Packs, #Sd.List end
	Sd.scanned = true
	Sd.Packs, Sd.Issues, Sd.List, Sd.ByPath = {}, {}, {}, {}

	local _, folders = file.Find(Sd.ROOT .. "*", "GAME")
	folders = folders or {}
	table.sort(folders)
	for _, folder in ipairs(folders) do
		if not ENGINE_DIRS[string.lower(folder)] then
			local ok, pack = pcall(scanPack, folder)
			if not ok then
				ErrorNoHalt("[GM:FM] shader pack '" .. folder .. "': " .. tostring(pack) .. "\n")
				pack = { name = folder, slug = slug(folder), issue = "shader_pack_error", shaders = 0, files = 0 }
			end
			Sd.Packs[#Sd.Packs + 1] = pack
			if pack.issue then Sd.Issues[#Sd.Issues + 1] = { name = folder, reason = pack.issue } end
		end
	end

	-- materials of installed addons and the Workshop
	local budget = { left = 800 }
	for _, dir in ipairs(MATERIAL_DIRS) do scanMaterialDir(dir, "addons", 0, budget) end

	table.sort(Sd.List, function(a, b)
		if a.source ~= b.source then return a.source < b.source end
		return a.path < b.path
	end)
	hook.Run("SPeditor_ShadersScanned")
	return #Sd.Packs, #Sd.List
end

function Sd.Get(path)
	if not isstring(path) or path == "" then return nil end
	if not Sd.scanned then Sd.Scan(false) end
	return Sd.ByPath[string.lower(path)]
end

local materials = {}
function Sd.Material(info)
	local m = materials[info.path]
	if m == nil then
		m = Material(info.path)
		if m:IsError() then m = false end
		materials[info.path] = m
	end
	return m or nil
end

-- Packs are mounted when the editor is first opened: their materials are not needed before that
SPeditor.Hook("SPeditor_StateChanged", "SPeditor.Shaders", function(on)
	if on and not Sd.scanned then
		local ok, err = pcall(Sd.Scan, false)
		if not ok then ErrorNoHalt("[GM:FM] shaders: " .. tostring(err) .. "\n") end
	end
end)

---------------------------------------------------------------------
-- Hook-based effects: list "PostProcess" (stock, from addons and the Workshop)
---------------------------------------------------------------------
local function phrase(s)
	if not isstring(s) then return "" end
	if string.sub(s, 1, 1) == "#" then return language.GetPhrase(string.sub(s, 2)) end
	return s
end

-- { key, name, category, convar, cpanel, icon }
function Sd.PostProcess()
	local out = {}
	for key, item in pairs(list.Get("PostProcess") or {}) do
		if istable(item) then
			local cv = isstring(item.convar) and item.convar ~= "" and item.convar or nil
			out[#out + 1] = {
				key = key, name = phrase(key), category = phrase(item.category),
				convar = cv and GetConVar(cv) and cv or nil,
				cpanel = isfunction(item.cpanel) and item.cpanel or nil, icon = item.icon,
			}
		end
	end
	table.sort(out, function(a, b)
		if a.category ~= b.category then return a.category < b.category end
		return a.name < b.name
	end)
	return out
end

function Sd.IsOn(entry)
	local cv = entry.convar and GetConVar(entry.convar)
	return cv ~= nil and cv:GetBool()
end

function Sd.SetOn(entry, on)
	if entry.convar then RunConsoleCommand(entry.convar, on and "1" or "0") end
end

-- How many hook-based effects are switched on now
function Sd.ActiveCount()
	local n = 0
	for _, e in ipairs(Sd.PostProcess()) do
		if Sd.IsOn(e) then n = n + 1 end
	end
	return n
end

---------------------------------------------------------------------
-- Addon effects in camera keys (b0.1, asked in the Workshop chat: "the depth of field shader
-- as keyframes"). The settings of a hook-based effect are console variables; a camera can keep
-- a copy of them in its effects under "e:<on/off variable>" = { [variable] = value }, and that
-- copy is keyed and blended with the camera like its own effects. While the engine shoots a
-- frame for that camera (Engine frame) the variables are set to the camera's values and put
-- back right after the frame, so the player's own Q-menu settings stay as they were.
---------------------------------------------------------------------
Sd.KEY_PREFIX = "e:"
local MAX_VARS = 15            -- the server keeps 16 values per effect: "on" + 15 variables
local MAX_NAME = 24

-- The variables of an effect, read from its own settings panel (as the Q menu builds it): the
-- sliders, check boxes, colour mixers and presets there name them. Cached per effect.
local varsCache = {}
local function collect(panel, out, depth)
	if depth > 12 or not IsValid(panel) then return end
	for _, k in ipairs({ "m_strConVar", "m_ConVarR", "m_ConVarG", "m_ConVarB", "m_ConVarA" }) do
		local v = panel[k]
		if isstring(v) and v ~= "" then out[v] = true end
	end
	if istable(panel.ConVars) then
		for _, v in pairs(panel.ConVars) do
			if isstring(v) then out[v] = true end
		end
	end
	for _, ch in ipairs(panel:GetChildren()) do collect(ch, out, depth + 1) end
end

function Sd.ConVarsOf(entry)
	if not entry.convar then return {} end
	local cached = varsCache[entry.key]
	if cached then return cached end
	local found = {}
	if entry.cpanel then
		local cp
		pcall(function()
			cp = vgui.Create("ControlPanel")
			cp:SetVisible(false)
			entry.cpanel(cp)
			collect(cp, found, 0)
		end)
		if IsValid(cp) then cp:Remove() end
	end
	found[entry.convar] = nil
	local list = {}
	for name in pairs(found) do
		if #name <= MAX_NAME and GetConVar(name) then list[#list + 1] = name end
	end
	table.sort(list)
	while #list > MAX_VARS do table.remove(list) end
	varsCache[entry.key] = list
	return list
end

local function value(cv)
	local s = cv:GetString()
	return tonumber(s) or s
end

-- The addon effects as they are set now, for a camera's effects: { ["e:pp_bokeh"] = {...} }.
-- An effect that is off is kept too (switched off in this key); one whose variable name is too
-- long for a camera's effects is left out.
function Sd.Snapshot()
	local out = {}
	for _, e in ipairs(Sd.PostProcess()) do
		local cv = e.convar and GetConVar(e.convar)
		if cv and #e.convar + #Sd.KEY_PREFIX <= MAX_NAME then
			local t = { on = true, [e.convar] = cv:GetBool() and 1 or 0 }
			if cv:GetBool() then
				for _, name in ipairs(Sd.ConVarsOf(e)) do t[name] = value(GetConVar(name)) end
			end
			out[Sd.KEY_PREFIX .. e.convar] = t
		end
	end
	return out
end

-- how many effects of a camera's effects table are on
function Sd.KeyedCount(fx)
	local n, on = 0, 0
	for id, t in pairs(istable(fx) and fx or {}) do
		if istable(t) and string.sub(id, 1, #Sd.KEY_PREFIX) == Sd.KEY_PREFIX then
			n = n + 1
			if tonumber(t[string.sub(id, #Sd.KEY_PREFIX + 1)]) == 1 then on = on + 1 end
		end
	end
	return n, on
end

-- Put a camera's keyed variables on for an engine frame. (b0.2.6, Workshop: "65 GB of RAM, a
-- crash — rendering shader addons") They were put back after every frame, so the effects of a
-- camera were switched on and off twice a frame through the whole render: an addon that makes its
-- buffers or meshes when its effect is switched on made them anew every frame. Now the camera's
-- values stay on while engine frames keep coming and the player's own come back once, half a second
-- after the last one (SPeditor.Shaders held / RestoreKeyed below); a variable the next camera
-- does not key gets the player's value back at once.
Sd.held = Sd.held or {}         -- [variable] = the player's own value while a camera's is on it
local HOLD = 0.5

function Sd.ApplyKeyed(fx)
	local want = {}
	for id, t in pairs(istable(fx) and fx or {}) do
		if istable(t) and t.on and string.sub(id, 1, #Sd.KEY_PREFIX) == Sd.KEY_PREFIX then
			for name, v in pairs(t) do
				if name ~= "on" and GetConVar(name) then
					want[name] = isnumber(v) and tostring(math.Round(v, 4)) or tostring(v)
				end
			end
		end
	end
	for name, own in pairs(Sd.held) do
		if want[name] == nil then
			local cv = GetConVar(name)
			if cv and cv:GetString() ~= own then pcall(cv.SetString, cv, own) end
			Sd.held[name] = nil
		end
	end
	for name, s in pairs(want) do
		local cv = GetConVar(name)
		local had = cv:GetString()
		if had ~= s and (tonumber(had) == nil or tonumber(had) ~= tonumber(s)) then
			if Sd.held[name] == nil then Sd.held[name] = had end
			pcall(cv.SetString, cv, s)
		end
	end
	Sd.heldAt = RealTime()
	return next(Sd.held) ~= nil or nil
end

-- the frame is shot: the player's values come back once no engine frame has asked for a while
function Sd.RestoreKeyed()
	Sd.heldAt = RealTime()
end

function Sd.RestoreAllKeyed()
	for name, own in pairs(Sd.held) do
		local cv = GetConVar(name)
		if cv then pcall(cv.SetString, cv, own) end
	end
	Sd.held = {}
end

SPeditor.Hook("Think", "SPeditor.ShadersHeld", function()
	if next(Sd.held) == nil or RealTime() - (Sd.heldAt or 0) < HOLD then return end
	if SPeditor.Export and SPeditor.Export.Busy and SPeditor.Export.Busy() then return end
	Sd.RestoreAllKeyed()
end)
SPeditor.Hook("ShutDown", "SPeditor.ShadersHeld", function() Sd.RestoreAllKeyed() end)
