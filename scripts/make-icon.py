#!/usr/bin/env python3
"""Draws the app icon (app/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png): an open-wheel car seen from
above under radio waves, on red. Geometry only, no font and no licensed artwork. Needs Pillow.

    python3 scripts/make-icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
S = 4  # drawn 4x larger, then reduced: smooth edges
OUT = Path(__file__).resolve().parent.parent / "app/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

TOP = (232, 22, 32)
BOTTOM = (122, 8, 14)
WHITE = (255, 255, 255)
DARK = (22, 22, 26)


def px(v):
    return int(round(v * S))


def rect(d, x0, y0, x1, y1, r, fill):
    d.rounded_rectangle([px(x0), px(y0), px(x1), px(y1)], radius=px(r), fill=fill)


def main():
    w = SIZE * S
    img = Image.new("RGB", (w, w))
    d = ImageDraw.Draw(img)
    for y in range(w):
        t = y / (w - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))

    cx = SIZE / 2
    # radio waves over the nose
    for i, radius in enumerate((80, 145, 210)):
        box = [px(cx - radius), px(320 - radius), px(cx + radius), px(320 + radius)]
        d.arc(box, start=232, end=308, fill=WHITE, width=px(28 - i * 3))

    # wheels (front pair, rear pair wider)
    for side in (-1, 1):
        rect(d, cx + side * 150 - 48, 400, cx + side * 150 + 48, 530, 26, DARK)
        rect(d, cx + side * 165 - 58, 700, cx + side * 165 + 58, 860, 30, DARK)
    # front wing, nose, body, sidepods, rear wing
    rect(d, cx - 230, 345, cx + 230, 390, 18, WHITE)
    d.polygon([(px(cx - 34), px(355)), (px(cx + 34), px(355)), (px(cx + 62), px(600)), (px(cx - 62), px(600))], fill=WHITE)
    rect(d, cx - 110, 560, cx + 110, 840, 70, WHITE)
    rect(d, cx - 70, 520, cx + 70, 880, 60, WHITE)
    rect(d, cx - 200, 865, cx + 200, 920, 20, WHITE)
    # cockpit
    d.ellipse([px(cx - 42), px(600), px(cx + 42), px(720)], fill=DARK)

    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, optimize=True)
    print(OUT)


if __name__ == "__main__":
    main()
