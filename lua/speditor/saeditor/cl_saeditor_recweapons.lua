--[[
SAeditor — the weapons of a take (b0.2.1). Before a gameplay take the player picks one or more
weapons from the spawn menu's list (Workshop weapons included, grouped by their category); "Done"
gives them (sv_saeditor_record.lua SA.PrepareTake) and starts the countdown. In the GM:FM gamemode
this step is always there — there is no Q menu to take a weapon from; in Sandbox it is an option
of the Record window (gmfm_rec_weapons).
]]
local COMP = SPeditor.Component("saeditor")
local SA   = COMP.SA
local UI   = SPeditor.UI
local Dock = SPeditor.Dock
local L    = SPeditor.L
local COL  = UI.PAL

local TILE_W, TILE_H = 112, 100
local gunIcon = Material("icon16/gun.png")

-- the weapons a player may take: { class, name, category, icon }, sorted by category and name
local function weaponList()
	local out = {}
	local admin = IsValid(LocalPlayer()) and LocalPlayer():IsAdmin()
	for class, w in pairs(list.Get("Weapon")) do
		-- what the spawn menu shows: spawnable ones (base classes are not), admin-only ones for admins
		if istable(w) and w.Spawnable and (not w.AdminOnly or admin) then
			local name = w.PrintName or class
			if isstring(name) and string.sub(name, 1, 1) == "#" then name = language.GetPhrase(string.sub(name, 2)) end
			out[#out + 1] = { class = class, name = tostring(name), category = tostring(w.Category or "Other"),
				icons = { w.IconOverride, "entities/" .. class .. ".png", "vgui/entities/" .. class } }
		end
	end
	table.sort(out, function(a, b)
		if a.category ~= b.category then return a.category < b.category end
		return string.lower(a.name) < string.lower(b.name)
	end)
	return out
end

-- a name cut to the width of a tile
local function fit(text, font, maxW)
	surface.SetFont(font)
	if surface.GetTextSize(text) <= maxW then return text end
	local n = utf8.len(text) or #text
	while n > 1 do
		n = n - 1
		local cut = utf8.sub and utf8.sub(text, 1, n) or string.sub(text, 1, n)
		if surface.GetTextSize(cut .. "…") <= maxW then return cut .. "…" end
	end
	return text
end

-- the spawn menu's picture of a weapon: its own, entities/<class>.png, or the old vgui/entities/<class>
local iconCache = {}
local function iconOf(w)
	if iconCache[w.class] == nil then
		iconCache[w.class] = false
		for _, path in pairs(w.icons) do
			local file_ = string.find(path, "%.%w+$") and path or (path .. ".vmt")
			if file.Exists("materials/" .. file_, "GAME") then
				local m = Material(path, "smooth mips")
				if m and not m:IsError() then
					iconCache[w.class] = m
					break
				end
			end
		end
	end
	return iconCache[w.class] or nil
end

