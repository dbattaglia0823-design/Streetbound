extends SceneTree
## Traffic remains physical during city races. A fast AI plans an actual paved
## lane change around slow civilians; oncoming cars or blocked gaps force a safe
## speed cap instead of collision, teleporting or rubber-band boosts.
const VehicleScene = preload("res://scenes/vehicle.tscn")
const Navigation = preload("res://scripts/world/race_navigation.gd")
const Planner = preload("res://scripts/world/race_traffic_overtaking.gd")
const Driver = preload("res://scripts/world/race_ai_driver.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")


class TestPavement:
	extends Node2D
	var half_width_m := 4.5
	func surface_at(point_px: Vector2) -> Dictionary:
		return {"name":"ASPHALT", "grip":1.0} if \
			absf(point_px.x / 20.0) <= half_width_m else {"name":"GRASS", "grip":0.6}


class TestTrafficFlow:
	extends Node
	var agents: Array[Dictionary] = []


class TrafficBody:
	extends CharacterBody2D
	var width_px := 42.0
	var recovering := false


func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL",label])
	if not passed:
		failures.append(label)


func _add_traffic(flow: TestTrafficFlow, location_m: Vector2,
		velocity_mps: float, id: int) -> TrafficBody:
	var body := TrafficBody.new()
	flow.add_child(body)
	body.global_position = location_m * 20.0
	body.rotation = PI if velocity_mps >= 0.0 else 0.0
	flow.agents.append({"uid":id,"node":body,
		"speed":absf(velocity_mps) * 20.0})
	return body


