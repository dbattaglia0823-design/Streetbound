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

The main regression workflow separates the existing checks into eight isolated jobs: 4.6.3 gameplay, editor interaction, editor construction/bake, and startup/render; browser and source world bake; and 4.4.1 physics/UI, world/traffic, and career/driving. The two original job names, `godot-463-game-startup` and `physics-and-world`, are aggregate gates: any failed, skipped, or cancelled dependency prevents a successful gate. Every original test step is retained. Each legacy Godot shard independently rebuilds the production Morrow Coast before testing, so its world data is not dependent on another runner's temporary files. The exact 4.6.3 startup/render shard continues to cold-import; the legacy career/driving shard also cold-imports. Other primary Linux shards can reuse only `.godot/imported`, keyed by engine, OS, architecture, project/import settings and asset content; a normal editor import still runs and script metadata is never cached. Engine binaries and macOS export templates use versioned caches. The macOS export, both engine versions and focused workflows retain their original test/trigger coverage. Superseded main regression and applicable specialized workflow runs are cancelled.

First runs or asset-heavy changes may be cache misses. Additional parallel runners can increase billed runner-minutes and queue contention. Compare total wall-clock duration, individual shard times, cache hits, and the two aggregate conclusions before judging the optimization. Classic branch-protection settings were inaccessible to the editing integration; existing job names and workflow triggers are deliberately retained. Full CI and real timing validation are pending.

The editor construction/bake shard runs on an independent checkout with its own import and temporary files. The existing 4.6.3 aggregate gate now requires both editor shards. All former test steps and per-test timeout/error assertions are retained. Extra parallelism may increase runner usage; timing improvement must be measured on completed runs.

The shared racing menu refresh retains Toolkit settings action IDs, native CheckBox and HSlider controls and the original pause navigation. Title navigation tests assert the left rail, focus-driven contextual help and live volume readout. The existing controls and pause tests still exercise the saved settings. Visual verification on Godot 4.6.3 and small windows remains pending.

Dealership UI regressions verify that the finance and class labels are separate, the stock grid adapts to multiple viewport widths with reserved scrollbar space, and live card rectangles fit horizontally. The shared racing menu palette also extends to garage, quick upgrades, contacts and race entry; existing gameplay and ownership assertions remain intact. In-game visual verification is still required.

### Recovery-to-bake validation and failure diagnostics

Recovered native race JSON is retyped at the Godot/Python boundary for all integer-only race settings, including career locks and multiplayer prizes. The interaction fixture tests the recovered document and the production bake pre-validates its race schema before building. Malformed fractional and boolean values are not coerced into valid levels. CI names the race fixture, production bake and pause behavior separately; dependent bakes require a successful producer, while independent checks continue after failure. Failed Godot shards upload their known test logs for seven days; aggregate gates publish a shard summary and failure annotations. Test invocations and existing required job identities are unchanged. Full CI re-run pending.
