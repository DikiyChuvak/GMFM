--[[
GM:FM — picking the texture (mask) of a spot light with pictures (b0.2).

UI.PickLightTexture{ ent, current, onPick(path, final) }
  A window with every light texture as a picture: the soft masks of the editor, the textures
  of the Lamp tool and the other light textures of the game and the mounted addons
  (SPeditor.Lights.TextureList). Under the cursor a texture is shown big on the right, in the
  colour of the light. A click puts it on the light at once, so it is seen in the scene too;
  "Choose" (or a double click) keeps it, "Cancel" and closing the window give the light back
  the texture it had.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI   = SPeditor.UI
local L    = SPeditor.L
local Dock = SPeditor.Dock

local TILE, THUMB = 92, 72

-- one material per texture, made when its picture is first drawn. The texture is given when the
-- material is made: swapped in later (SetTexture), it is drawn with the sizes of the one it
-- replaced, and over a 1-pixel placeholder the whole picture came out as its middle pixel.
local mats, nMats = {}, 0
local function matFor(path)
	local Lt = SPeditor.Lights
	-- the editor's own masks are drawn into a texture of their own a moment later
	local tex, key = path, path
	if Lt.IsGenerated(path) then tex, key = Lt.Mask(path, 0) end
	local m = mats[path]
	if not m or m.key ~= key then
		nMats = nMats + 1
		m = { key = key, mat = CreateMaterial("gmfm_lpick3_" .. nMats, "UnlitGeneric", {
			["$basetexture"] = isstring(tex) and tex or tex:GetName(), ["$vertexcolor"] = "1", ["$nolod"] = "1" }) }
		mats[path] = m
	end
	return m.mat
end

local function lightColor(ent)
	if not IsValid(ent) or not ent.GetLightColor then return Color(255, 255, 255) end
	local v = ent:GetLightColor()
	local k = 255 / math.max(v.x, v.y, v.z, 0.001)
	return Color(math.Clamp(v.x * k, 0, 255), math.Clamp(v.y * k, 0, 255), math.Clamp(v.z * k, 0, 255))
end

-- a texture over a dark checked floor, in the colour of the light
local function drawTexture(path, x, y, w, h, col)
	surface.SetDrawColor(14, 14, 16, 255)
	surface.DrawRect(x, y, w, h)
	if not path or path == "" then return end
	surface.SetMaterial(matFor(path))
	surface.SetDrawColor(col or color_white)
	surface.DrawTexturedRect(x, y, w, h)
end

UI.DrawLightTexture = drawTexture

function UI.PickLightTexture(o)
	o = o or {}
	local old = Dock.ByKey("lmask_pick")
	if IsValid(old) then old:Remove() end
	local COL = UI.PAL
	local Lt = SPeditor.Lights
	local ent = o.ent
	local original = o.current or ""
	local chosen = original
	local hovered = nil
	local kept = false

	local W = 820
	local win, body = Dock.Create({ key = "lmask_pick", id = "lmask_pick", title = L("lpick_title"),
		w = W, h = math.min(560, ScrH() - 140), x = math.floor(ScrW() / 2 - UI.S(W) / 2), y = 110,
		dockable = false, icon = "icon16/photos.png" })
	win.minW, win.minH = UI.S(520), UI.S(340)
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		-- closed without "Choose": the light gets its own texture back
		if not kept and chosen ~= original and o.onPick then o.onPick(original, true) end
	end

	local function try(path)
		if path == chosen then return end
		chosen = path
		if o.onPick then o.onPick(path, false) end
	end

	-- the top: which textures and a search
	local top = vgui.Create("DPanel", body)
	top:Dock(TOP)
	top:DockMargin(6, 6, 6, 2)
	top:SetTall(UI.S(22))
	top.Paint = function() end
	local groups = UI.StyleCombo(vgui.Create("DComboBox", top))
	groups:Dock(LEFT)
	groups:SetWide(UI.S(230))
	groups:SetSortItems(false)
	local search = vgui.Create("DTextEntry", top)
	search:Dock(FILL)
	search:DockMargin(6, 0, 0, 0)
	search:SetFont("SPeditor.Small")
	search:SetPlaceholderText(L("lpick_search"))

	-- the bottom: the buttons
	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:DockMargin(6, 2, 6, 6)
	foot:SetTall(UI.S(26))
	foot.Paint = function() end
	local function btn(text, icon, w, dock, fn)
		local b = vgui.Create("DButton", foot)
		b:Dock(dock)
		b:DockMargin(2, 0, 2, 0)
		b:SetWide(UI.S(w))
		b:SetText("  " .. text)
		b:SetIcon(icon)
		UI.StyleButton(b, nil, 3)
		b.DoClick = fn
		return b
	end
	btn(L("lmask_custom") .. "…", "icon16/folder_picture.png", 170, LEFT, function()
		Derma_StringRequest(L("ctl_light_texture"), L("lmask_custom_prompt"), chosen, function(path)
			path = string.gsub(string.gsub(string.Trim(path), "\\", "/"), "%.vtf$", "")
			path = string.gsub(path, "^materials/", "")
			if path ~= "" and #path <= 96 and not string.find(path, "[^%w_%-/%.]") then
				try(path)
			else
				SPeditor.Notify("#lmask_custom_bad", 1)
			end
		end)
	end)
	btn(L("cancel"), "icon16/cross.png", 110, RIGHT, function() win:Remove() end)
	local okBtn = btn(L("snd_pick_choose"), "icon16/accept.png", 130, RIGHT, function()
		kept = true
		if o.onPick then o.onPick(chosen, true) end
		win:Remove()
	end)
	okBtn:SetTooltip(L("lpick_choose_tip"))

	-- the right: the big picture of the texture under the cursor (or the chosen one)
	local side = vgui.Create("DPanel", body)
	side:Dock(RIGHT)
	side:DockMargin(2, 2, 6, 2)
	side:SetWide(UI.S(280))
	side.Paint = function(s, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		local path = hovered or chosen
		if path == "" then path = SPeditor.DefaultLightTexture end
		local sz = math.min(w - 16, h - 96)
		local x, y = math.floor((w - sz) / 2), 8
		drawTexture(path, x, y, sz, sz, lightColor(ent))
		surface.SetDrawColor(COL.BORDER)
		surface.DrawOutlinedRect(x - 1, y - 1, sz + 2, sz + 2, 1)
		local ty = y + sz + 10
		draw.SimpleText(Lt.TextureName(path), "SPeditor.Bold", w / 2, ty, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		draw.SimpleText(Lt.IsGenerated(path) and L("lmask_group_gen") or path, "SPeditor.Small", w / 2, ty + 18, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		local state = (path == chosen) and L("lpick_on_light") or L("lpick_click_to_try")
		draw.SimpleText(state, "SPeditor.Small", w / 2, ty + 36, path == chosen and COL.GREEN or COL.ORANGE, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
	end

	-- the middle: the pictures
	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)
	scroll:DockMargin(6, 2, 2, 2)
	scroll.Paint = function(_, w, h)
		surface.SetDrawColor(COL.TREE_BG or COL.BG)
		surface.DrawRect(0, 0, w, h)
	end
	local grid = vgui.Create("DIconLayout", scroll)
	grid:Dock(TOP)
	grid:SetSpaceX(4)
	grid:SetSpaceY(4)
	grid:DockMargin(4, 4, 4, 4)

	local list = Lt.TextureList()
	groups:AddChoice(L("lpick_all"), 0, true)
	for i, g in ipairs(list) do
		if #g.items > 0 then groups:AddChoice(L(g.title) .. "  (" .. #g.items .. ")", i) end
	end
	local which = 0

	local function tile(path)
		local t = grid:Add("DButton")
		t:SetSize(UI.S(TILE), UI.S(TILE) + UI.S(16))
		t:SetText("")
		t:SetTooltip(Lt.IsGenerated(path) and Lt.TextureName(path) or path)
		local name = Lt.TextureName(path)
		t.Paint = function(s, w, h)
			local on = path == chosen
			local hot = s:IsHovered()
			if hot and hovered ~= path then hovered = path end
			surface.SetDrawColor(on and COL.TAB_ON or (hot and COL.ROW_A or COL.ROW_B))
			surface.DrawRect(0, 0, w, h)
			local th = UI.S(THUMB)
			local x = math.floor((w - th) / 2)
			drawTexture(path, x, 4, th, th, color_white)
			if on then
				surface.SetDrawColor(COL.ORANGE)
				surface.DrawOutlinedRect(0, 0, w, h, 2)
			end
			-- the name, cut to the tile (by letters: Cyrillic ones are two bytes)
			if s.fitW ~= w then
				s.fitW = w
				surface.SetFont("SPeditor.Small")
				local text = name
				if surface.GetTextSize(text) > w - 6 then
					local cps = {}
					for _, c in utf8.codes(name) do cps[#cps + 1] = utf8.char(c) end
					while #cps > 1 and surface.GetTextSize(table.concat(cps) .. "…") > w - 6 do table.remove(cps) end
					text = table.concat(cps) .. "…"
				end
				s.fitText = text
			end
			draw.SimpleText(s.fitText, "SPeditor.Small", w / 2, h - 3, on and COL.TEXT or COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
		end
		t.OnCursorExited = function() if hovered == path then hovered = nil end end
		t.DoClick = function() try(path) end
		t.DoDoubleClick = function()
			try(path)
			kept = true
			if o.onPick then o.onPick(path, true) end
			win:Remove()
		end
	end

	local function fill()
		grid:Clear()
		hovered = nil
		local q = string.lower(string.Trim(search:GetValue() or ""))
		local n = 0
		for i, g in ipairs(list) do
			if which == 0 or which == i then
				for _, path in ipairs(g.items) do
					if q == "" or string.find(string.lower(path), q, 1, true) or string.find(string.lower(Lt.TextureName(path)), q, 1, true) then
						tile(path)
						n = n + 1
					end
				end
			end
		end
		if n == 0 then
			local l = grid:Add("DLabel")
			l:SetFont("SPeditor.Small")
			l:SetTextColor(COL.DIM)
			l:SetText(L("lpick_none"))
			l:SizeToContents()
		end
		grid:InvalidateLayout(true)
	end
	groups.OnSelect = function(_, _, _, data)
		which = data
		fill()
	end
	search.OnChange = fill
	fill()
	return win
end
