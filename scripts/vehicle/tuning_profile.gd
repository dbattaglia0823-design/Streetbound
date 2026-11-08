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
		if value < float(entry[2]) - 0.0001 or value > float(entry[3]) + 0.0001:
			continue
		config.set(key, clampf(value, float(entry[2]), float(entry[3])))
		applied = true
	var gear_drive: Variant = file.get_value("tuning", "drivetrain", null)
	if typeof(gear_drive) == TYPE_INT and gear_drive >= 0 and gear_drive <= 2:
		config.drivetrain = gear_drive
		applied = true
	return applied

func save_from(config: VehicleConfig) -> Error:
	var file := ConfigFile.new()
	file.set_value("meta", "version", VERSION)
	for entry in slider_specs:
		var key: String = str(entry[0])
		file.set_value("tuning", key, float(config.get(key)))
	file.set_value("tuning", "drivetrain", int(config.drivetrain))
	return file.save(save_path)

func clear_profile() -> Error:
	if not FileAccess.file_exists(save_path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
