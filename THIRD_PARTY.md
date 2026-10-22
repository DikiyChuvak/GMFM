# Third-party parts

The [MIT license](LICENSE) covers GM:FM's own code, texts, pictures, sounds and shaders.
The parts below are bundled with GM:FM but **belong to their authors**: they are not under
the MIT license and keep their own terms. If you fork GM:FM and publish it, check these
parts first (keep them with their credits, or leave them out).

[Лицензия MIT](LICENSE) распространяется на собственный код, тексты, картинки, звуки и шейдеры
GM:FM. Перечисленные ниже части входят в GM:FM, но **принадлежат своим авторам**: они не
под лицензией MIT и остаются на своих условиях. Если делаете форк и публикуете его, сначала
проверьте эти части (оставьте их с указанием авторов или уберите).

## Interface skins

Adapted copies of Workshop Derma skins (`lua/speditor/skins/*.lua`) and their textures
(`materials/speditor/skins/*.png`, `materials/speditor/skins/ecoui/`):

| GM:FM theme | Original | Author |
|---|---|---|
| EcoUI (`ecoui.lua`, `ecoui/`) | [EcoUI](https://steamcommunity.com/sharedfiles/filedetails/?id=3255386124) | ELuminumG24 |
| Dark UI (`darkui.lua`, `darkui*.png`) | [Dark UI Spawnmenu](https://steamcommunity.com/sharedfiles/filedetails/?id=888392108) | AquaRex |
| Steam 2004 (`steam2004.lua`, `steam2004*.png`) | [Steam 2004 Derma Skin](https://steamcommunity.com/sharedfiles/filedetails/?id=3321557660) | Maks1mDiamond (Valve's look) |
| GMod 98 (`gmod98.lua`, `gmod98*.png`) | [GMod98 UI Skin](https://steamcommunity.com/sharedfiles/filedetails/?id=2972603323) | AwesomeGraczGie21 |
| OneShot (`oneshot.lua`, `oneshot.png`) | [OneShot - UI Skin](https://steamcommunity.com/sharedfiles/filedetails/?id=3659339920) | Flarky |
| Lambda UI (`lambdaui.lua`, `lambdaui.png`) | [Lambda UI](https://steamcommunity.com/sharedfiles/filedetails/?id=2927713362) | 晦涩弗里曼 |
| Vanilla UI (`vanillaui.lua`) | [Vanilla UI+ Derma Skin](https://steamcommunity.com/sharedfiles/filedetails/?id=3818111525) | Qude |
| GMod XP (`gmodxp.lua`) | [Windows XP Classic UI & HUD](https://steamcommunity.com/sharedfiles/filedetails/?id=3816955790) | w4da |
| HL2 Media Player (`hl2mp.png`) | [HL2 Media Player Skin Inspired Spawnmenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3263951771) | GhostSynth |
| Aero Blur (`aeroblur.png`) | [Aero Blur Spawnmenu Skin - Dark](https://steamcommunity.com/sharedfiles/filedetails/?id=2919822758) | Luigi |
| GMod Classic (`gmodclassic.png`) | [Garry's Mod Classic UI Spawnmenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3379423670) | Bon Bon 3016 |
| GMod (`gmod.lua`, `gmod.png`) | the game's stock Derma skin (`lua/skins/default.lua`) | Garry Newman / Facepunch Studios |

## GM:FM UI — Source Filmmaker's pictures / картинки Source Filmmaker

The GM:FM UI theme (`lua/speditor/skins/sfm.lua`) is GM:FM's own code under MIT, but the
pictures it draws — `materials/speditor/skins/sfm/base/` and `materials/speditor/skins/sfm/sfm/`
— are copied from Source Filmmaker (`platform/tools/images`) and belong to **Valve
Corporation**. GM:FM is not affiliated with Valve.

Тема GM:FM UI (`lua/speditor/skins/sfm.lua`) — собственный код GM:FM под MIT, но картинки,
которые она рисует, — `materials/speditor/skins/sfm/base/` и `materials/speditor/skins/sfm/sfm/`
— взяты из Source Filmmaker (`platform/tools/images`) и принадлежат **Valve Corporation**.
GM:FM с Valve не связан.

The grey glyphs `materials/speditor/skins/sfm/glyph/` are made (`tools/make_glyphs.py`) from
the [Silk icons](http://www.famfamfam.com/lab/icons/silk/) by Mark James that come with
Garry's Mod (Creative Commons Attribution 2.5).

## Sounds

| Folder | Source |
|---|---|
| `sound/speditor/notify/halflife/` | [Half Life UI Sounds](https://steamcommunity.com/sharedfiles/filedetails/?id=2790356494) — ВРАТАРb_DINAMO (Half-Life sounds, Valve) |
| `sound/speditor/notify/winxp/` | [Windows XPerience UI Sounds](https://steamcommunity.com/sharedfiles/filedetails/?id=2979067313) — Jade (Windows XP sounds, Microsoft) |
| `sound/speditor/notify/aero7ui/` | Windows 7 system sounds, Microsoft |

## Other

- `materials/speditor/brand/start_bg.jpg` — Garry's Mod's own background picture (Facepunch Studios).
- The SSAO, film grain and colour correction shaders (`shaders_src/`, `shaders/fxc/`) are
  GM:FM's own code (MIT); the SSAO follows the algorithm of Source Filmmaker's shader.
- Built against the sources of Ragdoll Mover, Advanced Bonemerge, Easy Bonemerge, Advanced
  Light Entities, Soft Lamps, Stop Motion Helper and GShader Library for compatibility; no
  code of theirs is bundled.

Garry's Mod is a product of Facepunch Studios; Source Filmmaker and Half-Life are products
of Valve Corporation.
