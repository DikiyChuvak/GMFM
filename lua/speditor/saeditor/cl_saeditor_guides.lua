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
	{ "h", "The timeline, part by part", "Таймлайн по частям" },
	{ "keys", w = 170, {
		{ "Ruler (frame numbers)", "click — go to that frame; Shift + drag — select time", "щелчок — перейти на кадр; Shift + перетаскивание — выделить время", "Линейка (номера кадров)" },
		{ "Blue line", "the playhead: the frame you see and edit", "головка: кадр, который вы видите и правите", "Синяя линия" },
		{ "Diamond", "a key; its colour and shape tell the motion to the next key", "ключ; цвет и форма говорят, как он движется к следующему", "Ромб" },
		{ "Row on the left", "one object (and its bones or face under it)", "один объект (и его кости или лицо под ним)", "Строка слева" },
		{ "Film (shots)", "which camera the video is shot through, shot by shot", "через какую камеру снимается видео, план за планом", "Film (shots)" },
		{ "frame / length, s / fps", "where you are, how long the animation is, frames a second", "где вы, длина анимации, кадров в секунду", "frame / length, s / fps" },
		{ "Shaded part", "before 0 and after the end — keys can go there too", "до 0 и после конца — туда тоже можно ставить ключи", "Затенённая часть" },
		{ "0 button", "back to frame 0 after scrolling far away", "вернуться к кадру 0, если прокрутили далеко", "Кнопка 0" },
	} },
	{ "keys", w = 170, {
		{ "Space", "play / stop", "пуск / стоп", "Пробел" },
		{ "K", "key the selection at the playhead", "ключ выделенному на головке", "K" },
		{ ", / .", "one frame back / forward", "кадр назад / вперёд", ", / ." },
		{ "Middle drag", "pan the timeline", "двигать таймлайн", "Средняя кнопка" },
		{ "Wheel", "zoom the time", "масштаб времени", "Колесо" },
	} },
	{ "p", "Changed a pose and it jumped back when the playhead moved? The frame had no key: without Auto key an edit between keys is not kept. Press K (or turn Auto key on) before moving the playhead.",
		"Изменили позу, а она откатилась, когда головка сдвинулась? На кадре не было ключа: без автоключа правка между ключами не сохраняется. Нажмите K (или включите автоключ) до того, как двигать головку." },
	{ "result", "Motion from a few poses; the timeline shows where every object has its keys.",
		"Движение из нескольких поз; таймлайн показывает, где у каждого объекта ключи." },
	{ "see", "sa_marks", "bookmarks, play modes (once / loop / bounce), the shot list", "закладки, режимы воспроизведения (раз / круг / туда-обратно), список планов" },
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
	{ "img", "speditor/help/tsel_falloff.jpg", "The time selection menu: Falloff (in frames, to the nearest bookmarks, Autofalloff to bookmarks) and, on the right, the four Falloff shapes.",
		"Меню выделения времени: «Затухание» (в кадрах, до ближайших закладок, автозатухание до закладок) и справа четыре формы затухания." },
	{ "demo", h = 120, draw = motionDemo, "The keys in the middle of the selection take the edit in full, the ones in the falloff less and less, the ones outside do not move — the motion stays smooth at both ends.",
		"Ключи в середине выделения получают правку полностью, ключи в затухании — всё меньше, ключи снаружи не двигаются — движение остаётся плавным с обеих сторон." },
	{ "steps",
		en = { "Shift + drag on the frame numbers of the timeline: a time selection. Its middle is drawn blue; the curve above the numbers shows how much an edit counts at every frame.",
			"Drag its edges on the frame numbers. Edges that stand together part when dragged: outwards — a falloff (a soft edge), inwards — a narrower middle.",
			"Or use the clock button (also a right click on the frame numbers): a selection from the selected keys, around the playhead, over the whole animation; the falloff in frames and its shape — Smooth, Linear, Ease in (slow at the outer edge) or Ease out (slow at the inner edge).",
			"With bookmarks on the ruler: Falloff → Falloff to the nearest bookmarks moves the outer edges out to the bookmarks around the selection; Autofalloff to bookmarks does it for every new selection (as in SFM). Edges you drag by hand stay where you put them.",
			"Put the playhead inside the selection, change the pose, press K (Auto key works too): the change goes over the whole selection. Keys are added at its edges, so nothing outside it moves.",
			"Shift + click on the frame numbers (or Remove the time selection) — back to ordinary keys." },
		ru = { "Shift + перетаскивание по номерам кадров таймлайна — выделение времени. Его середина подсвечена синим; кривая над номерами показывает, насколько правка действует на каждом кадре.",
			"Края двигаются там же, на номерах кадров. Края, стоящие вместе, расходятся при перетаскивании: наружу — затухание (мягкий край), внутрь — середина уже.",
			"Или кнопка с часами (и ПКМ по номерам кадров): выделение по выбранным ключам, вокруг курсора, на всю анимацию; затухание в кадрах и его форма — плавная, линейная, Ease in (медленно у внешнего края) или Ease out (медленно у внутреннего).",
			"Если на линейке есть закладки: «Затухание» → «Затухание до ближайших закладок» отодвигает внешние края к закладкам вокруг выделения; «Автозатухание до закладок» делает это для каждого нового выделения (как в SFM). Края, которые вы тянете руками, остаются там, где вы их оставили.",
			"Поставьте курсор времени внутрь выделения, измените позу, нажмите K (автоключ тоже работает): правка ляжет на всё выделение. По краям добавляются ключи, поэтому снаружи ничего не сдвигается.",
			"Shift + клик по номерам кадров (или «Убрать выделение времени») — снова обычные ключи." } },
	{ "result", "One edit changes seconds of animation, softly blended into what is around it.",
		"Одна правка меняет секунды анимации и мягко вплетается в то, что вокруг." },
	{ "p", "See it in the example scene demo_a07 (Help → How to use → Example scenes): the hero's head turn to the ball is one such edit.",
		"Посмотрите в сцене-примере demo_a07 (Справка → Как пользоваться → Сцены-примеры): поворот головы героя к мячу — одна такая правка." },
	{ "see", "sa_presets", "procedural presets on the selection: smooth, jitter, stagger, ramp and 15 more", "процедурные пресеты на выделение: сгладить, дрожь, волна, рампа и ещё 15" },
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
	{ "p", "The Film (shots) row at the top of the timeline (it was called Cameras before a0.9) says which scene camera the animation is watched through, from which frame on — like the shots of SFM's film strip. The player and the video follow it.",
		"Строка «Лента (планы)» вверху таймлайна (до a0.9 — «Камеры») говорит, через какую камеру сцены смотреть анимацию, с какого кадра, — как планы на ленте кадров SFM. Плеер и видео следуют ей." },
	{ "demo", h = 90, draw = cutsDemo, "Camera 1, then Camera 2 from the middle, then Camera 1 again: the player switches exactly there.",
		"Сначала Camera 1, с середины Camera 2, потом снова Camera 1: плеер переключается ровно там." },
	{ "img", "speditor/help/cuts.jpg", "The shots row: a coloured band per shot, named after its camera, with its length in seconds.", "Строка планов: цветная полоса на каждый план, подписанная именем камеры, с длиной в секундах." },
	{ "steps",
		en = { "Add two cameras to the scene and place them.",
			"Right click the Film (shots) row at a frame → Switch to Camera 1 here. Do the same later for Camera 2.",
			"Drag a cut mark to move it; right click it to change its camera or delete it. Ctrl + Z undoes.",
			"The player: the TV button of the timeline (or File → Watch in the game → Player). A click on the camera name at the top of the player picks another camera.",
			"The same shots are listed in the Render window → Animation → Cameras of the video, where they can be added and changed without the timeline." },
		ru = { "Добавьте в сцену две камеры и расставьте их.",
			"ПКМ по строке «Лента (планы)» на нужном кадре → Переключиться на Camera 1 здесь. Позже так же для Camera 2.",
			"Метку смены можно перетащить; ПКМ по ней — сменить камеру или удалить. Ctrl + Z отменяет.",
			"Плеер: кнопка с телевизором на таймлайне (или Файл → Смотреть в игре → Плеер). Щелчок по имени камеры вверху плеера выбирает другую камеру.",
			"Те же планы перечислены в окне «Рендер» → «Анимация» → «Камеры видео» — там их можно добавлять и менять без таймлайна." } },
	{ "h", "Editing the film", "Монтаж ленты" },
	{ "img", "speditor/help/film_menu.jpg", "The menu of the shot Follow (frames 96–216): split it at the playhead, delete it with its time, cut out its start or end, change its speed (the lengths it would get are shown), insert time, make a new track, switch the camera from here.",
		"Меню плана Follow (кадры 96–216): разрезать по головке, удалить вместе с его временем, вырезать начало или конец, изменить скорость (показано, какой длины он станет), вставить время, создать ленту, переключить камеру отсюда." },
	{ "steps",
		en = { "The menu of a shot (right click it on the Film row): split the shot at the playhead, delete the shot with its time, trim its start or end at the playhead, speed it up or slow it down (×0.25 … ×4), insert time.",
			"Alt + drag a cut: the time at the cut grows or shrinks and everything after it moves — like trimming a clip in SFM.",
			"The timeline does not end at frame 0 and at the last frame: the middle button drags the view, the time outside is shaded. A key put before frame 0 adds that much time in front; a key past the end makes the animation longer. The 0 button brings the view back to the start." },
		ru = { "Меню плана (ПКМ по нему в строке «Лента»): разрезать план на головке, удалить план вместе с его временем, подрезать начало или конец по головке, ускорить или замедлить (×0.25 … ×4), вставить время.",
			"Alt + перетаскивание смены: время у смены растягивается или сжимается, и всё после неё сдвигается — как подрезка клипа в SFM.",
			"Таймлайн не кончается на кадре 0 и на последнем кадре: средняя кнопка двигает вид, время снаружи затенено. Ключ до кадра 0 добавляет столько времени в начало; ключ за концом удлиняет анимацию. Кнопка 0 возвращает вид в начало." } },
	{ "h", "Tracks: objects in groups", "Ленты: объекты группами" },
	{ "img", "speditor/help/anim_tracks.jpg", "Two tracks under the film strip: Combine (folded — one row with the keys of its four objects) and Gordon (open).",
		"Две ленты под лентой кадров: Combine (свёрнута — одна строка с ключами четырёх её объектов) и Gordon (раскрыта)." },
	{ "steps",
		en = { "Like the track groups of SFM's clip editor: right click an object's row → Track → New track with these objects (the selected ones go too), or put them into a track that is there.",
			"The header of a track shows the keys of all its objects; the + / − on the left (or a click on it) folds and unfolds it. A double click on the name renames it.",
			"The menu of the header: select the objects of the track, put the selected ones in, rename, move up or down, delete the track (the objects stay). Tracks are saved with the scene." },
		ru = { "Как группы треков в клип-редакторе SFM: ПКМ по строке объекта → Лента → «Новая лента с этими объектами» (выделенные тоже уйдут в неё) или положите их в уже существующую.",
			"Заголовок ленты показывает ключи всех её объектов; + / − слева (или щелчок по нему) сворачивает и разворачивает её. Двойной щелчок по имени — переименовать.",
			"Меню заголовка: выделить объекты ленты, положить в неё выделенные, переименовать, выше / ниже, удалить ленту (объекты останутся). Ленты сохраняются вместе со сценой." } },
	{ "h", "The player", "Плеер" },
	{ "img", "speditor/help/player.jpg", "The player in the look of Windows Media Player (b0.2): the scene and the camera written big at the top left, Cameras at the top right; at the bottom the thin seek bar with the shots marked, and the glossy capsule — repeat, render settings, stop, the previous / next shot around the blue play / pause orb, the volume. The cameras and leave are on the right.",
		"Плеер в стиле Windows Media Player (b0.2): сцена и камера крупно слева сверху, «Камеры» справа сверху; внизу тонкая полоса перемотки с отмеченными планами и глянцевая капсула — повтор, настройки рендера, стоп, предыдущий / следующий план вокруг синего шара пуска / паузы, громкость. Справа — камеры и выход." },
	{ "p", "Keys: Space — play / pause, ← → — 5 seconds, PgUp / PgDn — the previous / next shot, Home / End, ↑ ↓ — volume, M — mute, R — repeat, V — render settings, Backspace or the cross — leave. The bar hides while the mouse rests and comes back when it moves; a click on the picture pauses.",
		"Клавиши: Пробел — пуск / пауза, ← → — 5 секунд, PgUp / PgDn — предыдущий / следующий план, Home / End, ↑ ↓ — громкость, M — без звука, R — повтор, V — настройки рендера, Backspace или крестик — выйти. Панель прячется, пока мышь не двигается, и появляется снова; щелчок по картинке ставит паузу." },
	{ "p", "Render settings (the button beside repeat): the player shows the video as the Render window will make it — its frame proportions with black bars, camera effects, soft shadows, the engine frame — before you render anything. An animation has no depth of field (since a0.9): a few passes a frame gave ghost copies and a smeared picture. While it plays, soft shadows are lighter; on pause the frame is full.",
		"Настройки рендера (кнопка рядом с повтором): плеер показывает видео таким, каким его сделает окно «Рендер», — его пропорции кадра с чёрными полями, эффекты камеры, мягкие тени, кадр движка — ещё до рендера. У анимации нет глубины резкости (с a0.9): несколько проходов на кадр давали двоящиеся копии и размытую картинку. Во время воспроизведения мягкие тени облегчены, на паузе кадр полный." },
	{ "h", "Walking around the scene", "Ходить по сцене" },
	{ "p", "The eye button of the timeline (File → Watch in the game → Walk around the scene): the animation plays while you walk around it yourself, with your HUD and weapon, and look at it from any side. Backspace stops it.",
		"Кнопка с глазом на таймлайне (Файл → Смотреть в игре → Ходить по сцене): анимация идёт, а вы сами ходите вокруг неё, с HUD и оружием, и смотрите с любой стороны. Backspace — стоп." },
	{ "see", "sa_marks", "the shot list as text, bookmarks", "список планов текстом, закладки" },
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
			"Camera of the take → First person (camera in the eyes), the default: a camera <your name> view (rec) strictly in your character's eyes, keyed along the take, looking where you aimed — even if the game showed you from behind. Third person (no camera of the player): no such camera; you film the take with your own scene cameras. With no camera cuts yet the video goes through it at once; your own body is not drawn in it, as in the game (the weapon in your hands is seen only from other cameras).",
			"Edit it like any animation: delete keys, fix a pose (with Bone keys — just one arm), add cameras and cuts, record another take on top." },
		ru = { "Поставьте головку туда, где должен начаться дубль. Откройте «Запись игры» и выберите, что записывать: NPC вокруг (в радиусе), звуки, эффекты, как часто брать ключ.",
			"«Начать запись»: редактор закроется, пойдёт отсчёт, потом в углу замигает REC. Играйте. Уже сделанная анимация идёт вместе с записью — можно играть против неё.",
			"Backspace останавливает дубль. Откроется редактор: в сцене вы — рэгдолл вашей модели игрока (скин, бодигруппы, цвет игрока) с оружием в руке, каждый NPC со своим оружием, звуки на таймлайне и эффекты отдельными объектами. Объекты карты, которые двигались во время дубля, двигаются в анимации в те же моменты.",
			"«Камера дубля» → «1-е лицо (камера в глазах)», по умолчанию: камера <ваш ник> view (rec) строго в глазах вашего персонажа, с ключами по всему дублю, смотрит туда, куда вы целились, — даже если игра показывала вас со спины. «3-е лицо (без камеры игрока)»: такой камеры нет, дубль снимают ваши камеры сцены. Если смен камер ещё нет, видео сразу идёт через неё; ваше тело в ней не рисуется, как в игре (оружие в руках видно только с других камер).",
			"Правьте как любую анимацию: удалите лишние ключи, поправьте позу (с ключами костей — одну руку), добавьте камеры и смены камер, запишите поверх ещё один дубль." } },
	{ "h", "Getting ready for the take: weapons, countdown, time limit", "Подготовка к дублю: оружие, отсчёт, время" },
	{ "steps",
		en = { "The take part of the Record gameplay window: the countdown before the take (1–10 seconds), a time limit (the take stops by itself; 0 — none), full health and armour before it, god mode during it.",
			"Choose the weapons before the take: Start recording first opens the list of weapons from the spawn menu (Workshop ones too, by category, with a search). Click one or more — the number on a weapon is the order they are given, the first one is in your hands. Take away my other weapons and Ammunition for each are at the bottom.",
			"Done — start the countdown gives you the weapons and the countdown begins. The list is remembered for the next take (Weapons of the take: N chosen… changes it without recording).",
			"In the GM:FM gamemode this step is always there: the player has no weapons of their own and there is no spawn menu to take one from. In Sandbox tick Choose the weapons before the take." },
		ru = { "Часть «Дубль» окна «Запись игры»: обратный отсчёт перед дублем (1–10 секунд), ограничение времени (дубль остановится сам; 0 — без ограничения), полное здоровье и броня перед ним, бессмертие во время него.",
			"Оружие перед дублем: «Начать запись» сначала откроет список оружия из меню спавна (и из Мастерской, по категориям, с поиском). Нажмите на одно или несколько — номер на оружии показывает порядок выдачи, первое будет в руках. Внизу — «Забрать моё остальное оружие» и «Патронов к каждому».",
			"«Готово — начать отсчёт» выдаёт оружие, и начинается отсчёт. Список запоминается до следующего дубля («Оружие дубля: выбрано N…» меняет его без записи).",
			"В режиме GM:FM этот шаг есть всегда: своего оружия у игрока нет, а меню спавна, чтобы его взять, тоже нет. В Sandbox поставьте галочку «Выбирать оружие перед дублем»." } },
	{ "h", "NPCs of the take, each on its own mark", "NPC дубля, каждый на своей метке" },
	{ "see", "sa_rec_npcs", "Put NPCs where they should stand before the take — step by step, with pictures.",
		"Расставьте NPC по местам перед дублем — шаг за шагом, с картинками." },
	{ "img", "speditor/help/rec_result.jpg", "A recorded take: the player with a crowbar and a citizen with an SMG, keyed every 2 frames; the tracer and the explosion are effect objects, the shot is a sound from the player.",
		"Записанный дубль: игрок с монтировкой и гражданин с SMG, ключ каждые 2 кадра; трассер и взрыв — объекты-эффекты, выстрел — звук от игрока." },
	{ "p", "What is not recorded: fingers (the hands keep their rest grip), the faces of the actors and bullet holes. The muzzle flash, the shell and the tracer of a shot are recorded and come out of the muzzle of the weapon in the hand; the hit raises the dust or the blood of what it hit.",
		"Что не записывается: пальцы (кисти остаются в исходном хвате), лица актёров и следы от пуль. Вспышка, гильза и трассер выстрела записываются и вылетают из дула оружия в руке; попадание поднимает пыль или кровь того, во что попало." },
	{ "h", "Weapon packs and other addons", "Оружейные паки и другие аддоны" },
	{ "steps",
		en = { "ARC9, TFA, ArcCW, MW and other weapon bases make their muzzle flashes, impacts, smoke and sparks on your screen only. During a take with effects Garry's Mod Filmmaker writes them down there too and puts them into the scene as effect objects (particle systems keep their .pcf file, so they play in the scene).",
			"Effects on the first-person gun in front of the camera are left out — they are in front of your eyes, not in the world; the take fires the muzzle flash from the weapon in the hand instead.",
			"A weapon whose base draws the gun itself and leaves the entity without a model gets its world model from the weapon's own settings.",
			"Animation mods (other walks, runs, idles) usually change only what you see: the recorder takes your body from the server, so the take shows the game's own animations.",
			"Each take names its objects so that nothing has the same name twice: the second camera is <your name> view (rec) 2, the second rifle w_smg1 2 — easy to tell apart in the Render window." },
		ru = { "ARC9, TFA, ArcCW, MW и другие оружейные базы делают вспышки, попадания, дым и искры только на вашем экране. Во время дубля с эффектами Garry's Mod Filmmaker записывает их и там и кладёт в сцену объектами-эффектами (системы частиц хранят свой .pcf-файл и проигрываются в сцене).",
			"Эффекты на оружии от первого лица перед камерой не записываются — они перед глазами, а не в мире; вспышку дубль берёт из оружия в руке.",
			"Оружие, база которого рисует ствол сама и оставляет сущность без модели, получает модель из собственных настроек оружия.",
			"Моды анимаций (другая ходьба, бег, стойка) обычно меняют только то, что видите вы: запись берёт тело с сервера, поэтому в дубле — стандартные анимации игры.",
			"Каждый дубль называет объекты так, чтобы имена не повторялись: вторая камера — <ваш ник> view (rec) 2, вторая винтовка — w_smg1 2; в окне «Рендер» их легко различить." } },
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
	{ "p", "Camera of the take is First person by default. Your look, turns and zoom become keys of the camera <your name> view (rec); with no camera cuts yet the video goes through it at once, so you can render right after the take. Your body, what you hold and PAC3 outfits are not drawn in that camera, as in the game; from other cameras they are seen as usual. Doors, lifts and buttons you used — of the map or spawned by tools and addons — move in the animation at the same moments.",
		"«Камера дубля» по умолчанию — «1-е лицо». Взгляд, повороты и зум становятся ключами камеры <ваш ник> view (rec); если смен камер ещё нет, видео сразу идёт через неё — можно рендерить сразу после дубля. Ваше тело, то, что в руках, и наряды PAC3 в этой камере не рисуются, как в игре; с других камер всё видно как обычно. Двери, лифты и кнопки, которыми вы пользовались, — карты или заспавненные инструментами и аддонами, — двигаются в анимации в те же моменты." },
	{ "h", "Physics of ragdolls and props", "Физика регдоллов и пропов" },
	{ "steps",
		en = { "Record physics only: select ragdolls or props (nothing selected — all of them), put the playhead where the fall starts and press Record physics only (stay in the editor). They are let go and fall, roll and collide; Stop (or Backspace) writes their keys from that frame on.",
			"In a game take: Physics of the scene → Selected or All ragdolls and props. They are unfrozen for the take — throw them with the physics gun, shoot them, push them with a car — and get their own keys, next to the recorded player and NPCs. Objects that already have keys (the actors of earlier takes) are not let go: they play their animation during the take.",
			"The keys go onto the objects themselves (their old keys inside the take are replaced). Locked and attached objects are not moved." },
		ru = { "Только физика: выделите регдоллы или пропы (ничего не выделено — все), поставьте головку туда, где начинается падение, и нажмите «Записать только физику (не выходя из редактора)». Они отпускаются и падают, катятся, сталкиваются; «Стоп» (или Backspace) записывает их ключи начиная с этого кадра.",
			"В записи игры: «Физика сцены» → выделенные или все регдоллы и пропы. На время дубля они размораживаются — бросайте их гравипушкой, стреляйте, толкайте машиной — и получают свои ключи рядом с записанными игроком и NPC. Объекты, у которых уже есть ключи (актёры прошлых дублей), не отпускаются: во время дубля они играют свою анимацию.",
			"Ключи пишутся на сами объекты (их прежние ключи внутри дубля заменяются). Закреплённые и привязанные объекты не двигаются." } },
	{ "tip", "A breakable prop (a crate, a barrel, a melon) can fall apart: right click it → Utilities → Break into pieces at the playhead (b0.2.4). The prop vanishes at that frame, its pieces appear in its place and a physics take of them starts at once — Stop or Backspace writes their keys.",
		"Ломающийся проп (ящик, бочка, арбуз) может развалиться: ПКМ по нему → «Утилиты» → «Разбить на обломки на текущем кадре» (b0.2.4). На этом кадре проп исчезает, на его месте появляются обломки, и сразу начинается запись их физики — «Стоп» или Backspace записывает ключи." },
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

