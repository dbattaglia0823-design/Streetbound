# Streetbound Map Builder

This is a repository-owned version of World Forge from
https://github.com/dbattaglia0823-design/Game-Dev-Toolkit/tree/main/web/map-builder
with Streetbound-specific road precedence. It lives inside this repository.
No separate Toolkit setup is required.

## Open the real game project (recommended)

On Windows 11, open your local Streetbound checkout and double-click
**map-editor/Start Map Editor.cmd**. This now starts the local-only Python 3
project server at http://127.0.0.1:8765/ and opens the browser. It requires
the same Python 3 installation used by the production Morrow Coast rebaker;
no Node or additional Python packages are needed.

The editor **automatically imports the current**
`worlds/morrow-coast.world.json` on startup. It previews the actual baked
road layout, biome regions, named destinations, parked traffic, existing
buildings, scenery and foliage. The imagery comes from the **real game-folder
scenery atlas and traffic-vehicle PNGs** rather than placeholder symbols.

With **Select** active, click or drag a visible ordinary building, tree or rock
in the baked game map. The first click makes the object editable automatically
and it can be dragged immediately; scenery takes priority over underlying
roads and terrain. The **Edit existing game scenery** button and Ctrl-click
remain available as alternatives. Move, rotate, resize, change its
compatible game atlas artwork, or use **Hide original from game**. The next
world rebuild replaces/hides the original instead of creating an overlapping
duplicate. Important game structures such as Laurel Motor House's active
garage are protected from this conversion.

Click **Apply to Game** after editing. The local server validates the document,
writes its authoring source to
`map-editor/maps/morrow-coast.edits.world.json`, runs the actual
`tools/build_morrow_coast.py` generation, then updates the playable
`worlds/morrow-coast.world.json` and overview. **No manual export, moving
files, or separate rebuild step is required.** A failed validation restores
the previous authoring, playable map, and overview together. External file
changes are detected before applying, to prevent overwriting a newer map.

Restart Streetbound after Apply to Game: a game that was already launched
keeps its old world in memory. Review the changes, then commit the edited
authoring JSON and generated `worlds/` files to Git as normal.

The browser still cannot write a checkout opened remotely from GitHub Pages.
If Python 3 is absent or you use a regular static server, Morrow Coast import
is read-only; **Export Morrow edits** remains a fallback, followed by running
`tools/Rebuild Morrow Coast.cmd` yourself. To use a different port:
`python tools/map_editor_server.py --port 8766`.

The project server binds **only to 127.0.0.1**, serves a restricted asset
allowlist, requires a same-origin private session token for writes, and
accepts changes only to the single Morrow Coast map. Keep its terminal open
during editing; press Ctrl+C to stop.

The canvas uses the same game sprite atlas and real baked object positions,
but Godot's shaders, dynamic shadows and animated vehicles are not reproduced
pixel-for-pixel inside the browser. Run the game to confirm final lighting,
collision behavior, traffic navigation and framerate.

## Editing

Draw a road by clicking successive centerline points; Enter or Finish ends
the shape. Select a road to drag its control points, insert new ones, extend
the ends, and adjust width, surface, lanes, shoulder and curvature.

- **Paved intersections**: asphalt, concrete and racing asphalt form auto
  junction polygons wherever the centerlines cross, a T/endpoint touches,
  or angled paved footprints overlap. Parallel nearby roads remain separate.
- **Paved priority**: dirt/gravel roads that cross/overlap paved roads create
  no connected intersection. The loose road is drawn and exported as separate
  branches, with clean terminations outside the paved shoulder, and resumes
  across the other side. Moving a road updates the derived gap automatically.
- Edit biome terrain polygons, paint scenery, import PNG/WebP props, insert
  garages/dealers/traffic/race markers; use minimap, undo/redo and Layers
  visibility controls.
- **Manual scenery placement is exact by default.** Creating, dragging,
  resizing, rotating, duplicating or moving roads does not push houses or other
  props toward unrelated road segments. A new road may cross scenery without
  modifying the authored scenery coordinates. Run Map health or enable the
  live road-clearance overlay to identify conflicts. Markers remain free.
