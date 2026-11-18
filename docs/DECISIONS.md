# Streetbound — current architecture decisions

**Status:** Documented from current source and existing project guides; not a history of every past design discussion.

| Choice reflected in current project | Evidence | Practical impact |
|---|---|---|
| The physical car controller owns movement; race AI supplies normalized inputs | `scripts/vehicle/vehicle_controller.gd`, `scripts/world/race_ai_driver.gd` | Keep path planning independent of vehicle force calculations |
| Use metre-space navigation and fixed 120 Hz physics | `scripts/world/race_navigation.gd`, `project.godot` | Preserve unit conversions and deterministic benchmark conditions |
| Maintain the playable Morrow Coast plus explicit world rebake | `README.md`, `docs/MORROW_EDITOR_AND_TRAFFIC.md` | Do not silently replace or rebake map assets |
| Separate compact minimap enemy display from AI behavior | `scripts/world/map_enemy_overlay.gd` | Marker registration should not affect physics or opponent ownership |
| Index and retrieve project docs selectively; reuse shared patterns centrally | This docs/AGENTS.md change | Avoid accumulating a second full copy of the central toolkit vault |

Record new substantive tradeoffs here or as a linked ADR, with date/PR and test evidence. Do not turn inferred intentions into historical facts.
