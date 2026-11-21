"""SDICS chiefs training report (A4 PDF): Thursday 19 and Friday 20 November 2026.

usage: build_training_report.py <analysis.json> <out.pdf>
The JSON holds aggregates only (from the live Checkin and SDICS databases, read-only): per county
and day, chiefs present, SDICS accounts, first SDICS sign-ins, arrivals by hour. Smooth (monotone)
line charts and progress bars; SDICS look (Lexend, green / amber / navy, flag stripe).
"""
import json
import os
import sys

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph

DATA, OUT = sys.argv[1], sys.argv[2]
d = json.load(open(DATA))
FONTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fonts')
for n, w in [('Lexend', 400), ('Lexend-Medium', 500), ('Lexend-Bold', 700)]:
    pdfmetrics.registerFont(TTFont(n, os.path.join(FONTS, f'Lexend-{w}.ttf')))
pdfmetrics.registerFontFamily('Lexend', normal='Lexend', bold='Lexend-Bold', italic='Lexend', boldItalic='Lexend-Bold')

C = colors.HexColor
GREEN, AMBER, BLUE = C('#00875A'), C('#B45309'), C('#2563C9')       # validated series order
NAVY, INK, GREY, LINE, HEAD = C('#0F1419'), C('#111827'), C('#4B5563'), C('#D5DAE1'), C('#EEF1F5')
TINT, AMBER_BG = C('#E0F5ED'), C('#FDF0D7')
W, H = A4
M = 15 * mm
DAYS = {'2026-11-19': 'Thursday 19 Nov', '2026-11-20': 'Friday 20 Nov'}
SHORT = {'2026-11-19': 'Thu 19 Nov', '2026-11-20': 'Fri 20 Nov', '2026-11-21': 'Sat 21 Nov'}

rows = [r for r in d['checkins'] if r['day'] in DAYS]
T = lambda k: sum(r.get(k, 0) for r in rows)
present, with_acct, same_day, signed = T('present'), T('sdics_officer'), T('first_signin_same_day'), T('signed_in_sdics')
female, subchief, out_region = T('female'), T('subchief'), T('present') - T('in_region')
sdics_in_counties = sum(r['sdics_chiefs_in_county'] for r in rows)
onboard = {k: sum(v.values()) for k, v in d['first_login_by_day'].items()}
regs = {k: int(v) for k, v in d['registrations_by_day'].items()}
pct = lambda a, b: f'{round(100 * a / b)}%' if b else '—'
fmt = lambda n: f'{n:,}'

BODY = ParagraphStyle('b', fontName='Lexend', fontSize=8.6, leading=12, textColor=INK)
SMALL = ParagraphStyle('s', parent=BODY, fontSize=7.4, leading=10, textColor=GREY)


def stripe(c, y):
    sw = (W - 2 * M) / 3
    for i, col in enumerate(['#000000', '#BB0000', '#006600']):
        c.setFillColor(C(col)); c.rect(M + i * sw, y, sw, 1.6 * mm, stroke=0, fill=1)


def para(c, text, x, y, w, style=BODY):
    p = Paragraph(text, style); _, h = p.wrap(w, 200 * mm); p.drawOn(c, x, y - h); return y - h


def tile(c, x, y, w, h, label, value, caption, tone=GREEN, prog=None):
    c.setFillColor(colors.white); c.setStrokeColor(LINE); c.setLineWidth(.7)
    c.roundRect(x, y - h, w, h, 3 * mm, stroke=1, fill=1)
    c.setFillColor(tone); c.rect(x, y - h + 3 * mm, 1.2 * mm, h - 6 * mm, stroke=0, fill=1)
    c.setFillColor(GREY); c.setFont('Lexend-Medium', 6.8); c.drawString(x + 4.5 * mm, y - 6 * mm, label.upper())
    c.setFillColor(INK); c.setFont('Lexend-Bold', 19); c.drawString(x + 4.5 * mm, y - 14.5 * mm, value)
    c.setFillColor(GREY); c.setFont('Lexend', 7.2); c.drawString(x + 4.5 * mm, y - 19.5 * mm, caption)
    if prog is not None:
        bar(c, x + 4.5 * mm, y - h + 4 * mm, w - 9 * mm, prog, tone)


