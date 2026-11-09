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
	check("wheel_size_reasonable", size.x >= 8.0 and size.x <= 15.0
		and size.y >= 16.0 and size.y <= 26.0, size)
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
	check("reverse_steer_clamped", fl.rotation <= deg_to_rad(-30.0) and
		fl.rotation >= -deg_to_rad(float(rig.max_visual_steer_degrees)) - 0.001,
		rad_to_deg(fl.rotation))
	car.reset_vehicle()
	for i in 30:
		rig._process(1.0 / 60.0)
	check("reset_realigns_front", absf(fl.rotation) < deg_to_rad(0.05) and
		absf(fr.rotation) < deg_to_rad(0.05), [fl.rotation, fr.rotation])
	check("reset_keeps_rear_straight", is_zero_approx(rl.rotation) and is_zero_approx(rr.rotation))

	print("WHEEL VISUAL TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
