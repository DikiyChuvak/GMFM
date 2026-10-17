<p align="center"><img src="materials/speditor/icon128.png" width="96" alt="SPeditor"></p>

<h1 align="center">SPeditor</h1>

<p align="center">
A poster, scene and animation studio inside Garry's Mod, in the style of Source Filmmaker.<br>
Студия постеров, сцен и анимации прямо в Garry's Mod, в стиле Source Filmmaker.
</p>

<p align="center">
<a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3817852435"><b>Steam Workshop</b></a> ·
<a href="https://DikiyChuvak.github.io/SPeditor/"><b>Wiki (EN / RU)</b></a> ·
<a href="https://DikiyChuvak.github.io/SPeditor/SPeditor_Guide_EN.pdf">PDF (EN)</a> ·
<a href="https://DikiyChuvak.github.io/SPeditor/SPeditor_Guide_RU.pdf">PDF (RU)</a> ·
<a href="https://github.com/DikiyChuvak/SPeditor/issues">Issues</a>
</p>

<p align="center"><img src="https://DikiyChuvak.github.io/SPeditor/img/01_overview.jpg" alt="SPeditor editor"></p>

## English

SPeditor turns Garry's Mod into a small film studio. It brings the working habits of Source Filmmaker — dockable windows, an Animation Set Editor, two viewports, a free work camera — to any map.

- **Posing:** a gizmo for objects and every bone (fingers too), inverse kinematics that keeps the feet planted, bones locked to other bones, face flexes, eye target, skins and bodygroups, a pose library.
- **Objects:** colour, opacity, texture replacement, stretching; attach a weapon to a hand; **wear** clothing that bends with the body.
- **Lights:** point and spot lights with soft edges, penumbra, glow, a visible beam, light masks and 19 ready-made light kinds.
- **Effects:** particle effects of the game and of Workshop addons, frozen at any moment.
- **Render** to PNG, JPEG or straight into your Steam screenshots, up to 3840 px: smoothing, depth of field, soft shadows, camera effects, Workshop shaders.
- **SAeditor:** keyframe animation of everything in the scene (up to an hour) with bone keys, ghosts and continuous spline keys, a curve editor, the **Motion Editor** (an edit over a time selection with falloff), camera cuts and an in-game player, cameras and lights that keep looking at an actor, **recorded gameplay (machinima)**, lip sync, procedural breathing and blinking, imported model animations and Stop Motion Helper saves, sounds and voices, AVI video at any frame rate up to 120 fps with motion blur.
- **Take objects from the map:** Ragdoll Mover poses, Advanced / Easy Bonemerge, Advanced Light Entities, Soft Lamps.
- Scenes, poses and layouts are saved; undo for every edit; illustrated in-game guides (Help → How to use); every hotkey can be changed; interface scale 50–200 %; ten interface themes with your own accent and font; styled notifications; English and Russian, other languages as community language packs (`lua/speditor_lang/`).

