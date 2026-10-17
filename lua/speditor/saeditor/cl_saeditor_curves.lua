--[[
SAeditor — the curve editor (a0.5): the keys of the selected object drawn as curves of its
values over time, as in the SFM graph editor.

What is shown: the object itself (place, turn, and FOV / brightness / moment … for cameras,
lights and effects) or the selected bone (a physical bone of a ragdoll — its place and turn
relative to the ragdoll's root; any other bone — its offset). The window follows the
selection. Channels: x y z — place, p y r — turn (pitch, yaw, roll), the rest by name.

  LMB on a key point — select it; drag up/down — change that value of the key,
      left/right — move the key in time (the drag direction decides);
  LMB on a round handle — bend the curve between the selected key and the next one
      (the easing becomes a curve of its own; it may overshoot);
  LMB on empty space — move the playhead; RMB on a key — its menu;
  wheel — zoom time, Ctrl+wheel — zoom values, RMB drag — pan, the Fit button — show all.
"Normalized" scales every channel to its own range, so that degrees and units fit together.

Under the graph (a0.6) the motion of the selected key — or of the stretch the playhead is in —
is shown as it looks: a ball goes from this key to the next one with the key's easing, and
grey dots mark equal steps of time (close dots — slow, far apart — fast), with the easing
said in plain words. The "?" button opens the guide (Help → How to use).

The values come from the server (sv_saeditor.lua, the Curve / CurveData messages); the
curves between keys are worked out here with the same easing as playback.
]]
local COMP  = SPeditor.Component("saeditor")
local SA   = COMP.SA
local C    = SPeditor.Client
local UI   = SPeditor.UI
local Dock = SPeditor.Dock
local L    = SPeditor.L
local COL  = UI.PAL

local CH_COLORS = {
	x = Color(235, 90, 90), y = Color(110, 220, 110), z = Color(100, 150, 255),
	pitch = Color(240, 150, 150), yaw = Color(160, 235, 160), roll = Color(150, 180, 255),
	fov = Color(240, 200, 90), bri = Color(240, 200, 90), radius = Color(200, 140, 240), lfov = Color(120, 220, 220),
	time = Color(240, 200, 90), fxscale = Color(200, 140, 240), scale = Color(240, 200, 90),
}
local ANGLE_CH = { pitch = 1, yaw = 2, roll = 3 }
local PAD_L, PAD_B, PAD_T = 46, 18, 8
local HIT = 6

---------------------------------------------------------------------
-- How an easing moves (also used by the guides, cl_saeditor_guides.lua)
---------------------------------------------------------------------
local MOTION_RUN, MOTION_REST = 1.6, 0.7       -- seconds the ball moves, and stands at the end

-- the easing in words: a dictionary string
function SA.EaseWords(ease, bz)
	if ease ~= "bezier" or not bz then return L("sa_ew_" .. (table.HasValue(SA.EASES, ease) and ease or "ease")) end
	local function slope(u0, u1) return (SA.BezierEase(u1, bz) - SA.BezierEase(u0, bz)) / (u1 - u0) end
	local s0, s1 = slope(0, 0.08), slope(0.92, 1)
	local lo, hi = 0, 1
	for i = 1, 39 do
		local v = SA.BezierEase(i / 40, bz)
		lo, hi = math.min(lo, v), math.max(hi, v)
	end
	local parts = { L(s0 < 0.6 and "sa_ew_b_start_slow" or (s0 > 1.6 and "sa_ew_b_start_fast" or "sa_ew_b_start_even")),
		L(s1 < 0.6 and "sa_ew_b_end_slow" or (s1 > 1.6 and "sa_ew_b_end_fast" or "sa_ew_b_end_even")) }
	if hi > 1.02 then parts[#parts + 1] = L("sa_ew_b_over") end
	if lo < -0.02 then parts[#parts + 1] = L("sa_ew_b_back") end
	return table.concat(parts, ", ")
end

-- The motion of an easing inside x, y, w, h at the moment t (seconds, it repeats): a track
-- from "A" to "B", grey dots at equal steps of time and the ball. col — the ball's colour.
function SA.DrawMotion(x, y, w, h, ease, bz, t, col)
	local pad = math.min(28, w * 0.12)
	local x0, x1 = x + pad, x + w - pad
	local cy = y + h / 2
	local function at(u)
		local v = SA.EaseValue(ease, u, bz)
		if ease == "hold" and u >= 1 then v = 1 end
		return x0 + (x1 - x0) * v
	end
	surface.SetDrawColor(COL.BORDER)
	surface.DrawRect(x0, cy, x1 - x0, 1)
	draw.SimpleText("A", "SPeditor.Small", x0, cy - 9, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
	draw.SimpleText("B", "SPeditor.Small", x1, cy - 9, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
	surface.DrawRect(x0, cy - 6, 1, 13)
	surface.DrawRect(x1, cy - 6, 1, 13)
	draw.NoTexture()
	for i = 0, 12 do
		local px = at(i / 12)
		surface.SetDrawColor(COL.DIM.r, COL.DIM.g, COL.DIM.b, 160)
		surface.DrawRect(px - 1, cy + 6, 3, 3)
	end
	local cyc = t % (MOTION_RUN + MOTION_REST)
	local u = math.min(cyc / MOTION_RUN, 1)
	local bx = at(u)
	local r = math.min(7, h / 4)
	col = col or COL.ORANGE
	surface.SetDrawColor(col)
	local poly = {}
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		poly[#poly + 1] = { x = bx + math.cos(a) * r, y = cy + math.sin(a) * r }
	end
	surface.DrawPoly(poly)
end

local CV = SA.curves or { visible = {}, normalized = true }
SA.curves = CV

-- the part shown: the selected bone, or the object itself
local function currentTarget()
	local ent = C.selected
	if not IsValid(ent) then return nil end
	local uid = SA.UID(ent)
	if uid == 0 then return nil end
	return ent, uid, (C.selBone or -1) >= 0 and C.selBone or -1
end

function SA.RequestCurve(uid, part)
	COMP:NetStart("Curve")
	net.WriteUInt(0, 2)
	net.WriteUInt(uid, 32)
	net.WriteInt(part, 16)
	net.SendToServer()
end

local function sendValue(id, uid, part, frame, ch, v)
	COMP:NetStart("Curve")
	net.WriteUInt(1, 2)
	net.WriteUInt(uid, 32)
	net.WriteInt(part, 16)
	net.WriteUInt(id, 32)
	net.WriteUInt(frame, 32)
	net.WriteString(ch)
	net.WriteFloat(v)
	net.SendToServer()
end

SA.ReceiveParts("CurveData", function(t)
	t = t or {}
	-- an answer for another object (the selection changed meanwhile) is dropped
	if CV.uid ~= tonumber(t.uid) or CV.part ~= tonumber(t.part) then return end
	CV.data = { chans = t.chans or {}, keys = SA.FromPages(t.keys) }
	-- the drag in progress keeps its own value
	if CV.drag and CV.drag.kind == "value" then
		for _, k in ipairs(CV.data.keys) do
			if k.f == CV.drag.f then k.v[CV.drag.c] = CV.drag.value end
		end
	end
	if CV.onData then CV.onData() end
end)

-- re-ask when the keys change (debounced: an edit sends many summaries)
COMP:Hook("SAeditor_Changed", function()
	if not CV.uid then return end
	timer.Create("SAeditor.CurveRefresh", 0.1, 1, function()
		if CV.uid and IsValid(CV.panel) then SA.RequestCurve(CV.uid, CV.part) end
	end)
end, "curves")

---------------------------------------------------------------------
-- Values between keys (the same maths as playback)
---------------------------------------------------------------------
local function keyAngle(k) return Angle(k.v[CV.ai[1]] or 0, k.v[CV.ai[2]] or 0, k.v[CV.ai[3]] or 0) end

-- the value of channel c at frame f
local function valueAt(keys, c, f, chName)
	local n = #keys
	if n == 0 then return 0 end
	if f <= keys[1].f then return keys[1].v[c] or 0 end
	if f >= keys[n].f then return keys[n].v[c] or 0 end
	local lo = 1
	for i = 1, n - 1 do
		if keys[i + 1].f > f then lo = i break end
	end
	local a, b = keys[lo], keys[lo + 1]
	local u = (f - a.f) / math.max(b.f - a.f, 1e-6)
	local va, vb = a.v[c] or 0, b.v[c] or 0
	local ai = ANGLE_CH[chName]
	-- a spline stretch: through the keys around it (the server blends turns as quaternions;
	-- here each angle channel is unwrapped around this key, close enough for the drawing)
	if a.e == "spline" then
		local k0, k3 = keys[lo - 1], keys[lo + 2]
		local function val(k, near)
			local v = k.v[c] or 0
			if ai then v = near + math.NormalizeAngle(v - near) end
			return v
		end
		local v1 = va
		local v2 = val(b, v1)
		local v0 = k0 and val(k0, v1) or v1
		local v3 = k3 and val(k3, v2) or v2
		local w0, w1, w2, w3 = SA.SplineWeights(k0 and k0.f or (2 * a.f - b.f), a.f, b.f, k3 and k3.f or (2 * b.f - a.f), u)
		return v0 * w0 + v1 * w1 + v2 * w2 + v3 * w3
	end
	local w = SA.EaseValue(a.e, u, a.bz)
	if ai then
		local lin = va + math.NormalizeAngle(vb - va) * w
		-- a turn of the object itself or a physical bone goes along the shortest arc (slerp)
		if CV.slerp and CV.ai[1] and CV.ai[2] and CV.ai[3] then
			local an = SA.SlerpAngle(keyAngle(a), keyAngle(b), w)
			local comp = ai == 1 and an.p or (ai == 2 and an.y or an.r)
			return lin + math.NormalizeAngle(comp - lin)
		end
		return lin
	end
	return va + (vb - va) * w
end

-- the value channel c of the part shown has at frame f, as the curve draws it (scripts, tests)
function SA.CurveValue(c, f)
	local d = CV.data
	if not d or not d.chans[c] then return nil end
	return valueAt(d.keys, c, f, d.chans[c])
end

---------------------------------------------------------------------
-- The window
---------------------------------------------------------------------
function SA.OpenCurves()
	if Dock.ShowPage("sa_curves") then return end
	local W, H = math.min(900, ScrW() - 80), 430
	local win, body = Dock.Create({ key = "sa_curves", id = "sa_curves", title = L("sa_crv_title"), w = W, h = H,
			x = math.floor(ScrW() / 2 - W / 2), y = ScrH() - H - 260, dockable = true, floating = true, icon = "icon16/chart_curve.png" })
	win.minW, win.minH = UI.S(480), UI.S(260)

	local top = vgui.Create("DPanel", body)
	top:Dock(TOP)
	top:SetTall(UI.S(28))
	top.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
	end
	local title = vgui.Create("DLabel", top)
	title:Dock(LEFT)
	title:DockMargin(8, 0, 8, 0)
	title:SetFont("SPeditor.Small")
	title:SetTextColor(COL.TEXT)
	title:SetWide(UI.S(220))

	-- second row: the channels on the left, the view on the right
	local row2 = vgui.Create("DPanel", body)
	row2:Dock(TOP)
	row2:SetTall(UI.S(28))
	row2.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(0, h - 1, w, 1)
	end
	local chanBar = vgui.Create("DPanel", row2)
	chanBar:Dock(LEFT)
	chanBar:DockMargin(6, 0, 0, 0)
	chanBar:SetWide(UI.S(10))
	chanBar.Paint = function() end

	local function btn(text, tip, fn, parent)
		local b = vgui.Create("DButton", parent or top)
		b:Dock(RIGHT)
		b:DockMargin(2, 4, 2, 4)
		surface.SetFont("SPeditor.Small")
		b:SetWide(select(1, surface.GetTextSize(text)) + UI.S(16))
		b:SetText(text)
		b:SetTooltip(tip)
		UI.StyleButton(b, nil, 3)
		b.DoClick = fn
		return b
	end

	local graph = vgui.Create("DPanel", body)
	graph:Dock(FILL)
	CV.panel = graph
	local view = { f0 = 0, f1 = SA.frames, v0 = -1, v1 = 1 }
	local sel                 -- { f = frame of the selected key, c = channel index }

	local function chans() return CV.data and CV.data.chans or {} end
	local function keys() return CV.data and CV.data.keys or {} end
	local function shown(name) return CV.visible[name] ~= false end

	-- The curves are drawn from samples worked out once per change. An angle is unwrapped
	-- along the curve (a turn through 180 degrees goes on to 190, not back to -170), and every
	-- key is drawn on its curve: offs[c][frame] is the whole turns added to the key's own value.
	local samples, offs, dirty = {}, {}, true
	local function rebuildSamples()
		samples, offs, dirty = {}, {}, false
		local ks, cs = keys(), chans()
		if #ks == 0 then return end
		local step = math.max((ks[#ks].f - ks[1].f) / 600, 0.25)
		local frames = {}
		for i, k in ipairs(ks) do
			frames[#frames + 1] = { f = k.f, key = k }
			local nx = ks[i + 1]
			if nx then
				local n = math.max(math.ceil((nx.f - k.f) / step), 1)
				for j = 1, n - 1 do frames[#frames + 1] = { f = k.f + (nx.f - k.f) * j / n } end
			end
		end
		for c, name in ipairs(cs) do
			local list, off, prev = {}, {}, nil
			for _, fr in ipairs(frames) do
				local v = valueAt(ks, c, fr.f, name)
				if ANGLE_CH[name] and prev then v = prev + math.NormalizeAngle(v - prev) end
				list[#list + 1] = { fr.f, v }
				if fr.key then off[fr.key.f] = v - (fr.key.v[c] or 0) end
				prev = v
			end
			samples[c], offs[c] = list, off
		end
	end
	-- the value of a key as drawn (on its unwrapped curve)
	local function shownValue(k, c)
		return (k.v[c] or 0) + (offs[c] and offs[c][k.f] or 0)
	end

	-- the range of a channel over its curve (normalized view)
	local function rangeOf(c)
		if dirty then rebuildSamples() end
		local lo, hi
		for _, sm in ipairs(samples[c] or {}) do
			local v = sm[2]
			lo, hi = math.min(lo or v, v), math.max(hi or v, v)
		end
		if not lo then return -1, 1 end
		if hi - lo < 1e-3 then return lo - 1, hi + 1 end
		local pad = (hi - lo) * 0.15
		return lo - pad, hi + pad
	end

	-- channel value -> the value drawn (normalized: -1..1 over the channel's range)
	local ranges = {}
	local function toView(c, v)
		if not CV.normalized then return v end
		local r = ranges[c]
		return (v - r[1]) / (r[2] - r[1]) * 2 - 1
	end
	local function fromView(c, y)
		if not CV.normalized then return y end
		local r = ranges[c]
		return r[1] + (y + 1) / 2 * (r[2] - r[1])
	end

	local function fit()
		view.f0, view.f1 = 0, math.max(SA.frames, 1)
		local ks = keys()
		if #ks > 0 then
			view.f0 = math.max(ks[1].f - 4, 0)
			view.f1 = math.max(ks[#ks].f + 4, view.f0 + 8)
		end
		if CV.normalized then
			view.v0, view.v1 = -1.15, 1.15
		else
			local lo, hi
			for c, name in ipairs(chans()) do
				if shown(name) then
					local a, b = rangeOf(c)
					lo, hi = math.min(lo or a, a), math.max(hi or b, b)
				end
			end
			view.v0, view.v1 = lo or -1, hi or 1
		end
	end

	-- screen <-> graph
	local function sx(f, w) return PAD_L + (f - view.f0) / (view.f1 - view.f0) * (w - PAD_L - 6) end
	local function sy(v, h) return PAD_T + (1 - (v - view.v0) / (view.v1 - view.v0)) * (h - PAD_T - PAD_B) end
	local function fAt(x, w) return view.f0 + (x - PAD_L) / (w - PAD_L - 6) * (view.f1 - view.f0) end
	local function vAt(y, h) return view.v0 + (1 - (y - PAD_T) / (h - PAD_T - PAD_B)) * (view.v1 - view.v0) end

	local function rebuildChannels()
		chanBar:Clear()
		local x = 0
		for _, name in ipairs(chans()) do
			local b = vgui.Create("DButton", chanBar)
			b:SetPos(x, 4)
			b:SetSize(UI.S(46), UI.S(20))
			b:SetText("")
			b:SetTooltip(L("sa_crv_ch_" .. name))
			b.Paint = function(s, w, h)
				local col = CH_COLORS[name] or COL.TEXT
				draw.RoundedBox(3, 0, 0, w, h, shown(name) and Color(col.r, col.g, col.b, 70) or COL.CTRL)
				draw.SimpleText(L("sa_crv_s_" .. name), "SPeditor.Small", w / 2, h / 2, shown(name) and color_white or COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
			b.DoClick = function() CV.visible[name] = not shown(name) end
			x = x + 48
		end
		chanBar:SetWide(x + 4)
	end

	local lastSig
	CV.onData = function()
		dirty = true
		local sig = table.concat(chans(), ",")
		if sig ~= lastSig then
			lastSig = sig
			rebuildChannels()
			fit()
		end
		-- angles: their three channels and whether the server slerps them (root, physical bone)
		CV.ai = {}
		for c, name in ipairs(chans()) do
			if ANGLE_CH[name] then CV.ai[ANGLE_CH[name]] = c end
		end
	end

	-- follow the selection
	local function retarget()
		local ent, uid, part = currentTarget()
		part = part or -1          -- nothing selected: currentTarget returns nil for all three
		if uid ~= CV.uid or part ~= CV.part then
			CV.uid, CV.part, CV.data, sel, lastSig = uid, part, nil, nil, nil
			chanBar:Clear()
			if uid then SA.RequestCurve(uid, part) end
		end
		local name = IsValid(ent) and C.DisplayName(ent) or L("sa_crv_none")
		if IsValid(ent) and part >= 0 then name = name .. " · " .. (string.gsub(ent:GetBoneName(part) or "", "^ValveBiped%.Bip01_", "")) end
		title:SetText(name)
		-- the turn of the object itself and of a physical bone of a ragdoll is slerped by playback
		CV.slerp = part < 0 or (IsValid(ent) and C.PhysIndexOfBone(ent, part) ~= nil)
	end
	graph.Think = function()
		if not C.active then return end
		retarget()
	end

	-- the easing of the selected key as handles (x1, y1, x2, y2)
	local function selKeyIndex()
		if not sel then return nil end
		for i, k in ipairs(keys()) do
			if k.f == sel.f then return i end
		end
	end

	-- the motion strip under the graph: the selected key, or the stretch the playhead is in
	local strip = vgui.Create("DPanel", body)
	strip:Dock(BOTTOM)
	strip:SetTall(UI.S(46))
	local t0 = RealTime()
	strip.Paint = function(s, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(0, 0, w, 1)
		local ks = keys()
		local i = selKeyIndex()
		if not i then
			for j = 1, #ks - 1 do
				if SA.frame >= ks[j].f and SA.frame < ks[j + 1].f then i = j break end
			end
		end
		local a, b = i and ks[i], i and ks[i + 1]
		if not a or not b then
			draw.SimpleText(L("sa_ew_none"), "SPeditor.Small", 10, h / 2, COL.DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
			return
		end
		local words = SA.EaseWords(a.e, a.bz)
		surface.SetFont("SPeditor.Small")
		-- the ball's track starts after the words (but always keeps some room)
		local tw = math.Clamp(select(1, surface.GetTextSize(words)) + 30, math.floor(w * 0.3), w - 180)
		draw.SimpleText(string.format(L("sa_ew_from_to"), a.f, b.f, (b.f - a.f) / SA.fps), "SPeditor.Bold", 10, 13, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(words, "SPeditor.Small", 10, 31, COL.ORANGE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		-- the real duration of the stretch, but at least half a second so that it can be seen
		local dur = math.Clamp((b.f - a.f) / SA.fps, 0.5, 3)
		SA.DrawMotion(tw, 2, w - tw - 8, h - 4, a.e, a.bz, (RealTime() - t0) * MOTION_RUN / dur)
	end
	local function handlesOf(k)
		if k.e == "bezier" and k.bz then return k.bz end
		return SA.EASE_BEZIER[k.e] or SA.EASE_BEZIER.linear
	end
	-- the screen places of the two handles of segment i -> i + 1 on channel c
	local function handlePoints(i, c, w, h)
		local ks = keys()
		local a, b = ks[i], ks[i + 1]
		if not a or not b then return nil end
		local bz = handlesOf(a)
		local x0, x1 = sx(a.f, w), sx(b.f, w)
		local y0, y1 = sy(toView(c, shownValue(a, c)), h), sy(toView(c, shownValue(b, c)), h)
		-- a flat stretch has no height: the handles are drawn over a virtual one
		if math.abs(y1 - y0) < 24 then y1 = y0 - 40 end
		return x0 + bz[1] * (x1 - x0), y0 + bz[2] * (y1 - y0), x0 + bz[3] * (x1 - x0), y0 + bz[4] * (y1 - y0), x0, y0, x1, y1
	end

	graph.Paint = function(s, w, h)
		surface.SetDrawColor(COL.LIST_BG or COL.BG)
		surface.DrawRect(0, 0, w, h)
		local ks, cs = keys(), chans()
		for c in ipairs(cs) do ranges[c] = { rangeOf(c) } end
		-- the channel being dragged keeps the range it had: otherwise the scale would follow the point
		local dg = CV.drag
		if dg and dg.kind == "value" and dg.range then ranges[dg.c] = dg.range end
		-- frame grid and numbers
		local span = view.f1 - view.f0
		local step = 1
		for _, st in ipairs({ 1, 2, 5, 10, 20, 25, 50, 100, 200, 500 }) do
			if span / st <= w / 60 then step = st break end
			step = st
		end
		surface.SetDrawColor(255, 255, 255, 12)
		for f = math.ceil(view.f0 / step) * step, view.f1, step do
			local x = sx(f, w)
			surface.DrawLine(x, PAD_T, x, h - PAD_B)
			draw.SimpleText(tostring(f), "SPeditor.Small", x, h - PAD_B + 2, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
		end
		-- value lines
		for i = 0, 4 do
			local v = view.v0 + (view.v1 - view.v0) * i / 4
			local y = sy(v, h)
			surface.SetDrawColor(255, 255, 255, 12)
			surface.DrawLine(PAD_L, y, w, y)
			draw.SimpleText(CV.normalized and string.format("%.1f", v) or string.format("%.4g", v), "SPeditor.Small", PAD_L - 4, y, COL.DIM,
				TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
		end
		-- the timeline's length and the playhead
		local xe = sx(SA.frames, w)
		surface.SetDrawColor(0, 0, 0, 60)
		if xe < w then surface.DrawRect(xe, PAD_T, w - xe, h - PAD_T - PAD_B) end
		local xp = sx(SA.frame, w)
		surface.SetDrawColor(COL.RED or Color(230, 80, 60))
		surface.DrawLine(xp, PAD_T, xp, h - PAD_B)

		if not CV.uid then
			draw.SimpleText(L("sa_crv_pick"), "SPeditor.Small", w / 2, h / 2, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return
		end
		if #ks == 0 then
			draw.SimpleText(L("sa_crv_nokeys"), "SPeditor.Small", w / 2, h / 2, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			return
		end

		local drag = CV.drag
		local dragF = drag and drag.kind == "time" and drag.to or nil
		-- curves
		local x0, x1 = math.max(PAD_L, sx(view.f0, w)), math.min(w - 6, sx(view.f1, w))
		if dirty then rebuildSamples() end
		for c, name in ipairs(cs) do
			local list = samples[c]
			if shown(name) and list and #list > 0 then
				local col = CH_COLORS[name] or COL.TEXT
				surface.SetDrawColor(col.r, col.g, col.b, 220)
				-- flat before the first key and after the last one
				local yFirst, yLast = sy(toView(c, list[1][2]), h), sy(toView(c, list[#list][2]), h)
				surface.DrawLine(x0, yFirst, math.max(sx(list[1][1], w), x0), yFirst)
				surface.DrawLine(math.min(sx(list[#list][1], w), x1), yLast, x1, yLast)
				local px, py
				for _, sm in ipairs(list) do
					local x, y = sx(sm[1], w), sy(toView(c, sm[2]), h)
					if px and x >= x0 - 50 and px <= x1 + 50 then surface.DrawLine(px, py, x, y) end
					px, py = x, y
				end
			end
		end
		-- keys
		for _, k in ipairs(ks) do
			for c, name in ipairs(cs) do
				if shown(name) then
					local f = (drag and drag.kind == "time" and drag.f == k.f) and dragF or k.f
					local x, y = sx(f, w), sy(toView(c, shownValue(k, c)), h)
					local isSel = sel and sel.f == k.f
					local col = isSel and COL.ORANGE or (CH_COLORS[name] or COL.TEXT)
					surface.SetDrawColor(0, 0, 0, 220)
					surface.DrawRect(x - 4, y - 4, 8, 8)
					surface.SetDrawColor(col)
					surface.DrawRect(x - 3, y - 3, 6, 6)
				end
			end
		end
		-- handles of the selected key's segment (on the channel it was picked on)
		local i = selKeyIndex()
		if i and ks[i + 1] and sel.c and shown(cs[sel.c]) and ks[i].e ~= "hold" then
			local hx1, hy1, hx2, hy2, ax, ay, bx, by = handlePoints(i, sel.c, w, h)
			surface.SetDrawColor(255, 255, 255, 120)
			surface.DrawLine(ax, ay, hx1, hy1)
			surface.DrawLine(bx, by, hx2, hy2)
			for _, p in ipairs({ { hx1, hy1, 1 }, { hx2, hy2, 2 } }) do
				local hot = drag and drag.kind == "handle" and drag.which == p[3]
				draw.RoundedBox(5, p[1] - 5, p[2] - 5, 10, 10, hot and COL.ORANGE or color_white)
			end
		end
		-- the value under the mouse while dragging
		if drag and drag.kind == "value" then
			local mx, my = s:CursorPos()
			draw.SimpleTextOutlined(string.format("%s = %.3f", L("sa_crv_s_" .. cs[drag.c]), drag.value), "SPeditor.Small", mx + 14, my + 10,
				color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
		elseif drag and drag.kind == "time" then
			local mx, my = s:CursorPos()
			draw.SimpleTextOutlined(L("sa_frame") .. " " .. drag.to, "SPeditor.Small", mx + 14, my + 10, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, color_black)
		end
	end

	-- what is under the mouse: a handle, a key point, or nothing
	local function pick(mx, my)
		local w, h = graph:GetSize()
		local ks, cs = keys(), chans()
		local i = selKeyIndex()
		if i and ks[i + 1] and sel.c and ks[i].e ~= "hold" then
			local hx1, hy1, hx2, hy2 = handlePoints(i, sel.c, w, h)
			if math.abs(mx - hx1) < HIT + 1 and math.abs(my - hy1) < HIT + 1 then return { handle = 1, i = i } end
			if math.abs(mx - hx2) < HIT + 1 and math.abs(my - hy2) < HIT + 1 then return { handle = 2, i = i } end
		end
		local best, bestD
		for _, k in ipairs(ks) do
			for c, name in ipairs(cs) do
				if shown(name) then
					local d = math.max(math.abs(mx - sx(k.f, w)), math.abs(my - sy(toView(c, shownValue(k, c)), h)))
					if d < HIT and (not bestD or d < bestD) then best, bestD = { key = k, c = c }, d end
				end
			end
		end
		return best
	end

	graph.PickAt = pick           -- what is at a point of the graph (scripts and tests)

	local function keyMenu(k)
		local m = UI.Menu()
		local uid = CV.uid
		local em = m:AddSubMenu(L("sa_ease"))
		for _, e in ipairs(SA.EASES) do
			em:AddOption(L("sa_ease_" .. e), function() SA.SetEase(uid, k.f, e) end):SetChecked(k.e == e)
		end
		if k.e == "bezier" then em:AddOption(L("sa_ease_bezier")):SetChecked(true) end
		m:AddOption(L("sa_crv_goto"), function() SA.Seek(k.f) end)
		m:AddOption(L("sa_key_delete"), function() SA.DeleteKey(uid, k.f) sel = nil end):SetIcon("icon16/key_delete.png")
		m:Open()
	end

	graph.OnMousePressed = function(s, code)
		local mx, my = s:CursorPos()
		local w, h = s:GetSize()
		local hit = pick(mx, my)
		if code == MOUSE_RIGHT then
			if hit and hit.key then
				sel = { f = hit.key.f, c = hit.c }
				keyMenu(hit.key)
				return
			end
			CV.drag = { kind = "pan", mx = mx, my = my, f0 = view.f0, f1 = view.f1, v0 = view.v0, v1 = view.v1 }
			s:MouseCapture(true)
			return
		end
		if code ~= MOUSE_LEFT then return end
		s:MouseCapture(true)
		if hit and hit.handle then
			local k = keys()[hit.i]
			local bz = handlesOf(k)
			CV.drag = { kind = "handle", which = hit.handle, i = hit.i, id = SA.NextOp(), bz = { bz[1], bz[2], bz[3], bz[4] }, f = k.f }
			return
		end
		if hit and hit.key then
			sel = { f = hit.key.f, c = hit.c }
			CV.drag = { kind = "pending", f = hit.key.f, c = hit.c, mx = mx, my = my, v0 = hit.key.v[hit.c] or 0, key = hit.key,
				off = shownValue(hit.key, hit.c) - (hit.key.v[hit.c] or 0) }
			return
		end
		sel = nil
		CV.drag = { kind = "seek" }
		SA.Seek(math.Clamp(math.floor(fAt(mx, w) + 0.5), 0, SA.frames))
	end

	local lastSend = 0
	graph.OnCursorMoved = function(s, mx, my)
		local d = CV.drag
		if not d then return end
		local w, h = s:GetSize()
		if d.kind == "pan" then
			local df = (mx - d.mx) / (w - PAD_L - 6) * (d.f1 - d.f0)
			local dv = (my - d.my) / (h - PAD_T - PAD_B) * (d.v1 - d.v0)
			view.f0, view.f1 = d.f0 - df, d.f1 - df
			view.v0, view.v1 = d.v0 + dv, d.v1 + dv
		elseif d.kind == "seek" then
			SA.Seek(math.Clamp(math.floor(fAt(mx, w) + 0.5), 0, SA.frames))
		elseif d.kind == "pending" then
			-- the drag direction decides: up/down changes the value, left/right moves the key
			if math.abs(mx - d.mx) > 4 or math.abs(my - d.my) > 4 then
				if math.abs(my - d.my) >= math.abs(mx - d.mx) then
					d.kind, d.id, d.value = "value", SA.NextOp(), d.v0
					local r = ranges[d.c]
					d.range = r and { r[1], r[2] } or nil
				else
					d.kind, d.to = "time", d.f
				end
			end
		end
		if d.kind == "value" then
			local name = chans()[d.c]
			local r = d.range or ranges[d.c]
			local v = fromView(d.c, vAt(my, h)) - (d.off or 0)
			-- normalized: the range must not follow the point that is being dragged
			if CV.normalized and r then
				local dy = (d.my - my) / (h - PAD_T - PAD_B) * (view.v1 - view.v0) / 2 * (r[2] - r[1])
				v = d.v0 + dy
			end
			if input.IsKeyDown(KEY_LSHIFT) then v = math.Round(v) end      -- Shift: whole numbers
			d.value = v
			for _, k in ipairs(keys()) do
				if k.f == d.f then k.v[d.c] = v end
			end
			dirty = true
			if RealTime() - lastSend > 0.05 then
				lastSend = RealTime()
				sendValue(d.id, CV.uid, CV.part, d.f, name, v)
				d.sent = true
			end
		elseif d.kind == "time" then
			d.to = math.Clamp(math.floor(fAt(mx, w) + 0.5), 0, SA.frames)
		elseif d.kind == "handle" then
			local ks = keys()
			local a, b = ks[d.i], ks[d.i + 1]
			if not a or not b then return end
			local _, _, _, _, ax, ay, bx, by = handlePoints(d.i, sel.c, w, h)
			local x = math.Clamp((mx - ax) / math.max(bx - ax, 1), 0, 1)
			local y = math.Clamp((my - ay) / ((by - ay) ~= 0 and (by - ay) or -40), -1, 2)
			if d.which == 1 then d.bz[1], d.bz[2] = x, y else d.bz[3], d.bz[4] = x, y end
			a.e, a.bz = "bezier", { d.bz[1], d.bz[2], d.bz[3], d.bz[4] }
			dirty = true
			if RealTime() - lastSend > 0.08 then
				lastSend = RealTime()
				SA.SendKeyOp(d.id, SA.OP.EASE, CV.uid, d.f, 0, string.format("bezier:%.3f,%.3f,%.3f,%.3f", d.bz[1], d.bz[2], d.bz[3], d.bz[4]))
				d.sent = true
			end
		end
	end

	graph.OnMouseReleased = function(s, code)
		s:MouseCapture(false)
		local d = CV.drag
		CV.drag = nil
		if not d then return end
		if d.kind == "value" then
			sendValue(d.id, CV.uid, CV.part, d.f, chans()[d.c], d.value)
			SA.PushOpHistory("sa curve", d.id)
		elseif d.kind == "time" then
			if d.to ~= d.f then
				SA.MoveKey(CV.uid, d.f, d.to)
				if sel then sel.f = d.to end
			end
		elseif d.kind == "handle" then
			SA.SendKeyOp(d.id, SA.OP.EASE, CV.uid, d.f, 0, string.format("bezier:%.3f,%.3f,%.3f,%.3f", d.bz[1], d.bz[2], d.bz[3], d.bz[4]))
			SA.PushOpHistory("sa ease", d.id)
		end
	end

	graph.OnMouseWheeled = function(s, delta)
		local mx, my = s:CursorPos()
		local w, h = s:GetSize()
		local k = delta > 0 and 0.8 or 1.25
		if input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL) then
			local v = vAt(my, h)
			view.v0, view.v1 = v + (view.v0 - v) * k, v + (view.v1 - v) * k
		else
			local f = fAt(mx, w)
			view.f0, view.f1 = f + (view.f0 - f) * k, f + (view.f1 - f) * k
			if view.f1 - view.f0 < 4 then view.f1 = view.f0 + 4 end
		end
		return true
	end

	-- buttons on the right: easing of the selected key, view
	local function ease(e)
		return function()
			local k = sel and keys()[selKeyIndex() or 0]
			if k then SA.SetEase(CV.uid, k.f, e) else SPeditor.Notify(L("sa_crv_need_key"), 0) end
		end
	end
	UI.GuideButton(top, "sa_curves")
	btn(L("sa_crv_fit"), L("sa_crv_fit_tip"), fit, row2)
	local norm = btn(L("sa_crv_norm"), L("sa_crv_norm_tip"), function()
		CV.normalized = not CV.normalized
		fit()
	end, row2)
	norm.PaintOver = function(s2, w, h)
		if CV.normalized then
			surface.SetDrawColor(COL.ORANGE)
			surface.DrawOutlinedRect(0, 0, w, h, 1)
		end
	end
	-- the other kinds (elastic, bounce…) in a menu
	btn(L("sa_ease_more") .. "…", L("sa_crv_ease_tip"), function()
		local m = UI.Menu()
		for _, e in ipairs(SA.EASES) do
			if not table.HasValue(SA.EASE_MAIN, e) then m:AddOption(L("sa_ease_" .. e), ease(e)) end
		end
		m:Open()
	end)
	for i = #SA.EASE_MAIN, 1, -1 do
		local e = SA.EASE_MAIN[i]
		btn(L("sa_ease_" .. e), L("sa_crv_ease_tip"), ease(e))
	end

	CV.uid, CV.part, CV.data = nil, nil, nil
	retarget()
	return win
end
