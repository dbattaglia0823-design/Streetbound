---
name: godot-change-verification
description: Use for Godot 4 scenes, scripts, driving physics, AI, UI or assets that need import, parse, regression and device-aware checks.
---

# Godot 4 verification

1. Read the actual game instructions, `docs/INDEX.md` if present, `project.godot`, engine version and affected scenes/scripts.
2. Trace node paths, signals, autoloads, input maps, resource UIDs and save contracts before editing.
3. Change minimal relevant code and tests; keep shared gameplay behavior stable unless requested. Inspect `.gd`, `.tscn` and `.tres` compatibility.
4. If the executable is available, run the target project's import/parse checks with the correct path:
       godot --headless --path . --import --quit
       godot --headless --path . --quit
5. Run the real project's dedicated tests and CI. For racing/vehicle changes use deterministic physics cases plus gameplay tests.
6. Visually verify responsive HUD, mobile touch, wheel and sprite alignment, animation and audio where affected.
7. Report exactly which checks ran; headless success does not certify visual correctness, vehicle feel or mobile input.
8. Update verified game-local architecture/issues/handoff. Shared guidance: `knowledge/standards/godot.md` in the toolkit, if accessible.

Never vendor GDScript reference samples that register colliding global `class_name` identifiers.
