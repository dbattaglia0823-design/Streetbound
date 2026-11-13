# Streetbound native map editor — transition plan

## Phase 1 (this PR): inspect actual Godot world

In a **Godot development/debug build**, drive in Morrow Coast and press **F6**.

- The actual running world remains rendered, with the existing shaders, scenery, buildings, roads and baked collisions; no browser screenshot or duplicate world is used.
- Left-click a road, paved intersection, or placed prop to inspect the **real baked** metadata. The interface reads `MorrowCoast.data`, the exact surface/geometry queries, and the existing `TrafficNetwork.edges` generated for moving AI traffic.
- Toggle **LANES** to show the real directional lane paths, arrows, and cubic legal turn connectors. Toggle **JUNCTIONS** to show the game's baked intersection pavement polygons. Cyan marks road lanes, orange marks connector turns, pink marks junctions, and yellow highlights the selection.
- Use right/middle mouse drag or WASD/arrows to pan; mouse wheel zooms; **CENTER ON CAR** returns to the player.
- **TEST DRIVE** or **F6** returns to normal player control. The car is not respawned and its original camera is restored. World streaming follows the editor camera while inspecting, then the player after exit.

The mode pauses physics while browsing and builds actual Morrow Coast chunks when the editor camera pans beyond already loaded areas. It exists only in Godot development/debug runs. **It is read-only and cannot save any map changes**.

### Why editing/saving is intentionally excluded from phase 1

Streetbound already has two distinct map representations:

1. **Source**: `map-editor/maps/morrow-coast.edits.world.json` plus the authored roads/regions and protected base generator in `tools/build_morrow_coast.py`.
2. **Play runtime**: `worlds/morrow-coast.world.json`, with baked world chunks, intersections, physical surface indices, and traffic graph inputs.

The browser Map Builder currently validates edits, saves the source, calls the authoritative Python generator, verifies the new archive, and rolls back failures. A native editor must not silently rewrite the generated archive or allow source/runtime drift.

## Phase 2: native authoring operations

Add source-aware selection, drag handles, snapping, undo/redo and **non-destructive previews** for road control points and placed assets. Track stable authored IDs; do not treat bake-only props as independently editable. Reuse or replicate source validation, but do not invent a competing junction generator.

## Phase 3: safe apply / instant inspection

Add a restricted local development bridge for **Apply to Game**. Use the existing validated `build_morrow_coast.py` workflow with revision checks and rollback, then reload the updated archive, scene, pavement geometry, and traffic graph. Keep the map open at the same world coordinates. Provide a deterministic no-edit round-trip and geometry parity suite before allowing writes.

## Phase 4: migrate UI and retire the browser editor

Move asset palette, terrain tools, road topology operations and multi-select to native UI. Maintain the browser editor until the native editor passes the same source preservation, geometry, collision, traffic, undo, and startup tests.

**Do not delete the browser editor or generated assets during this transition.**
