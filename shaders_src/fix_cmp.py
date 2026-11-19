#!/usr/bin/env python3
"""GM:FM (b0.2.7) — makes the cmp instructions of a D3D9 pixel shader safe for the Linux / macOS
game's D3D -> OpenGL layer (ToGL).

ToGL writes a cmp out one component at a time: "r0.x = (c >= 0) ? a.x : b.x; r0.y = ...". Valve's
own ToGL copies the destination register to a temporary first; the game's build does not (measured
with a probe shader: cmp r0.xyzw, -r0.x, r1, c0 gave (0.6, 0.4, 0.6) for (0.6, 0.4, 0.2) — r0.y and
r0.z tested the r0.x the first line had just written). So where a source of a cmp reads, for some
component, a component of the destination that an earlier component of the same cmp has written,
the destination is first copied to a free temporary (mov) and the source reads that instead —
the same result in Direct3D, the right one under ToGL.

    python3 fix_cmp.py in.o out.o        (prints how many cmps were changed)
"""
import struct, sys

CMP = 88
COMPS = "xyzw"


def regtype(t):
    return ((t >> 28) & 7) | ((t >> 8) & 0x18)


def regnum(t):
    return t & 0x7FF


def parse(words):
    """-> list of ("raw", [words]) / ("ins", opcode, [token, params...])"""
    out, i = [], 1
    while i < len(words):
        t = words[i]
        op = t & 0xFFFF
        if op == 0xFFFF:
            out.append(("raw", words[i:]))
            break
        if op == 0xFFFE:
            n = (t >> 16) & 0x7FFF
            out.append(("raw", words[i:i + 1 + n]))
            i += 1 + n
            continue
        n = (t >> 24) & 0xF
        out.append(("ins", op, words[i:i + 1 + n]))
        i += 1 + n
    return out


def fix(code):
    words = list(struct.unpack("<%dI" % (len(code) // 4), code))
    items = parse(words)
    # the temporaries in use -> the first free one
    used = set()
    for it in items:
        if it[0] == "ins" and it[1] not in (31, 81, 47, 48):     # not dcl / def / defb / defi
            for p in it[2][1:]:
                if regtype(p) == 0:
                    used.add(regnum(p))
    tmp = max(used) + 1 if used else 0
    changed = 0
    out = [words[0]]
    for it in items:
        if it[0] == "raw":
            out += it[1]
            continue
        op, toks = it[1], list(it[2])
        if op == CMP and len(toks) == 5 and regtype(toks[1]) == 0:
            d = toks[1]
            R = regnum(d)
            mask = (d >> 16) & 0xF
            order = [c for c in range(4) if mask & (1 << c)]
            hazard = []
            for si in (2, 3, 4):
                s = toks[si]
                if regtype(s) != 0 or regnum(s) != R:
                    continue
                sw = (s >> 16) & 0xFF
                written = set()
                for c in order:
                    if (sw >> (2 * c)) & 3 in written:
                        hazard.append(si)
                        break
                    written.add(c)
            if hazard:
                if tmp > 31:
                    raise SystemExit("no free temporary register")
                # mov r<tmp>.xyzw, r<R>.xyzw
                out += [0x02000001, 0x800F0000 | tmp, 0x80E40000 | R]
                for si in set(hazard):
                    toks[si] = (toks[si] & ~0x7FF) | tmp
                changed += 1
        out += toks
    return struct.pack("<%dI" % len(out), *out), changed


if __name__ == "__main__":
    code = open(sys.argv[1], "rb").read()
    new, n = fix(code)
    open(sys.argv[2], "wb").write(new)
    print(sys.argv[1], "cmps fixed:", n)
