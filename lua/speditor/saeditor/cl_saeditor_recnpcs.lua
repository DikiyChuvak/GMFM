--[[
SAeditor — the NPCs of a take (b0.2.1). Before a gameplay take the player picks NPCs from the
spawn menu's list (Workshop ones too) and puts each where it should stand: Place, then a click in
the Primary Viewport puts it on whatever is under the cursor, the wheel turns it. Every mark keeps
its NPC, its weapon and how it treats the player (as it is / hostile / friendly). The marks are
drawn in the viewports (a ghost of the model, the way it faces, its name), never in a render; they
are kept per map in data/speditor/rec_npcs/<map>.json. When the take starts the server spawns the
NPCs on the marks (sv_saeditor_record.lua SA.PrepareTake); they are recorded as any NPC around,
and taken away after the take unless the player keeps them.
In the GM:FM gamemode this is the only way to get NPCs: there is no spawn menu.
]]
local COMP = SPeditor.Component("saeditor")
local SA   = COMP.SA
local C    = SPeditor.Client
local UI   = SPeditor.UI
local Dock = SPeditor.Dock
local L    = SPeditor.L
local COL  = UI.PAL

local DIR = "speditor/rec_npcs"
local MAX_MARKS = 64
local cvWait    = CreateClientConVar("gmfm_rec_npc_wait", "1", true, false, "Recorder: the NPCs of the marks stand still until the take starts (their AI wakes with the recording)", 0, 1)
local cvCleanup = CreateClientConVar("gmfm_rec_npc_cleanup", "1", true, false, "Recorder: take the NPCs of the take away after it (they stay in the scene as recorded actors)", 0, 1)

SA.recNPCs = SA.recNPCs or nil      -- { { class, pos = Vector, yaw, weapon = "" | "none" | class, att = 0 as is | 1 hostile | 2 friendly } }

local function file_()
	return DIR .. "/" .. game.GetMap() .. ".json"
end

local function load()
	SA.recNPCs = {}
	local t = util.JSONToTable(file.Read(file_(), "DATA") or "") or {}
	for _, m in ipairs(t) do
		if isstring(m.class) and istable(m.pos) then
			SA.recNPCs[#SA.recNPCs + 1] = { class = m.class, pos = Vector(m.pos[1], m.pos[2], m.pos[3]), yaw = tonumber(m.yaw) or 0,
				weapon = isstring(m.weapon) and m.weapon or "", att = math.Clamp(tonumber(m.att) or 0, 0, 2) }
		end
	end
end

local function save()
	local t = {}
	for i, m in ipairs(SA.recNPCs or {}) do
		t[i] = { class = m.class, pos = { m.pos.x, m.pos.y, m.pos.z }, yaw = m.yaw, weapon = m.weapon, att = m.att }
	end
	file.CreateDir(DIR)
	file.Write(file_(), util.TableToJSON(t))
end

function SA.RecNPCList()
	if not SA.recNPCs then load() end
	return SA.recNPCs
end

-- what the server gets with the take
function SA.RecNPCsForTake()
	local out = {}
	for i, m in ipairs(SA.RecNPCList()) do
		out[i] = { class = m.class, pos = m.pos, yaw = m.yaw, weapon = m.weapon, att = m.att }
	end
	return out, cvCleanup:GetBool(), cvWait:GetBool()
end

---------------------------------------------------------------------
-- The NPC types of the spawn menu
---------------------------------------------------------------------
-- a name cut to the width of a tile
local function fit(text, font, maxW)
	surface.SetFont(font)
	if surface.GetTextSize(text) <= maxW then return text end
	local n = utf8.len(text) or #text
	while n > 1 do
		n = n - 1
		local cut = utf8.sub(text, 1, n)
		if surface.GetTextSize(cut .. "…") <= maxW then return cut .. "…" end
	end
	return text
end

local function npcName(class, t)
	local name = t.Name or class
	if isstring(name) and string.sub(name, 1, 1) == "#" then name = language.GetPhrase(string.sub(name, 2)) end
	return tostring(name)
end

