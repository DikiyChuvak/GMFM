# Моды для SPeditor

SPeditor — редактор неподвижных сцен. Всё, что выходит за эту задачу (анимация,
свои инструменты, экспорт в другие форматы), делается **модами**: мод дополняет
редактор изнутри — добавляет страницы в его окна, пункты в его меню, свои
горячие клавиши — и не требует отдельного окна или отдельной программы.

Первый мод встроен в SPeditor и служит рабочим примером:
`lua/speditor_mods/saeditor` — **SAeditor** (Source Animation Editor), покадровая
анимация с таймлайном.

Версия API: **1** (SPeditor a0.2). Номер лежит в `SPeditor.API`.

---

## 1. Где лежит мод

Игра загружает Lua только из папок `lua/`, поэтому мод — это папка

```
garrysmod/addons/<ваш_аддон>/lua/speditor_mods/<id>/
    mod.lua            описание мода (обязательно)
    sh_<id>.lua        общий код
    sv_<id>.lua        сервер
    cl_<id>.lua        клиент
```

`<id>` — латинские буквы, цифры и `_`. Папка может быть в самом SPeditor
(встроенные моды) или в любом другом аддоне: игра склеивает `lua/`-папки всех
аддонов в одну. Для мастерской Steam мод публикуется как обычный аддон, в
зависимостях указывается SPeditor.

Папка, имя которой начинается с `_`, не загружается.

Папка `mods/` в исходниках SPeditor — только документация: Lua оттуда игра не
видит, и в мастерскую она не попадает. Это же руководство сохраняется из игры:
**Окна → Моды → Сохранить руководство** (файлы появятся в
`garrysmod/data/speditor/`).

### Быстрый старт

В консоли игры:

```
speditor_mod_template mytool
```

или в редакторе: **Окна → Моды → Записать заготовку мода**. В
`garrysmod/data/speditor/mod_template/mytool/` появятся готовые файлы (игра
разрешает писать только `.txt`, поэтому у них двойное расширение). Скопируйте их
в `addons/<ваш_аддон>/lua/speditor_mods/mytool/`, уберите `.txt` и перезагрузите
карту. Мод появится в окне «Моды».

---

## 2. mod.lua

Файл выполняется на сервере и на клиенте и возвращает таблицу:

```lua
return {
    name        = "My tool",
    version     = "1.0",
    author      = "me",
    description = { en = "What it does.", ru = "Что он делает." },   -- или одна строка
    api         = 1,                    -- версия API, для которой написан мод
    net         = { "Hello", "Data" },  -- сетевые сообщения мода
    shared      = { "sh_mytool.lua" },  -- сервер и клиент
    server      = { "sv_mytool.lua" },  -- только сервер
    client      = { "cl_mytool.lua" },  -- только клиент (сервер отправит файл игрокам сам)
}
```

Порядок загрузки: `shared`, затем `server` или `client`, внутри списка — как
написано. Моды загружаются после всего SPeditor, поэтому `SPeditor.Client`,
`SPeditor.UI`, `SPeditor.Server` уже существуют. Если `api` мода больше, чем
`SPeditor.API`, мод не загружается и в окне «Моды» помечается «нужен SPeditor
новее».

Каждый файл мода начинается одинаково:

```lua
local MOD = SPeditor.Mod("mytool")
```

`MOD` — объект мода. В нём удобно держать и своё состояние: `MOD.state = MOD.state or {}`
(так оно переживает автообновление файла при разработке).

---

## 3. Что умеет объект мода

### Общее (сервер и клиент)

| Вызов | Что делает |
|---|---|
| `MOD:Lang("ru", { mytool_title = "…" })` | Добавляет строки в словарь редактора. Ключи начинайте с id мода. |
| `MOD:L("mytool_title")`, `MOD:L(key, a, b)` | Строка на языке интерфейса; с аргументами — через `string.format`. |
| `MOD:Hook(event, fn [, name])` | `hook.Add` с именем, уникальным для мода. |
| `MOD:NetStart("Hello")` | `net.Start` сообщения мода. Дальше — обычные `net.Write…` и `net.Send` / `net.SendToServer`. |
| `MOD:NetReceive("Hello", fn [, noActive])` | Приём сообщения. На сервере `fn(ply)`, на клиенте `fn()`. |
| `MOD:DataDir()` | Папка мода в `garrysmod/data`: `speditor/mods/<id>` (создаётся). |
| `MOD:Print(...)` | Сообщение в консоль с именем мода. |

Сообщения перечисляются в `net` файла `mod.lua` — сервер регистрирует их сам.
На сервере `MOD:NetReceive` вызывает ваш обработчик только если у игрока есть
доступ к SPeditor (`SPeditor.CanUse`) и редактор у него открыт; частота сообщений
ограничена, как у самого редактора. `noActive = true` снимает условие «редактор
открыт». **Проверять данные из сообщения всё равно нужно самим**: числа — через
`SPeditor.Clamp`, векторы — `SPeditor.ValidVec`, объекты — `S.ReadOwned(ply)`.

