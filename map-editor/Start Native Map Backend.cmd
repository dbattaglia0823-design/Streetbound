@echo off
setlocal
title Streetbound Native Map Editor - Local Safe Rebuild Backend
echo Starting the local-only map source and production rebuild backend.
echo Open Streetbound in Godot debug mode and press F6 to edit the map.
echo This window can be closed when you are finished.
where py >nul 2>&1
if not errorlevel 1 (
  py -3 "%~dp0..\tools\map_editor_server.py" --no-browser
  goto done
)
where python >nul 2>&1
if not errorlevel 1 (
  python "%~dp0..\tools\map_editor_server.py" --no-browser
  goto done
)
echo Python 3 is required for safe rebuilding of the game map.
:done
if errorlevel 1 pause