def bar(c, x, y, w, v, tone=GREEN, h=2.2 * mm):
    v = max(0, min(1, v))
    c.setFillColor(HEAD); c.roundRect(x, y, w, h, h / 2, stroke=0, fill=1)
    if v > 0:
        c.setFillColor(tone); c.roundRect(x, y, max(h, w * v), h, h / 2, stroke=0, fill=1)


def smooth(c, pts):
    """Monotone cubic (Fritsch–Carlson) through pts, drawn as a reportlab path."""
    n = len(pts)
    p = c.beginPath(); p.moveTo(*pts[0])
    if n == 1:
        return p
    dx = [pts[i + 1][0] - pts[i][0] for i in range(n - 1)]
    m = [(pts[i + 1][1] - pts[i][1]) / (dx[i] or 1) for i in range(n - 1)]
    t = [m[0]] + [0 if m[i - 1] * m[i] <= 0 else (m[i - 1] + m[i]) / 2 for i in range(1, n - 1)] + [m[-1]]
    for i in range(n - 1):
        if m[i] == 0:
            t[i] = t[i + 1] = 0; continue
        a, b = t[i] / m[i], t[i + 1] / m[i]
        if a * a + b * b > 9:
            s = 3 / (a * a + b * b) ** .5; t[i], t[i + 1] = s * a * m[i], s * b * m[i]
    for i in range(n - 1):
        k = dx[i] / 3
        p.curveTo(pts[i][0] + k, pts[i][1] + k * t[i], pts[i + 1][0] - k, pts[i + 1][1] - k * t[i + 1], *pts[i + 1])
    return p


