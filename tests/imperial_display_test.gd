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
		check("mph_telemetry", hud.telemetry.text.contains("LONG +67.1 MPH")
			and hud.telemetry.text.contains("LAT +8.9 MPH"))
		check("imperial_vehicle_specs", hud.telemetry.text.contains(" lb")
			and hud.telemetry.text.contains(" lb-ft")
			and hud.telemetry.text.contains(" hp")
			and not hud.telemetry.text.contains("m/s"))
		for data in [
			["mass_kg", "Mass / lb"],
			["engine_torque_nm", "Engine torque / lb-ft"],
			["engine_power_kw", "Engine power / hp"],
			["brake_force_n", "Brakes / lbf"],
			["cornering_stiffness", "Tire response / lbf per rad"]
		]:
			var key: String = data[0]
			var caption: Label = hud.config_labels[key]
			var display: String = Imperial.tune_text(key, float(car.config.get(key)))
			check("imperial_tuning_%s" % key, caption.text.contains(data[1])
				and caption.text.ends_with(display))
		var mass_caption: Label = hud.config_labels["mass_kg"]
		var mass_slider: HSlider = mass_caption.get_parent().get_child(mass_caption.get_index() + 1) as HSlider
		mass_slider.value = 1675.0
		print("TUNING DEBUG mass=",car.config.mass_kg," slider=",mass_slider.value,
			" label=",mass_caption.text," expected=",Imperial.tune_text("mass_kg",1675.0))
		check("tuning_retains_physics_in_si", is_equal_approx(car.config.mass_kg, 1675.0)
			and mass_caption.text.ends_with(Imperial.tune_text("mass_kg", 1675.0)))
		# No physics values should change during display-only rendering.
		check("physics_speed_remains_mps", is_equal_approx(car.linear_velocity.length(), 30.0))
	main.queue_free()
	print("IMPERIAL DISPLAY TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
