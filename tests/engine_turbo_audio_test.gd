extends SceneTree
## Validate all 88 sound profiles, deterministic seamless synth loops and
## telemetry-coupled engine, turbo, BOV, flutter, shift and tuned exhaust.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Synth = preload("res://scripts/audio/engine_sound_synthesis.gd")
const Parts = preload("res://scripts/vehicle/upgrade_parts.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, good: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL",label,detail])
	if not good:
		failures.append(label)


func run() -> void:
	var entries := Catalog.all()
	var families: Dictionary = {}
	var complete := true
	for entry in entries:
		var family := str(entry.get("audio_family",""))
		var induction := str(entry.get("audio_induction",""))
		families[family] = true
		complete = complete and Synth.family_supported(family) and \
			induction in ["naturally_aspirated","turbo","supercharger"] and \
			float(entry.get("audio_aggression",-1.0)) >= 0.0 and \
			float(entry.get("audio_aggression",100.0)) <= 1.4 and \
			float(entry.get("audio_flutter",-1.0)) >= 0.0 and \
			float(entry.get("audio_flutter",10.0)) <= 1.0
		if induction == "turbo":
			complete = complete and float(entry.get("boost_max_psi",0.0)) > 0.05
	check("all_eighty_eight_cars_have_valid_sound_profile",
		entries.size() == 88 and complete,entries.size())
	check("engine_layout_profiles_are_individually_distinct",
		families.size() == 10,families.keys())
	var v8 := Synth.engine_loop("v8_cross",2,0.9,0.7)
	var v12 := Synth.engine_loop("v12",2,0.9,0.2)
	var i4 := Synth.engine_loop("i4",2,0.7,0.3)
	check("original_exhaust_samples_differ_between_engine_families",
		v8.data != v12.data and v8.data != i4.data and v12.data != i4.data)
	check("engine_loop_samples_are_bounded_and_looped",
		v8.loop_mode == AudioStreamWAV.LOOP_FORWARD and
		v8.mix_rate == Synth.RATE and v8.loop_end == Synth.LOOP_FRAMES and
		v8.data.size() == Synth.LOOP_FRAMES * 2)
	check("loop_synthesis_reuses_cached_waveforms",
		v8 == Synth.engine_loop("v8_cross",2,0.9,0.7))
	check("sample_frequency_tracks_engine_cylinder_firing",
		is_equal_approx(Synth.firing_frequency("v8_cross",3600.0),240.0)
		and is_equal_approx(Synth.firing_frequency("v12",3600.0),360.0))
	for kind in ["intake","turbo","blower","gear"]:
		check("continuous_synth_"+kind,
			Synth.texture_loop(kind).loop_mode == AudioStreamWAV.LOOP_FORWARD)
	for kind in ["bov","flutter","pop","shift","impact"]:
		check("bounded_transient_"+kind,
			Synth.transient(kind).loop_mode == AudioStreamWAV.LOOP_DISABLED and
			Synth.transient(kind).get_length() < 0.65)
	var m3: Dictionary = Catalog.find_by_id("bmw-m3")
	var mustang: Dictionary = Catalog.find_by_id("ford-mustang")
	var f40: Dictionary = Catalog.find_by_id("ferrari-f40")
	var chiron: Dictionary = Catalog.find_by_id("bugatti-chiron")
	var z06: Dictionary = Catalog.find_by_id("chevrolet-corvette-z06")
	check("reference_cars_have_different_engine_character",
		str(m3.audio_family) == "i6" and str(mustang.audio_family) == "v8_cross"
		and str(f40.audio_family) == "v8_flat" and
		str(chiron.audio_family) == "w16" and str(z06.audio_family) == "v8_flat")
	var game: Node = load("res://scenes/proving_ground.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	var car: VehicleController2D = game.vehicle
	car.set_physics_process(false)
	var audio: Node = game.get_node("VehicleAudio")
	check("original_engine_idle_and_tire_loops_remain_live",
		audio.engine.playing and audio.tires.playing and audio.scrub.playing)
	check("engine_sound_has_four_separate_rpm_bands",
		audio.low.playing and audio.mid.playing and audio.high.playing)
	check("intake_and_drivetrain_are_separate_mixers",
		audio.intake.playing and audio.gear_whine.playing)
	var starter_family := str(audio._profile_family)
	check("initial_catalog_audio_matches_selected_vehicle",
		starter_family == str(car.config.audio_family))
	car.transmission.rpm = 3500.0
	car.throttle = 0.18
	audio._process(0.1)
	var low_gain := float(audio.low.volume_db)
	var intake_quiet := float(audio.intake.volume_db)
	car.transmission.rpm = 7100.0
	car.throttle = 1.0
	for i in 8:
		audio._process(0.1)
	check("engine_high_band_responds_to_real_engine_rpm",
		audio.high.volume_db > audio.low.volume_db and
		audio.high.pitch_scale > 0.65,[audio.high.volume_db,audio.low.volume_db])
	check("throttle_adds_real_intake_response",
		audio.intake.volume_db > intake_quiet)
	check("engine_low_band_recedes_at_high_revs",
		audio.low.volume_db < low_gain)
	check("rpm_pitch_follows_current_simulated_engine",
		audio.high.pitch_scale > 0.9)
	check("turbo_absent_on_na_cars",
		audio._induction == "naturally_aspirated" and
		audio.turbo.volume_db < -65.0)
	# Move to a boosted straight-six, without reparenting or changing the
	# original player's AudioStreamPlayer references.
	check("can_select_tuned_turbo_straight_six",
		Catalog.select(car,m3))
	audio._process(0.1)
	check("audio_profile_reloads_on_car_switch",
		audio._profile_family == "i6" and audio._induction == "turbo" and
		audio.engine.playing and audio.high.playing)
	car.transmission.rpm = 6000.0
	car.throttle = 1.0
	car.boost_psi = 12.0
	for i in 8:
		audio._process(0.1)
	var spool_volume := float(audio.turbo.volume_db)
	check("live_turbo_pressure_raises_spool_audio",spool_volume > -45.0,
		spool_volume)
	var before_release := int(audio.flutters_played)+int(audio.releases_played)
	car.transmission.shift_timer = 0.0
	car.transmission.shift(1,car.config)
	check("boosted_gear_shift_dips_engine_and_releases_air",
		audio._shift_dip_time > 0.0 and
		int(audio.flutters_played)+int(audio.releases_played) == before_release + 1)
	audio._release_cooldown = 0.0
	car.transmission.rpm = 5700.0
	car.boost_psi = 13.5
	car.throttle = 1.0
	audio._process(0.1)
	car.throttle = 0.0
	audio._process(0.1)
	check("high_boost_throttle_lift_creates_blowoff_or_flutter",
		int(audio.flutters_played)+int(audio.releases_played) >= before_release + 2)
	check("stronger_turbo_tunes_can_flutter",
		audio.flutters_played >= 1)
	car.boost_psi = 0.0
	for i in 9:
		audio._process(0.1)
	check("zero_boost_silences_turbo_spool",
		audio.turbo.volume_db < spool_volume)
	var no_more := int(audio.flutters_played)+int(audio.releases_played)
	audio._release_cooldown = 0.0
	car.throttle = 0.9
	audio._process(0.1)
	car.throttle = 0.0
	audio._process(0.1)
	check("zero_boost_never_triggers_false_blowoff",
		int(audio.flutters_played)+int(audio.releases_played) == no_more)
	check("mustang_v8_profile_installs",Catalog.select(car,mustang))
	audio._process(0.1)
	car.transmission.rpm = 6900.0
	car.throttle = 0.9
	audio._process(0.1)
	car.throttle = 0.0
	audio._process(0.1)
	check("tuned_v8_overrun_can_create_exhaust_pop",
		audio.pops_played > 0)
	check("naturally_aspirated_v8_has_no_compressor_bov",
		audio._induction == "naturally_aspirated")
	check("camaro_zl1_uses_blower_instead_of_turbo",
		Catalog.select(car,Catalog.find_by_id("chevrolet-camaro-zl1")))
	audio._process(0.1)
	check("supercharger_only_generates_blower_whine",
		audio._induction == "supercharger" and audio.turbo.playing)
	var boosted_sound: VehicleConfig = Catalog.make_configuration(m3)
	var upgraded: VehicleConfig = Catalog.make_configuration(m3)
	var exhaust: Dictionary = Parts.get_part("exhaust-street-rare")
	var parts: Array[Dictionary] = [exhaust]
	Parts.apply_to_config(upgraded,parts)
	check("exhaust_upgrade_changes_sound_and_performance",
		upgraded.audio_aggression > boosted_sound.audio_aggression and
		upgraded.audio_exhaust_roughness > boosted_sound.audio_exhaust_roughness and
		upgraded.engine_power_kw > boosted_sound.engine_power_kw)
	check("exhaust_upgrade_does_not_add_fake_turbo",
		upgraded.audio_induction == boosted_sound.audio_induction)
	# Returning to stock should restore exact original profile values.
	check("fresh_car_configuration_restores_original_sound",
		is_equal_approx(Catalog.make_configuration(m3).audio_aggression,
			boosted_sound.audio_aggression))
	# Mute must silence all loops and also reject new transients.
	audio.muted = true
	for i in 10:
		audio._process(0.1)
	var before_muted_events := int(audio.flutters_played)+int(audio.releases_played)
	check("mute_fades_every_engine_and_induction_loop",
		audio.engine.volume_db < -79.0 and audio.turbo.volume_db < -79.0 and
		audio.tires.volume_db <= -79.0 and audio.scrub.volume_db <= -79.0)
	audio._release_cooldown = 0.0
	audio._release_pressure(12.0,false)
	check("mute_blocks_new_blowoff_and_flutter_events",
		int(audio.flutters_played)+int(audio.releases_played) == before_muted_events)
	print("ENGINE / TURBO AUDIO PROFILES: ",
		"PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