**Install:** subscribe on the [Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3817852435), or clone this repository into `garrysmod/addons/speditor`. **Open:** C menu → SPeditor, Q menu → SPeditor → Toggle editor, or `speditor_toggle` in the console. Read the [wiki](https://DikiyChuvak.github.io/SPeditor/) for everything else.

## Русский

SPeditor превращает Garry's Mod в маленькую киностудию с приёмами работы из Source Filmmaker: стыкуемые окна, Animation Set Editor, два вьюпорта, свободная рабочая камера — на любой карте.

- **Позы:** гизмо для объектов и каждой кости (включая пальцы), инверсная кинематика с неподвижными стопами, крепление кости к кости, мимика, взгляд, скины и бодигруппы, библиотека поз.
- **Объекты:** цвет, прозрачность, замена текстур, растяжение; оружие в руке; **одежда**, которая гнётся вместе с телом.
- **Свет:** точечный свет и прожекторы с мягким краем, полутенью, свечением, видимым лучом, масками и 19 готовыми видами.
- **Эффекты:** частицы игры и аддонов Workshop, остановленные в любой момент.
- **Рендер** в PNG, JPEG или сразу в скриншоты Steam, до 3840 px: сглаживание, глубина резкости, мягкие тени, эффекты камеры, шейдеры Workshop.
- **SAeditor:** анимация ключевыми кадрами всего в сцене (до часа) с ключами костей, призраками и непрерывными сплайн-ключами, редактор кривых, **Motion Editor** (правка на выделение времени с затуханием), смены камер и плеер в игре, камеры и свет, которые следят за актёром, **запись игры (машинима)**, липсинк, процедурное дыхание и моргание, импорт анимаций моделей и сохранений Stop Motion Helper, звуки и голоса, видео AVI с любой частотой кадров до 120 к/с с размытием движения.
- **Объекты с карты:** позы Ragdoll Mover, Advanced / Easy Bonemerge, Advanced Light Entities, Soft Lamps.
- Сохранение сцен, поз и раскладок; отмена любого действия; иллюстрированные статьи в игре (Справка → Как пользоваться); любые горячие клавиши можно сменить; масштаб интерфейса 50–200 %; десять тем интерфейса со своим акцентом и шрифтом; настраиваемые уведомления; английский и русский, другие языки — языковые пакеты сообщества (`lua/speditor_lang/`).

**Установка:** подпишитесь в [Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3817852435) или склонируйте репозиторий в `garrysmod/addons/speditor`. **Запуск:** меню C → SPeditor, меню Q → SPeditor → Toggle editor или `speditor_toggle` в консоли. Всё остальное — в [вики](https://DikiyChuvak.github.io/SPeditor/).

## Repository / Репозиторий

| Path | Contents |
|---|---|
| `lua/speditor/` | The editor (client `cl_*`, server `sv_*`, shared `sh_*`) |
| `lua/speditor/saeditor/` | SAeditor, the built-in animation part (timeline, keys, curves, sound, video) |
| `lua/entities/` | Light, camera and effect entities |
| `materials/speditor/` | Icons, interface skin textures, pictures of the in-game guides (`help/`) |
| `data_static/speditor/examples/` | The example scene `shootout_construct` |
| `shaders/` | The folder for your own shader packs |

The wiki lives in the `gh-pages` branch.

## Credits

The bundled interface skins belong to their authors: [EcoUI](https://steamcommunity.com/sharedfiles/filedetails/?id=3255386124) — ELuminumG24, [Dark UI Spawnmenu](https://steamcommunity.com/sharedfiles/filedetails/?id=888392108) — AquaRex, [Steam 2004 Derma Skin](https://steamcommunity.com/sharedfiles/filedetails/?id=3321557660) — Maks1mDiamond, [GMod98 UI Skin](https://steamcommunity.com/sharedfiles/filedetails/?id=2972603323) — AwesomeGraczGie21, [OneShot - UI Skin](https://steamcommunity.com/sharedfiles/filedetails/?id=3659339920) — Flarky, [Lambda UI](https://steamcommunity.com/sharedfiles/filedetails/?id=2927713362) — 晦涩弗里曼, [Vanilla UI+ Derma Skin](https://steamcommunity.com/sharedfiles/filedetails/?id=3818111525) — Qude, [Windows XP Classic UI & HUD](https://steamcommunity.com/sharedfiles/filedetails/?id=3816955790) — w4da. Notification sounds: [Half Life UI Sounds](https://steamcommunity.com/sharedfiles/filedetails/?id=2790356494) — ВРАТАРb_DINAMO, [Windows XPerience UI Sounds](https://steamcommunity.com/sharedfiles/filedetails/?id=2979067313) — Jade. Workshop shader support was built with [GShader Library](https://steamcommunity.com/sharedfiles/filedetails/?id=3542644649) by Akabenko. The GMod theme is a copy of the standard Derma skin by Garry Newman. Source Filmmaker is a product of Valve; SPeditor is not affiliated with Valve.

## License

SPeditor's own code is released under the [MIT license](LICENSE). The bundled skins keep their authors' terms.
