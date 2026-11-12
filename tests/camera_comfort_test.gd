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
	# Mouse wheel is an unhandled driving-camera input; UI map scroll
	# consumes its own wheel events before they reach the world camera.
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	var wheel_down := InputEventMouseButton.new()
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	camera._unhandled_input(wheel_up)
	check("wheel_up_zooms_toward_car",
		camera.player_zoom_multiplier > 1.0,
		camera.player_zoom_multiplier)
	camera._unhandled_input(wheel_down)
	check("wheel_down_zooms_away_from_car",
		is_equal_approx(camera.player_zoom_multiplier, 1.0),
		camera.player_zoom_multiplier)
	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_WHEEL_UP
	released.pressed = false
	camera._unhandled_input(released)
	check("wheel_release_does_not_zoom",
		is_equal_approx(camera.player_zoom_multiplier, 1.0),
		camera.player_zoom_multiplier)
	for i in 30:
		camera._unhandled_input(wheel_up)
	check("close_zoom_hard_limited",
		is_equal_approx(camera.player_zoom_multiplier, camera.PLAYER_ZOOM_MAX),
		camera.player_zoom_multiplier)
	for i in 60:
		camera._unhandled_input(wheel_down)
	check("far_zoom_hard_limited",
		is_equal_approx(camera.player_zoom_multiplier, camera.PLAYER_ZOOM_MIN),
		camera.player_zoom_multiplier)
	check("zoom_is_proportional_not_fixed_world_units",
		absf(camera.stepped_player_zoom(1.3, 1) - 1.3) >
		absf(camera.stepped_player_zoom(0.75, 1) - 0.75),
		[camera.stepped_player_zoom(1.3, 1),
			camera.stepped_player_zoom(0.75, 1)])
	var before_paused: float = camera.player_zoom_multiplier
	paused = true
	camera._unhandled_input(wheel_up)
	paused = false
	check("paused_camera_ignores_wheel_input",
		is_equal_approx(camera.player_zoom_multiplier, before_paused),
		camera.player_zoom_multiplier)
	# User zoom must not accumulate into an unbounded speed-driven zoom
	# when driving quickly or after a hard launch/impact.
	for value in [camera.PLAYER_ZOOM_MIN, 1.0, camera.PLAYER_ZOOM_MAX]:
		for speed in [0.0, 30.0, 65.0]:
			var result: float = camera.target_zoom_for(speed, value, 1.20, 1.0, 1.0)
			check("absolute_zoom_bounds_%.2f_%.0f" % [value, speed],
				result >= camera.ABSOLUTE_ZOOM_MIN and
				result <= camera.ABSOLUTE_ZOOM_MAX, result)
	check("speed_auto_zoom_tapers_at_both_manual_extremes",
		camera.speed_zoom_weight(camera.PLAYER_ZOOM_MIN) < 1.0 and
		camera.speed_zoom_weight(camera.PLAYER_ZOOM_MAX) < 1.0 and
		is_equal_approx(camera.speed_zoom_weight(1.0), 1.0),
		[camera.speed_zoom_weight(camera.PLAYER_ZOOM_MIN),
			camera.speed_zoom_weight(camera.PLAYER_ZOOM_MAX)])
	check("at_default_settings_camera_still_widens_with_speed",
		camera.target_zoom_for(45.0, 1.0, 1.20) <
		camera.target_zoom_for(0.0, 1.0, 1.20), camera.zoom)
	# Smooth input response should never jump directly to the new target.
	camera.player_zoom_multiplier = 1.0
	camera._smoothed_player_zoom = 1.0
	var zoom_at_rest: float = camera.zoom.x
	camera._unhandled_input(wheel_up)
	camera._physics_process(1.0 / 60.0)
	check("first_wheel_frame_is_smoothed",
		camera.zoom.x > zoom_at_rest and
		camera.zoom.x < camera.target_zoom_for(0.0,
			camera.player_zoom_multiplier, camera.world_zoom_multiplier),
		camera.zoom.x)
	for i in 150:
		camera._physics_process(1.0 / 60.0)
	check("manual_camera_zoom_converges_without_overshoot",
		absf(camera.zoom.x - camera.target_zoom_for(0.0,
			camera.player_zoom_multiplier, camera.world_zoom_multiplier)) < 0.002,
		camera.zoom.x)
	# Restore normal framing for the existing heading-control tests.
	camera.player_zoom_multiplier = 1.0
	camera._smoothed_player_zoom = 1.0
	camera.zoom = Vector2.ONE * (1.06 * camera.world_zoom_multiplier)
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
