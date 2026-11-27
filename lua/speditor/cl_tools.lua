--[[
SPeditor — poster tools that SFM has but GMod lacks:
  * aiming a camera / light at an object (C.AimAt);
  * a three-point lighting rig around an object (key / fill / rim);
  * copying and pasting a pose between models of the same type;
  * frame guides (thirds, centre, safe area, golden ratio);
  * scene autosave.
]]
SPeditor = SPeditor or {}
local C = SPeditor.Client
local L = SPeditor.L
local UI = SPeditor.UI

-- (r1.0) SFM-style influence of a look-at constraint: 1 — full turn, 0 — no turn
function C.OpenAimStrength(src)
	if not IsValid(src) then return end
	local target = src:GetNW2Entity("SPeditor_AimAt")
	if not IsValid(target) then return end
	if IsValid(C.AimWin) then C.AimWin:Remove() end
	local f = vgui.Create("DFrame")
	C.AimWin = f
	f:SetTitle(L("aim_strength"))
	f:SetSize(440, 190)
	f:Center()
	f:MakePopup()
	if f.GetTitleLabel and IsValid(f:GetTitleLabel()) then f:GetTitleLabel():SetFont("SPeditor.Bold") end
	local hint = vgui.Create("DLabel", f)
	hint:Dock(TOP)
	hint:DockMargin(10, 8, 10, 0)
	hint:SetFont("SPeditor.Small")
	hint:SetText(L("aim_strength_hint"))
	hint:SetTextColor(UI.PAL and UI.PAL.DIM or color_white)
	hint:SetWrap(true)
	hint:SetAutoStretchVertical(true)
	local s = UI.Slider(f, L("aim_strength"), 0, 1, 2, src:GetNW2Float("SPeditor_AimWeight", 1))
	s:DockMargin(10, 6, 10, 4)
	s.OnValueChanged = function(_, v)
		C.SendAim(src, target, src:GetNW2Int("SPeditor_AimBone", -1), nil, v)
	end
end

---------------------------------------------------------------------
-- Aiming a camera / light at an object
---------------------------------------------------------------------
function C.AimAt(src, target)
	if not (IsValid(src) and IsValid(target)) or src == target then return false end
	if not SPeditor.IsEditable(src) then return false end
	local center = C.CenterOf(target)
	if not center then return false end
	local pos, oldAng = src:GetPos(), src:GetAngles()
	local newAng = (center - pos):Angle()
	newAng.r = C.IsCamera(src) and 0 or oldAng.r
	C.SendTransform(src, pos, newAng, true)
	local ref = C.Ref(src)
	C.PushHistory("aim",
		function() local e = C.Deref(ref) if e then C.SendTransform(e, pos, oldAng, true) end end,
	function() local e = C.Deref(ref) if e then C.SendTransform(e, pos, newAng, true) end end)
	return true
end

function C.AimCameraAt(camEnt, target)   -- compatibility
	return C.IsCamera(camEnt) and C.AimAt(camEnt, target)
end

