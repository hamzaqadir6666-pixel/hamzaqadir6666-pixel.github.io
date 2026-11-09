"""The animation math — pure Pillow, no Windows APIs.

Every effect renders one frame of the captured window bitmap onto a
transparent canvas:

``render_frame(image, effect, t, src_rect, target, canvas_size)``

* ``image``     – RGBA screenshot of the real window
* ``t``         – *eased* progress, 0.0 = untouched window, 1.0 = fully
                  sucked into the taskbar
* ``src_rect``  – (left, top, right, bottom) of the window, in canvas coords
* ``target``    – (x, y) point on the taskbar the window pours into
* ``canvas_size`` – (width, height) of the overlay canvas

Because this module is platform independent it is unit-tested and is
also what generates the preview GIF in ``assets/``.
"""
from __future__ import annotations

from PIL import Image

Rect = tuple  # (left, top, right, bottom)


# ----------------------------------------------------------------------
# Easing
# ----------------------------------------------------------------------
def ease_in_out_cubic(t: float) -> float:
    t = max(0.0, min(1.0, t))
    if t < 0.5:
        return 4 * t * t * t
    return 1 - pow(-2 * t + 2, 3) / 2


def ease_out_cubic(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return 1 - pow(1 - t, 3)


# ----------------------------------------------------------------------
# Genie geometry
# ----------------------------------------------------------------------
def _genie_move(v: float, e: float) -> float:
    """How far a horizontal slice at height fraction ``v`` (0=top,
    1=bottom) has travelled toward the target at progress ``e``.

    The bottom slice leads (exponent 1) and the top slice lags
    (exponent 2.6), which is what makes the window stretch and pour
    instead of just sliding.
    """
    if e <= 0.0:
        return 0.0
    return e ** (1.0 + (1.0 - v) * 1.6)


def _genie_width_scale(v: float, e: float) -> float:
    """Width of a slice: the bottom pinches to a thin neck (~3%) while
    the top is still ~33% wide at the end — the classic funnel shape."""
    return (1.0 - e) + e * (0.03 + 0.30 * (1.0 - v) ** 1.5)


def _genie_y(v: float, e: float, top: float, height: float, target_y: float) -> float:
    src_y = top + v * height
    return src_y + (target_y - src_y) * _genie_move(v, e)


def render_genie_frame(image: Image.Image, t: float,
                       src_rect: Rect, target: tuple,
                       canvas_size: tuple) -> Image.Image:
    left, top, right, bottom = src_rect
    width, height = right - left, bottom - top
    tx, ty = target
    frame = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    if width <= 0 or height <= 0:
        return frame
    e = max(0.0, min(1.0, t))
    if e == 0.0:
        frame.alpha_composite(image.resize((width, height)), (left, top))
        return frame

    src = image.resize((width, height))
    strips = max(24, min(120, height // 6))
    src_cx = left + width / 2.0
    for i in range(strips):
        v0, v1 = i / strips, (i + 1) / strips
        vc = (v0 + v1) / 2.0
        y0 = _genie_y(v0, e, top, height, ty)
        y1 = _genie_y(v1, e, top, height, ty)
        dest_h = max(1, int(round(y1 - y0)))
        dest_w = max(1, int(round(width * _genie_width_scale(vc, e))))
        move = _genie_move(vc, e)
        dest_cx = src_cx + (tx - src_cx) * move
        strip = src.crop((0, int(v0 * height), width, max(int(v0 * height) + 1, int(v1 * height))))
        strip = strip.resize((dest_w, dest_h))
        frame.alpha_composite(strip, (int(round(dest_cx - dest_w / 2)), int(round(y0))))
    return frame


# ----------------------------------------------------------------------
# Scale & Fade
# ----------------------------------------------------------------------
def render_scale_frame(image: Image.Image, t: float,
                       src_rect: Rect, target: tuple,
                       canvas_size: tuple) -> Image.Image:
    left, top, right, bottom = src_rect
    width, height = right - left, bottom - top
    frame = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    if width <= 0 or height <= 0:
        return frame
    e = max(0.0, min(1.0, t))
    scale = 1.0 - e * 0.97
    new_w, new_h = max(1, int(width * scale)), max(1, int(height * scale))
    src_cx, src_cy = left + width / 2.0, top + height / 2.0
    cx = src_cx + (target[0] - src_cx) * e
    cy = src_cy + (target[1] - src_cy) * e
    resized = image.resize((new_w, new_h))
    if e > 0:  # gentle fade-out while shrinking
        alpha = resized.split()[3].point(lambda a: int(a * (1.0 - 0.35 * e)))
        resized.putalpha(alpha)
    frame.alpha_composite(resized, (int(cx - new_w / 2), int(cy - new_h / 2)))
    return frame


def render_fade_frame(image: Image.Image, t: float,
                      src_rect: Rect, target: tuple,
                      canvas_size: tuple) -> Image.Image:
    left, top, right, bottom = src_rect
    width, height = right - left, bottom - top
    frame = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    if width <= 0 or height <= 0:
        return frame
    e = max(0.0, min(1.0, t))
    scale = 1.0 - 0.12 * e
    new_w, new_h = max(1, int(width * scale)), max(1, int(height * scale))
    cx = left + width / 2.0 + (target[0] - (left + width / 2.0)) * e * 0.35
    cy = top + height / 2.0 + e * 46  # slide down while fading
    resized = image.resize((new_w, new_h))
    alpha = resized.split()[3].point(lambda a: int(a * (1.0 - e)))
    resized.putalpha(alpha)
    frame.alpha_composite(resized, (int(cx - new_w / 2), int(cy - new_h / 2)))
    return frame


_RENDERERS = {
    "genie": render_genie_frame,
    "scale": render_scale_frame,
    "fade": render_fade_frame,
}


def render_frame(image: Image.Image, effect: str, t: float,
                 src_rect: Rect, target: tuple,
                 canvas_size: tuple) -> Image.Image:
    try:
        renderer = _RENDERERS[effect]
    except KeyError:
        raise ValueError(f"unknown effect: {effect!r}") from None
    return renderer(image, t, src_rect, target, canvas_size)


def frame_bbox(src_rect: Rect, target: tuple, pad: int = 24) -> Rect:
    """Smallest canvas (overlay window) covering both the window and
    the taskbar target point, so frames are rendered into a window
    only as large as they need to be."""
    left, top, right, bottom = src_rect
    tx, ty = target
    return (min(left, tx - pad), min(top, ty - pad),
            max(right, tx + pad), max(bottom, ty + pad))
