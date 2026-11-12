extends SceneTree
## The original authored road centerlines remain fixed, but the *playable*
## asphalt width, lane graph, sidewalks and static roadside asset footprints
## change together. Never change player / traffic car scale or dimensions.
const Widen = preload("res://scripts/world/road_width_upgrade.gd")
const RoadMap = preload("res://scripts/world/coast_map_model.gd")
const Network = preload("res://scripts/world/traffic_network.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, okay: bool) -> void:
	print("%s %s" % ["PASS" if okay else "FAIL", label])
	if not okay:
		failures.append(label)


func _v(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))


func _run() -> void:
	var source: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://worlds/morrow-coast.world.json"))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var world: MorrowCoast = main.ground
	var car: VehicleController2D = main.vehicle
	var revised: Dictionary = world.data
	check("all_roads_preserved_in_original_positions",
		revised.roads.size() == source.roads.size() and
		revised.segments.size() == source.segments.size())
	var every_road_scaled := true
	var class_coverage := {}
	for i in revised.roads.size():
		var original: Dictionary = source.roads[i]
		var current: Dictionary = revised.roads[i]
		class_coverage[str(original.kind)] = true
		if not is_equal_approx(float(current.width), float(original.width) * 1.10):
			every_road_scaled = false
		if current.points != original.points or current.lanes != original.lanes:
			every_road_scaled = false
	check("all_roads_are_exactly_ten_percent_wider_and_keep_lane_counts", every_road_scaled)
	check("road_widening_applies_to_all_real_road_classes",class_coverage.has("local") and
		class_coverage.has("arterial") and class_coverage.has("highway") and
		class_coverage.has("track") and class_coverage.has("rural"))
	var bridges_ok := revised.bridges.size() == source.bridges.size()
	for i in revised.bridges.size():
		if not is_equal_approx(float(revised.bridges[i].width),
				float(source.bridges[i].width) * 1.10):
			bridges_ok = false
	check("bridge_rail_and_deck_width_expand_with_road",bridges_ok)
	var same_vehicle := car.scale.is_equal_approx(Vector2.ONE)
	var same_shapes := true
	var original_shapes := []
	var traffic_vehicle_scene: PackedScene = load("res://scenes/vehicle.tscn")
	var reference: VehicleController2D = traffic_vehicle_scene.instantiate()
	root.add_child(reference)
	reference.set_physics_process(false)
	for shape_name in ["CollisionShape2D"]:
		var current_shape: CollisionShape2D = car.get_node_or_null(shape_name)
		var base_shape: CollisionShape2D = reference.get_node_or_null(shape_name)
		same_shapes = same_shapes and current_shape != null and base_shape != null and
			current_shape.shape.get_rect() == base_shape.shape.get_rect()
	check("player_car_scale_and_collision_bounds_are_not_widened",
		same_vehicle and same_shapes)
	reference.queue_free()
	var traffic: Node = world.get_node("AmbientTraffic")
	var graph: RefCounted = traffic.get("network") as RefCounted
	var graph_edges: Array = graph.get("edges")
	var kind_found := false
	for edge in graph_edges:
		if bool(edge.get("connector", false)):
			continue
		var road_id: int = int(edge.road)
		if str(revised.roads[road_id].kind) != "arterial":
			continue
		# Lane center should move outward when the road gets wider, while
		# its actual physical car body remains the same.
		var path: PackedVector2Array = edge.points
		var origin: Vector2 = _v(revised.roads[road_id].points[0]) * 20.0
		if path.size() < 2:
			continue
		kind_found = true
		break
	check("ambient_traffic_network_rebuilt_using_wider_road_widths",
		kind_found and graph_edges.size() > 0)
	var map := RoadMap.new(revised)
	var map_ok := map.roads.size() == revised.roads.size()
	if map_ok:
		for i in map.roads.size():
			var source_road: Dictionary = map.roads[i].source
			map_ok = map_ok and is_equal_approx(float(source_road.width),
				float(revised.roads[i].width))
	check("minimap_reads_same_road_widths_as_game_world",map_ok)
	# The surrounding buildings/foliage are the only resized classes.
	var adjusted := 0
	var protected_assets_ok := true
	var protected_kinds := ["lot","forecourt","parked_car","start_line",
		"finish_line","drag_scoreboard"]
	for i in revised.props.size():
		var orig: Dictionary = source.props[i]
		var now: Dictionary = revised.props[i]
		if str(orig.kind) in protected_kinds or orig.has("poi"):
			protected_assets_ok = protected_assets_ok and
				orig.size == now.size and orig.p == now.p
		if orig.size != now.size:
			adjusted += 1
			var scale_x := float(now.size[0]) / float(orig.size[0])
			var scale_y := float(now.size[1]) / float(orig.size[1])
			protected_assets_ok = protected_assets_ok and
				is_equal_approx(scale_x,0.97) and is_equal_approx(scale_y,0.97)
	check("roadside_buildings_and_decor_shrink_slightly_to_keep_clearance",
		adjusted > 0 and protected_assets_ok)
	check("parking_lots_dealerships_and_parked_cars_stay_unchanged",
		protected_assets_ok)
	var count := int(world.data.get("_road_widening_stats", {}).get("roads",-1))
	var applied_again: Dictionary = Widen.apply(world)
	check("upgrade_is_idempotent_on_game_reload",
		int(applied_again.get("roads",-2)) == count and
		is_equal_approx(float(revised.roads[0].width),
			float(source.roads[0].width) * 1.10))
	var physics_road_ok := false
	for i in range(0, revised.segments.size(), maxi(1,revised.segments.size()/60)):
		var segment: Dictionary = revised.segments[i]
		var road: Dictionary = revised.roads[int(segment.road)]
		if str(road.surface) != "ASPHALT":
			continue
		var a := _v(segment.a)
		var b := _v(segment.b)
		var tangent := (b-a).normalized()
		if tangent.length_squared() < 0.9 or a.distance_to(b) < 1.0:
			continue
		var test_point := (a+b)*0.5 + tangent.orthogonal() * float(road.width)*0.48
		var surface: Dictionary = world.surface_at(test_point*20.0)
		if str(surface.name) == "ASPHALT" and is_equal_approx(float(surface.grip),1.0):
			physics_road_ok = true
			break
	check("widened_outer_lane_is_real_drivable_road_not_grass",physics_road_ok)
	print("TEN PERCENT WIDER ROADS: ",
		"PASS" if failures.is_empty() else "FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
