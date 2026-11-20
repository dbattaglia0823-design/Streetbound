# Streetbound source and driving physics audit

**Display note (2026-11-08):** Streetbound's game HUD and live tuning labels now use MPH, lb, lb-ft, hp and lbf. Internal handling, gear calculations, vehicle resource values and tests remain in metric SI. Conversion lives exclusively in `scripts/ui/imperial_units.gd` to avoid breaking existing physics.

This audit is based on the complete Streetbound code pushed to main on November 8, 2026, not the earlier initial repo containing only one PNG. Preserve and extend the established Driving Lab.

## Existing functionality reviewed

The VehicleController2D uses a CharacterBody2D, fixed 120 Hz updates, metres/seconds/kg/Newtons, swept wall collisions, slip-angle-based axle forces, front/rear lateral saturation, per-surface grip, drift and countersteering. VehicleConfig and sport_coupe.tres contain stock specifications and the tuned racing setup. VehicleTransmission handles manual and automatic shifts and RPM coupling. The repo also has dedicated input rebinding, camera tracking, engine/tire audio placeholders, live HUD/tuning, skid marks and meaningful driving/racing/runtime regression tests.

These features are substantially beyond a basic arcade controller. The existing grip balance and steering feel are deliberately retained.

## Safe physics fixes included

1. Full vehicle reset now also clears cached longitudinal speed, lateral speed, slip angle, throttle, brake, handbrake and pending controls. Before this, a reset could leave misleading telemetry.
2. After collision response, CharacterBody2D.velocity is resynchronized from the damped physical velocity, and speed/slip telemetry is updated immediately rather than one frame late.
3. Normalized commands for future AI/touch inputs are clamped to throttle/brake/handbrake 0-1 and steering -1 to 1.
4. Brake force now consumes some of the tires' available lateral grip via a simplified friction circle. Previously full cornering capacity could coexist with full braking capacity. Existing steering/tire balance is unchanged without braking. This is not ABS, tire temperature or dynamic weight transfer.
5. The existing driving tests gained targeted assertions. Godot Actions also checks the existing racing-tune comparisons, full runtime scene and archived world integrity.

## Priority areas that still need refinement

- The two-axle tire model does not simulate individual wheel slip ratios, suspension load transfer, ABS/traction control, differential behavior or tire temperature.
- Engine and gearbox coupling lacks detailed clutch dynamics, torque converter, differential losses, realistic limiter cuts and calibrated shift audio.
- Collisions use a swept kinematic body with energy loss; there is no car-to-car crash model.
- The proving ground's road surface query scans segments on every physics tick. A spatial index is needed before loading a large continuous world.
- Audio streams are placeholders, not recordings mapped to real engine RPM/load or road noise.
- Any change to racing grip or steering should continue to pass the existing high-speed, slalom, lift-off and drift-recovery comparisons, followed by hands-on tests.

## Atlas Coast map scale and integration risks

Saved files are in the worlds folder: atlas-coast.world.json, atlas-coast-overview.svg and world_loader.gd. The level design notes are in docs/ATLAS_COAST_PLAN.md. The source is World Forge in Game-Dev-Toolkit at commit 825780debc1e760239297d9bf661c4ab3bde546c.

The Driving Lab controller uses 20 pixels per meter. Atlas Coast uses independent authoring units: a 32-unit two-lane street would be only 1.6 metres across if treated as native game pixels, while the current Porsche collision is about 39 pixels (1.95 metres) wide. Do not load that map as-is for physical driving.

A reasonable INITIAL layout conversion to evaluate is scaling world coordinates and widths by 4. A 32-unit road becomes 128 pixels, or 6.4 metres at 20 px/m; the full map becomes 88,000 by 72,000 pixels (roughly 4.4 by 3.6 km). This is a starting hypothesis, not a surveyed road plan. Validate proportions against the final car asset and camera in gameplay before committing to scale.

The archived loader renders roads, regions, decorative props and collision without streaming, and checks road segments without a runtime spatial index. Activating all of Atlas Coast at once could be prohibitively expensive, especially on mobile. Before switching the game from the existing proving ground, implement chunked rendering/props/collisions, indexed queries, spawn alignment, highway overpass semantics and verified traffic/race route connectivity. Automatically generated crossings currently assume at-grade intersections.

## Validation

The runnable main scene stays the current Driving Lab. Run run_tests.ps1 locally under the installed Godot 4.6.3 for multi-render-rate physics comparisons. The new Actions workflow runs a pinned Godot 4.4.1 compatibility test for driver physics, racing grip, runtime input/UI/audio and saved Atlas Coast markers.

These tests detect regressions but are not real-car telemetry validation. No production map streaming, dealership gameplay, traffic AI or progression is claimed.

## Vehicle stats after removal of the F1 performance menu (2026-11-20)

- The F1 horsepower/torque/weight overlay and its keyboard/controller binding are removed. The HUD only displays vehicle telemetry; it does not modify live physics.
- Switching cars still builds a fresh `VehicleConfig` from `player_vehicle_catalog.gd`, with that model's power, torque, mass, drivetrain, tire grip and braking parameters. Legitimate owned garage upgrades still apply afterward.
- Older `user://streetbound_vehicle_tuning.cfg` files are left untouched for user data safety but are no longer loaded or written. They cannot override the active vehicle.
- Focused regressions: `tests/tuning_persistence_test.gd` (now tests legacy save isolation), `tests/live_vehicle_dashboard_test.gd`, `tests/game_startup_smoke_test.gd`, and `tests/remappable_controls_settings_test.gd`.

## 2026-11-20 — Longitudinal weight transfer and axle grip allocation

The physical 120 Hz bicycle model now derives front/rear normal loads from signed, filtered longitudinal acceleration and an estimated centre-of-gravity height. The axle loads sum to the vehicle's weight, with contact bounds to avoid numerical lift-off. Service brakes are allocated by front brake bias, while the handbrake remains rear-only. Both delivered drive and brake force consume each axle's lateral tire budget via a bounded friction-circle approximation; the existing arcade-braking assist may restore some lateral authority, but cannot increase straight-line tire drive or braking forces. This does **not** simulate wheel-by-wheel load transfer, active ABS, or roll/suspension travel.

The parameters `center_of_gravity_height_m` and `brake_bias_front` are calibration controls, not measured OEM numbers. Before merging, compare the existing drift/handbrake, race tuning, 120 Hz driving, high-output powertrain and AI baseline tests, plus a real player drive. Follow in a separate roster-calibration PR once the physics PR is validated.

### Tire-load sensitivity follow-up

The original full-load longitudinal transfer caused an excessive braking-corner slip angle in `tests/racing_tune_test.gd` when lateral cornering force also grew linearly with each axle's load. Lateral tire force now responds sublinearly to normal-load changes (0.58 power) while longitudinal drive/braking contact remains load-sensitive. The high-speed brake-corner scenario is now exercised by the dedicated two-version race/drift workflow. This is a bounded arcade-friendly contact approximation, not a measured tire curve.

### Braking-yaw envelope

The existing arcade steering target can demand more turn rate than the combined front/rear lateral tire forces support while the service brake is held. During service-brake cornering, yaw is now bounded by the axle-force lateral acceleration budget divided by speed. Existing brake-turn upgrades still vary the limit within a controlled range; no yaw cap is applied for handbrake/rear-lock drifts, and normal non-braking cornering is untouched. The 120 Hz racing-braking test is a CI gate to prevent excessive slip under sustained braking.
