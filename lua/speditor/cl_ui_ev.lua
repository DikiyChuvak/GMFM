--[[
SPeditor — Element Viewer (as in SFM: "name / value" columns).

Properties of the selected element on the stock DProperties panel (per the wiki:
CreateRow(category, name), row:Setup(type, data), row:SetValue, row.DataChanged).
Categories: Element, Transform, Appearance, Flags, Light, Camera.
Transform numbers follow the entity while the field is not being edited.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI = SPeditor.UI
local C  = SPeditor.Client
local L  = SPeditor.L
local COL = UI.PAL

local function toVec(v)
	if isvector(v) then return v end
	local ok, res = pcall(Vector, tostring(v))
	return ok and res or nil
end

function UI.BuildElementViewer(host)
	local page = vgui.Create("DPanel")
	page.Paint = function(_, w, h)
		surface.SetDrawColor(COL.BG)
		surface.DrawRect(0, 0, w, h)
	end

	local head = vgui.Create("DPanel", page)
	head:Dock(TOP)
	head:SetTall(UI.S(22))
	local title = ""
	head.Paint = function(_, w, h)
		surface.SetDrawColor(COL.HEADER)
		surface.DrawRect(0, 0, w, h)
		draw.SimpleText(title, "SPeditor.Bold", 6, h / 2, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local props
	local current
	local syncing = false
	local live = {}          -- rows that follow the entity: { row, get }

	-- groups and attribute names are translated only on screen (ev_* keys in sh_lang.lua)
	local function row(cat, name, kind, data, value, onChange, getter)
		cat, name = SPeditor.LN("ev_", cat), SPeditor.LN("ev_", name)
		local r = props:CreateRow(cat, name)
		-- the stock row is 20 px tall whatever the font: at the interface scale it grows
		if UI.Scale() ~= 1 then
			local layout = r.PerformLayout
			r.PerformLayout = function(s, ...)
				layout(s, ...)
				s:SetTall(UI.S(20))
			end
		end
		-- DProperties rows have a white background; dark themes need their own
		local group = props:GetCategory(cat)
		local bg = UI.Theme and UI.Theme.propBG
		if bg and IsValid(group) and not group.SPThemed then
			group.SPThemed = true
			group.Container.Paint = function(_, w, h)
				surface.SetDrawColor(bg)
				surface.DrawRect(0, 0, w, h)
			end
		end
		r:Setup(kind, data)
		syncing = true
		r:SetValue(value)
		syncing = false
		r.DataChanged = function(_, v)
			if syncing then return end
			r.SPLastEdit = RealTime()
			onChange(v)
		end
		if getter then live[#live + 1] = { row = r, get = getter, last = value } end
		return r
	end

	local function rebuild()
		if IsValid(props) then props:Remove() end
		live = {}
		current = C.selected
		local ent = current

		props = vgui.Create("DProperties", page)
		props:Dock(FILL)

		if not IsValid(ent) then
			title = L("no_selection")
			return
		end
		title = C.DisplayName(ent) .. "   (" .. ent:GetClass() .. ")"

		-- Element
		row("Element", "name", "Generic", nil, C.DisplayName(ent), function(v) C.SendRename(ent, tostring(v)) end)
		if not C.IsAux(ent) then
			row("Element", "model", "Generic", nil, ent:GetModel() or "", function() end)
		end

		-- Transform
		local function getT()
			return C.GetEntityTransform(ent)
		end
		local p0, a0 = getT()
		local function sendT(axis, v)
			if not IsValid(ent) then return end
			local p, a = getT()
			p, a = Vector(p.x, p.y, p.z), Angle(a.p, a.y, a.r)
			local bp, ba = Vector(p.x, p.y, p.z), Angle(a.p, a.y, a.r)
			local ref = C.Ref(ent)
			v = tonumber(v) or 0
			if axis == "x" then p.x = v elseif axis == "y" then p.y = v elseif axis == "z" then p.z = v
			elseif axis == "p" then a.p = v elseif axis == "yw" then a.y = v else a.r = v end
			C.SendTransform(ent, p, a, true)
			-- a series of edits of one field is merged into one history entry
			C.BurstEdit("evt" .. ent:EntIndex(), "transform", function() return { bp, ba } end, { p, a }, function(st)
				local e = C.Deref(ref)
				if e then C.SendTransform(e, st[1], st[2], true) end
			end)
		end
		local big = { min = -16384, max = 16384 }
		local deg = { min = -180, max = 180 }
		row("Transform", "position x", "Float", big, p0.x, function(v) sendT("x", v) end, function() return (getT()).x end)
		row("Transform", "position y", "Float", big, p0.y, function(v) sendT("y", v) end, function() return (getT()).y end)
		row("Transform", "position z", "Float", big, p0.z, function(v) sendT("z", v) end, function() return (getT()).z end)
		row("Transform", "pitch", "Float", deg, a0.p, function(v) sendT("p", v) end, function() local _, a = getT() return a.p end)
		row("Transform", "yaw", "Float", deg, a0.y, function(v) sendT("yw", v) end, function() local _, a = getT() return a.y end)
		row("Transform", "roll", "Float", deg, a0.r, function(v) sendT("r", v) end, function() local _, a = getT() return a.r end)

		if C.CanScale(ent) then
			row("Transform", "scale", "Float", { min = 0.05, max = 10 }, ent:GetModelScale() or 1, function(v)
				local s0 = ent:GetModelScale() or 1
				local s1 = math.Clamp(tonumber(v) or 1, 0.05, 10)
				local ref = C.Ref(ent)
				C.SendScale(ent, s1, true)
				C.BurstEdit("evs" .. ent:EntIndex(), "scale", function() return s0 end, s1, function(s)
					local e = C.Deref(ref)
					if e then C.SendScale(e, s, true) end
				end)
			end, function() return ent:GetModelScale() or 1 end)
		end

		-- Appearance
		if not C.IsAux(ent) then
			local skins = ent:SkinCount() or 1
			if skins > 1 then
				row("Appearance", "skin", "Int", { min = 0, max = skins - 1 }, ent:GetSkin() or 0,
					function(v) C.SendSkin(ent, math.floor((tonumber(v) or 0) + 0.5)) end)
			end
			for i = 0, (ent:GetNumBodyGroups() or 0) - 1 do
				local n = ent:GetBodygroupCount(i)
				if n and n > 1 then
					row("Appearance", ent:GetBodygroupName(i) or ("bodygroup " .. i), "Int", { min = 0, max = n - 1 },
						ent:GetBodygroup(i) or 0, function(v) C.SendBodygroup(ent, i, math.floor((tonumber(v) or 0) + 0.5)) end)
				end
			end
		end

		-- Flags
		if not C.IsAux(ent) or C.IsEffect(ent) then
			row("Flags", "renderable", "Boolean", nil, not C.IsHidden(ent),
				function(v) C.SendFlags(ent, not tobool(v), C.IsLocked(ent)) end)
		end
		row("Flags", "selectable", "Boolean", nil, not C.IsLocked(ent),
			function(v) C.SendFlags(ent, C.IsHidden(ent), not tobool(v)) end)

		-- Light
		if C.IsLight(ent) then
			local function state()
				local c = ent:GetLightColor()
				return {
					col = Color(math.Round(c.x * 255), math.Round(c.y * 255), math.Round(c.z * 255)),
					radius = ent:GetLightRadius(), bri = ent:GetLightBrightness(), fov = ent:GetLightFOV(),
				}
			end
			local function send(patch, sh)
				local st = state()
				for k, v in pairs(patch) do st[k] = v end
				C.SendLightEdit(ent, ent:GetLightType(), st.col, st.radius, st.bri, st.fov, sh, true)
			end
			row("Light", "color", "VectorColor", nil, ent:GetLightColor(), function(v)
				local vec = toVec(v)
				if vec then send({ col = Color(math.Round(vec.x * 255), math.Round(vec.y * 255), math.Round(vec.z * 255)) }) end
			end)
			row("Light", "intensity", "Float", { min = 0, max = 8 }, ent:GetLightBrightness(),
				function(v) send({ bri = tonumber(v) or 2 }) end, function() return ent:GetLightBrightness() end)
			row("Light", ent:GetLightType() == 1 and "distance" or "radius", "Float", { min = 32, max = 4000 }, ent:GetLightRadius(),
				function(v) send({ radius = tonumber(v) or 400 }) end, function() return ent:GetLightRadius() end)
			if ent:GetLightType() == 1 then
				row("Light", "fieldOfView", "Float", { min = 5, max = 120 }, ent:GetLightFOV(),
					function(v) send({ fov = tonumber(v) or 60 }) end, function() return ent:GetLightFOV() end)
				row("Light", "castsShadows", "Boolean", nil, ent:GetLightShadows(),
					function(v) send({}, { shadows = tobool(v) }) end)
				row("Light", "shadowFilterSize", "Float", { min = 0, max = 5 }, ent:GetShadowSoft(),
					function(v) send({}, { soft = tonumber(v) or 0.2 }) end)
				row("Light", "shadowNearZ", "Float", { min = 1, max = 500 }, ent:GetShadowNear(),
					function(v) send({}, { near = tonumber(v) or 10 }) end)
				row("Light", "shadowSlopeBias", "Float", { min = 0, max = 16 }, ent:GetShadowSlope(),
					function(v) send({}, { slope = tonumber(v) or 0 }) end)
				row("Light", "linearAttenuation", "Float", { min = 0, max = 1000 }, ent:GetAttLinear(),
					function(v) send({}, { attl = tonumber(v) or 100 }) end)
				row("Light", "orthographic", "Boolean", nil, ent:GetLightOrtho(),
					function(v) send({}, { ortho = tobool(v) }) end)
				row("Light", "orthoSize", "Float", { min = 8, max = 2000 }, ent:GetOrthoSize(),
					function(v) send({}, { osize = tonumber(v) or 200 }) end)
				row("Light", "edgeSoftness", "Float", { min = 0, max = 1 }, ent:GetEdgeSoft(),
					function(v) send({}, { edge = tonumber(v) or 0 }) end)
				row("Light", "sourceSize", "Float", { min = 0, max = 64 }, ent:GetSourceSize(),
					function(v) send({}, { area = tonumber(v) or 0 }) end)
				row("Light", "beamStrength", "Float", { min = 0, max = 1 }, ent:GetVolStrength(),
					function(v) send({}, { vol = tonumber(v) or 0 }) end)
				row("Light", "beamLength", "Float", { min = 0.05, max = 1 }, ent:GetVolLength(),
					function(v) send({}, { voll = tonumber(v) or 0.5 }) end)
			end
			row("Light", "glowSize", "Float", { min = 0, max = 400 }, ent:GetGlowSize(),
				function(v) send({}, { glow = tonumber(v) or 0 }) end)
			row("Light", "glowBrightness", "Float", { min = 0, max = 4 }, ent:GetGlowBright(),
				function(v) send({}, { glowb = tonumber(v) or 1 }) end)
		end

		-- Effect
		if C.IsEffect(ent) then
			row("Effect", "moment", "Float", { min = 0, max = 10 }, ent:GetFxTime(),
				function(v) C.SendEffectEdit(ent, { time = tonumber(v) or 0 }, true) end, function() return ent:GetFxTime() end)
			row("Effect", "scale", "Float", { min = 0.05, max = 10 }, ent:GetFxScale(),
				function(v) C.SendEffectEdit(ent, { scale = tonumber(v) or 1 }, true) end, function() return ent:GetFxScale() end)
			row("Effect", "length", "Float", { min = 0, max = 2000 }, ent:GetFxLength(),
				function(v) C.SendEffectEdit(ent, { length = tonumber(v) or 0 }, true) end, function() return ent:GetFxLength() end)
		end

		-- Camera
		if C.IsCamera(ent) then
			row("Camera", "fieldOfView", "Float", { min = 10, max = 120 }, ent:GetCameraFOV(),
				function(v) C.SendCameraEdit(ent, "fov", tonumber(v) or 75, true) end, function() return ent:GetCameraFOV() end)
		end
	end

	-- pull the values in if the field is not focused and has not been touched
	local nextPoll = 0
	page.Think = function()
		if RealTime() < nextPoll or not IsValid(props) then return end
		nextPoll = RealTime() + 0.3
		if not IsValid(current) then return end
		local focus = vgui.GetKeyboardFocus()
		if IsValid(focus) and (focus == props or focus:HasParent(props)) then return end
		for _, it in ipairs(live) do
			if IsValid(it.row) and RealTime() - (it.row.SPLastEdit or 0) > 0.8 then
				local v = it.get()
				if v and it.last and math.abs(v - it.last) > 0.05 then
					it.last = v
					syncing = true
					it.row:SetValue(math.Round(v, 2))
					syncing = false
				end
			end
		end
	end

	hook.Add("SPeditor_Selected", "SPeditor.ElementViewer", function(ent)
		if IsValid(page) and ent ~= current then rebuild() end
	end)
	rebuild()

	host:AddSheet(L("win_ev"), page, "icon16/application_view_detail.png", "ev")
end
