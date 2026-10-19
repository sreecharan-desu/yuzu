import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from typo import text, rrect, shadow
import washes
R2 = '/workspace/yuzu/design/src/r2'; OUT = '/workspace/yuzu/design'
INK = '#1d1d1f'; SOFT = '#6e6e73'; MUTE = '#86868b'

OPTS = {
  'a': dict(name='Segment', icon='a', glyph='a', blurb=[('A citrus cross-section, drawn ', False), ('once', True), (', in ink on pearl.', False)],
            note='Most literal. Reads instantly as yuzu; least specific to the ring.'),
  'b': dict(name='Orb', icon='b', glyph='b', blurb=[('A pearl sphere, softly lit, with a ', False), ('single', True), (' warm pole.', False)],
            note='Most sculptural and calm. Abstract; weakest at 16 px.'),
  'c': dict(name='Ring', icon='cd', alt='c', glyph='c', blurb=[('Eight soft petals. One is ', False), ('chosen', True), ('.', False)],
            note='The product itself: the ring you open under the cursor. Strongest at every size.'),
}
def icon(k, s): return Image.open(f'{R2}/icon-{k}-1024.png').resize((s, s), Image.LANCZOS)
def glyph(k, s, color):
    g = Image.open(f'{R2}/glyph-{k}-36.png').resize((s, s), Image.LANCZOS)
    solid = Image.new('RGBA', g.size, color); solid.putalpha(g.split()[3]); return solid

def menubar(w, dark, gk):
    h = 48  # 24 pt @2x
    bar = washes.render('graphite' if dark else 'pearl', w, h).copy()
    ov = Image.new('RGBA', (w, h), (30, 30, 32, 150) if dark else (255, 255, 255, 150)); bar.alpha_composite(ov)
    fg = '#F5F5F7' if dark else INK
    x = w - 24
    for s in ['Mon 19 Oct  8:16 PM']:
        tw = text(bar, (x, 32), s, 26, fg, 500, -0.005, anchor="r", tight=False); x = int(x - tw - 34)
    # quiet system-like shapes (generic, not Apple glyphs)
    d = ImageDraw.Draw(bar)
    for i in range(2):
        d.rounded_rectangle((x - 30, 14, x, 34), 6, outline=fg, width=3); x -= 58
    g = glyph(gk, 36, fg)
    hl = Image.new('RGBA', (60, 40), (0, 0, 0, 0)); ImageDraw.Draw(hl).rounded_rectangle((0, 0, 59, 39), 10, fill=(255, 255, 255, 40) if dark else (0, 0, 0, 22))
    bar.alpha_composite(hl, (x - 52, 4)); bar.alpha_composite(g, (x - 40, 6))
    return bar

