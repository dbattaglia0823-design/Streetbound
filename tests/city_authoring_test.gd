extends SceneTree
const Snap=preload("res://scripts/dev/building_snap.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func run() -> void:
	check("building_edges_snap_without_overlap",Snap.position(Vector2(11,0),Vector2(10,20),0,[{"p":Vector2.ZERO,"size":Vector2(10,20),"angle":0}]).is_equal_approx(Vector2(10,0)))
	check("rotated_city_blocks_snap_on_rotated_edges",Snap.position(Vector2(0,11),Vector2(10,20),PI/2,[{"p":Vector2.ZERO,"size":Vector2(10,20),"angle":PI/2}]).is_equal_approx(Vector2(0,10)))
	check("distant_buildings_do_not_jump",Snap.position(Vector2(30,0),Vector2(10,20),0,[{"p":Vector2.ZERO,"size":Vector2(10,20),"angle":0}])==Vector2(30,0))
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH","res://.runtime/road-edit-audit/city-recovery.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://.runtime/road-edit-audit/city-recovery.json"))
	var scene=load("res://scenes/world_editor.tscn").instantiate();root.add_child(scene)
	for i in 6:await process_frame
	var e=scene.native_world_editor;var count: int=e.authoring.doc.props.size()
	e._choose_tool("draw_sidewalk")
	e.draft_points.assign([Vector2(3000,3000),Vector2(3300,3000),Vector2(3300,3300)])
	e._update_context_panels()
	check("sidewalk_finish_available_with_road_style_points",not e.finish_button.disabled)
	e._finish_shape()
	var item: Dictionary=e.authoring.prop_at_id(e.source_id)
	check("sidewalk_path_is_editable_and_traffic_independent",not item.is_empty() and item.type=="sidewalk" and item.sidewalkPoints.size()==3 and e.authoring.doc.props.size()==count+1)
	check("sidewalk_uses_concrete_preview",e.gizmos.preview_scenery.prop_list.any(func(p):return p.kind=="sidewalk" and p.sidewalk_points.size()==3))
	check("sidewalk_has_no_wall_collisions",e.gizmos.preview_body.get_children().all(func(c):return str(c.get_meta("draft_prop_id",""))!=str(item.id)))
	var file=FileAccess.open("res://.runtime/road-edit-audit/city-source.json",FileAccess.WRITE);file.store_string(JSON.stringify(e.bridge._python_typed_source(e.authoring.doc)));file.close()
	e._undo();check("entire_sidewalk_path_undoes_together",e.authoring.doc.props.size()==count)
	e._discard_draft();scene.queue_free();await process_frame;await process_frame
	print("CITY AUTHORING: ","PASS" if failures.is_empty() else str(failures));quit(0 if failures.is_empty() else 1)
