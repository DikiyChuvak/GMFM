--[[
GM:FM — the Environment window (b0.2 round 6): the lighting of the whole map (cl_env.lua,
sv_env.lua). Windows → Environment. Four parts:
  Sun          the sun with cascaded shadows over the whole map, its direction, colour, power
  Ambient      the brightness of the map's baked light
  Sky          the skybox texture and the painted sky (its colours, the sun disc, the stars)
  Fog          the fog of the world and of the 3D skybox
Everything is saved with the scene; "Back to the map" undoes it.
]]
local UI = SPeditor.UI
local C = SPeditor.Client
local Env = SPeditor.Env
local Dock = SPeditor.Dock
local L = SPeditor.L
local COL = UI.PAL

-- the painted sky's fields (env_skypaint) and how the window shows them
local PAINT_COLORS = { "TopColor", "BottomColor", "DuskColor", "SunColor" }
local PAINT_SLIDERS = {
	{ "FadeBias", 0, 1, 2 }, { "HDRScale", 0, 1, 2 }, { "DuskIntensity", 0, 4, 2 }, { "DuskScale", 0, 1, 2 },
	{ "SunSize", 0, 10, 2 }, { "StarScale", 0, 5, 2 }, { "StarFade", 0, 5, 2 },
}

-- the painted sky as the map has it now (the entity is networked)
local function mapPaint()
	local e = ents.FindByClass("env_skypaint")[1]
	if not IsValid(e) then return nil end
	local t = {}
	for _, k in ipairs(PAINT_COLORS) do if e["Get" .. k] then t[k] = e["Get" .. k](e) end end
	for _, s in ipairs(PAINT_SLIDERS) do if e["Get" .. s[1]] then t[s[1]] = e["Get" .. s[1]](e) end end
	if e.GetDrawStars then t.DrawStars = e:GetDrawStars() end
	return t
end

local function paintNow()
	if not Env.cur.sky.paint then Env.cur.sky.paint = mapPaint() or {} end
	return Env.cur.sky.paint
end

