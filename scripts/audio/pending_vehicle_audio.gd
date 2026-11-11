class_name PendingVehicleAudio
extends RefCounted
## Prepares future car audio WITHOUT adding unbuilt cars to the garage, dealer,
## race opponents, or physics roster. Names and IDs are sourced directly from
## streetbound_vehicle_list.txt. Vehicle models and trims may be ambiguous.
const PATH := "res://data/pending_vehicle_audio_profiles.json"
const SOURCE_LIST := "res://streetbound_vehicle_list.txt"
const Synth = preload("res://scripts/audio/engine_sound_synthesis.gd")
static var _profiles: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func all() -> Array[Dictionary]:
	if not _profiles.is_empty():
		return _profiles
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		push_error("Pending vehicle audio catalog missing")
		return _profiles
	for record in parsed.get("profiles",[]):
		if not record is Dictionary:
			continue
		var id := str(record.get("id",""))
		if id.is_empty() or _by_id.has(id):
			continue
		if not Synth.family_supported(str(record.get("audio_family",""))):
			continue
		_profiles.append(record)
		_by_id[id] = record
	return _profiles


static func find_by_id(id: String) -> Dictionary:
	all()
	return _by_id.get(id,{})


static func is_prepared(id: String) -> bool:
	return not find_by_id(id).is_empty()


static func apply_to_config(config: VehicleConfig, id: String,
		with_preview_rpm := false) -> bool:
	# Never change mass, torque, tires, gear ratios or drivetrain here.
	# with_preview_rpm is for auditioning an UNRELEASED audio identity.
	var record := find_by_id(id)
	if record.is_empty() or config == null:
		return false
	config.audio_sample_id = id
	config.audio_family = str(record.audio_family)
	config.audio_induction = str(record.audio_induction)
	config.audio_aggression = clampf(float(record.audio_aggression),0.0,1.4)
	config.audio_flutter = clampf(float(record.audio_flutter),0.0,1.0)
	config.audio_exhaust_roughness = clampf(
		float(record.audio_exhaust_roughness),0.0,1.0)
	config.audio_tone = clampf(float(record.audio_tone),-1.0,1.0)
	config.audio_intake_presence = clampf(
		float(record.audio_intake_presence),0.0,1.5)
	config.audio_driveline_presence = clampf(
		float(record.audio_driveline_presence),0.0,1.5)
	config.audio_lope = clampf(float(record.audio_lope),0.0,1.0)
	config.audio_overrun = clampf(float(record.audio_overrun),0.0,1.0)
	config.audio_turbo_presence = clampf(
		float(record.audio_turbo_presence),0.0,1.5)
	config.audio_hybrid_assist = 1.0 if bool(
		record.get("hybrid_electric_assist",false)) else 0.0
	if with_preview_rpm:
		config.idle_rpm = maxf(0.0,float(record.engine_reference_rpm_idle))
		config.redline_rpm = maxf(config.idle_rpm+100.0,
			float(record.engine_reference_rpm_redline))
		config.boost_max_psi = maxf(0.0,float(record.boost_max_psi))
	return true


static func make_preview_configuration(id: String) -> VehicleConfig:
	if not is_prepared(id):
		return null
	var baseline: VehicleConfig = load("res://resources/sport_coupe.tres")
	var config := baseline.duplicate(true) as VehicleConfig
	if apply_to_config(config,id,true):
		return config
	return null


static func read_requested_models() -> Array[String]:
	# Each indented list row is one requested model. Ignore the prose/style
	# instructions at the start. Preserve Unicode model names and spelling.
	var names: Array[String] = []
	var make := ""
	var started := false
	var lines: PackedStringArray = FileAccess.get_file_as_string(
		SOURCE_LIST).split("\n")
	for raw in lines:
		var line := raw.strip_edges()
		if line == "Acura":
			started = true
		if not started or line.is_empty():
			continue
		if raw.begins_with("  "):
			if not make.is_empty():
				names.append(make+" "+line)
		else:
			make = line
	return names