def dock(w, h, k, dark):
    bg = washes.render('graphite' if dark else 'mist', w, h)
    n = 7; s = 128; gap = 22; dw = n * s + (n + 1) * gap; dh = s + 2 * gap
    x0 = (w - dw) // 2; y0 = h - dh - 30
    shadow(bg, (x0, y0, x0 + dw, y0 + dh), 44, blur=30, alpha=60 if dark else 30, dy=10)
    glass = bg.crop((x0, y0, x0 + dw, y0 + dh)).filter(ImageFilter.GaussianBlur(24))
    tint = Image.new('RGBA', glass.size, (60, 60, 64, 120) if dark else (255, 255, 255, 140)); glass.alpha_composite(tint)
    m = Image.new('L', glass.size, 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, dw - 1, dh - 1), 44, fill=255)
    bg.paste(glass, (x0, y0), m)
    ImageDraw.Draw(bg).rounded_rectangle((x0, y0, x0 + dw, y0 + dh), 44, outline=(255, 255, 255, 50) if dark else (0, 0, 0, 20), width=2)
    for i in range(n):
        x = x0 + gap + i * (s + gap); y = y0 + gap
        if i == 3:
            bg.alpha_composite(icon(k, s), (x, y))
            ImageDraw.Draw(bg).ellipse((x + s // 2 - 4, y0 + dh - 12, x + s // 2 + 4, y0 + dh - 4), fill=(245, 245, 247) if dark else (29, 29, 31))
        else:  # neutral stand-ins: hairline pearl/graphite tiles, deliberately quiet
            t = Image.new('RGBA', (s, s), (0, 0, 0, 0)); dd = ImageDraw.Draw(t)
            dd.rounded_rectangle((10, 10, s - 10, s - 10), 26, fill=(58, 58, 62, 255) if dark else (250, 250, 251, 255), outline=(0, 0, 0, 24))
            bg.alpha_composite(t, (x, y))
    return bg

def strip(w, k, dark):
    bgc = (29, 29, 31, 255) if dark else (245, 245, 247, 255)
    im = Image.new('RGBA', (w, 300), bgc)
    sizes = [16, 32, 64, 128, 256]; x = (w - (sum(sizes) + 56 * 4)) // 2
    for s in sizes:
        im.alpha_composite(icon(k, s), (x, 260 - s))
        text(im, (x + s // 2, 292), f'{s}', 20, '#a1a1a6' if dark else MUTE, 500, 0, anchor='c', tight=False)
        x += s + 56
    return im

def sheet(key):
    o = OPTS[key]; W, H = 2400, 1560
    im = Image.new('RGBA', (W, H), (255, 255, 255, 255))
    text(im, (120, 150), f'Option {key.upper()}', 30, MUTE, 500, 0.005)
    text(im, (120, 240), o['name'], 84, INK, 500, -0.034)
    text(im, (120, 300), o['blurb'], 34, SOFT, 450, -0.005)
    # hero icon on a step card
    rrect(im, (120, 360, 900, 1140), 48, (245, 245, 247, 255))
    im.alpha_composite(icon(o['icon'], 640), (190, 430))
    if 'alt' in o:
        im.alpha_composite(icon(o['alt'], 150), (730, 970))
    # strips
    text(im, (980, 400), 'Sizes', 26, INK, 600, -0.01)
    for i, dark in enumerate([False, True]):
        s = strip(1300, o['icon'] if dark or 'alt' not in o else o['icon'], dark)
        m = Image.new('L', s.size, 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, s.width - 1, s.height - 1), 28, fill=255)
        im.paste(s, (980, 420 + i * 320), m)
    # menubar
    text(im, (120, 1220), 'Menu bar', 26, INK, 600, -0.01)
    for i, dark in enumerate([False, True]):
        b = menubar(760, dark, o['glyph']); m = Image.new('L', b.size, 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, b.width - 1, b.height - 1), 14, fill=255)
        im.paste(b, (120, 1250 + i * 70), m)
    # dock
    text(im, (980, 1100), 'Dock', 26, INK, 600, -0.01)
    for i, dark in enumerate([False, True]):
        d = dock(1300, 220, o['icon'], dark).resize((640, 108), Image.LANCZOS) if False else dock(1300, 230, o['icon'], dark)
        d = d.resize((640, 113), Image.LANCZOS)
        m = Image.new('L', d.size, 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, d.width - 1, d.height - 1), 20, fill=255)
        im.paste(d, (980 + i * 660, 1130), m)
    text(im, (980, 1330), o['note'], 28, SOFT, 450, -0.005)
    text(im, (120, 1500), [('Yuzu', False), ('  ·  logo exploration  ·  ink / pearl, a whisper of yuzu', False)], 22, MUTE, 500, 0)
    im.convert('RGB').save(f'{OUT}/logo-option-{key}.png')
    return im

def overview():
    W, H = 2400, 1400
    im = Image.new('RGBA', (W, H), (255, 255, 255, 255))
    text(im, (W // 2, 170), [('Three marks, ', False), ('one', True), (' quiet world.', False)], 84, INK, 500, -0.034, anchor='c')
    text(im, (W // 2, 240), 'Ink and pearl first. Yuzu yellow only as a whisper.', 34, SOFT, 450, -0.005, anchor='c')
    for i, k in enumerate('abc'):
        o = OPTS[k]; x = 120 + i * 740
        rrect(im, (x, 320, x + 680, 1080), 40, (245, 245, 247, 255), outline=(232, 232, 236, 255))
        im.alpha_composite(icon(o['icon'], 440), (x + 120, 380))
        xs = x + 120
        for s in (16, 32, 64):
            im.alpha_composite(icon(o['icon'], s), (xs, 940 - s)); xs += s + 36
        im.alpha_composite(glyph(o['glyph'], 36, INK), (xs + 40, 904))
        t = Image.new('RGBA', (90, 52), (29, 29, 31, 255)); im.alpha_composite(t, (xs + 120, 896)); im.alpha_composite(glyph(o['glyph'], 36, '#F5F5F7'), (xs + 147, 904))
        text(im, (x + 40, 1180), [(f'{k.upper()}  ', False), (o['name'], False)] , 44, INK, 500, -0.02)
        words = o['note'].split(); lines = ['']
        for wd in words:
            if len(lines[-1]) + len(wd) > 50: lines.append('')
            lines[-1] += (' ' if lines[-1] else '') + wd
        for j, ln in enumerate(lines): text(im, (x + 40, 1232 + j * 36), ln, 26, SOFT, 450, -0.005)
        if k == 'c':
            pill_w = 220; rrect(im, (x + 680 - pill_w - 30, 340, x + 680 - 30, 392), 26, (29, 29, 31, 255))
            text(im, (x + 680 - 30 - pill_w // 2, 375), 'Recommended', 24, '#ffffff', 500, -0.005, anchor='c')
    im.convert('RGB').save(f'{OUT}/logo-options.png')

if __name__ == '__main__':
    for k in 'abc': sheet(k)
    overview()
