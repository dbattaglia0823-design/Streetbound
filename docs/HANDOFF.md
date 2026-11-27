# Streetbound — current development handoff

- **Current source snapshot:** `main` at `78100d5e524b132242a6048c5fbf1690f9f45052`, surveyed 2026-11-24.
- **Purpose:** Short routing and risk summary, not an append-only release log. Prior detailed milestones were preserved in [WORK_LOG.md](WORK_LOG.md).
- **Document status:** Source and merged-PR history checked; no Godot runtime, interactive drive, device, network/WAN or complete CI regression suite was executed in this documentation pass.

## Current source context

- Streetbound remains a Godot 4 driving/racing project. `scripts/vehicle/vehicle_controller.gd` owns vehicle physics and race AI supplies driver inputs; see [RACING_AI](systems/RACING_AI.md) and [PHYSICS_AUDIT](PHYSICS_AUDIT.md).
- `main` includes the merged Phase 2 wake/drafting refinements (PR #192) and Phase 3 environmental effects (PR #193), including rain, spray, collisions and reflections. This is **merge confirmation**, not visual/physical validation. Relevant documentation: [handling](CAR_HANDLING_AND_DRIFT.md), [rendering/performance](performance-maintenance.md) and `tests/driving_phase_three_effects_test.gd`.
- The friend-session multiplayer implementation has separate design and validation requirements in [FRIENDS_MULTIPLAYER.md](FRIENDS_MULTIPLAYER.md). Do not infer working remote Internet play or complete platform compatibility from source or isolated localhost probes.
- The playable Morrow Coast world is authoritative. Do not replace it with toolkit sample maps; see [map documentation](MORROW_COAST.md) and [editor/rebake instructions](MORROW_EDITOR_AND_TRAFFIC.md).

## Road elevation foundation

- Review branch adds signed road layers, layer-aware baking and lane routing,
  browser and native authoring, and a physical deck/tunnel fixture. See
  [Road elevation](ROAD_ELEVATION.md) for limitations and test commands.
- Local Godot 4.6.3 passed the road elevation graph and drive tests, the
  original open world, ambient traffic, native authoring, driving contracts
  and police tactics. The isolated Morrow rebake matched the 126-road
  baseline byte for byte. OpenGL Compatibility captures verified deck
  stacking and the tunnel entrance on Windows.

- Stunt jumps are now authored in both builders. The production bake validates
  the full approach and landing corridor. Godot 4.6.3 verified valid launches,
  rejected approaches and reset input, blocked flight, and recovery from an
  invalid landing. Ambient traffic has independent level contacts and
  recovery, and police route toward the confirmed sighting layer.

## Verification boundaries and remaining work

- Police fleet branch: the seven uploaded police PNG hashes match the generated artwork; Crown Vic and armored truck face up, the other five face down. The model roster is cumulative with a four-unit cap. Focused asset/dispatch tests passed the prior commit’s three CI checks; this follow-up adds five ordinary ambient patrol models within the traffic cap and extends traffic art/movement tests. Follow-up expands to 2/4/6/8/10 responders, delayed replacements, patrol recruitment, PIT contact, emergency effects and host-authoritative shared police snapshots. New CI and live driving/LAN validation remain pending.

1. Before changing code, read [INDEX.md](INDEX.md), the relevant system note and the current script/tests. Identify the exact feature branch/PR rather than relying on this snapshot.
2. For environmental effects, check the **latest commit** in the 4.4.1 and 4.6.3 Godot workflows, then perform actual visual and gameplay evaluation on representative maps, weather levels and vehicles. CI conclusions were not independently established by this documentation edit.
3. For physics/AI, keep real driving benchmarks; for network changes, check two-process regression plus actual player-hosted LAN/WAN latency and disconnect behavior separately; for macOS, test packaged builds on target hardware.
4. Verify save compatibility, world compilation, input controls, wheel visuals and player experience on relevant devices. Headless tests are not equivalent to device or graphical validation.
5. After verified implementation, update the **affected** docs and replace this short handoff with the latest actionable state. Record a major decision or reproducible defect separately; preserve older narrative in [WORK_LOG.md](WORK_LOG.md) and GitHub PR history.

**Shared guidance:** [Game-Dev-Toolkit knowledge](https://github.com/dbattaglia0823-design/Game-Dev-Toolkit/tree/main/knowledge); project-specific mechanics and evidence stay in this repository.

- Robbery career phase 1: five game-owned payout/heat/reputation tiers, race reputation progression, stock Morrow Coast solo contact board using existing road anchors and regression coverage. No crew hiring or cargo yet; CI and live validation pending.

- Robbery career phase 2: selectable Quick/Standard/Maximum profile risks, bounded risk-dependent cash/rep and heat, live crew progress meter and optional lower completed checkpoint, with regression tests. Existing legacy offers unchanged. CI and visual playtest pending.

- Robbery career phase 3: seating/cargo stats for 256 vehicles, mission capacity locks and transient physical load after pickup; regression tests added, live handling and CI unverified.

- Robbery career phase 4: derived ranks and future access gates, pause Career view with real fixer GPS, contact rank/lock display and post-settlement promotions. Existing save format unchanged; crew and black-market content remain later phases. CI/visual validation pending.

- Phase 5: black-market inventory, purchase/equip reputation gates, four slots and real protection/cargo modifiers, upgrade UI and career status. No new tire/cargo damage or outgoing-impact mechanics; CI and live validation pending.

- Phase 6: six persistent recruitable specialists, preferred roster, optional contract crew, previewed net rewards and bounded bonuses, atomic XP/cut settlement. CI and visual verification pending.

- Phase 7: rotating profile availability and persisted per-target cooldown reserved on acceptance; live countdowns, runtime validation and regression tests. UTC system clock, offline expiry, no multiplayer synchronization yet. CI and visual validation pending.

- Phase 8: opt-in co-op stock robbery director with host getaway car, shared physical objectives, individual split reward receipts, online race reputation, protocol 12 and regression tests. Host-only pursuit/cooldown; no NPC specialist bonuses or reconnect resume. CI and real multiplayer testing pending.
