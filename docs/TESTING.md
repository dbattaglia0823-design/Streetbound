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


## Parallel CI regression jobs

The main regression workflow separates the existing checks into seven isolated jobs: 4.6.3 gameplay, editor, and startup/render; browser and source world bake; and 4.4.1 physics/UI, world/traffic, and career/driving. The two original job names, `godot-463-game-startup` and `physics-and-world`, are aggregate gates: any failed, skipped, or cancelled dependency prevents a successful gate. Every original test step is retained. Each legacy Godot shard independently rebuilds the production Morrow Coast before testing, so its world data is not dependent on another runner's temporary files. The exact 4.6.3 startup/render shard continues to cold-import; the legacy career/driving shard also cold-imports. Other primary Linux shards can reuse only `.godot/imported`, keyed by engine, OS, architecture, project/import settings and asset content; a normal editor import still runs and script metadata is never cached. Engine binaries and macOS export templates use versioned caches. The macOS export, both engine versions and focused workflows retain their original test/trigger coverage. Superseded main regression and applicable specialized workflow runs are cancelled.

First runs or asset-heavy changes may be cache misses. Additional parallel runners can increase billed runner-minutes and queue contention. Compare total wall-clock duration, individual shard times, cache hits, and the two aggregate conclusions before judging the optimization. Classic branch-protection settings were inaccessible to the editing integration; existing job names and workflow triggers are deliberately retained. Full CI and real timing validation are pending.
