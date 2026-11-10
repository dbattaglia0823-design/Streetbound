# Morrow Coast: streaming and map quality

This optimization preserves the authored **192-metre** world, the original
road geometry, player driving physics, map/physics boundaries and minimap.

## Changes

**Warm chunk cache, cold outer ring.** Previously built cells remain cached
up to two cells away, avoiding redundant construction near boundaries.
Only the central **3×3** cell ring draws or participates in physics.
Cached outer cells are invisible, and their static collision layer is
disabled until reactivation. No shapes are deleted or reconstructed.
Colliders are toggled when entering another cell, not every frame.
The existing 25-cell cache maximum and 9-cell active maximum are retained.
Developers can inspect `active_chunk_count()`, `chunk_build_count`, and
`cached_chunk_reuses` to investigate streaming and rebuild frequency.

**Skip empty nodes.** Chunks without roads or junctions avoid creating
unused four-stage road painters. Chunks with no relief or rail data skip
relief layers; those with no scenery skip shadow/scenery layers; and cells
with neither walls nor solid props skip the static physics body.

**Boardwalk index.** Shoreline segments are indexed in metres once when
the map loads. Only cells near the actual boardwalk create and clip its
renderer. Inland map chunks do not process the full beach polyline.

**Traffic artwork.** All ten existing traffic car PNGs remain in the repo
at full source resolution, while their Godot texture imports now cap the
larger side at **512 pixels** and enable mipmaps for smoother small cars at
normal driving zoom. This reduces imported texture dimensions and sampling
bandwidth; mipmaps add their own memory overhead (~33% relative to the
downscaled base texture). The tests verify real imported dimensions.

**World-aligned terrain and roads.** Asphalt has deterministic fine grain,
weathering and rare soft road-repair marks. A new shader uniform called
`road_detail` controls the strength without adding decals or physics nodes.
Beach sand gets subtle packed variation, and fine grass silhouettes fade
out when they become subpixel to reduce shimmering while zooming.
Surface grip, lane width and collision footprints are unchanged.

## Live measurements (F7)

Press **F7** while driving Morrow Coast to toggle the lightweight performance
HUD. It shows measured FPS, per-frame/physics CPU time, draw calls, texture
memory, active versus cached chunk counts, nearby traffic, cumulative chunk
builds/cache reuses and worst recorded chunk setup duration.

The panel is created only after F7 is first pressed and samples Godot's
`Performance` monitors about twice per second. Those monitors can update
at different intervals and some values are unavailable in release builds.
Use the Godot profiler and target-device hardware measurements for exact
benchmarking. **F4** still shows map collision boundaries and **F6** shows
traffic routing.

## Validation and visual review

GitHub Actions now runs `tests/map_stream_quality_test.gd` against the
real Morrow Coast scene. It checks the active/dormant chunk cycle, collision
activation, cached reuse, sparse-chunk allocation, boardwalk indexing,
shader properties and all ten traffic image imports.

Existing map, driving, coast tour, traffic, mountain and collision tests
remain enabled. Inspect roads, beach, forest and traffic manually across
chunk boundaries and at different camera zooms. Frame-time and GPU savings
have not been benchmarked on the user's device and should not be presented
as measured FPS gains until separately profiled.

Official reference: [Godot 2D MultiMesh](https://docs.godotengine.org/en/4.6/classes/class_multimeshinstance2d.html)
and [texture mipmaps / resolution tradeoffs](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html).
