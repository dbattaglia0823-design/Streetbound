extends SceneTree
## Verify that F1 tuning survives a complete scene restart and is stored in
## user://, without modifying the stock resource or existing controls.cfg.
const Profile = preload("res://scripts/vehicle/tuning_profile.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(name: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", name])
	if not passed:
		failures.append(name)

func _new_game() -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	return game

func _discard(game: Node) -> void:
	game.queue_free()
	await process_frame

func _run() -> void:
	var path: String = Profile.SAVE_PATH
	var had_previous: bool = FileAccess.file_exists(path)
	var previous: PackedByteArray = FileAccess.get_file_as_bytes(path) if had_previous else PackedByteArray()
	var existing_controls: bool = FileAccess.file_exists("user://controls.cfg")
	var control_bytes: PackedByteArray = FileAccess.get_file_as_bytes("user://controls.cfg") if existing_controls else PackedByteArray()
	if had_previous:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var game: Node = _new_game()
	var car: VehicleController2D = game.vehicle
	var hud = game.get_children().filter(func(child: Node) -> bool:
		return child.get_script() == load("res://scripts/ui/driving_hud.gd"))[0]
	car.set_physics_process(false)
	var stock_power: float = float(car.config.engine_power_kw)
	var stock_torque: float = float(car.config.engine_torque_nm)
	var stock_mass: float = float(car.config.mass_kg)
	check("only_three_stat_sliders", hud.tuning_sliders.size() == 3)
	var power_slider: HSlider = hud.tuning_sliders["engine_power_kw"]
	var torque_slider: HSlider = hud.tuning_sliders["engine_torque_nm"]
	var weight_slider: HSlider = hud.tuning_sliders["mass_kg"]
	for slider in [power_slider, torque_slider, weight_slider]:
		check("stats_slider_range_and_step", is_equal_approx(slider.min_value, 50.0)
			and is_equal_approx(slider.max_value, 10000.0)
			and is_equal_approx(slider.step, 10.0))
	power_slider.value = 10000.0
	torque_slider.value = 50.0
	weight_slider.value = 2500.0
	check("live_imperial_stats_convert_to_si",
		absf(car.config.engine_power_kw - 10000.0 / 1.341022089595) < 0.05
		and absf(car.config.engine_torque_nm - 50.0 / 0.73756214927727) < 0.05
		and absf(car.config.mass_kg - 2500.0 / 2.2046226218488) < 0.05)
	await create_timer(0.50).timeout
	check("auto_save_without_manual_button", FileAccess.file_exists(path) and not hud._tuning_dirty)
	var saved_profile := ConfigFile.new()
	check("serialized_tuning_profile_is_readable",
		saved_profile.load(path) == OK and
		saved_profile.get_value("meta","version",0) == Profile.VERSION)
	# ConfigFile rounds the SI power limit from 7456.9987 to 7457.0 on
	# Godot 4.4.1. That value must be accepted and clamped at reload.
	check("max_power_endpoint_is_represented_in_save",
		absf(float(saved_profile.get_value("tuning","engine_power_kw",0.0)) -
			10000.0 / 1.341022089595) < 0.01)
	await _discard(game)
	game = _new_game()
	car = game.vehicle
	hud = game.get_children().filter(func(child: Node) -> bool:
		return child.get_script() == load("res://scripts/ui/driving_hud.gd"))[0]
	car.set_physics_process(false)
	check("reloaded_stats", absf(car.config.engine_power_kw - 10000.0 / 1.341022089595) < 0.05
		and absf(car.config.engine_torque_nm - 50.0 / 0.73756214927727) < 0.05
		and absf(car.config.mass_kg - 2500.0 / 2.2046226218488) < 0.05)
	check("reloaded_slider_display", is_equal_approx((hud.tuning_sliders["engine_power_kw"] as HSlider).value, 10000.0)
		and is_equal_approx((hud.tuning_sliders["engine_torque_nm"] as HSlider).value, 50.0))
	# A file tampered well outside the small serialization tolerance should
	# still be refused without changing the actual vehicle configuration.
	var invalid_path := "user://streetbound_test_invalid_tuning.cfg"
	var invalid := ConfigFile.new()
	invalid.set_value("meta","version",Profile.VERSION)
	invalid.set_value("tuning","engine_power_kw",10000.0)
	check("write_invalid_tuning_fixture",invalid.save(invalid_path)==OK)
	var scratch: VehicleConfig = car.config.duplicate(true)
	var prior_power: float = scratch.engine_power_kw
	var invalid_loader := Profile.new(hud.TUNING_FIELDS,invalid_path)
	check("reject_genuinely_out_of_range_saved_power",
		not invalid_loader.load_into(scratch) and
		is_equal_approx(scratch.engine_power_kw,prior_power))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(invalid_path))
	hud.reset_tuning_button.pressed.emit()
	check("restore_stock_stats", is_equal_approx(car.config.engine_power_kw, stock_power)
		and is_equal_approx(car.config.engine_torque_nm, stock_torque)
		and is_equal_approx(car.config.mass_kg, stock_mass)
		and not FileAccess.file_exists(path))
	await _discard(game)

	# Leave the caller's settings exactly as they were before the test.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if had_previous:
		var restore := FileAccess.open(path, FileAccess.WRITE)
		if restore != null:
			restore.store_buffer(previous)
			restore.close()
	check("existing_controls_untouched",
		FileAccess.file_exists("user://controls.cfg") == existing_controls and
		(not existing_controls or FileAccess.get_file_as_bytes("user://controls.cfg") == control_bytes))
	print("F1 TUNING PERSISTENCE: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
