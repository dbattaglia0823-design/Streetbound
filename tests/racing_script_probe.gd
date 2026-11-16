extends SceneTree
## Cold-load every new race script individually, to surface the real script
## errors instead of only an opaque failure from main.gd's preload.
func _initialize() -> void:
	for path in [
		"res://scripts/world/race_traffic_overtaking.gd",
		"res://scripts/world/race_ai_driver.gd",
		"res://scripts/world/traffic_flow.gd",
		"res://scripts/world/larkspur_street_sprint.gd",
		"res://scripts/world/ashford_drag_race.gd",
		"res://scripts/world/ashford_ai_race.gd",
		"res://scripts/world/ashford_circuit_practice.gd",
		"res://scripts/world/race_start_grid.gd",
		"res://scripts/world/authored_race_definition.gd",
		"res://scripts/world/authored_race.gd",
		"res://scripts/dev/native_race_editor.gd",
		"res://scripts/dev/native_map_edit_session.gd",
		"res://scripts/dev/native_world_editor_gizmos.gd",
		"res://scripts/dev/native_world_editor.gd",
		"res://scripts/dev/custom_map_test_drive.gd",
		"res://tests/racing_traffic_overtaking_test.gd",
		"res://scripts/main.gd"
	]:
		var script: Variant=load(path)
		print("RACING LOAD PROBE ", path, " = ", script != null, " can instantiate ", script.can_instantiate() if script is Script else false)
	quit()
