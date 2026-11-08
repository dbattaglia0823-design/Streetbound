extends "res://tests/driving_test.gd"
## Regression coverage for the handbrake-release direction-change exploit.

func make_slide() -> void:
	fresh(22)
	await drive(0.7, Vector4(0.3, 0, 0.7, 0))
	await drive(0.5, Vector4(0.7, 0, 0.7, 1))

func run() -> void:
	car = Vehicle.instantiate()
	root.add_child(car)
	car.set_physics_process(false)
	await physics_frame
	await make_slide()
	var entry_velocity := car.linear_velocity
	var entry_slip := absf(car.slip_angle)
	await drive(1.0 / 120, Vector4(1, 0, 0, 0))
	var direction_change := absf(entry_velocity.angle_to(car.linear_velocity))
	check("release_preserves_slide", car.handbrake_grip_loss > 0.9 and absf(car.slip_angle) > entry_slip * 0.8,
		[car.handbrake_grip_loss, rad_to_deg(entry_slip), rad_to_deg(car.slip_angle)])
	check("release_does_not_snap_momentum", direction_change < deg_to_rad(1), rad_to_deg(direction_change))
	check("sliding_disables_direction_assist", car.arcade_assist_fraction < 0.01, car.arcade_assist_fraction)
	var max_spin := 0.0
	for i in 36:
		await physics_frame
		car.step_vehicle(1.0 / 120, Vector4(1, 0, -0.5, 0))
		max_spin = maxf(max_spin, car.wheel_spin)
	check("power_after_release_spins_driven_wheels", max_spin > 0.1, max_spin)
	check("rear_grip_recovers_briefly_not_like_ice", car.handbrake_grip_loss > 0.05 and car.handbrake_grip_loss < 0.3, car.handbrake_grip_loss)
	await drive(0.35, Vector4(1, 0, -0.5, 0))
	check("powered_exit_regains_contact_promptly", car.handbrake_grip_loss == 0.0 and car.wheel_spin < 0.15, [car.handbrake_grip_loss, car.wheel_spin])
	# Throttle must produce useful propulsion while the rear is stepping out,
	# not just increase wheelspin with almost no transmitted force.
	var pull_speeds: Array[float] = []
	var pull_slips: Array[float] = []
	var pull_spins: Array[float] = []
	var release_speeds: Array[float] = []
	var release_progress: Array[float] = []
	for pedal in [0.0, 0.5, 1.0]:
		fresh(22)
		await drive(0.5, Vector4(pedal, 0, 0.7, 1))
		pull_speeds.append(car.linear_velocity.length())
		pull_slips.append(absf(car.slip_angle))
		pull_spins.append(car.wheel_spin)
		await make_slide()
		var release_position := car.position
		var release_heading := Vector2.UP.rotated(car.rotation)
		await drive(0.3, Vector4(pedal, 0, -0.5, 0))
		release_speeds.append(car.linear_velocity.length())
		release_progress.append((car.position - release_position).dot(release_heading) / car.PIXELS_PER_METER)
	check("throttle_powers_handbrake_drift", pull_speeds[2] > pull_speeds[0] + 1.0 and pull_speeds[1] > pull_speeds[0], pull_speeds)
	check("throttle_controls_power_slip", pull_spins[2] > pull_spins[1] and pull_spins[1] > pull_spins[0] and pull_spins[2] <= 0.55, pull_spins)
	check("powered_handbrake_remains_controllable", pull_slips[2] > deg_to_rad(5) and pull_slips[2] < deg_to_rad(45), rad_to_deg(pull_slips[2]))
	check("throttle_drives_release_instead_of_free_spinning", release_speeds[2] > release_speeds[0] + 0.5 and release_progress[2] > release_progress[0] + 0.1,
		[release_speeds, release_progress])
	# Releasing the accelerator should settle the tires sooner than flooring it.
	var recovery: Array[float] = []
	for pedal in [0.0, 1.0]:
		await make_slide()
		var peak := 0.0
		var elapsed := 0.0
		for i in 720:
			await physics_frame
			var countersteer := clampf(car.slip_angle * 1.5 - car.yaw_rate * 0.15, -1.0, 1.0)
			car.step_vehicle(1.0 / 120, Vector4(pedal, 0, countersteer, 0))
			peak = maxf(peak, car.wheel_spin)
			elapsed += 1.0 / 120
			if car.handbrake_grip_loss == 0.0 and car.wheel_spin == 0.0:
				break
		recovery.append(elapsed)
		print("Recovery pedal %.1f: %.3f s | peak wheelspin %.3f | slip %.2f deg" % [pedal, elapsed, peak, rad_to_deg(car.slip_angle)])
		check("eventual_tire_recovery_" + str(pedal), car.handbrake_grip_loss == 0.0 and car.wheel_spin == 0.0 and elapsed < 1.6, elapsed)
	check("lifting_restores_contact_sooner", recovery[0] < recovery[1] * 0.9, recovery)
	# Same right-angle corner, engine, entry speed and steering policy. Time the
	# exit only when the car is actually traveling along it, rather than sideways.
	var exit_times: Array[float] = []
	for strategy in ["clean", "handbrake", "repeated_handbrake"]:
		fresh(25)
		var start_x := car.position.x
		var finish := 12.0
		for i in 1440:
			await physics_frame
			var elapsed := float(i) / 120
			var hand := 0.0
			if strategy == "handbrake" and elapsed >= 0.2 and elapsed < 0.65:
				hand = 1.0
			elif strategy == "repeated_handbrake" and elapsed < 4.0 and i % 72 < 18:
				hand = 1.0
			var steer := clampf(angle_difference(car.rotation, PI / 2) * 2.0 + car.slip_angle * 0.6 - car.yaw_rate * 0.15, -1.0, 1.0)
			car.step_vehicle(1.0 / 120, Vector4(1, 0, steer, hand))
			if car.position.x > start_x + 1400 and absf(angle_difference(car.rotation, PI / 2)) < deg_to_rad(12) and absf(car.slip_angle) < deg_to_rad(8):
				finish = elapsed + 1.0 / 120
				break
		exit_times.append(finish)
		print("Corner exit %s: %.3f s | speed %.2f m/s" % [strategy, finish, car.linear_velocity.length()])
	check("clean_line_beats_handbrake_shortcut", exit_times[0] < exit_times[1] and exit_times[0] < exit_times[2], exit_times)
	fresh()
	await drive(0.5, Vector4(0, 0, 0, 1))
	await drive(0.1, Vector4(0, 0, 0, 0))
	check("parked_handbrake_does_not_create_slide", car.handbrake_grip_loss == 0.0 and car.wheel_spin == 0.0, [car.handbrake_grip_loss, car.wheel_spin])
	car.handbrake_grip_loss = 0.8
	car.wheel_spin = 0.6
	car.reset_vehicle()
	check("reset_clears_tire_state", car.handbrake_grip_loss == 0.0 and car.wheel_spin == 0.0 and car.arcade_assist_fraction == 0.0, car.wheel_spin)
	print("HANDBRAKE RECOVERY TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
