"""Turns minimize/restore events into overlay animations.

Key design rule (learned the hard way in v1.0.x): the screenshot of
the window must be taken **synchronously inside the event callback**,
before the window finishes minimizing.  Spawning a thread first loses
the race — Windows (especially with its own animation disabled, as we
configure it) minimizes instantly, the worker then sees an already
iconic window, and silently gives up.  That was the "app opens but
nothing ever animates" bug.

Flow:
* minimize — event arrives, we grab rect + screenshot immediately,
  then a worker thread plays the effect on a click-through overlay
  while the real window minimizes underneath.
* restore — the real window is briefly made transparent while the
  effect plays in reverse (screenshot cached at minimize time, or a
  fresh capture), then the real window is revealed.

Every decision (event seen, capture ok/failed, animation played or
skipped and why) is written to the log — see tray -> "Open log file".
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
        self._animating: set[tuple] = set()      # (hwnd, kind)
        self._recent: dict[tuple, float] = {}    # (hwnd, kind) -> last start
        self._lock = threading.Lock()

    # -- event entry points (called from hook / poll threads) --------------
    def handle_minimize(self, hwnd: int) -> None:
        cfg = self._get_config()
        if not cfg.enabled:
            return
        if not self._claim(hwnd, "min"):
            log.debug("minimize %s: duplicate, ignored", hwnd)
            return
        # Synchronous snapshot — the window may vanish at any moment.
        snap = self._snapshot(hwnd, cfg, want_capture=True)
        if snap is None:
            self._release(hwnd, "min")
            return
        image, rect = snap
        self._cache[hwnd] = (image, rect)
        target = winapi.get_taskbar_target(hwnd, rect)
        log.info("minimize %s (%r): animating -> taskbar %s",
                 hwnd, _title(hwnd), target)
        threading.Thread(target=self._play_and_release,
                         args=(hwnd, "min", image, rect, target, cfg, False),
                         name=f"macwin-min-{hwnd}", daemon=True).start()

    def handle_restore(self, hwnd: int) -> None:
        cfg = self._get_config()
        if not cfg.enabled or not cfg.animate_restore:
            return
        if not self._claim(hwnd, "res"):
            log.debug("restore %s: duplicate, ignored", hwnd)
            return
        snap = self._snapshot(hwnd, cfg, want_capture=False)
        if snap is None:
            self._release(hwnd, "res")
            return
        _, rect = snap
        cached = self._cache.pop(hwnd, None)
        image = cached[0] if cached else capture.capture_window(hwnd)
        if image is None:
            log.info("restore %s: no screenshot available, skipping", hwnd)
            self._release(hwnd, "res")
            return
        target = winapi.get_taskbar_target(hwnd, rect)
        log.info("restore %s (%r): animating from taskbar %s",
                 hwnd, _title(hwnd), target)
        threading.Thread(target=self._restore_thread,
                         args=(hwnd, image, rect, target, cfg),
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

    def run_self_test(self) -> None:
        """Tray 'Run self-test': checks capture + overlay visibly and
        reports the result in a message box (and the log)."""
        threading.Thread(target=self._self_test_thread,
                         name="macwin-selftest", daemon=True).start()

    # -- snapshot ------------------------------------------------------------
    def _snapshot(self, hwnd: int, cfg, want_capture: bool):
        """(image, rect) or None. Runs on the caller's thread."""
        if not (winapi.is_window_visible(hwnd) or winapi.is_iconic(hwnd)):
            log.info("event %s: window not visible, skipping", hwnd)
            return None
        cls = winapi.get_class_name(hwnd)
        if cls in cfg.excluded_classes:
            log.info("event %s: excluded window class %r, skipping", hwnd, cls)
            return None
        if winapi.is_tool_window(hwnd):
            log.info("event %s: tool window, skipping", hwnd)
            return None
        iconic = winapi.is_iconic(hwnd)
        # A minimized window lives at (-32000,-32000); its real geometry
        # is in the window placement.
        rect = (winapi.get_normal_rect(hwnd) if iconic
                else winapi.get_window_rect(hwnd))
        if rect[2] - rect[0] < 80 or rect[3] - rect[1] < 60:
            log.info("event %s: window too small %s, skipping", hwnd, rect)
            return None
        if not want_capture:
            return (None, rect)
        image = capture.capture_window(
            hwnd, rect_override=rect if iconic else None)
        if image is None:
            log.info("event %s (%r): could not screenshot window "
                     "(iconic=%s), skipping animation",
                     hwnd, _title(hwnd), iconic)
            return None
        return (image, rect)

    # -- worker threads ---------------------------------------------------------
    def _restore_thread(self, hwnd, image, rect, target, cfg) -> None:
        original_exstyle = None
        hidden = False
        try:
            original_exstyle = winapi.get_exstyle(hwnd)
            hidden = winapi.set_window_alpha(hwnd, 0)
            try:
                self._play(image, rect, target, cfg, reverse=True)
            finally:
                if hidden:
                    winapi.restore_window_alpha(hwnd, original_exstyle)
        except Exception:
            log.exception("restore animation failed for %s", hwnd)
            if hidden and original_exstyle is not None:
                try:
                    winapi.restore_window_alpha(hwnd, original_exstyle)
                except Exception:
                    pass
        finally:
            self._release(hwnd, "res")

    def _play_and_release(self, hwnd, kind, image, rect, target, cfg, reverse):
        try:
            self._play(image, rect, target, cfg, reverse=reverse)
        except Exception:
            log.exception("%s animation failed for %s", kind, hwnd)
        finally:
            self._release(hwnd, kind)

    def _test_thread(self, hwnd: int) -> None:
        cfg = self._get_config()
        rect = winapi.get_window_rect(hwnd)
        if rect[2] - rect[0] < 80:
            log.info("test: foreground window too small")
            return
        image = capture.capture_window(hwnd)
        if image is None:
            log.info("test: could not screenshot foreground window %s", hwnd)
            return
        target = winapi.get_taskbar_target(hwnd, rect)
        try:
            self._play(image, rect, target, cfg, reverse=False)
            time.sleep(0.12)
            self._play(image, rect, target, cfg, reverse=True)
        except Exception:
            log.exception("test animation failed")

    def _self_test_thread(self) -> None:
        lines = ["MacWinAnimator self-test", ""]
        # 1) capture
        try:
            fg = winapi.user32.GetForegroundWindow()
            img = capture.capture_window(int(fg)) if fg else None
            lines.append(f"[{'OK' if img else 'FAIL'}] Screenshot a window "
                         f"(foreground hwnd={fg})")
        except Exception as exc:
            img = None
            lines.append(f"[FAIL] Screenshot a window — {exc!r}")
        # 2) overlay: a solid teal rectangle in the middle of the screen
        try:
            from PIL import Image
            sw = winapi.user32.GetSystemMetrics(0)
            sh = winapi.user32.GetSystemMetrics(1)
            bbox = (sw // 2 - 260, sh // 2 - 150, sw // 2 + 260, sh // 2 + 150)
            frame = Image.new("RGBA", (520, 300), (45, 212, 191, 255))
            with LayeredOverlay(bbox) as overlay:
                overlay.show_frame(frame)
                deadline = time.perf_counter() + 1.4
                while time.perf_counter() < deadline:
                    overlay.pump_messages()
                    time.sleep(0.02)
            lines.append("[OK] Show overlay window (you should have seen "
                         "a teal rectangle)")
        except Exception as exc:
            lines.append(f"[FAIL] Show overlay window — {exc!r}")
            log.exception("self-test overlay failed")
        lines += ["", "If capture is OK but animations don't play, check "
                      "that 'Enabled' is on in the tray menu, then see the "
                      "log for each minimize event."]
        winapi.message_box("\n".join(lines), "MacWinAnimator self-test")
        log.info("self-test done:\n%s", "\n".join(lines))

    # -- claim / dedupe ---------------------------------------------------------
    def _claim(self, hwnd: int, kind: str) -> bool:
        with self._lock:
            key = (hwnd, kind)
            now = time.monotonic()
            if key in self._animating or now - self._recent.get(key, 0) < _DEDUPE_SECONDS:
                return False
            self._recent[key] = now
            self._animating.add(key)
            return True

    def _release(self, hwnd: int, kind: str) -> None:
        with self._lock:
            self._animating.discard((hwnd, kind))

    # -- the frame loop -----------------------------------------------------------
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
                overlay.pump_messages()
                spent = time.perf_counter() - start
                expected = (int(raw / frame_time) + 1) * frame_time
                if expected > spent:
                    time.sleep(expected - spent)
            overlay.show_frame(effects.render_frame(
                image, cfg.effect, 0.0 if reverse else 1.0,
                rel_rect, rel_target, size))


def _title(hwnd: int) -> str:
    try:
        return winapi.get_window_title(hwnd)[:60]
    except Exception:
        return ""
