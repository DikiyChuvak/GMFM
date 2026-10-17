-- Client entry point: mode toggle, hotkeys, HUD,
-- a separate SPeditor tab in the Q menu (launch, language, About).
SPeditor.Client = SPeditor.Client or {}
local C = SPeditor.Client
local L = SPeditor.L

local function restoreCursor()
	local wp = vgui.GetWorldPanel()
	if IsValid(wp) then wp:SetCursor("arrow") end
end

concommand.Add("speditor_toggle", function()
	C.SendToggle(not C.active)
end)

-- Shadow of the player and their weapon: the body is hidden through PrePlayerDraw, but the shadow
-- kept falling from the player's real position (a "black blob" near the camera).
local function setLocalShadows(hide)
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	ply:DrawShadow(not hide)
	for _, w in ipairs(ply:GetWeapons()) do
		if IsValid(w) then w:DrawShadow(not hide) end
	end
end

local nextShadowFix = 0
hook.Add("Think", "SPeditor.NoPlayerShadow", function()
	if not C.active or RealTime() < nextShadowFix then return end
	nextShadowFix = RealTime() + 1.5
	setLocalShadows(true)
end)

hook.Add("SPeditor_StateChanged", "SPeditor.Entry", function(on)
	setLocalShadows(on)
	if on then
		C.InitCamera()
		gui.EnableScreenClicker(true)
		RunConsoleCommand("cl_drawhud", "0")
		if SPeditor.UI and SPeditor.UI.Open then SPeditor.UI.Open() end
	else
		C.StopViewCamera()
		C.Select(nil)
		C.camMode = nil
		RunConsoleCommand("cl_drawhud", "1")
		if SPeditor.UI and SPeditor.UI.Close then SPeditor.UI.Close() end
		gui.EnableScreenClicker(false)
		restoreCursor()
	end
end)

---------------------------------------------------------------------
-- Q menu: a separate SPeditor category (next to Tools)
---------------------------------------------------------------------
hook.Add("PopulateToolMenu", "SPeditor.QMenu", function()
	-- 16x16 tab icon: materials/speditor/icon16.png
	spawnmenu.AddToolTab("SPeditor", "SPeditor", "speditor/icon16.png")

	spawnmenu.AddToolMenuOption("SPeditor", L("qmenu_main"), "SPeditor_Toggle", "SPeditor", "", "", function(p)
		p:ClearControls()
		p:Help("SPeditor " .. (SPeditor.Version or ""))
		p:Button(L("qmenu_toggle"), "speditor_toggle")
	end)

	spawnmenu.AddToolMenuOption("SPeditor", L("qmenu_main"), "SPeditor_Lang", L("qmenu_lang_item"), "", "", function(p)
		p:ClearControls()
		local row = vgui.Create("DComboBox")
		local cur = GetConVarString("speditor_language") or "en"
		row:SetValue(cur == "ru" and "Русский" or "English")
		row:AddChoice("English", "en")
		row:AddChoice("Русский", "ru")
		row.OnSelect = function(_, _, text, data)
			RunConsoleCommand("speditor_language", data)
		end
		p:AddPanel(row, L("qmenu_language") .. ":")
		p:Help(L("qmenu_lang_hint"))
	end)

	spawnmenu.AddToolMenuOption("SPeditor", L("qmenu_main"), "SPeditor_Theme", L("qmenu_theme"), "", "", function(p)
		p:ClearControls()
		local UI = SPeditor.UI
		local row = vgui.Create("DComboBox")
		local cur = UI.ThemeById[GetConVarString("speditor_theme")] or UI.ThemeById.speditor
		for _, t in ipairs(UI.Themes) do
			row:AddChoice(t.group and t.group ~= t.name and (t.group .. ": " .. t.name) or t.name, t.id, t == cur)
		end
		row.OnSelect = function(_, _, _, id) UI.SetTheme(id) end
		p:AddPanel(row, L("menu_theme") .. ":")
	end)
end)

---------------------------------------------------------------------
-- C menu: the SPeditor icon among the desktop icons of the context menu
---------------------------------------------------------------------
list.Set("DesktopWindows", "SPeditor", {
	title = "SPeditor",
	icon  = "speditor/icon128.png",
	width = 120, height = 60,       -- the menu creates a window before calling init and requires a size
	init  = function(icon, window)
		-- the icon needs no window of its own: it opens (or closes) the editor.
		-- The C menu itself is closed first, otherwise it would stay over the editor
		-- until the key is released and would take the cursor away when closing.
		if IsValid(window) then window:Remove() end
		if IsValid(g_ContextMenu) and g_ContextMenu:IsVisible() then g_ContextMenu:Close() end
		timer.Simple(0.05, function() RunConsoleCommand("speditor_toggle") end)
	end,
})

