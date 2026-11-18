"""Images for the two 1-page guides (frontend/public/guide/clerks and
guide/chiefs): the v5 Field app shots with an orange outline on the thing to
tap, no numbers.
usage: python -I guide_images.py <shots_dir> <guide_dir>"""
import json, os, sys
from PIL import Image, ImageDraw
src, out = sys.argv[1], sys.argv[2]
rects = json.load(open(os.path.join(src, 'rects.json')))
ORANGE = (242, 160, 7)
# guide image: (shot, marks to outline, top of a 1200 px window of the 1560 px shot)
PICK = {
    'clerks': {
        '1-sign-in': ('c01_login', ['1', '2', '3'], 300),
        '2-check-id': ('c11_check_id', ['1', '3'], 0),
        '3-details': ('c12_person_elsewhere', ['2', '3'], 300),
        '4-register': ('c09_confirm', ['2'], 160),
        '5-done': ('c10_success', ['1'], 360),
        '6-roll': ('c07_search', ['1', '2'], 0),
    },
    'chiefs': {
        '1-sign-in': ('01_login', ['1', '2', '4'], 300),
        '2-find': ('05_search', ['1', '2'], 0),
        '3-details': ('06_person', ['4'], 360),
        '4-register': ('07_confirm', ['3'], 160),
        '5-done': ('08_success', ['1'], 360),
        '6-check-id': ('12_check_id', ['1', '4'], 0),
        '7-not-your-area': ('12b_check_id_elsewhere', ['3'], 300),
    },
}
for who, pick in PICK.items():
    d_out = os.path.join(out, who)
    os.makedirs(d_out, exist_ok=True)
    for name, (shot, marks, crop) in pick.items():
        im = Image.open(os.path.join(src, shot + '.png')).convert('RGB')
        d = ImageDraw.Draw(im)
        for k in marks:
            l, t, r, b = rects[shot][k]
            d.rounded_rectangle([l - 8, t - 8, r + 8, b + 8], radius=18, outline=ORANGE, width=7)
        im = im.crop((0, crop, im.width, crop + 1200))
        im = im.resize((360, round(im.height * 360 / im.width)), Image.LANCZOS)
        p = os.path.join(d_out, name + '.jpg')
        im.save(p, quality=82, optimize=True, progressive=True)
        print(who, name, im.size, os.path.getsize(p))
