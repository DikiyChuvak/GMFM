--[[
GM:FM gamemode, the client's part (sh_gamemode.lua). In the gamemode:
  * the editor opens by itself once the player is in the game, and comes back by itself when
    something left it (the console, another addon) — only the player, a walk around the scene
    (gmfm_show) and a gameplay take keep it closed for their time;
  * a start window after joining, after Source Filmmaker's welcome: a new scene, a saved one,
    a gameplay take, another map, How to use (File → Start window… opens it again);
  * Change map… (the top bar and File) instead of Exit Editor: a list of the installed maps
    with their pictures.
]]
if not SPeditor.FilmMode() then return end

local C  = SPeditor.Client
local UI = SPeditor.UI
local L  = SPeditor.L

local cvStart = CreateClientConVar("gmfm_mode_start", "1", true, false, "GM:FM gamemode: show the start window after joining")

local function SA()
	local comp = SPeditor.Component and SPeditor.Component("saeditor")
	return comp and comp.SA or {}
end

-- the editor is away on purpose: the player / a walk around the scene, a gameplay take (with its
-- countdown), the show about to start
local function away()
	local sa = SA()
	return sa.show ~= nil or sa.showPending ~= nil or sa.rec ~= nil
end

---------------------------------------------------------------------
-- The editor is always open
---------------------------------------------------------------------
local joined, nextTry = false, 0
SPeditor.Hook("Think", "GMFM.ModeOpen", function()
	if C.active or RealTime() < nextTry then return end
	local ply = LocalPlayer()
	if not IsValid(ply) or not (UI and UI.Open) then return end
	if joined and away() then return end
	-- left on purpose with Shift + F4: it waits for gmfm_toggle
	if C.forcedOut then return end
	-- a guest of a server without the editor (gmfm_access): it watches and plays, it is not asked again
	if ply:GetNW2Bool("SPeditor_Denied", false) then return end
	nextTry = RealTime() + 1.5
	joined = true
	C.SendToggle(true)
end)

-- gmfm_toggle only opens it here
concommand.Add("gmfm_toggle", function()
	if C.active then
		SPeditor.Notify(L("mode_no_exit"), 0)
	else
		C.forcedOut = nil
		C.SendToggle(true)
	end
end)

local shown = false
SPeditor.Hook("SPeditor_StateChanged", "GMFM.ModeStart", function(on)
	if not on or shown then return end
	shown = true
	if cvStart:GetBool() then timer.Simple(0.4, function() if C.active then UI.OpenModeStart() end end) end
end)

---------------------------------------------------------------------
-- Fonts and a picture of the map
---------------------------------------------------------------------
surface.CreateFont("GMFM.ModeLogo", { font = "Verdana", size = 44, weight = 800, antialias = true, extended = true })
surface.CreateFont("GMFM.ModeSub", { font = "Verdana", size = 15, weight = 500, antialias = true, extended = true })
surface.CreateFont("GMFM.ModeHead", { font = "Verdana", size = 13, weight = 700, antialias = true, extended = true })

