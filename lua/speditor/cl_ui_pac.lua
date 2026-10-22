--[[
SPeditor — the PAC3 window (a0.7): a small window instead of PAC3's own editor, which takes
the whole height of the screen and asks you to dress yourself first.

  * the object it dresses: the one it was opened for; selecting another character or prop
    in the editor moves the window to it;
  * the outfits it wears: take one off, put on a saved one (data/pac3/*.txt);
  * a new part — a model on a bone (a hat, glasses, a backpack, a TF2 cosmetic): the model,
    the bone, the place, the turn and the size, seen on the object while you set them; Save
    writes an ordinary PAC3 outfit file (it opens in PAC3's own editor too) and puts it on;
  * PAC3's own editor, for outfits of many parts, effects and materials.

  UI.OpenPACWindow(ent)
]]
SPeditor.UI = SPeditor.UI or {}
local UI   = SPeditor.UI
local C    = SPeditor.Client
local L    = SPeditor.L
local PAC  = SPeditor.PAC
local Dock = SPeditor.Dock
local COL  = UI.PAL

-- models people put on heads; only the ones the game has are offered
local PRESETS = {
	"models/props_junk/TrafficCone001a.mdl",
	"models/props_junk/watermelon01.mdl",
	"models/props_c17/metalPot001a.mdl",
	"models/props_junk/MetalBucket01a.mdl",
	"models/props_interiors/pot02a.mdl",
	"models/props_junk/garbage_takeoutcarton001a.mdl",
	"models/player/items/humans/top_hat.mdl",                       -- TF2 (mounted)
	"models/player/items/all_class/all_class_oculus_heavy.mdl",
}

local function header(parent, text)
	local h = vgui.Create("DPanel", parent)
	h:Dock(TOP)
	h:DockMargin(0, 6, 0, 2)
	h:SetTall(UI.S(20))
	h.Paint = function(_, w, ht)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, ht)
		surface.SetDrawColor(COL.ORANGE)
		surface.DrawRect(0, 0, 3, ht)
		draw.SimpleText(text, "SPeditor.Bold", 8, ht / 2, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	return h
end

local function row(parent, text)
	local r = vgui.Create("DPanel", parent)
	r:Dock(TOP)
	r:DockMargin(4, 2, 4, 0)
	r:SetTall(UI.S(22))
	r.Paint = function() end
	local l = vgui.Create("DLabel", r)
	l:Dock(LEFT)
	l:SetWide(UI.S(96))
	l:SetFont("SPeditor.Small")
	l:SetTextColor(COL.TEXT)
	l:SetText(text)
	return r
end

-- the bones PAC3 knows the object by ("head", "spine 4", …), the head first
local function boneNames(ent)
	local out = {}
	local ok, bones = pcall(pac.GetModelBones, ent)
	if ok and istable(bones) then
		for name, b in pairs(bones) do
			if isstring(name) and istable(b) and not b.is_special and not b.is_attachment and not string.find(name, "invalid", 1, true) then out[#out + 1] = name end
		end
	end
	table.sort(out, function(a, b)
		if (a == "head") ~= (b == "head") then return a == "head" end
		return a < b
	end)
	if #out == 0 then out[1] = "none" end
	return out
end

local function newID() return util.SHA256(tostring(SysTime()) .. tostring(math.random()) .. tostring(FrameNumber())) end

-- the outfit of one part: a group (the outfit) with a model on a bone
local function outfitOf(p)
	return {
		self = { ClassName = "group", UniqueID = p.gid, Name = p.name ~= "" and p.name or "outfit", OwnerName = "self" },
		children = { {
			self = { ClassName = "model2", UniqueID = p.mid, Name = "", Model = p.model, Bone = p.bone,
				Position = Vector(p.x, p.y, p.z), Angles = Angle(p.pitch, p.yaw, p.roll), Size = p.size },
			children = {},
		} },
	}
end

function UI.OpenPACWindow(ent)
	if not IsValid(ent) or C.IsAux(ent) then return end
	local old = Dock.ByKey("pac")
	local x, y = math.floor(ScrW() / 2 - 180), 110
	if IsValid(old) then
		x, y = old:GetPos()
		old:Remove()
	end
	local win, body = Dock.Create({ key = "pac", id = "pac", title = L("pac_win"), w = 360, h = math.min(620, ScrH() - 160),
			x = x, y = y, dockable = false, icon = "icon16/user_suit.png" })
	win.minW, win.minH = UI.S(320), UI.S(300)
	win.SPState = function() return ent end

	-- the part being made, seen on the object (only here, not saved) until Save
	local part = { name = "", model = PRESETS[1], bone = "head", x = 0, y = 0, z = 0, pitch = 0, yaw = 0, roll = 0, size = 1,
		gid = newID(), mid = newID() }
	local preview, previewOn          -- the attached outfit table, the entity it is on
	local function dropPreview()
		if IsValid(previewOn) and preview and previewOn.RemovePACPart then pcall(previewOn.RemovePACPart, previewOn, preview) end
		if IsValid(previewOn) then PAC.SetKeep(previewOn, "preview", {}) end
		preview, previewOn = nil, nil
	end
	local function showPreview()
		dropPreview()
		if not PAC.Available() or not IsValid(ent) or part.model == "" then return end
		if not ent.AttachPACPart then pac.SetupENT(ent, "self") end
		ent.pac_owner = "self"
		preview = outfitOf(part)
		previewOn = ent
		PAC.SetKeep(ent, "preview", { preview })
		pcall(ent.AttachPACPart, ent, preview, ent)
		if ent.SetPACDrawDistance then ent:SetPACDrawDistance(0) end
	end
	-- sliders move many times a second: the outfit is put on again at most 20 times a second
	local dirtyAt
	local function changed() dirtyAt = RealTime() end

	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		dropPreview()
		if baseRemove then baseRemove(s) end
		Dock.pages.pac = nil
	end

	local title = vgui.Create("DPanel", body)
	title:Dock(TOP)
	title:SetTall(UI.S(24))
	title.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText(IsValid(ent) and C.DisplayName(ent) or "—", "SPeditor.Bold", 8, h / 2, COL.ORANGE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(32))
	foot.Paint = function() end
	local full = vgui.Create("DButton", foot)
	full:Dock(LEFT)
	full:DockMargin(6, 4, 4, 4)
	full:SetWide(UI.S(190))
	full:SetIcon("icon16/pencil.png")
	full:SetText("  " .. L("pac_editor"))
	UI.StyleButton(full, nil, 3)
	full.DoClick = function() PAC.OpenEditor() end
	local close = vgui.Create("DButton", foot)
	close:Dock(RIGHT)
	close:DockMargin(4, 4, 6, 4)
	close:SetWide(UI.S(100))
	close:SetText(L("about_close"))
	UI.StyleButton(close, nil, 3)
	close.DoClick = function() win:Remove() end

	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	scroll:DockMargin(4, 0, 4, 0)

	if not PAC.Available() then
		local miss = UI.Label(scroll, L("pac_missing"), COL.ORANGE)
		miss:SetWrap(true)
		miss:SetAutoStretchVertical(true)
	end

	-----------------------------------------------------------------
	-- The outfits it wears
	-----------------------------------------------------------------
	header(scroll, L("pac_worn"))
	local worn = vgui.Create("DPanel", scroll)
	worn:Dock(TOP)
	worn.Paint = function() end
	local function rebuildWorn()
		worn:Clear()
		local list = PAC.List(ent)
		worn:SetTall(math.max(#list, 1) * UI.S(23) + 4)
		if #list == 0 then UI.Label(worn, L("pac_worn_none")):SetTall(UI.S(20)) end
		for i, it in ipairs(list) do
			local r = vgui.Create("DPanel", worn)
			r:Dock(TOP)
			r:DockMargin(4, 1, 4, 0)
			r:SetTall(UI.S(22))
			r.Paint = function(_, w, h)
				surface.SetDrawColor(COL.ROW_B)
				surface.DrawRect(0, 0, w, h)
				draw.SimpleText(it.name, "SPeditor.Small", 8, h / 2, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			UI.IconButton(r, "icon16/cross.png", L("pac_remove"), function() PAC.Remove(ent, i) end, nil, RIGHT)
		end
		scroll:InvalidateLayout()
	end

	local putRow = row(scroll, L("pac_add"))
	local filesBox = UI.StyleCombo(vgui.Create("DComboBox", putRow))
	filesBox:Dock(FILL)
	local function fillFiles()
		filesBox:Clear()
		local files = PAC.Files()
		filesBox:SetValue(#files == 0 and L("pac_none_short") or L("pac_choose"))
		for _, name in ipairs(files) do filesBox:AddChoice(name, name) end
	end
	fillFiles()
	filesBox.OnSelect = function(_, _, _, name) PAC.Add(ent, name) end
	UI.IconButton(putRow, "icon16/arrow_refresh.png", L("pac_refresh"), fillFiles, nil, RIGHT)

	-----------------------------------------------------------------
	-- A new part: a model on a bone
	-----------------------------------------------------------------
	header(scroll, L("pac_new"))
	local hint = UI.Label(scroll, L("pac_new_hint"))
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)

	local mRow = row(scroll, L("pac_model"))
	local modelBox = UI.StyleCombo(vgui.Create("DComboBox", mRow))
	modelBox:Dock(FILL)
	modelBox:SetValue(part.model)
	local function fillModels()
		modelBox:Clear()
		modelBox:SetValue(part.model)
		local seen = {}
		-- the models of the scene's props first: spawn a prop from the browser and pick it here
		for _, obj in ipairs(C.BuildEntityList()) do
			local m = IsValid(obj.ent) and obj.ent ~= ent and obj.kind == "prop" and obj.ent:GetModel()
			if m and not seen[m] then
				seen[m] = true
				modelBox:AddChoice(L("pac_model_scene") .. ": " .. obj.name, m)
			end
		end
		for _, m in ipairs(PRESETS) do
			if not seen[m] and file.Exists(m, "GAME") then
				seen[m] = true
				modelBox:AddChoice(string.GetFileFromFilename(m), m)
			end
		end
	end
	fillModels()
	local modelEntry = vgui.Create("DTextEntry", scroll)
	modelEntry:Dock(TOP)
	modelEntry:DockMargin(UI.S(96) + 4, 2, 4, 0)
	modelEntry:SetTall(UI.S(20))
	modelEntry:SetValue(part.model)
	modelEntry:SetPlaceholderText(L("pac_model_ph"))
	modelEntry.OnEnter = function(s)
		part.model = string.Trim(s:GetValue())
		modelBox:SetValue(part.model)
		changed()
	end
	modelBox.OnSelect = function(_, _, _, m)
		part.model = m
		modelEntry:SetValue(m)
		changed()
	end

	local bRow = row(scroll, L("pac_bone"))
	local boneBox = UI.StyleCombo(vgui.Create("DComboBox", bRow))
	boneBox:Dock(FILL)
	local function fillBones()
		boneBox:Clear()
		local names = boneNames(ent)
		if not table.HasValue(names, part.bone) then part.bone = names[1] end
		for _, n in ipairs(names) do boneBox:AddChoice(n, n, n == part.bone) end
	end
	fillBones()
	boneBox.OnSelect = function(_, _, _, n)
		part.bone = n
		changed()
	end

	local sliders = {}
	local function slider(label, key, min, max, dec)
		local s = UI.Slider(scroll, label, min, max, dec, part[key], function(v)
			part[key] = v
			changed()
		end)
		sliders[key] = s
	end
	slider(L("pac_fwd"), "x", -60, 60, 1)
	slider(L("pac_side"), "y", -60, 60, 1)
	slider(L("pac_up"), "z", -60, 60, 1)
	slider(L("pac_pitch"), "pitch", -180, 180, 0)
	slider(L("pac_yaw"), "yaw", -180, 180, 0)
	slider(L("pac_roll"), "roll", -180, 180, 0)
	slider(L("pac_size"), "size", 0.05, 5, 2)

	local reset = UI.Button(scroll, L("pac_reset"), "icon16/arrow_undo.png", function()
		for k, v in pairs({ x = 0, y = 0, z = 0, pitch = 0, yaw = 0, roll = 0, size = 1 }) do
			part[k] = v
			if IsValid(sliders[k]) then sliders[k]:SetValue(v) end
		end
		changed()
	end)
	reset:DockMargin(4, 4, 4, 0)

	local nRow = row(scroll, L("pac_name"))
	local nameEntry = vgui.Create("DTextEntry", nRow)
	nameEntry:Dock(FILL)
	nameEntry:SetPlaceholderText(L("pac_name_ph"))
	local save = UI.Button(scroll, L("pac_save"), "icon16/disk.png", function()
		local name = SPeditor.SafeName(string.Trim(nameEntry:GetValue()))
		if name == "" then name = "gmfm_" .. os.date("%Y%m%d_%H%M%S") end
		local ld = PAC.LuaData()
		if not ld or part.model == "" then
			SPeditor.Notify("#pac_missing", 1)
			return
		end
		part.name = name
		local out = outfitOf(part)
		out.self.UniqueID, out.children[1].self.UniqueID = newID(), newID()
		file.CreateDir("pac3")
		file.Write("pac3/" .. name .. ".txt", ld.Encode({ out }))
		dropPreview()
		PAC.Add(ent, name)
		SPeditor.Notify("#pac_saved|" .. name .. "|garrysmod/data/pac3/" .. name .. ".txt", 2)
		-- a fresh part for the next one, the same settings to start from
		part.gid, part.mid = newID(), newID()
		fillFiles()
	end, 26)
	save:DockMargin(4, 6, 4, 4)

	-- set the part from code (the guides' demonstrations): { model, bone, x, y, z, pitch, yaw, roll, size, name }
	win.SPSetPart = function(t)
		for k, v in pairs(t) do
			if k == "name" then nameEntry:SetValue(v)
			elseif part[k] ~= nil then part[k] = v end
			if IsValid(sliders[k]) then sliders[k]:SetValue(v) end
		end
		if t.model then modelBox:SetValue(part.model) modelEntry:SetValue(part.model) end
		if t.bone then fillBones() end
		changed()
	end
	win.SPSave = function() save:DoClick() end

	-----------------------------------------------------------------
	-- Following the object and the selection
	-----------------------------------------------------------------
	local wornSig
	scroll.Think = function()
		if not IsValid(ent) then
			if IsValid(win) then win:Remove() end
			return
		end
		-- another character or prop selected: the window dresses it
		local sel = C.selected
		if IsValid(sel) and sel ~= ent and not C.IsAux(sel) and (C.IsRagdoll(sel) or sel:GetClass() == "prop_physics" or sel:GetClass() == "prop_dynamic") then
			dropPreview()
			ent = sel
			wornSig = nil
			fillBones()
			fillModels()
			changed()
		end
		local sig = { ent:EntIndex() }
		for _, it in ipairs(PAC.List(ent)) do sig[#sig + 1] = it.name end
		sig = table.concat(sig, "|")
		if sig ~= wornSig then
			wornSig = sig
			rebuildWorn()
		end
		if dirtyAt and RealTime() - dirtyAt > 0.05 then
			dirtyAt = nil
			showPreview()
		end
	end
	changed()
end
