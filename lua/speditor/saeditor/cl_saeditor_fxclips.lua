--[[
SAeditor — FX clips of the timeline (b0.2 round 6), after SFM's effect clips: an effect laid
over the finished frame on a stretch of the animation, on its own row under the film strip.

  text     titles and captions (SFM's TextFX): the text, its place, size, colour, outline
  grain    film grain (after SFM's HSL Grain): shaders_src/gmfm_grain2b.hlsl
  color    colour correction (SFM's Color Correction clip): brightness, contrast,
           saturation, a tint — shaders_src/gmfm_cc2b.hlsl
  overlay  a material laid over the frame (SFM's Material Overlay), see-through or added

A clip { k = kind, a = from, b = to, fi, fo = fade in / out in frames, p = parameters } works
from a to b; over its fades its strength goes from nothing to full and back, so a title can
come up and fade out and grain can creep in. The server keeps the list with the animation
(sv_saeditor.lua "Clips": saved in the scene, moved when time is inserted or cut out).

R.ApplyClips (cl_render.lua R.ApplyFX) lays the clips of the current frame over every
finished frame: renders, the Render window preview, the player, the render look.
]]
local COMP = SPeditor.Component("saeditor")
local SA = COMP.SA
local C = SPeditor.Client
local UI = SPeditor.UI
local R = SPeditor.Render
local L = SPeditor.L
local COL = UI.PAL

SA.fxClips = SA.fxClips or {}

-- the parameters of each kind: { key, kind of control, default, min, max, decimals }
SA.CLIP_PARAMS = {
	text = {
		{ "text", "text", "Title" }, { "size", "num", 0.08, 0.01, 0.4, 3 }, { "x", "num", 0.5, 0, 1, 3 }, { "y", "num", 0.85, 0, 1, 3 },
		{ "align", "align", 1 }, { "color", "color", { r = 255, g = 255, b = 255 } }, { "outline", "num", 0.06, 0, 0.3, 3 },
		{ "bold", "bool", true }, { "box", "num", 0, 0, 1, 2 },
	},
	grain = { { "amount", "num", 0.12, 0, 1, 3 }, { "size", "num", 1.5, 1, 6, 2 }, { "colour", "bool", false } },
	color = {
		{ "brightness", "num", 0, -0.5, 0.5, 3 }, { "contrast", "num", 1, 0, 2, 2 }, { "saturation", "num", 1, 0, 2, 2 },
		{ "tint", "color", { r = 255, g = 220, b = 180 } }, { "tintAmount", "num", 0, 0, 1, 2 },
	},
	overlay = { { "material", "text", "effects/combine_binocoverlay" }, { "alpha", "num", 1, 0, 1, 2 }, { "additive", "bool", false } },
}
local KIND_COLORS = { text = Color(200, 170, 90), grain = Color(140, 140, 140), color = Color(170, 110, 170), overlay = Color(90, 150, 170) }
SA.CLIP_COLORS = KIND_COLORS

function SA.ClipParam(c, key)
	local v = c.p and c.p[key]
	if v ~= nil then return v end
	for _, d in ipairs(SA.CLIP_PARAMS[c.k] or {}) do
		if d[1] == key then return istable(d[3]) and table.Copy(d[3]) or d[3] end
	end
end

-- how much of the clip is on at frame f (0 … 1), with its fades
function SA.ClipWeight(c, f)
	if f < c.a or f > c.b then return 0 end
	local w = 1
	if (c.fi or 0) > 0 and f < c.a + c.fi then w = math.min(w, (f - c.a) / c.fi) end
	if (c.fo or 0) > 0 and f > c.b - c.fo then w = math.min(w, (c.b - f) / c.fo) end
	return math.Clamp(w, 0, 1)
end

---------------------------------------------------------------------
-- Editing (one undo step each; the server sends the list back in the summary)
---------------------------------------------------------------------
local function copyClips(list)
	local out = {}
	for i, c in ipairs(list) do out[i] = table.Copy(c) end
	return out
end

local function sendClips(list)
	COMP:NetStart("Clips")
	SPeditor.WriteTable(list)
	net.SendToServer()
end

function SA.CommitClips(list, label)
	local before, after = copyClips(SA.fxClips), copyClips(list)
	SA.fxClips = copyClips(list)
	sendClips(after)
	hook.Run("SAeditor_Changed")
	C.PushHistory(label or "sa fx clip", function() sendClips(before) end, function() sendClips(after) end)
end

-- a new clip of kind at frame f: two seconds long (or to the end), with short fades
function SA.AddClip(kind, f)
	if not SA.CLIP_KINDS[kind] then return end
	local len = math.max(math.floor(SA.fps * 2), 2)
	local a = math.Clamp(math.floor(f or SA.frame), 0, math.max(SA.frames - 1, 0))
	local b = math.min(a + len, SA.frames)
	if b <= a then return end
	local fade = kind == "text" and math.floor(SA.fps / 3) or 0
	local list = copyClips(SA.fxClips)
	list[#list + 1] = { k = kind, a = a, b = b, fi = fade, fo = fade, p = {} }
	SA.CommitClips(list, "sa fx clip add")
	return #list
end

function SA.RemoveClip(i)
	local list = copyClips(SA.fxClips)
	table.remove(list, i)
	SA.CommitClips(list, "sa fx clip delete")
end

-- the clip i with changes (a table of fields; p — parameters to merge)
function SA.EditClip(i, changes, label)
	local list = copyClips(SA.fxClips)
	local c = list[i]
	if not c then return end
	for k, v in pairs(changes) do
		if k == "p" then
			c.p = c.p or {}
			for pk, pv in pairs(v) do c.p[pk] = pv end
		else
			c[k] = v
		end
	end
	c.a = math.Clamp(math.floor(c.a), 0, SA.frames)
	c.b = math.Clamp(math.floor(c.b), c.a + 1, SA.frames)
	c.fi = math.Clamp(math.floor(c.fi or 0), 0, c.b - c.a)
	c.fo = math.Clamp(math.floor(c.fo or 0), 0, c.b - c.a)
	SA.CommitClips(list, label or "sa fx clip edit")
end

-- Clips that overlap in time share the row in lanes (thin bands one under another):
-- lane of each clip (1 …) and how many lanes there are
function SA.ClipLanes()
	local lanes, ends = {}, {}
	local order = {}
	for i in ipairs(SA.fxClips) do order[i] = i end
	table.sort(order, function(x, y) return SA.fxClips[x].a < SA.fxClips[y].a end)
	for _, i in ipairs(order) do
		local c = SA.fxClips[i]
		local lane = 1
		while ends[lane] and ends[lane] > c.a do lane = lane + 1 end
		ends[lane] = c.b
		lanes[i] = lane
	end
	return lanes, math.max(#ends, 1)
end

-- the index of the clip at frame f in lane (nil — any lane), or nil
function SA.ClipAt(f, lane)
	local lanes = lane and SA.ClipLanes()
	for i = #SA.fxClips, 1, -1 do
		local c = SA.fxClips[i]
		if f >= c.a and f <= c.b and (not lane or lanes[i] == lane) then return i, c end
	end
end

function SA.ClipLabel(c)
	if c.k == "text" then return "T  " .. tostring(SA.ClipParam(c, "text")) end
	return L("sa_clip_" .. c.k)
end

---------------------------------------------------------------------
-- Drawing over a finished frame
---------------------------------------------------------------------
-- Shader Model 2 (b0.2.1): a ps_3_0 pass is not run in a game at DirectX level 90 (Linux)
local function screenMat(name, ps)
	return CreateMaterial(name, "screenspace_general", {
		["$pixshader"] = ps, ["$vertextransform"] = "1",
		["$basetexture"] = "vgui/white", ["$ignorez"] = "1", ["$copyalpha"] = "0",
		["$linearread_basetexture"] = "0", ["$linearwrite"] = "0",
		["$alpha_blend"] = "0", ["$alpha_blend_color_overlay"] = "0",
	})
end
-- made on the first use (as the occlusion's, cl_ssao.lua: made while the game starts they may
-- get no shader for the whole session)
local matGrain, matCC
local matCopy = CreateMaterial("gmfm_clip_copy", "UnlitGeneric", { ["$nolod"] = "1", ["$ignorez"] = "1" })

local spares = {}
local function spareRT(w, h)
	local key = w .. "x" .. h
	spares[key] = spares[key] or GetRenderTargetEx("gmfm_clipsrc_" .. key, w, h, RT_SIZE_LITERAL,
		MATERIAL_RT_DEPTH_NONE, 4 + 8, 0, IMAGE_FORMAT_RGBA8888)
	return spares[key]
end

-- a shader pass over the frame rt (w x h): the frame is copied aside first and the shader draws
-- the result back into rt, so the frame always stays in its own texture
local function shaderPass(mat, rt, w, h)
	local src = spareRT(w, h)
	render.PushRenderTarget(src)
	matCopy:SetTexture("$basetexture", rt)
	render.SetMaterial(matCopy)
	render.DrawScreenQuad()
	render.PopRenderTarget()
	mat:SetTexture("$basetexture", src)
	render.PushRenderTarget(rt)
	render.SetMaterial(mat)
	render.DrawScreenQuad()
	render.PopRenderTarget()
end

local fonts = {}
local function fontFor(px, bold)
	px = math.Clamp(math.floor(px / 2 + 0.5) * 2, 8, 512)
	local name = "GMFM_Clip_" .. px .. (bold and "b" or "")
	if not fonts[name] then
		surface.CreateFont(name, { font = "Roboto", size = px, weight = bold and 800 or 500, antialias = true, extended = true })
		fonts[name] = true
	end
	return name
end

local function drawText(c, w, h, weight)
	local text = tostring(SA.ClipParam(c, "text") or "")
	if text == "" then return end
	local size = math.Clamp(tonumber(SA.ClipParam(c, "size")) or 0.08, 0.01, 0.4) * h
	local font = fontFor(size, SA.ClipParam(c, "bold") ~= false)
	local col = SA.ClipParam(c, "color") or color_white
	local x = (tonumber(SA.ClipParam(c, "x")) or 0.5) * w
	local y = (tonumber(SA.ClipParam(c, "y")) or 0.85) * h
	local align = ({ [0] = TEXT_ALIGN_LEFT, [1] = TEXT_ALIGN_CENTER, [2] = TEXT_ALIGN_RIGHT })[math.Clamp(math.floor(tonumber(SA.ClipParam(c, "align")) or 1), 0, 2)]
	local a = math.floor(255 * weight)
	local outline = math.floor((tonumber(SA.ClipParam(c, "outline")) or 0) * size)
	local lines = string.Explode("\n", text)
	surface.SetFont(font)
	local _, lh = surface.GetTextSize("Ag")
	local y0 = y - lh * #lines / 2
	local box = tonumber(SA.ClipParam(c, "box")) or 0
	if box > 0 then
		local bw = 0
		for _, ln in ipairs(lines) do bw = math.max(bw, (surface.GetTextSize(ln))) end
		local pad = lh * 0.3
		local bx = align == TEXT_ALIGN_LEFT and x or (align == TEXT_ALIGN_RIGHT and x - bw or x - bw / 2)
		surface.SetDrawColor(0, 0, 0, math.floor(box * 220 * weight))
		surface.DrawRect(bx - pad, y0 - pad * 0.5, bw + pad * 2, lh * #lines + pad)
	end
	for i, ln in ipairs(lines) do
		local ly = y0 + (i - 1) * lh + lh / 2
		if outline > 0 then
			draw.SimpleTextOutlined(ln, font, x, ly, Color(col.r, col.g, col.b, a), align, TEXT_ALIGN_CENTER, outline, Color(0, 0, 0, a))
		else
			draw.SimpleText(ln, font, x, ly, Color(col.r, col.g, col.b, a), align, TEXT_ALIGN_CENTER)
		end
	end
end

local function drawOverlay(c, w, h, weight)
	local path = tostring(SA.ClipParam(c, "material") or "")
	if path == "" then return end
	local m = Material(path)
	if m:IsError() then return end
	local alpha = math.Clamp(tonumber(SA.ClipParam(c, "alpha")) or 1, 0, 1) * weight
	if SA.ClipParam(c, "additive") then
		render.OverrideBlend(true, BLEND_SRC_ALPHA, BLEND_ONE, BLENDFUNC_ADD)
	end
	surface.SetMaterial(m)
	surface.SetDrawColor(255, 255, 255, math.floor(alpha * 255))
	surface.DrawTexturedRect(0, 0, w, h)
	if SA.ClipParam(c, "additive") then render.OverrideBlend(false) end
end

-- rt: the finished frame (w x h); the clips at frame f are laid over it, in place. Returns rt.
function SA.ApplyClips(rt, w, h, f)
	f = f or SA.frame or 0
	if not matGrain then
		matGrain = screenMat("gmfm_clip_grain2b", "gmfm_grain2b_ps20b")
		matCC = screenMat("gmfm_clip_cc2b", "gmfm_cc2b_ps20b")
	end
	local cur = rt
	for _, c in ipairs(SA.fxClips) do
		local weight = SA.ClipWeight(c, f)
		if weight > 0 then
			if c.k == "grain" then
				matGrain:SetFloat("$c0_x", math.Clamp(tonumber(SA.ClipParam(c, "amount")) or 0.1, 0, 1) * weight)
				-- the grain keeps its size in the picture whatever the frame size (1080 lines = 1)
				matGrain:SetFloat("$c0_y", math.Clamp(tonumber(SA.ClipParam(c, "size")) or 1.5, 1, 6) * math.max(h / 1080, 0.35))
				matGrain:SetFloat("$c0_z", (math.floor(f) * 7.31) % 61.7 + 1)
				matGrain:SetFloat("$c0_w", SA.ClipParam(c, "colour") and 1 or 0)
				matGrain:SetFloat("$c1_z", 1 / w)
				matGrain:SetFloat("$c1_w", 1 / h)
				shaderPass(matGrain, cur, w, h)
			elseif c.k == "color" then
				local tint = SA.ClipParam(c, "tint") or color_white
				matCC:SetFloat("$c0_x", tonumber(SA.ClipParam(c, "brightness")) or 0)
				matCC:SetFloat("$c0_y", tonumber(SA.ClipParam(c, "contrast")) or 1)
				matCC:SetFloat("$c0_z", tonumber(SA.ClipParam(c, "saturation")) or 1)
				matCC:SetFloat("$c0_w", weight)
				matCC:SetFloat("$c1_x", tint.r / 255)
				matCC:SetFloat("$c1_y", tint.g / 255)
				matCC:SetFloat("$c1_z", tint.b / 255)
				matCC:SetFloat("$c1_w", math.Clamp(tonumber(SA.ClipParam(c, "tintAmount")) or 0, 0, 1))
				matCC:SetFloat("$c2_z", 1 / w)
				matCC:SetFloat("$c2_w", 1 / h)
				shaderPass(matCC, cur, w, h)
			else
				render.PushRenderTarget(cur)
				cam.Start2D()
				local ok, err = pcall(c.k == "text" and drawText or drawOverlay, c, w, h, weight)
				cam.End2D()
				render.PopRenderTarget()
				if not ok then ErrorNoHalt("[GM:FM] FX clip: " .. tostring(err) .. "\n") end
			end
		end
	end
	return cur
end

R.ApplyClips = function(rt, w, h)
	if #SA.fxClips == 0 or not rt then return rt end
	return SA.ApplyClips(rt, w, h, SA.frame)
end

---------------------------------------------------------------------
-- The clip window: its parameters, start, end and fades
---------------------------------------------------------------------
function SA.OpenClip(i)
	local c = SA.fxClips[i]
	if not c then return end
	if IsValid(SA.clipWin) then SA.clipWin:Remove() end
	local f = UI.Skin(vgui.Create("DFrame"))
	SA.clipWin = f
	f:SetTitle(L("sa_clip_" .. c.k))
	f:SetSize(UI.S(380), UI.S(460))
	f:Center()
	f:MakePopup()
	f.Paint = function(s, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, 24)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end
	local scroll = vgui.Create("DScrollPanel", f)
	scroll:Dock(FILL)
	-- changes go to the server a moment after the last one: a slider dragged makes one undo
	-- step, not a hundred
	local pending
	local function set(key, v)
		if not SA.fxClips[i] then return end
		pending = pending or { p = {} }
		if key == "a" or key == "b" or key == "fi" or key == "fo" then pending[key] = math.floor(v) else pending.p[key] = v end
		timer.Create("GMFM.ClipEdit", 0.35, 1, function()
			local d = pending
			pending = nil
			if d then SA.EditClip(i, d) end
		end)
	end
	local function timeSlider(label, key, max)
		UI.Slider(scroll, label, 0, max, 0, c[key] or 0, function(v)
			if math.floor(v) ~= (SA.fxClips[i] and SA.fxClips[i][key]) then set(key, v) end
		end)
	end
	timeSlider(L("sa_clip_from"), "a", SA.frames)
	timeSlider(L("sa_clip_to"), "b", SA.frames)
	timeSlider(L("sa_clip_fadein"), "fi", math.max(c.b - c.a, 1))
	timeSlider(L("sa_clip_fadeout"), "fo", math.max(c.b - c.a, 1))
	for _, d in ipairs(SA.CLIP_PARAMS[c.k] or {}) do
		local key, kind = d[1], d[2]
		local label = L("sa_clip_p_" .. key)
		local val = SA.ClipParam(c, key)
		if kind == "num" then
			UI.Slider(scroll, label, d[4], d[5], d[6] or 2, tonumber(val) or d[3], function(v) set(key, v) end)
		elseif kind == "bool" then
			UI.Check(scroll, label, val and true or false, function(v) set(key, v and true or false) end)
		elseif kind == "color" then
			local b = UI.Button(scroll, label, "icon16/color_wheel.png", function()
				local cur = SA.ClipParam(SA.fxClips[i] or c, key) or color_white
				UI.OpenColorPopup(label, Color(cur.r, cur.g, cur.b), function(col) set(key, { r = col.r, g = col.g, b = col.b }) end)
			end)
			b.PaintOver = function(s, w, h)
				local cur = SA.ClipParam(SA.fxClips[i] or c, key) or color_white
				surface.SetDrawColor(cur.r, cur.g, cur.b, 255)
				surface.DrawRect(w - h - 2, 3, h - 6, h - 6)
			end
		elseif kind == "align" then
			local combo = UI.StyleCombo(vgui.Create("DComboBox", scroll))
			combo:Dock(TOP)
			combo:DockMargin(4, 2, 4, 2)
			combo:SetTall(UI.S(22))
			for n = 0, 2 do combo:AddChoice(L("sa_clip_align_" .. n), n, (tonumber(val) or 1) == n) end
			combo.OnSelect = function(_, _, _, n) set(key, n) end
		elseif kind == "text" then
			UI.Label(scroll, label)
			local e = vgui.Create("DTextEntry", scroll)
			e:Dock(TOP)
			e:DockMargin(4, 1, 4, 4)
			e:SetMultiline(key == "text")
			e:SetTall(UI.S(key == "text" and 60 or 22))
			e:SetValue(tostring(val or ""))
			e.OnLoseFocus = function(s)
				if s:GetValue() ~= tostring(SA.ClipParam(SA.fxClips[i] or c, key) or "") then set(key, s:GetValue()) end
			end
			e.OnEnter = e.OnLoseFocus
		end
	end
	local del = UI.Button(scroll, L("sa_clip_delete"), "icon16/cross.png", function()
		SA.RemoveClip(i)
		f:Remove()
	end)
	del:DockMargin(4, 10, 4, 4)
end

-- The menu of the FX row: add a clip at frame f; a clip under the cursor — edit / delete
function SA.ClipMenu(i, f)
	local m = UI.Menu()
	if i then
		local c = SA.fxClips[i]
		m:AddOption(L("sa_clip_edit"), function() SA.OpenClip(i) end):SetIcon("icon16/pencil.png")
		m:AddOption(L("sa_clip_to_sel"), function()
			local t = SA.timeSel
			if t then SA.EditClip(i, { a = t[1], b = t[4], fi = t[2] - t[1], fo = t[4] - t[3] }) end
		end):SetEnabled(SA.timeSel ~= nil)
		m:AddOption(L("sa_clip_delete"), function() SA.RemoveClip(i) end):SetIcon("icon16/cross.png")
		m:AddSpacer()
		if c then m:AddOption(SA.ClipLabel(c) .. "  " .. c.a .. "–" .. c.b):SetEnabled(false) end
		m:AddSpacer()
	end
	local add = m:AddSubMenu(L("sa_clip_add"))
	for _, k in ipairs(SA.CLIP_ORDER) do
		add:AddOption(L("sa_clip_" .. k), function()
			local n = SA.AddClip(k, f)
			-- the time selection gives the new clip its stretch and fades
			local t = SA.timeSel
			if n and t then SA.EditClip(n, { a = t[1], b = t[4], fi = t[2] - t[1], fo = t[4] - t[3] }) end
		end)
	end
	m:Open()
end
