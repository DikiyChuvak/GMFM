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

- **Posing:** a gizmo for objects and every bone (fingers too), inverse kinematics, face flexes, eye target, skins and bodygroups, a pose library.
- **Objects:** colour, opacity, texture replacement, stretching; attach a weapon to a hand; **wear** clothing that bends with the body.
- **Lights:** point and spot lights with soft edges, penumbra, glow, a visible beam, light masks and 19 ready-made light kinds.
- **Effects:** particle effects of the game and of Workshop addons, frozen at any moment.
- **Render** to PNG or JPEG up to 3840 px: smoothing, depth of field, soft shadows, camera effects, Workshop shaders.
- **SAeditor:** keyframe animation of everything in the scene, imported model animations, sounds and voices, video export.
- Scenes, poses and layouts are saved; undo for every edit; eight interface themes; a mod system.

**Install:** subscribe on the [Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3817852435), or clone this repository into `garrysmod/addons/speditor`. **Open:** C menu → SPeditor, Q menu → SPeditor → Toggle editor, or `speditor_toggle` in the console. Read the [wiki](https://DikiyChuvak.github.io/SPeditor/) for everything else.

## Русский

SPeditor превращает Garry's Mod в маленькую киностудию с приёмами работы из Source Filmmaker: стыкуемые окна, Animation Set Editor, два вьюпорта, свободная рабочая камера — на любой карте.

- **Позы:** гизмо для объектов и каждой кости (включая пальцы), инверсная кинематика, мимика, взгляд, скины и бодигруппы, библиотека поз.
- **Объекты:** цвет, прозрачность, замена текстур, растяжение; оружие в руке; **одежда**, которая гнётся вместе с телом.
- **Свет:** точечный свет и прожекторы с мягким краем, полутенью, свечением, видимым лучом, масками и 19 готовыми видами.
- **Эффекты:** частицы игры и аддонов Workshop, остановленные в любой момент.
- **Рендер** в PNG или JPEG до 3840 px: сглаживание, глубина резкости, мягкие тени, эффекты камеры, шейдеры Workshop.
- **SAeditor:** анимация ключевыми кадрами всего в сцене, импорт анимаций моделей, звуки и голоса, экспорт видео.
- Сохранение сцен, поз и раскладок; отмена любого действия; восемь тем интерфейса; система модов.

**Установка:** подпишитесь в [Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3817852435) или склонируйте репозиторий в `garrysmod/addons/speditor`. **Запуск:** меню C → SPeditor, меню Q → SPeditor → Toggle editor или `speditor_toggle` в консоли. Всё остальное — в [вики](https://DikiyChuvak.github.io/SPeditor/).

## Repository / Репозиторий

| Path | Contents |
|---|---|
| `lua/speditor/` | The editor (client `cl_*`, server `sv_*`, shared `sh_*`) |
| `lua/speditor_mods/saeditor/` | SAeditor, the animation mod — also the example for mod authors |
| `lua/entities/` | Light, camera and effect entities |
| `materials/speditor/` | Icons and interface skin textures |
| `data_static/speditor/examples/` | The example scene `shootout_construct` |
| `mods/` | Mod guide sources (`build_guide.py` generates `cl_mods_guide.lua`) |
| `tools/` | `speditor_mp4.sh` / `.bat`: turn rendered videos into MP4 with ffmpeg |
| `shaders/` | The folder for your own shader packs |

The wiki lives in the `gh-pages` branch.

## Credits

The bundled interface skins belong to their authors: [EcoUI](https://steamcommunity.com/sharedfiles/filedetails/?id=3255386124) — ELuminumG24, [Dark UI Spawnmenu](https://steamcommunity.com/sharedfiles/filedetails/?id=888392108) — AquaRex, [Steam 2004 Derma Skin](https://steamcommunity.com/sharedfiles/filedetails/?id=3321557660) — Maks1mDiamond, [GMod98 UI Skin](https://steamcommunity.com/sharedfiles/filedetails/?id=2972603323) — AwesomeGraczGie21, [OneShot - UI Skin](https://steamcommunity.com/sharedfiles/filedetails/?id=3659339920) — Flarky, [Lambda UI](https://steamcommunity.com/sharedfiles/filedetails/?id=2927713362) — 晦涩弗里曼. Workshop shader support was built with [GShader Library](https://steamcommunity.com/sharedfiles/filedetails/?id=3542644649) by Akabenko. The GMod theme is a copy of the standard Derma skin by Garry Newman. Source Filmmaker is a product of Valve; SPeditor is not affiliated with Valve.

## License

SPeditor's own code is released under the [MIT license](LICENSE). The bundled skins keep their authors' terms.
