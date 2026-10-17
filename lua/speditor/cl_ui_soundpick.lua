--[[
SPeditor — picking a sound with the game's own file browser, and the interface sounds.

UI.PickSound{ title, current, onPick(path) }
  A window with the game's file browser (DFileBrowser): the sounds of the game and of every
  mounted addon and game (sound/), or the user's own files (data/speditor/sounds/ — .wav,
  .mp3 and .ogg put there by hand show up at once). A click plays a sound, a double click
  or "Choose" gives its full path ("sound/…" or "data/…") to onPick.

UI.ShortSoundPath(path)    "sound/x.wav" -> "x.wav" (what surface.PlaySound takes); data/… as is

Interface sounds (Interface settings → Windows): a click on a button and the closing of a
window. A sound of one's own (speditor_ui_snd_click / _back) plays with any theme; without
one only themes that have sounds of their own make them (SKIN.SPeditorSounds, Vanilla UI).
  UI.UISound(kind, default)   kind "accept" | "back"; default — the theme's own sound
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI   = SPeditor.UI
local L    = SPeditor.L
local Dock = SPeditor.Dock

local USER_DIR = "data/speditor/sounds"

function UI.ShortSoundPath(path)
	if isstring(path) and string.StartWith(path, "sound/") then return string.sub(path, 7) end
	return path
end

---------------------------------------------------------------------
-- Interface sounds
---------------------------------------------------------------------
local cvOn = GetConVar("speditor_ui_sounds") or CreateClientConVar("speditor_ui_sounds", "1", true, false)
local cvSnd = {
	accept = CreateClientConVar("speditor_ui_snd_click", "", true, false),
	back   = CreateClientConVar("speditor_ui_snd_back", "", true, false),
}

function UI.UISound(kind, default)
	if not cvOn:GetBool() then return end
	local cv = cvSnd[kind] or cvSnd.accept
	local path = cv:GetString()
	if path == "" then path = default end
	if path and path ~= "" then UI.PlayNotifyPath(path) end
end

local CLICKABLE = { DButton = true, DImageButton = true, DCheckBox = true, DCheckBoxLabel = true,
	DMenuOption = true, DComboBox = true, DTab = true, DCollapsibleCategory = true }

-- a theme without sounds of its own: the sounds of one's own are played here
hook.Add("VGUIMousePressed", "SPeditor.UISounds", function(pnl, code)
	local C = SPeditor.Client
	if code ~= MOUSE_LEFT or not C or not C.active or not IsValid(pnl) then return end
	local skin = UI.SkinName and derma.GetNamedSkin(UI.SkinName)
	if skin and skin.SPeditorSounds then return end
	if not CLICKABLE[pnl:GetClassName()] and not CLICKABLE[pnl.ClassName or ""] then return end
	if pnl.IsEnabled and not pnl:IsEnabled() then return end
	local kind = pnl.SPeditorClose and "back" or "accept"
	if cvSnd[kind]:GetString() ~= "" then UI.UISound(kind) end
end)

---------------------------------------------------------------------
-- The sound picker
---------------------------------------------------------------------
local preview
local function listen(path)
	if IsValid(preview) then preview:Stop() end
	preview = nil
	if not path then return end
	sound.PlayFile(path, "noblock", function(ch)
		if not IsValid(ch) then
			SPeditor.Notify("#snd_pick_failed|" .. path, 1)
			return
		end
		if IsValid(preview) then preview:Stop() end
		preview = ch
	end)
end

local state = { root = "sound", folder = nil }

function UI.PickSound(o)
	o = o or {}
	local old = Dock.ByKey("snd_pick")
	if IsValid(old) then old:Remove() end
	if not file.IsDir("speditor/sounds", "DATA") then file.CreateDir("speditor/sounds") end
	local COL = UI.PAL

	-- the current sound: the browser opens in its folder
	local cur = isstring(o.current) and o.current or ""
	if cur ~= "" and not string.StartWith(cur, "data/") and not string.StartWith(cur, "sound/") then cur = "sound/" .. cur end
	if cur ~= "" then
		state.root = string.StartWith(cur, USER_DIR) and USER_DIR or "sound"
		state.folder = string.GetPathFromFilename(cur):TrimRight("/")
	end

	local W = 600
	local win, body = Dock.Create({ key = "snd_pick", id = "snd_pick", title = o.title or L("snd_pick_title"),
		w = W, h = math.min(520, ScrH() - 140), x = math.floor(ScrW() / 2 - UI.S(W) / 2), y = 120,
		dockable = false, icon = "icon16/sound.png" })
	win.minW, win.minH = UI.S(420), UI.S(320)
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		listen(nil)
	end

	local top = vgui.Create("DPanel", body)
	top:Dock(TOP)
	top:DockMargin(6, 6, 6, 2)
	top:SetTall(UI.S(22))
	top.Paint = function() end
	local roots = UI.StyleCombo(vgui.Create("DComboBox", top))
	roots:Dock(LEFT)
	roots:SetWide(UI.S(190))
	roots:AddChoice(L("snd_pick_game"), "sound", state.root == "sound")
	roots:AddChoice(L("snd_pick_user"), USER_DIR, state.root ~= "sound")
	local refresh = vgui.Create("DButton", top)
	refresh:Dock(LEFT)
	refresh:DockMargin(4, 0, 0, 0)
	refresh:SetWide(UI.S(24))
	refresh:SetText("")
	refresh:SetIcon("icon16/arrow_refresh.png")
	refresh:SetTooltip(L("snd_pick_refresh"))
	UI.StyleButton(refresh, nil, 3)
	local chosen = vgui.Create("DLabel", top)
	chosen:Dock(FILL)
	chosen:DockMargin(8, 0, 0, 0)
	chosen:SetFont("SPeditor.Small")
	chosen:SetTextColor(COL.DIM)
	chosen:SetText(cur)

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:DockMargin(4, 2, 4, 4)
	foot:SetTall(UI.S(70))
	foot.Paint = function() end
	local hint = UI.Label(foot, L("snd_pick_hint"))
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:DockMargin(4, 2, 4, 4)
	local buttons = vgui.Create("DPanel", foot)
	buttons:Dock(BOTTOM)
	buttons:SetTall(UI.S(26))
	buttons.Paint = function() end

	local picked = nil
	local function choose(path)
		path = path or picked
		if not path then SPeditor.Notify(L("snd_pick_none"), 0) return end
		if o.onPick then o.onPick(path) end
		win:Remove()
	end

	local browser
	local function build()
		if IsValid(browser) then browser:Remove() end
		browser = vgui.Create("DFileBrowser", body)
		browser:Dock(FILL)
		browser:DockMargin(6, 2, 6, 2)
		browser:SetPath("GAME")
		browser:SetBaseFolder(state.root)
		browser:SetName(state.root == "sound" and "sound" or L("snd_pick_user"))
		browser:SetFileTypes("*.wav *.mp3 *.ogg")
		browser:SetOpen(true)
		if state.folder and string.StartWith(state.folder, state.root) then browser:SetCurrentFolder(state.folder) end
		local baseShow = browser.ShowFolder
		browser.ShowFolder = function(b, path)
			baseShow(b, path)
			state.folder = path
		end
		browser.OnSelect = function(_, path)
			picked = path
			chosen:SetText(path)
			listen(path)
		end
		browser.OnDoubleClick = function(_, path) choose(path) end
	end
	roots.OnSelect = function(_, _, _, data)
		state.root, state.folder = data, nil
		build()
	end
	refresh.DoClick = build
	build()

	local function btn(text, icon, w, fn)
		local b = vgui.Create("DButton", buttons)
		b:Dock(w and LEFT or FILL)
		b:DockMargin(2, 0, 2, 0)
		if w then b:SetWide(UI.S(w)) end
		b:SetText("  " .. text)
		b:SetIcon(icon)
		UI.StyleButton(b, nil, 3)
		b.DoClick = fn
		return b
	end
	btn(L("snd_pick_listen"), "icon16/control_play_blue.png", 110, function() if picked then listen(picked) end end)
	btn(L("snd_pick_stop"), "icon16/control_stop_blue.png", 80, function() listen(nil) end)
	if o.allowClear then
		btn(L("snd_pick_clear"), "icon16/cross.png", 120, function()
			if o.onPick then o.onPick("") end
			win:Remove()
		end)
	end
	btn(L("snd_pick_choose"), "icon16/accept.png", nil, function() choose() end)
	return win
end
