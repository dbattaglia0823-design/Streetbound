# Streetbound Map Builder

This is a repository-owned version of World Forge from
https://github.com/dbattaglia0823-design/Game-Dev-Toolkit/tree/main/web/map-builder
with Streetbound-specific road precedence. It lives inside this repository.
No separate Toolkit setup is required.

## Native editor inside Streetbound

Choose **Map Editor** on the game's title screen in a local development build.
This opens `scenes/world_editor.tscn`, using the real Godot map renderer and
project artwork. **F6** also opens the editor during single-player free roam.

The native workspace follows the browser builder: a top tool strip, settings
and scenery library on the left, a canvas action bar, and layers, inspector and
searchable object list on the right. A clickable minimap navigates the world.
**Fit / F** fits the complete map inside the canvas between the sidebars.
Zooming out retains the entire map's real terrain, roads and scenery in a
cached 4096-pixel overview. Close views switch to collision-free detail tiles
only after all requested tiles are ready. The tile budget never blanks the map.

**Dealership areas and vehicle inventory (native Morrow Coast editor):** In the
left Tool Settings panel, select **Dealership areas & stock**. Choose one of
the ten existing dealerships or **Place new dealership**, then **Move selected
on map** to click its new location. Place the building center on clear land
at least 35 metres from a road, leaving room for the drive-in lot and paved
entrance. The map overlays the editable forecourt; the selected shop and
parking/browse bay are highlighted. Edit the dealership name, tier, artwork,
center coordinates, lot width and lot depth in the manager. Default shops
keep their existing automatic roadside placement until you explicitly move
them; changes to inventory alone never relocate them. The currently supported
playable deployment is Morrow Coast.

Inventory can use **Automatic** (every car whose catalog `dealership_id`
matches this shop, including newly added models) or **Custom** (Ctrl-click
the vehicle catalog list to select vehicle IDs). The selector loads the
latest `data/player_vehicle_catalog.json`; no copied car prices or stats
are stored. In the running game, both shop listings and purchase validation
use the same resolved catalog, and the outlined forecourt remains the actual
drivable pavement / slow-speed interaction area. **Save to Game**, then
**Reload World** to use the changed dealerships. Authoring overrides are
saved with the World Forge source and included in baked Morrow Coast export
data; Undo/Redo/Discard protect them like other map edits.

**Automatic bridges:** Roads crossing rivers, lakes or ocean gain a raised deck,
shadows and guardrails automatically. Bridge width follows road width and the
rails leave the driving lanes and intersection mouths clear. Road and terrain
edits update the preview immediately; moving back onto land removes the bridge.
Save to Game rebuilds the bridge artwork, streaming membership and rail collision
together. Existing maps also derive bridges on load; no manual bridge placement
or rebake is required to see the updated bridges.

- **Select / Edit**: drag a road's body to move the whole road. Shared endpoints
  move together. Select a road, then drag its orange handles to reshape it;
  **Shift-click** adds a control point. **Road Point** exposes every road handle.
- **Draw Road**: choose class, surface, width in metres and lanes, then click
  successive points. **Finish / Enter** creates the road; double-click also
  finishes. Compatible nearby roads attract new points for clean joins.
- **Road Shapes** in the left settings: select an open road, set **Bend m**,
  then **Curve left**, **Curve right** or **Straighten road**. Left/right is
  relative to the first-to-last control-point direction. The whole selected
  road is reshaped, keeping its end positions and moving attached branch
  endpoints with its junction anchors. Use Split first to shape just one part.
  **Place circular road** lets you set **Radius m** and click a center to make
  an exact closed circle. Select it and use **Apply radius to circle** or the
  **−/+ 5 m** buttons to resize around the same center; attached entry roads
  follow. Circles retain their radius and smooth closing seam after saving,
  moving or duplicating. Shape changes support Undo/Redo and reject edits
  outside the map. Manually reshaping individual circle points returns it
  to a normal road; the radius tools apply only to circular geometry.
