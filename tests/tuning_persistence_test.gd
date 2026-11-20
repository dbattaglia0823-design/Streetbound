extends SceneTree
## Regression: old F1 performance saves must not override a car's catalog
## configuration, including on launch, model switch or scene restart.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const ControlsScript = preload("res://scripts/input/controls.gd")
const LEGACY_PATH := "user://streetbound_vehicle_tuning.cfg"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		failures.append(label)


func _new_game() -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	return game


func _discard(game: Node) -> void:
	game.queue_free()
	await process_frame


func _matches_catalog(car: VehicleController2D, entry: Dictionary) -> bool:
	var expected: VehicleConfig = Catalog.make_configuration(entry)
	return is_equal_approx(car.config.engine_power_kw, expected.engine_power_kw) and \
		is_equal_approx(car.config.engine_torque_nm, expected.engine_torque_nm) and \
		is_equal_approx(car.config.mass_kg, expected.mass_kg) and \
		car.config.drivetrain == expected.drivetrain and \
		is_equal_approx(car.config.tire_grip, expected.tire_grip) and \
		is_equal_approx(car.config.brake_force_n, expected.brake_force_n)


func _run() -> void:
	var had_previous := FileAccess.file_exists(LEGACY_PATH)
	var previous: PackedByteArray = FileAccess.get_file_as_bytes(LEGACY_PATH) if had_previous else PackedByteArray()
	var legacy := ConfigFile.new()
	legacy.set_value("meta", "version", 1)
	legacy.set_value("tuning", "engine_power_kw", 7456.9987)
	legacy.set_value("tuning", "engine_torque_nm", 13558.179)
	legacy.set_value("tuning", "mass_kg", 4535.924)
	check("write_legacy_f1_override_fixture", legacy.save(LEGACY_PATH) == OK)
	var fixture_bytes: PackedByteArray = FileAccess.get_file_as_bytes(LEGACY_PATH)

	var game := _new_game()
	await process_frame
	var car: VehicleController2D = game.vehicle
	car.set_physics_process(false)
	var hud: CanvasLayer = null
	for child in game.get_children():
		if child is CanvasLayer and child.get_script() == load("res://scripts/ui/driving_hud.gd"):
			hud = child
	var panels := 0
	if hud != null:
		for child in hud.get_children():
			if child is PanelContainer:
				panels += 1
	check("f1_menu_removed_but_driving_hud_preserved", hud != null and
		hud.dashboard != null and panels == 1)
	check("f1_input_and_controller_action_removed",
		not ControlsScript.ACTIONS.has("tuning") and not InputMap.has_action("tuning"))
	check("legacy_override_not_applied_at_startup",
		car.config.engine_power_kw < 7000.0 and car.config.mass_kg < 4500.0)

	var fiesta: Dictionary = Catalog.find_by_id("ford-fiesta")
	var chiron: Dictionary = Catalog.find_by_id("bugatti-chiron")
	check("catalog_test_models_exist", not fiesta.is_empty() and not chiron.is_empty())
	if not fiesta.is_empty() and not chiron.is_empty():
		check("fiesta_uses_own_stats_after_switch", Catalog.select(car, fiesta) and
			_matches_catalog(car, fiesta))
		if hud != null:
			hud.on_vehicle_selected(fiesta)
		check("chiron_uses_own_stats_after_switch", Catalog.select(car, chiron) and
			_matches_catalog(car, chiron))
		if hud != null:
			hud.on_vehicle_selected(chiron)
		check("return_to_fiesta_restores_original_stats", Catalog.select(car, fiesta) and
			_matches_catalog(car, fiesta))
	check("legacy_saved_file_unmodified", FileAccess.get_file_as_bytes(LEGACY_PATH) == fixture_bytes)
	await _discard(game)

	game = _new_game()
	await process_frame
	car = game.vehicle
	car.set_physics_process(false)
	check("scene_restart_does_not_load_legacy_override",
		car.config.engine_power_kw < 7000.0 and car.config.mass_kg < 4500.0)
	await _discard(game)

	# Preserve users' old settings files, even though they are no longer read.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_PATH))
	if had_previous:
		var restore := FileAccess.open(LEGACY_PATH, FileAccess.WRITE)
		if restore != null:
			restore.store_buffer(previous)
			restore.close()
	check("prior_legacy_file_restored", FileAccess.file_exists(LEGACY_PATH) == had_previous and
		(not had_previous or FileAccess.get_file_as_bytes(LEGACY_PATH) == previous))
	print("STOCK VEHICLE STATS WITHOUT F1: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
