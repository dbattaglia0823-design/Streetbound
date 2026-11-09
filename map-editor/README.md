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
