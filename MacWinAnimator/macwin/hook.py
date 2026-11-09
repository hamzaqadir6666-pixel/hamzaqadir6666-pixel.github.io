"""Watches Windows for minimize / restore events.

Primary source: ``SetWinEventHook`` for EVENT_SYSTEM_MINIMIZESTART /
MINIMIZEEND (delivered on this module's own message-pump thread).
A lightweight polling fallback (4x/second) catches anything the hook
misses, e.g. windows minimized by exotic shell replacements.
Duplicates are de-duplicated by the Animator.
"""
from __future__ import annotations

import ctypes
import logging
import threading
import time
from ctypes import wintypes

from . import winapi

log = logging.getLogger("macwin.hook")

EVENT_SYSTEM_MINIMIZESTART = 0x0016
EVENT_SYSTEM_MINIMIZEEND = 0x0017
OBJID_WINDOW = 0
CHILDID_SELF = 0
WINEVENT_OUTOFCONTEXT = 0x0000
WINEVENT_SKIPOWNPROCESS = 0x0002
WM_QUIT = 0x0012

if winapi.IS_WINDOWS:
    WINEVENTPROC = ctypes.WINFUNCTYPE(
        None, wintypes.HANDLE, wintypes.DWORD, wintypes.HWND,
        ctypes.c_long, ctypes.c_long, wintypes.DWORD, wintypes.DWORD)
    winapi.user32.SetWinEventHook.restype = wintypes.HANDLE


class WindowEventHook:
    """Calls ``on_minimize(hwnd)`` / ``on_restore(hwnd)``."""

    def __init__(self, on_minimize, on_restore):
        self.on_minimize = on_minimize
        self.on_restore = on_restore
        self._thread: threading.Thread | None = None
        self._poll_thread: threading.Thread | None = None
        self._thread_id = 0
        self._running = False
        self._proc_ref = None
        self._hooks = []

    # ------------------------------------------------------------------
    def start(self) -> None:
        if not winapi.IS_WINDOWS:
            log.warning("WindowEventHook: not on Windows, disabled")
            return
        self._running = True
        self._thread = threading.Thread(target=self._hook_thread, name="macwin-hook", daemon=True)
        self._thread.start()
        self._poll_thread = threading.Thread(target=self._poll_loop, name="macwin-poll", daemon=True)
        self._poll_thread.start()

    def stop(self) -> None:
        self._running = False
        if self._thread_id:
            winapi.user32.PostThreadMessageW(self._thread_id, WM_QUIT, 0, 0)

    # ------------------------------------------------------------------
    def _hook_thread(self) -> None:
        user32 = winapi.user32
        self._thread_id = winapi.kernel32.GetCurrentThreadId()

        def _proc(h_hook, event, hwnd, id_object, id_child, _tid, _time):
            if id_object != OBJID_WINDOW or id_child != CHILDID_SELF or not hwnd:
                return
            try:
                if event == EVENT_SYSTEM_MINIMIZESTART:
                    self.on_minimize(hwnd)
                elif event == EVENT_SYSTEM_MINIMIZEEND:
                    self.on_restore(hwnd)
            except Exception:
                log.exception("event handler failed")

        self._proc_ref = WINEVENTPROC(_proc)
        flags = WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS
        for lo, hi in ((EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND),):
            hook = user32.SetWinEventHook(lo, hi, None, self._proc_ref, 0, 0, flags)
            if hook:
                self._hooks.append(hook)
            else:
                log.error("SetWinEventHook failed: %s", ctypes.get_last_error())

        msg = wintypes.MSG()
        while self._running and user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))
        for hook in self._hooks:
            user32.UnhookWinEvent(hook)
        self._hooks.clear()

    # ------------------------------------------------------------------
    def _poll_loop(self) -> None:
        """Fallback: watch IsIconic transitions of visible top windows."""
        user32 = winapi.user32
        state: dict[int, bool] = {}
        last_sent: dict[int, float] = {}
        ENUMPROC = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

        while self._running:
            seen: dict[int, bool] = {}

            def _enum(hwnd, _lparam):
                if winapi.is_window_visible(hwnd) or winapi.is_iconic(hwnd):
                    seen[hwnd] = winapi.is_iconic(hwnd)
                return True

            try:
                user32.EnumWindows(ENUMPROC(_enum), 0)
            except Exception:
                pass
            now = time.monotonic()
            for hwnd, iconic in seen.items():
                was = state.get(hwnd)
                if was is not None and was != iconic and now - last_sent.get(hwnd, 0) > 1.0:
                    last_sent[hwnd] = now
                    try:
                        (self.on_minimize if iconic else self.on_restore)(hwnd)
                    except Exception:
                        log.exception("poll handler failed")
            state = seen
            time.sleep(0.25)
