# Streetbound validation guide

**Status:** Commands derived from existing repo workflows and `docs/ai-driving-benchmark.md`; no new gameplay tests were executed to create these notes.

- Main regression: `.github/workflows/streetbound-validation.yml` tests source imports, many game systems and rendering/headless cases.
- Race AI benchmark: `.github/workflows/ai-driving-benchmark.yml` runs engine import, metric checks, real-vehicle simulation, and JSON/CSV/report verification; can also be manually dispatched in Actions.
- Handbrake and parked steering: `.github/workflows/handbrake-physics.yml` tests targeted conflicts/recovery across the listed Godot matrix.
- World bake: `.github/workflows/morrow-coast-rebake.yml` handles source/world regeneration concerns; avoid running rebuild just for docs changes.

## Target commands (local checkout)

Install Godot 4.6.3 for parity with the current primary CI workflow, then from repo root:

    godot --headless --path . --editor --import --quit
    godot --headless --path . --fixed-fps 120 --script res://tests/ai_benchmark_metrics_test.gd
    godot --headless --path . --fixed-fps 120 --script res://tests/ai_driving_benchmark.gd -- --smoke
    python3 tests/validate_ai_benchmark_report.py --mode smoke

For vehicle input issues, follow the exact invocations in `.github/workflows/handbrake-physics.yml`. For live visual/gameplay changes, also launch the playable game and inspect scenes on the target OS/GPU; headless checks alone are insufficient.

## Reporting

Document **which** commands actually ran, engine version, JSON report paths, warnings and outstanding manual tests. Do not infer CI success from a README. For benchmark comparison, preserve equivalent seeds, physics tick rates and build conditions.
