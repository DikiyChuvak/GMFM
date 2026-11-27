<img align="left" width="104" height="104" hspace="14" vspace="2" src="materials/speditor/icon128.png" alt="GM:FM">

# GM:FM — Garry's Mod Filmmaker

Scenes, animation and film inside Garry's Mod — close to a full port of Source Filmmaker.
Called SPeditor until b0.1.

[![Steam Workshop](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fshieldsio-steam-workshop.jross.me%2F3817852435%2Fsubscriptions-text)](https://steamcommunity.com/sharedfiles/filedetails/?id=3817852435)
[Issues](https://github.com/DikiyChuvak/GMFM/issues) · [MIT](LICENSE)

<br clear="left">

## About GM:FM

*The whole source code of GM:FM is open under the MIT license. Fork it, or dig into it if you
are an enthusiast. Changes from other developers may get into the Workshop version (always
credited) — message me on Steam first so I can look at what you have changed. The Simplified
Chinese translation is by [fugui9527121](https://github.com/fugui9527121) — thank you!*

This repository is the **full source code** of GM:FM — the addon, its gamemode, shaders and
tools. Release **r1.1** is the default branch; the previous release, **r1.0**, stays on the
`r1.0` tag, and `b0.3` is the last version before the r1.0 line. How to use the editor is
explained inside the game: **Help → How to use** (illustrated guides with live demonstrations).

## Changes and fixes (r1.1)

Release r1.1 builds on r1.0. Please report anything unexpected in
[issues](https://github.com/DikiyChuvak/GMFM/issues).

**Demos and HLAE are gone**

- The demo import and everything that needed HLAE are removed for good: the client file
  `cl_saeditor_demo.lua`, its network messages, the File menu item, the guide tab, the About
  entry and all `sa_dm_*` strings (English, Russian, Chinese). Recording a gameplay take,
  scenes and the render are untouched.
- The About window's news list now skips a missing entry instead of stopping at it (the removed
  demo entry would have hidden every entry after it).

**PAC3 outfits no longer leak**

- The outfit list is synced with the object's UID, not only its entity index, and the server
  sends a "forget" message when an object is removed. A new object that takes the index of a
  removed one does not put on the old outfits, while outfits survive PVS transitions and undo.

**Materials changed by other tools**

- A key, a preset, `S.CaptureLook` and the scene file now take the materials the game's own
  Material / SubMaterial tool set on the entity, instead of overwriting them. Between keys only
  the slots the key controls (and the ones the previous key set) change, so an outside edit is
  kept.

**Mocap for a foreign skeleton**

- The BVH import window has a **Bones…** button: the joints on the left, the model's bones on
  the right with a search, a "Match by name" button, and the map is saved per model in
  `data/speditor/bvhmaps/`. Name matching now understands thigh / leg, forearm / elbow,
  left / right and numbers, and each bone is used once.

**A crash when opening a scene**

- A scene with coloured material slots and the camera's ambient occlusion on could close the
  game while it was drawn: the occlusion's depth pass and the per-slot material colours were
  applied in the same draw (a native crash in `DrawModel`). The depth pass and the shadow maps now
  draw such objects with their own material only; the colours still show in the viewport and in
  the render.
- A long session no longer fills the memory. The colour mixer used to make a new material for
  every step of a drag (the game never frees a material), and the render look made a new set of
  render targets for every size a dragged splitter passed through (the game never frees a render
  target either). Both are capped now; Help → Problems and answers has "The game closes when I
  open a scene".

**Help**

- New answers in Help → Problems and answers: an effect of a weapon pack that is not part of
  the scene, the map's doors and buttons (the editor animates scene objects, not `func_door`),
  and working on a server or with another player.

**Core (r1.1)**

- Performance: View → Interface settings → Appearance → Performance → **Viewport picture
  resolution** (100 / 85 / 75 / 50 %). The scene inside the viewports (and the moving render-look
  frames) is drawn at that share of the screen's pixels; the windows, the gizmo and the final
  render keep their resolution, and the render look at rest is always full. On a 2K / 4K screen
  or with many addons this is the direct way to more frames per second without losing the render.
- Scene diagnostics now also names other addons that hook `RenderScene` / `CalcView` (the usual
  source of a strange picture or camera with many addons), the world's entity count and the
  errors caught since the game started.
- The GM:FM gamemode keeps the filmmaker out of the scene: while the editor is open the player
  takes no damage and NPCs do not target them; the editor is unchanged in Sandbox.
- Motion Editor: **Remove redundant keys**, **Resample** (a key every 1 / 2 / 3 / 5 / 10
  frames) and **Keep only the selection** in the time selection menu, for imported mocap and
  recorded takes. Redundant removal works on whole keys; resample works on tracks without
  per-bone / per-slider keys (those are left alone). All three are one undo step.
- More of SFM's rig: **Aim** (keep looking at) now works for props, characters and single
  bones, not only cameras and lights; a **Rotation** constraint follows the target's turn around
  the vertical;
  a **persistent IK target** makes a ragdoll's hand or foot follow an object (the chain is solved
  every tick, saved with the scene, undo and duplicate); the light rig has a **bounce** light and
  a **master colour** for the selected lights; **bookmark sets** keep named copies of the
  bookmarks; the camera's ambient occlusion has **AOTint** (three sliders).
- Old scenes, animations and poster settings keep working: the scene and SAeditor formats are
  unchanged, and a scene saved before this update loads with its keys (checked with the shipped
  `demo_ball` example).

**Bone keys and faces (r1.0 feedback)**

- The **Bone keys** mode is back as a timeline toggle (the branch button, off by default): K
  then keys only the selected bone, and a key of the whole body leaves the bones that have keys
  of their own alone, so a body key no longer flattens their motion. Auto key still keys only
  the bones a drag moved.
- Auto key after a face edit now keys the whole face at that frame (an expression is a
  combination of sliders), and the first face key always holds the whole face, so the other
  sliders no longer change as the playhead moves. One slider alone can still be keyed from its
  row on the timeline.

**Checks:** `luajit -bl` over all Lua and `lint_glua` over the changed files (0 errors);
`SPeditor.SelfTest` in the game (38 of 38, empty scene, editor closed). In the game, also: an
outside submaterial edit survives `SyncSubMats → CaptureLook → ApplyLook` and two keys evaluated
at frames 0 and 10; a `PACSync` with a UID reaches the client, the removal clears it, and a reused
entity index with another UID is refused; with Bone keys on, K made a key of the selected bone
only (`only=b14`), a whole-body key carried `skip=b14`, and with it off a plain key; the first
face key of a track was full, the next slider key partial, and an auto key after a face edit was
full. The viewport resolution gave 1440×810 at 75 % and 960×540 at 50 % of a 1920×1080 screen,
and Scene diagnostics listed the other addons hooking `CalcView` / `RenderScene`; the shipped
`demo_ball` scene loaded with its 2 objects and both animation tracks. The new key operations were
run in the game: removing redundant keys took 0, 10, 20, 30 to 0, 20, 30 (undo brought 10 back);
resampling every 5 frames gave 0…30 with frame 25 halfway; a face track 0 / 20 / 40 (0, 1, 0)
became 0…40 (0, 0.5, 1, 0.5, 0); a track with a partial key (`only=b5`) was left untouched;
a mask over 10…20 cut 0, 10, 20, 30 to 10, 20; aiming a prop at another turned it to yaw 90°;
a Rotation constraint on a prop kept pitch 20° and roll 10° while yaw followed the parent to
90°; the light rig made 4 lights and the master colour reached all of them; bookmark sets saved,
cleared, loaded and deleted; AOTint returned 127.5, 255, 255 for the camera SSAO. A persistent IK
target brought a ragdoll's right hand to the target point (distance 0.0); the scene saved it as
`ikTo`/`ikBone` and loading the scene restored the link; stop + undo restored the target; a
single-bone aim on the head changed its manip angle and carried `SPeditor_AimSrc = 6`. `SelfTest`
38/38 was run again after all of it. The BVH name matching was run against a Mixamo rig and a
ValveBiped rig (24 of 24 joints, and 23 of 24 where the model has no thumb bone). The help
screenshot of the import window was retaken with the English interface. After the crash fixes: a
clean process ran `SPeditor.SelfTest` 38 of 38 again (the render-target check reported `none`);
a SSAO render of 640×316 with a coloured object set no per-slot overrides in the depth pass and
40 outside it; 300 calls of the tint material helper made 255 materials (the cap).

## Changes and fixes (r1.0)

Release r1.0 collects three patches on top of b0.3. Please report anything unexpected in
[issues](https://github.com/DikiyChuvak/GMFM/issues).

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

**Animation tools**

- Tween machine with a strength slider (1–200 %) and a face switch (`OP.TWEEN_FACE`);
  mute / solo / lock switches on every timeline row (`SPeditor_TlFlags`).
- Real per-element keys: right click an element row to key only that part; the client also
  works out the element mask for partial keys sent by older servers.
- Look-at constraints have a strength (influence) slider: 1 turns all the way to the target,
  0 keeps the object's own angle.
- BVH mocap import (`data/speditor/mocap/`) through the SMH bridge; pose layers blend two saved
  poses with a weight; a keyable rotator (SFM's Create rotator) keeps its angle in the scene
  instead of deriving it from time — no per-frame calculation.
- SMH import now creates face keys in the face track; the SMH item is back in the File menu.

**Rendering and utilities**

- Posters can save render elements (depth, AO, edges) as PNG beside the picture, use a
  transparent background, and blur the finished frame with a sample slider; a render queue
  renders a poster through every scene camera in turn.
- Windows → Scene diagnostics, Audio mixer and Rig editor; File → Export glTF scene.
- GMFM-Misc additions: SFM-style right/left face slider groups and a How to Use guide for
  bringing Source Filmmaker models into the game.
- The File menu crash (`SetIcon` on a submenu) reported for b0.3 is fixed.
- 46 illustrated How to Use tabs, About entries `about_r10_1…6`, and help screenshots taken
  with the English interface.

**Checks:** `luajit -bl` over all Lua, `lint_glua`, `SPeditor.SelfTest` (38/38),
light and heavy poster renders, an SMH export/import round trip, and in-game UI checks
(buttons, labels, screenshots) all pass.

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
