extends SceneTree
## Validate ten real CC0 field-derived audio foundations, per-car vs family
## resolution, playback on actual vehicle, pitch/load response and V-mute.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Bank = preload("res://scripts/audio/vehicle_audio_sample_bank.gd")
const FAMILIES := ["i3","i4","i6","v6","v8_cross","v8_flat","v10",
	"v12","w12","w16"]
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, good: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL",label,detail])
	if not good:
		failures.append(label)


func run() -> void:
	var manifest_path := "res://assets/audio/engines/RECORDING_MANIFEST.json"
	check("recording_manifest_is_present",FileAccess.file_exists(manifest_path))
	if not FileAccess.file_exists(manifest_path):
		quit(1)
		return
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	check("recording_manifest_is_valid",doc is Dictionary)
	if not doc is Dictionary:
		quit(1)
		return
	var records: Array = doc.get("recordings",[])
	var coverage: Dictionary = {}
	var licensing_ok := records.size() == 10
	var qc_ok := true
	var playback_ok := true
	var source_links_ok := true
	for row in records:
		var family := str(row.get("family",""))
		coverage[family] = true
		licensing_ok = licensing_ok and row.get("license","") == "CC0-1.0"
		source_links_ok = source_links_ok and \
			str(row.get("source_blob_sha","")).length() == 40 and \
			str(row.get("source_revision","")).length() == 40
		qc_ok = qc_ok and float(row.get("seam_ratio",999.0)) < 3.51 and \
			float(row.get("rms_dbfs",-99.0)) > -28.0 and \
			float(row.get("peak",999)) <= 0.91
		var filename := Bank.path_for(family,"recorded_texture")
		var from_bank: AudioStream = Bank.resolve(
			"vehicle-without-a-specific-recording",family,"recorded_texture")
		playback_ok = playback_ok and ResourceLoader.exists(filename,"AudioStream") and \
			from_bank != null and from_bank is AudioStreamOggVorbis and \
			from_bank.get_length() > 1.0
	check("all_ten_engine_families_have_public_domain_recordings",
		FAMILIES.size() == coverage.size() and
		FAMILIES.all(func(f: String) -> bool: return coverage.has(f)),coverage)
	check("original_recording_hashes_and_cc0_license_preserved",
		licensing_ok and source_links_ok)
	check("ten_recorded_loops_pass_audio_quality_checks",qc_ok)
	check("recorded_family_loops_resolve_as_imported_ogg",playback_ok)

	var scene: Node = load("res://scenes/proving_ground.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var car: VehicleController2D = scene.vehicle
	car.set_physics_process(false)
	var audio: Node = scene.get_node("VehicleAudio")
	check("real_recorded_player_exists_and_plays",
		audio.recorded_texture != null and
		audio.recorded_texture.playing and audio.recorded_texture.stream != null)
	check("recorded_texture_is_loop_enabled",
		(audio.recorded_texture.stream as AudioStreamOggVorbis).loop)
	car.throttle = 0.0
	car.transmission.rpm = car.config.idle_rpm+100.0
	for i in 14:
		audio._process(0.09)
	var idle_level := float(audio.recorded_texture.volume_db)
	var idle_pitch := float(audio.recorded_texture.pitch_scale)
	car.throttle = 1.0
	car.transmission.rpm = car.config.redline_rpm*0.87
	for i in 14:
		audio._process(0.09)
	check("recorded_bed_responds_to_rpm_increase",
		audio.recorded_texture.pitch_scale > idle_pitch+0.3,
		[audio.recorded_texture.pitch_scale,idle_pitch])
	check("recorded_bed_is_audible_under_load",
		audio.recorded_texture.volume_db > idle_level+6.0,
		[audio.recorded_texture.volume_db,idle_level])
	var original_stream: AudioStream = audio.recorded_texture.stream
	for id in ["bmw-m3","ford-mustang","chevrolet-corvette-z06",
		"bugatti-chiron"]:
		var entry := Catalog.find_by_id(id)
		check("vehicle_switch_selects_"+id,Catalog.select(car,entry))
		audio._process(0.1)
		check("authentic_engine_family_bed_"+id,
			audio.recorded_texture.stream != null and
			audio.recorded_texture.playing and
			audio.recorded_texture.stream ==
			Bank.resolve(id,str(entry.audio_family),"recorded_texture"))
	# The Audi RS3 and Chiron artwork were referenced in the catalog before
	# their respective PNGs were actually committed. Missing art should no
	# longer prevent applying the vehicle's true engine audio identity.
	var rs3 := Catalog.find_by_id("audi-rs3")
	check("missing_audi_art_does_not_block_rs3_selection", Catalog.select(car,rs3))
	audio._process(0.1)
	check("rs3_keeps_i5_audio_with_unverified_art",
		audio._profile_family == "i5" and
		(audio.recorded_texture.stream != null or audio.generic_recorded_engine.active))
	check("different_engine_families_do_not_reuse_one_bed",
		audio.recorded_texture.stream != original_stream)
	audio.muted = true
	for i in 15:
		audio._process(0.1)
	check("recorded_engine_bed_respects_existing_mute",
		audio.recorded_texture.volume_db < -79.0 and audio.engine.volume_db < -79.0)
	print("CC0 RECORDED ENGINE SOUNDS: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
