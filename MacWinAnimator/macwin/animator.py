"""Turns minimize/restore events into overlay animations.

Minimize flow (EVENT_SYSTEM_MINIMIZESTART arrives *before* the window
disappears): screenshot the window, let Windows minimize the real
window underneath, and play the effect on a click-through overlay
that pours the screenshot into the taskbar.

Restore flow: the window is already back, so we briefly make the real
window transparent, play the effect in reverse (window grows out of
the taskbar using the screenshot cached at minimize-time), then fade
the real window back in.  Net result: it looks like the window itself
is doing the macOS animation.
"""
from __future__ import annotations

import logging
import threading
import time

from . import capture, effects, winapi
from .overlay import LayeredOverlay

log = logging.getLogger("macwin.animator")

_DEDUPE_SECONDS = 0.9


class Animator:
    def __init__(self, get_config):
        """``get_config`` is a callable returning the live Config."""
        self._get_config = get_config
        self._cache: dict[int, tuple] = {}       # hwnd -> (image, rect)
        self._animating: set[int] = set()
        self._recent: dict[int, float] = {}      # hwnd -> last anim start
        self._lock = threading.Lock()

    # -- event entry points ---------------------------------------------
    def handle_minimize(self, hwnd: int) -> None:
        cfg = self._get_config()
        if not cfg.enabled or not self._claim(hwnd):
            return
        threading.Thread(target=self._minimize_thread, args=(hwnd,),
                         name=f"macwin-min-{hwnd}", daemon=True).start()

    def handle_restore(self, hwnd: int) -> None:
        cfg = self._get_config()
        if not cfg.enabled or not cfg.animate_restore or not self._claim(hwnd):
            return
        threading.Thread(target=self._restore_thread, args=(hwnd,),
                         name=f"macwin-res-{hwnd}", daemon=True).start()

    def test_animation(self, hwnd: int | None = None) -> None:
        """Preview the current effect on the foreground window without
        actually minimizing it (used by Settings / tray 'Test')."""
        if not winapi.IS_WINDOWS:
            return
        hwnd = hwnd or winapi.user32.GetForegroundWindow()
        if not hwnd:
            return
        threading.Thread(target=self._test_thread, args=(int(hwnd),),
                         name="macwin-test", daemon=True).start()

    # -- internals ---------------------------------------------------------
    def _claim(self, hwnd: int) -> bool:
        with self._lock:
            now = time.monotonic()
            if hwnd in self._animating or now - self._recent.get(hwnd, 0) < _DEDUPE_SECONDS:
                return False
            self._recent[hwnd] = now
            self._animating.add(hwnd)
            return True

    def _release(self, hwnd: int) -> None:
        with self._lock:
            self._animating.discard(hwnd)

    def _acceptable(self, hwnd: int, cfg) -> bool:
        if not winapi.is_window_visible(hwnd) and not winapi.is_iconic(hwnd):
            return False
        rect = winapi.get_window_rect(hwnd)
        if rect[2] - rect[0] < 80 or rect[3] - rect[1] < 60:
            return False
        if winapi.get_class_name(hwnd) in cfg.excluded_classes:
            return False
        if winapi.is_tool_window(hwnd):
            return False
        return True

    def _minimize_thread(self, hwnd: int) -> None:
        try:
            cfg = self._get_config()
            if winapi.is_iconic(hwnd) or not self._acceptable(hwnd, cfg):
                return
            rect = winapi.get_window_rect(hwnd)
            image = capture.capture_window(hwnd)
            if image is None:
                return
            self._cache[hwnd] = (image, rect)
            target = winapi.get_taskbar_target(hwnd, rect)
            self._play(image, rect, target, cfg, reverse=False)
        except Exception:
            log.exception("minimize animation failed")
        finally:
            self._release(hwnd)

    def _restore_thread(self, hwnd: int) -> None:
        original_exstyle = None
        hidden = False
        try:
            cfg = self._get_config()
            if winapi.is_iconic(hwnd) or not self._acceptable(hwnd, cfg):
                return
            rect = winapi.get_window_rect(hwnd)
            cached = self._cache.pop(hwnd, None)
            image = cached[0] if cached else capture.capture_window(hwnd)
            if image is None:
                return
            target = winapi.get_taskbar_target(hwnd, rect)
            # Hide the real window while its 'ghost' grows out of the taskbar
            original_exstyle = winapi.get_exstyle(hwnd)
            hidden = winapi.set_window_alpha(hwnd, 0)
            try:
                self._play(image, rect, target, cfg, reverse=True)
            finally:
                if hidden:
                    winapi.restore_window_alpha(hwnd, original_exstyle)
        except Exception:
            log.exception("restore animation failed")
            if hidden and original_exstyle is not None:
                try:
                    winapi.restore_window_alpha(hwnd, original_exstyle)
                except Exception:
                    pass
        finally:
            self._release(hwnd)

    def _test_thread(self, hwnd: int) -> None:
        cfg = self._get_config()
        rect = winapi.get_window_rect(hwnd)
        if rect[2] - rect[0] < 80:
            return
        image = capture.capture_window(hwnd)
        if image is None:
            return
        target = winapi.get_taskbar_target(hwnd, rect)
        self._play(image, rect, target, cfg, reverse=False)
        time.sleep(0.12)
        self._play(image, rect, target, cfg, reverse=True)

    # -- the frame loop -----------------------------------------------------
    def _play(self, image, src_rect, target, cfg, reverse: bool) -> None:
        bbox = effects.frame_bbox(src_rect, target)
        rel_rect = (src_rect[0] - bbox[0], src_rect[1] - bbox[1],
                    src_rect[2] - bbox[0], src_rect[3] - bbox[1])
        rel_target = (target[0] - bbox[0], target[1] - bbox[1])
        size = (bbox[2] - bbox[0], bbox[3] - bbox[1])
        duration = cfg.duration_ms / 1000.0
        frame_time = 1.0 / max(24, cfg.fps)
        with LayeredOverlay(bbox) as overlay:
            start = time.perf_counter()
            while True:
                raw = (time.perf_counter() - start) / duration
                if raw >= 1.0:
                    break
                eased = effects.ease_in_out_cubic(raw)
                progress = 1.0 - eased if reverse else eased
                frame = effects.render_frame(image, cfg.effect, progress,
                                             rel_rect, rel_target, size)
                overlay.show_frame(frame)
                spent = time.perf_counter() - start
                expected = (int(raw / frame_time) + 1) * frame_time
                if expected > spent:
                    time.sleep(expected - spent)
            # final frame
            end_progress = 0.0 if reverse else 1.0
            overlay.show_frame(effects.render_frame(
                image, cfg.effect, end_progress, rel_rect, rel_target, size))
