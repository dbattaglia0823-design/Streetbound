# Streetbound racing and traffic AI — working map

**Status:** Verified code-path survey, 2026-11-18. Not a claim that current racing behavior is bug-free.

## Runtime wiring

- `scripts/world/race_navigation.gd`: samples metre-space route points, stations and vehicle-dependent corner/braking speed envelope.
- `scripts/world/race_line_builder.gd`: constructs an AI racing line; inspect geometry and race call sites before changing it.
- `scripts/world/race_ai_driver.gd`: `setup()`, `setup_navigation()`, `enable_race_traffic()` and `launch()` configure a physical vehicle for racing. `command` is a normalized Vector4; the actual acceleration/torque/traction/collisions remain with `VehicleController2D`.
- `scripts/world/race_traffic_overtaking.gd`: selects paved passing corridors by sampling `surface_at()` and nearby ambient traffic. It does not teleport the racer or override physics.
- `scripts/world/traffic_flow.gd`, `traffic_network.gd`, `traffic_car.gd`: ambient vehicles and the road traffic model; racing rivals intentionally have different passing behavior.
- `scripts/world/map_enemy_overlay.gd`: small enemy map markers from `race_opponent`, plus optional future `minimap_enemy` group members. Avoid converting this informational feature into AI control logic.
- `scripts/ui/offscreen_vehicle_awareness.gd`: player-centered warning display; see [detailed description](../offscreen-vehicle-awareness.md).

## Tests and comparative metrics

[Automated AI driving benchmark](../ai-driving-benchmark.md) describes the existing deterministic benchmark matrix, scenarios, metrics and report validation. Use the real scene/controller and physical vehicles. Relevant tests and workflows:

- `tests/ai_benchmark_metrics_test.gd`
- `tests/ai_driving_benchmark.gd`
- `tests/race_ai_test.gd`
- `tests/racing_traffic_overtaking_test.gd`
- `tests/handbrake_input_conflict_test.gd`
- `.github/workflows/ai-driving-benchmark.yml`
- `.github/workflows/handbrake-physics.yml`

Check that graph paths, lookahead, speed envelopes, recovery and overtaking are consistent with actual road surfaces. Compare before/after benchmark JSON, not just a single happy-path lap.

## Constraints

No synthetic speed/traction multipliers, target teleporting or side effects that bypass player-equivalent vehicle physics. CI uses Godot 4.6.3 for the race benchmark; the physics project tick rate is 120 Hz. A benchmark result describes these scenarios, **not** the quality of every world race. Distinguish tests actually executed from tests merely listed here.


### Ambient dead-end turnarounds

The ambient graph now generates a low-speed (up to 7.2 km/h) continuous U-turn at genuine two-way flat road ends, including new Map Builder roads using the same native traffic preview. A unique endpoint, sufficient straight terminal length and pavement clearance for a nominal 5.4 m by 2.1 m car are required. The incoming and opposing outgoing lanes end/start before the road cap, leaving room for the tangent-matched cubic connector. The terminal graph remains routable rather than being pruned. Ordinary junction rules, closed loops, one-way ramps, graded roads, GPS and police graph construction remain unchanged. Traffic waits for the shared turnaround area and receiving lane to clear, then uses the normal collision-aware body movement and yaw controller. Narrow or curved ends that fail the footprint check retain terminal behavior; no three-point reverse maneuver or automatic pavement enlargement is introduced. Regression coverage checks route connectivity, pavement clearance, normal lane alignment and occupied turns. CI and in-game verification pending.
