extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/basic-editor-test"))
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH","res://.runtime/basic-editor-test/recovery.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://.runtime/basic-editor-test/recovery.json"))
	var scene=load("res://scenes/world_editor.tscn").instantiate();root.add_child(scene)
	for i in 6:await process_frame
	var e=scene.native_world_editor
	var original: Dictionary={}
	for prop in scene.ground.data.props:
		if prop.kind=="house" and not prop.has("authoring_id") and not prop.has("poi"):original=prop.duplicate(true);break
	e.source_id=e.authoring.adopt_runtime_prop(original);e._refresh_authoring()
	var id: String=e.source_id;var origin:=Vector2(original.p[0],original.p[1])*20
	if DisplayServer.get_name()!="headless":
		e.editor_camera.global_position=origin;e.editor_camera.zoom=Vector2.ONE*.24;e._position_camera_canvas();e._update_view(true)
		for i in 20:await process_frame
	e.pending_drag={"kind":"prop","id":id,"from":origin,"grab":origin,"to":origin};e._refresh_authoring()
	for i in 3:await process_frame
	var atlas_refreshes: int=e.overview_renderer.refresh_count
	var redraws: int=e.gizmos.static_redraw_count;var frame_times: Array=[]
	for i in 100:
		var start:=Time.get_ticks_usec();e._update_drag_preview(origin+Vector2(i,0))
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw;frame_times.append((Time.get_ticks_usec()-start)/1000.0);await process_frame
	if not frame_times.is_empty():
		frame_times.sort();print("RENDERED HOUSE DRAG ms median=",frame_times[50]," p95=",frame_times[95])
		check("drag_leaves_static_road_and_debug_canvas_cached",e.gizmos.static_redraw_count==redraws)
	check("drag_draws_one_house_on_separate_canvas",e.gizmos.drag_scenery.prop_list.size()==1 and e.gizmos.preview_scenery.suppressed_preview_id==id and e.gizmos.drag_scenery.prop_list[0].p[0]>original.p[0])
	check("drag_does_not_refresh_entire_map_texture",e.overview_renderer.refresh_count==atlas_refreshes)
	e._finish_source_drag(origin+Vector2(100,0))
	check("release_restores_cached_house_batch",e.gizmos.drag_scenery.prop_list.is_empty() and e.gizmos.preview_scenery.suppressed_preview_id.is_empty())
	var house: Dictionary=e.authoring.prop_at_id(id)
	check("basic_house_rotation_and_size_change",e.authoring.edit_entity(id,{"rotation":float(house.rotation)+15,"scaleX":.9,"scaleY":1.1},Vector2(house.x,house.y)))
	var road: Dictionary=e.authoring.road_at_id("road-0")
	check("basic_road_reshape_and_width_change",e.authoring.move_road_point("road-0",road.points.size()-1,Vector2(road.points[-1].x+8,road.points[-1].y),0) and e.authoring.set_road_settings("road-0",{"width":12.0}))
	check("manual_house_can_be_placed_for_overlap_warning",not e.authoring.add_prop("house",Vector2(road.points[0].x,road.points[0].y)).is_empty())
	var points: Array[Vector2]=[Vector2(1000,4000),Vector2(1200,4100)]
	check("separate_road_is_an_editable_object",not e.authoring.add_road_path(points).is_empty())
	var file=FileAccess.open("res://.runtime/basic-editor-test/source.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(e.bridge._python_typed_source(e.authoring.doc)));file.close()
	e._discard_draft();scene.queue_free();await process_frame;await process_frame
	print("BASIC EDITOR CHANGES: ","PASS" if failures.is_empty() else str(failures));quit(0 if failures.is_empty() else 1)
