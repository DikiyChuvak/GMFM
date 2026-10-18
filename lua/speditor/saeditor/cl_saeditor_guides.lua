-- SAeditor — its guides in Help → How to use (cl_ui_guide.lua), with live demonstrations
-- drawn by the same code the tools use (SA.DrawMotion of the curve editor).
local COMP = SPeditor.Component("saeditor")
local SA  = COMP.SA
local UI  = SPeditor.UI
local C   = SPeditor.Client
local L   = SPeditor.L
local COL = UI.PAL
local T   = UI.GuideText

local function smooth(u) u = math.Clamp(u, 0, 1) return u * u * (3 - 2 * u) end

-- demo: every kind of easing at once, a lane each
local function easesDemo(w, h, t)
	local kinds = SA.EASES
	local lane = h / #kinds
	for i, e in ipairs(kinds) do
		local y = (i - 1) * lane
		draw.SimpleText(L("sa_ease_" .. e), "SPeditor.Small", 10, y + lane / 2, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		SA.DrawMotion(190, y, w - 200, lane, e, nil, t)
	end
end

-- demo: an own curve that overshoots the key, its graph on the left and the motion on the right
local OVERSHOOT = { 0.25, 0.1, 0.35, 1.45 }
local function overshootDemo(w, h, t)
	local gx, gy, gw, gh = 14, 12, 120, h - 24
	surface.SetDrawColor(COL.BORDER)
	surface.DrawOutlinedRect(gx, gy, gw, gh)
	local function pt(u, v) return gx + u * gw, gy + gh - (v + 0.25) / 1.75 * gh end
	-- the 0 and 1 levels (the two keys)
	for _, v in ipairs({ 0, 1 }) do
		local _, yy = pt(0, v)
		surface.SetDrawColor(COL.DIM.r, COL.DIM.g, COL.DIM.b, 90)
		surface.DrawRect(gx, yy, gw, 1)
	end
	local px, py
	for i = 0, 40 do
		local u = i / 40
		local x, y = pt(u, SA.BezierEase(u, OVERSHOOT))
		if px then
			surface.SetDrawColor(COL.ORANGE)
			surface.DrawLine(px, py, x, y)
		end
		px, py = x, y
	end
	-- the two handles
	local ax, ay = pt(0, 0)
	local bx, by = pt(1, 1)
	local h1x, h1y = pt(OVERSHOOT[1], OVERSHOOT[2])
	local h2x, h2y = pt(OVERSHOOT[3], OVERSHOOT[4])
	surface.SetDrawColor(COL.TEXT)
	surface.DrawLine(ax, ay, h1x, h1y)
	surface.DrawLine(bx, by, h2x, h2y)
	surface.DrawRect(h1x - 3, h1y - 3, 6, 6)
	surface.DrawRect(h2x - 3, h2y - 3, 6, 6)
	draw.SimpleText(SA.EaseWords("bezier", OVERSHOOT), "SPeditor.Small", gw + 30, 14, COL.ORANGE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	SA.DrawMotion(gw + 30, 20, w - gw - 40, h - 24, "bezier", OVERSHOOT, t)
end

-- demo: two bones with keys of their own; each arm moves between its own keys
local function boneKeysDemo(w, h, t)
	local len = 2.4
	local f = (t % (len + 0.8)) / len          -- 0..1 over the timeline, then a pause at the end
	f = math.min(f, 1)
	local tlx, tlw = 150, w - 330
	local lanes = {
		{ name = T("Right arm", "Правая рука"), keys = { 0, 0.4 }, from = -60, to = 60 },
		{ name = T("Left arm", "Левая рука"), keys = { 0, 1 }, from = 60, to = -60 },
	}
	for i, ln in ipairs(lanes) do
		local y = 18 + (i - 1) * 30
		draw.SimpleText(ln.name, "SPeditor.Small", 10, y, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		surface.SetDrawColor(COL.BORDER)
		surface.DrawRect(tlx, y, tlw, 1)
		for _, k in ipairs(ln.keys) do
			local x = tlx + k * tlw
			draw.NoTexture()
			surface.SetDrawColor(COL.TEXT)
			surface.DrawPoly({ { x = x, y = y - 5 }, { x = x + 5, y = y }, { x = x, y = y + 5 }, { x = x - 5, y = y } })
		end
		ln.u = smooth((f - ln.keys[1]) / (ln.keys[2] - ln.keys[1]))
	end
	local px = tlx + f * tlw
	surface.SetDrawColor(COL.ORANGE)
	surface.DrawRect(px, 4, 1, 66)
	-- the little figure: a body and two arms
	local cx, cy = w - 90, h / 2 + 4
	surface.SetDrawColor(COL.TEXT)
	surface.DrawRect(cx - 1, cy - 20, 3, 44)
	surface.DrawRect(cx - 6, cy - 34, 13, 13)
	for i, side in ipairs({ -1, 1 }) do
		local ln = lanes[i]
		local a = math.rad(ln.from + (ln.to - ln.from) * ln.u)
		local sx, sy = cx + side * 2, cy - 16
		local ex, ey = sx + side * math.cos(a) * 36, sy + math.sin(a) * 36
		surface.SetDrawColor(i == 1 and COL.ORANGE or COL.TEXT)
		for o = -1, 1 do surface.DrawLine(sx, sy + o, ex, ey + o) end
	end
end

-- demo: the camera row of the timeline and the picture the player shows
local function cutsDemo(w, h, t)
	local len = 3
	local f = math.min((t % (len + 0.6)) / len, 1)
	local tlx, tlw, y = 20, w - 220, 26
	local cuts = { { 0, "Camera 1", Color(70, 120, 200) }, { 0.45, "Camera 2", Color(190, 110, 50) }, { 0.75, "Camera 1", Color(70, 120, 200) } }
	local active
	for i, c in ipairs(cuts) do
		local x0 = tlx + c[1] * tlw
		local x1 = tlx + (cuts[i + 1] and cuts[i + 1][1] or 1) * tlw
		surface.SetDrawColor(c[3])
		surface.DrawRect(x0, y - 8, x1 - x0, 16)
		draw.SimpleText(c[2], "SPeditor.Small", x0 + 4, y, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		if f >= c[1] then active = c end
	end
	surface.SetDrawColor(COL.ORANGE)
	surface.DrawRect(tlx + f * tlw, y - 14, 2, 28)
	-- the "screen" of the player
	local sx, sy, sw, sh = w - 180, 8, 164, h - 16
	surface.SetDrawColor(0, 0, 0, 255)
	surface.DrawRect(sx, sy, sw, sh)
	surface.SetDrawColor(active[3])
	surface.DrawOutlinedRect(sx, sy, sw, sh, 2)
	draw.SimpleText(active[2], "SPeditor.Bold", sx + sw / 2, sy + sh / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(T("the player shows", "плеер показывает"), "SPeditor.Small", sx + sw / 2, sy + sh - 12, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

UI.AddGuide({ id = "sa_keys", order = 10, icon = "icon16/key.png", title = { en = "Animation: keys and the timeline", ru = "Анимация: ключи и таймлайн" }, blocks = {
	{ "p", "A key remembers how an object is at a frame. Between two keys SAeditor moves the object by itself — so an animation is a few poses at a few frames.",
		"Ключ запоминает, каким объект был на кадре. Между двумя ключами SAeditor двигает объект сам — поэтому анимация — это несколько поз на нескольких кадрах." },
	{ "img", "speditor/help/timeline.jpg", "The Timeline (bottom window): the animated objects on the left, their keys (diamonds) on the right.",
		"Таймлайн (нижнее окно): анимированные объекты слева, их ключи (ромбы) справа." },
	{ "steps",
		en = { "Select a character and press K: a key at frame 0.",
			"Click the ruler at frame 24 (one second), change the pose, press K again.",
			"Space plays it. That is an animation.",
			"Auto key (the red dot button): every edit sets the key by itself — pose and move on.",
			"New keys are Continuous: the motion flows through them without stopping (other kinds — right click a key → Motion to the next key).",
			"Keys can be dragged; Ctrl + drag copies. Ctrl + click picks several keys, Shift + drag over empty space picks keys in a box — then they all move, change their motion and are deleted together. Right click a key for its menu." },
		ru = { "Выделите персонажа и нажмите K: ключ на кадре 0.",
			"Щёлкните линейку на кадре 24 (одна секунда), измените позу, снова нажмите K.",
			"Пробел воспроизводит. Это уже анимация.",
			"Автоключ (кнопка с красной точкой): каждая правка сама ставит ключ — позируйте и идите дальше.",
			"Новые ключи — «Непрерывно»: движение перетекает через них без остановок (другие виды — ПКМ по ключу → Движение к следующему ключу).",
			"Ключи можно перетаскивать; Ctrl + перетаскивание копирует. Ctrl + клик выбирает несколько ключей, Shift + перетаскивание по пустому месту — ключи рамкой; тогда они двигаются, меняют движение и удаляются вместе. ПКМ по ключу — его меню." } },
	{ "p", "Changed a pose and it jumped back when the playhead moved? The frame had no key: without Auto key an edit between keys is not kept. Press K (or turn Auto key on) before moving the playhead.",
		"Изменили позу, а она откатилась, когда головка сдвинулась? На кадре не было ключа: без автоключа правка между ключами не сохраняется. Нажмите K (или включите автоключ) до того, как двигать головку." },
	{ "result", "Motion from a few poses; the timeline shows where every object has its keys.",
		"Движение из нескольких поз; таймлайн показывает, где у каждого объекта ключи." },
	{ "see", "first_anim", "a first animation from start to video", "первая анимация от начала до видео" },
	{ "see", "sa_curves", "how objects move between keys, smooth motion", "как объект движется между ключами, плавность" },
} })

UI.AddGuide({ id = "sa_curves", order = 11, icon = "icon16/chart_curve.png", title = { en = "How objects move between keys (curves)", ru = "Как объект движется между ключами (кривые)" }, blocks = {
	{ "p", "Between two keys an object can move evenly, start slowly, stop softly, overshoot… This is the easing of the key (the motion to the next key). Watch the same distance travelled with each kind:",
		"Между двумя ключами объект может ехать равномерно, трогаться медленно, мягко тормозить, проскакивать… Это сглаживание ключа (движение к следующему ключу). Вот одно и то же расстояние с каждым видом:" },
	{ "demo", h = 24 * #SA.EASES, draw = easesDemo, "The grey dots are equal steps of time: where they are close, the object is slow; where they are far apart, it is fast.",
		"Серые точки — равные промежутки времени: где они близко, объект медленный; где далеко — быстрый." },
	{ "h", "Choosing it", "Как выбрать" },
	{ "steps",
		en = { "Right click a key on the timeline → Motion to the next key, or select the key in the Curve editor and press one of the buttons at its top.",
			"Continuous (spline, the kind of every new key) passes through the keys without stopping — the motion flows from pose to pose as in SFM and Blender. Smooth stops at every key; Linear — machines and camera pans; Speed up — falling, throwing; Slow down — arriving, landing; Hold — cuts and switches.",
			"More… has the expressive kinds: With a swing (an anticipation and an overshoot), Springy (a spring), Bouncing (a ball hitting the floor), Gentle and Sharp." },
		ru = { "ПКМ по ключу на таймлайне → Движение к следующему ключу, или выделите ключ в редакторе кривых и нажмите одну из кнопок вверху.",
			"«Непрерывно» (сплайн, так ставится каждый новый ключ) проходит ключи не останавливаясь — движение перетекает из позы в позу, как в SFM и Blender. «Плавно» останавливается на каждом ключе; «Равномерно» — механизмам и панорамам камеры; «Разгон» — падению, броску; «Торможение» — приходу, приземлению; «Скачком» — склейкам и переключениям.",
			"В «Ещё…» — выразительные виды: «С замахом» (замах и перелёт), «Упруго» (пружина), «С подскоками» (мяч об пол), «Мягко» и «Резко»." } },
	{ "h", "Smooth motion without stops", "Плавное движение без остановок" },
	{ "p", "If a character stops at every pose and only then goes on, its keys have the motion Ease (stops at keys) — older scenes and some ready moves use it. Two commands fix it in Edit → Animation:",
		"Если персонаж останавливается в каждой позе и только потом едет дальше, у его ключей движение «Плавно, с остановкой» — так сделаны старые сцены и некоторые готовые движения. В Правка → Анимация это исправляют две команды:" },
	{ "steps",
		en = { "Make the whole animation smooth (continuous keys): every key of every object becomes Continuous at once. Hold keys (jump cuts) stay. One Ctrl + Z takes it back.",
			"New keys move → Continuous / Ease / Linear / Hold: what every new key gets. Continuous is the default; a key that is already there keeps its own motion when you key it again." },
		ru = { "«Сделать всю анимацию плавной (непрерывные ключи)»: все ключи всех объектов разом становятся «Непрерывно». Ключи «Скачком» (резкие склейки) остаются. Одно Ctrl + Z возвращает всё.",
			"«Движение новых ключей» → Непрерывно / Плавно, с остановкой / Равномерно / Скачком: что получает каждый новый ключ. По умолчанию — «Непрерывно»; ключ, который уже есть, при повторной установке сохраняет своё движение." } },
	{ "img", "speditor/help/smooth_menu.jpg", "Edit → Animation: New keys move and Make the whole animation smooth.",
		"Правка → Анимация: «Движение новых ключей» и «Сделать всю анимацию плавной»." },
	{ "tip", "Continuous keys follow the poses around them, so a key far from the others can make the motion swing past it. Add a key in between, or give that one key Ease.",
		"Непрерывные ключи учитывают соседние позы, поэтому ключ, далёкий от остальных, может дать заброс движения мимо него. Добавьте ключ посередине или дайте этому ключу «Плавно, с остановкой»." },
	{ "h", "The curve editor", "Редактор кривых" },
	{ "img", "speditor/help/curves.jpg", "Every line is one value of the selected bone or object over time (X Y Z — place, P Yw R — turn). Here a recorded hand: with Continuous keys the lines pass through the points without breaks. The strip at the bottom shows how the selected key moves, in words and with a ball.",
		"Каждая линия — одно значение выделенной кости или объекта во времени (X Y Z — место, P Yw R — поворот). Здесь записанная кисть: с непрерывными ключами линии проходят через точки без изломов. Полоса внизу показывает, как движется выбранный ключ — словами и шариком." },
	{ "steps",
		en = { "Open it: the chart button of the timeline (or Edit → Animation → Curve editor). It shows what is selected — select a bone to see that bone.",
			"Drag a key point up / down to change its value, left / right to move it in time.",
			"Drag one of the two round handles after a key to bend the motion yourself. Pull a handle above the next key and the object goes past it and comes back:" },
		ru = { "Откройте: кнопка с графиком на таймлайне (или Правка → Анимация → Редактор кривых). Он показывает выделенное — выделите кость, чтобы видеть её.",
			"Тяните точку ключа вверх / вниз, чтобы изменить значение, влево / вправо — чтобы сдвинуть во времени.",
			"Тяните одну из двух круглых ручек после ключа, чтобы согнуть движение самому. Вытяните ручку выше следующего ключа — объект проскочит его и вернётся:" } },
	{ "demo", h = 120, draw = overshootDemo, "An own curve: the handle above the top line (the next key) makes the motion overshoot — good for a punch, a head turn, a bouncing stop.",
		"Своя кривая: ручка выше верхней линии (следующего ключа) даёт перелёт — хорошо для удара, поворота головы, упругой остановки." },
	{ "result", "Motion with weight: slow starts, soft stops and overshoots where you want them.",
		"Движение с весом: медленный старт, мягкие остановки и перелёты там, где нужно." },
	{ "see", "sa_motion", "change a whole stretch at once", "правка целого отрезка" },
	{ "see", "sa_bones", "a rhythm of its own for every bone", "свой ритм для каждой кости" },
	{ "try", "Open the Curve editor", "Открыть редактор кривых", fn = function() SA.OpenCurves() end },
} })

-- demo: the Motion Editor — keys of one value (dots on a line), a time selection over the
-- middle of them, and an edit that rises and falls: the keys inside follow it in full, the ones
-- in the falloff less and less, the ones outside stay
local function motionDemo(w, h, t)
	local x0, x1 = 20, w - 20
	local base, amp = h - 30, h - 60
	local sel = { 5, 8, 12, 15, shape = "smooth" }
	local n = 20
	local function fx(f) return x0 + f / n * (x1 - x0) end
	for x = math.floor(fx(sel[1])), math.ceil(fx(sel[4])), 2 do
		local wt = SA.TimeSelWeight((x - x0) / (x1 - x0) * n, sel)
		surface.SetDrawColor(COL.BLUE.r, COL.BLUE.g, COL.BLUE.b, 60 * wt)
		surface.DrawRect(x, 6, 2, h - 12)
	end
	local lift = (0.5 - 0.5 * math.cos(t * 1.6)) * amp
	surface.SetDrawColor(COL.DIM)
	surface.DrawLine(x0, base, x1, base)
	local prevX, prevY
	for f = 0, n do
		local x, y = fx(f), base - SA.TimeSelWeight(f, sel) * lift
		if prevX then
			surface.SetDrawColor(COL.TAB_ON)
			surface.DrawLine(prevX, prevY, x, y)
		end
		prevX, prevY = x, y
		draw.RoundedBox(3, x - 3, y - 3, 6, 6, (f >= sel[2] and f <= sel[3]) and COL.ORANGE or COL.TEXT)
	end
	draw.SimpleText(T("falloff", "затухание"), "SPeditor.Small", (fx(sel[1]) + fx(sel[2])) / 2, 12, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(T("full", "полностью"), "SPeditor.Small", (fx(sel[2]) + fx(sel[3])) / 2, 12, COL.TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	draw.SimpleText(T("falloff", "затухание"), "SPeditor.Small", (fx(sel[3]) + fx(sel[4])) / 2, 12, COL.DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

UI.AddGuide({ id = "sa_motion", order = 11.5, icon = "icon16/time.png", title = { en = "Motion Editor: change a whole stretch at once", ru = "Motion Editor: правка целого отрезка" }, blocks = {
	{ "p", "A key changes one moment. Often you want more: lift the arm a little higher during the whole wave, push a walk a step to the left, make a head look down for two seconds. The Motion Editor of SFM does this with a time selection, and so does SAeditor.",
		"Ключ меняет один момент. Часто нужно больше: поднять руку чуть выше на всё время взмаха, сдвинуть походку на шаг влево, опустить голову на две секунды. В SFM для этого есть Motion Editor с выделением времени — в SAeditor тоже." },
	{ "img", "speditor/help/motion_editor.jpg", "demo_a07: the time selection 330–480 on the timeline (blue, fading at the edges) and its menu (the clock button or a right click on the frame numbers).",
		"demo_a07: выделение времени 330–480 на таймлайне (синее, гаснущее к краям) и его меню (кнопка с часами или ПКМ по номерам кадров)." },
	{ "demo", h = 120, draw = motionDemo, "The keys in the middle of the selection take the edit in full, the ones in the falloff less and less, the ones outside do not move — the motion stays smooth at both ends.",
		"Ключи в середине выделения получают правку полностью, ключи в затухании — всё меньше, ключи снаружи не двигаются — движение остаётся плавным с обеих сторон." },
	{ "steps",
		en = { "Shift + drag on the frame numbers of the timeline: a time selection. Its middle is drawn blue; the curve above the numbers shows how much an edit counts at every frame.",
			"Drag its edges on the frame numbers. Edges that stand together part when dragged: outwards — a falloff (a soft edge), inwards — a narrower middle.",
			"Or use the clock button (also a right click on the frame numbers): a selection from the selected keys, around the playhead, over the whole animation; the falloff in frames and its shape.",
			"Put the playhead inside the selection, change the pose, press K (Auto key works too): the change goes over the whole selection. Keys are added at its edges, so nothing outside it moves.",
			"Shift + click on the frame numbers (or Remove the time selection) — back to ordinary keys." },
		ru = { "Shift + перетаскивание по номерам кадров таймлайна — выделение времени. Его середина подсвечена синим; кривая над номерами показывает, насколько правка действует на каждом кадре.",
			"Края двигаются там же, на номерах кадров. Края, стоящие вместе, расходятся при перетаскивании: наружу — затухание (мягкий край), внутрь — середина уже.",
			"Или кнопка с часами (и ПКМ по номерам кадров): выделение по выбранным ключам, вокруг курсора, на всю анимацию; затухание в кадрах и его форма.",
			"Поставьте курсор времени внутрь выделения, измените позу, нажмите K (автоключ тоже работает): правка ляжет на всё выделение. По краям добавляются ключи, поэтому снаружи ничего не сдвигается.",
			"Shift + клик по номерам кадров (или «Убрать выделение времени») — снова обычные ключи." } },
	{ "result", "One edit changes seconds of animation, softly blended into what is around it.",
		"Одна правка меняет секунды анимации и мягко вплетается в то, что вокруг." },
	{ "p", "See it in the example scene demo_a07 (Help → How to use → Example scenes): the hero's head turn to the ball is one such edit.",
		"Посмотрите в сцене-примере demo_a07 (Справка → Как пользоваться → Сцены-примеры): поворот головы героя к мячу — одна такая правка." },
	{ "see", "sa_curves", "how the motion between keys is shaped", "как движение между ключами получает форму" },
	{ "try", "Open the time selection menu", "Открыть меню выделения времени", fn = function() SA.TimeSelMenu(math.floor(SA.frame + 0.5)) end },
} })

UI.AddGuide({ id = "sa_bones", order = 12, icon = "icon16/arrow_branch.png", title = { en = "Bone keys and ghosts", ru = "Ключи костей и призраки" }, blocks = {
	{ "p", "Normally a key holds the whole character. With Bone keys on, a key set while a bone is selected holds only that bone — every bone gets keys of its own, as in SFM: an arm can wave twice while the head turns once.",
		"Обычно ключ хранит всего персонажа. С включёнными «Ключами костей» ключ, поставленный при выделенной кости, хранит только её — у каждой кости свои ключи, как в SFM: рука может махнуть дважды, пока голова повернётся один раз." },
	{ "demo", h = 80, draw = boneKeysDemo, "The right arm has keys at 0 and 0.4 of the timeline, the left one at 0 and 1: each moves between its own keys.",
		"У правой руки ключи на 0 и 0.4 таймлайна, у левой — на 0 и 1: каждая движется между своими ключами." },
	{ "steps",
		en = { "Turn on Bone keys: the branch button of the timeline (or Edit → Animation → Bone keys).",
			"Select a bone and press K — a key of that bone only. With Auto key, dragging a bone keys just the bones the drag moved.",
			"The selected bone gets its own row under the character: its keys only. Drag them, delete them (right click) — the rest of the character is not touched.",
			"Keys of some bones are drawn as small hollow diamonds on the character's row; full keys as usual." },
		ru = { "Включите «Ключи костей»: кнопка с веткой на таймлайне (или Правка → Анимация → Ключи костей).",
			"Выделите кость и нажмите K — ключ только этой кости. С автоключом перетаскивание кости ставит ключ только тем костям, которые сдвинулись.",
			"У выделенной кости появляется своя строка под персонажем: только её ключи. Их можно двигать и удалять (ПКМ) — остальной персонаж не меняется.",
			"Ключи отдельных костей рисуются на строке персонажа маленькими полыми ромбами, полные ключи — как обычно." } },
	{ "h", "Ghosts", "Призраки" },
	{ "img", "speditor/help/bonekeys.jpg", "Ghosts on: the arm at the key before the playhead is drawn see-through in blue, at the key after it — in green. Below — the row of the selected bone.",
		"Призраки включены: рука на ключе перед головкой полупрозрачная синяя, на ключе после неё — зелёная. Внизу — строка выделенной кости." },
	{ "p", "The grey figure button of the timeline shows the selected character at its previous and next keys, so you see where the motion comes from and goes to without scrubbing.",
		"Кнопка с серой фигурой на таймлайне показывает выделенного персонажа на предыдущем и следующем ключах — видно, откуда и куда идёт движение, без перемотки." },
	{ "see", "sa_keys", "keys and the timeline", "ключи и таймлайн" },
	{ "see", "posing", "IK, stretch, locks", "IK, растяжение, замки" },
	{ "result", "Layered animation: separate rhythms for the arms, the head and the body, and the neighbouring poses always in sight.",
		"Слоёная анимация: свой ритм у рук, головы и тела, а соседние позы всегда перед глазами." },
} })

UI.AddGuide({ id = "sa_cuts", order = 13, icon = "icon16/camera_go.png", title = { en = "Cameras of the animation and the player", ru = "Камеры анимации и плеер" }, blocks = {
	{ "p", "The Cameras row at the top of the timeline says which scene camera the animation is watched through, from which frame on — like shots in a film. The player and the video follow it.",
		"Строка «Камеры» вверху таймлайна говорит, через какую камеру сцены смотреть анимацию, с какого кадра, — как планы в фильме. Плеер и видео следуют ей." },
	{ "demo", h = 90, draw = cutsDemo, "Camera 1, then Camera 2 from the middle, then Camera 1 again: the player switches exactly there.",
		"Сначала Camera 1, с середины Camera 2, потом снова Camera 1: плеер переключается ровно там." },
	{ "img", "speditor/help/cuts.jpg", "The Cameras row: a coloured band per shot, named after its camera.", "Строка «Камеры»: цветная полоса на каждый план, подписанная именем камеры." },
	{ "steps",
		en = { "Add two cameras to the scene and place them.",
			"Right click the Cameras row at a frame → Switch to Camera 1 here. Do the same later for Camera 2.",
			"Drag a cut mark to move it; right click it to change its camera or delete it. Ctrl + Z undoes.",
			"The player: the TV button of the timeline (or File → Watch in the game → Player). A click on the camera name at the top of the player picks another camera.",
			"The same shots are listed in the Render window → Animation → Cameras of the video, where they can be added and changed without the timeline." },
		ru = { "Добавьте в сцену две камеры и расставьте их.",
			"ПКМ по строке «Камеры» на нужном кадре → Переключиться на Camera 1 здесь. Позже так же для Camera 2.",
			"Метку смены можно перетащить; ПКМ по ней — сменить камеру или удалить. Ctrl + Z отменяет.",
			"Плеер: кнопка с телевизором на таймлайне (или Файл → Смотреть в игре → Плеер). Щелчок по имени камеры вверху плеера выбирает другую камеру.",
			"Те же планы перечислены в окне «Рендер» → «Анимация» → «Камеры видео» — там их можно добавлять и менять без таймлайна." } },
	{ "h", "The player", "Плеер" },
	{ "img", "speditor/help/player.jpg", "The player: the scene and the camera at the top, the seek bar with the shots marked, play / pause in the middle, stop and the previous / next shot beside it, repeat on the left, the volume on the right.",
		"Плеер: сцена и камера сверху, полоса перемотки с отмеченными планами, пуск / пауза в центре, рядом стоп и предыдущий / следующий план, слева повтор, справа громкость." },
	{ "p", "Keys: Space — play / pause, ← → — 5 seconds, PgUp / PgDn — the previous / next shot, Home / End, ↑ ↓ — volume, M — mute, R — repeat, V — render settings, Backspace or the cross — leave. The bar hides while the mouse rests and comes back when it moves; a click on the picture pauses.",
		"Клавиши: Пробел — пуск / пауза, ← → — 5 секунд, PgUp / PgDn — предыдущий / следующий план, Home / End, ↑ ↓ — громкость, M — без звука, R — повтор, V — настройки рендера, Backspace или крестик — выйти. Панель прячется, пока мышь не двигается, и появляется снова; щелчок по картинке ставит паузу." },
	{ "p", "Render settings (the button beside repeat): the player shows the video as the Render window will make it — its frame proportions with black bars, camera effects, depth of field, soft shadows, the engine frame — before you render anything. While it plays, depth of field and soft shadows are lighter; on pause the frame is full.",
		"Настройки рендера (кнопка рядом с повтором): плеер показывает видео таким, каким его сделает окно «Рендер», — его пропорции кадра с чёрными полями, эффекты камеры, глубина резкости, мягкие тени, кадр движка — ещё до рендера. Во время воспроизведения глубина резкости и мягкие тени облегчены, на паузе кадр полный." },
	{ "h", "Walking around the scene", "Ходить по сцене" },
	{ "p", "The eye button of the timeline (File → Watch in the game → Walk around the scene): the animation plays while you walk around it yourself, with your HUD and weapon, and look at it from any side. Backspace stops it.",
		"Кнопка с глазом на таймлайне (Файл → Смотреть в игре → Ходить по сцене): анимация идёт, а вы сами ходите вокруг неё, с HUD и оружием, и смотрите с любой стороны. Backspace — стоп." },
	{ "see", "camera", "cameras, look-at, recording a camera", "камеры, слежение, запись камеры" },
	{ "see", "sa_render", "render the shots to a video", "рендер планов в видео" },
	{ "result", "The animation watched in the game as a finished film, with its camera changes — and rendered to video the same way.",
		"Анимация смотрится в игре как готовый фильм со сменами камер — и так же рендерится в видео." },
} })

UI.AddGuide({ id = "sa_rec", order = 12.5, icon = "icon16/webcam.png", title = { en = "Record gameplay (machinima)", ru = "Запись игры (машинима)" }, blocks = {
	{ "p", "Instead of posing every frame you can simply play: walk, run, shoot, let the NPCs around do their thing. The take becomes ordinary keys, sounds and effects that you edit like any animation.",
		"Вместо того чтобы позировать каждый кадр, можно просто играть: ходить, бегать, стрелять, а NPC вокруг живут своей жизнью. Дубль становится обычными ключами, звуками и эффектами, которые правятся как любая анимация." },
	{ "img", "speditor/help/rec_window.jpg", "The Record gameplay window (the webcam button of the timeline, or File → Record gameplay…): what to record, the physics of the scene, and Record physics only.",
		"Окно «Запись игры» (кнопка с веб-камерой на таймлайне или Файл → Запись игры…): что записывать, физика сцены и «Записать только физику»." },
	{ "steps",
		en = { "Put the playhead where the take should start. Open Record gameplay and choose what to record: the NPCs around (within the radius), sounds, effects, how often a key is taken.",
			"Start recording: the editor closes, a countdown runs, then REC blinks in the corner. Play. The animation you already have plays along, so you can act against it.",
			"Backspace stops the take. The editor opens: you are in the scene as a ragdoll of your player model (skin, bodygroups, player colour) with your weapon in the hand, every NPC with its weapon, the sounds on the timeline and the effects as objects. Objects of the map that moved during the take move in the animation at the same moments.",
			"Record my view as a camera (on by default): what you saw becomes the camera <your name> view (rec), keyed along the take — your look, turns and zoom. With no camera cuts yet the video goes through it at once; your own body is not drawn in it, as in the game (the weapon in your hands is seen only from other cameras).",
			"Edit it like any animation: delete keys, fix a pose (with Bone keys — just one arm), add cameras and cuts, record another take on top." },
		ru = { "Поставьте головку туда, где должен начаться дубль. Откройте «Запись игры» и выберите, что записывать: NPC вокруг (в радиусе), звуки, эффекты, как часто брать ключ.",
			"«Начать запись»: редактор закроется, пойдёт отсчёт, потом в углу замигает REC. Играйте. Уже сделанная анимация идёт вместе с записью — можно играть против неё.",
			"Backspace останавливает дубль. Откроется редактор: в сцене вы — рэгдолл вашей модели игрока (скин, бодигруппы, цвет игрока) с оружием в руке, каждый NPC со своим оружием, звуки на таймлайне и эффекты отдельными объектами. Объекты карты, которые двигались во время дубля, двигаются в анимации в те же моменты.",
			"«Записать мой вид как камеру» (включено по умолчанию): то, что вы видели, становится камерой <ваш ник> view (rec) с ключами по всему дублю — взгляд, повороты и зум. Если смен камер ещё нет, видео сразу идёт через неё; ваше тело в ней не рисуется, как в игре (оружие в руках видно только с других камер).",
			"Правьте как любую анимацию: удалите лишние ключи, поправьте позу (с ключами костей — одну руку), добавьте камеры и смены камер, запишите поверх ещё один дубль." } },
	{ "img", "speditor/help/rec_result.jpg", "A recorded take: the player with a crowbar and a citizen with an SMG, keyed every 2 frames; the tracer and the explosion are effect objects, the shot is a sound from the player.",
		"Записанный дубль: игрок с монтировкой и гражданин с SMG, ключ каждые 2 кадра; трассер и взрыв — объекты-эффекты, выстрел — звук от игрока." },
	{ "p", "What is not recorded: fingers (the hands keep their rest grip), the faces of the actors, and effects the engine draws by itself (bullet holes, the muzzle flashes of HL2 weapons).",
		"Что не записывается: пальцы (кисти остаются в исходном хвате), лица актёров и эффекты, которые движок рисует сам (следы от пуль, вспышки выстрелов оружия HL2)." },
	{ "h", "NPC wars: deaths are recorded as falling ragdolls", "Войны NPC: смерти записываются падающими рэгдоллами" },
	{ "img", "speditor/help/rec_death.jpg", "A citizen shot during a take: frame 240 alive, 248 he folds, 256 the hit throws him back, 290 he lies where he fell — all of it keys of the animation.",
		"Гражданин, застреленный во время дубля: кадр 240 жив, 248 оседает, 256 удар отбрасывает его, 290 он лежит там, где упал, — всё это ключи анимации." },
	{ "steps",
		en = { "Spawn the two sides: for example Combine soldiers and rebels (spawn menu → NPCs), far enough apart, and give them weapons (the weapon choice of the NPCs tab of the spawn menu).",
			"Stand where you can see the fight. In Record gameplay keep Record the NPCs around and Killed NPCs fall as ragdolls on; set the radius so that everybody is inside it (the radius is around you).",
			"Start recording and let them fight (you can join in). Every NPC that dies keeps going as a ragdoll: the fall, the roll down the stairs, where the body ends up.",
			"Stop with Backspace. Each NPC is a ragdoll of the scene with its weapon; after its death the same ragdoll plays the fall. Re-shoot the fight from scene cameras, add camera cuts, render.",
			"Too many NPCs make the game slow, and the take with them: start with 4–8 per side." },
		ru = { "Заспавньте две стороны: например, солдат Альянса и повстанцев (меню спавна → NPC) на расстоянии друг от друга и дайте им оружие (выбор оружия на вкладке NPC меню спавна).",
			"Встаньте так, чтобы видеть бой. В «Записи игры» оставьте включёнными «Записывать NPC вокруг» и «Убитые NPC падают рэгдоллами»; радиус выберите такой, чтобы все были внутри (радиус — вокруг вас).",
			"Начните запись и дайте им сражаться (можно и самому). Каждый погибший NPC продолжает двигаться как рэгдолл: падение, кувырок по лестнице, место, где осталось тело.",
			"Остановите Backspace. Каждый NPC — рэгдолл сцены со своим оружием; после смерти тот же рэгдолл проигрывает падение. Переснимите бой камерами сцены, добавьте смены камер, отрендерите.",
			"Слишком много NPC замедляет игру, а с ней и дубль: начните с 4–8 на сторону." } },
	{ "p", "How it works: normally Garry's Mod makes the body of a killed NPC only on your screen (a client ragdoll), and the editor cannot see it — such an NPC used to just disappear after its death. For the take the editor switches Keep corpses (ai_serverragdolls) on, so the bodies are real ragdolls of the server, records them and afterwards puts the setting back and removes the extra bodies from the map — the scene has its own copies. Turn Killed NPCs fall as ragdolls off to get the old behaviour.",
		"Как это работает: обычно Garry's Mod создаёт тело убитого NPC только на вашем экране (клиентский рэгдолл), и редактор его не видит — раньше такой NPC просто исчезал после смерти. На время дубля редактор включает Keep corpses (ai_serverragdolls), тела становятся настоящими рэгдоллами сервера, записываются, а потом настройка возвращается, а лишние тела убираются с карты — у сцены есть свои копии. Выключите «Убитые NPC падают рэгдоллами», чтобы было как раньше." },
	{ "tip", "An NPC dissolved by a combine ball leaves no body at all; it is hidden after its last frame.",
		"NPC, растворённый энергошаром Альянса, не оставляет тела вовсе — он скрывается после своего последнего кадра." },
	{ "h", "Your view as a camera, doors", "Ваш вид как камера, двери" },
	{ "img", "speditor/help/rec_view.jpg", "Left: the camera DikiyChuvak view (rec) — what the player saw, the door opening in front of him; right: a scene camera shows the recorded player at the same frame. The door was spawned with a tool and opens in the animation as it did in the game.",
		"Слева: камера DikiyChuvak view (rec) — то, что видел игрок, дверь открывается перед ним; справа: камера сцены показывает записанного игрока на том же кадре. Дверь заспавнена инструментом и открывается в анимации так же, как в игре." },
	{ "p", "Record my view as a camera is on by default. Your look, turns and zoom become keys of the camera <your name> view (rec); with no camera cuts yet the video goes through it at once, so you can render right after the take. Your body, what you hold and PAC3 outfits are not drawn in that camera, as in the game; from other cameras they are seen as usual. Doors, lifts and buttons you used — of the map or spawned by tools and addons — move in the animation at the same moments.",
		"«Записать мой вид как камеру» включено по умолчанию. Взгляд, повороты и зум становятся ключами камеры <ваш ник> view (rec); если смен камер ещё нет, видео сразу идёт через неё — можно рендерить сразу после дубля. Ваше тело, то, что в руках, и наряды PAC3 в этой камере не рисуются, как в игре; с других камер всё видно как обычно. Двери, лифты и кнопки, которыми вы пользовались, — карты или заспавненные инструментами и аддонами, — двигаются в анимации в те же моменты." },
	{ "h", "Physics of ragdolls and props", "Физика регдоллов и пропов" },
	{ "steps",
		en = { "Record physics only: select ragdolls or props (nothing selected — all of them), put the playhead where the fall starts and press Record physics only (stay in the editor). They are let go and fall, roll and collide; Stop (or Backspace) writes their keys from that frame on.",
			"In a game take: Physics of the scene → Selected or All ragdolls and props. They are unfrozen for the take — throw them with the physics gun, shoot them, push them with a car — and get their own keys, next to the recorded player and NPCs.",
			"The keys go onto the objects themselves (their old keys inside the take are replaced). Locked and attached objects are not moved." },
		ru = { "Только физика: выделите регдоллы или пропы (ничего не выделено — все), поставьте головку туда, где начинается падение, и нажмите «Записать только физику (не выходя из редактора)». Они отпускаются и падают, катятся, сталкиваются; «Стоп» (или Backspace) записывает их ключи начиная с этого кадра.",
			"В записи игры: «Физика сцены» → выделенные или все регдоллы и пропы. На время дубля они размораживаются — бросайте их гравипушкой, стреляйте, толкайте машиной — и получают свои ключи рядом с записанными игроком и NPC.",
			"Ключи пишутся на сами объекты (их прежние ключи внутри дубля заменяются). Закреплённые и привязанные объекты не двигаются." } },
	{ "result", "A scene that plays like your gameplay, ready to be re-shot from scene cameras and rendered.",
		"Сцена, которая играет как ваша игра, — её можно переснять камерами сцены и отрендерить." },
	{ "see", "sa_cuts", "re-shoot the take with scene cameras", "переснять дубль камерами сцены" },
	{ "see", "sa_render", "render it to a video", "отрендерить в видео" },
	{ "try", "Open Record gameplay", "Открыть «Запись игры»", fn = function() SA.OpenRecord() end },
} })

UI.AddGuide({ id = "sa_face", order = 14, icon = "icon16/emoticon_smile.png", title = { en = "Faces and lip sync", ru = "Лица и липсинк" }, blocks = {
	{ "p", "The face can have its own keys (Shift + K, the Face row under the character): a blink or a line of speech keeps its own rhythm over a slow body motion.",
		"У лица могут быть свои ключи (Shift + K, строка «Лицо» под персонажем): моргание или реплика идут в своём ритме поверх медленного движения тела." },
	{ "img", "speditor/help/sounds.jpg", "Sounds and voices: pick a file, it goes onto the timeline at the playhead.", "Звуки и голоса: выберите файл — он ляжет на таймлайн у головки." },
	{ "steps",
		en = { "Add a voice line: the speaker button of the timeline (Add a sound or a voice line…).",
			"Right click the sound bar → Lip sync → for the character.",
			"The mouth follows the phonemes written in the file (voices of Valve games have them) or the loudness of the sound. The keys go to the Face row; the rest of the face is kept.",
			"Too strong or too weak: Lip sync → How wide the mouth opens, then run it again." },
		ru = { "Добавьте реплику: кнопка с динамиком на таймлайне (Добавить звук или реплику…).",
			"ПКМ по полосе звука → Липсинк → для персонажа.",
			"Рот следует фонемам, записанным в файле (они есть у голосов игр Valve), или громкости звука. Ключи ложатся на строку «Лицо»; остальное лицо не трогается.",
			"Слишком сильно или слабо: Липсинк → Насколько открывается рот, затем повторите." } },
	{ "see", "sa_keys", "keys and the timeline", "ключи и таймлайн" },
	{ "result", "A talking character in one click per line.", "Говорящий персонаж за один щелчок на реплику." },
} })

UI.AddGuide({ id = "sa_import", order = 15, icon = "icon16/film_add.png", title = { en = "Ready motions and model animations", ru = "Готовые движения и анимации моделей" }, blocks = {
	{ "p", "A character does not have to be animated by hand: walks, gestures, dances and any animation of a model (or of an addon's animation pack) turn into keys.",
		"Персонажа не обязательно анимировать вручную: ходьба, жесты, танцы и любая анимация модели (или пака анимаций из аддона) превращаются в ключи." },
	{ "steps",
		en = { "Ready motion (the walking figure button): pick a motion for the selected character, or a camera move (dolly, orbit, pan…) for a camera. It is placed at the playhead.",
			"Import model animation… (the film button): every animation of the model and of the player models, with a search. Key every N frames; Repeats; Speed; Move the character along — the character really walks.",
			"The baked keys can be edited like any others: change a pose at a key, delete keys, bend the curves." },
		ru = { "Готовое движение (кнопка с идущей фигуркой): выберите движение для выделенного персонажа или пролёт (наезд, облёт, панорама…) для камеры. Оно ставится от головки.",
			"Импорт анимации модели… (кнопка с плёнкой): все анимации модели и моделей игрока, с поиском. Ключ каждые N кадров; Повторов; Скорость; Двигать персонажа — персонаж действительно идёт.",
			"Запечённые ключи правятся как любые другие: измените позу на ключе, удалите ключи, согните кривые." } },
	{ "img", "speditor/help/import.jpg", "Import model animation.", "Импорт анимации модели." },
	{ "see", "sa_curves", "make imported motion smoother or sharper", "сделать импортированное движение плавнее или резче" },
	{ "see", "sa_motion", "adjust an imported stretch at once", "поправить импортированный отрезок разом" },
	{ "result", "A living character in seconds, ready to be fine-tuned.", "Живой персонаж за секунды, которого остаётся только подправить." },
} })

UI.AddGuide({ id = "sa_proc", order = 16, icon = "icon16/heart.png", title = { en = "Procedural motion: breathing, blinking", ru = "Процедурное движение: дыхание, моргание" }, blocks = {
	{ "p", "Small life on top of the keys, worked out from time: the chest breathes, the eyes blink, the head drifts, a lamp sways. It shows in playback and in the render; while you edit, the scene stays as its keys make it.",
		"Мелкая жизнь поверх ключей, вычисляемая по времени: грудь дышит, глаза моргают, голова чуть гуляет, лампа качается. Видно при воспроизведении и в рендере; пока вы правите, сцена такая, как её задают ключи." },
	{ "img", "speditor/help/proc.jpg", "Procedural motion of a character.", "Процедурное движение персонажа." },
	{ "steps",
		en = { "Right click the object → Animation → Procedural motion… (or the heart button of the timeline).",
			"Move the sliders; Play to see it.", "Switch off removes it." },
		ru = { "ПКМ по объекту → Анимация → Процедурное движение… (или кнопка с сердцем на таймлайне).",
			"Двигайте ползунки; «Запустить, чтобы увидеть» — посмотреть.", "«Выключить» убирает его." } },
	{ "see", "sa_face", "faces and lip sync", "лица и липсинк" },
	{ "result", "Characters that never freeze between keys.", "Персонажи, которые не застывают между ключами." },
} })

UI.AddGuide({ id = "sa_render", order = 17, icon = "icon16/film_save.png", title = { en = "Render the animation to video", ru = "Рендер анимации в видео" }, blocks = {
	{ "p", "A scene with animation renders as one AVI video with its sound. The game names it <name>.avi.dat (it lets Lua write only a few kinds of files): remove .dat and any player opens it.",
		"Сцена с анимацией рендерится в одно видео AVI со звуком. Игра называет его <имя>.avi.dat (Lua можно писать лишь несколько видов файлов): уберите .dat — и его откроет любой плеер." },
	{ "steps",
		en = { "Render (top right) → the Animation tab (an animated scene opens on it). The Picture tab renders one still of the current frame instead.",
			"Frames: the whole animation or a part (from – to). The player under the preview (to the start, a frame back, play / pause, a frame forward, to the end, the scrub bar) shows any moment of the video before you render it.",
			"Cameras of the video: The shots below — a list of shots right in the window: Add a shot at the current frame takes the camera you look through or have selected, each shot can get another camera or start frame, the arrow jumps to it. Or shoot the whole video through one camera.",
			"Video size trades quality for megabytes; Video frame rate can be higher than the animation's — the frames in between are worked out.",
			"Motion blur: every frame becomes the mean of several moments around it, as a film camera sees motion (the Shutter: 180° is the usual film look). The render takes that many times longer.",
			"Sounds: uncompressed WAV clips (effects, voices, footsteps) are mixed into the video with their place in the scene. MP3 and OGG play in the editor but cannot be mixed in by the game — add such music when you edit the video, or convert it to WAV first.",
			"After the render the console prints the ffmpeg command that turns the AVI into a small MP4.",
			"On Windows (and the Windows version of the game under Proton) Video file → WebM: the game's own video writer makes a ready garrysmod/videos/<name>.webm (no renaming, smaller). It is at most the size of the screen, and its width is rounded down to a multiple of 16 (the writer needs it). The game writes no sound into it: the sound goes next to it as data/speditor/renders/<name>.wav — put both into a video editor. On Linux the writer makes no file, so there it is AVI only.",
			"The window follows the loaded scene: after you load another scene the frames, the cameras of the video and the file name (if you left its field empty) are that scene's — there is no need to close the window or rejoin the map." },
		ru = { "«Рендер» (справа вверху) → вкладка «Анимация» (сцена с анимацией открывается на ней). Вкладка «Картинка» вместо этого рендерит один кадр — текущий.",
			"«Кадры»: вся анимация или её часть (с – по). Плеер под превью (в начало, кадр назад, пуск / пауза, кадр вперёд, в конец, полоса перемотки) показывает любой момент видео до рендера.",
			"«Камеры видео»: «Планы ниже» — список планов прямо в окне: «Добавить план на текущем кадре» берёт камеру, через которую вы смотрите, или выделенную; у каждого плана можно сменить камеру и первый кадр, стрелка переходит к нему. Или снимайте всё видео одной камерой.",
			"«Размер видео» меняет качество на мегабайты; «Частота кадров видео» может быть выше, чем у анимации, — промежуточные кадры вычисляются.",
			"«Размытие движения»: каждый кадр становится средним из нескольких моментов вокруг него — так движение видит киноплёнка («Затвор»: 180° — обычный кинематографичный вид). Рендер идёт во столько же раз дольше.",
			"Звуки: несжатые WAV (эффекты, голоса, шаги) подмешиваются в видео с учётом места в сцене. MP3 и OGG играют в редакторе, но игра не может их подмешать — такую музыку добавьте при монтаже или заранее переведите в WAV.",
			"После рендера в консоль печатается команда ffmpeg, которая сделает из AVI маленький MP4.",
			"На Windows (и в Windows-версии игры через Proton) «Видеофайл» → WebM: встроенная запись видео игры делает готовый garrysmod/videos/<имя>.webm (без переименования, меньше). Он не больше размера экрана, а ширина округляется вниз до числа, кратного 16 (так нужно записи). Звук игра в него не пишет: он ложится рядом в data/speditor/renders/<имя>.wav — соедините их в видеоредакторе. На Linux запись не создаёт файла, там только AVI.",
			"Окно следует за загруженной сценой: после загрузки другой сцены кадры, камеры видео и имя файла (если его поле пустое) — уже её; закрывать окно или перезаходить на карту не нужно." } },
	{ "img", "speditor/help/render_anim.jpg", "The Animation tab of the Render window: frames, the video file, video settings, motion blur and the four shots of demo_a07.",
		"Вкладка «Анимация» окна «Рендер»: кадры, видеофайл, настройки видео, размытие движения и четыре плана demo_a07." },
	{ "h", "When the render is done", "Когда рендер готов" },
	{ "img", "speditor/help/render_done.jpg", "The Render finished window: the path of the file with Copy path, what to do with .avi.dat, and Where are my files.",
		"Окно «Рендер готов»: путь к файлу с кнопкой «Копировать путь», что делать с .avi.dat и «Где мои файлы»." },
	{ "steps",
		en = { "Copy path puts the path into the clipboard. In Steam: Library → Garry's Mod → right click → Manage → Browse local files, then open garrysmod/data/speditor/renders.",
			"Rename <name>.avi.dat to <name>.avi (in Windows turn on View → File name extensions to see the .dat). VLC plays the file even with .dat.",
			"Don't want the window after every render? Untick Show after every render — the notification and File → Where are my files stay." },
		ru = { "«Копировать путь» кладёт путь в буфер обмена. В Steam: Библиотека → Garry's Mod → ПКМ → Управление → Просмотреть локальные файлы, затем откройте garrysmod/data/speditor/renders.",
			"Переименуйте <имя>.avi.dat в <имя>.avi (в Windows включите Вид → Расширения имён файлов, чтобы видеть .dat). VLC играет файл и с .dat.",
			"Не нужно окно после каждого рендера? Снимите «Показывать после каждого рендера» — уведомление и Файл → «Где мои файлы» останутся." } },
	{ "tip", "A scene with effects: keep Slow the game down for effects on (the Animation tab). The game then runs slowed during the render, so particles are exact in every frame instead of twitching, and Emitter / Lua effects keep the speed of the video. The game speed comes back by itself when the render ends.",
		"Сцена с эффектами: оставьте включённым «Замедлять игру для эффектов» (вкладка «Анимация»). Тогда на время рендера игра замедляется, и частицы точны в каждом кадре, а не дёргаются, а эффекты Emitter / Lua идут со скоростью видео. Скорость игры возвращается сама, когда рендер заканчивается." },
	{ "result", "garrysmod/data/speditor/renders/<name>.avi.dat (or garrysmod/videos/<name>.webm) — the finished film.", "garrysmod/data/speditor/renders/<имя>.avi.dat (или garrysmod/videos/<имя>.webm) — готовый фильм." },
	{ "try", "Open the Render window", "Открыть окно «Рендер»", fn = function() UI.OpenRenderDialog() end },
} })

UI.AddGuide({ id = "sa_smh", order = 18, icon = "icon16/arrow_switch.png", title = { en = "Stop Motion Helper saves", ru = "Сохранения Stop Motion Helper" }, blocks = {
	{ "p", "Animations made in Stop Motion Helper can be brought into the timeline, and the timeline can be written as an SMH save.",
		"Анимации из Stop Motion Helper можно перенести на таймлайн, а таймлайн — записать как сохранение SMH." },
	{ "img", "speditor/help/smh.jpg", "File → Stop Motion Helper.", "Файл → Stop Motion Helper." },
	{ "steps",
		en = { "File → Stop Motion Helper…: the saves of the game and of addons are listed.",
			"Select the object of the scene, pick a save and the object in it; Take onto the object.",
			"Write the SMH save writes the selected objects as a save SMH can load." },
		ru = { "Файл → Stop Motion Helper…: перечислены сохранения игры и аддонов.",
			"Выделите объект сцены, выберите сохранение и объект в нём; «Взять на объект».",
			"«Записать сохранение SMH» записывает выделенные объекты как сохранение, которое загрузит SMH." } },
	{ "see", "adopt", "your dupes and saves", "свои дупы и сейвы" },
	{ "result", "Old SMH animations continue in SAeditor, and back.", "Старые анимации SMH продолжаются в SAeditor — и обратно." },
} })
