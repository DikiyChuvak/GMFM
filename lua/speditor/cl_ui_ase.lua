--[[
SPeditor — Animation Set Editor in the style of SFM (adapted for posters).

Three columns, as in SFM:
  1. Tree: scene objects (animation sets) → control groups
     (Face / Eyes / Body / Head / RightArm / LeftArm / RightLeg / LeftLeg /
     RightFingers / LeftFingers / Torso). The right side is red, the left one green.
  2. Presets (top of the right column) — depend on the selection:
     model: Default / Zero / Half / One for the face, reset, pose copy / paste,
             saved poses; light: light presets; camera: lenses.
  3. Controls (bottom of the right column): face and eye sliders, bone rows
     "- pos / - rot" (a click selects the bone in the gizmo); a light and a camera show their
     parameters as controls.
There is no timeline: SPeditor is for posters.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI = SPeditor.UI
local C  = SPeditor.Client
local L  = SPeditor.L
local COL = UI.PAL
local SFM_SELECTION = Color(76, 91, 122)

local ICONS = {
	light = "icon16/lightbulb.png", camera = "icon16/camera.png", effect = "icon16/lightning.png",
	ragdoll = "icon16/user.png", prop = "icon16/box.png",
	group = "icon16/folder.png", face = "icon16/emoticon_smile.png", eyes = "icon16/eye.png",
}

---------------------------------------------------------------------
-- Bone groups as in SFM
---------------------------------------------------------------------
local function sideOf(lname)
	if string.find(lname, "_r_", 1, true) or string.find(lname, "right", 1, true)
		or string.sub(lname, -2) == "_r" or string.find(lname, "%.r_") then return "Right" end
	if string.find(lname, "_l_", 1, true) or string.find(lname, "left", 1, true)
		or string.sub(lname, -2) == "_l" or string.find(lname, "%.l_") then return "Left" end
	return nil
end

local function anyOf(s, list)
	for _, p in ipairs(list) do
		if string.find(s, p, 1, true) then return true end
	end
	return false
end

local GROUP_ORDER = { "Body", "Head", "RightArm", "LeftArm", "RightLeg", "LeftLeg",
"RightFingers", "LeftFingers", "FaceBones", "Unknown" }


-- the colour of light of a temperature in kelvins (the curve fitted by Tanner Helland to the
-- black-body colours), and the temperatures of common light sources (a0.9)
function UI.KelvinColor(k)
	local t = math.Clamp(k, 1000, 40000) / 100
	local r, g, b
	if t <= 66 then
		r = 255
		g = 99.4708025861 * math.log(t) - 161.1195681661
		b = t <= 19 and 0 or (138.5177312231 * math.log(t - 10) - 305.0447927307)
	else
		r = 329.698727446 * (t - 60) ^ -0.1332047592
		g = 288.1221695283 * (t - 60) ^ -0.0755148492
		b = 255
	end
	return Color(math.Clamp(math.Round(r), 0, 255), math.Clamp(math.Round(g), 0, 255), math.Clamp(math.Round(b), 0, 255))
end
UI.KELVIN_PRESETS = { { 1900, "candle" }, { 2700, "tungsten" }, { 3200, "halogen" }, { 4100, "moon" }, { 5000, "noon" },
	{ 5600, "day" }, { 6500, "overcast" }, { 7500, "shade" }, { 10000, "sky" } }

function UI.BoneGroupSFM(name)
	local l = string.lower(name or "")
	local side = sideOf(l)
	if anyOf(l, { "finger", "thumb", "index", "pinky", "ring", "middle" }) and side then return side .. "Fingers" end
	if anyOf(l, { "jaw", "eye", "brow", "lip", "cheek", "tongue", "mouth", "teeth" }) then return "FaceBones" end
	if anyOf(l, { "clavicle", "upperarm", "forearm", "hand", "shoulder", "elbow", "wrist", "ulna", "bicep", "arm" }) and side then return side .. "Arm" end
	if anyOf(l, { "thigh", "calf", "foot", "toe", "knee", "ankle", "leg", "hip" }) and side then return side .. "Leg" end
	if anyOf(l, { "neck", "head" }) then return "Head" end
	if anyOf(l, { "pelvis", "spine", "root", "hips", "chest", "torso" }) then return "Body" end
	return "Unknown"
end

-- Bone group caption. Bones that fell into no group are shown as "Torso" for a
-- character; props (a crate, a bottle) have no body bones — "Object".
local function groupLabel(ent, g)
	if g == "Unknown" then g = C.IsRagdoll(ent) and "Torso" or "Object" end
	return SPeditor.LN("grp_", g)
end

local function groupColor(g)
	if string.sub(g, 1, 5) == "Right" then return COL.RED end
	if string.sub(g, 1, 4) == "Left" then return COL.GREEN end
	return COL.BLUE
end

-- «ValveBiped.Bip01_R_Hand» -> «R_Hand»
local function shortBone(name)
	local n = string.gsub(name or "", "^ValveBiped%.", "")
	n = string.gsub(n, "^Bip01_", "")
	return n
end

local function boneGroupsOf(ent)
	local groups = {}
	for _, b in ipairs(C.GetBoneList(ent)) do
		local g = UI.BoneGroupSFM(b.name)
		groups[g] = groups[g] or {}
		groups[g][#groups[g] + 1] = b
	end
	return groups
end

local FACE_ORDER = { "Brows", "Eyes", "Nose", "Mouth", "Other" }

local function flexGroupsOf(ent)
	local groups = {}
	if ent:GetFlexNum() == 0 then return groups end
	for _, f in ipairs(C.GetFlexList(ent)) do
		local g = f.group or "Other"
		groups[g] = groups[g] or {}
		groups[g][#groups[g] + 1] = f
	end
	return groups
end

local function isModel(ent) return IsValid(ent) and not C.IsAux(ent) end

---------------------------------------------------------------------
-- The skeleton tree (as in Ragdoll Mover): bones in their real hierarchy
---------------------------------------------------------------------
local cvTree    = CreateClientConVar("gmfm_ase_tree", "groups", true, false)     -- groups / skeleton / none
local cvNonPhys = CreateClientConVar("gmfm_ase_nonphys", "1", true, false)       -- show bones without a physics object
local cvMerged  = CreateClientConVar("gmfm_ase_merged", "1", true, false)        -- show bonemerged models

function UI.AseTreeMode()
	local m = cvTree:GetString()
	if m ~= "skeleton" and m ~= "none" then m = "groups" end
	return m
end

-- a bone kind: physical (has a physics object), procedural (driven by the model), plain
local BONE_ICONS = { phys = "icon16/brick.png", plain = "icon16/connect.png", proc = "icon16/cog.png" }
local function boneKind(ent, b)
	if C.PhysIndexOfBone(ent, b.id) then return "phys" end
	if BONE_ALWAYS_PROCEDURAL and ent:BoneHasFlag(b.id, BONE_ALWAYS_PROCEDURAL) then return "proc" end
	return "plain"
end

-- the bone under the cursor in the tree is marked in the viewports
UI.TreeHover = nil
SPeditor.Hook("PostDrawTranslucentRenderables", "SPeditor.TreeHover", function(depth, sky)
	local h = UI.TreeHover
	if depth or sky or not h or not C.active or C.exporting then return end
	if not IsValid(h.ent) or RealTime() - h.t > 0.15 then return end
	local pos = C.GetBoneWorld(h.ent, h.bone)
	if not pos then return end
	local c = COL.ORANGE
	render.SetColorMaterial()
	render.DrawWireframeSphere(pos, 3, 10, 10, Color(c.r, c.g, c.b), false)
	render.DrawSphere(pos, 1.5, 8, 8, Color(c.r, c.g, c.b, 200))
end)

-- The model has eyes (an "eyes" attachment or face flexes). Crates, bottles
-- and other props do not — the "Eyes" section is not shown for them.
local function hasEyes(ent)
	if not isModel(ent) then return false end
	local att = ent:LookupAttachment("eyes")
	return (att and att > 0) or (ent:GetFlexNum() or 0) > 0
end

---------------------------------------------------------------------
-- Light colour: a pop-up with a palette and a mixer
---------------------------------------------------------------------
local SWATCHES = {
	{ 255, 255, 255 }, { 255, 244, 224 }, { 255, 214, 170 }, { 255, 180, 100 }, { 255, 147, 41 }, { 201, 226, 255 }, { 140, 180, 255 },
	{ 255, 40, 40 },   { 255, 130, 0 },   { 255, 230, 0 },   { 140, 255, 0 },   { 0, 220, 60 },   { 0, 220, 160 },   { 70, 235, 255 },
	{ 0, 140, 255 },   { 30, 60, 255 },   { 140, 60, 255 },  { 200, 40, 255 },  { 255, 70, 180 }, { 255, 150, 200 }, { 150, 150, 150 },
}

function UI.OpenColorPopup(title, start, onPick)
	if IsValid(UI.ColorPopup) then UI.ColorPopup:Remove() end
	local f = UI.Skin(vgui.Create("DFrame"))
	f:SetTitle(title)
	f:SetSize(UI.S(260), UI.S(330))
	local mx, my = gui.MousePos()
	f:SetPos(math.Clamp(mx - 130, 0, ScrW() - 260), math.Clamp(my - 20, 0, ScrH() - 330))
	f:MakePopup()
	f:SetKeyboardInputEnabled(false)
	f.Paint = function(s, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, 24)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	UI.ColorPopup = f

	local pal = vgui.Create("DPanel", f)
	pal:Dock(TOP)
	pal:SetTall(UI.S(3 * 28))
	pal.Paint = function() end
	local mixer
	for i, rgb in ipairs(SWATCHES) do
		local sw = vgui.Create("DButton", pal)
		sw:SetPos(((i - 1) % 7) * 34 + 6, math.floor((i - 1) / 7) * 28 + 2)
		sw:SetSize(UI.S(30), UI.S(24))
		sw:SetText("")
		local col = Color(rgb[1], rgb[2], rgb[3])
		sw.Paint = function(s, w, h)
			surface.SetDrawColor(col)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(s:IsHovered() and COL.ORANGE or COL.BORDER)
			surface.DrawOutlinedRect(0, 0, w, h, s:IsHovered() and 2 or 1)
		end
		sw.DoClick = function()
			if IsValid(mixer) then mixer:SetColor(col) end
			onPick(col)
		end
	end

	mixer = vgui.Create("DColorMixer", f)
	mixer:Dock(FILL)
	mixer:DockMargin(4, 4, 4, 4)
	mixer:SetAlphaBar(false)
	mixer:SetPalette(false)
	mixer:SetColor(start)
	mixer.ValueChanged = function(_, c) onPick(Color(c.r, c.g, c.b)) end
	return f
end

---------------------------------------------------------------------
-- ASE page
---------------------------------------------------------------------
function UI.BuildASE(body)
	local cur = { ent = nil, scope = "all" }   -- what the presets and controls show
	local rebuildControls, rebuildPresets, rebuildTree, addSkeleton

	-----------------------------------------------------------------
	-- Toolbar: "+", search, gear
	-----------------------------------------------------------------
	local bar = vgui.Create("DPanel", body)
	bar:Dock(TOP)
	bar:SetTall(UI.S(28))
	bar.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
	end

	local add = vgui.Create("DButton", bar)
	add:Dock(LEFT)
	add:DockMargin(4, 3, 0, 3)
	add:SetWide(UI.S(26))
	add:SetText("+")
	UI.StyleButton(add)
	add:SetFont("SPeditor.Bold")
	add:SetTooltip(L("ase_add"))
	UI.ThemeButton(add, "ase_add")
	add.DoClick = function()
		local m = SPeditor.UI.Menu()
		m:AddOption(L("ase_add_model"), function() UI.ToggleBrowser() end):SetIcon("icon16/user_add.png")
		m:AddOption(L("act_spawn_camera"), function() C.SendCameraSpawn(C.camera.pos, C.camera.ang) end):SetIcon("icon16/camera_add.png")
		m:AddOption(L("spawn_spot"), function() UI.SpawnLight(1) end):SetIcon("icon16/lightbulb.png")
		m:AddOption(L("spawn_point"), function() UI.SpawnLight(0) end):SetIcon("icon16/lightbulb_off.png")
		UI.LightKindMenu(m)
		m:AddOption(L("eff_add"), function() UI.ToggleEffects() end):SetIcon("icon16/lightning_add.png")
		m:AddSpacer()
		m:AddOption(L("rig_make"), function() C.SpawnLightRig(C.selected) end):SetIcon("icon16/lightbulb_add.png")
		SPeditor.Components.RunMenu("create", m)
		m:Open()
	end

	local gear = vgui.Create("DButton", bar)
	gear:Dock(RIGHT)
	gear:DockMargin(0, 3, 4, 3)
	gear:SetWide(UI.S(26))
	gear:SetText("")
	gear:SetIcon("icon16/cog.png")
	gear.Paint = nil
	UI.ThemeButton(gear, "ase_gear")
	gear.DoClick = function()
		local m = SPeditor.UI.Menu()
		-- what is shown under a model: SFM groups, the skeleton as in Ragdoll Mover, or nothing
		local mode = UI.AseTreeMode()
		for _, id in ipairs({ "groups", "skeleton", "none" }) do
			m:AddOption(L("ase_tree_" .. id), function()
				RunConsoleCommand("gmfm_ase_tree", id)
				timer.Simple(0, rebuildTree)
			end):SetChecked(mode == id)
		end
		if mode == "skeleton" then
			local sub = m:AddSubMenu(L("ase_tree_show"))
			sub:AddOption(L("ase_bone_nonphys"), function()
				RunConsoleCommand("gmfm_ase_nonphys", GetConVar("gmfm_ase_nonphys"):GetBool() and "0" or "1")
				timer.Simple(0, rebuildTree)
			end):SetChecked(GetConVar("gmfm_ase_nonphys"):GetBool())
			sub:AddOption(L("ase_bone_merged"), function()
				RunConsoleCommand("gmfm_ase_merged", GetConVar("gmfm_ase_merged"):GetBool() and "0" or "1")
				timer.Simple(0, rebuildTree)
			end):SetChecked(GetConVar("gmfm_ase_merged"):GetBool())
		end
		m:AddSpacer()
		m:AddOption(L("expand_all"), function() UI.ExpandTree(true) end)
		m:AddOption(L("collapse_all"), function() UI.ExpandTree(false) end)
		m:Open()
	end

	local search = vgui.Create("DTextEntry", bar)
	search:Dock(FILL)
	search:DockMargin(6, 4, 6, 4)
	search:SetFont("SPeditor.Small")
	search:SetPlaceholderText(L("obj_search"))

	-----------------------------------------------------------------
	-- Columns
	-----------------------------------------------------------------
	local treeHost = vgui.Create("DPanel")
	treeHost.Paint = function(_, w, h)
		surface.SetDrawColor(COL.TREE_BG)
		surface.DrawRect(0, 0, w, h)
	end
	local tree = UI.StyleTree(vgui.Create("DTree", treeHost))
	tree:Dock(FILL)
	UI.ObjectTree = tree

	-- an empty scene (a0.7): what to do first, instead of an empty list. Props and ragdolls
	-- spawned from the Sandbox spawn menu are not scene objects until they are taken in.
	local empty = vgui.Create("DPanel", treeHost)
	empty:SetPaintBackground(false)
	empty:DockPadding(8, 8, 8, 8)
	local emptyText = vgui.Create("DLabel", empty)
	emptyText:Dock(TOP)
	emptyText:SetFont("SPeditor.Small")
	emptyText:SetTextColor(COL.DIM)
	emptyText:SetWrap(true)
	emptyText:SetAutoStretchVertical(true)
	emptyText:SetText(L("ase_empty"))
	local b1 = UI.Button(empty, L("ase_add_model"), "icon16/user_add.png", function() UI.ToggleBrowser() end)
	b1:Dock(TOP)
	b1:DockMargin(0, 8, 0, 0)
	local b2 = UI.Button(empty, L("adopt_title") .. "…", "icon16/arrow_in.png", function() UI.OpenAdopt() end)
	b2:Dock(TOP)
	b2:DockMargin(0, 4, 0, 0)
	empty:SetVisible(false)
	treeHost.PerformLayout = function(s, w, h) empty:SetSize(w, h) end
	-- shown by the tree's own check below (a hidden panel gets no Think of its own)
	local function updateEmpty()
		local none = #C.Objects() == 0
		if empty:IsVisible() ~= none then
			empty:SetVisible(none)
			tree:SetVisible(not none)
		end
	end

	local presetHost = vgui.Create("DPanel")
	presetHost.Paint = function(_, w, h)
		surface.SetDrawColor(COL.ROW_B)
		surface.DrawRect(0, 0, w, h)
	end
	local presetHdr = vgui.Create("DPanel", presetHost)
	presetHdr:Dock(TOP)
	presetHdr:SetTall(UI.S(20))
	presetHdr.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.TAB_ON)
		surface.DrawRect(2, 2, 74, h - 2)
		draw.SimpleText(L("ase_presets"), "SPeditor.Small", 39, h / 2 + 1, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	local presets = vgui.Create("DScrollPanel", presetHost)
	presets:Dock(FILL)

	local ctrlHost = vgui.Create("DPanel")
	ctrlHost.Paint = function(_, w, h)
		surface.SetDrawColor(COL.ROW_B)
		surface.DrawRect(0, 0, w, h)
	end
	local ctrlHdr = vgui.Create("DPanel", ctrlHost)
	ctrlHdr:Dock(TOP)
	ctrlHdr:SetTall(UI.S(20))
	local ctrlTitle = ""
	ctrlHdr.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText(ctrlTitle, "SPeditor.Small", 6, h / 2, COL.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	local controls = vgui.Create("DScrollPanel", ctrlHost)
	controls:Dock(FILL)

	local right = vgui.Create("DVerticalDivider")
	right:SetTop(presetHost)
	right:SetBottom(ctrlHost)
	right:SetDividerHeight(5)
	right:SetTopMin(60)
	right:SetBottomMin(80)
	right:SetTopHeight(200)

	local split = vgui.Create("DHorizontalDivider", body)
	split:Dock(FILL)
	split:SetLeft(treeHost)
	split:SetRight(right)
	split:SetDividerWidth(5)
	split:SetLeftMin(120)
	split:SetRightMin(110)
	split:SetLeftWidth(200)
	local sized = false
	split.Think = function(s)
		if sized or s:GetWide() < 50 then return end
		sized = true
		-- the skeleton is deeper than the groups: its column is wider
		s:SetLeftWidth(math.floor(s:GetWide() * (UI.AseTreeMode() == "skeleton" and 0.6 or 0.48)))
		right:SetTopHeight(math.floor(math.max(right:GetTall(), 300) * 0.34))
	end

	-----------------------------------------------------------------
	-- Preset column
	-----------------------------------------------------------------
	local rowAlt = false
	local function presetRow(text, fn, col, icon)
		rowAlt = not rowAlt
		local b = vgui.Create("DButton", presets)
		b:Dock(TOP)
		b:SetTall(UI.S(18))
		b:SetText("")
		local alt = rowAlt
		b.Paint = function(s, w, h)
			surface.SetDrawColor(s:IsHovered() and COL.SEL or (alt and COL.ROW_A or COL.ROW_B))
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(text, "SPeditor.Small", w / 2, h / 2, col or COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		if icon then b:SetTooltip(icon) end
		b.DoClick = fn
		return b
	end
	local function presetHeader(text)
		local p = vgui.Create("DPanel", presets)
		p:Dock(TOP)
		p:SetTall(UI.S(16))
		p.Paint = function(_, w, h)
			surface.SetDrawColor(COL.HEADER)
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(text, "SPeditor.Small", 6, h / 2, COL.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end

	-- flexes in the current scope (the whole model or one face group)
	local function flexesInScope(ent)
		local out = {}
		local scopeGroup = string.match(cur.scope, "^face:(.+)$")
		for _, f in ipairs(C.GetFlexList(ent)) do
			if not scopeGroup or (f.group or "Other") == scopeGroup then out[#out + 1] = f end
		end
		return out
	end

	local function applyFlexPreset(ent, which)
		local list = flexesInScope(ent)
		if #list == 0 then SPeditor.Notify(L("face_no_flex"), 0) return end
		C.SnapshotThen(ent, "face preset", function()
			for _, f in ipairs(list) do
				local v
				if which == "default" then v = math.Clamp(0, f.min, f.max)
				elseif which == "zero" then v = f.min
				elseif which == "half" then v = (f.min + f.max) / 2
				else v = f.max end
				C.SendFlex(ent, f.id, v, true)
			end
		end)
	end

	local LENSES = { 18, 24, 35, 50, 85, 135 }

	function rebuildPresets()
		presets:Clear()
		rowAlt = false
		local ent = cur.ent
		if not IsValid(ent) then
			presetHeader(L("no_selection"))
			return
		end

		if C.IsLight(ent) then
			presetHeader(L("light_kinds"))
			for _, k in ipairs(SPeditor.LightKinds or {}) do
				presetRow(SPeditor.LN("lkind_", k.name), function()
					C.ApplyLightKind(ent, k)
					-- the light type may have changed: the controls are rebuilt once it arrives over the network
					timer.Simple(0.3, function() if IsValid(ent) and cur.ent == ent then rebuildControls() end end)
				end, Color(math.max(k.r, 150), math.max(k.g, 150), math.max(k.b, 150)))
			end
			presetHeader(L("presets"))
			for _, p in ipairs(SPeditor.LightPresets or {}) do
				presetRow(SPeditor.LN("preset_", p.name), function()
					C.SendLightEdit(ent, ent:GetLightType(), Color(p.r, p.g, p.b), p.radius, p.brightness, p.fov, nil, true)
				end, Color(p.r, p.g, p.b))
			end
			presetHeader(L("sec_actions"))
			presetRow(L("aim_at"), function() C.OpenAimMenu(ent) end)
			return
		end

		if C.IsCamera(ent) then
			presetHeader(L("ase_lenses"))
			for _, mm in ipairs(LENSES) do
				local fov = math.deg(2 * math.atan(18 / mm))
				presetRow(string.format("%d mm  (%d°)", mm, math.Round(fov)), function()
					C.SendCameraEdit(ent, "fov", fov, true)
				end)
			end
			presetHeader(L("sec_actions"))
			presetRow(L("aim_at"), function() C.OpenAimMenu(ent) end)
			presetRow(L("match_cam_work"), function() C.MatchCameraToWork(ent) end)
			presetRow(L("match_work_cam"), function() C.MatchWorkToCamera(ent) end)
			presetRow(L("fx_open"), function() UI.OpenRenderDialog(ent) end)
			presetRow(L("cam_rec"), function() C.SetCameraRecords(ent, not C.CameraRecords(ent)) end)
			return
		end

		if C.IsEffect(ent) then
			-- the moment of the effect: how long after its start it is shown
			presetHeader(L("eff_moments"))
			for _, t in ipairs({ 0.05, 0.1, 0.25, 0.5, 1, 2, 4 }) do
				presetRow(string.format(L("eff_moment_s"), t), function() C.SendEffectEdit(ent, { time = t }, true) end)
			end
			presetHeader(L("sec_actions"))
			presetRow(L("eff_play"), function() SPeditor.Effects.Preview(ent) end)
			presetRow(L("eff_replace"), function() C.Select(ent, -1) UI.ToggleEffects() end)
			presetRow(L("aim_at"), function() C.OpenAimMenu(ent) end)
			return
		end

		if ent:GetFlexNum() > 0 then
			presetHeader(L("face"))
			presetRow(L("face_preset_default"), function() applyFlexPreset(ent, "default") end)
			presetRow(L("face_preset_zero"), function() applyFlexPreset(ent, "zero") end)
			presetRow(L("face_preset_half"), function() applyFlexPreset(ent, "half") end)
			presetRow(L("face_preset_one"), function() applyFlexPreset(ent, "one") end)
		end
		presetHeader(L("sec_appearance"))
		presetRow(L("props_open"), function() UI.OpenObjectProps(ent) end)
		presetHeader(L("pose_scene_section"))
		presetRow(L("reset_selected"), function() C.ResetPoseFull(ent) end)
		if ent:GetFlexNum() > 0 then presetRow(L("face_reset"), function() C.ResetFlexes(ent) end) end
		presetRow(L("pose_copy"), function() C.CopyPose(ent) end)
		presetRow(L("pose_paste"), function() C.PastePose(ent) end)
		presetRow(L("pose_save") .. "…", function()
			Derma_StringRequest(L("pose_save"), L("pose_name_prompt"), "", function(name) C.SavePose(ent, name) end)
		end)

		local infos = C.ListPoseInfos()
		if #infos > 0 then
			presetHeader(L("pose_library"))
			local model = ent:GetModel()
			for _, info in ipairs(infos) do
				local same = (info.model == "" or info.model == model)
				presetRow(info.name, function() C.LoadPose(ent, info.name) end, same and COL.TEXT or COL.DIM)
			end
		end
	end
	SPeditor.Hook("SPeditor_PoseListChanged", "SPeditor.ASE", function() if IsValid(presets) then rebuildPresets() end end)

	-----------------------------------------------------------------
	-- Control column
	-----------------------------------------------------------------
	local ctrlAlt = false
	local function ctrl(o)
		ctrlAlt = not ctrlAlt
		local c = UI.Control(controls, o)
		c.alt = ctrlAlt
		return c
	end
	local function ctrlHeader(text, col)
		local p = vgui.Create("DPanel", controls)
		p:Dock(TOP)
		p:SetTall(UI.S(16))
		p.Paint = function(_, w, h)
			surface.SetDrawColor(COL.HEADER)
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(text, "SPeditor.Small", 6, h / 2, col or COL.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end

	local function flexControls(ent, list)
		for _, f in ipairs(list) do
			ctrl({
					label = f.name, min = f.min, max = f.max, value = f.weight,
					default = math.Clamp(0, f.min, f.max),
					onChange = function(v) C.EditFlex(ent, f.id, v) end,
			getter = function() return IsValid(ent) and ent:GetFlexWeight(f.id) or nil end,
			})
		end
	end

	local function eyeControls(ent)
		local function edit(field, v)
			local st = C.GetEyeState(ent)
			st[field] = v
			if field ~= "on" then st.on = true end
			C.EditEye(ent, st)
		end
		UI.ToggleRow(controls, L("ctl_view_target"), function() return IsValid(ent) and C.GetEyeState(ent).on end,
		function(v) edit("on", v) end)
		local st = C.GetEyeState(ent)
		ctrl({ label = L("ctl_eyes_yaw"), min = -180, max = 180, value = st.yaw, default = 0, decimals = 0,
				onChange = function(v) edit("yaw", v) end,
		getter = function() return IsValid(ent) and C.GetEyeState(ent).yaw end })
		ctrl({ label = L("ctl_eyes_pitch"), min = -90, max = 90, value = st.pitch, default = 0, decimals = 0,
				onChange = function(v) edit("pitch", v) end,
		getter = function() return IsValid(ent) and C.GetEyeState(ent).pitch end })
		ctrl({ label = L("ctl_eyes_dist"), min = 10, max = 500, value = st.dist, default = 100, decimals = 0,
				onChange = function(v) edit("dist", v) end,
		getter = function() return IsValid(ent) and C.GetEyeState(ent).dist end })
		-- b0.1: the eyes on the camera in one click (a key then keeps it, as any eye pose)
		UI.LinkRow(controls, L("ctl_eyes_at_cam"), nil, nil, function()
			if not IsValid(ent) then return end
			local st = C.EyeStateTowards(ent, (C.GetView()))
			if st then C.EditEye(ent, st) else SPeditor.Notify(L("ctl_eyes_none"), 1) end
		end)
		UI.LinkRow(controls, L("ctl_eyes_ahead"), nil, nil, function()
			if not IsValid(ent) then return end
			local st = C.GetEyeState(ent)
			st.on = false
			C.EditEye(ent, st)
		end)
	end

	local function boneRows(ent, list, col)
		for _, b in ipairs(list) do
			local short = shortBone(b.name)
			-- every bone can be moved: a physical one moves its physics object, the others
			-- (clavicles, fingers) get a bone offset
			UI.LinkRow(controls, short .. " - pos", col, function()
				return C.selected == ent and C.selBone == b.id and C.gizmo.mode == "move"
			end, function()
				C.Select(ent, b.id)
				C.gizmo.mode = "move"
			end)
			UI.LinkRow(controls, short .. " - rot", col, function()
				return C.selected == ent and C.selBone == b.id and C.gizmo.mode == "rotate"
			end, function()
				C.Select(ent, b.id)
				C.gizmo.mode = "rotate"
			end)
			UI.LinkRow(controls, short .. " - scale", col, function()
				return C.selected == ent and C.selBone == b.id and C.gizmo.mode == "scale"
			end, function()
				C.Select(ent, b.id)
				C.gizmo.mode = "scale"
			end)
		end
	end

	local function lightControls(ent)
		local col = ent:GetLightColor()
		local color = Color(math.Round(col.x * 255), math.Round(col.y * 255), math.Round(col.z * 255))
		local bri, rng, cone
		local extra = {}     -- controls of the extended settings: [SPeditor.LightFields key] = { ctrl, scale }

		local function send(final)
			if not IsValid(ent) then return end
			local sh = {}
			for key, e in pairs(extra) do sh[key] = e.ctrl:GetValue() / e.scale end
			C.SendLightEdit(ent, ent:GetLightType(), color, rng:GetValue(), bri:GetValue(),
				cone and cone:GetValue() or ent:GetLightFOV(), sh, final)
		end
		-- toggles and lists: one field changes, the rest is taken from the light state
		local function sendExtra(sh)
			if not IsValid(ent) then return end
			C.SendLightEdit(ent, ent:GetLightType(), color, ent:GetLightRadius(), ent:GetLightBrightness(), ent:GetLightFOV(), sh, true)
		end
		-- slider of an extended setting; scale — how many times the interface value is larger than the stored one
		local function extraCtrl(key, label, min, max, decimals, scale)
			local def
			for _, f in ipairs(SPeditor.LightFields) do
				if f.key == key then def = f end
			end
			scale = scale or 1
			local getter = function() return IsValid(ent) and ent["Get" .. def.nw](ent) * scale end
			extra[key] = { scale = scale, ctrl = ctrl({ label = label, min = min, max = max, value = getter(), default = def.default * scale,
					decimals = decimals, onChange = function(_, final) send(final) end, getter = getter }) }
			-- captions in the narrow column are short; what a setting does is in the tooltip
			extra[key].ctrl:SetTooltip(L("ctl_tip_" .. key))
		end

		local ltype = ent:GetLightType()
		UI.LinkRow(controls, L("light_type") .. ":  " .. (ltype == 1 and L("light_spot") or L("light_point")), COL.ORANGE, nil, function()
			C.SendLightEdit(ent, 1 - ent:GetLightType(), color, ent:GetLightRadius(), ent:GetLightBrightness(), ent:GetLightFOV(), nil, true)
			timer.Simple(0.2, function() if IsValid(controls) then rebuildControls() end end)
		end)

		-- colour: a click opens the palette
		local cb = vgui.Create("DButton", controls)
		cb:Dock(TOP)
		cb:DockMargin(0, 0, 0, 1)
		cb:SetTall(UI.S(18))
		cb:SetText("")
		cb.Paint = function(s, w, h)
			surface.SetDrawColor(s:IsHovered() and COL.ROW_A or COL.ROW_B)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(color)
			surface.DrawRect(4, 3, 28, h - 6)
			surface.SetDrawColor(COL.BORDER)
			surface.DrawOutlinedRect(4, 3, 28, h - 6, 1)
			draw.SimpleText(L("ctl_color"), "SPeditor.Small", w / 2, h / 2, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		cb.DoClick = function()
			UI.OpenColorPopup(L("light_custom"), color, function(c)
				color = c
				send(false)
			end)
		end
		cb.Think = function()
			if IsValid(UI.ColorPopup) or not IsValid(ent) then return end
			local v = ent:GetLightColor()
			color = Color(math.Round(v.x * 255), math.Round(v.y * 255), math.Round(v.z * 255))
		end

		-- colour temperature (a0.9): the colours of real light sources, by kelvins
		UI.LinkRow(controls, L("light_kelvin") .. "…", COL.TEXT, nil, function()
			local m = UI.Menu()
			for _, p in ipairs(UI.KELVIN_PRESETS) do
				local c = UI.KelvinColor(p[1])
				m:AddOption(string.format("%s  (%d K)", L("kelvin_" .. p[2]), p[1]), function()
					color = c
					send(true)
				end)
			end
			m:Open()
		end):SetTooltip(L("light_kelvin_tip"))

		bri = ctrl({ label = L("ctl_intensity"), min = 0, max = 8, value = ent:GetLightBrightness(), default = 2,
				onChange = function(_, final) send(final) end,
		getter = function() return IsValid(ent) and ent:GetLightBrightness() end })
		rng = ctrl({ label = L(ltype == 1 and "ctl_distance" or "ctl_radius"), min = 32, max = 4000, value = ent:GetLightRadius(),
				default = 400, decimals = 0,
				onChange = function(_, final) send(final) end,
		getter = function() return IsValid(ent) and ent:GetLightRadius() end })
		if ltype == 1 then
			cone = ctrl({ label = L("ctl_fov"), min = 5, max = 120, value = ent:GetLightFOV(), default = 60, decimals = 0,
					onChange = function(_, final) send(final) end,
			getter = function() return IsValid(ent) and ent:GetLightFOV() end })

			-- soft light (a0.2)
			ctrlHeader(L("light_sec_soft"))
			extraCtrl("edge", L("ctl_edge"), 0, 1, 2)
			extraCtrl("area", L("ctl_area"), 0, 64, 1)

			-- shadows
			ctrlHeader(L("light_sec_shadows"))
			UI.ToggleRow(controls, L("ctl_casts_shadows"), function() return IsValid(ent) and ent:GetLightShadows() end, function(v)
				sendExtra({ shadows = v })
			end)
			extraCtrl("soft", L("ctl_shadow_filter"), 0, 5, 2)
			extraCtrl("bias", L("ctl_shadow_bias"), 0, 10, 2, 10000)
			extraCtrl("slope", L("ctl_shadow_slope"), 0, 16, 1)
			extraCtrl("near", L("ctl_shadow_near"), 1, 500, 0)

			-- beam shape and falloff
			ctrlHeader(L("light_sec_beam"))
			UI.ToggleRow(controls, L("ctl_ortho"), function() return IsValid(ent) and ent:GetLightOrtho() end, function(v)
				sendExtra({ ortho = v })
			end):SetTooltip(L("ctl_ortho_tip"))
			extraCtrl("osize", L("ctl_ortho_size"), 8, 2000, 0)
			extraCtrl("attc", L("ctl_att_const"), 0, 10, 2)
			extraCtrl("attl", L("ctl_att_linear"), 0, 1000, 0)
			extraCtrl("attq", L("ctl_att_quad"), 0, 2000, 0)

			-- light mask: textures of the Lamp tool
			-- editor masks, Lamp tool textures and all other light textures from the game and addons
			local Lt = SPeditor.Lights
			local texName = Lt.TextureName
			local texRow
			-- the quick list (a right click on the row); a click opens the picker with pictures (b0.2)
			local function texMenu()
				local m = UI.Menu()
				local now = ent:GetLightTexture()
				for i, group in ipairs(Lt.TextureList()) do
					if #group.items > 0 then
						local sub = m:AddSubMenu(L(group.title) .. "  (" .. #group.items .. ")")
						for _, path in ipairs(group.items) do
							sub:AddOption(texName(path), function() sendExtra({ tex = path }) end):SetChecked(path == now)
						end
					end
				end
				-- any other game texture — by path
				m:AddSpacer()
				m:AddOption(L("lmask_custom") .. "…", function()
					Derma_StringRequest(L("ctl_light_texture"), L("lmask_custom_prompt"), now, function(path)
						path = string.gsub(string.gsub(string.Trim(path), "\\", "/"), "%.vtf$", "")
						path = string.gsub(path, "^materials/", "")
						if path ~= "" and #path <= 96 and not string.find(path, "[^%w_%-/%.]") then
							sendExtra({ tex = path })
						else
							SPeditor.Notify("#lmask_custom_bad", 1)
						end
					end)
				end):SetIcon("icon16/folder_picture.png")
				m:Open()
			end
			texRow = UI.LinkRow(controls, "", COL.TEXT, nil, function()
				UI.PickLightTexture({ ent = ent, current = ent:GetLightTexture(), onPick = function(path)
					if IsValid(ent) and path ~= ent:GetLightTexture() then sendExtra({ tex = path }) end
				end })
			end)
			texRow.DoRightClick = texMenu
			texRow:SetTooltip(L("lpick_row_tip"))
			texRow.Paint = function(s, w, h)
				surface.SetDrawColor(s:IsHovered() and COL.ROW_A or COL.ROW_B)
				surface.DrawRect(0, 0, w, h)
				local tex = IsValid(ent) and ent:GetLightTexture() or ""
				if tex == "" then tex = SPeditor.DefaultLightTexture end
				draw.SimpleText(L("ctl_light_texture") .. ":  " .. texName(tex), "SPeditor.Small",
					w / 2, h / 2, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				-- the texture itself, small, at the left end of the row
				if UI.DrawLightTexture then UI.DrawLightTexture(tex, 3, 1, h - 2, h - 2) end
			end
		else
			-- shadows of a point light: it shines as six spots, a cube (speditor_light.lua)
			ctrlHeader(L("light_sec_shadows"))
			UI.ToggleRow(controls, L("ctl_casts_shadows"), function() return IsValid(ent) and ent:GetLightShadows() end, function(v)
				sendExtra({ shadows = v })
			end):SetTooltip(L("ctl_point_shadows_tip"))
			extraCtrl("area", L("ctl_area"), 0, 64, 1)
			extraCtrl("soft", L("ctl_shadow_filter"), 0, 5, 2)
			extraCtrl("bias", L("ctl_shadow_bias"), 0, 10, 2, 10000)
			extraCtrl("slope", L("ctl_shadow_slope"), 0, 16, 1)
			extraCtrl("near", L("ctl_shadow_near"), 1, 500, 0)
		end
	end

	-- visible source (a0.2): glow for any light, beam for a spot
	local baseLightControls = lightControls
	lightControls = function(ent)
		baseLightControls(ent)
		local function field(key)
			for _, f in ipairs(SPeditor.LightFields) do
				if f.key == key then return f end
			end
		end
		local function fx(key, label, min, max, decimals)
			local def = field(key)
			local c = ctrl({ label = label, min = min, max = max, default = def.default, decimals = decimals,
					value = ent["Get" .. def.nw](ent),
					onChange = function(v, final)
						if not IsValid(ent) then return end
						local col = ent:GetLightColor()
						C.SendLightEdit(ent, ent:GetLightType(), Color(math.Round(col.x * 255), math.Round(col.y * 255), math.Round(col.z * 255)),
							ent:GetLightRadius(), ent:GetLightBrightness(), ent:GetLightFOV(), { [key] = v }, final)
					end,
					getter = function() return IsValid(ent) and ent["Get" .. def.nw](ent) end })
			c:SetTooltip(L("ctl_tip_" .. key))
		end
		ctrlHeader(L("light_sec_visible"))
		fx("glow", L("ctl_glow"), 0, 400, 0)
		fx("glowb", L("ctl_glow_bright"), 0, 4, 2)
		if ent:GetLightType() == 1 then
			fx("vol", L("ctl_vol"), 0, 1, 2)
			fx("voll", L("ctl_vol_len"), 0.05, 1, 2)
		end
	end

	local function cameraControls(ent)
		ctrl({ label = L("ctl_fov"), min = 10, max = 120, value = ent:GetCameraFOV(), default = 75, decimals = 1,
				onChange = function(v, final) C.SendCameraEdit(ent, "fov", v, final) end,
		getter = function() return IsValid(ent) and ent:GetCameraFOV() end })
		-- the lens (a0.9): the same field of view as a focal length of a 36 mm wide frame, as SFM
		-- and real cameras name it (the lens presets are in the list above)
		local function fovToMM(f) return 18 / math.tan(math.rad(f) / 2) end
		local function mmToFov(mm) return math.deg(2 * math.atan(18 / math.max(mm, 1))) end
		ctrl({ label = L("cam_focal"), min = 11, max = 205, value = fovToMM(ent:GetCameraFOV()), default = 35, decimals = 0,
				onChange = function(v, final) C.SendCameraEdit(ent, "fov", math.Clamp(mmToFov(v), 10, 120), final) end,
				getter = function() return IsValid(ent) and fovToMM(ent:GetCameraFOV()) end }):SetTooltip(L("cam_focal_tip"))
		-- the dutch angle: the camera turned round its own axis
		ctrl({ label = L("cam_dutch"), min = -45, max = 45, value = ent:GetAngles().r, default = 0, decimals = 1,
				onChange = function(v, final)
					if not IsValid(ent) then return end
					local p, a = ent:GetPos(), ent:GetAngles()
					local before = Angle(a.p, a.y, a.r)
					local after = Angle(a.p, a.y, v)
					C.SendTransform(ent, p, after, true)
					local ref = C.Ref(ent)
					C.BurstEdit("dutch" .. ent:EntIndex(), "transform", function() return { p, before } end, { p, after }, function(st)
						local e = C.Deref(ref)
						if e then C.SendTransform(e, st[1], st[2], true) end
					end)
				end,
				getter = function() return IsValid(ent) and ent:GetAngles().r end }):SetTooltip(L("cam_dutch_tip"))
		-- the near clipping plane (b0.2.2, SFM's znear)
		local zGet = function() return IsValid(ent) and ent.GetZNear and ent:GetZNear() or 3 end
		ctrl({ label = L("cam_znear"), min = 0.1, max = 100, value = zGet(), default = 3, decimals = 1,
				onChange = function(v, final) C.SendCameraEdit(ent, "znear", v, final) end, getter = zGet }):SetTooltip(L("cam_tip_znear"))
		UI.ToggleRow(controls, L("look_through"), function() return C.GetViewCamera() == ent end, function(v)
			if v then C.StartViewCamera(ent) else C.StopViewCamera() end
		end)
		-- motion: shake and smoothness (SPeditor.CameraFields)
		ctrlHeader(L("cam_sec_motion"))
		local DEC = { shake = 1, shakerot = 2, shakefreq = 1, smooth = 2 }
		for _, f in ipairs(SPeditor.CameraFields) do
			local getter = function() return IsValid(ent) and ent["Get" .. f.nw] and ent["Get" .. f.nw](ent) or f.default end
			-- the near plane has its own row above, beside the lens
			if f.key ~= "znear" then
				ctrl({ label = L("cam_" .. f.key), min = f.min, max = f.max, value = getter(), default = f.default, decimals = DEC[f.key] or 2,
						onChange = function(v, final) C.SendCameraEdit(ent, f.key, v, final) end, getter = getter })
					:SetTooltip(L("cam_tip_" .. f.key))
			end
		end
	end

	local function effectControls(ent)
		local live = SPeditor.Effects.IsLive(ent)
		local kind = L("eff_src_" .. ent:GetFxSource())
		local nameRow = UI.LinkRow(controls, "", COL.ORANGE, nil, function() UI.ToggleEffects() end)
		nameRow.Paint = function(s, w, h)
			surface.SetDrawColor(s:IsHovered() and COL.ROW_A or COL.ROW_B)
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(kind .. ":  " .. (IsValid(ent) and ent:GetFxName() or ""), "SPeditor.Small", w / 2, h / 2, COL.ORANGE,
				TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		nameRow:SetTooltip(L("eff_replace"))

		local function field(key, label, min, max, decimals)
			local def
			for _, f in ipairs(SPeditor.EffectFields) do
				if f.key == key then def = f end
			end
			local getter = function() return IsValid(ent) and ent["Get" .. def.nw](ent) end
			local c = ctrl({ label = label, min = min, max = max, value = getter(), default = def.default, decimals = decimals,
					onChange = function(v, final) C.SendEffectEdit(ent, { [key] = v }, final) end, getter = getter })
			c:SetTooltip(L("eff_tip_" .. key))
			return c
		end
		field("time", L("eff_time"), 0, 10, 2)
		if live then field("scale", L("eff_scale"), 0.05, 10, 2) end
		field("length", L("eff_length"), 0, 2000, 0)
		UI.LinkRow(controls, L("eff_play"), COL.TEXT, nil, function() SPeditor.Effects.Preview(ent) end)

		-- what the moment means for this kind of effect
		local note = vgui.Create("DLabel", controls)
		note:Dock(TOP)
		note:DockMargin(6, 4, 6, 0)
		note:SetFont("SPeditor.Small")
		note:SetTextColor(COL.DIM)
		note:SetWrap(true)
		note:SetAutoStretchVertical(true)
		note:SetText(L(live and "eff_note_live" or "eff_note_pcf"))
	end

	function rebuildControls()
		controls:Clear()
		ctrlAlt = false
		local ent = cur.ent
		if not IsValid(ent) then
			ctrlTitle = L("no_selection")
			return
		end
		ctrlTitle = C.DisplayName(ent) .. ((cur.scope ~= "all") and ("  /  " .. (cur.scopeLabel or cur.scope)) or "")

		if C.IsLight(ent) then lightControls(ent) return end
		if C.IsCamera(ent) then cameraControls(ent) return end
		if C.IsEffect(ent) then effectControls(ent) return end

		local scope = cur.scope
		local faceGroup = string.match(scope, "^face:(.+)$")
		local boneGroup = string.match(scope, "^bones:(.+)$")
		local oneBone = tonumber(string.match(scope, "^bone:(%d+)$") or "")
		if oneBone then
			-- one bone of the skeleton tree, and the bones below it
			local list, under = {}, { [oneBone] = true }
			for _, b in ipairs(C.GetBoneList(ent)) do
				if b.id == oneBone or under[b.parent] then
					under[b.id] = true
					list[#list + 1] = b
				end
			end
			local g = UI.BoneGroupSFM(ent:GetBoneName(oneBone))
			boneRows(ent, list, groupColor(g))
			return
		end

		if (scope == "all" or scope == "eyes") and hasEyes(ent) then
			if scope == "all" then ctrlHeader(L("grp_eyes")) end
			eyeControls(ent)
		end
		if scope == "all" or scope == "face" or faceGroup then
			local groups = flexGroupsOf(ent)
			for _, g in ipairs(FACE_ORDER) do
				if groups[g] and (not faceGroup or faceGroup == g) then
					if not faceGroup then ctrlHeader(L("face") .. " / " .. SPeditor.LN("grp_", g)) end
					flexControls(ent, groups[g])
				end
			end
		end
		if scope == "all" or boneGroup then
			local groups = boneGroupsOf(ent)
			for _, g in ipairs(GROUP_ORDER) do
				if groups[g] and (not boneGroup or boneGroup == g) then
					if not boneGroup then ctrlHeader(groupLabel(ent, g), groupColor(g)) end
					boneRows(ent, groups[g], groupColor(g))
				end
			end
		end
	end

	local function setScope(ent, scope, label)
		if cur.ent ~= ent or cur.scope ~= scope then
			cur.ent, cur.scope, cur.scopeLabel = ent, scope, label
			rebuildPresets()
			rebuildControls()
		end
		if C.selected ~= ent then C.Select(ent, -1) end
	end

	-----------------------------------------------------------------
	-- Tree
	-----------------------------------------------------------------
	local function objectMenu(obj)
		local ent = obj.ent
		if not IsValid(ent) then return end
		local m = SPeditor.UI.Menu()
		if not C.IsAux(ent) then
			m:AddOption(L("props_open"), function() UI.OpenObjectProps(ent) end):SetIcon("icon16/wrench.png")
			local look = C.GetLook(ent)
			local lm = m:AddSubMenu(L("sec_appearance"))
			lm:AddOption(L("props_color") .. "…", function()
				local c = ent:GetColor()
				UI.OpenColorPopup(L("props_color"), Color(c.r, c.g, c.b), function(col)
					if IsValid(ent) then C.EditLook(ent, { color = { col.r, col.g, col.b, ent:GetColor().a } }) end
				end)
			end):SetIcon("icon16/color_wheel.png")
			lm:AddOption(L("props_mat_remove"), function() UI.RemoveTextures(ent) end):SetIcon("icon16/picture_delete.png")
			lm:AddOption(L("props_mat_restore"), function() UI.RestoreTextures(ent) end):SetIcon("icon16/picture_go.png")
			lm:AddOption(L("props_cast_shadow"), function() C.EditLook(ent, { noshadow = not look.noshadow }, true) end)
				:SetChecked(not look.noshadow)
			lm:AddSpacer()
			lm:AddOption(L("props_reset"), function() UI.ResetLook(ent) end)
			-- PAC3 outfits (cl_pac.lua): props and characters
			if SPeditor.PAC and (C.IsRagdoll(ent) or ent:GetClass() == "prop_physics" or ent:GetClass() == "prop_dynamic") then
				SPeditor.PAC.AddMenu(m, ent)
			end
			m:AddSpacer()
		elseif C.IsCamera(ent) then
			m:AddOption(L("fx_open"), function() UI.OpenRenderDialog(ent) end):SetIcon("icon16/wand.png")
			m:AddOption(L("cam_rec"), function() C.SetCameraRecords(ent, not C.CameraRecords(ent)) end):SetChecked(C.CameraRecords(ent))
			m:AddSpacer()
		elseif C.IsEffect(ent) then
			m:AddOption(L("eff_play"), function() SPeditor.Effects.Preview(ent) end):SetIcon("icon16/control_play.png")
			m:AddOption(L("eff_replace"), function() C.Select(ent, -1) UI.ToggleEffects() end):SetIcon("icon16/arrow_refresh.png")
			m:AddSpacer()
		end
		m:AddOption(L("obj_rename"), function()
			Derma_StringRequest(L("obj_rename"), L("enter_name"), obj.name, function(name) C.SendRename(ent, name) end)
		end)
		m:AddOption(L("obj_duplicate"), function() C.SendDuplicate(ent) end)
		m:AddOption(L("obj_delete"), function() C.SendDelete(ent) C.Select(nil) end)
		m:AddSpacer()
		if not C.IsAux(ent) or C.IsEffect(ent) then
			m:AddOption(L("ase_renderable"), function() C.SendFlags(ent, not obj.hidden, obj.locked) end):SetChecked(not obj.hidden)
		end
		m:AddOption(L("ase_selectable"), function() C.SendFlags(ent, obj.hidden, not obj.locked) end):SetChecked(not obj.locked)
		m:AddSpacer()
		-- attaching to an object / bone
		local am = m:AddSubMenu(L("attach_to"))
		-- SFM's point and orient constraints (b0.2): codes as S.AttachCode on the server
		local function constraintItems(bm, tgt, bones)
			bm:AddSpacer()
			bm:AddOption(L("attach_point"), function() C.SendAttach(ent, tgt, -100) end):SetIcon("icon16/arrow_inout.png")
			bm:AddOption(L("attach_orient"), function() C.SendAttach(ent, tgt, -1000) end):SetIcon("icon16/arrow_rotate_clockwise.png")
			if bones then
				local pm = bm:AddSubMenu(L("attach_point_bone"))
				for _, b in ipairs(C.GetBoneList(tgt)) do
					if b.phys then
						pm:AddOption((string.gsub(b.name, "^ValveBiped%.Bip01_", "")), function() C.SendAttach(ent, tgt, -100 - (b.id + 1)) end)
					end
				end
			end
		end
		local nTargets = 0
		for _, o in ipairs(C.BuildEntityList()) do
			local tgt = o.ent
			if IsValid(tgt) and tgt ~= ent and o.kind ~= "light" and o.kind ~= "camera" and o.kind ~= "effect" then
				nTargets = nTargets + 1
				-- a ragdoll, or a model with a skeleton but no physics (a character ported from SFM)
				if o.kind == "ragdoll" or (not C.IsAux(tgt) and (tgt:GetBoneCount() or 0) > 1) then
					local bm = am:AddSubMenu(o.name)
					-- clothing, armour, hair for the same skeleton: bends with the bones
					if not C.IsAux(ent) then
						local w = bm:AddOption(L("attach_wear"), function() C.SendAttach(ent, tgt, -2) end)
						w:SetIcon("icon16/user_suit.png")
						w:SetTooltip(L("attach_wear_tip"))
					end
					bm:AddOption(L("attach_root"), function() C.SendAttach(ent, tgt, -1) end)
					constraintItems(bm, tgt, o.kind == "ragdoll")
					if o.kind == "ragdoll" then
						bm:AddSpacer()
						for _, b in ipairs(C.GetBoneList(tgt)) do
							if b.phys then
								local short = string.gsub(b.name, "^ValveBiped%.Bip01_", "")
								bm:AddOption(short, function() C.SendAttach(ent, tgt, b.id) end)
							end
						end
					end
				else
					-- b0.2: a submenu — the whole object, or SFM's point / orient constraints
					local bm = am:AddSubMenu(o.name, function() C.SendAttach(ent, tgt, -1) end)
					bm:AddOption(L("attach_root"), function() C.SendAttach(ent, tgt, -1) end)
					constraintItems(bm, tgt, false)
				end
			end
		end
		if nTargets == 0 then
			local o = am:AddOption(L("aim_none"))
			if o.SetEnabled then o:SetEnabled(false) end
		end
		if C.AttachParent(ent) then
			m:AddOption(L("attach_detach"), function() C.SendAttach(ent, nil, -1) end)
			-- b0.2 (SFM's reparenting with "maintain world"): the motion the parent gave becomes keys
			local SA = SPeditor.Component("saeditor").SA
			if SA and SA.BakeDetach then
				m:AddOption(L("attach_bake"), function() SA.BakeDetach(ent) end):SetIcon("icon16/key_go.png")
			end
		end
		-- saved looks (b0.2.4, cl_presets.lua): material presets, outfits of a character
		local Pr = SPeditor.Presets
		if Pr and not C.IsAux(ent) then
			m:AddSpacer()
			local mm, mo = m:AddSubMenu(L("matpreset_title"))
			mo:SetIcon("icon16/palette.png")
			Pr.MaterialMenu(mm, ent)
			if (ent:GetBoneCount() or 0) > 1 then
				local om, oo = m:AddSubMenu(L("outfit_title"))
				oo:SetIcon("icon16/user_suit.png")
				Pr.OutfitMenu(om, ent)
			end
		end
		m:AddSpacer()
		m:AddOption(L("ase_show_ev"), function() C.Select(ent, -1) SPeditor.Dock.ShowPage("ev") end)
		m:AddOption(L("obj_focus"), function() C.Select(ent, -1) C.FocusSelected() end)
		m:AddSpacer()

		if C.IsAux(ent) then
			m:AddOption(L("aim_at"), function() C.OpenAimMenu(ent) end)
			if C.IsCamera(ent) then
				m:AddOption(L("look_through"), function() C.StartViewCamera(ent) end)
				m:AddOption(L("match_cam_work"), function() C.MatchCameraToWork(ent) end)
			end
		else
			local um = m:AddSubMenu(L("ase_utilities"))
			um:AddOption(L("drop_floor"), function() C.SendDropToFloor(ent) end)
			um:AddOption(L("reset_rotation"), function() C.ResetRotation({ ent }) end)
			um:AddOption(L("rig_make"), function() C.SpawnLightRig(ent) end)
			um:AddOption(L("reset_selected"), function() C.ResetPoseFull(ent) end)
			-- copies in a row (a0.9)
			um:AddOption(L("array_dup") .. "…", function()
				Derma_StringRequest(L("array_dup"), L("array_dup_prompt"), "5  64 0 0", function(text)
					local n, x, y, z = string.match(text, "^%s*(%d+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
					n = math.Clamp(tonumber(n) or 0, 0, 50)
					if n > 0 then C.ArrayDuplicate(ent, n, Vector(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)) end
				end)
			end):SetIcon("icon16/application_cascade.png")
			-- physics off / on (a0.9, cl_saeditor_extra.lua): limbs can be pulled apart, the whole model scaled
			local SA = SPeditor.Component("saeditor").SA
			-- a crate, a melon, a barrel falls apart at the playhead (b0.2.4)
			if SA.BreakProp and ent:GetClass() == "prop_physics" then
				local info = util.GetModelInfo(ent:GetModel() or "")
				if info and isstring(info.KeyValues) and string.find(info.KeyValues, '"break"', 1, true) then
					local b = um:AddOption(L("brk_menu"), function() SA.BreakProp(ent) end)
					b:SetIcon("icon16/bomb.png")
					b:SetTooltip(L("brk_tip"))
				end
			end
			if SA.TogglePhysics and (ent:GetBoneCount() or 0) > 1 then
				if obj.kind == "ragdoll" then
					m:AddOption(L("phys_off"), function() SA.TogglePhysics(ent) end):SetIcon("icon16/link_break.png")
				elseif ent:GetClass() == "prop_dynamic" and util.IsValidRagdoll(ent:GetModel() or "") then
					m:AddOption(L("phys_on"), function() SA.TogglePhysics(ent) end):SetIcon("icon16/link.png")
				end
			end
			if obj.kind == "ragdoll" then
				um:AddOption(L("pose_copy"), function() C.CopyPose(ent) end)
				um:AddOption(L("pose_paste"), function() C.PastePose(ent) end)
				-- a physical bone is selected: it can hold on to another bone (cl_gizmo.lua)
				if C.selected == ent and C.selBone >= 0 then C.BoneLockMenu(m, ent, C.selBone) end
			end
			-- an own IK chain ending at the selected bone (a0.9, cl_rig.lua)
			if C.selected == ent and C.selBone >= 0 then SPeditor.Rig.ChainMenu(m, ent, C.selBone) end
			-- a model without physics: the animation its bone offsets are put on (cl_ui_props.lua)
			if UI.IsPoseProp(ent) then
				m:AddOption(L("bpose_title") .. "…", function() UI.OpenBasePose(ent) end):SetIcon("icon16/user_edit.png")
			end
			local skins = ent:SkinCount() or 1
			if skins > 1 then
				local sk = m:AddSubMenu(L("ase_set_skin"))
				for i = 0, skins - 1 do
					sk:AddOption(tostring(i), function() C.SendSkin(ent, i) end):SetChecked(ent:GetSkin() == i)
				end
			end
			local nb = ent:GetNumBodyGroups() or 0
			local bodyMenu
			for i = 0, nb - 1 do
				local n = ent:GetBodygroupCount(i)
				if n and n > 1 then
					bodyMenu = bodyMenu or m:AddSubMenu(L("ase_set_body"))
					local sub = bodyMenu:AddSubMenu(ent:GetBodygroupName(i) or ("#" .. i))
					for v = 0, n - 1 do
						sub:AddOption(tostring(v), function() C.SendBodygroup(ent, i, v) end):SetChecked(ent:GetBodygroup(i) == v)
					end
				end
			end
		end
		SPeditor.Components.RunMenu("object", m, ent)
		m:Open()
	end

	-- the same menu on a right click in the frame (cl_camera.lua)
	UI.ObjectMenu = function(ent)
		for _, o in ipairs(C.BuildEntityList()) do
			if o.ent == ent then
				objectMenu(o)
				return
			end
		end
	end

	local nodesByEnt = {}

	function UI.ExpandTree(open)
		for _, node in pairs(nodesByEnt) do
			if IsValid(node) then node:SetExpanded(open) end
		end
	end

	local treeSig = ""
	local function signature()
		local parts = { search:GetValue() or "", UI.AseTreeMode(), cvNonPhys:GetString(), cvMerged:GetString() }
		for _, o in ipairs(C.BuildEntityList()) do
			parts[#parts + 1] = table.concat({ IsValid(o.ent) and o.ent:EntIndex() or 0, o.name, tostring(o.hidden), tostring(o.locked),
					IsValid(o.parent) and o.parent:EntIndex() or 0,
					IsValid(o.ent) and IsValid(o.ent:GetNW2Entity("SPeditor_AimAt")) and o.ent:GetNW2Entity("SPeditor_AimAt"):EntIndex() or 0 }, ":")
		end
		return table.concat(parts, "|")
	end

	local function addGroup(parent, text, col, icon, ent, scope)
		local n = parent:AddNode(text, icon or ICONS.group)
		UI.NodeColor(n, col)
		n.DoClick = function() setScope(ent, scope, text) end
		n.DoRightClick = function() setScope(ent, scope, text) end
		return n
	end

	-- The skeleton under a model node: face and eyes first, then the bones in their
	-- hierarchy (a bone without a shown parent hangs on the nearest shown ancestor),
	-- then the models bonemerged onto it by other tools
	function addSkeleton(node, ent)
		local fg = flexGroupsOf(ent)
		if next(fg) then addGroup(node, L("face"), COL.BLUE, ICONS.face, ent, "face") end
		if hasEyes(ent) then addGroup(node, L("grp_eyes"), COL.BLUE, ICONS.eyes, ent, "eyes") end
		local showPlain = cvNonPhys:GetBool()
		local list = C.GetBoneList(ent)
		local byId, shown = {}, {}
		for _, b in ipairs(list) do byId[b.id] = b end
		local nodes = {}
		for _, b in ipairs(list) do
			local kind = boneKind(ent, b)
			if kind == "phys" or showPlain then
				-- the nearest shown ancestor
				local p = b.parent
				while p and p >= 0 and not nodes[p] do p = byId[p] and byId[p].parent or -1 end
				local parentNode = (p and p >= 0 and nodes[p]) or node
				local g = UI.BoneGroupSFM(b.name)
				local col = (string.sub(g, 1, 5) == "Right") and COL.RED or ((string.sub(g, 1, 4) == "Left") and COL.GREEN or COL.TEXT)
				local n = parentNode:AddNode(shortBone(b.name), BONE_ICONS[kind])
				UI.NodeColor(n, col)
				n:SetTooltip(b.name .. "\n" .. L("ase_bone_" .. kind))
				n.DoClick = function()
					setScope(ent, "bone:" .. b.id, shortBone(b.name))
					C.Select(ent, b.id)
				end
				n.DoRightClick = function()
					n.DoClick()
					local m = SPeditor.UI.Menu()
					if kind == "phys" and C.IsRagdoll(ent) then C.BoneLockMenu(m, ent, b.id) end
					SPeditor.Rig.ChainMenu(m, ent, b.id)
					m:Open()
				end
				-- the bone under the cursor is marked in the viewports
				local label = n.Label
				if IsValid(label) then
					local think = label.Think
					label.Think = function(s2)
						if think then think(s2) end
						if s2:IsHovered() then UI.TreeHover = { ent = ent, bone = b.id, t = RealTime() } end
					end
				end
				nodes[b.id] = n
				-- hands stay folded: five fingers of three bones each would push the tree far to the right
				if not string.find(string.lower(b.name), "hand", 1, true) then shown[#shown + 1] = n end
			end
		end
		-- expanded down to the hands and feet
		for _, n in ipairs(shown) do n:SetExpanded(true) end
		if cvMerged:GetBool() then
			for _, ch in ipairs(ent:GetChildren()) do
				if IsValid(ch) and not SPeditor.IsEditable(ch) and (ch:GetModel() or "") ~= ""
					and not string.StartWith(ch:GetClass(), "manipulate_") then
					local name = string.StripExtension(string.GetFileFromFilename(ch:GetModel()))
					local mn = node:AddNode(name .. "  (" .. L("ase_merged") .. ")", "icon16/brick_link.png")
					UI.NodeColor(mn, COL.DIM)
					mn:SetTooltip(ch:GetClass() .. "\n" .. ch:GetModel())
				end
			end
		end
	end

	function rebuildTree()
		treeSig = signature()
		tree:Clear()
		local skeleton = UI.AseTreeMode() == "skeleton"
		tree:SetIndentSize(skeleton and 9 or 12)
		if skeleton and split:GetWide() > 50 and split:GetLeftWidth() < split:GetWide() * 0.58 then
			split:SetLeftWidth(math.floor(split:GetWide() * 0.6))
		end
		nodesByEnt = {}
		local q = string.lower(string.Trim(search:GetValue() or ""))

		-- one object the tree cannot show (a model with a broken skeleton, an entity of another
		-- addon) must not take the whole list with it: it used to stop the rebuild at that object,
		-- and everything after it, newly spawned objects too, never got into the tree
		local function selectionColor()
			-- GM:FM UI: the blue selection of Valve's Qt style (valve_base.qss)
			if UI.IsNative() then return SFM_SELECTION end
			return COL.SEL
		end
		local function addObject(obj)
			local ent = obj.ent
			-- an attached object shows in the tree what it is attached to
			local label = obj.name
			if IsValid(obj.parent) then label = label .. "  → " .. C.DisplayName(obj.parent) end
			-- a look-at (a0.7): what the camera / light keeps turning to
			local aim = ent:GetNW2Entity("SPeditor_AimAt")
			if IsValid(aim) then label = label .. "   (" .. string.format(L("aim_tree"), C.DisplayName(aim)) .. ")" end
			local node = tree:AddNode(label, UI.ThemeIconPath(obj.kind) or ICONS[obj.kind] or ICONS.prop)
			UI.NodeColor(node, (obj.hidden or obj.locked) and COL.DIM or COL.TEXT)
			nodesByEnt[ent] = node
			-- every selected object has the same highlight (b0.2): the main one and those added with
			-- Shift / Ctrl / a box, so it is plain to see that they all are taken; the main one
			-- has a light stripe at the left
			if IsValid(node.Label) then
				local paint = node.Label.Paint
				node.Label.Paint = function(s, w, h)
					local main = C.selected == ent
					if not main and not C.IsMulti(ent) then return paint(s, w, h) end
					local c = selectionColor()
					surface.SetDrawColor(c.r, c.g, c.b, main and 255 or 200)
					surface.DrawRect(0, 0, w, h)
					if main then
						surface.SetDrawColor(255, 255, 255, 170)
						surface.DrawRect(0, 0, 2, h)
					end
				end
			end
			node.DoClick = function()
				-- Shift / Ctrl + click: add to / remove from the selection
				if C.Keys.ClickAny(C.MULTI_CLICK) then
					C.ToggleMulti(ent)
					return
				end
				setScope(ent, "all")
			end
			node.DoRightClick = function()
				setScope(ent, "all")
				objectMenu(obj)
			end

			local mode = UI.AseTreeMode()
			if mode == "skeleton" and isModel(ent) then
				addSkeleton(node, ent)
			elseif mode == "groups" and isModel(ent) then
				local fg = flexGroupsOf(ent)
				if next(fg) then
					local face = addGroup(node, L("face"), COL.BLUE, ICONS.face, ent, "face")
					for _, g in ipairs(FACE_ORDER) do
						if fg[g] then addGroup(face, SPeditor.LN("grp_", g), COL.TEXT, nil, ent, "face:" .. g) end
					end
				end
				if hasEyes(ent) then addGroup(node, L("grp_eyes"), COL.BLUE, ICONS.eyes, ent, "eyes") end
				local bg = boneGroupsOf(ent)
				for _, g in ipairs(GROUP_ORDER) do
					if bg[g] then addGroup(node, groupLabel(ent, g), groupColor(g), nil, ent, "bones:" .. g) end
				end
			end
			if ent == cur.ent then
				node:SetExpanded(true)
				tree:SetSelectedItem(node)
			end
		end
		for _, obj in ipairs(C.BuildEntityList()) do
			if IsValid(obj.ent) and (q == "" or string.find(string.lower(obj.name), q, 1, true)) then
				local ok, err = pcall(addObject, obj)
				if not ok then ErrorNoHalt("[GM:FM] tree: " .. tostring(obj.name) .. ": " .. tostring(err) .. "\n") end
			end
		end
	end

	search.OnChange = function() rebuildTree() end
	SPeditor.Hook("SPeditor_MultiChanged", "SPeditor.ASE", function()
		if IsValid(tree) then rebuildTree() end
	end)

	-- selection from the viewport / another window
	SPeditor.Hook("SPeditor_Selected", "SPeditor.ASE", function(ent)
		if not IsValid(tree) then return end
		if ent ~= cur.ent then
			cur.ent, cur.scope, cur.scopeLabel = ent, "all", nil
			rebuildPresets()
			rebuildControls()
			local node = nodesByEnt[ent]
			if IsValid(node) then
				node:SetExpanded(true)
				tree:SetSelectedItem(node)
			end
		end
	end)

	-- a selection box in the tree (b0.2): a press with the left button and a drag up or down
	-- over the object rows selects every object it crosses (with Shift / Ctrl — adds them)
	local box
	SPeditor.Hook("VGUIMousePressed", "SPeditor.ASEBox", function(pnl, code)
		if code ~= MOUSE_LEFT or not IsValid(tree) or not IsValid(pnl) or not tree:IsVisible() then return end
		if pnl ~= tree and not pnl:HasParent(tree) then return end
		local bar = tree.GetVBar and tree:GetVBar()
		if IsValid(bar) and (pnl == bar or pnl:HasParent(bar)) then return end
		local mx, my = gui.MousePos()
		box = { x0 = mx, y0 = my, x1 = mx, y1 = my, add = C.Keys.ClickAny(C.MULTI_CLICK) }
	end)
	local function boxRows(b)
		local y0, y1 = math.min(b.y0, b.y1), math.max(b.y0, b.y1)
		local tx, ty = tree:LocalToScreen(0, 0)
		local out = {}
		for _, obj in ipairs(C.BuildEntityList()) do
			local node = nodesByEnt[obj.ent]
			if IsValid(node) and IsValid(node.Label) and node:IsVisible() then
				local _, ny = node.Label:LocalToScreen(0, 0)
				local nh = node.Label:GetTall()
				-- rows scrolled out of the tree do not count
				if ny + nh > ty and ny < ty + tree:GetTall() and ny + nh > y0 and ny < y1 then out[#out + 1] = obj.ent end
			end
		end
		return out
	end
	local function boxShown(b) return b and math.abs(b.y1 - b.y0) >= 6 end
	local function endBox()
		local b = box
		box = nil
		if not boxShown(b) then return end
		local list = boxRows(b)
		if #list == 0 then return end
		-- after the click of the row the press began on (it selects that one object)
		timer.Simple(0, function()
			if not b.add then
				C.Select(list[1], -1)
				for i = 2, #list do C.multi[#C.multi + 1] = list[i] end
				if #list > 1 then hook.Run("SPeditor_MultiChanged") end
				return
			end
			local changed = false
			for _, e in ipairs(list) do
				if not IsValid(C.selected) then
					C.Select(e, -1, true)
				elseif e ~= C.selected and not C.IsMulti(e) then
					C.multi[#C.multi + 1] = e
					changed = true
				end
			end
			if changed then hook.Run("SPeditor_MultiChanged") end
		end)
	end
	tree.PaintOver = function(s, w, h)
		if not boxShown(box) then return end
		local tx, ty = s:LocalToScreen(0, 0)
		local y0, y1 = math.min(box.y0, box.y1) - ty, math.max(box.y0, box.y1) - ty
		local x0, x1 = math.min(box.x0, box.x1) - tx, math.max(box.x0, box.x1) - tx
		x0, x1 = math.max(x0, 0), math.min(math.max(x1, x0 + 4), w)
		local acc = COL.ORANGE
		surface.SetDrawColor(acc.r, acc.g, acc.b, 40)
		surface.DrawRect(x0, y0, x1 - x0, y1 - y0)
		surface.SetDrawColor(acc.r, acc.g, acc.b, 230)
		surface.DrawOutlinedRect(x0, y0, x1 - x0, y1 - y0, 1)
		-- the rows it takes
		for _, e in ipairs(boxRows(box)) do
			local node = nodesByEnt[e]
			local _, ny = node.Label:LocalToScreen(0, 0)
			surface.SetDrawColor(acc.r, acc.g, acc.b, 60)
			surface.DrawRect(0, ny - ty, w, node.Label:GetTall())
		end
	end

	local nextCheck = 0
	treeHost.Think = function()
		if box then
			if input.IsMouseDown(MOUSE_LEFT) then
				box.x1, box.y1 = gui.MousePos()
			else
				endBox()
			end
		end
		if RealTime() < nextCheck or not C.active then return end
		nextCheck = RealTime() + 0.5
		updateEmpty()
		if signature() ~= treeSig then rebuildTree() end
		if IsValid(cur.ent) == false and cur.ent ~= nil then
			cur.ent = nil
			rebuildPresets()
			rebuildControls()
		end
	end

	cur.ent = C.selected
	rebuildTree()
	rebuildPresets()
	rebuildControls()
end

-- "Soft light" submenu: create a light of the needed kind right away (SPeditor.LightKinds)
function UI.LightKindMenu(m)
	local sub, opt = m:AddSubMenu(L("light_kinds_spawn"))
	if opt and opt.SetIcon then opt:SetIcon("icon16/weather_sun.png") end
	for _, k in ipairs(SPeditor.LightKinds or {}) do
		sub:AddOption(SPeditor.LN("lkind_", k.name), function() C.SpawnLightKind(k) end)
			:SetIcon(k.ltype == 0 and "icon16/lightbulb_off.png" or "icon16/lightbulb.png")
	end
end

-- shared light spawn in front of the work camera
function UI.SpawnLight(ltype)
	local cam = C.camera
	C.SendLightSpawn(ltype, cam.pos + cam.ang:Forward() * 150, cam.ang, Color(255, 244, 224), 400, 2, 60)
end
