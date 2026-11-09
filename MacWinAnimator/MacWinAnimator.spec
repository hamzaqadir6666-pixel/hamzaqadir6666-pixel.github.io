# PyInstaller spec — build with:  python -m PyInstaller MacWinAnimator.spec
# Produces dist/MacWinAnimator.exe : single file, no console window,
# custom icon, admin NOT required.

a = Analysis(
    ["main.py"],
    pathex=[],
    binaries=[],
    datas=[("assets/icon.png", "assets"), ("assets/icon.ico", "assets")],
    hiddenimports=["pystray._win32", "PIL._tkinter_finder"],
    hookspath=[],
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="MacWinAnimator",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    runtime_tmpdir=None,
    console=False,          # tray app: no black console window
    icon="assets/icon.ico",
)
