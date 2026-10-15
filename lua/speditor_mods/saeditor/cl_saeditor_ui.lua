--[[
SAeditor — interface: the Timeline page in the editor's bottom window (where SFM has
the timeline), the "Import model animation" and "Render animation" windows, menu items.

Timeline: names of animated objects on the left, the frame ruler and keys on the right;
below the objects — the sounds: one row per file and source, a bar for every time it plays.
  LMB on the ruler or empty space — move the playhead (can be dragged);
  LMB on a key — select it, drag — move it (with Ctrl — copy it);
  RMB on a key — the key menu, RMB on a row — set or paste a key;
  LMB on a sound bar — drag the sound along the timeline, on its edge — trim it, RMB — the sound menu;
  wheel — scroll the object list.
]]
local MOD  = SPeditor.Mod("saeditor")
local SA   = MOD.SA
local C    = SPeditor.Client
local UI   = SPeditor.UI
local Dock = SPeditor.Dock
local L    = SPeditor.L
local COL  = UI.PAL

local NAME_W, RULER_H, ROW_H, PAD = 170, 20, 18, 10
local TICKS = { 1, 2, 5, 10, 20, 25, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000 }

local function round(v) return math.floor(v + 0.5) end

---------------------------------------------------------------------
-- Timeline page
---------------------------------------------------------------------
local function buildTimeline(page)
	local bar = vgui.Create("DPanel", page)
	bar:Dock(TOP)
	bar:SetTall(28)
	bar.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
	end

	local function sep()
		local s = vgui.Create("DPanel", bar)
		s:Dock(LEFT)
		s:DockMargin(6, 6, 4, 6)
		s:SetWide(1)
		s.Paint = function(_, _, h) surface.SetDrawColor(COL.BORDER) surface.DrawRect(0, 0, 1, h) end
	end
	local function label(text, wide)
		local l = vgui.Create("DLabel", bar)
		l:Dock(LEFT)
		l:DockMargin(6, 0, 2, 0)
		l:SetFont("SPeditor.Small")
		l:SetTextColor(COL.DIM)
		l:SetText(text)
		surface.SetFont("SPeditor.Small")
		l:SetWide(wide or (select(1, surface.GetTextSize(text)) + 2))
		return l
	end
	local function entry(wide, get, set)
		local e = vgui.Create("DTextEntry", bar)
		e:Dock(LEFT)
		e:DockMargin(2, 4, 2, 4)
		e:SetWide(wide)
		e:SetFont("SPeditor.Small")
		e:SetNumeric(true)
		e.OnEnter = function(s)
			local v = tonumber(s:GetValue())
			if v then set(v) end
			s:KillFocus()
		end
		e.Think = function(s)
			if s:HasFocus() then return end
			local text = tostring(get())
			if s.SPText ~= text then
				s.SPText = text
				s:SetText(text)
			end
		end
		return e
	end
	local function selectedUIDs()
		local set, n = {}, 0
		for _, e in ipairs(C.SelectionList()) do
			local uid = SA.UID(e)
			if SA.tracks[uid] then set[uid] = true n = n + 1 end
			local fid = SA.FaceTrack(uid)
			if SA.tracks[fid] then set[fid] = true n = n + 1 end
		end
		return n > 0 and set or nil
	end

	UI.IconButton(bar, "icon16/control_start_blue.png", L("sa_first"), function() SA.Seek(0) end)
	UI.IconButton(bar, "icon16/control_rewind_blue.png", L("sa_prev_key"), function()
		local f = SA.NeighbourKey(-1, selectedUIDs())
		if f then SA.Seek(f) end
	end)
	local play = UI.IconButton(bar, "icon16/control_play_blue.png", L("sa_play"), function() SA.Play() end, function() return SA.playing end)
	play.Think = function(s)
		local icon = SA.playing and "icon16/control_pause_blue.png" or "icon16/control_play_blue.png"
		if s.SPIcon ~= icon then
			s.SPIcon = icon
			s:SetIcon(icon)
		end
	end
	UI.IconButton(bar, "icon16/control_fastforward_blue.png", L("sa_next_key"), function()
		local f = SA.NeighbourKey(1, selectedUIDs())
		if f then SA.Seek(f) end
	end)
	UI.IconButton(bar, "icon16/control_end_blue.png", L("sa_last"), function() SA.Seek(SA.frames) end)
	UI.IconButton(bar, "icon16/arrow_refresh.png", L("sa_loop"), function() SA.SetConfig(nil, nil, not SA.loop) end, function() return SA.loop end)
	sep()

	label(L("sa_frame"))
	entry(46, function() return round(SA.frame) end, function(v) SA.Seek(round(v)) end)
	local total = label("", 86)
	total.Think = function(s)
		local text = string.format("/ %d   %.2f s", SA.frames, SA.frame / SA.fps)
		if s.SPText ~= text then
			s.SPText = text
			s:SetText(text)
		end
	end
	label(L("sa_fps"))
	local fps = UI.StyleCombo(vgui.Create("DComboBox", bar))
	fps:Dock(LEFT)
	fps:DockMargin(2, 4, 2, 4)
	fps:SetWide(52)
	for _, v in ipairs(SA.FPS_LIST) do fps:AddChoice(tostring(v), v) end
	fps.OnSelect = function(_, _, _, v)
		-- the duration in seconds is kept: the number of frames is recalculated
		local seconds = SA.frames / SA.fps
		SA.SetConfig(v, math.max(round(seconds * v), 1))
	end
	fps.Think = function(s)
		if s:IsMenuOpen() then return end
		local text = tostring(SA.fps)
		if s.SPText ~= text then
			s.SPText = text
			s:SetText(text)
		end
	end
	label(L("sa_length"))
	entry(46, function() return math.Round(SA.frames / SA.fps, 2) end, function(v)
		SA.SetConfig(nil, math.max(round(math.Clamp(v, 0.1, 3600) * SA.fps), 1))
	end)
	sep()

	UI.IconButton(bar, "icon16/key_add.png", L("sa_key"), function() SA.SetKey() end)
	UI.IconButton(bar, "icon16/emoticon_smile.png", L("sa_face_key"), function() SA.SetFaceKey() end)
	UI.IconButton(bar, "icon16/key_go.png", L("sa_key_all"), function() SA.SetKey(C.Objects()) end)
	UI.IconButton(bar, "icon16/key_delete.png", L("sa_key_delete"), function()
		local k = SA.selKey
		if k and SA.HasKey(k.uid, k.f) then
			SA.DeleteKey(k.uid, k.f)
			return
		end
		-- no key is selected: the key of the selected object at the current frame is deleted
		local uid, f = SA.UID(C.selected), round(SA.frame)
		if SA.HasKey(uid, f) then SA.DeleteKey(uid, f) end
	end)
	UI.IconButton(bar, "icon16/bullet_red.png", L("sa_autokey"), function() SA.autokey = not SA.autokey end, function() return SA.autokey end)
	sep()
	UI.IconButton(bar, "icon16/film_add.png", L("sa_import"), function() SA.OpenImport(C.selected) end)
	UI.IconButton(bar, "icon16/sound_add.png", L("sa_snd_add"), function() SA.OpenSounds() end)
	UI.IconButton(bar, "icon16/film_save.png", L("sa_render"), function() SA.OpenRender() end)
	UI.IconButton(bar, "icon16/chart_curve.png", L("sa_crv_title"), function() SA.OpenCurves() end)
	UI.IconButton(bar, "icon16/heart.png", L("sa_proc_title"), function() SA.OpenProc(C.selected) end)
	UI.IconButton(bar, "icon16/arrow_switch.png", L("sa_smh_title"), function() SA.OpenSMH() end)

	-----------------------------------------------------------------
	-- Tracks
	-----------------------------------------------------------------
	local tl = vgui.Create("DPanel", page)
	tl:Dock(FILL)
	tl:SetMouseInputEnabled(true)
	local rows, rowsAt = {}, 0
	local scroll = 0
	local drag            -- { kind = "scrub" } | { kind = "key", uid, from, to, moved }

	local function buildRows()
		rows = {}
		local seen = {}
		for _, obj in ipairs(C.BuildEntityList()) do
			local uid = SA.UID(obj.ent)
			if SA.tracks[uid] then
				rows[#rows + 1] = { uid = uid, ent = obj.ent, name = obj.name, keys = SA.tracks[uid] }
				seen[uid] = true
			end
			-- the face track goes right under its object
			local fid = SA.FaceTrack(uid)
			if uid ~= 0 and SA.tracks[fid] then
				if not seen[uid] then
					rows[#rows + 1] = { uid = uid, ent = obj.ent, name = obj.name, keys = {} }
					seen[uid] = true
				end
				rows[#rows + 1] = { uid = fid, owner = uid, face = true, ent = obj.ent, name = L("sa_face_row"), keys = SA.tracks[fid] }
			end
		end
		-- selected objects without keys get a row too: a key can be set here
		for _, e in ipairs(C.SelectionList()) do
			local uid = SA.UID(e)
			if uid ~= 0 and not seen[uid] then
				rows[#rows + 1] = { uid = uid, ent = e, name = C.DisplayName(e), keys = {} }
				seen[uid] = true
			end
		end
		-- sounds: the same file from the same source shares a row (a burst of shots is one row)
		local lanes = {}
		for _, c in ipairs(SA.sounds or {}) do
			local key = c.path .. "|" .. c.uid .. "|" .. tostring(c.voice)
			local row = lanes[key]
			if not row then
				row = { sounds = {}, uid = -c.id, name = string.StripExtension(string.GetFileFromFilename(c.path) or c.path), keys = {} }
				lanes[key] = row
				rows[#rows + 1] = row
			end
			row.sounds[#row.sounds + 1] = c
		end
		rowsAt = RealTime()
	end
	MOD:Hook("SAeditor_Changed", function() rowsAt = 0 end, "ui")
	MOD:Hook("SPeditor_Selected", function() rowsAt = 0 end, "ui")
	MOD:Hook("SPeditor_MultiChanged", function() rowsAt = 0 end, "ui")

	-- the visible part of the animation: frames v0 … v0 + vlen (Ctrl + wheel zooms, Shift + wheel scrolls);
	-- vlen = nil — the whole animation
	local v0, vlen = 0, nil
	local function viewLen() return math.min(vlen or SA.frames, SA.frames) end
	local function clampView()
		if vlen and vlen >= SA.frames then vlen = nil end
		v0 = math.Clamp(v0, 0, SA.frames - viewLen())
	end
	local function span(w) return math.max(w - NAME_W - PAD * 2, 10) end
	local function frameX(f, w) return NAME_W + PAD + (f - v0) * span(w) / viewLen() end
	local function frameAt(mx, w) return math.Clamp(v0 + (mx - NAME_W - PAD) / span(w) * viewLen(), 0, SA.frames) end
	local function rowAt(my)
		if my < RULER_H then return nil end
		return rows[math.floor((my - RULER_H) / ROW_H) + 1 + scroll]
	end
	local function keyAt(row, mx, w)
		local best, bestD
		for _, k in ipairs(row.keys) do
			local d = math.abs(frameX(k.f, w) - mx)
			if d <= 6 and (not bestD or d < bestD) then best, bestD = k, d end
		end
		return best
	end

	-- a sound bar: from the start frame over the length of the sound (a second until it is loaded)
	local function soundSpan(c, w)
		local f = (drag and drag.kind == "sound" and drag.id == c.id) and drag.to or c.f
		local x0 = frameX(f, w)
		local x1 = frameX(f + (SA.SoundLength(c) or SA.fps), w)
		-- an edge being dragged follows the cursor
		if drag and drag.kind == "trim" and drag.id == c.id then
			if drag.side == "in" then x0 = math.min(frameX(drag.to, w), x1 - 6) else x1 = math.max(frameX(drag.to, w), x0 + 6) end
		end
		return x0, math.max(math.min(x1, w - 2), x0 + 6)
	end
	-- the edge of a bar under the cursor: "in", "out" or nil (the bar must be wide enough to have a middle)
	local EDGE = 4
	local function soundEdge(c, mx, w)
		if not SA.SoundLength(c) then return nil end
		local x0, x1 = soundSpan(c, w)
		if x1 - x0 < EDGE * 4 then return nil end
		if math.abs(mx - x0) <= EDGE then return "in" end
		if math.abs(mx - x1) <= EDGE then return "out" end
	end
	-- the clip of a sound row under the cursor (the one that starts last, if they overlap)
	local function soundHit(row, mx, w)
		local best
		for _, c in ipairs(row.sounds) do
			local x0, x1 = soundSpan(c, w)
			if mx >= x0 - 2 and mx <= x1 + 2 and (not best or c.f > best.f) then best = c end
		end
		return best
	end
	local function soundLabel(c)
		local ent = c.uid ~= 0 and SA.EntByUID(c.uid) or nil
		local text = IsValid(ent) and C.DisplayName(ent) or L("sa_snd_everywhere")
		if c.voice and IsValid(ent) then text = text .. "  ·  " .. L("sa_snd_voice_tag") end
		if c.vol ~= 1 then text = text .. "  ·  " .. math.Round(c.vol * 100) .. "%" end
		return text
	end
	local matSound = Material("icon16/sound.png")
	local matFace = Material("icon16/emoticon_smile.png")

	local function diamond(x, y, r, col)
		draw.NoTexture()
		surface.SetDrawColor(col)
		surface.DrawPoly({ { x = x, y = y - r }, { x = x + r, y = y }, { x = x, y = y + r }, { x = x - r, y = y } })
	end

	tl.Paint = function(s, w, h)
		if RealTime() - rowsAt > 0.5 then buildRows() end
		surface.SetDrawColor(COL.LIST_BG or COL.BG)
		surface.DrawRect(0, 0, w, h)

		clampView()
		-- the view follows the playhead while the animation plays
		if vlen and (SA.playing or SA.rendering) and (SA.frame < v0 or SA.frame > v0 + vlen) then
			v0 = SA.frame
			clampView()
		end
		local sx, sy = s:LocalToScreen(0, 0)
		local function clip(on)
			if on then render.SetScissorRect(sx + NAME_W + 1, sy, sx + w, sy + h, true) else render.SetScissorRect(0, 0, 0, 0, false) end
		end

		-- ruler
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, RULER_H)
		local pxf = span(w) / viewLen()
		local tick = TICKS[#TICKS]
		for _, t in ipairs(TICKS) do
			if t * pxf >= 46 then tick = t break end
		end
		local minor = (tick >= 10) and tick / 5 or ((tick * pxf >= 60 and tick > 1) and 1 or nil)
		local vEnd = math.min(v0 + viewLen() + tick, SA.frames)
		clip(true)
		if minor and minor * pxf >= 4 then
			surface.SetDrawColor(COL.BORDER)
			for f = math.floor(v0 / minor) * minor, vEnd, minor do surface.DrawRect(frameX(f, w), RULER_H - 4, 1, 4) end
		end
		for f = math.floor(v0 / tick) * tick, vEnd, tick do
			local x = frameX(f, w)
			surface.SetDrawColor(COL.DIM)
			surface.DrawRect(x, RULER_H - 8, 1, 8)
			draw.SimpleText(tostring(f), "SPeditor.Small", x + 3, RULER_H / 2 - 2, COL.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
		clip(false)
		draw.SimpleText(string.format("%d %s", SA.fps, L("sa_fps")) .. (vlen and string.format("   ×%.1f", SA.frames / vlen) or ""),
			"SPeditor.Small", 8, RULER_H / 2, COL.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		-- rows
		local visible = math.max(math.floor((h - RULER_H) / ROW_H), 1)
		scroll = math.Clamp(scroll, 0, math.max(#rows - visible, 0))
		local selUID = SA.UID(C.selected)
		for i = 1, visible do
			local row = rows[i + scroll]
			if not row then break end
			local y = RULER_H + (i - 1) * ROW_H
			surface.SetDrawColor(((i + scroll) % 2 == 0) and COL.ROW_A or COL.ROW_B)
			surface.DrawRect(0, y, w, ROW_H)
			if row.uid == selUID or (row.face and row.owner == selUID) then
				surface.SetDrawColor(COL.SEL)
				surface.DrawRect(0, y, NAME_W, ROW_H)
			end
			if row.face then
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(matFace)
				surface.DrawTexturedRect(8, y + 1, 16, 16)
			end
			if row.sounds then
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(matSound)
				surface.DrawTexturedRect(6, y + 1, 16, 16)
				draw.SimpleText(row.name, "SPeditor.Small", 26, y + ROW_H / 2, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				clip(true)
				local right = 0
				for _, c in ipairs(row.sounds) do
					local x0, x1 = soundSpan(c, w)
					local held = drag and (drag.kind == "sound" or drag.kind == "trim") and drag.id == c.id
					surface.SetDrawColor(held and COL.ORANGE or COL.BLUE)
					surface.DrawRect(x0, y + 3, x1 - x0, ROW_H - 6)
					surface.SetDrawColor(color_black)
					surface.DrawOutlinedRect(x0, y + 3, x1 - x0, ROW_H - 6)
					-- a trimmed side is marked with a light edge
					surface.SetDrawColor(COL.TEXT)
					if (c.cin or 0) > 0 then surface.DrawRect(x0 + 1, y + 4, 2, ROW_H - 8) end
					if (c.cout or 0) > 0 then surface.DrawRect(x1 - 3, y + 4, 2, ROW_H - 8) end
					-- fades: a slope from the bottom corner up to the full height
					local len = SA.SoundLength(c)
					if len and len > 0 and ((c.fin or 0) > 0 or (c.fout or 0) > 0) then
						local px = (x1 - x0) / len * SA.fps / (c.pitch / 100)    -- pixels per second of the file at its speed
						local top, bot = y + 4, y + ROW_H - 4
						surface.SetDrawColor(COL.TEXT)
						if c.fin > 0 then surface.DrawLine(x0, bot, x0 + math.min(c.fin * px * (c.pitch / 100), x1 - x0), top) end
						if c.fout > 0 then surface.DrawLine(x1, bot, x1 - math.min(c.fout * px * (c.pitch / 100), x1 - x0), top) end
					end
					right = math.max(right, x1)
				end
				draw.SimpleText(soundLabel(row.sounds[1]), "SPeditor.Small", right + 6, y + ROW_H / 2, COL.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				clip(false)
			else
				draw.SimpleText(row.name, "SPeditor.Small", row.face and 28 or 8, y + ROW_H / 2, #row.keys > 0 and COL.TEXT or COL.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			end
			-- segments between keys and the keys themselves. A baked animation has a key
			-- every frame or two — hundreds per row: neighbouring segments of one kind are
			-- drawn as one strip, and keys that stand closer than a diamond is wide are
			-- drawn as thin marks (a diamond costs two polygons; measured in game: 9 ms a
			-- frame for a scene with six baked characters before this).
			local cy = y + ROW_H / 2
			local keys = row.keys
			clip(true)
			local runFrom, runHold
			for n, k in ipairs(keys) do
				local nxt = keys[n + 1]
				local hold = k.e == "hold"
				if runFrom and (not nxt or hold ~= runHold) then
					surface.SetDrawColor(runHold and COL.BORDER or COL.TAB_ON)
					surface.DrawRect(frameX(runFrom, w), cy - 1, frameX(k.f, w) - frameX(runFrom, w), 2)
					runFrom = nil
				end
				if nxt and not runFrom then runFrom, runHold = k.f, hold end
			end
			local lastX = -100
			for n, k in ipairs(keys) do
				local f = k.f
				local dragged = drag and drag.kind == "key" and drag.uid == row.uid and drag.from == k.f
				if dragged then f = drag.to end
				local selected = SA.selKey and SA.selKey.uid == row.uid and SA.selKey.f == k.f
				local x = frameX(f, w)
				local col = (selected or dragged) and COL.ORANGE or (k.e == "linear" and COL.TIMECODE or COL.TEXT)
				local nxt = keys[n + 1]
				if selected or dragged or (x - lastX >= 9 and (not nxt or frameX(nxt.f, w) - x >= 9)) then
					diamond(x, cy, 5, color_black)
					diamond(x, cy, 4, col)
					lastX = x
				elseif x - lastX >= 2 then
					surface.SetDrawColor(col)
					surface.DrawRect(x - 1, cy - 4, 2, 9)
					lastX = x
				end
			end
			clip(false)
		end
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(NAME_W, 0, 1, h)
		if #rows == 0 then
			draw.SimpleText(L("sa_no_tracks"), "SPeditor.Small", NAME_W + (w - NAME_W) / 2, RULER_H + (h - RULER_H) / 2, COL.DIM,
				TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end

		-- playhead
		clip(true)
		local px = frameX(SA.frame, w)
		surface.SetDrawColor(COL.ORANGE)
		surface.DrawRect(px, 0, 1, h)
		draw.NoTexture()
		surface.DrawPoly({ { x = px - 5, y = 0 }, { x = px + 6, y = 0 }, { x = px + 6, y = 7 }, { x = px + 0.5, y = 13 }, { x = px - 5, y = 7 } })
		clip(false)

		if SA.rendering then
			local job = SA.rendering
			draw.SimpleTextOutlined(string.format(L("sa_rnd_progress"), SA.RenderProgress(job)), "SPeditor.Bold",
				w - 10, h - 12, COL.ORANGE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 1, color_black)
		end
	end

	local function keyMenu(row, k)
		local m = UI.Menu()
		local em = m:AddSubMenu(L("sa_ease"))
		for _, e in ipairs(SA.EASES) do
			em:AddOption(L("sa_ease_" .. e), function() SA.SetEase(row.uid, k.f, e) end):SetChecked(k.e == e)
		end
		m:AddOption(L("sa_copy_key"), function() SA.keyClip = { uid = row.uid, f = k.f } end):SetIcon("icon16/page_copy.png")
		m:AddSpacer()
		m:AddOption(L("sa_key_delete"), function() SA.DeleteKey(row.uid, k.f) end):SetIcon("icon16/key_delete.png")
		m:Open()
	end

	local function rowMenu(row, frame)
		local m = UI.Menu()
		m:AddOption(L("sa_key_here") .. "  (" .. frame .. ")", function()
			if not IsValid(row.ent) then return end
			if row.face then SA.SetFaceKey({ row.ent }, frame) else SA.SetKey({ row.ent }, frame) end
		end):SetIcon("icon16/key_add.png")
		-- the face of a body row: its own keys
		if not row.face and IsValid(row.ent) and not C.IsAux(row.ent) and row.ent:GetFlexNum() > 0 and not SA.HasFaceTrack(row.ent) then
			m:AddOption(L("sa_face_start") .. "  (" .. frame .. ")", function() SA.SetFaceKey({ row.ent }, frame) end):SetIcon("icon16/emoticon_smile.png")
		end
		local clip = SA.keyClip
		if clip and clip.uid == row.uid and SA.HasKey(clip.uid, clip.f) then
			m:AddOption(L("sa_paste_key") .. "  (" .. clip.f .. " → " .. frame .. ")", function()
				SA.MoveKey(row.uid, clip.f, frame, true)
			end):SetIcon("icon16/page_paste.png")
		end
		if #row.keys > 0 then
			m:AddSpacer()
			m:AddOption(L(row.face and "sa_face_clear" or "sa_clear_track"), function() SA.ClearTrack(row.uid) end):SetIcon("icon16/cross.png")
		end
		m:Open()
	end

	local function soundMenu(c)
		local m = UI.Menu()
		m:AddOption(L("sa_snd_m_listen"), function() SA.ListenSound(c.path) end):SetIcon("icon16/control_play_blue.png")
		m:AddSpacer()
		local em = m:AddSubMenu(L("sa_snd_m_emitter"))
		em:AddOption(L("sa_snd_m_none"), function() SA.ChangeSound(c.id, { uid = 0, voice = false }) end):SetChecked(c.uid == 0)
		if IsValid(C.selected) and SA.UID(C.selected) ~= 0 then
			em:AddOption(L("sa_snd_m_selected") .. ": " .. C.DisplayName(C.selected), function()
				SA.ChangeSound(c.id, { uid = SA.UID(C.selected) })
			end):SetIcon("icon16/cursor.png")
		end
		em:AddSpacer()
		for _, obj in ipairs(C.BuildEntityList()) do
			local uid = SA.UID(obj.ent)
			if uid ~= 0 then
				em:AddOption(obj.name, function() SA.ChangeSound(c.id, { uid = uid }) end):SetChecked(c.uid == uid)
			end
		end
		if c.uid ~= 0 then
			m:AddOption(L("sa_snd_m_voice"), function() SA.ChangeSound(c.id, { voice = not c.voice }) end):SetChecked(c.voice)
		end
		local function numbers(title, key, list, suffix, scale)
			local sub = m:AddSubMenu(title)
			for _, v in ipairs(list) do
				sub:AddOption(v .. suffix, function() SA.ChangeSound(c.id, { [key] = v * scale }) end):SetChecked(math.abs(c[key] - v * scale) < 0.001)
			end
		end
		numbers(L("sa_snd_m_volume"), "vol", { 10, 25, 50, 75, 100, 150, 200 }, "%", 0.01)
		numbers(L("sa_snd_m_pitch"), "pitch", { 50, 75, 90, 100, 110, 125, 150, 200 }, "%", 1)
		if c.uid ~= 0 then numbers(L("sa_snd_m_dist"), "dist", { 50, 100, 150, 300, 600, 1200, 2400 }, "", 1) end
		numbers(L("sa_snd_m_fin"), "fin", { 0, 0.1, 0.25, 0.5, 1, 2, 4 }, " " .. L("sa_snd_sec"), 1)
		numbers(L("sa_snd_m_fout"), "fout", { 0, 0.1, 0.25, 0.5, 1, 2, 4 }, " " .. L("sa_snd_sec"), 1)
		m:AddSpacer()
		m:AddOption(L("sa_snd_m_here") .. "  (" .. round(SA.frame) .. ")", function() SA.ChangeSound(c.id, { f = round(SA.frame) }) end)
		m:AddOption(L("sa_snd_m_dup"), function()
			SA.AddSound(c.path, { f = round(SA.frame), uid = c.uid, voice = c.voice, vol = c.vol, pitch = c.pitch, dist = c.dist,
				cin = c.cin, cout = c.cout, fin = c.fin, fout = c.fout })
		end):SetIcon("icon16/page_copy.png")
		-- trimming at the playhead (the edges of a bar can also be dragged)
		if SA.SoundLength(c) then
			m:AddSpacer()
			local function cut(fn)
				return function()
					if not fn() then SPeditor.Notify("#sa_snd_trim_bad", 1) end
				end
			end
			m:AddOption(L("sa_snd_m_split"), cut(function() return SA.SplitSound(c.id, round(SA.frame)) end)):SetIcon("icon16/cut.png")
			m:AddOption(L("sa_snd_m_trim_in"), cut(function() return SA.TrimSound(c.id, "in", round(SA.frame)) end))
			m:AddOption(L("sa_snd_m_trim_out"), cut(function() return SA.TrimSound(c.id, "out", round(SA.frame)) end))
			if c.cin > 0 or c.cout > 0 then
				m:AddOption(L("sa_snd_m_untrim"), function()
					SA.TrimSound(c.id, "in", nil)
					SA.TrimSound(c.id, "out", nil)
				end):SetIcon("icon16/arrow_undo.png")
			end
		end
		m:AddOption(L("sa_snd_m_delete"), function() SA.RemoveSound(c.id) end):SetIcon("icon16/cross.png")
		m:Open()
	end

	tl.OnMousePressed = function(s, code)
		local mx, my = s:CursorPos()
		local w = s:GetWide()
		local row = rowAt(my)
		if row and row.sounds then
			local c = soundHit(row, mx, w)
			if mx < NAME_W then
				-- the name of a sound selects the object it comes from
				local ent = row.sounds[1].uid ~= 0 and SA.EntByUID(row.sounds[1].uid) or nil
				if IsValid(ent) then C.Select(ent, -1) end
				if code == MOUSE_RIGHT then soundMenu(row.sounds[1]) end
				return
			end
			if code == MOUSE_RIGHT then
				if c then soundMenu(c) end
				return
			end
			if code == MOUSE_LEFT and not SA.rendering and c then
				SA.selKey = nil
				local edge = soundEdge(c, mx, w)
				if edge then
					drag = { kind = "trim", id = c.id, side = edge, to = round(frameAt(mx, w)) }
				else
					drag = { kind = "sound", id = c.id, from = c.f, to = c.f, grab = frameAt(mx, w) - c.f }
				end
				s:MouseCapture(true)
				return
			end
		end
		if mx < NAME_W then
			if row and IsValid(row.ent) then
				C.Select(row.ent, -1)
				if code == MOUSE_RIGHT then rowMenu(row, round(SA.frame)) end
			end
			return
		end
		local k = row and keyAt(row, mx, w)
		if code == MOUSE_RIGHT then
			if k then keyMenu(row, k) elseif row then rowMenu(row, round(frameAt(mx, w))) end
			return
		end
		if code ~= MOUSE_LEFT or SA.rendering then return end
		if k then
			SA.selKey = { uid = row.uid, f = k.f }
			if IsValid(row.ent) and C.selected ~= row.ent then C.Select(row.ent, -1) end
			SA.Seek(k.f)
			drag = { kind = "key", uid = row.uid, from = k.f, to = k.f }
		else
			SA.selKey = nil
			drag = { kind = "scrub" }
			SA.Seek(round(frameAt(mx, w)))
		end
		s:MouseCapture(true)
	end

	tl.OnCursorMoved = function(s, mx, my)
		if not drag then
			-- the edge of a sound bar can be dragged: show it with the cursor
			local row = rowAt(my)
			local edge
			if row and row.sounds and mx >= NAME_W then
				local c = soundHit(row, mx, s:GetWide())
				edge = c and soundEdge(c, mx, s:GetWide())
			end
			s:SetCursor(edge and "sizewe" or "arrow")
			return
		end
		local f = round(frameAt(mx, s:GetWide()))
		if drag.kind == "scrub" then
			if f ~= round(SA.frame) then SA.Seek(f) end
		elseif drag.kind == "sound" then
			drag.to = math.Clamp(round(frameAt(mx, s:GetWide()) - drag.grab), 0, SA.frames)
		else
			drag.to = f
		end
	end

	tl.OnMouseReleased = function(s, code)
		if code ~= MOUSE_LEFT or not drag then return end
		s:MouseCapture(false)
		local d = drag
		drag = nil
		if d.kind == "sound" then
			if d.to ~= d.from then SA.ChangeSound(d.id, { f = d.to }) end
		elseif d.kind == "trim" then
			-- dragged past the start / end of the file: TrimSound stops at it
			SA.TrimSound(d.id, d.side, d.to)
		elseif d.kind == "key" and d.to ~= d.from then
			local copy = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
			SA.MoveKey(d.uid, d.from, d.to, copy)
			SA.selKey = { uid = d.uid, f = d.to }
			SA.Seek(d.to)
		end
	end

	tl.OnMouseWheeled = function(s, delta)
		local ctrl = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
		local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
		local mx = s:CursorPos()
		if ctrl and mx >= NAME_W then
			-- zoom around the frame under the cursor (down to ~20 frames on the whole width)
			local w = s:GetWide()
			local at = frameAt(mx, w)
			local len = math.Clamp(viewLen() * (delta > 0 and 0.8 or 1.25), math.min(20, SA.frames), SA.frames)
			v0 = at - (mx - NAME_W - PAD) / span(w) * len
			vlen = len
			clampView()
		elseif shift then
			v0 = v0 - delta * viewLen() * 0.1
			clampView()
		else
			scroll = math.max(scroll - delta, 0)
		end
		return true
	end
end

MOD:AddPage({ id = "sa_timeline", titleKey = "sa_timeline", icon = "icon16/film.png", window = "bottom", build = buildTimeline })

---------------------------------------------------------------------
-- "Import model animation" window
---------------------------------------------------------------------
-- a character: a ragdoll, or a model without physics posed by its bones (prop_dynamic)
local function animatable(ent)
	return IsValid(ent) and (C.IsRagdoll(ent) or (ent:GetClass() == "prop_dynamic" and (ent:GetBoneCount() or 0) > 1))
end
SA.CanImport = animatable

function SA.OpenImport(ent)
	if not animatable(ent) then
		SPeditor.Notify("#sa_need_ragdoll", 0)
		return
	end
	local old = Dock.ByKey("sa_import")
	if IsValid(old) then old:Remove() end
	local win, body = Dock.Create({ key = "sa_import", id = "sa_import", title = L("sa_imp_title"), w = 400, h = math.min(560, ScrH() - 160),
			x = math.floor(ScrW() / 2 - 200), y = 120, dockable = false, icon = "icon16/film_add.png" })
	win.minW, win.minH = 320, 320
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.sa_import = nil
	end

	local hint = UI.Label(body, L("sa_imp_hint"))
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:DockMargin(8, 6, 8, 4)

	local opts = { step = 2, loops = 1, speed = 1, root = true }
	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(138)
	foot.Paint = function() end
	UI.Slider(foot, L("sa_imp_step"), 1, 6, 0, opts.step, function(v) opts.step = round(v) end)
	UI.Slider(foot, L("sa_imp_loops"), 1, 8, 0, opts.loops, function(v) opts.loops = round(v) end)
	UI.Slider(foot, L("sa_imp_speed"), 0.25, 2, 2, opts.speed, function(v) opts.speed = v end)
	UI.Check(foot, L("sa_imp_root"), opts.root, function(v) opts.root = v end)

	local search = vgui.Create("DTextEntry", body)
	search:Dock(TOP)
	search:DockMargin(6, 2, 6, 2)
	search:SetTall(20)
	search:SetFont("SPeditor.Small")
	search:SetPlaceholderText(L("sa_imp_search"))

	local list = vgui.Create("DListView", body)
	list:Dock(FILL)
	list:DockMargin(6, 0, 6, 2)
	list:SetMultiSelect(false)
	list:AddColumn(L("sa_imp_col_name"))
	list:AddColumn(L("sa_imp_col_len")):SetFixedWidth(70)
	if list.SetBackgroundColor then list:SetBackgroundColor(COL.LIST_BG) end

	-- whose animations are listed: the character's own or those of another model with the
	-- same skeleton (a player model has every player animation, the ones addons add included)
	local source = nil
	local seqs = SA.SequenceList(ent)
	local fill
	local srcRow = vgui.Create("DPanel", body)
	srcRow:Dock(TOP)
	srcRow:DockMargin(6, 0, 6, 2)
	srcRow:SetTall(22)
	srcRow.Paint = function() end
	local srcCombo = UI.StyleCombo(vgui.Create("DComboBox", srcRow))
	srcCombo:Dock(FILL)
	srcCombo:SetSortItems(false)
	srcCombo:SetTooltip(L("sa_imp_src_tip"))
	local function setSource(model)
		source = (model ~= nil and model ~= "") and model or nil
		seqs = SA.SequenceList(ent, source)
		fill()
		hint:SetText(L(#seqs == 0 and "sa_imp_none" or "sa_imp_hint"))
	end
	srcCombo:AddChoice(L("sa_imp_src_own"), "", true)
	for _, m in ipairs(SA.ANIM_MODELS) do
		if util.IsValidModel(m[2]) then srcCombo:AddChoice(L(m[1]), m[2]) end
	end
	srcCombo:AddChoice(L("sa_imp_src_path"), "?")
	srcCombo.OnSelect = function(s, _, text, data)
		if data ~= "?" then
			setSource(data)
			return
		end
		Derma_StringRequest(L("sa_imp_src_path"), L("sa_imp_src_prompt"), source or "models/player/kleiner.mdl", function(path)
			path = string.lower(string.Trim(string.gsub(path, "\\", "/")))
			if string.sub(path, -4) ~= ".mdl" or not util.IsValidModel(path) then
				SPeditor.Notify("#bad_model_path", 1)
				return
			end
			s:SetText(path)
			setSource(path)
		end)
	end

	function fill()
		list:Clear()
		local q = string.lower(string.Trim(search:GetValue() or ""))
		for _, sq in ipairs(seqs) do
			if q == "" or string.find(string.lower(sq.name), q, 1, true) then
				list:AddLine(sq.name, string.format("%.2f", sq.dur)).SPSeq = sq
			end
		end
	end
	search.OnChange = fill
	fill()
	if #seqs == 0 then hint:SetText(L("sa_imp_none")) end

	local function import()
		local _, line = list:GetSelectedLine()
		if not line or not line.SPSeq or not IsValid(ent) then return end
		local seq, name = line.SPSeq.id, line.SPSeq.name
		-- the same animation for every selected character, from the same frame: they move in
		-- step. With an animation of the character's own model the others take the one with
		-- the same name from theirs.
		local targets = { ent }
		for _, e in ipairs(C.SelectionList()) do
			if e ~= ent and animatable(e) then targets[#targets + 1] = e end
		end
		local start = SA.frame
		for i, e in ipairs(targets) do
			-- one character at a time: an import is a burst of network messages
			timer.Simple((i - 1) * 0.25, function()
				if not IsValid(e) then return end
				local o = table.Copy(opts)
				o.start, o.model = start, source
				local id = seq
				if not source and e ~= ent and e:GetModel() ~= ent:GetModel() then id = e:LookupSequence(name) end
				if not id or id < 0 then return end
				local count = SA.ImportSequence(e, id, o)
				if count and i == 1 then
					SPeditor.Notify(#targets > 1 and ("#sa_imp_done_n|" .. name .. "|" .. #targets) or ("#sa_imp_done|" .. name .. "|" .. count), 2)
				end
			end)
		end
	end
	list.DoDoubleClick = import
	local go = UI.Button(foot, L("sa_imp_go"), "icon16/film_add.png", import, 26)
	go:DockMargin(6, 6, 6, 2)
	return win
end

---------------------------------------------------------------------
-- Speed settings of the animation render, the same in both render windows: JPEG quality
-- of the video and the part of soft shadow / depth of field passes. row(text) -> a row panel.
---------------------------------------------------------------------
local function renderSpeedRows(row)
	local qRow = row(L("sa_rd_quality"))
	local q = UI.StyleCombo(vgui.Create("DComboBox", qRow))
	q:Dock(FILL)
	for _, v in ipairs(SA.RENDER_QUALITIES) do q:AddChoice(L("sa_rd_q_" .. v), v, v == SA.RenderQuality()) end
	if not q:GetSelected() then q:SetText("JPEG " .. SA.RenderQuality()) end
	q.OnSelect = function(_, _, _, data) RunConsoleCommand("saeditor_render_quality", tostring(data)) end
	local sRow = row(L("sa_rd_samples"))
	local sm = UI.StyleCombo(vgui.Create("DComboBox", sRow))
	sm:Dock(FILL)
	for _, v in ipairs(SA.RENDER_SAMPLES) do sm:AddChoice(L("sa_rd_samples_" .. v), v, v == SA.RenderSamples()) end
	if not sm:GetSelected() then sm:SetText(SA.RenderSamples() .. "%") end
	sm.OnSelect = function(_, _, _, data) RunConsoleCommand("saeditor_render_samples", tostring(data)) end
	local fRow = row(L("sa_rd_fps"))
	local fc = UI.StyleCombo(vgui.Create("DComboBox", fRow))
	fc:Dock(FILL)
	fc:SetTooltip(L("sa_rd_fps_tip"))
	local cur = math.floor(GetConVar("saeditor_render_fps"):GetFloat())
	for _, v in ipairs(SA.RENDER_FPS) do
		fc:AddChoice(v == 0 and string.format(L("sa_rd_fps_anim"), SA.fps) or (v .. " " .. L("sa_fps")), v, v == cur)
	end
	if not fc:GetSelected() then fc:SetText(cur .. " " .. L("sa_fps")) end
	fc.OnSelect = function(_, _, _, data) RunConsoleCommand("saeditor_render_fps", tostring(data)) end
	return qRow, sRow, fRow
end

---------------------------------------------------------------------
-- "Render animation" window
---------------------------------------------------------------------
function SA.OpenRender()
	if Dock.ShowPage("sa_render") then return end
	local win, body = Dock.Create({ key = "sa_render", id = "sa_render", title = L("sa_rnd_title"), w = 400, h = 500,
			x = math.floor(ScrW() / 2 - 190), y = 140, dockable = false, icon = "icon16/film_save.png" })
	win.minW, win.minH = 320, 340
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.sa_render = nil
	end

	local function row(text)
		local r = vgui.Create("DPanel", body)
		r:Dock(TOP)
		r:DockMargin(8, 4, 8, 0)
		r:SetTall(22)
		r.Paint = function() end
		local l = vgui.Create("DLabel", r)
		l:Dock(LEFT)
		l:SetWide(150)
		l:SetFont("SPeditor.Small")
		l:SetTextColor(COL.TEXT)
		l:SetText(text)
		return r
	end
	local function entry(parent, value, numeric)
		local e = vgui.Create("DTextEntry", parent)
		e:Dock(FILL)
		e:SetFont("SPeditor.Small")
		e:SetNumeric(numeric and true or false)
		e:SetText(tostring(value))
		return e
	end

	local camera = nil
	local cam = UI.StyleCombo(vgui.Create("DComboBox", row(L("sa_rnd_camera"))))
	cam:Dock(FILL)
	cam:AddChoice(L("win_primary"), false, true)
	cam:AddChoice(L("work_camera"), "work")
	for _, e in ipairs(C.Objects()) do
		if C.IsCamera(e) then cam:AddChoice(C.DisplayName(e), e, e == C.GetViewCamera()) end
	end
	if C.GetViewCamera() then camera = C.GetViewCamera() end
	cam.OnSelect = function(_, _, _, data) camera = data or nil end

	local from = entry(row(L("sa_rnd_from")), 0, true)
	local to   = entry(row(L("sa_rnd_to")), SA.frames, true)
	local only = entry(row(L("sa_rnd_only")), "")
	only:SetPlaceholderText(L("sa_rnd_only_tip"))
	only:SetTooltip(L("sa_rd_which_tip"))
	local name = entry(row(L("sa_rnd_name")), (C.sceneName and C.sceneName ~= "" and C.sceneName or "anim"))
	local format = SA.RenderFormat()
	local fmt = UI.StyleCombo(vgui.Create("DComboBox", row(L("sa_rnd_format"))))
	fmt:Dock(FILL)
	for _, f in ipairs(SA.RENDER_FORMATS) do fmt:AddChoice(L("sa_fmt_" .. f), f, f == format) end
	fmt.OnSelect = function(_, _, _, data)
		format = data
		RunConsoleCommand("saeditor_render_format", data)
	end
	renderSpeedRows(row)
	local settle = GetConVar("saeditor_render_settle"):GetFloat()
	UI.Slider(body, L("sa_rnd_settle"), 0.05, 1.5, 2, settle, function(v)
		settle = v
		RunConsoleCommand("saeditor_render_settle", tostring(math.Round(v, 2)))
	end):SetTooltip(L("sa_rnd_settle_tip"))

	-- the hint follows the format: a video is one file, pictures go into a folder
	local function hintKey() return format == "avi" and "sa_rd_note_avi" or "sa_rnd_hint" end
	local hint = UI.Label(body, L(hintKey()))
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:DockMargin(8, 8, 8, 4)
	hint.SPKey = hintKey()
	hint.Think = function(s)
		local key = hintKey()
		if s.SPKey ~= key then
			s.SPKey = key
			s:SetText(L(key))
		end
		s:SizeToContentsY()       -- DLabel stretches itself in its own Think, which this one replaces
	end

	local status = UI.Label(body, "", COL.ORANGE)
	status:DockMargin(8, 4, 8, 4)
	status.Think = function(s)
		local job = SA.rendering
		local text = job and string.format(L("sa_rnd_progress"), SA.RenderProgress(job)) or ""
		if s.SPText ~= text then
			s.SPText = text
			s:SetText(text)
		end
	end

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(34)
	foot.Paint = function() end
	local go = vgui.Create("DButton", foot)
	go:Dock(LEFT)
	go:DockMargin(8, 4, 4, 4)
	go:SetWide(170)
	go:SetText("  " .. L("sa_rnd_go"))
	go:SetIcon("icon16/film_save.png")
	UI.StyleButton(go, nil, 3)
	go.DoClick = function()
		local frames
		if string.Trim(only:GetValue()) ~= "" then
			frames = SA.ParseFrames(only:GetValue())
			if #frames == 0 then
				SPeditor.Notify("#sa_rnd_frames_none", 1)
				return
			end
		end
		SA.RenderSequence({ camera = camera, from = tonumber(from:GetValue()) or 0, to = tonumber(to:GetValue()) or SA.frames,
				frames = frames, name = name:GetValue(), format = format, settle = settle })
	end
	local cancel = vgui.Create("DButton", foot)
	cancel:Dock(RIGHT)
	cancel:DockMargin(4, 4, 8, 4)
	cancel:SetWide(120)
	cancel:SetText(L("sa_rnd_cancel"))
	UI.StyleButton(cancel, nil, 3)
	cancel.DoClick = function()
		if SA.rendering then SA.StopRender(false) else win:Remove() end
	end
	return win
end

---------------------------------------------------------------------
-- The editor's Render window. When it opens, SAeditor checks whether the scene has
-- animation (playing right now or not — it does not matter), and for an animated scene
-- adds its own section at the top of the settings: what to render and in what form.
-- The section watches the scene itself: once the first key appears, so does the section.
---------------------------------------------------------------------
MOD:Hook("SPeditor_RenderDialog", function(ctx)
	local body, button = ctx.body, ctx.button

	local sec = vgui.Create("DPanel", body)
	sec:Dock(TOP)
	sec:DockMargin(4, 4, 4, 6)
	sec:DockPadding(0, 22, 0, 6)
	sec.Paint = function(_, w, h)
		surface.SetDrawColor(COL.ROW_B)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, 20)
		surface.SetDrawColor(COL.ORANGE)
		surface.DrawRect(0, 0, 3, 20)
		draw.SimpleText(string.format(L("sa_rd_title"), SA.frames + 1, SA.frames / SA.fps, SA.fps), "SPeditor.Bold", 10, 10, COL.TEXT,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local function row(text)
		local r = vgui.Create("DPanel", sec)
		r:Dock(TOP)
		r:DockMargin(6, 4, 6, 0)
		r:SetTall(22)
		r.Paint = function() end
		local l = vgui.Create("DLabel", r)
		l:Dock(LEFT)
		l:SetWide(140)
		l:SetFont("SPeditor.Small")
		l:SetTextColor(COL.TEXT)
		l:SetText(text)
		return r
	end

	local mode = UI.StyleCombo(vgui.Create("DComboBox", row(L("sa_rd_what"))))
	mode:Dock(FILL)
	mode:AddChoice(L("sa_rd_anim"), "anim", SA.RenderMode() == "anim")
	mode:AddChoice(L("sa_rd_frame"), "frame", SA.RenderMode() == "frame")
	mode:AddChoice(L("sa_rd_frames"), "frames", SA.RenderMode() == "frames")
	mode.OnSelect = function(_, _, _, data) RunConsoleCommand("saeditor_render_mode", data) end

	-- which frames: keys / every N / a list; the menu button fills in the usual choices
	local framesRow = row(L("sa_rd_which"))
	local framesBox = vgui.Create("DTextEntry", framesRow)
	framesBox:Dock(FILL)
	framesBox:SetFont("SPeditor.Small")
	framesBox:SetValue(SA.RenderFramesSpec())
	framesBox:SetTooltip(L("sa_rd_which_tip"))
	local function setSpec(v)
		framesBox:SetValue(v)
		RunConsoleCommand("saeditor_render_frames", v)
	end
	framesBox.OnChange = function(s2) RunConsoleCommand("saeditor_render_frames", s2:GetValue()) end
	local pick = vgui.Create("DButton", framesRow)
	pick:Dock(RIGHT)
	pick:DockMargin(4, 0, 0, 0)
	pick:SetWide(24)
	pick:SetText("…")
	UI.StyleButton(pick, nil, 3)
	pick.DoClick = function()
		local m = UI.Menu()
		m:AddOption(L("sa_rd_which_keys"), function() setSpec("keys") end)
		for _, n in ipairs({ 2, 4, 6, 12, 24 }) do
			m:AddOption(string.format(L("sa_rd_which_every"), n), function() setSpec("every " .. n) end)
		end
		m:AddOption(string.format(L("sa_rd_which_cur"), math.floor(SA.frame + 0.5)), function()
			local cur = string.Trim(framesBox:GetValue())
			local f = tostring(math.floor(SA.frame + 0.5))
			setSpec((cur == "" or cur == "keys" or string.find(cur, "every", 1, true)) and f or (cur .. ", " .. f))
		end)
		m:Open()
	end

	local fmtRow = row(L("sa_rd_format"))
	local fmt = UI.StyleCombo(vgui.Create("DComboBox", fmtRow))
	fmt:Dock(FILL)
	for _, f in ipairs(SA.RENDER_FORMATS) do fmt:AddChoice(L("sa_fmt_" .. f), f, f == SA.RenderFormat()) end
	fmt.OnSelect = function(_, _, _, data) RunConsoleCommand("saeditor_render_format", data) end
	local qRow, sRow, fRow = renderSpeedRows(row)

	local note = vgui.Create("DLabel", sec)
	note:Dock(TOP)
	note:DockMargin(8, 6, 8, 0)
	note:SetWrap(true)
	note:SetAutoStretchVertical(true)
	note:SetFont("SPeditor.Small")
	note:SetTextColor(COL.DIM)
	note:SetText("")

	local stop = UI.Button(sec, L("sa_rd_stop"), "icon16/stop.png", function() SA.StopRender(false) end)
	stop:DockMargin(6, 6, 6, 0)

	local state
	sec.Think = function(s)
		local animated = SA.IsAnimated()
		local anim = animated and SA.RenderMode() ~= "frame"
		local job = SA.rendering
		local text
		if job then
			text = string.format(L("sa_rnd_progress"), SA.RenderProgress(job))
		elseif SA.RenderMode() == "frames" then
			local n = #SA.ParseFrames(SA.RenderFramesSpec())
			text = n > 0 and string.format(L("sa_rd_note_frames"), n) or L("sa_rnd_frames_none")
		else
			text = L(anim and ("sa_rd_note_" .. SA.RenderFormat()) or "sa_rd_note_frame")
		end
		local key = tostring(animated) .. tostring(anim) .. tostring(job ~= nil) .. text
		if key == state then return end
		state = key
		s:SetVisible(animated)
		fmtRow:SetVisible(anim)
		qRow:SetVisible(anim and SA.RenderFormat() ~= "png")
		sRow:SetVisible(anim)
		fRow:SetVisible(anim and SA.RenderMode() ~= "frames")
		stop:SetVisible(job ~= nil)
		framesRow:SetVisible(animated and SA.RenderMode() == "frames")
		note:SetText(text)
		note:SetTextColor(job and COL.ORANGE or COL.DIM)
		-- the window button says what exactly will be rendered
		if IsValid(button) then
			button:SetText("  " .. L(anim and "sa_rd_button" or "act_render"))
			button:SetIcon(anim and "icon16/film_save.png" or "icon16/picture_save.png")
		end
		s:InvalidateLayout(true)
		s:SizeToChildren(false, true)
		body:InvalidateLayout()
	end
	sec.PerformLayout = function(s) s:SizeToChildren(false, true) end
end, "render_dialog")

---------------------------------------------------------------------
-- Preview of the Render window: animation playback buttons — to the start, a frame
-- back, play / pause, a frame forward, to the end — and a scrub bar. Visible only for
-- an animated scene.
---------------------------------------------------------------------
MOD:Hook("SPeditor_RenderPreviewBuilt", function(side, pv)
	local bar = vgui.Create("DPanel", side)
	bar:Dock(BOTTOM)
	bar:DockMargin(0, 4, 0, 0)
	bar:SetTall(26)
	bar.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
	end
	local function refresh() pv.next = 0 end
	local function seek(f)
		SA.Seek(math.Clamp(math.floor(f + 0.5), 0, SA.frames))
		refresh()
	end

	UI.IconButton(bar, "icon16/control_start_blue.png", L("sa_first"), function() seek(0) end)
	UI.IconButton(bar, "icon16/control_rewind_blue.png", L("sa_prev_frame"), function() seek(SA.frame - 1) end)
	local play = UI.IconButton(bar, "icon16/control_play_blue.png", L("sa_play"), function() SA.Play() end, function() return SA.playing end)
	play.Think = function(s)
		local icon = SA.playing and "icon16/control_pause_blue.png" or "icon16/control_play_blue.png"
		if s.SPIcon ~= icon then
			s.SPIcon = icon
			s:SetIcon(icon)
		end
	end
	UI.IconButton(bar, "icon16/control_fastforward_blue.png", L("sa_next_frame"), function() seek(SA.frame + 1) end)
	UI.IconButton(bar, "icon16/control_end_blue.png", L("sa_last"), function() seek(SA.frames) end)

	local label = vgui.Create("DLabel", bar)
	label:Dock(RIGHT)
	label:DockMargin(6, 0, 8, 0)
	label:SetWide(150)
	label:SetFont("SPeditor.Small")
	label:SetTextColor(COL.TEXT)
	label:SetContentAlignment(6)
	label.Think = function(s)
		local text = string.format("%d / %d   %.2f / %.2f s", math.floor(SA.frame + 0.5), SA.frames, SA.frame / SA.fps, SA.frames / SA.fps)
		if s.SPText ~= text then
			s.SPText = text
			s:SetText(text)
		end
	end

	-- scrub bar: click or drag
	local scrub = vgui.Create("DPanel", bar)
	scrub:Dock(FILL)
	scrub:DockMargin(10, 0, 4, 0)
	scrub:SetCursor("hand")
	local dragging = false
	local function frameAt(s, mx) return math.Clamp((mx - 6) / math.max(s:GetWide() - 12, 1), 0, 1) * SA.frames end
	scrub.Paint = function(s, w, h)
		local x0, x1, cy = 6, w - 6, h / 2
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(x0, cy - 2, x1 - x0, 4)
		local px = x0 + (x1 - x0) * math.Clamp(SA.frame / SA.frames, 0, 1)
		surface.SetDrawColor(COL.ORANGE)
		surface.DrawRect(x0, cy - 2, px - x0, 4)
		surface.DrawRect(px - 3, cy - 8, 6, 16)
		if SA.rendering then
			local job = SA.rendering
			draw.SimpleText(string.format(L("sa_rnd_progress"), SA.RenderProgress(job)), "SPeditor.Small",
				w / 2, cy - 1, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
	end
	scrub.OnMousePressed = function(s, code)
		if code ~= MOUSE_LEFT or SA.rendering then return end
		dragging = true
		s:MouseCapture(true)
		seek(frameAt(s, (s:CursorPos())))
	end
	scrub.OnCursorMoved = function(s, mx)
		if not dragging then return end
		local f = math.floor(frameAt(s, mx) + 0.5)
		if f ~= math.floor(SA.frame + 0.5) then seek(f) end
	end
	scrub.OnMouseReleased = function(s, code)
		if code ~= MOUSE_LEFT then return end
		dragging = false
		s:MouseCapture(false)
	end

	local shown
	bar.Think = function(s)
		local animated = SA.IsAnimated()
		if animated == shown then return end
		shown = animated
		s:SetVisible(animated)
		side:InvalidateLayout()
	end
end, "render_preview")

---------------------------------------------------------------------
-- Editor menus
---------------------------------------------------------------------
MOD:AddMenu("object", function(m, ent)
	local sub = m:AddSubMenu(L("sa_menu"))
	sub:AddOption(L("sa_key"), function() SA.SetKey({ ent }) end):SetIcon("icon16/key_add.png")
	if animatable(ent) then
		sub:AddOption(L("sa_import"), function() SA.OpenImport(ent) end):SetIcon("icon16/film_add.png")
	end
	if C.IsEffect(ent) then
		-- an effect is played by keys of its moment (SA.PlayEffect)
		local pm, po = sub:AddSubMenu(L("sa_fx_play"))
		if po and po.SetIcon then po:SetIcon("icon16/lightning_go.png") end
		pm:AddOption(L("sa_fx_to_end"), function() SA.PlayEffect(ent) end)
		for _, sec in ipairs({ 0.1, 0.25, 0.5, 1, 2, 4 }) do
			pm:AddOption(string.format(L("sa_fx_for"), sec), function() SA.PlayEffect(ent, sec) end)
		end
	end
	sub:AddOption(L("sa_snd_add"), function()
		C.Select(ent, -1)
		SA.OpenSounds()
	end):SetIcon("icon16/sound_add.png")
	sub:AddOption(L("sa_crv_title") .. "…", function() C.Select(ent, C.selected == ent and C.selBone or -1) SA.OpenCurves() end):SetIcon("icon16/chart_curve.png")
	if not C.IsCamera(ent) then
		sub:AddOption(L("sa_proc_title") .. "…", function() SA.OpenProc(ent) end):SetIcon("icon16/heart.png")
	end
	if SA.tracks[SA.UID(ent)] then
		sub:AddSpacer()
		sub:AddOption(L("sa_clear_track"), function() SA.ClearTrack(SA.UID(ent)) end):SetIcon("icon16/cross.png")
	end
end)

MOD:AddMenu("file", function(m)
	m:AddOption(L("sa_render"), function() SA.OpenRender() end):SetIcon("icon16/film_save.png")
	m:AddOption(L("sa_smh_title") .. "…", function() SA.OpenSMH() end):SetIcon("icon16/arrow_switch.png")
end)

MOD:AddMenu("edit", function(m)
	local sub = m:AddSubMenu(L("sa_menu"))
	sub:AddOption(L("sa_key") , function() SA.SetKey() end):SetIcon("icon16/key_add.png")
	sub:AddOption(L("sa_key_all"), function() SA.SetKey(C.Objects()) end):SetIcon("icon16/key_go.png")
	sub:AddOption(L("sa_autokey"), function() SA.autokey = not SA.autokey end):SetChecked(SA.autokey)
	sub:AddOption(L("sa_snd_add"), function() SA.OpenSounds() end):SetIcon("icon16/sound_add.png")
	sub:AddOption(L("sa_crv_title") .. "…", function() SA.OpenCurves() end):SetIcon("icon16/chart_curve.png")
	sub:AddSpacer()
	sub:AddOption(L("sa_clear_all"), function()
		Derma_Query(L("sa_clear_all_q"), "SAeditor", L("yes"), function() SA.ClearAll() end, L("cancel"), function() end)
	end):SetIcon("icon16/cross.png")
end)
