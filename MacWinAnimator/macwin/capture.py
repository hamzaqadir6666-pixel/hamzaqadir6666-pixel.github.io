"""Screenshot a single window with PrintWindow (works even for
hardware-accelerated / UWP windows thanks to PW_RENDERFULLCONTENT),
falling back to a screen BitBlt.

``capture_window`` returns a Pillow RGBA image or None.
``capture_window_detailed`` also returns *why* it failed, which the
self-test surfaces to the user instead of failing silently.
"""
from __future__ import annotations

import ctypes
import logging
from ctypes import wintypes

from . import winapi

log = logging.getLogger("macwin.capture")

PW_RENDERFULLCONTENT = 0x00000002
SRCCOPY = 0x00CC0020
DIB_RGB_COLORS = 0


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [("biSize", wintypes.DWORD), ("biWidth", ctypes.c_long),
                ("biHeight", ctypes.c_long), ("biPlanes", wintypes.WORD),
                ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", ctypes.c_long),
                ("biYPelsPerMeter", ctypes.c_long), ("biClrUsed", wintypes.DWORD),
                ("biClrImportant", wintypes.DWORD)]


if winapi.IS_WINDOWS:
    winapi.user32.GetWindowDC.restype = wintypes.HDC
    winapi.user32.GetWindowDC.argtypes = [wintypes.HWND]
    winapi.user32.GetDC.restype = wintypes.HDC
    winapi.user32.GetDC.argtypes = [wintypes.HWND]
    winapi.user32.PrintWindow.argtypes = [wintypes.HWND, wintypes.HDC, wintypes.UINT]
    winapi.user32.PrintWindow.restype = wintypes.BOOL
    winapi.gdi32.CreateCompatibleDC.restype = wintypes.HDC
    winapi.gdi32.CreateCompatibleDC.argtypes = [wintypes.HDC]
    winapi.gdi32.CreateCompatibleBitmap.restype = wintypes.HBITMAP
    winapi.gdi32.CreateCompatibleBitmap.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int]
    winapi.gdi32.BitBlt.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int,
                                    ctypes.c_int, ctypes.c_int, wintypes.HDC,
                                    ctypes.c_int, ctypes.c_int, wintypes.DWORD]
    winapi.gdi32.BitBlt.restype = wintypes.BOOL
    winapi.gdi32.GetDIBits.argtypes = [wintypes.HDC, wintypes.HBITMAP, wintypes.UINT,
                                       wintypes.UINT, wintypes.LPVOID,
                                       ctypes.POINTER(BITMAPINFOHEADER), wintypes.UINT]
    winapi.gdi32.GetDIBits.restype = ctypes.c_int


def capture_window(hwnd: int, rect_override=None):
    image, _error = capture_window_detailed(hwnd, rect_override)
    return image


def capture_window_detailed(hwnd: int, rect_override=None):
    """Returns ``(image, None)`` or ``(None, reason)``.

    ``rect_override`` supplies geometry for minimized windows whose
    live rect is the off-screen parking spot (see winapi.get_normal_rect).
    """
    if not winapi.IS_WINDOWS:
        return None, "not running on Windows"
    user32, gdi32 = winapi.user32, winapi.gdi32
    left, top, right, bottom = rect_override or winapi.get_window_rect(hwnd)
    width, height = right - left, bottom - top
    if width <= 10 or height <= 10:
        return None, f"window too small to capture ({width}x{height})"

    hwnd_dc = user32.GetWindowDC(wintypes.HWND(hwnd))
    if not hwnd_dc:
        return None, f"GetWindowDC failed, err={ctypes.get_last_error()}"
    mem_dc = gdi32.CreateCompatibleDC(hwnd_dc)
    bitmap = gdi32.CreateCompatibleBitmap(hwnd_dc, width, height)
    if not mem_dc or not bitmap:
        err = ctypes.get_last_error()
        if mem_dc:
            gdi32.DeleteDC(mem_dc)
        user32.ReleaseDC(wintypes.HWND(hwnd), hwnd_dc)
        return None, f"CreateCompatibleDC/Bitmap failed, err={err}"
    old = gdi32.SelectObject(mem_dc, bitmap)
    try:
        ok = user32.PrintWindow(wintypes.HWND(hwnd), mem_dc, PW_RENDERFULLCONTENT)
        if not ok and not winapi.is_iconic(hwnd):
            # fallback: copy what's on screen (skipped for minimized
            # windows — they'd copy whatever sits at their old spot)
            screen_dc = user32.GetDC(None)
            try:
                gdi32.BitBlt(mem_dc, 0, 0, width, height, screen_dc, left, top, SRCCOPY)
            finally:
                user32.ReleaseDC(None, screen_dc)

        bmi = BITMAPINFOHEADER()
        bmi.biSize = ctypes.sizeof(BITMAPINFOHEADER)
        bmi.biWidth, bmi.biHeight = width, -height  # top-down
        bmi.biPlanes, bmi.biBitCount, bmi.biCompression = 1, 32, 0
        buf = ctypes.create_string_buffer(width * height * 4)
        got = gdi32.GetDIBits(mem_dc, bitmap, 0, height, buf,
                              ctypes.byref(bmi), DIB_RGB_COLORS)
        if not got:
            return None, (f"GetDIBits failed, err={ctypes.get_last_error()} "
                          f"(PrintWindow={'ok' if ok else 'failed'})")
        from PIL import Image
        img = Image.frombuffer("RGBA", (width, height), buf, "raw", "BGRA", 0, 1).copy()
        # PrintWindow leaves alpha=0 on most windows -> force opaque
        if img.split()[3].getextrema()[1] == 0:
            img.putalpha(255)
        return img, None
    except Exception as exc:
        log.exception("capture failed for hwnd=%s", hwnd)
        return None, f"{type(exc).__name__}: {exc}"
    finally:
        gdi32.SelectObject(mem_dc, old)
        gdi32.DeleteObject(bitmap)
        gdi32.DeleteDC(mem_dc)
        user32.ReleaseDC(wintypes.HWND(hwnd), hwnd_dc)
