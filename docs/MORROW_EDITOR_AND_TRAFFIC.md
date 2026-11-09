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
Press F6 to reveal the real junction/lane graph during drive testing.

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
