extends SceneTree
## Cold-load every new race script individually, to surface the real script
## errors instead of only an opaque failure from main.gd's preload.
func _initialize() -> void:
	for path in [
		"res://scripts/world/race_traffic_overtaking.gd",
		"res://scripts/world/race_ai_driver.gd",
		"res://scripts/world/traffic_flow.gd",
		"res://scripts/world/larkspur_street_sprint.gd",
		"res://scripts/main.gd"
	]:
		print("RACING LOAD PROBE ", path, " = ", load(path) != null)
	quit()
