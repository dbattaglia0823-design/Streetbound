extends SceneTree
## Four independent visual wheels follow the existing vehicle steering state.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, value: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL", label, value])
	if not passed:
		failures.append(label)

func run() -> void:
	var main: Node = load("res://scenes/proving_ground.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var car: VehicleController2D = main.vehicle
	car.set_physics_process(false)
	var art: Node2D = car.get_node("Art")
	var rig: Variant = art.get_node("Wheels")
	var sprite: Sprite2D = art.get_node("Sprite")
	check("rig_behind_body", rig.z_index < sprite.z_index, [rig.z_index, sprite.z_index])
	check("wheels_share_body_motion", rig.get_parent() == art)
	check("four_wheels_present", rig.get_child_count() == 4, rig.get_child_count())
	var fl: Node2D = rig.get_node("FrontLeft")
	var fr: Node2D = rig.get_node("FrontRight")
	var rl: Node2D = rig.get_node("RearLeft")
	var rr: Node2D = rig.get_node("RearRight")
	check("front_and_rear_order", fl.position.y < 0.0 and rl.position.y > 0.0,
		[fl.position, rl.position])
	check("left_right_pair_alignment", is_equal_approx(fl.position.x + fr.position.x, rl.position.x + rr.position.x)
		and fl.position.x < fr.position.x and rl.position.x < rr.position.x,
		[fl.position, fr.position, rl.position, rr.position])
	var size: Vector2 = rig.tire_size
	check("smaller_wheel_size_reasonable", size.x >= 4.0 and size.x <= 10.0
		and size.y >= 12.0 and size.y <= 21.0, size)
	var profile: VehicleAppearanceProfile = rig.appearance
	var bounds: Rect2 = rig.visible_bounds
	var original_width: float = clampf(bounds.size.x * profile.tire_width_ratio,
		minf(profile.minimum_tire_px.x, profile.maximum_tire_px.x),
		maxf(profile.minimum_tire_px.x, profile.maximum_tire_px.x))
	check("tire_width_is_calibrated_smaller_than_original",
		is_equal_approx(size.x, original_width * rig.visual_tire_width_scale) and
		rig.visual_tire_width_scale <= 0.62 and size.x < original_width,
		[size.x, original_width])
	var original_length: float = clampf(bounds.size.y *
		profile.tire_length_ratio,
		minf(profile.minimum_tire_px.y, profile.maximum_tire_px.y),
		maxf(profile.minimum_tire_px.y, profile.maximum_tire_px.y))
	check("tire_length_is_reduced_for_all_models",
		is_equal_approx(size.y,
			original_length * rig.visual_tire_length_scale) and
		rig.visual_tire_length_scale <= 0.80,
		[size.y, original_length])
	var left_edge_anchor := bounds.position.x + bounds.size.x * profile.front_left_uv.x
	var right_edge_anchor := bounds.position.x + bounds.size.x * profile.front_right_uv.x
	check("front_wheels_inset_toward_body_center",
		fl.position.x > left_edge_anchor and fr.position.x < right_edge_anchor,
		[fl.position.x, fr.position.x, left_edge_anchor, right_edge_anchor])
	check("visual_wheels_have_no_colliders",
		not (fl is CollisionObject2D) and not (rl is CollisionObject2D))
	var car_heading: float = car.rotation
	var shape: Shape2D = car.get_node("CollisionShape2D").shape

	car.steering = deg_to_rad(20.0)
	for i in 10:
		rig._process(1.0 / 60.0)
	check("front_wheels_follow_physical_steer", fl.rotation > deg_to_rad(15.0)
		and is_equal_approx(fl.rotation, fr.rotation), rad_to_deg(fl.rotation))
	check("rear_wheels_stay_straight", is_zero_approx(rl.rotation) and is_zero_approx(rr.rotation))
	check("visual_steering_does_not_change_vehicle",
		is_equal_approx(car.rotation, car_heading) and car.get_node("CollisionShape2D").shape == shape)
	car.steering = deg_to_rad(-50.0)
	for i in 30:
		rig._process(1.0 / 60.0)
	check("reverse_steer_is_less_exaggerated_and_clamped",
		fl.rotation <= deg_to_rad(-24.0) and
		fl.rotation >= -deg_to_rad(float(rig.VISUAL_STEER_LIMIT_DEGREES)) - 0.001,
		rad_to_deg(fl.rotation))
	check("actual_physical_steering_not_modified_by_visual_limit",
		is_equal_approx(car.steering, deg_to_rad(-50.0)), car.steering)
	car.reset_vehicle()
	for i in 30:
		rig._process(1.0 / 60.0)
	check("reset_realigns_front", absf(fl.rotation) < deg_to_rad(0.05) and
		absf(fr.rotation) < deg_to_rad(0.05), [fl.rotation, fr.rotation])
	check("reset_keeps_rear_straight", is_zero_approx(rl.rotation) and is_zero_approx(rr.rotation))

	print("WHEEL VISUAL TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
