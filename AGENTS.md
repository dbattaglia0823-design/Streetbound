# Streetbound — development instructions

Streetbound is an existing Godot driving game. Work from **this repository's current code and tests**, not from an old conversation or toolkit demo.

## Read only relevant context

1. Read [docs/INDEX.md](docs/INDEX.md), then only the topic page needed for the task.
2. For driving/AI: [docs/systems/RACING_AI.md](docs/systems/RACING_AI.md) and the actual `scripts/world/` and `scripts/vehicle/` implementations.
3. For map edits: `docs/MORROW_EDITOR_AND_TRAFFIC.md`, `docs/MORROW_COAST.md`, the actual `map-editor/` and `tools/` code.
4. For visuals, vehicle art, audio and UI: follow the focused documents linked from the index, not the entire docs directory.
5. Reusable practices from [Game-Dev-Toolkit](https://github.com/dbattaglia0823-design/Game-Dev-Toolkit/tree/main/knowledge) are optional guidance. Hosted Codex sessions must explicitly access that repository; a URL is not a mounted directory.

## Hard requirements

- The playable project is Godot 4; CI uses Godot **4.6.3** and `project.godot` requests GL Compatibility, with fixed **120 Hz physics ticks**. Validate the exact environment; do not assume every test runs on a local install.
- `scripts/vehicle/vehicle_controller.gd` owns the actual vehicle physics; race AI writes normalized commands. Preserve handling, unit conversions, save files, rebinding, wheel layers, collision rules and driving feel unless the task explicitly changes them.
- Do not replace the real Morrow Coast world with Atlas Coast sample content or bypass the map author's explicit rebake pipeline.
- No fake AI movement, position teleportation or synthetic performance boosts to make benchmarks pass. Record failures and measurable behavior instead.
- Do not auto-import external repositories, MCP plugins or game assets without inspecting license, code and compatibility.
- Work on a reviewable branch; add or update focused tests; report actual commands and CI outcomes. Headless parse success is not visual or driving validation.
- After **verified** changes, update the appropriate project-specific page and [docs/HANDOFF.md](docs/HANDOFF.md). Shared generalizable knowledge belongs in the toolkit, not a copy of game internals.

Existing documentation and gameplay take precedence over these routing conventions where more specific.
