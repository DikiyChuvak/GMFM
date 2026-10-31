--[[
SPeditor — Windows → Reference video (b0.2.7, asked on the Workshop: "a webm from a folder as a
panel, so the reference clip sits beside the editor instead of alt-tabbing").

Clips are the .webm and .mov (H.264) files in garrysmod/data/speditor/refs/
The window plays the chosen one in a browser panel. Nothing is copied or sent anywhere.

  UI.OpenRef()    the window (opened again, it is brought to the front)
]]
SPeditor = SPeditor or {}
local UI   = SPeditor.UI
local L    = SPeditor.L
local COL  = UI.PAL
local Dock = SPeditor.Dock

local DIR = "speditor/refs/"
local EXTS = { "webm", "mov" }

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

	local player = vgui.Create("DHTML", body)
	player:Dock(FILL)
	player:DockMargin(8, 0, 8, 4)
	player:SetHTML('<!doctype html><html><body style="margin:0;background:#111;color:#888;font-family:sans-serif;padding:12px">'
		.. L("ref_none") .. "</body></html>")

	local function fill()
		combo:Clear()
		combo:SetValue(L("ref_pick"))
		local list = clips()
		for _, name in ipairs(list) do combo:AddChoice(name) end
		if #list == 0 then
			player:SetHTML('<!doctype html><html><body style="margin:0;background:#111;color:#888;font-family:sans-serif;padding:12px">'
				.. L("ref_none") .. "</body></html>")
		end
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
	refresh:SetWide(UI.S(160))
	local copy = UI.Button(row, L("ref_copy"), "icon16/page_copy.png", function()
		SetClipboardText("garrysmod/data/" .. DIR)
		SPeditor.Notify("#ref_copied", 2)
	end, 26)
	copy:Dock(RIGHT)
	copy:SetWide(UI.S(200))

	return win
end
