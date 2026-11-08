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
	var stock_grip: float = float(car.config.tire_grip)
	var stock_power: float = float(car.config.engine_power_kw)
	check("uses_stock_values_without_profile", is_equal_approx(stock_grip, 1.65) and not FileAccess.file_exists(path))
	check("all_tuning_fields_have_sliders", hud.tuning_sliders.size() == 20)

	(hud.tuning_sliders["tire_grip"] as HSlider).value = 1.27
	(hud.tuning_sliders["engine_power_kw"] as HSlider).value = 480.0
	(hud.tuning_sliders["handbrake_grip_recovery_seconds"] as HSlider).value = 0.55
	(hud.tuning_sliders["handbrake_drive_grip"] as HSlider).value = 0.9
	hud.drivetrain_select.select(VehicleConfig.Drivetrain.AWD)
	hud.drivetrain_select.item_selected.emit(VehicleConfig.Drivetrain.AWD)
	check("live_sliders_change_car", is_equal_approx(car.config.tire_grip, 1.27)
		and is_equal_approx(car.config.engine_power_kw, 480.0)
		and is_equal_approx(car.config.handbrake_grip_recovery_seconds, 0.55)
		and is_equal_approx(car.config.handbrake_drive_grip, 0.9)
		and car.config.drivetrain == VehicleConfig.Drivetrain.AWD)
	await create_timer(0.50).timeout
	check("auto_save_without_manual_button", FileAccess.file_exists(path) and not hud._tuning_dirty)

	var disk := ConfigFile.new()
	var loaded: Error = disk.load(path)
	check("profile_saved_versioned_and_complete", loaded == OK and
		disk.get_value("meta","version",0) == 1 and disk.get_value("tuning","drivetrain",-1) == VehicleConfig.Drivetrain.AWD
		and is_equal_approx(float(disk.get_value("tuning", "handbrake_drive_grip", 0.0)), 0.9))
	await _discard(game)

	# Simulates opening the game again: the car is a fresh instance with a
	# fresh duplicate of the original .tres, and the F1 UI must match the disk.
	game = _new_game()
	car = game.vehicle
	hud = game.get_children().filter(func(child: Node) -> bool:
		return child.get_script() == load("res://scripts/ui/driving_hud.gd"))[0]
	car.set_physics_process(false)
	check("tune_reloaded_on_game_start", is_equal_approx(car.config.tire_grip, 1.27)
		and is_equal_approx(car.config.engine_power_kw, 480.0)
		and is_equal_approx(car.config.handbrake_grip_recovery_seconds, 0.55)
		and is_equal_approx(car.config.handbrake_drive_grip, 0.9)
		and car.config.drivetrain == VehicleConfig.Drivetrain.AWD)
	check("sliders_and_drivetrain_match_loaded_tune",
		is_equal_approx(float((hud.tuning_sliders["tire_grip"] as HSlider).value), 1.27)
		and hud.drivetrain_select.selected == VehicleConfig.Drivetrain.AWD
		and (hud.config_labels["engine_power_kw"] as Label).text.contains("hp"))

	# The user may exit immediately after moving a slider. _exit_tree must
	# flush pending edits even if the 350ms timer has not fired yet.
	(hud.tuning_sliders["tire_grip"] as HSlider).value = 1.44
	check("pending_save_before_quit", hud._tuning_dirty)
	await _discard(game)
	game = _new_game()
	car = game.vehicle
	hud = game.get_children().filter(func(child: Node) -> bool:
		return child.get_script() == load("res://scripts/ui/driving_hud.gd"))[0]
	car.set_physics_process(false)
	check("last_second_quit_flushes_changes", is_equal_approx(car.config.tire_grip, 1.44))

	# Restore must remove the profile, reset live controls, and honor stock
	# values next launch. Position reset (R) must never reset the saved tune.
	car.reset_vehicle()
	check("position_reset_preserves_tune", is_equal_approx(car.config.tire_grip, 1.44))
	hud.reset_tuning_button.pressed.emit()
	check("restore_stock_updates_game_and_ui", is_equal_approx(car.config.tire_grip, stock_grip)
		and is_equal_approx(car.config.engine_power_kw, stock_power)
		and is_equal_approx(car.config.handbrake_drive_grip, 0.75)
		and car.config.drivetrain == VehicleConfig.Drivetrain.RWD
		and is_equal_approx(float((hud.tuning_sliders["tire_grip"] as HSlider).value), stock_grip)
		and not FileAccess.file_exists(path))
	await _discard(game)
	game = _new_game()
	car = game.vehicle
	car.set_physics_process(false)
	check("fresh_start_uses_stock_after_reset", is_equal_approx(car.config.tire_grip, stock_grip)
		and car.config.drivetrain == VehicleConfig.Drivetrain.RWD)
	await _discard(game)

	# Malformed or out-of-range values cannot override vehicle Resource data.
	var corrupt := ConfigFile.new()
	corrupt.set_value("meta", "version", 1)
	corrupt.set_value("tuning", "tire_grip", -999.0)
	corrupt.set_value("tuning", "drivetrain", 99)
	corrupt.set_value("tuning", "engine_power_kw", "not a number")
	corrupt.save(path)
	game = _new_game()
	car = game.vehicle
	car.set_physics_process(false)
	check("invalid_save_cannot_corrupt_vehicle", is_equal_approx(car.config.tire_grip, stock_grip)
		and is_equal_approx(car.config.engine_power_kw, stock_power)
		and car.config.drivetrain == VehicleConfig.Drivetrain.RWD)
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
