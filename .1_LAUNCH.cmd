@echo off
setlocal
if exist "C:\Godot\godot.exe" (
    set "STREETBOUND_GODOT=C:\Godot\godot.exe"
    goto prepare
)
where godot >nul 2>nul
if not errorlevel 1 (
    set "STREETBOUND_GODOT=godot"
    goto prepare
)
echo Godot was not found. Open project.godot in Godot 4 and press F5.
pause
exit /b 1

:prepare
rem A Git pull includes source artwork, not Godot's local .godot import cache.
rem Import changed assets before scripts preload textures in the actual game.
echo Preparing Streetbound assets...
"%STREETBOUND_GODOT%" --headless --path "%~dp0." --editor --import --quit --log-file "%~dp0launch_import.log"
if errorlevel 1 goto import_failed
findstr /C:"SCRIPT ERROR:" /C:"ERROR:" "%~dp0launch_import.log" >nul
if not errorlevel 1 goto import_failed
start "Streetbound" "%STREETBOUND_GODOT%" --path "%~dp0." --maximized
exit /b 0

:import_failed
echo Asset preparation failed. See launch_import.log in the Streetbound folder.
pause
exit /b 1
