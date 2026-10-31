--[[
SPeditor — model browser in the style of SFM / the Q menu.

On the left, a tree of sources:
  * All models (search over the whole models/);
  * Addons — the Workshop subscriptions that have models, each with its own models (as
    Browse → Addons of the Q menu); above the tree they can be sorted (by name, the newest
    subscriptions first, the latest updated, by the number of models) and filtered by name;
  * Games — mounted games (Counter-Strike: Source, TF2…), each with its models;
  * Legacy addons — folders in garrysmod/addons (not from the Workshop), each with its models;
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

-- of the hidden ones, those that are animation models (the import takes animations from them)
local ANIMLIKE = { "anim", "_anm", "_gst", "_pst", "gesture", "posture" }
local function isAnimModel(path)
	for _, s in ipairs(ANIMLIKE) do
		if string.find(path, s, 1, true) then return true end
	end
	return false
end

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
-- Models of one addon or one mounted game (path id = the addon title / the game folder),
-- collected in the background a bit per frame. done(list, finished) is called as it grows.
-- prefix: the models are looked for under prefix .. "models/" of that path id (a legacy
-- addon: "addons/<folder>/" of "MOD"), and listed as "models/…" as the game mounts them.
---------------------------------------------------------------------
local sourceCache = {}

local function scanSource(pathId, done, prefix)
	prefix = prefix or ""
	local key = pathId .. "|" .. prefix
	local c = sourceCache[key]
	if c and c.finished then
		done(c.list, true, c.anims)
		return
	end
	if c then
		c.done = done
		return
	end
	-- anims: the models the browser hides (animation and gesture models of characters):
	-- the animation import takes its animations from them
	c = { list = {}, anims = {}, queue = { "models/" }, finished = false, done = done }
	sourceCache[key] = c
	local id = "SPeditor.SourceScan." .. key
	timer.Create(id, 0, 0, function()
		local t0 = SysTime()
		while #c.queue > 0 and SysTime() - t0 < 0.004 do
			local dir = table.remove(c.queue)
			local files, dirs = file.Find(prefix .. dir .. "*", pathId)
			for _, f in ipairs(files or {}) do
				if string.sub(f, -4) == ".mdl" then
					local path = string.lower(dir .. f)
					if not isUseless(path) then
						c.list[#c.list + 1] = path
					elseif isAnimModel(path) then
						c.anims[#c.anims + 1] = path
					end
				end
			end
			for _, d in ipairs(dirs or {}) do c.queue[#c.queue + 1] = dir .. d .. "/" end
		end
		if #c.queue == 0 then
			c.finished = true
			table.sort(c.list)
			table.sort(c.anims)
			timer.Remove(id)
		end
		if c.done then c.done(c.list, c.finished, c.anims) end
	end)
end

-- Workshop subscriptions with models, sorted: name / name_desc / newest / oldest / updated / models
local cvSort = CreateClientConVar("gmfm_browser_sort", "name", true, false)
UI.BrowserSorts = { "name", "name_desc", "newest", "oldest", "updated", "models" }

local function addonsWithModels(filter)
	local out = {}
	filter = string.lower(filter or "")
	for _, a in ipairs(engine.GetAddons() or {}) do
		if a.mounted and (a.models or 0) > 0 and (filter == "" or string.find(string.lower(a.title or ""), filter, 1, true)) then
			out[#out + 1] = a
		end
	end
	-- timeadded is the order of subscription (bigger — newer); 0 — subscribed in this session
	local function added(a) return (a.timeadded or 0) == 0 and math.huge or a.timeadded end
	local mode = cvSort:GetString()
	table.sort(out, function(x, y)
		if mode == "name_desc" then return string.lower(x.title) > string.lower(y.title) end
		if mode == "newest" then return added(x) > added(y) end
		if mode == "oldest" then return added(x) < added(y) end
		if mode == "updated" then return (x.updated or 0) > (y.updated or 0) end
		if mode == "models" then return (x.models or 0) > (y.models or 0) end
		return string.lower(x.title) < string.lower(y.title)
	end)
	return out
end

-- Legacy addons: folders in garrysmod/addons. The game mounts them, but engine.GetAddons()
-- lists only Workshop subscriptions, so they are found on disk. Returns { { name, models =
-- has a models/ folder, smh = has data/smh or data_static/smh } }, sorted by name.
function UI.LegacyAddons()
	local out = {}
	local _, dirs = file.Find("addons/*", "MOD")
	for _, d in ipairs(dirs or {}) do
		local base = "addons/" .. d .. "/"
		local models = file.IsDir(base .. "models", "MOD")
		local smh = file.IsDir(base .. "data/smh", "MOD") or file.IsDir(base .. "data_static/smh", "MOD")
		if models or smh then out[#out + 1] = { name = d, models = models, smh = smh } end
	end
	table.sort(out, function(x, y) return string.lower(x.name) < string.lower(y.name) end)
	return out
end

-- Models of a source for other windows: (path id, prefix, done(list, finished, anims)) as scanSource;
-- a Workshop addon is (its title, nil), a legacy addon ("MOD", "addons/<folder>/")
UI.ScanSourceModels = function(pathId, prefix, done) scanSource(pathId, done, prefix) end
UI.AddonsWithModels = function(filter) return addonsWithModels(filter) end

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
	if UI.ModelIcons[className] then return UI.ModelIcons[className] end
	-- lights and lamps of other addons taken from the map
	if className and (string.find(className, "light", 1, true) or string.find(className, "lamp", 1, true)) then
		return "icon16/lightbulb.png"
	end
	return "icon16/box.png"
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

-- open the browser showing a category ("cat", name) or everything ("all")
function UI.BrowserShow(kind, name)
	local win = SPeditor.Dock.ByKey("browser")
	if IsValid(win) then SPeditor.Dock.ShowPage("browser") else UI.BuildBrowser() end
	timer.Simple(0, function() if UI.BrowserSelect then UI.BrowserSelect(kind, name) end end)
end

function UI.BuildBrowser()
	UI.StartModelScan()

	local win, body = SPeditor.Dock.Create({
			key = "browser", id = "browser", title = L("win_browser"),
			w = 1000, h = math.min(ScrH() - 120, 560), x = 20, y = 90, dockable = true, floating = true,
			-- the browser stays above the other editor windows until that is switched off
			-- in its properties (right click on the tab strip → "Window properties")
			onTop = true,
			icon = "icon16/application_view_tile.png",
	})
	UI.BrowserFrame = win

	-- top: path + search
	local top = vgui.Create("DPanel", body)
	top:Dock(TOP)
	top:SetTall(UI.S(54))
	top.Paint = function() end

	local pathBox = vgui.Create("DTextEntry", top)
	pathBox:Dock(TOP)
	pathBox:DockMargin(4, 4, 4, 0)
	pathBox:SetTall(UI.S(22))
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
	search:SetTall(UI.S(22))
	search:SetPlaceholderText(L("search_models"))

	local status = vgui.Create("DLabel", body)
	status:Dock(BOTTOM)
	status:DockMargin(6, 2, 6, 2)
	status:SetTall(UI.S(16))
	status:SetTextColor(COL.DIM)

	-- left: the addon sort / filter row, then the tree
	local left = vgui.Create("DPanel", body)
	left:Dock(LEFT)
	left:SetWide(UI.S(250))
	left:DockMargin(4, 4, 0, 4)
	left.Paint = function() end

	local addonBar = vgui.Create("DPanel", left)
	addonBar:Dock(TOP)
	addonBar:SetTall(UI.S(22))
	addonBar:DockMargin(0, 0, 0, 4)
	addonBar.Paint = function() end
	local sortBox = vgui.Create("DComboBox", addonBar)
	sortBox:Dock(RIGHT)
	sortBox:SetWide(UI.S(118))
	sortBox:SetSortItems(false)
	UI.StyleCombo(sortBox)
	sortBox:SetTooltip(L("browser_sort"))
	for _, id in ipairs(UI.BrowserSorts) do sortBox:AddChoice(L("browser_sort_" .. id), id, cvSort:GetString() == id) end
	local addonFilter = vgui.Create("DTextEntry", addonBar)
	addonFilter:Dock(FILL)
	addonFilter:DockMargin(0, 0, 4, 0)
	addonFilter:SetPlaceholderText(L("browser_addon_filter"))

	local tree = vgui.Create("DTree", left)
	tree:Dock(FILL)
	tree:SetIndentSize(UI.S(12))
	tree:SetLineHeight(math.max(UI.S(17), 17))
	tree.Paint = function(_, w, h)
		surface.SetDrawColor(COL.TREE_BG)
		surface.DrawRect(0, 0, w, h)
	end

	-- the model under the cursor, turning in its idle animation (a0.9, as in SFM; cl_ui_preview.lua);
	-- b0.2.6: on a floor grid, with SFM's tabs under it (Render, Sequences, Activities, Skins)
	local side = vgui.Create("DPanel", body)
	side:Dock(RIGHT)
	side:SetWide(UI.S(280))
	side:DockMargin(0, 4, 4, 4)
	side.Paint = function() end
	local preview = UI.ModelPreview(side)
	preview:Dock(TOP)
	local tabs = UI.ModelPreviewTabs(side, preview)
	tabs:Dock(FILL)
	tabs:DockMargin(0, 4, 0, 0)
	side.PerformLayout = function(s2, w, h) preview:SetTall(math.Clamp(math.floor(h * 0.55), UI.S(120), w)) end
	-- the preview changes once the cursor rests on an icon: on the way to the tabs it crosses others
	preview.Think = function(s2)
		if s2.SPWant and RealTime() - s2.SPWantT > 0.25 then
			s2:SetModel(s2.SPWant)
			s2.SPWant = nil
		end
	end
	-- a click puts the model in with the skin picked in the preview
	local function spawn(model)
		if IsValid(preview) and preview.SPPath == model and (preview.SPSkin or 0) > 0 then
			C.spawnSkin = { model = string.lower(model), skin = preview.SPSkin, untilT = RealTime() + 5 }
		end
		C.SpawnModel(model)
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
		-- the size of the spawn menu icons: the game then takes the same cached picture
		-- (materials/spawnicons/<model>.png, or the one shipped in the model's addon); any
		-- other size is a picture of its own (<model>_128.png) that has to be rendered again
		icon:SetSize(UI.S(64), UI.S(64))
		icon:SetModel(model)
		icon:SetTooltip(model)
		icon.DoClick = function() spawn(model) end
		local baseEnter = icon.OnCursorEntered
		icon.OnCursorEntered = function(s2)
			if baseEnter then baseEnter(s2) end
			if not IsValid(preview) then return end
			if not preview.SPPath then
				preview:SetModel(model)
			else
				preview.SPWant, preview.SPWantT = model, RealTime()
			end
		end
		icon.OpenMenu = function()
			local menu = SPeditor.UI.Menu()
			menu:AddOption(L("spawn"), function() spawn(model) end)
			menu:AddOption(L("copy_path"), function()
				SetClipboardText(model)
				SPeditor.Notify("#path_copied|" .. model, 0)
			end)
			menu:AddOption(L("browser_rerender"), function()
				if IsValid(icon) then icon:RebuildSpawnIcon() end
			end):SetIcon("icon16/arrow_refresh.png")
			menu:Open()
		end
	end

	local addMore
	function addMore()
		if #pending <= shownCount then return end
		local more = vgui.Create("DButton", icons)
		more:SetSize(UI.S(132), UI.S(64))
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
		elseif current.kind == "folder" or current.kind == "source" then
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
			-- the search runs over all models; inside an addon or a game — over its models
			if current.kind ~= "all" and current.kind ~= "source" and v ~= "" then current = { kind = "all" } end
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

	-- other windows open the browser on a category: UI.BrowserShow("cat", "Ragdolls") (cl_ui_ase.lua)
	UI.BrowserSelect = function(kind, name)
		if not IsValid(icons) then return end
		if kind == "cat" and not collectCategories()[name] then kind = "all" end
		select(kind, name)
	end

	local allNode = tree:AddNode(L("browser_all"), "icon16/database.png")
	allNode.DoClick = function() select("all") end
	UI.NodeColor(allNode, COL.TEXT)

	-- Workshop subscriptions and mounted games, each with its models
	local function openSource(pathId, title, prefix)
		local key = pathId .. "|" .. (prefix or "")
		current = { kind = "source", name = key, list = {} }
		search:SetValue("")
		lastQ = ""
		scanSource(pathId, function(list, finished)
			if current.kind ~= "source" or current.name ~= key or not IsValid(icons) then return end
			current.list = list
			-- while indexing, show what is found every so often
			if finished or #list ~= (current.shown or 0) and RealTime() > (current.nextShow or 0) then
				current.shown = #list
				current.nextShow = RealTime() + 0.5
				refresh()
				status:SetText(string.format(L("browser_source_status"), title, #list, finished and "" or (" — " .. L("browser_indexing"))))
			end
		end, prefix)
	end

	local addonsNode = tree:AddNode(L("browser_addons"), "icon16/plugin.png")
	UI.NodeColor(addonsNode, COL.ORANGE)
	local function fillAddons()
		for _, n in ipairs(addonsNode:GetChildNodes() or {}) do n:Remove() end
		local list = addonsWithModels(addonFilter:GetValue())
		for _, a in ipairs(list) do
			local n = addonsNode:AddNode(string.format("%s (%d)", a.title, a.models or 0), "icon16/package.png")
			UI.NodeColor(n, COL.TEXT)
			n:SetTooltip(a.title .. (a.wsid and a.wsid ~= "0" and ("\nWorkshop: " .. a.wsid) or ""))
			n.DoClick = function() openSource(a.title, a.title) end
		end
		addonsNode:SetText(string.format("%s (%d)", L("browser_addons"), #list))
		addonsNode:InvalidateLayout(true)
		tree:InvalidateLayout(true)
	end
	fillAddons()
	addonFilter.OnChange = function()
		addonsNode:SetExpanded(true)
		fillAddons()
	end
	sortBox.OnSelect = function(_, _, _, id)
		RunConsoleCommand("gmfm_browser_sort", id)
		timer.Simple(0, function()
			if not IsValid(addonsNode) then return end
			addonsNode:SetExpanded(true)
			fillAddons()
		end)
	end

	local games = {}
	for _, g in ipairs(engine.GetGames() or {}) do
		if g.mounted and g.folder then games[#games + 1] = g end
	end
	if #games > 0 then
		table.sort(games, function(x, y) return string.lower(x.title) < string.lower(y.title) end)
		local gamesNode = tree:AddNode(L("browser_games"), "icon16/joystick.png")
		UI.NodeColor(gamesNode, COL.ORANGE)
		for _, g in ipairs(games) do
			local n = gamesNode:AddNode(g.title, "icon16/controller.png")
			UI.NodeColor(n, COL.TEXT)
			n.DoClick = function() openSource(g.folder, g.title) end
		end
	end

	-- legacy addons (folders in garrysmod/addons) with models
	local legacy = {}
	for _, a in ipairs(UI.LegacyAddons()) do
		if a.models then legacy[#legacy + 1] = a end
	end
	if #legacy > 0 then
		local legacyNode = tree:AddNode(string.format("%s (%d)", L("browser_legacy"), #legacy), "icon16/folder_wrench.png")
		UI.NodeColor(legacyNode, COL.ORANGE)
		legacyNode:SetTooltip(L("browser_legacy_tip"))
		for _, a in ipairs(legacy) do
			local n = legacyNode:AddNode(a.name, "icon16/folder_page.png")
			UI.NodeColor(n, COL.TEXT)
			n:SetTooltip("garrysmod/addons/" .. a.name)
			n.DoClick = function() openSource("MOD", a.name, "addons/" .. a.name .. "/") end
		end
	end

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

-- the skin picked in the browser's preview goes onto the model a click has just put in (b0.2.6)
SPeditor.Hook("SPeditor_ObjectSpawned", "SPeditor.SpawnSkin", function(ent)
	local s = C.spawnSkin
	if not s or RealTime() > s.untilT or not IsValid(ent) then return end
	if string.lower(ent:GetModel() or "") ~= s.model then return end
	C.spawnSkin = nil
	C.SendSkin(ent, s.skin, true)
end)
