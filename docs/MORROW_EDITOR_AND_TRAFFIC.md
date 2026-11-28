# Morrow Coast editor-to-game bridge and traffic patterns

## Edit the real game world

1. Start map-editor/Start Map Editor.cmd from your local Streetbound checkout.
2. Choose **Edit Morrow Coast**. This reads the actual playable streamed-world
   JSON and imports authored road anchor points, terrain masks, landmarks and
   player spawn into the World Forge v2 editor.
3. Modify existing roads or add connected roads. Enable Traffic lanes / travel
   direction to inspect the directional lane overlays. Use Map health to check.
4. Save Morrow edits as map-editor/maps/morrow-coast.edits.world.json. Chrome
   and Edge provide a browser Save dialog; other browsers download the file.
5. Run tools/Rebuild Morrow Coast.cmd (Python 3) or the GitHub Actions manual
   Morrow Coast World Rebake workflow to regenerate game data and overview.
6. Commit the editable overlay and generated worlds files together, then
   launch Godot and review actual roads/sidewalks and traffic. F4 shows map
   boundaries and F6 shows the actual baked lane network.

World coordinates are in metres in the editor and sampled world; Godot
uses 20 pixels per metre. Edits never overwrite runtime JSON while drawing.
Deleting original roads fails validation; new roads must connect. Shared
named endpoints propagate together. Unchanged high-detail coastal polygons
are protected from the editor's simplified preview geometry.
Scenery is generated during baking and is not yet editable individually.

## Road elevation

Select an existing road in either Map Builder and apply start and end layers.
[Ramp length, road connectivity, and the elevation test fixture](ROAD_ELEVATION.md)
describe the elevation preview and the existing save and rebake paths.

## Directed ambient traffic

Based on the baked road centerlines and junction approach metadata,
the game constructs directional lane edges and curved intersection links.
Right-hand traffic has one lane per direction on normal streets and two
on highways. Road-type speed limits: local 36, arterial 51, highway 82,
rural 60, and mountain 34 km/h. Regular traffic excludes gravel/dirt,
driveways and racing tracks. Lane-specific turn rules, stop/yield dwell,
junction reservations, vehicle-following distance and player awareness
provide a baseline flow.

Traffic is spawned only near the player with distance/headway checks
and despawned outside the active radius. Default cap is 16 cosmetic
noncollidable traffic vehicles, intentionally isolated from the existing
player handling tests. An eventual collision/damage system is separate.
Press **F5** to toggle ambient traffic safely (turning it off clears cars),
and **F6** to reveal the real junction/lane graph during drive testing.

This first iteration does not promise signal timing, pathfinding to
specific destinations, congestion-aware rerouting or traffic collisions.

## References

- SUMO road network lanes, directed edges, junction connections:
  https://sumo.dlr.de/docs/Networks/SUMO_Road_Networks.html
- SUMO right-of-way and junction controls:
  https://sumo.dlr.de/docs/Networks/PlainXML.html
- Godot Road Generator neighbor-connected lane path design:
  https://github.com/TheDuckCow/godot-road-generator

No external project source code was copied.


## Traffic artwork, contact and road recovery

Ambient traffic now uses the **10 existing PNG car models** from
`assets/Vehicles/Traffic Vehicles/` instead of the generic polygon bodies. Each
vehicle gets a scaled, cropped top-down sprite and its own collision shape.
The player can hit traffic cars, and contact supplies a physically bounded
knockback impulse. AI cars remain collidable during recovery.

After a crash, the traffic car remains at its new displaced location and
searches the closest suitable *directed* lane in the baked Morrow road graph.
It then steers back at low speed, avoiding reversing into oncoming lanes or
teleporting through scenery. Once position and heading are aligned with the
road, normal intersection routing resumes. Traffic does not keep making a
simulated crash forever if the player has driven far away.

The traffic pool remains capped at 16 cars; the artwork is shared between
cars and import cropping is cached per model. If a PNG is missing, a
small procedural backup body remains visible as a diagnostic fallback.

## Responsive automatic transmission

Automatic changes now have a short ~85 ms torque interruption rather than
using the longer manual shift duration. Switching safely between reverse and
Drive reselects first gear immediately and clears any previous shift timer.
Entering reverse from a near stop now requires a shorter, deliberate brake
hold, while switching from a fast reverse speed still requires slowing down.
Manual gear changes keep their previous shift duration.

Use F5 to disable traffic or F6 to inspect lane routes while checking crash
recovery in-game. Collision reaction and geometry are automatically verified
by `tests/traffic_impact_recovery_test.gd`; transmission behavior is checked
by `tests/automatic_shift_response_test.gd`.

## Reusable environment presets and Morrow Coast integration

