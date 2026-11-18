"""Build the SDICS Clerk and Chief Training Manual (PDF) with ReportLab.
Style follows the Checkin training manuals (teal cover, step squares,
callout boxes, framed screenshots). Run with the venv python:
  python -I build_manual.py <assets_dir> <out.pdf>
"""
import sys, os
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_CENTER
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Table,
                                TableStyle, Image, PageBreak, KeepTogether, Flowable, NextPageTemplate,
                                CondPageBreak)

A, OUT = sys.argv[1], sys.argv[2]
AUD = sys.argv[3] if len(sys.argv) > 3 else 'clerks'   # 'clerks' or 'chiefs'
CFG = {
    'clerks': dict(
        title='IEBC Clerks', who='IEBC clerks',
        sub1='How to use the IEBC dashboard and the Checkin app,', sub2='step by step, in simple words.',
        covers='Phone basics · IEBC dashboard · Checkin app · Quick reference',
        footer='IEBC Clerks · Version 2.0 · November 2026', p0_sub='Read this before you start.',
        battery_off='Charge it. Checkin records saved on the phone stay there and sync when you are back online.',
        pdf_title='SDICS Training Manual — IEBC Clerks',
        pdf_subject='IEBC dashboard and Checkin app'),
    'chiefs': dict(
        title='Chiefs and Sub-chiefs', who='Chiefs and Sub-chiefs (SDICS Field app officers)',
        sub1='How to use the SDICS Field app,', sub2='step by step, in simple words.',
        covers='Phone basics · SDICS Field app · Quick reference',
        footer='Chiefs and Sub-chiefs · Version 2.0 · November 2026', p0_sub='Read this before you start.',
        battery_off='Charge it. Your saved work in the SDICS Field app stays on the phone; it is sent when the phone is on and has signal.',
        pdf_title='SDICS Training Manual — Chiefs and Sub-chiefs',
        pdf_subject='SDICS Field app'),
}[AUD]
QR = 3 if AUD == 'clerks' else 2          # number of the Quick reference part
SUP = '/System/Library/Fonts/Supplemental/'
pdfmetrics.registerFont(TTFont('Arial', SUP + 'Arial.ttf'))
pdfmetrics.registerFont(TTFont('Arial-Bold', SUP + 'Arial Bold.ttf'))
pdfmetrics.registerFont(TTFont('Arial-Italic', SUP + 'Arial Italic.ttf'))
pdfmetrics.registerFont(TTFont('Arial-BoldItalic', SUP + 'Arial Bold Italic.ttf'))
from reportlab.pdfbase.pdfmetrics import registerFontFamily
registerFontFamily('Arial', normal='Arial', bold='Arial-Bold', italic='Arial-Italic', boldItalic='Arial-BoldItalic')

C = colors.HexColor
# SDICS brand (mobile-flutter/lib/core/theme.dart, IEBC dashboard):
# green #00A86B (#00875A on light), bright green #00D084, navy #0F1419 /
# #1A2332, amber #F2A007, Kenyan flag black / red #BB0000 / green #006600.
TEAL, TEAL_D, H1C, H2C = C('#00875A'), C('#0B3D2E'), C('#0F1419'), C('#00875A')
KICK, GREY, LINE = C('#00D084'), C('#5A6472'), C('#DCE3DF')
# Tints as the app draws them: amber #F2A007 at 16% on white = #FDF0D7;
# green #00A86B at 12% on white = #E0F5ED. Surfaces: #F6F8F7 / #EFF3F1.
TIP_BG, IMP_BG, ORANGE, FRAME = C('#E0F5ED'), C('#FDF0D7'), C('#F2A007'), C('#F6F8F7')
AMBER_D, NAVY2, FLAG_RED, FLAG_GREEN = C('#9A6200'), C('#1A2332'), C('#BB0000'), C('#006600')


def flag_stripe(c, x, y, w, h):
    """The apps' FlagStripe: black, red (#BB0000), green (#006600), side by side."""
    for i, col in enumerate([colors.black, FLAG_RED, FLAG_GREEN]):
        c.setFillColor(col)
        c.rect(x + i * w / 3, y, w / 3, h, stroke=0, fill=1)


LOGO = os.path.join(A, 'coat_of_arms_disc.png')  # the apps' coat of arms on a white disc

PW, PH = A4
LM = RM = 18 * mm
TW = PW - LM - RM

st = lambda name, **kw: ParagraphStyle(name, **{'fontName': 'Arial', 'fontSize': 10.5, 'leading': 14.5,
                                                'textColor': C('#1F2A28'), **kw})
BODY = st('body', spaceAfter=5)
SMALL = st('small', fontSize=9, leading=12)
CAP = st('cap', fontName='Arial-Italic', fontSize=8.5, leading=11, textColor=GREY, alignment=TA_CENTER)
LEG = st('leg', fontSize=8.8, leading=11.5, textColor=C('#33413E'))
LABEL = st('label', fontName='Arial-Bold', fontSize=8.5, leading=10, textColor=TEAL, spaceAfter=2)
H1 = st('h1', fontName='Arial-Bold', fontSize=24, leading=28, textColor=H1C, spaceAfter=3)
SUB = st('sub', fontSize=11, leading=15, textColor=GREY)
H2 = st('h2', fontName='Arial-Bold', fontSize=14, leading=18, textColor=H2C, spaceBefore=10, spaceAfter=5)
H3 = st('h3', fontName='Arial-Bold', fontSize=11.5, leading=15, textColor=H1C, spaceBefore=6, spaceAfter=3)
STEPT = st('stept', fontSize=10.3, leading=13.8)
CELL = st('cell', fontSize=9.4, leading=12.4)
CELLB = st('cellb', fontName='Arial-Bold', fontSize=9.4, leading=12.4, textColor=TEAL_D)
CELLH = st('cellh', fontName='Arial-Bold', fontSize=9.4, leading=12.4, textColor=colors.white)


def P(t, s=BODY):
    return Paragraph(t, s)


class NumBox(Flowable):
    def __init__(self, n, size=7.5 * mm):
        super().__init__(); self.n, self.s = str(n), size
    def wrap(self, *a): return self.s, self.s
    def draw(self):
        c = self.canv
        c.setFillColor(TEAL); c.roundRect(0, 0, self.s, self.s, 1.6 * mm, stroke=0, fill=1)
        c.setFillColor(colors.white); c.setFont('Arial-Bold', 11)
        c.drawCentredString(self.s / 2, self.s / 2 - 3.8, self.n)


class Rule(Flowable):
    def __init__(self, w=TW, color=TEAL, th=1.6, space=4):
        super().__init__(); self.w, self.color, self.th, self.space = w, color, th, space
    def wrap(self, *a): return self.w, self.th + 2 * self.space
    def draw(self):
        self.canv.setStrokeColor(self.color); self.canv.setLineWidth(self.th)
        self.canv.line(0, self.space, self.w, self.space)


def section(label, title, subtitle):
    return [P(label.upper(), LABEL), P(title, H1), P(subtitle, SUB), Rule(space=6), Spacer(1, 4)]


def step(n, title, text='', width=TW):
    body = f'<b>{title}</b>' + (f'<br/>{text}' if text else '')
    t = Table([[NumBox(n), P(body, STEPT)]], colWidths=[10 * mm, width - 10 * mm])
    t.setStyle(TableStyle([('VALIGN', (0, 0), (-1, -1), 'TOP'), ('LEFTPADDING', (0, 0), (-1, -1), 0),
                           ('RIGHTPADDING', (0, 0), (-1, -1), 0), ('TOPPADDING', (0, 0), (-1, -1), 2),
                           ('BOTTOMPADDING', (0, 0), (-1, -1), 4)]))
    return t


def steps(items, start=1, width=TW):
    return [step(i + start, *it, width=width) for i, it in enumerate(items)]