### Сервер

```lua
local S = SPeditor.Server

-- объект редактора, принадлежащий игроку (или nil): читает net.ReadEntity()
local ent = S.ReadOwned(ply)

-- данные мода в файле сцены
MOD:SceneData(
    function(ply, ctx)            -- сохранение: вернуть таблицу или nil
        return { note = "hi", target = ctx.indexOf[someEnt] }
    end,
    function(ply, data, ctx)      -- загрузка: data = nil, если мода в сцене не было
        local ent = data and ctx.ents[data.target]
    end)
```

В файле сцены объекты нумеруются по порядку; `ctx.indexOf[ent]` — номер объекта,
`ctx.ents[номер]` — объект. UID объектов (`ent.SPeditor_UID`) живут только в
пределах сессии, зато не меняются при удалении и отмене удаления.

Полезные функции сервера (`lua/speditor/sv_speditor.lua`):

| Функция | Назначение |
|---|---|
| `S.List(ply)` | Все объекты редактора игрока. |
| `S.FindUID(ply, uid)` | Объект по UID. |
| `S.IsRagdoll / S.IsLight / S.IsCamera / S.IsEffect / S.IsAux(ent)` | Вид объекта. |
| `S.GetTransform(ent)`, `S.SetTransform(ent, pos, ang)` | Положение (у рэгдолла — корня, вместе со всей позой). |
| `S.CapturePose(ent)`, `S.ApplyPose(ent, pose)` | Поза целиком (кости, мимика, взгляд). |
| `S.SpawnModel`, `S.SpawnLight`, `S.SpawnCamera` | Создание объектов. |
| `S.Notice(ply, "#ключ_словаря|арг", kind)` | Уведомление игроку (0 сведения, 1 ошибка, 2 успех, 3 тихое). |

Хуки сервера:

| Хук | Когда |
|---|---|
| `SPeditor_CanUse(ply)` | Вернуть `true` / `false`, чтобы решить, кому доступен редактор. |
| `SPeditor_PlayerState(ply, on)` | Игрок открыл или закрыл редактор. |
| `SPeditor_PlayerCleanup(ply)` | Сцена игрока очищена (кнопка «Очистить», загрузка другой сцены, выход). |

### Клиент

```lua
local C, UI = SPeditor.Client, SPeditor.UI
```

**Страница в окне редактора**

```lua
MOD:AddPage({
    id = "mytool", titleKey = "mytool_title", icon = "icon16/plugin.png",   -- или title = "готовая строка"
    window = "bottom",            -- "bottom" | "left" | "float"
    build = function(panel, win)  -- вызывается при каждом открытии редактора
        UI.Button(panel, "Нажми", "icon16/accept.png", function() … end)
    end,
})
```

`"bottom"` — вкладка нижнего окна (рядом со «Сценой» и «Тенями»), `"left"` —
рядом с Animation Set Editor, `"float"` — отдельное плавающее окно. Страница сама
попадает в меню «Окна»; как любую вкладку редактора, её можно оторвать,
пристыковать и сохранить в раскладке. Виджеты редактора (`cl_ui_theme.lua`):
`UI.Button`, `UI.IconButton`, `UI.Slider`, `UI.Check`, `UI.Label`, `UI.Section`,
`UI.Control` (ползунок как в Animation Set Editor), `UI.ToggleRow`, `UI.Menu()`,
цвета темы — `UI.PAL`.

**Меню**

```lua
MOD:AddMenu("object", function(menu, ent)        -- меню объекта (правый щелчок)
    menu:AddOption("Моё действие", function() … end)
end)
MOD:AddMenu("file", function(menu) … end)
```

Места: `"file"`, `"edit"`, `"windows"`, `"view"`, `"help"` — меню верхней
полосы; `"create"` — меню «+» (создание объектов); `"object"` — меню объекта.

**Горячие клавиши и строка состояния**

```lua
MOD:AddHotkey({ key = KEY_K, ctrl = false, shift = false, fn = function() … end,
                desc = "mytool_hotkey" })      -- desc — строка для окна «Горячие клавиши»
MOD:AddStatus(function() return "мой текст в строке состояния" end)
```

Клавиши не срабатывают, пока идёт ввод текста или полёт камеры. Занятые
редактором клавиши: `1 2 3 4 F V B I Del`, `Ctrl+Z/Y/D/C/V`; SAeditor занимает
`Пробел K , . Home End`.

**Состояние редактора** (`SPeditor.Client`)

