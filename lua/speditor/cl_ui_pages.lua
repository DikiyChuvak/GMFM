--[[
SPeditor — pages of the bottom window (where SFM has the timeline):
  * Scene   — saved scenes, pose library, autosave;
  * Shadows — global shadow settings (the SPeditor.Shadows library): shadows from
    the editor's spot lights and prop shadows from the map light.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI = SPeditor.UI
local C  = SPeditor.Client
local L  = SPeditor.L
local COL = UI.PAL

local function styledList(parent, col1, col2)
	local l = vgui.Create("DListView", parent)
	UI.StyleListView(l)
	l:SetMultiSelect(false)
	local a = l:AddColumn(col1)
	if col2 then l:AddColumn(col2) end
	if l.SetBackgroundColor then l:SetBackgroundColor(COL.LIST_BG) end
	return l
end

local function column(parent, title)
	local p = vgui.Create("DPanel", parent)
	p.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, 20)
		draw.SimpleText(title, "SPeditor.Bold", 6, 10, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	p:DockPadding(2, 22, 2, 2)
	return p
end

local function buttonRow(parent)
	local r = vgui.Create("DPanel", parent)
	r:Dock(BOTTOM)
	r:SetTall(UI.S(26))
	r.Paint = function() end
	return r
end

local function rowButton(row, text, icon, fn)
	local b = UI.Button(row, text, icon, fn)
	b:Dock(LEFT)
	b:DockMargin(2, 2, 0, 2)
	surface.SetFont("SPeditor.Small")
	b:SetWide(select(1, surface.GetTextSize(text)) + UI.S(34))
	return b
end

---------------------------------------------------------------------
-- Scene
---------------------------------------------------------------------
function UI.BuildScenePage(host)
	local page = vgui.Create("DPanel")
	page.Paint = function() end

	local left = column(page, L("tab_scene"))
	local rightCol = column(page, L("pose_library"))
	local div = vgui.Create("DHorizontalDivider", page)
	div:Dock(FILL)
	div:SetLeft(left)
	div:SetRight(rightCol)
	div:SetDividerWidth(5)
	div:SetLeftMin(200)
	div:SetRightMin(200)
	div:SetLeftWidth(380)

	-- scenes
	local brow = buttonRow(left)
	local auto = UI.Check(left, L("autosave"), GetConVar("gmfm_autosave"):GetBool(), function(v)
		RunConsoleCommand("gmfm_autosave", v and "1" or "0")
	end)
	auto:Dock(BOTTOM)
	local scList = styledList(left, L("tab_scene"))
	scList:Dock(FILL)

	local selectedScene
	local function refreshScenes()
		if not IsValid(scList) then return end
		scList:Clear()
		selectedScene = nil
		for _, name in ipairs(C.sceneList or {}) do scList:AddLine(name) end
	end
	scList.OnRowSelected = function(_, _, line) selectedScene = line:GetColumnText(1) end
	scList.DoDoubleClick = function(_, _, line)
		local name = line:GetColumnText(1)
		Derma_Query(string.format(L("load_confirm"), name), "GM:FM",
			L("load"), function() C.SceneLoad(name) end, L("cancel"), function() end)
	end
	SPeditor.Hook("SPeditor_SceneList", "SPeditor.ScenePage", refreshScenes)
	refreshScenes()
	C.SceneRequestList()

	rowButton(brow, L("save_scene"), "icon16/disk.png", function()
		Derma_StringRequest(L("save_name"), L("enter_name"), "", function(name) C.SceneSave(name, C.GetSceneMeta()) end)
	end)
	rowButton(brow, L("load"), "icon16/folder_go.png", function()
		if not selectedScene then SPeditor.Notify(L("select_scene_first"), 0) return end
		local name = selectedScene
		Derma_Query(string.format(L("load_confirm"), name), "GM:FM",
			L("load"), function() C.SceneLoad(name) end, L("cancel"), function() end)
	end)
	rowButton(brow, L("delete"), "icon16/folder_delete.png", function()
		if not selectedScene then SPeditor.Notify(L("select_scene_first"), 0) return end
		local name = selectedScene
		Derma_Query(string.format(L("delete_confirm"), name), "GM:FM",
			L("delete"), function() C.SceneDelete(name) end, L("cancel"), function() end)
	end)
	rowButton(brow, "", "icon16/arrow_refresh.png", function() C.SceneRequestList() end):SetWide(UI.S(26))

	-- poses
	local prow = buttonRow(rightCol)
	local poseList = styledList(rightCol, L("pose_col_name"), L("pose_col_model"))
	poseList:Dock(FILL)
	local selectedPose
	local function refreshPoses()
		if not IsValid(poseList) then return end
		poseList:Clear()
		selectedPose = nil
		for _, info in ipairs(C.ListPoseInfos()) do
			poseList:AddLine(info.name, string.GetFileFromFilename(info.model) or "")
		end
	end
	poseList.OnRowSelected = function(_, _, line) selectedPose = line:GetColumnText(1) end
	poseList.DoDoubleClick = function(_, _, line)
		local ent = C.selected
		if IsValid(ent) and not C.IsAux(ent) then C.LoadPose(ent, line:GetColumnText(1)) end
	end
	SPeditor.Hook("SPeditor_PoseListChanged", "SPeditor.ScenePage", refreshPoses)
	refreshPoses()

	rowButton(prow, L("pose_save"), "icon16/disk.png", function()
		local ent = C.selected
		if not IsValid(ent) or C.IsAux(ent) then SPeditor.Notify(L("pose_need_entity"), 0) return end
		Derma_StringRequest(L("pose_save"), L("pose_name_prompt"), "", function(name) C.SavePose(ent, name) end)
	end)
	rowButton(prow, L("pose_load"), "icon16/user_go.png", function()
		local ent = C.selected
		if not IsValid(ent) or C.IsAux(ent) then SPeditor.Notify(L("pose_need_entity"), 0) return end
		if not selectedPose then SPeditor.Notify(L("pose_select_first"), 0) return end
		C.LoadPose(ent, selectedPose)
	end)
	rowButton(prow, L("delete"), "icon16/cross.png", function()
		if not selectedPose then SPeditor.Notify(L("pose_select_first"), 0) return end
		local name = selectedPose
		Derma_Query(string.format(L("pose_delete_confirm"), name), "GM:FM",
			L("delete"), function() C.DeletePose(name) end, L("cancel"), function() end)
	end)
	rowButton(prow, "", "icon16/arrow_refresh.png", refreshPoses):SetWide(UI.S(26))

	host:AddSheet(L("tab_scene"), page, "icon16/folder.png", "scene")
end

---------------------------------------------------------------------
-- Shadows: on the left shadows from the editor's spot lights, on the right prop shadows from the map light
---------------------------------------------------------------------
function UI.BuildShadowsPage(host)
	local Sh = SPeditor.Shadows
	local Map = Sh.Map
	local page = vgui.Create("DPanel")
	page.Paint = function() end

	local function scrollColumn()
		local sc = vgui.Create("DScrollPanel", page)
		sc.Paint = function(_, w, h)
			surface.SetDrawColor(COL.BG)
			surface.DrawRect(0, 0, w, h)
		end
		return sc
	end
	local left, right = scrollColumn(), scrollColumn()
	local div = vgui.Create("DHorizontalDivider", page)
	div:Dock(FILL)
	div:SetLeft(left)
	div:SetRight(right)
	div:SetDividerWidth(5)
	div:SetLeftMin(240)
	div:SetRightMin(240)
	div:SetLeftWidth(math.floor(ScrW() * 0.36))

	local function note(parent, text)
		local l = vgui.Create("DLabel", parent)
		l:Dock(TOP)
		l:DockMargin(6, 6, 6, 6)
		l:SetWrap(true)
		l:SetAutoStretchVertical(true)
		l:SetFont("SPeditor.Small")
		l:SetTextColor(COL.DIM)
		l:SetText(text)
		return l
	end

	-- shadows from spot lights
	local form = UI.Section(left, L("shadows_sec_lights"))
	UI.Check(form, L("shadows_master"), Sh.IsEnabled(), function(v) Sh.SetEnabled(v) end)
	UI.Check(form, L("shadows_onlylights"), Sh.OnlyLights(), function(v) Sh.SetOnlyLights(v) end)
		:SetTooltip(L("shadows_onlylights_tip"))

	UI.Label(form, L("shadows_quality"))
	local q = UI.StyleCombo(vgui.Create("DComboBox", form))
	q:Dock(TOP)
	q:DockMargin(6, 2, 6, 2)
	q:SetTall(UI.S(22))
	for i, preset in ipairs(Sh.QUALITY) do
		q:AddChoice(string.format("%s (%d)", L("shadows_q" .. i), preset.res), i, i == Sh.GetQuality())
	end
	q.OnSelect = function(_, _, _, i)
		Sh.SetQuality(i)
		SPeditor.Notify("#shadows_quality_set|" .. Sh.QUALITY[i].res, 0)
	end

	UI.Slider(form, L("shadows_max"), 1, 16, 0, Sh.GetMax(), function(v) Sh.SetMax(v) end)
	UI.Slider(form, L("shadows_dist"), 0, Sh.MAX_DISTANCE, 0, Sh.GetDistance(), function(v) Sh.SetDistance(v) end)
		:SetTooltip(L("shadows_dist_tip"))
	UI.Slider(form, L("shadows_softscale"), 0, 4, 2, Sh.GetSoftScale(), function(v) Sh.SetSoftScale(v) end)
		:SetTooltip(L("shadows_softscale_tip"))
	UI.Slider(form, L("shadows_slope"), 0, 8, 1, Sh.GetSlope(), function(v) Sh.SetSlope(v) end)
		:SetTooltip(L("shadows_slope_tip"))

	local active = UI.Label(form, "", COL.ORANGE)
	local shown
	form.Think = function()
		local text = string.format(L("shadows_active"), Sh.ActiveCount())
		if Sh.SkippedCount() > 0 then text = text .. "   ·   " .. string.format(L("shadows_skipped"), Sh.SkippedCount()) end
		if text ~= shown then
			shown = text
			active:SetText(text)
		end
	end
	note(form, L("shadows_note"))

	-- prop shadows from the map light
	local mform = UI.Section(right, L("shadows_sec_map"))
	UI.Check(mform, L("mapshadow_enabled"), Map.GetEngine("enabled") ~= 0, function(v) Map.SetEngine("enabled", v and 1 or 0) end)
	UI.Check(mform, L("mapshadow_detailed"), Map.GetEngine("detailed") ~= 0, function(v) Map.SetEngine("detailed", v and 1 or 0) end)
	UI.Slider(mform, L("mapshadow_max"), 0, 128, 0, Map.GetEngine("max"), function(v) Map.SetEngine("max", v) end)

	local controls = {}
	local function setEnabled(on)
		for _, c in ipairs(controls) do
			if IsValid(c) then c:SetEnabled(on) end
		end
	end
	UI.Check(mform, L("mapshadow_custom"), Map.IsCustom(), function(v)
		Map.SetCustom(v)
		setEnabled(v)
	end):SetTooltip(L("mapshadow_custom_tip"))

	local Lim = SPeditor.MapShadowLimits
	local function mapSlider(key, dec)
		local sl = UI.Slider(mform, L("mapshadow_" .. key), Lim[key].min, Lim[key].max, dec, Map.Get(key), function(v) Map.Set(key, v) end)
		sl:SetTooltip(L("mapshadow_" .. key .. "_tip"))
		controls[#controls + 1] = sl
		return sl
	end
	local sliders = { dist = mapSlider("dist", 0), dark = mapSlider("dark", 0), pitch = mapSlider("pitch", 0), yaw = mapSlider("yaw", 0) }
	controls[#controls + 1] = UI.Check(mform, L("mapshadow_off"), Map.IsDisabled(), function(v) Map.SetDisabled(v) end)

	local reset = UI.Button(mform, L("mapshadow_reset"), "icon16/arrow_undo.png", function()
		for key, sl in pairs(sliders) do sl:SetValue(Lim[key].default) end
	end)
	reset:DockMargin(6, 4, 6, 2)
	controls[#controls + 1] = reset
	setEnabled(Map.IsCustom())
	note(mform, L("mapshadow_note"))

	host:AddSheet(L("tab_shadows"), page, "icon16/weather_sun.png", "shadows")
end