- **Terrain Region**: choose a material, click at least three polygon corners,
  then **Finish**. **Game Marker** offers checkpoint, race start, finish and
  traffic spawn types. Select markers or terrain edges to move them.
- **Scenery**: choose project artwork, click to place, then use Select / Edit
  to move it. Inspector rotation and scale update the draft art and collision.
  **Refresh Assets** scans the project again for newly added artwork.
- Right/middle drag or **Space + drag** pans; the wheel zooms around the cursor.
  WASD pans, except while entering text. Arrows nudge a selected object by
  one metre; Shift nudges ten metres. Without a selection, arrows pan.
  **Snap to grid** controls one-metre snapping; the separate Grid layer draws
  an adaptive guide. Terrain, roads, scenery, markers, lanes and junctions can
  be toggled independently.
- The inspector edits names and coordinates, plus scenery rotation/scale.
  Its road point picker targets one handle or the whole road; interior road
  points can be removed. **Ctrl+D / Duplicate** creates an undoable copy.
- **Ctrl+Z / Ctrl+Y** undo/redo. During drawing, Undo removes the last point.
  Existing roads support **Add road point**, the control-point picker,
  **Remove selected road point**, and **Split road here** in the native inspector.
  With the whole road selected, Add chooses its longest span and Split chooses
  its middle. A road must retain at least two points. Browser point insertion
  and splitting can also target a click on the selected curve. Splitting keeps
  the original outer endpoints and creates a second editable road.
  Select the first or last control point for **Detach junction**. Detached
  roads move independently; drag the endpoint away to create a gap. To join
  again, move it within 12 m of a compatible endpoint and choose
  **Reconnect endpoint**. Equally close endpoints in different places require
  moving closer to the intended connection. Undo restores the previous geometry.
  The connection readout shows whether touching ends move together.
  Endpoints can also attach to the **middle of another compatible road**.
  Drag an endpoint onto a road, draw a new road ending on it, or use
  Reconnect endpoint. The target receives a shared control point; junctions,
  markings and navigation update from that geometry. Hold Alt while releasing
  a dragged endpoint to bypass the automatic connection.
  Asset picking excludes hidden/replaced baked objects and uses a small
  screen-space tolerance around the current footprint. Live scenery has its
  own visibility mask, so moving saved adopted assets keeps their artwork.
  Dragging props updates their transform directly; full scenery/collision
  work happens at edit boundaries, and road topology rebuilds after commits.
  The moving asset and outline use separate draw canvases, leaving roads,
  lane guides and other scenery cached. The full-map texture refresh waits
  until overview LOD is needed; asset-folder scans wait until dragging ends.
  Adopted scenery keeps its saved appearance across procedural regeneration.
  Save reports disconnected roads and manual building overlaps as warnings;
  it keeps explicit placements and their collision instead of discarding the
  whole transaction. Invalid source geometry still rolls the transaction back.
- **Street races & routes** opens native sprint/circuit route editing. Give
  the race a name, choose **Race vs AI** (1–6 opponents) or **Time trial (solo)**
  (zero opponents), and select sprint or circuit, lap count, start-circle
  radius, checkpoint-gate radius and optional time limit (zero disables it).
  Click existing roads in order for the **start, intermediate checkpoints and
  finish**, then press Enter. Placement snaps to the road centerline; clicks
  away from any authored road are rejected. Circuits loop back to their start.
  To edit a placed event, click its start marker or select it in Objects/the
  race selector. Drag a checkpoint onto a road, or choose a numbered gate and
  **Place checkpoint on road** to insert an additional waypoint in order. Use
  **Move checkpoint earlier/later** to reorder intermediate gates. Start and
  sprint finish are preserved when deleting/reordering checkpoints; reposition
  them by dragging. Grid controls allow individual player/AI start placements
  or auto-arranged formations; switching to Time trial removes all AI starts.
  Edits are undoable. **Save to Game** bakes the race and grid into the playable
  Morrow Coast archive. Reload/Test Drive to see race starts and markers; drive
  into the start circle facing the route and press F. You must cross every
  checkpoint in order. Both formats are practice events without economy
  rewards. Custom maps retain their races in editor documents.
  Existing races no longer cancel for leaving their racing line. Actual
  position jumps still invalidate built-in reward races. During a countdown
  or run, Pause shows **Quit Race**; it clears rivals and race state and
  returns to free driving without rewards. The button is hidden otherwise.