- **Live generated-map layers** draw cyan junction locations and pavement
  outlines, orange dirt/gravel terminations, amber possible endpoint joins,
  and optional red scenery-road overlaps. These are read-only previews derived
  from the latest editable roads, including during drags. Traffic lanes and
  their direction remain separately toggleable.
- **Preview selected environment preset** simulates the selected generator in
  place, showing ghost objects, access roads and updated region outlines
  without editing the source. Apply is always a separate action; the entire
  application remains undoable. The original baked trees and game structures
  appear in the editor, but source-generated scenery not yet baked into Godot
  can differ until Apply to Game rebuilds the runtime world.

## Save and import/export

**Save** uses browser storage only. Use **Export JSON** to download an
editable gdt.racing-world v2 map file. Put it in the repo and commit it
for permanent source control. Use **Import JSON** to reopen a previously
exported editable map. The browser cannot silently modify local Git files.

**Godot 4 ZIP** includes an editable world JSON, runtime loader, and a road
network. Dirt and gravel include precomputed renderPieces, and navigable
traversableCenterlines are separated across paved crossings. No false
dirt-to-pavement connections are exported. Traffic AI must use the
traversable centerlines rather than the author's unbroken control spline.

## Increasing the existing map size

Open **Game Map** in the editor and use **Expand Game Map** under World
details. Enter a larger Width to extend the **east (+X) edge** and/or a
larger Height to extend the **south (+Y) edge**, then click **Expand map**.
The editor refreshes the overview and keeps this change in Undo/Redo until
you choose **Apply to Game**. This action writes the updated source and
rebakes the playable world as usual.

Morrow Coast starts at **6,400 × 4,800 metres**. Expansion is supported
up to **9,600 × 7,200 metres**, in steps of 100 metres in the UI. It is
**growth only**: the west/north origin always stays (0,0), no existing
objects are repositioned, and no roads, building dimensions, region IDs,
garage positions or road samples are scaled. The old map remains fully
playable. New room to the east is ocean/coast; new room south is natural
land with sparse, deterministic vegetation and a continuous shoreline.
Build new roads and districts there using the existing Map Builder tools.
The existing world is not automatically stretched or tiled into the new
area.

The first 6,400 × 4,800 metres are generated using the exact original
source coastline, procedural RNG sequence, props, buildings, and road
layout. Added scenery uses an independent coordinate-seeded generator
and never consumes the original random sequence. Future expansions
reproduce the same trees in previously added areas.

The project server rejects shrinking, oversized bounds or overwriting a
newer map revision; failed rebakes restore the playable world and
authoring file. Commit both the edited source and rebuilt world files to
Git, restart Streetbound, and check the new area in the actual game.
Large maps use more storage, streaming chunks, and rendering resources.

## Production-world editing notes

Morrow Coast has more baked objects than authorable control points. The
editor keeps full production scenery in spatial preview buckets, rather
than duplicating thousands of generated trees in the editable source overlay.
The **Map assets** panel counts the actual baked game objects even when
there are zero manually placed objects. Under **Game scenery & edits**, the
nearest existing buildings, foliage, rocks, parking and landmarks can be
selected to focus the camera. Ordinary scenery is made editable by selecting
it; gameplay landmarks can be located but not overwritten. Click-to-edit
converts only selected ordinary objects into a stable source replacement. Other procedural items remain driven by the normal world
generator, so future road and biome changes still generate coherent scenery.


When opening Game Map, the editor initially centers on the player start at
a readable zoom (0.65). Use **Fit** to see the entire coastline, or scroll to
inspect individual roofs and trees. Map assets are not removed when the
editable source list contains zero authored props; the runtime preview
continues drawing the real baked scenery.

Existing roads keep their source IDs, and unchanged high-detail coastline
polygons keep their original geometry. Marker and new building edits take the
same path through production junction, collision and chunk generation.
The editable `gdt.racing-world` document must never replace the game's
`streetbound.streamed-world` runtime JSON directly.

