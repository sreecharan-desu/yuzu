import numpy as np, sys
sys.path.insert(0, '/workspace/yuzu/design/src')
from iconkit import *

CX = CY = 512; HALF = 412
CITRUS = hexc('#F4B223'); CITRUS_DEEP = hexc('#D98E0B'); CITRUS_LIGHT = hexc('#FFD566')

def base(c, top, bottom, edge_light=0.10, edge_dark=0.10):
    d1, d2 = tile_shadow(c)
    c.fill(d1, hexc('#000000'), soft=48, alpha=0.30)
    c.fill(d2, hexc('#000000'), soft=6, alpha=0.20)
    tile = squircle(c, CX, CY, HALF)
    c.fill(tile, vgrad(c, top, bottom))
    # hairline edge and a faint top light, like a real material edge
    ring = np.abs(tile + 1.5) - 1.5
    c.fill(ring, hexc('#000000'), alpha=edge_dark)
    toplight = np.clip((300 - c.y) / 200, 0, 1)
    c.fill(np.abs(tile + 3) - 1.5, hexc('#FFFFFF'), alpha=edge_light, mask=toplight)
    return tile

def ellipse(c, cx, cy, a, b):
    return (np.hypot((c.x - cx) / a, (c.y - cy) / b) - 1) * min(a, b)

def segments(c, cx, cy, r, count, gap, hub, k, rot=-np.pi / 2):
    sp = wedge_gap(c, cx, cy, count, gap, rot)
    d = round_inter(circle(c, cx, cy, r), -sp, k)
    return round_inter(d, -circle(c, cx, cy, hub), k * 0.6)

def radial(c, cx, cy, r, inner, outer, power=1.0):
    t = np.clip(np.hypot(c.x - cx, c.y - cy) / r, 0, 1)[..., None] ** power
    return lerp(inner, outer, t)

# ---------- A: Segment (yuzu cross-section) ----------
def icon_a(size=1024):
    c = Canvas(size)
    tile = base(c, hexc('#FCFAF6'), hexc('#EEEAE2'))
    cx, cy, R = 512, 524, 292
    c.fill(ellipse(c, cx, cy + 250, 230, 46), hexc('#5A3A00'), soft=70, alpha=0.16)       # contact shadow
    c.fill(circle(c, cx, cy + 8, R), hexc('#7A4A00'), soft=40, alpha=0.18)                 # body shadow
    c.fill(circle(c, cx, cy, R), vgrad(c, hexc('#F7BC2E'), hexc('#DE930C'), cy - R, cy + R))  # rind
    c.fill(circle(c, cx, cy, R - 18), vgrad(c, hexc('#FFF8E6'), hexc('#F8EACB'), cy - R, cy + R))  # pith
    seg = segments(c, cx, cy, R - 40, 9, 16, 44, 24, rot=-np.pi / 2)
    pulp = radial(c, cx, cy, R - 40, hexc('#FFD45C'), hexc('#F6B32A'), 1.2)
    c.fill(seg, pulp)
    # soft light: brighter at the top of the slice, a touch of shade at the bottom
    c.fill(seg, hexc('#FFFFFF'), alpha=0.16, mask=np.clip((cy - c.y) / R, 0, 1) ** 1.5)
    c.fill(seg, hexc('#9A5A00'), alpha=0.12, mask=np.clip((c.y - cy) / R, 0, 1) ** 1.5)
    # inner edge of the rind catches light
    c.fill(np.abs(circle(c, cx, cy, R - 1.5)) - 1.5, hexc('#FFFFFF'), alpha=0.25, mask=np.clip((cy - c.y) / R, 0, 1))
    return c.image()

# ---------- B: Orb (soft citrus with one precise detail) ----------
def icon_b(size=1024):
    return _icon_b(size).image()

def _icon_b(size=1024):
    c = Canvas(size)
    base(c, hexc('#FBF9F5'), hexc('#ECE8E1'))
    cx, cy, R = 512, 552, 262
    c.fill(ellipse(c, cx, cy + R - 4, 200, 30), hexc('#4A3000'), soft=64, alpha=0.30)
    dx = (c.x - cx) / R; dy = (c.y - cy) / R
    rr = np.clip(dx * dx + dy * dy, 0, 1); nz = np.sqrt(1 - rr)
    L = np.array([-0.28, -0.52, 0.81]); L /= np.linalg.norm(L)
    diff = np.clip(dx * L[0] + dy * L[1] + nz * L[2], 0, 1)
    col = lerp(hexc('#D2810C'), hexc('#FFC53A'), (diff ** 0.7)[..., None])
    # warm bounce from the surface below and a soft rim, no gloss
    bounce = np.clip(dy, 0, 1) ** 2.5 * (1 - nz) * 0.30
    col[..., :3] += bounce[..., None] * np.array([0.40, 0.25, 0.05])
    rng = np.random.default_rng(7)
    col[..., :3] *= (1 + 0.014 * rng.normal(0, 1, (c.n, c.n)))[..., None]
    c.fill(circle(c, cx, cy, R), np.clip(col, 0, 1))
    # the one precise detail: a flat geometric leaf (vesica) resting on top
    lx, ly = cx + 54, cy - R + 2
    a = np.deg2rad(-30)
    class P: pass
    p = P(); p.x = (c.x - lx) * np.cos(a) - (c.y - ly) * np.sin(a); p.y = (c.x - lx) * np.sin(a) + (c.y - ly) * np.cos(a)
    p.x = p.x - 66
    leaf = inter(circle(p, 0, 46, 80), circle(p, 0, -46, 80))
    c.fill(leaf - 0, hexc('#000000'), soft=18, alpha=0.18)
    c.fill(leaf, vgrad(c, hexc('#7F8D4C'), hexc('#58652E'), ly - 70, ly + 40))
    c.fill(np.maximum(np.abs(p.y) - 1.4, np.abs(p.x) - 50), hexc('#3D461F'), alpha=0.45)
    return c

