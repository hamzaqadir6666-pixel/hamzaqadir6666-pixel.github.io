"""Screenshot a single window with PrintWindow (works even for
hardware-accelerated / UWP windows thanks to PW_RENDERFULLCONTENT),
falling back to a screen BitBlt.  Returns a Pillow RGBA image or None.
"""
from __future__ import annotations

import ctypes
import logging
from ctypes import wintypes

from . import winapi

log = logging.getLogger("macwin.capture")

PW_RENDERFULLCONTENT = 0x00000002
SRCCOPY = 0x00CC0020

if winapi.IS_WINDOWS:
    from ctypes import wintypes as _wt
    winapi.user32.GetWindowDC.restype = _wt.HDC
    winapi.user32.GetDC.restype = _wt.HDC
    winapi.gdi32.CreateCompatibleDC.restype = _wt.HDC
    winapi.gdi32.CreateCompatibleBitmap.restype = _wt.HBITMAP


def capture_window(hwnd: int, rect_override=None):
    """``rect_override`` supplies geometry for minimized windows whose
    live rect is the off-screen parking spot (see winapi.get_normal_rect)."""
    if not winapi.IS_WINDOWS:
        return None
    user32, gdi32 = winapi.user32, winapi.gdi32
    left, top, right, bottom = rect_override or winapi.get_window_rect(hwnd)
    width, height = right - left, bottom - top
    if width <= 10 or height <= 10:
        log.info("capture %s: bad size %sx%s", hwnd, width, height)
        return None

    hwnd_dc = user32.GetWindowDC(wintypes.HWND(hwnd))
    if not hwnd_dc:
        return None
    mem_dc = gdi32.CreateCompatibleDC(hwnd_dc)
    bitmap = gdi32.CreateCompatibleBitmap(hwnd_dc, width, height)
    old = gdi32.SelectObject(mem_dc, bitmap)
    try:
        ok = user32.PrintWindow(wintypes.HWND(hwnd), mem_dc, PW_RENDERFULLCONTENT)
        if not ok:  # fallback: copy what's on screen
            screen_dc = user32.GetDC(None)
            try:
                gdi32.BitBlt(mem_dc, 0, 0, width, height, screen_dc, left, top, SRCCOPY)
            finally:
                user32.ReleaseDC(None, screen_dc)

        class BITMAPINFOHEADER(ctypes.Structure):
            _fields_ = [("biSize", wintypes.DWORD), ("biWidth", ctypes.c_long),
                        ("biHeight", ctypes.c_long), ("biPlanes", wintypes.WORD),
                        ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                        ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", ctypes.c_long),
                        ("biYPelsPerMeter", ctypes.c_long), ("biClrUsed", wintypes.DWORD),
                        ("biClrImportant", wintypes.DWORD)]

        bmi = BITMAPINFOHEADER()
        bmi.biSize = ctypes.sizeof(BITMAPINFOHEADER)
        bmi.biWidth, bmi.biHeight = width, -height  # top-down
        bmi.biPlanes, bmi.biBitCount, bmi.biCompression = 1, 32, 0
        buf = ctypes.create_string_buffer(width * height * 4)
        got = gdi32.GetDIBits(mem_dc, bitmap, 0, height, buf, ctypes.byref(bmi), 0)
        if not got:
            log.info("capture %s: GetDIBits failed, err=%s",
                     hwnd, ctypes.get_last_error())
            return None
        from PIL import Image
        img = Image.frombuffer("RGBA", (width, height), buf, "raw", "BGRA", 0, 1).copy()
        # PrintWindow leaves alpha=0 on most windows -> force opaque
        if img.split()[3].getextrema()[1] == 0:
            img.putalpha(255)
        return img
    except Exception:
        log.exception("capture failed for hwnd=%s", hwnd)
        return None
    finally:
        gdi32.SelectObject(mem_dc, old)
        gdi32.DeleteObject(bitmap)
        gdi32.DeleteDC(mem_dc)
        user32.ReleaseDC(wintypes.HWND(hwnd), hwnd_dc)
