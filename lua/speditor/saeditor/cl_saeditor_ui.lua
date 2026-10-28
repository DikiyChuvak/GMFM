--[[
SAeditor — interface: the Timeline page in the editor's bottom window (where SFM has
the timeline), the "Import model animation" and "Render animation" windows, menu items.

Timeline: names of animated objects on the left, the frame ruler and keys on the right;
below the objects — the sounds: one row per file and source, a bar for every time it plays.
  LMB on the ruler or empty space — move the playhead (can be dragged);
  LMB on a key — select it, drag — move it (with Ctrl — copy it); Ctrl+click — add a key to the
  selection or take it out; Shift+drag over empty space — select the keys in a box; the selected
  keys move, copy, change their motion and are deleted together;
  RMB on a key — the key menu, RMB on a row — set or paste a key;
  LMB on a sound bar — drag the sound along the timeline, on its edge — trim it, RMB — the sound menu;
  wheel — scroll the object list.
The "Cameras" row at the top (camera cuts, cl_saeditor_cuts.lua): RMB — switch to a camera
here; a cut mark can be dragged, RMB on it — change its camera or delete it.
]]
local COMP  = SPeditor.Component("saeditor")
local SA   = COMP.SA
local C    = SPeditor.Client
local UI   = SPeditor.UI
local Dock = SPeditor.Dock
local L    = SPeditor.L
local COL  = UI.PAL
local markMat = Material("speditor/skins/sfm/sfm/timeline_bookmark.png")
local headMat = Material("speditor/skins/sfm/sfm/timeline_upper_playhead.png")

local NAME_W, RULER_H, ROW_H, PAD = 170, 20, 18, 10
-- the timeline follows the interface scale (UI.S)
local function metrics() NAME_W, RULER_H, ROW_H = UI.S(170), UI.S(20), UI.S(18) end
metrics()
COMP:Hook("SPeditor_FontsCreated", metrics, "timeline_metrics")
local TICKS = { 1, 2, 5, 10, 20, 25, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000 }

local function round(v) return math.floor(v + 0.5) end

-- Selected keys of the timeline: { ["uid:frame:parts"] = { uid, f, parts } } — parts is set for
-- a key picked on the row of a bone (bone keys): it stands for that bone's part of the key
SA.selKeys = SA.selKeys or {}
local function isSel(uid, f, parts) return SA.selKeys[uid .. ":" .. f .. ":" .. (parts or "")] ~= nil end
local function setSel(uid, f, on, parts)
	SA.selKeys[uid .. ":" .. f .. ":" .. (parts or "")] = on and { uid = uid, f = f, parts = parts } or nil
