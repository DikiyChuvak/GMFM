# GM:FM b0.2: the pictures of the animation player in the look of Windows Media Player 11/12
# ("Now Playing"): the glass play orb, the glossy capsule of the controls, the joined
# previous / next lozenge and the white glyphs. Drawn 4x larger and scaled down (smooth edges).
# usage: python3 tools/make_player_skin.py materials/speditor/player
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
SS = 4
os.makedirs(OUT, exist_ok=True)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def save(im, name, size):
    im.resize(size, Image.LANCZOS).save(os.path.join(OUT, name + ".png"))


def vgrad(w, h, stops):
    """a vertical gradient through (t, rgba) stops"""
    im = Image.new("RGBA", (w, h))
    px = im.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                u = (t - stops[i][0]) / max(stops[i + 1][0] - stops[i][0], 1e-6)
                c = lerp(stops[i][1], stops[i + 1][1], u)
                break
        for x in range(w):
            px[x, y] = c
    return im


def masked(src, mask):
    out = Image.new("RGBA", src.size, (0, 0, 0, 0))
    out.paste(src, (0, 0), mask)
    return out


def rrect_mask(w, h, r, box=None):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle(box or (0, 0, w - 1, h - 1), r, fill=255)
    return m


def ellipse_mask(w, h, box):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).ellipse(box, fill=255)
    return m


