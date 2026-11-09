# MacWinAnimator — macOS window animations for Windows 🧞

![preview](assets/preview.gif)

**MacWinAnimator gives Windows the macOS minimize animation.** Minimize any
window and instead of the plain Windows shrink, it *pours into the taskbar*
with the classic macOS **Genie effect** — and grows back out when you restore
it. It runs silently in the background as a **small icon in the system tray,
next to the Windows clock** (bottom-right of the taskbar).

| Effect | What it looks like |
|---|---|
| **Genie** | The macOS classic — window squeezes into a funnel and pours into the taskbar |
| **Scale** | Window shrinks smoothly down into the taskbar |
| **Fade & slide** | Window fades out while sliding gently downward |

---

## Get the app (pick one)

### Option A — Download the ready-made EXE (easiest)
1. Go to the repo's **Actions** tab → latest **"Build Windows EXE"** run →
   download the `MacWinAnimator-exe` artifact — *or* grab `MacWinAnimator.exe`
   from **Releases** if a release is published.
2. Double-click `MacWinAnimator.exe`. Done — look for its icon near the clock
   (click the `^` arrow by the clock if you don't see it).

### Option B — Build the EXE yourself (one click)
1. Install [Python 3.10+](https://www.python.org/downloads/) (tick
   *"Add python.exe to PATH"*).
2. Download this folder, then double-click **`build.bat`**.
3. Your app appears at **`dist\MacWinAnimator.exe`** — double-click it to run.

### Option C — Run from source (no build)
```bat
python -m pip install -r requirements.txt
python main.py            :: tray + Settings
python main.py --background   :: tray only
```
(or double-click `run.bat`)

> Requires **Windows 10 or 11**. No admin rights needed.

---

## Using it

- **Right-click the tray icon** (next to the clock) for quick controls:
  Settings, Test animation, on/off, effect picker, Start-with-Windows, Quit.
- **Double-click the tray icon** to open Settings.
- In **Settings** you can pick the effect, change the speed (200–900 ms),
  toggle restore animations, and enable *Start with Windows* so it's always
  there after you log in — silently, with no window.
- **Preview animation** plays the effect on your current window without
  minimizing it.

Settings are stored in `%APPDATA%\MacWinAnimator\config.json` and apply
instantly. The app is single-instance: launching it twice just tells you it's
already running in the tray.

## How it works

1. A Win32 event hook (`SetWinEventHook`) notices the exact moment a window
   starts minimizing — *before* it disappears. (A polling fallback catches
   anything the hook misses; duplicates are filtered.)
2. The window is screenshotted with `PrintWindow(PW_RENDERFULLCONTENT)`,
   which works even for accelerated/UWP apps.
3. The real window minimizes underneath while a click-through, always-on-top
   layered overlay (`UpdateLayeredWindow`, per-pixel alpha) plays the effect
   at up to 60 fps, warping the screenshot slice-by-slice into the taskbar
   button area. On restore it plays in reverse while the real window is
   briefly transparent, so the window itself appears to grow out of the
   taskbar.
4. By default it also switches off Windows' own minimize animation (so the
   two don't play at once) — and **restores your original setting when you
   quit**.

Written in pure Python with `ctypes` — the only pip dependencies are Pillow
(and pystray for the tray; numpy optionally speeds up compositing).

## Honest limitations

- Windows has **no public API for the exact rectangle of a window's taskbar
  button**, so the genie aims at the taskbar edge closest to the window,
  which lands where the button sits in the vast majority of layouts.
- A few windows can't be captured or hooked perfectly: elevated (admin)
  windows when MacWinAnimator isn't elevated, some fullscreen games, and
  windows that minimize themselves in unusual ways. Run the EXE as
  administrator if you need it to cover elevated apps.
- Very large windows on very slow PCs may animate at less than 60 fps —
  shorten the duration in Settings if so.

## Uninstall

Right-click tray icon → **Quit**, then delete the folder/EXE. If you enabled
*Start with Windows*, turn it off first (or delete the `MacWinAnimator` value
under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`). If the
*"Turn off Windows' own minimize animation"* option was on, quitting restores
your previous setting automatically.

## Development

```bash
python -m pytest tests/        # animation-engine + config tests (cross-platform)
python tools/make_assets.py    # regenerate assets/icon.*, assets/preview.gif
```

Layout: `macwin/effects.py` (pure animation math, unit-tested) ·
`macwin/capture.py` / `overlay.py` / `hook.py` / `winapi.py` (Win32 layer) ·
`macwin/animator.py` (event → animation) · `macwin/tray.py` ·
`macwin/settings_window.py` · `main.py` (entry point).

## License

MIT — do what you like, attribution appreciated.