The browser Map Builder includes five one-click environment kits, each
applied as a single Undo operation:

- **Street furniture:** Lamps and signs following the selected city or
  country road, including its bends and both road edges.
- **Parking + access:** An asphalt access road joins the nearest street,
  with a parking lot and dedicated lighting.
- **Forest and coastal:** Repaint a selected dry terrain region and scatter
  vegetation while avoiding roads and occupied space.
- **Industrial:** Place compatible warehouses, signs and streetlights.

Editor Map Health now warns about unusual building scale, crowded building
footprints and garages or parking lots without a nearby vehicle route.

### Applying authored scenery to the real Morrow Coast

The rebake importer validates and includes up to 200 new editor-authored
props (parking, lighting, buildings, vegetation and infrastructure). These
are not copied over the original production map: the full baker regenerates
collisions, streaming chunks and procedural scenery. Supported authored
props are tagged with stable IDs and reappear as editable objects when the
map is reopened. Unchanged procedural objects remain source-owned.

Choose **Edit Morrow Coast**, apply a preset, **Save Morrow edits**, then
run `tools/Rebuild Morrow Coast.cmd` or the documented GitHub rebake workflow.
Custom embedded PNG assets are not baked; use source-controlled models.

### Playable-world visual improvements

Street furniture, benches, signs and rural reflectors follow sampled road
paths. Urban utility covers and drains, service building fascia signs,
parking driveway openings, warmer shadows and small biome-specific ground
details improve cohesion without altering road grip or traffic lanes.
Street furniture uses a single cached canvas per streamed chunk, not a
new live physics body for every pole. It is decorative, not collidable.

Validation: `map-editor/tests/environment-presets.test.mjs`,
`tests/morrow_environment_props_test.py` and
`tests/morrow_environment_visual_test.gd`.

### Named traffic artwork

The ambient and parked vehicle renderers share `TrafficCar.MODEL_PATHS`.
The existing model slot order is preserved with the current filenames:
- 1. `Electric Traffic.png`
- 2. `Car1.png`
- 3. `Sedan.png`
- 4. `SportSUV.png`
- 5. `SUV.png`
- 6. `Minivan.png`
- 7. `Van.png`
- 8. `Taxi.png`
- 9. `Pickup Truck.png`
- 10. `Box Truck.png`

All ten paths must resolve to imported textures; the traffic impact/recovery test
checks the exact paths, rendered texture identity, alpha bounds and collision.

## On-ramp road type

Choose **On-ramp** in the road type selector (browser or native editor). Draw a paved, single-lane road in its intended travel direction, ending on the centerline of an uninterrupted through road. Approach from the right at a shallow 5–45 degree angle. The entrance can join an ordinary intersection; the final merge requires an interior through-road point, not a multi-road junction or an opposing lane. A successful bake produces a directional merge with a yield-controlled ramp and continuing through lanes, no traffic signals or crosswalk at the merge, and outside-lane-only routing. Invalid or disconnected ramp ends reject the bake with an explanation. Existing roads and junctions are unchanged unless explicitly edited. This is an at-grade ramp; elevation and dedicated acceleration-lane extensions are separate work. Preview and full-game behavior require visual and traffic playtesting.

### Swap existing connections

Select the branch road in either editor and use **Start connection** or **End connection** to select Automatic, Intersection, or On-ramp. Each end is independent, persisted in the source JSON, and undoable. Existing road class, dimensions, control points and other junctions are untouched. Explicit overrides accept a right-angle T as a yield-only merge; a gently curved approach is preferable for highway-speed driving. An ordinary road remains two-way along its existing length, but its selected merge admits only incoming branch traffic into the outside through lane. Three-arm geometry is required: a four-way crossing or disconnected end must first be reshaped or split into a valid T. The baker rejects invalid overrides rather than silently converting them. Use Automatic to clear the override; an authored one-way On-ramp road still defaults to merging at its final point. Rebuild/Test Drive to apply to gameplay.


Road artwork refresh: native draft roads share the game's lane-paint planner; browser previews use matching metric proportions and colors. Fine aggregate is game-shader-only. No rebake of stock road geometry required.


## Gameplay authoring (Phase 5)

The native World settings tab offers Gameplay authoring: generate a single-level directed-lane time trial, link existing contract markers, and inspect source coverage and estimated chunk load. Coverage uses 800 m straight-line distance from occupied road cells; heat is a relative estimate from authored scenery, road length and available junction approaches, not measured frame time. Double-click a report row to inspect the cell. Ctrl+F6 over the map requests a temporary Test Drive spawn; explicitly choose a road level for elevated pavement. Unsupported elevated spawn positions retain the normal spawn. No authored player spawn is changed. Mixed-grade draft route generation is not supported. Godot CI and visual verification are pending.