local thumbs = {}
local function mapThumb(map)
	if thumbs[map] == nil then
		thumbs[map] = false
		-- garrysmod/maps/thumb (Material() takes the path from the game's root for a .png)
		for _, path in ipairs({ "maps/thumb/" .. map .. ".png", "maps/" .. map .. ".png" }) do
			if file.Exists(path, "GAME") then
				local m = Material(path, "smooth")
				if m and not m:IsError() then thumbs[map] = m break end
			end
		end
	end
	return thumbs[map] or nil
end

local brandGarrys = Material("speditor/brand/garrysmod.png", "smooth")
local brandFilm   = Material("speditor/brand/filmmaker.png", "smooth")
local brandIcon   = Material("speditor/icon128.png", "smooth")

-- the background of the start window: Garry's Mod's blue picture
local banner
local function bannerMat()
	if banner == nil then
		local m = Material("speditor/brand/start_bg.jpg", "smooth")
		banner = (m and not m:IsError()) and m or false
	end
	return banner or nil
end

-- a picture drawn to cover w x h (cropped, not stretched)
local function drawCover(mat, x, y, w, h)
	local tex = mat:GetTexture("$basetexture")
	local tw, th = tex and tex:Width() or 16, tex and tex:Height() or 9
	local k = math.max(w / tw, h / th)
	local uw, vh = w / (tw * k), h / (th * k)
	local u0, v0 = (1 - uw) / 2, (1 - vh) / 2
	surface.SetMaterial(mat)
	surface.SetDrawColor(255, 255, 255, 255)
	surface.DrawTexturedRectUV(x, y, w, h, u0, v0, u0 + uw, v0 + vh)
end

---------------------------------------------------------------------
-- The start window
---------------------------------------------------------------------
function UI.OpenModeStart()
	local Dock = SPeditor.Dock
	local COL = UI.PAL
	local old = Dock.ByKey("gmfm_start")
	if old then old:Remove() end
	local W, H = math.min(820, ScrW() - 80), math.min(520, ScrH() - 120)
	local win, body = Dock.Create({ key = "gmfm_start", id = "gmfm_start", title = L("mode_start"),
		w = W, h = H, x = math.floor(ScrW() / 2 - W / 2), y = math.floor(ScrH() / 2 - H / 2), dockable = false,
		icon = "icon16/application_home.png" })
	win.minW, win.minH = UI.S(560), UI.S(380)
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.gmfm_start = nil
	end

	-- left: the name, the version, the map, over Garry's Mod's blue picture
	local left = vgui.Create("DPanel", body)
	left:Dock(LEFT)
	left:SetWide(UI.S(300))
	left.Paint = function(_, w, h)
		surface.SetDrawColor(20, 20, 22, 255)
		surface.DrawRect(0, 0, w, h)
		local m = bannerMat()
		if m then drawCover(m, 0, 0, w, h) end
		-- darker towards the text
		-- darker under the name (as tall as the lettering and the version)
		-- the reel icon on the left, the name beside it
		local ic = math.floor(math.min(w * 0.26, 84))
		local tx = 16 + ic + 10
		local k = (w - tx - 16) / brandGarrys:GetTexture("$basetexture"):Width()
		local nameH = (brandGarrys:GetTexture("$basetexture"):Height() + brandFilm:GetTexture("$basetexture"):Height()) * k + 2
		surface.SetDrawColor(0, 0, 0, 120)
		surface.DrawRect(0, 0, w, 14 + math.max(nameH, ic) + 30)
		surface.SetDrawColor(0, 0, 0, 120)
		surface.DrawRect(0, h - 70, w, 70)
		-- the name in its own lettering (materials/speditor/brand), one letter size for both words
		local y = 14 + math.max(0, math.floor((ic - nameH) / 2))
		surface.SetDrawColor(255, 255, 255, 255)
		surface.SetMaterial(brandIcon)
		surface.DrawTexturedRect(16, 14 + math.max(0, math.floor((nameH - ic) / 2)), ic, ic)
		for _, m in ipairs({ brandGarrys, brandFilm }) do
			local tex = m:GetTexture("$basetexture")
			local bw, bh = tex:Width() * k, tex:Height() * k
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(m)
			surface.DrawTexturedRect(tx, y, bw, bh)
			y = y + bh + 2
		end
		y = math.max(y, 14 + ic)
		draw.SimpleText(L("about_version") .. " " .. (SPeditor.Version or ""), "GMFM.ModeSub", 20, y + 4, Color(200, 200, 200))
		draw.SimpleText(L("mode_map"), "GMFM.ModeHead", 20, h - 58, Color(200, 200, 200))
		draw.SimpleText(game.GetMap(), "GMFM.ModeSub", 20, h - 38, color_white)
	end

	local right = vgui.Create("DPanel", body)
	right:Dock(FILL)
	right:DockPadding(UI.S(12), UI.S(10), UI.S(12), UI.S(8))
	right.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
	end

	local function head(text)
		local l = UI.Label(right, text, COL.ORANGE)
		l:SetFont("SPeditor.Bold")
		l:DockMargin(0, 6, 0, 4)
		return l
	end
	local function big(text, icon, fn)
		local b = UI.Button(right, text, icon, function()
			win:Remove()
			fn()
		end, 30)
		b:DockMargin(0, 2, 0, 2)
		return b
	end

	head(L("mode_start_begin"))
	big(L("mode_continue"), "icon16/film_edit.png", function() end)
	big(L("mode_new"), "icon16/page_white.png", function()
		local sa = SA()
		if #C.Objects() == 0 and not (sa.RecNPCList and #sa.RecNPCList() > 0) then return end
		Derma_Query(L("clear_confirm"), "GM:FM", L("yes"), function() C.ClearScene() end, L("cancel"), function() end)
	end)
	big(L("mode_record"), "icon16/webcam.png", function()
		local sa = SA()
		if sa.OpenRecord then sa.OpenRecord() end
	end)
	big(L("mode_change_map") .. "…", "icon16/world.png", function() UI.OpenMapPicker() end)

	head(L("mode_scenes"))
	local list = vgui.Create("DListView", right)
	list:Dock(FILL)
	list:SetMultiSelect(false)
	list:AddColumn(L("tab_scene"))
	UI.Skin(list)
	local function fill()
		if not IsValid(list) then return end
		list:Clear()
		for _, name in ipairs(C.sceneList or {}) do list:AddLine(name) end
	end
	SPeditor.Hook("SPeditor_SceneList", "GMFM.ModeStart", fill)
	fill()
	C.SceneRequestList()
	local function open(name)
		if not name then SPeditor.Notify(L("select_scene_first"), 0) return end
		win:Remove()
		C.SceneLoad(name)
	end
	list.DoDoubleClick = function(_, _, line) open(line:GetColumnText(1)) end

	local foot = vgui.Create("DPanel", right)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(30))
	foot:DockMargin(0, 6, 0, 0)
	foot.Paint = function() end
	local again = UI.Check(foot, L("mode_start_show"), cvStart:GetBool(), function(v) RunConsoleCommand("gmfm_mode_start", v and "1" or "0") end)
	again:Dock(LEFT)
	again:SetWide(UI.S(230))
	local help = UI.Button(foot, L("mode_help"), "icon16/help.png", function()
		win:Remove()
		UI.OpenGuide("interface")
	end)
	help:Dock(RIGHT)
	help:SetWide(UI.S(140))
	local load = UI.Button(foot, L("load"), "icon16/folder_go.png", function()
		local line = list:GetSelectedLine() and list:GetLine(list:GetSelectedLine())
		open(line and line:GetColumnText(1) or nil)
	end)
	load:Dock(RIGHT)
	load:SetWide(UI.S(120))
	load:DockMargin(0, 0, 6, 0)
	UI.StyleButton(load, true)
	return win
