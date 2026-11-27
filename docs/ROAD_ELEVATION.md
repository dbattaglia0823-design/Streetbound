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

## Individual road-point elevations

In either Map Builder, select a road, expand **Individual point elevations**,
choose a signed layer for every numbered control point, and select **Apply
point elevations**. For example, 0, +1, +1, 0 creates an ascent, a deck and a
descent. The operation retains the original road ID and saves all its heights in one undoable edit. Flat runs retain
their control points. Each changing-grade span must be at least 50 m long and
join adjacent layers. Existing start/end elevation controls continue to work.

The authored road stays a single road object with its original ID and all
control points. Its optional elevation profile stores `point_layers`.
The bake preserves the flattened horizontal spline and derives connected runtime
sections, keeping the source anchors and profile for editor round trips.
Vertical smoothing uses a cubic blend bounded by the existing 12% maximum
grade. A 75 m span per 6 m rise gives zero slope at both ends; shorter
50–75 m spans blend progressively toward the legacy linear grade. Ordinary
legacy ramps retain their previous behavior. Closed variable-height loops
and multi-grade on-ramps are rejected until adjusted. The 180 authored-road
limit is unchanged; derived runtime sections have a separate safety limit.
Point insertion/removal preserves the profile when the resulting grades are
valid; other topology-changing operations may require clearing the profile first.

## Individual elevated race and contract objectives

In the browser's race settings expand **Individual race objective elevations**.
In the native race sidebar select an objective number (1 is the start), set
its road layer, and apply. Each start, checkpoint and finish retains its own
signed layer in the source and archive. The race checks actual vehicle height
within 0.65 m of that layer, rejects airborne vehicles, and routes between
the chosen layers. Start-grid slots must have physical pavement on the start
level. An elevated race cannot begin if a required gate or route is unsupported.

For contracts, select the contract/contact, robbery target or drop-off marker
and set **Objective road layer** in the marker editor. Each marker may use a
different layer. Pickups, timed robbery holds, deliveries and GPS arrivals
require the matching height. The job checks legal graph connectivity before
acceptance. Other service markers such as fuel, garage and fast travel stay
ground-level. Elevated authored races are excluded from online friend races
until the online gate and start-grid protocol supports verified height.

## Driving and boundaries

The controller gets a continuous height and slope from the indexed road
surface. Pavement on the active grade remains selected at an XY overlap.
Entry into a ramp is limited to its mouth. The controller sweeps its
movement against the supported road strip and preserves separate physics
collision bands for stacked decks. Objectives without a configured layer
remain ground-level. Dispatch line of sight and containment
also compare vehicle height.

The road renderer draws deck edges, rails, shadows and supports. The deck
above the player fades while driving below it. A tunnel mouth adds an
embankment and retaining walls at a connected ramp. The interior reveals
a dim road and wall lights when the primary driver descends.

Ambient traffic follows the same grade-aware lane graph. It brakes and
rejoins a lane on its own level after contact. Police use the last confirmed
road layer for pursuit and route ordinary ground-level dispatch through
connected ramps. Open surface-to-tunnel ramps excavate a continuous corridor
from final road width. Streamed terrain, solid mountain art and relief use the
same cutout mask; mountain collision polygons are geometrically subtracted.
Retaining walls protect both surface and first underground collision bands.
The covered end has a surface-only physical cap; the tunnel beneath remains
open. Covered tunnels and deeper ramps retain the surface roof. Ordinary maps
without negative ramps allocate no cutout resources. The bake rejects open
cuts reaching the map edge or water; covered tunnel sections can remain beneath
water. Scenery remains authored rather than being deleted automatically.
Multiplayer friend
replicas receive host-owned signed road height in the existing timestamped
movement history, so remote deck and tunnel drawing order follows the host.
Height is interpolated but not extrapolated; invalid values are rejected and
legacy snapshots default to ground. Local guest pose correction now carries the host's baked road identity and
validates it against the shared pavement before applying the collision band.
Police replica height is carried in the same buffered visual metadata.
Multiplayer jumps and live network validation remain pending. Host simulation
remains authoritative. These new integration changes are awaiting CI.

## Author and test a stunt jump

Select a straight, ground-level paved road in either Map Builder, open
**Stunt jump**, and enable it. The takeoff distance is measured from the
first road point. Use **Launch toward road start** to reverse the direction.
Adjust the ramp length, width, height, launch angle, speed range, and
landing dimensions, then choose **Apply jump**. The colored preview marks
the launch lip, trajectory, and permitted landing. The full Test Drive or
publish bake checks scenery, walls, terrain, map edges, and intersecting
roads. A jump moves and duplicates with its road.

In single-player free roam, cross the lip in the configured direction and
speed range. The controller preserves planar momentum, sweeps its existing
collision shape, and validates the touchdown on the marked runway.
The reset key, throttle, and handbrake cannot change an airborne trajectory.
A blocked or invalid flight recovers at the last clear approach and emits
no successful landing. Launches are limited to the primary free-roam driver
during solo play, with active races, contracts, and police pursuits retaining
their ordinary ground routes.

Open `tests/fixtures/road-jumps.world.json` for the playable ramp and the
overpass and tunnel fixture. Unsafe map cases in
`tests/road_jump_bake_test.py` cover blocking scenery, guardrails, walls,
water, unsafe speed and landing limits, and stacked crossings.

## Reproduce the elevation tests

From the project root, after importing Godot 4.6.3 resources:

```text
python tests/road_elevation_bake_test.py
python tests/road_jump_bake_test.py
node --test map-editor/tests/road-elevation.test.mjs
python tools/build_custom_test_world.py --source tests/fixtures/road-elevation.world.json --output .runtime/road-elevation.stream.json
godot --headless --path . --fixed-fps 120 --script res://tests/road_elevation_graph_test.gd -- res://.runtime/road-elevation.stream.json
godot --headless --path . --fixed-fps 120 --script res://tests/road_elevation_drive_test.gd -- res://.runtime/road-elevation.stream.json
python tools/build_custom_test_world.py --source tests/fixtures/road-jumps.world.json --output .runtime/road-jumps.stream.json
godot --headless --path . --fixed-fps 120 --script res://tests/road_jump_drive_test.gd -- res://.runtime/road-jumps.stream.json
```

The production bake tests also cover an on-ramp overlapping a deck and a
same-layer elevated directional merge. Browser tests check the matching
preview and junction-mode toggle. The fixture includes an overpass, a same-height elevated intersection, a
tunnel, a ground-level intersection, and overlapping endpoints with no road
connection. The drive test uses the real controller and verifies collision
isolation, same-deck impacts, lateral containment, and ground reset.
