@echo off
setlocal
title Streetbound Map Builder
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1"
if errorlevel 1 (
  echo Could not launch the map editor. See map-editor\README.md.
  pause
)
