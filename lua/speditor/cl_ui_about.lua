--[[
SPeditor — the About and Camera settings windows (Help menu).

About: a 128x128 icon, name, version, GitHub link, addon description
(the window tab and the menu item use the stock GMod "information" icon, icon16/information.png)
and (at the very bottom) links to the pages of the bundled skins.
  * icon: materials/speditor/icon128.png (if the file is missing, a placeholder is drawn);
    icon16 / icon32 / icon64 live there too — for the Q menu tab, the window title and menus;
  * link: SPeditor.GitHub in sh_config.lua (the full source code, MIT); empty — a caption instead.
The windows are built from the same widgets and palette as the whole editor (UI.PAL),
so they look SFM-like and change with the interface theme.

Camera settings: keyboard flight speed, wheel step and smoothness, FOV of the
work camera. The values are kept in gmfm_cam_* (cl_camera.lua).
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI   = SPeditor.UI
local C    = SPeditor.Client
local L    = SPeditor.L
local Dock = SPeditor.Dock
local COL  = UI.PAL

surface.CreateFont("SPeditor.Title", { font = "Tahoma", size = 34, weight = 800, antialias = true })

-- Skins bundled with the editor as themes: their authors' pages in the Steam Workshop
local WORKSHOP = "https://steamcommunity.com/sharedfiles/filedetails/?id="
local SKIN_LINKS = {
	{ name = "EcoUI",                 author = "ELuminumG24",       id = "3255386124" },
	{ name = "Dark UI Spawnmenu",     author = "AquaRex",           id = "888392108" },
	{ name = "Steam 2004 Derma Skin", author = "Maks1mDiamond",     id = "3321557660" },
	{ name = "GMod98 UI Skin",        author = "AwesomeGraczGie21", id = "2972603323" },
	{ name = "OneShot - UI Skin",     author = "Flarky",            id = "3659339920" },
	{ name = "Lambda UI",             author = "晦涩弗里曼",          id = "2927713362" },
	{ name = "Vanilla UI+ Derma Skin", author = "Qude",                id = "3818111525" },
	{ name = "Windows XP Classic UI & HUD (GMod XP)", author = "w4da", id = "3816955790" },
	{ name = "HL2 Media Player Skin Inspired Spawnmenu (HL2 Media Player)", author = "GhostSynth", id = "3263951771" },
	{ name = "Aero Blur Spawnmenu Skin - Dark (Aero Blur)", author = "Luigi", id = "2919822758" },
	{ name = "Garry's Mod Classic UI Spawnmenu (GMod Classic)", author = "Bon Bon 3016", id = "3379423670" },
	-- sounds of the notification sound sets (sound/speditor/notify)
	{ name = "Half Life UI Sounds",    author = "ВРАТАРb_DINAMO",      id = "2790356494" },
	{ name = "Windows XPerience UI Sounds", author = "Jade",           id = "2979067313" },
	-- a set made by the author of SPeditor from the sounds of Windows 7 — an example of a pack
	-- that does not come from the Workshop (shown when sound/speditor/notify/aero7ui is there;
	-- give it an id when the pack has a Workshop page of its own)
	{ name = "Aero7UI (Windows 7 sounds)", author = "DikiyChuvak",   pack = "aero7ui" },
}

-- a sound pack of the list is in the addon (the folder name may be written in any case)
local function packPresent(name)
	local _, dirs = file.Find("sound/speditor/notify/*", "GAME")
	for _, d in ipairs(dirs or {}) do
		if string.lower(d) == string.lower(name) then return true end
	end
	return false
end

local ICON_PATH = "speditor/icon128.png"
local ICON_SIZE = 128

---------------------------------------------------------------------
-- About
---------------------------------------------------------------------
local function text(parent, str, col, font, top)
	local l = vgui.Create("DLabel", parent)
	l:Dock(TOP)
	l:DockMargin(12, top or 2, 12, 0)
	l:SetFont(font or "SPeditor.Small")
	l:SetTextColor(col or COL.TEXT)
	l:SetWrap(true)
	l:SetAutoStretchVertical(true)
	l:SetText(str)
	return l
end

function UI.OpenAbout()
	if Dock.ShowPage("about") then return end
	local W, H = 620, 680
	local win, body = Dock.Create({ key = "about", id = "about", title = L("about_title"), w = W, h = math.min(H, ScrH() - 160),
			x = math.floor(ScrW() / 2 - W / 2), y = 110, dockable = false, icon = "icon16/information.png" })
	win.minW, win.minH = UI.S(420), UI.S(320)

	local icon
	if file.Exists("materials/" .. ICON_PATH, "GAME") then
		icon = Material(ICON_PATH, "smooth")
		if icon:IsError() then icon = nil end
	end
	local github = SPeditor.GitHub or ""

	-- header: icon, name, version
	local head = vgui.Create("DPanel", body)
	head:Dock(TOP)
	head:SetTall(UI.S(ICON_SIZE + 24))
	head.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(0, h - 1, w, 1)

		local x, y = 12, 12
		if icon then
			surface.SetMaterial(icon)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawTexturedRect(x, y, ICON_SIZE, ICON_SIZE)
		else
			-- placeholder while there is no icon
			surface.SetDrawColor(COL.LIST_BG)
			surface.DrawRect(x, y, ICON_SIZE, ICON_SIZE)
			draw.SimpleText("FM", "SPeditor.Title", x + ICON_SIZE / 2, y + ICON_SIZE / 2, COL.ORANGE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		surface.SetDrawColor(COL.BORDER)
		surface.DrawOutlinedRect(x, y, ICON_SIZE, ICON_SIZE, 1)

		local tx = x + ICON_SIZE + 16
		draw.SimpleText("GM:FM", "SPeditor.Title", tx, 14, COL.TEXT)
		draw.SimpleText(L("about_version") .. " " .. (SPeditor.Version or "?"), "SPeditor.Time", tx, 56, COL.ORANGE)
		draw.SimpleText(L("about_tagline"), "SPeditor.Small", tx, 86, COL.DIM)
		if github == "" then
			draw.SimpleText("GitHub: " .. L("about_soon"), "SPeditor.Small", tx, 112, COL.DIM)
		end
	end

	if github ~= "" then
		local link = vgui.Create("DButton", head)
		link:SetPos(12 + ICON_SIZE + 16, 106)
		link:SetText("GitHub")
		link:SetIcon("icon16/world_link.png")
		link:SetTooltip(github)
		UI.StyleButton(link)
		link:SetSize(UI.S(110), UI.S(22))
		link.DoClick = function() gui.OpenURL(github) end
	end

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(34))
	foot.Paint = function() end
	local close = vgui.Create("DButton", foot)
	close:Dock(RIGHT)
	close:DockMargin(4, 5, 8, 5)
	close:SetWide(UI.S(110))
	close:SetText(L("about_close"))
	UI.StyleButton(close, nil, 3)
	close.DoClick = function() win:Close() end

	-- description
	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	scroll.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
	end

	local function bullets(prefix)
		for i = 1, 40 do
			local key = prefix .. i
			local str = L(key)
			if str == key then break end
			text(scroll, "•  " .. str, COL.TEXT, nil, 4)
		end
	end

	text(scroll, L("about_intro"), COL.TEXT, nil, 10)
	-- what changed: a patch (about_p1, about_p2, …) above the release it builds on (about_n1, …)
	local base = SPeditor.VersionBase or SPeditor.Version or ""
	-- a second patch on the same release (b0.2.2): its own news first, then the patch before
	local prev = SPeditor.VersionPrev
	if prev and prev ~= SPeditor.Version and L("about_u1") ~= "about_u1" then
		text(scroll, string.format(L("about_news"), SPeditor.Version), COL.ORANGE, "SPeditor.Bold", 12)
		bullets("about_u")
	end
	if base ~= SPeditor.Version and L("about_p1") ~= "about_p1" then
		text(scroll, string.format(L("about_news"), prev or SPeditor.Version), COL.ORANGE, "SPeditor.Bold", 12)
		bullets("about_p")
	end
	text(scroll, string.format(L("about_news"), base), COL.ORANGE, "SPeditor.Bold", 12)
	bullets("about_n")
	text(scroll, L("about_features"), COL.ORANGE, "SPeditor.Bold", 12)
	bullets("about_f")
	text(scroll, L("about_usage"), COL.ORANGE, "SPeditor.Bold", 12)
	text(scroll, L("about_usage_text"), COL.TEXT, nil, 4)
	text(scroll, L("about_credits"), COL.ORANGE, "SPeditor.Bold", 12)
	text(scroll, L("about_credits_text"), COL.DIM, nil, 4)

	-- at the very bottom: interface skins bundled with the editor, with links to their pages
	text(scroll, L("about_skins"), COL.ORANGE, "SPeditor.Bold", 12)
	local links = {}
	for _, s in ipairs(SKIN_LINKS) do
		if not s.pack or packPresent(s.pack) then links[#links + 1] = s end
	end
	for _, s in ipairs(links) do
		local url = s.id and (WORKSHOP .. s.id) or nil
		local b = vgui.Create("DButton", scroll)
		b:Dock(TOP)
		b:DockMargin(12, 3, 12, 0)
		b:SetTall(UI.S(32))
		b:SetText("")
		if url then b:SetTooltip(L("about_link_hint")) end
		b.Paint = function(self, w, h)
			surface.SetDrawColor(self:IsHovered() and COL.ROW_A or COL.ROW_B)
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(s.name .. "  —  " .. s.author, "SPeditor.Small", 8, 9, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			if url then
				draw.SimpleText(url, "SPeditor.Small", 8, 23, self:IsHovered() and COL.ORANGE or COL.BLUE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
		end
		b.DoClick = function() if url then gui.OpenURL(url) end end
		b.DoRightClick = function() if url then SetClipboardText(url) end end
	end
	local pad = vgui.Create("DPanel", scroll)
	pad:Dock(TOP)
	pad:SetTall(UI.S(12))
	pad.Paint = function() end
end

---------------------------------------------------------------------
-- Where the files are (Help → Where are my files): scenes, renders, poses… all live in
-- garrysmod/data/speditor, and the game cannot open a folder by itself — so the window
-- shows the paths and copies them.
---------------------------------------------------------------------
function UI.OpenFileLocations()
	if Dock.ShowPage("fileloc") then return end
	local W = 560
	local win, body = Dock.Create({ key = "fileloc", id = "fileloc", title = L("files_title"), w = W, h = 400,
			x = math.floor(ScrW() / 2 - W / 2), y = 140, dockable = false, icon = "icon16/folder_explore.png" })
	win.minW, win.minH = UI.S(420), UI.S(300)

	local root = "garrysmod/data/" .. (SPeditor.Config.SaveDir or "speditor") .. "/"
	local sid = (IsValid(LocalPlayer()) and LocalPlayer():SteamID64()) or "local"
	local rows = {
		{ "files_scenes",  root .. "scenes/" .. sid .. "/" },
		{ "files_renders", root .. "renders/" },
		{ "files_poses",   root .. "poses/" },
		{ "files_layouts", root .. "layouts/" },
		{ "files_sounds",  root .. "sounds/" },
	}

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(34))
	foot.Paint = function() end
	local close = vgui.Create("DButton", foot)
	close:Dock(RIGHT)
	close:DockMargin(4, 5, 8, 5)
	close:SetWide(UI.S(110))
	close:SetText(L("about_close"))
	UI.StyleButton(close, nil, 3)
	close.DoClick = function() win:Close() end

	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	scroll.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
	end
	text(scroll, L("files_hint"), COL.TEXT, nil, 10)
	for _, r in ipairs(rows) do
		local row = vgui.Create("DPanel", scroll)
		row:Dock(TOP)
		row:DockMargin(12, 6, 12, 0)
		row:SetTall(UI.S(38))
		row.Paint = function(_, w, h)
			surface.SetDrawColor(COL.ROW_B)
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(L(r[1]), "SPeditor.Small", 8, 10, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			draw.SimpleText(r[2], "SPeditor.Small", 8, 27, COL.BLUE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		local copy = vgui.Create("DButton", row)
		copy:Dock(RIGHT)
		copy:DockMargin(4, 8, 6, 8)
		copy:SetWide(UI.S(96))
		copy:SetText(L("files_copy"))
		UI.StyleButton(copy, nil, 3)
		copy.DoClick = function()
			SetClipboardText(r[2])
			SPeditor.Notify("#path_copied|" .. r[2], 0)
		end
	end
	text(scroll, L("files_steam"), COL.DIM, nil, 12)
end

---------------------------------------------------------------------
-- A render is done (a0.8): people could not find their videos — a notification fades away, so
-- the path stays in a small window with a copy button and what to do with the file.
-- info = { title, path = "garrysmod/…", notes = { text, … } }
---------------------------------------------------------------------
local cvRenderDone = CreateClientConVar("gmfm_render_done_window", "1", true, false)
function UI.ShowRenderDone(info)
	if not cvRenderDone:GetBool() then return end
	local old = Dock.ByKey("renderdone")
	if IsValid(old) then old:Remove() end
	local W = 560
	local win, body = Dock.Create({ key = "renderdone", id = "renderdone", title = info.title or L("rdone_title"), w = W, h = 270,
			x = math.floor(ScrW() / 2 - W / 2), y = 160, dockable = false, icon = "icon16/film_save.png" })
	win.minW, win.minH = UI.S(420), UI.S(240)
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.renderdone = nil
	end

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(34))
	foot.Paint = function() end
	local close = vgui.Create("DButton", foot)
	close:Dock(RIGHT)
	close:DockMargin(4, 5, 8, 5)
	close:SetWide(UI.S(110))
	close:SetText(L("about_close"))
	UI.StyleButton(close, nil, 3)
	close.DoClick = function() win:Remove() end
	local where = vgui.Create("DButton", foot)
	where:Dock(LEFT)
	where:DockMargin(8, 5, 4, 5)
	where:SetWide(UI.S(180))
	where:SetText(L("files_title") .. "…")
	UI.StyleButton(where, nil, 3)
	where.DoClick = function() UI.OpenFileLocations() end
	local again = vgui.Create("DCheckBoxLabel", foot)
	again:Dock(LEFT)
	again:DockMargin(8, 9, 4, 5)
	again:SetText(L("rdone_again"))
	again:SetTextColor(COL.TEXT)
	again:SetFont("SPeditor.Small")
	again:SetConVar("gmfm_render_done_window")
	again:SizeToContents()

	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	scroll.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
	end
	text(scroll, L("rdone_file"), COL.TEXT, nil, 10)
	local row = vgui.Create("DPanel", scroll)
	row:Dock(TOP)
	row:DockMargin(12, 4, 12, 0)
	row:SetTall(UI.S(26))
	row.Paint = function() end
	local copy = vgui.Create("DButton", row)
	copy:Dock(RIGHT)
	copy:DockMargin(4, 0, 0, 0)
	copy:SetWide(UI.S(96))
	copy:SetText(L("files_copy"))
	UI.StyleButton(copy, nil, 3)
	copy.DoClick = function()
		SetClipboardText(info.path)
		SPeditor.Notify("#path_copied|" .. info.path, 0)
	end
	local entry = vgui.Create("DTextEntry", row)
	entry:Dock(FILL)
	entry:SetFont("SPeditor.Small")
	entry:SetText(info.path)
	entry.AllowInput = function() return true end     -- read only, but the text can be selected
	for _, n in ipairs(info.notes or {}) do text(scroll, n, COL.TEXT, nil, 10) end
	text(scroll, L("files_steam"), COL.DIM, nil, 12)
	return win
end

---------------------------------------------------------------------
-- Work camera settings
---------------------------------------------------------------------
function UI.OpenCameraSettings()
	if Dock.ShowPage("camset") then return end
	local W = 400
	local win, body = Dock.Create({ key = "camset", id = "camset", title = L("cam_settings"), w = W, h = 270,
			x = math.floor(ScrW() / 2 - W / 2), y = 160, dockable = false, icon = "icon16/camera_edit.png" })
	win.minW, win.minH = UI.S(320), UI.S(240)

	local D = C.CAM_DEFAULTS
	local syncing = false

	UI.Label(body, L("cam_settings_hint")):DockMargin(8, 8, 8, 6)

	local speed = UI.Slider(body, L("cam_speed"), 16, 4000, 0, C.GetFlySpeed(), function(v)
		if not syncing then C.SetFlySpeed(v) end
	end)
	local wheel = UI.Slider(body, L("cam_wheel"), 0.1, 4, 2, C.GetWheelScale(), function(v)
		if not syncing then C.SetWheelScale(v) end
	end)
	local smooth = UI.Slider(body, L("cam_wheel_smooth"), 0, 1, 2, C.GetWheelSmooth(), function(v)
		if not syncing then C.SetWheelSmooth(v) end
	end)
	local fov = UI.Slider(body, L("cam_fov"), 10, 120, 0, C.camera.fov, function(v)
		if syncing then return end
		C.camera.fovPending = nil
		C.SetWorkFOV(v)
	end)
	for _, s in ipairs({ speed, wheel, smooth, fov }) do s:DockMargin(8, 3, 8, 3) end

	-- FOV is changed both by the wheel (Alt + wheel) and by loading a scene: the slider follows
	SPeditor.Hook("SPeditor_WorkFOVChanged", "SPeditor.CamSettings", function(v)
		if not IsValid(fov) then
			hook.Remove("SPeditor_WorkFOVChanged", "SPeditor.CamSettings")
			return
		end
		if fov:IsEditing() or math.abs(fov:GetValue() - v) < 0.5 then return end
		syncing = true
		fov:SetValue(v)
		syncing = false
	end)

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(34))
	foot.Paint = function() end
	local reset = vgui.Create("DButton", foot)
	reset:Dock(LEFT)
	reset:DockMargin(8, 5, 4, 5)
	reset:SetWide(UI.S(150))
	reset:SetText(L("cam_reset"))
	UI.StyleButton(reset, nil, 3)
	reset.DoClick = function()
		speed:SetValue(D.speed)
		wheel:SetValue(D.wheel)
		smooth:SetValue(D.smooth)
		fov:SetValue(D.fov)
	end
	local close = vgui.Create("DButton", foot)
	close:Dock(RIGHT)
	close:DockMargin(4, 5, 8, 5)
	close:SetWide(UI.S(110))
	close:SetText(L("about_close"))
	UI.StyleButton(close, nil, 3)
	close.DoClick = function() win:Close() end
end
