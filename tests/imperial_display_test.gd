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
		# F1 is now a compact stats-only panel; the main dial retains MPH.
		check("stats_only_telemetry", hud.telemetry.text.contains("POWER ")
			and hud.telemetry.text.contains("TORQUE ")
			and hud.telemetry.text.contains("WEIGHT ")
			and not hud.telemetry.text.contains("LONG "))
		check("imperial_vehicle_specs", hud.telemetry.text.contains(" lb")
			and hud.telemetry.text.contains(" lb-ft")
			and hud.telemetry.text.contains(" hp")
			and not hud.telemetry.text.contains("m/s"))
		var labels := {
			"mass_kg": "Weight (lb)",
			"engine_torque_nm": "Torque (lb-ft)",
			"engine_power_kw": "Horsepower (hp)"
		}
		check("only_three_performance_sliders", hud.tuning_sliders.size() == 3)
		for key in labels:
			var caption: Label = hud.config_labels[key]
			check("imperial_tuning_%s" % key, caption.text.contains(labels[key])
				and caption.text.ends_with(Imperial.tune_text(key, float(car.config.get(key)))))
			var slider: HSlider = hud.tuning_sliders[key]
			check("slider_range_and_step_%s" % key,
				is_equal_approx(slider.min_value, 50.0)
				and is_equal_approx(slider.max_value, 10000.0)
				and is_equal_approx(slider.step, 10.0))
		# Sliders work in displayed imperial units and convert to native kg.
		var mass_slider: HSlider = hud.tuning_sliders["mass_kg"]
		mass_slider.value = 1670.0
		check("tuning_retains_physics_in_si",
			absf(car.config.mass_kg - 1670.0 / Imperial.KG_TO_LB) < 0.01
			and (hud.config_labels["mass_kg"] as Label).text.ends_with("1670"))
		# No physics values should change during display-only rendering.
		check("physics_speed_remains_mps", is_equal_approx(car.linear_velocity.length(), 30.0))
	main.queue_free()
	print("IMPERIAL DISPLAY TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
