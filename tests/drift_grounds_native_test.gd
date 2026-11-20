extends SceneTree
## Real native map-library and production editor-source checks for Drift Grounds.
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Library=preload("res://scripts/dev/native_map_library.gd")
const PRESET="res://map-editor/maps/drift-grounds.world.json"
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool) -> void:
	print("%s %s"%["PASS" if condition else "FAIL",label])
	if not condition:failures.append(label)

func _run() -> void:
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(PRESET))
	check("drift_starter_source_is_json",parsed is Dictionary)
	if not parsed is Dictionary:
		quit(1)
		return
	var doc: Dictionary=parsed
	var session=Session.new()
	check("native_editor_accepts_drift_source",session._valid_source(doc))
	check("compact_driving_world_dimensions",int(doc.world.width)==820 and int(doc.world.height)==700 and bool(doc.get("customMap",false)))
	check("linked_track_corners_and_skidpad_saved",doc.roads.size()==8 and doc.regions.size()==7)
	check("three_playable_drift_sessions_preserved",doc.races.size()==3)
	check("exactly_one_start_marker",doc.markers.filter(func(p):return str(p.get("type",""))=="player_spawn").size()==1)
	check("solid_skidpad_and_circuit_guardrails",doc.props.filter(func(p):return str(p.get("type",""))=="guardrail").size()==5)
	var folder: String="user://drift-grounds-ci-%d"%Time.get_ticks_usec()
	OS.set_environment("STREETBOUND_MAP_LIBRARY",folder)
	var saved: String=Library.save(doc,"drift-grounds.world.json")
	check("saved_drift_source_to_private_map_library",not saved.is_empty())
	var loaded: Dictionary=Library.load_map(saved)
	check("drift_map_library_roundtrip_keeps_every_drivable_route",loaded.get("roads",[]).size()==8 and loaded.get("props",[]).size()==doc.props.size())
	check("preserves_drift_races_and_walls",loaded.get("races",[]).size()==3 and loaded.get("markers",[]).size()==5)
	check("drift_preset_listed_in_map_selector",Library.list_maps().any(func(m):return str(m.get("file",""))==saved))
	if not saved.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(saved)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	print("DRIFT GROUNDS NATIVE: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
