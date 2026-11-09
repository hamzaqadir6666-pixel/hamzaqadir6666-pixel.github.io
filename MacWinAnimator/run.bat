@echo off
REM Run MacWinAnimator from source (no build needed).
REM First time:  python -m pip install -r requirements.txt
cd /d "%~dp0"
where pythonw >nul 2>nul
if errorlevel 1 (
  python main.py
) else (
  start "" pythonw main.py --background
)