def line_chart(c, x, y, w, h, title, labels, series, note=None, peaks=True):
    """series: [(name, colour, values)] — one axis, 2px smooth lines, legend + end labels."""
    c.setFillColor(colors.white); c.setStrokeColor(LINE); c.setLineWidth(.7)
    c.roundRect(x, y - h, w, h, 3 * mm, stroke=1, fill=1)
    c.setFillColor(INK); c.setFont('Lexend-Bold', 9.5); c.drawString(x + 5 * mm, y - 7 * mm, title)
    lx, ly = x + 5 * mm, y - 11.6 * mm
    for name, col, _ in series:
        wname = 9 * mm + pdfmetrics.stringWidth(name, 'Lexend', 7)
        if lx + wname > x + w - 4 * mm:  # wrap the legend
            lx, ly = x + 5 * mm, ly - 4 * mm
        c.setStrokeColor(col); c.setLineWidth(2); c.line(lx, ly, lx + 5 * mm, ly)
        c.setFillColor(GREY); c.setFont('Lexend', 7); c.drawString(lx + 6.5 * mm, ly - 0.8 * mm, name)
        lx += wname
    px0, px1 = x + 12 * mm, x + w - (40 * mm if not peaks else 22 * mm)
    py0, py1 = y - h + 13 * mm, y - (21 * mm if len(series) > 2 else 17 * mm)
    top = max(v for _, _, vs in series for v in vs) or 1
    nice = next(n for n in [5, 10, 20, 25, 50, 100, 150, 200, 250, 300, 400, 500, 750, 1000] if n >= top)
    c.setFont('Lexend', 6.4)
    for f in (0, .5, 1):
        yy = py0 + f * (py1 - py0)
        c.setStrokeColor(HEAD); c.setLineWidth(.6); c.line(px0, yy, px1, yy)
        c.setFillColor(GREY); c.drawRightString(px0 - 1.5 * mm, yy - 2, fmt(round(nice * f)))
    X = lambda i: px0 + (i * (px1 - px0) / (len(labels) - 1) if len(labels) > 1 else (px1 - px0) / 2)
    Y = lambda v: py0 + v / nice * (py1 - py0)
    step = max(1, -(-len(labels) // 7))
    for i, lb in enumerate(labels):
        if i % step == 0 or i == len(labels) - 1:
            c.setFillColor(GREY); c.drawCentredString(X(i), py0 - 4.5 * mm, lb)
    ends = []
    for name, col, vs in series:
        pts = [(X(i), Y(v)) for i, v in enumerate(vs)]
        c.setStrokeColor(col); c.setLineWidth(1.8); c.setLineCap(1); c.setLineJoin(1)
        c.drawPath(smooth(c, pts), stroke=1, fill=0)
        if peaks:  # label the peak (selective direct label)
            pk = max(range(len(vs)), key=lambda i: vs[i])
            c.setFillColor(col); c.circle(X(pk), Y(vs[pk]), 1.1 * mm, stroke=0, fill=1)
            c.setFillColor(INK); c.setFont('Lexend-Bold', 6.8); c.drawCentredString(X(pk), Y(vs[pk]) + 2 * mm, fmt(vs[pk]))
        else:  # values at the line ends instead
            for i in (0, len(vs) - 1):
                c.setFillColor(col); c.circle(pts[i][0], pts[i][1], 1.0 * mm, stroke=0, fill=1)
            name = f'{fmt(vs[-1])} {name[0].lower() + name[1:]}'
        ends.append((pts[-1][1], name, col))
    ends.sort()
    for i in range(1, len(ends)):  # nudge end labels apart instead of dropping them
        if ends[i][0] - ends[i - 1][0] < 9:
            ends[i] = (ends[i - 1][0] + 9, ends[i][1], ends[i][2])
    if not peaks or all(ends[i][0] - ends[i - 1][0] >= 9 for i in range(1, len(ends))):
        for yy, name, col in ends:
            c.setFillColor(INK); c.setFont('Lexend-Medium', 6.6); c.drawString(px1 + 2 * mm, yy - 2, name if peaks else name)
    if note:
        c.setFillColor(GREY); c.setFont('Lexend', 6.4); c.drawString(x + 5 * mm, y - h + 3 * mm, note)


c = canvas.Canvas(OUT, pagesize=A4)
c.setTitle('SDICS Chiefs Training Report — 19 and 20 November 2026'); c.setAuthor('SDICS')

# ---------------------------------------------------------------- page 1
y = H - M
stripe(c, y - 1.6 * mm)
c.setFillColor(GREEN); c.setFont('Lexend-Bold', 7.6); c.drawString(M, y - 7 * mm, 'SDICS CHIEFS TRAINING  ·  ATTENDANCE AND ONBOARDING REPORT')
c.setFillColor(INK); c.setFont('Lexend-Bold', 18); c.drawString(M, y - 15 * mm, 'Thursday 19 and Friday 20 November 2026')
y = para(c, 'Chiefs and sub-chiefs marked present at the county trainings for the SDICS app, matched with SDICS records: '
            'who has an SDICS account, and who signed in to the SDICS app for the first time on their training day '
            '(onboarding). Dates and times are Nairobi time, taken from the check-ins.', M, y - 18.5 * mm, W - 2 * M, SMALL)

tw = (W - 2 * M - 3 * 4 * mm) / 4
ty = y - 4 * mm
tile(c, M, ty, tw, 30 * mm, 'Chiefs present', fmt(present), f'5 county trainings, 2 days')
tile(c, M + (tw + 4 * mm), ty, tw, 30 * mm, 'Phone numbers', fmt(present), '100% of chiefs present')
tile(c, M + 2 * (tw + 4 * mm), ty, tw, 30 * mm, 'Have an SDICS account', fmt(with_acct), f'{pct(with_acct, present)} of chiefs present',
     prog=with_acct / present)
tile(c, M + 3 * (tw + 4 * mm), ty, tw, 30 * mm, 'Onboarded that day', fmt(same_day), f'{pct(same_day, present)}: first SDICS sign-in', AMBER,
     prog=same_day / present)

# county table with progress bars
y = ty - 36 * mm
c.setFillColor(INK); c.setFont('Lexend-Bold', 11); c.drawString(M, y, 'By county')
y -= 4 * mm
cols = [('County', 26), ('Held', 27), ('Present', 15), ('Of SDICS chiefs in the county', 50), ('Onboarded that day', 42), ('Other county', 20)]
tx = M
c.setFillColor(HEAD); c.rect(M, y - 7 * mm, W - 2 * M, 7 * mm, stroke=0, fill=1)
c.setFillColor(GREY); c.setFont('Lexend-Medium', 6.6)
for name, wmm in cols:
    c.drawString(tx + 2 * mm, y - 4.6 * mm, name.upper()); tx += wmm * mm
y -= 7 * mm
for r in sorted(rows, key=lambda r: (r['day'], -r['present'])):
    rh = 11 * mm
    tx = M
    c.setFillColor(INK); c.setFont('Lexend-Bold', 9); c.drawString(tx + 2 * mm, y - 6.6 * mm, r['county']); tx += cols[0][1] * mm
    c.setFont('Lexend', 8); c.drawString(tx + 2 * mm, y - 5 * mm, SHORT[r['day']])
    first = r.get('first'); last = r.get('last')
    c.setFillColor(GREY); c.setFont('Lexend', 6.8); c.drawString(tx + 2 * mm, y - 8.6 * mm, f"{first}–{last}" if first else ''); tx += cols[1][1] * mm
    c.setFillColor(INK); c.setFont('Lexend-Bold', 10); c.drawRightString(tx + cols[2][1] * mm - 3 * mm, y - 6.8 * mm, fmt(r['present'])); tx += cols[2][1] * mm
    of = r['sdics_chiefs_in_county']
    bar(c, tx + 2 * mm, y - 7.2 * mm, 22 * mm, r['present'] / of if of else 0)
    c.setFillColor(INK); c.setFont('Lexend', 7.4); c.drawString(tx + 26 * mm, y - 6.8 * mm, f"{r['present']}/{of} · {pct(r['present'], of)}"); tx += cols[3][1] * mm
    bar(c, tx + 2 * mm, y - 7.2 * mm, 20 * mm, r['first_signin_same_day'] / r['present'], AMBER)
    c.setFillColor(INK)
    c.drawString(tx + 24 * mm, y - 6.8 * mm, f"{r['first_signin_same_day']} · {pct(r['first_signin_same_day'], r['present'])}"); tx += cols[4][1] * mm
    c.drawRightString(tx + cols[5][1] * mm - 3 * mm, y - 6.8 * mm, str(r['present'] - r['in_region']))
    c.setStrokeColor(LINE); c.setLineWidth(.5); c.line(M, y - rh, W - M, y - rh)
    y -= rh
c.setFillColor(INK); c.setFont('Lexend-Bold', 9)
c.drawString(M + 2 * mm, y - 5.6 * mm, 'Total')
c.drawRightString(M + (26 + 27 + 15) * mm - 3 * mm, y - 5.6 * mm, fmt(present))
c.setFont('Lexend', 7.4)
c.drawString(M + (26 + 27 + 15 + 26) * mm, y - 5.6 * mm, f'{present}/{fmt(sdics_in_counties)} · {pct(present, sdics_in_counties)}')
c.drawString(M + (26 + 27 + 15 + 50 + 24) * mm, y - 5.6 * mm, f'{same_day} · {pct(same_day, present)}')
c.drawRightString(W - M - 3 * mm, y - 5.6 * mm, str(out_region))
y -= 10 * mm

# charts
hours = list(range(7, 16))
ser = []
for day, col in [('2026-11-19', GREEN), ('2026-11-20', AMBER)]:
    hh = d['hours'].get(day, {})
    ser.append((SHORT[day], col, [int(hh.get(f'{h:02d}', 0)) for h in hours]))
cw = (W - 2 * M - 4 * mm) / 2
line_chart(c, M, y, cw, 62 * mm, 'Chiefs arriving, by hour', [f'{h:02d}:00' for h in hours], ser,
           note='Each chief counted once, at the hour they were marked present.')
od = ['2026-11-19', '2026-11-20']
line_chart(c, M + cw + 4 * mm, y, cw, 62 * mm, 'Each day: present and onboarded', [SHORT[x] for x in od],
           [('Present at training', GREEN, [sum(r['present'] for r in rows if r['day'] == x) for x in od]),
            ('First signed in to SDICS', AMBER, [onboard.get(x, 0) for x in od]),
            ('Voters marked registered', BLUE, [regs.get(x, 0) for x in od])],
           note='Onboarding and registrations: all chiefs in SDICS, those days.', peaks=False)
c.setFillColor(GREY); c.setFont('Lexend', 6.6)
c.drawString(M, 9 * mm, 'SDICS Chiefs Training · Attendance and onboarding · 19–20 November 2026')
c.drawRightString(W - M, 9 * mm, 'Page 1 of 2')
c.showPage()

# ---------------------------------------------------------------- page 2: findings
y = H - M
stripe(c, y - 1.6 * mm)
c.setFillColor(INK); c.setFont('Lexend-Bold', 14); c.drawString(M, y - 10 * mm, 'What the figures show')
y -= 14 * mm
by = {r['county']: r for r in rows}
em = d['first_login_by_day']
em_signins = em.get('2026-11-19', {}).get('elgeyomarakwet', 0) + em.get('2026-11-20', {}).get('elgeyomarakwet', 0)
no_acct = present - with_acct
findings = [
    ('Training turned into onboarding',
     f'{fmt(same_day)} of the {fmt(present)} chiefs present ({pct(same_day, present)}) signed in to the SDICS app for the first time on the day '
     f'of their training; {fmt(signed)} ({pct(signed, present)}) have signed in at all. Nandi ({pct(by["Nandi"]["first_signin_same_day"], by["Nandi"]["present"])}) '
     f'and Bomet ({pct(by["Bomet"]["first_signin_same_day"], by["Bomet"]["present"])}) were highest; Baringo was lowest '
     f'({pct(by["Baringo"]["first_signin_same_day"], by["Baringo"]["present"])}).'),
    ('Attendance against the chiefs SDICS has',
     f'The five counties have {fmt(sdics_in_counties)} chiefs with SDICS accounts; {fmt(present)} attended ({pct(present, sdics_in_counties)}). '
     f'Kericho reached {pct(by["Kericho"]["present"], by["Kericho"]["sdics_chiefs_in_county"])} and Baringo '
     f'{pct(by["Baringo"]["present"], by["Baringo"]["sdics_chiefs_in_county"])}; Nandi and Bomet reached '
     f'{pct(by["Nandi"]["present"], by["Nandi"]["sdics_chiefs_in_county"])}: '
     f'{by["Nandi"]["sdics_chiefs_in_county"] - by["Nandi"]["present"]} Nandi and {by["Bomet"]["sdics_chiefs_in_county"] - by["Bomet"]["present"]} '
     'Bomet chiefs still need training.'),
    ('Onboarding across SDICS',
     f'{fmt(onboard.get("2026-11-19", 0))} chiefs signed in to SDICS for the first time on Thursday and {fmt(onboard.get("2026-11-20", 0))} on Friday, '
     f'and chiefs marked {fmt(regs.get("2026-11-19", 0))} and {fmt(regs.get("2026-11-20", 0))} voters as registered those days.'),
    ('Elgeyo-Marakwet: trained, but attendance not recorded',
     f'SDICS shows {em_signins} Elgeyo-Marakwet chiefs signing in for the first time on Thursday and Friday, but no attendance was recorded '
     'in Checkin on those days (the first check-ins there were on Saturday 21 November). Ask the Elgeyo-Marakwet trainer to mark the '
     'chiefs who attended, or record the attendance list.'),
    ('Chiefs present without an SDICS account',
     f'{no_acct} chiefs present ({by["Baringo"]["present"] - by["Baringo"]["sdics_officer"]} in Baringo, '
     f'{by["Kericho"]["present"] - by["Kericho"]["sdics_officer"]} in Kericho, {by["Nandi"]["present"] - by["Nandi"]["sdics_officer"]} in Nandi) '
     'have no SDICS account under the ID they gave. Either the account is still to be created, or the ID on their SDICS account is wrong. '
     'Administrators can check them against the attendance list.'),
    ('Who attended',
     f'{fmt(female)} women ({pct(female, present)}) and {fmt(present - female)} men; {subchief} sub-chiefs. '
     f'{out_region} chiefs ({pct(out_region, present)}) were from outside the training\'s county and were marked present as out of region. '
     'Every chief present gave a phone number.'),
    ('When they arrived',
     'On Thursday most chiefs arrived at 09:00 and 12:00 (Baringo in the morning, Uasin Gishu after noon); on Friday at 08:00–09:00 '
     '(Nandi and Kericho) and 11:00 (Bomet). Plan registration desks for these peaks.'),
    ('Dates corrected',
     'The trainings now carry the dates they were held, from their check-ins: Baringo and Uasin Gishu on Thursday 19 November; '
     'Bomet, Kericho and Nandi on Friday 20 November; Elgeyo-Marakwet from Saturday 21 November. One test check-in in Narok '
     '(18 November) is not counted. Bungoma, Nakuru, Narok, Samburu, Trans Nzoia, Turkana and West Pokot: not held yet.'),
]
for i, (title, text) in enumerate(findings, 1):
    c.setFillColor(GREEN); c.circle(M + 3 * mm, y - 2.6 * mm, 3 * mm, stroke=0, fill=1)
    c.setFillColor(colors.white); c.setFont('Lexend-Bold', 8.5); c.drawCentredString(M + 3 * mm, y - 3.6 * mm, str(i))
    c.setFillColor(INK); c.setFont('Lexend-Bold', 10); c.drawString(M + 9 * mm, y - 3.6 * mm, title)
    y = para(c, text, M + 9 * mm, y - 6 * mm, W - 2 * M - 9 * mm) - 6 * mm
bh = 22 * mm
c.setFillColor(AMBER_BG); c.setStrokeColor(C('#F2A007')); c.roundRect(M, y - bh, W - 2 * M, bh, 3 * mm, stroke=1, fill=1)
c.setFillColor(AMBER); c.setFont('Lexend-Bold', 9.5); c.drawString(M + 5 * mm, y - 6 * mm, 'How these figures were made')
para(c, 'Attendance: every chief marked present in the Checkin system at a county training (each chief counted once). '
        'SDICS: chiefs with an active SDICS account in the county; first sign-in from the SDICS sign-in log; registrations: voters marked '
        'registered in SDICS. Matched by National ID. Figures as of Saturday 21 November 2026, 10:45; Saturday is not included.',
     M + 5 * mm, y - 8.5 * mm, W - 2 * M - 10 * mm, SMALL)
c.setFillColor(GREY); c.setFont('Lexend', 6.6)
c.drawString(M, 9 * mm, 'SDICS Chiefs Training · Attendance and onboarding · 19–20 November 2026')
c.drawRightString(W - M, 9 * mm, 'Page 2 of 2')
c.showPage(); c.save()
print('wrote', OUT)
