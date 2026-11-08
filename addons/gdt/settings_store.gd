extends RefCounted
class_name GDTSettingsStore
## Basic INI-style settings; caller chooses unique save path.

var path: String
var defaults: Dictionary
var values: Dictionary

func _init(config_path: String = "user://gdt_settings.cfg", initial: Dictionary = {}) -> void:
    path = config_path
    defaults = initial.duplicate(true)
    values = defaults.duplicate(true)
    load_settings()

func load_settings() -> void:
    values = defaults.duplicate(true)
    var config := ConfigFile.new()
    if config.load(path) != OK:
        return
    for key in defaults.keys():
        var value: Variant = config.get_value("settings", str(key), defaults[key])
        if typeof(value) == typeof(defaults[key]):
            values[key] = value

func get_setting(key: String) -> Variant:
    return values.get(key, null)

func set_setting(key: String, value: Variant) -> bool:
    if not defaults.has(key) or typeof(value) != typeof(defaults[key]):
        return false
    values[key] = value
    var config := ConfigFile.new()
    for k in values.keys():
        config.set_value("settings", str(k), values[k])
    return config.save(path) == OK
