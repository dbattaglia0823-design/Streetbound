# Morrow Coast terrain depth

Streetbound's non-road ground no longer relies on large flat polygons alone.
The existing authored terrain palettes, mountain lighting, collisions and
192-meter streamed chunks remain in place.

## What is different

- Grassland, forest and farmland use broad irregular light/dark patches,
  smaller vegetation tones, restrained fine grain, plus tiny blade shapes.
- A limited number of hand-drawn clumps and small wildflowers are baked into
  each chunk's existing draw commands, filtered to avoid water and beach.
- Beach sand uses warmer surface flecks and subtle broad grain.
- Ocean, rivers and lake polygons receive gentle static ripples and variation.
- Muted city and mountain areas get lighter, less saturated detail.
- Farm plots have shaded planting ridges and crop accents; gardens have leafy
  shapes, while parking and forecourts receive soft paving seams and scuffs.

## Implementation and performance

The ground material lives in scripts/world/mountain_ground.gdshader. It uses
world-space meters (derived from MODEL_MATRIX), so texture patches do not slide
with the camera or restart at chunk boundaries. The original relief texture
and lighting behavior remain active. It also exposes terrain_detail (default
1.0) for reducing GPU texture variation if profiling shows an issue.

scripts/world/coast_chunk.gd draws small grass clumps once into cached chunk
geometry. The decorative 12-meter grid divides the 192-meter chunk evenly.
No runtime vegetation nodes, extra colliders, imported assets, animated
particle simulations, or physics surface changes are added. Roads use their
own independent shader and draw over the ground.

## Validation

CI runs tests/terrain_detail_test.gd and the existing world, junction, road,
mountain, and driving regression tests. Check the spawn, farms, forest,
Juniper Pass, ocean and sandy beach visually at low and high camera zoom.
Also check chunk streaming and FPS on the target hardware.

Reference: https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html
