"""MacWinAnimator — macOS-style window animations for Windows.

Runs silently in the Windows system tray (the icons area next to the
clock) and replaces the plain Windows minimize/restore animation with
the classic macOS effects:

* **Genie**  — the window squeezes and pours into the taskbar
* **Scale**  — the window shrinks smoothly into the taskbar
* **Fade**   — the window fades and slides away

Only :mod:`macwin.effects` and :mod:`macwin.config` are platform
independent (and unit-tested).  Everything that talks to Win32 is
guarded so the package can still be imported on other systems for
development and testing.
"""

__version__ = "1.0.1"
__all__ = ["__version__"]
