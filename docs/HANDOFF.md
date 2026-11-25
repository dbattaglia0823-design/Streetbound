# Streetbound — current development handoff

- **Current source snapshot:** `main` at `78100d5e524b132242a6048c5fbf1690f9f45052`, surveyed 2026-11-24.
- **Purpose:** Short routing and risk summary, not an append-only release log. Prior detailed milestones were preserved in [WORK_LOG.md](WORK_LOG.md).
- **Document status:** Source and merged-PR history checked; no Godot runtime, interactive drive, device, network/WAN or complete CI regression suite was executed in this documentation pass.

## Current source context

- Streetbound remains a Godot 4 driving/racing project. `scripts/vehicle/vehicle_controller.gd` owns vehicle physics and race AI supplies driver inputs; see [RACING_AI](systems/RACING_AI.md) and [PHYSICS_AUDIT](PHYSICS_AUDIT.md).
- `main` includes the merged Phase 2 wake/drafting refinements (PR #192) and Phase 3 environmental effects (PR #193), including rain, spray, collisions and reflections. This is **merge confirmation**, not visual/physical validation. Relevant documentation: [handling](CAR_HANDLING_AND_DRIFT.md), [rendering/performance](performance-maintenance.md) and `tests/driving_phase_three_effects_test.gd`.
- The friend-session multiplayer implementation has separate design and validation requirements in [FRIENDS_MULTIPLAYER.md](FRIENDS_MULTIPLAYER.md). Do not infer working remote Internet play or complete platform compatibility from source or isolated localhost probes.
- The playable Morrow Coast world is authoritative. Do not replace it with toolkit sample maps; see [map documentation](MORROW_COAST.md) and [editor/rebake instructions](MORROW_EDITOR_AND_TRAFFIC.md).

## Verification boundaries and remaining work

1. Before changing code, read [INDEX.md](INDEX.md), the relevant system note and the current script/tests. Identify the exact feature branch/PR rather than relying on this snapshot.
2. For environmental effects, check the **latest commit** in the 4.4.1 and 4.6.3 Godot workflows, then perform actual visual and gameplay evaluation on representative maps, weather levels and vehicles. CI conclusions were not independently established by this documentation edit.
3. For physics/AI, keep real driving benchmarks; for network changes, check two-process regression plus actual player-hosted LAN/WAN latency and disconnect behavior separately; for macOS, test packaged builds on target hardware.
4. Verify save compatibility, world compilation, input controls, wheel visuals and player experience on relevant devices. Headless tests are not equivalent to device or graphical validation.
5. After verified implementation, update the **affected** docs and replace this short handoff with the latest actionable state. Record a major decision or reproducible defect separately; preserve older narrative in [WORK_LOG.md](WORK_LOG.md) and GitHub PR history.

**Shared guidance:** [Game-Dev-Toolkit knowledge](https://github.com/dbattaglia0823-design/Game-Dev-Toolkit/tree/main/knowledge); project-specific mechanics and evidence stay in this repository.
