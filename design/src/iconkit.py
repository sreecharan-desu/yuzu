"""Tiny SDF renderer for icon design: crisp analytic anti-aliasing, soft shadows, simple lighting."""
import numpy as np
from PIL import Image

def hexc(h, a=1.0):
    h = h.lstrip('#'); return np.array([int(h[i:i+2], 16) / 255 for i in (0, 2, 4)] + [a])

def srgb_to_lin(c): return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
def lin_to_srgb(c): c = np.clip(c, 0, 1); return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)

class Canvas:
    """Linear-light premultiplied RGBA canvas, coordinates in a 1024 design space (y down)."""
    def __init__(self, size=1024, design=1024):
        self.n = size; self.k = size / design
        ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
        self.x = (xs + 0.5) / self.k; self.y = (ys + 0.5) / self.k
        self.px = 1 / self.k                      # one pixel in design units
        self.buf = np.zeros((size, size, 4))

    def cov(self, d, soft=0.0):
        """Coverage from a signed distance (negative inside). soft widens the edge (design units)."""
        w = max(self.px, soft)
        return np.clip(0.5 - d / w, 0, 1) if soft == 0 else smooth(np.clip(0.5 - d / w, 0, 1))

    def fill(self, d, color, soft=0.0, alpha=1.0, mask=None):
        a = self.cov(d, soft) * alpha * (color[..., 3] if np.ndim(color) == 3 else color[3])
        if mask is not None: a = a * mask
        rgb = srgb_to_lin(color[..., :3] if np.ndim(color) == 3 else color[:3])
        a3 = a[..., None]
        self.buf[..., :3] = rgb * a3 + self.buf[..., :3] * (1 - a3)
        self.buf[..., 3] = a + self.buf[..., 3] * (1 - a)

    def image(self):
        a = self.buf[..., 3:4]
        rgb = np.where(a > 0, self.buf[..., :3] / np.maximum(a, 1e-6), 0)
        out = np.concatenate([lin_to_srgb(rgb), a], axis=-1)
        return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGBA')

def smooth(t): return t * t * (3 - 2 * t)

# ---- SDFs (design units, y down) ----
def circle(c, cx, cy, r): return np.hypot(c.x - cx, c.y - cy) - r

def squircle(c, cx, cy, half, n=4.6):
    """Superellipse approximating Apple's continuous-corner icon shape."""
    ax = np.abs(c.x - cx) / half; ay = np.abs(c.y - cy) / half
    f = (ax ** n + ay ** n) ** (1 / n)
    # first-order distance correction
    gx = np.where(ax > 0, ax ** (n - 1), 0); gy = np.where(ay > 0, ay ** (n - 1), 0)
    g = np.hypot(gx, gy) / np.maximum(f ** (n - 1), 1e-9)
    return (f - 1) * half / np.maximum(g, 1e-6)

def rounded_box(c, cx, cy, hw, hh, r):
    qx = np.abs(c.x - cx) - hw + r; qy = np.abs(c.y - cy) - hh + r
    return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - r

def angle(c, cx, cy): return np.arctan2(c.y - cy, c.x - cx)

def wedge_gap(c, cx, cy, count, gap, rot=-np.pi / 2):
    """Distance to the nearest of `count` radial spokes of half-width gap/2 (for cutting segments)."""
    a = angle(c, cx, cy) - rot
    step = 2 * np.pi / count
    a = (a + step / 2) % step - step / 2           # angle to nearest spoke... offset so spokes sit between segments
    r = np.hypot(c.x - cx, c.y - cy)
    return np.abs(np.sin(a)) * r - gap / 2           # perpendicular distance to spoke line

def union(a, b): return np.minimum(a, b)
def inter(a, b): return np.maximum(a, b)
def sub(a, b): return np.maximum(a, -b)

def lerp(a, b, t): return a + (b - a) * t

def vgrad(c, top, bottom, y0=100, y1=924):
    t = np.clip((c.y - y0) / (y1 - y0), 0, 1)[..., None]
    return lerp(top, bottom, t)

def tile_shadow(c, cx=512, cy=512, half=412):
    """Apple-style icon drop shadow: soft and short, slightly below."""
    d1 = squircle(c, cx, cy + 10, half - 6)
    d2 = squircle(c, cx, cy + 4, half - 2)
    return d1, d2

def save(img, path, size=None):
    if size: img = img.resize((size, size), Image.LANCZOS)
    img.save(path); return img


def round_inter(a, b, r):
    """Intersection with rounded convex corners (exact-ish outside)."""
    ux = np.maximum(r + a, 0); uy = np.maximum(r + b, 0)
    return np.minimum(-r, np.maximum(a, b)) + np.hypot(ux, uy)
