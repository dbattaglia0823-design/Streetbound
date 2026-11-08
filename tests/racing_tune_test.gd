extends "res://tests/driving_test.gd"
## Compare the stock racing tune to the previous setup at the same speed/input.
func run() -> void:
	car = Vehicle.instantiate()
	root.add_child(car)
	car.set_physics_process(false)
	await physics_frame
	var racing := car.config.duplicate(true) as VehicleConfig
	var previous_results: Dictionary = {}
	for setup in ["previous", "racing"]:
		car.config = racing.duplicate(true)
		if setup == "previous":
			car.config.tire_grip = 1.15
			car.config.cornering_stiffness = 68000
			car.config.rear_cornering_stiffness_ratio = 1.0
			car.config.rear_grip_balance = 1.12
			car.config.yaw_damping = 1.2
			car.config.countersteer_assist = 0.45
			car.config.high_speed_steer_degrees = 9
			car.config.max_steer_degrees = 32
		for speed in [20.0, 30.0, 42.0]:
			for steer in [0.5, 1.0]:
				fresh(speed)
				var max_slip := 0.0
				for i in 360:
					await physics_frame
					car.step_vehicle(1.0 / 120, Vector4(1.0, 0, steer, 0))
					max_slip = maxf(max_slip, absf(car.slip_angle))
				var radius := car.linear_velocity.length() / maxf(absf(car.yaw_rate), 0.001)
				print("%s %.0f m/s steer %.1f: peak slip %.2f deg | radius %.1f m | speed %.1f" % [setup, speed, steer, rad_to_deg(max_slip), radius, car.linear_velocity.length()])
				var key := "%s_%s" % [speed, steer]
				if setup == "previous":
					previous_results[key] = Vector2(max_slip, radius)
				else:
					var old: Vector2 = previous_results[key]
					check("racing_grip_" + key, max_slip < deg_to_rad(7) and max_slip < old.x * 0.95, rad_to_deg(max_slip))
					# A spinning car can report a small radius; only compare turns
					# that the old setup could complete without a large slide.
					if old.x < deg_to_rad(10):
						check("tighter_turn_" + key, radius < old.y * 0.9, [old.y, radius])
	# Fast alternating inputs should not produce an unintended drift or spin.
	car.config = racing.duplicate(true)
	fresh(35)
	var slalom_peak := 0.0
	for side in [1.0, -1.0, 1.0, -1.0]:
		for i in 90:
			await physics_frame
			car.step_vehicle(1.0 / 120, Vector4(0.75, 0, side, 0))
			slalom_peak = maxf(slalom_peak, absf(car.slip_angle))
	check("racing_direction_changes", slalom_peak < deg_to_rad(9), rad_to_deg(slalom_peak))
	# Check that lifting or using partial throttle doesn't destabilize the rear.
	for pedal in [0.0, 0.4]:
		fresh(35)
		var corner_slip := 0.0
		for i in 360:
			await physics_frame
			car.step_vehicle(1.0 / 120, Vector4(pedal, 0, 1, 0))
			corner_slip = maxf(corner_slip, absf(car.slip_angle))
		check("racing_lift_corner_" + str(pedal), corner_slip < deg_to_rad(9) and car.linear_velocity.length() > 15, rad_to_deg(corner_slip))
	fresh(35)
	var brake_slip := 0.0
	for i in 240:
		await physics_frame
		car.step_vehicle(1.0 / 120, Vector4(0, 0.4, 0.8, 0))
		brake_slip = maxf(brake_slip, absf(car.slip_angle))
	check("racing_braking_corner", brake_slip < deg_to_rad(9), rad_to_deg(brake_slip))
	print("RACING TUNE TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
