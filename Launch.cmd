@echo off
setlocal
if exist "C:\Godot\godot.exe" (
    start "Streetbound" "C:\Godot\godot.exe" --path "%~dp0." --maximized
    exit /b 0
)
where godot >nul 2>nul
if not errorlevel 1 (
    start "Streetbound" godot --path "%~dp0." --maximized
    exit /b 0
)
echo Godot was not found. Open project.godot in Godot 4 and press F5.
pause
