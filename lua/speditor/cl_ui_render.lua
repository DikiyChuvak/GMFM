--[[
SPeditor — the Render window (after Export Frame / Render in SFM).
Settings on the left: camera, aspect ratio and resolution, fullbright,
smoothing, depth of field, "engine frame" for Workshop shaders,
file format, file name and camera effects (including "custom shaders").

The rest of the window is the preview: a frame assembled by the same code as
the final render (SPeditor.Render.RenderBase + camera effects). It grows and
shrinks with the window. Camera effects are visible only here and in the finished file,
so they are laid over the preview every frame — an effect slider responds
at once, even when the scene itself (with depth of field, say) is re-shot rarely.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI = SPeditor.UI
local C  = SPeditor.Client
local L  = SPeditor.L
local COL = UI.PAL

local function row(parent, label)
	local p = vgui.Create("DPanel", parent)
	p:Dock(TOP)
	p:DockMargin(6, 4, 6, 0)
	p:SetTall(UI.S(24))
	p.Paint = function() end
	local l = vgui.Create("DLabel", p)
	l:Dock(LEFT)
	l:SetWide(UI.S(150))
	l:SetTextColor(COL.TEXT)
	l:SetText(label)
	-- a long caption is cut by the column width: the tooltip shows it in full
	l:SetMouseInputEnabled(true)
	l:SetTooltip(label)
	return p
end

local function styleCombo(c)
	UI.StyleButton(c, nil, 2)
end

---------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------
local cvPreview = CreateClientConVar("gmfm_render_preview", "1", true, false)

-- The preview frame is drawn into one of three 5:4 textures and stretched to the
-- proportions of the final file; which one depends on the panel size. There are only
-- three sizes because every size is a separate set of render targets.
local PREVIEW_LEVELS  = { { 640, 512 }, { 960, 768 }, { 1280, 1024 } }
local PREVIEW_SAMPLES = 12     -- depth-of-field passes in the preview
local PREVIEW_FAST    = 0.1    -- scene re-shoot period, s
local PREVIEW_DOF     = 1.5    -- the same with depth of field (many passes)
local PREVIEW_DOF_MIN = 0.4    -- and no more often than this while settings are being changed
local PREVIEW_MOVING  = 4      -- passes while the camera moves (shot every PREVIEW_FAST)

local SETTINGS = {
	"gmfm_aspect", "gmfm_render_side", "gmfm_render_custom", "gmfm_render_w", "gmfm_render_h",
	"gmfm_render_fullbright", "gmfm_render_ss", "gmfm_dof", "gmfm_dof_aperture", "gmfm_exposure",
	"gmfm_render_engine", "gmfm_softlight_samples",
	"gmfm_ssao", "gmfm_ssao_radius", "gmfm_ssao_strength", "gmfm_ssao_mode", "gmfm_ssao_passes",
}

local function settingsKey(camera)
	local parts = { tostring(camera) }
	for i, name in ipairs(SETTINGS) do parts[i + 1] = GetConVar(name):GetString() end
	return table.concat(parts, "|")
end

-- texture for a frame that will take iw x ih pixels in the panel
local function previewLevel(panel, aspect)
	local _, _, iw, ih = C.FitRect(panel:GetWide(), panel:GetTall(), aspect)
	for _, l in ipairs(PREVIEW_LEVELS) do
		if iw <= l[1] * 1.2 and ih <= l[2] * 1.2 then return l end
	end
	return PREVIEW_LEVELS[#PREVIEW_LEVELS]
end

-- pv = { panel, camera = function() -> "primary" | "work" | Entity, base, rt, key, next, soon, samples }
SPeditor.Hook("PostRender", "SPeditor.RenderPreview", function()
	local pv = UI.RenderPreview
	if not pv or not IsValid(pv.panel) or not C.active or C.hideUI or C.exporting then return end
	if SPeditor.Export.pending or not cvPreview:GetBool() or not UI.PageShown("render") then return end
	-- a frame sequence is being rendered: the frame time is not spent on the preview
	if SPeditor.Render.busy and pv.base then return end

	local R, FX = SPeditor.Render, SPeditor.FX
	local camera = pv.camera()
	-- nothing to show without a camera in the scene (the work camera is not rendered)
	if not SPeditor.Export.SceneCamera(camera) then
		pv.base, pv.rt = nil, nil
		return
	end
	local W, H = C.GetRenderSize()
	local aspect = W / H
	local lvl = previewLevel(pv.panel, aspect)
	local pw, ph = lvl[1], lvl[2]
	local src = SPeditor.Export.Source(camera)
	local fx = FX.For(src.ent)
	local wide = R.FXSource(src, fx)

	-- the scene: on a timer, and at once when settings change
	local now = RealTime()
	local key = settingsKey(camera) .. "|" .. pw .. "|" .. math.Round(wide.fov, 1)
	-- the camera moves (an animation, flying, look-at): with depth of field the preview was
	-- shot once in 1.5 s and a turning camera looked as if it stood still. While it moves the
	-- preview is shot every PREVIEW_FAST with a few passes; at rest — in full.
	local o, a = wide.origin, wide.angles
	local place = string.format("%.1f %.1f %.1f %.2f %.2f %.2f", o.x, o.y, o.z, a.p, a.y, a.r)
	if place ~= pv.place then pv.place, pv.movedAt = place, now end
	local moving = now - (pv.movedAt or 0) < 0.4 or (C.ScenePlaying and C.ScenePlaying())
	if R.EngineFor(GetConVar("gmfm_render_fullbright"):GetBool()) then
		-- "engine frame": the engine shoots the scene in the next game frame, here we take the finished one
		R.FinishEngineFrame()
		local E = R.Engine
		if E.info and E.info.owner == pv and E.serial ~= pv.engSerial then
			pv.engSerial = E.serial
			local ok, rt = pcall(R.EngineToRT, pw, ph, aspect)
			pv.base = ok and rt or nil
		end
		-- The previous frame stays on screen until a new one is shot, and a new one is ordered no
		-- more often than once per PREVIEW_FAST. A settings change used to drop the frame and order
		-- the next one at once; for a camera with an animated field of view (SAeditor) the key
		-- changes every frame — the preview never got to appear, and every other frame the game
		-- drew the scene full screen (flicker).
		if not pv.base or now >= (pv.next or 0) then
			pv.key, pv.samples = key, nil
			pv.next = now + PREVIEW_FAST
			R.RequestEngineFrame(wide, { fullbright = GetConVar("gmfm_render_fullbright"):GetBool(), aspect = aspect, owner = pv })
		end
	elseif not pv.base or now >= (pv.next or 0) or (key ~= pv.key and now >= (pv.soon or 0))
		or (moving and now >= (pv.fastNext or 0)) or (not moving and pv.fastShot) then
		pv.key = key
		local opts = { fullbright = GetConVar("gmfm_render_fullbright"):GetBool(), aspect = aspect,
			ss = (GetConVar("gmfm_render_ss"):GetBool() and pw < 1280) and 2 or 1 }
		pv.samples = nil
		-- the Animation tab shows the video as it will be: without depth of field (a0.9)
		local anim = UI.renderTab == "anim"
		if GetConVar("gmfm_dof"):GetBool() and not anim then
			pv.samples = math.min(math.Clamp(GetConVar("gmfm_dof_samples"):GetInt(), 2, 128), PREVIEW_SAMPLES)
			opts.dof = { aperture = math.Clamp(GetConVar("gmfm_dof_aperture"):GetFloat(), 0.05, 20), samples = pv.samples,
				focus = SPeditor.Export.FocusDistance(src) }
		end
		-- a camera with its own depth of field (camera effects) uses it instead
		local own = not anim and FX.DOF(fx)
		if own then
			pv.samples = math.min(own.samples, PREVIEW_SAMPLES)
			opts.dof = { aperture = own.aperture, samples = pv.samples, focus = own.focus }
		end
		-- soft shadows from lights with a size: the same accumulator and the same pass ceiling
		opts.softMax = PREVIEW_SAMPLES
		local slow = opts.dof or (not opts.fullbright and SPeditor.Lights.SoftSamples() > 0)
		pv.next = now + (slow and PREVIEW_DOF or PREVIEW_FAST)
		pv.soon = now + (slow and PREVIEW_DOF_MIN or 0)
		-- a moving camera: a light frame now, the full one when it stops
		pv.fastShot = moving and slow or nil
		if pv.fastShot then
			if opts.dof then opts.dof.samples = math.min(opts.dof.samples, PREVIEW_MOVING) end
			opts.softMax = PREVIEW_MOVING
			pv.samples = opts.dof and opts.dof.samples or pv.samples
			pv.fastNext = now + PREVIEW_FAST
		end

		-- as in export: the gizmo and helper graphics are hidden for the render
		local prevHide, prevExp = C.hideUI, C.exporting
		C.hideUI, C.exporting = true, true
		local ok, rt = pcall(R.RenderBase, wide, pw, ph, opts)
		C.hideUI, C.exporting = prevHide, prevExp
		pv.base = ok and rt or nil
		if not ok then ErrorNoHalt("[GM:FM] render preview: " .. tostring(rt) .. "\n") end
	end

	-- camera effects: every frame over a copy of the shot scene (the scene itself stays untouched)
	pv.rt = pv.base
	local clips = R.ApplyClips and SPeditor.Component("saeditor").SA.fxClips
	if pv.base and (fx or (clips and #clips > 0)) then
		local work = R.GetRT("pvw_" .. pw .. "x" .. ph, pw, ph)
		R.Copy(pv.base, work)
		pv.rt = fx and FX.Apply(work, R.GetRT("pvs_" .. pw .. "x" .. ph, pw, ph), pw, ph, fx, aspect) or work
		-- the FX clips of the timeline at the current frame (b0.2 round 6)
		if R.ApplyClips then pv.rt = R.ApplyClips(pv.rt, pw, ph) end
	end
end)

local function buildPreview(body, getCamera)
	local side = vgui.Create("DPanel", body)
	side:Dock(FILL)
	side:DockPadding(6, 0, 6, 6)
	side.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(0, 0, 1, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(1, 0, w - 1, 22)
		draw.SimpleText(L("render_preview"), "SPeditor.Bold", 8, 11, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local pv = { camera = getCamera, next = 0 }
	UI.RenderPreview = pv

	local foot = vgui.Create("DPanel", side)
	foot:Dock(BOTTOM)
	foot:DockMargin(0, 4, 0, 0)
	foot:SetTall(UI.S(22))
	foot.Paint = function() end

	-- SAeditor adds its panels here (SAeditor — the animation playback buttons);
	-- pv.next = 0 makes the preview re-shoot the scene at once
	hook.Run("SPeditor_RenderPreviewBuilt", side, pv)

	local live = UI.Check(foot, L("render_preview_live"), cvPreview:GetBool(), function(v)
		RunConsoleCommand("gmfm_render_preview", v and "1" or "0")
		pv.next = 0
	end)
	live:Dock(LEFT)
	live:DockMargin(2, 2, 12, 0)
	live:SetWide(UI.S(200))

	local note = vgui.Create("DLabel", foot)
	note:Dock(FILL)
	note:SetFont("SPeditor.Small")
	note:SetTextColor(COL.DIM)
	note:SetText("")

	-- the frame takes all the remaining space of the window and scales with it
	local view = vgui.Create("DPanel", side)
	view:Dock(FILL)
	view:DockMargin(0, 28, 0, 0)
	view.Paint = function(_, w, h)
		surface.SetDrawColor(COL.VIEW_BG)
		surface.DrawRect(0, 0, w, h)
		local W, H = C.GetRenderSize()
		if cvPreview:GetBool() and pv.rt then
			local ix, iy, iw, ih = C.FitRect(w - 2, h - 2, W / H)
			SPeditor.Render.DrawRT(pv.rt, math.floor(ix) + 1, math.floor(iy) + 1, math.floor(iw), math.floor(ih))
		else
			local msg = not cvPreview:GetBool() and "render_preview_off"
				or (not SPeditor.Export.SceneCamera(getCamera()) and "render_need_camera") or "render_preview_wait"
			draw.SimpleText(L(msg), "SPeditor.Small",
				w / 2, h / 2, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		surface.SetDrawColor(COL.BORDER)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	view.Think = function()
		local W, H = C.GetRenderSize()
		local text = string.format("%d × %d px", W, H)
		if pv.samples and cvPreview:GetBool() then
			text = text .. "   ·   " .. string.format(L("render_preview_dof"), pv.samples, GetConVar("gmfm_dof_samples"):GetInt())
		end
		if note.SPText ~= text then
			note.SPText = text
			note:SetText(text)
		end
	end
	pv.panel = view
	return side
end

---------------------------------------------------------------------
-- Curve editor (the Curves effect): four curves — the master and per channel.
-- LMB on empty space — a new point, drag — move, RMB on a point — remove.
-- o = { get = function(channel) -> string, set = function(channel, string, final) }
---------------------------------------------------------------------
local CHANNELS = { { "m", "RGB" }, { "r", "R" }, { "g", "G" }, { "b", "B" } }

function UI.CurveEditor(parent, o)
	local FX = SPeditor.FX
	local host = vgui.Create("DPanel", parent)
	host:Dock(TOP)
	host:DockMargin(18, 1, 2, 2)
	host:SetTall(UI.S(214))
	host.Paint = function() end

	local channel = "m"
	local colors = { m = COL.TEXT, r = COL.RED, g = COL.GREEN, b = COL.BLUE }
	local pts = {}
	local drag, lastEdit = nil, 0

	local function load()
		for _, ch in ipairs(CHANNELS) do pts[ch[1]] = FX.ParseCurve(o.get(ch[1])) end
	end
	load()

	local function commit(final)
		lastEdit = RealTime()
		o.set(channel, FX.FormatCurve(pts[channel]), final)
	end

	local bar = vgui.Create("DPanel", host)
	bar:Dock(TOP)
	bar:SetTall(UI.S(20))
	bar.Paint = function() end
	for _, ch in ipairs(CHANNELS) do
		local b = vgui.Create("DButton", bar)
		b:Dock(LEFT)
		b:DockMargin(0, 0, 2, 0)
		b:SetWide(UI.S(40))
		b:SetText("")
		b.Paint = function(s, w, h)
			surface.SetDrawColor(channel == ch[1] and COL.TAB_ON or (s:IsHovered() and COL.HOVER or COL.CTRL))
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(ch[2], "SPeditor.Bold", w / 2, h / 2, colors[ch[1]], TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function() channel = ch[1] end
	end
	local reset = vgui.Create("DButton", bar)
	reset:Dock(RIGHT)
	reset:SetWide(UI.S(110))
	reset:SetText(L("curve_reset"))
	UI.StyleButton(reset)
	reset.DoClick = function()
		pts[channel] = { { 0, 0 }, { 1, 1 } }
		commit(true)
	end

	local graph = vgui.Create("DPanel", host)
	graph:Dock(FILL)
	graph:DockMargin(0, 2, 0, 0)
	graph:SetCursor("crosshair")
	graph:SetTooltip(L("curve_hint"))
	local PAD = 6

	local function toScreen(x, y, w, h)
		return PAD + x * (w - PAD * 2), h - PAD - y * (h - PAD * 2)
	end
	local function fromScreen(mx, my, w, h)
		return math.Clamp((mx - PAD) / math.max(w - PAD * 2, 1), 0, 1), math.Clamp((h - PAD - my) / math.max(h - PAD * 2, 1), 0, 1)
	end
	local function nearest(mx, my, w, h)
		local best, bestD
		for i, p in ipairs(pts[channel]) do
			local x, y = toScreen(p[1], p[2], w, h)
			local d = (x - mx) ^ 2 + (y - my) ^ 2
			if d < 81 and (not bestD or d < bestD) then best, bestD = i, d end
		end
		return best
	end

	local function drawCurve(list, col, w, h)
		local f = FX.CurveFunction(list)
		surface.SetDrawColor(col)
		local px, py
		for i = 0, 48 do
			local x, y = toScreen(i / 48, f(i / 48), w, h)
			if px then surface.DrawLine(px, py, x, y) end
			px, py = x, y
		end
	end

	graph.Paint = function(_, w, h)
		surface.SetDrawColor(COL.LIST_BG)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.CTRL)
		for i = 0, 4 do
			local x, y = toScreen(i / 4, i / 4, w, h)
			surface.DrawLine(x, PAD, x, h - PAD)
			surface.DrawLine(PAD, y, w - PAD, y)
		end
		local x0, y0 = toScreen(0, 0, w, h)
		local x1, y1 = toScreen(1, 1, w, h)
		surface.SetDrawColor(COL.DIM.r, COL.DIM.g, COL.DIM.b, 90)
		surface.DrawLine(x0, y0, x1, y1)
		-- the other curves — pale, the chosen one — on top
		for _, ch in ipairs(CHANNELS) do
			if ch[1] ~= channel and #pts[ch[1]] > 0 and FX.FormatCurve(pts[ch[1]]) ~= FX.FormatCurve({ { 0, 0 }, { 1, 1 } }) then
				local c = colors[ch[1]]
				drawCurve(pts[ch[1]], Color(c.r, c.g, c.b, 70), w, h)
			end
		end
		drawCurve(pts[channel], colors[channel], w, h)
		for i, p in ipairs(pts[channel]) do
			local x, y = toScreen(p[1], p[2], w, h)
			surface.SetDrawColor((drag == i) and COL.ORANGE or colors[channel])
			surface.DrawRect(x - 3, y - 3, 7, 7)
			surface.SetDrawColor(COL.BORDER)
			surface.DrawOutlinedRect(x - 3, y - 3, 7, 7, 1)
		end
	end

	graph.OnMousePressed = function(s, code)
		local mx, my = s:CursorPos()
		local w, h = s:GetSize()
		local list = pts[channel]
		local i = nearest(mx, my, w, h)
		if code == MOUSE_RIGHT then
			if i and i > 1 and i < #list then
				table.remove(list, i)
				commit(true)
			end
			return
		end
		if code ~= MOUSE_LEFT then return end
		if not i then
			if #list >= FX.MAX_CURVE_POINTS then return end
			local x, y = fromScreen(mx, my, w, h)
			i = #list + 1
			for k, p in ipairs(list) do
				if p[1] > x then i = k break end
			end
			if i == 1 then i = 2 end
			if i > #list then i = #list end
			table.insert(list, i, { x, y })
		end
		drag = i
		s:MouseCapture(true)
		s:OnCursorMoved()
	end

	graph.OnCursorMoved = function(s)
		if not drag then return end
		local list = pts[channel]
		local p = list[drag]
		if not p then drag = nil return end
		local mx, my = s:CursorPos()
		local w, h = s:GetSize()
		local x, y = fromScreen(mx, my, w, h)
		-- the end points stay on the edges; the others do not overtake their neighbours
		if drag == 1 then x = 0
		elseif drag == #list then x = 1
		else x = math.Clamp(x, list[drag - 1][1] + 0.02, list[drag + 1][1] - 0.02) end
		p[1], p[2] = x, y
		commit(false)
	end

	graph.OnMouseReleased = function(s, code)
		if code ~= MOUSE_LEFT or not drag then return end
		drag = nil
		s:MouseCapture(false)
		commit(true)
	end

	-- the curve is also changed by undo (Ctrl+Z): the editor follows while it is not touched
	graph.Think = function()
		if drag or RealTime() - lastEdit < 1 then return end
		if (graph.SPNext or 0) > RealTime() then return end
		graph.SPNext = RealTime() + 0.3
		load()
	end
	return host
end

---------------------------------------------------------------------
-- Camera effects (cl_postfx.lua): a section of the Render window
---------------------------------------------------------------------
-- getCamera() -> the scene camera whose effects are edited, or nil
local function buildEffects(parent, getCamera)
	local FX = SPeditor.FX
	local host = vgui.Create("DPanel", parent)
	host:Dock(TOP)
	host:DockMargin(6, 10, 6, 6)
	host.Paint = function(_, w, h)
		surface.SetDrawColor(COL.ROW_B)
		surface.DrawRect(0, 0, w, h)
	end

	local function edit(id, key, value, final)
		local cam = getCamera()
		if not cam then return end
		local fx = table.Copy(C.GetCameraFX(cam) or {})
		fx[id] = istable(fx[id]) and fx[id] or {}
		fx[id][key] = value
		C.SendCameraFX(cam, fx, final)
	end

	local function head(text, col)
		local p = vgui.Create("DPanel", host)
		p:Dock(TOP)
		p:SetTall(UI.S(18))
		p.Paint = function(_, w, h)
			surface.SetDrawColor(COL.HEADER)
			surface.DrawRect(0, 0, w, h)
			draw.SimpleText(text, "SPeditor.Bold", 6, h / 2, col or COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end

	local function materialRow(def, prm, cam)
		local p = vgui.Create("DPanel", host)
		p:Dock(TOP)
		p:DockMargin(0, 0, 0, 1)
		p:SetTall(UI.S(22))
		p.Paint = function() end
		local box = UI.StyleCombo(vgui.Create("DComboBox", p))
		box:Dock(FILL)
		box:DockMargin(18, 1, 2, 1)
		local cur = FX.Get(C.GetCameraFX(cam), def.id, prm.key)
		local names = {}
		for name, item in pairs(list.Get(prm.list) or {}) do
			if istable(item) and isstring(item.Material) then names[#names + 1] = { name = name, mat = item.Material } end
		end
		table.sort(names, function(a, b) return a.name < b.name end)
		for _, n in ipairs(names) do
			local label = (string.sub(n.name, 1, 1) == "#") and language.GetPhrase(string.sub(n.name, 2)) or n.name
			box:AddChoice(label, n.mat, n.mat == cur)
		end
		box.OnSelect = function(_, _, _, mat) edit(def.id, prm.key, mat, true) end
	end

	-- Custom shader: picking a material from those found (cl_shaders.lua) and its parameters
	local function shaderRows(def, prm, cam)
		local Sd = SPeditor.Shaders
		Sd.Scan(false)
		local cur = FX.Get(C.GetCameraFX(cam), def.id, prm.key)
		local p = vgui.Create("DPanel", host)
		p:Dock(TOP)
		p:DockMargin(0, 0, 0, 1)
		p:SetTall(UI.S(22))
		p.Paint = function() end
		local box = UI.StyleCombo(vgui.Create("DComboBox", p))
		box:Dock(FILL)
		box:DockMargin(18, 1, 2, 1)
		box:SetValue(cur ~= "" and cur or L("fx_shader_pick"))
		for _, info in ipairs(Sd.List) do
			local src = (info.source == "addons") and L("shader_src_addons") or info.source
			box:AddChoice(src .. ":  " .. info.path, info.path, info.path == cur)
		end
		box.OnSelect = function(_, _, _, path)
			-- another material has its own parameters: old values are not carried over
			local c = getCamera()
			if not c then return end
			local fx = table.Copy(C.GetCameraFX(c) or {})
			fx[def.id] = { on = true, material = path }
			C.SendCameraFX(c, fx, true)
		end

		local info = Sd.Get(cur)
		local hint
		if #Sd.List == 0 then hint = L("fx_shader_none")
		elseif cur ~= "" and not info then hint = string.format(L("fx_shader_missing"), cur)
		elseif info and info.buffers then hint = L("fx_shader_buffers") end
		if hint then
			local l = UI.Label(host, hint, COL.ORANGE)
			l:SetWrap(true)
			l:SetAutoStretchVertical(true)
			l:DockMargin(18, 2, 6, 3)
		end
		if not info then return end
		for _, sp in ipairs(info.params) do
			local function get()
				local t = IsValid(cam) and C.GetCameraFX(cam)
				local v = t and istable(t[def.id]) and tonumber(t[def.id][sp.key])
				return v or sp.default
			end
			UI.Control(host, { label = "    " .. sp.name, min = sp.min, max = sp.max, default = sp.default, decimals = 3,
					value = get(), onChange = function(v, final) edit(def.id, sp.key, v, final) end, getter = get })
		end
	end

	local built
	local function rebuild()
		host:Clear()
		local cam = getCamera()
		head(L("fx_title") .. (cam and ("  —  " .. C.DisplayName(cam)) or ""), COL.ORANGE)
		if not cam then
			local l = UI.Label(host, L("fx_need_camera"))
			l:SetWrap(true)
			l:SetAutoStretchVertical(true)
			l:DockMargin(6, 4, 6, 6)
		else
			local note = UI.Label(host, L("fx_preview_only"))
			note:SetWrap(true)
			note:SetAutoStretchVertical(true)
			note:DockMargin(6, 3, 6, 3)
			local fx = C.GetCameraFX(cam)
			for _, cat in ipairs(FX.Cats) do
				head(L("fxc_" .. cat))
				for _, def in ipairs(FX.Defs) do
					if def.cat == cat then
						local title = def.dynamic and string.format(L("fx_shader"), tonumber(string.match(def.id, "%d+")) or 1) or L("fx_" .. def.id)
UI.ToggleRow(host, title, function() return FX.IsOn(C.GetCameraFX(cam), def.id) end, function(v)
							edit(def.id, "on", v, true)
						end)
						if FX.IsOn(fx, def.id) then
							for _, prm in ipairs(def.params) do
								if prm.shader then
									shaderRows(def, prm, cam)
								elseif prm.list then
									materialRow(def, prm, cam)
								elseif prm.curve then
									UI.CurveEditor(host, {
											get = function(ch) return IsValid(cam) and FX.Get(C.GetCameraFX(cam), def.id, prm.key .. "_" .. ch) or FX.DEFAULT_CURVE end,
											set = function(ch, str, final) edit(def.id, prm.key .. "_" .. ch, str, final) end,
									})
								else
									UI.Control(host, { label = "    " .. L("fxp_" .. prm.key), min = prm.min, max = prm.max, default = prm.default,
											decimals = prm.decimals or 2, value = FX.Get(fx, def.id, prm.key),
											onChange = function(v, final) edit(def.id, prm.key, v, final) end,
											getter = function() return IsValid(cam) and FX.Get(C.GetCameraFX(cam), def.id, prm.key) or nil end })
								end
							end
						end
					end
				end
			end
			-- addon effects (Q menu post-processing, GShader…) kept and keyed with the camera (b0.1)
			local Sd = SPeditor.Shaders
			head(L("fx_addons"))
			local info = UI.Label(host, "")
			info:SetWrap(true)
			info:SetAutoStretchVertical(true)
			info:DockMargin(6, 3, 6, 3)
			info.Think = function(s)
				local c = getCamera()
				local n, on = Sd.KeyedCount(c and C.GetCameraFX(c))
				local text = n > 0 and string.format(L("fx_addons_has"), on) or L("fx_addons_none")
				if not SPeditor.Render.EngineMode() then text = text .. "  " .. L("fx_addons_engine") end
				if s.SPText ~= text then
					s.SPText = text
					s:SetText(text)
					s:SetTextColor(SPeditor.Render.EngineMode() and COL.DIM or COL.ORANGE)
				end
				s:SizeToContentsY()
			end
			local take = UI.Button(host, L("fx_addons_take"), "icon16/key_add.png", function()
				local c = getCamera()
				if not c then return end
				local fx, own = {}, 0
				for id, t in pairs(C.GetCameraFX(c) or {}) do
					if string.sub(id, 1, #Sd.KEY_PREFIX) ~= Sd.KEY_PREFIX then
						fx[id] = t
						own = own + 1
					end
				end
				-- the camera keeps at most 24 effects: the ones switched on go first
				local snap, ids = Sd.Snapshot(), {}
				for id in pairs(snap) do ids[#ids + 1] = id end
				table.sort(ids, function(a, b)
					local oa, ob = snap[a][string.sub(a, #Sd.KEY_PREFIX + 1)] == 1, snap[b][string.sub(b, #Sd.KEY_PREFIX + 1)] == 1
					if oa ~= ob then return oa end
					return a < b
				end)
				for i, id in ipairs(ids) do
					if own + i > 24 then break end
					fx[id] = snap[id]
				end
				C.SendCameraFX(c, fx, true)
				SPeditor.Notify("#fx_addons_taken", 0)
			end)
			take:SetTooltip(L("fx_addons_tip"))
			take:DockMargin(4, 4, 4, 2)
			local forget = UI.Button(host, L("fx_addons_clear"), "icon16/key_delete.png", function()
				local c = getCamera()
				if not c then return end
				local fx = {}
				for id, t in pairs(C.GetCameraFX(c) or {}) do
					if string.sub(id, 1, #Sd.KEY_PREFIX) ~= Sd.KEY_PREFIX then fx[id] = t end
				end
				C.SendCameraFX(c, fx, true)
			end)
			forget:DockMargin(4, 2, 4, 2)

			local reset = UI.Button(host, L("fx_reset"), "icon16/cross.png", function() C.SendCameraFX(cam, {}, true) end)
			reset:DockMargin(4, 6, 4, 4)
		end
		host:InvalidateLayout(true)
		host:SizeToChildren(false, true)
	end

	-- the section is rebuilt when the camera or the set of enabled effects changes
	host.Think = function()
		local cam = getCamera()
		local parts = { tostring(cam) }
		local fx = cam and C.GetCameraFX(cam) or nil
		for i, def in ipairs(FX.Defs) do
			parts[i + 1] = FX.IsOn(fx, def.id) and "1" or "0"
			-- the sliders of a "custom shader" depend on the chosen material
			if def.dynamic and fx and istable(fx[def.id]) then parts[i + 1] = parts[i + 1] .. tostring(fx[def.id].material) end
		end
		parts[#parts + 1] = tostring(#SPeditor.Shaders.List)
		local sig = table.concat(parts)
		if sig ~= built then
			built = sig
			rebuild()
		end
	end
	return host
end

-- cam (optional) — the scene camera to select in the window (its effects and render)
function UI.OpenRenderDialog(cam)
	local existing = SPeditor.Dock.ByKey("render")
	if existing then
		SPeditor.Dock.ShowPage("render")
		if IsValid(cam) and existing.SPSetCamera then existing.SPSetCamera(cam) end
		return
	end

	local win, body = SPeditor.Dock.Create({
			key = "render", id = "render", title = L("render_title"),
			w = math.min(1240, ScrW() - 80), h = math.min(760, ScrH() - 130),
			x = math.floor(ScrW() / 2 - math.min(1240, ScrW() - 80) / 2), y = 70, dockable = false,
	})
	win.minW, win.minH = UI.S(700), UI.S(420)
	UI.RenderWin = win

	-- only the cameras of the scene (a0.9): the work camera is never rendered
	local camera = SPeditor.Export.SceneCamera(cam)    -- Entity | nil (no cameras in the scene)
	local sizeLabel, nameBox
	-- two tabs (a0.7): "Picture" — a still of the current frame, "Animation" — the video. The
	-- preview and the look of the frame (size, smoothing, depth of field, SSAO, shaders,
	-- camera effects) are shared; each tab has only its own settings.
	local tab, ctx = "still", nil
	local function inAnim() return tab == "anim" and ctx and ctx.animated ~= nil end
	-- the camera the preview and the render use: in Animation — the video's camera (the shots)
	local function shotCamera()
		if inAnim() and ctx.previewCamera then return ctx.previewCamera() or camera end
		return camera
	end

	local btns = vgui.Create("DPanel", body)
	btns:Dock(BOTTOM)
	btns:SetTall(UI.S(36))
	btns.Paint = function() end

	local go = vgui.Create("DButton", btns)
	go:Dock(LEFT)
	go:DockMargin(8, 5, 4, 5)
	go:SetWide(UI.S(170))
	go:SetText("  " .. L("act_render"))
	go:SetIcon("icon16/picture_save.png")
	UI.StyleButton(go, nil, 3, COL.TAB_ON)
	go.DoClick = function()
		local name = IsValid(nameBox) and nameBox:GetValue() or ""
		if inAnim() then
			if not ctx.animated() then SPeditor.Notify("#render_no_anim", 1) return end
			SPeditor.Export.Render({ camera = ctx.getAnimCamera and ctx.getAnimCamera() or camera, name = name })
		else
			SPeditor.Export.Render({ camera = camera, name = name })
		end
	end

	-- whether the button can be pressed is decided here, for the tab shown (b0.2.2): it was
	-- switched by the Animation tab's own section, which gets no Think while hidden — after a
	-- look at the Animation tab of a scene without animation, Render stayed grey on the Picture
	-- tab too until the editor was opened again (reports from the Workshop). The row does it, not
	-- the button: a disabled button gets no Think and would never come back on (measured)
	btns.Think = function()
		local on = not inAnim() or not ctx.canRender or ctx.canRender()
		if go:IsEnabled() ~= on then go:SetEnabled(on) end
	end

	local close = vgui.Create("DButton", btns)
	close:Dock(RIGHT)
	close:DockMargin(4, 5, 8, 5)
	close:SetWide(UI.S(110))
	close:SetText(L("cancel"))
	UI.StyleButton(close, nil, 3)
	close.DoClick = function() win:Close() end

	-- on the left — the settings column (scrollable: with camera effects there are more of them
	-- than the window height), the rest of the window — the preview
	local outer = body
	body = vgui.Create("DScrollPanel", outer)
	body:Dock(LEFT)
	body:SetWide(UI.S(410))
	buildPreview(outer, shotCamera)
	local preview = UI.RenderPreview

	-- a group of rows shown only in one tab: as tall as its rows
	local function group()
		local g = vgui.Create("DPanel", body)
		g:Dock(TOP)
		g.Paint = function() end
		g.PerformLayout = function(s2) s2:SizeToChildren(false, true) end
		return g
	end
	local tabBar = vgui.Create("DPanel", body)
	tabBar:Dock(TOP)
	tabBar:DockMargin(4, 4, 4, 2)
	tabBar:SetTall(UI.S(30))
	tabBar.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(0, h - 1, w, 1)
	end
	local stillTop = group()
	local animHost = group()
	local setTab
	local tabBtns = {}
	for _, t in ipairs({ { "still", "render_tab_still", "icon16/picture.png" }, { "anim", "render_tab_anim", "icon16/film.png" } }) do
		local b = vgui.Create("DButton", tabBar)
		b:Dock(LEFT)
		b:DockMargin(0, 0, 4, 0)
		b:SetWide(UI.S(150))
		b:SetText("  " .. L(t[2]))
		b:SetIcon(t[3])
		b.SPTab = t[1]
		UI.StyleButton(b, nil, 3, COL.TAB_ON)
		local basePaint = b.Paint
		b.Paint = function(s2, w, h)
			if tab == s2.SPTab then
				surface.SetDrawColor(COL.TAB_ON or COL.BLUE)
				surface.DrawRect(0, 0, w, h)
				surface.SetDrawColor(COL.ORANGE)
				surface.DrawRect(0, h - 3, w, 3)
				return
			end
			if basePaint then return basePaint(s2, w, h) end
		end
		b.DoClick = function() setTab(t[1]) end
		tabBtns[#tabBtns + 1] = b
	end

	local function updateSize()
		if not IsValid(sizeLabel) then return end
		local w, h = C.GetRenderSize()
		sizeLabel:SetText(string.format("%d × %d px", w, h))
	end

	-- the Animation tab is filled by SAeditor; it answers with ctx.animated (is there an
	-- animation), ctx.getAnimCamera (the video's camera: "cuts" | Entity | "primary"),
	-- ctx.previewCamera, ctx.setMode and ctx.canRender (can the Render button be pressed there)
	ctx = { body = animHost, button = go, win = win, getCamera = function() return camera end }
	hook.Run("SPeditor_RenderDialog", ctx)
	if not ctx.animated then tabBar:SetVisible(false) end

	-- Camera (the picture; the video has its own in the Animation tab)
	local rc = row(stillTop, L("render_camera"))
	local camBox = vgui.Create("DComboBox", rc)
	camBox:Dock(FILL)
	styleCombo(camBox)
	local function fillCameras()
		camBox:Clear()
		local any = false
		for _, obj in ipairs(C.BuildEntityList()) do
			if obj.kind == "camera" and IsValid(obj.ent) then
				camBox:AddChoice(obj.name, obj.ent, camera == obj.ent)
				any = true
			end
		end
		if not any then camBox:SetValue(L("render_no_cams")) end
	end
	fillCameras()
	camBox.OnSelect = function(_, _, _, data) camera = data end
	win.SPState = function() return IsValid(camera) and camera or nil end
	win.SPSetCamera = function(e)
		camera = e
		fillCameras()
	end
	-- the chosen camera was deleted: fall back to the Primary Viewport source; the cameras of
	-- the scene changed (another scene loaded, a camera added or renamed): the list follows
	local camSig, sceneSeen = nil, C.sceneSerial
	rc.Think = function()
		if sceneSeen ~= C.sceneSerial then
			sceneSeen = C.sceneSerial
			camera = SPeditor.Export.SceneCamera(nil)
			preview.next, preview.key = 0, nil
		end
		if not IsValid(camera) then camera = SPeditor.Export.SceneCamera(nil) end
		local sig = { tostring(camera) }
		for _, obj in ipairs(C.BuildEntityList()) do
			if obj.kind == "camera" and IsValid(obj.ent) then sig[#sig + 1] = obj.ent:EntIndex() .. obj.name end
		end
		sig = table.concat(sig, ",")
		if sig ~= camSig then
			camSig = sig
			fillCameras()
		end
	end
	-- Aspect ratio
	local ra = row(body, L("menu_aspect"))
	local aspBox = vgui.Create("DComboBox", ra)
	aspBox:Dock(FILL)
	styleCombo(aspBox)
	local curAsp = C.GetAspectDef().id
	for _, a in ipairs(SPeditor.Aspects) do
		aspBox:AddChoice(SPeditor.LN("aspect_", a.name), a.id, (not GetConVar("gmfm_render_custom"):GetBool()) and a.id == curAsp)
	end
	aspBox:AddChoice(L("render_custom"), "__custom", GetConVar("gmfm_render_custom"):GetBool())

	-- Size (long side)
	local rs = row(body, L("menu_size"))
	local sizeBox = vgui.Create("DComboBox", rs)
	sizeBox:Dock(FILL)
	styleCombo(sizeBox)
	for _, side in ipairs(SPeditor.RenderSides) do
		sizeBox:AddChoice(tostring(side), side, side == C.GetRenderSide())
	end
	sizeBox.OnSelect = function(_, _, _, data)
		C.SetRenderSide(data)
		timer.Simple(0.05, updateSize)
	end

	-- Custom size W × H
	local rw = row(body, L("render_wh"))
	local wW = vgui.Create("DNumberWang", rw)
	wW:Dock(LEFT)
	wW:SetWide(UI.S(80))
	wW:SetMinMax(16, SPeditor.Config.MaxRenderSide)
	wW:SetValue(GetConVar("gmfm_render_w"):GetInt())
	local xl = vgui.Create("DLabel", rw)
	xl:Dock(LEFT)
	xl:DockMargin(6, 0, 6, 0)
	xl:SetWide(UI.S(10))
	xl:SetTextColor(COL.TEXT)
	xl:SetText("×")
	local wH = vgui.Create("DNumberWang", rw)
	wH:Dock(LEFT)
	wH:SetWide(UI.S(80))
	wH:SetMinMax(16, SPeditor.Config.MaxRenderSide)
	wH:SetValue(GetConVar("gmfm_render_h"):GetInt())
	wW.OnValueChanged = function(_, v) RunConsoleCommand("gmfm_render_w", tostring(math.floor(tonumber(v) or 1920))) timer.Simple(0.05, updateSize) end
	wH.OnValueChanged = function(_, v) RunConsoleCommand("gmfm_render_h", tostring(math.floor(tonumber(v) or 1080))) timer.Simple(0.05, updateSize) end

	local function applyCustomState(custom)
		sizeBox:SetEnabled(not custom)
		wW:SetEnabled(custom)
		wH:SetEnabled(custom)
		RunConsoleCommand("gmfm_render_custom", custom and "1" or "0")
		timer.Simple(0.05, updateSize)
	end
	aspBox.OnSelect = function(_, _, _, data)
		if data == "__custom" then
			applyCustomState(true)
		else
			applyCustomState(false)
			C.SetAspect(data)
		end
	end
	applyCustomState(GetConVar("gmfm_render_custom"):GetBool())

	-- Final size
	local rr = row(body, L("render_result"))
	sizeLabel = vgui.Create("DLabel", rr)
	sizeLabel:Dock(FILL)
	sizeLabel:SetTextColor(COL.ORANGE)
	updateSize()

	-- Fullbright
	local fb = vgui.Create("DCheckBoxLabel", body)
	fb:Dock(TOP)
	fb:DockMargin(8, 10, 8, 0)
	fb:SetText(L("render_fullbright"))
	fb:SetTextColor(COL.TEXT)
	fb:SetValue(GetConVar("gmfm_render_fullbright"):GetBool() and 1 or 0)
	fb.OnChange = function(_, v) RunConsoleCommand("gmfm_render_fullbright", v and "1" or "0") end

	-- Smoothing
	local ssBox = vgui.Create("DCheckBoxLabel", body)
	ssBox:Dock(TOP)
	ssBox:DockMargin(8, 6, 8, 0)
	ssBox:SetText(L("render_ss"))
	ssBox:SetTextColor(COL.TEXT)
	ssBox:SetValue(GetConVar("gmfm_render_ss"):GetBool() and 1 or 0)
	ssBox.OnChange = function(_, v) RunConsoleCommand("gmfm_render_ss", v and "1" or "0") end

	-- Depth of field
	local dofBox = vgui.Create("DCheckBoxLabel", body)
	dofBox:Dock(TOP)
	dofBox:DockMargin(8, 6, 8, 0)
	dofBox:SetText(L("render_dof"))
	dofBox:SetTextColor(COL.TEXT)
	dofBox:SetValue(GetConVar("gmfm_dof"):GetBool() and 1 or 0)
	dofBox.OnChange = function(_, v) RunConsoleCommand("gmfm_dof", v and "1" or "0") end

	UI.Slider(body, L("render_dof_aperture"), 0.05, 6, 2, GetConVar("gmfm_dof_aperture"):GetFloat(), function(v)
		RunConsoleCommand("gmfm_dof_aperture", tostring(math.Round(v, 2)))
	end)

	local rd = row(body, L("render_dof_samples"))
	local smpBox = vgui.Create("DComboBox", rd)
	smpBox:Dock(FILL)
	styleCombo(smpBox)
	local curS = GetConVar("gmfm_dof_samples"):GetInt()
	for _, n in ipairs({ 16, 32, 64, 96 }) do smpBox:AddChoice(tostring(n), n, n == curS) end
	smpBox.OnSelect = function(_, _, _, data) RunConsoleCommand("gmfm_dof_samples", tostring(data)) end

	-- Soft shadows from lights with a size (cl_lights.lua): number of passes
	local rs = row(body, L("render_soft_samples"))
	rs:SetTooltip(L("render_soft_samples_tip"))
	local softBox = vgui.Create("DComboBox", rs)
	softBox:Dock(FILL)
	styleCombo(softBox)
	local curSoft = SPeditor.Lights.GetSampleCount()
	for _, n in ipairs({ 8, 16, 24, 48, 96 }) do softBox:AddChoice(tostring(n), n, n == curSoft) end
	softBox.OnSelect = function(_, _, _, data) SPeditor.Lights.SetSampleCount(data) end

	-- Ambient occlusion: the editor's own SSAO (cl_ssao.lua)
	local aoBox = vgui.Create("DCheckBoxLabel", body)
	aoBox:Dock(TOP)
	aoBox:DockMargin(8, 6, 8, 0)
	aoBox:SetText(L("render_ssao"))
	aoBox:SetTextColor(COL.TEXT)
	aoBox:SetTooltip(L("render_ssao_tip"))
	aoBox:SetValue(GetConVar("gmfm_ssao"):GetBool() and 1 or 0)
	aoBox.OnChange = function(_, v) RunConsoleCommand("gmfm_ssao", v and "1" or "0") end
	-- b0.2: Source Filmmaker's own occlusion or the a0.7 one
	local aoMode = vgui.Create("DComboBox", body)
	aoMode:Dock(TOP)
	aoMode:DockMargin(8, 4, 8, 0)
	aoMode:SetTall(UI.S(20))
	styleCombo(aoMode)
	aoMode:SetSortItems(false)
	local curMode = SPeditor.Render.SSAOMode()
	aoMode:AddChoice(L("render_ssao_sfm"), "sfm", curMode == "sfm")
	aoMode:AddChoice(L("render_ssao_classic"), "classic", curMode == "classic")
	aoMode.OnSelect = function(_, _, _, data) RunConsoleCommand("gmfm_ssao_mode", data) end
	aoMode:SetTooltip(L("render_ssao_mode_tip"))
	UI.Slider(body, L("render_ssao_radius"), 4, 128, 0, GetConVar("gmfm_ssao_radius"):GetFloat(), function(v)
		RunConsoleCommand("gmfm_ssao_radius", tostring(math.Round(v)))
	end)
	UI.Slider(body, L("render_ssao_strength"), 0.1, 4, 2, GetConVar("gmfm_ssao_strength"):GetFloat(), function(v)
		RunConsoleCommand("gmfm_ssao_strength", tostring(math.Round(v, 2)))
	end)
	-- round 6: SFM's progressive occlusion — the passes averaged in a render (SFM mode)
	UI.Slider(body, L("render_ssao_passes"), 1, 64, 0, GetConVar("gmfm_ssao_passes"):GetInt(), function(v)
		RunConsoleCommand("gmfm_ssao_passes", tostring(math.Round(v)))
	end):SetTooltip(L("render_ssao_passes_tip"))

	-- Engine frame: shaders of addons and the Workshop (cl_render.lua, cl_shaders.lua)
	local R = SPeditor.Render
	local engBox = vgui.Create("DCheckBoxLabel", body)
	engBox:Dock(TOP)
	engBox:DockMargin(8, 10, 8, 0)
	engBox:SetText(L("render_engine"))
	engBox:SetTextColor(COL.TEXT)
	engBox:SetValue(R.EngineMode() and 1 or 0)
	engBox:SetTooltip(L("render_engine_tip"))
	engBox.OnChange = function(s, v)
		s.SPHold = RealTime() + 0.3
		R.SetEngineMode(v)
	end
	-- the mode is also switched from the "Addon shaders" window
	engBox.Think = function(s)
		if s:GetChecked() ~= R.EngineMode() and RealTime() > (s.SPHold or 0) then s:SetChecked(R.EngineMode()) end
	end

	local engRow = vgui.Create("DPanel", body)
	engRow:Dock(TOP)
	engRow:DockMargin(8, 4, 8, 0)
	engRow:SetTall(UI.S(22))
	engRow.Paint = function() end
	local engBtn = vgui.Create("DButton", engRow)
	engBtn:Dock(LEFT)
	engBtn:SetWide(UI.S(190))
	engBtn:SetText("  " .. L("shaders_open"))
	engBtn:SetIcon("icon16/wand.png")
	UI.StyleButton(engBtn, nil, 2)
	engBtn.DoClick = function() UI.OpenShaders() end
	local engNote = vgui.Create("DLabel", engRow)
	engNote:Dock(FILL)
	engNote:DockMargin(8, 0, 0, 0)
	engNote:SetFont("SPeditor.Small")
	engNote:SetTextColor(COL.ORANGE)
	engNote:SetText("")
	engRow.Think = function()
		local text = ""
		if R.EngineMode() then
			local W, H = C.GetRenderSize()
			local cw, ch = R.EngineCropSize(W / H)
			text = string.format(L("render_engine_size"), cw, ch)
		end
		if engNote.SPText ~= text then
			engNote.SPText = text
			engNote:SetText(text)
		end
		-- smoothing and depth of field are not applied in this mode
		local off = R.EngineMode()
		if ssBox.SPOff ~= off then
			ssBox.SPOff = off
			ssBox:SetEnabled(not off)
			dofBox:SetEnabled(not off)
		end
	end

	-- Format, quality: the picture only (the video has its own size and quality)
	local stillBottom = group()
	local rf = row(stillBottom, L("render_format"))
	local fmtBox = vgui.Create("DComboBox", rf)
	fmtBox:Dock(FILL)
	styleCombo(fmtBox)
	local cur = GetConVar("gmfm_render_format"):GetString()
	fmtBox:AddChoice("PNG", "png", cur ~= "jpeg" and cur ~= "steam")
	fmtBox:AddChoice("JPEG", "jpeg", cur == "jpeg")
	fmtBox:AddChoice(L("render_fmt_steam"), "steam", cur == "steam")
	fmtBox.OnSelect = function(_, _, _, data) RunConsoleCommand("gmfm_render_format", data) end

	local q = UI.Slider(stillBottom, L("render_quality"), 1, 100, 0, GetConVar("gmfm_render_quality"):GetInt(), function(v)
		RunConsoleCommand("gmfm_render_quality", tostring(math.floor(v)))
	end)

	-- File name
	local rn = row(body, L("render_filename"))
	nameBox = vgui.Create("DTextEntry", rn)
	nameBox:Dock(FILL)
	nameBox:SetPlaceholderText(L("render_filename_ph"))

	local info = vgui.Create("DLabel", stillBottom)
	info:Dock(TOP)
	info:DockMargin(8, 8, 8, 0)
	info:SetWrap(true)
	info:SetAutoStretchVertical(true)
	info:SetTextColor(COL.DIM)
	info:SetText(L("render_info"))

	-- Camera effects: of the chosen scene camera (or of the one the Primary Viewport looks through)
	buildEffects(body, function()
		local c = shotCamera()
		if isstring(c) then return c == "cuts" and SPeditor.Export.SceneCamera(nil) or nil end
		return SPeditor.Export.SceneCamera(c)
	end)

	setTab = function(t)
		if t == "anim" and not ctx.animated then t = "still" end
		tab = t
		UI.renderTab = t
		stillTop:SetVisible(t == "still")
		stillBottom:SetVisible(t == "still")
		animHost:SetVisible(t == "anim")
		if ctx.setMode then ctx.setMode(t == "anim" and "anim" or "frame") end
		go:SetText("  " .. L(t == "anim" and "render_go_anim" or "act_render"))
		go:SetIcon(t == "anim" and "icon16/film_save.png" or "icon16/picture_save.png")
		if preview then preview.next = 0 end
		body:InvalidateLayout(true)
	end
	-- an animated scene opens on the Animation tab; afterwards the window keeps the last one
	setTab(UI.renderTab or ((ctx.animated and ctx.animated()) and "anim" or "still"))
	win.SPSetTab = setTab

	local baseRemove = win.OnRemove
	win.OnRemove = function(s)
		if baseRemove then baseRemove(s) end
		-- the window is removed with a one-frame delay: by then a new one may already be
		-- open (interface rebuild on a theme change) — its state is left alone
		if UI.RenderWin == s then UI.RenderWin = nil end
		if UI.RenderPreview == preview then UI.RenderPreview = nil end
	end
end
