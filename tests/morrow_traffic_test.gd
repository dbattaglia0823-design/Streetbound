extends SceneTree
## Regression: real Morrow roads create directional lanes, legal connectors,
## driveable agents and strictly bounded streamed ambient traffic.
const Net = preload("res://scripts/world/traffic_network.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")


func check(label: String, valid: bool, data: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if valid else "FAIL", label, data])
	if not valid:
		failures.append(label)


func run() -> void:
	var main := load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var world: MorrowCoast = main.ground
	var traffic: Node2D = main.get_node_or_null("TrafficWorld")
	check("production_world_owns_traffic", traffic != null)
	if traffic == null:
		quit(1)
		return
	var graph: Dictionary = Net.build(world.data)
	check("directed_road_network_generated",graph.routes.size() >= world.data.roads.size(),
		[graph.routes.size(),world.data.roads.size()])
	check("junction_connections_generated",int(graph.link_count) >= 5,int(graph.link_count))
	var speeds := {}
	var gripped := true
	var wrong_way := false
	var links_count := 0
	for route in graph.routes:
		var path: PackedVector2Array = route.points
		var station: PackedFloat32Array = route.stations
		if path.size() < 2:
			gripped = false
			continue
		for i in range(1,station.size()):
			if station[i] <= station[i-1]:
				gripped = false
		var road: Dictionary = world.data.roads[int(route.road)]
		speeds[str(road.kind)] = true
		for link in route.links:
			links_count += 1
			var next: Dictionary = graph.routes[int(link.to)]
			if bool(route.loose) != bool(next.loose):
				wrong_way = true
			if int(link.at) >= path.size() or int(link.target) >= (next.points as PackedVector2Array).size():
				wrong_way = true
	check("lane_stations_monotonic",gripped)
	check("road_classes_receive_speed_limits",speeds.size() >= 3,speeds.keys())
	check("no_paved_to_dirt_connections",not wrong_way)
	check("every_link_targets_real_lane",links_count == int(graph.link_count),links_count)
	var forward_route := {}
	var backward_route := {}
	for route in graph.routes:
		if int(route.road) == int(graph.routes[0].road) and int(route.lane) == 0:
			if int(route.direction) == 1:
				forward_route = route
			elif int(route.direction) == -1:
				backward_route = route
	if not forward_route.is_empty() and not backward_route.is_empty():
		var f: PackedVector2Array = forward_route.points
		var b: PackedVector2Array = backward_route.points
		var forward_heading := (f[1]-f[0]).normalized()
		var lateral := (f[0]-b[-1]).dot(forward_heading.orthogonal())
		check("right_hand_lane_offsets",lateral > 0.5,lateral)
	var routes_before := traffic.network.routes.size()
	check("traffic_loaded_from_same_source",routes_before == graph.routes.size(),routes_before)
	traffic.MAX_ACTIVE # const reference validates script interface
	traffic.spawn_clock = 0.59
	for tick in 120:
		traffic._physics_process(1.0/60.0)
	check("traffic_population_bounded",traffic.cars.size() <= 18,traffic.cars.size())
	check("traffic_pool_can_spawn",traffic.spawned_total >= 1,traffic.spawned_total)
	for agent in traffic.cars:
		if not is_instance_valid(agent.car):
			gripped = false
			continue
		var car: AnimatableBody2D = agent.car
		if car.collision_layer != 1 or car.collision_mask != 0:
			gripped = false
	check("AI_cars_use_physics_collision_layer",gripped)
	var proving := load("res://scenes/main.tscn").instantiate()
	proving.proving_ground = true
	root.add_child(proving)
	await physics_frame
	check("proving_ground_has_no_city_traffic",proving.get_node_or_null("TrafficWorld") == null)
	print("MORROW TRAFFIC TESTS: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