def callout(kind, title, text, width=TW):
    bg, bar = (IMP_BG, ORANGE) if kind == 'IMPORTANT' else (TIP_BG, TEAL)
    lab = st('cl', fontName='Arial-Bold', fontSize=8, leading=10, textColor=AMBER_D if kind == 'IMPORTANT' else bar)
    inner = [P(kind, lab), P(f'<b>{title}</b>', st('ct', fontSize=10.5, leading=14, textColor=H1C))]
    if isinstance(text, str):
        text = [text]
    inner += [P(x, st('cx', fontSize=9.8, leading=13.4)) for x in text]
    t = Table([[inner]], colWidths=[width])
    t.setStyle(TableStyle([('BACKGROUND', (0, 0), (-1, -1), bg), ('LINEBEFORE', (0, 0), (0, -1), 4, bar),
                           ('LEFTPADDING', (0, 0), (-1, -1), 10), ('RIGHTPADDING', (0, 0), (-1, -1), 10),
                           ('TOPPADDING', (0, 0), (-1, -1), 7), ('BOTTOMPADDING', (0, 0), (-1, -1), 8)]))
    if width != TW:
        return t
    return KeepTogether([Spacer(1, 4), t, Spacer(1, 6)])


def table(header, rows, widths, width=TW):
    data = [[P(h, CELLH) for h in header]] + [[P(r[0], CELLB)] + [P(x, CELL) for x in r[1:]] for r in rows]
    t = Table(data, colWidths=[w * width for w in widths], repeatRows=1)
    t.setStyle(TableStyle([('BACKGROUND', (0, 0), (-1, 0), NAVY2), ('VALIGN', (0, 0), (-1, -1), 'TOP'),
                           ('LINEBELOW', (0, 1), (-1, -1), 0.5, LINE), ('TOPPADDING', (0, 0), (-1, -1), 5),
                           ('BOTTOMPADDING', (0, 0), (-1, -1), 5), ('LEFTPADDING', (0, 0), (-1, -1), 6)]))
    return t


def framed(path, w):
    from PIL import Image as PI
    iw, ih = PI.open(path).size
    img = Image(path, width=w, height=w * ih / iw)
    t = Table([[img]], colWidths=[w + 8])
    t.setStyle(TableStyle([('BACKGROUND', (0, 0), (-1, -1), FRAME), ('BOX', (0, 0), (-1, -1), 0.8, LINE),
                           ('LEFTPADDING', (0, 0), (-1, -1), 4), ('RIGHTPADDING', (0, 0), (-1, -1), 4),
                           ('TOPPADDING', (0, 0), (-1, -1), 4), ('BOTTOMPADDING', (0, 0), (-1, -1), 4)]))
    return t


def legend(items):
    return P('&nbsp;&nbsp; '.join(f'<font color="#9A6200"><b>{k}</b></font> = {v}' for k, v in items), LEG)


def shot(path, caption, items=None, w=TW):
    out = [framed(path, w - 8), Spacer(1, 3), P(caption, CAP)]
    if items:
        out += [Spacer(1, 2), legend(items)]
    return KeepTogether(out + [Spacer(1, 8)])


def shot_steps(path, caption, step_items, start=1, items=None, extra=None, iw=50 * mm):
    """Phone screenshot on the left; numbered steps (and legend) on the right."""
    right_w = TW - iw - 8 * mm
    left = [framed(path, iw - 8), Spacer(1, 3), P(caption, CAP)]
    right = steps(step_items, start, width=right_w)
    if items:
        right += [Spacer(1, 4), P('<b>On the picture</b>', SMALL)] + [P(f'<font color="#9A6200"><b>{k}</b></font> = {v}', LEG) for k, v in items]
    if extra:
        right += [Spacer(1, 6)] + [x for e in extra for x in (e, Spacer(1, 5))]
    t = Table([[left, right]], colWidths=[iw, TW - iw])
    t.setStyle(TableStyle([('VALIGN', (0, 0), (-1, -1), 'TOP'), ('LEFTPADDING', (0, 0), (-1, -1), 0),
                           ('LEFTPADDING', (1, 0), (1, 0), 8 * mm), ('RIGHTPADDING', (0, 0), (-1, -1), 0)]))
    return KeepTogether([t, Spacer(1, 10)])


def two_shots(p1, c1, p2, c2, w=62 * mm, items=None):
    t = Table([[[framed(p1, w - 8), Spacer(1, 3), P(c1, CAP)], [framed(p2, w - 8), Spacer(1, 3), P(c2, CAP)]]],
              colWidths=[w + 10 * mm, w + 10 * mm])
    t.setStyle(TableStyle([('VALIGN', (0, 0), (-1, -1), 'TOP'), ('ALIGN', (0, 0), (-1, -1), 'CENTER')]))
    out = [t]
    if items:
        out += [Spacer(1, 3), legend(items)]
    return KeepTogether(out + [Spacer(1, 8)])


def placeholder(text, h=38 * mm, w=TW):
    t = Table([[P(f'[SCREENSHOT NEEDED: {text}]', st('ph', fontName='Arial-Bold', fontSize=9.5, leading=13,
                                                    textColor=GREY, alignment=TA_CENTER))]],
              colWidths=[w], rowHeights=[h])
    t.setStyle(TableStyle([('BACKGROUND', (0, 0), (-1, -1), FRAME), ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                           ('BOX', (0, 0), (-1, -1), 1, C('#B8C2BE'))]))
    return KeepTogether([t, Spacer(1, 8)])


def bullets(items, style=BODY):
    return [P(f'•&nbsp;&nbsp;{x}', st('b', parent=style, leftIndent=12, firstLineIndent=-10, spaceAfter=3)) for x in items]


def word(term, meaning):
    return P(f'<b>{term}</b> — {meaning}', st('w', fontSize=10, leading=13.5, leftIndent=10, spaceAfter=3))


F = lambda n: os.path.join(A, 'ann_field_v3', n + '.png')
I = lambda n: os.path.join(A, 'ann_iebc_v3', n + '.png')
K2 = lambda n: os.path.join(A, 'ann_checkin_app', n + '.png')
RAW_I = lambda n: os.path.join(A, 'iebc_shots_v2', n + '.png')

# ---------------------------------------------------------------- pages
def cover(c, d):
    """Like the SDICS Field sign-in header: diagonal gradient #0B3D2E -> #0F1F1C
    -> #0F1419, coat of arms on a white disc, REPUBLIC OF KENYA / Registration
    Drive, then the flag stripe; the rest of the page is navy."""
    c.saveState()
    hb = PH * 0.40                      # bottom of the header band
    c.setFillColor(H1C); c.rect(0, 0, PW, PH, stroke=0, fill=1)
    p = c.beginPath(); p.rect(0, hb, PW, PH - hb); c.clipPath(p, stroke=0, fill=0)
    c.linearGradient(0, PH, PW, hb, [C('#0B3D2E'), C('#0F1F1C'), C('#0F1419')], [0, 0.45, 1], extend=True)
    c.restoreState(); c.saveState()
    flag_stripe(c, 0, hb - 2.2 * mm, PW, 2.2 * mm)
    x, y, ds = LM, PH - 48 * mm, 22 * mm
    c.drawImage(LOGO, x, y, ds, ds, mask='auto')
    c.setFillColor(C('#B3B3B3')); c.setFont('Arial-Bold', 9)
    c.drawString(x + ds + 6 * mm, y + ds / 2 + 2.5 * mm, 'R E P U B L I C   O F   K E N Y A')
    c.setFillColor(colors.white); c.setFont('Arial', 13)
    c.drawString(x + ds + 6 * mm, y + ds / 2 - 4 * mm, 'Registration Drive')
    c.setFillColor(KICK); c.setFont('Arial-Bold', 11)
    c.drawString(LM, PH * 0.66, 'S D I C S   ·   F I E L D   T R A I N I N G   M A N U A L')
    c.setFillColor(colors.white); c.setFont('Arial-Bold', 36)
    c.drawString(LM, PH * 0.66 - 17 * mm, CFG['title'])
    c.setFont('Arial', 14.5); c.setFillColor(C('#CCCCCC'))
    c.drawString(LM, PH * 0.66 - 28 * mm, CFG['sub1'])
    c.drawString(LM, PH * 0.66 - 35 * mm, CFG['sub2'])
    c.setFillColor(C('#CCCCCC'))
    yy = hb - 22 * mm
    for k, v in [('For:', CFG['who']),
                 ('Covers:', CFG['covers']),
                 ('Version:', '2.0 · November 2026')]:
        c.setFont('Arial-Bold', 10.5); c.drawString(LM, yy, k)
        c.setFont('Arial', 10.5); c.drawString(LM + 20 * mm, yy, v); yy -= 7 * mm
    c.setFont('Arial-Italic', 8.5); c.setFillColor(C('#8B95A5'))
    c.drawString(LM, 15 * mm, 'All names, ID numbers and figures in the pictures are SAMPLE data, not real people.')
    c.restoreState()


