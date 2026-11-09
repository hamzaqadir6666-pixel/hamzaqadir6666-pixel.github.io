"""Thin ctypes wrappers around the Win32 / DWM APIs we need.

Everything here is Windows-only; callers check :func:`is_windows`
first.  No pywin32 dependency — ctypes + the standard library only.
"""
from __future__ import annotations

import ctypes
import sys
from ctypes import wintypes

IS_WINDOWS = sys.platform.startswith("win")


def is_windows() -> bool:
    return IS_WINDOWS


if IS_WINDOWS:
    user32 = ctypes.windll.user32
    gdi32 = ctypes.windll.gdi32
    dwmapi = ctypes.windll.dwmapi
    kernel32 = ctypes.windll.kernel32

    class RECT(ctypes.Structure):
        _fields_ = [("left", ctypes.c_long), ("top", ctypes.c_long),
                    ("right", ctypes.c_long), ("bottom", ctypes.c_long)]

        def as_tuple(self):
            return (self.left, self.top, self.right, self.bottom)

    class ANIMATIONINFO(ctypes.Structure):
        _fields_ = [("cbSize", wintypes.UINT), ("iMinAnimate", ctypes.c_int)]

    # Correct 64-bit handle return types (ctypes defaults to 32-bit int,
    # which can truncate HWND/HANDLE values on 64-bit Windows).
    user32.FindWindowW.restype = wintypes.HWND
    user32.GetForegroundWindow.restype = wintypes.HWND
    kernel32.CreateMutexW.restype = wintypes.HANDLE
    kernel32.GetModuleHandleW.restype = wintypes.HMODULE

    # --- window geometry ------------------------------------------------
    DWMWA_EXTENDED_FRAME_BOUNDS = 9

    def get_window_rect(hwnd: int):
        """Real on-screen bounds (excludes the invisible resize shadow)."""
        rect = RECT()
        hr = dwmapi.DwmGetWindowAttribute(
            wintypes.HWND(hwnd), DWMWA_EXTENDED_FRAME_BOUNDS,
            ctypes.byref(rect), ctypes.sizeof(rect))
        if hr != 0 or rect.right - rect.left <= 0:
            user32.GetWindowRect(wintypes.HWND(hwnd), ctypes.byref(rect))
        return rect.as_tuple()

    def get_class_name(hwnd: int) -> str:
        buf = ctypes.create_unicode_buffer(256)
        user32.GetClassNameW(wintypes.HWND(hwnd), buf, 256)
        return buf.value

    def get_window_title(hwnd: int) -> str:
        buf = ctypes.create_unicode_buffer(512)
        user32.GetWindowTextW(wintypes.HWND(hwnd), buf, 512)
        return buf.value

    def is_window_visible(hwnd: int) -> bool:
        return bool(user32.IsWindowVisible(wintypes.HWND(hwnd)))

    def is_iconic(hwnd: int) -> bool:
        return bool(user32.IsIconic(wintypes.HWND(hwnd)))

    GWL_EXSTYLE = -20
    WS_EX_TOOLWINDOW = 0x00000080
    WS_EX_LAYERED = 0x00080000

    def get_exstyle(hwnd: int) -> int:
        return user32.GetWindowLongW(wintypes.HWND(hwnd), GWL_EXSTYLE)

    def is_tool_window(hwnd: int) -> bool:
        return bool(get_exstyle(hwnd) & WS_EX_TOOLWINDOW)

    LWA_ALPHA = 0x00000002

    def set_window_alpha(hwnd: int, alpha: int) -> bool:
        """Make a window transparent (0-255), adding WS_EX_LAYERED."""
        ex = get_exstyle(hwnd)
        user32.SetWindowLongW(wintypes.HWND(hwnd), GWL_EXSTYLE, ex | WS_EX_LAYERED)
        return bool(user32.SetLayeredWindowAttributes(
            wintypes.HWND(hwnd), 0, max(0, min(255, alpha)), LWA_ALPHA))

    def restore_window_alpha(hwnd: int, original_exstyle: int) -> None:
        user32.SetLayeredWindowAttributes(wintypes.HWND(hwnd), 0, 255, LWA_ALPHA)
        user32.SetWindowLongW(wintypes.HWND(hwnd), GWL_EXSTYLE, original_exstyle)

    # --- taskbar ---------------------------------------------------------
    def get_taskbar_target(hwnd: int, src_rect) -> tuple:
        """Point on the taskbar the window should pour into.

        Windows has no public API for 'the rect of this window's
        taskbar button', so we aim at the taskbar edge closest to the
        window, clamped along the bar — visually this lands the genie
        right where the button sits.
        """
        screen_w = user32.GetSystemMetrics(0)
        screen_h = user32.GetSystemMetrics(1)
        cx = (src_rect[0] + src_rect[2]) // 2
        cy = (src_rect[1] + src_rect[3]) // 2
        tray = user32.FindWindowW("Shell_TrayWnd", None)
        if tray:
            r = RECT()
            user32.GetWindowRect(wintypes.HWND(tray), ctypes.byref(r))
            if r.bottom - r.top < r.right - r.left:      # horizontal bar
                if r.top > screen_h // 2:                # bottom taskbar
                    return (max(r.left + 90, min(r.right - 90, cx)), r.top)
                return (max(r.left + 90, min(r.right - 90, cx)), r.bottom)  # top
            if r.left > screen_w // 2:                   # right taskbar
                return (r.left, max(r.top + 90, min(r.bottom - 90, cy)))
            return (r.right, max(r.top + 90, min(r.bottom - 90, cy)))       # left
        return (cx, screen_h)  # fallback: bottom-centre of the window

    # --- Windows' own minimize animation --------------------------------
    SPI_GETANIMATION = 0x0048
    SPI_SETANIMATION = 0x0049
    SPIF_SENDCHANGE = 0x0002

    def get_native_animation_enabled() -> bool:
        info = ANIMATIONINFO(cbSize=ctypes.sizeof(ANIMATIONINFO))
        user32.SystemParametersInfoW(SPI_GETANIMATION, ctypes.sizeof(info),
                                     ctypes.byref(info), 0)
        return bool(info.iMinAnimate)

    def set_native_animation_enabled(enabled: bool) -> None:
        info = ANIMATIONINFO(cbSize=ctypes.sizeof(ANIMATIONINFO),
                             iMinAnimate=1 if enabled else 0)
        user32.SystemParametersInfoW(SPI_SETANIMATION, ctypes.sizeof(info),
                                     ctypes.byref(info), SPIF_SENDCHANGE)

    # --- single instance ---------------------------------------------------
    def acquire_single_instance_mutex(name: str = "MacWinAnimator_SingleInstance") -> bool:
        ERROR_ALREADY_EXISTS = 183
        kernel32.CreateMutexW(None, True, name)
        return kernel32.GetLastError() != ERROR_ALREADY_EXISTS

    def message_box(text: str, title: str = "MacWinAnimator") -> None:
        user32.MessageBoxW(None, text, title, 0x00000040)  # MB_ICONINFORMATION
