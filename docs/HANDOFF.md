# Streetbound — knowledge integration handoff

- **Surveyed:** 2026-11-18, `main`
- **Scope:** Documentation/agent routing only; no game code, art, save data or map was changed.
- **Shared reference:** https://github.com/dbattaglia0823-design/Game-Dev-Toolkit/tree/main/knowledge

## Added knowledge navigation

`AGENTS.md`, `docs/INDEX.md`, `docs/ARCHITECTURE.md`, `docs/systems/RACING_AI.md`, `docs/TESTING.md`, `docs/DECISIONS.md`, `docs/KNOWN_ISSUES.md`, and this handoff.

## Verified

Read the repository structure, `project.godot`, selected race and vehicle source, current documentation and CI workflow definitions. Existing AI benchmark docs and regression scripts are preserved.

## Not verified

No actual Godot run, map rebake, interactive vehicle drive, mobile input or race benchmark was executed in this documentation-only change. GitHub PR checks, if any, must be evaluated separately.

## Next use

On the next racing AI request, read `docs/INDEX.md` and `docs/systems/RACING_AI.md`, inspect the actual code, run the appropriate before/after benchmark, then update only the affected files and evidence. Keep generalized lessons in Game-Dev-Toolkit, not duplicated here.

## 2026-11-20 — Remove F1 debug performance overrides

Scope: driving HUD, controls, vehicle-selection callback, stock configuration comments, targeted regression tests and validation step descriptions. F1 tuning UI is removed. Per-model catalog physics and installed upgrades remain the supported stat paths; the legacy tuning save is ignored without deleting user data. Test runs and CI conclusions must be confirmed separately; this handoff does not claim executed gameplay validation.

Further legacy test audit: `tests/imperial_display_test.gd` and `tests/runtime_test.gd` now assert no F1 menu and preserve dashboard display. README and test-runner instructions were updated; actual engine and CI results still require verification.

Fixed final references to the removed F1 panel in the world minimap and race status strip, and revised the race-dismiss test to check normal race overlay visibility without the old menu.

Updated `tests/world_render_contract_test.gd` to verify F7/F4 cooperation without the removed F1 tuning UI.

Clarified that the quick-upgrades delta application preserves runtime driving state and unrelated stats; old F1 tuning is no longer an active concept.

## 2026-11-20 — PR #172 CI follow-up

Two Godot regression jobs (4.6.3 and 4.4.1) reported a script error during `tests/pause_menu_test.gd`: `world_map_hud.gd:307` read the deleted `driving_hud.waiting_action` property. Removed the obsolete F1 input-capture guard in world-map `_input`, while preserving the pause check; added map open/close and paused-state regression assertions to the existing pause-menu test. Car-specific racing/drift physics checks had passed. GitHub Actions must rerun on the updated commit; no unexecuted results are claimed.


## 2026-11-20 — Friends-first online multiplayer foundation

Added a review branch with Godot ENet direct-IP host/join UI, persistent admission/roster, host-driven guest physics, predicted local player and interpolated remote cars, nameplates, model identity broadcast, and online session teardown. The original solo career and local split-screen paths remain separate; no saved-profile migration.