def normal(c, d):
    c.saveState()
    c.drawImage(LOGO, LM, PH - 12.9 * mm, 5 * mm, 5 * mm, mask='auto')
    c.setFont('Arial-Bold', 9.5); c.setFillColor(TEAL); c.drawString(LM + 6.5 * mm, PH - 12 * mm, 'SDICS')
    c.setFont('Arial', 9); c.setFillColor(GREY); c.drawRightString(PW - RM, PH - 12 * mm, 'Field Training Manual')
    c.setStrokeColor(LINE); c.setLineWidth(0.6); c.line(LM, PH - 14 * mm, PW - RM, PH - 14 * mm)
    flag_stripe(c, LM, PH - 14.9 * mm, 24 * mm, 1.0 * mm)
    c.setFillColor(GREY); c.setFont('Arial', 8.5); c.drawString(LM, 10 * mm, CFG['footer'])
    c.drawRightString(PW - RM, 10 * mm, f'Page {d.page}')
    c.restoreState()


doc = BaseDocTemplate(OUT, pagesize=A4, leftMargin=LM, rightMargin=RM, topMargin=20 * mm, bottomMargin=17 * mm,
                      title=CFG['pdf_title'], author='SDICS',
                      subject='Field training manual: ' + CFG['pdf_subject'])
