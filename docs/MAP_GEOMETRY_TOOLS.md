# Streetbound: invisible map geometry tools

Streetbound already has a detailed road centerline graph, 64m spatial surface
index, clipped terrain polygons, junction aprons, and static collision shapes.
The new map geometry tools expose those authored boundaries directly rather
than adding a second set of manually placed outlines that would drift from
the artwork or physics.

## F4 developer mode (off by default)

Press **F4** while driving in Morrow Coast to show non-gameplay outlines.
Press F4 again to hide them. The overlay is not persisted to player settings.
The HUD shows the current region, ground type, grip, nearest road, distance
to road edge, and whether a hypothetical 2m radius prop fits at the car.

Color legend:

- Cyan = road edges/centerlines, both sides
- Amber = sidewalks, both sides and their real outer edges
- Pink = exact junction polygons and baked curved curb segments
- Green = boardwalk centerline and two deck edges
- Red = solid props, trees, buildings and guardrail walls
- Neutral gray = land-use terrain boundaries and parking/field parcels

The debug polygons and line buffers are built **lazily**, per visible
streamed 192m world chunk. With F4 off, the overlay nodes remain invisible
and generate no map geometry or GPU draw commands. There are no gameplay
collision shapes in the debug layer. Old chunk data is freed with streaming.

## Read-only geometry API

From a `MorrowCoast` instance, all positions are **world pixels**
(20 pixels/metre). Returned distances are explicitly in metres.

```gdscript
var nearest: Dictionary = world.nearest_road_at(global_position, 15.0)
# keys: found, road_id, road_name, road_kind, road_surface, road_width_m,
# closest_point_px, tangent, normal, lateral_offset_m,
# distance_to_center_m, distance_to_road_edge_m

var info: Dictionary = world.geometry_at(global_position)
# keys: region (road, sidewalk, intersection, boardwalk, terrain etc),
# surface, grip, position_m; also nearest-road fields when found

var placement: Dictionary = world.can_place_at(world_point_px, 3.0, 1.5)
# clear: true/false; reason: road_or_sidewalk / boardwalk / junction /
# obstacle / ocean / water. All radius/buffer arguments are metres.
```

All three APIs are usable whether F4 is showing or not. `surface_at()`
remains the authoritative physics hot-path query; the inspection functions
reuse it but do not alter grip, steering, braking or collision. The nearest-
road helper uses the existing baked 64m segment index; placement validation
uses existing authored junction polygons, the coastline boardwalk and the
world's solid props. It is for editor/tooling placement, not per-frame AI.

The feature builder `MapGeometry.chunk_features(chunk,world)` creates
structured dictionaries with `kind`, local-pixel `points`, `closed`,
`source_id`, and `side`. `source_id` uses world road indices for roads,
and data indices for junctions. Future map editor/export tools can use these
polylines for editable handles, previews, lane routing, pedestrian zones,
road clearance, object snap points, and geometry validation.

## Integrating future maps

Generate the road/sidewalk render and metadata from the same road batch
centerline and width; never hand-maintain a second outline. Add new parcel
and road class types to `map_geometry.gd` and the existing world builder
together. Keep the map measurements in metres; convert to world pixels only
at rendering or vehicle-query boundaries.

## Validation

`tests/map_geometry_tools_test.gd` verifies hidden-by-default behavior,
two-sided sidewalk/road boundaries, matching road offsets, nearest-road
and physics surface metadata, object placement rejection, boardwalk outlines,
and bounded chunk streaming. Existing driving and map regression tests also
run unchanged. F4 screenshots are a useful manual pass at intersections,
tight bends, urban building setbacks and the beach promenade.
