extends SceneTree
## Verify real curved-lane sensing and offscreen-only disposal. No vehicle
## sprite/physics scaling, teleporting, or invisible in-view removals.
const Network = preload("res://scripts/world/traffic_network.gd")
const Flow = preload("res://scripts/world/traffic_flow.gd")
const Car = preload("res://scripts/world/traffic_car.gd")
const PlayerScene = preload("res://scenes/vehicle.tscn")
const PPM := 20.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, ok: bool, detail: Variant = "") -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", label, str(detail)])
	if not ok:
		failures.append(label)


func _car(position_px: Vector2, angle: float = 0.0) -> CharacterBody2D:
	var node := CharacterBody2D.new()
	node.set_script(Car)
	node.position = position_px
	node.rotation = angle
	root.add_child(node)
	return node


func _agent(node: CharacterBody2D, uid: int, speed_px: float) -> Dictionary:
	return {"uid":uid, "node":node, "edge":0, "progress":0.0,
		"speed":speed_px, "cruise":speed_px, "next":-2,
		"stop_done":false, "stop_wait":0.0,
		"obstacle_scan_clock":0.0,"obstacle_position":Vector2.INF,
		"recovery_time":0.0,"recovery_refresh":0.0,"recovery_goal":{},
		"stuck_time":0.0,"stuck_clock":0.0,"stuck_anchor":node.global_position,
		"path_scan_clock":0.0,"path_speed_cap":INF}


func _graph(origin: Vector2) -> RefCounted:
	var result := Network.new()
	result._add_edge({"road":0,"connector":false,"start_j":-1,
		"end_j":-1,"points":PackedVector2Array([
		origin,origin+Vector2.UP*PPM*8.0,
		origin+Vector2.UP*PPM*8.0+Vector2.RIGHT*PPM*25.0]),
		"speed_px":PPM*16.0,"control":"none","turn":"straight"})
	return result