Custom maps also have Traffic / police districts and Intersection controls. District rectangles use metres, are undoable, and later overlaps take precedence. Traffic density scales the local vehicle budget (0–200%); zero prevents new spawns in that zone. Vehicle groups select existing civilian models; speed caps apply to ambient traffic; patrol interval zero disables new patrols and response capacity scales pursuit slots. Intersection rules bind to an existing non-merge junction on the requested level within 8 m during bake. They support all-way stop, yield, sequential signal phases (8 seconds green, 2 seconds all-red) and uncontrolled operation with allowed turn directions. They affect AI routing and driving, not player law enforcement; signal fixture lenses remain static. Rebuild or Test Drive after changes; stock-map authoring and live draft traffic-control preview are not supported. Existing custom maps without these fields retain the default behavior.

### Integration follow-up

Custom route generation now compiles the exact source draft to a private scratch archive, caches the graph by geometry/control inputs and preserves mixed-grade checkpoints. Morrow Coast uses its current baked graph when intersection overrides match the saved version. District and intersection controls also persist through browser normalization and the Morrow rebake; lane selectors restrict turns on a chosen approach, and signal lenses use the traffic clock. New contract locations and offers commit together. Test Drive collects real per-cell CPU chunk-build measurements, frame and process samples, and draw-call peaks; the editor only shows a matching source revision. These measurements are not isolated GPU execution times. No automatic hardware performance guarantee or visual validation is implied.

## Advanced world construction (Phase 7)

Open **Build city** and choose Advanced neighborhood. The seeded generator produces variable-width blocks around wider central avenues, frontage-oriented houses, shops, warehouses and downtown buildings, editable terrain parcels, optional park trees/paths, and commercial parking lots with service-road access. Choose mixed use or a single district style, 2–8 blocks per axis, 120–300 m nominal spacing, and a 0–22% spacing variation. Optional sidewalks leave driveway openings. Existing props/roads, authored gameplay locations and restricted terrain block generation; Morrow requires a connected endpoint. All objects are previewed and applied as one undoable transaction. Artwork uses existing project files with atlas fallback.

Directional diamond is a separate custom-map template with an elevated four-lane highway, ground-level cross street, two one-way exits and two one-way entrances with true yield merges. Exits use ordinary T-junction routing, not dedicated highway divergence logic. Both advanced custom-map modes require a successful scratch production bake before Apply. Morrow neighborhoods use the normal Morrow rebake after Apply. No shipped source or archive is modified by preflight. The existing compiler and incremental Test Drive remain authoritative. Tests cover deterministic plans, occupancy/capacity, undo and real compiler acceptance. CI and visual/physical playtesting pending.

### Per-asset draw order (Z)

Select an ordinary placed scenery asset and change **Draw order (Z)** in the Inspector in either Map Builder. Zero preserves the original rendering category; positive values place sprites in higher Canvas Z batches and negative values move them lower. Values are integer -5 to +10. This is a per-instance visual property, not road elevation, a physical height, or a named workspace layer. It persists through source saves and both world compilers and can be undone. Sidewalk and guardrail paths retain their dedicated rendering/clip passes. Parking pavement retains its normal under-road pass at zero, but an explicit nonzero value uses the common scenery Z band. Negative layers can appear behind road paint and positive layers can cover vehicles, depending on the selected Z value. Browser preview orders scenery but does not reproduce all Godot render passes. Live Godot overlap and chunk-boundary verification remain pending.

Terrain regions also have **Draw order (Z)** in the Terrain Footprint inspector (native) or Terrain inspector (browser). The signed -5 to +10 value sorts painted terrain against other terrain; ties preserve source order. The map base remains underneath all painted regions. Both compilers preserve the value in the source terrain and sort clipped chunk ground polygons consistently. This is not physical elevation or collision priority; roads, props, solid mountain artwork and special water/relief passes keep their existing rendering categories. The native Morrow draft overlays are approximate until Apply/rebake.

Roads also expose **Draw order (Z)** at the top of both inspectors. Signed -5 to +10 values persist through source saves and both compilers; zero preserves the default pavement passes. Explicit groups paint their pavement and markings before or after the default group. Road draw order is visual, relative to other roads on the same physical elevation; junctions, bridge structures, jumps, road connectivity and collisions keep their dedicated passes. Native draft previews are approximate against unedited baked roads until Apply. Streamed chunk edges require visual verification.


## Selected marker interaction overlays

