@echo off
setlocal
title Streetbound Map Builder - Live Game Map
where py >nul 2>&1
if not errorlevel 1 (
  py -3 "%~dp0..\tools\map_editor_server.py"
  goto done
)
where python >nul 2>&1
if not errorlevel 1 (
  python "%~dp0..\tools\map_editor_server.py"
  goto done
)
echo Python 3 is required for direct editing of the playable Streetbound map.
echo The static Map Builder can still be viewed, but cannot apply to the game.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1"
:done
if errorlevel 1 (
  echo Could not launch the map editor. See map-editor\README.md.
  pause
)