# ---------------------------------------------------------------- the orb
def orb(name, hot=False, down=False):
    D = 76 * SS
    im = Image.new("RGBA", (D, D), (0, 0, 0, 0))
    c = D / 2
    # the dark bezel ring with a light rim at the top
    bez = vgrad(D, D, [(0, (120, 130, 150, 255)), (0.5, (30, 32, 38, 255)), (1, (8, 8, 10, 255))])
    im.alpha_composite(masked(bez, ellipse_mask(D, D, (2 * SS, 2 * SS, D - 2 * SS, D - 2 * SS))))
    inner = (7 * SS, 7 * SS, D - 7 * SS, D - 7 * SS)
    im.alpha_composite(masked(Image.new("RGBA", (D, D), (0, 0, 0, 255)), ellipse_mask(D, D, (6 * SS, 6 * SS, D - 6 * SS, D - 6 * SS))))
    # the blue glass: a radial light from below, darker at the edge
    glass = Image.new("RGBA", (D, D))
    px = glass.load()
    top, mid, low = ((20, 60, 150), (30, 110, 230), (110, 200, 255))
    if hot:
        top, mid, low = ((35, 90, 190), (50, 140, 250), (150, 225, 255))
    if down:
        top, mid, low = ((15, 45, 120), (25, 90, 200), (80, 170, 240))
    for y in range(D):
        for x in range(D):
            dx, dy = (x - c) / (D / 2), (y - c * 1.35) / (D / 2)
            d = min(math.sqrt(dx * dx + dy * dy) / 1.25, 1)
            col = lerp(low, mid, min(d * 1.6, 1)) if d < 0.62 else lerp(mid, top, (d - 0.62) / 0.38)
            px[x, y] = col + (255,)
    im.alpha_composite(masked(glass, ellipse_mask(D, D, inner)))
    # the gloss: a soft white ellipse on the upper half
    gl = vgrad(D, D, [(0, (255, 255, 255, 190)), (0.42, (255, 255, 255, 30)), (1, (255, 255, 255, 0))])
    gmask = ellipse_mask(D, D, (int(D * 0.2), int(D * 0.11), int(D * 0.8), int(D * 0.52)))
    im.alpha_composite(masked(gl, gmask))
    # a thin light edge around the glass
    ring = Image.new("RGBA", (D, D), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse(inner, outline=(170, 215, 255, 120), width=SS)
    im.alpha_composite(ring)
    save(im, name, (76, 76))


orb("orb")
orb("orb_hot", hot=True)
orb("orb_down", down=True)


# ---------------------------------------------------------------- the glow under the orb (hover)
def glow():
    D = 128 * SS
    im = Image.new("RGBA", (D, D), (0, 0, 0, 0))
    ImageDraw.Draw(im).ellipse((D * 0.18, D * 0.18, D * 0.82, D * 0.82), fill=(80, 170, 255, 150))
    im = im.filter(ImageFilter.GaussianBlur(D * 0.08))
    save(im, "glow", (128, 128))


glow()


# ---------------------------------------------------------------- the capsule: left, middle, right
def capsule():
    H = 44 * SS
    W = 120 * SS
    body = vgrad(W, H, [(0, (70, 76, 88, 245)), (0.08, (40, 44, 52, 245)), (0.5, (14, 16, 20, 245)), (1, (4, 4, 6, 245))])
    m = rrect_mask(W, H, H // 2)
    im = masked(body, m)
    # the gloss of the upper half
    gl = vgrad(W, H, [(0, (255, 255, 255, 60)), (0.5, (255, 255, 255, 8)), (0.51, (255, 255, 255, 0)), (1, (0, 0, 0, 0))])
    im.alpha_composite(masked(gl, rrect_mask(W, H, H // 2, (SS, SS, W - SS, H // 2 + 2 * SS))))
    rim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle((0, 0, W - 1, H - 1), H // 2, outline=(120, 130, 150, 150), width=SS)
    im.alpha_composite(rim)
    im = im.resize((120, 44), Image.LANCZOS)
    im.crop((0, 0, 24, 44)).save(os.path.join(OUT, "cap_l.png"))
    im.crop((48, 0, 72, 44)).save(os.path.join(OUT, "cap_m.png"))
    im.crop((96, 0, 120, 44)).save(os.path.join(OUT, "cap_r.png"))


capsule()


# ---------------------------------------------------------------- the previous / next lozenge
def lozenge(name, hot_side=None):
    W, H = 156 * SS, 32 * SS
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    body = vgrad(W, H, [(0, (150, 160, 175, 255)), (0.48, (60, 66, 78, 255)), (0.52, (36, 40, 48, 255)), (1, (20, 22, 26, 255))])
    im.alpha_composite(masked(body, rrect_mask(W, H, 7 * SS)))
    if hot_side:
        hl = vgrad(W // 2, H, [(0, (120, 190, 255, 120)), (1, (40, 110, 220, 60))])
        x = 0 if hot_side == "l" else W // 2
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        layer.paste(hl, (x, 0))
        im.alpha_composite(masked(layer, rrect_mask(W, H, 7 * SS)))
    rim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle((0, 0, W - 1, H - 1), 7 * SS, outline=(10, 10, 12, 255), width=SS)
    im.alpha_composite(rim)
    save(im, name, (156, 32))


lozenge("pair")
lozenge("pair_l", "l")
lozenge("pair_r", "r")


# ---------------------------------------------------------------- the glyphs (white, a dark shadow)
def glyph(name, draw_fn, size=32):
    D = size * SS
    shape = Image.new("L", (D, D), 0)
    draw_fn(ImageDraw.Draw(shape), D)
    white = Image.new("RGBA", (D, D), (255, 255, 255, 255))
    shadow = Image.new("RGBA", (D, D), (0, 0, 0, 255))
    out = Image.new("RGBA", (D, D), (0, 0, 0, 0))
    sm = shape.filter(ImageFilter.GaussianBlur(SS * 1.2)).point(lambda v: int(v * 0.7))
    out.paste(shadow, (0, SS), sm)
    out.alpha_composite(masked(white, shape))
    save(out, "g_" + name, (size, size))


def tri(d, pts):
    d.polygon(pts, fill=255)


def g_play(d, D):
    tri(d, [(D * 0.34, D * 0.22), (D * 0.34, D * 0.78), (D * 0.8, D * 0.5)])


def g_pause(d, D):
    d.rounded_rectangle((D * 0.28, D * 0.24, D * 0.44, D * 0.76), D * 0.03, fill=255)
    d.rounded_rectangle((D * 0.56, D * 0.24, D * 0.72, D * 0.76), D * 0.03, fill=255)


def g_stop(d, D):
    d.rounded_rectangle((D * 0.3, D * 0.3, D * 0.7, D * 0.7), D * 0.05, fill=255)


def g_prev(d, D):
    d.rectangle((D * 0.2, D * 0.3, D * 0.27, D * 0.7), fill=255)
    tri(d, [(D * 0.52, D * 0.3), (D * 0.52, D * 0.7), (D * 0.28, D * 0.5)])
    tri(d, [(D * 0.78, D * 0.3), (D * 0.78, D * 0.7), (D * 0.54, D * 0.5)])


def g_next(d, D):
    d.rectangle((D * 0.73, D * 0.3, D * 0.8, D * 0.7), fill=255)
    tri(d, [(D * 0.48, D * 0.3), (D * 0.48, D * 0.7), (D * 0.72, D * 0.5)])
    tri(d, [(D * 0.22, D * 0.3), (D * 0.22, D * 0.7), (D * 0.46, D * 0.5)])


def g_repeat(d, D):
    w = int(D * 0.09)
    d.arc((D * 0.2, D * 0.24, D * 0.8, D * 0.76), 200, 520 - 40, fill=255, width=w)
    # the head of the arrow at the end of the arc (top left)
    tri(d, [(D * 0.12, D * 0.36), (D * 0.36, D * 0.36), (D * 0.24, D * 0.56)])


def g_look(d, D):
    # a frame with a mountain and a sun: "as the render makes it"
    w = int(D * 0.07)
    d.rounded_rectangle((D * 0.16, D * 0.24, D * 0.84, D * 0.76), D * 0.06, outline=255, width=w)
    tri(d, [(D * 0.24, D * 0.68), (D * 0.44, D * 0.42), (D * 0.6, D * 0.68)])
    tri(d, [(D * 0.48, D * 0.68), (D * 0.62, D * 0.5), (D * 0.76, D * 0.68)])
    d.ellipse((D * 0.62, D * 0.32, D * 0.72, D * 0.42), fill=255)


def g_speaker(d, D, waves=2, mute=False):
    d.polygon([(D * 0.16, D * 0.4), (D * 0.3, D * 0.4), (D * 0.48, D * 0.24), (D * 0.48, D * 0.76), (D * 0.3, D * 0.6), (D * 0.16, D * 0.6)], fill=255)
    w = int(D * 0.06)
    if mute:
        d.line((D * 0.58, D * 0.38, D * 0.82, D * 0.62), fill=255, width=w)
        d.line((D * 0.58, D * 0.62, D * 0.82, D * 0.38), fill=255, width=w)
        return
    if waves >= 1:
        d.arc((D * 0.36, D * 0.34, D * 0.68, D * 0.66), -50, 50, fill=255, width=w)
    if waves >= 2:
        d.arc((D * 0.32, D * 0.2, D * 0.84, D * 0.8), -50, 50, fill=255, width=w)


def g_camera(d, D):
    d.rounded_rectangle((D * 0.14, D * 0.34, D * 0.64, D * 0.7), D * 0.05, fill=255)
    tri(d, [(D * 0.66, D * 0.52), (D * 0.86, D * 0.36), (D * 0.86, D * 0.68)])
    d.ellipse((D * 0.18, D * 0.14, D * 0.36, D * 0.32), fill=255)
    d.ellipse((D * 0.4, D * 0.14, D * 0.58, D * 0.32), fill=255)


def g_close(d, D):
    w = int(D * 0.09)
    d.line((D * 0.3, D * 0.3, D * 0.7, D * 0.7), fill=255, width=w)
    d.line((D * 0.3, D * 0.7, D * 0.7, D * 0.3), fill=255, width=w)


def g_list(d, D):
    w = int(D * 0.07)
    for i, y in enumerate((0.3, 0.5, 0.7)):
        d.rectangle((D * 0.2, D * (y - 0.04), D * 0.3, D * (y + 0.04)), fill=255)
        d.line((D * 0.38, D * y, D * 0.8, D * y), fill=255, width=w)


glyph("play", g_play)
glyph("pause", g_pause)
glyph("stop", g_stop)
glyph("prev", g_prev)
glyph("next", g_next)
glyph("repeat", g_repeat)
glyph("look", g_look)
glyph("vol", lambda d, D: g_speaker(d, D, 2))
glyph("vol_low", lambda d, D: g_speaker(d, D, 1))
glyph("vol_mute", lambda d, D: g_speaker(d, D, 0, True))
glyph("camera", g_camera)
glyph("close", g_close)
glyph("list", g_list)
print("done")
