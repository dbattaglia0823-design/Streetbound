extends SceneTree
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Library=preload("res://scripts/dev/native_map_library.gd")
const Traffic=preload("res://scripts/dev/native_traffic_preview.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func run() -> void:
	# This test also runs on a fresh, independent CI shard. Never depend on
	# an earlier road-edit test creating the fixture directory.
	var fixture_dir := ProjectSettings.globalize_path("res://.runtime/road-edit-audit")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(fixture_dir)
	check("fixture_output_directory_available",mkdir_error==OK or DirAccess.dir_exists_absolute(fixture_dir))
	if not failures.is_empty():quit(1);return
	var s=Session.new();s.doc=Library.create("Junction test",2400,1800,"grass")
	var main_points: Array[Vector2]=[Vector2(300,800),Vector2(1800,800)]
	var branch_points: Array[Vector2]=[Vector2(1000,300),Vector2(1000,790)]
	var main_id: String=s.add_road_path(main_points)
	var branch_id: String=s.add_road_path(branch_points)
	check("endpoint_can_connect_to_middle_of_road",s.reconnect_endpoint(branch_id,1,12))
	check("target_road_receives_exact_shared_control_point",s.road_at_id(main_id).points.size()==3 and s.road_at_id(branch_id).points[-1]==s.road_at_id(main_id).points[1])
	var baked: Dictionary=Traffic.build_data({"roads":[],"road_width_scale":1},s.doc.roads,[])
	check("connected_roads_form_real_t_junction",baked.junctions.any(func(j):return j.approaches.size()==3))
	s.undo();check("road_connection_undo_is_atomic",s.road_at_id(main_id).points.size()==2 and is_equal_approx(float(s.road_at_id(branch_id).points[-1].y),790))
	var draw_points: Array[Vector2]=[Vector2(1300,300),Vector2(1300,800)]
	s.add_road_path(draw_points);check("drawing_onto_existing_road_connects_automatically",s.road_at_id(main_id).points.size()==3)
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH","res://.runtime/road-edit-audit/integrity-recovery.json")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://.runtime/road-edit-audit/integrity-recovery.json"))
	var scene=load("res://scenes/world_editor.tscn").instantiate();root.add_child(scene)
	for i in 6:await process_frame
	var e=scene.native_world_editor;e.building_snap_enabled=false
	var production=Session.new();production.load_source();production.reconcile_runtime(scene.ground.data)
	var target: Dictionary=production.road_at_id("road-0")
	var center: Vector2=(Vector2(target.points[0].x,target.points[0].y)+Vector2(target.points[-1].x,target.points[-1].y))*.5
	var branch: Array[Vector2]=[center+Vector2(150,0),center]
	production.add_road_path(branch)
	var source=FileAccess.open("res://.runtime/road-edit-audit/junction-source.json",FileAccess.WRITE)
	check("junction_fixture_file_opened",source!=null)
	if source==null:quit(1);return
	source.store_string(JSON.stringify(e.bridge._python_typed_source(production.doc)))
	check("junction_fixture_written",source.get_error()==OK)
	source.close()
	var original: Dictionary={};var original_index:=-1
	for i in scene.ground.data.props.size():
		var p: Dictionary=scene.ground.data.props[i]
		if p.kind=="house" and not p.has("authoring_id") and not p.has("poi") and p.p[0]>300 and p.p[0]<5000:original=p.duplicate(true);original_index=i;break
	var id: String=e.authoring.adopt_runtime_prop(original)
	check("test_asset_is_adopted",not id.is_empty())
	var prop: Dictionary=e.authoring.prop_at_id(id)
	# Reproduce a saved replacement whose appearance retains its baked ID.
	prop.sourceAppearance["authoring_id"]=id
	e.source_id=id;e._refresh_authoring()
	var origin:=Vector2(original.p[0],original.p[1])*20
	e.pending_drag={"kind":"prop","id":id,"from":origin,"grab":origin,"to":origin}
	e._refresh_authoring()
	var rebuilds: int=e.gizmos.scenery_rebuild_count
	var started:=Time.get_ticks_usec()
	for i in 200:e._update_drag_preview(origin+Vector2(1600+i,0))
	print("200 DRAG UPDATES MS ",(Time.get_ticks_usec()-started)/1000.0)
	check("dragging_does_not_rebuild_all_scenery",e.gizmos.scenery_rebuild_count==rebuilds)
	check("preview_is_not_hidden_by_baked_identity",e.gizmos.preview_scenery.ignore_editor_mask and e.gizmos.preview_indices.has(id))
	e._finish_source_drag(origin+Vector2(1800,0))
	var hit: Dictionary=e._nearest_prop(origin)
	check("empty_former_location_cannot_select_moved_baked_asset",hit.is_empty() or int(hit.index)!=original_index)
	var moved: Dictionary=e._pick_source_prop(origin+Vector2(1800,0))
	check("moved_asset_is_selectable_at_its_visible_location",str(moved.get("id",""))==id)
	check("moving_keeps_live_asset_rendered",e.gizmos.preview_indices.has(id) and e.gizmos.preview_scenery.prop_list[int(e.gizmos.preview_indices[id])].p[0]>original.p[0]+80)
	check("same_original_resolves_existing_editor_identity",e._ensure_editable_runtime_prop(original)==id)
	if DisplayServer.get_name()!="headless":
		e.editor_camera.global_position=origin+Vector2(900,0);e.editor_camera.zoom=Vector2.ONE*.35;e._position_camera_canvas();e._update_view(true)
		for i in 12:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.runtime/road-edit-audit/integrity-visual.png")
	e._undo();e._redo();check("undo_redo_preserve_live_asset",e.gizmos.preview_indices.has(id))
	var before_revision: int=e.authoring.edit_revision
	var before_history: int=e.authoring.history.size()
	var refreshes: int=e.full_refresh_count
	var road: Dictionary=e.authoring.road_at_id("road-0")
	var start:=Vector2(float(road.points[0].x),float(road.points[0].y))*20.0
	e.source_id="road-0";e.source_anchor=0
	e.pending_drag={"kind":"road","id":"road-0","index":0,"from":start,"grab":start,"to":start+Vector2(40,0)}
	e._refresh_drag_geometry()
	check("road_preview_does_not_commit_or_refresh_inspector",e.authoring.edit_revision==before_revision and e.authoring.history.size()==before_history and e.full_refresh_count==refreshes and e.drag_preview_count>0)
	e.pending_drag.clear();e._refresh_authoring()
	var terrain_preview=preload("res://scripts/dev/custom_map_terrain.gd").new()
	root.add_child(terrain_preview)
	var custom: Dictionary=Library.create("Terrain performance",1200,1000,"grass")
	terrain_preview.update_map(custom)
	var terrain_builds: int=terrain_preview.rebuild_count
	custom.props.append({"id":"prop-preview-only"})
	terrain_preview.update_map(custom)
	check("scenery_change_does_not_rebuild_terrain",terrain_preview.rebuild_count==terrain_builds)
	terrain_preview.queue_free()
	e._discard_draft();scene.queue_free();await process_frame;await process_frame
	print("EDITOR INTEGRITY: ","PASS" if failures.is_empty() else str(failures));quit(0 if failures.is_empty() else 1)
