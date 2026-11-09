"""Programmatic tray icon — a rounded gradient tile with a white
'genie funnel' glyph.  Used live by the tray and to generate the
committed files in ``assets/`` (see tools/make_assets.py)."""
from __future__ import annotations

import math

from PIL import Image, ImageDraw


def _lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def make_icon_image(size: int = 256) -> Image.Image:
    """Draw the MacWinAnimator icon at ``size`` x ``size`` (RGBA)."""
    s = size
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # vertical gradient background (teal -> blue, matches the site)
    top_rgb, bot_rgb = (45, 212, 191), (37, 99, 235)
    grad = Image.new("RGBA", (1, s))
    for y in range(s):
        t = y / max(1, s - 1)
        grad.putpixel((0, y), (_lerp(top_rgb[0], bot_rgb[0], t),
                               _lerp(top_rgb[1], bot_rgb[1], t),
                               _lerp(top_rgb[2], bot_rgb[2], t), 255))
    grad = grad.resize((s, s))
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [s * 0.04, s * 0.04, s * 0.96, s * 0.96], radius=s * 0.24, fill=255)
    img.paste(grad, (0, 0), mask)
    draw = ImageDraw.Draw(img)

    # white genie funnel: wide window at the top pouring to a point
    cx = s / 2
    funnel = [
        (cx - s * 0.30, s * 0.18), (cx + s * 0.30, s * 0.18),
        (cx + s * 0.10, s * 0.52), (cx + s * 0.035, s * 0.74),
        (cx - s * 0.035, s * 0.74), (cx - s * 0.10, s * 0.52),
    ]
    draw.polygon(funnel, fill=(255, 255, 255, 235))
    # window title-bar dots (traffic lights)
    for i, col in enumerate([(255, 95, 86, 255), (255, 189, 46, 255), (39, 201, 63, 255)]):
        x = cx - s * 0.30 + s * 0.07 + i * s * 0.11
        r = s * 0.032
        draw.ellipse([x - r, s * 0.245 - r, x + r, s * 0.245 + r], fill=col)
    # the drop landing in the 'dock'
    draw.ellipse([cx - s * 0.055, s * 0.78, cx + s * 0.055, s * 0.89],
                 fill=(255, 255, 255, 235))
    draw.rounded_rectangle([cx - s * 0.30, s * 0.905, cx + s * 0.30, s * 0.935],
                           radius=s * 0.02, fill=(255, 255, 255, 160))
    return img


def make_demo_window_image(width: int = 600, height: int = 400) -> Image.Image:
    """A fake app window used only for the preview GIF / tests."""
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([0, 0, width - 1, height - 1], radius=18,
                           fill=(32, 36, 48, 255), outline=(90, 100, 120, 255), width=2)
    draw.rounded_rectangle([0, 0, width - 1, 52], radius=18, fill=(52, 58, 74, 255))
    draw.rectangle([0, 30, width, 53], fill=(52, 58, 74, 255))
    for i, col in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        x = 22 + i * 26
        draw.ellipse([x, 18, x + 15, 33], fill=col + (255,))
    draw.rounded_rectangle([width - 130, 16, width - 22, 38], radius=8, fill=(70, 78, 98, 255))
    for i in range(6):
        y = 84 + i * 46
        w = width - 90 - (i * 53) % 170
        draw.rounded_rectangle([26, y, 26 + w, y + 20], radius=9, fill=(86, 96, 118, 255))
    draw.rounded_rectangle([26, height - 62, width - 26, height - 24], radius=10,
                           fill=(45, 212, 191, 255))
    return img
