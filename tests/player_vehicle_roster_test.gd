extends SceneTree
## End-to-end vehicle roster and selector integration. Verify asset presence,
## fitted colliders, wheel positions, per-car dynamics and immediate selection.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(title: String, valid: bool, details: Variant = "") -> void:
	print("%s %s %s" % ["PASS" if valid else "FAIL", title, details])
	if not valid:
		failures.append(title)


func run() -> void:
	var vehicles: Array[Dictionary] = Catalog.all()
	check("all_playable_vehicle_assets_cataloged", vehicles.size() == 89, vehicles.size())
	var ids := {}
	var brands := {}
	var all_resources := true
	var all_metrics := true
	var unverified := 0
	for entry in vehicles:
		var id := str(entry.id)
		ids[id] = true
		brands[str(entry.brand)] = true
		all_resources = all_resources and ResourceLoader.exists(str(entry.texture))
		all_metrics = all_metrics and float(entry.length_m) > 3.0 and \
			float(entry.width_m) > 1.6 and float(entry.wheelbase_m) > 2.0 and \
			float(entry.mass_kg) > 800.0 and float(entry.brake_force_n) > 9000.0 \
			and float(entry.power_kw) > 70.0
		if bool(entry.source_model_unverified):
			unverified += 1
	check("all_vehicle_pictures_exist", all_resources)
	check("unique_vehicle_ids", ids.size() == vehicles.size())
	check("twelve_vehicle_brands", brands.size() == 12, brands.size())
	check("plausible_vehicle_baseline_data", all_metrics)
	check("unknown_images_remain_flagged", unverified == 47, unverified)
	# Calibration fields must reject malformed values, and individual
	# axle hubs stay independent from neighboring car selections.
	var default_front := Vector2(0.075, 0.25)
	check("wheel_calibration_defaults_to_measured_wheelbase",
		Catalog._wheel_uv({}, "front_left_uv", default_front) == default_front)
	check("model_specific_front_hub_can_be_calibrated",
		Catalog._wheel_uv({"front_left_uv": [0.11, 0.19]},
			"front_left_uv", default_front) == Vector2(0.11, 0.19))
	check("invalid_hub_outside_body_is_ignored",
		Catalog._wheel_uv({"front_left_uv": [-0.2, 1.3]},
			"front_left_uv", default_front) == default_front)
	check("incomplete_hub_override_is_ignored",
		Catalog._wheel_uv({"front_left_uv": [0.12]},
			"front_left_uv", default_front) == default_front)
	var save_path := "user://streetbound_selected_vehicle.cfg"
	var old_save := FileAccess.get_file_as_string(save_path) if FileAccess.file_exists(save_path) else ""
	var main: Node = load("res://scenes/proving_ground.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	main.vehicle.set_physics_process(false)
	var selector: CanvasLayer = main.get_node_or_null("VehicleSelector")
	check("selector_attached_to_playable_scene", selector != null)
	if selector == null:
		quit(1)
		return
	check("all_playable_cards_in_scrollable_grid",
		selector.cards.size() == 89 and selector.scroll is ScrollContainer \
		and selector.grid is GridContainer)
	selector.open_menu()
	check("vehicle_menu_pauses_driving",
		selector.overlay.visible and paused and not selector.launch_button.visible)
	selector.close_menu()
	check("vehicle_menu_restores_driving",
		not selector.overlay.visible and not paused and selector.launch_button.visible)
	selector._apply_filter("Ferrari")
	var visible_ferrari := 0
	for card in selector.cards:
		if (card.button as Button).visible:
			visible_ferrari += 1
	check("vehicle_search_filters_grid", visible_ferrari == 10, visible_ferrari)
	selector._apply_filter("")
	var player: VehicleController2D = main.vehicle
	var first_location := player.global_transform
	var per_brand_pass := true
	var brand_errors: Array[String] = []
	for brand in brands.keys():
		var entry := {}
		for item in vehicles:
			if str(item.brand) == str(brand):
				entry = item
				break
		if not Catalog.select(player, entry):
			per_brand_pass = false
			continue
		var shape := (player.get_node("CollisionShape2D") as CollisionShape2D).shape as CapsuleShape2D
		var wheels := player.get_node("Art/Wheels")
		var sprite := player.get_node("Art/Sprite") as Sprite2D
		var bounds: Rect2 = wheels.visible_bounds
		var expected_width: float = float(entry.width_m) * 20.0
		var expected_length: float = float(entry.length_m) * 20.0
		var good := absf(bounds.size.x - expected_width) < expected_width * 0.16 and \
			absf(bounds.size.y - expected_length) < expected_length * 0.16 and \
			shape.radius > 8.0 and shape.height > shape.radius * 2.0 and \
			sprite.texture != null and \
			is_equal_approx(player.config.mass_kg, float(entry.mass_kg)) and \
			is_equal_approx(player.config.engine_power_kw, float(entry.power_kw)) \
			and player.global_position.distance_to(first_location.origin) < 0.01
		if not good:
			brand_errors.append("%s: actual=%s desired=(%.1f,%.1f) collider=%s" % [
				str(brand), bounds.size, expected_width, expected_length,
				[shape.radius, shape.height]])
		per_brand_pass = per_brand_pass and good
	check("all_brands_instantiate_with_fitted_art_and_physics", per_brand_pass, brand_errors)
	# Every binary should be selectable, not just one representative brand.
	var missing_models: Array[String] = []
	for entry in vehicles:
		if not Catalog.select(player, entry):
			missing_models.append(str(entry.display_name))
			continue
		var sprite := player.get_node("Art/Sprite") as Sprite2D
		var shape := (player.get_node("CollisionShape2D") as CollisionShape2D).shape as CapsuleShape2D
		var wheels := player.get_node("Art/Wheels")
		var size: Vector2 = wheels.visible_bounds.size
		if sprite.texture == null or shape == null or size.x < 25.0 or size.y < 50.0:
			missing_models.append(str(entry.display_name))
	check("every_catalog_vehicle_can_be_equipped", missing_models.is_empty(), missing_models)
	var slow := Catalog.find_by_id("ford-fiesta")
	var fast := Catalog.find_by_id("bugatti-chiron")
	check("distinct_power_to_weight_ratios",
		float(fast.power_kw) / float(fast.mass_kg) > \
		float(slow.power_kw) / float(slow.mass_kg) * 2.0)
	check("distinct_braking_capacity",
		float(fast.brake_force_n) > float(slow.brake_force_n))
	selector.open_menu()
	selector._choose(slow)
	check("clicking_car_equips_and_resumes",
		not paused and not selector.overlay.visible and \
		is_equal_approx(player.config.mass_kg, float(slow.mass_kg)))
	var saved := ConfigFile.new()
	check("selected_vehicle_id_persists",
		saved.load("user://streetbound_selected_vehicle.cfg") == OK and \
		str(saved.get_value("vehicle", "selected_id", "")) == str(slow.id))
	check("hud_shows_selected_vehicle",
		main.get_node("VehicleSelector").driving_hud.active_vehicle_label.text == \
		str(slow.display_name).to_upper())
	if old_save.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	else:
		var file := FileAccess.open(save_path, FileAccess.WRITE)
		if file != null:
			file.store_string(old_save)
	print("PLAYER VEHICLE ROSTER: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