UI.AddGuide({ id = "sa_proc", order = 16, icon = "icon16/heart.png", title = { en = "Procedural motion: breathing, blinking, noise", ru = "Процедурное движение: дыхание, моргание, шум" }, blocks = {
	{ "p", "Small life on top of the keys, worked out from time: the chest breathes, the eyes blink, the head drifts, a lamp sways. It shows in playback and in the render; while you edit, the scene stays as its keys make it.",
		"Мелкая жизнь поверх ключей, вычисляемая по времени: грудь дышит, глаза моргают, голова чуть гуляет, лампа качается. Видно при воспроизведении и в рендере; пока вы правите, сцена такая, как её задают ключи." },
	{ "img", "speditor/help/proc.jpg", "Procedural motion of a character.", "Процедурное движение персонажа." },
	{ "img", "speditor/help/proc_noise.jpg", "The window with breathing and blinking on, and the noise of the right hand (R_Hand was selected before the window was opened): 12° of trembling at 0.8 Hz.",
		"Окно с включёнными дыханием и морганием и шумом правой кисти (R_Hand была выделена перед открытием окна): дрожь 12° с частотой 0.8 Гц." },
	{ "steps",
		en = { "Right click the object → Animation → Procedural motion… (or the heart button of the timeline).",
			"Move the sliders; Play to see it.", "Switch off removes it.",
			"Noise (as the Noise modifier in Blender): a random but repeatable shake on top of the keys — move (units), turn (degrees), speed (Hz) and pattern. It works on cameras too: a camera held in the hand, a car on a bumpy road. Select a bone first and the window gets a slider for the noise of that bone (a trembling hand)." },
		ru = { "ПКМ по объекту → Анимация → Процедурное движение… (или кнопка с сердцем на таймлайне).",
			"Двигайте ползунки; «Запустить, чтобы увидеть» — посмотреть.", "«Выключить» убирает его.",
			"Шум (как модификатор Noise в Blender): случайная, но повторяемая тряска поверх ключей — сдвиг (юниты), поворот (градусы), скорость (Гц) и рисунок. Работает и для камер: камера в руке, машина на неровной дороге. Сначала выделите кость — и в окне появится ползунок шума этой кости (дрожащая рука)." } },
	{ "see", "sa_rotator", "a wheel, a fan, a propeller that turns all the time", "колесо, вентилятор, пропеллер, которые вращаются всё время" },
	{ "see", "sa_face", "faces and lip sync", "лица и липсинк" },
	{ "result", "Characters that never freeze between keys.", "Персонажи, которые не застывают между ключами." },
} })

