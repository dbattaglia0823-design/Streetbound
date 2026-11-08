extends "res://tests/driving_test.gd"
## Compare the arcade setup against the previous grip-racing setup with the
## same tire/engine specs. Measure heading change, not a spinning car's radius.
func run() -> void:
	car = Vehicle.instantiate()
	root.add_child(car)
	car.set_physics_process(false)
	await physics_frame
	var arcade_config := car.config.duplicate(true) as VehicleConfig
	var previous: Dictionary = {}
	for setup in ["grip", "arcade"]:
		car.config = arcade_config.duplicate(true)
		if setup == "grip":
			car.config.arcade_steering_assist = 0.0
			car.config.max_steer_degrees = 36
			car.config.high_speed_steer_degrees = 11
		for speed in [3.0, 12.0, 30.0, 42.0]:
			fresh(speed)
			var peak_slip := 0.0
			for i in 144:
				await physics_frame
				car.step_vehicle(1.0 / 120, Vector4(0.1, 0, 0.65, 0))
				peak_slip = maxf(peak_slip, absf(car.slip_angle))
			if setup == "grip":
				previous[speed] = car.rotation
			else:
				check("arcade_tighter_turn_%s" % speed, car.rotation > previous[speed] * 1.15, [previous[speed], car.rotation])
				check("arcade_stable_turn_%s" % speed, peak_slip < deg_to_rad(9), rad_to_deg(peak_slip))
	car.config = arcade_config.duplicate(true)
	var braking_headings: Array[float] = []
	for boost in [0.0, arcade_config.brake_turn_boost]:
		car.config.brake_turn_boost = boost
		fresh(25)
		await drive(1.0, Vector4(0, 0.65, 0.65, 0))
		braking_headings.append(car.rotation)
	check("braking_turn_boost", braking_headings[1] > braking_headings[0] * 1.1, braking_headings)
	car.config = arcade_config.duplicate(true)
	fresh(30)
	await drive(1.0, Vector4(0.1, 0, 0.65, 0))
	var asphalt_turn := car.rotation
	ground = Ground.new()
	root.add_child(ground)
	fresh(30)
	car.surface_provider = ground
	await drive(1.0, Vector4(0.1, 0, 0.65, 0))
	check("arcade_retains_surface_difference", car.surface == "GRASS" and car.rotation < asphalt_turn * 0.8, [asphalt_turn, car.rotation])
	fresh()
	await drive(1.0, Vector4(0, 0, 1, 0))
	check("stationary_steering_does_not_rotate_car", absf(car.rotation) < 0.001, car.rotation)
	# Full braking without steering must remain straight, even with the boost.
	fresh(25)
	await drive(1.0, Vector4(0, 1, 0, 0))
	check("arcade_straight_braking", absf(car.rotation) < 0.001 and absf(car.linear_velocity.x) < 0.001, car.rotation)
	print("ARCADE TUNE TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
