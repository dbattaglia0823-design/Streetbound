extends SceneTree
## Runs against the actual controller and Godot collision world, without addons.
const Vehicle = preload("res://scenes/vehicle.tscn")
const Ground = preload("res://scripts/world/proving_ground.gd")
var car: VehicleController2D
var ground: ProvingGround
var results: Dictionary = {}
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(name: String, condition: bool, value: Variant) -> void:
	results[name] = value
	if not condition:
		failures.append(name)
	print("%s %s: %s" % ["PASS" if condition else "FAIL", name, value])

func fresh(speed := 0.0) -> void:
	car.reset_vehicle()
	# Isolate handling traces from the proving-ground perimeter. Collision
	# scenarios explicitly place the car next to their target barrier.
	car.position = Vector2(-8000, 0)
	car.surface_provider = null
	car.linear_velocity = Vector2.UP * speed

func drive(seconds: float, input: Vector4) -> void:
	for i in roundi(seconds * 120):
		await physics_frame
		car.step_vehicle(1.0 / 120, input)

func run() -> void:
	ground = Ground.new()
	root.add_child(ground)
	car = Vehicle.instantiate()
	root.add_child(car)
	car.set_physics_process(false)
	await physics_frame
	fresh()
	await drive(6.0, Vector4(1, 0, 0, 0))
	var start_speed := car.linear_velocity.length()
	check("starting", start_speed > 20.0, start_speed)
	check("auto_upshift", car.transmission.gear > 1, car.transmission.gear)
	results["straight_position"] = [car.position.x, car.position.y]
	fresh(20)
	# Measure the first stop rather than holding past it: grippier setups stop
	# sooner and a continued brake hold intentionally engages reverse.
	for i in 360:
		await physics_frame
		car.step_vehicle(1.0 / 120, Vector4(0, 1, 0, 0))
		if car.linear_velocity.length() < 0.1:
			break
	check("stopping_before_reverse", absf(car.longitudinal_speed) < 0.7 and not car.reversing, car.longitudinal_speed)
	await drive(2.0, Vector4(0, 1, 0, 0))
	check("reverse", car.reversing and car.longitudinal_speed < -2.0, car.longitudinal_speed)
	fresh(-3)
	car.reversing = true
	await drive(1, Vector4(0, 0.1, 0.5, 0))
	check("reverse_steering", car.rotation < -0.1, car.rotation)
	fresh(4)
	await drive(1.5, Vector4(0.15, 0, 0.65, 0))
	check("low_speed_turn", car.rotation > 0.25 and car.linear_velocity.is_finite(), car.rotation)
	# A right steer must accelerate the car right, not just rotate its body.
	fresh(15)
	await drive(0.4, Vector4(0.2, 0, 0.5, 0))
	check("tire_force_direction", car.linear_velocity.x > 0.5 and car.rotation > 0.0, [car.linear_velocity.x, car.rotation])
	# Released wheels center even with lateral slip, in either direction and
	# when parked, moving forward or reversing. No overshoot or assist offset.
	for test_speed in [0.0, 20.0, -5.0]:
		for side in [-1.0, 1.0]:
			fresh(test_speed)
			car.steering = deg_to_rad(20.0) * side
			if test_speed != 0.0:
				car.linear_velocity.x = 2.0
			var monotonic := true
			var previous_angle := absf(car.steering)
			for i in 30:
				await physics_frame
				car.step_vehicle(1.0 / 120, Vector4.ZERO)
				monotonic = monotonic and absf(car.steering) <= previous_angle and car.steering * side >= 0.0
				previous_angle = absf(car.steering)
			check("wheel_center_%s_%s" % [test_speed, side], monotonic and absf(car.steering) < deg_to_rad(0.3), rad_to_deg(car.steering))
	fresh()
	car.steering = deg_to_rad(20)
	car.config.steering_return_strength = 4.0
	await drive(0.25, Vector4.ZERO)
	check("return_strength_resource", rad_to_deg(car.steering) > 5.0, rad_to_deg(car.steering))
	car.config.steering_return_strength = 18.0
	fresh(42)
	await drive(3, Vector4(0.3, 0, 0.5, 0))
	check("high_speed_turn", car.rotation > 0.1 and absf(car.yaw_rate) < 2.4 and car.linear_velocity.length() > 20, [car.rotation, car.yaw_rate, car.slip_angle])
	check("high_speed_slip_control", absf(car.slip_angle) < 0.4, car.slip_angle)
	fresh(22)
	await drive(0.7, Vector4(0.3, 0, 0.7, 0))
	await drive(0.7, Vector4(0.4, 0, 0.7, 1))
	var drift_slip := absf(car.slip_angle)
	check("handbrake_drift", drift_slip > 0.15 and drift_slip < 1.5, drift_slip)
	# Countersteer opposite the slide, then let the rear tires recover.
	await drive(0.5, Vector4(0.25, 0, -0.6, 0))
	await drive(3, Vector4(0.2, 0, 0, 0))
	check("drift_recovery", absf(car.slip_angle) < 0.2, car.slip_angle)
	fresh()
	await drive(3, Vector4(1, 0, 0, 0))
	var asphalt_speed := car.linear_velocity.length()
	fresh()
	car.surface_provider = ground
	await drive(3, Vector4(1, 0, 0, 0))
	check("grass_traction", car.surface == "GRASS" and car.linear_velocity.length() < asphalt_speed * 0.85, [asphalt_speed, car.linear_velocity.length()])
	check("gravel_detection", ground.surface_at(Vector2(1300, -1000)).name == "GRAVEL", ground.surface_at(Vector2(1300, -1000)))
	fresh()
	car.surface_provider = ground
	car.position = Vector2(-1000, -1400)
	car.linear_velocity = Vector2.UP * 25
	var impacts: Array[float] = []
	car.impacted.connect(func(strength: float): impacts.append(strength))
	await drive(0.8, Vector4.ZERO)
	check("barrier_collision", not impacts.is_empty() and car.position.y > -1600 and car.linear_velocity.length() < 10, [car.position.y, car.linear_velocity.length(), impacts.size()])
	check("post_collision_velocity_sync", car.velocity.distance_to(car.linear_velocity * car.PIXELS_PER_METER) < 0.01,
		[car.velocity, car.linear_velocity])
	car.throttle = 1.0
	car.brake = 0.5
	car.handbrake = 1.0
	car.longitudinal_speed = 35.0
	car.lateral_speed = 4.0
	car.slip_angle = 0.15
	car.command = Vector4(1, 1, 1, 1)
	car.reset_vehicle()
	check("reset", car.transform == car.spawn_transform and car.linear_velocity == Vector2.ZERO and car.yaw_rate == 0, car.position)
	check("reset_telemetry_and_inputs", car.longitudinal_speed == 0.0 and car.lateral_speed == 0.0
		and car.slip_angle == 0.0 and car.throttle == 0.0 and car.brake == 0.0 and car.handbrake == 0.0
		and car.command == Vector4.ZERO and car.cornering_grip_fraction == 1.0,
		[car.longitudinal_speed, car.lateral_speed, car.slip_angle, car.command])
	fresh(25)
	await drive(0.15, Vector4(3.0, -2.0, 8.0, 4.0))
	check("normalized_external_commands", car.throttle == 1.0 and car.brake == 0.0 and car.handbrake == 1.0
		and absf(car.steering) <= deg_to_rad(car.config.max_steer_degrees) + 0.02,
		[car.throttle, car.brake, car.handbrake, rad_to_deg(car.steering)])
	fresh(25)
	await drive(0.15, Vector4(0, 1, 0.5, 0))
	check("braking_consumes_lateral_tire_grip", car.cornering_grip_fraction >= 0.0
		and car.cornering_grip_fraction < 0.80, car.cornering_grip_fraction)
	fresh(25)
	await drive(0.15, Vector4(0, 0, 0.5, 0))
	check("coasting_retains_full_tire_grip", is_equal_approx(car.cornering_grip_fraction, 1.0),
		car.cornering_grip_fraction)
	# Specs genuinely affect acceleration, grip and drivetrain behavior.
	fresh()
	car.config.engine_torque_nm *= 0.45
	car.config.engine_power_kw *= 0.45
	await drive(3, Vector4(1, 0, 0, 0))
	check("power_resource_response", car.linear_velocity.length() < asphalt_speed * 0.85, car.linear_velocity.length())
	car.config.engine_torque_nm /= 0.45
	car.config.engine_power_kw /= 0.45
	var drive_speeds: Array[float] = []
	for drivetrain in 3:
		fresh()
		car.config.drivetrain = drivetrain
		await drive(2, Vector4(1, 0, 0, 0))
		drive_speeds.append(car.linear_velocity.length())
	check("drivetrain_response", drive_speeds[2] > drive_speeds[1] and drive_speeds[1] > drive_speeds[0], drive_speeds)
	# A repeatable steering/shift/drift trace for render-FPS comparisons.
	car.config.drivetrain = VehicleConfig.Drivetrain.RWD
	fresh()
	await drive(4, Vector4(1, 0, 0, 0))
	await drive(1.5, Vector4(0.6, 0, 0.45, 0))
	await drive(0.5, Vector4(0.3, 0, 0.7, 1))
	await drive(1.0, Vector4(0.3, 0, -0.3, 0))
	results["fps_trace"] = [car.position.x, car.position.y, car.rotation, car.linear_velocity.x, car.linear_velocity.y, car.transmission.rpm]
	results["failures"] = failures
	var output := "res://test_results.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="):
			output = "res://" + arg.trim_prefix("output=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "  "))
	print("DRIVING TESTS: ", "PASS" if failures.is_empty() else "FAIL", " | ", output)
	quit(0 if failures.is_empty() else 1)
