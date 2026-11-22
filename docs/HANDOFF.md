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

## 2026-11-22 — Universal macOS build (awaiting CI)

Added a Godot 4.6.3 macOS Universal 2 export preset (Apple Silicon + Intel), included raw JSON/TXT game data required by FileAccess, enabled ETC2/ASTC imports, and introduced a native macOS GitHub Actions job. The job cold-imports, executes title/main-world/control regressions, exports an ad-hoc signed `.app`, checks architectures and signature, runs a packaged headless launch, and publishes a ZIP artifact. New packaging contract test and player instructions live in `tests/macos_export_contract_test.py` and `docs/MACOS.md`.

**Evidence boundary:** changes are source-only until the new PR's Mac CI completes. A generated app and macOS interactive driving, audio, gamepad, saves, Gatekeeper launch, and two-machine LAN are not yet verified. Do not claim a distributable/notarized release. On CI failures, fix the actual error and rerun on the latest commit; afterward test on Apple Silicon and Intel hardware before calling this fully playable.
