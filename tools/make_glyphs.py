# GM:FM UI (b0.2): the grey glyphs of materials/speditor/skins/sfm/glyph are made from the silkicons
# the editor uses (read out of the game into a folder), so tool buttons look like SFM's.
# usage: python3 tools/make_glyphs.py <silkicons dir> materials/speditor/skins/sfm/glyph
import os, sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
n = 0
for f in sorted(os.listdir(src)):
    if not f.endswith('.png'): continue
    im = Image.open(os.path.join(src, f)).convert('RGBA')
    w, h = im.size
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    for y in range(h):
        g = (0.5 - y / (h - 1)) * 20
        for x in range(w):
            r, gg, b, a = im.getpixel((x, y))
            if a == 0: continue
            lum = 0.3 * r + 0.59 * gg + 0.11 * b
            v = int(max(0, min(255, 92 + lum * 0.56 + g)))
            out.putpixel((x, y), (v, v, v, a))
    out.save(os.path.join(dst, f)); n += 1
print(n)
