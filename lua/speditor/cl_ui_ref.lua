--[[
SPeditor — Windows → Reference video (b0.2.7, asked on the Workshop: "a webm from a folder as a
panel, so the reference clip sits beside the editor instead of alt-tabbing"; b0.2.7: "the video
follows the timeline, started at a chosen frame").

Clips are the .webm and .mov (H.264) files in garrysmod/data/speditor/refs/
The window plays the chosen one in a browser panel. Nothing is copied or sent anywhere.
Start at the playhead: the clip starts at the frame the playhead is on now and follows the timeline
(the editor's frame and play state) until it is switched off.

  UI.OpenRef()    the window (opened again, it is brought to the front)
]]
SPeditor = SPeditor or {}
local UI   = SPeditor.UI
local L    = SPeditor.L
local COL  = UI.PAL
local Dock = SPeditor.Dock

local DIR = "speditor/refs/"
local EXTS = { "webm", "mov" }

-- the clip the window plays, its page and the timeline sync: { frame = the frame the clip starts at }
local sync = nil
local player = nil

local EMPTY = '<!doctype html><html><body style="margin:0;background:#111;color:#888;font-family:sans-serif;padding:12px">'

-- the clip names in the folder (the engine's search takes one "*" only, so each extension is looked for on its own)
local function clips()
	file.CreateDir(DIR)
	local out = {}
	for _, ext in ipairs(EXTS) do
		for _, name in ipairs(file.Find(DIR .. "*." .. ext, "DATA")) do out[#out + 1] = name end
	end
	table.sort(out)
	return out
end

-- the page that plays one clip; the name goes into the address as it is (no quotes in file names)
local function pageOf(name)
	local src = "asset://garrysmod/data/" .. DIR .. string.gsub(name, '["<>]', "")
	return '<!doctype html><html><body style="margin:0;background:#111;height:100%">'
		.. '<video src="' .. src .. '" controls autoplay loop style="width:100%;height:100%;object-fit:contain"></video>'
		.. "</body></html>"
end

-- the editor's animation clock (the client's saeditor component); nil before the editor is loaded
local function anim()
	local comp = SPeditor.Components and SPeditor.Components.byId and SPeditor.Components.byId.saeditor
	return comp and comp.SA or nil
end

-- every tick while the sync is on: the clip's time is the timeline's time since the start frame
local function followTimeline()
	if not sync or not IsValid(player) then return end
	local SA = anim()
	if not SA then return end
	local fps = math.max(tonumber(SA.fps) or 24, 1)
	local t = math.max(((tonumber(SA.frame) or 0) - sync.frame) / fps, 0)
	player:RunJavascript(string.format(
		"(function(){var v=document.querySelector('video');if(!v)return;var t=%.3f;" ..
		"if(Math.abs(v.currentTime-t)>0.2)v.currentTime=t;if(%s)v.play();else v.pause();})();",
		t, SA.playing and "true" or "false"))
end

timer.Create("SPeditor.RefSync", 0.2, 0, function()
	if not IsValid(player) then sync = nil return end
	followTimeline()
end)

function UI.OpenRef()
	local win = Dock.ByKey("ref")
	if IsValid(win) then
		Dock.ShowPage("ref")
		return win
	end
	local W = UI.S(520)
	local win, body = Dock.Create({ key = "ref", id = "ref", title = L("ref_title"), w = W, h = UI.S(400),
		x = 40, y = 120, dockable = false, icon = "icon16/film.png" })
	win.minW, win.minH = UI.S(300), UI.S(240)

	local folder = vgui.Create("DLabel", body)
	folder:Dock(TOP)
	folder:DockMargin(8, 6, 8, 2)
	folder:SetFont("SPeditor.Small")
	folder:SetTextColor(COL.DIM)
	folder:SetText(L("ref_folder") .. ": data/" .. DIR)

	local combo = UI.StyleCombo(vgui.Create("DComboBox", body))
	combo:Dock(TOP)
	combo:DockMargin(8, 2, 8, 4)
	combo:SetTall(UI.S(24))
	combo:SetValue(L("ref_pick"))

	local status = vgui.Create("DLabel", body)
	status:Dock(TOP)
	status:DockMargin(8, 0, 8, 2)
	status:SetFont("SPeditor.Small")
	status:SetTextColor(COL.DIM)
	local function showStatus()
		if sync then
			status:SetText(string.format(L("ref_sync_on"), sync.frame))
		else
			status:SetText(L("ref_sync_off"))
		end
	end
	showStatus()

	player = vgui.Create("DHTML", body)
	player:Dock(FILL)
	player:DockMargin(8, 0, 8, 4)
	player:SetHTML(EMPTY .. L("ref_none") .. "</body></html>")

	local function fill()
		combo:Clear()
		combo:SetValue(L("ref_pick"))
		local list = clips()
		for _, name in ipairs(list) do combo:AddChoice(name) end
		if #list == 0 then player:SetHTML(EMPTY .. L("ref_none") .. "</body></html>") end
	end
	combo.OnSelect = function(_, _, name)
		player:SetHTML(pageOf(name))
	end
	fill()

	local row = vgui.Create("DPanel", body)
	row:Dock(BOTTOM)
	row:DockMargin(8, 0, 8, 6)
	row:SetTall(UI.S(26))
	row.Paint = function() end
	local refresh = UI.Button(row, L("ref_refresh"), "icon16/arrow_refresh.png", fill, 26)
	refresh:Dock(LEFT)
	refresh:SetWide(UI.S(150))
	local copy = UI.Button(row, L("ref_copy"), "icon16/page_copy.png", function()
		SetClipboardText("garrysmod/data/" .. DIR)
		SPeditor.Notify("#ref_copied", 2)
	end, 26)
	copy:Dock(RIGHT)
	copy:SetWide(UI.S(170))

	-- (b0.2.7) the clip starts at the playhead and follows the timeline; again — the sync is off
	local syncRow = vgui.Create("DPanel", body)
	syncRow:Dock(BOTTOM)
	syncRow:DockMargin(8, 0, 8, 4)
	syncRow:SetTall(UI.S(26))
	syncRow.Paint = function() end
	local syncBtn
	local function paintSync()
		syncBtn:SetText((UI.ButtonPad or "  ") .. L(sync and "ref_sync_stop" or "ref_sync_start"))
		syncBtn:SetIcon(sync and "icon16/stop.png" or "icon16/control_play_blue.png")
	end
	syncBtn = UI.Button(syncRow, L("ref_sync_start"), "icon16/control_play_blue.png", function()
		local SA = anim()
		if sync then
			sync = nil
		else
			sync = { frame = SA and math.floor((tonumber(SA.frame) or 0) + 0.5) or 0 }
		end
		showStatus()
		paintSync()
	end, 26)
	syncBtn:Dock(FILL)
	paintSync()

	return win
end