end
local function clearSel() SA.selKeys = {} end
-- the selected keys that still exist
local function selList()
	local out = {}
	for id, k in pairs(SA.selKeys) do
		if SA.HasKey(k.uid, k.f) then out[#out + 1] = k else SA.selKeys[id] = nil end
	end
	return out
end
SA.SelectedKeys = selList

---------------------------------------------------------------------
-- The Motion Editor's time selection (a0.7, SA.timeSel / SA.TimeSelWeight): made with
-- Shift + drag on the frame numbers, its four edges dragged there; this menu (the clock
-- button, a right click on the frame numbers) makes it from the keys or the animation and
-- sets its falloff.
---------------------------------------------------------------------
-- The procedural presets (SA.PRESETS) grouped as submenus of m; strengths: 25 / 50 / 100 %
-- under each one (else they apply in full)
local PRESET_GROUPS = {
	{ "sa_presets_motion", { "smooth", "sharp", "steady", "jitter", "hold", "round", "default", "stagger" } },
	{ "sa_presets_shape", { "in", "out", "ramp", "spline", "drop", "release" } },
	{ "sa_presets_face", { "zero", "half", "one" } },
}
function SA.PresetMenu(m, strengths)
	local function add(menu, p)
		if not strengths then
			menu:AddOption(L("sa_preset_" .. p), function() SA.ApplyPreset(p, 100) end)
			return
		end
		local sub = menu:AddSubMenu(L("sa_preset_" .. p))
		for _, pct in ipairs({ 25, 50, 100 }) do
			sub:AddOption(pct .. " %", function() SA.ApplyPreset(p, pct) end)
		end
	end
	for _, g in ipairs(PRESET_GROUPS) do
		local gm = m:AddSubMenu(L(g[1]))
		for _, p in ipairs(g[2]) do add(gm, p) end
	end
	m:AddSpacer()
	add(m, "playhead")
	add(m, "paste")
	m:AddOption(L("sa_preset_copy"), function() SA.presetCopy = math.floor(SA.frame + 0.5) end):SetIcon("icon16/page_copy.png")
end

function SA.TimeSelMenu(frame)
	local m = UI.Menu()
	local t = SA.timeSel
	m:AddOption(L("sa_tsel")):SetEnabled(false)
	m:AddSpacer()
	local function fall(n)
		local cur = SA.timeSel
		if not cur then return end
		SA.SetTimeSel({ cur[2] - n, cur[2], cur[3], cur[3] + n, shape = cur.shape })
	end
	-- the frames of the selected keys
	local lo, hi
	for _, k in ipairs(selList()) do
		lo, hi = math.min(lo or k.f, k.f), math.max(hi or k.f, k.f)
	end
	if lo and hi > lo then
		m:AddOption(string.format(L("sa_tsel_keys"), lo, hi), function() SA.SetTimeSel({ lo, lo, hi, hi }) end):SetIcon("icon16/key.png")
	end
	local n = math.max(math.floor(SA.fps / 2), 1)
	m:AddOption(string.format(L("sa_tsel_around"), n), function()
		SA.SetTimeSel({ frame - n * 2, frame - n, frame + n, frame + n * 2 })
	end):SetIcon("icon16/time.png")
	m:AddOption(L("sa_tsel_all"), function() SA.SetTimeSel({ 0, 0, SA.frames, SA.frames }) end)
	if not t then SA.PresetMenu(m:AddSubMenu(L("sa_presets_all")), false) end
	if t then
		m:AddSpacer()
		local fm = m:AddSubMenu(L("sa_tsel_falloff"))
		local cur = t[2] - t[1]
		fm:AddOption(L("sa_tsel_fall_none"), function() fall(0) end):SetChecked(cur == 0 and t[4] == t[3])
		for _, sec in ipairs({ 0.25, 0.5, 1, 2 }) do
			local f = math.max(math.floor(sec * SA.fps + 0.5), 1)
			fm:AddOption(string.format(L("sa_tsel_fall_n"), f, sec), function() fall(f) end):SetChecked(cur == f and t[4] - t[3] == f)
		end
		if #(SA.marks or {}) > 0 then
			fm:AddSpacer()
			fm:AddOption(L("sa_tsel_tomarks"), function()
				local cur = SA.timeSel
				if not cur then return end
				SA.SetTimeSel(SA.FalloffToMarks({ cur[1], cur[2], cur[3], cur[4], shape = cur.shape }))
			end):SetIcon("icon16/flag_blue.png")
		end
		fm:AddOption(L("sa_tsel_automarks"), function()
			SA.autoFalloffMarks = not SA.autoFalloffMarks
			local cur = SA.timeSel
			if cur and SA.autoFalloffMarks then SA.SetTimeSel({ cur[1], cur[2], cur[3], cur[4], shape = cur.shape }) end
		end):SetChecked(SA.autoFalloffMarks == true)
		local sm = m:AddSubMenu(L("sa_tsel_shape"))
		for _, shape in ipairs(SA.TIMESEL_SHAPES) do
			sm:AddOption(L("sa_tsel_shape_" .. shape), function()
				if SA.timeSel then
					SA.timeSel.shape = shape
					hook.Run("SAeditor_TimeSelChanged", SA.timeSel)
				end
			end):SetChecked(t.shape == shape)
		end
		m:AddOption(L("sa_tsel_apply"), function() SA.SetKey() end):SetIcon("icon16/key_add.png")
		-- SFM's procedural presets over the keys inside the selection (b0.2)
		SA.PresetMenu(m:AddSubMenu(L("sa_presets")), true)
		m:AddOption(L("sa_tsel_select_keys"), function()
			clearSel()
			for uid, keys in pairs(SA.tracks) do
				for _, k in ipairs(keys) do
					if k.f >= t[1] and k.f <= t[4] then setSel(uid, k.f, true) end
				end
			end
		end):SetIcon("icon16/key_go.png")
		m:AddSpacer()
		m:AddOption(L("sa_tsel_clear"), function() SA.SetTimeSel(nil) end):SetIcon("icon16/cross.png")
	end
	m:AddSpacer()
	m:AddOption(L("sa_tsel_how")):SetEnabled(false)
	-- bookmarks (b0.2) live on the same ruler
	m:AddSpacer()
	m:AddOption(SA.MarkAt(frame) and L("sa_mark_delete") or L("sa_mark_add"), function()
		if SA.MarkAt(frame) then SA.RemoveMark(frame) else SA.AddMark(frame) end
	end):SetIcon("icon16/flag_blue.png")
	m:Open()
end

---------------------------------------------------------------------
-- Timeline page
---------------------------------------------------------------------
local function buildTimeline(page)
	local bar = vgui.Create("DPanel", page)
	bar:Dock(TOP)
	-- a theme may want a taller transport bar (GM:FM UI: SFM's big play buttons)
	bar:SetTall(UI.S(UI.Theme and UI.Theme.transportH or 28))
	bar.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
	end

	local function sep()
		local s = vgui.Create("DPanel", bar)
		s:Dock(LEFT)
		s:DockMargin(6, 6, 4, 6)
		s:SetWide(UI.S(1))
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
		l:SetWide(wide or (select(1, surface.GetTextSize(text)) + UI.S(2)))
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

	UI.GuideButton(bar, "sa_keys")
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
	-- SFM's play modes: once → loop → bounce (to the end and back)
	local MODES = { once = { "icon16/arrow_right.png", "play_once", "loop" }, loop = { "icon16/arrow_refresh.png", "play_loop", "bounce" },
		bounce = { "icon16/arrow_rotate_anticlockwise.png", "play_bounce", "once" } }
	local mode = UI.IconButton(bar, MODES.loop[1], L("sa_loop"), function() SA.SetPlayMode(MODES[SA.PlayMode()][3]) end,
		function() return SA.PlayMode() ~= "once" end)
	mode.Think = function(s)
		local m = SA.PlayMode()
		if s.SPMode ~= m then
			s.SPMode = m
			s.SPThemeKey = MODES[m][2]
			s:SetIcon(MODES[m][1])
			s:SetTooltip(L("sa_mode_" .. m))
		end
	end
	-- bookmarks (b0.2, SFM): a click marks the playhead's frame, a right click lists them
	local mark = UI.IconButton(bar, "icon16/flag_blue.png", L("sa_mark_tip"), function()
		local f = round(SA.frame)
		if SA.MarkAt(f) then SA.RemoveMark(f) else SA.AddMark(f) end
	end, function() return SA.MarkAt(round(SA.frame)) ~= nil end)
	mark.SPThemeKey = "bookmark"
	mark.DoRightClick = function() SA.MarkMenu(round(SA.frame)) end
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
	fps:SetWide(UI.S(52))
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
		local list = selList()
		if #list > 0 then
			SA.DeleteKeys(list)
			clearSel()
			return
		end
		-- no key is selected: the key of the selected object at the current frame is deleted
		local uid, f = SA.UID(C.selected), round(SA.frame)
		if SA.HasKey(uid, f) then SA.DeleteKey(uid, f) end
	end)
	UI.IconButton(bar, "icon16/bullet_red.png", L("sa_autokey"), function() SA.autokey = not SA.autokey end, function() return SA.autokey end)
	UI.IconButton(bar, "icon16/arrow_branch.png", L("sa_bone_keys"), function() SA.ToggleBoneKeys() end, function() return SA.BoneKeysOn() end)
	UI.IconButton(bar, "icon16/user_gray.png", L("sa_ghosts"), function() SA.ToggleGhosts() end, function() return SA.GhostsOn() end)
	UI.IconButton(bar, "icon16/time.png", L("sa_tsel_tip"), function() SA.TimeSelMenu(round(SA.frame)) end, function() return SA.timeSel ~= nil end)
	sep()
	UI.IconButton(bar, "icon16/user_go.png", L("sa_easy"), function() SA.EasyMenu() end)
	UI.IconButton(bar, "icon16/film_add.png", L("sa_import"), function() SA.OpenImport(C.selected) end)
	UI.IconButton(bar, "icon16/sound_add.png", L("sa_snd_add"), function() SA.OpenSounds() end)
	UI.IconButton(bar, "icon16/film_save.png", L("sa_render"), function() SA.OpenRender() end)
	-- the player (through the cameras; the camera is picked in the player) and walking around
	UI.IconButton(bar, "icon16/television.png", L("sa_show_player_tip"), function() SA.StartShow() end)
	UI.IconButton(bar, "icon16/eye.png", L("sa_show_eyes_tip"), function() SA.StartShow("eyes") end)
	UI.IconButton(bar, "icon16/webcam.png", L("sa_rec_title"), function() SA.OpenRecord() end)
	UI.IconButton(bar, "icon16/chart_curve.png", L("sa_crv_title"), function() SA.OpenCurves() end)
	UI.IconButton(bar, "icon16/heart.png", L("sa_proc_title"), function() SA.OpenProc(C.selected) end)
	UI.IconButton(bar, "icon16/arrow_switch.png", L("sa_smh_title"), function() SA.OpenSMH() end)
	-- "0": back to frame 0 with the whole animation in view (the timeline is endless, a0.9)
	local home = vgui.Create("DButton", bar)
	home:SetText("0")
	home:Dock(LEFT)
	home:DockMargin(2, 3, 2, 3)
	home:SetWide(UI.S(22))
	UI.StyleButton(home, nil, 3)
	home:SetTooltip(L("sa_tl_home"))
	home.DoClick = function() if SA.TimelineHome then SA.TimelineHome() end end

	-----------------------------------------------------------------
	-- Tracks
	-----------------------------------------------------------------
	local tl = vgui.Create("DPanel", page)
	tl:Dock(FILL)
	tl:SetMouseInputEnabled(true)
	local rows, rowsAt = {}, 0
	local scroll = 0
	local drag            -- { kind = "scrub" } | { kind = "keys", from, to, lo, hi, … } | { kind = "box", x0, y0, x1, y1 } | sound

	-- the row of a bone, under its object (bone keys): the keys that hold that bone
	local function boneRow(ent, uid, bone, keyedOnly)
		local parts = SA.BoneParts(ent, bone)
		if not parts then return end
		local keys = {}
		for _, k in ipairs(SA.tracks[uid] or {}) do
			if SA.KeyHasParts(k, parts) then
				-- the bone's own motion at that key, if it was given one (b0.2.5)
				local e
				for part in string.gmatch(parts, "[pb]%d+") do e = e or (k.pe and k.pe[part]) end
				keys[#keys + 1] = e and setmetatable({ e = e }, { __index = k }) or k
			end
		end
		-- shown when the mode is on, or when the track has bone keys at all
		local any = SA.BoneKeysOn()
		for _, k in ipairs(SA.tracks[uid] or {}) do
			if any then break end
			any = k.only ~= nil or k.skip ~= nil
		end
		if not any then return end
		if keyedOnly then
			-- a bone that is not selected shows only when it has keys of its own
			local own = false
			for _, k in ipairs(keys) do
				if k.only then own = true break end
			end
			if not own then return end
		end
		local name = string.gsub(ent:GetBoneName(bone) or "", "^ValveBiped%.Bip01_", "")
		rows[#rows + 1] = { uid = uid, ent = ent, parts = parts, bone = true, name = name, keys = keys }
	end

	-- (b0.2.5) the selected object shows a row for every bone with keys of its own, not only for
	-- the selected bone: the bone channels can be seen and edited side by side, as in SFM
	local function boneRows(ent, uid)
		if ent ~= C.selected then return end
		local own = SA.OwnParts(uid)
		local bones, seen = {}, {}
		if C.selBone >= 0 then
			bones[1] = C.selBone
			seen[C.selBone] = true
		end
		for kind, idx in string.gmatch(own or "", "([pb])(%d+)") do
			local b = tonumber(idx)
			if kind == "p" then b = ent:TranslatePhysBoneToBone(b) end
			if b and b >= 0 and not seen[b] then
				seen[b] = true
				bones[#bones + 1] = b
			end
		end
		if #bones > 1 then table.sort(bones, function(x, y)
			if x == y then return false end
			return x == C.selBone or (y ~= C.selBone and x < y)
		end) end
		for _, b in ipairs(bones) do boneRow(ent, uid, b, b ~= C.selBone) end
	end

	local function buildRows()
		rows = {}
		local seen = {}
		-- the film strip on top (a0.9, was "Cameras"): the shots of the camera cuts, or the
		-- whole animation as one shot; its menu cuts, trims and speeds up the time of the film
		rows[1] = { cutsRow = true, uid = -1e9, name = L("sa_cuts_row"), keys = {} }
		-- the FX clips under it (b0.2 round 6, cl_saeditor_fxclips.lua): titles, grain, colour
		-- clips that overlap in time go into lanes, one row each
		local _, nl = SA.ClipLanes()
		for lane = 1, nl do
			rows[#rows + 1] = { fxRow = true, lane = lane, uid = -1e9 + lane, name = lane == 1 and L("sa_fx_row") or "", keys = {} }
		end
		-- the rows of one object: its track, the selected bone, its face; always = a row even
		-- without keys (an object of a track, a selected object: a key can be set there)
		local function objectRows(ent, name, always, indent)
			local uid = SA.UID(ent)
			if uid == 0 or seen[uid] then return end
			local fid = SA.FaceTrack(uid)
			if not (always or SA.tracks[uid] or SA.tracks[fid]) then return end
			seen[uid] = true
			rows[#rows + 1] = { uid = uid, ent = ent, name = name, keys = SA.tracks[uid] or {}, indent = indent }
			boneRows(ent, uid)
			-- the face track goes right under its object
			if SA.tracks[fid] then
				rows[#rows + 1] = { uid = fid, owner = uid, face = true, ent = ent, name = L("sa_face_row"), keys = SA.tracks[fid], indent = indent }
			end
		end
		local objs = C.BuildEntityList()
		local nameOf = {}
		for _, obj in ipairs(objs) do nameOf[SA.UID(obj.ent)] = obj end
		-- the tracks (a0.9, SFM's track groups): a header row with all the keys of its objects,
		-- then the objects when it is open
		for gi, g in ipairs(SA.groups or {}) do
			local head = { groupRow = true, gi = gi, uid = -2e9 - gi, name = g.name, open = g.open, keys = {}, gkeys = {}, n = 0 }
			rows[#rows + 1] = head
			local frames = {}
			for _, u in ipairs(g.uids) do
				local obj = nameOf[u]
				if obj then
					head.n = head.n + 1
					for _, k in ipairs(SA.tracks[u] or {}) do frames[k.f] = true end
					for _, k in ipairs(SA.tracks[SA.FaceTrack(u)] or {}) do frames[k.f] = true end
					if g.open then objectRows(obj.ent, obj.name, true, 1) else seen[u] = true end
				end
			end
			for f in pairs(frames) do head.gkeys[#head.gkeys + 1] = f end
			table.sort(head.gkeys)
		end
		for _, obj in ipairs(objs) do objectRows(obj.ent, obj.name, false) end
		-- selected objects without keys get a row too: a key can be set here
		for _, e in ipairs(C.SelectionList()) do objectRows(e, C.DisplayName(e), true) end
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
	COMP:Hook("SAeditor_Changed", function() rowsAt = 0 end, "ui")
	COMP:Hook("SPeditor_Selected", function() rowsAt = 0 end, "ui")
	COMP:Hook("SPeditor_MultiChanged", function() rowsAt = 0 end, "ui")

	-- the visible part of the time: frames v0 … v0 + vlen (Ctrl + wheel zooms, Shift + wheel or the middle
	-- button scrolls); vlen = nil — the whole animation. Since a0.9 the view is endless, as in SFM:
	-- it goes before frame 0 and past the end (shaded there), the playhead too
	local v0, vlen = 0, nil
	local function viewLen() return vlen or SA.frames end
	local function clampView()
		if vlen then vlen = math.Clamp(vlen, 10, SA.MAX_FRAMES) end
		v0 = math.Clamp(v0, -SA.MAX_FRAMES, SA.MAX_FRAMES)
	end
	local function span(w) return math.max(w - NAME_W - PAD * 2, 10) end
	local function frameX(f, w) return NAME_W + PAD + (f - v0) * span(w) / viewLen() end
	local function frameAt(mx, w) return v0 + (mx - NAME_W - PAD) / span(w) * viewLen() end
	-- a frame inside the animation (cuts, time selection, menus of the rows)
	local function inAnim(f) return math.Clamp(f, 0, SA.frames) end
	-- time put in front of the animation: the view stays on the same moments
	COMP:Hook("SAeditor_TimeInserted", function(at, n)
		if at <= v0 then v0 = v0 + n end
		if not vlen then vlen = SA.frames - n end
	end, "timeline_view")
	-- The scroll bar of the time (b0.2.5): a strip along the bottom of the timeline, its thumb the
	-- part of the time in view — dragged, it scrolls (before, only Shift + wheel and the middle
	-- button did, and nobody found them); a click beside the thumb pages there.
	local function hbarH() return math.max(UI.S(7), 6) end
	local function hbarRange()
		local len = viewLen()
		local a, b = math.min(0, v0), math.max(SA.frames, v0 + len)
		return a, b, len
	end
	local function hbarThumb(w)
		local a, b, len = hbarRange()
		local x0, bw = NAME_W, math.max(w - NAME_W, 10)
		local tx = x0 + (v0 - a) / (b - a) * bw
		local tw = math.max(len / (b - a) * bw, 16)
		return tx, tw, x0, bw
	end
	local function drawHBar(w, h)
		local y, bh = h - hbarH(), hbarH()
		local tx, tw, x0, bw = hbarThumb(w)
		surface.SetDrawColor(0, 0, 0, 90)
		surface.DrawRect(x0, y, bw, bh)
		local hot = drag and drag.kind == "hbar"
		surface.SetDrawColor(hot and COL.ORANGE or COL.BORDER)
		surface.DrawRect(tx, y + 1, tw, bh - 2)
	end
	-- "0" (a0.9): to frame 0 with the whole animation in view
	SA.TimelineHome = function()
		v0, vlen = 0, nil
		SA.Seek(0)
	end
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
	local matFx = Material("icon16/film_add.png")
	local matCam = Material("icon16/camera.png")
	-- the cut mark under the cursor (the "Cameras" row)
	local function cutAt(mx, w)
		for _, c in ipairs(SA.cuts) do
			if math.abs(frameX(c.f, w) - mx) <= 6 then return c end
		end
	end
	local CUT_COLORS = { Color(70, 120, 200), Color(190, 110, 50), Color(80, 160, 90), Color(160, 80, 170), Color(170, 150, 60), Color(60, 150, 160) }
	local matFace = Material("icon16/emoticon_smile.png")
	local matGroup = Material("icon16/folder_table.png")
	local matOpen, matShut = Material("icon16/bullet_toggle_minus.png"), Material("icon16/bullet_toggle_plus.png")

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
		if (SA.playing or SA.rendering) and (SA.frame < v0 or SA.frame > v0 + viewLen()) then
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
		local vEnd = v0 + viewLen() + tick
		clip(true)
		-- outside the animation: before frame 0 and past its end, a darker band
		local xa, xb = frameX(0, w), frameX(SA.frames, w)
		surface.SetDrawColor(0, 0, 0, 70)
		if xa > NAME_W then surface.DrawRect(NAME_W, 0, xa - NAME_W, h) end
		if xb < w then surface.DrawRect(xb, 0, w - xb, h) end
		surface.SetDrawColor(COL.ACCENT or COL.DIM)
		if xa > NAME_W and xa < w then surface.DrawRect(xa, 0, 1, h) end
		if xb > NAME_W and xb < w then surface.DrawRect(xb, 0, 1, h) end
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
		draw.SimpleText(string.format("%d %s", SA.fps, L("sa_fps")) .. (vlen and string.format("   ×%.2g", SA.frames / vlen) or ""),
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
				local is = UI.IconSize(ROW_H + 2)
				surface.DrawTexturedRect(8, y + math.floor((ROW_H - is) / 2), is, is)
			end
			if row.cutsRow then
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(matCam)
				local is = UI.IconSize(ROW_H + 2)
				surface.DrawTexturedRect(6, y + math.floor((ROW_H - is) / 2), is, is)
				draw.SimpleText(row.name, "SPeditor.Small", 10 + is, y + ROW_H / 2, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				clip(true)
				if #SA.cuts == 0 then
					-- one shot: the whole animation
					local x0, x1 = frameX(0, w), frameX(SA.frames, w)
					surface.SetDrawColor(110, 110, 110, 110)
					surface.DrawRect(x0, y + 2, x1 - x0, ROW_H - 4)
					draw.SimpleText(L("sa_cuts_empty") .. "  ·  " .. string.format("%.1f %s", SA.frames / SA.fps, L("sa_snd_sec")),
						"SPeditor.Small", math.max(x0, NAME_W) + PAD, y + ROW_H / 2, COL.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
				-- a band for every shot: from its cut to the next one, named after its camera
				local list = {}
				for _, c in ipairs(SA.cuts) do
					local f = (drag and drag.kind == "cut" and drag.from == c.f) and drag.to or c.f
					list[#list + 1] = { f = f, uid = c.uid }
				end
				table.sort(list, function(a, b) return a.f < b.f end)
				local cams = SA.SceneCameras()
				for i, c in ipairs(list) do
					local x0 = (i == 1) and frameX(0, w) or frameX(c.f, w)
					local x1 = list[i + 1] and frameX(list[i + 1].f, w) or frameX(SA.frames, w)
					local cam = SA.EntByUID(c.uid)
					local ci = 1
					for j, e in ipairs(cams) do if e == cam then ci = j end end
					local col = CUT_COLORS[(ci - 1) % #CUT_COLORS + 1]
					surface.SetDrawColor(col.r, col.g, col.b, i == 1 and c.f > 0 and 90 or 170)
					surface.DrawRect(x0, y + 2, x1 - x0, ROW_H - 4)
					local mx = frameX(c.f, w)
					surface.SetDrawColor(COL.TEXT)
					surface.DrawRect(mx, y, 2, ROW_H)
					local nextF = list[i + 1] and list[i + 1].f or SA.frames
					local dur = string.format("  %.1f %s", (nextF - (i == 1 and 0 or c.f)) / SA.fps, L("sa_snd_sec"))
					draw.SimpleText((IsValid(cam) and C.DisplayName(cam) or "?") .. dur, "SPeditor.Small", mx + 5, y + ROW_H / 2, color_white,
						TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
				clip(false)
			elseif row.fxRow then
				local is = UI.IconSize(ROW_H + 2)
				if row.lane == 1 then
					surface.SetDrawColor(255, 255, 255, 255)
					surface.SetMaterial(matFx)
					surface.DrawTexturedRect(6, y + math.floor((ROW_H - is) / 2), is, is)
				end
				draw.SimpleText(row.name, "SPeditor.Small", 10 + is, y + ROW_H / 2, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				clip(true)
				if #SA.fxClips == 0 and row.lane == 1 then
					draw.SimpleText(L("sa_fx_empty"), "SPeditor.Small", math.max(frameX(0, w), NAME_W) + PAD, y + ROW_H / 2, COL.DIM,
						TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
				local lanes = SA.ClipLanes()
				local lh = ROW_H - 4
				for ci, c in ipairs(SA.fxClips) do
				if lanes[ci] == row.lane then
					local a, b = c.a, c.b
					local ly = y + 2
					-- a clip being dragged is drawn where it is going
					if drag and drag.kind == "clip" and drag.i == ci then a, b = drag.a, drag.b end
					local x0, x1 = frameX(a, w), frameX(b, w)
					local col = SA.CLIP_COLORS[c.k] or COL.BLUE
					local held = drag and drag.kind == "clip" and drag.i == ci
					surface.SetDrawColor(col.r, col.g, col.b, held and 230 or 170)
					surface.DrawRect(x0, ly, x1 - x0, lh)
					surface.SetDrawColor(held and COL.ORANGE or color_black)
					surface.DrawOutlinedRect(x0, ly, x1 - x0, lh)
					-- the fades: a slope up from the bottom corner, as on the sound clips
					local pxf = (x1 - x0) / math.max(b - a, 1)
					surface.SetDrawColor(255, 255, 255, 200)
					if (c.fi or 0) > 0 then surface.DrawLine(x0, ly + lh - 1, x0 + c.fi * pxf, ly + 1) end
					if (c.fo or 0) > 0 then surface.DrawLine(x1, ly + lh - 1, x1 - c.fo * pxf, ly + 1) end
					draw.SimpleText(SA.ClipLabel(c), "SPeditor.Small", x0 + 5, ly + lh / 2, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				end
				end
				clip(false)
			elseif row.sounds then
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(matSound)
				local is = UI.IconSize(ROW_H + 2)
				surface.DrawTexturedRect(6, y + math.floor((ROW_H - is) / 2), is, is)
				draw.SimpleText(row.name, "SPeditor.Small", 10 + is, y + ROW_H / 2, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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
			elseif row.groupRow then
				-- a track: the fold arrow, its name and the keys of all its objects
				surface.SetDrawColor(COL.HEADER or COL.ROW_A)
				surface.DrawRect(0, y, w, ROW_H)
				surface.SetDrawColor(255, 255, 255, 255)
				local is = UI.IconSize(ROW_H + 2)
				surface.SetMaterial(row.open and matOpen or matShut)
				surface.DrawTexturedRect(2, y + math.floor((ROW_H - is) / 2), is, is)
				surface.SetMaterial(matGroup)
				surface.DrawTexturedRect(2 + is, y + math.floor((ROW_H - is) / 2), is, is)
				draw.SimpleText(row.name .. "  (" .. row.n .. ")", "SPeditor.Bold", 6 + is * 2, y + ROW_H / 2, COL.ORANGE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
				clip(true)
				local cy = y + ROW_H / 2
				if #row.gkeys > 1 then
					surface.SetDrawColor(COL.BORDER)
					surface.DrawRect(frameX(row.gkeys[1], w), cy - 1, frameX(row.gkeys[#row.gkeys], w) - frameX(row.gkeys[1], w), 2)
				end
				local lastX = -100
				for _, f in ipairs(row.gkeys) do
					local x = frameX(f, w)
					if x - lastX >= 3 then
						surface.SetDrawColor(COL.DIM)
						surface.DrawRect(x - 1, cy - 4, 2, 9)
						lastX = x
					end
				end
				clip(false)
			elseif row.bone then
				-- a bone of the object above
				surface.SetDrawColor(COL.DIM)
				surface.DrawRect(12, y + 2, 1, ROW_H / 2 - 2)
				surface.DrawRect(12, y + ROW_H / 2, 8, 1)
				draw.SimpleText(row.name, "SPeditor.Small", 24, y + ROW_H / 2, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			else
				local ind = row.indent and UI.S(14) or 0
				if ind > 0 then
					-- an object of the track above
					surface.SetDrawColor(COL.BORDER)
					surface.DrawRect(8, y, 1, ROW_H)
				end
				draw.SimpleText(row.name, "SPeditor.Small", (row.face and 28 or 8) + ind, y + ROW_H / 2, #row.keys > 0 and COL.TEXT or COL.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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
				local selected = isSel(row.uid, k.f, row.parts)
				local dragged = selected and drag and drag.kind == "keys" and drag.to ~= drag.from
				if dragged then f = f + drag.to - drag.from end
				local x = frameX(f, w)
				local col = (selected or dragged) and COL.ORANGE or (k.e == "linear" and COL.TIMECODE or COL.TEXT)
				local nxt = keys[n + 1]
				if selected or dragged or (x - lastX >= 9 and (not nxt or frameX(nxt.f, w) - x >= 9)) then
					-- a key of some bones only (bone keys): a smaller, hollow diamond on the object's row
					local part = k.only and not row.bone
					diamond(x, cy, part and 4 or 5, color_black)
					diamond(x, cy, part and 3 or 4, col)
					if part then diamond(x, cy, 1.5, color_black) end
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

		-- the time selection: tinted over the rows as strongly as an edit counts there, its
		-- weight drawn as a curve on the frame numbers, its four edges as handles
		local ts = SA.timeSel
		if ts then
			if ts[4] > SA.frames then SA.SetTimeSel({ ts[1], ts[2], ts[3], ts[4], shape = ts.shape, noMarks = true }) ts = SA.timeSel end
		end
		if ts then
			clip(true)
			local c = COL.BLUE
			local xa, xb = math.max(frameX(ts[1], w), NAME_W), math.min(frameX(ts[4], w), w)
			local step = 2
			local poly = { { x = xa, y = RULER_H } }
			for x = xa, xb, step do
				local wt = SA.TimeSelWeight(frameAt(x, w), ts)
				surface.SetDrawColor(c.r, c.g, c.b, 45 * wt)
				surface.DrawRect(x, RULER_H, step, h - RULER_H)
				poly[#poly + 1] = { x = x, y = RULER_H - 1 - wt * (RULER_H - 3) }
			end
			surface.SetDrawColor(c.r, c.g, c.b, 230)
			for i = 2, #poly - 1 do surface.DrawLine(poly[i].x, poly[i].y, poly[i + 1].x, poly[i + 1].y) end
			for i = 1, 4 do
				local x = frameX(ts[i], w)
				surface.SetDrawColor((i == 2 or i == 3) and COL.TEXT or c)
				surface.DrawRect(x, 0, 1, RULER_H)
				surface.DrawRect(x - 2, (i == 2 or i == 3) and 0 or RULER_H - 3, 5, 3)
			end
			clip(false)
		end

		-- bookmarks (b0.2): a flag on the ruler with its name, a faint line down the rows
		if #SA.marks > 0 then
			clip(true)
			local flag = UI.Theme and UI.Theme.id == "speditor" and markMat
			for _, mk in ipairs(SA.marks) do
				local f = (drag and drag.kind == "mark" and drag.from == mk.f) and drag.to or mk.f
				local x = frameX(f, w)
				if x >= NAME_W - 8 and x <= w + 8 then
					surface.SetDrawColor(COL.BLUE.r, COL.BLUE.g, COL.BLUE.b, 50)
					surface.DrawRect(x, RULER_H, 1, h - RULER_H)
					if flag then
						surface.SetMaterial(flag)
						surface.SetDrawColor(255, 255, 255, 255)
						surface.DrawTexturedRect(x - 3, RULER_H - 16, 7, 16)
					else
						draw.NoTexture()
						surface.SetDrawColor(COL.BLUE)
						surface.DrawPoly({ { x = x - 4, y = RULER_H - 11 }, { x = x + 5, y = RULER_H - 11 }, { x = x + 5, y = RULER_H - 4 }, { x = x + 0.5, y = RULER_H }, { x = x - 4, y = RULER_H - 4 } })
					end
					if mk.name ~= "" then
						draw.SimpleText(mk.name, "SPeditor.Small", x + 7, RULER_H - 7, COL.BLUE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
					end
				end
			end
			clip(false)
		end

		-- playhead
		clip(true)
		local px = frameX(SA.frame, w)
		surface.SetDrawColor(COL.ORANGE)
		surface.DrawRect(px, 0, 1, h)
		if UI.Theme and UI.Theme.id == "speditor" and not headMat:IsError() then
			-- GM:FM UI: SFM's own playhead
			surface.SetMaterial(headMat)
			surface.SetDrawColor(255, 255, 255, 255)
			surface.DrawTexturedRect(px - 5, 0, 11, 16)
		else
			draw.NoTexture()
			surface.DrawPoly({ { x = px - 5, y = 0 }, { x = px + 6, y = 0 }, { x = px + 6, y = 7 }, { x = px + 0.5, y = 13 }, { x = px - 5, y = 7 } })
		end
		clip(false)

		-- the box of a Shift+drag selection
		if drag and drag.kind == "box" then
			local x, y = math.min(drag.x0, drag.x1), math.min(drag.y0, drag.y1)
			local bw, bh = math.abs(drag.x1 - drag.x0), math.abs(drag.y1 - drag.y0)
			surface.SetDrawColor(COL.ORANGE.r, COL.ORANGE.g, COL.ORANGE.b, 40)
			surface.DrawRect(x, y, bw, bh)
			surface.SetDrawColor(COL.ORANGE)
			surface.DrawOutlinedRect(x, y, bw, bh)
		end

		drawHBar(w, h)
		if SA.rendering then
			local job = SA.rendering
			draw.SimpleTextOutlined(string.format(L("sa_rnd_progress"), SA.RenderProgress(job)), "SPeditor.Bold",
				w - 10, h - 12, COL.ORANGE, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER, 1, color_black)
		end
	end

	-- the menu of a key; a key of a selection of several speaks for all of them
	local function keyMenu(row, k)
		local list = isSel(row.uid, k.f, row.parts) and selList() or {}
		if #list < 2 then list = { { uid = row.uid, f = k.f, parts = row.parts } } end
		local many = #list > 1
		local m = UI.Menu()
		if many then
			m:AddOption(string.format(L("sa_keys_n"), #list)):SetEnabled(false)
			m:AddSpacer()
		end
		local em = m:AddSubMenu(L("sa_ease"))
		for _, e in ipairs(SA.EASES) do
			em:AddOption(L("sa_ease_" .. e), function() SA.SetEaseMany(list, e) end):SetChecked(not many and k.e == e)
		end
		m:AddOption(L(many and "sa_copy_keys" or "sa_copy_key"), function() SA.keyClip = list end):SetIcon("icon16/page_copy.png")
		m:AddSpacer()
		m:AddOption(L(row.bone and "sa_bone_key_delete" or (many and "sa_keys_delete" or "sa_key_delete")), function()
			SA.DeleteKeys(list)
			clearSel()
		end):SetIcon("icon16/key_delete.png")
		m:Open()
	end

	-- the tracks an object (with the other selected ones) can be put in
	local function trackMenu(m, ent)
		local ents = C.SelectionList()
		if not table.HasValue(ents, ent) then ents = { ent } end
		m:AddSpacer()
		local sub, o = m:AddSubMenu(L("sa_grp_menu"))
		if o and o.SetIcon then o:SetIcon("icon16/folder_table.png") end
		sub:AddOption(L("sa_grp_new_with"), function()
			Derma_StringRequest(L("sa_grp_new"), L("enter_name"), string.format(L("sa_grp_default"), #SA.groups + 1), function(name)
				SA.NewGroup(string.Trim(name), ents)
			end)
		end):SetIcon("icon16/folder_add.png")
		local cur = SA.GroupOf(SA.UID(ent))
		if #SA.groups > 0 then sub:AddSpacer() end
		for gi, g in ipairs(SA.groups) do
			local opt = sub:AddOption(g.name, function() SA.MoveToGroup(gi, ents) end)
			opt:SetIcon("icon16/folder_go.png")
			if opt.SetChecked then opt:SetChecked(cur == gi) end
		end
		if cur then
			sub:AddSpacer()
			sub:AddOption(L("sa_grp_leave"), function() SA.UngroupEnts(ents) end):SetIcon("icon16/folder_delete.png")
		end
	end

	-- the menu of a track's header
	local function groupMenu(row)
		local gi, g = row.gi, SA.groups[row.gi]
		if not g then return end
		local m = UI.Menu()
		m:AddOption(L(g.open and "sa_grp_fold" or "sa_grp_unfold"), function() SA.ToggleGroup(gi) end)
			:SetIcon(g.open and "icon16/bullet_arrow_up.png" or "icon16/bullet_arrow_down.png")
		m:AddOption(L("sa_grp_select"), function()
			local first = true
			for _, u in ipairs(g.uids) do
				local e = SA.EntByUID(u)
				if IsValid(e) then
					if first then C.Select(e, -1) first = false else C.multi[#C.multi + 1] = e end
				end
			end
			hook.Run("SPeditor_MultiChanged")
		end):SetIcon("icon16/table_multiple.png")
		local sel = C.SelectionList()
		if #sel > 0 then
			m:AddOption(string.format(L("sa_grp_add_sel"), #sel), function() SA.MoveToGroup(gi, sel) end):SetIcon("icon16/folder_add.png")
		end
		m:AddSpacer()
		m:AddOption(L("sa_grp_rename"), function()
			Derma_StringRequest(L("sa_grp_rename"), L("enter_name"), g.name, function(name) SA.RenameGroup(gi, string.Trim(name)) end)
		end):SetIcon("icon16/textfield_rename.png")
		if gi > 1 then m:AddOption(L("sa_grp_up"), function() SA.MoveGroup(gi, -1) end):SetIcon("icon16/arrow_up.png") end
		if gi < #SA.groups then m:AddOption(L("sa_grp_down"), function() SA.MoveGroup(gi, 1) end):SetIcon("icon16/arrow_down.png") end
		m:AddOption(L("sa_grp_new"), function()
			Derma_StringRequest(L("sa_grp_new"), L("enter_name"), string.format(L("sa_grp_default"), #SA.groups + 1), function(name)
				SA.NewGroup(string.Trim(name), {})
			end)
		end):SetIcon("icon16/folder_add.png")
		m:AddSpacer()
		m:AddOption(L("sa_grp_delete"), function() SA.DeleteGroup(gi) end):SetIcon("icon16/folder_delete.png")
		m:Open()
	end

	local function rowMenu(row, frame)
		local m = UI.Menu()
		m:AddOption(L(row.bone and "sa_bone_key_here" or "sa_key_here") .. "  (" .. frame .. ")", function()
			if not IsValid(row.ent) then return end
			if row.face then SA.SetFaceKey({ row.ent }, frame) else SA.SetKey({ row.ent }, frame, nil, row.parts) end
		end):SetIcon("icon16/key_add.png")
		-- the face of a body row: its own keys
		if not row.face and not row.bone and IsValid(row.ent) and not C.IsAux(row.ent) and row.ent:GetFlexNum() > 0 and not SA.HasFaceTrack(row.ent) then
			m:AddOption(L("sa_face_start") .. "  (" .. frame .. ")", function() SA.SetFaceKey({ row.ent }, frame) end):SetIcon("icon16/emoticon_smile.png")
		end
		-- copied keys go back onto their own tracks, the first of them at this frame
		local clip = {}
		for _, c in ipairs(SA.keyClip or {}) do
			if SA.HasKey(c.uid, c.f) then clip[#clip + 1] = c end
		end
		if #clip > 0 then
			local first = clip[1].f
			for _, c in ipairs(clip) do first = math.min(first, c.f) end
			local text = #clip == 1 and (L("sa_paste_key") .. "  (" .. first .. " → " .. frame .. ")")
				or (string.format(L("sa_paste_keys"), #clip) .. "  (" .. first .. " → " .. frame .. ")")
			m:AddOption(text, function() SA.MoveKeys(clip, frame - first, true) end):SetIcon("icon16/page_paste.png")
		end
		if #row.keys > 0 and row.bone then
			m:AddSpacer()
			m:AddOption(L("sa_bone_clear"), function()
				local list = {}
				for _, k in ipairs(row.keys) do list[#list + 1] = { uid = row.uid, f = k.f, parts = row.parts } end
				SA.DeleteKeys(list)
			end):SetIcon("icon16/cross.png")
		elseif #row.keys > 0 then
			m:AddSpacer()
			m:AddOption(L(row.face and "sa_face_clear" or "sa_clear_track"), function() SA.ClearTrack(row.uid) end):SetIcon("icon16/cross.png")
		end
		if not row.face and not row.bone and IsValid(row.ent) then trackMenu(m, row.ent) end
		m:Open()
	end

	local function soundMenu(c)
		local m = UI.Menu()
		m:AddOption(L("sa_snd_m_listen"), function() SA.ListenSound(c.path) end):SetIcon("icon16/control_play_blue.png")
		-- another file in the same place: the trimming belongs to the old file and is dropped
		m:AddOption(L("sa_snd_m_replace"), function()
			UI.PickSound({ title = L("sa_snd_m_replace"), current = c.path, onPick = function(path)
				if path ~= "" and path ~= c.path then SA.ChangeSound(c.id, { path = path, cin = 0, cout = 0 }) end
			end })
		end):SetIcon("icon16/folder_explore.png")
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
		-- lip sync (cl_saeditor_lipsync.lua): the speaker first, then the selected object, then the rest
		do
			local who, seen = {}, {}
			local function add(e, label)
				local uid = SA.UID(e)
				if uid == 0 or seen[uid] or not SA.MouthMap(e) then return end
				seen[uid] = true
				who[#who + 1] = { e = e, label = label }
			end
			local speaker = c.uid ~= 0 and SA.EntByUID(c.uid) or nil
			if IsValid(speaker) then add(speaker, C.DisplayName(speaker)) end
			if IsValid(C.selected) then add(C.selected, C.DisplayName(C.selected)) end
			for _, obj in ipairs(C.BuildEntityList()) do
				if IsValid(obj.ent) then add(obj.ent, obj.name) end
			end
			local lm, lo = m:AddSubMenu(L("sa_lip_menu"))
			if lo and lo.SetIcon then lo:SetIcon("icon16/comments.png") end
			if #who == 0 then
				lm:AddOption(L("sa_lip_nobody")):SetEnabled(false)
			end
			for i, t in ipairs(who) do
				lm:AddOption(string.format(L("sa_lip_for"), t.label), function() SA.LipSync(c, t.e) end):SetIcon(i == 1 and "icon16/user_comment.png" or "icon16/user.png")
			end
			lm:AddSpacer()
			local sm = lm:AddSubMenu(L("sa_lip_strength"))
			local cur = GetConVar("gmfm_lip_strength"):GetFloat()
			for _, v in ipairs({ 50, 75, 100, 125, 150, 200 }) do
				sm:AddOption(v .. "%", function() RunConsoleCommand("gmfm_lip_strength", tostring(v / 100)) end):SetChecked(math.abs(cur - v / 100) < 0.01)
			end
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

	-- the menu of the "Cameras" row: a cut mark, or a new cut at frame
	-- the shot of the film at frame f: its first frame and the first frame after it
	local function shotAt(f)
		local s0, s1 = 0, SA.frames
		for i, c in ipairs(SA.cuts) do
			if c.f <= f and i > 1 then s0 = c.f end
			if c.f > f then s1 = c.f break end
		end
		return s0, s1
	end
	-- the film part of the strip's menu (a0.9, SFM's clip editor): time, not cameras
	local function filmMenu(m, frame)
		local s0, s1 = shotAt(frame)
		local fps = SA.fps
		local ph = math.floor(SA.frame + 0.5)
		m:AddOption(string.format(L("sa_film_head"), s0, s1, (s1 - s0) / fps)):SetEnabled(false)
		-- a split needs a camera for the new shot: the one of this shot, else the first of the scene
		local cam = SA.CameraAt(ph) or SA.SceneCameras()[1]
		local split = m:AddOption(L("sa_film_split"), function() SA.AddCut(ph, cam) end)
		split:SetIcon("icon16/cut.png")
		split:SetEnabled(IsValid(cam) and ph > 0 and ph < SA.frames)
		m:AddOption(L("sa_film_delete"), function() SA.CutTime(s0, s1 - s0) end):SetIcon("icon16/cut_red.png")
		if ph > s0 and ph < s1 then
			m:AddOption(L("sa_film_trim_in"), function() SA.CutTime(s0, ph - s0) end):SetIcon("icon16/control_start.png")
			m:AddOption(L("sa_film_trim_out"), function() SA.CutTime(ph, s1 - ph) end):SetIcon("icon16/control_end.png")
		end
		local sp, so = m:AddSubMenu(L("sa_film_speed"))
		if so and so.SetIcon then so:SetIcon("icon16/time.png") end
		for _, k in ipairs({ 0.25, 0.5, 0.75, 1.5, 2, 4 }) do
			sp:AddOption(string.format("×%s  (%.1f %s)", tostring(k), (s1 - s0) / k / fps, L("sa_snd_sec")), function() SA.SpeedRange(s0, s1, k) end)
		end
		local ins, io = m:AddSubMenu(L("sa_film_insert"))
		if io and io.SetIcon then io:SetIcon("icon16/time_add.png") end
		for _, sec in ipairs({ 0.5, 1, 2, 5 }) do
			ins:AddOption(string.format("%s %s", tostring(sec), L("sa_snd_sec")), function() SA.InsertTime(ph, math.floor(sec * fps + 0.5)) end)
		end
		-- a new track under the film strip, with the selected objects in it
		local sel = C.SelectionList()
		m:AddOption(#sel > 0 and string.format(L("sa_grp_new_sel"), #sel) or L("sa_grp_new"), function()
			Derma_StringRequest(L("sa_grp_new"), L("enter_name"), string.format(L("sa_grp_default"), #SA.groups + 1), function(name)
				SA.NewGroup(string.Trim(name), sel)
			end)
		end):SetIcon("icon16/folder_add.png")
		m:AddSpacer()
	end

	local function cutMenu(c, frame)
		local m = UI.Menu()
		filmMenu(m, frame)
		local cams = SA.SceneCameras()
		if #cams == 0 then m:AddOption(L("sa_cuts_nocam")):SetEnabled(false) end
		if c then
			local sub = m:AddSubMenu(L("sa_cuts_change"))
			for _, e in ipairs(cams) do
				sub:AddOption(C.DisplayName(e), function() SA.AddCut(c.f, e) end):SetChecked(SA.UID(e) == c.uid)
			end
			m:AddOption(L("sa_cuts_go"), function() SA.Seek(c.f) end):SetIcon("icon16/arrow_right.png")
			m:AddSpacer()
			m:AddOption(L("sa_cuts_delete"), function() SA.RemoveCut(c.f) end):SetIcon("icon16/cross.png")
		else
			for _, e in ipairs(cams) do
				m:AddOption(string.format(L("sa_cuts_here"), C.DisplayName(e), frame), function() SA.AddCut(frame, e) end):SetIcon("icon16/camera_go.png")
			end
		end
		-- b0.2: the shot list as text (SFM's Export Shot List)
		m:AddSpacer()
		m:AddOption(L("sa_shots_export"), function() SA.ExportShotList() end):SetIcon("icon16/page_white_text.png")
		m:Open()
	end

	-- the edges of the time selection under the cursor on the frame numbers: their indices
	-- (two or more when they stand together: the drag direction picks one)
	local function tselEdges(mx, w)
		local ts = SA.timeSel
		if not ts then return nil end
		local out
		for i = 1, 4 do
			if math.abs(frameX(ts[i], w) - mx) <= 5 then
				out = out or {}
				out[#out + 1] = i
			end
		end
		return out
	end

	-- the bookmark under the mouse on the ruler (5 px either way)
	local function markAt(mx, w)
		local best, bd
		for _, mk in ipairs(SA.marks) do
			local d = math.abs(frameX(mk.f, w) - mx)
			if d <= 5 and (not bd or d < bd) then best, bd = mk, d end
		end
		return best
	end

	tl.OnMousePressed = function(s, code)
		local mx, my = s:CursorPos()
		local w = s:GetWide()
		-- the scroll bar along the bottom
		if code == MOUSE_LEFT and mx >= NAME_W and my >= s:GetTall() - hbarH() - 2 then
			local tx, tw, _, bw = hbarThumb(w)
			local a, b = hbarRange()
			vlen = viewLen()
			if mx < tx or mx > tx + tw then
				-- beside the thumb: the thumb's middle jumps there
				v0 = a + (mx - NAME_W) / bw * (b - a) - vlen / 2
				clampView()
			end
			drag = { kind = "hbar", mx = mx, v0 = v0, per = (b - a) / bw }
			s:MouseCapture(true)
			return
		end
		-- the middle button drags the view along the time
		if code == MOUSE_MIDDLE and mx >= NAME_W then
			drag = { kind = "pan", mx = mx, v0 = v0 }
			vlen = viewLen()
			s:MouseCapture(true)
			return
		end
		if my < RULER_H and mx >= NAME_W and not SA.rendering then
			local mk = markAt(mx, w)
			if code == MOUSE_RIGHT then
				if mk then SA.MarkMenu(mk.f) else SA.TimeSelMenu(round(inAnim(frameAt(mx, w)))) end
				return
			end
			-- a bookmark: a click goes to it, a drag moves it
			if code == MOUSE_LEFT and mk and not (input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)) then
				drag = { kind = "mark", from = mk.f, to = mk.f }
				s:MouseCapture(true)
				return
			end
			local edges = code == MOUSE_LEFT and tselEdges(mx, w)
			local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
			if edges then
				drag = { kind = "tsel", edges = edges, from = frameAt(mx, w) }
				s:MouseCapture(true)
				return
			elseif code == MOUSE_LEFT and shift then
				drag = { kind = "tselnew", from = round(inAnim(frameAt(mx, w))) }
				s:MouseCapture(true)
				return
			end
		end
		local row = rowAt(my)
		if row and row.cutsRow and mx >= NAME_W then
			local c = cutAt(mx, w)
			if code == MOUSE_RIGHT then
				cutMenu(c, round(inAnim(frameAt(mx, w))))
				return
			end
			if code == MOUSE_LEFT and c and not SA.rendering then
				-- Alt + drag: the time at the cut grows or shrinks (what is after moves), the
				-- shots before it get longer or shorter — as trimming a clip in SFM
				drag = { kind = "cut", from = c.f, to = c.f, ripple = input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT) }
				s:MouseCapture(true)
				return
			end
		elseif row and row.cutsRow then
			if code == MOUSE_RIGHT then cutMenu(nil, round(SA.frame)) end
			return
		end
		-- the FX row: a right click — the menu; a press on a clip — move it, or near its ends —
		-- make it longer or shorter; a double click — its parameters
		if row and row.fxRow then
			if mx < NAME_W then
				if code == MOUSE_RIGHT then SA.ClipMenu(nil, round(SA.frame)) end
				return
			end
			local fAt = frameAt(mx, w)
			local ci, c = SA.ClipAt(round(inAnim(fAt)), row.lane)
			if code == MOUSE_RIGHT then
				SA.ClipMenu(ci, round(inAnim(fAt)))
				return
			end
			if code == MOUSE_LEFT and c then
				if s.SPLastClip == ci and RealTime() - (s.SPLastClipT or 0) < 0.35 then
					s.SPLastClip = nil
					SA.OpenClip(ci)
					return
				end
				s.SPLastClip, s.SPLastClipT = ci, RealTime()
				local x0, x1 = frameX(c.a, w), frameX(c.b, w)
				local mode = (math.abs(mx - x0) <= 5) and "a" or ((math.abs(mx - x1) <= 5) and "b" or "move")
				drag = { kind = "clip", i = ci, mode = mode, from = round(fAt), a = c.a, b = c.b }
				s:MouseCapture(true)
			end
			return
		end
		if row and row.groupRow then
			if code == MOUSE_RIGHT then groupMenu(row) return end
			if code == MOUSE_LEFT and mx < NAME_W then
				-- the arrow folds; a double click on the name renames
				if mx < UI.IconSize(ROW_H + 2) + 4 then
					SA.ToggleGroup(row.gi)
				elseif s.SPLastGroup == row.gi and RealTime() - (s.SPLastGroupT or 0) < 0.35 then
					local g = SA.groups[row.gi]
					if g then
						Derma_StringRequest(L("sa_grp_rename"), L("enter_name"), g.name, function(name) SA.RenameGroup(row.gi, string.Trim(name)) end)
					end
				end
				s.SPLastGroup, s.SPLastGroupT = row.gi, RealTime()
				return
			end
		end
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
				clearSel()
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
		local ctrl = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
		local shift = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
		if k then
			-- a key outside the selection: it alone is selected (with Ctrl it joins the
			-- selection); a key of the selection drags all of it
			local was = isSel(row.uid, k.f, row.parts)
			if not was and not ctrl then clearSel() end
			setSel(row.uid, k.f, true, row.parts)
			if IsValid(row.ent) and C.selected ~= row.ent then C.Select(row.ent, -1) end
			SA.Seek(k.f)
			local lo, hi = SA.frames, 0
			for _, sk in ipairs(selList()) do lo, hi = math.min(lo, sk.f), math.max(hi, sk.f) end
			drag = { kind = "keys", uid = row.uid, parts = row.parts, key = k.f, from = k.f, to = k.f, lo = lo, hi = hi, was = was, ctrl = ctrl }
		elseif shift then
			drag = { kind = "box", x0 = mx, y0 = my, x1 = mx, y1 = my, add = ctrl }
		else
			clearSel()
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
			if not edge and my < RULER_H and mx >= NAME_W then edge = tselEdges(mx, s:GetWide()) end
			s:SetCursor(edge and "sizewe" or "arrow")
			return
		end
		local f = round(frameAt(mx, s:GetWide()))
		if drag.kind == "pan" then
			v0 = drag.v0 - (mx - drag.mx) / span(s:GetWide()) * viewLen()
			clampView()
			return
		end
		if drag.kind == "hbar" then
			v0 = drag.v0 + (mx - drag.mx) * drag.per
			clampView()
			return
		end
		if drag.kind ~= "scrub" then f = inAnim(f) end
		if drag.kind == "clip" then
			local c = SA.fxClips[drag.i]
			if not c then return end
			local d = f - drag.from
			if drag.mode == "move" then
				d = math.Clamp(d, -c.a, SA.frames - c.b)
				drag.a, drag.b = c.a + d, c.b + d
			elseif drag.mode == "a" then
				drag.a = math.Clamp(c.a + d, 0, c.b - 1)
			else
				drag.b = math.Clamp(c.b + d, c.a + 1, SA.frames)
			end
			return
		end
		if drag.kind == "tselnew" then
			if f ~= drag.from or drag.moved then
				drag.moved = true
				local a, b = math.min(f, drag.from), math.max(f, drag.from)
				SA.SetTimeSel({ a, a, b, b })
			end
			return
		elseif drag.kind == "tsel" then
			local ts = SA.timeSel
			if not ts then return end
			local edges = drag.edges
			if #edges > 1 then
				-- edges standing together: moving left takes the leftmost, right the rightmost
				local fx = frameAt(mx, s:GetWide())
				if math.abs(fx - drag.from) < 0.5 then return end
				edges = { fx < drag.from and edges[1] or edges[#edges] }
				drag.edges = edges
			end
			local i = edges[1]
			ts[i] = math.Clamp(f, ts[i - 1] or 0, ts[i + 1] or SA.frames)
			return
		end
		if drag.kind == "scrub" then
			if f ~= round(SA.frame) then SA.Seek(f) end
		elseif drag.kind == "sound" then
			drag.to = math.Clamp(round(frameAt(mx, s:GetWide()) - drag.grab), 0, SA.frames)
		elseif drag.kind == "box" then
			drag.x1, drag.y1 = mx, my
		elseif drag.kind == "keys" then
			-- the whole selection stays inside the animation
			drag.to = drag.from + math.Clamp(f - drag.from, -drag.lo, SA.frames - drag.hi)
		else
			drag.to = f
		end
	end

	tl.OnMouseReleased = function(s, code)
		if code == MOUSE_MIDDLE and drag and drag.kind == "pan" then
			drag = nil
			s:MouseCapture(false)
			return
		end
		if code ~= MOUSE_LEFT or not drag then return end
		s:MouseCapture(false)
		local d = drag
		drag = nil
		if d.kind == "tselnew" or d.kind == "tsel" then
			-- a Shift+click without a drag takes the selection away
			local ts = SA.timeSel
			if d.kind == "tselnew" and (not d.moved or (ts and ts[1] == ts[4])) then
				SA.SetTimeSel(nil)
				return
			end
			-- edges dragged by hand stay where they were put (no autofalloff to bookmarks)
			if ts then SA.SetTimeSel({ ts[1], ts[2], ts[3], ts[4], shape = ts.shape, noMarks = d.kind == "tsel" }) end
			return
		end
		if d.kind == "mark" then
			if d.to ~= d.from then SA.MoveMark(d.from, d.to) else SA.Seek(d.from) end
			return
		end
		if d.kind == "clip" then
			local c = SA.fxClips[d.i]
			if c and (d.a ~= c.a or d.b ~= c.b) then SA.EditClip(d.i, { a = d.a, b = d.b }, "sa fx clip move") end
			return
		end
		if d.kind == "cut" then
			if d.ripple and d.to > d.from then
				SA.InsertTime(d.from, d.to - d.from)
			elseif d.ripple and d.to < d.from then
				SA.CutTime(d.to, d.from - d.to)
			elseif d.to ~= d.from then SA.MoveCut(d.from, d.to) else SA.Seek(d.from) end
		elseif d.kind == "sound" then
			if d.to ~= d.from then SA.ChangeSound(d.id, { f = d.to }) end
		elseif d.kind == "trim" then
			-- dragged past the start / end of the file: TrimSound stops at it
			SA.TrimSound(d.id, d.side, d.to)
		elseif d.kind == "keys" then
			if d.to == d.from then
				-- a Ctrl+click on a selected key takes it out of the selection
				if d.ctrl and d.was then setSel(d.uid, d.key, false, d.parts) end
				return
			end
			local copy = input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL)
			local list, by = selList(), d.to - d.from
			SA.MoveKeys(list, by, copy)
			-- the selection goes with the keys (a copy selects the copies)
			clearSel()
			for _, k in ipairs(list) do setSel(k.uid, k.f + by, true, k.parts) end
			SA.Seek(d.key + by)
		elseif d.kind == "box" then
			if not d.add then clearSel() end
			local w = s:GetWide()
			local xa, xb = math.min(d.x0, d.x1), math.max(d.x0, d.x1)
			local ya, yb = math.min(d.y0, d.y1), math.max(d.y0, d.y1)
			for i, row in ipairs(rows) do
				local y = RULER_H + (i - 1 - scroll) * ROW_H
				if not row.sounds and y + ROW_H > ya and y < yb then
					for _, k in ipairs(row.keys) do
						local x = frameX(k.f, w)
						if x >= xa - 4 and x <= xb + 4 then setSel(row.uid, k.f, true, row.parts) end
					end
				end
			end
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
			local len = math.Clamp(viewLen() * (delta > 0 and 0.8 or 1.25), 10, SA.MAX_FRAMES)
			v0 = at - (mx - NAME_W - PAD) / span(w) * len
			vlen = len
			clampView()
		elseif shift then
			vlen = viewLen()
			v0 = v0 - delta * viewLen() * 0.1
			clampView()
		else
			scroll = math.max(scroll - delta, 0)
		end
		return true
	end
end

COMP:AddPage({ id = "sa_timeline", titleKey = "sa_timeline", icon = "icon16/film.png", window = "bottom", build = buildTimeline })

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
	win.minW, win.minH = UI.S(320), UI.S(320)
	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		Dock.pages.sa_import = nil
	end

	local hint = UI.Label(body, L("sa_imp_hint"))
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	hint:DockMargin(8, 6, 8, 4)

	local opts = { step = 2, loops = 1, speed = 1, root = true, forward = 0 }
	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(166))
	foot.Paint = function() end
	UI.Slider(foot, L("sa_imp_step"), 1, 6, 0, opts.step, function(v) opts.step = round(v) end)
	UI.Slider(foot, L("sa_imp_loops"), 1, 8, 0, opts.loops, function(v) opts.loops = round(v) end)
	UI.Slider(foot, L("sa_imp_speed"), 0.25, 2, 2, opts.speed, function(v) opts.speed = v end)
	UI.Check(foot, L("sa_imp_root"), opts.root, function(v) opts.root = v end)
	-- (b0.2.5) a walk or a run made in place goes forward at this speed (grounded root motion)
	UI.Slider(foot, L("sa_imp_forward"), 0, 400, 0, opts.forward, function(v) opts.forward = round(v) end)
		:SetTooltip(L("sa_imp_forward_tip"))

	local search = vgui.Create("DTextEntry", body)
	search:Dock(TOP)
	search:DockMargin(6, 2, 6, 2)
	search:SetTall(UI.S(20))
	search:SetFont("SPeditor.Small")
	search:SetPlaceholderText(L("sa_imp_search"))

	local list = vgui.Create("DListView", body)

	UI.StyleListView(list)
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
	srcRow:SetTall(UI.S(22))
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
	srcCombo:AddChoice(L("sa_imp_src_addon"), "+")
	srcCombo:AddChoice(L("sa_imp_src_path"), "?")
	srcCombo.OnSelect = function(s, _, text, data)
		if data == "+" then
			-- an animation pack of an installed addon (cl_saeditor_extra.lua)
			SA.OpenAnimModels(ent, function(path)
				if not IsValid(s) then return end
				s:SetText(path)
				setSource(path)
			end)
			return
		end
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
	-- the video file: AVI written by the editor, or WebM by the engine's writer (Windows)
	local vRow = row(L("sa_rd_video"))
	local vc = UI.StyleCombo(vgui.Create("DComboBox", vRow))
	vc:Dock(FILL)
	vc:SetTooltip(L(SA.WEBM_OK and "sa_rd_video_tip" or "sa_rd_webm_no"))
	local curFmt = SA.RenderVideoFormat()
	vc:AddChoice(L("sa_rd_video_avi"), "avi", curFmt == "avi")
	if SA.WEBM_OK then vc:AddChoice(L("sa_rd_video_webm"), "webm", curFmt == "webm") end
	vc:AddChoice(L("sa_rd_video_png"), "png", curFmt == "png")
	vc:AddChoice(L("sa_rd_video_jpeg"), "jpeg", curFmt == "jpeg")
	vc.OnSelect = function(_, _, _, data) RunConsoleCommand("gmfm_render_video", tostring(data)) end
	local qRow = row(L("sa_rd_quality"))
	local q = UI.StyleCombo(vgui.Create("DComboBox", qRow))
	q:Dock(FILL)
	for _, v in ipairs(SA.RENDER_QUALITIES) do q:AddChoice(L("sa_rd_q_" .. v), v, v == SA.RenderQuality()) end
	if not q:GetSelected() then q:SetText("JPEG " .. SA.RenderQuality()) end
	q.OnSelect = function(_, _, _, data) RunConsoleCommand("gmfm_video_quality", tostring(data)) end
	local sRow = row(L("sa_rd_samples"))
	local sm = UI.StyleCombo(vgui.Create("DComboBox", sRow))
	sm:Dock(FILL)
	for _, v in ipairs(SA.RENDER_SAMPLES) do sm:AddChoice(L("sa_rd_samples_" .. v), v, v == SA.RenderSamples()) end
	if not sm:GetSelected() then sm:SetText(SA.RenderSamples() .. "%") end
	sm.OnSelect = function(_, _, _, data) RunConsoleCommand("gmfm_render_samples", tostring(data)) end
	local fRow = row(L("sa_rd_fps"))
	local fc = UI.StyleCombo(vgui.Create("DComboBox", fRow))
	fc:Dock(FILL)
	fc:SetTooltip(L("sa_rd_fps_tip"))
	local cur = math.floor(GetConVar("gmfm_render_fps"):GetFloat())
	for _, v in ipairs(SA.RENDER_FPS) do
		fc:AddChoice(v == 0 and string.format(L("sa_rd_fps_anim"), SA.fps) or (v .. " " .. L("sa_fps")), v, v == cur)
	end
	if not fc:GetSelected() then fc:SetText(cur .. " " .. L("sa_fps")) end
	fc.OnSelect = function(_, _, _, data) RunConsoleCommand("gmfm_render_fps", tostring(data)) end
	-- motion blur (a0.7): moments a frame and how long the shutter stays open
	local bRow = row(L("sa_rd_blur"))
	local bc = UI.StyleCombo(vgui.Create("DComboBox", bRow))
	bc:Dock(FILL)
	bc:SetTooltip(L("sa_rd_blur_tip"))
	for _, v in ipairs(SA.RENDER_BLUR) do
		bc:AddChoice(v == 0 and L("sa_rd_blur_off") or string.format(L("sa_rd_blur_n"), v), v, v == SA.RenderBlur())
	end
	if not bc:GetSelected() then bc:SetText(string.format(L("sa_rd_blur_n"), SA.RenderBlur())) end
	bc.OnSelect = function(_, _, _, data) RunConsoleCommand("gmfm_render_mblur", tostring(data)) end
	local shRow = row(L("sa_rd_shutter"))
	local sc = UI.StyleCombo(vgui.Create("DComboBox", shRow))
	sc:Dock(FILL)
	sc:SetTooltip(L("sa_rd_shutter_tip"))
	for _, v in ipairs(SA.RENDER_SHUTTERS) do
		sc:AddChoice(string.format(L("sa_rd_shutter_n"), math.Round(v * 360)), v, math.abs(v - SA.RenderShutter()) < 0.01)
	end
	if not sc:GetSelected() then sc:SetText(string.format(L("sa_rd_shutter_n"), math.Round(SA.RenderShutter() * 360))) end
	sc.OnSelect = function(_, _, _, data) RunConsoleCommand("gmfm_render_shutter", tostring(data)) end
	-- effects (a0.8): the game slowed down so that particles are exact in every frame
	local slRow = row("")
	local sl = vgui.Create("DCheckBoxLabel", slRow)
	sl:Dock(FILL)
	sl:SetText(L("sa_rd_slowfx"))
	sl:SetFont("SPeditor.Small")
	sl:SetTextColor(UI.PAL.TEXT)
	sl:SetConVar("gmfm_render_slowfx")
	sl:SetTooltip(L("sa_rd_slowfx_tip"))
	-- b0.1: the depth of field the camera has keyed (Camera effects → Depth of field)
	local dfRow = row("")
	local df = vgui.Create("DCheckBoxLabel", dfRow)
	df:Dock(FILL)
	df:SetText(L("sa_rd_dof"))
	df:SetFont("SPeditor.Small")
	df:SetTextColor(UI.PAL.TEXT)
	df:SetConVar("gmfm_render_dof")
	df:SetTooltip(L("sa_rd_dof_tip"))
	return qRow, sRow, fRow, bRow, shRow, slRow, dfRow
end

---------------------------------------------------------------------
-- "Render animation": the Render window on its Animation tab (a0.9: the separate old window
-- of File → Render animation is gone, the same settings are on that tab since a0.7)
---------------------------------------------------------------------
function SA.OpenRender()
	UI.OpenRenderDialog()
	local win = Dock.ByKey("render")
	if win and win.SPSetTab then win.SPSetTab("anim") end
end

---------------------------------------------------------------------
-- The editor's Render window. When it opens, SAeditor checks whether the scene has
-- animation (playing right now or not — it does not matter), and for an animated scene
-- adds its own section at the top of the settings: what to render and in what form.
-- The section watches the scene itself: once the first key appears, so does the section.
---------------------------------------------------------------------
-- The Animation tab of the Render window (cl_ui_render.lua): what part of the animation, the
-- video settings and the cameras of the video — the shots, editable right here (they are the
-- Cameras row of the timeline too).
SA.rdCamera = SA.rdCamera or "cuts"       -- "cuts" | Entity | "primary"

-- another scene loaded: the frames and the camera of the video were the previous scene's
COMP:Hook("SPeditor_SceneLoaded", function()
	if SA.rendering then SA.StopRender(false) end
	SA.rdFrom, SA.rdTo, SA.rdCamera = nil, nil, "cuts"
end, "render_reset")

local function animCamera()
	local c = SA.rdCamera
	if c == "cuts" and #SA.cuts > 0 then return "cuts" end
	if IsValid(c) then return c end
	-- only scene cameras are rendered (cl_export.lua SceneCamera); nil — the scene has none
	return SPeditor.Export.SceneCamera(nil)
end

COMP:Hook("SPeditor_RenderDialog", function(ctx)
	local body = ctx.body
	ctx.animated = SA.IsAnimated
	ctx.canRender = function() return SA.IsAnimated() or SA.rendering ~= nil end
	ctx.setMode = function(m) RunConsoleCommand("gmfm_render_mode", m) end
	ctx.getAnimCamera = animCamera
	ctx.previewCamera = function()
		local c = animCamera()
		if c == "cuts" then return SA.CameraAt(SA.frame) or SPeditor.Export.SceneCamera(nil) end
		return c
	end

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

	local function row(text, parent)
		local r = vgui.Create("DPanel", parent or sec)
		r:Dock(TOP)
		r:DockMargin(6, 4, 6, 0)
		r:SetTall(UI.S(22))
		r.Paint = function() end
		local l = vgui.Create("DLabel", r)
		l:Dock(LEFT)
		l:SetWide(UI.S(140))
		l:SetFont("SPeditor.Small")
		l:SetTextColor(COL.TEXT)
		l:SetText(text)
		return r
	end
	local function label(parent, text, col)
		local l = vgui.Create("DLabel", parent)
		l:Dock(TOP)
		l:DockMargin(8, 6, 8, 0)
		l:SetWrap(true)
		l:SetAutoStretchVertical(true)
		l:SetFont("SPeditor.Small")
		l:SetTextColor(col or COL.DIM)
		l:SetText(text)
		return l
	end

	-- no animation yet: say how to make one
	local empty = label(sec, L("sa_rd_noanim"), COL.ORANGE)
	local emptyBtn = UI.Button(sec, L("guide_open"), "icon16/help.png", function() UI.OpenGuide("sa_keys") end)
	emptyBtn:DockMargin(6, 4, 6, 0)

	-- the frames to render
	local fr = row(L("sa_rd_frames"))
	local function num(parent, v)
		local e = vgui.Create("DNumberWang", parent)
		e:Dock(LEFT)
		e:SetWide(UI.S(60))
		e:SetMinMax(0, SA.MAX_FRAMES)
		e:SetDecimals(0)
		e:SetValue(v)
		return e
	end
	SA.rdFrom = SA.rdFrom or 0
	local fromE = num(fr, SA.rdFrom)
	local dash = vgui.Create("DLabel", fr)
	dash:Dock(LEFT)
	dash:SetWide(UI.S(16))
	dash:SetContentAlignment(5)
	dash:SetTextColor(COL.TEXT)
	dash:SetText("–")
	local toE = num(fr, SA.rdTo or SA.frames)
	fromE.OnValueChanged = function(_, v) SA.rdFrom = math.Clamp(math.floor(tonumber(v) or 0), 0, SA.frames) end
	toE.OnValueChanged = function(_, v) SA.rdTo = math.Clamp(math.floor(tonumber(v) or SA.frames), 0, SA.frames) end
	local whole = UI.Button(fr, L("sa_rd_whole"), nil, function()
		SA.rdFrom, SA.rdTo = 0, nil
		fromE:SetValue(0)
		toE:SetValue(SA.frames)
	end)
	whole:Dock(FILL)
	whole:DockMargin(6, 0, 0, 0)

	local qRow, sRow, fRow, bRow, shRow, slRow, dfRow = renderSpeedRows(row)

	-- the cameras of the video
	local camHead = label(sec, L("sa_rd_cams"), COL.ORANGE)
	camHead:SetFont("SPeditor.Bold")
	local cr = row(L("sa_rd_cam"))
	local camBox = UI.StyleCombo(vgui.Create("DComboBox", cr))
	camBox:Dock(FILL)
	local function fillCams()
		camBox:Clear()
		local cur = SA.rdCamera
		camBox:AddChoice(L("sa_rd_cam_cuts"), "cuts", cur == "cuts")
		for _, e in ipairs(SA.SceneCameras()) do camBox:AddChoice(C.DisplayName(e), e, cur == e) end
	end
	camBox.OnSelect = function(_, _, _, data)
		SA.rdCamera = data
		if UI.RenderPreview then UI.RenderPreview.next = 0 end
	end

	-- the shots: from which frame which camera (the Cameras row of the timeline)
	local shots = vgui.Create("DPanel", sec)
	shots:Dock(TOP)
	shots:DockMargin(6, 4, 6, 0)
	shots.Paint = function(_, w, h)
		surface.SetDrawColor(COL.LIST_BG or COL.BG)
		surface.DrawRect(0, 0, w, h)
	end
	shots.PerformLayout = function(s) s:SizeToChildren(false, true) end
	local function rebuildShots()
		shots:Clear()
		local cams = SA.SceneCameras()
		if #SA.cuts == 0 then
			label(shots, L(#cams == 0 and "sa_rd_need_cam" or "sa_rd_shot_none"))
		end
		for i, cut in ipairs(SA.cuts) do
			local r = vgui.Create("DPanel", shots)
			r:Dock(TOP)
			r:DockMargin(4, i == 1 and 4 or 2, 4, 0)
			r:SetTall(UI.S(22))
			r.Paint = function() end
			local n = vgui.Create("DLabel", r)
			n:Dock(LEFT)
			n:SetWide(UI.S(54))
			n:SetFont("SPeditor.Small")
			n:SetTextColor(COL.DIM)
			n:SetText(string.format(L("sa_rd_shot_n"), i))
			local f = vgui.Create("DNumberWang", r)
			f:Dock(LEFT)
			f:SetWide(UI.S(56))
			f:SetMinMax(0, SA.frames)
			f:SetDecimals(0)
			f:SetValue(cut.f)
			f:SetTooltip(L("sa_rd_shot_frame"))
			f.OnValueChanged = function(_, v)
				v = math.Clamp(math.floor(tonumber(v) or cut.f), 0, SA.frames)
				if v ~= cut.f then timer.Create("SAeditor.ShotMove", 0.4, 1, function() SA.MoveCut(cut.f, v) end) end
			end
			local del = UI.IconButton(r, "icon16/cross.png", L("sa_rd_shot_del"), function() SA.RemoveCut(cut.f) end, nil, RIGHT)
			local go = UI.IconButton(r, "icon16/control_end_blue.png", L("sa_rd_shot_go"), function() SA.Seek(cut.f) end, nil, RIGHT)
			local cb = UI.StyleCombo(vgui.Create("DComboBox", r))
			cb:Dock(FILL)
			cb:DockMargin(4, 0, 4, 0)
			local cur = SA.EntByUID(cut.uid)
			for _, e in ipairs(cams) do cb:AddChoice(C.DisplayName(e), e, e == cur) end
			if not IsValid(cur) then cb:SetText(L("sa_rd_shot_gone")) end
			cb.OnSelect = function(_, _, _, e) SA.AddCut(cut.f, e) end
		end
		local add = UI.Button(shots, L("sa_rd_shot_add"), "icon16/add.png", function()
			local cams2 = SA.SceneCameras()
			if #cams2 == 0 then SPeditor.Notify("#sa_rd_need_cam", 1) return end
			-- the camera looked through or selected, else the next one after the shot in effect
			local cam = C.GetViewCamera() or (C.IsCamera(C.selected) and C.selected) or nil
			if not cam then
				local now = SA.CameraAt(SA.frame)
				cam = cams2[1]
				for k, e in ipairs(cams2) do if e == now then cam = cams2[k % #cams2 + 1] end end
			end
			SA.AddCut(SA.frame, cam)
			SA.rdCamera = "cuts"
			fillCams()
		end)
		add:DockMargin(4, 4, 4, 4)
		label(shots, L("sa_rd_shots_hint"))
		shots:InvalidateLayout(true)
		sec:InvalidateLayout(true)
	end

	local note = label(sec, "")
	local stop = UI.Button(sec, L("sa_rd_stop"), "icon16/stop.png", function() SA.StopRender(false) end)
	stop:DockMargin(6, 6, 6, 0)

	local state, shotSig, sceneSeen, framesSeen = nil, nil, C.sceneSerial, SA.frames
	sec.Think = function(s)
		local animated = SA.IsAnimated()
		local job = SA.rendering
		-- another scene (or another length): the frame fields show the new one, not the old
		if sceneSeen ~= C.sceneSerial or (framesSeen ~= SA.frames and not SA.rdTo) then
			sceneSeen, framesSeen = C.sceneSerial, SA.frames
			local from, to = SA.rdFrom, SA.rdTo
			fromE:SetValue(from or 0)
			toE:SetValue(to or SA.frames)
			SA.rdFrom, SA.rdTo = from, to     -- SetValue runs OnValueChanged: keep "to the end" as nil
			if UI.RenderPreview then UI.RenderPreview.next = 0 end
		end
		-- the shots changed (here, on the timeline, by undo): the list follows
		local sig = {}
		for _, c in ipairs(SA.cuts) do sig[#sig + 1] = c.f .. ":" .. c.uid end
		for _, e in ipairs(SA.SceneCameras()) do sig[#sig + 1] = C.DisplayName(e) end
		sig = table.concat(sig, ",") .. "|" .. SA.frames .. "|" .. tostring(SA.rdCamera)
		if sig ~= shotSig then
			shotSig = sig
			fillCams()
			rebuildShots()
		end
		local text = job and string.format(L("sa_rnd_progress"), SA.RenderProgress(job)) or L("sa_rd_note_avi")
		local key = tostring(animated) .. tostring(job ~= nil) .. text .. tostring(SA.rdCamera == "cuts")
		if key == state then return end
		state = key
		empty:SetVisible(not animated)
		emptyBtn:SetVisible(not animated)
		for _, r in ipairs({ fr, qRow, sRow, fRow, bRow, shRow, slRow, dfRow, camHead, cr }) do r:SetVisible(animated) end
		shots:SetVisible(animated and SA.rdCamera == "cuts")
		stop:SetVisible(job ~= nil)
		note:SetVisible(animated)
		note:SetText(text)
		note:SetTextColor(job and COL.ORANGE or COL.DIM)
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
COMP:Hook("SPeditor_RenderPreviewBuilt", function(side, pv)
	local bar = vgui.Create("DPanel", side)
	bar:Dock(BOTTOM)
	bar:DockMargin(0, 4, 0, 0)
	bar:SetTall(UI.S(26))
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
	label:SetWide(UI.S(150))
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

	-- shown for an animated scene; watched from the parent: a hidden panel gets no Think, so
	-- once hidden (the window opened on a still scene) the bar never came back
	local shown
	local sideThink = side.Think
	side.Think = function(s)
		if sideThink then sideThink(s) end
		if not IsValid(bar) then return end
		local animated = SA.IsAnimated()
		if animated == shown then return end
		shown = animated
		bar:SetVisible(animated)
		s:InvalidateLayout()
	end
end, "render_preview")

---------------------------------------------------------------------
-- Editor menus
---------------------------------------------------------------------
COMP:AddMenu("object", function(m, ent)
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

COMP:AddMenu("file", function(m)
	m:AddOption(L("sa_render"), function() SA.OpenRender() end):SetIcon("icon16/film_save.png")
	local sm, so = m:AddSubMenu(L("sa_show_menu"))
	if so and so.SetIcon then so:SetIcon("icon16/television.png") end
	SA.ShowMenu(sm)
	m:AddOption(L("sa_rec_title") .. "…", function() SA.OpenRecord() end):SetIcon("icon16/webcam.png")
	m:AddOption(L("sa_smh_title") .. "…", function() SA.OpenSMH() end):SetIcon("icon16/arrow_switch.png")
end)

COMP:AddMenu("edit", function(m)
	local sub = m:AddSubMenu(L("sa_menu"))
	sub:AddOption(L("sa_key") , function() SA.SetKey() end):SetIcon("icon16/key_add.png")
	sub:AddOption(L("sa_key_all"), function() SA.SetKey(C.Objects()) end):SetIcon("icon16/key_go.png")
	sub:AddOption(L("sa_autokey"), function() SA.autokey = not SA.autokey end):SetChecked(SA.autokey)
	sub:AddOption(L("sa_bone_keys"), function() SA.ToggleBoneKeys() end):SetChecked(SA.BoneKeysOn())
	sub:AddOption(L("sa_ghosts"), function() SA.ToggleGhosts() end):SetChecked(SA.GhostsOn())
	-- a0.8: how new keys move, and the whole animation made continuous at once
	local em, eo = sub:AddSubMenu(L("sa_new_ease"))
	if eo and eo.SetIcon then eo:SetIcon("icon16/chart_curve.png") end
	for _, e in ipairs(SA.NEW_EASES) do
		em:AddOption(L("sa_ease_" .. e), function() SA.SetNewEase(e) end):SetChecked(SA.NewEase() == e)
	end
	sub:AddOption(L("sa_smooth_all"), function() SA.SmoothAll() end):SetIcon("icon16/chart_line.png")
	sub:AddOption(L("sa_snd_add"), function() SA.OpenSounds() end):SetIcon("icon16/sound_add.png")
	sub:AddOption(L("sa_crv_title") .. "…", function() SA.OpenCurves() end):SetIcon("icon16/chart_curve.png")
	sub:AddSpacer()
	sub:AddOption(L("sa_clear_all"), function()
		Derma_Query(L("sa_clear_all_q"), "SAeditor", L("yes"), function() SA.ClearAll() end, L("cancel"), function() end)
	end):SetIcon("icon16/cross.png")
end)
