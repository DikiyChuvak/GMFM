--[[
SPeditor — an example of a notification style written in Lua ("Neon").

Any addon may put such files into lua/speditor_notify/*.lua: SPeditor runs them on the
client after its own files (the server sends them to players). A file calls
  SPeditor.UI.AddNotifyStyle(id, def)          — a style for Interface settings → Notifications
  SPeditor.UI.AddNotifySoundSet(id, def)       — a sound set: { name = "…", [0] = info,
                                                 [1] = error, [2] = success, [3] = save }
                                                 (paths relative to sound/, or "data/…")
def of a style:
  name        the name in the list
  font, pad   the font and the padding of the card; icon = icon size (0 — none)
  bg(panel, w, h, kindColor)   draws the background; the text and icon are drawn by SPeditor
  text(kindColor) -> Color     the text colour
  shadow, center, title, gmodIcons, iconDisc — as the built-in styles (cl_ui_notify.lua)
  or paint(panel, w, h, kindColor, kind) to draw the whole card alone
  (panel.lines — the wrapped text, panel.lineH, panel.textX, panel.count).
Helpers: SPeditor.UI.NotifyDraw.outline(x, y, w, h, radius, color), .blur(panel, amount),
.mix(colorA, colorB, t), .withAlpha(color, a), .gradDown / .gradUp (materials).
]]
local UI = SPeditor and SPeditor.UI
if not (UI and UI.AddNotifyStyle) then return end
local D = UI.NotifyDraw

UI.AddNotifyStyle("neon", {
	name = "Neon",
	font = "SPeditor.Bold", pad = 10, icon = 16,
	bg = function(p, w, h, kc)
		draw.RoundedBox(6, 0, 0, w, h, Color(8, 6, 16, 240))
		-- a glow: the frame drawn a few times, fainter outwards
		for i = 0, 3 do
			D.outline(i, i, w - i * 2, h - i * 2, math.max(6 - i, 0), D.withAlpha(kc, 200 - i * 50))
		end
		-- a pulse along the bottom edge
		local t = (RealTime() * 0.6) % 1
		surface.SetDrawColor(kc.r, kc.g, kc.b, 160)
		surface.DrawRect(4 + (w - 48) * t, h - 6, 40, 2)
	end,
	text = function(kc) return D.mix(Color(255, 255, 255), kc, 0.25) end,
	shadow = true,
})
