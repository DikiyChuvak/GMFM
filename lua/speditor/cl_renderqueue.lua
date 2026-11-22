--[[
GM:FM — render queue (r1.0, Phase 3).

Render a shot list unattended: every scene camera in turn is used for the Primary Viewport,
the poster renderer is started, and the next shot begins when the previous picture is saved.
The queue is local and never touches the scene — it only changes which camera you look through.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI, C = SPeditor.UI, SPeditor.Client
local L = SPeditor.L

function UI.OpenRenderQueue()
	if IsValid(UI.RenderQueueWin) then UI.RenderQueueWin:Remove() end
	local f = vgui.Create("DFrame")
	UI.RenderQueueWin = f
	f:SetTitle(L("rq_title"))
	f:SetSize(420, 340)
	f:Center()
	f:MakePopup()

	local list = vgui.Create("DListView", f)
	list:Dock(FILL)
	list:DockMargin(8, 8, 8, 8)
	list:AddColumn(L("rq_shot"))
	list:AddColumn(L("rq_camera"))
	local SA = SPeditor.Component and SPeditor.Component("saeditor") and SPeditor.Component("saeditor").SA
	local cams = {}
	if SA and SA.SceneCameras then
		for _, e in ipairs(SA.SceneCameras()) do
			if IsValid(e) then
				cams[#cams + 1] = e
				list:AddLine(tostring(#cams), C.DisplayName(e))
			end
		end
	end

	local bottom = vgui.Create("DPanel", f)
	bottom:Dock(BOTTOM)
	bottom:SetTall(40)
	bottom.Paint = function() end
	local start = vgui.Create("DButton", bottom)
	start:Dock(LEFT)
	start:DockMargin(8, 6, 4, 6)
	start:SetWide(150)
	start:SetText(L("rq_start"))
	local stop = vgui.Create("DButton", bottom)
	stop:Dock(LEFT)
	stop:DockMargin(4, 6, 8, 6)
	stop:SetWide(100)
	stop:SetText(L("rq_stop"))

	local busy, index, waitUntil, phase = false, 0, 0, "idle"
	local function nextShot()
		index = index + 1
		if index > #cams then
			busy, phase = false, "idle"
			if C.GetViewCamera and IsValid(C.GetViewCamera()) then C.StopViewCamera() end
			SPeditor.Notify(L("rq_done"), 3)
			return
		end
		local cam = cams[index]
		if not IsValid(cam) then nextShot() return end
		C.StartViewCamera(cam)
		phase, waitUntil = "aim", RealTime() + 0.5
	end
	hook.Add("Think", "SPeditor.RenderQueue", function()
		if not busy then return end
		local now = RealTime()
		if now < waitUntil then return end
		if phase == "advance" then nextShot()
		elseif phase == "aim" then
			SPeditor.Poster.Start()
			phase, waitUntil = "render", now + 0.5
		elseif phase == "render" and not SPeditor.Poster.Busy() then
			-- the poster keeps its finished job; only its Busy flag changes when it is done
			phase, waitUntil = "advance", now + 0.3
		end
	end)
	start.DoClick = function()
		if #cams == 0 then SPeditor.Notify(L("rq_none"), 1) return end
		index, busy, phase, waitUntil = 0, true, "advance", RealTime() + 0.2
	end
	stop.DoClick = function()
		busy = false
		hook.Remove("Think", "SPeditor.RenderQueue")
		if SPeditor.Poster and SPeditor.Poster.Busy() and SPeditor.Poster.Stop then SPeditor.Poster.Stop() end
		f:Close()
	end
	f.OnRemove = function() hook.Remove("Think", "SPeditor.RenderQueue") busy = false end
end
