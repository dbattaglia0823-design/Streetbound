extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func run() -> void:
	var scene: Node=load("res://scenes/world_editor.tscn").instantiate();root.add_child(scene)
	for i in 6:await process_frame
	var e=scene.native_world_editor
	e.source_id="road-0";e.source_anchor=-1;e._refresh_authoring()
	var original: Dictionary=e.authoring.road_at_id("road-0").duplicate(true)
	e._add_point()
	check("existing_road_accepts_inserted_control_point",e.authoring.road_at_id("road-0").points.size()==original.points.size()+1)
	check("remove_is_enabled_after_adding_a_point",not e.remove_point_button.disabled)
	e._remove_point()
	check("existing_road_point_removal_preserves_endpoints",JSON.stringify(e.authoring.road_at_id("road-0").points)==JSON.stringify(original.points))
	e._split_road()
	var second: Dictionary=e.authoring.road_at_id(e.source_id)
	var first: Dictionary=e.authoring.road_at_id("road-0")
	check("existing_two_point_road_can_split",not second.is_empty() and second.id!="road-0")
	check("split_preserves_outer_endpoints_and_shared_join",first.points[0]==original.points[0] and second.points[-1]==original.points[-1] and first.points[-1]==second.points[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/road-edit-audit"))
	var file:=FileAccess.open("res://.runtime/road-edit-audit/source.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(e.bridge._python_typed_source(e.authoring.doc)));file.close()
	e._undo();check("split_is_one_undo_step",e.authoring.doc.roads.size()==scene.ground.data.roads.size())
	e._discard_draft();scene.queue_free();await process_frame;await process_frame
	print("ROAD POINT TOOLS: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
