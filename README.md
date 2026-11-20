<p align="center"><img src="materials/speditor/icon128.png" width="96" alt="GM:FM"></p>

<h1 align="center">GM:FM — Garry's Mod Filmmaker</h1>

<p align="center">
Scenes, animation and film inside Garry's Mod, close to a full port of Source Filmmaker. Called SPeditor until b0.1.<br>
</p>

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

This repository is the **full source code** of GM:FM — the addon, its gamemode, shaders and
tools. The `b0.3` branch is the version on the
[Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3817852435);
the `r1.0-test` branch is release **r1.0 in open testing** (not the default branch).
How to use the editor is explained inside the game: **Help → How to use** (illustrated guides
with live demonstrations).

## Changes and fixes (r1.0, test)

Release r1.0 collects three patches on top of b0.3. It is a release candidate: please report
anything unexpected in [issues](https://github.com/DikiyChuvak/GMFM/issues).

**Critical fixes**

- The Environment window now updates after loading a scene, a reset or a sun texture change:
  its hook used the panel as its identifier, so the callback received the panel instead of the
  change path (gmod-wiki: an object hook id is inserted as the first argument).
- The default GM:FM UI skin (`skins/sfm.lua`) is now sent to clients through `AddCSLuaFile`.
- `gmfm_prof` without an argument toggles the profiler instead of always enabling it; the
  profiler's global wrappers survive autorefresh and uninstall correctly.
- Render targets are no longer created for every pixel of a freely resized viewport (the height
  is stepped like the width), probe targets are reused, and light-mask names use a CRC so two
  different texture paths cannot share a mask.
- Shadow hysteresis is applied to the sort key, not to the squared distance; the gizmo's failed
  axis-ray test no longer starts a drag from zero.
- The Adopt and Model Browser windows call the base `OnRemove` again and clear their Dock pages.

**Network, performance and reliability**

- The Toggle message goes through the protected receiver (rate limit and access check); PAC
  entity indices use 16 bits; the PVS camera limit follows `Cfg.MaxCameras`.
- Long seeks in the animation editor sample the track instead of resolving every frame;
  material signatures and camera effects are compared without serialising JSON each tick.
- Sound-list decompression failures are reported instead of silently dropping the take;
  seek callbacks time out and pose-request callbacks are queued instead of overwriting each other.
- Hand/foot bone-name patterns live in one place (`sh_util.lua`) for IK, auto pose, fingers,
  the gizmo and bone groups; `LookupPoseParameter` replaces a dead `GetPoseParameter ~= nil` check.
- Removed a no-op `TrackFocus` wrapper, dead fallbacks, a one-element loop and a no-op call in
  the WebAudio page; bundle ignore patterns for folders absent from this repository are gone.

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
