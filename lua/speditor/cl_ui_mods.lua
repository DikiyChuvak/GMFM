--[[
SPeditor — the Mods window (Windows → Mods): installed mods, their state and
a note for authors. The mod system itself is sh_mods.lua. The guide is written in
mods/README_ru.md and mods/README_en.md; that folder does not go to the Workshop,
so its text is bundled in cl_mods_guide.lua and saved from the game with a button
(speditor_mod_guide) to garrysmod/data/speditor/mod_guide_<language>.txt.

speditor_mod_template <id> writes a mod template to
garrysmod/data/speditor/mod_template/<id>/ (the game allows writing only into data
and only .txt, so the files have a double extension that has to be removed).
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI   = SPeditor.UI
local L    = SPeditor.L
local Dock = SPeditor.Dock
local COL  = UI.PAL
local Mods = SPeditor.Mods

local STATE_COL = {
	loaded = Color(120, 200, 120), off = Color(150, 150, 150), error = Color(230, 90, 70), outdated = Color(230, 170, 60),
}

---------------------------------------------------------------------
-- Mod template
---------------------------------------------------------------------
local TEMPLATE = {
	["mod.lua"] = [[-- Mod description. Mod folder: lua/speditor_mods/%ID%/
return {
	name        = "%ID%",
	version     = "0.1",
	author      = "you",
	description = { en = "What the mod does.", ru = "Что делает мод." },
	api         = 1,                      -- SPeditor API version the mod is written for
	net         = { "Hello" },            -- the mod's network messages
	shared      = { "sh_%ID%.lua" },
	server      = { "sv_%ID%.lua" },
	client      = { "cl_%ID%.lua" },
}
]],
	["sh_%ID%.lua"] = [[-- Shared file: interface strings and whatever both the server and the client need
local MOD = SPeditor.Mod("%ID%")

MOD:Lang("en", { %ID%_title = "%ID%", %ID%_hello = "Say hello", %ID%_answer = "The server says: %s" })
MOD:Lang("ru", { %ID%_title = "%ID%", %ID%_hello = "Поздороваться", %ID%_answer = "Сервер отвечает: %s" })
]],
	["sv_%ID%.lua"] = [[-- Server
local MOD = SPeditor.Mod("%ID%")
local S = SPeditor.Server

-- a message from the client: access and "the editor is open" are already checked
MOD:NetReceive("Hello", function(ply)
	local ent = S.ReadOwned(ply)          -- an editor object of this player, or nil
	MOD:NetStart("Hello")
	net.WriteString(IsValid(ent) and ent:GetModel() or "nothing selected")
	net.Send(ply)
end)

-- mod data in the scene file
local notes = {}                          -- [ply] = string
MOD:SceneData(function(ply, ctx)
	return { note = notes[ply] }
end, function(ply, data, ctx)
	notes[ply] = data and data.note or nil
end)
]],
	["cl_%ID%.lua"] = [[-- Client
local MOD = SPeditor.Mod("%ID%")
local C, UI = SPeditor.Client, SPeditor.UI

local function hello()
	MOD:NetStart("Hello")
	net.WriteEntity(IsValid(C.selected) and C.selected or NULL)
	net.SendToServer()
end

MOD:NetReceive("Hello", function()
	SPeditor.Notify(MOD:L("%ID%_answer", net.ReadString()), 2)
end)

-- a tab in the editor's bottom window
MOD:AddPage({ id = "%ID%", titleKey = "%ID%_title", icon = "icon16/plugin.png", window = "bottom",
	build = function(panel)
		UI.Button(panel, MOD:L("%ID%_hello"), "icon16/user_comment.png", hello)
	end })

-- an item in the object menu and a hotkey
MOD:AddMenu("object", function(menu, ent)
	menu:AddOption(MOD:L("%ID%_hello"), hello)
end)
MOD:AddHotkey({ key = KEY_H, ctrl = true, fn = hello, desc = "%ID%_hello" })
]],
	["README.txt"] = [[SPeditor mod template "%ID%"

1. Create an addon folder:  garrysmod/addons/<your_addon>/lua/speditor_mods/%ID%/
2. Copy the files from this folder there and remove the ".txt" ending
   (mod.lua.txt -> mod.lua and so on).
3. Restart the map. The mod appears in SPeditor: Windows -> Mods.

Full guide: console command speditor_mod_guide (or SPeditor: Windows -> Mods -> Save the guide)
writes it to garrysmod/data/speditor/mod_guide_en.txt and mod_guide_ru.txt.
]],
}

function UI.WriteModTemplate(id)
	id = string.lower(string.gsub(tostring(id or ""), "[^%w_]", ""))
	if id == "" or tonumber(string.sub(id, 1, 1)) then return nil end
	local dir = SPeditor.Config.SaveDir .. "/mod_template/" .. id
	local acc = ""
	for part in string.gmatch(dir, "[^/]+") do
		acc = (acc == "") and part or (acc .. "/" .. part)
		if not file.IsDir(acc, "DATA") then file.CreateDir(acc) end
	end
	for name, text in pairs(TEMPLATE) do
		name = string.gsub(name, "%%ID%%", id)
		local suffix = string.EndsWith(name, ".txt") and "" or ".txt"
		file.Write(dir .. "/" .. name .. suffix, (string.gsub(text, "%%ID%%", id)))
	end
	return "garrysmod/data/" .. dir
end

-- Guide for mod authors -> garrysmod/data/speditor/mod_guide_ru.txt and _en.txt
function UI.WriteModGuide()
	local dir = SPeditor.Config.SaveDir
	if not file.IsDir(dir, "DATA") then file.CreateDir(dir) end
	for lang, text in pairs(SPeditor.ModGuide or {}) do
		file.Write(dir .. "/mod_guide_" .. lang .. ".txt", text)
	end
	return "garrysmod/data/" .. dir .. "/mod_guide_" .. (GetConVarString("speditor_language") == "ru" and "ru" or "en") .. ".txt"
end

concommand.Add("speditor_mod_guide", function()
	print("[SPeditor] mod guide written to " .. UI.WriteModGuide())
end)

concommand.Add("speditor_mod_template", function(_, _, args)
	local path = UI.WriteModTemplate(args[1])
	if path then
		print("[SPeditor] mod template written to " .. path)
		if SPeditor.Client.active then SPeditor.Notify(string.format(L("mods_template_done"), path), 2) end
	else
		print("usage: speditor_mod_template <id>   (letters, digits and _; must not start with a digit)")
	end
end)

---------------------------------------------------------------------
-- Window
---------------------------------------------------------------------
local function wrap(parent, text, col, font)
	local l = vgui.Create("DLabel", parent)
	l:Dock(TOP)
	l:DockMargin(8, 4, 8, 2)
	l:SetWrap(true)
	l:SetAutoStretchVertical(true)
	l:SetFont(font or "SPeditor.Small")
	l:SetTextColor(col or COL.TEXT)
	l:SetText(text)
	return l
end

function UI.OpenMods()
	if Dock.ShowPage("mods") then return end
	local W, H = 560, 520
	local win, body = Dock.Create({ key = "mods", id = "mods", title = L("mods_title"), w = W, h = math.min(H, ScrH() - 160),
			x = math.floor(ScrW() / 2 - W / 2), y = 110, dockable = false, icon = "icon16/plugin.png" })
	win.minW, win.minH = UI.S(380), UI.S(300)

	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)

	wrap(scroll, L("mods_intro"), COL.DIM)

	if #Mods.list == 0 then wrap(scroll, L("mods_none"), COL.ORANGE) end
	for _, mod in ipairs(Mods.list) do
		local card = vgui.Create("DPanel", scroll)
		card:Dock(TOP)
		card:DockMargin(6, 6, 6, 0)
		card:DockPadding(0, 24, 0, 6)
		card.Paint = function(_, w, h)
			surface.SetDrawColor(COL.ROW_B)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(COL.HEADER)
			surface.DrawRect(0, 0, w, 22)
			draw.SimpleText(mod.name .. (mod.version ~= "" and ("  " .. mod.version) or ""), "SPeditor.Bold", 8, 11, COL.TEXT,
				TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			local off = Mods.IsOff(mod.id)
			local state = mod.state or "loaded"
			-- the toggle takes effect after a map restart: show what it will become as well
			local text = L("mods_state_" .. state)
			if (state == "off") ~= off then text = text .. "  →  " .. L(off and "mods_state_off" or "mods_state_loaded") .. " (" .. L("mods_restart") .. ")" end
			draw.SimpleText(text, "SPeditor.Small", w - 8, 11, STATE_COL[state] or COL.DIM, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
		local desc = Mods.Description(mod)
		if desc ~= "" then wrap(card, desc) end
		wrap(card, string.format("%s: %s      %s: lua/%s", L("mods_author"), mod.author ~= "" and mod.author or "—", L("mods_folder"), mod.folder), COL.DIM)
		for _, err in ipairs(mod.errors or {}) do wrap(card, err, STATE_COL.error) end
		local chk = UI.Check(card, L("mods_enabled"), not Mods.IsOff(mod.id), function(v)
			Mods.SetOff(mod.id, not v)
		end)
		chk:DockMargin(8, 4, 8, 0)
		card:InvalidateLayout(true)
		card:SizeToChildren(false, true)
		card.PerformLayout = function(s) s:SizeToChildren(false, true) end
	end

	-- note for the mod author
	local head = vgui.Create("DPanel", scroll)
	head:Dock(TOP)
	head:DockMargin(6, 12, 6, 0)
	head:SetTall(UI.S(22))
	head.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText(L("mods_dev_title"), "SPeditor.Bold", 8, h / 2, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	wrap(scroll, L("mods_dev_text"))

	local row = vgui.Create("DPanel", scroll)
	row:Dock(TOP)
	row:DockMargin(6, 4, 6, 8)
	row:SetTall(UI.S(24))
	row.Paint = function() end
	local guide = vgui.Create("DButton", row)
	guide:Dock(RIGHT)
	guide:SetWide(UI.S(190))
	guide:SetText(L("mods_guide_save"))
	guide:SetIcon("icon16/book_open.png")
	UI.StyleButton(guide)
	guide.DoClick = function()
		SPeditor.Notify(string.format(L("mods_guide_done"), UI.WriteModGuide()), 2)
	end
	local entry = vgui.Create("DTextEntry", row)
	entry:Dock(LEFT)
	entry:SetWide(UI.S(150))
	entry:SetFont("SPeditor.Small")
	entry:SetPlaceholderText(L("mods_template_id"))
	local make = vgui.Create("DButton", row)
	make:Dock(LEFT)
	make:DockMargin(6, 0, 0, 0)
	make:SetWide(UI.S(190))
	make:SetText(L("mods_template_make"))
	make:SetIcon("icon16/page_white_code.png")
	UI.StyleButton(make)
	make.DoClick = function()
		local path = UI.WriteModTemplate(entry:GetValue())
		if path then
			SPeditor.Notify(string.format(L("mods_template_done"), path), 2)
		else
			SPeditor.Notify(L("mods_template_bad"), 1)
		end
	end
	return win
end
