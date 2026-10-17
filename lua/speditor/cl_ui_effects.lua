--[[
SPeditor — effect browser: every effect the game and the installed addons have.

Left: where the effects come from — particle files of the game, particle files of addons,
effects of the Emitter tool, engine effects, Lua effects. Right: the effects of the chosen
source; the search runs over all of them. A double click puts the effect into the scene in
front of the work camera; with an effect object selected it can be replaced instead.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI = SPeditor.UI
local C  = SPeditor.Client
local L  = SPeditor.L
local COL = UI.PAL
local Fx = SPeditor.Effects

local MAX_ROWS = 1500

-- moment a new effect is created with: a particle system is shown a quarter of a second
-- after its start (an explosion is in full bloom, a fire is burning)
local function describe(item)
	return { src = item.src, name = item.name, file = item.file or "", time = 0.25, scale = 1, length = 0 }
end

function UI.SpawnEffect(item)
	C.SendEffectSpawn(describe(item))
end

function UI.ReplaceEffect(ent, item)
	if not C.IsEffect(ent) then return end
	C.SendEffectEdit(ent, { src = item.src, name = item.name, file = item.file or "" }, true)
end

function UI.ToggleEffects()
	local win = SPeditor.Dock.ByKey("effects")
	if IsValid(win) and win:IsVisible() and win.active == "effects" then
		win:Close()
	elseif IsValid(win) then
		SPeditor.Dock.ShowPage("effects")
	else
		UI.BuildEffects()
	end
end

-- everything of one source as list items: { src, name, file, title, where }
local function itemsOfFile(f)
	local out = {}
	local names, part = Fx.Systems(f.path)
	for _, name in ipairs(names) do
		out[#out + 1] = { src = "pcf", name = name, file = f.path, title = name, where = f.name .. (part[name] and ("  ·  " .. L("effb_part")) or "") }
	end
	return out
end

local function itemsOfList(src, list, where)
	local out = {}
	for _, e in ipairs(list) do
		out[#out + 1] = { src = src, name = e.name, title = e.title, where = where }
	end
	return out
end

function UI.BuildEffects()
	local win, body = SPeditor.Dock.Create({
			key = "effects", id = "effects", title = L("win_effects"),
			w = 640, h = math.min(ScrH() - 120, 520), x = 60, y = 110, dockable = true, floating = true,
			onTop = true,
			icon = "icon16/lightning.png",
	})

	local search = vgui.Create("DTextEntry", body)
	search:Dock(TOP)
	search:DockMargin(4, 4, 4, 0)
	search:SetTall(UI.S(22))
	search:SetPlaceholderText(L("effb_search"))

	local bottom = vgui.Create("DPanel", body)
	bottom:Dock(BOTTOM)
	bottom:SetTall(UI.S(30))
	bottom.Paint = function() end

	local hint = vgui.Create("DLabel", body)
	hint:Dock(BOTTOM)
	hint:DockMargin(6, 2, 6, 0)
	hint:SetTall(UI.S(30))
	hint:SetWrap(true)
	hint:SetFont("SPeditor.Small")
	hint:SetTextColor(COL.DIM)
	hint:SetText(L("effb_hint_pcf"))

	local tree = UI.StyleTree(vgui.Create("DTree", body))
	tree:Dock(LEFT)
	tree:SetWide(UI.S(200))
	tree:DockMargin(4, 4, 0, 4)

	local list = vgui.Create("DListView", body)

	UI.StyleListView(list)
	list:Dock(FILL)
	list:DockMargin(4, 4, 4, 4)
	list:SetMultiSelect(false)
	list:AddColumn(L("effb_col_name"))
	list:AddColumn(L("effb_col_from")):SetFixedWidth(150)
	if list.SetBackgroundColor then list:SetBackgroundColor(COL.LIST_BG) end

	local files = Fx.Files()
	local current = { items = {}, live = false }
	local status

	local function selected()
		local line = list:GetSelectedLine()
		local row = line and list:GetLine(line)
		return row and row.SPItem or nil
	end

	local function add(item)
		if item then UI.SpawnEffect(item) end
	end

	local function replace(item)
		if not item then return end
		if not C.IsEffect(C.selected) then
			SPeditor.Notify("#fxb_need_effect", 0)
			return
		end
		UI.ReplaceEffect(C.selected, item)
	end

	local function show(items)
		list:Clear()
		local n = math.min(#items, MAX_ROWS)
		for i = 1, n do
			local it = items[i]
			local row = list:AddLine(it.title, it.where)
			row.SPItem = it
		end
		status:SetText(string.format(L("effb_status"), #items) .. (#items > n and ("  ·  " .. string.format(L("effb_shown"), n)) or ""))
	end

	-- every effect there is (the particle files are read on the first search)
	local everything
	local function all()
		if everything then return everything end
		everything = {}
		for _, f in ipairs(files) do
			for _, it in ipairs(itemsOfFile(f)) do everything[#everything + 1] = it end
		end
		for _, it in ipairs(itemsOfList("tool", Fx.ToolList(), L("effb_tool"))) do everything[#everything + 1] = it end
		for _, it in ipairs(itemsOfList("lua", Fx.EngineList(), L("effb_engine"))) do everything[#everything + 1] = it end
		for _, it in ipairs(itemsOfList("lua", Fx.LuaList(), L("effb_lua"))) do everything[#everything + 1] = it end
		return everything
	end

	local function refresh()
		local q = string.lower(string.Trim(search:GetValue() or ""))
		if q == "" then
			show(current.items)
			return
		end
		local out = {}
		for _, it in ipairs(all()) do
			if string.find(string.lower(it.title), q, 1, true) or string.find(string.lower(it.name), q, 1, true) then
				out[#out + 1] = it
			end
		end
		show(out)
	end

	local function choose(items, live)
		current = { items = items, live = live }
		hint:SetText(L(live and "effb_hint_live" or "effb_hint_pcf"))
		if (search:GetValue() or "") ~= "" then search:SetValue("") end
		refresh()
	end

	status = vgui.Create("DLabel", bottom)
	status:Dock(RIGHT)
	status:DockMargin(0, 0, 8, 0)
	status:SetWide(UI.S(220))
	status:SetContentAlignment(6)
	status:SetFont("SPeditor.Small")
	status:SetTextColor(COL.DIM)
	status:SetText("")

	local function button(text, icon, fn)
		local b = UI.Button(bottom, text, icon, fn)
		b:Dock(LEFT)
		b:DockMargin(4, 3, 0, 3)
		surface.SetFont("SPeditor.Small")
		b:SetWide(select(1, surface.GetTextSize(text)) + UI.S(36))
		return b
	end
	button(L("effb_add"), "icon16/add.png", function() add(selected()) end)
	button(L("effb_replace"), "icon16/arrow_refresh.png", function() replace(selected()) end)

	list.DoDoubleClick = function(_, _, row) add(row.SPItem) end
	list.OnRowRightClick = function(_, _, row)
		local it = row.SPItem
		if not it then return end
		local m = UI.Menu()
		m:AddOption(L("effb_add"), function() add(it) end):SetIcon("icon16/add.png")
		m:AddOption(L("effb_replace"), function() replace(it) end):SetIcon("icon16/arrow_refresh.png")
		m:AddOption(L("copy_path"), function() SetClipboardText(it.name) end)
		m:Open()
	end

	local lastQ = ""
	search.Think = function(s)
		local v = s:GetValue() or ""
		if v ~= lastQ then
			lastQ = v
			refresh()
		end
	end

	-- tree
	local function fileNodes(parent, wantStock)
		for _, f in ipairs(files) do
			if f.stock == wantStock then
				local n = parent:AddNode(f.name, "icon16/page_white_lightning.png")
				UI.NodeColor(n, COL.TEXT)
				n.DoClick = function() choose(itemsOfFile(f), false) end
			end
		end
	end

	-- a click on the folder itself: all the systems of its files
	local function allOf(wantStock)
		local out = {}
		for _, f in ipairs(files) do
			if f.stock == wantStock then
				for _, it in ipairs(itemsOfFile(f)) do out[#out + 1] = it end
			end
		end
		return out
	end
	local game = tree:AddNode(L("effb_pcf_game"), "icon16/folder_brick.png")
	UI.NodeColor(game, COL.ORANGE)
	game:SetExpanded(true)
	fileNodes(game, true)
	game.DoClick = function() choose(allOf(true), false) end

	local nAddon = 0
	for _, f in ipairs(files) do
		if not f.stock then nAddon = nAddon + 1 end
	end
	if nAddon > 0 then
		local addons = tree:AddNode(string.format("%s (%d)", L("effb_pcf_addons"), nAddon), "icon16/folder_brick.png")
		UI.NodeColor(addons, COL.ORANGE)
		fileNodes(addons, false)
		addons.DoClick = function()
			addons:SetExpanded(true)
			choose(allOf(false), false)
		end
	end

	local function listNode(title, icon, src, getList)
		local n = tree:AddNode(title, icon)
		UI.NodeColor(n, COL.ORANGE)
		n.DoClick = function() choose(itemsOfList(src, getList(), title), true) end
	end
	listNode(L("effb_tool"), "icon16/wand.png", "tool", Fx.ToolList)
	listNode(L("effb_engine"), "icon16/cog.png", "lua", Fx.EngineList)
	listNode(L("effb_lua"), "icon16/script.png", "lua", Fx.LuaList)

	choose(allOf(true), false)
end