- Scenery has independent X/Y size multipliers and a footprint readout in metres.
  Buildings default to **Face nearby road**: when brought within 3 m of the
  roadside, their front turns toward the local road direction and their actual
  scaled footprint snaps just outside its shoulder. The inspector checkbox
  applies to that asset only; switching it off retains its position/rotation
  and leaves building-edge snapping available. The preference is saved and
  copied when duplicating. **Artwork front** chooses bottom, right, top or left
  for models drawn with a different entrance direction. Existing assets align
  when moved near a road; editing a map does not reorient every building.
  **Building edges: on** snaps nearby building walls and corners to their
  exact world-space edges (up to 3.5 m), including differently rotated roofs,
  scaled footprints, and existing city buildings. Parallel facades can align
  their centres, leading corners or trailing corners. Edge/corner snapping
  overrides the one-metre grid and does not insert artificial wall gaps.
  Buildings can overlap on purpose when placed, dragged, resized, rotated,
  duplicated or moved together; the editor no longer rejects overlapping
  building footprints or pushes them apart. Road-facing alignment still keeps
  buildings outside road surfaces. Hold **Alt** to bypass both snaps temporarily,
  or turn off **Face nearby road** and **Building edges** for free placement.
  **Draw sidewalk** in Tool Settings accepts path points like roads: set the
  width (0.8–12 m), click points, then Enter/Finish. Escape cancels; Undo removes
  the whole path. Finished sidewalks can be selected, moved, rotated, resized,
  duplicated and deleted as scenery. They render below roads and do not add
  traffic lanes or collision walls. Save to Game preserves paths across chunks.
  Position, rotation and scale fields accept three decimal places.
  **Reset asset size** restores all size multipliers to one in a single undo
  step, preserving artwork, position and rotation.

New custom maps start empty. Morrow Coast's separate dealership and forecourt
display layer stays with Morrow Coast, including when the Scenery layer is
toggled. Custom-map data is isolated from the cached Morrow road/bridge
canvases; switching maps does not rewrite the playable archive.

  **Escape** cancels an unfinished shape or drag. **Delete** removes a selected
  prop or a newly created object. Original roads, terrain and gameplay markers
  are protected from deletion; they can be moved or reshaped.

**Save to Game / Ctrl+S** starts the local Python backend automatically if
needed, checks for outside file changes, and runs the production world builder.
The native header also includes a saved-map dropdown and **New map**. The dialog
asks for a name, width/height (600–24,000 m), and base terrain. Custom maps are
saved independently in Godot's `user://streetbound-maps/` folder; Ctrl+S saves
the selected custom map, and switching away saves its edits. Recovery journals
keep unsaved custom-map drafts separate from Morrow Coast. New maps have full
terrain coverage, support terrain polygons right to the edge, and draw land
over water in authored order. Water uses a cached shoreline distance field for
shallow/deep coloration, island shorelines, animated ripples and subtle foam.
Custom maps support **Test Drive (F6)** directly from the native map builder.
The editor saves the selected custom map, compiles its real production-style
road/junction geometry into a temporary `user://` streamed archive, then
launches the **same main game scene** used by Morrow Coast. This includes
curved intersections, lane markings, stop/yield controls, active traffic,
streamed world collision, driving HUD, minimap/atlas, vehicle selection,
audio, effects, settings, and mapped races/eligible dealerships. Only
Morrow-specific races and default showroom locations are omitted when no
matching content exists on the custom map. Python 3 is needed locally for
the same junction baker used by the regular world build. No source world
or playable Morrow Coast archive is overwritten; the playtest uses a separate
in-memory economy, so it does not update career balances, XP or ownership.
Use **Return to Map Editor** or **F6** to return to the same authored map
and camera view. **Esc** now opens the full normal pause/settings menu.
## Publish a custom map as the real game world

