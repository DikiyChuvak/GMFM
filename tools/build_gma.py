#!/usr/bin/env python3
"""SPeditor — builds the Workshop package (.gma) without gmad.

    python3 tools/build_gma.py [out.gma]

The Linux gmad that comes with the game has an old file whitelist without
shaders/fxc/*.vcs, so it refuses SPeditor's own shaders (SSAO), although the game itself
loads them from a Workshop addon. This script writes the same GMA format (version 3) with
the game's current whitelist and the "ignore" list of addon.json. The result is uploaded as
before: gmpublish update -id 3817852435 -addon out.gma -changes "...".
"""
import fnmatch, json, os, struct, sys, time, zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# the whitelist of the game (bin/linux64/*.so), shaders included
WHITELIST = """
lua/*.lua scenes/*.vcd particles/*.pcf resource/fonts/*.ttf scripts/vehicles/*.txt
resource/localization/*/*.properties maps/*.bsp maps/*.lmp maps/*.nav maps/*.ain maps/thumb/*.png
sound/*.wav sound/*.mp3 sound/*.ogg materials/*.vmt materials/*.vtf materials/*.png materials/*.jpg
materials/*.jpeg materials/colorcorrection/*.raw models/*.mdl models/*.phy models/*.ani models/*.vvd
models/*.vtx gamemodes/*/*.txt gamemodes/*/*.fgd gamemodes/*/logo.png gamemodes/*/icon24.png
gamemodes/*/gamemode/*.lua gamemodes/*/entities/effects/*.lua gamemodes/*/entities/weapons/*.lua
gamemodes/*/entities/entities/*.lua gamemodes/*/backgrounds/*.png gamemodes/*/backgrounds/*.jpg
gamemodes/*/backgrounds/*.jpeg data_static/*.txt data_static/*.dat data_static/*.json
data_static/*.xml data_static/*.csv shaders/fxc/*.vcs
""".split()


def allowed(rel):
    return any(fnmatch.fnmatchcase(rel, w) for w in WHITELIST)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "..", "speditor.gma")
    meta = json.load(open(os.path.join(ROOT, "addon.json"), encoding="utf-8"))
    ignore = meta.get("ignore", [])

    files, refused = [], []
    for base, dirs, names in os.walk(ROOT):
        dirs.sort()
        for n in sorted(names):
            full = os.path.join(base, n)
            rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
            if rel == "addon.json" or any(fnmatch.fnmatchcase(rel, p) for p in ignore):
                continue
            if rel.lower() != rel:
                refused.append(rel + " (upper case)")
            elif allowed(rel):
                files.append(rel)
            else:
                refused.append(rel)
    if refused:
        print("Not allowed by the whitelist:")
        for r in refused:
            print("   ", r)
        sys.exit(1)

    desc = json.dumps({"description": "Description", "type": meta.get("type", "tool"), "tags": meta.get("tags", [])},
                      indent="\t", ensure_ascii=False)
    head = bytearray(b"GMAD" + bytes([3]))
    head += struct.pack("<QQ", 0, int(time.time()))
    head += b"\0"                                   # required content: none
    for s in (meta.get("title", "SPeditor"), desc, "Author Name"):
        head += s.encode("utf-8") + b"\0"
    head += struct.pack("<i", 1)
    body = bytearray()
    for i, rel in enumerate(files, 1):
        data = open(os.path.join(ROOT, rel), "rb").read()
        head += struct.pack("<I", i) + rel.encode("utf-8") + b"\0" + struct.pack("<qI", len(data), zlib.crc32(data))
        body += data
    head += struct.pack("<I", 0)
    gma = bytes(head + body)
    gma += struct.pack("<I", zlib.crc32(gma))
    open(out, "wb").write(gma)
    print(f"{out}: {len(files)} files, {len(gma) / 1048576:.1f} MB")


if __name__ == "__main__":
    main()
