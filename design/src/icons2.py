"""Yuzu logo directions, round 2: a quiet editorial world (ink / pearl, a whisper of yuzu)."""
import numpy as np
from PIL import Image
from iconkit import *
from icons import base, ellipse, segments, CX, CY, HALF

INK = '#1d1d1f'

def sculpt(c, d, w, col_lo, col_hi, light=(-0.35, -0.75), amb=0.55, spec=0.0):
    """Soft pillow relief from an SDF: rounded bevel of width w, lit from the top-left."""
    t = np.clip(-d / w, 0, 1)
    h = np.sqrt(1 - (1 - t) ** 2) * w
    gy, gx = np.gradient(h, c.px)
    nx, ny, nz = -gx, -gy, np.ones_like(h)
    L = np.array([light[0], light[1], 0.9]); L /= np.linalg.norm(L)
    nl = (nx * L[0] + ny * L[1] + nz * L[2]) / np.sqrt(nx * nx + ny * ny + nz * nz)
    shade = np.clip(amb + (1 - amb) * nl, 0, 1.2)
    col = lerp(col_lo, col_hi, np.clip(shade, 0, 1)[..., None])
    if spec:
        col[..., :3] += (np.clip(nl, 0, 1) ** 40 * spec)[..., None]
    return np.clip(col, 0, 1)

def grain(c, img, amt=0.010, seed=3):
    rng = np.random.default_rng(seed)
    img[..., :3] *= (1 + amt * rng.normal(0, 1, (c.n, c.n)))[..., None]
    return np.clip(img, 0, 1)

def ink_tile(c):
    """neu-dark: 145deg #353538 -> #232325 with an inset top hairline."""
    d1, d2 = tile_shadow(c)
    c.fill(d1, hexc('#000000'), soft=48, alpha=0.32); c.fill(d2, hexc('#000000'), soft=6, alpha=0.22)
    tile = squircle(c, CX, CY, HALF)
    t = np.clip(((c.x - 100) + (c.y - 100)) / 1648, 0, 1)[..., None]
    c.fill(tile, grain(c, lerp(hexc('#38383B'), hexc('#202022'), t), 0.008))
    c.fill(np.abs(tile + 3) - 1.4, hexc('#FFFFFF'), alpha=0.16, mask=np.clip((300 - c.y) / 200, 0, 1))
    c.fill(np.abs(tile + 1) - 1, hexc('#000000'), alpha=0.5)
    return tile

def pearl_tile(c):
    """neu-pill/card: 145deg #ffffff -> #ededf0, hairline #00000014."""
    d1, d2 = tile_shadow(c)
    c.fill(d1, hexc('#000000'), soft=48, alpha=0.20); c.fill(d2, hexc('#000000'), soft=6, alpha=0.12)
    tile = squircle(c, CX, CY, HALF)
    t = np.clip(((c.x - 100) + (c.y - 100)) / 1648, 0, 1)[..., None]
    c.fill(tile, grain(c, lerp(hexc('#FFFFFF'), hexc('#E9E9EC'), t), 0.006))
    c.fill(np.abs(tile + 1) - 1, hexc('#000000'), alpha=0.08)
    c.fill(np.abs(tile + 3) - 1.4, hexc('#FFFFFF'), alpha=0.9, mask=np.clip((300 - c.y) / 200, 0, 1))
    return tile

# ---------- A: Segment — an ink citrus cross-section relief on pearl ----------
def icon_a(size=1024):
    c = Canvas(size); pearl_tile(c)
    cx, cy, R = 512, 512, 300
    rind = sub(circle(c, cx, cy, R), circle(c, cx, cy, R - 30))
    segs = segments(c, cx, cy, R - 52, 9, 22, 46, 26)
    mark = union(rind, segs)
    c.fill(mark, hexc('#000000'), soft=40, alpha=0.18)                     # soft cast
    c.fill(mark, sculpt(c, mark, 16, hexc('#0E0E10'), hexc('#4A4A4E')))
    # whisper of yuzu: the hub catches a tiny warm light
    c.fill(circle(c, cx, cy, 15), hexc('#F3D35B'), alpha=0.9)
    return c.image()

# ---------- B: Orb — a pearl sphere with a single ink leaf, on ink ----------
def icon_b(size=1024):
    c = Canvas(size); ink_tile(c)
    cx, cy, R = 512, 548, 258
    c.fill(ellipse(c, cx, cy + R - 6, 210, 30), hexc('#000000'), soft=60, alpha=0.55)
    dx = (c.x - cx) / R; dy = (c.y - cy) / R
    rr = np.clip(dx * dx + dy * dy, 0, 1); nz = np.sqrt(1 - rr)
    L = np.array([-0.35, -0.6, 0.72]); L /= np.linalg.norm(L)
    diff = np.clip(dx * L[0] + dy * L[1] + nz * L[2], 0, 1)
    col = lerp(hexc('#8E8E93'), hexc('#F7F6F2'), (diff ** 0.8)[..., None])
    # the whisper: faint yuzu warmth in the lit hemisphere only
    warm = np.clip(diff - 0.5, 0, 1)[..., None] * 0.32
    col = lerp(col, hexc('#FBE7A1'), warm)
    rim = (1 - nz) ** 3 * np.clip(dy, 0, 1)
    col[..., :3] += rim[..., None] * 0.10
    c.fill(circle(c, cx, cy, R), grain(c, np.clip(col, 0, 1), 0.012))
    # the one detail: a tiny stem dimple at the pole, catching a whisper of yuzu
    px_, py_ = cx - 10, cy - R * 0.80
    c.fill(ellipse(c, px_, py_ + 3, 24, 10), hexc('#6E6E73'), soft=10, alpha=0.55)
    c.fill(ellipse(c, px_, py_, 13, 6), hexc('#E8C64A'), alpha=0.95)
    return c.image()

