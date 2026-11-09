"""System-tray presence: the little icon that sits in the icons area
next to the Windows clock (bottom-right).  Right-click it for the
menu; double-click opens Settings.  Built on pystray.
"""
from __future__ import annotations

import logging
from pathlib import Path

from .config import EFFECT_LABELS
from .icon import make_icon_image

log = logging.getLogger("macwin.tray")


def _load_icon_image():
    """Prefer the committed assets/icon.png, fall back to drawing it."""
    here = Path(__file__).resolve().parent.parent
    for candidate in (here / "assets" / "icon.png",):
        if candidate.exists():
            from PIL import Image
            return Image.open(candidate).convert("RGBA")
    return make_icon_image(128)


class TrayApp:
    """``controller`` must provide:
    get_config(), open_settings(), set_enabled(bool), set_effect(name),
    toggle_autostart(bool), test_animation(), quit()
    """

    def __init__(self, controller):
        self.controller = controller
        self._icon = None

    def run(self) -> None:
        """Blocking — call on the main thread."""
        import pystray

        cfg = self.controller.get_config()
        menu = pystray.Menu(
            pystray.MenuItem("Settings…", lambda *_: self.controller.open_settings(), default=True),
            pystray.MenuItem("Test animation", lambda *_: self.controller.test_animation()),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Enabled", lambda *_: self._toggle_enabled(),
                             checked=lambda _i: self.controller.get_config().enabled),
            pystray.MenuItem("Effect", pystray.Menu(
                *[
                    pystray.MenuItem(
                        label,
                        (lambda name: lambda *_: self.controller.set_effect(name))(name),
                        checked=(lambda name: lambda _i: self.controller.get_config().effect == name)(name),
                        radio=True,
                    )
                    for name, label in EFFECT_LABELS.items()
                ]
            )),
            pystray.MenuItem("Start with Windows", lambda *_: self._toggle_autostart(),
                             checked=lambda _i: self.controller.get_config().start_with_windows),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Quit MacWinAnimator", lambda *_: self.controller.quit()),
        )
        self._icon = pystray.Icon(
            "MacWinAnimator", _load_icon_image(),
            "MacWinAnimator — macOS window animations", menu)
        log.info("tray icon running (look next to the clock, bottom-right)")
        self._icon.run()

    def _toggle_enabled(self):
        cfg = self.controller.get_config()
        self.controller.set_enabled(not cfg.enabled)
        self.refresh()

    def _toggle_autostart(self):
        cfg = self.controller.get_config()
        self.controller.set_autostart(not cfg.start_with_windows)
        self.refresh()

    def refresh(self) -> None:
        if self._icon is not None:
            try:
                self._icon.update_menu()
            except Exception:
                pass

    def stop(self) -> None:
        if self._icon is not None:
            try:
                self._icon.stop()
            except Exception:
                pass
            self._icon = None
