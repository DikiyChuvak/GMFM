<p align="center"><img src="materials/speditor/icon128.png" width="96" alt="GM:FM"></p>

<h1 align="center">GM:FM — Garry's Mod Filmmaker</h1>

<p align="center">
Scenes, animation and film inside Garry's Mod, close to a full port of Source Filmmaker. Called SPeditor until b0.1.<br>

<p align="center">
<a href="https://steamcommunity.com/sharedfiles/filedetails/?id=3817852435"><b>Steam Workshop</b></a> ·
<a href="https://github.com/DikiyChuvak/GMFM/issues">Issues</a> ·
<a href="LICENSE">MIT</a>
</p>

<p align="center"><img src="materials/speditor/help/overview.jpg" alt="GM:FM editor"></p>

## About GM:FM

*The whole source code of GM:FM is open under the MIT license. Fork it, or dig into it if you
are an enthusiast. Changes from other developers may get into the Workshop version (always
credited) — message me on Steam first so I can look at what you have changed. The Simplified
Chinese translation is by [fugui9527121](https://github.com/fugui9527121) — thank you!*

This repository is the **full source code** of GM:FM b0.3 — the addon as it is on the
[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3817852435), its
gamemode, shaders and tools. How to use the editor is explained inside the game: **Help → How
to use** (illustrated guides with live demonstrations).

### Run it from the source

1. Unsubscribe from GM:FM on the Workshop (two copies of the addon would clash).
2. Clone or unpack this repository into `garrysmod/addons/speditor` — the folder **must** be
   called `speditor` (the shader folder and the theme folder are looked for there).
3. Start Garry's Mod. Sandbox: C menu → GM:FM, or `gmfm_toggle`. The gamemode: Start New Game
   → gamemode **GM:FM**.

Lua autorefresh works for the files in `lua/`; a new file is picked up after
`lua/autorun/speditor_init.lua` is touched.

### What is where

| Path | What |
|---|---|
| `lua/autorun/speditor_init.lua` | loads everything: the lists `SHARED`, `SERVER_FILES`, `CLIENT_FILES` |
| `lua/speditor/sh_*.lua` | shared: settings (`sh_config`), languages (`sh_lang`), errors and reports, components |
| `lua/speditor/sv_*.lua` | server: objects, scenes, adopting map objects, PAC3, the Environment, the gamemode |
| `lua/speditor/cl_*.lua` | client: camera, gizmo, IK, rig, render (`cl_render`, `cl_export`, `cl_ssao`, `cl_postfx`), lights, effects, the whole interface (`cl_ui_*`), guides, self-test |
| `lua/speditor/saeditor/` | SAeditor — the animation component: tracks and keys, timeline, graph editor, sounds and lip sync, recorder, video |
| `lua/speditor/skins/` | Derma skins of the themes (GM:FM UI is `sfm.lua`) |
| `lua/entities/` | the editor's lights, cameras and effects |
| `gamemodes/gmfm/` | the GM:FM gamemode |
| `materials/`, `sound/`, `data_static/` | pictures, interface sounds, example scenes |
| `shaders_src/` → `shaders/fxc/` | HLSL sources of the SSAO, grain and colour correction shaders and their compiled `.vcs` (`shaders_src/build_vcs.py`; compile with `fxc /T ps_2_b`) |
| `tools/` | `build_gma.py` (the Workshop package), picture generators |

### Build the Workshop package

`python3 tools/build_gma.py out.gma` — writes the GMA itself (the game's Linux `gmad` refuses
`shaders/fxc/*.vcs`), skipping what `addon.json` → `ignore` lists.

### Bug reports and ideas

Changes
that get into the Workshop version are credited by name. Bugs and ideas: the
[issues](https://github.com/DikiyChuvak/GMFM/issues) or the
[Workshop discussions](https://steamcommunity.com/workshop/filedetails/discussion/3817852435/567048683131023614/).

## License

GM:FM's own code and content: [MIT](LICENSE). The bundled skins, sounds and Source Filmmaker
pictures of other authors keep their own terms: [THIRD_PARTY.md](THIRD_PARTY.md).
