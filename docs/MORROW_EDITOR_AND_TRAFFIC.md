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
`assets/Traffic Vehicles/` instead of the generic polygon bodies. Each
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