Select a gameplay marker to see its actual metre-space interaction radius, rather than the constant-screen-size picking icon. Ordinary markers share their runtime radius helper; linked robbery and contract destinations use the configured offer arrival radius (multiple distinct rings when necessary). Spawn/home/traffic markers and unlinked destinations do not acquire fictitious trigger areas. Native race gates use start radius for staging and checkpoint radius for subsequent gates; circuit start/finish can display both. Selecting a linked native dealership marker also highlights its actual rectangular browsing forecourt. The browser shows marker prompt and arrival ranges; physical dealership forecourts and native race gate selection remain native-editor features. Road Points mode keeps unselected anchors neutral; only the selected road point has the active highlight. Overlays are editor-only and do not modify gameplay reach, speed restrictions or collisions. CI and visual confirmation pending.


## Map Builder performance pass

World settings now include **Map Builder Performance**: keep recent detail tiles, adaptive tile streaming, optimize live drag previews, show performance statistics, and the per-frame tile-build budget. Visible detail tiles remain capped at 64, with up to 48 additional hidden collision-free warm tiles; revisit or zoom changes reuse them. The adaptive budget is a soft CPU limit between tile builds, not a guarantee that a single tile cannot exceed it. All warm tiles participate in layer/road/scenery/mountain invalidation. Unchanged cell coverage skips queue reconstruction. One clean full-map image can survive scene transitions within the running game; the real overview rebuilds progressively on a warm hit, and no dirty or masked view is cached. Cold first-open world/source parsing remains synchronous. No persistent disk atlas is used, avoiding stale artwork after game updates.

Live road/region/race drags use the existing source validation/connected geometry without creating temporary undo snapshots or refreshing unrelated inspector/list/recovery/traffic work. Full authoring refresh still runs when a drag commits or cancels; bridge topology is finalized then. Original lookup dictionaries, viewport culling and a revision-keyed scenery-picking grid preserve exact hit tests. Mountain colliders and custom terrain meshes stay intact for unrelated edits. Asset catalog rescans are less frequent; manual Refresh assets remains immediate. Performance statistics expose actual open/refresh/drag durations, FPS, tile counts, cache hits and build time. No graphics quality reduction or global FPS cap is applied.

Custom Test Drive displays progress while the existing production compiler runs on a worker, verifies source SHA before launching, and can reuse an identical checksum-verified archive rather than reconstructing scenery. Changed source falls back to the existing geometry/scenery rebuild path; corrupt cache falls back to a complete bake. Publishing and Morrow Save to Game retain their full transactional validation and rollback; partial authoritative rebakes are not implemented because junctions and dependent geometry span cells. Regression assertions cover warm tiles, drag history, unchanged terrain and exact/corrupt cache cases. Actual frame-time and startup improvements require CI and GPU/hardware profiling.


## Standalone map artwork and stale Test Drive references

Map Builder and runtime scenery now load complete individual PNG/WebP/SVG assets, rather than the old scenery sheet or cropped project-sheet entries. Legacy built-in IDs resolve to existing individual buildings and standalone nature SVGs. Legacy `Buildings/...` paths still resolve to the moved Buildings folder. Catalogs refuse sheet folders, sheet manifests and cropped regions. On opening a saved custom map, the native editor removes obsolete/missing project placements and sheet references from its working draft, reports the removal count, and marks it dirty; normal Save retains the existing automatic backup. Custom Test Drive compilation independently cleans a detached copy, drops stale placements before indexing scenery/collision, and reports their IDs; the source file is never rewritten by the compiler. Older compiled chunks skip missing explicit artwork, including their collision. The browser preview uses standalone artwork and current traffic filenames; it rejects retired crop references. Existing valid placements, roads, terrain, races and spawn markers remain intact. No speculative remapping of deleted sheet regions to unrelated images is performed. The actual local City Center save was not available for inspection; verify by reopening it and running Test Drive after updating. CI pending.


### Exact filename recovery (PR #238 follow-up)

The runtime locator checks the original path first, then a validated remembered alias, then indexes the asset folder by exact case-sensitive filename including extension. Successful relocations persist under `user://streetbound-asset-locations.cfg`; stale aliases are invalidated if their destination disappears. The editor invalidates the search index when its asset catalog changes. Map artwork searches only the approved map asset roots (`assets/Buildings`, `assets/Map Building Assets`); player and ambient/patrol car artwork searches the full assets tree. Retired sheets are excluded. Multiple matches without a valid known path are reported rather than guessed. Missing individual placements are retained in custom editor drafts, and Test Drive reports the missing or ambiguous filename instead of silently deleting it. Native custom map loading and placement canonicalize resolved paths/IDs; explicit Save uses the existing backup transaction. Python baking resolves the canonical path before writing the compiled archive, without rewriting source. The browser asset server also resolves relocated map artwork. Hard-coded engine preloads and other unrelated asset consumers are outside this pass. Cache and actual runtime verification pending CI.