| Поле / функция | Что это |
|---|---|
| `C.active` | Редактор открыт. |
| `C.selected`, `C.SelectionList()` | Выделенный объект; все выделенные. |
| `C.Select(ent)` | Выделить. |
| `C.Objects()`, `C.BuildEntityList()` | Объекты игрока; они же с именами. |
| `C.IsRagdoll / C.IsLight / C.IsCamera / C.IsEffect / C.IsAux(ent)` | Вид объекта. |
| `C.DisplayName(ent)` | Имя, как в списке объектов. |
| `C.GetEntityTransform(ent)`, `C.CenterOf(ent)` | Положение объекта. |
| `C.SendTransform(ent, pos, ang, now)` | Передвинуть объект. |
| `C.SendLightEdit`, `C.SendCameraEdit`, `C.EditLook`, `C.SendPhysBones` … | Правки объектов (`cl_net.lua`). |
| `C.PushHistory(label, undoFn, redoFn)` | Запись в историю отмены. Подпись — ключ словаря `hist_<label>`. |
| `C.Queue(key, fn)` | Отправка не чаще 25 раз в секунду (для ползунков). |
| `C.GetView()`, `C.GetViewCamera()` | Вид основного вьюпорта; камера сцены, через которую смотрят. |
| `C.vpPass`, `C.hideUI` | Какой вид рисуется сейчас (`"primary"`, `"secondary"`, `"export"`); идёт ли рендер. |
| `SPeditor.Notify(text, kind)` | Уведомление. |
| `SPeditor.Export.Render{ camera, name, dir, format, quality, silent, onDone, capture, warmup, sampleScale }` | Рендер кадра в файл. `capture = function(data, W, H)` получает закодированный кадр вместо записи в файл; `warmup` — сколько игровых кадров пропустить в режиме «Кадр движка»; `sampleScale` (0..1) — доля проходов мягких теней и глубины резкости (для серий кадров). |

Хуки клиента:

| Хук | Когда |
|---|---|
| `SPeditor_StateChanged(on)` | Редактор открыт или закрыт. |
| `SPeditor_UIBuilt()` | Окна редактора построены (открытие, смена темы). |
| `SPeditor_Selected(ent, bone)`, `SPeditor_MultiChanged()` | Изменилось выделение. |
| `SPeditor_ObjectSpawned(ent)` | Создан объект. |
| `SPeditor_SceneLoaded(meta)`, `SPeditor_SceneList(list)` | Сцена загружена; получен список сцен. |
| `SPeditor_HistoryPushed(label)` | В сцене что-то изменили (появилась запись истории). |
| `SPeditor_HistoryStep(label, isUndo)` | Выполнена отмена или повтор. |
| `SPeditor_ModsLoaded(list)` | Все моды загружены (общий хук). |
| `SPeditor_RenderRequest(opts)` | Нажали «Рендер». Верните `true`, если мод снимает сцену сам (SAeditor — анимацию). Свои вызовы `SPeditor.Export.Render` делайте с `single = true`, иначе хук вызовется снова. |
| `SPeditor_RenderDialog(ctx)` | Строится окно «Рендер»: `ctx.body` — колонка настроек (добавляйте панели с `Dock(TOP)`), `ctx.button` — кнопка «Рендер», `ctx.getCamera()` — выбранная камера. |
| `SPeditor_RenderPreviewBuilt(side, pv)` | Строится предпросмотр: в `side` можно добавить свою полосу (`Dock(BOTTOM)`); `pv.next = 0` — переснять предпросмотр сразу. |

**Рисование во вьюпорте.** Используйте обычные хуки отрисовки и проверяйте
проход: помощники рисуются только в редакторе и только в основном вьюпорте.

```lua
MOD:Hook("PostDrawTranslucentRenderables", function(depth, skybox)
    if depth or skybox or not C.active or C.hideUI or C.vpPass ~= "primary" then return end
    local restore = SPeditor.Render.HelperLighting()   -- цвета не ломаются в режиме «без теней»
    render.DrawLine(a, b, color_white, false)
    restore()
end)
```

---

## 4. Правила хорошего мода

* **Не меняйте файлы SPeditor.** Если не хватает хука или функции — напишите в
  обсуждениях, точку расширения добавят в API.
* **Сервер не доверяет клиенту.** Всё, что пришло по сети, проверяется:
  диапазоны чисел, принадлежность объекта игроку, длина строк и таблиц.
* **Файл должен переживать повторную загрузку** (Lua autorefresh): состояние
  храните как `MOD.x = MOD.x or …`, хуки добавляйте через `MOD:Hook`.
* **Ключи словаря, имена сообщений, переменные консоли** начинайте с id мода.
* **Строки интерфейса — на двух языках** (`en` обязательно; если ключа нет в
  выбранном языке, берётся английский).
* **Сцена остаётся сценой.** Данные мода в файле сцены — через `MOD:SceneData`;
  сцена должна открываться и без вашего мода.
