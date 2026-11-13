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
	check("six_slots_include_functional_turbo_and_nitrous",
		quick.slot_buttons.has("engine") and quick.slot_buttons.has("turbo") and
		quick.slot_buttons.has("transmission") and quick.slot_buttons.has("tires") and
		quick.slot_buttons.has("suspension") and quick.slot_buttons.has("nitrous"))
	check("in_game_car_preview_uses_current_vehicle_art",
		quick.car_preview.texture != null)
	check("world_visible_when_closed",
		not quick.overlay.visible and quick.launch_button.visible)
	var test_economy := Ownership.new(false)
	test_economy.car_xp[Ownership.STARTER_ID] = Progress.car_threshold(30)
	test_economy.upgrade_inventory = [
		{"uid":"up-101","template":"engine-street-common"},
		{"uid":"up-102","template":"engine-street-rare"},
		{"uid":"up-103","template":"turbo-balanced-common"},
		{"uid":"up-104","template":"nitrous-sprint-common"}
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
	var owned_buttons := 0
	var unowned_buttons := 0
	var all_unowned_disabled := true
	for button in quick.picker_parts.get_children():
		if button.name.begins_with("Part_"):
			owned_buttons += 1
		elif button.name.begins_with("Unowned_"):
			unowned_buttons += 1
			all_unowned_disabled = all_unowned_disabled and button.disabled
	check("picker_lists_all_15_variants_and_owned_parts",
		quick.picker.visible and quick.picker_parts.get_child_count() == 15 and
		owned_buttons == 2 and unowned_buttons == 13 and all_unowned_disabled)
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
	# Turbo kits must work on stock naturally aspirated cars. Swapping the
	# whole slot in-game must affect boost physics and restore the stock voice.
	quick._open_slot("turbo")
	var stock_boost := car.config.boost_max_psi
	var stock_induction := car.config.audio_induction
	quick._install_uid("up-103")
	check("turbo_hot_swap_creates_real_manifold_boost",
		car.config.boost_max_psi > stock_boost and
		test_economy.equipped_uid(Ownership.STARTER_ID,"turbo") == "up-103")
	if stock_induction == "naturally_aspirated":
		check("turbo_hot_swap_activates_turbo_audio",car.config.audio_induction=="turbo")
	quick._unequip_selected()
	check("removing_turbo_restores_stock_boost_and_audio",
		is_equal_approx(car.config.boost_max_psi,stock_boost) and
		car.config.audio_induction == stock_induction)
	# The new Nitrous slot is not just decorative. It changes live tank size
	# and enables temporary torque without spawning a new car.
	quick._open_slot("nitrous")
	quick._install_uid("up-104")
	check("nitrous_picker_shows_all_future_reward_variants",
		quick.picker_parts.get_child_count()==15)
	check("nitrous_slot_installs_real_tank",
		car.config.nitrous_capacity_seconds > 1.0 and
		car.config.nitrous_torque_fraction > 0.0 and
		car.nitrous_fuel_seconds > 0.0)
	var original_tank: float = car.nitrous_fuel_seconds
	car.nitrous_fuel_seconds = original_tank * 0.45
	quick._unequip_selected()
	quick._install_uid("up-104")
	check("nitrous_unequip_reinstall_does_not_refill_tank",
		car.nitrous_fuel_seconds <= original_tank * 0.46)
	quick._unequip_selected()
	check("nitrous_removal_disables_burn",
		is_equal_approx(car.config.nitrous_torque_fraction,0.0) and
		is_equal_approx(car.config.nitrous_capacity_seconds,0.0))
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
