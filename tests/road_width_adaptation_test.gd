extends SceneTree
## Runtime widening must agree with rendering, map, traffic and collision
## without scaling moving cars or relocating source-authored centerlines.
const Widths = preload("res://scripts/world/road_width_adaptation.gd")
const PPM := 20.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, valid: bool, detail: Variant = "") -> void:
	print("%s %s %s" % ["PASS" if valid else "FAIL", label, str(detail)])
	if not valid:
		failures.append(label)


func _run() -> void:
	var source: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://worlds/morrow-coast.world.json"))
	check("world_archive_loaded", not source.is_empty())
	var source_scale := float(source.get("road_width_scale", 1.0))
	var target_factor := 1.10 / source_scale
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var world: MorrowCoast = main.ground
	var car: VehicleController2D = main.vehicle
	car.set_physics_process(false)
	check("exactly_one_road_width_migration",
		is_equal_approx(float(world.data.get("road_width_scale", 0.0)), 1.10))
	var width_valid := true
	var all_centerlines_unchanged := true
	var lane_counts_unchanged := true
	for i in source.roads.size():
		var road: Dictionary = world.data.roads[i]
		var old: Dictionary = source.roads[i]
		width_valid = width_valid and absf(float(road.width) -
			roundf(float(old.width) * target_factor * 1000.0) / 1000.0) < 0.002
		all_centerlines_unchanged = all_centerlines_unchanged and \
			road.points == old.points and road.anchors == old.anchors
		lane_counts_unchanged = lane_counts_unchanged and int(road.lanes) == int(old.lanes)
	check("all_roads_are_exactly_ten_percent_wider",width_valid,
		[world.data.roads.size(), float(world.data.roads[0].width)])
	check("source_centerlines_and_road_endpoints_unchanged",all_centerlines_unchanged)
	check("traffic_lane_counts_unchanged",lane_counts_unchanged)
	var before: Array = []
	for r in world.data.roads:
		before.append(float(r.width))
	Widths.adapt(world.data)
	var not_double := true
	for i in before.size():
		not_double = not_double and is_equal_approx(float(world.data.roads[i].width), before[i])
	check("idempotent_migration_never_scales_again", not_double)
	# Source-wide bridge shoulders and rails follow the enlarged usable road.
	var bridges_valid := true
	for i in source.bridges.size():
		bridges_valid = bridges_valid and absf(float(world.data.bridges[i].width) -
			float(source.bridges[i].width) * target_factor) < 0.002
	check("bridge_decks_and_rails_match_wider_roads", bridges_valid,
		world.data.bridges.size())
	var junctions_valid := true
	for i in source.junctions.size():
		var old: Dictionary = source.junctions[i]
		var current: Dictionary = world.data.junctions[i]
		var radius_factor := 1.05 if source_scale < 1.09 else 1.0
		junctions_valid = junctions_valid and \
			absf(float(current.radius) - float(old.radius) * radius_factor) < 0.005
		for j in old.approaches.size():
			junctions_valid = junctions_valid and absf(
				float(current.approaches[j].width) -
				float(old.approaches[j].width) * target_factor) < 0.005
	check("junction_mouths_and_stop_lines_align_with_road_width", junctions_valid)
	var footprints_valid := true
	var moved_props := 0
	var static_scaled := 0
	var vehicles_unchanged := true
	for i in source.props.size():
		var old: Dictionary = source.props[i]
		var current: Dictionary = world.data.props[i]
		var kind := str(old.kind)
		if current.p != old.p:
			moved_props += 1
		var asset_factor := float(Widths.SCENERY_FACTORS.get(kind, 1.0))
		if source_scale > 1.09:
			asset_factor = 1.0
		if asset_factor < 1.0:
			static_scaled += 1
		if old.has("size") and current.has("size"):
			footprints_valid = footprints_valid and absf(
				float(current.size[0]) - float(old.size[0]) * asset_factor) < 0.01 and \
				absf(float(current.size[1]) - float(old.size[1]) * asset_factor) < 0.01
		if kind == "parked_car" or kind == "garage" or kind == "lot" or kind == "forecourt":
			vehicles_unchanged = vehicles_unchanged and current.size == old.size
	check("smaller_static_building_and_landscape_footprints", footprints_valid,
		static_scaled)
	check("no_scenery_moved_across_old_chunk_stream_boundaries", moved_props == 0)
	check("parked_vehicles_garage_and_parking_aprons_not_shrunk", vehicles_unchanged)
	check("player_vehicle_visual_scale_unchanged", car.scale == Vector2.ONE)
	# The physical road surface must occupy the added 5% on EACH side.
	# Prefer road segments away from junctions and compare only candidates
	# where the sampled road is the nearest one.
	var widened_edge_samples := 0
	var valid_edge_samples := 0
	for road_id in world.data.roads.size():
		if widened_edge_samples >= 45:
			break
		var road: Dictionary = world.data.roads[road_id]
		if str(road.surface) != "ASPHALT" or road.points.size() < 2:
			continue
		var samples: Array = road.points
		var a := Vector2(float(samples[0][0]),float(samples[0][1]))
		var b := Vector2(float(samples[1][0]),float(samples[1][1]))
		if a.distance_to(b) < 2.0:
			continue
		var tangent := (b-a).normalized()
		var old_width := float(source.roads[road_id].width)
		var half_old := old_width * .5
		var half_new := float(road.width) * .5
		if half_new - half_old < 0.25:
			continue
		var sample_m := a.lerp(b, 0.5) + tangent.orthogonal() * (half_new - .08)
		var nearest: Dictionary = world.nearest_road_at(sample_m * PPM, 9.0)
		if nearest.is_empty() or int(nearest.road_id) != road_id:
			continue
		widened_edge_samples += 1
		var hit: Dictionary = world.surface_at(sample_m * PPM)
		if str(hit.get("name", "")) == "ASPHALT" and float(hit.get("grip",0.0)) > .95:
			valid_edge_samples += 1
	check("new_outer_road_edges_have_full_asphalt_grip",
		widened_edge_samples >= 10 and valid_edge_samples >= widened_edge_samples - 2,
		[valid_edge_samples,widened_edge_samples])
	# Both traffic graph and map read the adapted road widths, never a
	# scaled car sprite. Check opposing traffic uses the wider painted lanes.
	var traffic: Node = world.get_node("AmbientTraffic")
	var network: RefCounted = traffic.get("network") as RefCounted
	var network_edges: Array = network.get("edges")
	var width_drives_traffic := false
	for edge in network_edges:
		if bool(edge.connector) or int(edge.road) != 0:
			continue
		if int(edge.lane) != 0 or int(edge.direction) != 1:
			continue
		var point_m: Vector2 = (edge.points as PackedVector2Array)[0] / PPM
		var road: Dictionary = world.data.roads[0]
		var tangent := Vector2(
			float(road.points[1][0]) - float(road.points[0][0]),
			float(road.points[1][1]) - float(road.points[0][1])).normalized()
		var origin := Vector2(float(road.points[0][0]),float(road.points[0][1]))
		var lateral := absf((point_m - origin).cross(tangent))
		width_drives_traffic = absf(lateral - float(road.width) * .25) < 0.5
		break
	check("ambient_traffic_lanes_follow_new_centered_width",width_drives_traffic)
	var original_prop_count := source.props.size()
	check("no_buildings_or_assets_deleted", world.data.props.size() == original_prop_count)
	print("MORROW 10 PERCENT WIDER ROADS: ",
		"PASS" if failures.is_empty() else "FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
