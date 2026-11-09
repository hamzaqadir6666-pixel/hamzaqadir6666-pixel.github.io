"""The Settings window (tkinter).  Runs on its own thread with a
hidden root so it can be opened/closed from tray callbacks at any
time without blocking the tray or the animation engine.
"""
from __future__ import annotations

import logging
import queue
import threading

from .config import EFFECTS, EFFECT_LABELS

log = logging.getLogger("macwin.settings")

BG = "#1C1C22"
CARD = "#26262E"
FG = "#F2F2F7"
MUTED = "#9A9AA5"
ACCENT = "#2DD4BF"

EFFECT_DESCRIPTIONS = {
    "genie": "The macOS classic — the window pours into the taskbar like a genie into a lamp.",
    "scale": "The window shrinks smoothly down into the taskbar.",
    "fade": "The window fades out while sliding gently downward.",
}


class SettingsWindow:
    """``controller`` provides get_config/save_config/open test hooks —
    see AppController in main.py."""

    def __init__(self, controller):
        self.controller = controller
        self._requests: queue.Queue[str] = queue.Queue()
        self._thread: threading.Thread | None = None
        self._ready = threading.Event()
        self._win = None

    # -- public, callable from any thread --------------------------------
    def show(self) -> None:
        if self._thread is None or not self._thread.is_alive():
            self._thread = threading.Thread(target=self._run, name="macwin-settings", daemon=True)
            self._thread.start()
        self._requests.put("show")

    def close(self) -> None:
        self._requests.put("quit")

    # -- GUI thread ---------------------------------------------------------
    def _run(self) -> None:
        import tkinter as tk

        cfg = self.controller.get_config()
        root = tk.Tk()
        root.withdraw()
        root.title("MacWinAnimator")
        self._root = root

        win = tk.Toplevel(root)
        win.title("MacWinAnimator — Settings")
        win.configure(bg=BG)
        win.geometry("460x600")
        win.resizable(False, False)
        win.protocol("WM_DELETE_WINDOW", win.withdraw)
        self._win = win
        try:
            win.iconphoto(True, tk.PhotoImage(data=_icon_png_base64()))
        except Exception:
            pass

        # header
        head = tk.Frame(win, bg=BG)
        head.pack(fill="x", padx=20, pady=(18, 4))
        tk.Label(head, text="✦  MacWinAnimator", bg=BG, fg=FG,
                 font=("Segoe UI", 17, "bold")).pack(anchor="w")
        tk.Label(head, text="macOS-style window animations for Windows.\n"
                            "Runs quietly in the tray, next to the clock.",
                 bg=BG, fg=MUTED, font=("Segoe UI", 10), justify="left").pack(anchor="w", pady=(2, 0))

        # enable switch
        self._enabled = tk.BooleanVar(value=cfg.enabled)
        tk.Checkbutton(win, text="Enable animations", variable=self._enabled,
                       bg=BG, fg=FG, activebackground=BG, activeforeground=FG,
                       selectcolor=CARD, font=("Segoe UI", 11, "bold"),
                       command=self._apply).pack(anchor="w", padx=20, pady=(10, 2))

        # effect picker
        card = tk.Frame(win, bg=CARD)
        card.pack(fill="x", padx=20, pady=8)
        tk.Label(card, text="Minimize effect", bg=CARD, fg=FG,
                 font=("Segoe UI", 11, "bold")).pack(anchor="w", padx=14, pady=(10, 2))
        self._effect = tk.StringVar(value=cfg.effect)
        for name in EFFECTS:
            tk.Radiobutton(card, text=EFFECT_LABELS[name], value=name,
                           variable=self._effect, bg=CARD, fg=FG,
                           activebackground=CARD, activeforeground=FG,
                           selectcolor=BG, font=("Segoe UI", 10),
                           command=self._apply).pack(anchor="w", padx=14)
            tk.Label(card, text=EFFECT_DESCRIPTIONS[name], bg=CARD, fg=MUTED,
                     font=("Segoe UI", 8), wraplength=390, justify="left").pack(anchor="w", padx=34, pady=(0, 6))
        tk.Frame(card, bg=CARD, height=4).pack()

        # duration slider
        dur_card = tk.Frame(win, bg=CARD)
        dur_card.pack(fill="x", padx=20, pady=8)
        self._duration_label = tk.Label(dur_card, bg=CARD, fg=FG, font=("Segoe UI", 11, "bold"))
        self._duration_label.pack(anchor="w", padx=14, pady=(10, 0))
        self._duration = tk.IntVar(value=cfg.duration_ms)
        tk.Scale(dur_card, from_=200, to=900, orient="horizontal", variable=self._duration,
                 bg=CARD, fg=FG, troughcolor=BG, highlightthickness=0,
                 activebackground=ACCENT, command=lambda _v: self._apply()).pack(fill="x", padx=14, pady=(0, 10))
        self._apply_duration_label()

        # toggles
        tog = tk.Frame(win, bg=CARD)
        tog.pack(fill="x", padx=20, pady=8)
        self._restore = tk.BooleanVar(value=cfg.animate_restore)
        self._autostart = tk.BooleanVar(value=cfg.start_with_windows)
        self._native = tk.BooleanVar(value=cfg.disable_native_animation)
        for text, var in (
            ("Animate windows when they restore", self._restore),
            ("Start with Windows (run in background)", self._autostart),
            ("Turn off Windows' own minimize animation (recommended)", self._native),
        ):
            tk.Checkbutton(tog, text=text, variable=var, bg=CARD, fg=FG,
                           activebackground=CARD, activeforeground=FG, selectcolor=BG,
                           font=("Segoe UI", 10), wraplength=390, justify="left",
                           command=self._apply).pack(anchor="w", padx=14, pady=3)
        tk.Frame(tog, bg=CARD, height=6).pack()

        # buttons
        row = tk.Frame(win, bg=BG)
        row.pack(fill="x", padx=20, pady=10)
        tk.Button(row, text="▶  Preview animation", bg=ACCENT, fg="#06281F",
                  activebackground="#5EEAD4", font=("Segoe UI", 10, "bold"),
                  relief="flat", padx=14, pady=7,
                  command=lambda: self.controller.test_animation()).pack(side="left")
        tk.Button(row, text="Close", bg=CARD, fg=FG, activebackground="#33333D",
                  font=("Segoe UI", 10), relief="flat", padx=18, pady=7,
                  command=win.withdraw).pack(side="right")

        tk.Label(win, text="Tip: right-click the MacWinAnimator icon next to the clock\n"
                           "for quick controls. Settings apply instantly.",
                 bg=BG, fg=MUTED, font=("Segoe UI", 8), justify="left").pack(anchor="w", padx=20, pady=(2, 0))

        def _poll():
            try:
                while True:
                    req = self._requests.get_nowait()
                    if req == "show":
                        self._sync_from_config()
                        win.deiconify()
                        win.lift()
                        win.focus_force()
                    elif req == "quit":
                        root.destroy()
                        return
            except queue.Empty:
                pass
            root.after(120, _poll)

        self._ready.set()
        root.after(120, _poll)
        win.withdraw()
        root.mainloop()

    # -- helpers ------------------------------------------------------------
    def _apply_duration_label(self):
        self._duration_label.config(
            text=f"Animation speed — {self._duration.get()} ms")

    def _sync_from_config(self):
        cfg = self.controller.get_config()
        self._enabled.set(cfg.enabled)
        self._effect.set(cfg.effect)
        self._duration.set(cfg.duration_ms)
        self._restore.set(cfg.animate_restore)
        self._autostart.set(cfg.start_with_windows)
        self._native.set(cfg.disable_native_animation)
        self._apply_duration_label()

    def _apply(self):
        self._apply_duration_label()
        self.controller.apply_settings(
            enabled=self._enabled.get(),
            effect=self._effect.get(),
            duration_ms=self._duration.get(),
            animate_restore=self._restore.get(),
            start_with_windows=self._autostart.get(),
            disable_native_animation=self._native.get(),
        )
        if hasattr(self.controller, "refresh_tray"):
            self.controller.refresh_tray()


def _icon_png_base64() -> bytes:
    import base64
    import io

    from .icon import make_icon_image
    buf = io.BytesIO()
    make_icon_image(64).save(buf, format="PNG")
    return base64.b64encode(buf.getvalue())
