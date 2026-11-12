extends SceneTree
## Race lines reuse the legal traffic graph and remain on usable asphalt.
## No rubber-banding or cross-traffic shortcuts; circuit uses wider pavement.
const RacingLine = preload("res://scripts/world/race_line_builder.gd")
const AIDriver = preload("res://scripts/world/race_ai_driver.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)


func _distance_to_center(point: Vector2, line: PackedVector2Array) -> float:
	var closest := INF
	for i in range(1, line.size()):
		closest = minf(closest, point.distance_to(
			Geometry2D.get_closest_point_to_segment(point, line[i - 1], line[i])))
	return closest


func _run() -> void:
	var synthetic := PackedVector2Array([
		Vector2(0,0), Vector2(60,0), Vector2(120,0),
		Vector2(140,12), Vector2(149,32), Vector2(149,70), Vector2(149,135)])
	var limits := PackedFloat32Array()
	limits.resize(synthetic.size())
	limits.fill(2.2)
	var shaped: PackedVector2Array = RacingLine.make_line(synthetic, limits)
	check("racing_line_is_dense_and_not_a_straight_shortcut", shaped.size() > 45)
	check("long_straights_follow_traffic_lane_center",
		shaped[0].distance_to(synthetic[0]) < 0.01 and
		shaped[5].distance_to(Vector2(20,0)) < 1.0)
	var has_apex := false
	var safe := true
	for i in range(shaped.size()):
		var error := _distance_to_center(shaped[i], synthetic)
		safe = safe and error <= 2.25
		if error > 0.32:
			has_apex = true
	check("corner_has_real_outside_apex_exit_lateral_movement", has_apex)
	check("synthetic_racing_line_never_exceeds_legal_corridor", safe)
	var flat_limits := PackedFloat32Array()
	flat_limits.resize(synthetic.size())
	flat_limits.fill(0.0)
	var center: PackedVector2Array = RacingLine.make_line(synthetic, flat_limits)
	var pure_lane := true
	for p in center:
		pure_lane = pure_lane and _distance_to_center(p, synthetic) < 0.06
	check("zero_available_lane_width_keeps_original_centerline", pure_lane)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var world: MorrowCoast = main.ground
	var player: VehicleController2D = main.vehicle
	player.set_physics_process(false)
	var traffic: Node = world.get_node("AmbientTraffic")
	var network: RefCounted = traffic.get("network") as RefCounted
	var sprint: Node = main.street_race
	check("street_event_instantiated", sprint != null and sprint.get_script() ==
		load("res://scripts/world/larkspur_street_sprint.gd"))
	check("street_race_constructed_from_connected_traffic_edges",
		sprint != null and sprint.available and sprint.edge_ids.size() > 4)
	if sprint == null or not sprint.available:
		print("TRAFFIC-AWARE RACING LINE: FAIL")
		quit(1)
		return
	var legal := true
	var edges: Array = network.get("edges")
	for i in range(1, sprint.edge_ids.size()):
		var from: Dictionary = edges[sprint.edge_ids[i - 1]]
		legal = legal and (from.get("next", []) as Array).has(sprint.edge_ids[i])
	check("street_sprint_only_uses_legal_forward_traffic_graph_links", legal)
	var street_points: PackedVector2Array = sprint.navigation.get("points_m")
	var paved := true
	for i in range(0, street_points.size(), 8):
		paved = paved and str(world.surface_at(street_points[i] * 20.0).name) == "ASPHALT"
	check("street_line_stays_on_authored_asphalt", paved)
	var road_center := PackedVector2Array()
	for edge_id in sprint.edge_ids:
		var e: Dictionary = edges[edge_id]
		var pts: PackedVector2Array = e.points
		for p in pts:
			road_center.append(p / 20.0)
	var lane_safe := true
	var lane_apex := false
	for i in range(0, street_points.size(), 5):
		var error := _distance_to_center(street_points[i], road_center)
		lane_safe = lane_safe and error <= 1.1
		lane_apex = lane_apex or error > 0.12
	check("city_apex_never_enters_opposing_lane", lane_safe)
	check("city_course_uses_racing_line_for_real_turns", lane_apex)
	var invalid_edges: Array[int] = [sprint.edge_ids[0], sprint.edge_ids[0]]
	check("illegal_traffic_sequence_is_refused",
		RacingLine.traffic_line(network, world, invalid_edges).is_empty())
	var circuit: Node = main.circuit_race
	check("existing_circuit_race_remains_available", circuit.available)
	var circuit_points: PackedVector2Array = circuit.navigation.get("points_m")
	var circuit_paved := true
	for i in range(0, circuit_points.size(), 12):
		circuit_paved = circuit_paved and \
			str(world.surface_at(circuit_points[i] * 20.0).name) == "ASPHALT"
	check("circuit_racing_line_remains_on_pavement", circuit_paved)
	var driver := AIDriver.new()
	root.add_child(driver)
	driver.set_physics_process(false)
	driver.setup_navigation(player, sprint.navigation)
	check("racing_AI_can_use_exact_same_waypoints_as_map",
		driver.navigation == sprint.navigation and
		driver.route.size() == street_points.size())
	# A route-specific speed envelope does not alter the actual engine or grip.
	var torque := player.config.engine_torque_nm
	var grip := player.config.tire_grip
	sprint.set_physics_process(false)
	player.global_position = sprint.start_m * 20.0
	player.rotation = sprint.heading.angle() + PI / 2.0
	player.linear_velocity = Vector2.ZERO
	player.velocity = Vector2.ZERO
	check("city_sprint_can_be_staged_without_a_menu",
		sprint.can_stage() and sprint.start_race())
	check("AI_course_does_not_modify_power_or_traction",
		player.config.engine_torque_nm == torque and player.config.tire_grip == grip)
	var map_hud: Node
	for child in main.get_children():
		if child.get_script() == load("res://scripts/world/world_map_hud.gd"):
			map_hud = child
	check("city_racing_line_appears_on_minimap",
		map_hud != null and map_hud._active_race_navigation() == sprint.navigation)
	print("TRAFFIC-AWARE RACING LINE: ",
		"PASS" if failures.is_empty() else "FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
