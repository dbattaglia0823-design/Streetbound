extends "res://tests/driving_test.gd"
## Reproduce stationary steering creep and triple-pedal handbrake drift on
## real VehicleController2D physics, across FWD, RWD and AWD stock cars.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const VEHICLES := ["acura-integra", "mclaren-570s", "cadillac-escalade"]


func run() -> void:
	car = Vehicle.instantiate()
	root.add_child(car)
	car.set_physics_process(false)
	await physics_frame
	for vehicle_id in VEHICLES:
		var entry: Dictionary = Catalog.find_by_id(vehicle_id)
		if entry.is_empty():
			check("catalog_has_" + vehicle_id, false, entry)
			continue
		car.config = Catalog.make_configuration(entry)
		car.transmission.reset(car.config)

		# Wheels may visibly steer but must never slide/propel a parked car.
		for side in [-1.0, 1.0]:
			fresh()
			var origin := car.global_position
			var heading := car.rotation
			await drive(2.0, Vector4(0, 0, side, 1))
			var drift_m := car.global_position.distance_to(origin) / 20.0
			check(vehicle_id + "_parked_handbrake_steer_no_motion_" + str(side),
				drift_m < 0.02 and car.linear_velocity.length() < 0.03 and
				absf(angle_difference(car.rotation, heading)) < deg_to_rad(0.1),
				[drift_m,car.linear_velocity,car.yaw_rate,car.rotation-heading])
			check(vehicle_id + "_parked_wheels_still_steer_" + str(side),
				car.steering * side > deg_to_rad(3.0),car.steering)

		# S is reverse by design only without parking brake. Holding both
		# brakes must not silently engage reverse while stationary.
		fresh()
		var parked := car.global_position
		await drive(0.5, Vector4(0, 1, 0.7, 1))
		check(vehicle_id + "_handbrake_and_service_brake_stay_parked",
			not car.reversing and absf(car.reverse_hold) < 0.001 and
			car.global_position.distance_to(parked) / 20.0 < 0.02,
			[car.reversing,car.reverse_hold,car.linear_velocity])

		# Three pedals together must hold the car instead of supplying
		# positive drive torque and lateral forces through sliding tyres.
		fresh()
		var start := car.global_position
		var rotation_start := car.rotation
		await drive(2.0, Vector4(1, 1, -1, 1))
		var unwanted_m := car.global_position.distance_to(start) / 20.0
		check(vehicle_id + "_triple_pedal_hold_is_stationary",
			unwanted_m < 0.02 and car.linear_velocity.length() < 0.03 and
			absf(angle_difference(car.rotation, rotation_start)) < deg_to_rad(0.1)
			and absf(car.delivered_wheel_force_n) < 0.01 and not car.reversing,
			[unwanted_m,car.linear_velocity,car.delivered_wheel_force_n])

		# Arrive while moving, then braking with both brakes and throttle
		# must slow the car; the throttle cannot fight the parking brakes.
		fresh(12.0)
		var speed_start := car.linear_velocity.length()
		await drive(1.6, Vector4(1, 1, 0.8, 1))
		check(vehicle_id + "_combined_brakes_slow_a_moving_car",
			car.linear_velocity.length() < speed_start * 0.45 and
			absf(car.delivered_wheel_force_n) < 0.01,
			[car.linear_velocity.length(),car.delivered_wheel_force_n])

		# Retain legitimate handbrake power slides, low-speed steering and
		# reverse on service brake alone.
		fresh()
		await drive(1.1,Vector4(0.8,0,0.55,1))
		check(vehicle_id + "_powered_handbrake_slide_still_moves",
			car.linear_velocity.length() > 1.0,car.linear_velocity.length())
		fresh(4)
		await drive(0.7,Vector4(0.3,0,0.6,0))
		check(vehicle_id + "_normal_rolling_steering_still_works",
			car.rotation > 0.08,car.rotation)
		fresh()
		await drive(1.0,Vector4(0,1,0,0))
		check(vehicle_id + "_brake_only_reverse_still_works",
			car.reversing and car.longitudinal_speed < -0.5,
			[car.reversing,car.longitudinal_speed])
	print("HANDBRAKE INPUT PHYSICS: ",
		"PASS" if failures.is_empty() else "FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
