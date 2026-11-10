extends SceneTree
## Upgrade inventory, race drops, gated car-specific slots, real physics
## specialization and saved/restored garage loadouts.
const Parts = preload("res://scripts/vehicle/upgrade_parts.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Progress = preload("res://scripts/vehicle/race_progression.gd")
const GarageGeometry = preload("res://scripts/world/garage_geometry.gd")
const PPM := 20.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(name: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL",name,detail])
	if not passed:
		failures.append(name)


func run() -> void:
	check("eight_distinct_upgrade_slots",Parts.SLOTS.size() == 8)
	check("fifty_part_variants_loaded",Parts.all().size() == 50)
	var complete := true
	for slot in Parts.SLOTS:
		for rarity in Parts.RARITIES:
			var variants := 0
			for part in Parts.in_slot(slot):
				if str(part.rarity) == rarity:
					variants += 1
			complete = complete and variants == (2 if slot in ["suspension","tires"] else 1)
	check("every_slot_has_all_five_rarities_and_both_handling_specs",complete)
	var economy := Ownership.new(false)
	check("fresh_ownership_has_no_upgrade_loot",
		economy.upgrade_inventory.is_empty() and economy.upgrade_loadouts.is_empty())
	check("invalid_race_never_creates_part",
		str(economy.record_completed_race("bad",0.0).result) != "completed" and \
		economy.upgrade_inventory.is_empty())
	var result := economy.record_completed_race("upgrade-test-first-race",12.5)
	check("winning_race_always_awards_owned_part",
		str(result.get("result","")) == "completed" and \
		result.get("part",{}) is Dictionary and \
		not (result.get("part",{}) as Dictionary).is_empty() and \
		economy.upgrade_inventory.size() == 1)
	var awarded_uid := str(result.get("part_uid",""))
	check("race_receipt_points_to_real_inventory_item",
		economy.get_upgrade_item(awarded_uid).get("template","") == \
		str((result.get("part",{}) as Dictionary).get("id","")))
	var old_inventory_count := economy.upgrade_inventory.size()
	check("same_race_cannot_duplicate_loot",
		str(economy.record_completed_race("upgrade-test-first-race",12.5).result)
		== "invalid_or_duplicate" and economy.upgrade_inventory.size() == old_inventory_count)
	check("fresh_car_cannot_equip_common_before_level_ten",
		economy.install_part(Ownership.STARTER_ID,awarded_uid) == "level_locked")
	var rewarded: Dictionary = Parts.get_part(str(economy.get_upgrade_item(awarded_uid).template))
	check("reward_part_stats_are_explicit",not rewarded.is_empty() and \
		rewarded.get("modifiers",{}) is Dictionary and \
		not (rewarded.modifiers as Dictionary).is_empty())
	economy.car_xp[Ownership.STARTER_ID] = Progress.car_threshold(10)
	check("common_upgrade_unlocks_at_car_level_ten",
		economy.install_part(Ownership.STARTER_ID,awarded_uid) == "installed")
	var installed_slot := str(rewarded.slot)
	check("part_occupies_its_declared_slot",
		economy.equipped_uid(Ownership.STARTER_ID,installed_slot) == awarded_uid and \
		economy.installed_templates(Ownership.STARTER_ID).size() == 1)
	var entry := Catalog.find_by_id(Ownership.STARTER_ID)
	var base: VehicleConfig = Catalog.make_configuration(entry)
	var upgraded: VehicleConfig = Catalog.make_configuration(entry)
	economy.apply_car_upgrades(upgraded,Ownership.STARTER_ID)
	var changed_some_stat := false
	for field in rewarded.modifiers:
		changed_some_stat = changed_some_stat or \
			not is_equal_approx(float(base.get(str(field))),float(upgraded.get(str(field))))
	check("installed_upgrades_change_real_vehicle_physics",changed_some_stat)
	var before_values := {}
	for field in rewarded.modifiers:
		before_values[str(field)] = float(upgraded.get(str(field)))
	economy.apply_car_upgrades(upgraded,Ownership.STARTER_ID)
	var applied_twice := false
	for field in rewarded.modifiers:
		if not is_equal_approx(float(before_values[str(field)]),float(upgraded.get(str(field)))):
			applied_twice = true
	# The modifier API requires a stock config. The garage rebuild always
	# provides it; applying twice to the same config is intentionally additive.
	var fresh: VehicleConfig = Catalog.make_configuration(entry)
	economy.apply_car_upgrades(fresh,Ownership.STARTER_ID)
	check("fresh_stock_rebuild_is_stable_and_repeatable",
		is_equal_approx(float(fresh.get(str(rewarded.modifiers.keys()[0]))),
			float(before_values[str(rewarded.modifiers.keys()[0])])))
	# Compare specializations with an identical untouched chassis.
	var grip_part := Parts.get_part("suspension-grip-common")
	var drift_part := Parts.get_part("suspension-drift-common")
	var grip: VehicleConfig = Catalog.make_configuration(entry)
	var drift: VehicleConfig = Catalog.make_configuration(entry)
	Parts.apply_to_config(grip,[grip_part])
	Parts.apply_to_config(drift,[drift_part])
	check("grip_suspension_has_higher_cornering_stiffness",
		grip.cornering_stiffness > drift.cornering_stiffness)
	check("drift_suspension_increases_steering_and_reduces_rear_grip",
		drift.max_steer_degrees > grip.max_steer_degrees and \
		drift.rear_grip_balance < grip.rear_grip_balance)
	grip = Catalog.make_configuration(entry)
	drift = Catalog.make_configuration(entry)
	Parts.apply_to_config(grip,[Parts.get_part("tires-grip-common")])
	Parts.apply_to_config(drift,[Parts.get_part("tires-drift-common")])
	check("grip_tires_have_more_lateral_grip",
		grip.tire_grip*grip.rear_grip_balance > drift.tire_grip*drift.rear_grip_balance)
	check("drift_tires_increase_slide_recovery",
		drift.countersteer_assist > grip.countersteer_assist)
	economy.upgrade_inventory.append({"uid":"up-9001","template":"suspension-drift-rare"})
	check("rare_parts_locked_below_car_level_30",
		economy.install_part(Ownership.STARTER_ID,"up-9001") == "level_locked")
	economy.car_xp[Ownership.STARTER_ID] = Progress.car_threshold(30)
	check("rare_parts_install_at_car_level_30",
		economy.install_part(Ownership.STARTER_ID,"up-9001") == "installed")
	check("garage_can_unequip_a_part_without_losing_it",
		economy.unequip_part(Ownership.STARTER_ID,"suspension") == "removed" and \
		not economy.get_upgrade_item("up-9001").is_empty() and \
		economy.equipped_uid(Ownership.STARTER_ID,"suspension").is_empty())
	check("cannot_equip_nonexistent_inventory_item",
		economy.install_part(Ownership.STARTER_ID,"forged-item") == "unknown_part")
	check("can_earn_purchasable_second_car_for_different_loadout",
		economy.purchase("dodge-neon") == "purchased")
	var second_car := "dodge-neon"
	economy.car_xp[second_car] = Progress.car_threshold(30)
	check("one_physical_part_cannot_be_equipped_on_two_cars",
		economy.install_part(second_car,awarded_uid) == "equipped_elsewhere")
	check("unequipping_allows_transfer_to_another_owned_car",
		economy.unequip_part(Ownership.STARTER_ID,installed_slot) == "removed" and \
		economy.install_part(second_car,awarded_uid) == "installed")
	check("each_car_retains_its_independent_upgrade_slots",
		economy.installed_templates(Ownership.STARTER_ID).is_empty() and \
		economy.installed_templates(second_car).size() == 1)
	# Exercise actual UI and character config while parked at Laurel.
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	var car: VehicleController2D = game.vehicle
	car.set_physics_process(false)
	var garage: CanvasLayer = game.get_node("VehicleSelector")
	garage.inventory = economy
	var screen: Control = garage.upgrade_screen
	screen.set("economy",economy)
	economy.changed.connect(screen.refresh)
	var garage_prop: Dictionary = game.ground.player_garage_prop
	var parking: Rect2 = GarageGeometry.parking_rect(
		Vector2(float(garage_prop.size[0]),float(garage_prop.size[1])))
	var p := parking.get_center().rotated(float(garage_prop.angle))
	car.global_position = (Vector2(float(garage_prop.p[0]),
		float(garage_prop.p[1]))+p)*PPM
	car.linear_velocity = Vector2.ZERO
	car.velocity = Vector2.ZERO
	garage.open_menu()
	garage._show_tab("upgrades")
	check("garage_has_real_upgrades_tab_and_eight_slot_buttons",
		garage.overlay.visible and garage.active_tab == "upgrades" and \
		screen.visible and screen.slots_box.get_child_count() == 8)
	check("garage_lists_owned_parts_for_chosen_slot",
		screen.inventory_label.text.contains("OWNED PART"))
	# UI installation changes actual controller parameters as well as the
	# saved loadout. Does not merely redraw the stat preview.
	economy.unequip_part(second_car,installed_slot)
	screen.call("_select_slot",installed_slot)
	screen.call("_equip",awarded_uid)
	var current_part := Parts.get_part(str(economy.get_upgrade_item(awarded_uid).template))
	var stock: VehicleConfig = Catalog.make_configuration(entry)
	var expected: VehicleConfig = Catalog.make_configuration(entry)
	Parts.apply_to_config(expected,[current_part])
	var key := str(current_part.modifiers.keys()[0])
	check("garage_part_install_applies_to_live_driving_physics",
		is_equal_approx(float(car.config.get(key)),float(expected.get(key))) and \
		not is_equal_approx(float(stock.get(key)),float(car.config.get(key))))
	screen.call("_unequip_current_slot")
	check("garage_unequip_restores_stock_driving_stat",
		is_equal_approx(float(car.config.get(key)),float(stock.get(key))))
	garage.close_menu()
	# Real persistence across a process restart, with restoration of any
	# prior user save after the test completes.
	var path := Ownership.SAVE_PATH
	var had_save := FileAccess.file_exists(path)
	var original := FileAccess.get_file_as_bytes(path) if had_save else PackedByteArray()
	var persisted := Ownership.new(false)
	persisted.persist_enabled = true
	persisted.owned[second_car] = true
	persisted.car_xp[second_car] = Progress.car_threshold(30)
	persisted.upgrade_inventory = [{"uid":"up-12","template":"tires-grip-rare"},
		{"uid":"up-13","template":"suspension-drift-uncommon"}]
	persisted.next_part_uid = 14
	persisted.upgrade_loadouts = {second_car:{"tires":"up-12"}}
	check("upgrades_persist_to_existing_ownership_file",persisted.save())
	var reloaded := Ownership.new()
	check("saved_inventory_restores_both_unique_parts",
		reloaded.upgrade_inventory.size() == 2 and \
		reloaded.get_upgrade_item("up-12").template == "tires-grip-rare")
	check("per_car_loadout_restores_at_eligible_level",
		reloaded.equipped_uid(second_car,"tires") == "up-12" and \
		reloaded.installed_templates(second_car).size() == 1 and \
		reloaded.equipped_uid(Ownership.STARTER_ID,"tires") == "")
	check("serialized_next_item_identifier_is_not_reused",
		reloaded.next_part_uid >= 14)
	var legacy := ConfigFile.new()
	legacy.set_value("economy","balance",32000)
	legacy.set_value("economy","owned_ids",[Ownership.STARTER_ID])
	legacy.set_value("economy","active_id",Ownership.STARTER_ID)
	legacy.save(path)
	var migrated := Ownership.new()
	check("older_saves_migrate_without_losing_cars_or_progress",
		migrated.owns(Ownership.STARTER_ID) and migrated.upgrade_inventory.is_empty()
		and migrated.upgrade_loadouts.is_empty())
	if had_save:
		var handle := FileAccess.open(path,FileAccess.WRITE)
		if handle != null:
			handle.store_buffer(original)
			handle.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RACE EARNED UPGRADES: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
