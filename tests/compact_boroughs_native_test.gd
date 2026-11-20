extends SceneTree
## Check the shipped compact preset using the real native map-source validator.
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Library=preload("res://scripts/dev/native_map_library.gd")
const PRESET="res://map-editor/maps/compact-boroughs.world.json"
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)

func _run() -> void:
	var parsed: Variant=JSON.parse_string(FileAccess.get_file_as_string(PRESET))
	check("bundled_compact_map_reads_as_dictionary",parsed is Dictionary)
	if not parsed is Dictionary:
		quit(1)
		return
	var doc: Dictionary=parsed
	var session=Session.new()
	check("real_native_map_validator_accepts_preset",session._valid_source(doc))
	check("compact_preset_is_user_editable",doc.get("customMap",false) and
		int(doc.world.width)==960 and int(doc.world.height)==720)
	check("all_three_areas_have_drivable_roads",doc.roads.size()==9 and
		doc.props.size()>300 and doc.regions.size()>=4)
	check("user_spawn_is_on_main_market_road",doc.markers.any(
		func(m):return str(m.get("type",""))=="player_spawn" and
			is_equal_approx(float(m.get("y",0)),250.0)))
	check("valid_editor_events",doc.races.size()==2)
	check("solid_waterfront_guardrail_survives",doc.props.any(
		func(p):return str(p.get("type",""))=="guardrail" and
			is_equal_approx(float(p.get("guardrailWidth",0)),.65)))
	var folder: String="user://compact-map-ci-%d"%Time.get_ticks_usec()
	OS.set_environment("STREETBOUND_MAP_LIBRARY",folder)
	var saved: String=Library.save(doc,"compact-boroughs.world.json")
	check("bundled_source_copies_to_writable_library",not saved.is_empty())
	var reopened: Dictionary=Library.load_map(saved)
	check("writable_native_source_preserves_road_and_scenery",
		reopened.get("roads",[]).size()==9 and
		reopened.get("props",[]).size()==doc.props.size() and
		str(reopened.get("name",""))=="Compact Boroughs")
	check("native_library_lists_copied_preset",Library.list_maps().any(
		func(m):return str(m.get("file",""))=="compact-boroughs.world.json"))
	if not saved.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(saved)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(folder))
	print("COMPACT BOROUGHS NATIVE: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
