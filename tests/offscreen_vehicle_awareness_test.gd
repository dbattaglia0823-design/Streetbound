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


func _marker_for_target(indicator: Control, target: Node2D) -> Dictionary:
	for marker in indicator.get("markers"):
		if marker.get("target") == target:
			return marker
	return {}


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
			Vector2(0,-PPM*185.0),Vector2.ZERO).is_empty())
	check("stationary_player_has_no_traffic_indicators",
		Awareness.approach_info(from,Vector2.ZERO,forward,ahead,
			Vector2(0,20)).is_empty())
	check("traffic_indicators_require_speed_above_40_mph",
		not Awareness.player_is_fast_enough(Vector2(0,39.9/Awareness.MPS_TO_MPH)) and \
		Awareness.player_is_fast_enough(Vector2(0,40.1/Awareness.MPS_TO_MPH)) and \
		Awareness.approach_info(from,Vector2(0,-39.9/Awareness.MPS_TO_MPH),
			forward,ahead,Vector2.ZERO).is_empty())
	# Range is interpolated from 300 ft just above 40 mph to 600 ft at
	# 100 mph, with no benefit from exceeding 100 mph.
	var slow_speed := Vector2.UP * (40.1/Awareness.MPS_TO_MPH)
	var medium_speed := Vector2.UP * (70.0/Awareness.MPS_TO_MPH)
	var fast_speed := Vector2.UP * (100.0/Awareness.MPS_TO_MPH)
	var extreme_speed := Vector2.UP * (140.0/Awareness.MPS_TO_MPH)
	check("onscreen_hold_scales_from_one_second_to_quarter_second",
		is_equal_approx(Awareness.MAX_ONSCREEN_HOLD_S,1.0) and
		is_equal_approx(Awareness.MIN_ONSCREEN_HOLD_S,0.25) and
		is_equal_approx(Awareness.onscreen_hold_seconds(slow_speed),0.99875) and
		is_equal_approx(Awareness.onscreen_hold_seconds(medium_speed),0.625) and
		is_equal_approx(Awareness.onscreen_hold_seconds(fast_speed),0.25) and
		is_equal_approx(Awareness.onscreen_hold_seconds(extreme_speed),0.25))
	check("adaptive_range_starts_near_300_feet_and_scales_with_speed",
		is_equal_approx(Awareness.MIN_SPEED_RANGE_M,91.44) and
		absf(Awareness.detection_range_m(slow_speed)-91.5924)<0.1 and
		absf(Awareness.detection_range_m(medium_speed)-137.16)<0.05 and
		absf(Awareness.detection_range_m(fast_speed)-182.88)<0.05)
	check("adaptive_range_never_exceeds_600_feet",
		is_equal_approx(Awareness.MAX_RANGE_M,182.88) and
		absf(Awareness.detection_range_m(extreme_speed)-182.88)<0.01)
	check("just_over_40_mph_detects_only_short_range",
		not Awareness.approach_info(from,slow_speed,forward,
			Vector2.UP*PPM*90.0,Vector2.ZERO).is_empty() and
		Awareness.approach_info(from,slow_speed,forward,
			Vector2.UP*PPM*95.0,Vector2.ZERO).is_empty())
	check("70_mph_sees_450_feet_but_not_farther",
		not Awareness.approach_info(from,medium_speed,forward,
			Vector2.UP*PPM*135.0,Vector2.ZERO).is_empty() and
		Awareness.approach_info(from,medium_speed,forward,
			Vector2.UP*PPM*140.0,Vector2.ZERO).is_empty())
	check("100_mph_reaches_600_feet_and_not_beyond",
		not Awareness.approach_info(from,fast_speed,forward,
			Vector2.UP*PPM*182.0,Vector2.ZERO).is_empty() and
		Awareness.approach_info(from,fast_speed,forward,
			Vector2.UP*PPM*184.0,Vector2.ZERO).is_empty())
	# Broader awareness must see side traffic that is actually closing,
	# without warning for directly rearward or receding vehicles.
	var right_approach := Vector2.RIGHT * PPM * 110.0
	check("closing_cross_traffic_detected_at_90_degrees",
		not Awareness.approach_info(from,player_velocity,forward,
			right_approach,Vector2.LEFT * 22.0).is_empty())
	var rear_quarter := forward.rotated(deg_to_rad(130.0)) * PPM * 110.0
	check("wider_270_degree_cone_sees_rear_side_approach",
		is_equal_approx(Awareness.FORWARD_DOT,-0.7071067811865476) and \
		not Awareness.approach_info(from,player_velocity,forward,
			rear_quarter,-rear_quarter.normalized() * 35.0).is_empty())
	var excluded_rear := forward.rotated(deg_to_rad(150.0)) * PPM * 110.0
	check("directly_rearward_traffic_outside_wide_cone",
		Awareness.approach_info(from,player_velocity,forward,
			excluded_rear,-excluded_rear.normalized() * 35.0).is_empty())
	check("side_traffic_moving_away_is_still_filtered",
		Awareness.approach_info(from,player_velocity,forward,
			right_approach,Vector2.RIGHT * 15.0).is_empty())
	check("distance_is_labeled_in_feet_without_vehicle_type",
		Awareness.distance_caption(60.0)=="197 FT" and \
		Awareness.distance_caption(60.0,true)=="197 FT" and \
		Awareness.distance_caption(182.88)=="600 FT")
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
	# A previously detected offscreen target should keep its edge marker for
	# a moment after entering the viewport, then fade out automatically.
	var edge_before_entry: Vector2 = _marker_for_target(indicator,car).get(
		"position",Vector2.ZERO)
	car.global_position = player.global_position + front*PPM*12.0
	var visible_target: Vector2 = camera.get_viewport().get_canvas_transform()*car.global_position
	check("fixture_enters_camera_view_for_hold_test",
		Awareness.is_on_screen(visible_target,
			camera.get_viewport().get_visible_rect().size,0.0))
	indicator.set("_clock",0.08)
	indicator._process(1.0/60.0)
	var held := _marker_for_target(indicator,car)
	var expected_hold: float = Awareness.onscreen_hold_seconds(player.linear_velocity)
	check("visible_car_keeps_edge_indicator_briefly",
		not held.is_empty() and bool(held.get("onscreen_hold",false)) and
		absf(float(held.get("hold_remaining_s",0.0))-expected_hold)<0.01 and
		(held.get("position",Vector2.ZERO) as Vector2).distance_to(edge_before_entry)<0.01)
	indicator.call("refresh_markers")
	indicator.call("refresh_markers")
	var after_scans := _marker_for_target(indicator,car)
	check("discovery_scans_do_not_restart_hold_countdown",
		bool(after_scans.get("onscreen_hold",false)) and
		absf(float(after_scans.get("hold_remaining_s",0.0))-expected_hold)<0.01)
	indicator._process(expected_hold*0.5)
	var half_held := _marker_for_target(indicator,car)
	check("visible_marker_fades_with_remaining_hold_time",
		bool(half_held.get("onscreen_hold",false)) and
		float(half_held.get("hold_remaining_s",0.0))<expected_hold*0.55 and
		float(half_held.get("hold_remaining_s",0.0))>expected_hold*0.45)
	indicator._process(expected_hold*0.55)
	check("visible_marker_expires_in_under_one_second",
		not _has_target(indicator,car))
	indicator.call("refresh_markers")
	check("expired_onscreen_marker_is_not_reacquired",
		not _has_target(indicator,car))
	# A vehicle that was already on screen is never assigned a new warning.
	var already_visible := Node2D.new()
	already_visible.add_to_group("traffic_vehicle")
	game.add_child(already_visible)
	already_visible.global_position = player.global_position + front*PPM*10.0
	indicator.call("refresh_markers")
	check("new_onscreen_traffic_gets_no_edge_chip",
		not _has_target(indicator,already_visible))
	already_visible.queue_free()
	# If a previously seen car leaves view again, normal offscreen detection
	# resumes rather than keeping or restarting an old onscreen timer.
	car.global_position = player.global_position + front*PPM*80.0
	indicator.call("refresh_markers")
	check("offscreen_target_can_be_detected_again",
		_has_target(indicator,car))
	car.global_position = player.global_position + front*PPM*12.0
	indicator._process(1.0/60.0)
	player.linear_velocity = front*(100.0/Awareness.MPS_TO_MPH)
	indicator._process(0.30)
	check("acceleration_shortens_existing_onscreen_hold",
		not _has_target(indicator,car))
	# Re-arm the offscreen marker for existing 40 mph cut-off tests.
	player.linear_velocity = front*32.0
	car.global_position = player.global_position + front*PPM*80.0
	indicator.call("refresh_markers")
	check("rearmed_marker_is_active_before_cutoff",
		_has_target(indicator,car))
	# Warnings disappear immediately below the 40 mph cutoff.
	player.linear_velocity = front*(39.0/Awareness.MPS_TO_MPH)
	indicator._process(1.0 / 60.0)
	check("slowing_below_40_mph_clears_existing_warning",
		(indicator.get("markers") as Array).is_empty())
	player.linear_velocity = front*32.0
	indicator._process(1.0 / 60.0)
	check("passing_40_mph_rechecks_traffic_without_delay",
		_has_target(indicator,car))
	# At ~72 mph the dynamic range is about 458 ft, not the 600 ft cap.
	car.global_position = player.global_position + front*PPM*130.0
	indicator.call("refresh_markers")
	check("medium_speed_warns_for_traffic_in_dynamic_range",
		_has_target(indicator,car))
	# The HUD must discard existing markers as soon as a slowing vehicle's
	# range shrinks, without waiting for the 100 ms discovery timer.
	player.linear_velocity = front*(55.0/Awareness.MPS_TO_MPH)
	indicator.set("_clock",0.08)
	indicator._process(1.0 / 60.0)
	check("slowing_reduces_range_on_next_render_frame",
		not _has_target(indicator,car))
	# At 100 mph, traffic approaching from within 600 ft is visible.
	player.linear_velocity = front*(100.0/Awareness.MPS_TO_MPH)
	car.global_position = player.global_position + front*PPM*180.0
	indicator.call("refresh_markers")
	check("fast_speed_acquires_traffic_at_590_feet",
		_has_target(indicator,car))
	# The absolute 600 ft limit still removes targets in between scans.
	car.global_position = player.global_position + front*PPM*185.0
	indicator.set("_clock",0.08)
	indicator._process(1.0 / 60.0)
	check("tracked_traffic_above_600_feet_clears_without_delay",
		not _has_target(indicator,car))
	indicator.call("refresh_markers")
	check("traffic_over_600_feet_is_not_reacquired",
		not _has_target(indicator,car))
	player.linear_velocity = front*32.0
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
