# Morrow Coast missing-world rendering fix

Verified on Windows with Godot 4.6.3, November 12, 2026.

## Specific root cause

The world archive and its chunk assignments were populated and correct. The
failure occurred during game initialization, before the renderer received them.

Four newly added SVG assets in `assets/Buildings/DowntownPilot/` were hard-preloaded
by `downtown_block_pilot.gd`. They had no local Godot import descriptors/cache.
Launching the player directly after a source pull produced `Preload file ...svg
has no resource loaders`. That failed the shared scenery/chunk/world dependency.
The subsequent `DowntownPilot.apply()` call aborted `MorrowCoast._ready()` before
`segment_stations`, spatial indices, tire marks and the initial world were ready.

Godot continued running the scene's process callbacks. Streaming attempted chunk
construction with an empty station cache. `CoastChunk.setup()` then failed at its
station lookup before constructing road layers or gathering scenery. The old
streamer still cached these partial nodes as successful chunks. Their base grass
could draw, explaining active chunks with zero road/scenery render layers. The
uninitialized tire-mark node and incomplete garage/dealer setup also caused
secondary runtime errors.

The initial GPU reproduction confirmed that spawn chunk `12,15` contained **78
source segments and 19 source props**, but instantiated **zero road and scenery
layers**. Actual garage, house and asphalt framebuffer samples were green.

The import pass also found stale import descriptors still naming `res://Buildings/`
and `res://Traffic Vehicles/` after those directories moved below `res://assets/`.
The corrected descriptors now name the real source and matching imported texture.
Other newly supplied vehicle/audio sources received normal Godot import descriptors.

## Data trace and preservation

- Archive: format `streetbound.streamed-world`, version 1, metres, 20 pixels/metre.
- Source: 120 roads, 16,189 segments, 19,116 scenery props, 850 chunks of 192 metres.
- Spawn: `(2420, 3035)` metres, `(48400, 60700)` world pixels, chunk `(12,15)`.
- Keys are the expected `x,y` strings. Segment midpoints and every prop's position
  match their independently checked source chunk assignments.
- Chunk origin is `cell * 192 * 20` pixels; content uses `(metres - origin) * 20`.
- The existing road-width adaptation is intentional and remains in use.
- The world JSON, road geometry, source art, physics/resources, traffic network and
  progression rules were not edited or rebaked. The archive's Git blob hash is
  identical to HEAD. All verification used isolated `.runtime` user-data folders.

## Changes

| File | Change |
|---|---|
| `scripts/world/downtown_block_pilot.gd` | Cache textures decoded from the actual source SVGs; remove import-sensitive hard preloads. Artwork metadata cannot prevent world compilation. |
| `Launch.cmd` | Import changed sources before starting the normal game; stop and show the import-log location if preparation reports errors. |
| `scripts/world/world_render_health.gd` | Audit archive format, units, indices and coordinate-derived assignments; inspect source, built chunks, visible render content and failure stages separately. |
| `scripts/world/morrow_coast.gd` | Audit before setup, build spatial indices before optional art metadata, track completed initialization and failed chunk builds, refuse to cache incomplete chunks, expand F7. |
| `scripts/world/coast_chunk.gd` | Validate assignments/station availability and expose `setup_complete` / `setup_error`. |
| `scripts/world/coast_map_world_mirror.gd` | Reject failed duplicate map render chunks rather than caching them. |
| `scripts/main.gd` | Show initialization diagnostics and avoid starting dependent systems against an incomplete world. Healthy startup retains all existing systems. |
| `scripts/ui/diagnostics_dock.gd` | Place F7 in free HUD space, avoiding visible panels and labels. Temporarily suspend it when a fullscreen menu leaves no free space, then restore it. |
| `tests/world_render_contract_test.gd` | Main-scene source-to-render regression, malformed-assignment/init/renderer-handoff cases, six-district GPU checks, building collision, cache reuse and F7 layout. |
| `run_tests.ps1` | Run the new contract test and require its completion marker. |
| `.github/workflows/streetbound-validation.yml` | Headless contract check plus rendered district verification using the existing virtual-display setup. |
| `assets/Buildings/**/*.import`, `assets/Traffic Vehicles/*.import` | Correct relocated source/import paths and register the four source SVGs. |
| `assets/Vehicles/**/*.import`, `assets/audio/**/*.import` | Standard import descriptors for existing sources that previously lacked them. No source images or sounds changed. |

F7 now shows player world position, current chunk, archive chunk count, active
source segment/prop assignments, visible batches/content, instantiated active
render nodes, failed builds/render chunks, unexpected empty versus valid
terrain-only chunks, archive compatibility, streaming/cache counters and timings.
Status distinguishes missing/incompatible archive data, missing assignments,
incomplete initialization, chunk construction, missing render content, hidden
layers and healthy terrain-only areas.

## Verification results

**Actual game launch:** launched `project.godot`'s main scene normally, without an
editor, map builder or alternate test scene. Inspected the live window and toggled
F7. Roads, the functional garage, parked cars, nearby houses, trees, navigation and
ambient traffic were visible. The normal launch log contains no runtime errors.

**GPU framebuffer verification:** both `actual_game_render_probe.gd` and the new
contract test passed with OpenGL on the local RTX 4080. The latter visited spawn,
downtown Larkspur, Bellwether Bay, Willowmere, Pinecrest and Ashford Park in the
actual main scene. Each region had populated, visible road/scenery layers and
asphalt pixels in the final game framebuffer. Visible solid building centers
were checked against the physical world where ordinary buildings were present.

At spawn after streaming settled:

| Value | Result |
|---|---:|
| Active/cached chunks | 9 / 9 |
| Assigned road segments | 614 |
| Road batches / road layers | 31 / 32 |
| Assigned and rendered props | 122 |
| Scenery layers | 10 |
| Failed / unexpectedly empty chunks | 0 / 0 |

F7 remained visible without intersecting other HUD rectangles while F1 and F4
were simultaneously open. It suspended during the full atlas and returned after
closing it. Cache reuse, source coordinates and renderer handoff checks passed.

**Driving:** the existing real-controller garage-to-marina route completed in
254.0 simulated seconds, with zero impacts and 1.55% grass frames. Driving tests
passed at 30, 60 and 144 rendering FPS, with identical physics traces.

**Other passing regressions:** downtown art, map streaming/visibility and cache,
road-width adaptation, live world/atlas mirroring, physical garage entry/walls,
parking/scenery layering, junction coverage/markings and garage upgrade/save
migration.

**Existing unrelated failure:** `morrow_traffic_test.gd` still fails its synthetic
`forward_lane_right_of_centerline` and `reverse_lane_uses_other_side` assertions
(Y values 5955 and 6045 around centerline Y=6000). These assertions exercise the
unchanged traffic network independently of world rendering. The traffic network
file has no diff from HEAD; its lane behavior was preserved for this task.

Captures are in `.runtime/renderfix_spawn.png`, `renderfix_downtown.png`,
`renderfix_coast.png`, `renderfix_village.png`, `renderfix_mountain.png`,
`renderfix_circuit.png` and `renderfix_diagnostics.png`. Logs use `renderfix_*.log`.

To repeat GPU verification on this machine, import the project, then run Godot
with `--path . --fixed-fps 60 --script res://tests/world_render_contract_test.gd`
without `--headless`. The ordinary Windows launcher now prepares imports itself.
