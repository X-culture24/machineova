"""One-page SDICS trainer guide: mark a chief present and collect their phone number.

usage: build_trainer_guide.py <annotated_shots_dir> <out.pdf>
Shots come from sdics_trainer_shots_test.dart (real app screens, made-up chiefs), numbered by
annotate.py. Lexend is the apps' font (fonts/, SIL OFL).
"""
import os
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph

SHOTS, OUT = sys.argv[1], sys.argv[2]
FONTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fonts')
pdfmetrics.registerFont(TTFont('Lexend', os.path.join(FONTS, 'Lexend-400.ttf')))
pdfmetrics.registerFont(TTFont('Lexend-Medium', os.path.join(FONTS, 'Lexend-500.ttf')))
pdfmetrics.registerFont(TTFont('Lexend-Bold', os.path.join(FONTS, 'Lexend-700.ttf')))
pdfmetrics.registerFontFamily('Lexend', normal='Lexend', bold='Lexend-Bold', italic='Lexend', boldItalic='Lexend-Bold')

C = colors.HexColor
GREEN, GREEN_D, NAVY, GREY = C('#00875A'), C('#0B3D2E'), C('#0F1419'), C('#5A6472')
AMBER, AMBER_BG, TINT, LINE = C('#F2A007'), C('#FDF0D7'), C('#E0F5ED'), C('#DCE3DF')
FLAG_BLACK, FLAG_RED, FLAG_GREEN = C('#000000'), C('#BB0000'), C('#006600')

BODY = ParagraphStyle('b', fontName='Lexend', fontSize=7.4, leading=9.6, textColor=NAVY, alignment=TA_LEFT)
TIP = ParagraphStyle('t', parent=BODY, fontSize=7.6, leading=10)

W, H = A4
M = 11 * mm          # page margin
GAP = 4 * mm         # between columns
COLS = 4
CW = (W - 2 * M - (COLS - 1) * GAP) / COLS   # column width
IW = CW - 2 * mm                              # screenshot width
IH = IW * 1560 / 720                          # phone aspect

# Bold numbers in the text match the orange numbers on the screenshots.
def n(k):
    return f'<font name="Lexend-Bold" color="#9A6200">({k})</font>'


STEPS = [
    ('1_login', 'Sign in',
     f'Open the <b>MachineNova</b> app. Type the email {n(1)} and password {n(2)} your admin gave you. '
     f'Tap <b>Sign in</b> {n(3)}. First time only: set a 4-digit app PIN.'),
    ('2_home', 'Start',
     f'Tap <b>Mark chief present</b> {n(1)} or the <b>+</b> button {n(2)}. '
     'Your county\'s training opens.'),
    ('3_find', 'Find the chief',
     f'Check the training {n(1)} is yours. <b>Scan the chief\'s ID card</b> {n(2)} or type the ID number {n(3)}. '
     f'Tap <b>Look up</b> {n(4)}.'),
    ('4_phone', 'Phone, then present',
     f'The chief comes up from the <b>IEBC voter register</b> {n(1)}. Confirm the name with the chief. '
     f'Type the <b>chief\'s phone number</b> {n(2)} (required). Tap <b>Mark chief present</b> {n(3)}.'),
    ('5_done', 'Saved: next chief',
     f'A green message {n(1)} means the chief is marked present with their phone number. '
     'The ID box is empty again: call the next chief.'),
    ('6_present', 'Who turned up',
     f'<b>People</b> tab: every chief marked present. Pick your training {n(1)}. '
     f'Each row shows the chief {n(2)} and their phone number {n(3)}.'),
    ('7_insights', 'How many came',
     f'<b>Insights</b> tab: <b>Chiefs present</b> {n(1)} at your training today, and when they arrived.'),
]


def header(c):
    top = H - M
    # Kenyan flag stripe, as on the SDICS manuals
    sw = (W - 2 * M) / 5
    for i, col in enumerate([FLAG_BLACK, FLAG_RED, FLAG_GREEN, FLAG_RED, FLAG_BLACK]):
        c.setFillColor(col)
        c.rect(M + i * sw, top - 1.6 * mm, sw, 1.6 * mm, stroke=0, fill=1)
    c.setFillColor(GREEN)
    c.setFont('Lexend-Bold', 7.5)
    c.drawString(M, top - 6.5 * mm, 'SDICS CHIEFS TRAINING  ·  TRAINER GUIDE')
    c.setFillColor(NAVY)
    c.setFont('Lexend-Bold', 17)
    c.drawString(M, top - 13.5 * mm, 'Mark a chief present and collect their phone number')
    c.setFillColor(GREY)
    c.setFont('Lexend', 8.6)
    c.drawString(M, top - 19 * mm,
                 'For trainers at the county trainings. One chief at a time: find them in the IEBC voter register, '
                 'take their phone number,')
    c.drawString(M, top - 23 * mm, 'mark them present.')
    return top - 27 * mm


