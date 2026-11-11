extends SceneTree
## Live-body traffic awareness, crossing prediction, physical hitbox sizing,
## and both frontal/side player crashes. No full coastal map needed.
const TrafficFlow = preload("res://scripts/world/traffic_flow.gd")
const TrafficCar = preload("res://scripts/world/traffic_car.gd")
const PlayerScene = preload("res://scenes/vehicle.tscn")
const PPM := 20.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, good: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL", label, detail])
	if not good:
		failures.append(label)


func make_car(pos: Vector2) -> CharacterBody2D:
	var car := CharacterBody2D.new()
	car.set_script(TrafficCar)
	car.position = pos
	root.add_child(car)
	return car


func make_agent(car: CharacterBody2D, id: int, velocity_px: float) -> Dictionary:
	return {
		"uid": id, "node": car, "speed": velocity_px,
		"cruise": velocity_px, "edge": 0, "progress": 0.0,
		"next": -2, "stop_wait": 0.0, "stop_done": false,
		"recovery_time": 0.0, "recovery_refresh": 0.0,
		"recovery_goal": {}
	}


func run() -> void:
	var flow := Node2D.new()
	flow.set_script(TrafficFlow)
	flow.enabled = false
	root.add_child(flow)
	var actor := make_car(Vector2(15000, 15000))
	var other := make_car(actor.position + Vector2.UP * PPM * 8.0)
	var player := PlayerScene.instantiate()
	player.position = actor.position + Vector2.UP * PPM * 12.0
	root.add_child(player)
	player.set_physics_process(false)
	await physics_frame
	flow.player = player
	var agent := make_agent(actor, 2, PPM * 16.0)
	var lead := make_agent(other, 1, 0.0)
	flow.agents.clear()
	flow.agents.append(agent)
	flow.agents.append(lead)
	check("player_collision_capsule",
		(player.get_node("CollisionShape2D") as CollisionShape2D).shape is CapsuleShape2D)
	var shape := (actor.get_node("VehicleCollider") as CollisionShape2D).shape as CapsuleShape2D
	check("traffic_dimensions_enlarged_exactly_ten_percent",
		is_equal_approx(float(actor.get("length_px")),
			TrafficCar.BASE_LENGTH_PX * 1.10) and
		is_equal_approx(float(actor.get("width_px")),
			TrafficCar.BASE_WIDTH_PX * 1.10),
		[actor.get("width_px"), actor.get("length_px")])
	check("traffic_art_fitted_hitbox", shape.radius > 7.0 and
		shape.radius <= float(actor.get("width_px")) * 0.45 + 0.01 and
		shape.height <= float(actor.get("length_px")) and
		shape.height > shape.radius * 2.0,
		[shape.radius, shape.height])
	var sprite: Sprite2D = actor.get_node_or_null("VehicleArtwork") as Sprite2D
	var art: Dictionary = TrafficCar.appearance_for(int(actor.get("model_index")))
	check("traffic_sprite_is_ten_percent_larger_in_world_units",
		sprite != null and not art.is_empty() and
		is_equal_approx(sprite.scale.x,
			minf(float(actor.get("width_px")) / float(art.aspect.x),
				float(actor.get("length_px")) / float(art.aspect.y))) and
		is_equal_approx(sprite.scale.y, sprite.scale.x))
	check("stopped_traffic_ahead_brakes",
		flow._car_following(0, PPM * 16.0) < PPM * 16.0)
	other.position = actor.position + Vector2.UP * PPM * 5.0
	check("bumper_to_bumper_traffic_stops",
		flow._car_following(0, PPM * 10.0) < PPM * 1.0)
	other.position = actor.position + Vector2.RIGHT * PPM * 4.5
	check("adjacent_lane_does_not_trigger_braking",
		is_equal_approx(flow._car_following(0, PPM * 12.0), PPM * 12.0))
	other.position = actor.position + Vector2.UP * PPM * 12.0
	lead.speed = PPM * 20.0
	check("faster_traffic_ahead_does_not_block",
		is_equal_approx(flow._car_following(0, PPM * 10.0), PPM * 10.0))
	flow.agents.clear()
	flow.agents.append(agent)
	player.position = actor.position + Vector2.UP * PPM * 5.0
	player.linear_velocity = Vector2.ZERO
	check("stationary_player_ahead_yields",
		flow._player_awareness(agent, PPM * 9.0) < PPM * 1.0)
	player.linear_velocity = Vector2.UP * 13.0
	agent.speed = PPM * 10.0
	check("moving_player_ahead_can_be_followed",
		is_equal_approx(flow._player_awareness(agent, PPM * 10.0), PPM * 10.0))
	player.position = actor.position + Vector2(-9.0, -9.0) * PPM
	player.linear_velocity = Vector2.RIGHT * 9.0
	agent.speed = PPM * 9.0
	check("crossing_player_predicted_before_impact",
		flow._player_awareness(agent, PPM * 9.0) < PPM * 9.0)
	player.position = actor.position + Vector2(7.0, -9.0) * PPM
	check("non_intersecting_crossing_does_not_brake",
		is_equal_approx(flow._player_awareness(agent, PPM * 9.0), PPM * 9.0))
	# Actual crossing priority belongs to vehicles approaching the
	# SAME junction; otherwise cars stop for unrelated traffic.
	var graph = preload("res://scripts/world/traffic_network.gd").new()
	graph.edges.append({"connector": false, "start_j": -1})
	graph.edges.append({"connector": false, "start_j": -1})
	graph.edges.append({"connector": true, "start_j": 7})
	graph.edges.append({"connector": true, "start_j": 7})
	flow.network = graph
	agent.edge = 0
	agent.next = 2
	lead.edge = 1
	lead.next = 3
	# Cross-traffic has a stable priority rule; the lower NPC ID proceeds.
	other.position = actor.position + Vector2(-9.0, -9.0) * PPM
	other.rotation = PI * 0.5
	lead.speed = PPM * 9.0
	flow.agents.clear()
	flow.agents.append(agent)
	flow.agents.append(lead)
	check("lower_id_has_intersection_priority",
		flow._car_following(1, PPM * 9.0) >= PPM * 8.0)
	check("higher_id_yields_at_crossing",
		flow._car_following(0, PPM * 9.0) < PPM * 9.0)
	lead.next = -2
	check("unrelated_junction_traffic_does_not_hold_queue",
		is_equal_approx(flow._car_following(0, PPM * 9.0), PPM * 9.0))
	lead.next = 3
	# Move to an isolated site and exercise the real player collision routine.
	var crash_car := make_car(Vector2(26000, 26000))
	var driver := PlayerScene.instantiate()
	driver.position = crash_car.position + Vector2.DOWN * 285.0
	root.add_child(driver)
	driver.set_physics_process(false)
	await physics_frame
	driver.linear_velocity = Vector2.UP * 18.0
	for i in 80:
		await physics_frame
		driver.step_vehicle(1.0 / 60.0, Vector4.ZERO)
		if crash_car.impact_count > 0:
			break
	check("front_impact_impulse_reaches_traffic", crash_car.impact_count == 1)
	check("front_impact_keeps_player_momentum", driver.linear_velocity.length() > 5.5,
		driver.linear_velocity)
	var front_impacts: int = int(crash_car.get("impact_count"))
	for i in 5:
		await physics_frame
		driver.step_vehicle(1.0 / 60.0, Vector4.ZERO)
	check("repeated_physics_contacts_do_not_stack_impulses",
		crash_car.impact_count == front_impacts, crash_car.impact_count)
	check("velocity_telemetry_sync", driver.velocity.distance_to(
		driver.linear_velocity * PPM) < 0.01)
	var side_car := make_car(Vector2(32000, 32000))
	var side_player := PlayerScene.instantiate()
	side_player.position = side_car.position + Vector2.LEFT * 250.0
	root.add_child(side_player)
	side_player.set_physics_process(false)
	await physics_frame
	side_player.rotation = PI * 0.5
	side_player.linear_velocity = Vector2.RIGHT * 22.0
	for i in 95:
		await physics_frame
		side_player.step_vehicle(1.0 / 60.0, Vector4.ZERO)
		if side_car.impact_count > 0:
			break
	check("sideways_impact_pushes_traffic", side_car.impact_count > 0,
		side_car.impact_count)
	check("sideways_impact_remains_bounded",
		side_player.linear_velocity.length() < 30.0,
		side_player.linear_velocity)
	print("TRAFFIC SAFETY / CRASH PHYSICS: ",
		"PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
