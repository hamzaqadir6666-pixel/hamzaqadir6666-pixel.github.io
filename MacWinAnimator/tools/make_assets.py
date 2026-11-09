#!/usr/bin/env python3
"""Regenerate everything in assets/: icon.png, icon.ico, preview.gif.

Run from the project root:   python tools/make_assets.py
Needs only Pillow.  The preview GIF renders the real Genie engine
(macwin.effects) on a fake desktop so users can see the effect
before installing anything.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from PIL import Image, ImageDraw  # noqa: E402

from macwin import effects  # noqa: E402
from macwin.icon import make_demo_window_image, make_icon_image  # noqa: E402

ASSETS = Path(__file__).resolve().parent.parent / "assets"


def make_icons() -> None:
    icon = make_icon_image(256)
    icon.save(ASSETS / "icon.png")
    icon.save(ASSETS / "icon.ico",
              sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("icon.png / icon.ico written")


def _wallpaper(w: int, h: int) -> Image.Image:
    img = Image.new("RGBA", (w, h))
    top, bot = (24, 28, 48), (52, 40, 84)
    for y in range(h):
        t = y / max(1, h - 1)
        img.paste(tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,),
                  (0, y, w, y + 1))
    draw = ImageDraw.Draw(img, "RGBA")
    for x, y, r, a in ((90, 70, 60, 60), (520, 120, 90, 45), (300, 40, 40, 50), (620, 300, 70, 35)):
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(120, 140, 220, a))
    # taskbar
    draw.rectangle([0, h - 34, w, h], fill=(16, 18, 26, 255))
    draw.rounded_rectangle([w // 2 - 120, h - 27, w // 2 + 120, h - 7], radius=8,
                           outline=(90, 100, 130, 255), width=1)
    for i in range(4):  # taskbar icons
        x = w // 2 - 104 + i * 30
        draw.rounded_rectangle([x, h - 25, x + 20, h - 9], radius=5,
                               fill=(70, 80, 105, 255))
    draw.rounded_rectangle([w // 2 - 10, h - 25, w // 2 + 10, h - 9], radius=5,
                           fill=(45, 212, 191, 255))  # the 'minimized to' icon
    return img


def make_preview() -> None:
    W, H = 640, 420
    base = _wallpaper(W, H)
    window = make_demo_window_image(320, 210)
    src = (160, 78, 480, 288)
    target = (W // 2, H - 34)
    frames: list[Image.Image] = []

    def compose(t: float | None) -> Image.Image:
        frame = base.copy()
        if t is not None:
            ghost = effects.render_genie_frame(window, t, src, target, (W, H))
            frame.alpha_composite(ghost)
        return frame.convert("P", palette=Image.ADAPTIVE, colors=128)

    for i in range(26):   # minimize
        frames.append(compose(effects.ease_in_out_cubic(i / 25)))
    for _ in range(7):    # sit in the taskbar
        frames.append(compose(1.0))
    for i in range(20):   # restore
        frames.append(compose(1.0 - effects.ease_out_cubic(i / 19)))
    for _ in range(8):    # rest
        frames.append(compose(0.0))

    frames[0].save(ASSETS / "preview.gif", save_all=True, append_images=frames[1:],
                   duration=33, loop=0, optimize=True)
    print(f"preview.gif written ({len(frames)} frames)")


if __name__ == "__main__":
    ASSETS.mkdir(exist_ok=True)
    make_icons()
    make_preview()
