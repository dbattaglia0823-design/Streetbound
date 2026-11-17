extends SceneTree
## Prevent another generic-spec copy/paste across any of the 98 playable
## vehicles. Every real-world reference is tied to a named year and trim.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const VehicleCfg = preload("res://scripts/vehicle/vehicle_config.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL",label,str(detail)])
	if not passed:
		failures.append(label)


func _run() -> void:
	var vehicles: Array[Dictionary] = Catalog.all()
	check("ninety_eight_playable_vehicles_retained",vehicles.size()==98,vehicles.size())
	var valid := true
	var proper_physics := true
	var ids := {}
	var direct_sources := 0
	var estimated_specs := 0
	var price_bases := {}
	var unique_signatures := {}
	var all_gears := true
	var all_hybrids := true
	for v in vehicles:
		var id := str(v.get("id",""))
		ids[id] = true
		var year := int(v.get("reference_year",0))
		var trim := str(v.get("reference_trim",""))
		var basis := str(v.get("price_basis",""))
		price_bases[basis] = true
		valid = valid and year>=1980 and year<=2027 and trim.length()>=6 and \
			str(v.get("reference_price_note","")).length()>20 and \
			int(v.get("price_usd",0))>=4500 and \
			float(v.get("power_kw",0.0))>70.0 and \
			float(v.get("mass_kg",0.0))>800.0 and \
			float(v.get("torque_nm",0.0))>100.0 and \
			float(v.get("wheelbase_m",0.0))>2.0
		var confidence := str(v.get("spec_confidence",""))
		if confidence == "source_checked":
			direct_sources += 1
			valid = valid and str(v.get("source_spec_url","")).begins_with("https://")
		elif confidence == "representative_trim":
			estimated_specs += 1
			valid = valid and str(v.get("source_spec_url","")).is_empty()
		else:
			valid = false
		var fingerprint := "%s/%s/%s/%s/%s" % [
			v.power_kw,v.torque_nm,v.mass_kg,v.length_m,v.width_m]
		unique_signatures[fingerprint] = true
		var cfg: VehicleConfig = Catalog.make_configuration(v)
		proper_physics = proper_physics and \
			is_equal_approx(cfg.engine_power_kw,float(v.power_kw)) and \
			is_equal_approx(cfg.engine_torque_nm,float(v.torque_nm)) and \
			is_equal_approx(cfg.mass_kg,float(v.mass_kg)) and \
			cfg.drivetrain == {"FWD":VehicleCfg.Drivetrain.FWD,
				"RWD":VehicleCfg.Drivetrain.RWD,
				"AWD":VehicleCfg.Drivetrain.AWD}.get(str(v.drivetrain),-1)
		all_gears = all_gears and cfg.gear_ratios.size() == \
			int(v.get("reference_gear_count",0)) and \
			int(v.get("reference_gear_count",0)) in [1,4,5,6,7,8,9,10]
		var powertrain := str(v.get("reference_powertrain",""))
		all_hybrids = all_hybrids and powertrain in ["gas","hybrid","electric"]
		if powertrain == "hybrid":
			all_hybrids = all_hybrids and cfg.audio_hybrid_assist>=0.99
		if powertrain == "electric":
			all_hybrids = all_hybrids and \
				cfg.audio_family=="electric" and \
				cfg.audio_induction=="electric" and cfg.gear_ratios.size()==1
	check("every_car_has_a_named_real_model_year_and_trim",valid)
	check("vehicle_ids_unchanged_and_unique",ids.size()==98)
	check("source_checked_and_representative_trims_distinguished",
		direct_sources>=31 and estimated_specs>=1 and \
		direct_sources+estimated_specs==98,[direct_sources,estimated_specs])
	check("prices_are_explicit_about_original_vs_estimated_market_basis",
		price_bases.size()==6 and \
		Catalog.price_basis_label({"price_basis":"msrp_usd"})=="BASE MSRP" and \
		Catalog.price_basis_label({"price_basis":"collector_estimate_usd"})=="EST. COLLECTOR" and \
		Catalog.price_basis_label({"price_basis":"international_used_estimate_usd"})=="EST. IMPORT/USED")
	check("class_copies_replaced_by_distinct_vehicle_baselines",
		unique_signatures.size()>88,unique_signatures.size())
	check("engine_torque_hp_mass_and_drivetrain_reach_real_driving_config",
		proper_physics)
	check("factory_forward_gear_counts_reach_real_driving_config",all_gears)
	check("ev_and_hybrid_sound_identity_follows_reference_powertrain",all_hybrids)
	var expected := {
		"acura-integra-types":[320,"FWD",52600],
		"acura-nsx":[600,"AWD",171495],
		"cadillac-ct5-v-blackwing":[668,"RWD",95595],
		"cadillac-celestiq":[655,"AWD",340000],
		"chevrolet-corvette-zr1x":[1250,"AWD",207395],
		"ferrari-f40":[478,"RWD",3000000],
		"bugatti-eb110":[560,"AWD",1900000],
		"bugatti-tourbillon":[1775,"AWD",4200000]
	}
	var priority_corrections := true
	for id in expected:
		var v: Dictionary = Catalog.find_by_id(id)
		var values: Array = expected[id]
		priority_corrections = priority_corrections and not v.is_empty() and \
			absf(float(v.power_kw)*1.341022-float(values[0]))<0.25 and \
			str(v.drivetrain)==str(values[1]) and \
			int(v.price_usd)==int(values[2])
	check("major_added_and_historical_vehicle_errors_are_corrected",
		priority_corrections)
	var batur: VehicleConfig = Catalog.make_configuration(
		Catalog.find_by_id("bentley-batur"))
	var mulsanne: VehicleConfig = Catalog.make_configuration(
		Catalog.find_by_id("bentley-mulsanne"))
	var bolide: Dictionary = Catalog.find_by_id("bugatti-bolide")
	var tourbillon: Dictionary = Catalog.find_by_id("bugatti-tourbillon")
	check("bentley_w12_and_rwd_luxury_sedan_not_generic_v8_awds",
		batur.drivetrain == VehicleCfg.Drivetrain.AWD and \
		mulsanne.drivetrain == VehicleCfg.Drivetrain.RWD and \
		batur.engine_power_kw > mulsanne.engine_power_kw)
	check("non_comparable_dry_weight_and_hybrid_torque_explicitly_labeled",
		str(bolide.reference_mass_basis)=="manufacturer_dry" and \
		str(tourbillon.reference_torque_basis)=="combustion_engine_only")
	print("VEHICLE REAL-WORLD AUDIT: ",
		"PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
