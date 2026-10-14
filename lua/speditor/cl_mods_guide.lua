-- Guide for mod authors. THIS FILE IS GENERATED from mods/README_ru.md and
-- mods/README_en.md by mods/build_guide.py — edit those, not this file.
SPeditor = SPeditor or {}
SPeditor.ModGuide = {}

SPeditor.ModGuide.ru = [===[
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
]===]

SPeditor.ModGuide.en = [===[
# Mods for SPeditor

SPeditor is an editor for still scenes. Everything beyond that job (animation,
your own tools, export to other formats) is done by **mods**: a mod extends the
editor from the inside — it adds pages to its windows, items to its menus, its
own hotkeys — and needs no separate window or program.

The first mod is built into SPeditor and doubles as a working example:
`lua/speditor_mods/saeditor` — **SAeditor** (Source Animation Editor), keyframe
animation with a timeline.

API version: **1** (SPeditor a0.2). The number is in `SPeditor.API`.

---

## 1. Where a mod lives

The game loads Lua only from `lua/` folders, so a mod is the folder

```
garrysmod/addons/<your_addon>/lua/speditor_mods/<id>/
    mod.lua            mod description (required)
    sh_<id>.lua        shared code
    sv_<id>.lua        server
    cl_<id>.lua        client
```

`<id>` — Latin letters, digits and `_`. The folder may be inside SPeditor itself
(built-in mods) or inside any other addon: the game merges the `lua/` folders of
all addons into one. For the Steam Workshop a mod is published as a regular
addon with SPeditor listed as a required item.

A folder whose name starts with `_` is not loaded.

The `mods/` folder in SPeditor's sources holds documentation only: the game does
not see Lua there, and it is not uploaded to the Workshop. The same guide can be
saved from the game: **Windows → Mods → Save the guide** (the files appear in
`garrysmod/data/speditor/`).

### Quick start

In the game console:

```
speditor_mod_template mytool
```

or in the editor: **Windows → Mods → Write a mod template**. Ready-made files
appear in `garrysmod/data/speditor/mod_template/mytool/` (the game may only
write `.txt`, hence the double extension). Copy them to
`addons/<your_addon>/lua/speditor_mods/mytool/`, remove `.txt` and restart the
map. The mod shows up in the Mods window.

---

## 2. mod.lua

The file runs on the server and on the client and returns a table:

```lua
return {
    name        = "My tool",
    version     = "1.0",
    author      = "me",
    description = { en = "What it does.", ru = "Что он делает." },   -- or a single string
    api         = 1,                    -- API version the mod is written for
    net         = { "Hello", "Data" },  -- the mod's network messages
    shared      = { "sh_mytool.lua" },  -- server and client
    server      = { "sv_mytool.lua" },  -- server only
    client      = { "cl_mytool.lua" },  -- client only (the server sends the file to players)
}
```

Load order: `shared`, then `server` or `client`; inside a list — as written.
Mods load after all of SPeditor, so `SPeditor.Client`, `SPeditor.UI` and
`SPeditor.Server` already exist. If the mod's `api` is greater than
`SPeditor.API`, the mod is not loaded and the Mods window marks it "needs a newer
SPeditor".

Every file of a mod starts the same way:

```lua
local MOD = SPeditor.Mod("mytool")
```

`MOD` is the mod object. It is a good place for your own state too:
`MOD.state = MOD.state or {}` (this way it survives Lua autorefresh during
development).

---

## 3. What the mod object can do

### Shared (server and client)

| Call | What it does |
|---|---|
| `MOD:Lang("en", { mytool_title = "…" })` | Adds strings to the editor dictionary. Start keys with the mod id. |
| `MOD:L("mytool_title")`, `MOD:L(key, a, b)` | A string in the interface language; with arguments it goes through `string.format`. |
| `MOD:Hook(event, fn [, name])` | `hook.Add` with a name unique to the mod. |
| `MOD:NetStart("Hello")` | `net.Start` for a mod message. Then the usual `net.Write…` and `net.Send` / `net.SendToServer`. |
| `MOD:NetReceive("Hello", fn [, noActive])` | Receives a message. `fn(ply)` on the server, `fn()` on the client. |
| `MOD:DataDir()` | The mod's folder in `garrysmod/data`: `speditor/mods/<id>` (created if missing). |
| `MOD:Print(...)` | A console message tagged with the mod name. |

Messages are listed in `net` of `mod.lua` — the server registers them itself.
On the server `MOD:NetReceive` calls your handler only if the player has access
to SPeditor (`SPeditor.CanUse`) and has the editor open; the message rate is
limited the same way as for the editor's own messages. `noActive = true` drops
the "editor is open" condition. **You still have to validate the data yourself**:
numbers with `SPeditor.Clamp`, vectors with `SPeditor.ValidVec`, objects with
`S.ReadOwned(ply)`.

### Server

```lua
local S = SPeditor.Server

-- an editor object that belongs to the player (or nil): reads net.ReadEntity()
local ent = S.ReadOwned(ply)

-- mod data inside the scene file
MOD:SceneData(
    function(ply, ctx)            -- save: return a table or nil
        return { note = "hi", target = ctx.indexOf[someEnt] }
    end,
    function(ply, data, ctx)      -- load: data = nil if the scene has no data of this mod
        local ent = data and ctx.ents[data.target]
    end)
```

Objects in a scene file are numbered in order; `ctx.indexOf[ent]` is the number
of an object, `ctx.ents[number]` is the object. Object UIDs (`ent.SPeditor_UID`)
live only within a session, but they do survive deletion and undo of deletion.

Useful server functions (`lua/speditor/sv_speditor.lua`):

| Function | Purpose |
|---|---|
| `S.List(ply)` | All editor objects of the player. |
| `S.FindUID(ply, uid)` | Object by UID. |
| `S.IsRagdoll / S.IsLight / S.IsCamera / S.IsEffect / S.IsAux(ent)` | Kind of object. |
| `S.GetTransform(ent)`, `S.SetTransform(ent, pos, ang)` | Position (for a ragdoll — of its root, moving the whole pose). |
| `S.CapturePose(ent)`, `S.ApplyPose(ent, pose)` | The whole pose (bones, face, eyes). |
| `S.SpawnModel`, `S.SpawnLight`, `S.SpawnCamera` | Creating objects. |
| `S.Notice(ply, "#dictionary_key|arg", kind)` | A notification (0 info, 1 error, 2 success, 3 silent). |

Server hooks:

| Hook | When |
|---|---|
| `SPeditor_CanUse(ply)` | Return `true` / `false` to decide who may use the editor. |
| `SPeditor_PlayerState(ply, on)` | The player opened or closed the editor. |
| `SPeditor_PlayerCleanup(ply)` | The player's scene was cleared (Clear Scene, loading another scene, leaving). |

### Client

```lua
local C, UI = SPeditor.Client, SPeditor.UI
```

**A page in an editor window**

```lua
MOD:AddPage({
    id = "mytool", titleKey = "mytool_title", icon = "icon16/plugin.png",   -- or title = "a ready string"
    window = "bottom",            -- "bottom" | "left" | "float"
    build = function(panel, win)  -- called every time the editor opens
        UI.Button(panel, "Press me", "icon16/accept.png", function() … end)
    end,
})
```

`"bottom"` — a tab of the bottom window (next to Scene and Shadows), `"left"` —
next to the Animation Set Editor, `"float"` — a floating window of its own. The
page gets into the Windows menu automatically; like any editor tab it can be torn
off, docked and saved in a layout. Editor widgets (`cl_ui_theme.lua`):
`UI.Button`, `UI.IconButton`, `UI.Slider`, `UI.Check`, `UI.Label`, `UI.Section`,
`UI.Control` (a slider as in the Animation Set Editor), `UI.ToggleRow`,
`UI.Menu()`; theme colours — `UI.PAL`.

**Menus**

```lua
MOD:AddMenu("object", function(menu, ent)        -- object menu (right click)
    menu:AddOption("My action", function() … end)
end)
MOD:AddMenu("file", function(menu) … end)
```

Places: `"file"`, `"edit"`, `"windows"`, `"view"`, `"help"` — menus of the top
bar; `"create"` — the "+" menu (creating objects); `"object"` — the object menu.

**Hotkeys and the status bar**

```lua
MOD:AddHotkey({ key = KEY_K, ctrl = false, shift = false, fn = function() … end,
                desc = "mytool_hotkey" })      -- desc — a line for the Hotkeys window
MOD:AddStatus(function() return "my text in the status bar" end)
```

Keys do not fire while text is being typed or the camera is flying. Keys taken by
the editor: `1 2 3 4 F V B I Del`, `Ctrl+Z/Y/D/C/V`; SAeditor takes
`Space K , . Home End`.

**Editor state** (`SPeditor.Client`)

| Field / function | What it is |
|---|---|
| `C.active` | The editor is open. |
| `C.selected`, `C.SelectionList()` | The selected object; everything selected. |
| `C.Select(ent)` | Select. |
| `C.Objects()`, `C.BuildEntityList()` | The player's objects; the same with names. |
| `C.IsRagdoll / C.IsLight / C.IsCamera / C.IsEffect / C.IsAux(ent)` | Kind of object. |
| `C.DisplayName(ent)` | The name as in the object list. |
| `C.GetEntityTransform(ent)`, `C.CenterOf(ent)` | Position of an object. |
| `C.SendTransform(ent, pos, ang, now)` | Move an object. |
| `C.SendLightEdit`, `C.SendCameraEdit`, `C.EditLook`, `C.SendPhysBones` … | Object edits (`cl_net.lua`). |
| `C.PushHistory(label, undoFn, redoFn)` | An undo history entry. The caption is the dictionary key `hist_<label>`. |
| `C.Queue(key, fn)` | Sending at most 25 times a second (for sliders). |
| `C.GetView()`, `C.GetViewCamera()` | The view of the primary viewport; the scene camera being looked through. |
| `C.vpPass`, `C.hideUI` | Which view is being drawn now (`"primary"`, `"secondary"`, `"export"`); whether a render is in progress. |
| `SPeditor.Notify(text, kind)` | A notification. |
| `SPeditor.Export.Render{ camera, name, dir, format, quality, silent, onDone, capture, warmup, sampleScale }` | Render a frame to a file. `capture = function(data, W, H)` takes the encoded frame instead of a file; `warmup` — game frames skipped in engine frame mode; `sampleScale` (0..1) — part of the soft shadow / depth of field passes (for frame sequences). |

Client hooks:

| Hook | When |
|---|---|
| `SPeditor_StateChanged(on)` | The editor was opened or closed. |
| `SPeditor_UIBuilt()` | The editor windows were built (opening, theme change). |
| `SPeditor_Selected(ent, bone)`, `SPeditor_MultiChanged()` | The selection changed. |
| `SPeditor_ObjectSpawned(ent)` | An object was created. |
| `SPeditor_SceneLoaded(meta)`, `SPeditor_SceneList(list)` | A scene was loaded; the scene list arrived. |
| `SPeditor_HistoryPushed(label)` | Something in the scene was changed (a history entry appeared). |
| `SPeditor_HistoryStep(label, isUndo)` | An undo or redo was performed. |
| `SPeditor_ModsLoaded(list)` | All mods are loaded (shared hook). |
| `SPeditor_RenderRequest(opts)` | Render was pressed. Return `true` if the mod renders the scene itself (SAeditor — the animation). Make your own `SPeditor.Export.Render` calls with `single = true`, otherwise the hook runs again. |
| `SPeditor_RenderDialog(ctx)` | The Render window is being built: `ctx.body` — the settings column (add panels with `Dock(TOP)`), `ctx.button` — the Render button, `ctx.getCamera()` — the chosen camera. |
| `SPeditor_RenderPreviewBuilt(side, pv)` | The preview is being built: add your own bar to `side` (`Dock(BOTTOM)`); `pv.next = 0` re-shoots the preview at once. |

**Drawing in the viewport.** Use the regular drawing hooks and check the pass:
helpers are drawn only in the editor and only in the primary viewport.

```lua
MOD:Hook("PostDrawTranslucentRenderables", function(depth, skybox)
    if depth or skybox or not C.active or C.hideUI or C.vpPass ~= "primary" then return end
    local restore = SPeditor.Render.HelperLighting()   -- keeps colours right in fullbright
    render.DrawLine(a, b, color_white, false)
    restore()
end)
```

---

## 4. Rules of a good mod

* **Do not edit SPeditor's files.** If a hook or a function is missing, write in
  the discussions — the extension point will be added to the API.
* **The server does not trust the client.** Everything that arrives over the
  network is checked: number ranges, object ownership, lengths of strings and tables.
* **A file must survive being loaded again** (Lua autorefresh): keep state as
  `MOD.x = MOD.x or …`, add hooks with `MOD:Hook`.
* **Dictionary keys, message names, console variables** start with the mod id.
* **Interface strings in two languages** (`en` is required; a key missing in the
  chosen language falls back to English).
* **A scene stays a scene.** Mod data goes into the scene file through
  `MOD:SceneData`; the scene must open without your mod as well.
* **Edits go into history.** Everything that changes the scene must be undoable
  (`C.PushHistory`).

---

## 5. The example explained: SAeditor

| File | What is inside |
|---|---|
| `mod.lua` | The description, ten network messages. |
| `sh_saeditor.lua` | Shared constants, rotation interpolation, strings in two languages. |
| `sv_saeditor.lua` | Animation storage, capturing and applying object state, playback (the `Think` hook), undo, data in the scene file (`MOD:SceneData`). |
| `cl_saeditor.lua` | Timeline state, commands to the server, auto key (the `SPeditor_HistoryPushed` hook), hotkeys, model animation import, image sequence render (`SPeditor.Export.Render` with `onDone`). |
| `cl_saeditor_video.lua` | Animation render: taking over the Render button (the `SPeditor_RenderRequest` hook), writing AVI video with a sound track. |
| `cl_saeditor_sound.lua` | Sounds and voices: clips on the timeline, spatial playback, mixing the sound track of the video, the sound browser window. |

A character can be animated from a script: `SA.ImportSequence(ent, seq, { start = frame, frames = length, pos = Vector, yaw = degrees, loops, step, root, cycle0, cycle1, params = { aim_yaw = 0 } })` bakes a model animation into keys of a ragdoll at an exact frame, place and direction. On the server `S.RigidPlaces` / `S.SnapRigid` put the bodies of a ragdoll where the client draws its bones — use them if your mod poses ragdolls and attaches objects to them.
| `cl_saeditor_ui.lua` | The Timeline page (`MOD:AddPage`, window `bottom`), the import and render windows, menu items (`MOD:AddMenu`), the section in the Render window and the playback buttons in the preview (hooks `SPeditor_RenderDialog`, `SPeditor_RenderPreviewBuilt`). |

Worth noticing:

* the animation is stored **on the server** — where the objects it moves live;
  the client only receives a table of contents for the timeline;
* every key edit is one entry of the editor's history: the client makes up an
  operation number, the server remembers the tracks before and after it;
* in the scene file objects are replaced by numbers (`ctx.indexOf`), and on load
  the data is validated field by field.

---

## 6. Switching mods off

The Mods window → untick "Enabled", or the server variable:

```
speditor_mods_off "saeditor,mytool"
```

The change takes effect after the map restarts.
]===]
