--[[
SPeditor — the "Take objects from the map" window (File → Take objects from the map…).

Lists what stands on the map but is not in the scene: ragdolls and props (posed with
Ragdoll Mover, the physgun…), lights and lamps of other addons (Advanced Light Entities,
Soft Lamps, stock lamps), other entities the duplicator can copy. The number in the
"With" column is how many bonemerged models (Advanced / Easy Bonemerge…) come along.
The server side and what happens to the objects: sv_adopt.lua.

A row under the cursor or selected is outlined in the viewports; Show turns the work
camera to it.

API:
  UI.OpenAdopt()       the window
  C.IsForeign(ent)     an object of another addon taken from the map
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI  = SPeditor.UI
local C   = SPeditor.Client
local L   = SPeditor.L
local Net = SPeditor.Net
local COL = UI.PAL

function C.IsForeign(e)
	return IsValid(e) and e:GetNW2String("SPeditor_Foreign", "") ~= ""
end

local KIND_ICON = { ragdoll = "icon16/user.png", prop = "icon16/box.png", light = "icon16/lightbulb.png", other = "icon16/brick.png" }

local state = { list = {}, onList = nil, outline = {} }

function C.SendAdoptList()
	net.Start(Net.AdoptList)
	net.SendToServer()
end

function C.SendAdopt(entsList)
	local n = math.min(#entsList, 1000)
	net.Start(Net.Adopt)
	net.WriteUInt(n, 10)
	for i = 1, n do net.WriteEntity(entsList[i]) end
	net.SendToServer()
end

net.Receive(Net.AdoptListData, function()
	local list = {}
	for _ = 1, net.ReadUInt(10) do
		list[#list + 1] = {
			ent = net.ReadEntity(), class = net.ReadString(), model = net.ReadString(),
			kind = net.ReadString(), extras = net.ReadUInt(8), name = net.ReadString(),
		}
	end
	state.list = list
	if state.onList then state.onList(list) end
end)

-- the outline of the rows under the cursor / selected, in every editor view
SPeditor.Hook("PostDrawTranslucentRenderables", "SPeditor.AdoptOutline", function(depth, sky)
	if depth or sky or not C.active or C.exporting or next(state.outline) == nil then return end
	local acc = COL.ORANGE
	for ent, hot in pairs(state.outline) do
		if IsValid(ent) then
			local mins, maxs = ent:GetRenderBounds()
			render.DrawWireframeBox(ent:GetPos(), ent:GetAngles(), mins, maxs,
				hot and Color(acc.r, acc.g, acc.b) or Color(255, 255, 255, 160), false)
		end
	end
end)

local function modelName(m)
	if not m or m == "" then return "" end
	return string.StripExtension(string.GetFileFromFilename(m))
end

function UI.OpenAdopt()
	local Dock = SPeditor.Dock
	if Dock.ShowPage("adopt") then
		C.SendAdoptList()
		return
	end
	local W, H = 620, 460
	local win, body = Dock.Create({ key = "adopt", id = "adopt", title = L("adopt_title"), w = W, h = H,
			x = math.floor(ScrW() / 2 - W / 2), y = 110, dockable = false, icon = "icon16/world_add.png" })
	win.minW, win.minH = UI.S(440), UI.S(260)

	local hint = UI.Label(body, L("adopt_hint"), COL.DIM)
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:DockMargin(8, 6, 8, 4)

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(34))
	foot.Paint = function() end

	local lv = vgui.Create("DListView", body)

	UI.StyleListView(lv)
	lv:Dock(FILL)
	lv:DockMargin(6, 0, 6, 0)
	lv:SetMultiSelect(true)
	lv:AddColumn(L("adopt_col_name"))
	lv:AddColumn(L("adopt_col_kind")):SetFixedWidth(90)
	lv:AddColumn(L("adopt_col_with")):SetFixedWidth(70)
	if lv.SetBackgroundColor then lv:SetBackgroundColor(COL.LIST_BG) end

	local function fill(list)
		if not IsValid(lv) then return end
		lv:Clear()
		for _, it in ipairs(list) do
			if IsValid(it.ent) then
				local name = it.name ~= "" and it.name or modelName(it.model)
				local line = lv:AddLine(name, L("adopt_kind_" .. it.kind), it.extras > 0 and ("+" .. it.extras) or "")
				line.item = it
				line:SetTooltip(it.class .. "\n" .. it.model)
				-- an icon of the kind in front of the name
				local icon = Material(KIND_ICON[it.kind] or KIND_ICON.other)
				local col = line.Columns[1]
				if IsValid(col) then
					col:SetTextInset(22, 0)
					local paint = col.Paint
					col.Paint = function(s, w, h)
						if paint then paint(s, w, h) end
						surface.SetMaterial(icon)
						surface.SetDrawColor(255, 255, 255, 255)
						local is = UI.IconSize(h + 3)
						surface.DrawTexturedRect(3, math.floor((h - is) / 2), is, is)
					end
				end
			end
		end
		if #list == 0 then lv:AddLine(L("adopt_none"), "", "") end
	end
	state.onList = fill
	fill(state.list)
	C.SendAdoptList()

	-- outline: the selected rows, and brighter — the one under the cursor
	lv.Think = function(s)
		local out = {}
		for _, line in ipairs(s:GetSelected()) do
			if line.item then out[line.item.ent] = false end
		end
		local hov = vgui.GetHoveredPanel()
		while IsValid(hov) and hov ~= s do
			if hov.item then out[hov.item.ent] = true break end
			hov = hov:GetParent()
		end
		state.outline = out
	end
	win.OnRemove = function() state.outline = {} state.onList = nil end
	local close = win.Close
	win.Close = function(...)
		state.outline = {}
		return close(...)
	end

	local function selectedEnts()
		local out = {}
		for _, line in ipairs(lv:GetSelected()) do
			if line.item and IsValid(line.item.ent) then out[#out + 1] = line.item.ent end
		end
		return out
	end

	local function take(list)
		if #list == 0 then
			SPeditor.Notify(L("adopt_pick"), 0)
			return
		end
		C.SendAdopt(list)
		timer.Simple(0.4, function() if IsValid(lv) then C.SendAdoptList() end end)
	end

	local function btn(text, icon, fn, dock)
		local b = vgui.Create("DButton", foot)
		b:Dock(dock or LEFT)
		b:DockMargin(dock == RIGHT and 4 or 8, 5, dock == RIGHT and 8 or 0, 5)
		surface.SetFont("SPeditor.Small")
		b:SetWide(select(1, surface.GetTextSize(text)) + UI.S(40))
		b:SetText("  " .. text)
		b:SetIcon(icon)
		UI.StyleButton(b, nil, 3)
		b.DoClick = fn
		return b
	end
	btn(L("adopt_take"), "icon16/add.png", function() take(selectedEnts()) end)
	btn(L("adopt_take_all"), "icon16/world_add.png", function()
		local all = {}
		for _, it in ipairs(state.list) do
			if IsValid(it.ent) then all[#all + 1] = it.ent end
		end
		take(all)
	end)
	btn(L("adopt_show"), "icon16/eye.png", function()
		local ent = selectedEnts()[1]
		if not IsValid(ent) then return end
		local radius = math.max(ent:BoundingRadius(), 20)
		C.camera.target = ent:WorldSpaceCenter() - C.camera.targetAngles:Forward() * (radius * 2.4)
	end)
	btn("", "icon16/arrow_refresh.png", function() C.SendAdoptList() end):SetWide(UI.S(30))
	btn(L("about_close"), "icon16/door_out.png", function() win:Close() end, RIGHT)

	lv.DoDoubleClick = function(_, _, line) if line.item then take({ line.item.ent }) end end
end