UI.AddGuide({ id = "sa_render", order = 17, icon = "icon16/film_save.png", title = { en = "Render the animation to video", ru = "Рендер анимации в видео" }, blocks = {
	{ "p", "A scene with animation renders as one AVI video with its sound. The game names it <name>.avi.dat (it lets Lua write only a few kinds of files): remove .dat and any player opens it.",
		"Сцена с анимацией рендерится в одно видео AVI со звуком. Игра называет его <имя>.avi.dat (Lua можно писать лишь несколько видов файлов): уберите .dat — и его откроет любой плеер." },
	{ "steps",
		en = { "Render (top right) → the Animation tab (an animated scene opens on it). The Picture tab renders one still of the current frame instead.",
			"Frames: the whole animation or a part (from – to). The player under the preview (to the start, a frame back, play / pause, a frame forward, to the end, the scrub bar) shows any moment of the video before you render it.",
			"Cameras of the video: The shots below — a list of shots right in the window: Add a shot at the current frame takes the camera you look through or have selected, each shot can get another camera or start frame, the arrow jumps to it. Or shoot the whole video through one camera. Only the cameras of the scene are rendered, never the work camera: a scene without a camera says Add a camera to the scene.",
			"Depth of field in a video: a camera that has its own (Camera effects → Depth of field) keeps it with all of its passes — key the focus to pull it from one actor to another; any other camera takes the Depth of field of the Render window when it is on (since b0.2.4). Depth of field on the Animation tab switches both off. The player in the game shows animations without it.",
			"Video file → PNG or JPEG pictures (b0.2.4): a picture for every frame in data/speditor/renders/<name>, the sound as <name>.wav beside them — for video editors that take an image sequence.",
			"Video size trades quality for megabytes; Video frame rate can be higher than the animation's — the frames in between are worked out.",
			"Motion blur: every frame becomes the mean of several moments around it, as a film camera sees motion (the Shutter: 180° is the usual film look). The render takes that many times longer.",
			"Sounds: uncompressed WAV clips (effects, voices, footsteps) are mixed into the video with their place in the scene. MP3 and OGG play in the editor but cannot be mixed in by the game — add such music when you edit the video, or convert it to WAV first.",
			"After the render the console prints the ffmpeg command that turns the AVI into a small MP4.",
			"On Windows (and the Windows version of the game under Proton) Video file → WebM: the game's own video writer makes a ready garrysmod/videos/<name>.webm (no renaming, smaller). It is at most the size of the screen, and its width is rounded down to a multiple of 16 (the writer needs it). The game writes no sound into it: the sound goes next to it as data/speditor/renders/<name>.wav — put both into a video editor. On Linux the writer makes no file, so there it is AVI only.",
			"The window follows the loaded scene: after you load another scene the frames, the cameras of the video and the file name (if you left its field empty) are that scene's — there is no need to close the window or rejoin the map." },
		ru = { "«Рендер» (справа вверху) → вкладка «Анимация» (сцена с анимацией открывается на ней). Вкладка «Картинка» вместо этого рендерит один кадр — текущий.",
			"«Кадры»: вся анимация или её часть (с – по). Плеер под превью (в начало, кадр назад, пуск / пауза, кадр вперёд, в конец, полоса перемотки) показывает любой момент видео до рендера.",
			"«Камеры видео»: «Планы ниже» — список планов прямо в окне: «Добавить план на текущем кадре» берёт камеру, через которую вы смотрите, или выделенную; у каждого плана можно сменить камеру и первый кадр, стрелка переходит к нему. Или снимайте всё видео одной камерой. Рендерятся только камеры сцены, рабочая камера — никогда: в сцене без камер окно скажет «Добавьте камеру в сцену».",
			"Глубина резкости в видео: камера со своей (Эффекты камеры → Глубина резкости) сохраняет её со всеми проходами — поставьте ключи фокуса, чтобы перевести его с одного актёра на другого; остальные камеры берут глубину резкости окна «Рендер», если она включена (с b0.2.4). «Глубина резкости» на вкладке «Анимация» выключает обе. Плеер в игре показывает анимацию без неё.",
			"«Видеофайл» → картинки PNG или JPEG (b0.2.4): по картинке на кадр в data/speditor/renders/<имя>, звук — <имя>.wav рядом с ними, для видеоредакторов, которые берут последовательность изображений.",
			"«Размер видео» меняет качество на мегабайты; «Частота кадров видео» может быть выше, чем у анимации, — промежуточные кадры вычисляются.",
			"«Размытие движения»: каждый кадр становится средним из нескольких моментов вокруг него — так движение видит киноплёнка («Затвор»: 180° — обычный кинематографичный вид). Рендер идёт во столько же раз дольше.",
			"Звуки: несжатые WAV (эффекты, голоса, шаги) подмешиваются в видео с учётом места в сцене. MP3 и OGG играют в редакторе, но игра не может их подмешать — такую музыку добавьте при монтаже или заранее переведите в WAV.",
			"После рендера в консоль печатается команда ffmpeg, которая сделает из AVI маленький MP4.",
			"На Windows (и в Windows-версии игры через Proton) «Видеофайл» → WebM: встроенная запись видео игры делает готовый garrysmod/videos/<имя>.webm (без переименования, меньше). Он не больше размера экрана, а ширина округляется вниз до числа, кратного 16 (так нужно записи). Звук игра в него не пишет: он ложится рядом в data/speditor/renders/<имя>.wav — соедините их в видеоредакторе. На Linux запись не создаёт файла, там только AVI.",
			"Окно следует за загруженной сценой: после загрузки другой сцены кадры, камеры видео и имя файла (если его поле пустое) — уже её; закрывать окно или перезаходить на карту не нужно." } },
	{ "img", "speditor/help/render_anim.jpg", "The Animation tab of the Render window: the frames, the video file and the video settings on the left, the preview on the right; the look of the frame (size, smoothing, SSAO, camera effects) is shared with the Picture tab.",
		"Вкладка «Анимация» окна «Рендер»: кадры, видеофайл и настройки видео слева, предпросмотр справа; вид кадра (размер, сглаживание, SSAO, эффекты камеры) общий с вкладкой «Картинка»." },
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

---------------------------------------------------------------------
-- A good animation, step by step (a0.9): the way animators work in SFM and Blender — poses
-- first, then the motion between them, then the details
---------------------------------------------------------------------
-- demo: the same five keys played two ways — stopping at every key and continuous
local GOOD_KEYS = { { 0, 0.9 }, { 0.25, 0.1 }, { 0.5, 0.7 }, { 0.75, 0.1 }, { 1, 0.5 } }
local function goodDemo(w, h, t)
	local len = 2.4
	local u = math.min((t % (len + 0.5)) / len, 1)
	local lanes = { { T("Ease: stops at every key", "Плавно, с остановкой: стоит в каждом ключе"), "ease" },
		{ T("Continuous: flows through the keys", "Непрерывно: перетекает через ключи"), "spline" } }
	local lh = h / 2
	local x0, x1 = 20, w - 20
	for li, lane in ipairs(lanes) do
		local top = (li - 1) * lh + 18
		local bot = li * lh - 10
		local function pt(k) return x0 + k[1] * (x1 - x0), bot - k[2] * (bot - top) end
		draw.SimpleText(lane[1], "SPeditor.Small", x0, top - 10, COL.TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		-- the place at the share v of the whole: between keys i and i + 1
		local function at(v)
			local n = #GOOD_KEYS - 1
			local i = math.min(math.floor(v * n) + 1, n)
			local s = v * n - (i - 1)
			local a, b = GOOD_KEYS[i], GOOD_KEYS[i + 1]
			local y
			if lane[2] == "spline" then
				local k0, k3 = GOOD_KEYS[i - 1] or a, GOOD_KEYS[i + 2] or b
				local w0, w1, w2, w3 = SA.SplineWeights(i - 2, i - 1, i, i + 1, s)
				y = k0[2] * w0 + a[2] * w1 + b[2] * w2 + k3[2] * w3
			else
				y = Lerp(SA.EaseValue("ease", s), a[2], b[2])
			end
			return x0 + v * (x1 - x0), bot - y * (bot - top)
		end
		-- the path, the keys, equal steps of time (dots) and the ball
		local px, py = at(0)
		for n = 1, 60 do
			local qx, qy = at(n / 60)
			surface.SetDrawColor(COL.TAB_ON)
			surface.DrawLine(px, py, qx, qy)
			px, py = qx, qy
		end
		for n = 0, 24 do
			local dx, dy = at(n / 24)
			surface.SetDrawColor(COL.DIM)
			surface.DrawRect(dx - 1, dy - 1, 2, 2)
		end
		for _, k in ipairs(GOOD_KEYS) do
			local kx, ky = pt(k)
			draw.RoundedBox(2, kx - 3, ky - 3, 6, 6, COL.TEXT)
		end
		local bx, by = at(u)
		draw.RoundedBox(6, bx - 6, by - 6, 12, 12, COL.ORANGE)
	end
end

UI.AddGuide({ id = "sa_good", order = 10.5, section = "anim", icon = "icon16/star.png", title = { en = "A good animation, step by step", ru = "Хорошая анимация шаг за шагом" }, blocks = {
	{ "p", "Animators in SFM and Blender work in passes: the key poses first (blocking), then the motion between them (splining), then timing, overlap and the little things that make it alive. Each pass is quick, and a mistake is cheap to fix while there are few keys. The same works in SAeditor.",
		"Аниматоры в SFM и Blender работают проходами: сначала ключевые позы (блокинг), потом движение между ними (сплайн), потом тайминг, захлёст и мелочи, которые оживляют. Каждый проход быстрый, а ошибка дешёвая, пока ключей мало. В SAeditor — так же." },
	{ "demo", h = 170, draw = goodDemo, "The same five keys. Above, every key has Ease: the ball stops in each pose and only then goes on — the robotic look. Below, Continuous: the motion flows through the poses. The grey dots are equal steps of time.",
		"Одни и те же пять ключей. Сверху у каждого ключа «Плавно, с остановкой»: мяч замирает в каждой позе и только потом едет дальше — роботизированный вид. Снизу «Непрерывно»: движение перетекает через позы. Серые точки — равные промежутки времени." },
	{ "h", "The example: demo_ball", "Пример: demo_ball" },
	{ "video", atlas = "speditor/help/video/demo_ball_%02d.jpg", count = 73, fps = 24, cols = 4, rows = 4, w = 480, h = 270,
		"demo_ball rendered to video (Render → Animation, 24 fps, motion blur 4): the ball of this guide — eleven keys, all of them Continuous. Click to pause, the bar to seek.",
		"demo_ball, отрендеренная в видео («Рендер» → «Анимация», 24 к/с, размытие движения 4): мяч из этой статьи — одиннадцать ключей, все «Непрерывно». Клик — пауза, полоса — перемотка." },
	{ "steps",
		en = { "Load it (the button below) and press Space. Select the Ball: its orange path shows the arcs; the diamonds on the timeline are its keys.",
			"The keys, frame → height above the ground: 0 → 130 (dropped), 10 → 0, 19 → 80, 27 → 0, 33 → 45, 39 → 0, 43 → 22, 47 → 0, 50 → 9, 53 → 0, 64 → 0 (it rolls to a stop). Forward it moves less with every bounce.",
			"Each bounce is shorter in time and lower than the one before: 10, 9, 8, 6, 6, 4, 4, 3, 3 frames. That ratio, not the heights, is what makes it read as a real ball.",
			"Try it yourself: move one apex key higher (select the Ball, playhead on the key, Move gizmo, K) and play again; or make the ball heavier by giving the bounces fewer frames.",
			"Side camera looks at it without moving (one Hold key). Render → Animation renders it as here." },
		ru = { "Загрузите её (кнопка ниже) и нажмите пробел. Выделите Ball: оранжевый путь показывает дуги, ромбы на таймлайне — его ключи.",
			"Ключи, кадр → высота над землёй: 0 → 130 (бросок), 10 → 0, 19 → 80, 27 → 0, 33 → 45, 39 → 0, 43 → 22, 47 → 0, 50 → 9, 53 → 0, 64 → 0 (докатывается). Вперёд он с каждым отскоком продвигается меньше.",
			"Каждый отскок короче по времени и ниже предыдущего: 10, 9, 8, 6, 6, 4, 4, 3, 3 кадра. Именно это соотношение, а не высоты, делает мяч похожим на настоящий.",
			"Попробуйте сами: поднимите одну верхнюю точку (выделите Ball, головка на ключе, гизмо переноса, K) и проиграйте снова; или сделайте мяч тяжелее, дав отскокам меньше кадров.",
			"Side camera смотрит на него не двигаясь (один ключ «Скачком»). «Рендер» → «Анимация» рендерит его, как здесь." } },
	{ "try", "Load demo_ball", "Загрузить demo_ball", fn = function()
		local C = SPeditor.Client
		if #C.Objects() == 0 then C.SceneLoad("demo_ball") return end
		Derma_Query(string.format(L("load_confirm"), "demo_ball"), "Garry's Mod Filmmaker", L("load"), function() C.SceneLoad("demo_ball") end, L("cancel"), function() end)
	end },
	{ "tip", "demo_ball is made on gm_construct_sunset. On another map the ball bounces in the same place of the world, maybe inside a wall: load gm_construct_sunset first.",
		"demo_ball сделана на gm_construct_sunset. На другой карте мяч прыгает в той же точке мира, возможно внутри стены: сначала загрузите gm_construct_sunset." },
	{ "h", "1. Plan it", "1. Продумайте" },
	{ "steps",
		en = { "Watch the real thing: film yourself or find a video of the move. Count how long it takes — a step is about half a second, a jump a second or two.",
			"Set the length of the animation (length, s on the timeline) and 24 fps. The timecode in the corner of the viewport shows minutes, seconds and frames.",
			"Draw the story in a few poses: where it starts, the extremes (the lowest crouch, the highest point, the hit), where it ends." },
		ru = { "Посмотрите, как это бывает в жизни: снимите себя или найдите видео движения. Засеките, сколько оно длится — шаг около полсекунды, прыжок секунду-две.",
			"Задайте длину анимации («длина, с» на таймлайне) и 24 к/с. Таймкод в углу вьюпорта показывает минуты, секунды и кадры.",
			"Расскажите движение несколькими позами: где оно начинается, крайние точки (самый низкий присед, самая высокая точка, удар), где заканчивается." } },
	{ "h", "2. Blocking: the key poses", "2. Блокинг: ключевые позы" },
	{ "steps",
		en = { "Edit → Animation → New keys move → Hold. Now the object jumps from pose to pose, so you judge the poses and the timing alone, not the motion between them.",
			"Put the extremes first: pose at the frame, press K. Then the poses in between that tell how it gets there (breakdowns): the arm passes low, the body leans first.",
			"Play it (Space). Too slow — drag keys closer on the timeline; too fast — apart. Fix the timing now: it is a matter of dragging diamonds." },
		ru = { "Правка → Анимация → Движение новых ключей → «Скачком». Теперь объект прыгает из позы в позу — вы оцениваете только позы и тайминг, а не движение между ними.",
			"Сначала крайние позы: поза на кадре, K. Потом промежуточные, которые объясняют, как он туда попадает (брейкдауны): рука проходит снизу, корпус наклоняется первым.",
			"Проиграйте (пробел). Медленно — сдвиньте ключи на таймлайне ближе, быстро — дальше. Тайминг правьте сейчас: это просто перетаскивание ромбов." } },
	{ "img", "speditor/help/anim_block.jpg", "The bouncing ball, blocked with Hold keys: the path (orange) is dashed — the ball stands at each key and jumps to the next. The ghost is the pose at the next key. The diamonds on the timeline are the poses.",
		"Прыгающий мяч, заблокированный ключами «Скачком»: путь (оранжевый) пунктирный — мяч стоит в каждом ключе и прыгает к следующему. Призрак — поза следующего ключа. Ромбы на таймлайне — позы." },
	{ "h", "3. Splining: the motion between", "3. Сплайн: движение между позами" },
	{ "steps",
		en = { "Edit → Animation → Make the whole animation smooth (continuous keys), and set New keys move back to Continuous.",
			"Select the object: the orange path in the viewport now shows the way it really goes. Good motion moves on arcs — a hand, a head, a ball draw curves, not straight lines and corners.",
			"A corner or a loop on the path is a key in the wrong place: move that pose, or add a key in between. Ghosts (the timeline button) show the poses at the keys around the playhead." },
		ru = { "Правка → Анимация → «Сделать всю анимацию плавной (непрерывные ключи)» и верните «Движение новых ключей» на «Непрерывно».",
			"Выделите объект: оранжевый путь во вьюпорте теперь показывает, как он движется на самом деле. Хорошее движение идёт по дугам — рука, голова, мяч рисуют кривые, а не прямые и углы.",
			"Угол или петля на пути — ключ не на месте: сдвиньте эту позу или добавьте ключ посередине. Призраки (кнопка на таймлайне) показывают позы в ключах вокруг головки." } },
	{ "img", "speditor/help/anim_spline.jpg", "The same ball with continuous keys: the path is a chain of arcs, each bounce lower and shorter, and the speed changes by itself — slow at the top, fast at the ground.",
		"Тот же мяч с непрерывными ключами: путь — цепочка дуг, каждый отскок ниже и короче, а скорость меняется сама — медленно наверху, быстро у земли." },
	{ "h", "4. Timing and spacing", "4. Тайминг и интервалы" },
	{ "p", "Timing is how many frames a move takes; spacing is how the object covers them. Weight lives in the spacing: a heavy thing starts slowly and stops slowly, a light one changes direction at once. The Curve editor shows it: steep — fast, flat — slow.",
		"Тайминг — сколько кадров занимает движение; интервалы — как объект их проходит. Вес живёт в интервалах: тяжёлое трогается и останавливается медленно, лёгкое меняет направление мгновенно. Редактор кривых это показывает: круто — быстро, полого — медленно." },
	{ "img", "speditor/help/anim_curves.jpg", "The ball in the Curve editor: Z (blue) — the bounces dying down, X (red) — steady forward motion. Flat tops: the ball hangs at the top of each bounce.",
		"Мяч в редакторе кривых: Z (синяя) — затухающие отскоки, X (красная) — ровное движение вперёд. Пологие вершины: мяч зависает в верхней точке каждого отскока." },
	{ "steps",
		en = { "A fall, a throw, a punch: give the key before the hit Speed up, so the motion arrives at full speed.",
			"Arriving, landing, a head turn that settles: Slow down, or bend the handle of the key past the next value for a small overshoot.",
			"Anticipation: before a big move, a small one the other way — a crouch before a jump, a swing back before a throw. More… → With a swing does it for one stretch.",
			"Nothing stands completely still: in a long pause leave a tiny drift (a moving hold), or the character looks frozen." },
		ru = { "Падение, бросок, удар: дайте ключу перед ударом «Разгон» — движение придёт на полной скорости.",
			"Приход, приземление, поворот головы, который успокаивается: «Торможение», или вытяните ручку ключа за следующее значение — небольшой перелёт.",
			"Замах (anticipation): перед большим движением — маленькое в обратную сторону. Присед перед прыжком, отвод руки перед броском. «Ещё…» → «С замахом» делает это для одного отрезка.",
			"Ничто не стоит совсем неподвижно: в долгой паузе оставьте едва заметное движение (moving hold), иначе персонаж выглядит застывшим." } },
	{ "h", "5. Overlap and follow-through", "5. Захлёст и доводка" },
	{ "p", "Parts of a body do not move together. The hips lead, the chest follows, the head and the hands come last and go on a little after the body has stopped. With Bone keys on, shift the keys of the head and the arms 2–4 frames later than the body's.",
		"Части тела не двигаются одновременно. Таз ведёт, грудь следует, голова и кисти приходят последними и продолжают чуть-чуть после того, как тело остановилось. С включёнными «Ключами костей» сдвиньте ключи головы и рук на 2–4 кадра позже ключей тела." },
	{ "img", "speditor/help/bonekeys.jpg", "Bone keys: the selected bone has its own row and its own rhythm; ghosts show its pose at the keys around.",
		"Ключи костей: у выделенной кости своя строка и свой ритм; призраки показывают её позу в соседних ключах." },
	{ "h", "6. Life: breathing, blinking, the face", "6. Жизнь: дыхание, моргание, лицо" },
	{ "steps",
		en = { "Procedural motion (the heart button): breathing and blinking without a single key.",
			"Eyes lead a head turn: look first, turn after. Key the eyes a few frames earlier.",
			"Speech: put a voice sound on the timeline and let Lip sync key the mouth." },
		ru = { "Процедурное движение (кнопка с сердцем): дыхание и моргание без единого ключа.",
			"Глаза ведут поворот головы: сначала взгляд, потом поворот. Ставьте ключи глаз на несколько кадров раньше.",
			"Речь: положите звук голоса на таймлайн и дайте липсинку поставить ключи рта." } },
	{ "img", "speditor/help/proc.jpg", "Procedural motion: breathing and blinking on top of the keys.", "Процедурное движение: дыхание и моргание поверх ключей." },
	{ "h", "Walking", "Ходьба" },
	{ "steps",
		en = { "Do not key a walk by hand at first: right click the character → Import model animation → a walk (walk_all, walk_suitcase…), with Move the character along on — the feet step without sliding.",
			"Make it yours on top: lean the chest, swing the arms more, tilt the head — with the Motion Editor over the whole walk, so one edit changes every step.",
			"A foot that slides after an edit: lock it (bone menu → lock) or move it back with IK (I)." },
		ru = { "Не ставьте ходьбу вручную с нуля: ПКМ по персонажу → Импорт анимации модели → ходьба (walk_all, walk_suitcase…) с включённым «Двигать персонажа» — ступни шагают без скольжения.",
			"Сделайте её своей поверх: наклоните грудь, сильнее махните руками, наклоните голову — Motion Editor на всю ходьбу, и одна правка меняет каждый шаг.",
			"Ступня поехала после правки: заблокируйте её (меню кости → замок) или верните на место IK (I)." } },
	{ "img", "speditor/help/import.jpg", "Import model animation: any animation of the model, or of another model with the same skeleton.", "Импорт анимации модели: любая анимация модели или другой модели с тем же скелетом." },
	{ "h", "Shooting", "Стрельба" },
	{ "steps",
		en = { "The quickest way: Record gameplay — play the fight; the take brings the bodies, the shots, the sounds, the muzzle flashes, shells, tracers and hits, all keyed.",
			"By hand: attach the weapon to the hand (Attach), key the aim; for each shot a recoil — 2 frames of the hands kicking up and back, then 5–8 frames of a soft return (Slow down).",
			"Add an effect (Windows → Effect Browser: MuzzleEffect, Tracer, Impact) and key its moment at the shot; the sound of the shot goes on the timeline from the weapon." },
		ru = { "Самый быстрый путь: «Запись игры» — сыграйте перестрелку; дубль приносит тела, выстрелы, звуки, вспышки, гильзы, трассеры и попадания с ключами.",
			"Вручную: привяжите оружие к руке (Привязка), поставьте ключи прицеливания; на каждый выстрел — отдача: 2 кадра руки уходят вверх-назад, потом 5–8 кадров мягкого возврата («Торможение»).",
			"Добавьте эффект (Окна → «Обозреватель эффектов»: MuzzleEffect, Tracer, Impact) и поставьте его момент на кадр выстрела; звук выстрела положите на таймлайн от оружия." } },
	{ "img", "speditor/help/rec_result.jpg", "A recorded fight: bodies, weapons, effects and sounds come with their keys.", "Записанная перестрелка: тела, оружие, эффекты и звуки приходят с ключами." },
	{ "h", "The camera and the cut", "Камера и монтаж" },
	{ "steps",
		en = { "Let a camera watch the hero (Aim at… → Keep looking at) instead of keying its turns.",
			"Change shots on the Film (shots) row: a wide shot to show the place, closer ones for the action. A cut on a movement hides the cut.",
			"Render the video with Motion blur: fast moves get the film look." },
		ru = { "Пусть камера сама следит за героем (Навести на… → Следить за объектом), а не ключи её поворотов.",
			"Меняйте планы в строке «Лента (планы)»: общий план показывает место, ближе — действие. Склейка на движении прячет склейку.",
			"Рендерите видео с размытием движения: быстрые движения получают киношный вид." } },
	{ "h", "Keep it tidy: tracks", "Порядок: ленты" },
	{ "p", "A scene with ten characters and their weapons is a long list. Right click a row → Track → New track with these objects: the objects go under one header that shows all their keys and folds into one row — like the track groups of SFM's clip editor.",
		"Сцена с десятком персонажей и их оружием — длинный список. ПКМ по строке → Лента → «Новая лента с этими объектами»: объекты уходят под один заголовок, который показывает все их ключи и сворачивается в одну строку, — как группы треков в клип-редакторе SFM." },
	{ "img", "speditor/help/anim_tracks.jpg", "Two tracks: Combine (folded — one row with the keys of its four objects) and Gordon (open).",
		"Две ленты: Combine (свёрнута — одна строка с ключами её четырёх объектов) и Gordon (раскрыта)." },
	{ "tip", "The usual mistakes: everything starts and stops at the same frame (shift some keys); Linear motion on living things (use Continuous); feet sliding (lock them); too many keys too early (block with few, add detail last).",
		"Частые ошибки: всё начинается и заканчивается на одном кадре (сдвиньте часть ключей); «Равномерно» на живых существах (используйте «Непрерывно»); скользящие ступни (заблокируйте их); слишком много ключей слишком рано (блокируйте немногими, детали — в конце)." },
	{ "result", "An animation with clear poses, motion on arcs, weight in the timing and a body that moves as a whole — not keys played one after another.",
		"Анимация с ясными позами, движением по дугам, весом в тайминге и телом, которое движется целиком, — а не ключи, сыгранные один за другим." },
	{ "see", "sa_keys", "the basics of keys", "основы ключей" },
	{ "see", "sa_curves", "the kinds of motion and the Curve editor", "виды движения и редактор кривых" },
	{ "see", "sa_motion", "one edit over a whole stretch", "одна правка на целый отрезок" },
	{ "see", "sa_bones", "bone keys for overlap", "ключи костей для захлёста" },
	{ "see", "sa_rec", "record a fight from the game", "записать перестрелку из игры" },
	{ "try", "Make the whole animation smooth", "Сделать всю анимацию плавной", fn = function() SA.SmoothAll() end },
} })

-- b0.1: people could not find how to animate the eyes (Workshop comments) — a guide per body part
UI.AddGuide({ id = "sa_body", order = 12.2, section = "anim", icon = "icon16/user.png", title = { en = "Animating hands, legs, eyes and head", ru = "Анимация рук, ног, глаз и головы" }, blocks = {
	{ "p", "Every part of a character is animated the same way: pose it, press K, go to another frame, pose it again, press K. What differs is how each part is posed. Bone keys (the branch button of the timeline) let every part keep keys of its own.",
		"Любая часть персонажа анимируется одинаково: поставьте её, нажмите K, перейдите на другой кадр, поставьте снова, нажмите K. Отличается только то, как ставится каждая часть. «Ключи костей» (кнопка с веткой на таймлайне) дают каждой части свои ключи." },
	{ "h", "Hands and arms", "Кисти и руки" },
	{ "steps",
		en = { "Turn the rig on (R, or the doll button of the viewport bar): the hands get boxes, the elbows diamonds.",
			"Drag a box: the hand moves and the arm bends after it (IK). Turn it with the rotate gizmo (2) — the wrist only.",
			"Drag the elbow diamond to choose where the elbow points; the hand stays where it is.",
			"Fingers: select a finger bone in the Animation Set Editor tree (or on the skeleton) and turn it (2)." },
		ru = { "Включите риг (R или кнопка с куклой на панели вьюпорта): у кистей появятся кубики, у локтей — ромбы.",
			"Тяните кубик: кисть двигается, рука сгибается за ней (IK). Поверните её гизмо поворота (2) — только запястье.",
			"Тяните ромб локтя, чтобы выбрать, куда смотрит локоть; кисть остаётся на месте.",
			"Пальцы: выделите кость пальца в дереве редактора набора анимаций (или на скелете) и поверните (2)." } },
	{ "h", "Legs and feet", "Ноги и стопы" },
	{ "steps",
		en = { "The feet are boxes of the rig, the knees diamonds: drag a foot, the leg bends; the knee diamond turns the knee in or out.",
			"Move the body by the big ring of the pelvis: the feet stay planted on the ground (View → IK: keep the feet planted).",
			"A step: key the foot on the ground, lift it half way at the middle frame, put it down at the next key — Animation → A good animation, step by step shows a whole walk." },
		ru = { "Стопы — кубики рига, колени — ромбы: тяните стопу — нога сгибается; ромб колена поворачивает колено внутрь или наружу.",
			"Двигайте тело большим кольцом таза: стопы остаются на земле (Вид → IK: стопы стоят на месте).",
			"Шаг: ключ со стопой на земле, на среднем кадре поднимите её, на следующем ключе поставьте — статья «Хорошая анимация шаг за шагом» показывает целую ходьбу." } },
	{ "h", "Head and neck", "Голова и шея" },
	{ "steps",
		en = { "With the rig on the spine, neck and head have rings: drag a ring and turn with the rotate gizmo (2). Too big over the face? View → Rig size, or switch the rings off there.",
			"Without the rig select the Head1 / Neck1 bone (tree or skeleton) and turn it (2). The white outer ring turns the head as you see it on the screen.",
			"A head that is never still: Procedural motion → Head moves by itself, or Noise of the Head1 bone (select the bone first)." },
		ru = { "С ригом у позвоночника, шеи и головы есть кольца: щёлкните кольцо и вращайте гизмо поворота (2). Слишком крупно над лицом? Вид → Размер рига, там же кольца можно выключить.",
			"Без рига выделите кость Head1 / Neck1 (в дереве или на скелете) и поверните (2). Белое внешнее кольцо поворачивает голову так, как вы её видите на экране.",
			"Голова, которая никогда не стоит на месте: «Процедурное движение» → «Голова двигается сама» или шум кости Head1 (сначала выделите кость)." } },
	{ "img", "speditor/help/rig_size.jpg", "View → Rig size: on the left the normal rig, on the right Tiny with thin lines and the rings of the spine, neck and head switched off — the face is free to pose.",
		"Вид → Размер рига: слева обычный риг, справа «Крошечный» с тонкими линиями и выключенными кольцами позвоночника, шеи и головы — лицо свободно для позы." },
	{ "h", "Eyes", "Глаза" },
	{ "steps",
		en = { "Select the character, open the Element Viewer (or click Eyes in the Animation Set Editor tree): viewTarget, eyes_rightleft, eyes_updown, eyes_distance.",
			"Move the sliders — the eyes look there. eyes: look at the camera aims them at the camera you look through in one click; eyes: look ahead lets them go.",
			"Press K: the eye target is in the key. On another frame aim the eyes elsewhere and press K again — between the keys the eyes move over (since b0.1).",
			"A key without an eye target lets the eyes look ahead by themselves from that key on.",
			"Blinks and lids are face sliders (the Face tree: blink, lid_closer…), keyed as the rest of the face; Procedural motion → Blinking blinks by itself." },
		ru = { "Выделите персонажа, откройте «Просмотр элементов» (или щёлкните «Глаза» в дереве редактора набора анимаций): цель взгляда, глаза: влево / вправо, вверх / вниз, расстояние до цели.",
			"Двигайте ползунки — глаза смотрят туда. «глаза: смотреть в камеру» одним щелчком наводит их на камеру, через которую вы смотрите; «смотреть прямо» отпускает их.",
			"Нажмите K: цель взгляда в ключе. На другом кадре наведите глаза в другое место и снова нажмите K — между ключами глаза переводятся плавно (с b0.1).",
			"Ключ без цели взгляда отпускает глаза смотреть прямо самим, начиная с этого ключа.",
			"Моргание и веки — ползунки лица (дерево «Лицо»: blink, lid_closer…), они ключуются вместе с лицом; «Процедурное движение» → «Моргание» моргает само." } },
	{ "img", "speditor/help/eyes_look.jpg", "Eyes: look at the camera — the Eyes item of the Animation Set Editor tree (left) shows viewTarget and the eye sliders; one click and the hero looks into the work camera. Press K to keep it in a key.",
		"«глаза: смотреть в камеру» — пункт «Глаза» в дереве Animation Set Editor (слева) показывает цель взгляда и ползунки глаз; один щелчок — и герой смотрит в рабочую камеру. K — сохранить это в ключе." },
	{ "tip", "A model without an eyes attachment cannot aim its eyes: the editor says so. Many SFM ports have it; some props do not.",
		"Модель без точки eyes не может наводить глаза — редактор об этом скажет. У большинства портов из SFM она есть, у некоторых пропов — нет." },
	{ "see", "sa_bones", "keys of single bones and ghosts", "ключи отдельных костей и призраки" },
	{ "see", "sa_face", "faces and lip sync", "лица и липсинк" },
	{ "see", "posing", "the gizmo, IK, stretching", "гизмо, IK, растяжение" },
	{ "result", "A character whose hands, feet, head and eyes each move on their own, as in SFM.", "Персонаж, у которого кисти, стопы, голова и глаза двигаются каждый сам по себе, как в SFM." },
} })

---------------------------------------------------------------------
-- b0.2: SFM's bookmarks, play modes, Motion Editor presets, the rotator, the shot list
---------------------------------------------------------------------
UI.AddGuide({ id = "sa_marks", order = 10.2, section = "anim", icon = "icon16/flag_blue.png", title = { en = "Bookmarks, play modes, shot list", ru = "Закладки, режимы воспроизведения, список планов" }, blocks = {
	{ "p", "Three small things of SFM's timeline that save a lot of time: bookmarks — named marks on the frame numbers to jump to; play modes — once, in a loop, or to the end and back; and the shot list — all the shots of the film as text.",
		"Три мелочи таймлайна SFM, которые экономят много времени: закладки — именованные отметки на номерах кадров, к которым можно прыгать; режимы воспроизведения — один раз, по кругу или до конца и обратно; список планов — все планы фильма текстом." },
	{ "img", "speditor/help/bookmarks.jpg", "The timeline: the play mode button (loop) and the bookmark button after the transport; the bookmarks Start (12) and Hit (48) are blue flags on the frame numbers, with a faint line down the rows.",
		"Таймлайн: кнопка режима воспроизведения (по кругу) и кнопка закладки после транспорта; закладки Start (12) и Hit (48) — синие флажки на номерах кадров со слабой линией вниз по строкам." },
	{ "h", "Bookmarks", "Закладки" },
	{ "steps",
		en = { "Put the playhead on a frame you will come back to: a beat of the music, the moment of a hit, the start of a move.",
			"Press the flag button of the timeline: a blue flag stands on that frame. Pressing it again on the same frame removes it.",
			"Click a flag to jump there; drag it to move it; right click it — Go to it, Rename the bookmark (its name is written next to the flag), Remove the bookmark.",
			"A right click on the flag button (or on the frame numbers) lists all bookmarks to jump to and has Remove all bookmarks.",
			"Bookmarks are saved with the scene. Inserting or cutting out time (the film strip, Alt + drag of a cut) moves them with the animation." },
		ru = { "Поставьте курсор времени на кадр, к которому будете возвращаться: удар в музыке, момент попадания, начало движения.",
			"Нажмите кнопку с флажком на таймлайне: на этом кадре встанет синий флажок. Повторное нажатие на том же кадре убирает его.",
			"Щелчок по флажку — переход к нему; перетаскивание — перенос; ПКМ — «Перейти к ней», «Переименовать закладку» (имя пишется рядом с флажком), «Убрать закладку».",
			"ПКМ по кнопке с флажком (или по номерам кадров) показывает список всех закладок для перехода и «Убрать все закладки».",
			"Закладки сохраняются со сценой. Вставка и вырезание времени (лента планов, Alt + перетаскивание склейки) сдвигают их вместе с анимацией." } },
	{ "h", "Play modes", "Режимы воспроизведения" },
	{ "p", "The button right after the transport (as SFM's play mode) switches with every click: Play once — stops at the last frame; Play in a loop — starts again; Play to the end and back (bounce) — the animation runs forward and backward for good, handy to look at a move or a cycle. The mode is saved with the scene. Watch in the game (outside the editor) keeps its own loop setting.",
		"Кнопка сразу после транспорта (как режим воспроизведения в SFM) переключается каждым щелчком: «Играть один раз» — останавливается на последнем кадре; «По кругу» — начинает снова; «До конца и обратно» (bounce) — анимация бесконечно идёт вперёд и назад, удобно разглядывать движение или цикл. Режим сохраняется со сценой. «Смотреть в игре» (вне редактора) хранит свою настройку повтора." },
	{ "h", "The shot list", "Список планов" },
	{ "img", "speditor/help/shotlist_menu.jpg", "File → Export the shot list (also in the menu of the film strip).",
		"Файл → «Экспорт списка планов» (есть и в меню ленты планов)." },
	{ "p", "File → Export the shot list (or a right click on the film strip) writes every shot as a line: its number, its camera, the first and the last frame, the length in frames and seconds, and the timecodes. The text goes to the clipboard and to a file in garrysmod/data/speditor/shotlists/ — for a storyboard, an edit in another program or the people you make the film with. It is SFM's Export Shot List script.",
		"Файл → «Экспорт списка планов» (или ПКМ по ленте планов) записывает каждый план строкой: номер, камера, первый и последний кадр, длина в кадрах и секундах, таймкоды. Текст попадает в буфер обмена и в файл в garrysmod/data/speditor/shotlists/ — для раскадровки, монтажа в другой программе или тех, с кем вы делаете фильм. Это скрипт SFM Export Shot List." },
	{ "result", "A timeline you can find your way around, played the way you want to see it, and a film you can describe in one paste.",
		"Таймлайн, в котором легко ориентироваться, воспроизведение так, как удобно смотреть, и фильм, который описывается одной вставкой текста." },
	{ "see", "sa_keys", "keys and the timeline", "ключи и таймлайн" },
	{ "see", "sa_cuts", "shots, cameras and the film strip", "планы, камеры и лента" },
	{ "try", "Bookmark the playhead's frame", "Закладка на кадре курсора", fn = function() SA.AddMark(math.floor(SA.frame + 0.5)) end },
} })

UI.AddGuide({ id = "sa_presets", order = 11.6, section = "anim", icon = "icon16/wand.png", title = { en = "Motion Editor presets: smooth, jitter, stagger and more", ru = "Пресеты Motion Editor: сгладить, дрожь, волна и другие" }, blocks = {
	{ "p", "SFM's Motion Editor has procedural presets: instead of moving keys one by one, a whole stretch of animation is smoothed, sharpened, shaken or frozen at once. Since b0.2 round 6 GM:FM has SFM's whole list — 19 presets in three groups — and they work on the keys of the selected objects inside the time selection: softly at its falloff, in full in its middle. SFM gives only their names; what each one does here is described below.",
		"В Motion Editor SFM есть процедурные пресеты: вместо того чтобы двигать ключи по одному, целый отрезок анимации разом сглаживается, заостряется, встряхивается или замирает. С b0.2 (раунд 6) в GM:FM есть весь список SFM — 19 пресетов в трёх группах, — и они работают с ключами выделенных объектов внутри выделения времени: мягко в его затухании, полностью в середине. SFM даёт только их названия; что каждый делает здесь, описано ниже." },
	{ "img", "speditor/help/presets_menu.jpg", "A right click on the frame numbers (or the clock button) → Procedural presets (SFM): the groups Motion, From edge to edge and Face, then Playhead, Paste and Copy the frame; each preset at 25 / 50 / 100 %.",
		"ПКМ по номерам кадров (или кнопка с часами) → «Процедурные пресеты (SFM)»: группы «Движение», «От края до края» и «Лицо», затем Playhead, Paste и «Скопировать кадр»; каждый пресет на 25 / 50 / 100 %." },
	{ "keys", {
		{ "Smooth", "every key goes half way to the middle of the keys before and after it: bumps and jerks go away (100 % — half way; apply again for more).", "каждый ключ сдвигается на полпути к середине между соседними: рывки и дёрганье уходят (100 % — на полпути; примените ещё раз для большего)." },
		{ "Sharp", "the opposite: every key goes away from that middle — the moves get stronger and snappier.", "наоборот: каждый ключ уходит от этой середины — движения становятся сильнее и резче." },
		{ "Jitter", "a small random shake on top of the keys: 1 unit of place, 1.5° of turn, 5 % of the face at 100 %. A nervous hand, a hand-held camera, cold. The same keys always get the same shake.", "небольшая случайная дрожь поверх ключей: 1 единица места, 1,5° поворота, 5 % лица при 100 %. Нервная рука, ручная камера, холод. Одни и те же ключи всегда получают одинаковую дрожь." },
		{ "Hold", "every key goes towards the first key of the selection: the pose holds still through the stretch.", "каждый ключ идёт к первому ключу выделения: поза держится весь отрезок." },
		{ "Default", "bone offsets and turns go to zero and the face to its rest: the model's own pose comes back over the stretch. The place of the object stays.", "смещения и повороты костей идут к нулю, лицо — к покою: на отрезке возвращается собственная поза модели. Место объекта остаётся." },
		{ "Steady", "Smooth four times over: removes a shake (a recorded or a hand-held motion) and keeps the big moves.", "Smooth четыре раза подряд: убирает дрожь (записанного или «ручного» движения) и оставляет крупные движения." },
		{ "Round", "whole numbers: places to whole units, turns to whole degrees, face sliders to off or on.", "целые значения: места — до целых единиц, повороты — до целых градусов, слайдеры лица — в «выкл» или «вкл»." },
		{ "Stagger", "with several objects selected, each next one plays the same motion 2 frames later than the one before (in the order they were selected): a wave through a crowd, falling dominoes.", "при нескольких выделенных объектах каждый следующий играет то же движение на 2 кадра позже предыдущего (в порядке выделения): волна по толпе, падающее домино." },
		{ "In / Out", "every key goes towards the value the animation has where the selection begins (In) or ends (Out).", "каждый ключ идёт к значению, которое анимация имеет там, где выделение начинается (In) или кончается (Out)." },
		{ "Ramp / Spline", "the stretch is laid again from the value at the start to the value at the end: in a straight line (Ramp) or smoothly (Spline).", "отрезок прокладывается заново от значения в начале к значению в конце: по прямой (Ramp) или плавно (Spline)." },
		{ "Drop / Release", "the same, speeding up (Drop) or slowing down (Release) towards the end.", "то же, с разгоном (Drop) или с торможением (Release) к концу." },
		{ "Zero/Half/One", "face sliders to 0, 0.5 or 1 (a mouth shut, half open, fully open; eyes closed…).", "слайдеры лица в 0, 0,5 или 1 (рот закрыт, приоткрыт, открыт полностью; глаза закрыты…)." },
		{ "Playhead", "every key goes towards the pose of the frame under the playhead.", "каждый ключ идёт к позе кадра под курсором времени." },
		{ "Paste", "every key goes towards a frame copied before with Copy the frame under the playhead (in the same menu).", "каждый ключ идёт к кадру, скопированному раньше пунктом «Скопировать кадр под курсором» (в том же меню)." },
	}, w = 90 },
	{ "steps",
		en = { "Select the objects whose animation you change (several are fine; their faces are changed too).",
			"Shift + drag on the frame numbers of the timeline: the time selection. Drag its edges apart for a soft falloff.",
			"Right click the frame numbers → Procedural presets (SFM) → a group → a preset → 25, 50 or 100 %.",
			"Play it. Not enough — apply again; too much — Ctrl+Z. Without a time selection the same menu has Procedural presets on the whole animation." },
		ru = { "Выделите объекты, анимацию которых меняете (можно несколько; их лица меняются тоже).",
			"Shift + перетаскивание по номерам кадров таймлайна — выделение времени. Разведите его края для мягкого затухания.",
			"ПКМ по номерам кадров → «Процедурные пресеты (SFM)» → группа → пресет → 25, 50 или 100 %.",
			"Проиграйте. Мало — примените ещё раз; много — Ctrl+Z. Без выделения времени в том же меню есть «Процедурные пресеты на всю анимацию»." } },
	{ "tip", "Presets change keys, they add none: a stretch with few keys changes little. For a long shake put keys every few frames first (or record the motion), then Jitter it.",
		"Пресеты меняют ключи, но не добавляют их: отрезок с малым числом ключей меняется мало. Для долгой дрожи сначала поставьте ключи через каждые несколько кадров (или запишите движение), потом примените Jitter." },
	{ "result", "Seconds of animation cleaned, livened up or calmed with one click — as in SFM.", "Секунды анимации очищены, оживлены или успокоены одним щелчком — как в SFM." },
	{ "see", "sa_motion", "the time selection itself", "само выделение времени" },
	{ "see", "sa_proc", "endless motion without keys: noise and the rotator", "бесконечное движение без ключей: шум и ротатор" },
} })

UI.AddGuide({ id = "sa_rotator", order = 16.2, section = "anim", icon = "icon16/arrow_rotate_clockwise.png", title = { en = "Rotator: wheels, fans, propellers", ru = "Ротатор: колёса, вентиляторы, пропеллеры" }, blocks = {
	{ "p", "Something that turns all the time — a wheel, a fan, a propeller, a turntable, a clock hand — needs no keys. SFM makes it with its Create rotator script; in GM:FM it is part of Procedural motion: the object turns round one of its own axes at a set speed while the animation plays and in the render.",
		"То, что вращается всё время — колесо, вентилятор, пропеллер, поворотный стол, стрелка часов, — не требует ключей. В SFM это делает скрипт Create rotator; в GM:FM это часть процедурного движения: объект вращается вокруг одной из своих осей с заданной скоростью при проигрывании и в рендере." },
	{ "img", "speditor/help/proc_rotator.jpg", "Procedural motion of the crate: Rotator — Spin 180 °/s round the axis up (yaw).",
		"Процедурное движение ящика: ротатор — вращение 180 °/с вокруг оси вверх (рыскание)." },
	{ "steps",
		en = { "Select the object, then the heart button of the timeline (or the object menu → Procedural motion…).",
			"Spin, °/s: how fast — 360 is a turn a second; minus turns the other way.",
			"Axis: across (pitch) for a wheel seen from the side, up (yaw) for a turntable or a fan on the ceiling, forward (roll) for a propeller.",
			"Press Play to see it: the object turns round the middle of the model, on top of its keys (it can be carried along and turn at the same time).",
			"Switch off in the same window takes all procedural motion of the object away." },
		ru = { "Выделите объект, затем кнопка с сердцем на таймлайне (или меню объекта → Процедурное движение…).",
			"«Вращение, °/с»: как быстро — 360 это оборот в секунду; минус вращает в другую сторону.",
			"Ось: поперёк (наклон) — колесо сбоку, вверх (рыскание) — поворотный стол или потолочный вентилятор, вперёд (крен) — пропеллер.",
			"Нажмите «Запустить, чтобы увидеть»: объект вращается вокруг середины модели поверх своих ключей (его можно одновременно везти и вращать).",
			"«Выключить» в том же окне убирает всё процедурное движение объекта." } },
	{ "tip", "While you edit, the scene stands as its keys make it: the turn shows only while playing and in the render, so it never gets into a key by accident.",
		"Пока вы редактируете, сцена стоит так, как её задают ключи: вращение видно только при проигрывании и в рендере, поэтому оно никогда случайно не попадёт в ключ." },
	{ "result", "Wheels that roll and blades that spin for the whole film without a single key.", "Колёса катятся, лопасти вращаются весь фильм — без единого ключа." },
	{ "see", "sa_proc", "breathing, blinking, noise", "дыхание, моргание, шум" },
} })

UI.AddGuide({ id = "sa_fxclips", order = 11.7, section = "anim", icon = "icon16/film_add.png", title = { en = "FX clips: titles, film grain, colour", ru = "FX-клипы: титры, зерно плёнки, цвет" }, blocks = {
	{ "p", "As SFM's effect clips (TextFX, HSL Grain, Color Correction, Material Overlay), GM:FM lays an effect over the finished frame on a stretch of the film. The clips live on the FX clips row under the film strip; ones that overlap in time take a row each.",
		"Как клипы-эффекты SFM (TextFX, HSL Grain, Color Correction, Material Overlay), GM:FM накладывает эффект на готовый кадр на отрезке фильма. Клипы лежат в строке «FX-клипы» под лентой планов; перекрывающиеся по времени занимают по строке." },
	{ "img", "speditor/help/fxclips_result.jpg", "Frame 48 of a film: the title The Warehouse in a dark box, film grain over the whole frame and a colour correction that takes the saturation down and warms the picture.",
		"Кадр 48 фильма: титр The Warehouse на тёмной плашке, зерно плёнки по всему кадру и цветокоррекция, которая убавляет насыщенность и согревает картинку." },
	{ "img", "speditor/help/fxclips_row.jpg", "The FX clips row under the film strip: the title (frames 0–72, its fades drawn as slopes), the grain over the whole film and the colour correction from frame 24 with a long fade in.",
		"Строка «FX-клипы» под лентой планов: титр (кадры 0–72, нарастание и угасание — наклонные линии), зерно на весь фильм и цветокоррекция с 24-го кадра с долгим нарастанием." },
	{ "steps",
		en = { "Right click on the FX clips row → Add an FX clip here: Text (title), Film grain, Colour correction or Material overlay. With a time selection the clip takes its stretch, and its falloff becomes the fades.",
			"Drag a clip to move it, drag near its ends to make it longer or shorter.",
			"Double click (or right click → Parameters…): the start and the end, the fades in and out, and the clip's own settings — the text and its place, size, colour, outline and dark box; the amount and size of the grain; brightness, contrast, saturation and tint.",
			"The clips are in the render, the video, the Render window preview and the player — not in the plain viewports." },
		ru = { "Правый клик по строке «FX-клипы» → «Добавить FX-клип сюда»: «Текст (титр)», «Зерно плёнки», «Цветокоррекция» или «Наложение материала». При выделении времени клип занимает его отрезок, а затухание выделения становится нарастанием и угасанием.",
			"Перетащите клип, чтобы сдвинуть; тащите у краёв, чтобы удлинить или укоротить.",
			"Двойной клик (или правый клик → «Параметры…»): начало и конец, нарастание и угасание и собственные настройки клипа — текст и его место, размер, цвет, обводка и плашка; сила и размер зерна; яркость, контраст, насыщенность и тонирование.",
			"Клипы есть в рендере, видео, превью окна «Рендер» и плеере — но не в обычных вьюпортах." } },
	{ "img", "speditor/help/fxclip_window.jpg", "The parameters of a text clip (double click on it): start, end, fades, the text (several lines), its size and place, alignment, colour, outline, bold and the dark box.",
		"Параметры текстового клипа (двойной клик по нему): начало, конец, нарастание и угасание, текст (несколько строк), размер и место, выравнивание, цвет, обводка, жирность и тёмная плашка." },
	{ "tip", "The fades are the clip's keys: a title comes up and goes away, grain creeps in. The clips are saved with the scene and move with the film when time is inserted or cut out.",
		"Нарастание и угасание — ключи клипа: титр появляется и уходит, зерно плавно нарастает. Клипы сохраняются со сценой и двигаются вместе с фильмом, когда время вставляют или вырезают." },
	{ "result", "Opening titles, a caption under a shot, an old-film look on a flashback.", "Вступительные титры, подпись под планом, вид старой плёнки на флешбэке." },
	{ "see", "sa_cuts", "the film strip: shots and cameras", "лента планов: планы и камеры" },
} })

UI.AddGuide({ id = "sa_rec_npcs", order = 12.6, section = "anim", icon = "icon16/group.png",
	title = { en = "NPCs of a take, step by step", ru = "NPC дубля шаг за шагом" }, blocks = {
	{ "p", "Before a gameplay take you can put NPCs exactly where they should stand: a soldier behind cover, a policeman at the door, a rebel next to you. Each gets a mark in the viewport with its own weapon and its attitude to you; when the take starts they appear on their marks and the take records them with you.",
		"Перед записью игры можно поставить NPC точно туда, где они должны стоять: солдата за укрытием, полицейского у двери, повстанца рядом с вами. Каждый получает метку во вьюпорте со своим оружием и отношением к вам; когда начинается дубль, они появляются на метках, и дубль записывает их вместе с вами." },
	{ "h", "1. Open the NPCs of the take", "1. Откройте «NPC дубля»" },
	{ "img", "speditor/help/rec_window.jpg", "The Record gameplay window (the webcam button of the timeline, or File → Record gameplay…).",
		"Окно «Запись игры» (кнопка с веб-камерой на таймлайне или «Файл» → «Запись игры…»).",
		marks = { { 0.06, 0.788 } } },
	{ "steps",
		en = { "NPCs of the take: N placed… opens the NPC window. N is how many marks this map already has." },
		ru = { "«NPC дубля: расставлено N…» открывает окно NPC. N — сколько меток уже есть на этой карте." } },
	{ "h", "2. Choose an NPC and its settings", "2. Выберите NPC и его настройки" },
	{ "img", "speditor/help/npc_window.jpg", "The NPCs of the take window: the NPCs of the spawn menu at the top, the marks of this map at the bottom.",
		"Окно «NPC дубля»: NPC из меню спавна сверху, метки этой карты снизу.",
		marks = { { 0.08, 0.33 }, { 0.035, 0.637 }, { 0.097, 0.677 }, { 0.436, 0.677 }, { 0.9, 0.774 }, { 0.04, 0.929 }, { 0.04, 0.967 } } },
	{ "steps",
		en = { "Click an NPC: every NPC of the spawn menu is here, Workshop ones too, by category; the field above finds one by name. A double click starts placing it at once.",
			"Place (click in the viewport) starts placing the chosen NPC (step 3).",
			"Weapon: Its own (as the spawn menu gives it), No weapon, or any weapon NPCs can use.",
			"Attitude: As the NPC is, Hostile to me or Friendly to me — a rebel friendly to you fights on your side, a soldier hostile to you attacks you.",
			"The marks of this map: click one to change its weapon and attitude, Move puts it somewhere else, Delete removes it, a double click brings the work camera to it.",
			"AI starts with the take (on by default): the NPCs appear on their marks when you press Start recording, but stand still — they do not think, move or shoot, and nobody targets them — until the recording itself begins after the countdown. So nothing happens before the camera rolls. Untick it and they act from the moment they appear.",
			"Take them away after the take: the live NPCs go when you are back in the editor (their recorded copies stay in the scene). Untick it to keep them on the map for the next take." },
		ru = { "Выберите NPC: здесь все NPC из меню спавна, и из Мастерской тоже, по категориям; поле сверху ищет по имени. Двойной щелчок сразу начинает его расстановку.",
			"«Поставить (щелчок во вьюпорте)» начинает расстановку выбранного NPC (шаг 3).",
			"«Оружие»: «Своё» (как его выдаёт меню спавна), «Без оружия» или любое оружие, которым умеют пользоваться NPC.",
			"«Отношение»: «Как у NPC», «Враждебен ко мне» или «Дружелюбен ко мне» — дружелюбный повстанец сражается на вашей стороне, враждебный солдат нападает на вас.",
			"Метки этой карты: щёлкните метку, чтобы поменять ей оружие и отношение; «Переставить» переносит её, «Удалить» убирает, двойной щелчок подводит к ней рабочую камеру.",
			"«ИИ включается со съёмкой» (включено по умолчанию): NPC появляются на метках, когда вы нажимаете «Начать запись», но стоят на месте — не думают, не двигаются, не стреляют, и никто их не трогает — пока после отсчёта не начнётся сама запись. Так до начала съёмки ничего не происходит. Без галочки они действуют сразу, как появились.",
			"«Убрать их после дубля»: живые NPC исчезают, когда вы возвращаетесь в редактор (их записанные копии остаются в сцене). Снимите галочку, чтобы оставить их на карте для следующего дубля." } },
	{ "h", "3. Put them in the viewport", "3. Расставьте их во вьюпорте" },
	{ "img", "speditor/help/npc_place.jpg", "Placing: the green ghost follows the cursor; the blue ones are the marks already placed, each with its number and name.",
		"Расстановка: зелёный призрак идёт за курсором; синие — уже поставленные метки, у каждой номер и имя." },
	{ "steps",
		en = { "Point at the ground in the Primary Viewport: a green ghost of the NPC stands under the cursor, the arrow shows where it will face.",
			"Turn the mouse wheel to turn it (15° a notch).",
			"Click: the NPC gets its mark (blue). Click again for the next one of the same kind; choose another NPC in the window to place that one instead.",
			"Esc or Stop placing ends. Fly the work camera as usual (right mouse button + WASD) to reach other places between clicks." },
		ru = { "Наведите курсор на землю в основном вьюпорте: под ним стоит зелёный призрак NPC, стрелка показывает, куда он будет смотреть.",
			"Колесо мыши поворачивает его (15° за щелчок колеса).",
			"Щелчок: NPC получает метку (синюю). Ещё щелчок — следующий такой же; выберите в окне другого NPC, чтобы ставить его.",
			"Esc или «Закончить расстановку» — готово. Между щелчками рабочую камеру можно водить как обычно (правая кнопка + WASD), чтобы добраться до других мест." } },
	{ "tip", "The marks are drawn only in the editor's viewports, never in a render, and are kept for each map — the same fight can be shot again and again.",
		"Метки рисуются только во вьюпортах редактора, никогда в рендере, и хранятся для каждой карты — тот же бой можно снимать снова и снова." },
	{ "h", "4. Start the take", "4. Начните дубль" },
	{ "img", "speditor/help/npc_take.jpg", "The moment the take starts: the soldier, the policeman and the rebel stand on their marks with the weapons the marks gave them (with AI starts with the take they stay like this through the countdown).",
		"Момент начала дубля: солдат, полицейский и повстанец стоят на своих метках с оружием, которое им дали метки (с «ИИ включается со съёмкой» они стоят так весь отсчёт)." },
	{ "steps",
		en = { "Start recording in the Record gameplay window (choose your weapons if the window asks). The NPCs appear on their marks before the countdown; with AI starts with the take they wait there, frozen, while the countdown runs.",
			"The take records them as any NPC around you; its radius grows by itself to reach the farthest mark.",
			"Play: from the first recorded frame they act — hostile ones attack you, friendly ones fight beside you, and they fight each other as the game makes them.",
			"Backspace stops the take: every NPC is in the scene as a recorded actor with its keys, the ones that died fall as ragdolls." },
		ru = { "«Начать запись» в окне «Запись игры» (выберите оружие, если окно попросит). NPC появляются на метках ещё до отсчёта; с «ИИ включается со съёмкой» они ждут там неподвижно, пока идёт отсчёт.",
			"Дубль записывает их, как любых NPC вокруг вас; его радиус сам увеличивается до самой дальней метки.",
			"Играйте: с первого записанного кадра они действуют — враждебные нападают на вас, дружелюбные сражаются рядом, и между собой они воюют так, как им велит игра.",
			"Backspace останавливает дубль: каждый NPC попадает в сцену записанным актёром с ключами, погибшие падают рэгдоллами." } },
	{ "img", "speditor/help/npc_fight.jpg", "A second after their AI woke: the Combine soldier and the policeman (hostile) have already shot the rebel, who was friendly to you — without AI starts with the take this would happen during the countdown, before anything is recorded.",
		"Через секунду после того, как включился их ИИ: солдат Альянса и полицейский (враждебные) уже застрелили повстанца, дружелюбного к вам, — без «ИИ включается со съёмкой» это случилось бы ещё во время отсчёта, до начала записи." },
	{ "tip", "In the GM:FM gamemode this is how NPCs get into a take — there is no spawn menu. In Sandbox it works the same, next to the spawn menu.",
		"В режиме GM:FM только так NPC и попадают в дубль — меню спавна там нет. В Sandbox всё работает так же, вместе с меню спавна." },
	{ "try", "Open NPCs of the take", "Открыть «NPC дубля»", fn = function() SA.OpenNPCPicker() end },
} })
