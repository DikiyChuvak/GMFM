--[[
SPeditor — "How to use" (a0.6): short illustrated guides to the tools, inside the game.
Help → How to use… opens the window; a "?" button in a tool's window (UI.GuideButton) opens
the guide of that tool. Every guide says what the tool is for, the steps, what comes out, and
shows it: a screenshot (materials/speditor/help/*.jpg) or a live animated demonstration.

A guide (core files and SAeditor add their own):
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
  { "tip", en, ru }                       a hint in a box with a lamp
  { "see", "guide_id", en, ru }           a link to another guide (with a few words why)
  { "keys", { { "K", en, ru }, … }, w = px } a table of keys (or words) and what they do; w — the
                                          width of the left column (120 by default)
  { "img", path, en, ru, marks = { { x, y }, … } }
                                          numbered circles on the picture (x, y — 0..1 of its
                                          size); the steps after it are numbered the same
A guide may name its part of the list: section = "start" | "pose" | "look" | "anim" | "render"
| "help" (SECTION_OF below gives the older guides theirs).
  { "video", atlas = "speditor/help/video/x_%02d.jpg", count = frames, fps = 12, cols = 4,
    rows = 4, w = frame width, h = frame height, sound = "sound/…/x.ogg", en, ru }
                                          a rendered video: its frames packed cols x rows into
                                          pictures (the game plays no video files), its sound
                                          track beside it; shown in a player with a control bar
                                          and full screen.
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

-- every English text shown in a guide, for the translation template (SPeditor.LangTemplate)
UI.GuideTextsSeen = UI.GuideTextsSeen or {}

-- the text of a block in the editor's language; a language pack translates it by its
-- English text (SPeditor.AddLanguage{ texts = … })
local function T(en, ru)
	local lang = GetConVarString("speditor_language")
	if lang == "ru" and ru then return ru end
	if isstring(en) then
		UI.GuideTextsSeen[en] = true
		local pack = lang ~= "en" and SPeditor.LangText[lang]
		if pack and pack[en] then return pack[en] end
	end
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

-- a numbered circle on a picture
local function drawMark(x, y, n, r)
	draw.RoundedBox(r, x - r, y - r, r * 2, r * 2, Color(0, 0, 0, 200))
	draw.RoundedBox(r - 2, x - r + 2, y - r + 2, r * 2 - 4, r * 2 - 4, COL.ORANGE)
	draw.SimpleTextOutlined(tostring(n), "SPeditor.Bold", x, y, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 200))
end

local function imageBlock(parent, path, caption, marks)
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
		for i, m in ipairs(marks or {}) do drawMark(x + m[1] * dw, m[2] * dh, i, UI.S(9)) end
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
			for i, m in ipairs(marks or {}) do drawMark((w - dw) / 2 + m[1] * dw, (h - dh) / 2 + m[2] * dh, i, UI.S(12)) end
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

-- A rendered video inside a guide (see the top of the file), in a player like any video
-- player: play / pause, stop, 5 s back / forward, a seek bar with the time, volume, repeat
-- and full screen. A click on the picture pauses, a double click opens full screen.
-- The sound follows the picture and stops with the window.
local vicons = {}
local function vicon(name)
	vicons[name] = vicons[name] or Material("icon16/" .. name .. ".png")
	return vicons[name]
end

local function vclock(s)
	s = math.max(s or 0, 0)
	return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60))
end

local function videoState(b)
	local st = { b = b, t = 0, playing = true, loop = true, vol = 1, mute = false, len = b.count / b.fps,
		cols = b.cols or 4, rows = b.rows or 4, fw = b.w or 480, fh = b.h or 270 }
	st.per = st.cols * st.rows
	function st:Seek(t)
		self.t = math.Clamp(t, 0, self.len - 0.001)
		if IsValid(self.ch) then self.ch:SetTime(math.min(self.t, self.ch:GetLength())) end
	end
	function st:Toggle()
		if not self.playing and self.t >= self.len - 0.01 then self:Seek(0) end
		self.playing = not self.playing
	end
	function st:Stop()
		self.playing = false
		self:Seek(0)
	end
	return st
end

-- the frame at the time of st inside x, y, w, h (letterboxed)
local function drawVideoFrame(st, x, y, w, h)
	surface.SetDrawColor(0, 0, 0, 255)
	surface.DrawRect(x, y, w, h)
	local k = math.min(w / st.fw, h / st.fh)
	local dw, dh = math.floor(st.fw * k), math.floor(st.fh * k)
	local dx, dy = x + math.floor((w - dw) / 2), y + math.floor((h - dh) / 2)
	local f = math.min(math.floor(st.t * st.b.fps), st.b.count - 1)
	local mat = helpMat(string.format(st.b.atlas, math.floor(f / st.per) + 1))
	if mat then
		local i = f % st.per
		local cx, cy = i % st.cols, math.floor(i / st.cols)
		surface.SetDrawColor(255, 255, 255, 255)
		surface.SetMaterial(mat)
		surface.DrawTexturedRectUV(dx, dy, dw, dh, cx / st.cols, cy / st.rows, (cx + 1) / st.cols, (cy + 1) / st.rows)
	end
end

-- The player panel: the picture and the control bar under it. Both the guide and the full
-- screen view use it; they share st, so the full screen goes on where the guide was.
local function videoPlayer(parent, st, full)
	local p = vgui.Create("DPanel", parent)
	p:SetCursor("hand")
	local btns = {}
	p.BarH = function() return UI.S(full and 34 or 28) end
	p.Paint = function(s, w, h)
		btns = {}
		local bh = s:BarH()
		local mx, my = s:CursorPos()
		local inside = mx >= 0 and my >= 0 and mx < w and my < h
		drawVideoFrame(st, 0, 0, w, h - bh)
		if not st.playing then
			-- the big play button over a paused picture
			local cx, cy, r = w / 2, (h - bh) / 2, UI.S(26)
			draw.RoundedBox(r, cx - r, cy - r, r * 2, r * 2, Color(0, 0, 0, 170))
			draw.NoTexture()
			surface.SetDrawColor(255, 255, 255, 235)
			local a = r * 0.45
			surface.DrawPoly({ { x = cx - a * 0.7, y = cy - a }, { x = cx + a, y = cy }, { x = cx - a * 0.7, y = cy + a } })
		end

		-- the bar
		local by = h - bh
		surface.SetDrawColor(18, 20, 24, 255)
		surface.DrawRect(0, by, w, bh)
		surface.SetDrawColor(70, 76, 88, 255)
		surface.DrawRect(0, by, w, 1)
		local cy = by + math.floor(bh / 2)
		local isz = UI.IconSize and UI.IconSize(bh) or 16
		local x = UI.S(4)
		local function button(name, fn, tip, on)
			local bw = bh
			local hot = inside and mx >= x and mx < x + bw and my >= by
			if hot or on then
				surface.SetDrawColor(on and Color(60, 120, 200, hot and 200 or 140) or Color(90, 110, 140, 120))
				surface.DrawRect(x + 2, by + 3, bw - 4, bh - 6)
			end
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(vicon(name))
			surface.DrawTexturedRect(x + math.floor((bw - isz) / 2), cy - math.floor(isz / 2), isz, isz)
			btns[#btns + 1] = { x0 = x, x1 = x + bw, fn = fn, tip = tip, hot = hot }
			x = x + bw
		end
		button(st.playing and "control_pause_blue" or "control_play_blue", function() st:Toggle() end, L(st.playing and "guide_v_pause" or "guide_v_play"))
		button("control_stop_blue", function() st:Stop() end, L("guide_v_stop"))
		button("control_rewind_blue", function() st:Seek(st.t - 5) end, L("guide_v_back"))
		button("control_fastforward_blue", function() st:Seek(st.t + 5) end, L("guide_v_fwd"))
		x = x + UI.S(6)
		surface.SetFont("SPeditor.Small")
		local tt = vclock(st.t) .. " / " .. vclock(st.len)
		local tw = surface.GetTextSize(vclock(st.len) .. " / " .. vclock(st.len))
		draw.SimpleText(tt, "SPeditor.Small", x, cy, Color(225, 230, 240), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		x = x + tw + UI.S(10)

		-- the right side, from the right edge: full screen, repeat, volume
		local rx = w - UI.S(4)
		local function rbutton(name, fn, tip, on)
			rx = rx - bh
			local save = x
			x = rx
			button(name, fn, tip, on)
			x = save
		end
		rbutton(full and "arrow_in" or "arrow_out", function()
			if full then s.CloseFull() else s.OpenFull() end
		end, L(full and "guide_v_unfull" or "guide_v_full"))
		rbutton("arrow_refresh", function() st.loop = not st.loop end, L("guide_v_loop"), st.loop)
		local vw = UI.S(60)
		rx = rx - vw - UI.S(6)
		local vol = st.mute and 0 or st.vol
		surface.SetDrawColor(60, 64, 74, 255)
		surface.DrawRect(rx, cy - 2, vw, 4)
		surface.SetDrawColor(60, 140, 230, 255)
		surface.DrawRect(rx, cy - 2, vw * vol, 4)
		draw.RoundedBox(4, rx + vw * vol - 4, cy - 4, 8, 8, Color(220, 235, 255))
		s.volArea = { x0 = rx, x1 = rx + vw, y0 = by, y1 = h }
		rx = rx - UI.S(4)
		rbutton(vol <= 0 and "sound_mute" or (vol < 0.5 and "sound_low" or "sound"), function() st.mute = not st.mute end, L("guide_v_mute"))

		-- the seek bar fills the middle
		local sx0, sx1 = x, rx - UI.S(10)
		if sx1 > sx0 + 20 then
			local hotSeek = s.dragSeek or (inside and my >= by and mx >= sx0 - 4 and mx <= sx1 + 4)
			local th = hotSeek and 6 or 4
			local u = st.t / st.len
			surface.SetDrawColor(60, 64, 74, 255)
			surface.DrawRect(sx0, cy - th / 2, sx1 - sx0, th)
			surface.SetDrawColor(60, 140, 230, 255)
			surface.DrawRect(sx0, cy - th / 2, (sx1 - sx0) * u, th)
			draw.RoundedBox(5, sx0 + (sx1 - sx0) * u - 5, cy - 5, 10, 10, Color(220, 235, 255))
			if hotSeek then
				local ht = math.Clamp((mx - sx0) / (sx1 - sx0), 0, 1) * st.len
				draw.SimpleTextOutlined(vclock(ht), "SPeditor.Small", math.Clamp(mx, sx0, sx1), by - 4, Color(255, 255, 255), TEXT_ALIGN_CENTER,
					TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 220))
			end
		end
		s.seekArea = { x0 = sx0, x1 = sx1, y0 = by, y1 = h }
		for _, bt in ipairs(btns) do
			if bt.hot and bt.tip then
				draw.SimpleTextOutlined(bt.tip, "SPeditor.Small", (bt.x0 + bt.x1) / 2, by - 4, Color(255, 255, 255), TEXT_ALIGN_CENTER,
					TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 220))
			end
		end
		surface.SetDrawColor(COL.BORDER)
		surface.DrawOutlinedRect(0, 0, w, h)
	end
	local function seekTo(s, mx)
		local a = s.seekArea
		if a and a.x1 > a.x0 then st:Seek(math.Clamp((mx - a.x0) / (a.x1 - a.x0), 0, 1) * st.len) end
	end
	local function volTo(s, mx)
		local a = s.volArea
		if a then
			st.vol = math.Clamp((mx - a.x0) / (a.x1 - a.x0), 0, 1)
			st.mute = false
		end
	end
	p.OnMousePressed = function(s, code)
		if code ~= MOUSE_LEFT then return end
		local mx, my = s:CursorPos()
		if my < s:GetTall() - s:BarH() then
			-- a double click on the picture: full screen
			if RealTime() - (s.lastClick or 0) < 0.3 then
				s.lastClick = 0
				st:Toggle()            -- the first click of the pair paused it
				if full then s.CloseFull() else s.OpenFull() end
				return
			end
			s.lastClick = RealTime()
			st:Toggle()
			return
		end
		for _, bt in ipairs(btns) do
			if mx >= bt.x0 and mx < bt.x1 then bt.fn() return end
		end
		local a, v = s.seekArea, s.volArea
		if a and mx >= a.x0 - 4 and mx <= a.x1 + 4 then
			s.dragSeek = true
			s:MouseCapture(true)
			seekTo(s, mx)
		elseif v and mx >= v.x0 - 4 and mx <= v.x1 + 4 then
			s.dragVol = true
			s:MouseCapture(true)
			volTo(s, mx)
		end
	end
	p.OnMouseReleased = function(s)
		s.dragSeek, s.dragVol = nil, nil
		s:MouseCapture(false)
	end
	p.Think = function(s)
		if not s.dragSeek and not s.dragVol then return end
		if not input.IsMouseDown(MOUSE_LEFT) then s:OnMouseReleased() return end
		local mx = s:CursorPos()
		if s.dragSeek then seekTo(s, mx) else volTo(s, mx) end
	end
	return p
end

local function videoBlock(parent, b)
	local st = videoState(b)
	local holder = vgui.Create("DPanel", parent)
	holder:Dock(TOP)
	holder:DockMargin(10, 6, 10, 2)
	holder.Paint = function() end
	local p = videoPlayer(holder, st, false)
	p:Dock(FILL)
	holder.PerformLayout = function(s, w)
		local dw = math.min(w, st.fw * 1.25)
		local dh = math.floor(dw * st.fh / st.fw) + p:BarH()
		if s:GetTall() ~= dh then s:SetTall(dh) end
		local side = math.floor((w - dw) / 2)
		s:DockPadding(side, 0, side, 0)
	end

	-- full screen: the same player over the whole screen; Esc or the button closes it
	local fullPanel
	local function closeFull()
		if IsValid(fullPanel) then fullPanel:Remove() end
		fullPanel = nil
	end
	local function openFull()
		closeFull()
		local f = vgui.Create("DPanel")
		f:SetSize(ScrW(), ScrH())
		f:MakePopup()
		f:SetKeyboardInputEnabled(true)
		f.Paint = function(_, w, h)
			surface.SetDrawColor(0, 0, 0, 255)
			surface.DrawRect(0, 0, w, h)
		end
		f.OnKeyCodePressed = function(_, key)
			if key == KEY_ESCAPE then closeFull()
			elseif key == KEY_SPACE then st:Toggle()
			elseif key == KEY_LEFT then st:Seek(st.t - 5)
			elseif key == KEY_RIGHT then st:Seek(st.t + 5) end
		end
		local fp = videoPlayer(f, st, true)
		fp:Dock(FILL)
		fp.OpenFull, fp.CloseFull = openFull, closeFull
		fullPanel = f
		-- Esc also opens the game menu: close the player instead
		SPeditor.Hook("OnPauseMenuShow", f, function()
			if IsValid(fullPanel) then
				closeFull()
				return false
			end
		end)
	end
	p.OpenFull, p.CloseFull = openFull, closeFull

	if b.sound then
		sound.PlayFile(b.sound, "noplay noblock", function(c)
			if not IsValid(holder) then
				if IsValid(c) then c:Stop() end
				return
			end
			st.ch = c
		end)
	end
	local function syncSound(on)
		local ch = st.ch
		if not IsValid(ch) then return end
		ch:SetVolume(st.mute and 0 or st.vol)
		if not on or not st.playing or st.t >= ch:GetLength() then
			if ch:GetState() == GMOD_CHANNEL_PLAYING then ch:Pause() end
			return
		end
		if ch:GetState() ~= GMOD_CHANNEL_PLAYING then
			ch:SetTime(st.t)
			ch:Play()
		elseif math.abs(ch:GetTime() - st.t) > 0.15 then
			ch:SetTime(st.t)
		end
	end
	holder.OnRemove = function()
		if IsValid(st.ch) then st.ch:Stop() end
		closeFull()
	end
	-- a hook, not the panel's Think: a hidden window gets no Think, and its sound must stop
	local function shown()
		if IsValid(fullPanel) then return true end
		local q = holder
		while IsValid(q) do
			if not q:IsVisible() then return false end
			q = q:GetParent()
		end
		return SPeditor.Client.active
	end
	local last = RealTime()
	SPeditor.Hook("Think", holder, function()
		local now = RealTime()
		local on = shown()
		if st.playing and on then
			st.t = st.t + now - last
			if st.t >= st.len then
				if st.loop then
					st.t = st.t % st.len
				else
					st.t = st.len - 0.001
					st.playing = false
				end
			end
		end
		last = now
		syncSound(on)
	end)
	local cap = T(b[2], b[3])
	if cap ~= "" then textBlock(parent, cap, "SPeditor.Small", COL.DIM) end
end

-- the parts of the guide list (a0.8): a guide names its own (g.section) or gets one here
local SECTIONS = {
	{ id = "start",  en = "Getting started",           ru = "С чего начать" },
	{ id = "pose",   en = "Objects and posing",        ru = "Объекты и позы" },
	{ id = "look",   en = "Light and cameras",         ru = "Свет и камеры" },
	{ id = "anim",   en = "Animation",                 ru = "Анимация" },
	{ id = "render", en = "Render: pictures and video", ru = "Рендер: картинки и видео" },
	{ id = "help",   en = "Problems and settings",     ru = "Проблемы и настройки" },
}
local SECTION_OF = {
	interface = "start", start = "start", first_anim = "start", examples = "start", adopt = "start",
	posing = "pose", select = "pose", attach = "pose", wear = "pose", pac3 = "pose", props = "pose",
	lights = "look", camera = "look",
	sa_keys = "anim", sa_curves = "anim", sa_motion = "anim", sa_bones = "anim", sa_rec = "anim", sa_cuts = "anim",
	sa_face = "anim", sa_import = "anim", sa_proc = "anim", sa_smh = "anim",
	render = "render", sa_render = "render",
	faq = "help", own_sounds = "help",
}
local function sectionOf(g)
	local sec = g.section or SECTION_OF[g.id]
	for _, s in ipairs(SECTIONS) do if s.id == sec then return sec end end
	return "help"
end

-- the guides in the order of the list: by section, then by their order
local function listed()
	local out = {}
	local all = sorted()
	for _, sec in ipairs(SECTIONS) do
		for _, g in ipairs(all) do
			if sectionOf(g) == sec.id then out[#out + 1] = g end
		end
	end
	return out
end

-- lower case for the search, Cyrillic too (string.lower knows only Latin letters)
local function lowerU(str)
	str = string.lower(str or "")
	str = string.gsub(str, "\208([\144-\159])", function(c) return "\208" .. string.char(string.byte(c) + 32) end)
	str = string.gsub(str, "\208([\160-\175])", function(c) return "\209" .. string.char(string.byte(c) - 32) end)
	return (string.gsub(str, "\208\129", "\209\145"))
end

-- every word of a guide in the editor's language (for the search)
local searchText = {}
local function textOf(g)
	local lang = GetConVarString("speditor_language")
	local key = g.id .. "|" .. lang
	if searchText[key] then return searchText[key] end
	local parts = { T(g.title.en, g.title.ru) }
	for _, b in ipairs(g.blocks or {}) do
		if b[1] == "steps" then
			local list = T(b.en, b.ru)
			for _, st in ipairs(istable(list) and list or {}) do parts[#parts + 1] = (list == b.en) and T(st) or st end
		elseif b[1] == "keys" then
			for _, k in ipairs(b[2] or {}) do parts[#parts + 1] = k[1] .. " " .. (k[4] or "") .. " " .. T(k[2], k[3]) end
		elseif b[1] == "img" or b[1] == "see" then
			parts[#parts + 1] = T(b[3], b[4])
		elseif isstring(b[2]) then
			parts[#parts + 1] = T(b[2], b[3])
		end
	end
	searchText[key] = lowerU(table.concat(parts, "\n"))
	return searchText[key]
end

-- a box with a coloured edge (result, tip)
local function boxBlock(parent, text, edge, label)
	local holder = vgui.Create("DPanel", parent)
	holder:Dock(TOP)
	holder:DockMargin(10, 6, 10, 4)
	holder:DockPadding(10, 4, 6, 4)
	holder.Paint = function(_, w, h)
		surface.SetDrawColor(COL.ROW_B)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(edge)
		surface.DrawRect(0, 0, 3, h)
	end
	local l = textBlock(holder, label .. "  " .. text)
	l:DockMargin(0, 0, 0, 0)
	holder.PerformLayout = function(s) s:SizeToChildren(false, true) end
	return holder
end

-- a line of text that works as a link
local function linkLine(parent, text, fn, indent)
	local b = vgui.Create("DButton", parent)
	b:Dock(TOP)
	b:DockMargin(indent or 18, 1, 10, 1)
	b:SetTall(UI.S(18))
	b:SetText("")
	b:SetCursor("hand")
	b.Paint = function(s, w, h)
		local col = s:IsHovered() and COL.ORANGE or COL.BLUE
		draw.SimpleText(text, "SPeditor.Small", 0, h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if s:IsHovered() then
			surface.SetFont("SPeditor.Small")
			local tw = surface.GetTextSize(text)
			surface.SetDrawColor(col)
			surface.DrawRect(0, h - 3, tw, 1)
		end
	end
	b.DoClick = fn
	return b
end

-- rows of "key — what it does" (or "word — what it means"); the text of a row wraps
local function keysBlock(parent, list, keyW)
	local box = vgui.Create("DPanel", parent)
	box:Dock(TOP)
	box:DockMargin(10, 4, 10, 4)
	box.Paint = function() end
	local kw = UI.S(keyW or 120)
	for i, k in ipairs(list) do
		local row = vgui.Create("DPanel", box)
		row:Dock(TOP)
		row:DockPadding(kw + 8, 2, 6, 2)
		local key = k[4] and T(k[1], k[4]) or k[1]     -- k[4]: the Russian name of a word
		row.Paint = function(_, w, h)
			surface.SetDrawColor(i % 2 == 0 and COL.ROW_A or COL.ROW_B)
			surface.DrawRect(0, 0, w, h)
			surface.SetFont("SPeditor.Bold")
			local tw, th = surface.GetTextSize(key)
			draw.RoundedBox(3, 6, 2, math.min(tw + 10, kw), th + 2, COL.CTRL)
			draw.SimpleText(key, "SPeditor.Bold", 11, 3, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		end
		local l = vgui.Create("DLabel", row)
		l:Dock(TOP)
		l:SetFont("SPeditor.Small")
		l:SetTextColor(COL.TEXT)
		l:SetWrap(true)
		l:SetAutoStretchVertical(true)
		l:SetText(T(k[2], k[3]))
		row.PerformLayout = function(s) s:SizeToChildren(false, true) end
	end
	box.PerformLayout = function(s) s:SizeToChildren(false, true) end
end

-- nav = { open = function(id), prev = guide, next = guide }
local function buildBlocks(scroll, g, nav)
	scroll:Clear()
	textBlock(scroll, T(g.title.en, g.title.ru), "SPeditor.Time", COL.TEXT)
	-- "In this guide": the headings, each a jump to its place
	local heads = {}
	for _, b in ipairs(g.blocks or {}) do
		if b[1] == "h" then heads[#heads + 1] = b end
	end
	local headPanels = {}
	-- after the first paragraph (the introduction), or at the very top
	local tocDone = #heads < 2
	local function toc()
		tocDone = true
		local l = textBlock(scroll, L("guide_toc"), "SPeditor.Small", COL.DIM)
		l:DockMargin(10, 6, 10, 0)
		for _, b in ipairs(heads) do
			linkLine(scroll, "•  " .. T(b[2], b[3]), function()
				local pnl = headPanels[b]
				if IsValid(pnl) then scroll:ScrollToChild(pnl) end
			end)
		end
	end
	if not tocDone and (g.blocks[1] or {})[1] ~= "p" then toc() end
	for i, b in ipairs(g.blocks or {}) do
		local kind = b[1]
		if i == 2 and not tocDone then toc() end
		if kind == "p" then
			textBlock(scroll, T(b[2], b[3]))
		elseif kind == "h" then
			local l = textBlock(scroll, T(b[2], b[3]), "SPeditor.Bold", COL.ORANGE)
			l:DockMargin(10, 12, 10, 2)
			headPanels[b] = l
		elseif kind == "steps" then
			local list = T(b.en, b.ru)
			for i, s in ipairs(istable(list) and list or {}) do
				-- a language pack translates the English steps one by one
				textBlock(scroll, i .. ".  " .. (list == b.en and T(s) or s), "SPeditor.Small", COL.TEXT, 18)
			end
		elseif kind == "img" then
			imageBlock(scroll, b[2], T(b[3], b[4]), b.marks)
		elseif kind == "result" then
			boxBlock(scroll, T(b[2], b[3]), COL.ORANGE, L("guide_result"))
		elseif kind == "tip" then
			boxBlock(scroll, T(b[2], b[3]), COL.BLUE, L("guide_tip"))
		elseif kind == "keys" then
			keysBlock(scroll, b[2] or {}, b.w)
		elseif kind == "see" then
			local other = UI.Guides[b[2]]
			if other then
				local why = T(b[3], b[4])
				linkLine(scroll, "→  " .. T(other.title.en, other.title.ru) .. (why ~= "" and ("  —  " .. why) or ""),
					function() if nav and nav.open then nav.open(other.id) else UI.OpenGuide(other.id) end end, 10)
			end
		elseif kind == "demo" then
			demoBlock(scroll, b)
		elseif kind == "video" then
			videoBlock(scroll, b)
		elseif kind == "try" then
			local btn = UI.Button(scroll, T(b[2], b[3]), "icon16/arrow_right.png", function()
				local ok, err = pcall(b.fn)
				if not ok then ErrorNoHalt("[SPeditor] guide: " .. tostring(err) .. "\n") end
			end, 24)
			btn:DockMargin(10, 6, 10, 2)
		end
	end
	-- previous / next guide
	if nav and (nav.prev or nav.next) then
		local bar = vgui.Create("DPanel", scroll)
		bar:Dock(TOP)
		bar:DockMargin(10, 14, 10, 0)
		bar:SetTall(UI.S(26))
		bar.Paint = function(_, w, h)
			surface.SetDrawColor(COL.BORDER)
			surface.DrawRect(0, 0, w, 1)
		end
		local function navButton(gd, dock, prefix, suffix)
			local b = vgui.Create("DButton", bar)
			b:Dock(dock)
			b:DockMargin(0, 4, 0, 0)
			b:SetText(prefix .. T(gd.title.en, gd.title.ru) .. suffix)
			b:SetFont("SPeditor.Small")
			b:SizeToContentsX(UI.S(16))
			UI.StyleButton(b, nil, 3)
			b.DoClick = function() nav.open(gd.id) end
		end
		if nav.prev then navButton(nav.prev, LEFT, "←  ", "") end
		if nav.next then navButton(nav.next, RIGHT, "", "  →") end
	end
	local pad = vgui.Create("DPanel", scroll)
	pad:Dock(TOP)
	pad:SetTall(UI.S(16))
	pad.Paint = function() end
end

---------------------------------------------------------------------
-- The window: the list of guides by section with a search on the left, the guide on the right
---------------------------------------------------------------------
function UI.OpenGuide(id)
	local win = Dock.ByKey("guide")
	if not IsValid(win) then
		local W, H = math.min(UI.S(1040), ScrW() - 80), math.min(UI.S(760), ScrH() - 120)
		local body
		win, body = Dock.Create({ key = "guide", id = "guide", title = L("guide_title"), w = W, h = H,
				x = math.floor(ScrW() / 2 - W / 2), y = 70, dockable = false, icon = "icon16/help.png" })
		win.minW, win.minH = UI.S(560), UI.S(340)
		local baseRemove = win.OnRemove
		win.OnRemove = function(s)
			if baseRemove then baseRemove(s) end
			Dock.pages.guide = nil
		end

		local side = vgui.Create("DPanel", body)
		side:Dock(LEFT)
		side:SetWide(UI.S(290))
		side.Paint = function(_, w, h)
			surface.SetDrawColor(COL.LIST_BG or COL.BG)
			surface.DrawRect(0, 0, w, h)
			surface.SetDrawColor(COL.BORDER)
			surface.DrawRect(w - 1, 0, 1, h)
		end
		local search = vgui.Create("DTextEntry", side)
		search:Dock(TOP)
		search:DockMargin(6, 6, 7, 4)
		search:SetTall(UI.S(22))
		search:SetFont("SPeditor.Small")
		search:SetPlaceholderText(L("guide_search"))
		search:SetUpdateOnType(true)
		local list = vgui.Create("DScrollPanel", side)
		list:Dock(FILL)

		local scroll = vgui.Create("DScrollPanel", body)
		scroll:Dock(FILL)
		scroll.Paint = function(_, w, h)
			surface.SetDrawColor(COL.BG)
			surface.DrawRect(0, 0, w, h)
		end

		local current
		local rowOf = {}
		local function show(gid)
			local order = listed()
			local g, idx
			for i, x in ipairs(order) do
				if x.id == gid then g, idx = x, i end
			end
			g, idx = g or order[1], idx or 1
			if not g then return end
			current = g.id
			buildBlocks(scroll, g, { open = show, prev = order[idx - 1], next = order[idx + 1] })
			scroll:GetVBar():SetScroll(0)
			-- the guide's line in the list in sight (after the list has its layout)
			timer.Simple(0, function()
				local row = rowOf[g.id]
				if IsValid(row) and IsValid(list) then list:ScrollToChild(row) end
			end)
		end

		local function fill(query)
			list:Clear()
			rowOf = {}
			query = lowerU(string.Trim(query or ""))
			local any = false
			for _, sec in ipairs(SECTIONS) do
				local rows = {}
				for _, g in ipairs(listed()) do
					if sectionOf(g) == sec.id and (query == "" or string.find(textOf(g), query, 1, true)) then rows[#rows + 1] = g end
				end
				if #rows > 0 then
					any = true
					local hdr = list:Add("DLabel")
					hdr:Dock(TOP)
					hdr:DockMargin(8, 8, 6, 2)
					hdr:SetFont("SPeditor.Bold")
					hdr:SetTextColor(COL.ORANGE)
					hdr:SetText(T(sec.en, sec.ru))
					hdr:SizeToContentsY()
					for _, g in ipairs(rows) do
						local b = list:Add("DButton")
						b:Dock(TOP)
						b:DockMargin(4, 0, 4, 0)
						b:SetTall(UI.S(22))
						b:SetText("")
						local title = T(g.title.en, g.title.ru)
						local icon = g.icon and Material(g.icon) or nil
						b:SetTooltip(title)
						b.Paint = function(s, w, h)
							if current == g.id then
								surface.SetDrawColor(COL.SEL)
								surface.DrawRect(0, 0, w, h)
							elseif s:IsHovered() then
								surface.SetDrawColor(COL.HOVER)
								surface.DrawRect(0, 0, w, h)
							end
							local x = 6
							if icon and not icon:IsError() then
								local is = UI.IconSize and UI.IconSize(h) or 16
								surface.SetDrawColor(255, 255, 255, 255)
								surface.SetMaterial(icon)
								surface.DrawTexturedRect(x, (h - is) / 2, is, is)
								x = x + is + 6
							else
								x = x + 22
							end
							draw.SimpleText(title, "SPeditor.Small", x, h / 2, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
						end
						b.DoClick = function() show(g.id) end
						rowOf[g.id] = b
					end
				end
			end
			if not any then
				local l = list:Add("DLabel")
				l:Dock(TOP)
				l:DockMargin(8, 8, 6, 2)
				l:SetFont("SPeditor.Small")
				l:SetTextColor(COL.DIM)
				l:SetWrap(true)
				l:SetAutoStretchVertical(true)
				l:SetText(L("guide_nothing"))
			end
		end
		search.OnValueChange = function(_, v) fill(v) end
		fill("")
		win.SPShow = function(gid) show(gid) end
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