-- Menu for picking the object to aim src at (a0.9: two labelled parts, it was not clear what the
-- plain list did): "turn once" (C.AimAt) and "keep watching" — the camera or light stays where it
-- is and keeps turning to the object while either of them moves (the look-at, C.SendAim, a0.7);
-- a character can be watched by its head.
function C.OpenAimMenu(src)
	local targets = {}
	for _, obj in ipairs(C.BuildEntityList()) do
		if IsValid(obj.ent) and obj.ent ~= src and obj.kind ~= "camera" and obj.kind ~= "light" then targets[#targets + 1] = obj end
	end
	if #targets == 0 then
		SPeditor.Notify(L("aim_none"), 0)
		return
	end
	local menu = SPeditor.UI.Menu()
	local canWatch = IsValid(src) and (C.IsCamera(src) or C.IsLight(src))
	if canWatch then
		local cur = src:GetNW2Entity("SPeditor_AimAt")
		menu:AddOption(L("aim_watch_head")):SetEnabled(false)
		for _, obj in ipairs(targets) do
			local e = obj.ent
			local head = e:LookupBone("ValveBiped.Bip01_Head1")
			if head and C.IsRagdoll(e) then
				local sub, o = menu:AddSubMenu(obj.name)
				if o and o.SetIcon then o:SetIcon("icon16/eye.png") end
				if o and o.SetChecked then o:SetChecked(cur == e) end
				sub:AddOption(L("aim_watch_body"), function() C.SendAim(src, e, -1) end):SetIcon("icon16/user.png")
				sub:AddOption(L("aim_watch_face"), function() C.SendAim(src, e, head) end):SetIcon("icon16/emoticon_smile.png")
			else
				local opt = menu:AddOption(obj.name, function() C.SendAim(src, e, -1) end)
				opt:SetIcon("icon16/eye.png")
				if opt.SetChecked then opt:SetChecked(cur == e) end
			end
		end
		if IsValid(cur) then
			menu:AddOption(L("aim_strength"), function() C.OpenAimStrength(src) end):SetIcon("icon16/control_sliders.png")
			menu:AddOption(L("aim_follow_stop") .. "  (" .. C.DisplayName(cur) .. ")", function() C.SendAim(src, nil) end):SetIcon("icon16/cross.png")
		end
		menu:AddSpacer()
	end
	local once, o = menu:AddSubMenu(L("aim_once_head"))
	if o and o.SetIcon then o:SetIcon("icon16/arrow_turn_right.png") end
	for _, obj in ipairs(targets) do
		once:AddOption(obj.name, function()
			if C.AimAt(src, obj.ent) then SPeditor.Notify(string.format(L("aim_once_done"), obj.name), 0) end
		end)
	end
	menu:Open()
end

---------------------------------------------------------------------
-- Three-point rig
---------------------------------------------------------------------
function C.SpawnLightRig(target)
	if not IsValid(target) or C.IsAux(target) then
		SPeditor.Notify(L("rig_need_object"), 0)
		return
	end
	local center = C.CenterOf(target)
	local radius = math.max(target:BoundingRadius(), 40)
	local dist   = math.max(radius * 2.4, 120)

	-- the rig "faces" the work camera
	local toCam = C.camera.pos - center
	toCam.z = 0
	local baseYaw = (toCam:LengthSqr() > 1) and toCam:Angle().y or 0

	local function spawn(yawOff, elev, col, bri, fov)
		local dir = Angle(-elev, baseYaw + yawOff, 0):Forward()
		local pos = center + dir * dist
		local ang = (center - pos):Angle()
		C.SendLightSpawn(1, pos, ang, col, dist * 1.8, bri, fov)
	end
	spawn(40,  35, Color(255, 244, 224), 3.0, 45)   -- key: warm, strong
	spawn(-45, 15, Color(201, 226, 255), 1.2, 60)   -- fill: cool, soft
	spawn(180, 30, Color(255, 255, 255), 2.5, 45)   -- rim: backlight from behind
	spawn(0, -12, Color(255, 226, 200), 0.8, 90)    -- bounce: dim, warm, from below/front
end

-- The master colour of a light rig: the lights of the rig are selected (Shift + click), and
-- one colour is given to all of them, keeping each light's own radius, brightness and cone.
function C.TintSelectedLights()
	local lights = {}
	for _, e in ipairs(C.SelectionList()) do
		if IsValid(e) and C.IsLight(e) then lights[#lights + 1] = e end
	end
	if #lights == 0 then SPeditor.Notify("#light_master_need", 1) return end
	UI.OpenColorPopup(L("light_master"), Color(255, 244, 224), function(col)
		for _, e in ipairs(lights) do
			if IsValid(e) then
				C.SendLightEdit(e, e:GetLightType(), col, e:GetLightRadius(), e:GetLightBrightness(), e:GetLightFOV(), nil, true)
			end
		end
	end)
end

---------------------------------------------------------------------
-- Pose copy / paste
---------------------------------------------------------------------
C.poseClip = C.poseClip or nil

function C.CopyPose(ent)
	if not IsValid(ent) or C.IsAux(ent) then SPeditor.Notify(L("pose_need_entity"), 0) return end
	local model = ent:GetModel()
	C.RequestPose(ent, function(pose)
		if not pose then return end
		C.poseClip = { model = model, pose = pose }
		SPeditor.Notify(L("pose_copied"), 2)
	end)
end

function C.PastePose(ent)
	local clip = C.poseClip
	if not clip then SPeditor.Notify(L("pose_clip_empty"), 0) return end
	if not IsValid(ent) or C.IsAux(ent) then SPeditor.Notify(L("pose_need_entity"), 0) return end
	-- a pose from another model fits if bone names are recorded in it
	if ent:GetModel() ~= clip.model and type(clip.pose.names) ~= "table" then SPeditor.Notify(L("pose_clip_model"), 1) return end
	C.SnapshotThen(ent, "paste pose", function() C.SendPoseApply(ent, clip.pose) end)
end

---------------------------------------------------------------------
-- Frame guides
---------------------------------------------------------------------
local cvGuides = CreateClientConVar("gmfm_guides", "thirds", true, false)
C.GUIDE_LIST = { "thirds", "center", "safe", "golden" }

function C.HasGuide(id)
	return string.find("," .. cvGuides:GetString() .. ",", "," .. id .. ",", 1, true) ~= nil
end

function C.ToggleGuide(id)
	local set, out = {}, {}
	for part in string.gmatch(cvGuides:GetString(), "[^,]+") do set[part] = true end
	set[id] = not set[id] or nil
	for _, g in ipairs(C.GUIDE_LIST) do if set[g] then out[#out + 1] = g end end
	RunConsoleCommand("gmfm_guides", table.concat(out, ","))
end

-- x, y, w, h — the frame rectangle in local panel coordinates
function C.DrawGuides(x, y, w, h)
	local line = Color(255, 255, 255, 90)
	local function vline(fx) surface.SetDrawColor(line) surface.DrawLine(x + w * fx, y, x + w * fx, y + h) end
	local function hline(fy) surface.SetDrawColor(line) surface.DrawLine(x, y + h * fy, x + w, y + h * fy) end
	if C.HasGuide("thirds") then vline(1 / 3) vline(2 / 3) hline(1 / 3) hline(2 / 3) end
	if C.HasGuide("golden") then vline(0.382) vline(0.618) hline(0.382) hline(0.618) end
	if C.HasGuide("center") then
		surface.SetDrawColor(255, 255, 255, 120)
		surface.DrawLine(x + w / 2 - 10, y + h / 2, x + w / 2 + 10, y + h / 2)
		surface.DrawLine(x + w / 2, y + h / 2 - 10, x + w / 2, y + h / 2 + 10)
	end
	if C.HasGuide("safe") then
		surface.SetDrawColor(255, 200, 60, 110)
		for _, m in ipairs({ 0.05, 0.035 }) do
			surface.DrawOutlinedRect(x + w * m, y + h * m, w * (1 - m * 2), h * (1 - m * 2), 1)
		end
	end
end

---------------------------------------------------------------------
-- Autosave
---------------------------------------------------------------------
CreateClientConVar("gmfm_autosave", "1", true, false)

timer.Create("SPeditor.Autosave", 150, 0, function()
	if not C.active or not GetConVar("gmfm_autosave"):GetBool() then return end
	if #C.Objects() == 0 then return end
	C.SceneSave("autosave", C.GetSceneMeta())
end)
