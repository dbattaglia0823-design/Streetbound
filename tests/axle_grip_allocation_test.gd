extends SceneTree
## Deterministic load transfer, axle demand, and actual-car integration.
const Vehicle = preload("res://scenes/vehicle.tscn")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, valid: bool, details: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if valid else "FAIL", label, details])
	if not valid:
		failures.append(label)

func drive(car: VehicleController2D, frames: int, controls: Vector4) -> void:
	for i in frames:
		car.step_vehicle(1.0 / 120.0, controls)

func _run() -> void:
	var entry := Catalog.find_by_id("acura-integra")
	check("known_fwd_car", not entry.is_empty())
	if entry.is_empty():
		quit(1)
		return
	var cfg := Catalog.make_configuration(entry)
	var static_load := VehicleController2D.axle_loads_n(cfg, 0.0)
	var acceleration_load := VehicleController2D.axle_loads_n(cfg, 6.0)
	var braking_load := VehicleController2D.axle_loads_n(cfg, -6.0)
	check("zero_accel_matches_static_distribution",
		is_equal_approx(static_load.x, cfg.mass_kg * 9.81 * cfg.front_weight), static_load)
	check("accelerating_moves_load_rearward",
		acceleration_load.x < static_load.x and acceleration_load.y > static_load.y,
		acceleration_load)
	check("braking_moves_load_forward",
		braking_load.x > static_load.x and braking_load.y < static_load.y,
		braking_load)
	check("contact_load_conserved",
		is_equal_approx(acceleration_load.x + acceleration_load.y, cfg.mass_kg * 9.81)
		and is_equal_approx(braking_load.x + braking_load.y, cfg.mass_kg * 9.81))
	var high_cg := cfg.duplicate(true) as VehicleConfig
	high_cg.center_of_gravity_height_m = 0.85
	check("higher_cg_increases_transfer",
		VehicleController2D.axle_loads_n(high_cg, -6.0).x > braking_load.x)
	var full_grip := VehicleController2D.lateral_grip_budget(7000.0, 1.0, 0.0)
	var partial_grip := VehicleController2D.lateral_grip_budget(7000.0, 1.0, 3200.0)
	var stressed_grip := VehicleController2D.lateral_grip_budget(7000.0, 1.0, 6500.0)
	check("shared_friction_budget_is_monotonic",
		is_equal_approx(full_grip, 1.0) and partial_grip < full_grip
		and stressed_grip < partial_grip and stressed_grip > 0.0)
	var car := Vehicle.instantiate() as VehicleController2D
	root.add_child(car)
	car.set_physics_process(false)
	await physics_frame
	car.config = cfg.duplicate(true)
	car.reset_vehicle()
	car.linear_velocity = Vector2.UP * 23.0
	drive(car, 55, Vector4(0.0, 1.0, 0.5, 0.0))
	check("actual_braking_loads_front_axle",
		car.front_axle_load_n > static_load.x and car.rear_axle_load_n < static_load.y,
		[car.front_axle_load_n, car.rear_axle_load_n])
	check("actual_braking_spends_grip",
		car.cornering_grip_fraction < 0.88 and car.cornering_grip_fraction > 0.0,
		car.cornering_grip_fraction)
	check("axle_grip_budgets_bounded",
		car.front_cornering_grip_fraction >= 0.0 and car.front_cornering_grip_fraction <= 1.0
		and car.rear_cornering_grip_fraction >= 0.0 and car.rear_cornering_grip_fraction <= 1.0)
	car.reset_vehicle()
	car.linear_velocity = Vector2.UP * 8.0
	drive(car, 60, Vector4(1.0, 0.0, 0.0, 0.0))
	check("actual_acceleration_unloads_front_axle",
		car.longitudinal_accel_mps2 > 0.0 and car.front_axle_load_n < static_load.x,
		[car.longitudinal_accel_mps2, car.front_axle_load_n])
	car.reset_vehicle()
	car.linear_velocity = Vector2.UP * 18.0
	drive(car, 1, Vector4.ZERO)
	check("coasting_retains_both_lateral_budgets",
		is_equal_approx(car.front_cornering_grip_fraction, 1.0)
		and is_equal_approx(car.rear_cornering_grip_fraction, 1.0))
	car.queue_free()
	print("AXLE LOAD AND GRIP ALLOCATION: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