func _run() -> void:
	var road := TestPavement.new()
	root.add_child(road)
	var flow := TestTrafficFlow.new()
	root.add_child(flow)
	var car := VehicleScene.instantiate() as VehicleController2D
	car.external_input = true
	car.surface_provider = road
	root.add_child(car)
	car.set_physics_process(false)
	car.global_position = Vector2(2.25, 50.0) * 20.0
	car.rotation = PI
	car.linear_velocity = Vector2(0, 31.0)
	car.surface_grip = 1.0
	var nav := Navigation.new()
	nav.call("setup", PackedVector2Array([
		Vector2(2.25,0.0), Vector2(2.25,800.0)]), false)
	var planner := Planner.new()
	planner.setup(car,road,flow,nav)
	var slow := _add_traffic(flow,Vector2(2.25,119.0),10.0,51)
	# A free destination lane is not proof that the transition corridor is
	# free. The rival must not cross through a car while changing lanes.
	var crossing: Array[Dictionary] = [
		{"ahead_m":28.0,"lateral_m":0.0,"width_m":2.1,
			"lateral_speed_mps":0.0}
	]
	check("race_AI_checks_entire_lane_change_not_just_target_lane",
		not planner._entry_clear(2.25,-4.5,crossing,31.0))
	var moving_into_path: Array[Dictionary] = [
		{"ahead_m":28.0,"lateral_m":-6.0,"width_m":2.1,
			"lateral_speed_mps":5.5}
	]
	check("race_AI_predicts_other_cars_moving_sideways_into_path",
		not planner._entry_clear(2.25,-4.5,moving_into_path,31.0))
	check("race_AI_keeps_full_speed_when_transition_is_truly_clear",
		planner._entry_clear(2.25,-4.5,[],31.0))
	var first: Dictionary = planner.plan(0.15,50.0,31.0)
	check("overtakes_slow_civilian_instead_of_braking_to_traffic_speed",
		first.mode == "passing" and float(first.speed_cap_mps) == INF)
	check("chooses_full_clear_lane_on_real_pavement",
		absf(absf(float(first.offset_m)) - 4.5) < 0.01)
	check("does_not_teleport_or_change_physical_car_while_planning",
		car.global_position.distance_to(Vector2(2.25,50.0)*20.0) < 0.01 and
		car.linear_velocity == Vector2(0.0,31.0))
	var steering_driver := Driver.new()
	root.add_child(steering_driver)
	steering_driver.set_physics_process(false)
	steering_driver.call("setup_navigation",car,nav)
	steering_driver.call("enable_race_traffic",road,flow)
	steering_driver.set("reaction_seconds", 0.0)
	steering_driver.call("launch")
	steering_driver._physics_process(0.2)
	check("passing_steers_via_real_vehicle_commands",
		absf(car.command.z) > 0.01 and car.command.x > 0.0 and
		car.command.x <= 1.0 and car.command.y == 0.0)
	var source_torque := car.config.engine_torque_nm
	var source_grip := car.config.tire_grip
	check("racing_overtake_cannot_augment_engine_or_grip",
		is_equal_approx(car.config.engine_torque_nm,source_torque) and
		is_equal_approx(car.config.tire_grip,source_grip))
	var oncoming := _add_traffic(flow,Vector2(-2.25,135.0),-21.0,52)
	var blocked: Dictionary = planner.plan(0.15,50.0,31.0)
	check("oncoming_traffic_blocks_opposing_lane_pass",
		blocked.mode == "following" and
		is_finite(float(blocked.speed_cap_mps)))
	check("planner_does_not_squeeze_between_unsafe_car_gaps",
		absf(float(blocked.offset_m)) < 0.1)
	flow.agents.remove_at(1)
	oncoming.queue_free()
	var open: Dictionary = planner.plan(0.15,50.0,31.0)
	check("immediately_resumes_overtake_when_gap_reopens",
		open.mode == "passing" and absf(float(open.offset_m)) > 3.0)
	# Both cars can be passed only if real body clearance exists.
	road.half_width_m = 2.7
	var narrow: Dictionary = planner.plan(0.15,50.0,31.0)
	check("no_pass_when_car_cannot_fit_within_pavement",
		narrow.mode == "following" and is_finite(float(narrow.speed_cap_mps)))
	# At 69m there is room to keep race speed while still planning a safe
	# braking approach. Bring the civilian nearer to verify actual braking.
	slow.global_position = Vector2(2.25,70.0) * 20.0
	var imminent: Dictionary = planner.plan(0.15,50.0,31.0)
	check("blocked_close_car_requires_physics_based_braking",
		imminent.mode == "following" and
		float(imminent.speed_cap_mps) < 31.0)
	slow.global_position = Vector2(2.25,119.0) * 20.0
	road.half_width_m = 4.5
	var resumed: Dictionary = planner.plan(0.15,50.0,31.0)
	check("paved_lane_reopens_after_narrow_section",
		resumed.mode == "passing")
	slow.global_position = Vector2(2.25,10.0) * 20.0
	var completed: Dictionary = planner.plan(0.15,50.0,31.0)
	check("return_to_racing_line_after_pass",
		completed.mode == "clear" and absf(float(completed.offset_m)) < 0.1)
	check("completed_pass_is_recorded_without_physics_cheat",
		planner.passed_count > 0 and
		car.config.engine_torque_nm == source_torque and car.config.tire_grip == source_grip)
	# Integrate with the real Morrow world, not just a synthetic planner.
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var street: Node = main.street_race
	var civilian: Node = main.ground.get_node("AmbientTraffic")
	var player: VehicleController2D = main.vehicle
	player.set_physics_process(false)
	street.set_physics_process(false)
	civilian.enabled = false
	civilian.clear_traffic()
	player.global_position = street.start_m * 20.0
	player.rotation = street.heading.angle() + PI / 2.0
	player.linear_velocity = Vector2.ZERO
	player.velocity = Vector2.ZERO
	check("street_race_staging_still_works",street.can_stage())
	check("street_race_spawns_real_AI_and_activates_ambient_cars",
		street.start_race() and civilian.enabled and
		civilian.street_race_active and street.opponent != null and
		street.opponent_driver != null)
	check("traffic_never_replaced_by_noncollidable_ghosts",
		street.opponent.collision_mask == 3 and
		street.opponent.collision_layer == 1)
	check("rival_is_equipped_with_same_car_as_player",
		street.opponent.config != player.config and
		is_equal_approx(street.opponent.config.mass_kg,player.config.mass_kg) and
		is_equal_approx(street.opponent.config.engine_torque_nm,player.config.engine_torque_nm))
	check("rival_has_predictive_traffic_planner",
		street.opponent_driver.get("traffic_planner") != null and
		street.opponent_driver.get("navigation") == street.navigation)
	var spawn_ok := false
	for i in 10:
		if civilian._spawn_one():
			spawn_ok = true
	check("civilian_traffic_remains_real_while_street_race_active",
		spawn_ok and civilian.agents.size() > 0 and
		(civilian.agents[0].node as Node).is_in_group("traffic_vehicle"))
	street._physics_process(3.2)
	check("AI_competes_after_countdown_not_during_staging",
		street.state == "running" and
		bool(street.opponent_driver.get("active")))
	street._abort("TEST RACE END")
	check("race_stop_restores_original_traffic_toggle",
		not civilian.street_race_active and not civilian.enabled)
	check("race_stop_disables_AI_and_frees_player_group",
		not bool(street.opponent_driver.get("active")) and
		not player.is_in_group("race_participant"))
	print("RACING TRAFFIC OVERTAKING: ",
		"PASS" if failures.is_empty() else "FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
