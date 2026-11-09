@echo off
REM ============================================================
REM  MacWinAnimator - one-click EXE builder
REM  Double-click this file on Windows. It will:
REM    1. install dependencies (Pillow, pystray, PyInstaller)
REM    2. build dist\MacWinAnimator.exe (single file, no console)
REM  Then just double-click dist\MacWinAnimator.exe to run it.
REM ============================================================
setlocal
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Python was not found. Install Python 3.10+ from
  echo         https://www.python.org/downloads/ and tick
  echo         "Add python.exe to PATH" during setup, then retry.
  pause
  exit /b 1
)

echo Installing dependencies...
python -m pip install --upgrade pip
python -m pip install -r requirements.txt pyinstaller
if errorlevel 1 (
  echo [ERROR] pip install failed - check your internet connection.
  pause
  exit /b 1
)

echo Building MacWinAnimator.exe ...
python -m PyInstaller --noconfirm --clean MacWinAnimator.spec
if errorlevel 1 (
  echo [ERROR] Build failed - see the messages above.
  pause
  exit /b 1
)

echo.
echo ============================================================
echo  DONE!  Your app is ready:
echo      %CD%\dist\MacWinAnimator.exe
echo.
echo  Double-click it - it will appear as a small icon in the
echo  tray area next to the clock (bottom-right, maybe under ^).
echo  Right-click the icon for Settings / effects / Quit.
echo ============================================================
pause
endlocal
