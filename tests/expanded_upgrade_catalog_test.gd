extends SceneTree
## Upgrade catalog integrity and unavailable-until-race-integration contract.
const Parts = preload("res://scripts/vehicle/upgrade_parts.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Progress = preload("res://scripts/vehicle/race_progression.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, success: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if success else "FAIL", label, str(detail)])
	if not success:
		failures.append(label)

func _run() -> void:
	var all_parts: Dictionary = Parts.all()
	check("catalog_has_150_unique_templates",all_parts.size()==150)
	check("ten_upgrade_categories_available",Parts.SLOTS.size()==10)
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
			complete = complete and count==3 and specialties.size()==3
	check("three_distinct_variants_in_each_of_five_rarities_per_category",complete)
	var legacy := 0
	var future := 0
	var modifiers_valid := true
	for part in all_parts.values():
		if bool(part.get("race_drop_enabled",true)):
			legacy += 1
		else:
			future += 1
		var mods: Dictionary = part.get("modifiers",{})
		modifiers_valid = modifiers_valid and not mods.is_empty()
		for field in mods:
			modifiers_valid = modifiers_valid and Parts.FIELD_LABELS.has(str(field)) and \
				(typeof(mods[field]) == TYPE_FLOAT or typeof(mods[field]) == TYPE_INT)
	check("legacy_50_preserved_new_100_are_future_race_rewards",legacy==50 and future==100,
		[legacy,future])
	check("new_modifier_fields_all_supported_by_physics",modifiers_valid)
	var no_new_race_part := true
	for rarity_seed in 90:
		var reward: Dictionary = Parts.reward_template("catalog-test-%d" % rarity_seed,50)
		no_new_race_part = no_new_race_part and not reward.is_empty() and \
			bool(reward.get("race_drop_enabled",true))
	check("current_race_rewards_never_grant_new_variants",no_new_race_part)
	var empty_inventory := Ownership.new(false)
	check("no_new_parts_auto_awarded_or_owned",
		empty_inventory.upgrade_inventory.is_empty() and
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
		turbo.boost_max_psi > stock.boost_max_psi and
		turbo.engine_torque_nm > stock.engine_torque_nm)
	if stock.audio_induction=="naturally_aspirated":
		check("turbo_uses_existing_turbo_audio_profile",
			turbo.audio_induction=="turbo" and
			turbo.audio_turbo_presence>stock.audio_turbo_presence)
	var nitro: VehicleConfig = Catalog.make_configuration(starter)
	Parts.apply_to_config(nitro,[Parts.get_part("nitrous-endurance-common")])
	check("nitrous_has_real_tank_power_and_recharge_fields",
		nitro.nitrous_capacity_seconds>0.0 and
		nitro.nitrous_torque_fraction>0.0 and
		nitro.nitrous_recharge_seconds>0.0)
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
