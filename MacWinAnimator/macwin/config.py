"""Persistent configuration for MacWinAnimator.

Settings live in ``%APPDATA%\\MacWinAnimator\\config.json`` on Windows
(override with the ``MACWIN_CONFIG_DIR`` environment variable — handy
for tests and portable runs).
"""
from __future__ import annotations

import json
import os
from dataclasses import asdict, dataclass, field
from pathlib import Path

EFFECTS = ("genie", "scale", "fade")

EFFECT_LABELS = {
    "genie": "Genie (macOS classic)",
    "scale": "Scale",
    "fade": "Fade & slide",
}


def config_dir() -> Path:
    override = os.environ.get("MACWIN_CONFIG_DIR")
    if override:
        return Path(override)
    appdata = os.environ.get("APPDATA")
    if appdata:
        return Path(appdata) / "MacWinAnimator"
    return Path.home() / ".macwinanimator"


def config_path() -> Path:
    return config_dir() / "config.json"


@dataclass
class Config:
    enabled: bool = True
    effect: str = "genie"            # one of EFFECTS
    duration_ms: int = 480           # animation length
    fps: int = 60                    # overlay redraw rate
    animate_restore: bool = True     # also animate windows coming back
    start_with_windows: bool = False
    disable_native_animation: bool = True  # turn off Windows' own min/max animation while we run
    excluded_classes: list = field(default_factory=lambda: [
        "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Progman", "WorkerW",
        "MacWinAnimatorOverlay", "Windows.UI.Core.CoreWindow",
    ])

    # -- validation -----------------------------------------------------
    def normalized(self) -> "Config":
        if self.effect not in EFFECTS:
            self.effect = "genie"
        self.duration_ms = max(120, min(1500, int(self.duration_ms)))
        self.fps = max(24, min(120, int(self.fps)))
        return self

    # -- persistence ----------------------------------------------------
    @classmethod
    def load(cls, path: Path | None = None) -> "Config":
        path = path or config_path()
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            known = {f for f in cls.__dataclass_fields__}
            cfg = cls(**{k: v for k, v in data.items() if k in known})
        except Exception:
            cfg = cls()
        return cfg.normalized()

    def save(self, path: Path | None = None) -> Path:
        path = path or config_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(asdict(self), indent=2), encoding="utf-8")
        return path
