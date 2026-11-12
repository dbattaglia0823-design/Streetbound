extends SceneTree
## Verify authored circuit lap, active map path, and physics-derived brake line.
const Navigation = preload("res://scripts/world/race_navigation.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		failures.append(label)


func _run() -> void:
	var main := load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var car: VehicleController2D = main.vehicle
	car.set_physics_process(false)
	var drag: Node2D = main.drag_race
	var circuit: Node2D = main.circuit_race
	check("drag_race_exposes_an_authored_route",drag != null and
		drag.navigation != null and not bool(drag.navigation.closed))
	check("circuit_lap_available_and_closed",circuit != null and
		circuit.available and circuit.navigation != null and
		bool(circuit.navigation.closed) and float(circuit.navigation.length_m) > 2000.0)
	if circuit == null or not circuit.available:
		print("RACE ROUTE AND BRAKING GUIDE: FAIL")
		quit(1)
		return
	var hud: CanvasLayer
	for child in main.get_children():
		if child.get_script() == load("res://scripts/world/world_map_hud.gd"):
			hud = child
	check("map_hud_available",hud != null)
	if hud == null:
		quit(1)
		return
	var mini: Control = hud.mini_view
	var atlas: Control = hud.full_view
	check("route_overlays_exist_but_hidden_outside_races",
		mini.race_overlay != null and atlas.race_overlay != null and
		not mini.race_overlay.enabled and not atlas.race_overlay.enabled)
	var test_route := Navigation.new()
	test_route.setup(PackedVector2Array([
		Vector2(0,0), Vector2(300,0), Vector2(330,0),
		Vector2(330,80), Vector2(330,200)]), false)
	test_route.update_envelope(car)
	var fast_corner: float = test_route.allowed_speed_at(302.0)
	var far_approach: float = test_route.allowed_speed_at(200.0)
	check("corner_target_slowed_by_real_curve_radius",fast_corner < far_approach)
	check("braking_begins_before_corner",test_route.allowed_speed_at(265.0) < far_approach)
	check("brake_line_red_at_high_speed",test_route.braking_state(280.0, 42.0) == 2)
	check("brake_line_stops_being_red_after_deceleration",
		test_route.braking_state(280.0, 3.0) != 2)
	var distance_fast: float = test_route.suggested_braking_distance(37.0, 12.0)
	var distance_slow: float = test_route.suggested_braking_distance(25.0, 12.0)
	check("required_braking_distance_grows_with_real_speed",
		distance_fast > distance_slow and distance_fast > 30.0)
	var current := test_route.allowed_speed_at(260.0)
	var original_brake := car.config.brake_force_n
	car.config.brake_force_n = original_brake * 0.25
	test_route.update_envelope(car)
	check("weaker_car_brakes_move_braking_line_earlier",
		test_route.allowed_speed_at(260.0) < current)
	car.config.brake_force_n = original_brake
	test_route.update_envelope(car)
	drag.set_physics_process(false)
	car.global_position = drag.start_m * 20.0
	car.rotation = drag.direction.angle() + PI / 2.0
	car.linear_velocity = Vector2.ZERO
	car.velocity = Vector2.ZERO
	check("drag_staging_still_works",drag.can_stage() and drag.start_race())
	hud._process(0.0)
	check("active_drag_race_draws_on_both_maps",mini.race_overlay.enabled and
		atlas.race_overlay.enabled and mini.race_overlay.navigation == drag.navigation)
	drag.state = "idle"
	hud._process(0.0)
	check("route_is_hidden_after_race",not mini.race_overlay.enabled)
	circuit.set_physics_process(false)
	car.global_position = circuit.start_m * 20.0
	car.rotation = circuit.heading.angle() + PI / 2.0
	car.linear_velocity = Vector2.ZERO
	car.velocity = Vector2.ZERO
	check("circuit_event_stages_by_driving_to_start",circuit.can_stage() and
		circuit.start_race())
	hud._process(0.0)
	check("circuit_route_replaces_drag_route_on_map",
		mini.race_overlay.enabled and mini.race_overlay.navigation == circuit.navigation)
	check("circuit_world_line_tracks_selected_player_car",
		circuit.world_guidance != null and circuit.world_guidance.player == car)
	print("RACE ROUTE AND BRAKING GUIDE: ",
		"PASS" if failures.is_empty() else "FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
