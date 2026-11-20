extends SceneTree
## Real 148-car roster physics, without changing published specifications.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Vehicle = preload("res://scenes/vehicle.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, valid: bool, value: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if valid else "FAIL", label, value])
	if not valid:
		failures.append(label)

func _run() -> void:
	var roster: Array[Dictionary] = Catalog.all()
	check("all_148_cars_loaded",roster.size() == 148,roster.size())
	if roster.size() != 148:
		quit(1)
		return
	var car := Vehicle.instantiate() as VehicleController2D
	root.add_child(car)
	car.set_physics_process(false)
	await physics_frame
	var bad_specs: Array[String] = []
	var bad_load: Array[String] = []
	var bad_brakes: Array[String] = []
	var unique_profiles := {}
	for entry in roster:
		var id := str(entry.id)
		var cfg: VehicleConfig = Catalog.make_configuration(entry)
		var match_specs := is_equal_approx(cfg.engine_power_kw,float(entry.power_kw)) and \
			is_equal_approx(cfg.engine_torque_nm,float(entry.torque_nm)) and \
			is_equal_approx(cfg.mass_kg,float(entry.mass_kg)) and \
			is_equal_approx(cfg.wheelbase_m,float(entry.wheelbase_m)) and \
			is_equal_approx(cfg.tire_grip,float(entry.tire_grip)) and \
			is_equal_approx(cfg.brake_force_n,float(entry.brake_force_n))
		if not match_specs:
			bad_specs.append(id)
		if not entry.has("front_weight_fraction") or not entry.has("center_of_gravity_height_m") or \
				not entry.has("brake_bias_front") or cfg.center_of_gravity_height_m < 0.39 or \
				cfg.center_of_gravity_height_m > 0.90 or cfg.front_weight < 0.40 or \
				cfg.front_weight > 0.67 or cfg.brake_bias_front < 0.60 or \
				cfg.brake_bias_front > 0.72:
			bad_load.append(id)
		unique_profiles["%s/%s/%s" % [cfg.front_weight,
			cfg.center_of_gravity_height_m,cfg.brake_bias_front]] = true
		# Run *every* stock model through real tire dynamics, not just metadata.
		car.config = cfg
		car.reset_vehicle()
		car.linear_velocity = Vector2.UP * 22.0
		for i in 28:
			car.step_vehicle(1.0 / 120.0, Vector4(0.0,0.85,0.0,0.0))
		var static_front := cfg.mass_kg * 9.81 * cfg.front_weight
		var physically_valid := car.front_axle_load_n > static_front and \
			car.rear_axle_load_n < cfg.mass_kg * 9.81 * (1.0-cfg.front_weight) and \
			absf(car.front_axle_load_n + car.rear_axle_load_n - cfg.mass_kg * 9.81) < 0.1 and \
			car.cornering_grip_fraction <= 1.0 and \
			car.linear_velocity.is_finite()
		if not physically_valid:
			bad_brakes.append(id)
	check("unchanged_real_world_factory_specs",bad_specs.is_empty(),bad_specs)
	check("all_cars_have_bounded_calibration",bad_load.is_empty(),bad_load)
	check("distinct_per_model_handling_profiles",unique_profiles.size() > 100,unique_profiles.size())
	check("all_148_cars_brake_with_forward_transfer",bad_brakes.is_empty(),bad_brakes)
	car.queue_free()
	print("148 VEHICLE AXLE CALIBRATION: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
