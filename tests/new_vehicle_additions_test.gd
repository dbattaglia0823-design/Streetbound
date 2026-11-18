extends SceneTree
## Every newly imported playable PNG must have a distinct market/spec profile
## and remain compatible with dealership, ownership, audio and driving configs.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const DealerConfig = preload("res://scripts/world/dealership_config.gd")
const Synth = preload("res://scripts/audio/engine_sound_synthesis.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s %s" % ["PASS" if passed else "FAIL", label, str(detail)])
	if not passed:
		failures.append(label)


func run() -> void:
	var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/player_vehicle_catalog.json"))
	var extension: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://data/player_vehicle_additions.json"))
	check("both_catalog_documents_parse", baseline is Dictionary and extension is Dictionary)
	if not baseline is Dictionary or not extension is Dictionary:
		quit(1)
		return
	var original: Array = baseline.get("vehicles", [])
	var added: Array = extension.get("vehicles", [])
	var combined: Array[Dictionary] = Catalog.all()
	check("retains_original_98_and_loads_50_new_assets",
		original.size() == 98 and added.size() == 50 and combined.size() == 148,
		[original.size(), added.size(), combined.size()])
	var ids: Dictionary = {}
	var textures: Dictionary = {}
	var valid := true
	var derived_physics := true
	var dealer_routing := true
	var price_provenance := true
	var fictional_prices := 0
	var source_backed := 0
	var dealers: Dictionary = {}
	for shop in DealerConfig.defaults():
		dealers[str(shop.get("id",""))] = shop
	for v in combined:
		var id := str(v.get("id",""))
		valid = valid and not ids.has(id) and not id.is_empty()
		ids[id] = true
	for i in original.size():
		valid = valid and str(original[i].id) == str(combined[i].id)
	for raw in added:
		if not raw is Dictionary:
			valid = false
			continue
		var v: Dictionary = raw
		var id := str(v.get("id",""))
		var sprite := str(v.get("texture",""))
		var basis := str(v.get("price_basis",""))
		var confidence := str(v.get("spec_confidence",""))
		valid = valid and not textures.has(sprite) and sprite.ends_with(".png") and \
			sprite.begins_with("res://assets/Vehicles/") and FileAccess.file_exists(sprite) and \
			not bool(v.get("source_model_unverified",true)) and \
			Catalog.find_by_id(id).get("texture","") == sprite and \
			int(v.get("reference_year",0)) >= 1960 and \
			float(v.get("mass_kg",0)) > 450.0 and \
			float(v.get("power_kw",0)) > 70.0 and \
			float(v.get("wheelbase_m",0)) > 2.0 and \
			int(v.get("price_usd",0)) >= 4500 and Synth.family_supported(
				str(v.get("audio_family",""))) and \
			str(v.get("audio_induction","")) in [
				"naturally_aspirated","turbo","supercharger","electric"]
		textures[sprite] = true
		dealer_routing = dealer_routing and dealers.has(str(v.get("dealership_id","")))
		var shop: Dictionary = dealers.get(str(v.get("dealership_id","")),{})
		if not shop.is_empty():
			dealer_routing = dealer_routing and DealerConfig.sells(shop,id)
		var cfg: VehicleConfig = Catalog.make_configuration(v)
		derived_physics = derived_physics and \
			is_equal_approx(cfg.engine_power_kw,float(v.power_kw)) and \
			is_equal_approx(cfg.engine_torque_nm,float(v.torque_nm)) and \
			is_equal_approx(cfg.mass_kg,float(v.mass_kg)) and \
			cfg.gear_ratios.size() == int(v.get("reference_gear_count",0)) and \
			cfg.audio_family == str(v.get("audio_family","")) and \
			cfg.audio_sample_id == id
		if str(v.get("reference_powertrain","")) == "electric":
			derived_physics = derived_physics and cfg.gear_ratios.size() == 1 and \
				cfg.audio_induction == "electric"
		if str(v.get("reference_powertrain","")) == "hybrid":
			derived_physics = derived_physics and cfg.audio_hybrid_assist >= 0.99
		if basis == "fictional_game_value_usd":
			fictional_prices += 1
			price_provenance = price_provenance and \
				Catalog.price_basis_label(v).contains("NO MARKET SALE") and \
				str(v.get("reference_price_note","")).contains("fictional")
		elif basis in ["msrp_usd","msrp_estimate_usd","used_estimate_usd",
				"collector_estimate_usd","converted_launch_estimate_usd"]:
			price_provenance = price_provenance and \
				str(v.get("reference_price_note","")).length() > 30
		else:
			price_provenance = false
		if confidence == "source_checked":
			source_backed += 1
			price_provenance = price_provenance and \
				str(v.get("source_spec_url","")).begins_with("https://")
		else:
			price_provenance = price_provenance and confidence == "representative_trim"
	check("new_models_preserve_old_ids_and_match_png_assets",
		valid and textures.size() == 50, textures.size())
	check("new_models_route_to_existing_dealerships", dealer_routing)
	check("new_models_configure_drivetrain_gearbox_audio_and_upgrades",derived_physics)
	check("market_basis_source_confidence_and_no_sale_prices_are_honest",
		price_provenance and fictional_prices == 4 and source_backed >= 15,
		[fictional_prices,source_backed])
	var mclaren: Dictionary = Catalog.find_by_id("mclaren-570s")
	var atom: Dictionary = Catalog.find_by_id("ariel-atom-500")
	var civic: Dictionary = Catalog.find_by_id("honda-civic-type-r")
	var gemera: Dictionary = Catalog.find_by_id("koenigsegg-gemera")
	var regera: Dictionary = Catalog.find_by_id("koenigsegg-regera")
	var regera_config := Catalog.make_configuration(regera)
	check("regera_hybrid_direct_drive_is_not_ev_reduction",
		regera_config.gear_ratios.size() == 1 and
		is_equal_approx(regera_config.final_drive,2.73))
	check("specific_2026_price_and_factory_spec_fixtures",
		int(mclaren.get("price_usd",0)) == 143000 and \
		float(atom.get("mass_kg",0)) < 600.0 and \
		int(civic.get("price_usd",0)) == 45895 and \
		int(gemera.get("reference_gear_count",0)) == 9 and \
		int(gemera.get("mass_kg",0)) == 2022)
	print("NEW VEHICLE ADDITIONS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
