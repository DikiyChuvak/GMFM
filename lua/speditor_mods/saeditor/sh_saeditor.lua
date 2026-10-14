-- SAeditor: shared constants, interpolation maths, interface strings
local MOD = SPeditor.Mod("saeditor")
MOD.SA = MOD.SA or {}
local SA = MOD.SA

SA.FPS_LIST   = { 12, 15, 24, 30, 60 }
SA.MAX_FRAMES = 3600            -- animation length in frames, at most
SA.MAX_KEYS   = 600             -- keys per object
SA.EASES      = { "ease", "linear", "hold" }

-- Models whose animations the import offers for any character with the same skeleton:
-- the player models carry every player animation (walking, gestures, dances and whatever
-- addons add to the player animation sets).
SA.ANIM_MODELS = {
	{ "sa_imp_src_male",   "models/player/kleiner.mdl" },
	{ "sa_imp_src_female", "models/player/alyx.mdl" },
	{ "sa_imp_src_zombie", "models/player/zombie_classic.mdl" },
}

SA.MAX_SOUNDS = 384             -- sound clips in one animation
SA.SOUND_EXT  = { wav = true, mp3 = true, ogg = true }
SA.SOUND_DIR  = "data/speditor/sounds"      -- the user's own sound files

-- A sound clip: { id, path, f = start frame, uid = the object it comes from (0 — heard
-- everywhere), voice = from the character's head, vol = 0..2, pitch = speed in percent,
-- dist = distance of full volume }. Returns a checked copy, or nil for a broken clip.
function SA.CleanSound(c)
	if not istable(c) or not isstring(c.path) then return nil end
	local path = string.gsub(c.path, "\\", "/")
	if #path < 8 or #path > 200 or string.find(path, "..", 1, true) or string.find(path, "[%c\":*?<>|]") then return nil end
	if string.sub(path, 1, 6) ~= "sound/" and string.sub(path, 1, 5) ~= "data/" then return nil end
	if not SA.SOUND_EXT[string.lower(string.GetExtensionFromFilename(path) or "")] then return nil end
	local function num(v, def, min, max) return math.Clamp(tonumber(v) or def, min, max) end
	return {
		id = math.floor(num(c.id, 0, 0, 1000000)), path = path,
		f = math.floor(num(c.f, 0, 0, SA.MAX_FRAMES) + 0.5), uid = math.floor(num(c.uid, 0, 0, 2 ^ 31)),
		voice = c.voice and true or false, vol = num(c.vol, 1, 0, 2),
		pitch = math.floor(num(c.pitch, 100, 25, 400) + 0.5), dist = num(c.dist, 300, 16, 8192),
		-- trimming: seconds of the file cut off at its start and at its end
		cin = math.Round(num(c.cin, 0, 0, 3600), 3), cout = math.Round(num(c.cout, 0, 0, 3600), 3),
	}
end

-- actions of the Key message
SA.OP = { SET = 1, DELETE = 2, MOVE = 3, EASE = 4, CLEAR = 5, CLEAR_ALL = 6, COPY = 7 }

function SA.EaseValue(ease, u)
	if ease == "hold" then return 0 end
	if ease == "linear" then return u end
	return u * u * (3 - 2 * u)
end

---------------------------------------------------------------------
-- Rotation along the shortest arc. LerpAngle adds Euler angles one by one,
-- and between distant poses a bone travels in a "figure of eight"; here the rotation difference
-- is converted to an axis and an angle, and the rotation goes around that axis evenly.
---------------------------------------------------------------------
local sin, cos, acos, sqrt, rad, deg = math.sin, math.cos, math.acos, math.sqrt, math.rad, math.deg

