--[[
SPeditor — the "Addon shaders" window (Windows → Addon shaders, a button in the Render window).

Two tabs:
  * "Addon effects" — everything registered in list "PostProcess": stock
    GMod post-processing and Workshop shaders (including those on GShader Library).
    On the left a list with the state (on / off), on the right — the effect's native
    settings panel, the same as in the Q menu. These effects get into the editor frame in
    "Engine frame" mode — its toggle is here and in the Render window.
  * "Shader folder" — packs from garrysmod/addons/speditor/shaders and the shader
    materials found (they are switched on in camera effects as "Custom shader").

The library is cl_shaders.lua, the "Engine frame" mode is cl_render.lua.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI   = SPeditor.UI
local C    = SPeditor.Client
local L    = SPeditor.L
local Dock = SPeditor.Dock
local COL  = UI.PAL

local FOLDER = "garrysmod/addons/speditor/shaders/"

local function wrapLabel(parent, text, col)
	local l = vgui.Create("DLabel", parent)
	l:Dock(TOP)
	l:DockMargin(8, 6, 8, 4)
	l:SetFont("SPeditor.Small")
	l:SetTextColor(col or COL.DIM)
	l:SetWrap(true)
	l:SetAutoStretchVertical(true)
	l:SetText(text)
	return l
end

local function styledList(parent)
	local l = vgui.Create("DListView", parent)
	UI.StyleListView(l)
	l:SetMultiSelect(false)
	if l.SetBackgroundColor then l:SetBackgroundColor(COL.LIST_BG) end
	return l
end

---------------------------------------------------------------------
-- "Addon effects" tab
---------------------------------------------------------------------
local function buildAddonsPage(page)
	local Sd, R = SPeditor.Shaders, SPeditor.Render

	local top = vgui.Create("DPanel", page)
	top:Dock(TOP)
	top:SetTall(UI.S(30))
	top.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
	end
	local engine = UI.Check(top, L("render_engine"), R.EngineMode(), function(v) R.SetEngineMode(v) end)
	engine:Dock(FILL)
	engine:DockMargin(8, 7, 8, 0)
	engine:SetTooltip(L("render_engine_tip"))
	-- the mode is also switched from the Render window
	engine.Think = function(s)
		if s:GetChecked() ~= R.EngineMode() and RealTime() > (s.SPHold or 0) then s:SetChecked(R.EngineMode()) end
	end
	local baseChange = engine.OnChange
	engine.OnChange = function(s, v)
		s.SPHold = RealTime() + 0.3
		baseChange(s, v)
	end

	wrapLabel(page, L("shaders_addons_note"))

	local list = styledList(page)
	list:Dock(LEFT)
	list:DockMargin(4, 2, 0, 4)
	list:SetWide(UI.S(330))
	list:AddColumn(L("shaders_col_on")):SetFixedWidth(46)
	list:AddColumn(L("shaders_col_effect"))
	list:AddColumn(L("shaders_col_category")):SetFixedWidth(110)

	local right = vgui.Create("DScrollPanel", page)
	right:Dock(FILL)
	right:DockMargin(4, 2, 4, 4)
	right.Paint = function(_, w, h)
		surface.SetDrawColor(COL.LIST_BG)
		surface.DrawRect(0, 0, w, h)
	end

	local entries, lines = {}, {}
	local function mark(e) return e.convar and (Sd.IsOn(e) and "●" or "○") or "–" end

	local function show(entry)
		right:Clear()
		if not entry then
			wrapLabel(right, L("shaders_pick_effect"))
			return
		end
		local head = vgui.Create("DPanel", right)
		head:Dock(TOP)
		head:SetTall(UI.S(26))
		head.Paint = function(_, w, h)
			surface.SetDrawColor(COL.HEADER)
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(entry.name, "SPeditor.Bold", 8, h / 2, COL.ORANGE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		if entry.convar then
			local on = UI.Check(right, string.format(L("shaders_enable"), entry.convar), Sd.IsOn(entry), function(v) Sd.SetOn(entry, v) end)
			on:DockMargin(8, 6, 8, 4)
		else
			wrapLabel(right, L("shaders_no_convar"))
		end
		if not entry.cpanel then
			wrapLabel(right, L("shaders_no_panel"))
			return
		end
		-- the effect's native settings panel (as in Q menu → Post Process)
		local ok, err = pcall(function()
			local cp = vgui.Create("ControlPanel", right)
			cp:Dock(TOP)
			cp:DockMargin(4, 4, 4, 8)
			cp:SetLabel(entry.name)
			entry.cpanel(cp)
		end)
		if not ok then
			wrapLabel(right, string.format(L("shaders_panel_error"), tostring(err)), COL.RED)
		end
	end

	local function fill()
		list:Clear()
		entries, lines = Sd.PostProcess(), {}
		for i, e in ipairs(entries) do
			lines[i] = list:AddLine(mark(e), e.name, e.category)
			lines[i].SPEntry = e
		end
	end
	list.OnRowSelected = function(_, _, line) show(line.SPEntry) end
	list.DoDoubleClick = function(_, _, line)
		local e = line.SPEntry
		if e and e.convar then Sd.SetOn(e, not Sd.IsOn(e)) end
	end
	fill()
	show(nil)

	-- the state is changed both from the effect panel and from the Q menu: the list follows
	local nextPoll = 0
	list.Think = function()
		if RealTime() < nextPoll then return end
		nextPoll = RealTime() + 0.3
		for i, e in ipairs(entries) do
			local m = mark(e)
			if IsValid(lines[i]) and lines[i]:GetColumnText(1) ~= m then lines[i]:SetColumnText(1, m) end
		end
	end
end

---------------------------------------------------------------------
-- "Shader folder" tab
---------------------------------------------------------------------
local function packStatus(p)
	if p.issue then return L(p.issue) end
	local text = string.format(L("shader_pack_ok"), p.files or 0, p.shaders or 0)
	if p.hasLua then text = text .. "  ·  " .. L("shader_pack_lua") end
	if p.stale then text = text .. "  ·  " .. L("shader_pack_stale") end
	if (p.skipped or 0) > 0 then text = text .. "  ·  " .. string.format(L("shader_pack_skipped"), p.skipped) end
	return text
end

local function buildPacksPage(page)
	local Sd = SPeditor.Shaders

	local foot = vgui.Create("DPanel", page)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(34))
	foot.Paint = function() end

	wrapLabel(page, string.format(L("shaders_folder_note"), FOLDER))

	local packs = styledList(page)
	packs:Dock(TOP)
	packs:DockMargin(4, 2, 4, 2)
	packs:SetTall(UI.S(120))
	packs:AddColumn(L("shaders_col_pack")):SetFixedWidth(200)
	packs:AddColumn(L("shaders_col_status"))

	local mats = styledList(page)
	mats:Dock(FILL)
	mats:DockMargin(4, 2, 4, 2)
	mats:AddColumn(L("shaders_col_material"))
	mats:AddColumn(L("shaders_col_source")):SetFixedWidth(150)
	mats:AddColumn(L("shaders_col_params")):SetFixedWidth(90)
	mats:AddColumn(L("shaders_col_buffers")):SetFixedWidth(110)

	local function fill()
		if not IsValid(packs) then return end
		packs:Clear()
		mats:Clear()
		for _, p in ipairs(Sd.Packs) do
			packs:AddLine(p.name, packStatus(p)):SetTooltip(packStatus(p))
		end
		if #Sd.Packs == 0 then packs:AddLine("—", L("shaders_no_packs")) end
		for _, info in ipairs(Sd.List) do
			local src = (info.source == "addons") and L("shader_src_addons") or info.source
			local line = mats:AddLine(info.path, src, tostring(#info.params), info.buffers and L("shaders_buffers_yes") or "—")
			line.SPPath = info.path
		end
	end
	mats.OnRowRightClick = function(_, _, line)
		if not line.SPPath then return end
		local m = UI.Menu()
		m:AddOption(L("copy_path"), function()
			SetClipboardText(line.SPPath)
			SPeditor.Notify("#path_copied|" .. line.SPPath, 0)
		end):SetIcon("icon16/page_copy.png")
		m:Open()
	end
	hook.Add("SPeditor_ShadersScanned", "SPeditor.ShadersWindow", function()
		if not IsValid(packs) then
			hook.Remove("SPeditor_ShadersScanned", "SPeditor.ShadersWindow")
			return
		end
		fill()
	end)
	Sd.Scan(false)
	fill()

	local rescan = vgui.Create("DButton", foot)
	rescan:Dock(LEFT)
	rescan:DockMargin(8, 5, 4, 5)
	rescan:SetWide(UI.S(210))
	rescan:SetText("  " .. L("shaders_rescan"))
	rescan:SetIcon("icon16/arrow_refresh.png")
	UI.StyleButton(rescan, nil, 3)
	rescan.DoClick = function()
		local nPacks, nShaders = Sd.Scan(true)
		SPeditor.Notify("#shaders_rescan_done|" .. nPacks .. "|" .. nShaders, 0)
		for _, issue in ipairs(Sd.Issues) do
			SPeditor.Notify(issue.name .. ": " .. L(issue.reason), 1)
		end
	end

	local copy = vgui.Create("DButton", foot)
	copy:Dock(LEFT)
	copy:DockMargin(4, 5, 4, 5)
	copy:SetWide(UI.S(210))
	copy:SetText("  " .. L("shaders_copy_folder"))
	copy:SetIcon("icon16/folder.png")
	UI.StyleButton(copy, nil, 3)
	copy.DoClick = function()
		SetClipboardText(FOLDER)
		SPeditor.Notify("#path_copied|" .. FOLDER, 0)
	end
end

---------------------------------------------------------------------
-- Window
---------------------------------------------------------------------
local function plainPage()
	local p = vgui.Create("DPanel")
	p.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
	end
	return p
end

-- tab: "fxaddons" (default) or "fxpacks"
function UI.OpenShaders(tab)
	tab = (tab == "fxpacks") and "fxpacks" or "fxaddons"
	if Dock.ShowPage(tab) then return end
	local W, H = math.min(860, ScrW() - 80), math.min(620, ScrH() - 140)
	local win = Dock.NewWindow({ key = "shaders_win", w = W, h = H, x = math.floor(ScrW() / 2 - W / 2), y = 90, dockable = false })
	win.minW, win.minH = UI.S(560), UI.S(360)
	win:AddCloseButton()

	local addons, packs = plainPage(), plainPage()
	win:AddPage("fxaddons", L("shaders_tab_addons"), addons, "icon16/wand.png")
	win:AddPage("fxpacks", L("shaders_tab_packs"), packs, "icon16/folder_brick.png")
	buildAddonsPage(addons)
	buildPacksPage(packs)
	win:SelectPage(tab)
	win.SPState = function() return win.active end
end
