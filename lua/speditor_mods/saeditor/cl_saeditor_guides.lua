-- SAeditor — its guides in Help → How to use (cl_ui_guide.lua), with live demonstrations
-- drawn by the same code the tools use (SA.DrawMotion of the curve editor).
local MOD = SPeditor.Mod("saeditor")
local SA  = MOD.SA
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
	{ "try", "Open the Curve editor", "Открыть редактор кривых", fn = function() SA.OpenCurves() end },
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
			"The player: the TV button of the timeline (or File → Watch in the game → Player). A click on the camera name at the top of the player picks another camera." },
		ru = { "Добавьте в сцену две камеры и расставьте их.",
			"ПКМ по строке «Камеры» на нужном кадре → Переключиться на Camera 1 здесь. Позже так же для Camera 2.",
			"Метку смены можно перетащить; ПКМ по ней — сменить камеру или удалить. Ctrl + Z отменяет.",
			"Плеер: кнопка с телевизором на таймлайне (или Файл → Смотреть в игре → Плеер). Щелчок по имени камеры вверху плеера выбирает другую камеру." } },
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
	{ "result", "The animation watched in the game as a finished film, with its camera changes — and rendered to video the same way.",
		"Анимация смотрится в игре как готовый фильм со сменами камер — и так же рендерится в видео." },
} })

UI.AddGuide({ id = "sa_rec", order = 12.5, icon = "icon16/webcam.png", title = { en = "Record gameplay (machinima)", ru = "Запись игры (машинима)" }, blocks = {
	{ "p", "Instead of posing every frame you can simply play: walk, run, shoot, let the NPCs around do their thing. The take becomes ordinary keys, sounds and effects that you edit like any animation.",
		"Вместо того чтобы позировать каждый кадр, можно просто играть: ходить, бегать, стрелять, а NPC вокруг живут своей жизнью. Дубль становится обычными ключами, звуками и эффектами, которые правятся как любая анимация." },
	{ "img", "speditor/help/rec_window.jpg", "The Record gameplay window (the webcam button of the timeline, or File → Record gameplay…).",
		"Окно «Запись игры» (кнопка с веб-камерой на таймлайне или Файл → Запись игры…)." },
	{ "steps",
		en = { "Put the playhead where the take should start. Open Record gameplay and choose what to record: the NPCs around (within the radius), sounds, effects, how often a key is taken.",
			"Start recording: the editor closes, a countdown runs, then REC blinks in the corner. Play. The animation you already have plays along, so you can act against it.",
			"Backspace stops the take. The editor opens: you are in the scene as a ragdoll of your player model (skin, bodygroups, player colour) with your weapon in the hand, every NPC with its weapon, the sounds on the timeline and the effects as objects.",
			"Edit it like any animation: delete keys, fix a pose (with Bone keys — just one arm), add cameras and cuts, record another take on top." },
		ru = { "Поставьте головку туда, где должен начаться дубль. Откройте «Запись игры» и выберите, что записывать: NPC вокруг (в радиусе), звуки, эффекты, как часто брать ключ.",
			"«Начать запись»: редактор закроется, пойдёт отсчёт, потом в углу замигает REC. Играйте. Уже сделанная анимация идёт вместе с записью — можно играть против неё.",
			"Backspace останавливает дубль. Откроется редактор: в сцене вы — рэгдолл вашей модели игрока (скин, бодигруппы, цвет игрока) с оружием в руке, каждый NPC со своим оружием, звуки на таймлайне и эффекты отдельными объектами.",
			"Правьте как любую анимацию: удалите лишние ключи, поправьте позу (с ключами костей — одну руку), добавьте камеры и смены камер, запишите поверх ещё один дубль." } },
	{ "img", "speditor/help/rec_result.jpg", "A recorded take: the player with a crowbar and a citizen with an SMG, keyed every 2 frames; the tracer and the explosion are effect objects, the shot is a sound from the player.",
		"Записанный дубль: игрок с монтировкой и гражданин с SMG, ключ каждые 2 кадра; трассер и взрыв — объекты-эффекты, выстрел — звук от игрока." },
	{ "p", "What is not recorded: fingers (the hands keep their rest grip), the faces of the actors, effects the engine draws by itself (bullet holes, the muzzle flashes of HL2 weapons), and an NPC whose body the game removes on death is simply hidden after its last frame. Ragdolls of dead NPCs that stay on the server are followed.",
		"Что не записывается: пальцы (кисти остаются в исходном хвате), лица актёров, эффекты, которые движок рисует сам (следы от пуль, вспышки выстрелов оружия HL2), а NPC, чьё тело игра убирает после смерти, просто скрывается после своего последнего кадра. Рэгдоллы убитых NPC, которые остаются на сервере, записываются дальше." },
	{ "result", "A scene that plays like your gameplay, ready to be re-shot from scene cameras and rendered.",
		"Сцена, которая играет как ваша игра, — её можно переснять камерами сцены и отрендерить." },
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
	{ "result", "Characters that never freeze between keys.", "Персонажи, которые не застывают между ключами." },
} })

UI.AddGuide({ id = "sa_render", order = 17, icon = "icon16/film_save.png", title = { en = "Render the animation to video", ru = "Рендер анимации в видео" }, blocks = {
	{ "p", "A scene with animation renders as one AVI video with its sound. The game names it <name>.avi.dat (it lets Lua write only a few kinds of files): remove .dat and any player opens it.",
		"Сцена с анимацией рендерится в одно видео AVI со звуком. Игра называет его <имя>.avi.dat (Lua можно писать лишь несколько видов файлов): уберите .dat — и его откроет любой плеер." },
	{ "steps",
		en = { "Render (top right) or Render animation… on the timeline.",
			"Camera: As the animation switches cameras (the Cameras row), the Primary Viewport, or one camera.",
			"Video size trades quality for megabytes; Video frame rate can be higher than the animation's — the frames in between are worked out.",
			"After the render the console prints the ffmpeg command that turns the AVI into a small MP4." },
		ru = { "«Рендер» (справа вверху) или «Рендер анимации…» на таймлайне.",
			"Камера: Как переключает камеры анимация (строка «Камеры»), основной вьюпорт или одна камера.",
			"«Размер видео» меняет качество на мегабайты; «Частота кадров видео» может быть выше, чем у анимации, — промежуточные кадры вычисляются.",
			"После рендера в консоль печатается команда ffmpeg, которая сделает из AVI маленький MP4." } },
	{ "result", "garrysmod/data/speditor/renders/<name>.avi.dat — the finished film.", "garrysmod/data/speditor/renders/<имя>.avi.dat — готовый фильм." },
	{ "try", "Render animation…", "Рендер анимации…", fn = function() SA.OpenRender() end },
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
	{ "result", "Old SMH animations continue in SAeditor, and back.", "Старые анимации SMH продолжаются в SAeditor — и обратно." },
} })
