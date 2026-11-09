"""Windows-only smoke test (runs in CI on windows-latest).

Reproduces the EXE's exact import graph on a real Windows Python so
import-time crashes in the Win32 layer (like the v1.0.0 HCURSOR bug)
fail the build instead of reaching users.  Skipped everywhere else.
"""
import sys

import pytest

pytestmark = pytest.mark.skipif(
    not sys.platform.startswith("win"), reason="Windows-only smoke test")


def test_win32_modules_import_cleanly():
    import macwin.animator  # noqa: F401  (imports overlay + capture)
    import macwin.capture  # noqa: F401
    import macwin.hook  # noqa: F401
    import macwin.overlay  # noqa: F401
    import macwin.tray  # noqa: F401
    import macwin.winapi  # noqa: F401
    assert macwin.winapi.IS_WINDOWS


def test_overlay_structs_are_well_formed():
    from macwin import overlay
    # constructing the structs proves every _fields_ entry resolved
    overlay.WNDCLASS()
    overlay.BLENDFUNCTION()
    overlay.BITMAPINFO()


def test_hook_callback_type_exists():
    from macwin import hook
    assert hook.WINEVENTPROC is not None


def test_windowplacement_struct_is_well_formed():
    from macwin import winapi
    wp = winapi.WINDOWPLACEMENT()
    wp.length = __import__("ctypes").sizeof(winapi.WINDOWPLACEMENT)
    assert wp.rcNormalPosition.right == 0


def test_overlay_prototypes_declared():
    from macwin import overlay
    # declared argtypes are what keep 64-bit/unsigned values correct
    assert overlay.user32.CreateWindowExW.argtypes is not None
    assert overlay.user32.UpdateLayeredWindow.argtypes is not None
    assert overlay.user32.UpdateLayeredWindow.restype is not None


def test_overlay_class_has_pump_messages():
    """The v1.1.0 EXE crashed the self-test on exactly this."""
    from macwin.overlay import LayeredOverlay
    assert callable(getattr(LayeredOverlay, "pump_messages", None))
    assert callable(getattr(LayeredOverlay, "show_frame", None))


def test_capture_of_desktop_window():
    """End-to-end on the Windows runner: screenshot the desktop shell
    window (always present) and require real pixels back."""
    from macwin import capture, winapi
    hwnd = winapi.user32.GetDesktopWindow()
    image, error = capture.capture_window_detailed(int(hwnd))
    assert image is not None, f"desktop capture failed: {error}"
    assert image.size[0] > 100 and image.size[1] > 100
