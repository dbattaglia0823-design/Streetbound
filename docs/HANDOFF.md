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
