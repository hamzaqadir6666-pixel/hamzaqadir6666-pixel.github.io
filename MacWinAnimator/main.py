#!/usr/bin/env python3
"""MacWinAnimator — macOS-style window animations for Windows.

Run it and it disappears into the system tray (the icons area next to
the clock, bottom-right of the taskbar).  From then on, every window
you minimize pours into the taskbar with the macOS Genie effect —
and grows back out of it when restored.

Usage:
    python main.py                tray + open Settings once
    python main.py --background   tray only (used by autostart)
    python main.py --settings     tray + open Settings
    MacWinAnimator.exe            same, once built with build.bat
"""
from __future__ import annotations

import argparse
import logging
import logging.handlers
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from macwin import __version__, autostart, winapi  # noqa: E402
from macwin.animator import Animator  # noqa: E402
from macwin.config import Config, config_dir  # noqa: E402
from macwin.settings_window import SettingsWindow  # noqa: E402
from macwin.tray import TrayApp  # noqa: E402

log = logging.getLogger("macwin")


def _setup_logging() -> None:
    fmt = logging.Formatter("%(asctime)s %(levelname)-7s %(name)s: %(message)s")
    console = logging.StreamHandler()
    console.setFormatter(fmt)
    handlers: list[logging.Handler] = [console]
    try:
        logfile = config_dir() / "macwinanimator.log"
        logfile.parent.mkdir(parents=True, exist_ok=True)
        file_handler = logging.handlers.RotatingFileHandler(
            logfile, maxBytes=512_000, backupCount=2, encoding="utf-8")
        file_handler.setFormatter(fmt)
        handlers.append(file_handler)
    except Exception:
        pass
    logging.basicConfig(level=logging.INFO, handlers=handlers)


class AppController:
    """Owns config + animator + hook + tray + settings; the tray and
    Settings window talk to the app only through this object."""

    def __init__(self):
        self.config = Config.load()
        self.animator = Animator(self.get_config)
        self.settings = SettingsWindow(self)
        self.tray = TrayApp(self)
        self._hook = None
        self._native_anim_was: bool | None = None
        self._quitting = False

    # -- config access ---------------------------------------------------
    def get_config(self) -> Config:
        return self.config

    def _save(self) -> None:
        self.config.save()

    def set_enabled(self, enabled: bool) -> None:
        self.config.enabled = bool(enabled)
        self._save()

    def set_effect(self, effect: str) -> None:
        self.config.effect = effect
        self.config.normalized()
        self._save()
        self.refresh_tray()

    def set_autostart(self, enabled: bool) -> None:
        self.config.start_with_windows = bool(enabled)
        autostart.set_enabled(bool(enabled))
        self._save()

    def apply_settings(self, *, enabled, effect, duration_ms, animate_restore,
                       start_with_windows, disable_native_animation) -> None:
        was_autostart = self.config.start_with_windows
        was_native_off = self.config.disable_native_animation
        self.config.enabled = enabled
        self.config.effect = effect
        self.config.duration_ms = duration_ms
        self.config.animate_restore = animate_restore
        self.config.start_with_windows = start_with_windows
        self.config.disable_native_animation = disable_native_animation
        self.config.normalized()
        self._save()
        if start_with_windows != was_autostart:
            autostart.set_enabled(start_with_windows)
        if disable_native_animation != was_native_off:
            self._sync_native_animation()

    # -- actions -----------------------------------------------------------
    def open_settings(self) -> None:
        self.settings.show()

    def test_animation(self) -> None:
        self.animator.test_animation()

    def refresh_tray(self) -> None:
        self.tray.refresh()

    # -- lifecycle -----------------------------------------------------------
    def _sync_native_animation(self) -> None:
        """Optionally switch off Windows' own minimize animation so it
        doesn't play at the same time as ours; remember the user's
        original setting and restore it on quit."""
        if not winapi.IS_WINDOWS:
            return
        try:
            if self.config.disable_native_animation:
                if self._native_anim_was is None:
                    self._native_anim_was = winapi.get_native_animation_enabled()
                winapi.set_native_animation_enabled(False)
            elif self._native_anim_was is not None:
                winapi.set_native_animation_enabled(self._native_anim_was)
                self._native_anim_was = None
        except Exception:
            log.exception("could not sync native animation setting")

    def start(self, open_settings: bool) -> None:
        from macwin.hook import WindowEventHook
        self._sync_native_animation()
        # keep the registry honest if the user deleted the value by hand
        if self.config.start_with_windows and not autostart.is_enabled():
            autostart.set_enabled(True)
        self._hook = WindowEventHook(self.animator.handle_minimize,
                                     self.animator.handle_restore)
        self._hook.start()
        log.info("MacWinAnimator %s started (effect=%s, %d ms)",
                 __version__, self.config.effect, self.config.duration_ms)
        if open_settings:
            self.settings.show()
        self.tray.run()  # blocks on the main thread until Quit

    def quit(self) -> None:
        if self._quitting:
            return
        self._quitting = True
        log.info("quitting — restoring Windows settings")
        try:
            if self._native_anim_was is not None:
                winapi.set_native_animation_enabled(self._native_anim_was)
                self._native_anim_was = None
        except Exception:
            pass
        try:
            if self._hook:
                self._hook.stop()
        except Exception:
            pass
        try:
            self.settings.close()
        except Exception:
            pass
        self.tray.stop()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="MacWinAnimator",
                                     description="macOS-style window animations for Windows")
    parser.add_argument("--background", action="store_true",
                        help="start tray-only, no Settings window (used by autostart)")
    parser.add_argument("--settings", action="store_true", help="open Settings on start")
    parser.add_argument("--version", action="version", version=f"MacWinAnimator {__version__}")
    args = parser.parse_args(argv)

    _setup_logging()

    if not winapi.IS_WINDOWS:
        print("MacWinAnimator only runs on Windows 10/11.\n"
              "(The animation engine can be previewed anywhere: "
              "see assets/preview.gif)")
        return 1

    if not winapi.acquire_single_instance_mutex():
        if not args.background:
            winapi.message_box("MacWinAnimator is already running.\n\n"
                               "Look for its icon in the tray area next to the clock "
                               "(bottom-right — you may need to click the ^ arrow).")
        return 0

    app = AppController()
    try:
        app.start(open_settings=args.settings or not args.background)
    except KeyboardInterrupt:
        app.quit()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