func _run() -> void:
	var flow := Node2D.new()
	flow.set_script(Flow)
	flow.enabled = false
	flow.maximum_vehicles = 0
	root.add_child(flow)
	var origin := Vector2(16000, 16000)
	var actor := _car(origin)
	var lead := _car(origin + Vector2.UP*PPM*8.0 + Vector2.RIGHT*PPM*3.0,
		PI*0.5)
	var player := PlayerScene.instantiate() as VehicleController2D
	player.position = origin + Vector2.RIGHT*PPM*260.0
	root.add_child(player)
	player.set_physics_process(false)
	flow.player = player
	flow.network = _graph(origin)
	var follower := _agent(actor, 7, PPM*14.0)
	var lead_agent := _agent(lead, 8, 0.0)
	flow.agents.clear()
	flow.agents.append(follower)
	flow.agents.append(lead_agent)
	await physics_frame
	check("curved_route_not_visible_to_straight_forward_sensor",
		is_equal_approx(flow._car_following(0,PPM*14.0),PPM*14.0))
	var curved_speed: float = flow._path_aware_speed(follower,PPM*14.0)
	check("sees_stopped_car_around_actual_curved_lane",
		curved_speed < PPM*14.0 and curved_speed >= 0.0,curved_speed)
	lead.position += Vector2.DOWN * PPM * 5.0
	follower.path_scan_clock = 0.0
	var adjacent_speed: float = flow._path_aware_speed(follower,PPM*14.0)
	check("adjacent_cars_not_on_route_do_not_cause_false_braking",
		is_equal_approx(adjacent_speed,PPM*14.0),adjacent_speed)
	# Normal route selection must not drive directly backwards when a
	# legal straight connection is available.
	var network: RefCounted = flow.network
	var last := origin + Vector2.UP*PPM*8.0 + Vector2.RIGHT*PPM*25.0
	var ahead := int(network.call("_add_edge", {"road":0,"connector":true,
		"start_j":-1,"end_j":-1,"turn":"straight","points":PackedVector2Array([
		last,last+Vector2.RIGHT*PPM*25.0]),"speed_px":PPM*10.0}))
	var reverse := int(network.call("_add_edge", {"road":0,"connector":true,
		"start_j":-1,"end_j":-1,"turn":"left","points":PackedVector2Array([
		last,last+Vector2.LEFT*PPM*25.0]),"speed_px":PPM*10.0}))
	var graph_edges: Array = network.get("edges")
	graph_edges[0]["next"] = [reverse, ahead]
	flow.random.seed = 12345
	var smooth_routes := true
	for i in 16:
		smooth_routes = smooth_routes and flow._choose_next(network.edges[0]) == ahead
	check("traffic_prefers_continuous_forward_routes_not_U_turns",smooth_routes)
	var camera := Camera2D.new()
	camera.position = origin
	root.add_child(camera)
	camera.make_current()
	await physics_frame
	check("actually_visible_stuck_vehicle_protected",
		flow._visible_to_any_player(actor.global_position))
	var original_car_dimensions := Vector2(float(actor.get("width_px")),
		float(actor.get("length_px")))
	var expired_visible := false
	for i in 25:
		expired_visible = flow._stalled_offscreen(follower, 0.75) or expired_visible
	check("visible_stationary_car_survives_full_timeout",not expired_visible and
		float(follower.stuck_time) >= Flow.STUCK_REMOVE_SECONDS)
	camera.position = player.position
	camera.force_update_scroll()
	await physics_frame
	check("far_road_car_outside_player_camera_not_visible",
		not flow._visible_to_any_player(actor.global_position))
	check("stuck_unseen_car_marked_for_removal",
		flow._stalled_offscreen(follower, 0.75))
	# Another player near the stranded car must protect it even when the
	# first player's active camera looks somewhere completely different.
	var second_player := PlayerScene.instantiate() as VehicleController2D
	second_player.position = actor.global_position + Vector2(8, 0)*PPM
	root.add_child(second_player)
	second_player.set_physics_process(false)
	second_player.add_to_group("player_vehicle")
	check("nearby_second_human_prevents_unseen_despawn",
		not flow._stalled_offscreen(follower,0.75))
	second_player.remove_from_group("player_vehicle")
	second_player.queue_free()
	# Once released, the actual update loop retires the car and the
	# junction reservation instead of leaving a permanent stopped collider.
	flow.agents.remove_at(1)
	lead.queue_free()
	follower.speed = 0.0
	follower.cruise = 0.0
	follower.stuck_time = Flow.STUCK_REMOVE_SECONDS + 1.0
	follower.stuck_clock = Flow.STUCK_WINDOW_SECONDS - 0.05
	flow.enabled = true
	flow._physics_process(0.05)
	check("real_traffic_update_removes_stuck_offscreen_body",
		flow.agents.is_empty() and actor.is_queued_for_deletion())
	check("removal_does_not_change_vehicle_size",
		original_car_dimensions.is_equal_approx(Vector2(
			Car.BASE_WIDTH_PX * Car.TRAFFIC_SIZE_MULTIPLIER,
			Car.BASE_LENGTH_PX * Car.TRAFFIC_SIZE_MULTIPLIER)))
	# Moving an actual distance resets its stuck clock, preventing removal
	# of slow but mobile vehicles outside the viewport.
	var moving := _car(origin + Vector2.RIGHT*PPM*11.0)
	var moving_agent := _agent(moving,9,PPM*10.0)
	moving_agent.stuck_time = 20.0
	moving.position += Vector2.RIGHT * PPM * 2.0
	check("real_displacement_resets_stuck_detection",
		not flow._stalled_offscreen(moving_agent,0.75) and
		float(moving_agent.stuck_time) == 0.0)
	print("AI PATH DETECTION AND OFFSCREEN CLEANUP: ",
		"PASS" if failures.is_empty() else "FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
