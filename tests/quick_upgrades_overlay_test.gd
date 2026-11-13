extends SceneTree
## Real paused-world upgrade UI, six visible slots and live-part hot swaps.
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Progress = preload("res://scripts/vehicle/race_progression.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool, detail: Variant = "") -> void:
	print("%s %s %s" % ["PASS" if condition else "FAIL",label,str(detail)])
	if not condition:
		failures.append(label)

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var quick: CanvasLayer = main.quick_upgrades
	var car: VehicleController2D = main.vehicle
	check("quick_overlay_exists_in_playable_scene",quick != null and
		quick.get_script() == load("res://scripts/ui/quick_upgrades_overlay.gd"))
	if quick == null or car == null:
		quit(1)
		return
	car.set_physics_process(false)
	check("six_quick_slots_not_eight",quick.slot_buttons.size() == 6)
	check("real_parts_not_fake_turbo_nitrous_slots",
		quick.slot_buttons.has("engine") and quick.slot_buttons.has("intake") and
		quick.slot_buttons.has("transmission") and quick.slot_buttons.has("tires") and
		quick.slot_buttons.has("suspension") and quick.slot_buttons.has("brakes"))
	check("in_game_car_preview_uses_current_vehicle_art",
		quick.car_preview.texture != null)
	check("world_visible_when_closed",
		not quick.overlay.visible and quick.launch_button.visible)
	var test_economy := Ownership.new(false)
	test_economy.car_xp[Ownership.STARTER_ID] = Progress.car_threshold(30)
	test_economy.upgrade_inventory = [
		{"uid":"up-101","template":"engine-street-common"},
		{"uid":"up-102","template":"engine-street-rare"}
	]
	quick.economy = test_economy
	# Use a deterministic starter car; no real save is changed.
	var starter := Catalog.find_by_id(Ownership.STARTER_ID)
	Catalog.select(car,starter)
	quick.last_car_id = ""
	quick.refresh()
	car.linear_velocity = Vector2(26,-4)
	var previous_position := car.global_position
	var previous_angle := car.rotation
	var previous_velocity := car.linear_velocity
	var previous_gear := car.transmission.gear
	var previous_rpm := car.transmission.rpm
	var before_power := car.config.engine_power_kw
	quick.open_menu()
	check("quick_overlay_pauses_world_anywhere",
		paused and quick.overlay.visible and not quick.launch_button.visible)
	quick._open_slot("engine")
	check("picker_renders_real_owned_parts",
		quick.picker.visible and quick.picker_parts.get_child_count() == 2)
	quick._install_uid("up-101")
	check("first_part_installs_from_overlay",
		test_economy.equipped_uid(Ownership.STARTER_ID,"engine") == "up-101" and
		car.config.engine_power_kw > before_power)
	var first_power := car.config.engine_power_kw
	quick._install_uid("up-102")
	check("hot_swap_replaces_same_slot_not_stack",
		test_economy.equipped_uid(Ownership.STARTER_ID,"engine") == "up-102" and
		car.config.engine_power_kw > first_power and
		test_economy.installed_templates(Ownership.STARTER_ID).size() == 1)
	quick._unequip_selected()
	check("unequip_returns_to_stock_without_drift",
		test_economy.equipped_uid(Ownership.STARTER_ID,"engine") == "" and
		is_equal_approx(car.config.engine_power_kw,before_power),
		[before_power,car.config.engine_power_kw])
	check("swap_preserves_car_position_speed_and_transmission",
		car.global_position.is_equal_approx(previous_position) and
		car.rotation == previous_angle and
		car.linear_velocity == previous_velocity and
		car.transmission.gear == previous_gear and
		car.transmission.rpm == previous_rpm)
	quick.close_menu()
	check("close_resumes_existing_game",
		not paused and not quick.overlay.visible and quick.launch_button.visible)
	paused = true
	quick.open_menu()
	check("cannot_override_other_paused_menu",
		not quick.overlay.visible and paused)
	paused = false
	main.queue_free()
	print("QUICK UPGRADES OVERLAY: ",
		"PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
