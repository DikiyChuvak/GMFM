--[[
SAeditor — a0.5 windows: procedural motion of an object and Stop Motion Helper saves.

Procedural motion (SA.OpenProc): breathing, blinking and a living head for characters, a slow
drift for props and lights. It is worked out from the time of the frame on the server
(sv_saeditor.lua, SA.ProcApply), shows during playback and in the render, and is saved
with the scene.

Stop Motion Helper (SA.OpenSMH): an SMH save (garrysmod/data/smh/<name>.txt) is taken onto
the selected object as keys, and the animation of the selected objects is written as an
SMH save that SMH loads as it loads its own (Load → the model's name).
]]
local COMP  = SPeditor.Component("saeditor")
local SA   = COMP.SA
local C    = SPeditor.Client
local UI   = SPeditor.UI
local Dock = SPeditor.Dock
local L    = SPeditor.L
local COL  = UI.PAL

-- a hint that wraps onto several lines
local function hint(parent, text)
	local l = vgui.Create("DLabel", parent)
	l:Dock(TOP)
	l:DockMargin(8, 6, 8, 4)
	l:SetFont("SPeditor.Small")
	l:SetTextColor(COL.DIM)
	l:SetWrap(true)
	l:SetAutoStretchVertical(true)
	l:SetText(text)
	return l
end

---------------------------------------------------------------------
-- Procedural motion
---------------------------------------------------------------------
local PROC_DEFAULT = { breath = 0, rate = 14, blink = 0, head = 0, sway = 0, freq = 0.3 }

function SA.SendProc(uid, t)
	COMP:NetStart("Proc")
	net.WriteUInt(uid, 32)
	SPeditor.WriteTable(t)
	net.SendToServer()
end

function SA.OpenProc(ent)
	ent = ent or C.selected
	local uid = SA.UID(ent)
	if uid == 0 or C.IsCamera(ent) then
		SPeditor.Notify(L("sa_proc_need"), 0)
		return
	end
	local old = Dock.ByKey("sa_proc")
	if IsValid(old) then old:Remove() end
	local W = 380
	local win, body = Dock.Create({ key = "sa_proc", id = "sa_proc", title = L("sa_proc_title") .. ": " .. C.DisplayName(ent), w = W, h = 330,
			x = math.floor(ScrW() / 2 - W / 2), y = 160, dockable = false, icon = "icon16/heart.png" })
	win.minW, win.minH = UI.S(300), UI.S(260)

	local cur = table.Copy(SA.proc and SA.proc[uid] or PROC_DEFAULT)
	for k, v in pairs(PROC_DEFAULT) do if cur[k] == nil then cur[k] = v end end
	local function send()
		timer.Create("SAeditor.Proc", 0.15, 1, function()
			if IsValid(ent) then SA.SendProc(uid, cur) end
		end)
	end

	hint(body, L("sa_proc_hint"))
	local isRag, hasFace = C.IsRagdoll(ent), not C.IsAux(ent) and ent:GetFlexNum() > 0
	local function slider(key, min, max, dec)
		local s = UI.Slider(body, L("sa_proc_" .. key), min, max, dec, cur[key], function(v)
			cur[key] = v
			send()
		end)
		s:DockMargin(8, 2, 8, 2)
		return s
	end
	if not C.IsAux(ent) then
		slider("breath", 0, 1, 2)
		slider("rate", 4, 40, 0)
	end
	if hasFace then slider("blink", 0, 1, 2) end
	if isRag then slider("head", 0, 1, 2) end
	if not isRag then slider("sway", 0, 64, 1) end
	if isRag or not C.IsAux(ent) or C.IsLight(ent) or C.IsEffect(ent) then slider("freq", 0.02, 4, 2) end

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(34))
	foot.Paint = function() end
	local play = vgui.Create("DButton", foot)
	play:Dock(LEFT)
	play:DockMargin(8, 5, 4, 5)
	play:SetWide(UI.S(210))
	play:SetText(L("sa_proc_preview"))
	play:SetIcon("icon16/control_play_blue.png")
	UI.StyleButton(play, nil, 3)
	play.DoClick = function() SA.Play() end
	local off = vgui.Create("DButton", foot)
	off:Dock(RIGHT)
	off:DockMargin(4, 5, 8, 5)
	off:SetWide(UI.S(110))
	off:SetText(L("sa_proc_off"))
	UI.StyleButton(off, nil, 3)
	off.DoClick = function()
		SA.SendProc(uid, {})
		win:Close()
	end
	return win
