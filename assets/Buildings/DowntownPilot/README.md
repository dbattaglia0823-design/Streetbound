# Modern Downtown Block — Style Pilot

**Purpose:** Try the richer city art direction in exactly one existing central Larkspur commercial block, near Market Street (approximately 3150 m east, 2820 m south). The selected block is determined deterministically from existing authored buildings in a single 144 m grid cell; no new map positions are invented.

## Current assets

Four newly authored, transparent, overhead SVG sprites (512 × 512):

- `glass-office.svg` — blue glass curtainwall and rooftop mechanical units
- `brick-hotel.svg` — warm brick, cream parapets and skylights
- `retail-studio.svg` — flat commercial rooftop, AC bank, glazed atrium and decorative accent bands
- `art-deco-tower.svg` — stepped pale stone roof and central blue-glass strip

These files are **original project assets**, not copies of the screenshot or unlicensed portions of third-party packs. They provide a reliable, editable first pass while we evaluate third-party CC0 building models. We have **not** imported Buggy Studio assets (commercial-use license not yet verified) or Kenney meshes (those still require a separate orthographic 3D-to-sprite render workflow).

## Map integration

`scripts/world/downtown_block_pilot.gd` chooses up to eight existing solid commercial buildings inside one 144 m cell within 620 m of the central Market Street anchor. It adds only `downtown_pilot_style` metadata to those props. `MorrowCoast` applies the choice once at load, before any chunks are built. `coast_scenery.gd` uses the appropriate SVG texture in the existing z=6 scenery batch.

Not changed: original baked world JSON, building placement, footprint/rotation, collision shapes, road/sidewalk geometry, traffic, parking entrances, shop interactions or terrain. Outside the selected block, the atlas art is identical to its previous state.

## Acceptance and rollout

Run `tests/downtown_block_pilot_test.gd` (included in the physics/world CI workflow) to validate actual map selection, unchanged authored prop data, texture import, sprite transparency and existing streamed scenery layers.

Inspect the pilot **in the Godot game**, including three camera zoom levels, lighting/contrast against the current roads, and whether the façade/roof appearance fits the requested reference. These overhead SVGs are a trial, not a claim of finished external asset-pack quality. If approved, use the same non-destructive tagging pipeline to roll out a consistent asset set to more blocks.