extends SceneTree
## User-facing units are imperial. Vehicle physics and Resource values stay SI.
const Imperial = preload("res://scripts/ui/imperial_units.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(name: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", name])
	if not passed:
		failures.append(name)

func _run() -> void:
	check("mph_conversion", is_equal_approx(Imperial.speed_mph(1.0), 2.2369362920544))
	check("mph_sixty", absf(Imperial.speed_mph(26.8224) - 60.0) < 0.01)
	check("weight_lb", absf(Imperial.tune_value("mass_kg", 1000.0) - 2204.62262) < 0.001)
	check("torque_lb_ft", absf(Imperial.tune_value("engine_torque_nm", 100.0) - 73.75621) < 0.001)
	check("power_hp", absf(Imperial.tune_value("engine_power_kw", 100.0) - 134.10221) < 0.001)
	check("force_lbf", absf(Imperial.tune_value("brake_force_n", 1000.0) - 224.80894) < 0.001)
	check("cornering_lbf_per_rad", absf(Imperial.tune_value("cornering_stiffness", 100000.0) - 22480.8943) < 0.01)
	check("dimensionless_setting_unchanged", Imperial.tune_value("tire_grip", 1.65) == 1.65)

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var car: VehicleController2D = main.vehicle
	var hud: CanvasLayer
	for child in main.get_children():
		if child is CanvasLayer and child.get_script() == load("res://scripts/ui/driving_hud.gd"):
			hud = child
	check("hud_found", hud != null)
	if hud != null:
		car.set_physics_process(false)
		car.linear_velocity = Vector2.UP * 30.0
		car.longitudinal_speed = 30.0
		car.lateral_speed = 4.0
		hud._process(0.0)
		check("mph_speedometer", hud.speed_unit_label.text.strip_edges() == "MPH"
			and hud.speed_label.text == "067")
		var dash: Control = hud.dashboard
		check("dashboard_shows_imperial_vehicle_specs",
			dash.model_label.text.contains("HP") and
			dash.model_label.text.contains("LB-FT") and
			not dash.model_label.text.contains("kW"))
		var panel_count := 0
		for child in hud.get_children():
			if child is PanelContainer:
				panel_count += 1
		check("removed_f1_controls_do_not_appear", panel_count == 0 and is_instance_valid(dash) and
			not InputMap.has_action("tuning"))
		var stock_mass: float = car.config.mass_kg
		var stock_torque: float = car.config.engine_torque_nm
		var stock_power: float = car.config.engine_power_kw
		hud._process(0.0)
		check("hud_readouts_do_not_change_live_stats",
			is_equal_approx(car.config.mass_kg, stock_mass) and
			is_equal_approx(car.config.engine_torque_nm, stock_torque) and
			is_equal_approx(car.config.engine_power_kw, stock_power))
		# No physics values should change during display-only rendering.
		check("physics_speed_remains_mps", is_equal_approx(car.linear_velocity.length(), 30.0))
	main.queue_free()
	print("IMPERIAL DISPLAY TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
