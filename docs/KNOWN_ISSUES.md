# Streetbound — known issues and verification queue

**Status:** Not a complete live issue tracker. Confirm current behavior and the linked PR/CI status before claiming a defect is open or resolved.

| Area | Specific verification point | Evidence or reference |
|---|---|---|
| Race AI routes and overtakes | Confirm route continuity, physical speed envelope and safe passing against current game, not just isolated tests | `docs/ai-driving-benchmark.md`, `tests/racing_traffic_overtaking_test.gd`, `tests/ai_driving_benchmark.gd` |
| Parked steering and simultaneous pedal/handbrake inputs | Regression scenarios must hold on both supported Godot CI variants | `.github/workflows/handbrake-physics.yml`, `tests/handbrake_input_conflict_test.gd` |
| Nearby vehicles at HUD edge | Confirm indicators respect active speed/closing distance/range behavior in the current revision | `docs/offscreen-vehicle-awareness.md`, `tests/offscreen_vehicle_awareness_test.gd` |
| Art alignment | Check actual wheel hubs, overlay sprite pivots and assets across the vehicle roster | `docs/STEERABLE_WHEELS.md`, `tests/multi_model_wheels_test.gd` |

These are **risk/check points, not newly diagnosed bugs**. For confirmed issues, add exact reproduction, expected behavior, observed result, build SHA, and owning PR/issue link. Remove or close them only with evidence.
