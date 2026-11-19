#!/usr/bin/env python3
"""SPeditor — packs compiled pixel shaders (fxc output) into Source .vcs files.

    python3 shaders_src/build_vcs.py

Compile first (Windows fxc, or under wine):
    fxc /nologo /T ps_2_b /E main /O3 /Fo speditor_ao2.o speditor_ao2.hlsl
Every shaders_src/<name>.o becomes shaders/fxc/<name>_ps20b.vcs: version 6, one static and
one dynamic combo, the bytecode in one LZMA block (the layout the engine reads). A name that
ends in _ps30 / _vs30 already (b0.2, the SFM ambient occlusion; fxc /T ps_3_0 or vs_3_0) keeps it.
"""
import glob, lzma, os, struct, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "shaders", "fxc")


def lzma_block(raw):
    # Valve's LZMA header: 'LZMA', real size, compressed size, 5 property bytes, the stream
    alone = lzma.compress(raw, format=lzma.FORMAT_ALONE, filters=[{"id": lzma.FILTER_LZMA1, "dict_size": 1 << 16}])
    props, stream = alone[:5], alone[13:]
    return b"LZMA" + struct.pack("<II", len(raw), len(stream)) + props + stream


def vcs(bytecode, crc):
    inner = struct.pack("<iI", 0, len(bytecode)) + bytecode
    block = lzma_block(inner)
    data_off = 28 + 2 * 8 + 4
    body = struct.pack("<I", len(block) | 0x40000000) + block + struct.pack("<I", 0xFFFFFFFF)
    end = data_off + len(body)
    head = struct.pack("<7I", 6, 1, 1, 0, 0, 2, crc)
    recs = struct.pack("<II", 0, data_off) + struct.pack("<II", 0xFFFFFFFF, end)
    return head + recs + struct.pack("<I", 0) + body


# (b0.2.7) the shaders only Linux / macOS draw: their cmps made safe for the game's ToGL there
# (fix_cmp.py: it writes a cmp out a component at a time without a copy of the destination)
LINUX_ONLY = ("gmfm_depthpack", "gmfm_depthpack2", "gmfm_depthsmooth", "gmfm_depthsmooth2",
              "gmfm_sfmao4b_pk", "gmfm_sfmaoblur4b_pk", "speditor_ao2_pk", "speditor_ao2_blur_pk")

os.makedirs(OUT, exist_ok=True)
for obj in sorted(glob.glob(os.path.join(HERE, "*.o"))):
    name = os.path.splitext(os.path.basename(obj))[0]
    code = open(obj, "rb").read()
    if name in LINUX_ONLY:
        import fix_cmp
        code, n = fix_cmp.fix(code)
        if n:
            print(name, "cmps made safe:", n)
    src = os.path.join(HERE, name + ".hlsl")
    crc = zlib.crc32(open(src, "rb").read()) if os.path.exists(src) else 0
    suffix = "" if name.endswith(("_ps30", "_vs30")) else "_ps20b"
    path = os.path.join(OUT, name + suffix + ".vcs")
    open(path, "wb").write(vcs(code, crc))
    print(path, os.path.getsize(path))

# (b0.2.7) Linux / macOS: every shader the editor draws there also goes out as a copy named
# <name>x_ps20b (byte for byte the same). The game there remembers the shaders it drew in
# glshaders.cfg and builds them again when the next session starts — before the addon is
# mounted, so they are not found and stay dead for that session (lua/speditor/cl_render.lua,
# R.ShaderName): each session the editor uses whichever of the two names works.
import shutil
LINUX_ALIASES = ["gmfm_depthpack", "gmfm_depthpack2", "gmfm_depthsmooth", "gmfm_depthsmooth2",
                 "gmfm_sfmao4b_pk", "gmfm_sfmaoblur4b_pk", "speditor_ao2_pk", "speditor_ao2_blur_pk",
                 "gmfm_cc2b", "gmfm_grain2b", "gmfm_sfmbloom2b"]
for base in LINUX_ALIASES:
    src = os.path.join(OUT, base + "_ps20b.vcs")
    if os.path.exists(src):
        dst = os.path.join(OUT, base + "x_ps20b.vcs")
        shutil.copyfile(src, dst)
        print(dst, "(copy)")
