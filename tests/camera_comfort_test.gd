extends SceneTree
## Verifies car-follow camera comfort without touching actual driving physics.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(name: String, condition: bool, value: Variant) -> void:
	print("%s %s: %s" % ["PASS" if condition else "FAIL", name, value])
	if not condition:
		failures.append(name)

func run() -> void:
	var main: Node = load("res://scenes/proving_ground.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var car: VehicleController2D = main.vehicle
	var camera: Camera2D
	for child in main.get_children():
		if child is Camera2D:
			camera = child
	check("camera_exists", camera != null, camera)
	if camera == null:
		quit(1)
		return
	check("driving_world_magnified_twenty_percent",
		is_equal_approx(float(camera.world_zoom_multiplier), 1.20),
		camera.world_zoom_multiplier)
	check("camera_starts_at_magnified_zoom_without_pop",
		is_equal_approx(camera.zoom.x, 1.06 * 1.20) and
		is_equal_approx(camera.zoom.x, camera.zoom.y),
		camera.zoom)
	# Stop automatic stepping so this test controls speed/heading deterministically.
	car.set_physics_process(false)
	camera.set_physics_process(false)
	camera.follow_heading = true
	camera.rotation = 0.0
	car.linear_velocity = Vector2.UP * 30.0
	car.longitudinal_speed = 30.0
	car.rotation = deg_to_rad(8.0)
	for i in 100:
		camera._physics_process(1.0 / 60.0)
	check("small_heading_change_keeps_world_stable",
		absf(rad_to_deg(camera.rotation)) < 0.01, rad_to_deg(camera.rotation))

	# A hard 90-degree steering change must not immediately swing the whole scene.
	car.rotation = deg_to_rad(90.0)
	var previous: float = camera.rotation
	var max_frame_step := 0.0
	for i in 12:
		camera._physics_process(1.0 / 60.0)
		var step: float = absf(wrapf(camera.rotation - previous, -PI, PI))
		max_frame_step = maxf(max_frame_step, step)
		previous = camera.rotation
	check("camera_turn_rate_is_bounded",
		max_frame_step <= deg_to_rad(70.0) / 60.0 + 0.0001,
		rad_to_deg(max_frame_step) * 60.0)
	check("camera_lags_rapid_turn",
		camera.rotation > deg_to_rad(1.0) and camera.rotation < deg_to_rad(35.0),
		rad_to_deg(camera.rotation))
	for i in 240:
		camera._physics_process(1.0 / 60.0)
	check("camera_catches_up_without_locking",
		absf(rad_to_deg(wrapf(car.rotation - camera.rotation, -PI, PI))) <= 13.0,
		rad_to_deg(camera.rotation))

	# Spins while stationary should not rotate the camera or induce nausea.
	car.linear_velocity = Vector2.ZERO
	car.longitudinal_speed = 0.0
	var resting_heading: float = camera.rotation
	car.rotation += PI
	for i in 160:
		camera._physics_process(1.0 / 60.0)
	check("stationary_spin_does_not_move_camera",
		absf(wrapf(camera.rotation - resting_heading, -PI, PI)) < deg_to_rad(0.1),
		rad_to_deg(camera.rotation))

	# North-up remains accessible and smoothly returns to zero.
	camera.follow_heading = false
	for i in 240:
		camera._physics_process(1.0 / 60.0)
	check("north_up_returns_to_zero", absf(camera.rotation) < deg_to_rad(0.2), rad_to_deg(camera.rotation))

	# Crossing the wrap boundary (+179 to -179) must not trigger a full spin.
	camera.follow_heading = true
	camera.rotation = deg_to_rad(-179.0)
	car.rotation = deg_to_rad(179.0)
	car.linear_velocity = Vector2.UP * 30.0
	var before_wrap: float = camera.rotation
	camera._physics_process(1.0 / 60.0)
	check("wraparound_uses_shortest_heading",
		absf(wrapf(camera.rotation - before_wrap, -PI, PI)) < deg_to_rad(0.1),
		rad_to_deg(camera.rotation))

	print("CAMERA COMFORT TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