function SA.SlerpAngle(a, b, u)
	if u <= 0 then return Angle(a.p, a.y, a.r) end
	if u >= 1 then return Angle(b.p, b.y, b.r) end
	-- rotation of b relative to a
	local _, l = WorldToLocal(vector_origin, b, vector_origin, a)
	-- its quaternion (the AngleQuaternion formula from Source)
	local sy, cy = sin(rad(l.y) * 0.5), cos(rad(l.y) * 0.5)
	local sp, cp = sin(rad(l.p) * 0.5), cos(rad(l.p) * 0.5)
	local sr, cr = sin(rad(l.r) * 0.5), cos(rad(l.r) * 0.5)
	local x = sr * cp * cy - cr * sp * sy
	local y = cr * sp * cy + sr * cp * sy
	local z = cr * cp * sy - sr * sp * cy
	local w = cr * cp * cy + sr * sp * sy
	if w < 0 then x, y, z, w = -x, -y, -z, -w end
	local s = sqrt(math.max(1 - w * w, 0))
	local out = Angle(a.p, a.y, a.r)
	if s < 1e-5 then return out end
	-- the axis in the space of a (x forward, y left, z up) -> into the world
	local axis = a:Forward() * (x / s) - a:Right() * (y / s) + a:Up() * (z / s)
	out:RotateAroundAxis(axis, deg(2 * acos(math.min(w, 1))) * u)
	return out
end

function SA.LerpNum(a, b, u) return a + (b - a) * u end

