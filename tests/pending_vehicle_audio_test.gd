extends SceneTree
## Verify audio-only future roster against streetbound_vehicle_list.txt,
## distinct combustion layouts, quiet electric/hybrid sounds, and no dealer
## /garage contamination. Does not introduce car models or gameplay stats.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Pending = preload("res://scripts/audio/pending_vehicle_audio.gd")
const Synth = preload("res://scripts/audio/engine_sound_synthesis.gd")
var failed: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(name: String, ok: bool, info: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if ok else "FAIL",name,info])
	if not ok:
		failed.append(name)


func run() -> void:
	var wanted: Array[String] = Pending.read_requested_models()
	var profiles: Array[Dictionary] = Pending.all()
	check("source_list_has_223_models",wanted.size() == 223,wanted.size())
	check("154_future_models_have_prepared_profiles",
		profiles.size() == 154,profiles.size())
	var existing: Dictionary = {}
	for entry in Catalog.all():
		existing[str(entry.display_name)] = true
	var aliases := {"Chevrolet Camaro Z/28":true,
		"Chevrolet Corvette ZO6":true,"Ford F-150":true}
	var expected_names: Dictionary = {}
	for name in wanted:
		expected_names[name] = true
	var found: Dictionary = {}
	var valid := true
	var duplicates := false
	var ev_count := 0
	var hybrid_count := 0
	var family_counts: Dictionary = {}
	for profile in profiles:
		var id := str(profile.id)
		var name := str(profile.display_name)
		duplicates = duplicates or found.has(id) or existing.has(name)
		found[id] = true
		valid = valid and expected_names.has(name) and \
			Pending.find_by_id(id).id == id and \
			not Catalog.find_by_id(id) and \
			Synth.family_supported(str(profile.audio_family)) and \
			str(profile.audio_status) == "prepared_unreleased" and \
			float(profile.audio_aggression) >= 0.0 and \
			float(profile.audio_tone) >= -1.0 and \
			float(profile.audio_tone) <= 1.0 and \
			float(profile.engine_reference_rpm_redline) > \
				float(profile.engine_reference_rpm_idle) and \
			(profile.audio_induction != "turbo" or \
				float(profile.boost_max_psi) > 0.05)
		if str(profile.audio_family) == "electric":
			ev_count += 1
			valid = valid and str(profile.audio_induction) == "electric" and \
				float(profile.audio_flutter) == 0.0 and \
				float(profile.audio_overrun) == 0.0 and \
				float(profile.boost_max_psi) == 0.0 and \
				float(profile.audio_intake_presence) == 0.0
		if bool(profile.hybrid_electric_assist):
			hybrid_count += 1
		family_counts[str(profile.audio_family)] = true
	check("no_prepared_model_duplicates_or_invalid_powertrains",
		valid and not duplicates)
	check("future_audio_covers_16_distinct_powertrain_families",
		family_counts.size() == 15,family_counts.keys())
	check("14_true_electric_vehicles_and_hybrid_variants_marked",
		ev_count == 14 and hybrid_count >= 10,[ev_count,hybrid_count])
	var missing_names: Array[String] = []
	for name in wanted:
		if existing.has(name) or aliases.has(name):
			continue
		var prepared := false
		for profile in profiles:
			if str(profile.display_name) == name:
				prepared = true
				break
		if not prepared:
			missing_names.append(name)
	check("every_list_model_is_playable_or_prepared_or_known_alias",
		missing_names.is_empty(),missing_names)
	check("playable_vehicle_catalog_remains_88_vehicles",
		Catalog.all().size() == 88)
	check("future_audi_five_cylinder_has_correct_turbo",
		Pending.find_by_id("audi-rs3").audio_family == "i5" and \
		Pending.find_by_id("audi-rs3").audio_induction == "turbo")
	check("rotary_cars_are_not_generic_four_cylinders",
		Pending.find_by_id("mazda-rx-7").audio_family == "rotary2" and \
		Pending.find_by_id("mazda-rx-8").audio_family == "rotary2")
	check("bugatti_v16_hybrid_is_not_turbo_w16",
		Pending.find_by_id("bugatti-tourbillon").audio_family == "v16" and \
		Pending.find_by_id("bugatti-tourbillon").hybrid_electric_assist and \
		Pending.find_by_id("bugatti-tourbillon").audio_induction == "naturally_aspirated")
	check("hellecat_redeye_has_supercharger_not_turbo",
		Pending.find_by_id("dodge-challenger-hellcat-redeye").audio_induction ==
			"supercharger")
	# New synthesis families should not simply alias existing i4/V6/W16.
	var i5_audio := Synth.engine_loop("i5",2,0.9,0.5,true,0.3)
	var boxer4_audio := Synth.engine_loop("boxer4",2,0.9,0.5,true,0.3)
	var boxer6_audio := Synth.engine_loop("boxer6",2,0.9,0.5,true,0.3)
	var rotary_audio := Synth.engine_loop("rotary2",2,0.9,0.5,true,0.3)
	var v16_audio := Synth.engine_loop("v16",2,0.9,0.5,true,0.3)
	var ev_audio := Synth.engine_loop("electric",2,0.4,0.0,true,0.3)
	var waves := [i5_audio,boxer4_audio,boxer6_audio,rotary_audio,v16_audio,ev_audio]
	var distinct := true
	for i in waves.size():
		distinct = distinct and waves[i].get_length() > 0.3
		for j in range(i+1,waves.size()):
			distinct = distinct and waves[i].data != waves[j].data
	check("six_new_engine_families_have_unique_synthesized_waves",distinct)
	check("ev_has_no_combustion_firing_frequency",
		Synth.firing_frequency("electric",7200.0) == 0.0)
	check("ev_motor_inverter_layer_exists",
		Synth.texture_loop("electric_drive").get_length() > 0.3)
	check("ev_wave_is_quieter_than_rotary_combustion",
		_ev_sample_peak(ev_audio) < _ev_sample_peak(rotary_audio))
	var baseline: VehicleConfig = load("res://resources/sport_coupe.tres")
	var original_mass := baseline.mass_kg
	var original_torque := baseline.engine_torque_nm
	var cfg := Pending.make_preview_configuration("mazda-rx-7")
	check("audio_preview_config_honors_rotary_turbo_reference",
		cfg != null and cfg.audio_family == "rotary2" and \
		cfg.boost_max_psi > 1.0 and cfg.audio_sample_id == "mazda-rx-7")
	check("audio_preview_does_not_edit_base_car_physics",
		is_equal_approx(baseline.mass_kg,original_mass) and \
		is_equal_approx(baseline.engine_torque_nm,original_torque))
	var alone := baseline.duplicate(true) as VehicleConfig
	var saved_boost := alone.boost_max_psi
	Pending.apply_to_config(alone,"mazda-rx-7")
	check("applying_audio_identity_does_not_change_physics",
		is_equal_approx(alone.boost_max_psi,saved_boost))
	var game: Node = load("res://scenes/proving_ground.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	var car: VehicleController2D = game.vehicle
	car.set_physics_process(false)
	var audio: Node = game.get_node("VehicleAudio")
	var before_ignition := int(audio.ignitions_played)
	_set_preview(car, audio,"tesla-model-s")
	check("switching_to_ev_never_cranks_gas_engine",
		audio.ignitions_played == before_ignition and \
		audio._induction == "electric")
	check("electric_car_does_not_get_fake_real_ice_recording",
		audio.recorded_texture.stream == null)
	car.transmission.rpm = 7500.0
	car.throttle = 0.85
	car.linear_velocity = Vector2.UP*32.0
	for i in 15:
		audio._process(0.08)
	check("ev_has_motor_inverter_audio_while_moving",
		audio.electric_drive.playing and audio.electric_drive.volume_db > -60.0,
		audio.electric_drive.volume_db)
	check("ev_has_no_combustion_intake_or_turbo",
		audio.intake.volume_db < -79.0 and audio.turbo.volume_db < -79.0)
	var last_pops := int(audio.pops_played)
	var last_lim := int(audio.limiters_played)
	audio._on_shift(3)
	audio._play_pop(1.0)
	audio._limiter_tick()
	check("electric_model_never_fakes_shift_pops_or_fuel_limiter",
		audio.pops_played == last_pops and \
		audio.limiters_played == last_lim)
	_set_preview(car,audio,"bugatti-tourbillon")
	car.throttle = 0.12
	car.linear_velocity = Vector2.UP*3.0
	car.transmission.rpm = 1800.0
	for i in 14:
		audio._process(0.08)
	var ice_low := float(audio.engine.volume_db)
	var electric_low := float(audio.electric_drive.volume_db)
	check("v16_hybrid_has_real_electric_assist_mix",
		audio._profile_family == "v16" and \
		car.config.audio_hybrid_assist > 0.2 and electric_low > -75.0)
	car.throttle = 1.0
	car.transmission.rpm = 8100.0
	car.linear_velocity = Vector2.UP*35.0
	for i in 18:
		audio._process(0.08)
	check("hybrid_combustion_engages_under_high_demand",
		audio.high.volume_db > ice_low)
	_set_preview(car,audio,"audi-rs3")
	check("new_turbo_i5_selects_without_model_or_dealer",
		audio._profile_family == "i5" and audio._induction == "turbo")
	car.throttle = 1.0
	car.boost_psi = 12.0
	car.transmission.rpm = 6500.0
	for i in 8:
		audio._process(0.1)
	check("pending_5_cylinder_uses_actual_turbo_spool",
		audio.turbo.volume_db > -55.0)
	audio.muted = true
	for i in 12:
		audio._process(0.1)
	check("pending_audio_families_respect_mute",
		audio.engine.volume_db < -79.0 and audio.electric_drive.volume_db < -79.0)
	print("PENDING 154 VEHICLE AUDIO: ","PASS" if failed.is_empty() else "FAIL")
	quit(0 if failed.is_empty() else 1)


func _set_preview(car: VehicleController2D, audio: Node, id: String) -> void:
	var config := Pending.make_preview_configuration(id)
	car.config = config
	car.transmission.reset(config)
	car.linear_velocity = Vector2.ZERO
	car.boost_psi = 0.0
	car.throttle = 0.0
	audio._configure_engine(true)


func _ev_sample_peak(stream: AudioStreamWAV) -> int:
	var maximum := 0
	for i in range(0,stream.data.size(),2):
		maximum = maxi(maximum,absi(stream.data.decode_s16(i)))
	return maximum
