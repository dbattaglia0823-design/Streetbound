extends SceneTree
## F4-only outlines and spatial tooling share the same geometry as real roads.
## The API is intentionally read-only: it must not alter vehicle collisions.
const Walkways = preload("res://scripts/world/urban_walkways.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(name: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL", name, detail])
	if not passed:
		failures.append(name)

func vec(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))

func run() -> void:
	print("GEOMETRY STAGE 1: instantiate main")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var world: MorrowCoast = main.ground
	var vehicle: VehicleController2D = main.vehicle
	vehicle.set_physics_process(false)
	check("inspector_is_off_by_default", not world.debug_geometry_enabled and
		not world.debug_hud.visible)
	var first: Node2D = world.chunks.values()[0]
	var overlay: Node2D = first.get_node_or_null("GeometryOverlay")
	check("chunk_has_invisible_boundary_layer", overlay != null)
	if overlay == null:
		quit(1)
		return
	check("hidden_overlay_has_no_cached_draw_geometry",
		not overlay.visible and overlay.cached_features.is_empty(),
		overlay.cached_features.size())

	var first_urban: Dictionary = {}
	for road in world.data.roads:
		if road.kind in ["local", "arterial"] and road.points.size() > 5:
			first_urban = road
			break
	check("urban_road_available", not first_urban.is_empty())
	if first_urban.is_empty():
		quit(1)
		return
	var a := vec(first_urban.points[3])
	var b := vec(first_urban.points[4])
	var along := (b-a).normalized()
	var mid := (a+b)*0.5
	var road_pos := mid * 20.0
	print("GEOMETRY STAGE 2: road query")
	var info: Dictionary = world.geometry_at(road_pos)
	var surface: Dictionary = world.surface_at(road_pos)
	check("geometry_reports_actual_physical_surface",
		info.surface == surface.name and is_equal_approx(float(info.grip), float(surface.grip)),
		[info.surface, surface.name])
	check("road_query_has_nearest_geometry",
		info.has("road_id") and info.has("road_name") and
		info.has("distance_to_road_edge_m") and float(info.distance_to_road_edge_m) <= 0.1,
		info)
	var nearest: Dictionary = world.nearest_road_at(road_pos)
	check("nearest_road_returns_tangent",
		bool(nearest.get("found",false)) and
		(nearest.tangent as Vector2).length_squared() > 0.9 and
		nearest.has("lateral_offset_m"),
		nearest.get("road_name","none"))
	check("offworld_road_query_is_empty",
		world.nearest_road_at(Vector2(-50000.0,-50000.0)).is_empty())
	check("building_inside_road_rejected",
		not bool(world.can_place_at(road_pos, 2.0, 1.0).clear),
		world.can_place_at(road_pos, 2.0, 1.0).reason)

	var urban_point := road_pos
	print("GEOMETRY STAGE 3: stream urban")
	world.stream_at(urban_point)
	while not world.pending.is_empty():
		world._build_chunk(world.pending.pop_front())
	var road_cell := Vector2i((urban_point / 20.0 / world.chunk_m).floor())
	check("road_cell_loaded",world.chunks.has(road_cell),road_cell)
	if world.chunks.has(road_cell):
		var chunk: Node2D = world.chunks[road_cell]
		var dev: Node2D = chunk.get_node("GeometryOverlay")
		check("debug_is_still_hidden_in_new_chunk",
			not dev.visible and dev.cached_features.is_empty())
		print("GEOMETRY STAGE 4: enable overlay")
		world.set_geometry_debug(true)
		check("debug_only_visible_on_request",
			dev.visible and world.debug_hud.visible and world.debug_geometry_enabled)
		print("GEOMETRY STAGE 5: cache outline paths")
		var features: Array[Dictionary] = dev.features()
		print("GEOMETRY STAGE 5b: created %d geometry features" % features.size())
		var road_edges := 0
		var sidewalk_edges := 0
		var junctions := 0
		var obstacle_bounds := 0
		var terrain_bounds := 0
		for f in features:
			if f.kind == "road_edge": road_edges += 1
			if f.kind == "sidewalk_outer": sidewalk_edges += 1
			if f.kind == "junction": junctions += 1
			if f.kind == "obstacle": obstacle_bounds += 1
			if str(f.kind).begins_with("terrain"): terrain_bounds += 1
		check("both_road_edges_are_metadata",road_edges >= 2,road_edges)
		check("both_urban_sidewalk_edges_are_metadata",sidewalk_edges >= 2,sidewalk_edges)
		check("invisible_terrain_and_obstacle_outline_support",
			terrain_bounds > 0 or obstacle_bounds > 0,
			[terrain_bounds, obstacle_bounds])
		var matched := false
		for batch in chunk.road_batches:
			if batch.road.kind not in ["local","arterial"]:
				continue
			var expected := Walkways.urban_sidewalk_outer(
				batch.path, float(batch.road.width)*20.0, 1.0)
			for feature in features:
				if feature.kind != "sidewalk_outer" or int(feature.source_id) != int(batch.road.id) or int(feature.side) != 1:
					continue
				var actual: PackedVector2Array = feature.points
				if actual.size() != expected.size():
					continue
				matched = actual[0].is_equal_approx(expected[0]) and actual[-1].is_equal_approx(expected[-1])
				if matched: break
			if matched: break
		check("outline_matches_actual_rendered_sidewalk_offset",matched)
		print("GEOMETRY STAGE 6: disable overlay")
		world.set_geometry_debug(false)
		check("toggle_hides_geometry_without_dropping_gameplay",
			not dev.visible and not world.debug_hud.visible and world.geometry_at(road_pos).surface == surface.name)
		check("debug_data_remains_cached_for_repeated_toggling", not dev.cached_features.is_empty())

	# Verify all beach boardwalk edge metadata appears in a streamed coast
	# chunk and the placement helper protects a future pedestrian promenade.
	if world.boardwalk_path.size() >= 4:
		var shore_m: Vector2 = world.boardwalk_path[int(world.boardwalk_path.size()/2)]
		var shore_px := shore_m * 20.0
		print("GEOMETRY STAGE 7: stream boardwalk")
		world.stream_at(shore_px)
		while not world.pending.is_empty():
			world._build_chunk(world.pending.pop_front())
		var coast_cell := Vector2i((shore_m/world.chunk_m).floor())
		if world.chunks.has(coast_cell):
			var coast_overlay: Node2D = world.chunks[coast_cell].get_node("GeometryOverlay")
			var features: Array[Dictionary] = coast_overlay.features()
			var deck_edges := 0
			var deck_centers := 0
			for feature in features:
				if feature.kind == "boardwalk_edge": deck_edges += 1
				if feature.kind == "boardwalk_center": deck_centers += 1
			check("boardwalk_both_edges_available",deck_edges >= 2 and deck_centers >= 1,
				[deck_edges,deck_centers])
		print("GEOMETRY STAGE 8: shore placement")
		var reserved: Dictionary = world.can_place_at(shore_px,1.0,0.0)
		check("map_object_placement_keeps_boardwalk_clear",not reserved.clear,reserved.reason)
		var found: Dictionary = world.geometry_at(shore_px)
		check("boardwalk_region_or_road_crossing_identified",
			found.region in ["boardwalk","road","sidewalk","intersection"], found.region)

	# Developer overlays don't affect static collision, vehicle input or
	# the existing world streaming cap.
	check("geometry_preview_does_not_create_colliders",
		not overlay is CollisionObject2D)
	check("chunk_streaming_still_bounded",world.chunks.size() <= 25,world.chunks.size())
	print("MAP GEOMETRY TOOL TESTS: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