def step(c, x, y, k, img, title, text):
    # number badge + title
    c.setFillColor(GREEN)
    c.circle(x + 3.2 * mm, y - 3.2 * mm, 3.2 * mm, stroke=0, fill=1)
    c.setFillColor(colors.white)
    c.setFont('Lexend-Bold', 9)
    c.drawCentredString(x + 3.2 * mm, y - 4.3 * mm, str(k))
    c.setFillColor(NAVY)
    c.setFont('Lexend-Bold', 9.4)
    c.drawString(x + 8 * mm, y - 4.4 * mm, title)
    # screenshot in a light phone frame
    iy = y - 8.5 * mm - IH
    c.setFillColor(C('#F6F8F7'))
    c.setStrokeColor(LINE)
    c.setLineWidth(0.6)
    c.roundRect(x, iy - 1 * mm, CW, IH + 2 * mm, 2.5 * mm, stroke=1, fill=1)
    c.drawImage(os.path.join(SHOTS, img + '.png'), x + (CW - IW) / 2, iy, IW, IH, mask='auto')
    # caption
    p = Paragraph(text, BODY)
    _, ph = p.wrap(CW, 40 * mm)
    p.drawOn(c, x, iy - 2.5 * mm - ph)
    return iy - 2.5 * mm - ph


def tips(c, x, y, h):
    c.setFillColor(AMBER_BG)
    c.setStrokeColor(AMBER)
    c.setLineWidth(0.8)
    c.roundRect(x, y - h, CW, h, 3 * mm, stroke=1, fill=1)
    c.setFillColor(C('#9A6200'))
    c.setFont('Lexend-Bold', 9.4)
    c.drawString(x + 3 * mm, y - 6 * mm, 'Good to know')
    items = [
        '<b>Not in the register?</b> The app says so. Type the chief\'s name, sex, date of birth and area, '
        'then the phone number, and mark present.',
        '<b>Already marked present today?</b> The app tells you and who did it. Nothing to do: next chief.',
        '<b>No signal?</b> Keep going. Each chief is saved on the phone and sent when you are back online.',
        '<b>Phone number:</b> type it as the chief gives it, for example 0712 345 678 or +254 712 345 678.',
        '<b>Admins</b> see every county at <b>checkin.sdics.tech</b>: <b>People</b> lists each chief present with '
        'their phone number; <b>Export CSV</b> downloads the list.',
        '<b>Problems signing in?</b> Ask your admin to reset your password.',
    ]
    yy = y - 10 * mm
    for t in items:
        p = Paragraph('•  ' + t, TIP)
        _, ph = p.wrap(CW - 6 * mm, h)
        p.drawOn(c, x + 3 * mm, yy - ph)
        yy -= ph + 2.2 * mm


def main():
    from reportlab.pdfgen import canvas
    c = canvas.Canvas(OUT, pagesize=A4)
    c.setTitle('SDICS Chiefs Training — Trainer guide')
    c.setSubject('Mark a chief present and collect their phone number')
    c.setAuthor('MachineNova')
    y = header(c)
    lowest = y
    for i, (img, title, text) in enumerate(STEPS[:4]):
        lowest = min(lowest, step(c, M + i * (CW + GAP), y, i + 1, img, title, text))
    y2 = lowest - 5 * mm
    lowest2 = y2
    for i, (img, title, text) in enumerate(STEPS[4:]):
        lowest2 = min(lowest2, step(c, M + i * (CW + GAP), y2, i + 5, img, title, text))
    tips(c, M + 3 * (CW + GAP), y2, y2 - lowest2)
    # footer
    c.setStrokeColor(LINE)
    c.line(M, 9.5 * mm, W - M, 9.5 * mm)
    c.setFillColor(GREY)
    c.setFont('Lexend', 6.8)
    c.drawString(M, 6 * mm, 'SDICS Chiefs Training · Trainer guide · November 2026')
    c.drawRightString(W - M, 6 * mm, 'Screens show sample data (made-up chiefs).')
    if lowest2 < 11 * mm:
        print(f'WARNING: content runs into the footer ({lowest2 / mm:.1f} mm from the bottom)')
    c.showPage()
    c.save()
    print('wrote', OUT)


main()