The inspector's game-art picker lists compatible **actual game-folder assets**
(houses, shops, garages, trees, palms, pines and rocks). Its references are
saved as game asset identifiers and resolve to the atlas at runtime.
Custom imported PNG/WebP files are still supported for standalone test maps;
unapproved external images cannot be installed in Morrow Coast through the
editor because the production game must ship them in its own assets folder.

Safety: selected source props cannot be reassigned to gameplay landmark
buildings; adopted object identity is checked on rebuild. Duplicate, stale
or obstructing object replacements cause validation failure, and the
previous playable world remains intact. At most 200 additional authored
scenery objects/replacements are supported in one overlay.

## Tests

From map-editor/, run:
    node --test tests/*.test.mjs
with Node 20+ to check the road priority, intersections and exports.
GitHub Actions runs this suite and the existing Godot driving tests.

Core source: world-model.js, world-geometry.js, world-editor.js,
world-renderer.js, world-junctions.js, world-road-priority.js,
world-export.js, and world_loader.gd.


## Quality safeguards (Map health)

Streetbound's editor now includes an **opt-in Map health** audit under World
layers. Click **Check map** (or the Map health button in the top toolbar) to
inspect the current map; click a finding to focus the problem on the canvas.
Errors show in red, warnings in amber, and informational suggestions in blue.
The audit is read-only and never changes the map automatically.

Checks include:
- Duplicate/zero-length road segments and unsafe overlapping road handles;
- Road self-crossings where a planar race map cannot model elevated crossings;
- Paved lane width versus lane count, and nearby dangling road endpoints;
- Self-intersecting terrain outlines (these block Godot ZIP export);
- Scenery footprints on roads and missing player starts. Gameplay markers can
  deliberately overlap roads, water, houses and other markers; there is no
  off-road marker warning or automatic road snapping.

The audit **never interprets intentional paved-over-dirt road gaps as missing
connections**, and does not reject a legitimate closed racing circuit. It
runs only when requested or immediately before Godot ZIP export, so normal
drawing, camera panning, and driving performance are not affected. The result
is invalidated when the map changes.

**One-click reversible repairs:** Snap safe road ends connects only unambiguous
endpoints in the same compatible network (paved to paved; loose to loose).
Roads within different networks remain separate. Clean duplicate points
removes immediately repeated control points while leaving valid loops intact.
Both operations use the ordinary Undo workflow. The optional Align selected
to road button moves only the chosen object. Align all overlapping scenery
previews candidates and asks before moving only conflicted objects; it never
adjusts unrelated scenery or gameplay markers.

**Smart draw snapping:** New roads are **freehand by default**. Enable the
dedicated Road designer toggle when you want new control points to snap to
nearby compatible endpoints and centerlines; a dashed line shows the exact
target before clicking. Dirt/gravel never snap onto paved centerlines.
Existing road handles do not snap automatically. A moved road handle or entire
road that jumps over 350 world units prompts before the change is committed,
to catch accidental drags.

**Safe exports:** Editable Export JSON always works as a portable recovery
backup. Godot 4 ZIP checks the map first, blocks only topology errors, and
asks for confirmation when warnings remain. Use **Download backup** for a
timestamped JSON copy. **Restore previous** returns to the last recoverable
browser snapshot when one exists; browser storage has limited capacity and
should never be the only backup for large maps.

These checks are *development aids*, not a guarantee that a map is visually
perfect, properly signaled, fully routable, or ready to ship. Traffic lane
permissions, elevation/bridges, AI turn decisions, accessibility and final
drive-testing still require separate implementation and visual review.

### Research references

- OSM JOSM validator — crossing ways, near-unconnected endpoints, geometry
  conflicts: https://josm.openstreetmap.de/wiki/Help/Preferences/Validator
- OSM iD issue 12853 — accidental drag warnings and safeguards:
  https://github.com/openstreetmap/iD/issues/12853
- Godot Road Generator — visual snapping, junction previews, connections:
  https://github.com/TheDuckCow/godot-road-generator
- openMapper — map checks, editor recovery and drive-testing:
  https://github.com/openOMSI-org/openMapper

All new checks and helpers are original code adapted to Streetbound's existing
JS model and geometry; no third-party source code was copied from the above
projects.
