# Morrow Coast editable source overlays

Use Map Builder > **Edit Morrow Coast**, then Save Morrow edits into
this folder as morrow-coast.edits.world.json.

This World Forge v2 authoring file is NOT the streamed game world.
Run tools/Rebuild Morrow Coast.cmd with Python 3 or use the manual
Morrow Coast World Rebake GitHub Actions workflow. The rebake rebuilds
the sampled roads, intersections, surface indices, chunks, terrain masks
and world overview; do not overwrite the original world with source JSON.

Existing road-ID values must stay stable. Deleting a source road is rejected.
New roads must connect to the existing graph or the build fails.
High-detail coast polygons are only changed if their edited version differs.
Procedural props are regenerated and cannot yet be directly edited.
Landmark and player start positions can be moved. Extra traffic/race
markers are preserved for future gameplay systems.
