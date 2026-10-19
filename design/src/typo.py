from PIL import Image, ImageDraw, ImageFont, ImageFilter
FD = '/usr/share/fonts/truetype/sand-box/google/'
def font(size, wght=500, italic=False, tight=True):
    p = FD + ('Inter Tight/InterTight-Italic-VariableFont_wght.ttf' if italic else 'Inter Tight/InterTight-VariableFont_wght.ttf') if tight else \
        FD + ('Inter/Inter-Italic-VariableFont_opsz,wght.ttf' if italic else 'Inter/Inter-VariableFont_opsz,wght.ttf')
    f = ImageFont.truetype(p, size)
    try:
        axes = f.get_variation_axes()
        vals = [wght if a.get('name', b'') in (b'Weight', 'Weight') else (min(max(size, 14), 32) if a.get('name') in (b'Optical size', 'Optical size', b'Optical Size') else a['default']) for a in axes]
        f.set_variation_by_axes(vals)
    except Exception:
        pass
    return f
def width(text, f, track=0.0):
    sz = f.size; w = 0
    for ch in text: w += f.getlength(ch) + track * sz
    return w - track * sz
def text(img, xy, s, size, color='#1d1d1f', wght=500, track=-0.02, italic=False, anchor='l', tight=True):
    """Draw with tracking (em). Runs: list of (str, italic) allowed."""
    runs = s if isinstance(s, list) else [(s, italic)]
    fonts = [font(size, wght, it, tight) for _, it in runs]
    total = sum(width(r, f, track) + track * size for (r, _), f in zip(runs, fonts)) - track * size
    x, y = xy
    if anchor == 'c': x -= total / 2
    elif anchor == 'r': x -= total
    d = ImageDraw.Draw(img)
    for (r, _), f in zip(runs, fonts):
        for ch in r:
            d.text((x, y), ch, font=f, fill=color, anchor='ls'); x += f.getlength(ch) + track * size
    return total
def rrect(img, box, r, fill, outline=None, width_=2):
    ImageDraw.Draw(img).rounded_rectangle(box, r, fill=fill, outline=outline, width=width_)
def shadow(img, box, r, blur=30, alpha=40, dy=12):
    sh = Image.new('RGBA', img.size, (0, 0, 0, 0))
    x0, y0, x1, y1 = box
    ImageDraw.Draw(sh).rounded_rectangle((x0, y0 + dy, x1, y1 + dy), r, fill=(0, 0, 0, alpha))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(blur)))
