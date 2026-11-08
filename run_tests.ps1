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
Invoke-Godot @('--headless', '--path', "`"$project`"", '--fixed-fps', '60', '--quit-after', '1200', '--script', 'res://tests/runtime_test.gd', '--log-file', "`"$project\runtime_test.log`"")
if (-not (Select-String -LiteralPath (Join-Path $project 'runtime_test.log') -SimpleMatch 'RUNTIME TESTS: PASS' -Quiet)) { throw 'Full-scene test did not finish.' }
Write-Output 'PASS: full scene, input, camera, manual shifting, tuning UI, audio and saved bindings.'
