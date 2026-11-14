extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func run() -> void:
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH","res://.runtime/road-edit-audit/point-recovery.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://.runtime/road-edit-audit/point-recovery.json"))
	var scene: Node=load("res://scenes/world_editor.tscn").instantiate();root.add_child(scene)
	for i in 6:await process_frame
	var e=scene.native_world_editor
	e.source_id="road-0";e.source_anchor=-1;e._refresh_authoring()
	var original: Dictionary=e.authoring.road_at_id("road-0").duplicate(true)
	var count: int=e.authoring.doc.roads.size()
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
	var join:=Vector2(second.points[0].x,second.points[0].y)
	check("split_half_can_move_without_dragging_the_other_half",e.authoring.move_road_point(second.id,0,join+Vector2(0,20),0) and e.authoring.road_at_id("road-0").points[-1]==first.points[-1])
	e.authoring.undo()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/road-edit-audit"))
	var file:=FileAccess.open("res://.runtime/road-edit-audit/source.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(e.bridge._python_typed_source(e.authoring.doc)));file.close()
	e._undo();check("split_is_one_undo_step",e.authoring.doc.roads.size()==count)
	e.source_id="road-0";e.source_anchor=0;e._refresh_authoring();e._split_road()
	var others: Array=[]
	for road in e.authoring.doc.roads:
		if road.id!="road-0":others.append(road.duplicate(true))
	var endpoint:=Vector2(original.points[0].x,original.points[0].y)
	check("connected_junction_endpoint_can_detach",bool(e.authoring.road_at_id("road-0").get("independentEnds",false)) and e.authoring.move_road_point("road-0",0,endpoint+Vector2(0,20),0))
	var unchanged:=true
	for road in others:unchanged=unchanged and JSON.stringify(road)==JSON.stringify(e.authoring.road_at_id(road.id))
	check("detached_junction_does_not_move_neighbor_roads",unchanged)
	check("reconnect_does_not_guess_a_distant_endpoint",not e.authoring.reconnect_endpoint("road-0",0,.1))
	e.authoring.move_road_point("road-0",0,endpoint+Vector2(0,2),0)
	e.source_anchor=0;e._refresh_authoring();e._reconnect_road()
	check("nearby_endpoint_can_snap_and_reconnect",Vector2(e.authoring.road_at_id("road-0").points[0].x,e.authoring.road_at_id("road-0").points[0].y).is_equal_approx(endpoint) and not e.authoring.road_at_id("road-0").get("independentEnds",false))
	e._undo()
	check("reconnect_is_one_undo_step",e.authoring.road_at_id("road-0").get("independentEnds",false) and is_equal_approx(float(e.authoring.road_at_id("road-0").points[0].y),endpoint.y+2))
	var isolated=e.authoring.get_script().new();isolated.doc=e.authoring.doc.duplicate(true)
	var a: Dictionary=original.duplicate(true);a.id="road-0";a.points=[{"x":2500,"y":2500},{"x":2600,"y":2500}]
	var b: Dictionary=a.duplicate(true);b.id="road-1";b.points=[{"x":2508,"y":2501},{"x":2600,"y":2600}]
	var c: Dictionary=a.duplicate(true);c.id="road-2";c.points=[{"x":2492,"y":2501},{"x":2400,"y":2600}]
	isolated.doc.roads=[a,b,c]
	var before:=JSON.stringify(isolated.doc)
	check("ambiguous_reconnect_preserves_geometry",not isolated.reconnect_endpoint("road-0",0) and JSON.stringify(isolated.doc)==before)
	e._discard_draft();scene.queue_free();await process_frame;await process_frame
	print("ROAD POINT TOOLS: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
