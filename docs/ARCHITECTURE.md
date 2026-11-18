# Streetbound architecture — code navigation

**Status:** Path-level survey verified against `main` on 2026-11-18. Gameplay outcomes have not been executed in this documentation change.

| Area | Actual locations | Responsibility / investigation entry |
|---|---|---|
| Startup / scene graph | `project.godot`, `scenes/title_menu.tscn`, `scripts/main.gd` | Main scene selected in project configuration; main world setup |
| Input and rebinding | `scripts/input/controls.gd` | Autoload `Controls`, mapped keyboard/controller actions |
| Physical vehicle motion | `scripts/vehicle/vehicle_controller.gd`, `powertrain_dynamics.gd`, `transmission.gd`, `vehicle_config.gd` | `VehicleController2D`, drive command, physical grip and drivetrain |
| Race route and opponent control | `scripts/world/race_navigation.gd`, `race_ai_driver.gd`, `race_line_builder.gd`, `race_traffic_overtaking.gd` | Physical route sampling, speed envelope, normalized commands, tactical passing |
| Ambient traffic | `scripts/world/traffic_flow.gd`, `traffic_network.gd`, `traffic_car.gd` | Traffic simulation and road/lane network |
| Minimap / navigation | `scripts/world/coast_map_view.gd`, `world_map_hud.gd`, `map_enemy_overlay.gd`, `player_waypoints.gd` | Map and enemy overlays, player waypoint handling |
| Driving UI / warning | `scripts/ui/driving_hud.gd`, `offscreen_vehicle_awareness.gd`, `race_status_strip.gd` | Driving HUD, forward traffic awareness and race status |
| World geometry/editor | `scripts/world/morrow_coast.gd`, `map-editor/`, `tools/build_morrow_coast.py` | Current region, editing and explicit baking |
| Content, progression, garages | `scripts/vehicle/player_vehicle_catalog.gd`, `race_progression.gd`, `scripts/world/player_garage.gd` | Vehicle selection/progression and garage-related content |
| Audio | `scripts/audio/vehicle_audio.gd`, `generic_recorded_engine.gd`, `engine_sound_synthesis.gd` | Vehicle audio mix and sound sources |

## Compatibility boundaries

`project.godot` configures 120 physics ticks per second, GL Compatibility, and `Controls` as an autoload. VehicleController2D maintains SI physics quantities while player-facing displays use imperial conversions (`docs/PHYSICS_AUDIT.md`). Preserve serialized scene references, group names, wheel pivots, user settings and game saves.

Race navigation is measured in metres and the AI driver converts to pixel-world routes with `PPM = 20`. The driver updates normalized commands; the vehicle controller owns force/traction/collision physics. Verify call sites before refactors.

The Morrow Coast authoring data and game-ready baked data are different concerns; follow [the editor/bake guide](MORROW_EDITOR_AND_TRAFFIC.md) for regeneration rather than replacing committed world artifacts by guesswork.

## Deeper references

- [Racing AI systems](systems/RACING_AI.md)
- [Morrow Coast](MORROW_COAST.md)
- [Physics audit](PHYSICS_AUDIT.md)
- [Current test entrypoints](TESTING.md)
