--[[
SPeditor — the "Object properties" window (right click on an object → Properties…).

Extended properties of models (props and characters):
  * colour and opacity;
  * material: replace the textures as a whole or slot by slot, remove them entirely
    (the model turns plain white and takes the chosen colour), restore them;
  * size (props only): overall scale and stretching in length, width, height;
  * shadow: cast it or not.
Everything goes into history (undo/redo), is saved in scenes and copied by duplicate
(see S.ApplyLook in sv_speditor.lua, C.EditLook in cl_net.lua).
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI   = SPeditor.UI
local C    = SPeditor.Client
local L    = SPeditor.L
local Dock = SPeditor.Dock
local COL  = UI.PAL

local WHITE_MAT = SPeditor.WhiteMaterial

local function header(parent, text)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:DockMargin(0, 6, 0, 2)
	p:SetTall(UI.S(18))
	p.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText(text, "SPeditor.Bold", 6, h / 2, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	return p
end

local function button(parent, text, icon, fn)
	local b = UI.Button(parent, text, icon, fn)
	b:DockMargin(4, 2, 4, 0)
	return b
end

-- Quick actions for the object menu
function UI.RemoveTextures(ent)
	C.EditLook(ent, { material = WHITE_MAT, submats = {} }, true)
end

function UI.RestoreTextures(ent)
	C.EditLook(ent, { material = "", submats = {} }, true)
end

function UI.ResetLook(ent)
	-- bone locks are kept in the look too, but they are not a part of the appearance
	C.SendLook(ent, { locks = C.GetLook(ent).locks }, true)
end

function UI.OpenObjectProps(ent)
	if not IsValid(ent) or C.IsAux(ent) then return end
	local old = Dock.ByKey("props")
	local x, y = math.floor(ScrW() / 2 - 190), 110
	if IsValid(old) then
		x, y = old:GetPos()
		old:Remove()
	end

	local win, body = Dock.Create({ key = "props", id = "props", title = L("props_title"), w = 380, h = math.min(680, ScrH() - 150),
			x = x, y = y, dockable = false, icon = "icon16/wrench.png" })
	win.minW, win.minH = UI.S(320), UI.S(300)
	win.SPState = function() return ent end
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.props = nil
	end

	local title = vgui.Create("DPanel", body)
	title:Dock(TOP)
	title:SetTall(UI.S(24))
	title.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText(IsValid(ent) and C.DisplayName(ent) or "—", "SPeditor.Bold", 8, h / 2, COL.ORANGE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
	title.Think = function() if not IsValid(ent) and IsValid(win) then win:Remove() end end

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(32))
	foot.Paint = function() end
	local reset = vgui.Create("DButton", foot)
	reset:Dock(LEFT)
	reset:DockMargin(6, 4, 4, 4)
	reset:SetWide(UI.S(190))
	reset:SetText(L("props_reset"))
	UI.StyleButton(reset, nil, 3)
	local close = vgui.Create("DButton", foot)
	close:Dock(RIGHT)
	close:DockMargin(4, 4, 6, 4)
	close:SetWide(UI.S(100))
	close:SetText(L("about_close"))
	UI.StyleButton(close, nil, 3)
	close.DoClick = function() win:Remove() end

	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)

	-----------------------------------------------------------------
	-- Colour
	-----------------------------------------------------------------
	header(scroll, L("props_color"))
	local mixer = vgui.Create("DColorMixer", scroll)
	mixer:Dock(TOP)
	mixer:DockMargin(4, 2, 4, 0)
	mixer:SetTall(UI.S(150))
	mixer:SetPalette(false)
	mixer:SetAlphaBar(true)
	mixer:SetColor(ent:GetColor())
	local colorEdit, syncing = 0, false
	mixer.ValueChanged = function(_, c)
		if syncing or not IsValid(ent) then return end
		colorEdit = RealTime()
		C.EditLook(ent, { color = { c.r, c.g, c.b, c.a or 255 } })
	end
	-- the colour is changed both from the menu and by undo: the palette follows while it is not touched
	mixer.Think = function()
		if not IsValid(ent) or RealTime() - colorEdit < 1 then return end
		local c, m = ent:GetColor(), mixer:GetColor()
		if c.r ~= m.r or c.g ~= m.g or c.b ~= m.b or c.a ~= (m.a or 255) then
			syncing = true
			mixer:SetColor(c)
			syncing = false
		end
	end
	button(scroll, L("props_color_reset"), "icon16/color_wheel.png", function()
		C.EditLook(ent, { color = { 255, 255, 255, 255 } }, true)
	end)

	-----------------------------------------------------------------
	-- Material
	-----------------------------------------------------------------
	header(scroll, L("props_material"))
	local slot = -1          -- -1 — the whole model, otherwise the material slot number
	local slots = ent:GetMaterials() or {}

	local targetRow = vgui.Create("DPanel", scroll)
	targetRow:Dock(TOP)
	targetRow:DockMargin(4, 2, 4, 0)
	targetRow:SetTall(UI.S(22))
	targetRow.Paint = function() end
	local tl = vgui.Create("DLabel", targetRow)
	tl:Dock(LEFT)
	tl:SetWide(UI.S(96))
	tl:SetFont("SPeditor.Small")
	tl:SetTextColor(COL.TEXT)
	tl:SetText(L("props_mat_target"))
	local target = UI.StyleCombo(vgui.Create("DComboBox", targetRow))
	target:Dock(FILL)
	target:AddChoice(L("props_mat_all"), -1, true)
	for i, path in ipairs(slots) do
		target:AddChoice(string.format("%d: %s", i - 1, string.GetFileFromFilename(path) or path), i - 1)
	end

	local current = vgui.Create("DLabel", scroll)
	current:Dock(TOP)
	current:DockMargin(6, 3, 6, 0)
	current:SetFont("SPeditor.Small")
	current:SetTextColor(COL.DIM)
	current:SetText("")

	local function currentMaterial()
		if not IsValid(ent) then return "" end
		local look = C.GetLook(ent)
		if slot >= 0 then return look.submats[tostring(slot)] or "" end
		return look.material or ""
	end

	local function setMaterial(path)
		if not IsValid(ent) then return end
		path = string.Trim(path or "")
		if slot < 0 then
			-- "restore textures" for the whole model also removes the replacements of single slots
			C.EditLook(ent, { material = path, submats = (path == "") and {} or nil }, true)
		else
			local sub = C.GetLook(ent).submats
			sub[tostring(slot)] = (path ~= "") and path or nil
			C.EditLook(ent, { submats = sub }, true)
		end
	end

	-- the colour of the chosen slot (a0.8, as SFM's material colour): tints that material only
	local tintHint = UI.Label(scroll, L("props_tint_hint"))
	tintHint:DockMargin(6, 3, 6, 0)
	local tintBox = vgui.Create("DPanel", scroll)
	tintBox:Dock(TOP)
	tintBox:DockMargin(4, 2, 4, 0)
	tintBox:SetTall(UI.S(150) + UI.S(24) + UI.S(16))
	tintBox.Paint = function() end
	local tintLabel = vgui.Create("DLabel", tintBox)
	tintLabel:Dock(TOP)
	tintLabel:SetTall(UI.S(16))
	tintLabel:SetFont("SPeditor.Small")
	tintLabel:SetTextColor(COL.TEXT)
	local tintMixer = vgui.Create("DColorMixer", tintBox)
	tintMixer:Dock(TOP)
	tintMixer:SetTall(UI.S(150))
	tintMixer:SetPalette(false)
	tintMixer:SetAlphaBar(false)
	local function slotTint()
		local t = IsValid(ent) and C.GetLook(ent).tints[tostring(slot)]
		return t and Color(t[1], t[2], t[3]) or Color(255, 255, 255)
	end
	local tintEdit, tintSync = 0, false
	local function setTint(c)
		if not IsValid(ent) or slot < 0 then return end
		local tints = C.GetLook(ent).tints
		tints[tostring(slot)] = (c.r < 255 or c.g < 255 or c.b < 255) and { c.r, c.g, c.b } or nil
		C.EditLook(ent, { tints = tints })
	end
	tintMixer.ValueChanged = function(_, c)
		if tintSync then return end
		tintEdit = RealTime()
		setTint(c)
	end
	tintMixer.Think = function()
		if not IsValid(ent) or slot < 0 or RealTime() - tintEdit < 1 then return end
		local c, m = slotTint(), tintMixer:GetColor()
		if c.r ~= m.r or c.g ~= m.g or c.b ~= m.b then
			tintSync = true
			tintMixer:SetColor(c)
			tintSync = false
		end
	end
	local tintReset = UI.Button(tintBox, L("props_tint_reset"), "icon16/color_wheel.png", function()
		tintEdit = 0
		setTint(Color(255, 255, 255))
	end)
	tintReset:Dock(TOP)
	tintReset:DockMargin(0, 2, 0, 0)
	local function showTint()
		tintBox:SetVisible(slot >= 0)
		tintHint:SetVisible(slot < 0)
		if slot >= 0 then
			tintLabel:SetText(string.format(L("props_tint_of"), string.GetFileFromFilename(slots[slot + 1] or "") or ""))
			tintSync = true
			tintMixer:SetColor(slotTint())
			tintSync = false
		end
		scroll:InvalidateLayout()
	end
	showTint()

	target.OnSelect = function(_, _, _, data)
		slot = data
		showTint()
	end
	current.Think = function(s)
		local m = currentMaterial()
		local text = L("props_mat_current") .. ": " .. (m == "" and L("props_mat_original") or (m == WHITE_MAT and L("props_mat_none") or m))
		if s.SPText ~= text then
			s.SPText = text
			s:SetText(text)
		end
	end

	button(scroll, L("props_mat_remove"), "icon16/picture_delete.png", function() setMaterial(WHITE_MAT) end)
	button(scroll, L("props_mat_restore"), "icon16/picture_go.png", function() setMaterial("") end)

	local path = vgui.Create("DTextEntry", scroll)
	path:Dock(TOP)
	path:DockMargin(4, 4, 4, 2)
	path:SetTall(UI.S(20))
	path:SetFont("SPeditor.Small")
	path:SetPlaceholderText(L("props_mat_path"))
	path.OnEnter = function(s) setMaterial(s:GetValue()) end

	-- materials of the Material tool (the same list as in the Q menu)
	local grid = vgui.Create("DIconLayout", scroll)
	grid:Dock(TOP)
	grid:DockMargin(4, 2, 4, 0)
	grid:SetSpaceX(2)
	grid:SetSpaceY(2)
	local seen = {}
	for _, mat in ipairs(list.Get("OverrideMaterials") or {}) do
		if isstring(mat) and not seen[mat] then
			seen[mat] = true
			local b = grid:Add("DImageButton")
			b:SetSize(UI.S(56), UI.S(56))
			b:SetOnViewMaterial(mat, "models/wireframe")
			b:SetTooltip(mat)
			b.DoClick = function() setMaterial(mat) end
			b.PaintOver = function(_, w, h)
				if currentMaterial() ~= mat then return end
				surface.SetDrawColor(COL.ORANGE)
				surface.DrawOutlinedRect(0, 0, w, h, 2)
			end
		end
	end

	-----------------------------------------------------------------
	-- Size (props only)
	-----------------------------------------------------------------
	if C.CanScale(ent) then
		header(scroll, L("props_size"))
		local ref = C.Ref(ent)
		UI.Control(scroll, { label = L("props_scale"), min = 0.05, max = 10, default = 1, value = ent:GetModelScale() or 1,
				onChange = function(v, final)
					if not IsValid(ent) then return end
					local s0 = ent:GetModelScale() or 1
					C.SendScale(ent, v, final)
					C.BurstEdit("evs" .. ent:EntIndex(), "scale", function() return s0 end, v, function(s)
						local e = C.Deref(ref)
						if e then C.SendScale(e, s, true) end
					end)
				end,
				getter = function() return IsValid(ent) and (ent:GetModelScale() or 1) or nil end })
		for i, key in ipairs({ "props_len", "props_wid", "props_hei" }) do
			UI.Control(scroll, { label = L(key), min = 0.05, max = 10, default = 1, value = C.GetStretch(ent)[i],
					onChange = function(v, final)
						if not IsValid(ent) then return end
						local st = C.GetStretch(ent)
						st[i] = v
						C.EditLook(ent, { stretch = { st.x, st.y, st.z } }, final)
					end,
					getter = function() return IsValid(ent) and C.GetStretch(ent)[i] or nil end })
		end
		UI.Label(scroll, L("props_size_hint")):DockMargin(6, 3, 6, 0)
	end

	-----------------------------------------------------------------
	-- Shadow
	-----------------------------------------------------------------
	header(scroll, L("props_shadow"))
	UI.ToggleRow(scroll, L("props_cast_shadow"), function()
		return IsValid(ent) and not C.GetLook(ent).noshadow
	end, function(v)
		C.EditLook(ent, { noshadow = not v }, true)
	end)

	local pad = vgui.Create("DPanel", scroll)
	pad:Dock(TOP)
	pad:SetTall(UI.S(8))
	pad.Paint = function() end

	reset.DoClick = function()
		if not IsValid(ent) then return end
		UI.ResetLook(ent)
	end
	return win
end

---------------------------------------------------------------------
-- Base pose of a model without physics (a prop_dynamic: a model with no ragdoll, e.g. one
-- ported from SFM). Such a model is posed by bone offsets on top of an animation of its own,
-- held at one moment; this window picks the animation and the moment (look.seq / look.cycle).
---------------------------------------------------------------------
function UI.IsPoseProp(ent)
	return IsValid(ent) and ent:GetClass() == "prop_dynamic" and (ent:GetBoneCount() or 0) > 1
end

function UI.OpenBasePose(ent)
	if not UI.IsPoseProp(ent) then return end
	local key = "basepose"
	local old = Dock.ByKey(key)
	if IsValid(old) then old:Remove() end
	local W = 420
	local win, body = Dock.Create({ key = key, id = key, title = L("bpose_title") .. ": " .. C.DisplayName(ent), w = W, h = 460,
			x = math.floor(ScrW() / 2 - W / 2), y = 130, dockable = false, icon = "icon16/user_edit.png" })
	win.minW, win.minH = UI.S(320), UI.S(300)

	local hint = UI.Label(body, L("bpose_hint"))
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:DockMargin(8, 6, 8, 4)
	local search = vgui.Create("DTextEntry", body)
	search:Dock(TOP)
	search:DockMargin(8, 0, 8, 4)
	search:SetTall(UI.S(22))
	search:SetPlaceholderText(L("bpose_search"))

	local cycle = UI.Slider(body, L("bpose_cycle"), 0, 1, 3, ent:GetCycle(), nil)
	cycle:Dock(BOTTOM)
	cycle:DockMargin(8, 4, 8, 8)

	local list = vgui.Create("DListView", body)

	UI.StyleListView(list)
	list:Dock(FILL)
	list:DockMargin(8, 0, 8, 0)
	list:SetMultiSelect(false)
	list:AddColumn(L("bpose_anim"))
	list:AddColumn(L("sa_imp_col_len")):SetFixedWidth(70)

	local busy = false
	local seqs = {}
	for id, name in pairs(ent:GetSequenceList() or {}) do
		seqs[#seqs + 1] = { id = id, name = name, dur = ent:SequenceDuration(id) or 0 }
	end
	table.sort(seqs, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
	local function fill()
		list:Clear()
		local q = string.lower(string.Trim(search:GetValue() or ""))
		local curName = ent:GetSequenceName(ent:GetSequence())
		local n, at = 0, nil
		for _, sq in ipairs(seqs) do
			if q == "" or string.find(string.lower(sq.name), q, 1, true) then
				local line = list:AddLine(sq.name, string.format("%.2f", sq.dur))
				line.seqName = sq.name
				n = n + 1
				if sq.name == curName then
					busy = true
					list:SelectItem(line)
					busy = false
					at = n
				end
			end
		end
		-- the animation in use is scrolled into view
		if at then
			-- after the list has its size (its scroll bar knows how far it can go)
			timer.Simple(0.15, function()
				if not IsValid(list) or not IsValid(list.VBar) then return end
				list:InvalidateLayout(true)
				list.VBar:SetScroll(math.max(at - 4, 0) * list:GetDataHeight())
			end)
		end
	end
	search.OnChange = fill
	fill()

	local function apply(name, cyc)
		if not IsValid(ent) or busy then return end
		C.EditLook(ent, { seq = name, cycle = cyc })
	end
	list.OnRowSelected = function(_, _, line)
		if line.seqName ~= ent:GetSequenceName(ent:GetSequence()) then apply(line.seqName, cycle:GetValue()) end
	end
	cycle.OnValueChanged = function(_, v)
		local _, line = list:GetSelectedLine()
		apply(line and line.seqName or ent:GetSequenceName(ent:GetSequence()), v)
	end
	return win
end
