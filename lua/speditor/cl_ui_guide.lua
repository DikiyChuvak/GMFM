--[[
SPeditor — "How to use" (a0.6): short illustrated guides to the tools, inside the game.
Help → How to use… opens the window; a "?" button in a tool's window (UI.GuideButton) opens
the guide of that tool. Every guide says what the tool is for, the steps, what comes out, and
shows it: a screenshot (materials/speditor/help/*.jpg) or a live animated demonstration.

A guide (core files and mods add their own):
  UI.AddGuide({ id, order = number, icon = "icon16/….png", title = { en =, ru = }, blocks = { … } })
Blocks, each text given in both languages:
  { "p", en, ru }                         a paragraph
  { "h", en, ru }                         a heading inside the guide
  { "steps", en = { … }, ru = { … } }     numbered steps
  { "img", "speditor/help/x.jpg", en, ru } a picture with a caption
  { "result", en, ru }                    what you get (a highlighted paragraph)
  { "demo", h = height, draw = function(w, h, t) end, en, ru }
                                          a live demonstration: draw is called every frame
                                          inside the block, t — seconds since it was shown
  { "try", en, ru, fn = function() end }  a button that opens the tool or does the step
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI   = SPeditor.UI
local L    = SPeditor.L
local COL  = UI.PAL
local Dock = SPeditor.Dock

UI.Guides = UI.Guides or {}       -- [id] = guide

function UI.AddGuide(g)
	if not istable(g) or not isstring(g.id) then return end
	UI.Guides[g.id] = g
end

-- the text of a block in the editor's language
local function T(en, ru)
	if GetConVarString("speditor_language") == "ru" and ru then return ru end
	return en or ru or ""
end
UI.GuideText = T

local function sorted()
	local list = {}
	for _, g in pairs(UI.Guides) do list[#list + 1] = g end
	table.sort(list, function(a, b)
		if (a.order or 100) ~= (b.order or 100) then return (a.order or 100) < (b.order or 100) end
		return a.id < b.id
	end)
	return list
end

---------------------------------------------------------------------
-- Blocks
---------------------------------------------------------------------
local function textBlock(parent, text, font, col, indent)
	local l = vgui.Create("DLabel", parent)
	l:Dock(TOP)
	l:DockMargin(indent or 10, 4, 10, 4)
	l:SetFont(font or "SPeditor.Small")
	l:SetTextColor(col or COL.TEXT)
	l:SetWrap(true)
	l:SetAutoStretchVertical(true)
	l:SetText(text)
	return l
end

local mats = {}
local function helpMat(path)
	local m = mats[path]
	if m == nil then
		m = Material(path, "smooth")
		if m:IsError() then m = false end
		mats[path] = m
	end
	return m or nil
end

local function imageBlock(parent, path, caption)
	local mat = helpMat(path)
	if not mat then return end
	local tex = mat:GetTexture("$basetexture")
	local iw, ih = tex and tex:Width() or 16, tex and tex:Height() or 9
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:DockMargin(10, 6, 10, 2)
	p.Paint = function(s, w, h)
		local dw = math.min(w, iw)
		local dh = math.floor(dw * ih / iw)
		local x = math.floor((w - dw) / 2)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.SetMaterial(mat)
		surface.DrawTexturedRect(x, 0, dw, dh)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawOutlinedRect(x, 0, dw, dh)
	end
	p.PerformLayout = function(s, w)
		local dh = math.floor(math.min(w, iw) * ih / iw)
		if s:GetTall() ~= dh then s:SetTall(dh) end
	end
	-- a click shows the picture as large as the screen allows
	p:SetCursor("hand")
	p.OnMousePressed = function()
		local f = vgui.Create("DPanel")
		f:SetSize(ScrW(), ScrH())
		f:MakePopup()
		f:SetCursor("hand")
		f.Paint = function(_, w, h)
			surface.SetDrawColor(0, 0, 0, 230)
			surface.DrawRect(0, 0, w, h)
			local k = math.min((w - 40) / iw, (h - 40) / ih, 1.5)
			local dw, dh = iw * k, ih * k
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(mat)
			surface.DrawTexturedRect((w - dw) / 2, (h - dh) / 2, dw, dh)
		end
		f.OnMousePressed = function(s) s:Remove() end
		f.OnKeyCodePressed = function(s) s:Remove() end
	end
	if caption and caption ~= "" then textBlock(parent, caption, "SPeditor.Small", COL.DIM) end
end

local function demoBlock(parent, b)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:DockMargin(10, 6, 10, 2)
	p:SetTall(UI.S(b.h or 90))
	local t0 = RealTime()
	p.Paint = function(s, w, h)
		surface.SetDrawColor(COL.LIST_BG or COL.BG)
		surface.DrawRect(0, 0, w, h)
		local ok, err = pcall(b.draw, w, h, RealTime() - t0)
		if not ok then
			b.draw = function() end
			ErrorNoHalt("[SPeditor] guide demo: " .. tostring(err) .. "\n")
		end
		surface.SetDrawColor(COL.BORDER)
		surface.DrawOutlinedRect(0, 0, w, h)
	end
	local cap = T(b[2], b[3])
	if cap ~= "" then textBlock(parent, cap, "SPeditor.Small", COL.DIM) end
end

local function buildBlocks(scroll, g)
	scroll:Clear()
	textBlock(scroll, T(g.title.en, g.title.ru), "SPeditor.Time", COL.TEXT)
	for _, b in ipairs(g.blocks or {}) do
		local kind = b[1]
		if kind == "p" then
			textBlock(scroll, T(b[2], b[3]))
		elseif kind == "h" then
			local l = textBlock(scroll, T(b[2], b[3]), "SPeditor.Bold", COL.ORANGE)
			l:DockMargin(10, 12, 10, 2)
		elseif kind == "steps" then
			local list = T(b.en, b.ru)
			for i, s in ipairs(istable(list) and list or {}) do
				textBlock(scroll, i .. ".  " .. s, "SPeditor.Small", COL.TEXT, 18)
			end
		elseif kind == "img" then
			imageBlock(scroll, b[2], T(b[3], b[4]))
		elseif kind == "result" then
			local holder = vgui.Create("DPanel", scroll)
			holder:Dock(TOP)
			holder:DockMargin(10, 6, 10, 4)
			holder:DockPadding(10, 4, 6, 4)
			holder.Paint = function(_, w, h)
				surface.SetDrawColor(COL.ROW_B)
				surface.DrawRect(0, 0, w, h)
				surface.SetDrawColor(COL.ORANGE)
				surface.DrawRect(0, 0, 3, h)
			end
			local l = textBlock(holder, L("guide_result") .. "  " .. T(b[2], b[3]))
			l:DockMargin(0, 0, 0, 0)
			holder.PerformLayout = function(s) s:SizeToChildren(false, true) end
		elseif kind == "demo" then
			demoBlock(scroll, b)
		elseif kind == "try" then
			local btn = UI.Button(scroll, T(b[2], b[3]), "icon16/arrow_right.png", function()
				local ok, err = pcall(b.fn)
				if not ok then ErrorNoHalt("[SPeditor] guide: " .. tostring(err) .. "\n") end
			end, 24)
			btn:DockMargin(10, 6, 10, 2)
		end
	end
	local pad = vgui.Create("DPanel", scroll)
	pad:Dock(TOP)
	pad:SetTall(UI.S(16))
	pad.Paint = function() end
end

---------------------------------------------------------------------
-- The window
---------------------------------------------------------------------
function UI.OpenGuide(id)
	local win = Dock.ByKey("guide")
	if not IsValid(win) then
		local W, H = math.min(940, ScrW() - 80), math.min(680, ScrH() - 120)
		local body
		win, body = Dock.Create({ key = "guide", id = "guide", title = L("guide_title"), w = W, h = H,
				x = math.floor(ScrW() / 2 - W / 2), y = 70, dockable = false, icon = "icon16/help.png" })
		win.minW, win.minH = UI.S(520), UI.S(320)
		local baseRemove = win.OnRemove
		win.OnRemove = function(s)
			if baseRemove then baseRemove(s) end
			Dock.pages.guide = nil
		end

		local list = vgui.Create("DListView", body)

		UI.StyleListView(list)
		list:Dock(LEFT)
		list:SetWide(UI.S(230))
		list:SetMultiSelect(false)
		list:SetHideHeaders(true)
		list:AddColumn("")
		if list.SetBackgroundColor then list:SetBackgroundColor(COL.LIST_BG) end

		local scroll = vgui.Create("DScrollPanel", body)
		scroll:Dock(FILL)
		scroll.Paint = function(_, w, h)
			surface.SetDrawColor(COL.BG)
			surface.DrawRect(0, 0, w, h)
		end

		local lines = {}
		for _, g in ipairs(sorted()) do
			local line = list:AddLine(T(g.title.en, g.title.ru))
			line.SPGuide = g.id
			lines[g.id] = line
		end
		list.OnRowSelected = function(_, _, line)
			local g = UI.Guides[line.SPGuide]
			if g then
				buildBlocks(scroll, g)
				scroll:GetVBar():SetScroll(0)
			end
		end
		win.SPShow = function(gid)
			local line = lines[gid] or lines[(sorted()[1] or {}).id]
			if IsValid(line) then list:ClearSelection() list:SelectItem(line) end
		end
	else
		Dock.ShowPage("guide")
	end
	win.SPShow(id)
	return win
end

-- a "?" button that opens the guide id (docked to the right of parent)
function UI.GuideButton(parent, id, dock)
	local b = UI.IconButton(parent, "icon16/help.png", L("guide_open"), function() UI.OpenGuide(id) end, nil, dock or RIGHT)
	return b
end