---------------------------------------------------------------------
-- Strings
---------------------------------------------------------------------
MOD:Lang("en", {
	sa_timeline = "Timeline",
	sa_play = "Play / pause (Space)", sa_first = "To the first frame (Home)", sa_last = "To the last frame (End)",
	sa_prev_key = "Previous key", sa_next_key = "Next key",
	sa_prev_frame = "Previous frame (,)", sa_next_frame = "Next frame (.)",
	sa_key = "Set key for the selection (K)", sa_key_all = "Set key for every object",
	sa_key_delete = "Delete key", sa_autokey = "Auto key: every edit sets a key at the current frame",
	sa_loop = "Loop playback", sa_frame = "frame", sa_fps = "fps", sa_length = "length, s",
	sa_import = "Import model animation…", sa_render = "Render animation…",
	sa_menu = "Animation", sa_clear_track = "Remove animation of this object", sa_clear_all = "Remove all animation",
	sa_clear_all_q = "Remove all keys of all objects?",
	sa_ease = "Motion to the next key", sa_ease_ease = "Smooth", sa_ease_linear = "Linear", sa_ease_hold = "Hold (jump)",
	sa_copy_key = "Copy key", sa_paste_key = "Paste key here", sa_key_here = "Set key here",
	sa_no_tracks = "No animation yet. Select an object, move the playhead and press K — or switch Auto key on.",
	sa_need_sel = "Select an object first", sa_need_ragdoll = "Select a character (ragdoll)",
	sa_key_set = "Key set: frame %d", sa_keys_limit = "Too many keys for one object",
	sa_status = "Animation: frame %d / %d  ·  %s",
	sa_status_play = "playing", sa_status_stop = "stopped", sa_status_auto = "AUTO KEY",
	sa_hk_play = "Play / pause the animation", sa_hk_key = "Set a key for the selection",
	sa_hk_prev = "Previous frame", sa_hk_next = "Next frame", sa_hk_first = "First frame", sa_hk_last = "Last frame",
	sa_imp_title = "Import model animation", sa_imp_search = "Search animations…",
	sa_imp_hint = "The animation of the model is baked into keys of the selected character, starting at the current frame.",
	sa_imp_step = "Key every N frames", sa_imp_loops = "Repeats", sa_imp_root = "Move the character along (root motion)",
	sa_imp_speed = "Speed", sa_imp_go = "Import", sa_imp_none = "This model has no animations",
	sa_imp_done = "Imported '%s': %d keys", sa_imp_col_name = "Animation", sa_imp_col_len = "Length, s",
	sa_imp_extend = "The animation is longer than the timeline: its length was increased.",
	sa_imp_src_own = "Animations of this model", sa_imp_src_male = "Player animations (male)",
	sa_imp_src_female = "Player animations (female)", sa_imp_src_zombie = "Player animations (zombie)",
	sa_imp_src_path = "Animations of another model…", sa_imp_src_prompt = "Path of a model with the same skeleton (models/….mdl):",
	sa_imp_src_tip = "A character can take the animations of another model with the same skeleton: a citizen can use the gestures and dances of the player models and of animation packs made for them.",
	sa_imp_skeleton = "This model has another skeleton: its animation does not fit the character",
	sa_imp_done_n = "Imported '%s' for %s characters",
	sa_rnd_title = "Render animation", sa_rnd_camera = "Camera",
	sa_rnd_from = "From frame", sa_rnd_to = "To frame", sa_rnd_name = "Name", sa_rnd_format = "Format",
	sa_rnd_settle = "Longest wait for the scene, s",
	sa_rnd_settle_tip = "The scene is moved by the server. A frame is taken as soon as every object has stopped on the client; this is the longest the render waits for that.",
	sa_rnd_go = "Render", sa_rnd_cancel = "Cancel",
	sa_rnd_hint = "Frames are saved as separate pictures to garrysmod/data/speditor/renders/<name>/. Picture size, smoothing, depth of field and camera effects are taken from the Render window.",
	sa_rnd_progress = "Rendering frame %d of %d…", sa_rnd_done = "Animation rendered: %d frames in %s",
	sa_rnd_stopped = "Animation render stopped", sa_rnd_busy = "An animation render is already running",
	sa_rnd_failed = "Could not create the video file", sa_rnd_done_avi = "Animation rendered: %d frames, video %s (remove '.dat' from the name)",
	sa_fmt_avi = "AVI video (MJPEG)", sa_fmt_jpeg = "JPEG frames (for MP4)", sa_fmt_png = "PNG frames",
	sa_rd_title = "Animated scene: %d frames, %.2f s, %d fps",
	sa_rd_what = "Render", sa_rd_anim = "The whole animation", sa_rd_frame = "Only the current frame",
	sa_rd_format = "Video format", sa_rd_button = "Render animation", sa_rd_stop = "Stop the animation render",
	sa_rd_note_avi = "One video file: garrysmod/data/speditor/renders/<name>.avi.dat. The game lets addons write only a few file types, so remove '.dat' from the name — it is a regular AVI that any player opens.",
	sa_rd_note_jpeg = "Frames go to garrysmod/data/speditor/renders/<name>/. The game cannot write MP4 itself; the ffmpeg command that turns the frames into MP4 is printed to the console after the render.",
	sa_rd_note_png = "Lossless frames in garrysmod/data/speditor/renders/<name>/ — for editing in a video editor.",
	sa_rd_note_frame = "The Render button saves one picture of the current frame, as in a still scene.",
	sa_rnd_video = "To make a video: ffmpeg -framerate %d -i %s_%%04d.%s%s -pix_fmt yuv420p %s.mp4",
	hist_sa_key = "Keyframe", hist_sa_key_delete = "Delete key", hist_sa_key_move = "Move key", hist_sa_ease = "Key motion",
	hist_sa_clear = "Remove animation", hist_sa_import = "Import animation", hist_sa_paste = "Paste key",
	hist_sa_sound = "Sound", hist_sa_effect = "Effect playback",
	sa_fx_play = "Play the effect from this frame", sa_fx_to_end = "Until the end of the animation",
	sa_fx_for = "For %.2f s, then off",
	sa_rnd_fx_live = "Effects that play by themselves (%d) cannot be rendered frame by frame: in the video they run at their own speed. Use particle effects for exact frames.",
	-- a0.3: sounds and voices, faster animation render
	sa_snd_add = "Add a sound or a voice line…", sa_snd_title = "Sounds and voices",
	sa_snd_root_game = "Game sounds", sa_snd_root_user = "My files",
	sa_snd_up = "Up", sa_snd_filter = "Filter this folder…", sa_snd_col_name = "Name",
	sa_snd_preview = "Listen", sa_snd_stop = "Stop",
	sa_snd_attach = "Comes from the selected object (spatial sound)",
	sa_snd_voice = "Voice: comes from the character's head",
	sa_snd_go = "Add at the current frame",
	sa_snd_hint = "A sound is placed on the timeline at the current frame. A spatial sound gets quieter with distance from the camera and moves between left and right as the object or the camera moves. Your own files (WAV, MP3, OGG) go to garrysmod/data/speditor/sounds/. Only uncompressed WAV gets into the rendered video.",
	sa_snd_added = "Sound added: %s, frame %d", sa_snd_limit = "Too many sounds in one animation",
	sa_snd_failed = "Could not load the sound: %s",
	sa_snd_everywhere = "everywhere", sa_snd_voice_tag = "voice",
	sa_snd_m_emitter = "Comes from", sa_snd_m_none = "Nowhere: heard everywhere", sa_snd_m_selected = "The selected object",
	sa_snd_m_voice = "Voice (from the head)", sa_snd_m_volume = "Volume", sa_snd_m_pitch = "Speed and pitch",
	sa_snd_m_dist = "Distance of full volume", sa_snd_m_here = "Start at the current frame",
	sa_snd_m_dup = "Duplicate", sa_snd_m_delete = "Remove the sound", sa_snd_m_listen = "Listen",
	sa_snd_m_split = "Cut in two at the playhead", sa_snd_m_trim_in = "Trim the start to the playhead",
	sa_snd_m_trim_out = "Trim the end to the playhead", sa_snd_m_untrim = "Restore the whole sound",
	sa_snd_trim_bad = "The playhead is not inside this sound",
	sa_snd_skipped = "Sounds left out of the video (only uncompressed WAV can be mixed in): %s",
	sa_snd_wav = "The sound track is saved next to the frames: %s",
	sa_rd_quality = "Video size", sa_rd_samples = "Shadow / DoF passes",
	sa_rd_samples_100 = "All, as in a still", sa_rd_samples_50 = "Half (faster)", sa_rd_samples_25 = "Quarter (fastest)",
	sa_rnd_part = "The video is larger than 1.9 GB: it continues in %s",
	sa_rd_q_100 = "Largest: JPEG 100 (7 times larger)", sa_rd_q_90 = "Normal: JPEG 90", sa_rd_q_70 = "Smaller by 40%: JPEG 70",
	sa_rd_q_50 = "Smaller by 65%: JPEG 50", sa_rd_q_30 = "Smallest, by 80%: JPEG 30",
	sa_rnd_size = "Video: %.1f MB, %.2f MB per second. Frames repeated without change: %d.",
	sa_rnd_mp4 = "The game can only write MJPEG video. To make it several times smaller without visible loss: ffmpeg -i %s -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac %s.mp4",
})

