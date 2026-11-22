--[[
GM:FM — audio mixer (r1.0, Phase 4).

All sound clips of the timeline in one place: volume and pitch of each clip, a mute switch
for the whole track, and the number of voices playing now. The changes go through the
existing SA.ChangeSound, so they are part of the scene and of Undo like edits in the
Sounds window.
]]
SPeditor = SPeditor or {}
SPeditor.UI = SPeditor.UI or {}
local UI, C = SPeditor.UI, SPeditor.Client
local L = SPeditor.L

function UI.OpenAudioMixer()
	if IsValid(UI.AudioMixerWin) then UI.AudioMixerWin:Remove() end
	local SA = SPeditor.Component("saeditor").SA
	local f = vgui.Create("DFrame")
	UI.AudioMixerWin = f
	f:SetTitle(L("mixer_title"))
	f:SetSize(560, 460)
	f:Center()
	f:MakePopup()

	local scroll = vgui.Create("DScrollPanel", f)
	scroll:Dock(FILL)
	scroll:DockMargin(8, 8, 8, 8)
	local function rebuild()
		scroll:Clear()
		for _, c in ipairs(SA.sounds or {}) do
			local row = vgui.Create("DPanel", scroll)
			row:Dock(TOP)
			row:DockMargin(0, 0, 0, 4)
			row:SetTall(88)
			row.Paint = function(s, w, h)
				surface.SetDrawColor(UI.PAL and UI.PAL.ROW_B or Color(50, 50, 55))
				surface.DrawRect(0, 0, w, h)
			end
			local name = vgui.Create("DLabel", row)
			name:SetPos(8, 4)
			name:SetSize(520, 18)
			name:SetFont("SPeditor.Small")
			name:SetTextColor(UI.PAL and UI.PAL.TEXT or color_white)
			name:SetText(string.format("#%d  %s  ·  %s", c.id or 0, tostring(c.path or ""), tostring(c.name or "")))
			local vol = UI.Slider(row, L("mixer_volume"), 0, 2, 2, c.vol or 1)
			vol:SetPos(8, 24)
			vol:SetSize(260, 22)
			vol.OnValueChanged = function(_, v) SA.ChangeSound(c.id, { vol = v }) end
			local pitch = UI.Slider(row, L("mixer_pitch"), 50, 200, 0, c.pitch or 100)
			pitch:SetPos(284, 24)
			pitch:SetSize(260, 22)
			pitch.OnValueChanged = function(_, v) SA.ChangeSound(c.id, { pitch = math.floor(v) }) end
			local mute = UI.Check(row, L("mixer_mute"), c.mute and true or false, function(on)
				SA.ChangeSound(c.id, { mute = on and true or nil })
			end)
			mute:SetPos(8, 54)
		end
	end
	rebuild()
	local foot = vgui.Create("DPanel", f)
	foot:Dock(BOTTOM)
	foot:SetTall(34)
	foot.Paint = function() end
	local refresh = vgui.Create("DButton", foot)
	refresh:Dock(RIGHT)
	refresh:DockMargin(8, 5, 8, 5)
	refresh:SetWide(110)
	refresh:SetText(L("mixer_refresh"))
	refresh.DoClick = rebuild
	hook.Run("SPeditor_AudioMixerOpen", f)
end
