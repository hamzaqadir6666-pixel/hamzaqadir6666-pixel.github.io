"""A click-through, always-on-top layered window that displays the
animation frames over the desktop (UpdateLayeredWindow, per-pixel
alpha).  Pure Win32 — no toolkit main-loop needed, so it can be driven
from the animator thread frame by frame.
"""
from __future__ import annotations

import ctypes
import logging
from ctypes import wintypes

from . import winapi

log = logging.getLogger("macwin.overlay")

OVERLAY_CLASS = "MacWinAnimatorOverlay"

if winapi.IS_WINDOWS:
    user32, gdi32 = winapi.user32, winapi.gdi32

    WS_POPUP = 0x80000000
    WS_EX_LAYERED = 0x00080000
    WS_EX_TRANSPARENT = 0x00000020
    WS_EX_TOPMOST = 0x00000008
    WS_EX_TOOLWINDOW = 0x00000080
    ULW_ALPHA = 0x00000002
    AC_SRC_OVER = 0x00
    AC_SRC_ALPHA = 0x01
    SW_SHOW = 5

    class BLENDFUNCTION(ctypes.Structure):
        _fields_ = [("BlendOp", ctypes.c_byte), ("BlendFlags", ctypes.c_byte),
                    ("SourceConstantAlpha", ctypes.c_byte), ("AlphaFormat", ctypes.c_byte)]

    class BITMAPINFOHEADER(ctypes.Structure):
        _fields_ = [("biSize", wintypes.DWORD), ("biWidth", ctypes.c_long),
                    ("biHeight", ctypes.c_long), ("biPlanes", wintypes.WORD),
                    ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                    ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", ctypes.c_long),
                    ("biYPelsPerMeter", ctypes.c_long), ("biClrUsed", wintypes.DWORD),
                    ("biClrImportant", wintypes.DWORD)]

    class BITMAPINFO(ctypes.Structure):
        _fields_ = [("bmiHeader", BITMAPINFOHEADER), ("bmiColors", wintypes.DWORD * 3)]

    WNDPROC = ctypes.WINFUNCTYPE(ctypes.c_ssize_t, wintypes.HWND, wintypes.UINT,
                                 wintypes.WPARAM, wintypes.LPARAM)

    # 64-bit-safe handle return types
    user32.CreateWindowExW.restype = wintypes.HWND
    user32.GetDC.restype = wintypes.HDC
    user32.DefWindowProcW.restype = ctypes.c_ssize_t
    gdi32.CreateCompatibleDC.restype = wintypes.HDC
    gdi32.CreateDIBSection.restype = wintypes.HBITMAP

    # ctypes.wintypes does NOT define every handle type — notably there
    # is no wintypes.HCURSOR, and referencing it crashes at import time
    # on Windows. All Win32 handles are pointers, so define them locally.
    HICON = ctypes.c_void_p
    HCURSOR = ctypes.c_void_p
    HBRUSH = ctypes.c_void_p

    class WNDCLASS(ctypes.Structure):
        _fields_ = [("style", wintypes.UINT), ("lpfnWndProc", WNDPROC),
                    ("cbClsExtra", ctypes.c_int), ("cbWndExtra", ctypes.c_int),
                    ("hInstance", wintypes.HINSTANCE), ("hIcon", HICON),
                    ("hCursor", HCURSOR), ("hbrBackground", HBRUSH),
                    ("lpszMenuName", wintypes.LPCWSTR), ("lpszClassName", wintypes.LPCWSTR)]

    # Declared prototypes: correct 64-bit/unsigned conversions for every
    # call on the overlay path (no reliance on ctypes' default int).
    _HWND, _HDC = wintypes.HWND, wintypes.HDC
    user32.CreateWindowExW.argtypes = [
        wintypes.DWORD, wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.DWORD,
        ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
        _HWND, wintypes.HMENU, wintypes.HINSTANCE, wintypes.LPVOID]
    user32.RegisterClassW.argtypes = [ctypes.POINTER(WNDCLASS)]
    user32.RegisterClassW.restype = wintypes.ATOM
    user32.ShowWindow.argtypes = [_HWND, ctypes.c_int]
    user32.DestroyWindow.argtypes = [_HWND]
    user32.UpdateLayeredWindow.argtypes = [
        _HWND, _HDC, ctypes.POINTER(wintypes.POINT),
        ctypes.POINTER(wintypes.SIZE), _HDC, ctypes.POINTER(wintypes.POINT),
        wintypes.COLORREF, ctypes.POINTER(BLENDFUNCTION), wintypes.DWORD]
    user32.UpdateLayeredWindow.restype = wintypes.BOOL
    user32.DefWindowProcW.argtypes = [
        _HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    user32.GetDC.argtypes = [_HWND]
    user32.ReleaseDC.argtypes = [_HWND, _HDC]
    gdi32.CreateCompatibleDC.argtypes = [_HDC]
    gdi32.DeleteDC.argtypes = [_HDC]
    gdi32.CreateDIBSection.argtypes = [
        _HDC, ctypes.POINTER(BITMAPINFO), wintypes.UINT,
        ctypes.POINTER(ctypes.c_void_p), wintypes.HANDLE, wintypes.DWORD]
    gdi32.SelectObject.argtypes = [_HDC, wintypes.HGDIOBJ]
    gdi32.SelectObject.restype = wintypes.HGDIOBJ
    gdi32.DeleteObject.argtypes = [wintypes.HGDIOBJ]

    _wndproc_ref = None
    _class_registered = False

    def _def_wndproc(hwnd, msg, wparam, lparam):
        return user32.DefWindowProcW(hwnd, msg, wparam, lparam)

    def _ensure_class():
        global _wndproc_ref, _class_registered
        if _class_registered:
            return
        _wndproc_ref = WNDPROC(_def_wndproc)
        wc = WNDCLASS()
        wc.lpfnWndProc = _wndproc_ref
        wc.hInstance = winapi.kernel32.GetModuleHandleW(None)
        wc.lpszClassName = OVERLAY_CLASS
        atom = user32.RegisterClassW(ctypes.byref(wc))
        if not atom:
            err = ctypes.get_last_error()
            if err != 1410:  # ERROR_CLASS_ALREADY_EXISTS is harmless
                raise ctypes.WinError(err)
        _class_registered = True

    def _premultiply(image):
        """PIL RGBA -> premultiplied BGRA bytes (what UpdateLayeredWindow wants)."""
        try:
            import numpy as np
            arr = np.asarray(image, dtype=np.uint8).astype(np.uint16)
            alpha = arr[..., 3:4]
            arr[..., :3] = (arr[..., :3] * alpha) // 255
            r = arr[..., 0].astype(np.uint8)
            g = arr[..., 1].astype(np.uint8)
            b = arr[..., 2].astype(np.uint8)
            a = arr[..., 3].astype(np.uint8)
            return np.dstack([b, g, r, a]).tobytes()
        except ImportError:
            from PIL import ImageChops
            r, g, b, a = image.split()
            r = ImageChops.multiply(r, a)
            g = ImageChops.multiply(g, a)
            b = ImageChops.multiply(b, a)
            from PIL import Image
            return Image.merge("RGBA", (b, g, r, a)).tobytes()


class LayeredOverlay:
    """One overlay window covering ``bbox`` for the life of an animation."""

    def __init__(self, bbox):
        if not winapi.IS_WINDOWS:
            raise RuntimeError("LayeredOverlay requires Windows")
        _ensure_class()
        self.left, self.top, self.right, self.bottom = bbox
        self.width = self.right - self.left
        self.height = self.bottom - self.top
        self._ulw_error_logged = False
        ex = WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST | WS_EX_TOOLWINDOW
        self.hwnd = user32.CreateWindowExW(
            ex, OVERLAY_CLASS, "", WS_POPUP,
            self.left, self.top, self.width, self.height,
            None, None, winapi.kernel32.GetModuleHandleW(None), None)
        if not self.hwnd:
            raise ctypes.WinError(ctypes.get_last_error())
        user32.ShowWindow(self.hwnd, SW_SHOW)

    def pump_messages(self) -> None:
        """Keep this thread's window responsive while animating —
        a window whose thread never retrieves messages can be
        ghosted or treated as hung by Windows."""
        msg = wintypes.MSG()
        PM_REMOVE = 0x0001
        while user32.PeekMessageW(ctypes.byref(msg), None, 0, 0, PM_REMOVE):
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))

    def show_frame(self, image) -> None:
        """Push one RGBA Pillow frame (sized exactly to the overlay)."""
        if image.size != (self.width, self.height):
            image = image.resize((self.width, self.height))
        data = _premultiply(image)
        screen_dc = user32.GetDC(None)
        mem_dc = gdi32.CreateCompatibleDC(screen_dc)
        bmi = BITMAPINFO()
        bmi.bmiHeader.biSize = ctypes.sizeof(BITMAPINFOHEADER)
        bmi.bmiHeader.biWidth = self.width
        bmi.bmiHeader.biHeight = -self.height
        bmi.bmiHeader.biPlanes = 1
        bmi.bmiHeader.biBitCount = 32
        bits = ctypes.c_void_p()
        bitmap = gdi32.CreateDIBSection(mem_dc, ctypes.byref(bmi), 0,
                                        ctypes.byref(bits), None, 0)
        if not bitmap:
            gdi32.DeleteDC(mem_dc)
            user32.ReleaseDC(None, screen_dc)
            return
        ctypes.memmove(bits, data, len(data))
        old = gdi32.SelectObject(mem_dc, bitmap)
        try:
            pos = wintypes.POINT(self.left, self.top)
            size = wintypes.SIZE(self.width, self.height)
            src = wintypes.POINT(0, 0)
            blend = BLENDFUNCTION(AC_SRC_OVER, 0, 255, AC_SRC_ALPHA)
            ok = user32.UpdateLayeredWindow(
                wintypes.HWND(self.hwnd), screen_dc, ctypes.byref(pos),
                ctypes.byref(size), mem_dc, ctypes.byref(src), 0,
                ctypes.byref(blend), ULW_ALPHA)
            if not ok and not self._ulw_error_logged:
                self._ulw_error_logged = True
                log.error("UpdateLayeredWindow failed, err=%s",
                          ctypes.get_last_error())
        finally:
            gdi32.SelectObject(mem_dc, old)
            gdi32.DeleteObject(bitmap)
            gdi32.DeleteDC(mem_dc)
            user32.ReleaseDC(None, screen_dc)

    def destroy(self) -> None:
        if getattr(self, "hwnd", None):
            user32.DestroyWindow(wintypes.HWND(self.hwnd))
            self.hwnd = None

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.destroy()