end

---------------------------------------------------------------------
-- Another map
---------------------------------------------------------------------
local HIDDEN_MAPS = { "^background", "^devtest", "^test_", "^styleguide", "^credits", "^intro", "^ep1_c17_0", "^d1_trainstation_01" }

local function mapList()
	local out = {}
	for _, f in ipairs(file.Find("maps/*.bsp", "GAME") or {}) do
		local name = string.StripExtension(f)
		local skip = false
		for _, p in ipairs(HIDDEN_MAPS) do
			if string.find(name, p) then skip = true break end
		end
		if not skip then out[#out + 1] = name end
	end
	-- Garry's Mod's own maps (gm_) first, then the rest by name
	table.sort(out, function(a, b)
		local ga, gb = string.StartWith(a, "gm_"), string.StartWith(b, "gm_")
		if ga ~= gb then return ga end
		return a < b
	end)
	return out
end

local function changeMap(map)
	Derma_Query(string.format(L("mode_map_confirm"), map), "GM:FM", L("mode_map_go"), function()
		net.Start(SPeditor.Net.ChangeMap)
		net.WriteString(map)
		net.SendToServer()
	end, L("cancel"), function() end)
end

function UI.OpenMapPicker()
	local Dock = SPeditor.Dock
	local COL = UI.PAL
	local old = Dock.ByKey("gmfm_maps")
	if old then old:Remove() end
	local W, H = math.min(860, ScrW() - 80), math.min(620, ScrH() - 120)
	local win, body = Dock.Create({ key = "gmfm_maps", id = "gmfm_maps", title = L("mode_change_map"),
		w = W, h = H, x = math.floor(ScrW() / 2 - W / 2), y = 70, dockable = false, icon = "icon16/world.png" })
	win.minW, win.minH = UI.S(480), UI.S(360)
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.gmfm_maps = nil
	end

	local top = vgui.Create("DPanel", body)
	top:Dock(TOP)
	top:DockMargin(8, 8, 8, 4)
	top:SetTall(UI.S(24))
	top.Paint = function() end
	local search = vgui.Create("DTextEntry", top)
	search:Dock(FILL)
	search:SetPlaceholderText(L("mode_map_search"))
	search:SetUpdateOnType(true)

	local note = UI.Label(body, L("mode_map_note"), COL.DIM)
	note:SetWrap(true)
	note:SetAutoStretchVertical(true)
	note:DockMargin(8, 0, 8, 4)

	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	scroll:DockMargin(8, 0, 8, 8)
	local grid = vgui.Create("DIconLayout", scroll)
	grid:Dock(TOP)
	grid:SetSpaceX(6)
	grid:SetSpaceY(6)

	local maps = mapList()
	local cur = game.GetMap()
	local function rebuild()
		grid:Clear()
		local q = string.lower(search:GetValue() or "")
		for _, map in ipairs(maps) do
			if q == "" or string.find(map, q, 1, true) then
				local t = grid:Add("DButton")
				t:SetSize(UI.S(132), UI.S(150))
				t:SetText("")
				t:SetTooltip(map)
				t.Paint = function(s, w, h)
					surface.SetDrawColor(s:IsHovered() and COL.ROW_B or COL.HEADER)
					surface.DrawRect(0, 0, w, h)
					local m = mapThumb(map)
					local isz = w - 8
					if m then
						surface.SetDrawColor(255, 255, 255, 255)
						surface.SetMaterial(m)
						surface.DrawTexturedRect(4, 4, isz, isz)
					else
						surface.SetDrawColor(COL.VIEW_BG or COL.BG)
						surface.DrawRect(4, 4, isz, isz)
						draw.SimpleText("?", "GMFM.ModeLogo", w / 2, 4 + isz / 2, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					end
					draw.SimpleText(map, "SPeditor.Small", w / 2, h - 11, map == cur and COL.ORANGE or COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
					surface.SetDrawColor(map == cur and COL.ORANGE or COL.BORDER)
					surface.DrawOutlinedRect(0, 0, w, h, map == cur and 2 or 1)
				end
				t.DoClick = function() changeMap(map) end
			end
		end
		grid:Layout()
	end
	search.OnValueChange = rebuild
	rebuild()
	return win
end

concommand.Add("gmfm_mode_startwindow", function() UI.OpenModeStart() end)
concommand.Add("gmfm_mode_maps", function() UI.OpenMapPicker() end)