# ---------- C: Ring — the product: eight soft petals, one chosen in ink ----------
def ring_sdf(c, cx, cy, Ro, Ri, n, gap, k):
    sp = wedge_gap(c, cx, cy, n, gap, rot=-np.pi / 2)
    return round_inter(round_inter(circle(c, cx, cy, Ro), -sp, k), -circle(c, cx, cy, Ri), k * 0.7)

def icon_c(size=1024, dark=False):
    c = Canvas(size)
    ink_tile(c) if dark else pearl_tile(c)
    cx, cy, Ro, Ri, n = 512, 512, 304, 168, 8
    ann = ring_sdf(c, cx, cy, Ro, Ri, n, 30, 30)
    ang = (angle(c, cx, cy) + np.pi / 2) % (2 * np.pi)
    idx = np.floor(ang / (2 * np.pi / n)).astype(int)
    sel = np.where(idx == 0, ann, 1e3); rest = np.where(idx == 0, 1e3, ann)
    if dark:
        c.fill(rest, hexc('#000000'), soft=30, alpha=0.5)
        c.fill(rest, sculpt(c, rest, 18, hexc('#2A2A2D'), hexc('#4C4C50')))
        c.fill(sel, hexc('#000000'), soft=30, alpha=0.5)
        c.fill(sel, sculpt(c, sel, 18, hexc('#B9B8B2'), hexc('#FBFAF6')))
        hub = sculpt(c, circle(c, cx, cy, 54), 20, hexc('#B9B8B2'), hexc('#FBFAF6'))
    else:
        c.fill(rest, hexc('#000000'), soft=34, alpha=0.16)
        c.fill(rest, sculpt(c, rest, 18, hexc('#C4C4CA'), hexc('#ECECEF')))
        c.fill(np.abs(rest) - 0.8, hexc('#000000'), alpha=0.08)
        c.fill(sel, hexc('#000000'), soft=34, alpha=0.30)
        c.fill(sel, sculpt(c, sel, 18, hexc('#0E0E10'), hexc('#48484C')))
        hub = sculpt(c, circle(c, cx, cy, 54), 20, hexc('#0E0E10'), hexc('#48484C'))
    c.fill(circle(c, cx, cy + 6, 54), hexc('#000000'), soft=24, alpha=0.3)
    c.fill(circle(c, cx, cy, 54), hub)
    c.fill(circle(c, cx, cy, 13), hexc('#F3D35B'), alpha=0.95)   # whisper of yuzu
    return c.image()

def glyph(kind, px=36):
    c = Canvas(px * 8, design=1024); cx = cy = 512
    if kind == 'a':
        d = union(sub(circle(c, cx, cy, 470), circle(c, cx, cy, 404)), segments(c, cx, cy, 352, 9, 64, 64, 34))
    elif kind == 'b':
        d = union(circle(c, cx, cy + 50, 410), 1e3 + 0 * c.x)
        d = sub(d, ellipse(c, cx - 10, cy + 50 - 410 * 0.8, 90, 44))
    else:
        Ro, Ri, gap, k = 400, 210, 88, 36
        ann = ring_sdf(c, cx, cy, Ro, Ri, 8, gap, k)
        ang = (angle(c, cx, cy) + np.pi / 2) % (2 * np.pi)
        idx = np.floor(ang / (np.pi / 4)).astype(int)
        mid = -np.pi / 2 + np.pi / 8; off = 70
        class P: pass
        p = P(); p.x = c.x - np.cos(mid) * off; p.y = c.y - np.sin(mid) * off
        a2 = (angle(p, cx, cy) + np.pi / 2) % (2 * np.pi)
        lifted = ring_sdf(p, cx, cy, Ro + 20, Ri, 8, gap, k)
        lifted = np.where(np.floor(a2 / (np.pi / 4)) == 0, lifted, 1e3)
        d = union(union(np.where(idx == 0, 1e3, ann), lifted), circle(c, cx, cy, 96))
    c.fill(d, hexc('#000000'))
    return c.image().resize((px, px), Image.LANCZOS)

if __name__ == '__main__':
    import sys
    out = '/workspace/yuzu/design/src/r2'
    import os; os.makedirs(out, exist_ok=True)
    for name, fn in [('a', icon_a), ('b', icon_b), ('c', icon_c), ('cd', lambda: icon_c(dark=True))]:
        fn().save(f'{out}/icon-{name}-1024.png'); print(name)
    for k in 'abc':
        for z in (18, 36): glyph(k, z).save(f'{out}/glyph-{k}-{z}.png')
