--[[
GM:FM — rig editor (r1.0, Phase 4).

A per-model list of bones the posing tools should treat as the character's rig: a simple
profile saved in data/speditor/rigs/. This is the first step toward a full rig editor —
GMod models bring their own skeleton, so the editor works with the bones a model has and
lets you mark the ones used by IK and Auto pose instead of creating new ones.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI, C = SPeditor.UI, SPeditor.Client
local L = SPeditor.L

local function dir() return SPeditor.Config.SaveDir .. "/rigs" end
local function profilePath(model)
	dir()
	return dir() .. "/" .. SPeditor.SafeName(string.GetFileFromFilename(model or "model")) .. ".json"
end

function UI.OpenRigEditor(ent)
	ent = ent or C.selected
	if not IsValid(ent) or ent:GetBoneCount() == 0 then SPeditor.Notify(L("rig_need"), 1) return end
	if IsValid(UI.RigEditorWin) then UI.RigEditorWin:Remove() end
	local data = util.JSONToTable(file.Read(profilePath(ent:GetModel()), "DATA") or "") or {}
	data.bones = type(data.bones) == "table" and data.bones or {}
	local f = vgui.Create("DFrame")
	UI.RigEditorWin = f
	f:SetTitle(L("rig_title") .. ": " .. C.DisplayName(ent))
	f:SetSize(480, 480)
	f:Center()
	f:MakePopup()
	local scroll = vgui.Create("DScrollPanel", f)
	scroll:Dock(FILL)
	scroll:DockMargin(8, 8, 8, 8)
	for b = 0, ent:GetBoneCount() - 1 do
		local name = ent:GetBoneName(b) or ("bone " .. b)
		if name ~= "__INVALIDBONE__" then
			local cb = UI.Check(scroll, name, data.bones[tostring(b)] == true, function(on)
				data.bones[tostring(b)] = on and true or nil
			end)
			cb:Dock(TOP)
			cb:DockMargin(2, 0, 2, 0)
		end
	end
	local foot = vgui.Create("DPanel", f)
	foot:Dock(BOTTOM)
	foot:SetTall(36)
	foot.Paint = function() end
	local save = vgui.Create("DButton", foot)
	save:Dock(RIGHT)
	save:DockMargin(8, 5, 8, 5)
	save:SetWide(130)
	save:SetText(L("rig_save"))
	save.DoClick = function()
		file.Write(profilePath(ent:GetModel()), util.TableToJSON({ model = ent:GetModel(), bones = data.bones }, true))
		SPeditor.Notify(L("rig_saved"), 2)
		f:Close()
	end
end
