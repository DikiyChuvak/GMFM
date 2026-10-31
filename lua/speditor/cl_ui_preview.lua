--[[
SPeditor — small previews for the browsers (a0.9), as in SFM: before a model or a particle system
is put into the scene, it is shown on its own.

  UI.ModelPreview(parent)      a panel: the model turns slowly in its idle animation; drag —
                               turn it yourself, wheel — closer / farther.  :SetModel(path)
  UI.ParticlePreview(parent)   a panel: the particle system plays over and over, the camera
                               widens to what it has emitted.  :SetEffect(item)  (item.src = "pcf")
                               Effects that play by themselves in the world (util.Effect, the
                               Emitter tool) cannot be drawn apart from it: the panel says so.

3D drawn from a panel's Paint does not show inside the editor's windows (measured in game: not
even a sphere), so every preview is drawn into its own render target in PostRender, the way the
render preview is, and the panel only shows that texture. The model is a ClientsideModel and the
particle system is made far above the player; neither is drawn in the world (SetNoDraw,
SetShouldDraw(false)) — the preview draws them itself (DrawModel, CNewParticleEffect:Render).
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI = SPeditor.UI
local L  = SPeditor.L
local COL = UI.PAL

local RT_SIZE = 512
local previews = setmetatable({}, { __mode = "k" })    -- [panel] = true
local serial = 0

local matShow = CreateMaterial("speditor_preview_show", "UnlitGeneric", { ["$nolod"] = "1" })

-- a preview panel: its texture, the size it is drawn at, and its own draw function (s:SPDraw())
local function newPreview(parent)
	local p = vgui.Create("DPanel", parent)
	serial = serial + 1
	p.SPRT = GetRenderTarget("speditor_preview_" .. serial, RT_SIZE, RT_SIZE)
	previews[p] = true
	p.SPShow = function(s, w, h)
		s.SPPainted = RealTime()
		local k = math.min(RT_SIZE / math.max(w, 1), RT_SIZE / math.max(h, 1), 1)
		s.SPW, s.SPH = math.max(math.floor(w * k), 8), math.max(math.floor(h * k), 8)
		if not s.SPReady then return end
		matShow:SetTexture("$basetexture", s.SPRT)
		surface.SetMaterial(matShow)
		surface.SetDrawColor(255, 255, 255, 255)
		SPeditor.Render.DrawTexturedUV(0, 0, w, h, s.SPW / RT_SIZE, s.SPH / RT_SIZE)
	end
	return p
end

SPeditor.Hook("PostRender", "SPeditor.Previews", function()
	local now = RealTime()
	for p in pairs(previews) do
		-- only what was on screen a moment ago
		if IsValid(p) and p.SPDraw and p.SPW and now - (p.SPPainted or 0) < 0.25 then
			render.PushRenderTarget(p.SPRT)
			render.Clear(20, 20, 24, 255, true, true)
			local ok, err = pcall(p.SPDraw, p, p.SPW, p.SPH)
			render.PopRenderTarget()
			if not ok then
				ErrorNoHalt("[GM:FM] preview: " .. tostring(err) .. "\n")
				p.SPDraw = nil
			end
			p.SPReady = true
		end
	end
end)

local function caption(w, h, text, col)
	draw.SimpleText(text, "SPeditor.Small", w / 2, h - 4, col or COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
end
local function middleText(w, h, a, b)
	draw.SimpleText(a, "SPeditor.Small", w / 2, h / 2 - (b and 8 or 0), COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	if b then draw.SimpleText(b, "SPeditor.Small", w / 2, h / 2 + 8, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
end
local function frame(w, h)
	surface.SetDrawColor(COL.BORDER)
	surface.DrawOutlinedRect(0, 0, w, h, 1)
end

---------------------------------------------------------------------
-- Models
---------------------------------------------------------------------
local IDLE = { "idle_all_01", "idle_subtle", "idle01", "idle", "ragdoll", "reference" }

-- (b0.2.6) As the preview of SFM's "Select .MDL file": the model stands on a floor grid, and the
-- tabs under it (UI.ModelPreviewTabs) switch the wireframe, the collision model, the floor, the
-- turning and the eyes, play any sequence or activity of the model and show its skins. The
-- skin picked here is the one a click puts into the scene (C.SpawnModel, cl_ui_model_list.lua).
local matWire = Material("models/wireframe")
local GRID_COL = Color(150, 150, 155)

-- boxes of the solids of a model's collision model, in the space of their bones: the game gives
-- no shape of a solid to Lua, so each is measured by tracing at it from 14 directions
local function collisionBoxes(path, ent)
	local out = {}
	local solids = CreatePhysCollidesFromModel(path)
	if not solids then return out end
	local info = util.GetModelInfo(path)
	local names = {}
	if info and isstring(info.KeyValues) then
		for block in string.gmatch(info.KeyValues, '"solid"%s*(%b{})') do
			local idx = tonumber(string.match(block, '"index"%s*"(%-?%d+)"'))
			local name = string.match(block, '"name"%s*"([^"]+)"')
			if idx then names[idx] = name end
		end
	end
	local DIRS = { Vector(1, 0, 0), Vector(-1, 0, 0), Vector(0, 1, 0), Vector(0, -1, 0), Vector(0, 0, 1), Vector(0, 0, -1),
		Vector(1, 1, 1), Vector(-1, 1, 1), Vector(1, -1, 1), Vector(1, 1, -1), Vector(-1, -1, 1), Vector(-1, 1, -1), Vector(1, -1, -1), Vector(-1, -1, -1) }
	for i, pc in ipairs(solids) do
		local mn, mx = Vector(1e9, 1e9, 1e9), Vector(-1e9, -1e9, -1e9)
		local hits = 0
		for _, d in ipairs(DIRS) do
			local dir = d:GetNormalized()
			local hit, _, frac = pc:TraceBox(vector_origin, angle_zero, dir * 512, vector_origin, Vector(0, 0, 0), Vector(0, 0, 0))
			-- a trace that "hits" where it starts has missed
			if hit and (frac or 0) > 0.001 and hit:Length() < 500 then
				hits = hits + 1
				mn.x, mn.y, mn.z = math.min(mn.x, hit.x), math.min(mn.y, hit.y), math.min(mn.z, hit.z)
				mx.x, mx.y, mx.z = math.max(mx.x, hit.x), math.max(mx.y, hit.y), math.max(mx.z, hit.z)
			end
		end
		if hits >= 2 then
			local bone = names[i - 1] and ent:LookupBone(names[i - 1]) or nil
			out[#out + 1] = { bone = bone, mn = mn, mx = mx }
		end
		pc:Destroy()
	end
	return out
end

function UI.ModelPreview(parent)
	local mp = newPreview(parent)
	mp.SPYaw, mp.SPZoom = 30, 1
	-- the Render tab of SFM's preview
	mp.SPOpt = { wire = false, collision = false, noground = false, lock = false, lookcam = true }

	local function drop(s)
		if IsValid(s.SPEnt) then s.SPEnt:Remove() end
		s.SPEnt = nil
	end

	function mp:SetModel(path)
		if not isstring(path) or path == self.SPPath then return end
		self.SPPath = path
		drop(self)
		self.SPSeq, self.SPSkin, self.SPBoxes = nil, 0, nil
		local ent = ClientsideModel(path, RENDERGROUP_OPAQUE)
		if not IsValid(ent) then return end
		ent:SetNoDraw(true)
		ent:SetIK(false)
		for _, name in ipairs(IDLE) do
			local seq = ent:LookupSequence(name)
			if seq and seq > 0 then
				ent:ResetSequence(seq)
				self.SPSeq = seq
				break
			end
		end
		self.SPEnt = ent
		self.SPInfo = string.format("%s  ·  %d %s", string.GetFileFromFilename(path), ent:GetBoneCount(), L("pv_bones"))
		if self.OnModelChanged then self:OnModelChanged(ent) end
	end

	function mp:PlaySequence(seq)
		local ent = self.SPEnt
		if not IsValid(ent) or not seq or seq < 0 then return end
		ent:ResetSequence(seq)
		ent:SetCycle(0)
		self.SPSeq = seq
	end

	function mp:SetPreviewSkin(skin)
		local ent = self.SPEnt
		if not IsValid(ent) then return end
		self.SPSkin = math.Clamp(math.floor(skin or 0), 0, math.max(ent:SkinCount() - 1, 0))
		ent:SetSkin(self.SPSkin)
	end

	mp.SPDraw = function(s, w, h)
		local ent = s.SPEnt
		if not IsValid(ent) then return end
		local opt = s.SPOpt
		if s.SPDrag and not opt.lock then
			local x = gui.MouseX()
			s.SPYaw = s.SPYaw + (x - s.SPDrag) * 0.6
			s.SPDrag = x
		elseif not s:IsHovered() and not opt.lock then
			s.SPYaw = s.SPYaw + FrameTime() * 25
		end
		ent:SetAngles(Angle(0, s.SPYaw, 0))
		ent:FrameAdvance(FrameTime())
		-- a sequence that does not loop starts over when it has played (as SFM's preview)
		if ent:GetCycle() >= 0.999 then ent:SetCycle(0) end
		ent:SetupBones()
		-- the camera looks at the middle of the model from as far as its size asks
		local mn, mx = ent:GetRenderBounds()
		local size = math.max((mx - mn):Length(), 8)
		local mid = ent:GetPos() + (mn + mx) * 0.5
		-- far enough for the model to fit both ways, whatever the panel's proportions
		local tx = math.tan(math.rad(32) / 2)
		local dist = size * 0.6 / math.min(tx, tx * h / math.max(w, 1)) * s.SPZoom
		local pos = mid + Vector(dist, 0, size * 0.2 * s.SPZoom)
		-- the eyes: at the camera, or straight ahead
		ent:SetEyeTarget(opt.lookcam and pos or (mid + ent:GetForward() * size * 4))
		cam.Start3D(pos, (mid - pos):Angle(), 32, 0, 0, w, h, 1, dist * 4)
		-- the floor: a grid under the feet, as in SFM
		if not opt.noground then
			local z = ent:GetPos().z + mn.z
			local half = math.max(size * 0.9, 24)
			local step = half / 6
			render.SetColorMaterial()
			for i = -6, 6 do
				local o = i * step
				render.DrawLine(Vector(o, -half, z), Vector(o, half, z), GRID_COL, true)
				render.DrawLine(Vector(-half, o, z), Vector(half, o, z), GRID_COL, true)
			end
		end
		render.SuppressEngineLighting(true)
		render.SetLightingOrigin(mid)
		render.ResetModelLighting(0.35, 0.35, 0.38)
		render.SetModelLighting(BOX_TOP, 1, 1, 1)
		render.SetModelLighting(BOX_FRONT, 0.9, 0.9, 0.9)
		render.SetModelLighting(BOX_RIGHT, 0.6, 0.6, 0.65)
		if opt.wire then render.MaterialOverride(matWire) end
		ent:DrawModel()
		if opt.wire then render.MaterialOverride() end
		render.SuppressEngineLighting(false)
		-- the collision model: the box of every solid on its bone
		if opt.collision then
			s.SPBoxes = s.SPBoxes or collisionBoxes(s.SPPath, ent)
			for _, b in ipairs(s.SPBoxes) do
				local bp, ba = ent:GetPos(), ent:GetAngles()
				if b.bone then
					local m = ent:GetBoneMatrix(b.bone)
					if m then bp, ba = m:GetTranslation(), m:GetAngles() end
				end
				render.DrawWireframeBox(bp, ba, b.mn, b.mx, Color(255, 170, 60), false)
			end
		end
		cam.End3D()
	end

	mp.Paint = function(s, w, h)
		surface.SetDrawColor(COL.VIEW_BG or COL.LIST_BG)
		surface.DrawRect(0, 0, w, h)
		if not s.SPPath then
			s.SPPainted = RealTime()
			middleText(w, h, L("pv_model_hint"))
		else
			s:SPShow(w, h)
			caption(w, h, s.SPInfo or s.SPPath)
		end
		frame(w, h)
	end
	mp.OnMousePressed = function(s, code)
		if code == MOUSE_LEFT then
			s.SPDrag = gui.MouseX()
			s:MouseCapture(true)
		end
	end
	mp.OnMouseReleased = function(s)
		s.SPDrag = nil
		s:MouseCapture(false)
	end
	mp.OnMouseWheeled = function(s, d)
		s.SPZoom = math.Clamp(s.SPZoom * (d > 0 and 0.88 or 1.14), 0.25, 4)
		return true
	end
	mp.OnRemove = drop
	return mp
end

-- The tabs under a model preview, as in SFM: Render, Sequences, Activities, Skins
function UI.ModelPreviewTabs(parent, mp)
	-- a strip of tabs in the editor's colours and the page of the active one
	local sheet = vgui.Create("DPanel", parent)
	sheet.Paint = function(_, w, h) surface.SetDrawColor(COL.BG) surface.DrawRect(0, 0, w, h) end
	local strip = vgui.Create("DPanel", sheet)
	strip:Dock(TOP)
	strip:SetTall(UI.S(22))
	strip.Paint = function(_, w, h) surface.SetDrawColor(COL.HEADER) surface.DrawRect(0, 0, w, h) end
	local pages, active = {}, nil
	local function show(pg)
		active = pg
		for _, p in ipairs(pages) do p:SetVisible(p == pg) end
		sheet:InvalidateLayout()
	end
	function sheet:AddSheet(title, page)
		page:SetParent(sheet)
		page:Dock(FILL)
		pages[#pages + 1] = page
		local b = vgui.Create("DButton", strip)
		b:Dock(LEFT)
		b:SetText("")
		surface.SetFont("SPeditor.Small")
		b:SetWide(select(1, surface.GetTextSize(title)) + UI.S(16))
		b.Paint = function(s2, w, h)
			surface.SetDrawColor(active == page and COL.TAB_ON or (s2:IsHovered() and COL.HOVER or COL.TAB_OFF))
			surface.DrawRect(0, 0, w - 1, h)
			draw.SimpleText(title, "SPeditor.Small", w / 2, h / 2, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function() show(page) end
		if #pages == 1 then show(page) else page:SetVisible(false) end
	end

	-- Render
	local rp = vgui.Create("DPanel", sheet)
	rp.Paint = function(_, w, h) surface.SetDrawColor(COL.BG) surface.DrawRect(0, 0, w, h) end
	for _, o in ipairs({ { "wire", "pv_wire" }, { "collision", "pv_collision" }, { "noground", "pv_noground" },
			{ "lock", "pv_lock" }, { "lookcam", "pv_lookcam" } }) do
		local cb = vgui.Create("DCheckBoxLabel", rp)
		cb:Dock(TOP)
		cb:DockMargin(8, 6, 4, 0)
		cb:SetText(L(o[2]))
		cb:SetFont("SPeditor.Small")
		cb:SetTextColor(COL.TEXT)
		cb:SetChecked(mp.SPOpt[o[1]])
		cb.OnChange = function(_, v) mp.SPOpt[o[1]] = v end
	end
	sheet:AddSheet(L("pv_tab_render"), rp)

	-- a list with a filter line on top: rows = { { text, data } }, pick(data) on a click
	local function filtered(onPick)
		local host = vgui.Create("DPanel", sheet)
		host.Paint = function(_, w, h) surface.SetDrawColor(COL.BG) surface.DrawRect(0, 0, w, h) end
		local filter = vgui.Create("DTextEntry", host)
		filter:Dock(TOP)
		filter:DockMargin(2, 2, 2, 2)
		filter:SetTall(UI.S(20))
		local list = vgui.Create("DListView", host)
		list:Dock(FILL)
		list:SetHeaderHeight(0)
		list:SetMultiSelect(false)
		list:AddColumn("")
		if UI.StyleListView then UI.StyleListView(list) end
		host.rows = {}
		function host:Fill(rows, current)
			self.rows = rows
			local q = string.lower(filter:GetValue() or "")
			list:Clear()
			for _, r in ipairs(rows) do
				if q == "" or string.find(string.lower(r[1]), q, 1, true) then
					local line = list:AddLine(r[1])
					line.SPData = r[2]
					if r[2] == current then line:SetSelected(true) end
				end
			end
		end
		filter.OnChange = function() host:Fill(host.rows, nil) end
		list.OnRowSelected = function(_, _, line) onPick(line.SPData) end
		host.filter = filter
		return host
	end

	local seqs = filtered(function(seq) mp:PlaySequence(seq) end)
	seqs.filter:SetPlaceholderText(L("pv_seq_filter"))
	sheet:AddSheet(L("pv_tab_seq"), seqs)
	local acts = filtered(function(seq) mp:PlaySequence(seq) end)
	acts.filter:SetPlaceholderText(L("pv_act_filter"))
	sheet:AddSheet(L("pv_tab_act"), acts)
	local skins = filtered(function(skin) mp:SetPreviewSkin(skin) end)
	skins.filter:SetPlaceholderText(L("pv_skin_filter"))
	sheet:AddSheet(L("pv_tab_skin"), skins)

	mp.OnModelChanged = function(_, ent)
		local srows, arows, seen = {}, {}, {}
		for i = 0, ent:GetSequenceCount() - 1 do
			local name = ent:GetSequenceName(i)
			srows[#srows + 1] = { name, i }
			local act = ent:GetSequenceActivityName(i)
			if act and act ~= "" and not seen[act] then
				seen[act] = true
				-- an activity plays the sequence the game would pick for it
				local id = ent:GetSequenceActivity(i)
				local pick = (id and id >= 0) and ent:SelectWeightedSequence(id) or i
				arows[#arows + 1] = { act, (pick and pick >= 0) and pick or i }
			end
		end
		local krows = {}
		for i = 0, math.max(ent:SkinCount() - 1, 0) do krows[#krows + 1] = { "skin" .. i, i } end
		seqs:Fill(srows, mp.SPSeq)
		acts:Fill(arows, nil)
		skins:Fill(krows, 0)
	end
	if IsValid(mp.SPEnt) then mp:OnModelChanged(mp.SPEnt) end
	return sheet
end

---------------------------------------------------------------------
-- Particle systems
---------------------------------------------------------------------
local LOOP_MAX = 6          -- a system that keeps going is started over after this long, seconds
local REST     = 0.6        -- a pause between two plays, seconds
local MAX_R    = 500        -- the widest view: some systems have huge bounds (explosion_huge)

function UI.ParticlePreview(parent)
	local pp = newPreview(parent)
	pp.SPRadius = 16

	local function kill(s)
		if s.SPPS and s.SPPS:IsValid() then s.SPPS:StopEmissionAndDestroyImmediately() end
		s.SPPS = nil
	end
	local function start(s)
		kill(s)
		local it = s.SPItem
		if not it or it.src ~= "pcf" then return end
		if it.file and it.file ~= "" and not SPeditor.Effects.Stock()[string.lower(it.file)] and file.Exists(it.file, "GAME") then
			game.AddParticles(it.file)
		end
		PrecacheParticleSystem(it.name)
		local ply = LocalPlayer()
		s.SPOrg = (IsValid(ply) and ply:GetPos() or vector_origin) + Vector(0, 0, 4000)
		local ok, ps = pcall(CreateParticleSystemNoEntity, it.name, s.SPOrg, angle_zero)
		if not ok or not ps or not ps:IsValid() then
			s.SPBroken = true
			return
		end
		ps:SetShouldDraw(false)
		-- a second point a little ahead: beams and tracers have somewhere to go
		ps:SetControlPoint(1, s.SPOrg + Vector(96, 0, 0))
		s.SPPS, s.SPT0, s.SPBroken = ps, RealTime(), nil
	end

	function pp:SetEffect(item)
		if item == self.SPItem then return end
		self.SPItem = item
		self.SPRadius, self.SPWait, self.SPMid, self.SPMidGoal = 16, nil, nil, nil
		start(self)
	end

	pp.Think = function(s)
		if not s.SPItem or s.SPItem.src ~= "pcf" or s.SPBroken then return end
		local now = RealTime()
		-- not on screen (another tab of the dock, the window closed): nothing keeps running
		if now - (s.SPPainted or 0) > 0.5 then
			if s.SPPS then kill(s) s.SPWait = now end
			return
		end
		if s.SPWait then
			if now >= s.SPWait then
				s.SPWait = nil
				start(s)
			end
			return
		end
		local ps = s.SPPS
		if not ps or not ps:IsValid() or ps:IsFinished() or now - (s.SPT0 or now) > LOOP_MAX then
			kill(s)
			s.SPWait = now + REST
		end
	end
	pp.OnRemove = kill

	pp.SPDraw = function(s, w, h)
		local ps, org = s.SPPS, s.SPOrg
		if not ps or not ps:IsValid() then return end
		-- the camera widens (never narrows within a play) to everything emitted so far and follows its
		-- middle; the
		-- bounds are around the system's own point (measured in game)
		local mn, mx = ps:GetRenderBounds()
		if mn and mx and mx.x >= mn.x then
			s.SPRadius = math.max(s.SPRadius, math.Clamp((mx - mn):Length() * 0.5, 16, MAX_R))
			local c = (mn + mx) * 0.5
			if c:Length() > MAX_R then c = c:GetNormalized() * MAX_R end
			s.SPMidGoal = c
		end
		local goal = org + (s.SPMidGoal or vector_origin)
		s.SPMid = s.SPMid and LerpVector(math.min(FrameTime() * 4, 1), s.SPMid, goal) or goal
		local dist = s.SPRadius * 2.6
		cam.Start3D(s.SPMid + Vector(-dist, -dist * 0.35, dist * 0.25), Angle(12, 19, 0), 50, 0, 0, w, h, 1, dist * 6)
		ps:Render()
		cam.End3D()
	end

	pp.Paint = function(s, w, h)
		surface.SetDrawColor(20, 20, 24, 255)
		surface.DrawRect(0, 0, w, h)
		local it = s.SPItem
		if not it then
			s.SPPainted = RealTime()
			middleText(w, h, L("pv_fx_hint"))
		elseif it.src ~= "pcf" then
			s.SPPainted = RealTime()
			middleText(w, h, L("pv_fx_live"), L("pv_fx_live2"))
		elseif s.SPBroken then
			s.SPPainted = RealTime()
			middleText(w, h, L("pv_fx_broken"))
		else
			s:SPShow(w, h)
		end
		if it then caption(w, h, it.name, COL.TEXT) end
		frame(w, h)
	end
	return pp
end
