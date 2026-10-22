# GM:FM UI (b0.2): SFM draws a switched-on manipulator button with a blue picture; the
# viewport bar keeps every picture grey, so <name>_grey.png is made from each blue one
# (the pressed shell stays, the blue arrows become SFM's light grey).
# usage: python3 tools/make_grey_active.py materials/speditor/skins/sfm/sfm
import os, sys
from PIL import Image
d = sys.argv[1]
names = ['icon_manipulator_move_activated', 'icon_manipulator_move_global',
         'icon_manipulator_rotate_activated', 'icon_manipulator_rotate_global',
         'icon_fullscreen_activated']
for n in names:
    im = Image.open(os.path.join(d, n + '.png')).convert('RGBA')
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = im.getpixel((x, y))
            if a == 0: continue
            sat = max(r, g, b) - min(r, g, b)
            lum = 0.3 * r + 0.59 * g + 0.11 * b
            # the blue glyph turns light grey, the grey shell keeps its tone
            v = int(min(255, lum + sat * 0.55)) if sat > 24 else int(lum)
            im.putpixel((x, y), (v, v, v, a))
    im.save(os.path.join(d, n + '_grey.png'))
print(len(names))
