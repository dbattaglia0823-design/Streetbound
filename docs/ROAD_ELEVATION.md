# Streetbound road elevation

Roads use the existing metre-space geometry and optional signed layers from
−2 to +2. Each layer represents 6 m of clearance. Roads with matching start
and end layers are level. Use a separate road section for each ramp between
adjacent layers, with at least 50 m of road length per 6 m of rise.

## Author and test a crossing

1. In the browser or native Map Builder, select a road and set **Start layer**
   and **End layer**. Choose **Apply road elevation**. A level +1 road is a
   deck, a level −1 road is a tunnel, and 0 to +1 is an uphill ramp.
2. Connect ramp ends to roads at their matching layer. A crossing on a
   constant-height deck can make an ordinary same-layer intersection.
   Each ramp connects at its two ends. The bake rejects unconnected
   centerline crossings with less than 4.5 m of clearance.
3. Use the browser **Road elevation** filter to select stacked roads. Blue
   strokes mark raised roads. Purple strokes mark tunnels. Dashed strokes
   indicate ramps.
4. Use the existing Test Drive or explicit Morrow Coast rebake workflow. The
   playable Morrow Coast source and baked archive are kept as supplied.

The existing World Forge format stores only the optional road
`elevation` profile with integer `start_layer` and `end_layer`.
The custom-map and Morrow compilers use the same junction bake. Legacy
`grade` still identifies water bridges. Older maps have ground-level roads.

## Driving and boundaries

The controller gets a continuous height and slope from the indexed road
surface. Pavement on the active grade remains selected at an XY overlap.
Entry into a ramp is limited to its mouth. The controller sweeps its
movement against the supported road strip and preserves separate physics
collision bands for stacked decks. Existing authored checkpoints and
contract stops are ground-level. Dispatch line of sight and containment
also compare vehicle height.

The road renderer draws deck edges, rails, shadows and supports. The deck
above the player fades while driving below it. A tunnel mouth adds an
embankment and retaining walls at a connected ramp. The interior reveals
a dim road and wall lights when the primary driver descends.

Supports and embankments are rendered artwork. Full terrain cutouts,
traffic and police routing on graded roads, grade-aware objective
authoring, jumps, and multiplayer state are pending. Ambient traffic uses
ground lanes in the interim.

## Reproduce the elevation tests

From the project root, after importing Godot 4.6.3 resources:

```text
python tests/road_elevation_bake_test.py
node --test map-editor/tests/road-elevation.test.mjs
python tools/build_custom_test_world.py --source tests/fixtures/road-elevation.world.json --output .runtime/road-elevation.stream.json
godot --headless --path . --fixed-fps 120 --script res://tests/road_elevation_graph_test.gd -- res://.runtime/road-elevation.stream.json
godot --headless --path . --fixed-fps 120 --script res://tests/road_elevation_drive_test.gd -- res://.runtime/road-elevation.stream.json
```

The fixture includes an overpass, a same-height elevated intersection, a
tunnel, a ground-level intersection, and overlapping endpoints with no road
connection. The drive test uses the real controller and verifies collision
isolation, same-deck impacts, lateral containment, and ground reset.
