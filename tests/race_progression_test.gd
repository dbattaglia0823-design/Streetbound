extends SceneTree
## Race-only player/car XP, persistence, purchase locks, rarity thresholds,
## and the physical Ashford 1/4-mile finish trigger.
const Progress = preload("res://scripts/vehicle/race_progression.gd")
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const PPM := 20.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(name: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL",name,detail])
	if not passed:
		failures.append(name)


func run() -> void:
	var curves_valid := true
	for level in range(1,Progress.MAX_PLAYER_LEVEL):
		curves_valid = curves_valid and \
			Progress.player_threshold(level) < Progress.player_threshold(level+1)
	for level in range(1,Progress.MAX_CAR_LEVEL):
		curves_valid = curves_valid and \
			Progress.car_threshold(level) < Progress.car_threshold(level+1)
	check("level_curves_are_strictly_increasing",curves_valid)
	check("driver_caps_at_level_100",
		Progress.player_level(Progress.player_threshold(100)) == 100 and \
		Progress.player_level(99999999) == 100 and \
		Progress.player_xp_remaining(99999999) == 0)
	check("car_caps_at_level_50",
		Progress.car_level(Progress.car_threshold(50)) == 50 and \
		Progress.car_level(99999999) == 50 and \
		Progress.car_xp_remaining(99999999) == 0)
	var rarity_ok := true
	for rarity in ["Common","Uncommon","Rare","Epic","Legendary"]:
		var threshold: int = Progress.RARITY_THRESHOLDS[rarity]
		rarity_ok = rarity_ok and \
			not Progress.can_install_rarity(threshold-1,rarity) and \
			Progress.can_install_rarity(threshold,rarity)
	check("rarity_gates_at_car_levels_10_20_30_40_50",rarity_ok)
	check("level_1_cannot_use_common_upgrades",
		Progress.highest_upgrade_rarity(1) == "Locked")
	check("level_50_can_use_all_rarities",
		Progress.highest_upgrade_rarity(50) == "Legendary")
	var requirements_valid := true
	var showroom_requires_progress := true
	for entry in Catalog.all():
		var needed := int(entry.get("required_player_level",0))
		requirements_valid = requirements_valid and needed >= 1 and needed <= 100
		if str(entry.dealership_id) in ["exotic","luxury"]:
			showroom_requires_progress = showroom_requires_progress and needed >= 52
	check("all_88_have_player_level_requirements",requirements_valid)
	check("exotic_and_luxury_shops_require_progress",showroom_requires_progress)
	var economy := Ownership.new(false)
	var expensive: Dictionary = Catalog.find_by_id("bugatti-chiron")
	economy.balance = 10000000
	var prior_cash := economy.balance
	check("unowned_high_level_car_locked_despite_money",
		economy.purchase("bugatti-chiron") == "level_locked" and \
		economy.balance == prior_cash and not economy.owns("bugatti-chiron"))
	var needed := economy.required_player_level(expensive)
	economy.player_xp = Progress.player_threshold(needed)
	check("player_level_unlocks_that_exact_car",
		economy.player_level() == needed and \
		economy.purchase("bugatti-chiron") == "purchased")
	check("new_purchase_starts_at_car_level_1",
		economy.level_for_car("bugatti-chiron") == 1 and \
		not economy.can_use_upgrade("bugatti-chiron","Common"))
	var neutral := Ownership.new(false)
	var before_player_xp := neutral.player_xp
	var before_car_xp := int(neutral.car_xp.get(neutral.active_id,0))
	check("no_passive_xp_without_a_completed_race",
		before_player_xp == 0 and before_car_xp == 0)
	check("malformed_races_cannot_award_xp",
		str(neutral.record_completed_race("bad",0).result) != "completed" and \
		str(neutral.record_completed_race("bad-event",5).result) != "completed")
	check("malformed_race_does_not_change_level",
		neutral.player_level() == 1 and neutral.active_car_level() == 1)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var vehicle: VehicleController2D = main.vehicle
	vehicle.set_physics_process(false)
	var race: Node2D = main.drag_race
	var level_hud: CanvasLayer = main.progression_hud
	check("playable_ashford_race_and_progress_hud_exist",
		race != null and race.available and level_hud != null)
	if race == null or not race.available:
		quit(1)
		return
	race.set_physics_process(false)
	race.economy = neutral
	level_hud.economy = neutral
	neutral.changed.connect(level_hud.refresh)
	check("racing_cannot_start_from_laurel_garage",not race.can_stage())
	var start: Vector2 = race.start_m * PPM
	vehicle.global_position = start
	vehicle.rotation = race.direction.angle() + PI/2.0
	vehicle.linear_velocity = Vector2.ZERO
	vehicle.velocity = Vector2.ZERO
	check("player_must_stop_at_track_start",race.can_stage())
	check("race_countdown_starts_only_once",race.start_race() and \
		not race.start_race() and race.state == "countdown")
	check("cannot_earn_during_countdown",
		neutral.player_xp == 0 and neutral.active_car_level() == 1)
	race._physics_process(3.05)
	check("race_transitions_to_live_run",race.state == "running")
	var elapsed_step := 0.025
	var forward := race.direction
	for i in range(405):
		vehicle.global_position = start + forward * (float(i+1) * PPM)
		vehicle.linear_velocity = forward * 40.0
		race._physics_process(elapsed_step)
		if race.state != "running":
			break
	check("quarter_mile_finish_is_valid_and_recorded",
		race.state == "results",race.state)
	check("race_awards_driver_and_only_active_car_xp",
		neutral.player_xp > 0 and int(neutral.car_xp.get(
			neutral.active_id,0)) > 0)
	check("valid_race_updates_driver_and_car_levels",
		neutral.player_level() > 1 and neutral.active_car_level() > 1)
	check("valid_race_awards_some_cash",neutral.balance > Ownership.STARTING_CASH)
	check("race_hud_displays_both_progressions",
		level_hud.player_label.text.contains("DRIVER LV") and \
		level_hud.car_label.text.contains("CAR LV"))
	var earned_xp := neutral.player_xp
	race._complete()
	check("finish_payout_is_not_repeatable",
		neutral.player_xp == earned_xp)
	var other_id := "dodge-neon"
	check("other_car_can_be_purchased",neutral.purchase(other_id) == "purchased")
	check("new_car_keeps_independent_level",
		neutral.level_for_car(other_id) == 1)
	check("equipping_car_switches_active_xp_track",neutral.equip(other_id) and \
		neutral.active_car_level() == 1)
	check("other_vehicle_does_not_inherit_xp",
		int(neutral.car_xp.get(other_id,0)) == 0)
	check("duplicate_race_id_does_not_grant_anything",
		str(neutral.record_completed_race(race._run_id, 11.2).result) != "completed")
	# Return to staging and simulate an invalid teleport instead of legitimate
	# longitudinal road progress. This must never credit either XP track.
	race.state = "idle"
	vehicle.global_position = start
	vehicle.rotation = race.direction.angle()+PI/2.0
	vehicle.linear_velocity = Vector2.ZERO
	check("second_race_can_be_staged",race.start_race())
	race._physics_process(3.05)
	vehicle.global_position = start + forward * (100.0*PPM)
	vehicle.linear_velocity = forward * 40.0
	race._physics_process(0.025)
	check("race_teleport_is_rejected",race.state == "aborted")
	check("aborted_run_awards_zero_xp_to_new_car",
		int(neutral.car_xp.get(other_id,0)) == 0 and neutral.player_xp == earned_xp)
	var first_car_xp := int(neutral.car_xp.get(Ownership.STARTER_ID,0))
	# Direct validated finish recording still applies to the actual active
	# vehicle, not the car that finished the previous event.
	var car2_result := neutral.record_completed_race("race-second-unique",15.0)
	check("recorded_race_xp_applies_to_equipped_car_only",
		str(car2_result.result) == "completed" and \
		int(neutral.car_xp.get(other_id,0)) > 0 and \
		int(neutral.car_xp.get(Ownership.STARTER_ID,0)) == first_car_xp)
	# Verify legacy save migration + persistence without modifying a user's save.
	var saved_path: String = Ownership.SAVE_PATH
	var had_save := FileAccess.file_exists(saved_path)
	var previous := FileAccess.get_file_as_bytes(saved_path) if had_save else PackedByteArray()
	var persist := Ownership.new(false)
	persist.persist_enabled = true
	persist.player_xp = Progress.player_threshold(36) + 130
	persist.owned[other_id] = true
	persist.car_xp[Ownership.STARTER_ID] = Progress.car_threshold(23) + 15
	persist.car_xp[other_id] = Progress.car_threshold(9)
	persist.active_id = other_id
	check("progression_save_succeeds",persist.save())
	var restored := Ownership.new()
	check("driver_level_and_xp_survive_reload",
		restored.player_xp == persist.player_xp and restored.player_level() == 36)
	check("each_car_level_survives_reload",
		restored.level_for_car(Ownership.STARTER_ID) == 23 and \
		restored.level_for_car(other_id) == 9)
	check("active_car_restores_correct_level",
		restored.active_id == other_id and restored.active_car_level() == 9)
	var legacy := ConfigFile.new()
	legacy.set_value("economy","balance",53000)
	legacy.set_value("economy","owned_ids",[Ownership.STARTER_ID,other_id])
	legacy.set_value("economy","active_id",other_id)
	legacy.save(saved_path)
	var migrated := Ownership.new()
	check("old_ownership_save_defaults_to_level_1",
		migrated.balance == 53000 and migrated.player_level() == 1 and \
		migrated.level_for_car(other_id) == 1 and migrated.owns(other_id))
	if had_save:
		var handle := FileAccess.open(saved_path, FileAccess.WRITE)
		if handle != null:
			handle.store_buffer(previous)
			handle.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_path))
	print("RACING / DRIVER / CAR LEVELS: ",
		"PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
