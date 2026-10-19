"""Quiet premium backdrops: pearl / mist / soft greys with gentle warm-cool washes and fine grain."""
import numpy as np
from PIL import Image

def _lin(h):
    c = np.array([int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)])
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
def _srgb(c):
    c = np.clip(c, 0, 1); return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)
# OKLab for perceptually even blends
M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929], [0.2119034982, 0.6806995451, 0.1073969566], [0.0883024619, 0.2817188376, 0.6299787005]])
M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468], [1.9779984951, -2.4285922050, 0.4505937099], [0.0259040371, 0.7827717662, -0.8086757660]])
def to_ok(rgb): return np.cbrt(rgb @ M1.T) @ M2.T
def from_ok(lab): return (np.linalg.solve(M2, lab.reshape(-1, 3).T).T.reshape(lab.shape) ** 3) @ np.linalg.inv(M1).T

PRESETS = {
    # name: base, list of (colour, cx, cy, radius, strength) soft washes in OKLab
    'pearl':    ('#F5F5F7', [('#FFFFFF', .30, .20, .70, .9), ('#EEE9E1', .85, .90, .75, .7), ('#E9EDF3', .05, .95, .60, .5)]),
    'mist':     ('#EDEEF1', [('#F8F9FB', .50, .10, .80, .9), ('#DDE3EA', .90, .80, .70, .6), ('#E9E6E1', .10, .70, .60, .5)]),
    'linen':    ('#F3F0EA', [('#FBFAF7', .40, .15, .75, .9), ('#E9E1D3', .90, .90, .70, .6), ('#F1EEE8', .00, .60, .55, .4)]),
    'graphite': ('#1D1D1F', [('#2C2C2F', .30, .10, .80, .9), ('#151516', .90, .95, .70, .8), ('#23252A', .05, .90, .60, .6)]),
    'dusk':     ('#202124', [('#2E2D2B', .70, .15, .70, .8), ('#1A1C21', .10, .90, .70, .8), ('#26272B', .50, .55, .50, .4)]),
}

def render(name, w, h, grain=0.010, seed=11):
    base, washes = PRESETS[name]
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    u = xs / w; v = ys / h * (h / w)
    lab = np.broadcast_to(to_ok(_lin(base)), (h, w, 3)).copy()
    for col, cx, cy, r, s in washes:
        d = np.hypot(u - cx, v - cy * (h / w)) / r
        t = (np.exp(-d * d * 2.2) * s)[..., None]
        lab = lab + (to_ok(_lin(col)) - lab) * t
    rgb = from_ok(lab)
    out = _srgb(rgb)
    rng = np.random.default_rng(seed)
    n = rng.normal(0, 1, (h, w))
    out = out + (n * grain)[..., None] * (0.6 + 0.4 * out)   # fine luminance grain, also kills banding
    return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), 'RGB').convert('RGBA')

if __name__ == '__main__':
    tiles = [render(k, 480, 300) for k in PRESETS]
    s = Image.new('RGBA', (480 * len(tiles), 300))
    for i, t in enumerate(tiles): s.paste(t, (i * 480, 0))
    s.save('/workspace/yuzu/design/src/r2/washes.png')
