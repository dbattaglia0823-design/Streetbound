@echo off
setlocal
cd /d "%~dp0.."
if not exist "map-editor\maps\morrow-coast.edits.world.json" (
  echo No Morrow Coast editor overlay found.
  echo Open Map Builder, choose Edit Morrow Coast, then Save Morrow edits
  echo into map-editor\maps\morrow-coast.edits.world.json.
  pause
  exit /b 2
)
where py >nul 2>&1
if not errorlevel 1 (
  py -3 tools\build_morrow_coast.py
) else (
  where python >nul 2>&1
  if errorlevel 1 (
    echo Python 3 required for local rebake. Use the GitHub Actions
    echo Morrow Coast World Rebake workflow as an alternative.
    pause
    exit /b 3
  )
  python tools\build_morrow_coast.py
)
if errorlevel 1 (
  echo Rebake failed. See the error above.
  pause
  exit /b 1
)
echo Rebake complete. Review and commit the regenerated worlds files.
pause
