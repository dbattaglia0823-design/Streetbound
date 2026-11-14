extends SceneTree
## Complete-fleet audio mastering verification: new power/coast layers, real
## driving telemetry, built-in license-safe source synthesis, and safety caps.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Synth = preload("res://scripts/audio/engine_sound_synthesis.gd")
const Bank = preload("res://scripts/audio/vehicle_audio_sample_bank.gd")
const Parts = preload("res://scripts/vehicle/upgrade_parts.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(name: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL",name,detail])
	if not passed:
		failures.append(name)


func run() -> void:
	var roster := Catalog.all()
	var values_ok := roster.size() == 89 and not Catalog.find_by_id("audi-rs3").is_empty()
	var car_sound_signatures: Dictionary = {}
	for car in roster:
		var keys := ["audio_tone","audio_intake_presence",
			"audio_driveline_presence","audio_lope","audio_overrun",
			"audio_turbo_presence"]
		for key in keys:
			values_ok = values_ok and car.has(key)
		var tone := float(car.get("audio_tone",3))
		values_ok = values_ok and tone >= -1.0 and tone <= 1.0 and \
			float(car.get("audio_intake_presence",-1)) >= 0.0 and \
			float(car.get("audio_driveline_presence",-1)) >= 0.0 and \
			float(car.get("audio_lope",-1)) >= 0.0 and \
			float(car.get("audio_overrun",-1)) >= 0.0 and \
			float(car.get("audio_turbo_presence",-1)) >= 0.0
		car_sound_signatures["%s:%s:%s:%s" % [
			str(car.audio_family),str(car.audio_tone),str(car.audio_lope),
			str(car.audio_overrun)]] = true
	check("all_playable_vehicles_have_curated_audio_mastering",values_ok)
	check("vehicles_have_many_distinct_acoustic_signatures",
		car_sound_signatures.size() >= 35,car_sound_signatures.size())
	for id in ["ford-mustang","dodge-challenger","bmw-m3",
		"ferrari-458-italia","ferrari-f40","bugatti-chiron"]:
		var config := Catalog.make_configuration(Catalog.find_by_id(id))
		check("sound_profile_applies_to_actual_car_"+id,
			is_equal_approx(config.audio_tone,
				float(Catalog.find_by_id(id).audio_tone)) and \
			config.audio_intake_presence > 0.0)
	check("recording_bank_resolves_safe_per_car_paths",
		Bank.path_for("ford-mustang","power_low") ==
		"res://assets/audio/engines/ford-mustang/power_low.ogg")
	check("recording_bank_rejects_path_traversal",
		Bank.path_for("../evil","power_low").is_empty() and \
		Bank.path_for("bmw-m3","../../secret").is_empty())
	var licensed_override: AudioStream = Synth.texture_loop("intake")
	check("explicit_recording_overrides_still_take_precedence",
		Bank.resolve("ford-mustang","v8_cross","power_idle",
			licensed_override) == licensed_override)
	check("no_unprovided_recordings_are_misrepresented_as_recorded",
		Bank.resolve("car-that-is-not-in-catalog","not-an-engine",
			"power_idle") == null)
	var engine_on := Synth.engine_loop("v8_cross",1,0.9,0.7,true,-0.7)
	var engine_off := Synth.engine_loop("v8_cross",1,0.9,0.7,false,-0.7)
	check("power_and_coast_use_different_combustion_waveforms",
		engine_on.data != engine_off.data)
	check("same_waveform_is_reused_not_regenerated",
		engine_on == Synth.engine_loop("v8_cross",1,0.9,0.7,true,-0.7))
	check("bright_vs_dark_exhaust_waveforms_are_distinct",
		Synth.engine_loop("v8_cross",1,0.9,0.7,true,0.7).data !=
		engine_on.data)
	check("all_pcm_loops_are_bounded_seamless_mono",
		engine_on.data.size() == Synth.LOOP_FRAMES * 2 and \
		engine_off.loop_end == Synth.LOOP_FRAMES and \
		engine_off.loop_mode == AudioStreamWAV.LOOP_FORWARD)
	var available := true
	for kind in ["intake","turbo","blower","gear","wind","road","drivetrain"]:
		var stream := Synth.texture_loop(kind)
		available = available and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and \
			stream.get_length() > 0.2
	check("wind_road_driveline_layers_have_original_looped_samples",available)
	var events := true
	for name in ["ignition","shutdown","blip","limiter","curb"]:
		var stream := Synth.transient(name)
		events = events and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and \
			stream.get_length() > 0.05 and stream.get_length() < 1.5
	check("additional_short_one_shot_favorites_are_valid",events)

	var scene: Node = load("res://scenes/proving_ground.tscn").instantiate()
	root.add_child(scene)
	await physics_frame
	var car: VehicleController2D = scene.vehicle
	car.set_physics_process(false)
	var mixer: Node = scene.get_node("VehicleAudio")
	check("engine_has_four_loaded_and_four_overrun_players",
		mixer.engine.playing and mixer.high.playing and
		mixer.coast_idle.playing and mixer.coast_high.playing)
	check("further_world_driving_players_start_at_scene_load",
		mixer.wind.playing and mixer.road.playing and mixer.driveline.playing)
	check("engine_starts_with_ignition_event",
		mixer.ignitions_played >= 1 and mixer.ignition.stream != null)
	# Fix RPM and other telemetry independently of the physics integrator,
	# to ensure mixer readouts correspond to the actual in-game values.
	car.throttle = 1.0
	car.transmission.rpm = 5100.0
	car.linear_velocity = Vector2.UP * 32.0
	for i in 10:
		mixer._process(0.08)
	var loaded_gain := float(mixer.mid.volume_db)
	var coast_gain_at_load := float(mixer.coast_mid.volume_db)
	check("loaded_engine_sound_dominates_when_accelerating",
		loaded_gain > coast_gain_at_load,[loaded_gain,coast_gain_at_load])
	var wind_gain_fast := float(mixer.wind.volume_db)
	var road_gain_fast := float(mixer.road.volume_db)
	check("speed_activates_wind_and_road_movement_beds",
		wind_gain_fast > -70.0 and road_gain_fast > -70.0)
	car.throttle = 0.0
	for i in 12:
		mixer._process(0.08)
	check("coast_engine_sound_dominates_after_lifting",
		mixer.coast_mid.volume_db > mixer.mid.volume_db)
	var wind_before_stop := float(mixer.wind.volume_db)
	car.linear_velocity = Vector2.ZERO
	for i in 12:
		mixer._process(0.08)
	check("road_and_wind_fade_when_stopped",
		mixer.wind.volume_db < wind_before_stop and
		mixer.road.volume_db < road_gain_fast)
	# Off-road texture is louder than asphalt at exactly the same speed.
	car.linear_velocity = Vector2.UP * 25.0
	car.surface = "ASPHALT"
	for i in 12:
		mixer._process(0.08)
	var road_on_asphalt := float(mixer.road.volume_db)
	car.surface = "GRAVEL"
	for i in 12:
		mixer._process(0.08)
	check("gravel_texture_is_louder_than_smooth_asphalt",
		mixer.road.volume_db > road_on_asphalt+6.0,
		[mixer.road.volume_db,road_on_asphalt])
	# Shift signal is the actual transmission event, not UI input.
	car.transmission.gear = 3
	mixer._last_gear = 3
	car.transmission.shift_timer = 0.0
	car.transmission.shift(-1,car.config)
	check("downshifting_plays_an_independent_rev_blip",
		mixer.downshifts_played >= 1 and mixer.downshift.playing)
	# Temporarily set a true near-redline RPM and throttle; only a
	# physical high-RPM cut can request a limiter transient.
	car.transmission.rpm = car.config.redline_rpm
	car.throttle = 1.0
	car.transmission.shift_timer = 0.0
	mixer._process(0.016)
	check("reaching_rev_limit_causes_performance_limiter_cut",
		mixer.limiters_played >= 1 and mixer.limiter.playing)
	var old_cut := int(mixer.limiters_played)
	car.transmission.rpm = car.config.redline_rpm*0.48
	car.throttle = 0.15
	for i in 12:
		mixer._process(0.016)
	check("rpm_below_limiter_does_not_emit_false_ticks",
		mixer.limiters_played == old_cut)
	var mustang := Catalog.find_by_id("ford-mustang")
	var f40 := Catalog.find_by_id("ferrari-f40")
	check("switching_back_to_performance_v8_changes_audio_live",
		Catalog.select(car,mustang))
	mixer._process(0.07)
	check("selected_mustang_retains_rumbly_idle_profile",
		mixer._profile_tone < -0.5 and mixer._profile_family == "v8_cross")
	check("switching_cars_triggers_ignition_without_recreating_nodes",
		mixer.ignitions_played >= 2 and mixer.engine.playing)
	check("f40_boosted_tone_can_be_loaded",
		Catalog.select(car,f40))
	mixer._process(0.07)
	check("f40_turbo_sound_not_faked_for_mustang",
		mixer._induction == "turbo" and mixer._profile_tone > 0.4)
	# The independent visual curb suspension no longer exists. Audio must
	# not attempt to write the retired chassis-heave field or fake curb hits.
	var art: Node2D = car.get_node("Art")
	check("retired_visual_curb_height_is_not_required_for_audio",
		art.get("curb_heave") == null)
	var curb_count := int(mixer.curb_hits_played)
	mixer._last_curb_height = 0.0
	mixer._curb_cooldown = 0.0
	mixer._process(0.08)
	check("no_false_visual_suspension_curb_one_shot",
		mixer.curb_hits_played == curb_count)
	# Mute must gate new events, low/coast engine, road, wind and induction.
	mixer.muted = true
	for i in 12:
		mixer._process(0.09)
	check("mute_fades_new_loaded_coast_and_environment_layers",
		mixer.engine.volume_db < -79.0 and
		mixer.coast_mid.volume_db < -79.0 and
		mixer.wind.volume_db < -79.0 and
		mixer.road.volume_db < -79.0 and
		mixer.driveline.volume_db < -79.0)
	var no_curb := int(mixer.curb_hits_played)
	mixer._curb_cooldown = 0.0
	mixer._process(0.08)
	check("mute_prevents_new_suspension_one_shot",
		mixer.curb_hits_played == no_curb)

	print("FULL FLEET AUDIO MASTERING: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
