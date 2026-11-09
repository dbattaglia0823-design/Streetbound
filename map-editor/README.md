# Streetbound Map Builder

This is a repository-owned version of World Forge from
https://github.com/dbattaglia0823-design/Game-Dev-Toolkit/tree/main/web/map-builder
with Streetbound-specific road precedence. It lives inside this repository.
No separate Toolkit setup is required.

## Launch from the repository files

On Windows 10/11, double-click **map-editor/Start Map Editor.cmd** from your
Streetbound checkout. It runs a tiny local-only PowerShell web server on
http://127.0.0.1:8765/ and opens the default browser. No Node, Python,
downloads, external accounts or software installation are needed. Keep the
terminal window open while editing; press Ctrl+C to stop.

On other systems, run:
    python3 -m http.server 8765 --directory map-editor
from the repository root and open http://127.0.0.1:8765/.

Do not double-click index.html itself: modern browser ES modules need
an HTTP origin rather than a file:// URL.

If port 8765 is occupied, run PowerShell with:
    powershell.exe -NoProfile -File ".\map-editor\serve.ps1" -Port 8766

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

**Integration boundary:** Streetbound's existing playable Morrow Coast
uses a distinct Python-baked streamed map format at
worlds/morrow-coast.world.json, NOT the editor's gdt.racing-world v2 schema.
Do not overwrite it with editor JSON. The exported Godot adapter can
preview new maps separately; converting new authoring maps into the game's
production streaming format is a separate bake/integration step. The existing
playable world stays unchanged.

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
- Scenery footprints on roads, off-road traffic/race spawn markers and missing
  player starts.

The audit **never interprets intentional paved-over-dirt road gaps as missing
connections**, and does not reject a legitimate closed racing circuit. It
runs only when requested or immediately before Godot ZIP export, so normal
drawing, camera panning, and driving performance are not affected. The result
is invalidated when the map changes.

**One-click reversible repairs:** Snap safe road ends connects only unambiguous
endpoints in the same compatible network (paved to paved; loose to loose).
Roads within different networks remain separate. Clean duplicate points
removes immediately repeated control points while leaving valid loops intact.
Both operations use the ordinary Undo workflow. The existing Fix all road
overlaps helper remains available for mispositioned scenery.

**Smart draw snapping:** New roads snap to compatible road endpoints first,
then nearby road centerlines to create deliberate T connections. Turn off
Smart road endpoint snapping in Road designer to place freehand control points.
Dirt/gravel never snap onto paved centerlines. A moved road handle or entire
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

## Editing the actual Morrow Coast production map

Use `map-editor/Start Map Editor.cmd`, then choose **Open Morrow Coast**.
The local server provides the existing baked world through one read-only
allowlisted URL. The editor loads all production roads and their editable
control-point anchors; it does NOT overwrite the large baked world JSON.

Modify interior control points, road width/lanes or add a new connecting road.
Existing road endpoints represent shared source nodes and cannot be moved
by the safe patch system. Click **Export Morrow patch**, then put the downloaded
`morrow-coast.editor-patch.json` into `worlds/` and run
`Rebuild Morrow Coast.cmd` (or `python tools/build_morrow_coast.py` on Python 3).
The builder validates edits and regenerates splines, intersections, scenery,
surface indexes and streaming chunks before saving world files.

**Current limits:** Production Morrow editing supports roads and new roads.
Terrain, POIs, buildings and props visible in other editor modes are NOT
included in the Morrow road patch. Production road deletion and changing
shared endpoints are blocked to avoid breaking the procedural source graph.
Exported editor-v2 JSON is NOT a substitute for the production streamed map.
Review and commit the patch and rebaked `worlds/morrow-coast.world.json`
and `worlds/morrow-coast-overview.svg` together after testing.

## Ambient traffic

Morrow Coast builds directional right-hand traffic routes from the SAME
baked road centerlines, widths and junction approaches as gameplay uses.
Routes have metre-based stations, speed limits and explicit legal turn
connections. Cars use smooth turns, stop and yield at existing intersection
controls, slow for leading traffic/player vehicles, and remain within a
bounded 18-car population around the player. AI cars have collision shapes.

**F5** toggles a developer traffic-lane display (both directions are
separately colored). F4 still shows static map geometry. There is no
manual traffic editing file to get out of sync with Morrow road edits.

Traffic lights, pedestrian routing, formal lane-changing, advanced demand
simulation and a full district-to-district global route solver are NOT
implemented by this version. Those are sensible future enhancements.

References: SUMO directed lane networks and intersection rules:
https://sumo.dlr.de/docs/Networks/SUMO_Road_Networks.html
https://sumo.dlr.de/docs/Simulation/Intersections.html
and CrowdSim's car-following approach:
https://github.com/VenomEddieVenom/CrowdSim

Automated tests: `map-editor/tests/morrow-bridge.test.mjs`,
`tests/morrow_editor_patch_test.py`, `tests/morrow_traffic_test.gd`.
