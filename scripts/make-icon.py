#!/usr/bin/env python3
"""Draws the app icon (app/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png): a checkered flag in white
lines on red, in the style of TV Scores' court (one centred subject, one line weight, the shapes only lightly filled,
lit from the top left). Julien, 2026-10-31: "the skeleton of an icon of sport, maybe a flag", not a drawing of the car.
Geometry only, no font and no artwork. Needs Pillow and numpy.

    python3 scripts/make-icon.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

SIZE = 1024
S = 4  # drawn 4x larger, then reduced: smooth edges
OUT = Path(__file__).resolve().parent.parent / "app/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"

RED_LIGHT = (236, 38, 44)
RED_DEEP = (128, 10, 18)
WHITE = (255, 255, 255, 255)
SQUARE = (255, 255, 255, 70)  # the dark squares of the flag: a light wash, as the court's surface
LINE = 24
COLS, ROWS = 4, 3
POLE_X = 282
FLAG = (POLE_X, 250, 742, 562)  # left, top, right, bottom
POLE_BOTTOM = 800


def px(v):
    return int(round(v * S))


def background(w):
    # lit from the top left, falling to the deep red at the bottom right
    t = (np.arange(w)[None, :] + np.arange(w)[:, None]) / (2 * (w - 1))
    rgb = [a + (b - a) * t for a, b in zip(RED_LIGHT, RED_DEEP)]
    return Image.fromarray(np.dstack(rgb).astype(np.uint8), "RGB").convert("RGBA")


def main():
    w = SIZE * S
    img = background(w)
    overlay = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)

    left, top, right, bottom = FLAG
    cw = (right - left) / COLS
    ch = (bottom - top) / ROWS
    # alternate squares, washed in white
    for r in range(ROWS):
        for c in range(COLS):
            if (r + c) % 2 == 0:
                d.rectangle([px(left + c * cw), px(top + r * ch), px(left + (c + 1) * cw), px(top + (r + 1) * ch)],
                            fill=SQUARE)
    img.alpha_composite(overlay)

    d = ImageDraw.Draw(img)
    half = LINE / 2
    # the grid inside the flag
    for c in range(1, COLS):
        x = left + c * cw
        d.rectangle([px(x - half), px(top), px(x + half), px(bottom)], fill=WHITE)
    for r in range(1, ROWS):
        y = top + r * ch
        d.rectangle([px(left), px(y - half), px(right), px(y + half)], fill=WHITE)
    # the flag's outline, its free corners rounded
    d.rounded_rectangle([px(left - half), px(top - half), px(right + half), px(bottom + half)], radius=px(30),
                        outline=WHITE, width=px(LINE), corners=(False, True, True, False))
    # the pole, from the flag's top to below it, round at both ends
    d.rounded_rectangle([px(POLE_X - half), px(top - half - 18), px(POLE_X + half), px(POLE_BOTTOM)], radius=px(half),
                        fill=WHITE)

    img = img.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, optimize=True)
    print(OUT)


if __name__ == "__main__":
    main()
