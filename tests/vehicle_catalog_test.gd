extends SceneTree
## Validate catalog completeness and full player-car swaps through the live UI.
const Catalog = preload("res://scripts/vehicle/vehicle_catalog.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, good: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL", label, detail])
	if not good:
		failures.append(label)


func run() -> void:
	var entries: Array[Dictionary] = Catalog.all_vehicles()
	check("catalog_has_all_88_vehicle_images", entries.size() == 88, entries.size())
	var ids := {}
	var known_paths := {}
	var makes := {}
	var provisional := 0
	for car in entries:
		var id := str(car.id)
		var texture := str(car.texture)
		check("unique_id_" + id, not ids.has(id))
		ids[id] = true
		known_paths[texture] = true
		makes[str(car.brand)] = true
		if not bool(car.get("verified_model", false)):
			provisional += 1
		check("path_exists_" + id, ResourceLoader.exists(texture), texture)
		check("dimensions_plausible_" + id,
			float(car.width_m) > 1.5 and float(car.width_m) < 2.3 and
			float(car.length_m) > 3.5 and float(car.length_m) < 6.4 and
			float(car.wheelbase_m) < float(car.length_m))
		var cfg: VehicleConfig = Catalog.build_config(car)
		check("specs_applied_" + id,
			is_equal_approx(cfg.mass_kg, float(car.mass_kg)) and
			is_equal_approx(cfg.engine_power_kw, float(car.engine_power_kw)) and
			is_equal_approx(cfg.brake_force_n, float(car.brake_force_n)) and
			is_equal_approx(cfg.wheelbase_m, float(car.wheelbase_m)))
	# Prevent quietly missing a new model as content is added in the future.
	var dirs := DirAccess.get_directories_at("res://assets/Vehicles")
	var count_disk := 0
	for brand in dirs:
		for filename in DirAccess.get_files_at("res://assets/Vehicles/" + brand):
			if filename.get_extension().to_lower() == "png":
				count_disk += 1
				check("file_registered_" + filename, known_paths.has(
					"res://assets/Vehicles/" + brand + "/" + filename))
	check("catalog_matches_asset_directory", count_disk == entries.size(),
		[count_disk, entries.size()])
	check("roster_has_all_twelve_makes", makes.size() == 12, makes.keys())
	check("generic_names_flagged_for_verification", provisional == 46, provisional)
	var main: Node2D = load("res://scenes/proving_ground.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var vehicle: VehicleController2D = main.vehicle
	vehicle.set_physics_process(false)
	var garage: CanvasLayer = main.get_node_or_null("VehicleGarage")
	check("garage_attached", garage != null)
	if garage == null:
		quit(1)
		return
	check("garage_grid_count", garage.entries.size() == entries.size() and
		garage.grid.get_child_count() == entries.size())
	check("garage_starts_hidden", not garage.overlay.visible)
	var original_transform := vehicle.global_transform
	var bmw := Catalog.find_vehicle("bmw-m2")
	var truck := Catalog.find_vehicle("ford-f150")
	var hyper := Catalog.find_vehicle("bugatti-chiron")
	check("three_distinct_car_specs", not bmw.is_empty() and not truck.is_empty() and not hyper.is_empty())
	if bmw.is_empty() or truck.is_empty() or hyper.is_empty():
		quit(1)
		return
	check("switch_bmw_model", vehicle.select_catalog_vehicle(bmw))
	check("switch_preserves_world_position", vehicle.global_position.distance_to(
		original_transform.origin) < 0.01)
	check("selected_visual_is_bmw", vehicle.get_node("Art/Sprite").texture ==
		load(str(bmw.texture)) as Texture2D)
	check("bmw_weight_and_power", is_equal_approx(vehicle.config.mass_kg, float(bmw.mass_kg))
		and is_equal_approx(vehicle.config.engine_power_kw, float(bmw.engine_power_kw)))
	var wheels: Node2D = vehicle.get_node("Art/Wheels")
	var fl: Node2D = wheels.get_node("FrontLeft")
	var rr: Node2D = wheels.get_node("RearRight")
	check("wheel_anchors_align_front_and_back", fl.position.y < rr.position.y)
	check("bumper_dimensions_match_art", absf(wheels.visible_bounds.size.x -
		float(bmw.width_m) * 20.0) < 2.5 and
		absf(wheels.visible_bounds.size.y - float(bmw.length_m) * 20.0) < 2.5,
		wheels.visible_bounds.size)
	var collider := vehicle.get_node("CollisionShape2D") as CollisionShape2D
	check("bmw_chassis_has_capsule_hitbox", collider.shape is CapsuleShape2D)
	check("switch_truck_model", vehicle.select_catalog_vehicle(truck))
	check("truck_is_heavier", vehicle.config.mass_kg > float(bmw.mass_kg))
	check("truck_has_longer_collision", (collider.shape as CapsuleShape2D).height >
		float(bmw.length_m) * 20.0)
	check("wheels_reused_no_duplicates", wheels.get_child_count() == 4)
	check("switch_hypercar_model", vehicle.select_catalog_vehicle(hyper))
	check("hypercar_more_powerful", vehicle.config.engine_power_kw > float(bmw.engine_power_kw) * 2.0)
	check("hypercar_drivetrain_awds", vehicle.config.drivetrain == VehicleConfig.Drivetrain.AWD)
	check("model_specific_tuning_hud", str(main.get_node("VehicleGarage").driving_hud.current_car_label.text).contains("CHIRON"))
	# A grid selection must pause, switch car, then resume without moving the camera.
	garage.open_menu()
	check("grid_opens_and_pauses", garage.overlay.visible and paused)
	var index := -1
	for i in garage.entries.size():
		if str(garage.entries[i].id) == "ford-mustang":
			index = i
			break
	check("mustang_card_exists", index >= 0)
	if index >= 0:
		garage._select(index)
		check("click_card_equips_selected_car", vehicle.selected_vehicle_id == "ford-mustang")
		check("selection_resumes_game", not garage.overlay.visible and not paused)
		check("hud_has_selected_name", str(garage.driving_hud.current_car_label.text).contains("MUSTANG"))
	check("original_map_location_unchanged", vehicle.global_position.distance_to(
		original_transform.origin) < 0.01)
	print("VEHICLE ROSTER / GRID / PHYSICS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
