extends SceneTree
## Six-slot upgrade catalog integrity and unavailable-until-race-integration contract.
const Parts = preload("res://scripts/vehicle/upgrade_parts.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Progress = preload("res://scripts/vehicle/race_progression.gd")
const Powertrain = preload("res://scripts/vehicle/powertrain_dynamics.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, success: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if success else "FAIL", label, str(detail)])
	if not success:
		failures.append(label)

func stat(template_id: String, field: String) -> float:
	var part := Parts.get_part(template_id)
	var mods: Dictionary = part.get("modifiers",{})
	return float(mods.get(field,0.0))


func _run() -> void:
	var all_parts: Dictionary = Parts.all()
	check("catalog_has_120_unique_templates",all_parts.size()==120)
	check("only_six_live_upgrade_slots",Parts.SLOTS == ["engine","turbo","transmission","tires","suspension","nitrous"])
	var complete := true
	for slot in Parts.SLOTS:
		for rarity in Parts.RARITIES:
			var count := 0
			var specialties: Dictionary = {}
			for part in Parts.in_slot(slot):
				if str(part.rarity)!=rarity:
					continue
				count += 1
				specialties[str(part.specialty)] = true
			complete = complete and count==4 and specialties.size()==4
	check("four_distinct_variants_in_each_of_five_rarities_per_category",complete)
	var legacy := 0
	var future := 0
	var modifiers_valid := true
	var event_metadata_valid := true
	for part in all_parts.values():
		var reward_sources: Variant = part.get("reward_sources",[])
		event_metadata_valid = event_metadata_valid and \
			reward_sources is Array and not reward_sources.is_empty() and \
			str(part.get("role","")).length() >= 12
		if reward_sources is Array:
			for source_tag in reward_sources:
				event_metadata_valid = event_metadata_valid and \
					Parts.EVENT_TYPES.has(str(source_tag))
		if bool(part.get("race_drop_enabled",true)):
			legacy += 1
		else:
			future += 1
		var mods: Dictionary = part.get("modifiers",{})
		modifiers_valid = modifiers_valid and not mods.is_empty()
		for field in mods:
			modifiers_valid = modifiers_valid and Parts.FIELD_LABELS.has(str(field)) and \
				(typeof(mods[field]) == TYPE_FLOAT or typeof(mods[field]) == TYPE_INT)
	check("retained_30_race_drops_and_90_catalog_only_variants",legacy==30 and future==90,
		[legacy,future])
	check("new_modifier_fields_all_supported_by_physics",modifiers_valid)
	check("all_parts_tagged_for_future_race_pools",event_metadata_valid)
	check("removed_slots_have_no_templates",
		Parts.in_slot("ecu").is_empty() and Parts.in_slot("intake").is_empty() and \
		Parts.in_slot("exhaust").is_empty() and Parts.in_slot("brakes").is_empty() and \
		Parts.get_part("ecu-street-common").is_empty() and \
		Parts.get_part("brakes-street-legendary").is_empty())
	check("old_ten_slot_ui_script_is_gone",
		not FileAccess.file_exists("res://scripts/ui/garage_upgrades.gd"))
	var no_new_race_part := true
	for rarity_seed in 90:
		var reward: Dictionary = Parts.reward_template("catalog-test-%d" % rarity_seed,50)
		no_new_race_part = no_new_race_part and not reward.is_empty() and \
			bool(reward.get("race_drop_enabled",true))
	check("current_race_rewards_never_grant_new_variants",no_new_race_part)
	var event_filtered := true
	for i in 30:
		var part: Dictionary = Parts.reward_template("drift-race-%d" % i,50,"drift")
		event_filtered = event_filtered and not part.is_empty() and \
			part.get("reward_sources",[]).has("drift") and \
			bool(part.get("race_drop_enabled",true))
	check("future_typed_drift_events_filter_to_drift_parts",event_filtered)
	check("unknown_event_types_never_award_unrelated_upgrades",
		Parts.reward_template("wrong-event",50,"unknown").is_empty() and \
		Parts.reward_template("highway-race",50,"highway").is_empty())
	var empty_inventory := Ownership.new(false)
	check("no_new_parts_auto_awarded_or_owned",
		empty_inventory.upgrade_inventory.is_empty() and \
		empty_inventory.installed_templates(Ownership.STARTER_ID).is_empty())
	for id in ["engine-street-common","suspension-grip-rare",
			"tires-drift-legendary","transmission-street-epic"]:
		check("legacy_save_template_still_loads_"+id,
			not Parts.get_part(id).is_empty())
	# Inspect real stat application on the Ford Fiesta, initially N/A.
	var starter: Dictionary = Catalog.find_by_id(Ownership.STARTER_ID)
	var stock: VehicleConfig = Catalog.make_configuration(starter)
	var turbo: VehicleConfig = Catalog.make_configuration(starter)
	Parts.apply_to_config(turbo,[Parts.get_part("turbo-quick-spool-common")])
	check("turbo_increases_real_boost_on_naturally_aspirated_car",
		turbo.boost_max_psi > stock.boost_max_psi and \
		turbo.engine_torque_nm > stock.engine_torque_nm)
	if stock.audio_induction=="naturally_aspirated":
		check("turbo_uses_existing_turbo_audio_profile",
			turbo.audio_induction=="turbo" and \
			turbo.audio_turbo_presence>stock.audio_turbo_presence)
	var nitro: VehicleConfig = Catalog.make_configuration(starter)
	Parts.apply_to_config(nitro,[Parts.get_part("nitrous-endurance-common")])
	check("nitrous_has_real_tank_power_and_recharge_fields",
		nitro.nitrous_capacity_seconds>0.0 and \
		nitro.nitrous_torque_fraction>0.0 and \
		nitro.nitrous_recharge_seconds>0.0)
	# All four same-tier specializations must lead at a different stat.
	# This catches accidental return of a single all-purpose best engine
	# or gearset without pretending a theoretical stat proves track times.
	var specialized := true
	for rarity in Parts.RARITIES:
		var suffix := "-" + str(rarity).to_lower()
		specialized = specialized and \
			stat("engine-torque"+suffix,"engine_torque_nm") > \
			stat("engine-street"+suffix,"engine_torque_nm") and \
			stat("engine-high-rpm"+suffix,"engine_power_kw") > \
			stat("engine-street"+suffix,"engine_power_kw") and \
			stat("engine-lightweight"+suffix,"mass_kg") < 0.0
		specialized = specialized and \
			stat("turbo-quick-spool"+suffix,"boost_spool_seconds") < \
			stat("turbo-balanced"+suffix,"boost_spool_seconds") and \
			stat("turbo-peak-boost"+suffix,"engine_power_kw") > \
			stat("turbo-balanced"+suffix,"engine_power_kw") and \
			stat("turbo-midrange"+suffix,"engine_torque_nm") > \
			stat("turbo-peak-boost"+suffix,"engine_torque_nm")
		specialized = specialized and \
			stat("transmission-launch"+suffix,"final_drive") > \
			stat("transmission-street"+suffix,"final_drive") and \
			stat("transmission-street"+suffix,"shift_duration") < \
			stat("transmission-track"+suffix,"shift_duration") and \
			stat("transmission-top-speed"+suffix,"final_drive") < 0.0
		specialized = specialized and \
			stat("tires-grip"+suffix,"tire_grip") > \
			stat("tires-drag"+suffix,"tire_grip") and \
			stat("tires-drag"+suffix,"launch_grip_bonus") > 0.0 and \
			stat("tires-drift"+suffix,"rear_grip_balance") < 0.0
		specialized = specialized and \
			stat("suspension-grip"+suffix,"cornering_stiffness") > \
			stat("suspension-balanced"+suffix,"cornering_stiffness") and \
			stat("suspension-balanced"+suffix,"yaw_damping") > \
			stat("suspension-grip"+suffix,"yaw_damping") and \
			stat("suspension-precision"+suffix,"steering_response") > \
			stat("suspension-drift"+suffix,"steering_response")
		specialized = specialized and \
			stat("nitrous-sprint"+suffix,"nitrous_torque_fraction") > \
			stat("nitrous-rapid-refill"+suffix,"nitrous_torque_fraction") and \
			stat("nitrous-endurance"+suffix,"nitrous_capacity_seconds") > \
			stat("nitrous-rapid-refill"+suffix,"nitrous_capacity_seconds") and \
			stat("nitrous-rapid-refill"+suffix,"nitrous_recharge_seconds") < \
			stat("nitrous-endurance"+suffix,"nitrous_recharge_seconds")
	check("all_rarities_have_mechanical_specialization_tradeoffs",specialized)
	var lightweight: VehicleConfig = Catalog.make_configuration(starter)
	var forged: VehicleConfig = Catalog.make_configuration(starter)
	Parts.apply_to_config(lightweight,[Parts.get_part("engine-lightweight-legendary")])
	Parts.apply_to_config(forged,[Parts.get_part("engine-street-legendary")])
	check("lightweight_engine_changes_real_mass_not_just_display",
		lightweight.mass_kg < forged.mass_kg and \
		lightweight.engine_power_kw < forged.engine_power_kw)
	var grip_tire: VehicleConfig = Catalog.make_configuration(starter)
	var drag_tire: VehicleConfig = Catalog.make_configuration(starter)
	Parts.apply_to_config(grip_tire,[Parts.get_part("tires-grip-legendary")])
	Parts.apply_to_config(drag_tire,[Parts.get_part("tires-drag-legendary")])
	var load_n := 13000.0
	var drag_launch := Powertrain.traction_force_n(
		drag_tire,load_n,1.0,1.0,"ASPHALT",0.0)
	var grip_launch := Powertrain.traction_force_n(
		grip_tire,load_n,1.0,1.0,"ASPHALT",0.0)
	var drag_fast := Powertrain.traction_force_n(
		drag_tire,load_n,1.0,1.0,"ASPHALT",35.0)
	var grip_fast := Powertrain.traction_force_n(
		grip_tire,load_n,1.0,1.0,"ASPHALT",35.0)
	check("drag_compound_wins_standing_launch_but_not_high_speed_grip",
		drag_launch > grip_launch and drag_fast < grip_fast and \
		drag_tire.tire_grip < grip_tire.tire_grip and \
		drag_tire.cornering_stiffness < grip_tire.cornering_stiffness)
	check("launch_bonus_has_no_effect_off_road",
		is_equal_approx(Powertrain.traction_force_n(
			drag_tire,load_n,0.65,1.0,"GRASS",0.0),
			Powertrain.traction_force_n(
			drag_tire,load_n,0.65,1.0,"GRASS",35.0)))
	var rapid: VehicleConfig = Catalog.make_configuration(starter)
	var endurance: VehicleConfig = Catalog.make_configuration(starter)
	Parts.apply_to_config(rapid,[Parts.get_part("nitrous-rapid-refill-legendary")])
	Parts.apply_to_config(endurance,[Parts.get_part("nitrous-endurance-legendary")])
	check("rapid_refill_short_bursts_have_faster_real_recharge",
		rapid.nitrous_capacity_seconds < endurance.nitrous_capacity_seconds and \
		rapid.nitrous_recharge_seconds < endurance.nitrous_recharge_seconds and \
		rapid.nitrous_torque_fraction > endurance.nitrous_torque_fraction)
	var launch_box: VehicleConfig = Catalog.make_configuration(starter)
	var fast_box: VehicleConfig = Catalog.make_configuration(starter)
	Parts.apply_to_config(launch_box,[Parts.get_part("transmission-launch-legendary")])
	Parts.apply_to_config(fast_box,[Parts.get_part("transmission-street-legendary")])
	check("launch_gearing_increases_ratio_but_fast_shifts_still_win_at_shifts",
		launch_box.final_drive > fast_box.final_drive and \
		launch_box.shift_duration > fast_box.shift_duration)
	var car: VehicleController2D = load("res://scenes/vehicle.tscn").instantiate()
	root.add_child(car)
	car.set_physics_process(false)
	car.external_input = true
	car.config = nitro
	car.on_upgrade_config_changed()
	var tank_before: float = car.nitrous_fuel_seconds
	car.nitrous_requested = true
	for i in 5:
		car.step_vehicle(1.0/60.0,Vector4(1.0,0.0,0.0,0.0))
	check("pressing_nitrous_drains_tank_and_activates_torque",
		car.nitrous_active and car.nitrous_fuel_seconds<tank_before,
		[car.nitrous_active,car.nitrous_fuel_seconds])
	var tank_after_burn: float = car.nitrous_fuel_seconds
	car.nitrous_requested = false
	for i in 6:
		car.step_vehicle(1.0/60.0,Vector4(1.0,0.0,0.0,0.0))
	check("releasing_nitrous_recharges_tank",
		not car.nitrous_active and car.nitrous_fuel_seconds>tank_after_burn)
	car.config = stock
	car.on_upgrade_config_changed(nitro.nitrous_capacity_seconds)
	car.nitrous_requested = true
	car.step_vehicle(1.0/60.0,Vector4(1.0,0.0,0.0,0.0))
	check("no_installed_nitrous_means_no_temporary_power",
		not car.nitrous_active)
	car.queue_free()
	print("EXPANDED UPGRADE CATALOG: ",
		"PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
