extends RefCounted
## Persistent F1 vehicle tune. Only the fields exposed by the HUD can be
## loaded: never deserialize arbitrary Resource objects or overwrite the
## original stock .tres. Runtime physics values stay in SI units.
const SAVE_PATH := "user://streetbound_vehicle_tuning.cfg"
const VERSION := 1

var save_path: String
var slider_specs: Array

func _init(specs: Array, path: String = SAVE_PATH) -> void:
	slider_specs = specs.duplicate(true)
	save_path = path

func load_into(config: VehicleConfig) -> bool:
	var file := ConfigFile.new()
	if file.load(save_path) != OK:
		return false
	if file.get_value("meta", "version", 0) != VERSION:
		return false
	var applied := false
	for entry in slider_specs:
		var key: String = str(entry[0])
		if not file.has_section_key("tuning", key):
			continue
		var raw: Variant = file.get_value("tuning", key)
		if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
			continue
		var value: float = float(raw)
		if is_nan(value) or is_inf(value):
			continue
		var minimum: float = float(entry[2])
		var maximum: float = float(entry[3])
		# ConfigFile serializes floats with reduced decimal precision. At the
		# 10,000 hp slider endpoint, 7456.9987 kW reloads as 7457.0 kW.
		# Treat ONLY small round-trip quantization as valid, and clamp back
		# to the original range. Larger invalid/corrupt edits remain ignored.
		var round_trip_tolerance: float = maxf(0.01,
			maxf(absf(minimum),absf(maximum)) * 0.000001)
		if value < minimum - round_trip_tolerance or \
				value > maximum + round_trip_tolerance:
			continue
		config.set(key, clampf(value, minimum, maximum))
		applied = true
	return applied

func save_from(config: VehicleConfig) -> Error:
	var file := ConfigFile.new()
	file.set_value("meta", "version", VERSION)
	for entry in slider_specs:
		var key: String = str(entry[0])
		file.set_value("tuning", key, float(config.get(key)))
	# Do not change the drivetrain from the simplified F1 stats panel.
	return file.save(save_path)

func clear_profile() -> Error:
	if not FileAccess.file_exists(save_path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