-- startAfter = true: "Done" starts the take (the Record window's Start recording)
function SA.OpenWeaponPicker(startAfter)
	local old = Dock.ByKey("sa_recweapons")
	if old then old:Remove() end
	local win, body = Dock.Create({ key = "sa_recweapons", id = "sa_recweapons", title = L("sa_wpn_title"),
		w = math.min(760, ScrW() - 80), h = math.min(600, ScrH() - 120),
		x = math.floor(ScrW() / 2 - math.min(760, ScrW() - 80) / 2), y = 90, dockable = false, icon = "icon16/gun.png" })
	win.minW, win.minH = UI.S(480), UI.S(360)
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.sa_recweapons = nil
	end

	local chosen, order = {}, {}
	for _, class in ipairs(SA.RecWeaponList()) do
		if not chosen[class] then
			chosen[class] = true
			order[#order + 1] = class
		end
	end
	local all = weaponList()
	local known = {}
	for _, w in ipairs(all) do known[w.class] = true end
	-- a weapon of an addon that is gone is not kept in the choice
	for i = #order, 1, -1 do
		if not known[order[i]] then
			chosen[order[i]] = nil
			table.remove(order, i)
		end
	end

	local hint = UI.Label(body, L(SPeditor.FilmMode() and "sa_wpn_hint_mode" or "sa_wpn_hint"), COL.TEXT)
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:DockMargin(8, 8, 8, 4)

	-- search and category
	local top = vgui.Create("DPanel", body)
	top:Dock(TOP)
	top:DockMargin(8, 2, 8, 4)
	top:SetTall(UI.S(24))
	top.Paint = function() end
	local search = vgui.Create("DTextEntry", top)
	search:Dock(LEFT)
	search:SetWide(UI.S(240))
	search:SetPlaceholderText(L("sa_wpn_search"))
	search:SetUpdateOnType(true)
	local catBox = UI.StyleCombo(vgui.Create("DComboBox", top))
	catBox:Dock(FILL)
	catBox:DockMargin(6, 0, 0, 0)
	catBox:SetSortItems(false)
	catBox:AddChoice(L("sa_wpn_all"), "", true)
	catBox:AddChoice(L("sa_wpn_chosen_only"), "\1")
	local cats, seen = {}, {}
	for _, w in ipairs(all) do
		if not seen[w.category] then
			seen[w.category] = true
			cats[#cats + 1] = w.category
		end
	end
	for _, c in ipairs(cats) do catBox:AddChoice(c, c) end

	-- the bottom: what is chosen, options, buttons
	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(88))
	foot:DockPadding(8, 4, 8, 6)
	foot.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(0, 0, w, 1)
	end
	local opts = vgui.Create("DPanel", foot)
	opts:Dock(TOP)
	opts:SetTall(UI.S(24))
	opts.Paint = function() end
	local strip = UI.Check(opts, L("sa_wpn_strip"), GetConVar("gmfm_rec_strip"):GetBool(), function(v)
		RunConsoleCommand("gmfm_rec_strip", v and "1" or "0")
	end)
	strip:Dock(LEFT)
	strip:SetWide(UI.S(260))
	local ammo = UI.Slider(opts, L("sa_wpn_ammo"), 0, 999, 0, GetConVar("gmfm_rec_ammo"):GetInt(), function(v)
		RunConsoleCommand("gmfm_rec_ammo", tostring(math.floor(v + 0.5)))
	end)
	ammo:Dock(FILL)

	local btns = vgui.Create("DPanel", foot)
	btns:Dock(BOTTOM)
	btns:SetTall(UI.S(32))
	btns.Paint = function() end
	local count = vgui.Create("DLabel", btns)
	count:Dock(LEFT)
	count:SetWide(UI.S(220))
	count:SetFont("SPeditor.Bold")
	count:SetTextColor(COL.ORANGE)
	local cancel = UI.Button(btns, L("cancel"), nil, function() win:Remove() end)
	cancel:Dock(RIGHT)
	cancel:SetWide(UI.S(110))
	cancel:DockMargin(4, 3, 0, 3)
	local done = UI.Button(btns, L(startAfter and "sa_wpn_done_go" or "sa_wpn_done"), startAfter and "icon16/webcam.png" or "icon16/tick.png", nil)
	done:Dock(RIGHT)
	done:SetWide(UI.S(startAfter and 230 or 130))
	done:DockMargin(4, 3, 0, 3)
	UI.StyleButton(done, true)
	local clear = UI.Button(btns, L("sa_wpn_clear"), "icon16/cross.png", nil)
	clear:Dock(RIGHT)
	clear:SetWide(UI.S(110))
	clear:DockMargin(4, 3, 0, 3)

	-- the tiles
	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	scroll:DockMargin(8, 0, 8, 4)
	scroll.Paint = function(_, w, h)
		surface.SetDrawColor(COL.VIEW_BG or COL.BG)
		surface.DrawRect(0, 0, w, h)
	end
	local grid = vgui.Create("DIconLayout", scroll)
	grid:Dock(TOP)
	grid:SetSpaceX(4)
	grid:SetSpaceY(4)
	grid:DockMargin(4, 4, 4, 4)

	local function updateCount()
		count:SetText(string.format(L("sa_wpn_count"), #order))
		-- the take needs at least one weapon when the step is asked
		done:SetEnabled(#order > 0)
	end

	local function tile(w)
		local t = grid:Add("DButton")
		t:SetSize(UI.S(TILE_W), UI.S(TILE_H))
		t:SetText("")
		t:SetTooltip(w.name .. "\n" .. w.class .. "\n" .. w.category)
		local icon = iconOf(w)
		t.Paint = function(s, tw, th)
			local on = chosen[w.class]
			surface.SetDrawColor(on and (COL.TAB_ON or COL.BLUE) or (s:IsHovered() and COL.ROW_B or COL.HEADER))
			surface.DrawRect(0, 0, tw, th)
			local isz = math.min(tw - 16, th - 30)
			if icon then
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(icon)
				surface.DrawTexturedRect(math.floor((tw - isz) / 2), 4, isz, isz)
			else
				surface.SetDrawColor(0, 0, 0, 60)
				surface.DrawRect(math.floor((tw - isz) / 2), 4, isz, isz)
				surface.SetDrawColor(255, 255, 255, 90)
				surface.SetMaterial(gunIcon)
				surface.DrawTexturedRect(math.floor(tw / 2 - 8), math.floor(4 + isz / 2 - 8), 16, 16)
			end
			s.SPLabel = s.SPLabel or fit(w.name, "SPeditor.Small", tw - 6)
			draw.SimpleText(s.SPLabel, "SPeditor.Small", tw / 2, th - 13, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			if on then
				surface.SetDrawColor(COL.ORANGE)
				surface.DrawOutlinedRect(0, 0, tw, th, 2)
				-- the number in the order the weapons are given (the first one is in the hands)
				local n = table.KeyFromValue(order, w.class) or 0
				draw.RoundedBox(4, tw - 22, 4, 18, 18, COL.ORANGE)
				draw.SimpleText(tostring(n), "SPeditor.Bold", tw - 13, 13, color_black, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			else
				surface.SetDrawColor(COL.BORDER)
				surface.DrawOutlinedRect(0, 0, tw, th, 1)
			end
		end
		t.DoClick = function()
			if chosen[w.class] then
				chosen[w.class] = nil
				table.RemoveByValue(order, w.class)
			else
				chosen[w.class] = true
				order[#order + 1] = w.class
			end
			surface.PlaySound("garrysmod/ui_click.wav")
			updateCount()
		end
		return t
	end

	local function rebuild()
		grid:Clear()
		local q = string.lower(search:GetValue() or "")
		local _, cat = catBox:GetSelected()
		cat = cat or ""
		local n, lastCat = 0, nil
		for _, w in ipairs(all) do
			local okCat = cat == "" or (cat == "\1" and chosen[w.class]) or w.category == cat
			local okText = q == "" or string.find(string.lower(w.name), q, 1, true) or string.find(w.class, q, 1, true)
			if okCat and okText then
				-- a heading line for every category, as the spawn menu
				if w.category ~= lastCat then
					lastCat = w.category
					local hd = grid:Add("DLabel")
					hd.OwnLine = true
					hd:SetTall(UI.S(20))
					hd:SetWide(math.max(grid:GetWide(), UI.S(300)))
					hd:SetFont("SPeditor.Bold")
					hd:SetTextColor(COL.ORANGE)
					hd:SetText(w.category)
				end
				tile(w)
				n = n + 1
			end
		end
		if n == 0 then
			local l = grid:Add("DLabel")
			l:SetText(L("sa_wpn_none"))
			l:SetFont("SPeditor.Small")
			l:SetTextColor(COL.DIM)
			l:SizeToContents()
		end
		grid:Layout()
	end
	search.OnValueChange = rebuild
	catBox.OnSelect = rebuild
	clear.DoClick = function()
		chosen, order = {}, {}
		updateCount()
	end
	done.DoClick = function()
		if #order == 0 then return end
		SA.RecSetWeaponList(order)
		win:Remove()
		if startAfter then
			-- the convar is written by the console a frame later: the list goes with the take itself
			timer.Simple(0.05, function() SA.StartRecording() end)
		end
	end
	updateCount()
	rebuild()
	return win
end

concommand.Add("gmfm_rec_weapons_pick", function() SA.OpenWeaponPicker() end)