fr = Frame(LM, 17 * mm, TW, PH - 37 * mm, id='f', leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
doc.addPageTemplates([PageTemplate('cover', frames=[fr], onPage=cover),
                      PageTemplate('normal', frames=[fr], onPage=normal)])

S = [NextPageTemplate('normal'), PageBreak()]

# ---------------------------------------------------------------- welcome
S += section('Welcome', 'About this manual', 'Read this page first.')
S += [P('This manual teaches you how to do your job with a phone' + (' or a computer' if AUD == 'clerks' else '') + '. '
        'Each part has short steps. Do one step at a time. The pictures show you where to tap.'),
      P('<b>The manual has %s parts:</b>' % ('four' if AUD == 'clerks' else 'three'))]
_parts = [('Phone basics', 'Turning the phone on, charging, battery, and keeping it safe.')]
if AUD == 'clerks':
    _parts += [('The IEBC dashboard', 'How to sign in on a phone or computer and find unregistered voters in your constituency.'),
               ('The Checkin app', 'How to check voters in at an event, mobilize (register) voters, and read your numbers.'),
               ('Quick reference', 'One-page reminders, Do\'s and Don\'ts, and who to call.')]
else:
    _parts += [('The SDICS Field app', 'How to sign in, find people on your roll, and mark them as registered.'),
               ('Quick reference', 'A one-page reminder, Do\'s and Don\'ts, and who to call.')]
for _n, (_t, _d) in enumerate(_parts):
    S.append(step(_n, _t, _d))
S += [Spacer(1, 4), P('<b>Words you will see</b>', H3),
      word('App', 'a program on the phone. You open it by tapping its picture (icon).'),
      word('Tap', 'touch the screen once with your finger.'),
      word('Sign in', 'type your name or number and your secret code, so the app knows who you are.'),
      word('Data / internet', 'what the phone uses to talk to the system.'),
      word('Signal', 'the bars at the top of the screen. No bars means no network.'),
      word('Offline', 'the phone has no internet right now.'),
      callout('NOTE', 'The pictures use sample data',
              'All names, ID numbers and numbers in the pictures are made up for training. '
              'On your phone you will see real people. '
              'The yellow boxes and numbers in the pictures are not on your screen: they only show you where to look.'),
      callout('IMPORTANT', 'Voter information is private',
              'You will see names and ID numbers of real people. Do not share them, photograph them, '
              'or write them down for anyone else. Every search is recorded.')]


# ---------------------------------------------------------------- PART 0
S += [PageBreak()] + section('Part 0', 'Phone basics', CFG['p0_sub'])
S += [P('<i>Phone model: [PHONE MODEL — to be filled in]. Buttons can be in a slightly different place on your phone.</i>', SMALL),
      P('0.1 Turn the phone on and off', H2)]
S += steps([('Find the power button', 'It is on the side of the phone. It is usually the small button on the right.'),
            ('Turn on', 'Press and hold the power button for about 3 seconds, until the screen lights up.'),
            ('Unlock', 'Swipe up on the screen. Type your screen code if the phone asks for one.'),
            ('Turn off', 'Press and hold the power button. Tap <b>Power off</b>. Tap it again if asked.'),
            ('Restart', 'Press and hold the power button. Tap <b>Restart</b>. A restart fixes many small problems.')])
S += [P('0.2 Charging the phone safely', H2)]
S += steps([('Use the charger you were given', 'Other chargers can damage the battery.'),
            ('Plug into the wall first', 'Then connect the cable to the phone.'),
            ('Charge in a dry, cool place', 'Not in the sun, not on a bed or under a pillow, never near water.'),
            ('Unplug when full', 'Full is 100%. Do not leave it charging all night.')])
S += [P('0.3 Battery level', H2),
      P('The battery picture is at the top right of the screen. The number next to it is how full it is, for example 80%.')]
S += [table(['Battery', 'What to do'], [
    ['More than 50%', 'All good. Work as normal.'],
    ['20% to 50%', 'Plan to charge soon. Make the screen darker to save power.'],
    ['Less than 20%', 'Charge now. Turn on <b>Battery saver</b> (Settings → Battery). Close apps you are not using.'],
    ['Phone turned off', CFG['battery_off']]],
    [0.25, 0.75]), Spacer(1, 8)]
S += [P('0.4 Keeping the phone safe, dry and clean', H2)] + bullets([
    'Keep the phone in its cover and in a bag when you walk or ride.',
    'Keep it away from rain, water, mud and dust. Use a plastic bag if it rains.',
    'Clean the screen with a soft dry cloth. Do not use water or spray.',
    'Never leave the phone alone or give it to someone else to use.',
    'Lock the screen when you are not using it (press the power button once).',
    'If the phone is lost or stolen, tell your supervisor <b>at once</b>.'])
S += [P('0.5 If the phone freezes', H2),
      P('<b>Freezes</b> means the screen does not move when you tap.')]
S += steps([('Wait one minute', 'Sometimes the phone is just slow.'),
            ('Go back', 'Tap the back button or swipe from the side of the screen.'),
            ('Restart', 'Press and hold the power button, then tap <b>Restart</b>.'),
            ('Force restart', 'If nothing works, hold the power button (and volume down) for about 10–15 seconds until the phone restarts.'),
            ('Still frozen?', f'Call support (see Part {QR}). Do not open the phone or remove anything.')])


def part_dashboard(n):
    global S
    # ---------------------------------------------------------------- PART 1
    S += [PageBreak()] + section(f'Part {n}', 'The IEBC dashboard',
                                  'Find the people in your constituency who are not yet registered to vote.')
    S += [P(f'{n}.1 What the dashboard is', H2),
          P('The <b>IEBC dashboard</b> is a web page. You open it in a <b>browser</b> '
            '(the app you use to visit websites, for example Chrome). The address is:'),
          P('<b>https://sdics.tech/iebc</b>', st('url', fontName='Arial-Bold', fontSize=13, leading=18, textColor=TEAL, spaceAfter=6)),
          P('It shows the people in <b>your constituency only</b> who are <b>not registered</b> to vote. '
            'For each person you see: ID number, name, father\'s name, clan name, family name, and county down to village.'),
          callout('IMPORTANT', 'The dashboard is view only',
                  'You can look and search. You <b>cannot</b> register anyone or change anything here. '
                  'Every search and every lookup is recorded with your name.'),
          callout('NOTE', 'What to do after you find a person',
                  'You (IEBC) register the person in the usual IEBC way. '
                  'The dashboard only helps you find who still needs to register and check their details.'),
          P('<b>You need:</b> a phone <b>or</b> a computer with internet, and the username and password an administrator gave you. '
            'The dashboard works the same on both.')]

    S += [P(f'{n}.2 Sign in', H2)]
    S.append(shot_steps(I('phone_01_login'), 'The sign-in page on a phone', [
        ('Open the browser', 'Tap Chrome. Type <b>sdics.tech/iebc</b> at the top and press Go.'),
        ('Type your username', 'Type the username an administrator gave you, exactly as it is written.'),
        ('Type your password', 'Tap the eye to see what you typed. Tap it again to hide it.'),
        ('Tap Sign in', 'The list of unregistered voters opens.')],
        items=[('1', 'Username'), ('2', 'Password'), ('3', 'Eye: show or hide the password'), ('4', 'Sign in button')]))
    S.append(shot_steps(I('phone_02_login_error'), 'A wrong password', [], items=[('1', 'The error message')], extra=[
        P('<b>If you see a red message:</b>', SMALL),
        table(['Message', 'What to do'], [
            ['Wrong username or password.', 'Check the spelling and try again. Passwords know big and small letters.'],
            ['Too many wrong attempts. Wait 15 minutes and try again.', 'Wait 15 minutes. Then try again carefully.'],
            ['Could not sign in. Check your connection and try again.', 'Check your data and signal (Part 0), then try again.']],
            [0.5, 0.5], width=TW - 58 * mm)]))

    S += [CondPageBreak(120 * mm), P(f'{n}.3 The main page', H2)]
    S.append(shot_steps(I('phone_03_list'), 'The main page after signing in', [
        ('Check your constituency', 'The grey box ("Your location") shows the constituency you are allowed to see.'),
        ('See the total', 'The big number is how many people in your constituency are not registered. '
         'It follows the latest IEBC register (2 November 2026): people who have registered since leave the list by themselves.'),
        ('Read the list', 'Scroll down to see the people. On a phone, slide the table left to see more columns.')],
        items=[('1', 'Your constituency'), ('2', 'Number not registered'), ('3', 'Search box'), ('4', 'Search button'),
               ('5', 'The list (table)'), ('6', 'Sign out')],
        extra=[P('The sun/moon button at the top makes the page light or dark. Use what is easier to read.', SMALL)]))

    S += [P(f'{n}.4 Find a voter', H2),
          P('Search by <b>ID number</b>, <b>father\'s name</b> or <b>family name</b>. '
            'You can also search by the person\'s name, clan or village. Type more than one word to narrow it down, '
            'for example a name and a father\'s name.')]
    S.append(shot_steps(I('phone_04_suggest'), 'Suggestions appear as you type', [
        ('Tap the search box', 'It says "Search ID number, name, father\'s name, family name, clan or village".'),
        ('Type at least 2 letters or digits', 'For example a family name like <b>chebet</b>, or the first digits of an ID number. If you see "Keep typing…", type more.'),
        ('Look at the suggestions', 'A short list appears under the box. Tap a name to show only that person.'),
        ('Or tap Search', 'To see <b>all</b> the matches in the table.')],
        items=[('1', 'Search box'), ('2', 'Suggestions')],
        extra=[P('"No one in your location matches" means nobody in your constituency fits what you typed. Check the spelling.', SMALL)]))
    S.append(shot_steps(I('phone_05_results'), 'The search results', [
        ('Read the results', 'The table now shows only the matches, for example "257 matching".'),
        ('Tap Clear', 'To empty the search and see everyone again.')], start=5,
        items=[('1', 'How many match'), ('2', 'Clear button')]))

    S += [P(f'{n}.5 Voter lookup: is this person registered?', H2),
          P('Use <b>Voter lookup</b> when you have one National ID number and want to know if that person is registered.')]
    S.append(shot_steps(I('phone_07_lookup_not'), 'A person who is NOT registered', [
        ('Type the ID number', 'Tap "National ID number" and type the number. Kenyan ID numbers have 4 to 9 digits.'),
        ('Tap Check', 'The answer appears under the box.'),
        ('Read the answer', '<b>Not registered</b> (orange) or <b>Registered</b> (green), with the person\'s details.')],
        items=[('1', 'ID number box'), ('2', 'Check button'), ('3', 'The answer')]))
    S.append(two_shots(I('phone_08_lookup_reg'), 'A person who IS registered (1 = Registered)',
                       I('phone_09_lookup_none'), 'An ID not found in your constituency (1 = the message)', w=48 * mm))
    S += [P('If you see "No one with ID … was found in your area.", the number is wrong or the person is not in your constituency. '
            'Check the number and try again. Tap <b>Clear</b> to start again.')]

    S += [P(f'{n}.6 Move through the list', H2)]
    S.append(shot_steps(I('phone_06_bottom'), 'The bottom of the list', [
        ('Choose rows per page', 'Tap the number next to "Per page" (on a computer: "Rows per page"). Choose 25, 50 or 100.'),
        ('See where you are', 'For example "1–25 of 257" means you see people 1 to 25.'),
        ('Go to the next page', 'Tap the arrow <b>&gt;</b>. Tap <b>&lt;</b> to go back.')],
        items=[('1', 'Rows per page'), ('2', 'Which people you see'), ('3', 'Next page'), ('4', 'Signed in as … Every search is logged.')]))

    S += [CondPageBreak(130 * mm), P(f'{n}.7 On a computer', H2),
          P('On a computer the page looks wider, but it works the same way. You see all the columns at once.')]
    S.append(shot(I('desktop_03_list'), 'The IEBC dashboard on a computer',
                  [('1', 'Your constituency'), ('2', 'Number not registered'), ('3', 'Search box'), ('4', 'Search button'),
                   ('5', 'The list'), ('6', 'Sign out')]))
    S.append(shot(I('desktop_07_lookup_not'), 'Voter lookup on a computer',
                  [('1', 'ID number box'), ('2', 'Check button'), ('3', 'The answer: Not registered')]))
    S += [P(f'{n}.8 Sign out', H2)]
    S += steps([('Tap the sign-out button', 'It is at the top right: a door with an arrow.'),
                ('Close the browser', 'Always sign out when you finish, and on any shared computer.')])
    S += [P(f'{n}.9 Common problems', H2),
          table(['Problem', 'What to do'], [
              ['The page does not open', 'Check data and signal. Check the address: <b>sdics.tech/iebc</b>.'],
              ['"No area has been assigned to your account yet."', 'Your account has no constituency yet. Call the SDICS help desk.'],
              ['I was sent back to the sign-in page', 'Your session ended (for example you signed in on another device). Sign in again.'],
              ['I forgot my password', 'Ask the SDICS administrator to reset it. They will give you a new one.'],
              ['"Type at least 2 characters"', 'Type more letters in the search box.'],
              ['I cannot find a person', 'Try the ID number, the father\'s name or the family name, or another spelling. The list shows only people <b>not</b> registered in your constituency: use Voter lookup to check someone who may already be registered.'],
              ['The table is cut off on my phone', 'Slide the table left and right with your finger.']],
              [0.38, 0.62])]


def part_field(n):
    global S
    # ---------------------------------------------------------------- PART 2
    S += [PageBreak()] + section(f'Part {n}', 'The SDICS Field app',
                                  'Mark people in your location as registered, even without signal.')
    S += [P(f'{n}.1 What the app does', H2),
          P('Chiefs and <b>sub-chiefs</b> are the <b>officers</b> who use the SDICS Field app on their phone. '
            'A chief works the whole location; a sub-chief works one <b>sub-location</b> in it (see {0}.4).'.format(n)),
          P('The <b>SDICS Field</b> app shows the <b>roll</b>: the list of people in your location who are '
            'still not registered to vote. When a person registers, you find them in the app and mark them as registered. '
            'The app also works with no signal and sends your work later.'),
          P(f'{n}.2 Sign in', H2)]
    S.append(shot_steps(F('01_login'), 'The sign-in screen', [
        ('Open SDICS Field', 'Tap the SDICS Field icon on the phone.'),
        ('Type your National ID', 'Your own ID number.'),
        ('Type your PIN', 'A <b>PIN</b> is a short secret number given to you when your account is made. '
         'It stays the same every time you sign in. Tap the eye to see it.'),
        ('Tap Sign in', 'The Home screen opens.')],
        items=[('1', 'National ID'), ('2', 'PIN'), ('3', 'Eye: show or hide the PIN'), ('4', 'Sign in'),
               ('5', 'Forgot your PIN? Ask your ACC or contact SDICS for a new one.')]))
    S.append(shot_steps(F('02_login_error'), 'A wrong PIN', [], items=[('1', 'The error message')], extra=[
        table(['Message', 'What to do'], [
            ['Wrong National ID or PIN.', 'Check both numbers and try again.'],
            ['This PIN is no longer valid. Contact SDICS for a new PIN.', 'Your PIN was replaced or ended. Contact SDICS (or your ACC) for a new one.'],
            ['Too many wrong attempts. Wait 15 minutes and try again.', 'Wait 15 minutes.'],
            ['Your session has ended. Sign in again with your PIN.', 'Sign in again.']], [0.55, 0.45], width=TW - 58 * mm)]))

    S += [P(f'{n}.3 The Home screen', H2)]
    S.append(shot_steps(F('03_home'), 'Home', [
        ('Check the top bar', 'It shows your initials, your name, your role ("Chief" or "Sub-chief") and your location. The three dots open your <b>Account</b>.'),
        ('Look at today\'s target', 'The ring shows how many you have registered today. "23 to go" is how many are left to reach the target.'),
        ('Use the quick actions', 'Big buttons for the things you do most.'),
        ('Use the bottom tabs', '<b>Home, Roll, Check ID, Statistics.</b> Tap one to move.')],
        items=[('1', 'Account (three dots)'), ('2', 'Today\'s target'), ('3', 'Open the roll'), ('4', 'Check an ID'),
               ('5', 'Daily total'), ('6', 'Correct figure'), ('7', 'Bottom tabs')]))

    S += [P(f'{n}.4 Sub-chiefs', H2),
          P('A <b>sub-chief</b> uses the same app, signs in the same way and has the same buttons as a chief. '
            'Two things are different:')]
    S.append(two_shots(F('18_subchief_home'), 'A sub-chief\'s Home screen', F('19_subchief_account'), 'A sub-chief\'s Account', w=48 * mm,
                       items=[('1', '"Sub-chief" next to your name'), ('2', 'Your location and your sub-location')]))
    S += steps([('Your role says Sub-chief', 'At the top, next to your name, and in your Account.'),
                ('You see only your sub-location', 'The roll, the search and the numbers on Home cover only the people of '
                 '<b>your sub-location</b> (for example KAPKUT EAST), not the whole location. Your sub-location is shown after '
                 'your location in the top bar and in your Account.'),
                ('Everything else is the same', 'Mark people as registered, work offline, check IDs, send a daily total and '
                 'correct figures exactly as this part explains.')])
    S += [callout('NOTE', 'Wrong sub-location?', 'If the sub-location in your Account is not where you work, call your ACC. '
                  'It is changed on the SDICS dashboard; sign out and in again after it is changed.')]

    S += [P(f'{n}.5 Moving around: the back arrow', H2),
          P('Pages you open from Home or the roll (a person, Daily total, Correct figure) have a <b>back arrow</b> '
            'at the top left. Tap it to go back. The phone\'s own <b>Back</b> button does the same. '
            'On Home, press Back twice to close the app.')]

    S += [PageBreak(), P(f'{n}.6 Mark a person as registered', H2),
          P('Do this <b>after</b> the person has registered with IEBC. Follow the steps in order.')]
    S.append(shot_steps(F('04_roll'), 'Step 1–2: the roll', [
        ('Open the roll', 'Tap <b>Roll</b> at the bottom (or "Open the roll" on Home).'),
        ('Look at the list', '"Still to register" shows everyone not yet registered. "Saved for offline" shows the list is saved on the phone.')],
        items=[('1', 'Still to register'), ('2', 'Saved for offline'), ('3', 'Search box'), ('4', 'A person'),
               ('5', 'Download the roll as PDF')]))
    S.append(shot_steps(F('05_search'), 'Step 3–4: search', [
        ('Search for the person', 'Tap the search box. Type at least 2 letters of the name, ID, father, clan or village.'),
        ('Tap the person', 'Tap their name in the list. Or tap "Show all matches" to see everyone who matches.')], start=3,
        items=[('1', 'Search box'), ('2', 'The person'), ('3', 'Show all matches')]))
    S.append(shot_steps(F('06_person'), 'Step 5–6: the person\'s details', [
        ('Check the details', 'Compare the name, ID, father and clan with the person in front of you. The ID shows only the last 3 digits.'),
        ('Tap Mark as registered', 'The green button at the bottom.')], start=5,
        items=[('1', 'Name'), ('2', 'NOT REGISTERED'), ('3', 'ID number (last 3 digits)'), ('4', 'Mark as registered'), ('5', 'Back arrow')]))
    S.append(shot_steps(F('07_confirm'), 'Step 7: confirm', [
        ('Tap Register', 'The box asks "Mark as registered?". It says the person will be recorded as registered by you, now. '
         'Tap <b>Register</b> if it is correct. Tap <b>Cancel</b> if it is the wrong person.')], start=7,
        items=[('1', 'The question'), ('2', 'Cancel'), ('3', 'Register')]))
    S.append(shot_steps(F('08_success'), 'Step 8: done', [
        ('See the message', '"<i>Name</i> is now registered." The person leaves the list. The green chip shows how many you did today.')], start=8,
        items=[('1', 'Success message'), ('2', 'Number registered today')],
        extra=[callout('TIP', 'Location is added for you', 'The app records the phone\'s location (GPS) when it can. You do not need to do anything.', width=TW - 58 * mm)]))

    S += [PageBreak(), P(f'{n}.7 Working without signal (offline)', H2),
          P('You can mark people as registered even with <b>no signal</b>. The app saves them on the phone and '
            '<b>sends them later</b> by itself.')]
    S.append(two_shots(F('09_offline_saved'), 'Marked while offline', F('10_offline_banner'), 'The yellow offline bar', w=48 * mm,
                       items=[('1', 'Offline — 1 waiting to send when you have signal'), ('2', 'The offline message / Sync now')]))
    S += steps([('Mark the person as usual', 'You see: "You\'re offline — <i>Name</i> is saved as registered and will be sent when you have signal."'),
                ('Look at the yellow bar', 'It shows how many are waiting to send.'),
                ('Get signal', 'Move to a place with signal. The app sends by itself. You can also tap <b>Sync now</b>.'),
                ('Tap the bar for more', 'It opens "Offline mode" with an explanation.')])
    S.append(shot_steps(F('11_offline_sheet'), 'Offline mode', [], items=[('1', 'Offline mode'), ('2', 'How many are waiting')], extra=[
        callout('IMPORTANT', 'Do not sign out while items are waiting',
                'Signing out deletes anything that has not been sent. Wait until the yellow bar is gone.', width=TW - 58 * mm),
        callout('NOTE', '"N saved items could not be sent"',
                'This means SDICS refused them. Call your ACC.', width=TW - 58 * mm)]))
    S += [P(f'{n}.8 When registration is not open', H2)]
    S.append(two_shots(F('16_not_open_home'), 'Message on Home', F('17_not_open_person'), 'Message on a person', w=48 * mm,
                       items=[('1', '"Registration isn\'t open in … yet"')]))
    S += [P('You can still look at the roll, but marking someone will not register them. Wait until your county is open.')]

    S += [PageBreak(), P(f'{n}.9 Check an ID', H2)]
    S.append(shot_steps(F('12_check_id'), 'Check an ID', [
        ('Tap Check ID', 'At the bottom of the screen.'),
        ('Type the ID number', 'In "National ID number". Kenyan ID numbers have 4 to 9 digits.'),
        ('Tap Check', 'You see <b>Registered</b> or <b>Not registered</b>, with the name and place.')],
        items=[('1', 'ID number box'), ('2', 'Check'), ('3', 'The answer')],
        extra=[P('"No one with ID … was found." means the number is wrong or not on the roll. '
                 'Without signal, the answer comes from the roll saved on your phone.', SMALL)]))
    S += [P(f'{n}.10 Statistics', H2)]
    S.append(shot_steps(F('13_stats'), 'Statistics', [
        ('Tap Statistics', 'At the bottom of the screen.'),
        ('Read your numbers', 'Pull the screen down to refresh.')],
        items=[('1', 'Registered today (and your target)'), ('2', 'This week'), ('3', 'Drive to date, through the app'),
               ('4', 'Still unregistered'), ('5', 'Drive progress %')]))
    S += [P(f'{n}.11 Daily total (paper registrations)', H2),
          P('Use this only if people were registered <b>on paper</b> today, for example when the phone was not working. '
            'Every chief has this button on the Home screen.')]
    S.append(shot_steps(F('20_daily_total'), 'Daily total', [
        ('Tap Daily total', 'On the Home screen.'),
        ('Type the number', 'In "People registered on paper today".'),
        ('Say why', 'In "Why paper today?". You must fill this in.'),
        ('Tap Send daily total', 'If you send again the same day, the new number <b>replaces</b> the old one.')],
        items=[('1', 'People registered on paper today'), ('2', 'Why paper today?'), ('3', 'Send daily total'), ('4', 'Back arrow')],
        extra=[callout('NOTE', 'Your daily total is checked', 'Every daily total is <b>verified</b> on the SDICS dashboard. '
                       'Until then it counts as pending. If it is <b>rejected</b> it no longer counts in your numbers. '
                       'If you send the day again, it is checked again.', width=TW - 58 * mm)]))
    S += [P(f'{n}.12 Correct figure', H2),
          P('Use this when the population number for your area is wrong.')]
    S += steps([('Tap Correct figure', 'On the Home screen. You see the CURRENT FIGURE.'),
                ('Type the correct number', 'In "Correct figure".'),
                ('Say how you know', 'In "How do you know? (optional)".'),
                ('Tap Send correction', 'You see "Correction sent for review." Someone will check it.')])

    S += [CondPageBreak(140 * mm), P(f'{n}.13 Sign out', H2),
          callout('NOTE', 'Your PIN stays the same',
                  'After you sign out, sign in again with the <b>same PIN</b>. You only need a new PIN if you forget it: '
                  'then contact SDICS (or your ACC). Only sign out when you are told to, '
                  'or when you hand the phone back.')]
    S.append(two_shots(F('14_account'), 'Account (tap the three dots)', F('15_signout'), 'Sign out?', w=48 * mm,
                       items=[('1', 'Your account / Stay signed in'), ('2', 'Sign out'), ('3', 'Your PIN stays the same')]))
    S += steps([('Tap the three dots', 'Top right. Your Account opens.'),
                ('Tap Sign out', 'A box asks "Sign out?".'),
                ('Choose', 'Tap <b>Stay signed in</b> to go back, or <b>Sign out</b> to finish. '
                 'If items are waiting to send, the app warns you: they will be lost.')])
    S += [P(f'{n}.14 Common problems', H2),
          table(['Problem', 'What to do'], [
              ['I forgot my PIN', 'Contact SDICS (or your ACC). They issue a new PIN; the old one stops working.'],
              ['"This PIN is no longer valid"', 'Your PIN was replaced. Contact SDICS for the new one.'],
              ['I see the wrong sub-location', 'Call your ACC; it is fixed on the SDICS dashboard. Sign out and in again.'],
              ['My daily total was rejected', 'Call your ACC to find out why, then send the correct number for that day.'],
              ['The yellow offline bar does not go away', 'Move to a place with signal. Check that mobile data is on. Tap Sync now.'],
              ['"N saved items could not be sent"', 'SDICS refused them. Call your ACC.'],
              ['I cannot find a person', 'Try another spelling, the father\'s name, clan or ID. If they are already registered, they are not on the list: use Check ID.'],
              ['I marked the wrong person', 'Call your ACC at once. Do not try to fix it yourself.'],
              ['"Registration isn\'t open in … yet"', 'Wait. Registration in your county has not started.'],
              ['The app is slow or frozen', 'Close it and open it again. Restart the phone (Part 0.5).']],
              [0.38, 0.62])]


# ---------------------------------------------------------------- Checkin app (clerks)
def part_checkin(n):
    global S
    S += [PageBreak()] + section(f'Part {n}', 'The Checkin app',
                                  'Check voters in at events, mobilize voters, and read your numbers.')
    S += [P(f'{n}.1 What the Checkin app is', H2),
          P('<b>Checkin</b> is MachineNova\'s app for your Android phone. You use it for two jobs:'),
          table(['Job', 'Colour', 'What it means'], [
              ['Check in', 'Green (teal)', 'Mark that a voter came to your <b>event</b>.'],
              ['Mobilize', 'Orange (amber)', '<b>Register</b> a voter you meet in the community, for example door to door.']],
              [0.2, 0.2, 0.6]),
          Spacer(1, 6),
          callout('TIP', 'The colour tells you the job',
                  'Green screens are for checking in. Orange screens are for mobilizing. Look at the colour before you start.')]
    S.append(shot_steps(K2('01_onboarding'), 'The first time you open the app', [
        ('Read the welcome pages', 'The app shows four short pages: welcome, scanning an ID, the two jobs, and working offline.'),
        ('Tap Next', 'On the last page the button says <b>Get started</b>. Tap <b>Skip</b> to go straight to sign in.')],
        items=[('1', 'Skip'), ('2', 'Next')]))

    S += [P(f'{n}.2 Sign in', H2),
          P('Your organization admin creates your account and gives you your email (or user ID) and password. '
            'This app is only for field staff: managers and admins use the web dashboard.')]
    S.append(shot_steps(K2('02_login'), 'Sign in to Checkin', [
        ('Type your email or user ID', 'The one your admin gave you.'),
        ('Type your password', 'Big and small letters must be exactly right. Tap the eye to see what you typed.'),
        ('Tap Sign in', 'Next, the app asks you to make a PIN.')],
        items=[('1', 'Email or user ID'), ('2', 'Password'), ('3', 'Sign in'), ('4', 'Forgot password?')],
        extra=[P('<b>Forgot password?</b> sends a reset link to your email.', SMALL)]))

    S += [P(f'{n}.3 Your app PIN', H2),
          P('A <b>PIN</b> is a short secret number (4 to 6 digits) that opens the app. It protects the voter information on the phone.')]
    S.append(two_shots(K2('03_set_pin'), 'Set an app PIN (first sign-in)', K2('04_lock'), 'Enter your PIN (every time)', w=48 * mm,
                       items=[('1', 'Set an app PIN / Enter your PIN'), ('2', 'Forgot PIN?')]))
    S += steps([('Choose a PIN', 'Type 4 to 6 digits, then type the same PIN again to confirm.'),
                ('Open the app with your PIN', 'The app locks itself after 2 minutes in the background. Type your PIN and tap <b>Unlock</b>.'),
                ('Forgot PIN?', 'Tap <b>Forgot PIN?</b> and type your account password (needs signal). Records saved on the phone are kept.')])
    S += [callout('IMPORTANT', 'Wrong PIN too many times',
                  '10 wrong tries in a row <b>erase this phone\'s Checkin data</b>. The data is also erased if the app is not '
                  'opened for 14 days. Then you must sign in again.')]

    S += [P(f'{n}.4 Getting around the app', H2)]
    S.append(shot_steps(K2('05_home'), 'The Home screen', [
        ('Look at Home', 'Your name and team, how many you checked in and mobilized today, and your team\'s totals.'),
        ('See recent activity', 'The people you and your team reached most recently.'),
        ('Tap the purple + button', 'It starts a check-in or a mobilization.'),
        ('Use the bottom bar', '<b>Home</b>, <b>People</b>, <b>Insights</b> and <b>Account</b>.')],
        items=[('1', 'Your name and team'), ('2', 'Team totals today'), ('3', 'Recent activity'), ('4', 'The + button'), ('5', 'Bottom bar')]))
    S.append(shot_steps(K2('06_choose'), 'After you tap +', [
        ('Choose the job', 'Tap <b>Check in</b> for an event, or <b>Mobilize</b> for registering voters.')], start=5,
        items=[('1', 'Check in'), ('2', 'Mobilize')]))

    S += [P(f'{n}.5 Check a voter in at an event', H2),
          P('You can only check people in to events you are <b>assigned</b> to. If your event is not in the list, ask your admin.')]
    S.append(shot_steps(K2('07_pick_event'), 'Choose your event', [
        ('Choose your event', 'Tap the green event box at the top, then tap your event. If you have only one, it is already chosen.')],
        items=[('1', 'Your event')]))
    S.append(shot_steps(K2('08_find'), 'Find the voter', [
        ('Scan the ID card', 'Tap <b>Scan ID card</b> and point the camera at the front or the back of the ID. The app reads the number.'),
        ('Or type the number', 'Type it in <b>ID number</b>.'),
        ('Tap Look up', 'The app finds the voter.')], start=2,
        items=[('1', 'Your event'), ('2', 'Scan ID card'), ('3', 'ID number'), ('4', 'Look up')]))
    S.append(shot_steps(K2('09_confirm'), 'Confirm and check in', [
        ('Check the details', 'Name, ID (last 3 digits), sex, age, where they vote and their polling centre. '
         'Green badges: <b>REGISTERED VOTER</b> and <b>IN REGION</b>.'),
        ('Add the phone number', 'If you have it.'),
        ('Tap Check in', 'The box clears for the next voter.')], start=5,
        items=[('1', 'The voter'), ('2', 'Phone'), ('3', 'Check in')]))
    S.append(shot_steps(K2('10_done'), 'Done', [
        ('See the message', 'A green message with a tick, "<i>Name</i> checked in", appears at the bottom. Scan or type the next ID.')], start=8,
        items=[('1', 'Success message')],
        extra=[callout('NOTE', 'Not in the register?',
                       'The app says "Not found in the register. Fill in their details." Type the name, sex, date of birth and where they are registered, then check them in.',
                       width=TW - 58 * mm)]))
    S.append(two_shots(K2('11_out_of_area'), 'A voter from outside the area', K2('12_already'), 'Already checked in today', w=48 * mm,
                       items=[('1', '"Outside this area" / "Already checked in today"'), ('2', 'Next voter')]))
    S += [table(['You see', 'What it means / what to do'], [
        ['OUT REGION and "Outside this area"', 'The voter is registered somewhere else. The app shows where they vote and where they come from, '
                                               'from official records: no need to ask. You can still check them in.'],
        ['"Already checked in today at … by …"', 'This person is done. Tap <b>Next voter</b>.'],
        ['"Not on the participant list"', 'This event only allows people on its list. They cannot be checked in.'],
        ['"Can\'t look up: …"', 'Check your signal and that you are assigned to the event. Try again.']], [0.36, 0.64]), Spacer(1, 6)]

    S += [P(f'{n}.6 No signal (offline)', H2)]
    S.append(shot_steps(K2('19_offline'), 'Saving a check-in with no signal', [
        ('Keep working', 'With no signal the app cannot check the register. It shows <b>Offline</b> at the top and a <b>Save check-in offline</b> form.'),
        ('Add what you know', 'Add the name and sex if the voter might not be on the register. Tap <b>Check in (save offline)</b>.'),
        ('Get signal', 'The app sends saved records by itself when you are back online. The top bar shows how many are waiting to sync.')],
        items=[('1', 'Offline bar'), ('2', 'Offline message')],
        extra=[callout('IMPORTANT', 'Before you sign out',
                       'Make sure everything is synced (Account → Sync &amp; offline data). If records are waiting, the app warns you before signing out.',
                       width=TW - 58 * mm)]))

    S += [P(f'{n}.7 Mobilize (register) a voter', H2),
          P('Do this when you meet a voter in the community. Each voter counts toward your <b>drive\'s</b> target. '
            'A voter can be mobilized only once, so there is no double counting.')]
    S.append(two_shots(K2('13_mobilize'), 'Choose the drive, find the voter', K2('14_mobilize_register'), 'Register', w=48 * mm,
                       items=[('1', 'Your drive / Register'), ('2', 'ID number'), ('3', 'Voter details')]))
    S += steps([('Start', 'Tap <b>+</b> and choose <b>Mobilize</b>.'),
                ('Check your drive', 'The orange box at the top shows your drive. The card under it shows Mobilized, Target, Remaining and the % done.'),
                ('Scan or type the ID', 'Tap <b>Scan ID card</b>, or type the number, then tap <b>Look up</b>.'),
                ('Check the voter details', 'Fill in anything missing. Add the phone number.'),
                ('Tap Register', 'A message with a tick, "<i>Name</i> registered", appears and the drive total goes up.')])
    S += [callout('NOTE', '"Already mobilized"',
                  'The app shows who registered this voter, where and when. Tap <b>Next voter</b>. Nothing else to do.')]

    S += [P(f'{n}.8 Insights: your numbers', H2),
          P('Tap <b>Insights</b> at the bottom. Choose <b>Check-ins</b> or <b>Mobilization</b> at the top. Tap the event or drive box to change it.')]
    S.append(two_shots(K2('15_insights_checkins'), 'Check-ins', K2('16_insights_mobilization'), 'Mobilization', w=48 * mm,
                       items=[('1', 'The tab'), ('2', 'The numbers'), ('3', 'Check-ins by hour / Top mobilizers')]))
    S += [table(['Number', 'What it means'], [
        ['Total check-ins', 'Every check-in at this event.'],
        ['Unique voters', 'How many different people came.'],
        ['In-region rate', 'How many of them are registered inside the event area.'],
        ['Peak hour', 'The busiest hour of the day.'],
        ['Voters mobilized / Of target / Remaining', 'How many the drive registered, how much of the goal that is, and how many are left.'],
        ['Mobilized today', 'How many were registered today.'],
        ['Top mobilizers', 'Your team, from the person who registered the most.']], [0.36, 0.64]), Spacer(1, 6)]

    S += [P(f'{n}.9 People and your account', H2)]
    S.append(two_shots(K2('17_people'), 'People', K2('18_account'), 'Account', w=48 * mm))
    S += [P('<b>People</b> (left): choose <b>Check-ins</b> or <b>Mobilized</b>, pick one event in <b>Event</b>, or search a name or ID number. '
            'Each row shows the name, ID (last 3 digits), place, time and an IN REGION or OUT REGION badge.'),
          P('<b>Account</b> (right): <b>Change password</b>, <b>Lock now</b>, <b>Change PIN</b>, '
            '<b>Unlock with fingerprint / face</b> (if your phone has it), <b>Sync &amp; offline data</b>, and <b>Sign out</b>.')]

    S += [P(f'{n}.10 Common problems', H2),
          table(['Problem', 'What to do'], [
              ['"You\'re not assigned to any active event"', 'Ask your organization admin to assign you.'],
              ['"This app is for field agents…"', 'Your account is a manager or admin account. Use the web dashboard, or ask your admin.'],
              ['I forgot my PIN', 'Tap <b>Forgot PIN?</b> and type your password (needs signal).'],
              ['I forgot my password', 'On the sign-in screen tap <b>Forgot password?</b>, or ask your admin.'],
              ['The camera does not read the ID', 'Hold the card flat in good light, or type the number.'],
              ['Records are waiting to sync', 'Get signal. Open Account → Sync &amp; offline data and tap Retry if needed.'],
              ['The phone\'s data was erased', 'Too many wrong PINs, or 14 days without use. Sign in again.']],
              [0.38, 0.62])]


# ---------------------------------------------------------------- Quick reference
def dos_donts(do, dont):
    t = Table([[[P('<b>DO</b>', st('do', fontName='Arial-Bold', fontSize=12, textColor=TEAL))] + bullets(do, SMALL),
                [P('<b>DON\'T</b>', st('dont', fontName='Arial-Bold', fontSize=12, textColor=FLAG_RED))] + bullets(dont, SMALL)]],
              colWidths=[TW / 2, TW / 2])
    t.setStyle(TableStyle([('VALIGN', (0, 0), (-1, -1), 'TOP'), ('BACKGROUND', (0, 0), (0, 0), TIP_BG),
                           ('BACKGROUND', (1, 0), (1, 0), IMP_BG), ('LEFTPADDING', (0, 0), (-1, -1), 10),
                           ('TOPPADDING', (0, 0), (-1, -1), 8), ('BOTTOMPADDING', (0, 0), (-1, -1), 10)]))
    return t


def quickref_clerks(n):
    global S
    S += [PageBreak()] + section(f'Part {n}', 'Quick reference', 'Cut out these pages and keep them with you.')
    S += [P('IEBC dashboard', H2), table(['To do this', 'Do this'], [
        ['Open the dashboard', 'Browser → <b>sdics.tech/iebc</b>'],
        ['Sign in', 'Your username + password → <b>Sign in</b>'],
        ['Find a voter', 'Type the ID number, father\'s name or family name (2+ letters) → tap a suggestion or <b>Search</b>'],
        ['Is this ID registered?', 'Voter lookup → type the ID → <b>Check</b>'],
        ['See everyone again', 'Tap <b>Clear</b>'],
        ['Next page', 'Tap the arrow <b>&gt;</b>'],
        ['Found someone unregistered', 'Register them the usual IEBC way'],
        ['Wrong password 5 times', 'Wait 15 minutes'],
        ['Finish', 'Sign-out button (top right), then close the browser']], [0.32, 0.68])]
    S += [Spacer(1, 10), P('Checkin app', H2), table(['To do this', 'Do this'], [
        ['Open the app', 'Type your PIN → <b>Unlock</b>'],
        ['Check a voter in', '<b>+</b> → Check in → choose the event → <b>Scan ID card</b> (or type the ID) → <b>Look up</b> → check → <b>Check in</b>'],
        ['Mobilize a voter', '<b>+</b> → Mobilize → <b>Scan ID card</b> (or type the ID) → <b>Look up</b> → fill in → <b>Register</b>'],
        ['No signal', 'Keep working: <b>Check in (save offline)</b>. It syncs when you are back online'],
        ['See my numbers', 'Insights → Check-ins or Mobilization'],
        ['See who I reached', 'People → Check-ins or Mobilized → search'],
        ['Forgot PIN', '<b>Forgot PIN?</b> → your password'],
        ['Before signing out', 'Account → Sync &amp; offline data: nothing waiting']], [0.32, 0.68])]
    S += [PageBreak(), P("Do's and Don'ts", H2), dos_donts([
        'Choose the right event or drive before you start.',
        'Check the name and ID before you check in or register someone.',
        'Keep the phone charged, dry and with you.',
        'Sign out of the IEBC dashboard when you finish.',
        'Call for help when you are not sure.'], [
        'Don\'t share your password or PIN with anyone.',
        'Don\'t photograph or share voter names or ID numbers.',
        'Don\'t let anyone else use your phone or account.',
        'Don\'t stop a check-in just because it says OUT REGION.',
        'Don\'t try to mobilize the same voter twice.'])]
    S += [Spacer(1, 12), P('Who to call', H2),
          table(['Who', 'When', 'Phone number'], [
              ['SDICS help desk', 'IEBC dashboard not working, no constituency assigned, password reset', '[to be filled in]'],
              ['IEBC help', 'Questions about voter registration itself', '[to be filled in]'],
              ['Checkin organization admin', 'Checkin account, event or drive missing, participant list', '[to be filled in]']],
              [0.27, 0.48, 0.25]),
          Spacer(1, 10),
          P('My name: ______________________________ &nbsp;&nbsp; My constituency: __________________________', BODY)]


def quickref_chiefs(n):
    global S
    S += [PageBreak()] + section(f'Part {n}', 'Quick reference', 'Cut out this page and keep it with you.')
    S += [P('SDICS Field app', H2), table(['To do this', 'Do this'], [
        ['Sign in', 'National ID + PIN → <b>Sign in</b>'],
        ['Register a person', 'Roll → search → tap the person → check details → <b>Mark as registered</b> → <b>Register</b>'],
        ['No signal', 'Work as normal. Items wait in the yellow bar. Get signal → <b>Sync now</b>'],
        ['Is this ID registered?', 'Check ID → type the number → <b>Check</b>'],
        ['My numbers', 'Statistics (pull down to refresh)'],
        ['Paper registrations', 'Home → Daily total → number + reason → <b>Send daily total</b>'],
        ['Population is wrong', 'Home → Correct figure → new number → <b>Send correction</b>'],
        ['Forgot PIN', 'Contact SDICS (or your ACC) for a new PIN'],
        ['Go back', 'The back arrow (top left) or the phone\'s Back button'],
        ['Sub-chief', 'Same app and buttons; you see only your sub-location'],
        ['Sign out', 'Only when told to. Your PIN stays the same. Never with items waiting to send.']], [0.32, 0.68])]
    S += [Spacer(1, 12), P("Do's and Don'ts", H2), dos_donts([
        'Check the name, ID and father\'s name before you mark someone.',
        'Keep the phone charged, dry and with you.',
        'Let offline items send before the end of the day.',
        'Call your ACC when you are not sure.'], [
        'Don\'t share your PIN with anyone.',
        'Don\'t mark a person who has not registered with IEBC.',
        'Don\'t photograph or share voter names or ID numbers.',
        'Don\'t sign out while items are waiting to send.'])]
    S += [Spacer(1, 12), P('Who to call', H2),
          table(['Who', 'When', 'Phone number'], [
              ['Your ACC', 'Items that could not be sent, wrong person marked, wrong sub-location, rejected daily total', '[to be filled in]'],
              ['SDICS', 'Forgotten PIN, "This PIN is no longer valid"', '[to be filled in]'],
              ['SDICS help desk', 'App not working, no location assigned', '[to be filled in]'],
              ['IEBC help', 'Questions about voter registration itself', '[to be filled in]']], [0.25, 0.5, 0.25]),
          Spacer(1, 10),
          P('My name: ______________________________ &nbsp;&nbsp; My location: ______________________________', BODY),
          P('My ACC: _______________________________ &nbsp;&nbsp; ACC phone: ________________________________', BODY)]


if AUD == 'clerks':
    part_dashboard(1); part_checkin(2); quickref_clerks(3)
else:
    part_field(1); quickref_chiefs(2)



def glue(story):
    out, i = [], 0
    while i < len(story):
        f = story[i]
        if isinstance(f, Paragraph) and f.style.name in ('h2', 'h3'):
            grp = [f]; i += 1
            while i < len(story) and isinstance(story[i], Paragraph) and story[i].style.name not in ('h2',):
                grp.append(story[i]); i += 1
            if i < len(story) and not isinstance(story[i], (PageBreak, CondPageBreak, Paragraph)):
                nxt = story[i]
                grp.extend(nxt._content if isinstance(nxt, KeepTogether) else [nxt]); i += 1
            out.append(KeepTogether(grp))
        else:
            out.append(f); i += 1
    return out

doc.build(glue(S))
print('wrote', OUT)