MOD:Lang("ru", {
	sa_timeline = "Таймлайн",
	sa_play = "Воспроизвести / пауза (Пробел)", sa_first = "К первому кадру (Home)", sa_last = "К последнему кадру (End)",
	sa_prev_key = "Предыдущий ключ", sa_next_key = "Следующий ключ",
	sa_prev_frame = "Предыдущий кадр (,)", sa_next_frame = "Следующий кадр (.)",
	sa_key = "Поставить ключ выделенному (K)", sa_key_all = "Поставить ключ всем объектам",
	sa_key_delete = "Удалить ключ", sa_autokey = "Автоключ: каждая правка ставит ключ на текущем кадре",
	sa_loop = "Повторять по кругу", sa_frame = "кадр", sa_fps = "к/с", sa_length = "длина, с",
	sa_import = "Импорт анимации модели…", sa_render = "Рендер анимации…",
	sa_menu = "Анимация", sa_clear_track = "Убрать анимацию этого объекта", sa_clear_all = "Убрать всю анимацию",
	sa_clear_all_q = "Удалить все ключи всех объектов?",
	sa_ease = "Движение к следующему ключу", sa_ease_ease = "Плавно", sa_ease_linear = "Равномерно", sa_ease_hold = "Скачком",
	sa_copy_key = "Копировать ключ", sa_paste_key = "Вставить ключ сюда", sa_key_here = "Поставить ключ здесь",
	sa_no_tracks = "Анимации пока нет. Выделите объект, передвиньте указатель кадра и нажмите K — или включите автоключ.",
	sa_need_sel = "Сначала выделите объект", sa_need_ragdoll = "Выделите персонажа (рэгдолл)",
	sa_key_set = "Ключ поставлен: кадр %d", sa_keys_limit = "Слишком много ключей у одного объекта",
	sa_status = "Анимация: кадр %d / %d  ·  %s",
	sa_status_play = "идёт", sa_status_stop = "стоп", sa_status_auto = "АВТОКЛЮЧ",
	sa_hk_play = "Воспроизвести / остановить анимацию", sa_hk_key = "Поставить ключ выделенному",
	sa_hk_prev = "Предыдущий кадр", sa_hk_next = "Следующий кадр", sa_hk_first = "Первый кадр", sa_hk_last = "Последний кадр",
	sa_imp_title = "Импорт анимации модели", sa_imp_search = "Поиск анимаций…",
	sa_imp_hint = "Анимация модели запекается в ключи выделенного персонажа, начиная с текущего кадра.",
	sa_imp_step = "Ключ каждые N кадров", sa_imp_loops = "Повторов", sa_imp_root = "Двигать персонажа (перемещение из анимации)",
	sa_imp_speed = "Скорость", sa_imp_go = "Импортировать", sa_imp_none = "У этой модели нет анимаций",
	sa_imp_done = "Импортировано «%s»: ключей — %d", sa_imp_col_name = "Анимация", sa_imp_col_len = "Длина, с",
	sa_imp_extend = "Анимация длиннее таймлайна: его длина увеличена.",
	sa_imp_src_own = "Анимации этой модели", sa_imp_src_male = "Анимации игрока (мужские)",
	sa_imp_src_female = "Анимации игрока (женские)", sa_imp_src_zombie = "Анимации игрока (зомби)",
	sa_imp_src_path = "Анимации другой модели…", sa_imp_src_prompt = "Путь к модели с таким же скелетом (models/….mdl):",
	sa_imp_src_tip = "Персонаж может взять анимации другой модели с таким же скелетом: горожанин — жесты и танцы моделей игроков и наборов анимаций, сделанных для них.",
	sa_imp_skeleton = "У этой модели другой скелет: её анимация не подходит персонажу",
	sa_imp_done_n = "Импортировано «%s» для персонажей: %s",
	sa_rnd_title = "Рендер анимации", sa_rnd_camera = "Камера",
	sa_rnd_from = "С кадра", sa_rnd_to = "По кадр", sa_rnd_name = "Имя", sa_rnd_format = "Формат",
	sa_rnd_settle = "Ждать сцену не дольше, с",
	sa_rnd_settle_tip = "Сцену двигает сервер. Кадр снимается, как только все объекты встали на место у клиента; это наибольшее время такого ожидания.",
	sa_rnd_go = "Рендер", sa_rnd_cancel = "Отмена",
	sa_rnd_hint = "Кадры сохраняются отдельными картинками в garrysmod/data/speditor/renders/<имя>/. Размер кадра, сглаживание, глубина резкости и эффекты камеры берутся из окна «Рендер».",
	sa_rnd_progress = "Рендер кадра %d из %d…", sa_rnd_done = "Анимация снята: кадров — %d, папка %s",
	sa_rnd_stopped = "Рендер анимации остановлен", sa_rnd_busy = "Рендер анимации уже идёт",
	sa_rnd_failed = "Не удалось создать видеофайл", sa_rnd_done_avi = "Анимация снята: кадров — %d, видео %s (уберите «.dat» из имени)",
	sa_fmt_avi = "Видео AVI (MJPEG)", sa_fmt_jpeg = "Кадры JPEG (для MP4)", sa_fmt_png = "Кадры PNG",
	sa_rd_title = "Анимированная сцена: кадров — %d, %.2f с, %d к/с",
	sa_rd_what = "Снимать", sa_rd_anim = "Всю анимацию", sa_rd_frame = "Только текущий кадр",
	sa_rd_format = "Формат видео", sa_rd_button = "Рендер анимации", sa_rd_stop = "Остановить рендер анимации",
	sa_rd_note_avi = "Один видеофайл: garrysmod/data/speditor/renders/<имя>.avi.dat. Игра разрешает аддонам создавать файлы только нескольких типов, поэтому уберите «.dat» из имени — это обычный AVI, его открывает любой проигрыватель.",
	sa_rd_note_jpeg = "Кадры сохраняются в garrysmod/data/speditor/renders/<имя>/. Записать MP4 сама игра не может; команда ffmpeg, которая соберёт из кадров MP4, печатается в консоль после рендера.",
	sa_rd_note_png = "Кадры без потерь в garrysmod/data/speditor/renders/<имя>/ — для монтажа в видеоредакторе.",
	sa_rd_note_frame = "Кнопка «Рендер» сохранит одну картинку текущего кадра, как у неподвижной сцены.",
	sa_rnd_video = "Собрать видео: ffmpeg -framerate %d -i %s_%%04d.%s%s -pix_fmt yuv420p %s.mp4",
	hist_sa_key = "Ключевой кадр", hist_sa_key_delete = "Удаление ключа", hist_sa_key_move = "Перенос ключа", hist_sa_ease = "Движение ключа",
	hist_sa_clear = "Удаление анимации", hist_sa_import = "Импорт анимации", hist_sa_paste = "Вставка ключа",
	hist_sa_sound = "Звук", hist_sa_effect = "Проигрывание эффекта",
	sa_fx_play = "Проиграть эффект с этого кадра", sa_fx_to_end = "До конца анимации",
	sa_fx_for = "В течение %.2f с, затем выключить",
	sa_rnd_fx_live = "Эффекты, которые проигрываются сами (%d), нельзя снять покадрово: в видео они идут со своей скоростью. Для точных кадров берите эффекты из частиц.",
	-- a0.3: sounds and voices, faster animation render
	sa_snd_add = "Добавить звук или голос…", sa_snd_title = "Звуки и голоса",
	sa_snd_root_game = "Звуки игры", sa_snd_root_user = "Мои файлы",
	sa_snd_up = "Вверх", sa_snd_filter = "Фильтр по этой папке…", sa_snd_col_name = "Имя",
	sa_snd_preview = "Прослушать", sa_snd_stop = "Стоп",
	sa_snd_attach = "Идёт от выделенного объекта (пространственный звук)",
	sa_snd_voice = "Голос: идёт от головы персонажа",
	sa_snd_go = "Добавить на текущий кадр",
	sa_snd_hint = "Звук ставится на таймлайн с текущего кадра. Пространственный звук становится тише с расстоянием до камеры и переходит между левым и правым каналом, когда движется объект или камера. Свои файлы (WAV, MP3, OGG) кладите в garrysmod/data/speditor/sounds/. В снятое видео попадает только несжатый WAV.",
	sa_snd_added = "Звук добавлен: %s, кадр %d", sa_snd_limit = "Слишком много звуков в одной анимации",
	sa_snd_failed = "Не удалось загрузить звук: %s",
	sa_snd_everywhere = "везде", sa_snd_voice_tag = "голос",
	sa_snd_m_emitter = "Откуда идёт", sa_snd_m_none = "Ниоткуда: слышен везде", sa_snd_m_selected = "Выделенный объект",
	sa_snd_m_voice = "Голос (от головы)", sa_snd_m_volume = "Громкость", sa_snd_m_pitch = "Скорость и высота",
	sa_snd_m_dist = "Расстояние полной громкости", sa_snd_m_here = "Начать с текущего кадра",
	sa_snd_m_dup = "Дублировать", sa_snd_m_delete = "Убрать звук", sa_snd_m_listen = "Прослушать",
	sa_snd_m_split = "Разрезать по курсору", sa_snd_m_trim_in = "Обрезать начало до курсора",
	sa_snd_m_trim_out = "Обрезать конец от курсора", sa_snd_m_untrim = "Вернуть звук целиком",
	sa_snd_trim_bad = "Курсор не внутри этого звука",
	sa_snd_skipped = "Звуки, не попавшие в видео (подмешать можно только несжатый WAV): %s",
	sa_snd_wav = "Звуковая дорожка сохранена рядом с кадрами: %s",
	sa_rd_quality = "Размер видео", sa_rd_samples = "Проходы теней и ГРИП",
	sa_rd_samples_100 = "Все, как в одном кадре", sa_rd_samples_50 = "Половина (быстрее)", sa_rd_samples_25 = "Четверть (ещё быстрее)",
	sa_rnd_part = "Видео больше 1,9 ГБ: продолжение в %s",
	sa_rd_q_100 = "Самое большое: JPEG 100 (в 7 раз больше)", sa_rd_q_90 = "Обычное: JPEG 90", sa_rd_q_70 = "Меньше на 40%: JPEG 70",
	sa_rd_q_50 = "Меньше на 65%: JPEG 50", sa_rd_q_30 = "Самое маленькое, на 80%: JPEG 30",
	sa_rnd_size = "Видео: %.1f МБ, %.2f МБ в секунду. Кадров, повторённых без изменений: %d.",
	sa_rnd_mp4 = "Игра умеет писать только видео MJPEG. Сделать его в несколько раз меньше без видимых потерь: ffmpeg -i %s -c:v libx264 -crf 18 -pix_fmt yuv420p -c:a aac %s.mp4",
})
