extends SceneTree
## Off-screen car warnings: projection, closing speed, direction, real
## single-player traffic, camera zoom and two independent split viewports.
const Awareness = preload("res://scripts/ui/offscreen_vehicle_awareness.gd")
const PPM := 20.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(name: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL",name,str(detail)])
	if not passed:
		failures.append(name)


func _has_target(indicator: Control, target: Node2D) -> bool:
	for marker in indicator.get("markers"):
		if marker.get("target") == target:
			return true
	return false


func _run() -> void:
	var from := Vector2.ZERO
	var forward := Vector2.UP
	var player_velocity := Vector2(0,-32)
	var ahead := Vector2(0,-PPM*75.0)
	var approaching := Awareness.approach_info(
		from,player_velocity,forward,ahead,Vector2(0,-14))
	check("forward_slow_vehicle_triggers_with_correct_meters",
		is_equal_approx(float(approaching.get("distance_m",0.0)),75.0) and \
		float(approaching.get("closing_mps",0.0)) > 17.9)
	check("same_speed_traffic_does_not_spam_indicator",
		Awareness.approach_info(from,player_velocity,forward,ahead,
			player_velocity).is_empty())
	check("receding_car_does_not_warn",
		Awareness.approach_info(from,player_velocity,forward,ahead,
			Vector2(0,-50)).is_empty())
	check("car_behind_player_is_not_an_upcoming_obstacle",
		Awareness.approach_info(from,player_velocity,forward,
			Vector2(0,PPM*60),Vector2.ZERO).is_empty())
	check("distant_unrelated_traffic_is_filtered",
		Awareness.approach_info(from,player_velocity,forward,
			Vector2(0,-PPM*650),Vector2.ZERO).is_empty())
	check("stationary_player_has_no_traffic_indicators",
		Awareness.approach_info(from,Vector2.ZERO,forward,ahead,
			Vector2(0,20)).is_empty())
	check("traffic_indicators_require_speed_above_40_mph",
		not Awareness.player_is_fast_enough(Vector2(0,39.9/Awareness.MPS_TO_MPH)) and \
		Awareness.player_is_fast_enough(Vector2(0,40.1/Awareness.MPS_TO_MPH)) and \
		Awareness.approach_info(from,Vector2(0,-39.9/Awareness.MPS_TO_MPH),
			forward,ahead,Vector2.ZERO).is_empty())
	check("traffic_detector_reaches_500_metres_exactly",
		is_equal_approx(Awareness.MAX_RANGE_M,500.0) and \
		not Awareness.approach_info(from,player_velocity,forward,
			Vector2(0,-PPM*499.0),Vector2.ZERO).is_empty() and \
		not Awareness.approach_info(from,player_velocity,forward,
			Vector2(0,-PPM*500.0),Vector2.ZERO).is_empty() and \
		Awareness.approach_info(from,player_velocity,forward,
			Vector2(0,-PPM*501.0),Vector2.ZERO).is_empty())
	# Broader awareness must see side traffic that is actually closing,
	# without warning for directly rearward or receding vehicles.
	var right_approach := Vector2.RIGHT * PPM * 350.0
	check("closing_cross_traffic_detected_at_90_degrees",
		not Awareness.approach_info(from,player_velocity,forward,
			right_approach,Vector2.LEFT * 22.0).is_empty())
	var rear_quarter := forward.rotated(deg_to_rad(110.0)) * PPM * 350.0
	check("wider_240_degree_cone_sees_rear_side_approach",
		is_equal_approx(Awareness.FORWARD_DOT,-0.5) and \
		not Awareness.approach_info(from,player_velocity,forward,
			rear_quarter,-rear_quarter.normalized() * 28.0).is_empty())
	var excluded_rear := forward.rotated(deg_to_rad(130.0)) * PPM * 350.0
	check("directly_rearward_traffic_outside_wide_cone",
		Awareness.approach_info(from,player_velocity,forward,
			excluded_rear,-excluded_rear.normalized() * 35.0).is_empty())
	check("side_traffic_moving_away_is_still_filtered",
		Awareness.approach_info(from,player_velocity,forward,
			right_approach,Vector2.RIGHT * 15.0).is_empty())
	check("distance_is_labeled_in_feet_without_vehicle_type",
		Awareness.distance_caption(60.0)=="197 FT" and \
		Awareness.distance_caption(60.0,true)=="197 FT" and \
		Awareness.distance_caption(500.0)=="1640 FT")
	check("on_screen_and_near_edge_suppressed",
		Awareness.is_on_screen(Vector2(500,250),Vector2(1000,600)) and \
		Awareness.is_on_screen(Vector2(-20,250),Vector2(1000,600)) and \
		not Awareness.is_on_screen(Vector2(-65,250),Vector2(1000,600)))
	var dimensions := Vector2(1000,600)
	var center := Vector2(500,300)
	var right := Awareness.edge_position(center,Vector2(2400,300),dimensions)
	var top := Awareness.edge_position(center,Vector2(500,-500),dimensions)
	var corner := Awareness.edge_position(center,Vector2(-300,-500),dimensions)
	check("directional_indicator_clamps_to_correct_viewport_edge",
		is_equal_approx(right.x,dimensions.x-Awareness.EDGE_MARGIN.x) and \
		is_equal_approx(right.y,center.y) and \
		is_equal_approx(top.y,Awareness.EDGE_MARGIN.y) and \
		corner.x>=Awareness.EDGE_MARGIN.x and \
		corner.y>=Awareness.EDGE_MARGIN.y)
	var small := Awareness.edge_position(Vector2(210,170),
		Vector2(1000,170),Vector2(420,340))
	check("small_viewports_keep_markers_inside_screen",
		small.x < 420.0 and small.x > 300.0 and small.y > 0.0)

	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var player: VehicleController2D = game.vehicle
	var indicator: Control = game.offscreen_vehicle_awareness
	var camera: Camera2D = get_first_node_in_group("player_camera") as Camera2D
	check("single_player_has_vehicle_awareness_hud",
		indicator != null and indicator.get_script() == Awareness and \
		indicator.get("player") == player and indicator.get("camera") == camera)
	if indicator == null or player == null:
		game.queue_free()
		quit(1)
		return
	player.set_physics_process(false)
	var front := Vector2.UP.rotated(player.global_rotation)
	player.linear_velocity = front*32.0
	# A deterministic fake traffic actor avoids relying on random world spawns.
	var ambient: Node = game.ground.get_node_or_null("AmbientTraffic")
	if is_instance_valid(ambient):
		ambient.call("clear_traffic")
	var car := Node2D.new()
	car.name = "OffscreenFixtureCar"
	car.add_to_group("traffic_vehicle")
	game.add_child(car)
	car.global_position = player.global_position + front*PPM*85.0
	var canvas_transform := camera.get_viewport().get_canvas_transform()
	var out_of_view: Vector2 = canvas_transform*car.global_position
	check("fixture_is_actually_outside_current_camera_bounds",
		not Awareness.is_on_screen(out_of_view,
			camera.get_viewport().get_visible_rect().size))
	indicator.call("refresh_markers")
	check("approaching_offscreen_traffic_has_a_marker",
		_has_target(indicator,car))
	var fixture_marker: Dictionary = {}
	for candidate in indicator.get("markers"):
		if candidate.get("target") == car:
			fixture_marker = candidate
	check("traffic_marker_has_screen_bearing_and_distance",
		not fixture_marker.is_empty() and \
		float(fixture_marker.get("distance_m",0.0))>80.0 and \
		(fixture_marker.get("direction",Vector2.ZERO) as Vector2).length()>0.9)
	# Refresh the existing target's distance between discovery ticks.
	car.global_position = player.global_position + front*PPM*80.0
	indicator.set("_clock",0.08)
	indicator._process(1.0 / 60.0)
	var updated_distance := -1.0
	for candidate in indicator.get("markers"):
		if candidate.get("target") == car:
			updated_distance = float(candidate.get("distance_m",-1.0))
	check("distance_updates_each_frame_without_waiting_for_scan",
		absf(updated_distance - 80.0) < 0.1)
	# Warnings disappear immediately below the 40 mph cutoff.
	player.linear_velocity = front*(39.0/Awareness.MPS_TO_MPH)
	indicator._process(1.0 / 60.0)
	check("slowing_below_40_mph_clears_existing_warning",
		(indicator.get("markers") as Array).is_empty())
	player.linear_velocity = front*32.0
	indicator._process(1.0 / 60.0)
	check("passing_40_mph_rechecks_traffic_without_delay",
		_has_target(indicator,car))
	car.global_position = player.global_position + front*PPM*480.0
	indicator.call("refresh_markers")
	check("distant_480m_traffic_still_gets_warning",
		_has_target(indicator,car))
	# A tracked actor crossing the new 500 m boundary should disappear on
	# the next render frame, without waiting for the discovery timer.
	car.global_position = player.global_position + front*PPM*510.0
	indicator.set("_clock",0.08)
	indicator._process(1.0 / 60.0)
	check("tracked_traffic_above_500m_clears_without_delay",
		not _has_target(indicator,car))
	indicator.call("refresh_markers")
	check("traffic_over_500m_is_not_reacquired",
		not _has_target(indicator,car))
	car.global_position = player.global_position + front*PPM*6.0
	indicator.call("refresh_markers")
	check("visible_cars_do_not_receive_extra_edge_warning",
		not _has_target(indicator,car))
	car.global_position = player.global_position - front*PPM*85.0
	indicator.call("refresh_markers")
	check("traffic_behind_driver_is_not_highlighted",
		not _has_target(indicator,car))
	car.global_position = player.global_position + front*PPM*85.0
	car.remove_from_group("traffic_vehicle")
	car.add_to_group("race_opponent")
	indicator.call("refresh_markers")
	check("offscreen_race_opponent_uses_rival_style",
		_has_target(indicator,car) and \
		bool((indicator.get("markers") as Array)[0].get("rival",false)))
	paused = true
	indicator._process(0.2)
	check("paused_menus_suppress_warning_markers",
		(indicator.get("markers") as Array).is_empty())
	paused = false
	car.queue_free()
	await process_frame

	var split = game.local_split_screen
	var started: bool = split.start_split([7])
	check("split_screen_starts_with_test_controller",started)
	if started:
		var found := 0
		for awareness in get_nodes_in_group("streetbound_vehicle_awareness"):
			if awareness != indicator:
				for i in 2:
					if awareness.get_viewport() == split.split_views[i] and \
							awareness.get("camera") == split.split_cameras[i] and \
							awareness.get("player") == (game.vehicle if i==0 else split.player_two):
						found += 1
		check("split_viewports_each_get_correct_player_specific_warning",found==2,found)
		split.stop_split()
	game.queue_free()
	print("OFFSCREEN VEHICLE AWARENESS: ",
		"PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