local function skyboxes()
	local out, seen = {}, {}
	for _, f in ipairs(file.Find("materials/skybox/*.vmt", "GAME") or {}) do
		local name = string.match(string.lower(f), "^(.+)up%.vmt$")
		if name and not seen[name] then
			seen[name] = true
			out[#out + 1] = name
		end
	end
	table.sort(out)
	table.insert(out, 1, "painted")
	return out
end

-- a row with a colour swatch: a click opens the colour picker
local function colorRow(parent, label, get, set)
	local row = vgui.Create("DPanel", parent)
	row:Dock(TOP)
	row:DockMargin(4, 2, 4, 2)
	row:SetTall(UI.S(22))
	row.Paint = function() end
	local lbl = vgui.Create("DLabel", row)
	lbl:Dock(LEFT)
	lbl:SetWide(UI.S(150))
	lbl:SetFont("SPeditor.Small")
	lbl:SetTextColor(COL.TEXT)
	lbl:SetText(label)
	local b = vgui.Create("DButton", row)
	b:Dock(FILL)
	b:SetText("")
	b.Paint = function(s, w, h)
		local c = get() or color_white
		surface.SetDrawColor(c.r, c.g, c.b, 255)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(s:IsHovered() and COL.ORANGE or COL.BORDER)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	b.DoClick = function() UI.OpenColorPopup(label, get() or color_white, set) end
	return row
end

local function vecToColor(v) return v and Color(math.Clamp(v.x * 255, 0, 255), math.Clamp(v.y * 255, 0, 255), math.Clamp(v.z * 255, 0, 255)) end
local function colorToVec(c) return Vector(c.r / 255, c.g / 255, c.b / 255) end

-- an explanation under a section header: wrapped over as many lines as it needs
local function note(parent, text)
	local l = UI.Label(parent, text)
	l:SetWrap(true)
	l:SetAutoStretchVertical(true)
	l:DockMargin(6, 2, 6, 4)
	return l
end

local function build(body)
	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	local syncing = false
	local controls = {}

	local function slider(parent, label, min, max, dec, path, get)
		local s = UI.Slider(parent, label, min, max, dec, get(), function(v)
			if not syncing then Env.Set(path, v) end
		end)
		controls[#controls + 1] = function() s:SetValue(get()) end
		return s
	end
	local function check(parent, label, path, get)
		local c = UI.Check(parent, label, get(), function(v)
			if not syncing then Env.Set(path, v and true or false) end
		end)
		controls[#controls + 1] = function() c:SetChecked(get() and true or false) end
		return c
	end

	-------------------------------------------------------------------
	-- Sun
	-------------------------------------------------------------------
	local sun = UI.Section(scroll, L("env_sun"))
	note(sun, L("env_sun_note"))
	check(sun, L("env_sun_on"), "sun.on", function() return Env.cur.sun.on end)
	check(sun, L("env_sun_mapdir"), "sun.mapDir", function() return Env.cur.sun.mapDir end)
	local function dirSlider(label, key, min, max)
		local s = UI.Slider(sun, label, min, max, 0, Env.cur.sun[key], function(v)
			if syncing then return end
			-- moving the sun by hand: it no longer follows the map's
			if Env.cur.sun.mapDir then
				local p, y = Env.DirAngles(Env.MapSunDir())
				Env.cur.sun.pitch, Env.cur.sun.yaw = p, y
				Env.Set("sun.mapDir", false)
			end
			Env.Set("sun." .. key, v)
		end)
		controls[#controls + 1] = function()
			local p, y = Env.cur.sun.pitch, Env.cur.sun.yaw
			if Env.cur.sun.mapDir then p, y = Env.DirAngles(Env.MapSunDir()) end
			s:SetValue(key == "pitch" and p or y)
		end
	end
	dirSlider(L("env_sun_pitch"), "pitch", 1, 90)
	dirSlider(L("env_sun_yaw"), "yaw", 0, 360)
	colorRow(sun, L("env_sun_color"), function() return Env.cur.sun.color end, function(c) Env.Set("sun.color", c) end)
	slider(sun, L("env_sun_bright"), 0, 10, 2, "sun.bright", function() return Env.cur.sun.bright end)
	slider(sun, L("env_sun_soft"), 0, 4, 2, "sun.soft", function() return Env.cur.sun.soft end)
	slider(sun, L("env_sun_cascades"), 1, 3, 0, "sun.cascades", function() return Env.cur.sun.cascades end):SetTooltip(L("env_sun_cascades_tip"))
	slider(sun, L("env_sun_reach"), 0.25, 8, 2, "sun.reach", function() return Env.cur.sun.reach end):SetTooltip(L("env_sun_reach_tip"))
	local static = check(sun, L("env_sun_static_off"), "sun.staticSun", function() return Env.cur.sun.staticSun == false end)
	-- the box reads "turn the baked sun off": checked = staticSun false
	static.OnChange = function(_, v) if not syncing then Env.Set("sun.staticSun", not v) end end
	local staticNote = note(sun, "")
	controls[#controls + 1] = function()
		static:SetEnabled(Env.info.hasLightEnv)
		staticNote:SetText(Env.info.hasLightEnv and "" or L("env_sun_static_none"))
		staticNote:SetVisible(not Env.info.hasLightEnv)
	end

	-------------------------------------------------------------------
	-- Ambient
	-------------------------------------------------------------------
	local amb = UI.Section(scroll, L("env_ambient"))
	note(amb, L("env_ambient_note"))
	slider(amb, L("env_ambient_level"), 1, 26, 0, "ambient", function() return Env.cur.ambient end)

	-------------------------------------------------------------------
	-- Sky
	-------------------------------------------------------------------
	local sky = UI.Section(scroll, L("env_sky"))
	local combo = UI.StyleCombo(vgui.Create("DComboBox", sky))
	combo:Dock(TOP)
	combo:DockMargin(4, 2, 4, 2)
	combo:SetTall(UI.S(22))
	combo:SetSortItems(false)
	local function fillSky()
		combo:Clear()
		local cur = Env.cur.sky.name or Env.info.sky or GetConVarString("sv_skyname")
		for _, n in ipairs(skyboxes()) do combo:AddChoice(n == "painted" and L("env_sky_painted") or n, n, n == cur) end
	end
	fillSky()
	combo.OnSelect = function(_, _, _, name) if not syncing then Env.Set("sky.name", name) end end
	controls[#controls + 1] = fillSky
	note(sky, L("env_sky_paint_note"))
	for _, k in ipairs(PAINT_COLORS) do
		colorRow(sky, L("env_paint_" .. k), function() return vecToColor(paintNow()[k]) end, function(c)
			paintNow()[k] = colorToVec(c)
			Env.Set("sky.paint", Env.cur.sky.paint)
		end)
	end
	for _, d in ipairs(PAINT_SLIDERS) do
		local k = d[1]
		local s = UI.Slider(sky, L("env_paint_" .. k), d[2], d[3], d[4], paintNow()[k] or 0, function(v)
			if syncing then return end
			paintNow()[k] = v
			Env.Set("sky.paint", Env.cur.sky.paint)
		end)
		controls[#controls + 1] = function() s:SetValue(paintNow()[k] or 0) end
	end
	local stars = UI.Check(sky, L("env_paint_DrawStars"), paintNow().DrawStars, function(v)
		if syncing then return end
		paintNow().DrawStars = v and true or false
		Env.Set("sky.paint", Env.cur.sky.paint)
	end)
	controls[#controls + 1] = function() stars:SetChecked(paintNow().DrawStars and true or false) end

	-------------------------------------------------------------------
	-- Fog
	-------------------------------------------------------------------
	local fog = UI.Section(scroll, L("env_fog"))
	check(fog, L("env_fog_on"), "fog.on", function() return Env.cur.fog.on end)
	slider(fog, L("env_fog_start"), 0, 20000, 0, "fog.start", function() return Env.cur.fog.start end)
	slider(fog, L("env_fog_end"), 1, 60000, 0, "fog.finish", function() return Env.cur.fog.finish end)
	slider(fog, L("env_fog_density"), 0, 1, 2, "fog.density", function() return Env.cur.fog.density end)
	colorRow(fog, L("env_fog_color"), function() return Env.cur.fog.color end, function(c) Env.Set("fog.color", c) end)
	check(fog, L("env_fog_sky"), "fog.sky", function() return Env.cur.fog.sky end)

	-------------------------------------------------------------------
	-- Sound of the map (b0.2.3)
	-------------------------------------------------------------------
	local snd = UI.Section(scroll, L("env_sound"))
	local mute = check(snd, L("env_mute_map"), "mapSounds", function() return Env.cur.mapSounds == false end)
	-- the box reads "mute": checked = mapSounds false
	mute.OnChange = function(_, v) if not syncing then Env.Set("mapSounds", not v) end end
	note(snd, L("env_mute_map_note"))

	local reset = UI.Button(scroll, L("env_reset"), "icon16/arrow_undo.png", function()
		Derma_Query(L("env_reset_q"), L("env_title"), L("yes"), function() Env.Reset() end, L("cancel"))
	end, 24)
	reset:DockMargin(4, 8, 4, 8)

	local function sync()
		syncing = true
		for _, fn in ipairs(controls) do pcall(fn) end
		syncing = false
	end
	sync()
	SPeditor.Hook("GMFM_EnvChanged", body, function(path)
		-- a whole new state (a scene, a reset): every control reads it again
		if path == "scene" or path == "reset" or path == "sun.mapDir" then sync() end
	end)
	SPeditor.Hook("GMFM_EnvInfo", body, sync)
	Env.RequestInfo()
end

function UI.OpenEnvironment()
	if Dock.ShowPage("environment") then return end
	local W, H = UI.S(420), math.min(UI.S(720), ScrH() - 140)
	local win = Dock.NewWindow({ key = "env_win", w = W, h = H, x = ScrW() - W - 60, y = 90, dockable = false })
	win.minW, win.minH = UI.S(320), UI.S(300)
	win:AddCloseButton()
	local body = vgui.Create("DPanel")
	body.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
	end
	win:AddPage("environment", L("env_title"), body, "icon16/weather_sun.png")
	build(body)
	win.SPState = function() return true end
end
