"""Unit tests for the platform-independent animation engine."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from PIL import Image  # noqa: E402

from macwin import effects  # noqa: E402
from macwin.icon import make_demo_window_image, make_icon_image  # noqa: E402

SRC = (100, 80, 500, 380)          # a 400x300 window
TARGET = (560, 700)                # taskbar point below-right of it
CANVAS = (800, 760)


def _img():
    return make_demo_window_image(400, 300)


def _nontransparent_bbox(frame):
    return frame.split()[3].getbbox()


def test_easing_endpoints_and_monotonic():
    assert effects.ease_in_out_cubic(0) == 0
    assert effects.ease_in_out_cubic(1) == 1
    values = [effects.ease_in_out_cubic(t / 20) for t in range(21)]
    assert values == sorted(values)


def test_genie_starts_as_untouched_window():
    frame = effects.render_genie_frame(_img(), 0.0, SRC, TARGET, CANVAS)
    assert _nontransparent_bbox(frame) == SRC


def test_genie_collapses_toward_taskbar():
    early = effects.render_genie_frame(_img(), 0.35, SRC, TARGET, CANVAS)
    late = effects.render_genie_frame(_img(), 0.9, SRC, TARGET, CANVAS)
    eb, lb = _nontransparent_bbox(early), _nontransparent_bbox(late)
    # shrinks as it goes…
    assert (lb[2] - lb[0]) < (eb[2] - eb[0])
    assert (lb[3] - lb[1]) < (eb[3] - eb[1])
    # …and its centre travels toward the taskbar target
    ecx, ecy = (eb[0] + eb[2]) / 2, (eb[1] + eb[3]) / 2
    lcx, lcy = (lb[0] + lb[2]) / 2, (lb[1] + lb[3]) / 2
    assert abs(lcx - TARGET[0]) < abs(ecx - TARGET[0])
    assert abs(lcy - TARGET[1]) < abs(ecy - TARGET[1])


def test_genie_fully_sucked_down_at_t1():
    frame = effects.render_genie_frame(_img(), 1.0, SRC, TARGET, CANVAS)
    bbox = _nontransparent_bbox(frame)
    assert bbox is not None
    cx, cy = (bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2
    assert abs(cx - TARGET[0]) <= 40          # ends at the taskbar point…
    assert abs(cy - TARGET[1]) <= 130         # …(a thin funnel tip remains)
    assert (bbox[2] - bbox[0]) < 180          # much narrower than the 400px window


def test_scale_shrinks_and_fades_slightly():
    start = effects.render_scale_frame(_img(), 0.0, SRC, TARGET, CANVAS)
    mid = effects.render_scale_frame(_img(), 0.6, SRC, TARGET, CANVAS)
    sb, mb = _nontransparent_bbox(start), _nontransparent_bbox(mid)
    assert (mb[2] - mb[0]) < (sb[2] - sb[0]) * 0.6


def test_fade_ends_invisible():
    frame = effects.render_fade_frame(_img(), 1.0, SRC, TARGET, CANVAS)
    assert frame.split()[3].getextrema()[1] == 0


def test_render_frame_rejects_unknown_effect():
    try:
        effects.render_frame(_img(), "sparkle", 0.5, SRC, TARGET, CANVAS)
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError")


def test_frame_bbox_covers_window_and_target():
    bbox = effects.frame_bbox(SRC, TARGET, pad=10)
    assert bbox[0] <= SRC[0] and bbox[1] <= SRC[1]
    assert bbox[2] >= SRC[2] and bbox[3] >= TARGET[1]


def test_icon_and_demo_window_render():
    icon = make_icon_image(128)
    assert icon.size == (128, 128) and icon.mode == "RGBA"
    assert icon.split()[3].getextrema()[1] == 255  # has opaque pixels