end

---------------------------------------------------------------------
-- Stop Motion Helper
---------------------------------------------------------------------
SA.smh = SA.smh or { files = {} }

local function smhSend(action, t)
	COMP:NetStart("SMH")
	net.WriteUInt(action, 2)
	if t then SPeditor.WriteTable(t) end
	net.SendToServer()
end

COMP:NetReceive("SMH", function()
	local t = SPeditor.ReadTable() or {}
	SA.smh.files = istable(t.files) and t.files or {}
	if SA.smh.onList then SA.smh.onList() end
end)

function SA.OpenSMH()
	local old = Dock.ByKey("sa_smh")
	if IsValid(old) then old:Remove() end
	local W = 560
	local win, body = Dock.Create({ key = "sa_smh", id = "sa_smh", title = L("sa_smh_title"), w = W, h = 520,
			x = math.floor(ScrW() / 2 - W / 2), y = 120, dockable = false, icon = "icon16/arrow_switch.png" })
	win.minW, win.minH = UI.S(440), UI.S(420)

	hint(body, L("sa_smh_hint"))

	-- export (bottom)
	local exp = vgui.Create("DPanel", body)
	exp:Dock(BOTTOM)
	exp:SetTall(UI.S(64))
	exp:DockMargin(8, 4, 8, 8)
	exp.Paint = function(_, w, h)
		surface.SetDrawColor(COL.ROW_B)
		surface.DrawRect(0, 0, w, h)
	end
	local expLbl = vgui.Create("DLabel", exp)
	expLbl:Dock(TOP)
	expLbl:DockMargin(8, 4, 8, 0)
	expLbl:SetFont("SPeditor.Small")
	expLbl:SetTextColor(COL.TEXT)
	expLbl:SetText(L("sa_smh_export_hint"))
	local expRow = vgui.Create("DPanel", exp)
	expRow:Dock(FILL)
	expRow:DockMargin(8, 4, 8, 6)
	expRow.Paint = function() end
	local expName = vgui.Create("DTextEntry", expRow)
	expName:Dock(FILL)
	expName:SetValue((C.sceneName and C.sceneName ~= "") and C.sceneName or "speditor_anim")
	local expBtn = vgui.Create("DButton", expRow)
	expBtn:Dock(RIGHT)
	expBtn:DockMargin(6, 0, 0, 0)
	expBtn:SetWide(UI.S(170))
	expBtn:SetText(L("sa_smh_export"))
	expBtn:SetIcon("icon16/page_save.png")
	UI.StyleButton(expBtn, true, 3)
	expBtn.DoClick = function()
		local uids = {}
		for _, e in ipairs(C.SelectionList()) do
			local u = SA.UID(e)
			if u ~= 0 and SA.tracks[u] then uids[#uids + 1] = u end
		end
		if #uids == 0 then SPeditor.Notify(L("sa_smh_need_anim"), 0) return end
		smhSend(2, { file = expName:GetValue(), uids = uids })
	end

	-- import options
	local opts = vgui.Create("DPanel", body)
	opts:Dock(BOTTOM)
	opts:SetTall(UI.S(120))
	opts:DockMargin(8, 4, 8, 0)
	opts.Paint = function(_, w, h)
		surface.SetDrawColor(COL.ROW_B)
		surface.DrawRect(0, 0, w, h)
	end
	local target = vgui.Create("DLabel", opts)
	target:Dock(TOP)
	target:DockMargin(8, 4, 8, 0)
	target:SetFont("SPeditor.Small")
	target:SetTextColor(COL.TEXT)
	target.Think = function(s2)
		local t = IsValid(C.selected) and C.DisplayName(C.selected) or L("sa_smh_no_target")
		s2:SetText(L("sa_smh_target") .. ": " .. t)
	end
	local start = UI.Slider(opts, L("sa_smh_start"), 0, math.max(SA.frames, 1), 0, 0, nil)
	start:DockMargin(8, 0, 8, 0)
	local row = vgui.Create("DPanel", opts)
	row:Dock(TOP)
	row:SetTall(UI.S(24))
	row:DockMargin(8, 2, 8, 0)
	row.Paint = function() end
	local conv = vgui.Create("DCheckBoxLabel", row)
	conv:Dock(LEFT)
	conv:SetWide(UI.S(330))
	conv:SetText(L("sa_smh_conv"))
	conv:SetTextColor(COL.TEXT)
	conv:SetValue(false)
	local fps = vgui.Create("DNumberWang", row)
	fps:Dock(LEFT)
	fps:SetWide(UI.S(50))
	fps:SetMinMax(1, 120)
	fps:SetValue(30)
	local row2 = vgui.Create("DPanel", opts)
	row2:Dock(TOP)
	row2:SetTall(UI.S(22))
	row2:DockMargin(8, 2, 8, 0)
	row2.Paint = function() end
	local world = vgui.Create("DCheckBoxLabel", row2)
	world:Dock(LEFT)
	world:SetWide(UI.S(330))
	world:SetText(L("sa_smh_world"))
	world:SetTextColor(COL.TEXT)
	world:SetValue(false)

	-- lists
	local lists = vgui.Create("DPanel", body)
	lists:Dock(FILL)
	lists:DockMargin(8, 0, 8, 0)
	lists.Paint = function() end
	local files = vgui.Create("DListView", lists)
	UI.StyleListView(files)
	files:Dock(LEFT)
	files:SetWide(UI.S(250))
	files:SetMultiSelect(false)
	files:AddColumn(L("sa_smh_file"))
	files:AddColumn(L("sa_smh_map")):SetFixedWidth(90)
	local objs = vgui.Create("DListView", lists)
	UI.StyleListView(objs)
	objs:Dock(FILL)
	objs:DockMargin(6, 0, 0, 0)
	objs:SetMultiSelect(false)
	objs:AddColumn(L("sa_smh_object"))
	objs:AddColumn(L("sa_smh_keys")):SetFixedWidth(50)

	local imp = vgui.Create("DButton", opts)
	imp:SetText(L("sa_smh_import"))
	imp:SetIcon("icon16/page_go.png")
	UI.StyleButton(imp, true, 3)
	opts.PerformLayout = function(_, w)
		imp:SetPos(w - 178, 4)
		imp:SetSize(UI.S(170), UI.S(22))
	end

	local curFile
	files.OnRowSelected = function(_, _, line)
		curFile = line.smh
		objs:Clear()
		for _, e in ipairs(curFile.ents or {}) do
			if not e.world then
				local l = objs:AddLine(e.name, tostring(e.frames))
				l.ent = e
			end
		end
		-- the save was made on this map: its places fit as they are
		world:SetValue(curFile.map == game.GetMap())
	end
	imp.DoClick = function()
		local _, line = objs:GetSelectedLine()
		if not curFile or not line then SPeditor.Notify(L("sa_smh_pick"), 0) return end
		local uid = SA.UID(C.selected)
		if uid == 0 or C.IsAux(C.selected) then SPeditor.Notify(L("sa_smh_no_target"), 0) return end
		local id = SA.NextOp()
		smhSend(1, { op = id, file = curFile.file, ent = line.ent.name, uid = uid, start = math.floor(start:GetValue()),
			fps = conv:GetChecked() and fps:GetValue() or 0, world = world:GetChecked() })
		SA.PushOpHistory("sa smh", id)
	end

	SA.smh.onList = function()
		if not IsValid(files) then return end
		files:Clear()
		objs:Clear()
		for _, f in ipairs(SA.smh.files) do
			local l = files:AddLine(f.file, f.map)
			l.smh = f
		end
		if #SA.smh.files == 0 then objs:AddLine(L("sa_smh_none"), "") end
	end
	smhSend(0)
	return win
end

---------------------------------------------------------------------
-- Animations from addons (a0.6): animation packs ("animation collections") are models whose
-- only content is animations — the model browser hides them. This window lists them for
-- every installed addon, Workshop or legacy (a folder in garrysmod/addons), and gives the
-- chosen one to the import as the source of animations. done(model) is called with its path.
---------------------------------------------------------------------
-- how many bones of the character the model has by name, and how many animations
local function animInfo(ent, model)
	local temp = ClientsideModel(model, RENDERGROUP_OTHER)
	if not IsValid(temp) then return nil end
	temp:SetNoDraw(true)
	local seqs, hit, total = 0, 0, 0
	for id in pairs(temp:GetSequenceList() or {}) do
		if (temp:SequenceDuration(id) or 0) > 0.05 then seqs = seqs + 1 end
	end
	if IsValid(ent) then
		for b = 0, ent:GetBoneCount() - 1 do
			local name = ent:GetBoneName(b)
			if name and name ~= "__INVALIDBONE__" then
				total = total + 1
				if temp:LookupBone(name) then hit = hit + 1 end
			end
		end
	end
	temp:Remove()
	return seqs, hit, total
end

function SA.OpenAnimModels(ent, done)
	local old = Dock.ByKey("sa_animsrc")
	if IsValid(old) then old:Remove() end
	local W = 620
	local win, body = Dock.Create({ key = "sa_animsrc", id = "sa_animsrc", title = L("sa_asrc_title"), w = W, h = 480,
			x = math.floor(ScrW() / 2 - W / 2), y = 130, dockable = false, icon = "icon16/package_go.png" })
	win.minW, win.minH = UI.S(480), UI.S(360)
	hint(body, L("sa_asrc_hint"))

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(30))
	foot:DockMargin(6, 2, 6, 6)
	foot.Paint = function() end
	local info = vgui.Create("DLabel", foot)
	info:Dock(FILL)
	info:SetFont("SPeditor.Small")
	info:SetTextColor(COL.DIM)
	info:SetText("")
	local go = UI.Button(foot, L("sa_asrc_go"), "icon16/film_add.png", function() end, 26)
	go:Dock(RIGHT)
	go:SetWide(UI.S(190))
	go:SetEnabled(false)

	local div = vgui.Create("DHorizontalDivider", body)
	div:Dock(FILL)
	div:DockMargin(6, 0, 6, 0)
	div:SetLeftWidth(230)
	local addons = vgui.Create("DListView", div)
	UI.StyleListView(addons)
	addons:SetMultiSelect(false)
	addons:AddColumn(L("sa_asrc_addon"))
	local right = vgui.Create("DPanel", div)
	right.Paint = function() end
	div:SetLeft(addons)
	div:SetRight(right)

	local all = false
	local allBox = UI.Check(right, L("sa_asrc_all"), false)
	local models = vgui.Create("DListView", right)
	UI.StyleListView(models)
	models:Dock(FILL)
	models:SetMultiSelect(false)
	models:AddColumn(L("sa_asrc_model"))
	for _, lv in ipairs({ addons, models }) do
		if lv.SetBackgroundColor then lv:SetBackgroundColor(COL.LIST_BG) end
	end

	local current, picked
	local function fillModels(list, finished, anims)
		models:Clear()
		local shown = 0
		for _, m in ipairs(anims or {}) do
			models:AddLine(m).SPModel = m
			shown = shown + 1
		end
		if all then
			for _, m in ipairs(list or {}) do models:AddLine(m).SPModel = m end
		end
		if finished and shown == 0 and not all then info:SetText(L("sa_asrc_none")) end
	end
	local function open(src)
		current = src
		picked = nil
		go:SetEnabled(false)
		info:SetText(L("browser_indexing"))
		UI.ScanSourceModels(src.pathId, src.prefix, function(list, finished, anims)
			if current ~= src or not IsValid(models) then return end
			src.list, src.anims, src.finished = list, anims, finished
			if finished then info:SetText("") end
			fillModels(list, finished, anims)
		end)
	end
	allBox.OnChange = function(_, v)
		all = v
		if current then fillModels(current.list, current.finished, current.anims) end
	end

	-- the sources: Workshop addons with models, then legacy addons
	-- addons named like animation packs go first
	local ws = table.Copy(UI.AddonsWithModels(""))
	local function animy(a) return string.find(string.lower(a.title), "anim", 1, true) and 0 or 1 end
	table.sort(ws, function(x, y)
		if animy(x) ~= animy(y) then return animy(x) < animy(y) end
		return string.lower(x.title) < string.lower(y.title)
	end)
	for _, a in ipairs(ws) do
		addons:AddLine(a.title).SPSrc = { pathId = a.title }
	end
	for _, a in ipairs(UI.LegacyAddons()) do
		if a.models then addons:AddLine("[addons] " .. a.name).SPSrc = { pathId = "MOD", prefix = "addons/" .. a.name .. "/" } end
	end
	addons.OnRowSelected = function(_, _, line) open(line.SPSrc) end

	models.OnRowSelected = function(_, _, line)
		picked = line.SPModel
		local seqs, hit, total = animInfo(ent, picked)
		if not seqs then
			info:SetText(L("sa_asrc_bad"))
			go:SetEnabled(false)
			return
		end
		info:SetText(string.format(L("sa_asrc_info"), seqs, hit, total))
		go:SetEnabled(seqs > 0 and (total == 0 or hit > 0))
	end
	local function choose()
		if not picked then return end
		win:Remove()
		done(picked)
	end
	go.DoClick = choose
	models.DoDoubleClick = choose
	return win
end
