--[[
SPeditor — custom themes from the themes folder.

A theme can be downloaded (any addon with a Derma skin) and put as a folder into
  garrysmod/addons/speditor/themes/<name>/
with the standard addon structure:
  lua/...                      the skin — a lua file that calls derma.DefineSkin
  materials/gwenskin/*.png     the skin texture(s)
Then: View → Interface theme → "Rescan the themes folder".

How it works:
  * the game does not mount the themes folder (it is neither lua/ nor materials/ of an addon),
    so the skin file is read as text and run here, and textures
    are taken by the full path themes/<name>/materials/...;
  * the skin runs in its own environment: it is registered under the name
    "SPeditor.user.*", and its hooks, console commands, sounds, windows and replacement
    of stock panels are disabled — the theme works only inside the editor;
  * one skin and several textures in gwenskin (as in EcoUI) — a separate theme per
    texture; several skins — a separate theme per skin;
  * the palette for the editor windows is sampled from the skin texture.

Limitations: textures only PNG/JPG (the engine will not load VMT/VTF from the
themes folder); on Linux the engine lower-cases paths, so the names of the
theme folder and of the files in it must be lower case.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI = SPeditor.UI
local util2 = UI.ThemeUtil

local ROOT = "themes/"

-- folders whose themes are already bundled with the addon (lua/speditor/skins)
local BUILTIN = {
	darkui = true, ecoui = true, gmod98 = true, lamdaui = true, oneshotui = true, steamderma2004 = true,
	vanillaui = true, gmodxp = true,
	-- a0.9: ported as hl2mp (the Lambda UI skin with its texture), gmodclassic and aeroblur
	hl2mediaplayer = true, gmodclassic = true, aeroblur = true,
}

UI.ThemeIssues = {}
local generation = 0

---------------------------------------------------------------------
-- Finding themes
---------------------------------------------------------------------
local function findLua(dir, out, depth)
	local files, dirs = file.Find(dir .. "*", "GAME")
	for _, f in ipairs(files or {}) do
		if string.EndsWith(string.lower(f), ".lua") then out[#out + 1] = dir .. f end
	end
	if depth >= 5 then return end
	for _, d in ipairs(dirs or {}) do findLua(dir .. d .. "/", out, depth + 1) end
end

local function baseName(path)
	return string.StripExtension(string.GetFileFromFilename(path))
end

local function slug(s)
	return (string.gsub(string.lower(s), "[^%w]+", "_"))
end

-- Rebuild the list of themes from the themes folder. Returns their number.
function UI.ScanUserThemes()
	generation = generation + 1
	for i = #UI.Themes, 1, -1 do
		local t = UI.Themes[i]
		if t.user then
			table.remove(UI.Themes, i)
			UI.ThemeById[t.id] = nil
		end
	end
	UI.ThemeIssues = {}

	local count = 0
	local function add(folder, id, name, group, luaPath, tex)
		id = "user_" .. id
		if UI.ThemeById[id] then return end
		UI.AddTheme({ id = id, name = name, group = group, user = true, native = true,
				skin = "SPeditor.user." .. id .. "#" .. generation,
				userRoot = ROOT .. folder .. "/", userFile = luaPath, userTex = tex })
		count = count + 1
	end

	local _, folders = file.Find(ROOT .. "*", "GAME")
	folders = folders or {}
	table.sort(folders)
	for _, folder in ipairs(folders) do
		if not BUILTIN[string.lower(folder)] then
			local root = ROOT .. folder .. "/"
			local inside, insideDirs = file.Find(root .. "*", "GAME")
			local skins = {}
			local luaFiles = {}
			findLua(root .. "lua/", luaFiles, 0)
			for _, path in ipairs(luaFiles) do
				local src = file.Read(path, "GAME")
				if src and string.find(src, "derma.DefineSkin", 1, true) then skins[#skins + 1] = path end
			end
			table.sort(skins)
			local pngs = file.Find(root .. "materials/gwenskin/*.png", "GAME") or {}
			table.sort(pngs)

			if #skins == 0 then
				-- the folder is visible but its content is not: the engine cannot enter it because of the name case
				local unreadable = #(inside or {}) == 0 and #(insideDirs or {}) == 0
				UI.ThemeIssues[#UI.ThemeIssues + 1] = { name = folder, reason = unreadable and "theme_case" or "theme_no_skin" }
			elseif #skins == 1 and #pngs > 1 then
				for _, png in ipairs(pngs) do
					local n = string.StripExtension(png)
					add(folder, slug(folder) .. "_" .. slug(n), n, folder, skins[1], root .. "materials/gwenskin/" .. png)
				end
			elseif #skins == 1 then
				add(folder, slug(folder), folder, nil, skins[1])
			else
				for _, path in ipairs(skins) do
					add(folder, slug(folder) .. "_" .. slug(baseName(path)), baseName(path), folder, path)
				end
			end
		end
	end
	return count
end

---------------------------------------------------------------------
-- Running a skin in its own environment
---------------------------------------------------------------------
local function noop() end

local function shallow(lib, overrides)
	local t = {}
	for k, v in pairs(lib) do t[k] = v end
	for k, v in pairs(overrides) do t[k] = v end
	return t
end

local function environment(t, onSkin)
	-- skin textures: look in the theme folder first, otherwise the regular game path
	local function material(path, params)
		local p = string.lower(string.gsub(tostring(path), "\\", "/"))
		if string.StartsWith(p, "materials/") then p = string.sub(p, 11) end
		if t.userTex and string.StartsWith(p, "gwenskin/") then return Material(t.userTex, params) end
		local own = t.userRoot .. "materials/" .. p
		if file.Exists(own, "GAME") then return Material(own, params) end
		return Material(path, params)
	end

	local env = {
		Material = material,
		include = noop, AddCSLuaFile = noop, RunConsoleCommand = noop,
		print = noop, Msg = noop, MsgN = noop, MsgC = noop,
		-- "Default" for a theme is our copy of the stock skin (see UI.BaseSkin)
		derma = shallow(derma, { DefineSkin = onSkin, DefineControl = noop, GetNamedSkin = function(name)
			if name == "Default" then return UI.BaseSkin() end
			return derma.GetNamedSkin(name)
		end }),
		hook = shallow(hook, { Add = noop, Remove = noop }),
		concommand = shallow(concommand, { Add = noop }),
		vgui = shallow(vgui, { Register = noop }),
		surface = shallow(surface, { PlaySound = noop }),
		timer = shallow(timer, { Simple = noop, Create = noop }),
		file = shallow(file, { Write = noop, Append = noop, Delete = noop, CreateDir = noop }),
	}
	env._G = env
	-- the rest are the real globals; SKIN is written into the real _G (GWEN reads it)
	return setmetatable(env, { __index = _G, __newindex = _G })
end

local function warn(t, text)
	MsgC(Color(255, 120, 80), "[GM:FM] theme '", t.name, "': ", tostring(text), "\n")
end

---------------------------------------------------------------------
-- Editor palette from the skin texture
---------------------------------------------------------------------
-- points on the standard GWEN texture layout (512x512)
local function sample(mat, x, y)
	local ok, c = pcall(mat.GetColor, mat, x, y)
	if ok and c and c.r then return c end
end

local function over(top, bottom)
	local a = (top.a or 255) / 255
	return Color(math.Round(top.r * a + bottom.r * (1 - a)), math.Round(top.g * a + bottom.g * (1 - a)),
		math.Round(top.b * a + bottom.b * (1 - a)))
end

local function saturation(c)
	local hi, lo = math.max(c.r, c.g, c.b), math.min(c.r, c.g, c.b)
	return hi > 0 and (hi - lo) / hi or 0
end

local function paletteBase(skin)
	local mat = skin.GwenTexture
	if not mat or mat:IsError() then return nil end
	local win, panel = sample(mat, 64, 80), sample(mat, 288, 32)
	if not win or not panel or ((win.a or 0) < 40 and (panel.a or 0) < 40) then return nil end
	local bg = over(panel, over(win, Color(40, 40, 40)))

	-- accent: the most saturated of the selection colours
	local accent
	for _, pt in ipairs({ { 335, 271 }, { 399, 47 }, { 495, 47 }, { 32, 400 } }) do
		local c = sample(mat, pt[1], pt[2])
		if c and (c.a or 0) > 128 and saturation(c) > 0.25 and (not accent or saturation(c) > saturation(accent)) then
			accent = Color(c.r, c.g, c.b)
		end
	end

	local base = { bg = bg, accent = accent, sel = accent }
	local btn = sample(mat, 495, 15)
	if btn and (btn.a or 0) > 128 then base.ctrl = Color(btn.r, btn.g, btn.b) end

	-- the skin's text colour, if it is readable on the background
	local labels = skin.Colours and skin.Colours.Label
	for _, key in ipairs({ "Dark", "Bright", "Default" }) do
		local c = labels and labels[key]
		if c and c.r and util2.contrast(c, bg) >= 4.5 then
			base.text = Color(c.r, c.g, c.b)
			break
		end
	end
	return base
end

-- Include a theme skin from the themes folder. false — failed.
function UI.LoadUserSkin(t)
	local src = file.Read(t.userFile, "GAME")
	if not src then
		warn(t, "cannot read " .. t.userFile)
		return false
	end
	local fn = CompileString(src, t.userFile, false)
	if not isfunction(fn) then
		warn(t, fn)
		return false
	end

	local captured
	setfenv(fn, environment(t, function(_, _, skin)
		if captured or not istable(skin) then return end
		captured = skin
		derma.DefineSkin(t.skin, t.name, skin)
	end))
	local ok, err = pcall(fn)
	if not ok then warn(t, err) end
	if not captured then return false end

	t.base = paletteBase(captured)
	-- DProperties rows are white: a skin with light text needs a dark background
	local props = captured.Colours and captured.Colours.Properties
	local label = props and props.Label_Normal
	if t.base and label and label.r and util2.luminance(label) > 0.4 then
		t.propBG = util2.mix(t.base.bg, Color(0, 0, 0), 0.25)
	end
	return true
end

UI.ScanUserThemes()
-- the chosen theme may be from the themes folder: it gets its palette when the editor opens