The **Game World / Publish** section in the standalone Map Builder is
separate from both **Save to Game (Ctrl+S)** and **Test Drive (F6)**.

1. Create or select your custom map in the saved-map selector. Build roads,
   scenery, events and interactions. Place **exactly one Player Spawn marker on a
   drivable road**. Test it using F6 first.
2. Click **Build Game World...** in the tool sidebar and confirm. The editor
   saves the current map, validates its geometry and event/marker links, checks
   that the player spawn sits on the road, verifies referenced in-project
   artwork, and runs the production junction/streaming-world compiler.
3. The publisher writes a versioned, **immutable compiled archive** and an
   editable source snapshot into `worlds/published/`. Only after those files
   exist does it switch `worlds/active-world.json` to the newly built map.
   Previous selections are backed up under
   `user://streetbound-maps/publish-backups/`.
4. Return to the title screen and select **PLAY**. The published map is now the
   normal game world with live traffic, your race progression, garages,
   dealerships, waypoints, fast travel, actual vehicle physics and **persistent**
   career rewards. Custom Test Drive still runs in an isolated save sandbox.
   Default Morrow Coast races and fixed facilities are not spawned off-map.
5. Click **Open Published Source...** to reimport the editable, checked-in
   source into the map selector on another development machine. This does not
   overwrite a different local draft with the same filename.
6. Click **Restore Morrow Coast...** to switch PLAY back without erasing the
   published archives or your saved custom map.

The publish command requires Python 3 (Windows: Python launcher `py -3`).
It writes into the **local development project**, not into an installed game's
read-only executable. **Commit `worlds/active-world.json` and the referenced
`worlds/published/*.world.json` files to Git before exporting/releasing** so the
published world is included in the shipped build. Referenced custom scenery
artwork must already live under `assets/` and must also be committed. Map
source snapshots are packaged alongside the compiled world, but player saves,
temporary Test Drive archives and Morrow Coast's original world data are never
overwritten. Failure to validate/build leaves the active game-world selection
unchanged; the game itself falls back to the original world if an active
published archive is unreadable or fails its runtime audit.

For scripted builds, the same operation is available from the repository root:

```sh
python tools/publish_custom_world.py --project . --source /path/to/saved-map.world.json --backup-dir /path/to/backups
python tools/publish_custom_world.py --project . --restore --backup-dir /path/to/backups
```

The standalone editor reloads the rebuilt world automatically and retains the
camera position. In the free-roam editor, use **Reload World** after saving.
Traffic lane guides regenerate in the background when roads move, bend, change
width/lane count, or are created. Undo restores the previous guides. Both editors
keep traffic on the right and fit lane positions inside single and odd lane-count
roads. The saved game uses the production junction geometry, including stop/yield
controls; Save to Game rebuilds that final result. Finish or cancel a gesture
before saving or leaving.

Junctions automatically draw approach markings, crossing paint, applicable
stop/yield signs, and decorative traffic-light fixtures. All signal lenses are
dark and neutral: there are no signal phases, timers, or new AI traffic rules.

Committed unsaved changes in the standalone editor have a local recovery copy,
restored only against the same source and world revision. **Discard** clears
the draft and recovery copy. Keep the editor open while saving. **Test Drive**
opens Morrow Coast after saving or discarding its standalone edits, or saves
and opens the selected custom map in isolated drive mode.

## Career events and gameplay markers