* **Правки — в историю.** Всё, что меняет сцену, должно отменяться (`C.PushHistory`).

---

## 5. Разбор примера: SAeditor

| Файл | Что в нём |
|---|---|
| `mod.lua` | Описание, десять сетевых сообщений. |
| `sh_saeditor.lua` | Общие константы, интерполяция поворотов, строки на двух языках. |
| `sv_saeditor.lua` | Хранение анимации, снимок и применение состояния объектов, воспроизведение (хук `Think`), отмена, данные в файле сцены (`MOD:SceneData`). |
| `cl_saeditor.lua` | Состояние таймлайна, команды серверу, автоключ (хук `SPeditor_HistoryPushed`), горячие клавиши, импорт анимаций модели, рендер серии кадров (`SPeditor.Export.Render` с `onDone`). |
| `cl_saeditor_video.lua` | Рендер анимации: перехват кнопки «Рендер» (хук `SPeditor_RenderRequest`), запись видео AVI со звуковой дорожкой. |
| `cl_saeditor_sound.lua` | Звуки и голоса: клипы на таймлайне, пространственное воспроизведение, сведение звуковой дорожки видео, окно выбора звуков. |

Персонажа можно анимировать из скрипта: `SA.ImportSequence(ent, seq, { start = кадр, frames = длина, pos = Vector, yaw = градусы, loops, step, root, cycle0, cycle1, params = { aim_yaw = 0 } })` запекает анимацию модели в ключи рэгдолла на точном кадре, в точном месте и направлении. На сервере `S.RigidPlaces` / `S.SnapRigid` ставят тела рэгдолла туда, где клиент рисует его кости, — используйте их, если ваш мод задаёт позы рэгдоллам и прикрепляет к ним объекты.
| `cl_saeditor_ui.lua` | Страница «Таймлайн» (`MOD:AddPage`, окно `bottom`), окна импорта и рендера, пункты меню (`MOD:AddMenu`), раздел в окне «Рендер» и кнопки воспроизведения в предпросмотре (хуки `SPeditor_RenderDialog`, `SPeditor_RenderPreviewBuilt`). |
| `cl_saeditor_lipsync.lua` | Липсинк: фонемы из блока VDAT в WAV или громкость звука, отправляются как формы рта (сообщение `Lip`); `SA.MouthMap(ent)` в `sh_saeditor.lua` находит флексы рта модели. |
| `cl_saeditor_show.lua` | Просмотр анимации вне редактора (сообщение `Show` с действиями пуск / пауза / перемотка, работает с закрытым редактором): вид через камеру смен или выбранную камеру, консольные команды `saeditor_show*`, панель в Q-меню. |
| `cl_saeditor_player.lua` | Плеер вне редактора в стиле Windows Media Player: пуск / пауза, стоп, предыдущий / следующий план, перемотка, повтор, громкость (`SA.OpenPlayer`). |
| `cl_saeditor_cuts.lua` | Смены камер — через какую камеру смотреть анимацию с какого кадра (`SA.cuts`, `SA.CameraAt(frame)`, сообщение `Cuts`); строка «Камеры» на таймлайне. |
| `cl_saeditor_ghost.lua` | Призраки: выделенная модель полупрозрачно на ключах вокруг головки (сообщение `Ghost`, `SA.StateAt` на сервере). |
| `cl_saeditor_record.lua`, `sv_saeditor_record.lua` | Запись игры (машинима): окно записи, отсчёт и метка REC (клиент); дубль — кости игрока и NPC снимаются на сервере, звуки (`EntityEmitSound`), трассеры, взрывы, `util.Effect` — превращается в рэгдоллы с ключами, прикреплённое оружие, звуковые клипы и объекты-эффекты (сообщение `Rec`). |
| `cl_saeditor_guides.lua` | Статьи SAeditor в Справка → Как пользоваться (`UI.AddGuide` в `cl_ui_guide.lua`; мод может так же добавить свои статьи с картинками и живыми демонстрациями). |
| `cl_saeditor_easy.lua` | Готовые движения персонажей (`SA.MOTIONS`, `SA.PlayMotion`) и пролёты камеры (`SA.CAM_MOVES`, сообщение `Cam`). |

На что обратить внимание:

* анимация хранится **на сервере** — там же, где объекты, которые она двигает;
  клиенту уходит только оглавление для таймлайна;
* каждая правка ключей — одна запись истории редактора: клиент придумывает номер
  операции, сервер запоминает дорожки до и после неё;
* в файле сцены объекты заменены номерами (`ctx.indexOf`), а при загрузке
  данные проверяются поле за полем.

---

## 6. Выключение модов

Окно «Моды» → снять «Включён», либо серверная переменная:

```
speditor_mods_off "saeditor,mytool"
```

Изменение действует после перезагрузки карты.
