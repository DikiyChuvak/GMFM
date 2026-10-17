SPeditor — папка шейдеров / shader folder
=========================================

RU
--
Сюда кладутся наборы сторонних шейдеров, скачанные из мастерской Steam или с GitHub.
Каждый набор — отдельная папка:

    garrysmod/addons/speditor/shaders/<набор>/
        materials/...          материалы (.vmt) и текстуры (.vtf, .png)
        shaders/fxc/*.vcs      скомпилированные шейдеры

Допустима лишняя вложенная папка, как в архивах GitHub (<набор>/<набор>-main/materials/...),
а также просто файлы .vmt и .vcs россыпью.

После этого в редакторе: «Окна» → «Шейдеры аддонов» → вкладка «Папка шейдеров» →
«Пересканировать папку шейдеров». Набор подключается без перезапуска игры, его
шейдеры появляются в окне «Рендер»: «Эффекты камеры» → «Свой шейдер».

Важно:
  * Папка shaders/fxc — шейдеры самого SPeditor (SSAO), не кладите набор с таким именем.
  * Подходят шейдеры-материалы: .vmt на шейдере screenspace_general со своим
    пиксельным шейдером ($pixshader). Кадр они получают через $basetexture
    (_rt_FullFrameFB), числа — через $c0_x … $c3_w (ползунки появятся сами).
  * Lua из набора НЕ запускается. Аддон с Lua (эффекты на хуках, GShader Library
    и шейдеры на ней) ставится как обычно — подпиской в мастерской или папкой в
    garrysmod/addons — и используется в режиме «Кадр движка» (окно «Рендер»).
  * На Linux имена папок и файлов набора должны быть в нижнем регистре.
  * Если набор изменили во время игры, уже загруженные материалы обновятся
    только после перезапуска игры.
  * Упакованные копии наборов лежат в garrysmod/data/speditor/shaderpacks — их
    можно удалять, они создаются заново.

EN
--
Put third-party shader packs downloaded from the Steam Workshop or GitHub here.
Each pack is its own folder:

    garrysmod/addons/speditor/shaders/<pack>/
        materials/...          materials (.vmt) and textures (.vtf, .png)
        shaders/fxc/*.vcs      compiled shaders

One extra nested folder is fine, as in GitHub archives (<pack>/<pack>-main/materials/...),
and so are loose .vmt and .vcs files.

Then in the editor: Windows → Addon shaders → Shader folder tab → Rescan shader
folder. The pack is mounted without restarting the game; its shaders appear in the
Render window: Camera effects → Custom shader.

Notes:
  * shaders/fxc holds SPeditor's own shaders (SSAO): do not name a pack "fxc".
  * Shader materials are supported: a .vmt using screenspace_general with its own
    pixel shader ($pixshader). The frame comes in through $basetexture
    (_rt_FullFrameFB), numbers through $c0_x … $c3_w (sliders appear automatically).
  * Lua from a pack is NOT run. An addon with Lua (hook-based effects, GShader
    Library and shaders built on it) is installed the usual way — a Workshop
    subscription or a folder in garrysmod/addons — and used in Engine frame mode
    (Render window).
  * On Linux the pack's folder and file names must be lowercase.
  * If a pack is changed while the game is running, materials that are already
    loaded are refreshed only after the game restarts.
  * Packed copies live in garrysmod/data/speditor/shaderpacks; they can be deleted
    and are rebuilt when needed.
