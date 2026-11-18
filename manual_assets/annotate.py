"""Annotate screenshots: orange rounded outline per target + numbered circle.
usage: annotate.py <shots_dir> <out_dir> [--only name1,name2]
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

ORANGE = (242, 160, 7)  # SDICS amber
NAVY = (15, 20, 25)
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
rects = json.load(open(os.path.join(src, 'rects.json')))
FONT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fonts', 'Lexend-700.ttf')  # the apps' font

for name, marks in rects.items():
    p = os.path.join(src, name + '.png')
    if not os.path.exists(p):
        continue
    im = Image.open(p).convert('RGB')
    W, H = im.size
    s = W / 720  # scale stroke/circle to the image
    lw = max(3, round(5 * s)) if W < 1000 else 4
    r = round(26 * s) if W < 1000 else 21
    font = ImageFont.truetype(FONT, round(r * 1.25))
    d = ImageDraw.Draw(im)
    for k, box in marks.items():
        if box is None:
            print('MISSING', name, k)
            continue
        pad = round(6 * s) if W < 1000 else 4
        l, t, rr, b = box
        l, t = max(lw, l - pad), max(lw, t - pad)
        rr, b = min(W - lw, rr + pad), min(H - lw, b + pad)
        d.rounded_rectangle([l, t, rr, b], radius=round(14 * s) if W < 1000 else 8, outline=ORANGE, width=lw)
        cx = min(max(l - r * 0.45, r + 2), W - r - 2)
        cy = min(max(t - r * 0.45, r + 2), H - r - 2)
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ORANGE, outline='white', width=max(2, lw // 2))
        d.text((cx, cy + 1), k, fill=NAVY, font=font, anchor='mm')
    im.save(os.path.join(out, name + '.png'))
print('done', out)