hook.Add("PlayerBindPress", "SPeditor.BlockUndo", function(_, bind)
	if not C.active then return end
	if bind == "gmod_undo" or bind == "undo" then return true end
end)

hook.Add("ShouldDrawLocalPlayer", "SPeditor.HideLocalPlayer", function()
	if C.active then return false end
end)
hook.Add("PrePlayerDraw", "SPeditor.HidePlayerModel", function(ply)
	if C.active and ply == LocalPlayer() then return true end
end)
hook.Add("PreDrawViewModel", "SPeditor.HideViewModel", function()
	if C.active then return true end
end)

local HIDE = {
	CHudCrosshair = true, CHudHealth = true, CHudBattery = true, CHudAmmo = true,
	CHudSecondaryAmmo = true, CHudWeaponSelection = true, CHudDamageIndicator = true,
	CHudZoom = true, CHudSuitPower = true, CHudHistoryResource = true,
}
hook.Add("HUDShouldDraw", "SPeditor.HideHUD", function(name)
	if C.active and HIDE[name] then return false end
end)

C.spawnHistory = C.spawnHistory or {}
hook.Add("SPeditor_ObjectSpawned", "SPeditor.TrackSpawn", function(ent)
	if IsValid(ent) then
		table.insert(C.spawnHistory, ent)
	end
end)

-- Editor hotkeys: the keys are set in Interface settings → Keys (cl_keys.lua)
local PRESS = {
	"undo", "redo", "redo2", "duplicate", "pose_copy", "pose_paste", "gizmo_move", "gizmo_rotate", "gizmo_scale",
	"gizmo_space", "focus", "camview", "skeleton", "ik", "delete",
	"list_select_all", "list_copy", "list_paste",
}
local ACTIONS = {
	undo = function() C.Undo() end,
	redo = function() C.Redo() end,
	redo2 = function() C.Redo() end,
	duplicate = function() C.DuplicateSelection() end,
	pose_copy = function() C.CopyPose(C.selected) end,
	pose_paste = function() C.PastePose(C.selected) end,
	gizmo_move = function() C.gizmo.mode = "move" end,
	gizmo_rotate = function() C.gizmo.mode = "rotate" end,
	gizmo_scale = function() C.gizmo.mode = "scale" end,
	gizmo_space = function() C.gizmo.space = (C.gizmo.space == "world") and "local" or "world" end,
	focus = function() C.FocusSelected() end,
	camview = function()
		if C.GetViewCamera() then
			C.StopViewCamera()
		elseif C.IsCamera(C.selected) then
			C.StartViewCamera(C.selected)
		end
	end,
	skeleton = function() C.showSkeleton = not C.showSkeleton end,
	ik = function()
		C.gizmo.ik = not C.gizmo.ik
		SPeditor.Notify(C.gizmo.ik and L("ik_hint") or L("ik_off"), 0)
	end,
	delete = function() if IsValid(C.selected) then C.DeleteSelection() end end,
	list_select_all = function() C.SelectAll() end,
	list_copy = function() C.CopyObjects() end,
	list_paste = function() C.PasteObjects() end,
}

hook.Add("Think", "SPeditor.Hotkeys", function()
	if not C.active then return end
	-- every key is polled each frame, so that a press made while typing does not fire later
	local fired = {}
	for _, id in ipairs(PRESS) do
		if C.Keys.Fired(id) then fired[#fired + 1] = id end
	end
	local focus = vgui.GetKeyboardFocus()
	local blocked = (IsValid(focus) and focus ~= vgui.GetWorldPanel()) or C.camMode ~= nil or C.Keys.capturing ~= nil
	SPeditor.Mods.RunHotkeys(blocked)
	if blocked then return end
	-- one key press, one action: over the object list its own keys win, elsewhere they are
	-- not used; otherwise the first in the list wins if two actions share a key
	local overList = C.MouseOverObjectList()
	local pick
	for _, id in ipairs(fired) do
		if C.Keys.ById[id].area == "list" then
			if overList then
				pick = id
				break
			end
		elseif not pick then
			pick = id
		end
	end
	if pick then ACTIONS[pick]() end
end)

-- The status line and the name of the active camera are shown in the status bar and in
-- the viewport header (cl_ui_main.lua); the game HUD is not drawn in the editor.
hook.Remove("HUDPaint", "SPeditor.HUD")
