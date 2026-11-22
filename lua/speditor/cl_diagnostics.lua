--[[
GM:FM — scene diagnostics (r1.0, Phase 4).

Help → Diagnostics checks the scene for the things that silently break a render:
models that the game cannot find, faces past the engine's 96 flex controllers, tracks
with keys past the end of the animation, and more light sources than GMod can shadow.
The check is local and read only — it never changes the scene.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI   = SPeditor.UI
local C    = SPeditor.Client
local L    = SPeditor.L
local Dock = SPeditor.Dock
local COL  = UI.PAL

local function line(parent, text, col)
	local l = vgui.Create("DLabel", parent)
	l:Dock(TOP)
	l:DockMargin(8, 2, 8, 0)
	l:SetFont("SPeditor.Small")
	l:SetTextColor(col or COL.TEXT)
	l:SetWrap(true)
	l:SetAutoStretchVertical(true)
	l:SetText(text)
	return l
end

function UI.OpenDiagnostics()
	local old = Dock.ByKey and Dock.ByKey("diagnostics")
	if IsValid(old) then old:Remove() end
	local W, H = 620, 520
	local win, body = Dock.Create({ key = "diagnostics", id = "diagnostics", title = L("diag_title"), w = W, h = H,
		x = math.floor(ScrW() / 2 - W / 2), y = 120, dockable = false, icon = "icon16/report_magnify.png" })
	win.minW, win.minH = UI.S(460), UI.S(320)

	local scroll = vgui.Create("DScrollPanel", body)
	scroll:Dock(FILL)

	local SA = SPeditor.Component and SPeditor.Component("saeditor") and SPeditor.Component("saeditor").SA
	local objects = C.BuildEntityList and C.BuildEntityList() or {}
	local issues, notes = {}, 0

	local function add(text)
		issues[#issues + 1] = text
		line(scroll, "•  " .. text, Color(235, 150, 90))
	end

	-- models the game cannot load (a missing addon is the usual reason)
	for _, o in ipairs(objects) do
		local ent = o.ent
		if IsValid(ent) and not C.IsAux(ent) then
			local mdl = ent:GetModel() or ""
			if mdl ~= "" and not file.Exists(mdl, "GAME") then
				add(string.format(L("diag_missing_model"), C.DisplayName(ent), mdl))
			end
			local nf = ent:GetFlexNum() or 0
			if nf > 96 then
				add(string.format(L("diag_flex_limit"), C.DisplayName(ent), nf))
			end
		end
	end

	-- tracks with keys past the animation, or without keys at all
	if SA then
		for uid, tr in pairs(SA.tracks or {}) do
			local ent = SA.EntByUID and SA.EntByUID(uid) or nil
			local name = IsValid(ent) and C.DisplayName(ent) or ("#" .. uid)
			local bad, lastF = 0, 0
			for _, k in ipairs(tr) do
				local f = tonumber(k.f or k[1]) or 0
				if f > lastF then lastF = f end
				if f > (SA.frames or 96) then bad = bad + 1 end
			end
			if bad > 0 then add(string.format(L("diag_keys_end"), name, bad)) end
			if #tr == 0 then notes = notes + 1 end
		end
	end

	-- GMod can cast only a few shadows at once
	local lights = 0
	for _, o in ipairs(objects) do
		if IsValid(o.ent) and C.IsLight(o.ent) then lights = lights + 1 end
	end
	if lights > 8 then add(string.format(L("diag_lights"), lights)) end

	if #issues == 0 then
		line(scroll, L("diag_clean"), Color(120, 210, 120))
	else
		line(scroll, string.format(L("diag_count"), #issues), COL.ORANGE)
	end
	line(scroll, string.format(L("diag_objects"), #objects), COL.DIM)
	if notes > 0 then line(scroll, string.format(L("diag_empty_tracks"), notes), COL.DIM) end

	local foot = vgui.Create("DPanel", body)
	foot:Dock(BOTTOM)
	foot:SetTall(UI.S(34))
	foot.Paint = function() end
	local close = vgui.Create("DButton", foot)
	close:Dock(RIGHT)
	close:DockMargin(4, 5, 8, 5)
	close:SetWide(UI.S(100))
	close:SetText(L("about_close"))
	UI.StyleButton(close, nil, 3)
	close.DoClick = function() win:Close() end
	return win
end