New smoke regression: \`tests/online_friend_session_test.gd\`, run in the Godot 4.6.3 validation workflow. This is a source/code milestone; no two-machine LAN/WAN, port forwarding, real latency or interactive network driving result is claimed. See \`docs/FRIENDS_MULTIPLAYER.md\` for operational caveats, security limitations and next steps.

## 2026-11-20 — Online friend-session CI verification

Godot 4.6.3 CI **run 44809030179** (PR #176) reported **success** for title/pause navigation, `tests/online_friend_session_test.gd` (host world/session lifecycle), and the real two-process ENet localhost probe `tests/online_friend_connection_probe.gd` (host admission, roster, world-ready, model identity, disconnect). The project's Godot 4.6.3 cold import and resource UID preflight were also successful on that run. These are CI regressions, not WAN/firewall, high-latency or interactive multi-person gameplay validation. PR remains a draft.


## 2026-11-20 — PR #176: private invite-only friend lobbies

Scope: \`scripts/network/online_session.gd\` now generates a 192-bit random per-host admission secret, embeds a reachable host endpoint/port plus secret in an \`SB1-\` invitation, requires valid admission before creating a roster member, rejects uninvited connections, and supports host lock/unlock and secret rotation. The title menu accepts a pasteable invitation; in-game host toolbar copies/rotates it. The existing peer-controlled free-roam world remains separate from offline play.

CI fix: standalone Godot 4.4.1 script loading could not resolve the global \`OnlineSession\` identifier; the gameplay scripts now access the \`/root/OnlineSession\` node at runtime. Godot type inference from dynamic Node properties required explicit \`bool\`/\`int\` annotations. Test coverage now exercises invitation parsing/rotation and a real ENet forged-secret rejection process alongside legitimate host/guest peers.

Verification boundary: this milestone requires a green latest-commit **Godot 4.6.3** job and **4.4.1** physics/world job before merging. Test results on earlier revisions do not certify the latest branch. A public relay, lobby discovery backend, automatic NAT traversal and real internet playtesting have **not** been provided; these are documented gaps, not completed features. See \`docs/FRIENDS_MULTIPLAYER.md\`.


## 2026-11-21 — PR on-demand player-hosted LAN sessions

Supersedes the draft dedicated-hosted room PR #177 (closed without merge): the requested player experience is to run a game only while a friend is actually playing, either on the same LAN or across homes. No continuously running dedicated Streetbound machine or subscription is needed.

Added an opt-in UDP LAN discovery autoload (`scripts/network/lan_discovery.gd`), a **Find / Host LAN Game** page on the existing title screen, and a real two-process ENet discovery/join regression. LAN discovery uses bounded UDP broadcast/unicast on **28164**, then rejoins the *existing* host-owned ENet world on the host's game port (default **28163**). It validates protocol, port, player count and credential, and uses the packet's source IP, not a peer-supplied hostname. LAN advertising shares the session invite credential with anyone on that local subnet, so the host must opt in explicitly; the original private invite flow remains available.

For friends at another house, keep the direct private invitation path and use a third-party virtual network such as Tailscale (which handles connectivity without a personally maintained dedicated machine) or an existing public UDP-forwarded host. No built-in relay, unattended dedicated service or cloud-backed invite lookup has been claimed.

Evidence/limits: Godot 4.6.3 cold import and two-process LAN host/guest CI must pass on the branch before merging; current tests do not establish real home Wi-Fi or real cross-house network reachability. Existing physics, map and vehicle systems are unchanged.


## 2026-11-22 — On-demand multiplayer latency and jitter pass

Following the merged LAN/direct-friend P2P PR #178, this work adjusts the existing host-authoritative free-roam transport **without adding a permanent server**. `scripts/network/online_world.gd` now schedules changed controls at 60 Hz with a 10 Hz held-command heartbeat, increases host snapshots from 15 to 30 Hz with monotonic sequence numbers, and corrects local position errors without overpowering local input. `scripts/network/remote_snapshot_buffer.gd` provides a bounded remote-car visual state history (up to seven), interpolation delay based on ENet RTT variance, and at most 60 ms of visual extrapolation. None of this authorizes remote transforms or changes the shared 120 Hz vehicle controller physics.

`scripts/network/online_session.gd` queries actual ENet RTT, RTT variance, and **reliable** loss (not total UDP loss) from `ENetPacketPeer`. An in-game status label surfaces these metrics. Because the snapshot RPC added an integer sequence number, the online protocol version is bumped from **2 to 3**; players must be on the same new game build. Existing invite encoding remains the same, but admission refuses mismatched versions.

Focused test `tests/online_network_smoothing_test.gd` checks rate contracts, interpolation, bounded extrapolation, RTT-aided correction, stale freeze, buffer size, and heading wrap. The existing two-process `tests/online_friend_connection_probe.gd` now checks an actual RTT sample on ENet. New `tests/online_realtime_world_probe.gd` runs two independent full Morrow Coast game processes and checks sequenced world snapshots and remote-car buffer bounds. The networking-specific CI workflow `.github/workflows/multiplayer-latency-validation.yml` was added for a faster dedicated validation path. CI runs all under Godot 4.6.3, alongside the broader 4.4.1 physics/world suite. A final clean CI check is required before saying this is verified or merged. Do not confuse timer intervals, RTT variance or visual delay with physical internet ping reductions.


## 2026-11-22 — Authenticated temporary multiplayer reconnection (PR pending)

From main including merged PR #179, this change adds bounded, **player-hosted** reconnect rather than an external hosted server. The host maintains each disconnected guest's seat and the exact preexisting `VehicleController2D` physics object for 35 seconds, immediately zeros guest control/nitrous on loss, and expires the reservation afterward. The guest automatically retries the prior ENet address and port every 5 seconds for 30 seconds using a separate, host-minted 192-bit in-memory credential. Only a matching credential can reclaim the reserved seat; new invitations still obey lobby lock, invite secret and capacity. Car objects are rekeyed when an ENet peer ID changes. Old v2/v3 builds are intentionally incompatible with the new **v4** admission RPC.

`scripts/network/online_world.gd` keeps the gameplay scene and original local vehicle alive during a short outage, temporarily suspends local input, then resets snapshot interpolation/correction and marks the world ready again before resuming controls. No client can set authoritative vehicle positions through the reconnect handshake. Failed recoveries explicitly fall back to the title menu. Neither host migration nor NAT traversal is added.

Regression coverage: `tests/online_reconnect_world_probe.gd` runs actual two-process Godot ENet connections, simulated mid-session transport loss, personal-token reentry into a locked and invite-rotated room, old host car identity/model restoration, and deterministic reservation expiry. `tests/online_reconnect_impairment_test.gd` drives the existing snapshot buffer under 30/80/150ms **synthetic** RTT, jitter and loss schedules to verify bounded visual extrapolation; it does **not** claim real WAN ping or packet-loss performance. Existing invite and world regressions updated for grace-window semantics. CI must finish green before merge or completion is claimed.

Known limitation: an intentional guest exit also reserves its seat for up to 35 seconds, as no explicit host-acknowledged clean-leave protocol exists. A future iteration can distinguish voluntary departures from unplanned transport loss.


## 2026-11-22 — Player-hosted synchronized Ashford friend racing (v5)

Built atop merged PR #181's player-hosted free roam and reconnect system, this addition integrates `scripts/network/online_friend_race.gd` into the existing `OnlineWorld` at the same stable multiplayer RPC node path on host and guest. The real Ashford Drag Strip supports **2–4 ready drivers** staged in separate lanes, a host-triggered **4.5-second countdown**, locked controls until green, host-authoritative physics and physical **402.336 m** finish-line verification. The host alone evaluates direction/finish bounds, implausible transform jumps, 180-second timeout and millisecond ordered rankings. Guest network actions only request admission/ready/forfeit; they cannot supply finishing transforms or rewards. Peer disconnect during a live run is recorded as DNF rather than an unearned retry. Host cancels and repeatable race lobbies supported.

The existing *solo* Ashford AI/time-trial event is disabled during online sessions so a friend session cannot accidentally award unsynchronized career XP/cash. Multiplayer racing is intentionally **practice-only**, with no wagering, rewards, player collisions, cross-mode career progression, or hosted race servers. `OnlineSession.PROTOCOL_VERSION=5` intentionally rejects old v4 clients that lack the matching friend-race RPC structure. Existing connection and LAN discovery methods are unchanged.

New dedicated tests: `tests/online_friend_drag_rules_test.gd` validates realistic 2–4 lane placement, exact quarter-mile crossing geometry, reset/jump rejection, deterministic ranking and DNF exclusion. `tests/online_friend_drag_world_probe.gd` launches real full-game host/guest processes, connects over actual ENet, stages the original car instances, synchronizes readiness/countdown and confirms host-only time-limit results propagate to guests. Wired CI tests can validate logic and localhost timing, not real cross-house WAN countdown alignment or physical side-by-side driving feel. Requires Godot 4.6.3 focused CI and both 4.4.1 and 4.6.3 full game checks before merge.


## 2026-11-22 — Host-authoritative multiplayer Ashford Grand Circuit (v6, PR pending)

Extend the single `FriendDragRace` RPC node with event selection by **physical host location**: quarter-mile at the existing Ashford drag strip, or a full-lap 2–4 driver race at the authored `AshfordCircuitPractice` start. The new circuit mode reuses the actual parsed, closed >1 km racing line, stages existing cars across safe 3 m lanes within the 14 m road, holds physics inputs until common green, shows route/braking guidance, and requires host-only sequential **directional** physical gates ~110 m apart. Reverse, out-of-order, off-track and implausible jump crossings cannot award laps. Finishes are host-clock results with a 480-second timeout; everything remains **practice only** (no progress rewards or cloud server). This extends the already-tested v5 ENet invite/reconnect system; use **protocol v6** because older clients do not support circuit event selection/state.

All solo race widgets, menus and physics/input updates are disabled while an online friend session is running, including Ashford drag, Ashford circuit, Larkspur sprint and authored races. The single-player routes are still instantiated to supply reliable race paths; single-player rewards and saves remain unchanged. The dedicated tests `tests/online_friend_circuit_rules_test.gd` and `tests/online_friend_circuit_world_probe.gd` cover direction/order/gate/lanes and real two-process event selection/green/DNF without awarding a client-side finish. The existing drag, LAN, reconnect, and 4.4.1/4.6.3 gameplay CI must continue to pass. Larkspur multiplayer sprint, physical player-player collisions, host migration and real WAN validation remain separate future work.

## 2026-11-23 — macOS Universal 2 packaging (PR #180)

Added native Godot 4.6.3 macOS Universal 2 exports for Apple Silicon and Intel, including raw JSON/TXT files consumed via FileAccess. The platform CI workflow cold-imports the project, runs title navigation, live-world startup and remappable controls regressions, builds an ad-hoc-signed app, checks its two executable architectures and code signature, performs an isolated headless packaged-app launch, and publishes a ZIP artifact. Configuration regression is in `tests/macos_export_contract_test.py`; player/setup instructions in `docs/MACOS.md`.

**Evidence:** The isolated macOS branch passed run [44993683948](https://github.com/dbattaglia0823-design/Streetbound/actions/runs/44993683948), and its normal Godot regressions passed run [44993683924](https://github.com/dbattaglia0823-design/Streetbound/actions/runs/44993683924). Since the feature was integrated with newer `main` code, these earlier results are historical; the combined branch requires fresh current-head CI before merge. Native GUI rendering, driving feel, hardware gamepads/audio, save persistence, Gatekeeper on consumer Macs and cross-machine multiplayer have not been tested physically, and Apple Developer ID/notarization are not included. This is an ad-hoc signed development build, not a public notarized release.

## 2026-11-23 — Phase 2 drafting wake refinement

From merged Phase 2 PR #191, refine the aerodynamic wake without changing the vehicle or network protocols. Relative forward-speed difference now attenuates the drafting bonus in addition to distance, alignment and lane offset; the cap stays at 18% aerodynamic drag reduction. The local vehicle and traffic visual scripts fade in four low-alpha background streaks from roughly 50–60 mph, expand to seven under an eligible follower, and fade on overtaking or separation. The existing tests now check relative-speed discrimination, low-speed invisibility, faint high-speed ambience, active-draft emphasis, and departure fade.

Verification status: code/tests authored for Godot 4.4.1 and 4.6.3 CI; GitHub Actions results and manual visual/drive checks must be reviewed on the final commit. No local Godot executable was available in the editing environment.

## Driving immersion Phase 3 — 2026-11-23 (PR pending verification)

This branch adds an optional map-level `rain_intensity` (0–1) to saved custom-map sources, Test Drive compilation and published streamed archives. Map Builder exposes Clear, Light Rain, Rain and Heavy Rain, saved and undoable alongside the map. The shared 120 Hz car physics reads the surface provider's weather, reducing full-wet asphalt grip at most 18%; clear/dry behavior is unchanged. Multiplayer uses the common compiled world state, not a client-authoritative weather or grip RPC.

Existing smoke and skid trails now support capped loose-surface stones and wet tire spray. Existing crash sparks add shallow fast guardrail scrape events and severe glass/plastic shards without changing collision response. A world-space renderer draws short rain streaks and stylized tail/headlamp wet-asphalt glints for nearby racers and traffic. Previous exhaust, nitrous, speed camera and drafting behavior remain intact. The new `tests/driving_phase_three_effects_test.gd` is wired into both CI engine lanes, and the crash regression expects scrape sparks. Pending GitHub checks and actual visual/performance testing; no validation result is asserted here.