local function npcTypes()
	local out = {}
	local admin = IsValid(LocalPlayer()) and LocalPlayer():IsAdmin()
	for class, t in pairs(list.Get("NPC")) do
		if istable(t) and (not t.AdminOnly or admin) then
			out[#out + 1] = { class = class, name = npcName(class, t), category = tostring(t.Category or "Other"),
				icons = { t.IconOverride, "entities/" .. class .. ".png", "vgui/entities/" .. class } }
		end
	end
	table.sort(out, function(a, b)
		if a.category ~= b.category then return a.category < b.category end
		return string.lower(a.name) < string.lower(b.name)
	end)
	return out
end

local iconCache = {}
local function iconOf(n)
	if iconCache[n.class] == nil then
		iconCache[n.class] = false
		for _, path in pairs(n.icons) do
			local f = string.find(path, "%.%w+$") and path or (path .. ".vmt")
			if file.Exists("materials/" .. f, "GAME") then
				local m = Material(path, "smooth mips")
				if m and not m:IsError() then iconCache[n.class] = m break end
			end
		end
	end
	return iconCache[n.class] or nil
end

local function weaponChoices()
	local out = { { "", L("sa_npc_wpn_default") }, { "none", L("sa_npc_wpn_none") } }
	local list_ = {}
	for _, w in pairs(list.Get("NPCUsableWeapons")) do
		if istable(w) and isstring(w.class) then list_[#list_ + 1] = { w.class, language.GetPhrase(w.title or w.class) } end
	end
	table.sort(list_, function(a, b) return a[2] < b[2] end)
	for _, w in ipairs(list_) do out[#out + 1] = w end
	return out
end

local function weaponTitle(cls)
	for _, w in ipairs(weaponChoices()) do
		if w[1] == cls then return w[2] end
	end
	return cls
end

local ATT = { "sa_npc_att_asis", "sa_npc_att_hostile", "sa_npc_att_friendly" }

---------------------------------------------------------------------
-- The marks in the viewports: a ghost of the model, an arrow the way it faces
---------------------------------------------------------------------
local ghosts = {}           -- [model] = ClientsideModel
-- NPCs whose spawn menu entry names no model: the one the game gives them
local CLASS_MODELS = {
	npc_metropolice = "models/police.mdl", npc_combine_s = "models/combine_soldier.mdl", npc_zombie = "models/zombie/classic.mdl",
	npc_fastzombie = "models/zombie/fast.mdl", npc_poisonzombie = "models/zombie/poison.mdl", npc_zombine = "models/zombie/zombie_soldier.mdl",
	npc_antlion = "models/antlion.mdl", npc_antlionguard = "models/antlion_guard.mdl", npc_alyx = "models/alyx.mdl", npc_barney = "models/barney.mdl",
	npc_monk = "models/monk.mdl", npc_kleiner = "models/kleiner.mdl", npc_eli = "models/eli.mdl", npc_gman = "models/gman_high.mdl",
	npc_breen = "models/breen.mdl", npc_vortigaunt = "models/vortigaunt.mdl", npc_hunter = "models/hunter.mdl", npc_dog = "models/dog.mdl",
	npc_mossman = "models/mossman.mdl", npc_headcrab = "models/headcrabclassic.mdl", npc_stalker = "models/stalker.mdl",
}
local CITIZEN_GROUP = { [1] = "group01", [2] = "group02", [3] = "group03", [4] = "group03m" }

local function modelOf(t, class)
	if isstring(t.Model) and t.Model ~= "" then return t.Model end
	local cls = t.Class or class
	if cls == "npc_citizen" then
		local kv = t.KeyValues or {}
		return "models/humans/" .. (CITIZEN_GROUP[tonumber(kv.citizentype) or 1] or "group01") .. "/male_07.mdl"
	end
	return CLASS_MODELS[cls]
end

local function ghostOf(class)
	local t = list.Get("NPC")[class]
	local mdl = t and modelOf(t, class)
	if not isstring(mdl) or mdl == "" or not file.Exists(mdl, "GAME") then return nil end
	local g = ghosts[mdl]
	if not IsValid(g) then
		g = ClientsideModel(mdl, RENDERGROUP_OPAQUE)
		if not IsValid(g) then return nil end
		g:SetNoDraw(true)
		g:SetIK(false)
		local seq = g:LookupSequence("idle_all_01")
		if seq < 0 then seq = g:LookupSequence("idle01") end
		if seq < 0 then seq = 0 end
		g:ResetSequence(seq)
		ghosts[mdl] = g
	end
	return g
end

local preview                       -- { pos, yaw } under the cursor while placing
local placing                       -- { class, index = mark being moved or nil, yaw }
local selectedMark                  -- index of the mark chosen in the window
local MARK_COL, SEL_COL, PRE_COL = Color(90, 200, 255), Color(255, 190, 60), Color(120, 255, 120)

local function drawMark(class, pos, yaw, col)
	local g = ghostOf(class)
	local ang = Angle(0, yaw, 0)
	if g then
		g:SetPos(pos)
		g:SetAngles(ang)
		g:SetupBones()
		render.SetColorModulation(col.r / 255, col.g / 255, col.b / 255)
		render.SetBlend(0.7)
		g:DrawModel()
		render.SetBlend(1)
		render.SetColorModulation(1, 1, 1)
	else
		render.DrawWireframeBox(pos, ang, Vector(-14, -14, 0), Vector(14, 14, 72), col, true)
	end
	render.SetColorMaterialIgnoreZ()
	local f = ang:Forward()
	render.DrawBeam(pos + Vector(0, 0, 2), pos + Vector(0, 0, 2) + f * 40, 1, 0, 1, col)
	render.DrawBeam(pos + Vector(0, 0, 2) + f * 40, pos + Vector(0, 0, 2) + f * 30 + ang:Right() * 8, 1, 0, 1, col)
	render.DrawBeam(pos + Vector(0, 0, 2) + f * 40, pos + Vector(0, 0, 2) + f * 30 - ang:Right() * 8, 1, 0, 1, col)
end

SPeditor.Hook("GMFM_DrawHelpers3D", "SAeditor.RecNPCs", function()
	local list_ = SA.RecNPCList()
	for i, m in ipairs(list_) do
		if not (placing and placing.index == i) then drawMark(m.class, m.pos, m.yaw, i == selectedMark and SEL_COL or MARK_COL) end
	end
	if placing and preview then drawMark(placing.class, preview.pos, placing.yaw, PRE_COL) end
end)

SPeditor.Hook("GMFM_ViewportOverlay", "SAeditor.RecNPCs", function(view, ix, iy, iw, ih)
	local list_ = SA.RecNPCList()
	if #list_ == 0 and not placing then return end
	local ox, oy = view:LocalToScreen(0, 0)
	local types = list.Get("NPC")
	for i, m in ipairs(list_) do
		local x, y, vis = C.ProjectToViewport(m.pos + Vector(0, 0, 80))
		if vis then
			local t = types[m.class]
			draw.SimpleTextOutlined(i .. ". " .. (t and npcName(m.class, t) or m.class), "SPeditor.Small", x - ox, y - oy,
				i == selectedMark and SEL_COL or MARK_COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, color_black)
		end
	end
	if placing then
		local text = L(placing.index and "sa_npc_hint_move" or "sa_npc_hint_place")
		draw.RoundedBox(4, ix + iw / 2 - 260, iy + 10, 520, 26, Color(0, 0, 0, 190))
		draw.SimpleText(text, "SPeditor.Bold", ix + iw / 2, iy + 23, PRE_COL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
end)

---------------------------------------------------------------------
-- Placing: a click in the Primary Viewport (cl_gizmo.lua C.placeTool)
---------------------------------------------------------------------
local function traceCursor()
	local origin, dir = C.MouseRay()
	local tr = util.TraceLine({ start = origin, endpos = origin + dir * 32768, mask = MASK_SOLID,
		filter = function(e) return e ~= LocalPlayer() and not SPeditor.IsEditable(e) end })
	if not tr.Hit then return nil end
	return tr.HitPos + tr.HitNormal * 1
end

local onChanged                     -- the window refreshes its list
local function stopPlacing()
	placing, preview = nil, nil
	C.placeTool = nil
	if onChanged then onChanged() end
end
SA.RecNPCStopPlacing = stopPlacing

local function startPlacing(class, index)
	if not class then return end
	local m = index and SA.RecNPCList()[index]
	placing = { class = class, index = index, yaw = m and m.yaw or (C.camera and C.camera.angles and C.camera.angles.y + 180 or 0) }
	C.placeTool = {
		click = function()
			local pos = traceCursor()
			if not pos then return end
			local list_ = SA.RecNPCList()
			if placing.index and list_[placing.index] then
				list_[placing.index].pos = pos
				list_[placing.index].yaw = placing.yaw
				save()
				stopPlacing()
				return
			end
			if #list_ >= MAX_MARKS then
				SPeditor.Notify(string.format(L("sa_npc_max"), MAX_MARKS), 1)
				return
			end
			list_[#list_ + 1] = { class = placing.class, pos = pos, yaw = placing.yaw, weapon = placing.weapon or "", att = placing.att or 0 }
			selectedMark = #list_
			save()
			surface.PlaySound("garrysmod/ui_click.wav")
			if onChanged then onChanged() end
		end,
		wheel = function(d)
			placing.yaw = math.NormalizeAngle(placing.yaw + d * 15)
		end,
	}
	if onChanged then onChanged() end
end

SPeditor.Hook("Think", "SAeditor.RecNPCs", function()
	if not placing then return end
	if not C.active then stopPlacing() return end
	local pos = C.MouseInViewport() and traceCursor()
	preview = pos and { pos = pos } or nil
end)

-- Esc ends the placing instead of opening the game menu
SPeditor.Hook("OnPauseMenuShow", "SAeditor.RecNPCs", function()
	if placing then
		stopPlacing()
		return false
	end
end)

---------------------------------------------------------------------
-- The window
---------------------------------------------------------------------
function SA.OpenNPCPicker()
	local old = Dock.ByKey("sa_recnpcs")
	if old then old:Remove() end
	local W, H = math.min(660, ScrW() - 80), math.min(780, ScrH() - 120)
	local win, body = Dock.Create({ key = "sa_recnpcs", id = "sa_recnpcs", title = L("sa_npc_title"),
		w = W, h = H, x = ScrW() - W - 30, y = 80, dockable = false, icon = "icon16/group.png" })
	win.minW, win.minH = UI.S(480), UI.S(420)
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.sa_recnpcs = nil
		onChanged = nil
		if placing then stopPlacing() end
		selectedMark = nil
	end

	local hint = UI.Label(body, L("sa_npc_hint"), COL.TEXT)
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:DockMargin(8, 8, 8, 4)

	local current           -- the NPC type chosen in the tiles
	local newWeapon, newAtt = "", 0

	-- the bottom: the marks
	local bottom = vgui.Create("DPanel", body)
	bottom:Dock(BOTTOM)
	bottom:SetTall(UI.S(296))
	bottom:DockPadding(8, 4, 8, 6)
	bottom.Paint = function(_, w)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(0, 0, w, 1)
	end

	local btns = vgui.Create("DPanel", bottom)
	btns:Dock(TOP)
	btns:SetTall(UI.S(28))
	btns.Paint = function() end
	local place = UI.Button(btns, L("sa_npc_place"), "icon16/add.png", nil)
	place:Dock(LEFT)
	place:SetWide(UI.S(190))
	place:DockMargin(0, 2, 4, 2)
	UI.StyleButton(place, true)
	local move = UI.Button(btns, L("sa_npc_move"), "icon16/arrow_out.png", nil)
	move:Dock(LEFT)
	move:SetWide(UI.S(120))
	move:DockMargin(0, 2, 4, 2)
	local del = UI.Button(btns, L("delete"), "icon16/delete.png", nil)
	del:Dock(LEFT)
	del:SetWide(UI.S(100))
	del:DockMargin(0, 2, 4, 2)
	local clear = UI.Button(btns, L("sa_wpn_clear"), "icon16/cross.png", nil)
	clear:Dock(LEFT)
	clear:SetWide(UI.S(100))
	clear:DockMargin(0, 2, 4, 2)

	local opts = vgui.Create("DPanel", bottom)
	opts:Dock(TOP)
	opts:SetTall(UI.S(26))
	opts:DockMargin(0, 4, 0, 0)
	opts.Paint = function() end
	local wl = vgui.Create("DLabel", opts)
	wl:Dock(LEFT)
	wl:SetWide(UI.S(60))
	wl:SetFont("SPeditor.Small")
	wl:SetTextColor(COL.TEXT)
	wl:SetText(L("sa_npc_weapon"))
	local wBox = UI.StyleCombo(vgui.Create("DComboBox", opts))
	wBox:Dock(LEFT)
	wBox:SetWide(UI.S(220))
	wBox:SetSortItems(false)
	for _, w in ipairs(weaponChoices()) do wBox:AddChoice(w[2], w[1], w[1] == "") end
	local aBox = UI.StyleCombo(vgui.Create("DComboBox", opts))
	aBox:Dock(FILL)
	aBox:DockMargin(6, 0, 0, 0)
	aBox:SetSortItems(false)
	for i, k in ipairs(ATT) do aBox:AddChoice(L(k), i - 1, i == 1) end

	local foot = vgui.Create("DPanel", bottom)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(30))
	foot:DockMargin(0, 4, 0, 0)
	foot.Paint = function() end
	local keep = UI.Check(foot, L("sa_npc_cleanup"), cvCleanup:GetBool(), function(v) RunConsoleCommand("gmfm_rec_npc_cleanup", v and "1" or "0") end)
	keep:Dock(LEFT)
	keep:SetWide(UI.S(330))
	local wait = UI.Check(bottom, L("sa_npc_wait"), cvWait:GetBool(), function(v) RunConsoleCommand("gmfm_rec_npc_wait", v and "1" or "0") end)
	wait:Dock(BOTTOM)
	wait:SetTooltip(L("sa_npc_wait_tip"))
	local done = UI.Button(foot, L("sa_wpn_done"), "icon16/tick.png", function() win:Remove() end)
	done:Dock(RIGHT)
	done:SetWide(UI.S(120))
	UI.StyleButton(done, true)

	local far = UI.Label(bottom, "", COL.ORANGE)
	far:Dock(BOTTOM)

	local marks = vgui.Create("DListView", bottom)
	marks:Dock(FILL)
	marks:DockMargin(0, 4, 0, 0)
	marks:SetMultiSelect(false)
	marks:AddColumn("#"):SetFixedWidth(UI.S(28))
	marks:AddColumn(L("sa_npc_col_npc"))
	marks:AddColumn(L("sa_npc_weapon"))
	marks:AddColumn(L("sa_npc_col_att"))
	UI.Skin(marks)

	local syncing = false
	local function refresh()
		if not IsValid(marks) or syncing then return end
		syncing = true
		marks:Clear()
		local types = list.Get("NPC")
		local nFar, radius = 0, GetConVar("gmfm_rec_radius"):GetFloat()
		local me = LocalPlayer()
		for i, m in ipairs(SA.RecNPCList()) do
			local t = types[m.class]
			local line = marks:AddLine(i, t and npcName(m.class, t) or m.class, weaponTitle(m.weapon), L(ATT[m.att + 1]))
			line.SPIndex = i
			if i == selectedMark then marks:SelectItem(line) end
			if IsValid(me) and me:GetPos():Distance(m.pos) > radius then nFar = nFar + 1 end
		end
		far:SetText(nFar > 0 and string.format(L("sa_npc_far"), nFar, math.floor(radius)) or "")
		local text = (UI.ButtonPad or "  ") .. L(placing and not placing.index and "sa_npc_place_stop" or "sa_npc_place")
		place:SetText(text)
		-- the combos follow the chosen mark
		local m = selectedMark and SA.RecNPCList()[selectedMark]
		for i, w in ipairs(weaponChoices()) do
			if w[1] == (m and m.weapon or newWeapon) then wBox:ChooseOptionID(i) break end
		end
		aBox:ChooseOptionID((m and m.att or newAtt) + 1)
		syncing = false
	end
	onChanged = refresh

	marks.OnRowSelected = function(_, _, line)
		if syncing then return end
		selectedMark = line.SPIndex
		refresh()
	end
	marks.DoDoubleClick = function(_, _, line)
		-- the work camera goes to look at the mark
		local m = SA.RecNPCList()[line.SPIndex]
		if m and C.camera then
			local target = m.pos + Vector(0, 0, 40)
			local from = target - (C.camera.angles or Angle()):Forward() * 220
			C.camera.target, C.camera.pos = from, from
		end
	end
	wBox.OnSelect = function(_, _, _, data)
		if syncing then return end
		local m = selectedMark and SA.RecNPCList()[selectedMark]
		if m then m.weapon = data save() refresh() else newWeapon = data end
		if placing then placing.weapon = data end
	end
	aBox.OnSelect = function(_, _, _, data)
		if syncing then return end
		local m = selectedMark and SA.RecNPCList()[selectedMark]
		if m then m.att = data save() refresh() else newAtt = data end
		if placing then placing.att = data end
	end
	place.DoClick = function()
		if placing and not placing.index then stopPlacing() return end
		if not current then SPeditor.Notify(L("sa_npc_pick_first"), 1) return end
		selectedMark = nil
		startPlacing(current)
		placing.weapon, placing.att = newWeapon, newAtt
	end
	move.DoClick = function()
		local m = selectedMark and SA.RecNPCList()[selectedMark]
		if not m then SPeditor.Notify(L("sa_npc_select_mark"), 1) return end
		startPlacing(m.class, selectedMark)
	end
	del.DoClick = function()
		if not selectedMark then return end
		table.remove(SA.RecNPCList(), selectedMark)
		selectedMark = nil
		save()
		refresh()
	end
	clear.DoClick = function()
		if #SA.RecNPCList() == 0 then return end
		Derma_Query(L("sa_npc_clear_q"), "GM:FM", L("yes"), function()
			SA.recNPCs = {}
			selectedMark = nil
			save()
			refresh()
		end, L("cancel"), function() end)
	end

	-- the top: the NPC types
	local top = vgui.Create("DPanel", body)
	top:Dock(TOP)
	top:DockMargin(8, 2, 8, 4)
	top:SetTall(UI.S(24))
	top.Paint = function() end
	local search = vgui.Create("DTextEntry", top)
	search:Dock(LEFT)
	search:SetWide(UI.S(220))
	search:SetPlaceholderText(L("sa_npc_search"))
	search:SetUpdateOnType(true)
	local catBox = UI.StyleCombo(vgui.Create("DComboBox", top))
	catBox:Dock(FILL)
	catBox:DockMargin(6, 0, 0, 0)
	catBox:SetSortItems(false)
	catBox:AddChoice(L("sa_wpn_all"), "", true)
	local all = npcTypes()
	local seen = {}
	for _, n in ipairs(all) do
		if not seen[n.category] then
			seen[n.category] = true
			catBox:AddChoice(n.category, n.category)
		end
	end

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

	local function tile(n)
		local t = grid:Add("DButton")
		t:SetSize(UI.S(84), UI.S(84))
		t:SetText("")
		t:SetTooltip(n.name .. "\n" .. n.class .. "\n" .. n.category)
		local icon = iconOf(n)
		t.Paint = function(s, tw, th)
			local on = current == n.class
			surface.SetDrawColor(on and (COL.TAB_ON or COL.BLUE) or (s:IsHovered() and COL.ROW_B or COL.HEADER))
			surface.DrawRect(0, 0, tw, th)
			local isz = th - 22
			if icon then
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(icon)
				surface.DrawTexturedRect(math.floor((tw - isz) / 2), 3, isz, isz)
			end
			s.SPLabel = s.SPLabel or fit(n.name, "SPeditor.Small", tw - 4)
			draw.SimpleText(s.SPLabel, "SPeditor.Small", tw / 2, th - 10, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			surface.SetDrawColor(on and COL.ORANGE or COL.BORDER)
			surface.DrawOutlinedRect(0, 0, tw, th, on and 2 or 1)
		end
		t.DoClick = function()
			current = n.class
			-- a new type while placing: the next clicks put this one
			if placing and not placing.index then placing.class = n.class end
		end
		t.DoDoubleClick = function()
			current = n.class
			selectedMark = nil
			startPlacing(current)
			placing.weapon, placing.att = newWeapon, newAtt
		end
	end

	local function rebuild()
		grid:Clear()
		local q = string.lower(search:GetValue() or "")
		local _, cat = catBox:GetSelected()
		cat = cat or ""
		local lastCat
		for _, n in ipairs(all) do
			if (cat == "" or n.category == cat) and (q == "" or string.find(string.lower(n.name), q, 1, true) or string.find(n.class, q, 1, true)) then
				if n.category ~= lastCat then
					lastCat = n.category
					local hd = grid:Add("DLabel")
					hd.OwnLine = true
					hd:SetTall(UI.S(18))
					hd:SetWide(math.max(grid:GetWide(), UI.S(300)))
					hd:SetFont("SPeditor.Bold")
					hd:SetTextColor(COL.ORANGE)
					hd:SetText(n.category)
				end
				tile(n)
			end
		end
		grid:Layout()
	end
	search.OnValueChange = rebuild
	catBox.OnSelect = rebuild
	rebuild()
	refresh()
	return win
end

concommand.Add("gmfm_rec_npcs_pick", function() SA.OpenNPCPicker() end)