**Create a race:** In the native Map Builder select **Street races & routes**,
place the start and checkpoints on connected roads, then press Enter. The
**Edit Race** dialog opens with two tabs. In **Race Setup**, choose
point-to-point, circuit, or time trial, opponent count/vehicle pool and repeat
cash/driver XP/car XP rewards. In **Career & Unlocks**, choose category and
difficulty, minimum driver/car level, eligible player vehicles, prior races
that must be won, repeatability, and a one-time first-win bonus.
Acyclic prerequisites and referenced IDs are checked before saving. Locked
events still appear on the Events page with their restrictions; successful
wins unlock downstream races and persist completion counts by map and race ID.
The same race in a different named map does not share completion history.

**Create a game marker:** Choose **Game marker**, select a kind and click
the map. The **Edit Game Marker** dialog opens immediately. It can also be
opened for a previously placed marker with **Edit Selected Marker**.
Configure a label/description, interaction radius, availability, required
race victory, and appropriate linked race or dealership. Only one player
spawn may exist in each map. **Mission** markers start their linked race;
**garage** markers access the real owned vehicle selector; **dealership**
markers use the existing forecourt/slow-driving checks; **fast travel** is
available between unlocked road-safe stations when stationary;
**fuel/service** refills installed nitrous; **traffic spawn** markers bias
real traffic spawning toward an authored neighborhood; custom and
checkpoint markers show map information or route to linked events.

For a staged world, first create the races and dealerships and *then* link
markers to their IDs. Rename names freely, but keep the underlying IDs
stable once the game ships because save progression is keyed to them.
Test Drive runs the complete gameplay path but never updates career saves.
Custom maps still require the separate production-world publishing workflow
before they can replace Morrow Coast as the shipped default.

## Browser editor

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

**Session recovery:** Refreshing restores unfinished editing sessions, including
the map view and the game revision they were based on. Ctrl+S saves the current
property field too. Finish or cancel a shape before saving. Game loads and
rebuilds temporarily pause editing; failed rebuilds keep your draft.

**Terrain materials:** Grass, forest floor, exposed rock, sand, water, crop rows,
urban ground and loose surfaces have distinct textured previews. Patterns are
cached and anchored in world space, so moving or resizing regions does not
stretch them. The game uses corresponding procedural materials with animated
water and relief lighting. Fine detail fades at distant zoom; map geometry,
surface grip and collisions are unchanged. No world rebake is needed.

**Building folders:** Launch `Start Map Editor.cmd` to automatically discover
PNG, WebP and SVG artwork in `assets/Buildings/`, including subfolders. New files
appear in the Buildings asset browser within a few seconds; **Refresh folders**
rescans immediately. Names come from filenames. Placed objects retain their
file references, aspect ratio and collision footprint when saved or reopened.
Godot ZIP exports include the used images. Keep files at their original paths;
if a used image is missing, Save to Game reports it instead of changing the art.

**Supplied sprite sheets:** All six PNGs in
`assets/Map Building Assets/Sprite Sheets/` have matching `.sheet.json` files
defining **271 individual objects**. In the in-game editor, choose **Scenery →
Sprite sheets**, then search for pallets, cones, fuel islands, garden props,
plants, rocks or tyre marks. The regular Nature, Industrial, Roadside and
Ground decals filters also include them. Each item has its own saved ID, pixel
region, size in metres and collision setting. Several sprites can share one
source texture without switching crops when moved, resized or reopened.
Foliage and ground details are non-solid; equipment and other solid props have
matching footprints. Runtime shadows use the same selected crop.

The source PNGs and their transparency are preserved. Region metadata supports
the irregular packing in these sheets; a uniform grid would cut many objects
apart. Keep each `.sheet.json` alongside its PNG for authoring and baking.
New sheets can use the same named-region format (or a `grid` definition for
uniform sheets). Existing whole-sheet references remain valid. The checked-in
definitions can be regenerated with `python tools/configure_map_sprite_sheets.py`.

**Regression checks:** Run `node --test map-editor/tests/*.test.mjs` for editor
checks. Run `python tests/morrow_rebuild_stability_test.py` for two real production
bakes in an isolated temporary copy. It verifies stable roads, widths, scenery,
coastal edits and custom checkpoints without modifying the playable map.

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
