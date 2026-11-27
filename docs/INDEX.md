# Streetbound — project knowledge index

**Verified repo survey:** 2026-11-18, `main` (structure and selected source files; not a gameplay test).

Use this as a **routing index**, not a replacement for existing detailed guides. Source code, actual CI and tests remain authoritative. Read one or two relevant notes, not everything.

| Task | First read | Then inspect |
|---|---|---|
| Private online lobbies with friends | [FRIENDS_MULTIPLAYER.md](FRIENDS_MULTIPLAYER.md) | `scripts/network/`, `scripts/ui/title_menu.gd`, `scripts/main.gd` |
| Native macOS build, distribution, input and LAN | [MACOS.md](MACOS.md) | `export_presets.cfg`, `.github/workflows/macos-build.yml`, `tests/macos_export_contract_test.py` |
| Game architecture / entrypoints | [ARCHITECTURE.md](ARCHITECTURE.md) | `project.godot`, `scenes/`, `scripts/main.gd` |
| Physics, traffic, racing AI, overtakes | [RACING_AI.md](systems/RACING_AI.md) | `scripts/world/race_*.gd`, `scripts/vehicle/vehicle_controller.gd` |
| Automated AI performance baseline | [ai-driving-benchmark.md](ai-driving-benchmark.md) | `tests/ai_driving_benchmark.gd`, CI benchmark workflow |
| Vehicle parameters and driving quality | [PHYSICS_AUDIT.md](PHYSICS_AUDIT.md) | `scripts/vehicle/`, physics tests |
| Street races and map waypoints | [RACES_AND_WAYPOINTS.md](RACES_AND_WAYPOINTS.md) | `scripts/world/`, `tests/races_waypoints_test.gd` |
| Enemy minimap and nearby traffic indicators | [RACING_AI.md](systems/RACING_AI.md), [offscreen-vehicle-awareness.md](offscreen-vehicle-awareness.md) | `scripts/world/map_enemy_overlay.gd`, `scripts/ui/offscreen_vehicle_awareness.gd` |
| Current Morrow Coast and map editing | [MORROW_COAST.md](MORROW_COAST.md), [MORROW_EDITOR_AND_TRAFFIC.md](MORROW_EDITOR_AND_TRAFFIC.md) | `map-editor/`, `tools/build_morrow_coast.py` |
| World rendering/performance | [performance-maintenance.md](performance-maintenance.md), [PERFORMANCE_MAP_QUALITY.md](PERFORMANCE_MAP_QUALITY.md) | `scripts/world/`, related tests |
| Vehicle additions, wheel alignment, art | [new_vehicle_2026_expansion.md](new_vehicle_2026_expansion.md), [STEERABLE_WHEELS.md](STEERABLE_WHEELS.md) | `scripts/vehicle/`, `assets/`, `tests/multi_model_wheels_test.gd` |
| Criminal career, robbery and crew | [DRIVING_CRIME_ROADMAP.md](DRIVING_CRIME_ROADMAP.md) | `scripts/world/driving_contracts.gd`, `scripts/world/driving_contract_rules.gd` |
| Garage, upgrades, audio | [upgrades.md](upgrades.md), [VEHICLE_AUDIO_REFERENCES.md](VEHICLE_AUDIO_REFERENCES.md) | `scripts/ui/`, `scripts/audio/` |
| Historical milestones and older handoffs | [WORK_LOG.md](WORK_LOG.md) | Verify old PR/CI status before relying on notes |
| Validation, CI and handoff | [TESTING.md](TESTING.md), [HANDOFF.md](HANDOFF.md) | `.github/workflows/`, `tests/` |
| Technical choices and risks | [DECISIONS.md](DECISIONS.md), [KNOWN_ISSUES.md](KNOWN_ISSUES.md) | Actual issue/PR and code evidence |

[Shared Game-Dev-Toolkit knowledge](https://github.com/dbattaglia0823-design/Game-Dev-Toolkit/tree/main/knowledge) and its `.agents/skills/` are optional. Don't automatically load them all.

**Documentation rule:** update only the affected note after code/tests support it. Keep hypotheses distinct from verified facts.