# ---------- C: Ring (the product's ring, one segment chosen) ----------
def icon_c(size=1024):
    c = Canvas(size)
    base(c, hexc('#2D2B28'), hexc('#1A1917'), edge_light=0.16, edge_dark=0.4)
    cx, cy = 512, 516; Ro, Ri, n, gap, k = 300, 168, 8, 30, 30
    sp = wedge_gap(c, cx, cy, n, gap, rot=-np.pi / 2)
    ann = round_inter(round_inter(circle(c, cx, cy, Ro), -sp, k), -circle(c, cx, cy, Ri), k * 0.7)
    ang = (angle(c, cx, cy) + np.pi / 2) % (2 * np.pi)
    idx = np.floor(ang / (2 * np.pi / n)).astype(int)
    chosen = (idx == 0)
    # shadows under petals
    class Q: pass
    q = Q(); q.x = c.x; q.y = c.y - 10
    sh = round_inter(round_inter(circle(q, cx, cy, Ro), -wedge_gap(q, cx, cy, n, gap, rot=-np.pi / 2), k), -circle(q, cx, cy, Ri), k * 0.7)
    c.fill(sh, hexc('#000000'), soft=28, alpha=0.45)
    neutral = vgrad(c, hexc('#4A4743'), hexc('#3A3834'), cy - Ro, cy + Ro)
    c.fill(ann, neutral, mask=(~chosen).astype(float))
    accent = vgrad(c, hexc('#FFC848'), hexc('#EE9F12'), cy - Ro, cy)
    c.fill(ann, accent, mask=chosen.astype(float))
    # top light on every petal edge
    c.fill(np.abs(ann + 2) - 1.4, hexc('#FFFFFF'), alpha=0.16, mask=np.clip((cy - c.y) / Ro + 0.3, 0, 1))
    # hub
    c.fill(circle(c, cx, cy + 6, 50), hexc('#000000'), soft=24, alpha=0.4)
    c.fill(circle(c, cx, cy, 50), vgrad(c, hexc('#F6F3EC'), hexc('#DCD7CD'), cy - 50, cy + 50))
    return c.image()

# ---------- menu bar template glyphs (black + alpha, 18 pt box, drawn in a 1024 space) ----------
def glyph(kind, px=36):
    """Monochrome menu bar template glyph (black on transparent)."""
    c = Canvas(px * 8, design=1024)
    cx = cy = 512
    if kind == 'a':
        d = sub(circle(c, cx, cy, 470), circle(c, cx, cy, 400))
        d = union(d, segments(c, cx, cy, 350, 8, 70, 60, 36))
    elif kind == 'b':
        cy2 = cy + 70
        d = circle(c, cx, cy2, 400)
        a = np.deg2rad(-30); lx, ly = cx + 70, cy2 - 400
        class P: pass
        p = P(); p.x = (c.x - lx) * np.cos(a) - (c.y - ly) * np.sin(a); p.y = (c.x - lx) * np.sin(a) + (c.y - ly) * np.cos(a)
        p.x = p.x - 130
        leaf = inter(circle(p, 0, 80, 140), circle(p, 0, -80, 140))
        halo = leaf - 56
        d = union(sub(d, halo), leaf)
    else:
        Ro, Ri, k, gap = 400, 200, 34, 92
        ang = (angle(c, cx, cy) + np.pi / 2) % (2 * np.pi)
        idx = np.floor(ang / (np.pi / 4)).astype(int)
        sp = wedge_gap(c, cx, cy, 8, gap, rot=-np.pi / 2)
        ring = round_inter(round_inter(circle(c, cx, cy, Ro), -sp, k), -circle(c, cx, cy, Ri), k * 0.7)
        # chosen petal (12 to 1:30) lifted outward
        mid = -np.pi / 2 + np.pi / 8; off = 74
        class P: pass
        p = P(); p.x = c.x - np.cos(mid) * off; p.y = c.y - np.sin(mid) * off
        sp2 = wedge_gap(p, cx, cy, 8, gap, rot=-np.pi / 2)
        a2 = (angle(p, cx, cy) + np.pi / 2) % (2 * np.pi)
        lifted = round_inter(round_inter(circle(p, cx, cy, Ro + 30), -sp2, k), -circle(p, cx, cy, Ri), k * 0.7)
        lifted = np.where(np.floor(a2 / (np.pi / 4)) == 0, lifted, 1e3)
        d = np.where(idx == 0, 1e3, ring)
        d = union(union(d, lifted), circle(c, cx, cy, 96))
    c.fill(d, hexc('#000000'))
    return c.image().resize((px, px), Image.LANCZOS)

if __name__ == '__main__':
    out = '/workspace/yuzu/design/src'
    for name, fn in [('a', icon_a), ('b', icon_b), ('c', icon_c)]:
        fn().save(f'{out}/icon-{name}-1024.png'); glyph(name, 36).save(f'{out}/glyph-{name}-36.png'); glyph(name, 18).save(f'{out}/glyph-{name}-18.png')
        print(name)
