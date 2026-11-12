extends SceneTree
## Five-figure F1 power / torque must produce a measurably different real
## launch and higher-speed pull. No position, velocity, RPM or gear cheating.
const Vehicle = preload("res://scenes/vehicle.tscn")
const Power = preload("res://scripts/vehicle/powertrain_dynamics.gd")
const Imperial = preload("res://scripts/ui/imperial_units.gd")
const MPH_60_MPS := 60.0 / Imperial.MPS_TO_MPH
var failures: Array[String] = []
var car: VehicleController2D
var baseline: VehicleConfig


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, passed: bool, details: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL", label, details])
	if not passed:
		failures.append(label)


func config_for(hp: float, lb_ft: float) -> VehicleConfig:
	var cfg: VehicleConfig = baseline.duplicate(true)
	cfg.engine_power_kw = hp / Imperial.KW_TO_HP
	cfg.engine_torque_nm = lb_ft / Imperial.NM_TO_LB_FT
	return cfg


func run_launch(cfg: VehicleConfig, duration_sec: float = 4.0,
		throttle_value: float = 1.0) -> Dictionary:
	car.config = cfg
	car.reset_vehicle()
	car.transmission.automatic = true
	var zero_to_60 := INF
	var checkpoints := {}
	var max_spin := 0.0
	var peak_force := 0.0
	var peak_traction := 0.0
	var elapsed := 0.0
	for i in ceili(duration_sec * 60.0):
		await physics_frame
		car.step_vehicle(1.0 / 60.0,Vector4(throttle_value,0,0,0))
		elapsed += 1.0 / 60.0
		max_spin = maxf(max_spin,car.wheel_spin)
		peak_force = maxf(peak_force,car.engine_wheel_force_n)
		peak_traction = maxf(peak_traction,car.traction_limit_n)
		if car.linear_velocity.length() >= MPH_60_MPS and not is_finite(zero_to_60):
			zero_to_60 = elapsed
		if i == 59 or i == 119 or i == 179 or i == 239:
			checkpoints[i] = car.linear_velocity.length()
	return {"t60":zero_to_60,"s1":float(checkpoints.get(59,0.0)),
		"s2":float(checkpoints.get(119,0.0)),
		"s3":float(checkpoints.get(179,0.0)),
		"s4":float(checkpoints.get(239,0.0)),
		"spin":max_spin,"force":peak_force,"traction":peak_traction}


func _run() -> void:
	car = Vehicle.instantiate() as VehicleController2D
	root.add_child(car)
	car.set_physics_process(false)
	await physics_frame
	baseline = car.config.duplicate(true)
	check("ordinary_power_and_torque_stock_mode_unmodified",
		Power.high_output_fraction(baseline) == 0.0 and
		is_equal_approx(Power.traction_force_n(baseline,6000.0,1.0),
			6000.0 * baseline.tire_grip))
	var stock_curve: float = baseline.torque_curve.sample_baked(0.83)
	var stock_high_rpm := Power.crank_torque_nm(baseline,
		baseline.redline_rpm * 0.83,stock_curve)
	var big_power := config_for(10000.0,Imperial.tune_value(
		"engine_torque_nm",baseline.engine_torque_nm))
	var high_power_torque := Power.crank_torque_nm(big_power,
		big_power.redline_rpm * 0.83,stock_curve)
	check("horsepower_slider_increases_high_rpm_engine_output",
		high_power_torque > stock_high_rpm * 8.0,
		[stock_high_rpm,high_power_torque])
	var big_torque := config_for(Imperial.tune_value(
		"engine_power_kw",baseline.engine_power_kw),10000.0)
	var stock_low := Power.crank_torque_nm(baseline,
		baseline.idle_rpm * 2.0,0.6)
	var tuned_low := Power.crank_torque_nm(big_torque,
		big_torque.idle_rpm * 2.0,0.6)
	check("torque_slider_increases_low_rpm_launch_force",
		tuned_low > stock_low * 2.5,[stock_low,tuned_low])
	var strong_at_redline := Power.crank_torque_nm(big_torque,
		big_torque.redline_rpm,0.7)
	var limited_kw := strong_at_redline * big_torque.redline_rpm * TAU /60.0/1000.0
	check("low_horsepower_still_limits_high_rpm_torque",
		limited_kw <= big_torque.engine_power_kw + 0.01,limited_kw)
	var full := config_for(10000.0,10000.0)
	check("five_figure_sliders_produce_high_output_drive_envelope",
		Power.high_output_fraction(full) > 0.98)
	var powered_road := Power.traction_force_n(full,9000.0,1.0)
	var powered_grass := Power.traction_force_n(full,9000.0,0.6,1.0,"GRASS")
	check("extreme_traction_on_dry_asphalt_only",
		powered_road > powered_grass * 4.0 and
		is_equal_approx(powered_grass,9000.0 * full.tire_grip * 0.6))
	check("full_power_cannot_exceed_safe_longitudinal_tire_envelope",
		powered_road <= full.mass_kg * 9.81 * 3.45 + 1.0)
	var stock: Dictionary = await run_launch(baseline)
	var rocket: Dictionary = await run_launch(full)
	print("STOCK LAUNCH: ",stock)
	print("10000 HP / 10000 LB-FT LAUNCH: ",rocket)
	check("five_figure_tune_launches_substantially_faster_than_stock",
		float(rocket.t60) < minf(2.8,float(stock.t60)*0.65),
		[stock.t60,rocket.t60])
	check("five_figure_power_still_pulls_hard_after_launch",
		float(rocket.s3) > float(stock.s3) * 1.7,
		[stock.s3,rocket.s3])
	check("huge_torque_produces_wheelspin_instead_of_silent_clamp",
		float(rocket.spin) > 0.30,rocket.spin)
	check("engine_force_output_actually_exceeds_tire_capacity",
		float(rocket.force) > float(rocket.traction) * 1.4,
		[rocket.force,rocket.traction])
	var power_only: Dictionary = await run_launch(big_power)
	var torque_only: Dictionary = await run_launch(big_torque)
	check("increasing_only_horsepower_improves_real_acceleration",
		float(power_only.s3) > float(stock.s3) * 1.3,
		[stock.s3,power_only.s3])
	check("increasing_only_torque_improves_launch_at_fixed_horsepower",
		float(torque_only.s2) > float(stock.s2) * 1.15,
		[stock.s2,torque_only.s2])
	var partial: Dictionary = await run_launch(full,2.0,0.20)
	check("high_power_throttle_remains_modulatable",
		float(partial.s2) < float(rocket.s2) * 0.80,
		[partial.s2,rocket.s2])
	# Stock tires are not silently enchanted on grass.
	var road_peak := Power.traction_force_n(full,9000.0,1.0,1.0,"ASPHALT")
	var dirt_peak := Power.traction_force_n(full,9000.0,1.0,1.0,"GRASS")
	check("offroad_force_does_not_receive_drag_slick_bonus",
		road_peak > dirt_peak * 2.0)
	car.config = baseline
	print("HIGH OUTPUT POWER AND TORQUE PHYSICS: ",
		"PASS" if failures.is_empty() else "FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
