param([string]$Godot = 'C:\Godot\godot.exe')
$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot
# Keep automated runs self-contained, including Godot's user data.
$env:APPDATA = Join-Path $project '.runtime\appdata'
$env:LOCALAPPDATA = Join-Path $project '.runtime\local'
New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA | Out-Null
New-Item -ItemType File -Force (Join-Path $project '.runtime\.gdignore') | Out-Null
function Invoke-Godot([string[]]$Arguments) {
    $process = Start-Process -FilePath $Godot -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) { throw "Godot failed with exit code $($process.ExitCode). Read the run log." }
    $logIndex = [array]::IndexOf($Arguments, '--log-file')
    if ($logIndex -ge 0) {
        $logPath = $Arguments[$logIndex + 1].Trim('"')
        if (Select-String -LiteralPath $logPath -Pattern 'SCRIPT ERROR:|^ERROR:' -Quiet) { throw "Godot reported errors in $logPath" }
    }
}
Invoke-Godot @('--headless', '--path', "`"$project`"", '--editor', '--import', '--quit', '--log-file', "`"$project\import.log`"")
$baseline = $null
foreach ($fps in @(30, 60, 144)) {
    Invoke-Godot @('--headless', '--path', "`"$project`"", '--fixed-fps', "$fps", '--script', 'res://tests/driving_test.gd', '--log-file', "`"$project\test_$fps.log`"", '--', "output=test_results_$fps.json")
    $result = Get-Content -Raw -LiteralPath (Join-Path $project "test_results_$fps.json") | ConvertFrom-Json
    if ($result.failures.Count -gt 0) { throw "Driving checks failed at $fps FPS" }
    if ($null -eq $baseline) { $baseline = $result.fps_trace }
    for ($i = 0; $i -lt $baseline.Count; $i++) {
        if ([math]::Abs($baseline[$i] - $result.fps_trace[$i]) -gt 0.001) { throw "Physics differs at $fps FPS, component $i" }
    }
    Write-Output "PASS: driving scenarios at $fps render FPS / 120 Hz physics."
}
Write-Output 'PASS: render-rate traces agree within 0.001.'
Invoke-Godot @('--headless', '--path', "`"$project`"", '--fixed-fps', '60', '--script', 'res://tests/racing_tune_test.gd', '--log-file', "`"$project\racing_tune.log`"")
Write-Output 'PASS: racing grip, tighter high-speed turns and direction changes.'
Invoke-Godot @('--headless', '--path', "`"$project`"", '--fixed-fps', '60', '--script', 'res://tests/arcade_tune_test.gd', '--log-file', "`"$project\arcade_tune.log`"")
Write-Output 'PASS: arcade turning at low/high speed, brake turn boost and loose surfaces.'
Invoke-Godot @('--headless', '--path', "`"$project`"", '--fixed-fps', '60', '--script', 'res://tests/handbrake_recovery_test.gd', '--log-file', "`"$project\handbrake_recovery.log`"")
Write-Output 'PASS: gradual handbrake recovery, power wheelspin and clean-line corner advantage.'
Invoke-Godot @('--headless', '--path', "`"$project`"", '--fixed-fps', '60', '--quit-after', '1200', '--script', 'res://tests/runtime_test.gd', '--log-file', "`"$project\runtime_test.log`"")
if (-not (Select-String -LiteralPath (Join-Path $project 'runtime_test.log') -SimpleMatch 'RUNTIME TESTS: PASS' -Quiet)) { throw 'Full-scene test did not finish.' }
Write-Output 'PASS: full scene, input, camera, manual shifting, tuning UI, audio and saved bindings.'
Invoke-Godot @('--headless', '--path', "`"$project`"", '--fixed-fps', '60', '--quit-after', '6000', '--script', 'res://tests/open_world_test.gd', '--log-file', "`"$project\open_world_test.log`"")
if (-not (Select-String -LiteralPath (Join-Path $project 'open_world_test.log') -SimpleMatch 'OPEN WORLD TESTS: PASS' -Quiet)) { throw 'Open-world validation did not finish.' }
Write-Output 'PASS: open-world spawn, atlas, connected roads, surfaces, collision clearance and streaming.'
Invoke-Godot @('--headless', '--path', "`"$project`"", '--fixed-fps', '60', '--quit-after', '30000', '--script', 'res://tests/open_world_drive.gd', '--log-file', "`"$project\open_world_drive.log`"")
if (-not (Select-String -LiteralPath (Join-Path $project 'open_world_drive.log') -SimpleMatch 'arrived=true' -Quiet)) { throw 'The garage-to-coast drive did not complete.' }
Write-Output 'PASS: actual garage-to-marina drive through streamed city and coastal roads.'

Invoke-Godot @('--headless', '--path', "`"$project`"", '--fixed-fps', '60', '--quit-after', '1200', '--script', 'res://tests/map_detail_test.gd', '--log-file', "`"$project\map_detail_test.log`"")
if (-not (Select-String -LiteralPath (Join-Path $project 'map_detail_test.log') -SimpleMatch 'MAP DETAIL TESTS: PASS' -Quiet)) { throw 'Atlas navigation validation did not finish.' }
Write-Output 'PASS: pointer-anchored atlas zoom, pan, cache bounds and local minimap follow.'

Invoke-Godot @('--headless', '--path', "`"$project`"", '--fixed-fps', '60', '--quit-after', '65000', '--script', 'res://tests/mountain_drive.gd', '--log-file', "`"$project\mountain_drive.log`"")
if (-not (Select-String -LiteralPath (Join-Path $project 'mountain_drive.log') -SimpleMatch 'arrived=true' -Quiet)) { throw 'Mountain climb did not complete.' }
Write-Output 'PASS: real-controller mountain climb through linked hairpins and guardrails.'

Invoke-Godot @('--headless', '--path', "`"$project`"", '--script', 'res://tests/junction_test.gd', '--log-file', "`"$project\junction_test.log`"")
if (-not (Select-String -LiteralPath (Join-Path $project 'junction_test.log') -SimpleMatch 'JUNCTION TESTS: PASS' -Quiet)) { throw 'Junction validation did not finish.' }
Write-Output 'PASS: all crossings, priority, paint clipping, valid corner geometry and clear turning areas.'
