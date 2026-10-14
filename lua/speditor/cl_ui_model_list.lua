--[[
SPeditor — model browser in the style of SFM / the Q menu.

On the left, a tree of sources:
  * All models (search over the whole models/);
  * Spawnlists (categories from the Q menu);
  * Player Models / Ragdolls;
  * models/ folders (loaded when expanded).
On the right, a grid of icons. Double click / click — create, right click — menu.
Search works as in the Q menu: a substring without "models/" and ".mdl". The index of all
models is built in the background (a bit per frame), so the game does not freeze.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI = SPeditor.UI
local C  = SPeditor.Client
local L  = SPeditor.L
local COL = UI.PAL

local MAX_ICONS = 120

---------------------------------------------------------------------
-- Index of all models (background scan of models/)
---------------------------------------------------------------------
local USELESS = {
	"_gestures", "_anim", "_gst", "_pst", "_shd", "_ss.mdl", "_posture", "_anm",
	"ghostanim", "_paths", "_shared", "anim_", "gestures_", "shared_ragdoll_",
}

local function isUseless(path)
	for _, s in ipairs(USELESS) do
		if string.find(path, s, 1, true) then return true end
	end
	return false
end

local index, scanDone = nil, false

function UI.StartModelScan()
	if index then return end
	index = {}
	local queue = { "models/" }
	timer.Create("SPeditor.ModelScan", 0, 0, function()
		local t0 = SysTime()
		while #queue > 0 and SysTime() - t0 < 0.004 do
			local dir = table.remove(queue)
			local files, dirs = file.Find(dir .. "*", "GAME")
			for _, f in ipairs(files or {}) do
				if string.sub(f, -4) == ".mdl" then
					local path = dir .. f
					if not isUseless(path) then index[#index + 1] = path end
				end
			end
			for _, d in ipairs(dirs or {}) do queue[#queue + 1] = dir .. d .. "/" end
		end
		if #queue == 0 then
			scanDone = true
			timer.Remove("SPeditor.ModelScan")
		end
	end)
end

---------------------------------------------------------------------
-- Q menu categories and players
---------------------------------------------------------------------
local cachedCats
local function collectCategories()
	if cachedCats then return cachedCats end
	local out, seen = {}, {}
	local function add(model, cat)
		if type(model) ~= "string" then return end
		model = string.lower(string.Replace(model, "\\", "/"))
		if string.sub(model, -4) ~= ".mdl" or seen[cat .. model] then return end
		seen[cat .. model] = true
		out[cat] = out[cat] or {}
		out[cat][#out[cat] + 1] = model
	end
	local function scan(source)
		if type(source) ~= "table" then return end
		for _, group in pairs(source) do
			if type(group) == "table" and type(group.contents) == "table" then
				for _, item in pairs(group.contents) do
					if type(item) == "table" and item.type == "model" then add(item.model, group.name or "Other") end
				end
			end
		end
	end
	if spawnmenu.GetPropTable then scan(spawnmenu.GetPropTable()) end
	if spawnmenu.GetCustomPropTable then scan(spawnmenu.GetCustomPropTable()) end
	-- AllValidModels: [name] = path, so take the VALUES
	for _, m in pairs(player_manager.AllValidModels() or {}) do
		if type(m) == "string" then
			add(m, util.IsValidRagdoll(m) and "Ragdolls" or "Player Models")
		end
	end
	cachedCats = out
	return out
end

UI.ModelIcons = {
	prop_ragdoll = "icon16/user.png", prop_physics = "icon16/box.png", prop_dynamic = "icon16/box.png",
	speditor_light = "icon16/lightbulb.png", speditor_camera = "icon16/camera.png",
	speditor_effect = "icon16/lightning.png",
}
function UI.GetIconForClass(className)
	return UI.ModelIcons[className] or "icon16/box.png"
end

---------------------------------------------------------------------
-- Window
---------------------------------------------------------------------
function UI.ToggleBrowser()
	local win = SPeditor.Dock.ByKey("browser")
	if IsValid(win) and win:IsVisible() and win.active == "browser" then
		win:Close()
	elseif IsValid(win) then
		SPeditor.Dock.ShowPage("browser")
	else
		UI.BuildBrowser()
	end
end

function UI.BuildBrowser()
	UI.StartModelScan()

	local win, body = SPeditor.Dock.Create({
			key = "browser", id = "browser", title = L("win_browser"),
			w = 780, h = math.min(ScrH() - 120, 560), x = 20, y = 90, dockable = true, floating = true,
			-- the browser stays above the other editor windows until that is switched off
			-- in its properties (right click on the tab strip → "Window properties")
			onTop = true,
			icon = "icon16/application_view_tile.png",
	})
	UI.BrowserFrame = win

	-- top: path + search
	local top = vgui.Create("DPanel", body)
	top:Dock(TOP)
	top:SetTall(54)
	top.Paint = function() end

	local pathBox = vgui.Create("DTextEntry", top)
	pathBox:Dock(TOP)
	pathBox:DockMargin(4, 4, 4, 0)
	pathBox:SetTall(22)
	pathBox:SetPlaceholderText(L("spawn_by_path") .. " " .. L("path_placeholder"))
	pathBox.OnEnter = function(self)
		local m = string.lower(string.Trim(string.Replace(self:GetValue() or "", "\\", "/")))
		if string.sub(m, -4) ~= ".mdl" then
			SPeditor.Notify(L("bad_model_path"), 1)
			return
		end
		C.SpawnModel(m)
	end

	local search = vgui.Create("DTextEntry", top)
	search:Dock(TOP)
	search:DockMargin(4, 4, 4, 0)
	search:SetTall(22)
	search:SetPlaceholderText(L("search_models"))

	local status = vgui.Create("DLabel", body)
	status:Dock(BOTTOM)
	status:DockMargin(6, 2, 6, 2)
	status:SetTall(16)
	status:SetTextColor(COL.DIM)

	-- left tree
	local tree = vgui.Create("DTree", body)
	tree:Dock(LEFT)
	tree:SetWide(210)
	tree:DockMargin(4, 4, 0, 4)
	tree:SetIndentSize(12)
	tree.Paint = function(_, w, h)
		surface.SetDrawColor(COL.TREE_BG)
		surface.DrawRect(0, 0, w, h)
	end

	-- right grid
	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	scroll:DockMargin(4, 4, 4, 4)
	if scroll.SetBackgroundColor then scroll:SetBackgroundColor(COL.LIST_BG) end
	local icons = vgui.Create("DIconLayout", scroll)
	icons:Dock(TOP)
	icons:SetSpaceX(4)
	icons:SetSpaceY(4)

	local current = { kind = "all" }
	local pending, shownCount = {}, 0

	local function addIcon(model)
		local icon = vgui.Create("SpawnIcon", icons)
		icon:SetSize(88, 88)
		icon:SetModel(model)
		icon:SetTooltip(model)
		icon.DoClick = function() C.SpawnModel(model) end
		icon.OpenMenu = function()
			local menu = SPeditor.UI.Menu()
			menu:AddOption(L("spawn"), function() C.SpawnModel(model) end)
			menu:AddOption(L("copy_path"), function()
				SetClipboardText(model)
				SPeditor.Notify("#path_copied|" .. model, 0)
			end)
			menu:Open()
		end
	end

	local addMore
	function addMore()
		if #pending <= shownCount then return end
		local more = vgui.Create("DButton", icons)
		more:SetSize(176, 88)
		more:SetText(string.format(L("browser_more"), #pending - shownCount))
		more:SetTextColor(COL.TEXT)
		more.Paint = function(s2, w, h) draw.RoundedBox(3, 0, 0, w, h, s2:IsHovered() and COL.HOVER or COL.CTRL) end
		more.DoClick = function()
			more:Remove()
			local upto = math.min(#pending, shownCount + MAX_ICONS)
			for i = shownCount + 1, upto do addIcon(pending[i]) end
			shownCount = upto
			addMore()
		end
	end

	local function showList(list)
		icons:Clear()
		pending, shownCount = list, 0
		local n = math.min(#list, MAX_ICONS)
		for i = 1, n do addIcon(list[i]) end
		shownCount = n
		status:SetText(string.format(L("browser_status"), #list, (not scanDone) and (" — " .. L("browser_indexing")) or ""))
		addMore()
	end

	local function refresh()
		local q = string.lower(string.Trim(search:GetValue() or ""))
		local base
		if current.kind == "cat" then
			base = (collectCategories()[current.name]) or {}
		elseif current.kind == "folder" then
			base = current.list or {}
		else
			base = index or {}
		end
		local out = {}
		for _, m in ipairs(base) do
			if q == "" then
				out[#out + 1] = m
			else
				-- as in the Q menu: do not search in the common "models/" and ".mdl"
				local short = m
				if string.sub(short, 1, 7) == "models/" and string.sub(short, -4) == ".mdl" and string.sub(q, -4) ~= ".mdl" then
					short = string.sub(short, 8, #short - 4)
				end
				if string.find(string.lower(short), q, 1, true) then out[#out + 1] = m end
			end
			if #out >= 2000 then break end
		end
		showList(out)
	end

	local lastQ
	search.Think = function(s)
		local v = s:GetValue() or ""
		if v ~= lastQ then
			lastQ = v
			if current.kind ~= "all" and v ~= "" then current = { kind = "all" } end  -- the search runs over all models
			refresh()
		end
	end

	-- tree nodes
	local function select(kind, name, list)
		current = { kind = kind, name = name, list = list }
		search:SetValue("")
		lastQ = ""
		refresh()
	end

	local allNode = tree:AddNode(L("browser_all"), "icon16/database.png")
	allNode.DoClick = function() select("all") end
	UI.NodeColor(allNode, COL.TEXT)

	local cats = collectCategories()
	local names = {}
	for c in pairs(cats) do names[#names + 1] = c end
	table.sort(names)
	local listsNode = tree:AddNode(L("browser_spawnlists"), "icon16/folder_brick.png")
	UI.NodeColor(listsNode, COL.ORANGE)
	listsNode:SetExpanded(true)
	for _, c in ipairs(names) do
		local n = listsNode:AddNode(string.format("%s (%d)", SPeditor.LN("browser_cat_", c), #cats[c]), "icon16/folder.png")
		UI.NodeColor(n, COL.TEXT)
		n.DoClick = function() select("cat", c) end
	end

	-- models/ folders are loaded when first expanded
	local diskNode = tree:AddNode("models/", "icon16/drive.png")
	UI.NodeColor(diskNode, COL.ORANGE)

	local function addFolder(parentNode, dir)
		local files, dirs = file.Find(dir .. "*", "GAME")
		table.sort(dirs or {})
		for _, d in ipairs(dirs or {}) do
			local path = dir .. d .. "/"
			local n = parentNode:AddNode(d, "icon16/folder.png")
			UI.NodeColor(n, COL.TEXT)
			n.SPeditorLoaded = false
			n.DoClick = function()
				if not n.SPeditorLoaded then
					n.SPeditorLoaded = true
					addFolder(n, path)
				end
				n:SetExpanded(true)
				local list = {}
				local fs = file.Find(path .. "*.mdl", "GAME")
				for _, f in ipairs(fs or {}) do
					if not isUseless(path .. f) then list[#list + 1] = path .. f end
				end
				table.sort(list)
				select("folder", path, list)
			end
		end
	end
	local diskLoaded = false
	diskNode.DoClick = function()
		if not diskLoaded then
			diskLoaded = true
			addFolder(diskNode, "models/")
		end
		diskNode:SetExpanded(true)
	end

	refresh()

	-- while indexing runs, refresh "all models" from time to time
	local nextRefresh = 0
	status.Think = function()
		if scanDone or RealTime() < nextRefresh then return end
		nextRefresh = RealTime() + 1.5
		if current.kind == "all" and (search:GetValue() or "") == "" then
			status:SetText(string.format(L("browser_status"), #(index or {}), " — " .. L("browser_indexing")))
		elseif current.kind == "all" then
			refresh()
		end
	end

	win.OnRemove = function() UI.BrowserFrame = nil end
end
