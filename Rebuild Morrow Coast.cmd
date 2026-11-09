@echo off
setlocal
title Streetbound - Rebuild Morrow Coast
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 tools\build_morrow_coast.py
) else (
  python tools\build_morrow_coast.py
)
if errorlevel 1 (
  echo.
  echo Morrow Coast bake FAILED. Verify your editor patch, Python 3 and road geometry.
  pause
  exit /b 1
)
echo.
echo Morrow Coast rebuilt. Check the game, then commit the patch and updated world files.
pause
