# Automated race-AI driving benchmark

The benchmark runs actual `VehicleController2D` vehicles controlled by the real `race_ai_driver.gd` against existing Morrow Coast race navigation. It does **not** teleport cars along a spline, apply synthetic grip/speed boosts, simulate fake race times, or write to player saves.

## Scenarios

| Route | Real game source | Metric type | Time limit |
|---|---|---|---|
| Ashford quarter-mile drag | `main.drag_race.navigation` | route completion/run time | 45 s |
| Larkspur street sprint | `main.street_race.navigation` | route completion/run time | 115 s |
| Ashford Grand Circuit | `main.circuit_race.navigation` | one-lap completion/lap time | 165 s |

Default full mode runs all three routes with three real stock vehicle configurations (`acura-integra`, `mclaren-570s`, `cadillac-escalade`), for nine primary runs. A tenth **diagnostic** run puts a solid obstacle on the Larkspur route with the Integra to exercise collision and stall/recovery telemetry. Diagnostics may legitimately fail to finish and are excluded from any clean-route success-rate calculation.

`--smoke` runs three distinct pairings, covering all three vehicles and all three routes with less CI load. Seeds, initial heading, vehicle starting configuration, and scene setup are fixed. Ambient traffic spawns are disabled to keep comparisons repeatable; the deliberate obstacle case is only present in full mode. The same game engine version and physics tick rate must be used when comparing results.

## Running

Import assets once in the Godot editor (or via `--editor --import --quit`), then:

```bash
godot --headless --path . --fixed-fps 120 --script res://tests/ai_benchmark_metrics_test.gd
godot --headless --path . --fixed-fps 120 --script res://tests/ai_driving_benchmark.gd -- --smoke
godot --headless --path . --fixed-fps 120 --script res://tests/ai_driving_benchmark.gd -- --full
python3 tests/validate_ai_benchmark_report.py --mode full
```

The dedicated GitHub Actions workflow `.github/workflows/ai-driving-benchmark.yml` runs **all ten cases automatically** on relevant changes to main and pull requests. **Actions → Streetbound AI driving benchmark → Run workflow** can run the full matrix again or choose the shorter smoke mode. It uploads JSON, CSV and benchmark console logs. A run does not fail CI solely because the current AI failed a route; the baseline must remain measurable even when it is weak.

## Metrics

- **Completion:** route finished in allowed simulated time. The circuit requires near-full forward progress and crossing the start/finish; open routes require forward progress, an actual finish approach, and proximity to the endpoint.
- **Run time / lap time:** simulated seconds from AI release to a valid finish; `null` on DNF. `lap_times_s` contains one value only for completed circuit laps.
- **Steering corrections:** left/right command sign flips where both directions exceed the 0.22 deadband, excluding neutral wheel centering.
- **Off-road time:** seconds while the vehicle's actual physics surface is not `ASPHALT`. `offroad_fraction` makes different-length runs comparable.
- **Collisions:** real `crash_contact` signal events from the physics controller, with a 150-ms duplicate-contact filter.
- **Stuck detection:** sustained demand of over 25% throttle at under 1.2 m/s for at least 2.5 seconds. Ordinary braking and legitimate stops do not count.
- **Stuck recovery:** after such a stall, the car physically moves at least 4 m from its stall point at 3 m/s or faster. `unresolved_stuck_events = stuck_events - stuck_recoveries`.
- **Additional diagnostics:** completed route progress, maximum cross-track deviation, peak speed, world distance and wall-clock execution duration.

The bench uses the true player collision/world surfaces. It intentionally retains the baseline AI controller's limitations; the benchmark measures rather than conceals them.

## Report files

```
.runtime/ai_benchmark/ai_driving_benchmark.json
.runtime/ai_benchmark/ai_driving_benchmark.csv
```

The JSON includes schema version, Godot version, physics tick rate, seed, scenario matrix and row-level telemetry. CSV has a flat row per scenario for dashboards. `tests/validate_ai_benchmark_report.py` checks field types, nonnegative metrics, completeness, no duplicated cases, consistency of lap times, and CSV parity. Use `tests/compare_ai_benchmarks.py` with two archived JSON files to see changes between commits:

```bash
python3 tests/compare_ai_benchmarks.py baseline.json candidate.json
```

## Future improvements

Add controlled traffic density, weather/grip presets, multiple deterministic collision perturbations, and matched A/B steering controllers after a baseline is captured. Keep this benchmark's stock vehicle and physics rules stable so changes in route completion, collisions or recovery can be attributed to AI changes.
