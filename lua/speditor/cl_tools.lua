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

---------------------------------------------------------------------
-- Aiming a camera / light at an object
---------------------------------------------------------------------
function C.AimAt(src, target)
	if not (IsValid(src) and IsValid(target)) or src == target then return false end
	if not C.IsAux(src) then return false end
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

-- Menu for picking the object to aim src at: once (C.AimAt), or for good — the look-at
-- keeps src turned to it while either of them moves (C.SendAim, a0.7)
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
	for _, obj in ipairs(targets) do
		menu:AddOption(obj.name, function() C.AimAt(src, obj.ent) end)
	end
	-- look-at: only a camera or a light can keep turning
	if IsValid(src) and (C.IsCamera(src) or C.IsLight(src)) then
		local cur = src:GetNW2Entity("SPeditor_AimAt")
		menu:AddSpacer()
		local follow, opt = menu:AddSubMenu(L("aim_follow"))
		if opt and opt.SetIcon then opt:SetIcon("icon16/eye.png") end
		for _, obj in ipairs(targets) do
			follow:AddOption(obj.name, function() C.SendAim(src, obj.ent, -1) end):SetChecked(cur == obj.ent)
		end
		if IsValid(cur) then
			menu:AddOption(L("aim_follow_stop") .. "  (" .. C.DisplayName(cur) .. ")", function() C.SendAim(src, nil) end):SetIcon("icon16/cross.png")
		end
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
local cvGuides = CreateClientConVar("speditor_guides", "thirds", true, false)
C.GUIDE_LIST = { "thirds", "center", "safe", "golden" }

function C.HasGuide(id)
	return string.find("," .. cvGuides:GetString() .. ",", "," .. id .. ",", 1, true) ~= nil
end

function C.ToggleGuide(id)
	local set, out = {}, {}
	for part in string.gmatch(cvGuides:GetString(), "[^,]+") do set[part] = true end
	set[id] = not set[id] or nil
	for _, g in ipairs(C.GUIDE_LIST) do if set[g] then out[#out + 1] = g end end
	RunConsoleCommand("speditor_guides", table.concat(out, ","))
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
CreateClientConVar("speditor_autosave", "1", true, false)

timer.Create("SPeditor.Autosave", 150, 0, function()
	if not C.active or not GetConVar("speditor_autosave"):GetBool() then return end
	if #C.Objects() == 0 then return end
	C.SceneSave("autosave", C.GetSceneMeta())
end)
