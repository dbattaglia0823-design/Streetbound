extends SceneTree
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Roads=preload("res://scripts/world/coast_roads.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool,detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if ok else "FAIL",label,detail])
	if not ok:failures.append(label)
func pointer(screen: Vector2,pressed: bool) -> InputEventMouseButton:
	var event:=InputEventMouseButton.new()
	event.position=screen;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
	return event
func wait_for_traffic(editor: Node) -> bool:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		editor._process(.016)
		if editor.traffic_preview.is_current():return true
		await process_frame
	return false
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/native-editor-audit"))
	var scene: Node=load("res://scenes/world_editor.tscn").instantiate()
	root.add_child(scene)
	var editor=scene.native_world_editor
	editor.recovery_path="res://.runtime/native-editor-audit/recovery-test.json"
	if FileAccess.file_exists(editor.recovery_path):DirAccess.remove_absolute(ProjectSettings.globalize_path(editor.recovery_path))
	for i in 6:await process_frame
	check("actual_standalone_editor_opens",editor.active and editor.source_ready)
	var session=editor.authoring
	var baked_before:=JSON.stringify(scene.ground.data.roads)
	var curve: Array=scene.ground.data.roads[6].points
	var curve_at:=Vector2(curve[curve.size()/2][0],curve[curve.size()/2][1])*20
	check("curved_road_selection_uses_rendered_path",editor._pick_source_road(curve_at).get("id","")=="road-6")
	var road: Dictionary=session.road_at_id("road-0").duplicate(true)
	var line:=Session.road_path(road)
	var at: Vector2=line[line.size()/2]*20.0
	editor.editor_camera.position=at
	editor.editor_camera.force_update_scroll()
	editor._source_click(at)
	check("select_tool_picks_whole_road_body",editor.pending_drag.get("kind","")=="road_move",editor.pending_drag)
	var grab: Vector2=editor.pending_drag.get("grab",at)
	var delta:=Vector2(6,4)*20
	var release_position: Vector2=root.canvas_transform*(grab+delta)
	editor._input(pointer(release_position,false))
	var moved: Dictionary=session.road_at_id("road-0")
	check("drag_release_commits_one_undoable_whole_road_move",Vector2(moved.points[0].x,moved.points[0].y).distance_to(Vector2(road.points[0].x,road.points[0].y)+Vector2(6,4))<.01 and session.history.size()==1)
	check("edited_runtime_road_is_hidden_in_preview",Roads.editor_hidden.has(0))
	var refreshed: bool=await wait_for_traffic(editor)
	check("traffic_preview_dynamically_follows_moved_roads",refreshed and editor.gizmos.network_is_draft and Vector2(editor.traffic_preview.data.roads[0].points[0][0],editor.traffic_preview.data.roads[0].points[0][1]).distance_to(Vector2(moved.points[0].x,moved.points[0].y))<.01)
	check("draft_traffic_keeps_gameplay_graph_unchanged",editor.gizmos.network!=editor.traffic_network and editor.traffic_network.source_road_count==scene.ground.data.roads.size())
	editor._undo()
	check("undo_restores_road_and_clears_old_geometry_mask",JSON.stringify(session.road_at_id("road-0"))==JSON.stringify(road) and not Roads.editor_hidden.has(0))
	check("undo_restores_original_traffic_immediately",editor.gizmos.network==editor.traffic_network and not editor.gizmos.network_is_draft)
	editor._redo();editor._undo()
	editor._source_click(at)
	# Release over the bottom toolbar. _unhandled_input cannot see this event;
	# _input must finish the gesture before the GUI consumes it.
	editor._input(pointer(Vector2(700,root.size.y-75),false))
	check("release_over_toolbar_never_leaves_drag_stuck",editor.pending_drag.is_empty() and session.dirty)
	editor._undo()
	editor._source_click(at)
	var cancel:=InputEventKey.new();cancel.keycode=KEY_ESCAPE;cancel.pressed=true
	editor._input(cancel)
	check("escape_cancels_drag_without_changing_source",editor.pending_drag.is_empty() and not session.dirty)
	var migration:=Session.new()
	migration.load_source()
	var custom_id:=migration.add_road(Vector2(2500,3200),Vector2(2600,3200))
	var remote:=migration.doc.duplicate(true)
	migration.accepted_remote(remote)
	var raw: Dictionary=scene.ground.data.duplicate(true)
	var basis:=int(remote.get("morrowSourceRoadCount",120))
	var extra: Dictionary=raw.roads[0].duplicate(true)
	extra.name="New baked default"
	raw.roads.resize(basis)
	raw.roads.append(extra)
	raw.editor_source_road_count=basis+1
	check("reload_reconciles_new_default_roads_without_wrong_ids",migration.reconcile_runtime(raw) and migration.road_at_id("road-%d"%basis).name=="New baked default" and not migration.road_at_id("road-%d"%(int(custom_id.trim_prefix("road-"))+1)).is_empty())
	check("layout_reconciliation_keeps_disk_revision_and_clean_undo_baseline",migration.matches_remote(remote) and not migration.dirty)
	editor._choose_tool("draw_road")
	var count: int=session.doc.roads.size()
	var start:=Vector2(road.points[-1].x,road.points[-1].y)
	for p in [start,start+Vector2(60,50),start+Vector2(120,30)]:editor._source_click(p*20)
	check("drawing_multiple_points_waits_for_finish",session.doc.roads.size()==count and editor.draft_points.size()==3 and not editor.finish_button.disabled)
	editor.road_width.value=14
	editor._finish_shape()
	var added: Dictionary=session.road_at_id(editor.source_id)
	check("finish_creates_curved_road_with_chosen_settings",not added.is_empty() and added.points.size()==3 and is_equal_approx(added.width,14))
	check("inspector_tracks_newly_created_road",editor.details.text.contains(str(added.id)))
	editor._choose_tool("move_prop");editor.road_lanes.value=4
	refreshed=await wait_for_traffic(editor)
	var lanes_on_new_road:=0
	if refreshed:
		for edge in editor.gizmos.network.edges:
			if int(edge.road)==int(str(added.id).trim_prefix("road-")) and not bool(edge.connector):lanes_on_new_road+=1
	check("new_road_traffic_tracks_live_lane_count",refreshed and lanes_on_new_road==4,lanes_on_new_road)
	editor.road_lanes.value=2
	check("new_roads_can_be_deleted_and_undone",session.delete_entity(str(added.id)) and session.doc.roads.size()==count and session.undo())
	editor._choose_tool("draw_terrain")
	editor.terrain_biome.select(1)
	for p in [Vector2(310,320),Vector2(390,320),Vector2(390,370)]:editor._source_click(p*20)
	editor._finish_shape()
	var ids: Dictionary={}
	for region in session.doc.regions:ids[str(region.id)]=true
	check("terrain_uses_unique_ids_material_and_required_metadata",ids.size()==session.doc.regions.size() and session.doc.regions[-1].biome=="forest" and session.doc.regions[-1].has("elevation"))
	var terrain_id: String=str(session.doc.regions[-1].id)
	var original_region: Dictionary=session.doc.regions[-1].duplicate(true)
	var inside:=Vector2(365,330)*20.0
	check("placed_terrain_selectable_from_interior",
		editor._pick_source_region(inside).get("id","")==terrain_id)
	editor._choose_tool("move_prop")
	editor.source_id=terrain_id
	editor._refresh_authoring()
	check("terrain_size_inspector_is_shown",
		editor.terrain_transforms.visible and
		absf(editor.inspector_terrain_width.value-80.0)<.01 and
		absf(editor.inspector_terrain_height.value-50.0)<.01)
	await process_frame
	check("terrain_expand_control_not_clipped_by_inspector",
		editor.terrain_expand_button.get_global_rect().end.x<=
		editor.inspector_panel.get_global_rect().end.x-5.0 and
		editor.terrain_shrink_button.get_global_rect().position.x>=
		editor.inspector_panel.get_global_rect().position.x+5.0)
	var terrain_history: int=session.history.size()
	editor._resize_selected_region(Vector2(1.2,0.8))
	var changed_region: Dictionary={}
	for region in session.doc.regions:
		if str(region.id)==terrain_id:changed_region=region;break
	check("terrain_resizes_both_axes_and_tracks_undo",
		session.history.size()==terrain_history+1 and
		absf(editor._region_bounds(changed_region).size.x-96.0)<.01 and
		absf(editor._region_bounds(changed_region).size.y-40.0)<.01)
	check("terrain_resize_rejects_out_of_bounds_without_mutating",
		not session.resize_region(terrain_id,999.0,999.0) and
		JSON.stringify(changed_region)==JSON.stringify(session.doc.regions[-1]))
	check("terrain_resize_undo_restores_vertices",
		session.undo() and JSON.stringify(session.doc.regions[-1].points)==JSON.stringify(original_region.points))
	check("terrain_resize_percent_control_starts_at_ten",
		is_equal_approx(editor.inspector_terrain_percent.value,10.0))
	editor.inspector_terrain_percent.value=25.0
	var percent_history: int=session.history.size()
	editor.terrain_expand_button.pressed.emit()
	check("terrain_expand_button_uses_entered_percentage",
		session.history.size()==percent_history+1 and
		absf(editor._region_bounds(session.doc.regions[-1]).size.x-100.0)<0.01 and
		absf(editor._region_bounds(session.doc.regions[-1]).size.y-62.5)<0.01)
	session.undo()
	editor._refresh_authoring()
	editor.inspector_terrain_percent.value=12.5
	editor.terrain_shrink_button.pressed.emit()
	check("terrain_shrink_button_uses_changed_percentage",
		absf(editor._region_bounds(session.doc.regions[-1]).size.x-70.0)<0.01 and
		absf(editor._region_bounds(session.doc.regions[-1]).size.y-43.75)<0.01)
	session.undo()
	editor._refresh_authoring()
	editor.inspector_terrain_percent.value=100.0
	editor.terrain_expand_button.pressed.emit()
	check("terrain_expand_supports_full_hundred_percent",
		absf(editor._region_bounds(session.doc.regions[-1]).size.x-160.0)<0.01 and
		absf(editor._region_bounds(session.doc.regions[-1]).size.y-100.0)<0.01)
	session.undo()
	editor._refresh_authoring()
	var before_invalid_shrink: int=session.history.size()
	editor.terrain_shrink_button.pressed.emit()
	check("terrain_shrink_prevents_collapsing_polygon",
		session.history.size()==before_invalid_shrink and
		JSON.stringify(session.doc.regions[-1].points)==JSON.stringify(original_region.points))
	editor.inspector_terrain_percent.value=12.5
	editor._refresh_authoring()
	check("resize_percentage_persists_between_edits",
		is_equal_approx(editor.inspector_terrain_percent.value,12.5))
	check("terrain_move_preserves_shape",
		session.move_shape("regions",terrain_id,Vector2(12,7)) and
		absf(float(session.doc.regions[-1].points[0].x)-float(original_region.points[0].x)-12.0)<.01)
	session.undo()
	editor._refresh_authoring()
	editor._choose_tool("place_marker")
	# Ordinary markers remain independent; race gates are placed by the
	# unified route tool, and must not create orphan standalone markers.
	var traffic_kind_index: int=-1
	var has_loose_race_gate:=false
	for index in editor.marker_kind.item_count:
		var kind:=str(editor.marker_kind.get_item_metadata(index))
		if kind in ["race_start","checkpoint","finish"]:has_loose_race_gate=true
		if kind=="traffic_spawn":traffic_kind_index=index
	check("generic_marker_menu_excludes_race_gates",not has_loose_race_gate and traffic_kind_index>=0)
	if traffic_kind_index>=0:editor.marker_kind.select(traffic_kind_index)
	editor._source_click(Vector2(3500,3500)*20)
	check("marker_tool_respects_marker_type",session.doc.markers[-1].type=="traffic_spawn")
	editor.marker_editor.dialog.hide()
	var marker_count: int=session.doc.markers.size()
	var race_count: int=session.doc.get("races",[]).size()
	var form=editor.race_editor
	form.begin_route(editor)
	form.title.text="Native linked sprint"
	form.mode.select(0)
	form.competition.select(1)
	var route: PackedVector2Array=editor._source_road_path(session.road_at_id(str(added.id)))
	editor._source_click(route[0]*20)
	check("race_start_marker_is_pending",editor.draft_points.size()==1 and session.doc.get("races",[]).size()==race_count)
	form.select_checkpoint_gate(editor)
	editor._source_click(route[route.size()/2]*20)
	check("race_checkpoint_marker_is_pending",editor.draft_points.size()==2)
	form.select_finish_gate(editor)
	editor._source_click(route[-1]*20)
	var linked: Dictionary=session.race_at_id(editor.source_id)
	var linked_ok: bool=not linked.is_empty() and linked.points.size()==3 and session.doc.markers.size()==marker_count and session.doc.get("races",[]).size()==race_count+1
	if linked_ok:
		linked_ok=Session.race_gate_marker(linked,0).type=="race_start" and Session.race_gate_marker(linked,1).properties.race_id==linked.id and Session.race_gate_marker(linked,2).type=="finish"
	check("finish_creates_one_race_with_linked_gates",linked_ok)
	form.dialog.hide()
	if linked_ok:
		editor.source_id=""
		editor._set_multi([])
		editor._refresh_authoring()
		var middle:=Vector2(linked.points[1].x,linked.points[1].y)*20
		var hit: Dictionary=editor._pick_race_handle(middle)
		check("unselected_checkpoint_resolves_owning_race",hit.get("id","")==linked.id and int(hit.get("index",-1))==1)
	else:check("unselected_checkpoint_resolves_owning_race",false)
	editor._choose_tool("draw_road");editor._source_click(Vector2(2700,3200)*20)
	editor._apply_draft()
	check("unfinished_shape_cannot_be_silently_saved",editor.bridge.phase=="" and editor.authoring_notice.text.contains("Finish or cancel"))
	editor._test_drive()
	check("unfinished_shape_cannot_be_lost_to_test_drive",editor.active and editor.draft_points.size()==1 and editor.authoring_notice.text.contains("Finish or cancel"))
	editor._cancel_gesture()
	check("draft_edits_have_a_recovery_copy",FileAccess.file_exists(editor.recovery_path))
	var dirty_source:=JSON.stringify(session.doc)
	session.doc=session.initial.duplicate(true);session.dirty=false
	editor._restore_recovery()
	check("recovery_restores_unsaved_edits",session.dirty and session._fingerprint(session.doc)==session._fingerprint(JSON.parse_string(dirty_source)))
	editor._choose_tool("place:house");editor.asset_search.grab_focus()
	var camera_before: Vector2=editor.editor_camera.position
	var key:=InputEventKey.new();key.physical_keycode=KEY_W;key.keycode=KEY_W;key.pressed=true
	Input.parse_input_event(key);editor._process(.1)
	var released:=key.duplicate() as InputEventKey
	released.pressed=false;Input.parse_input_event(released)
	check("typing_in_asset_search_does_not_pan_camera",editor.editor_camera.position.is_equal_approx(camera_before))
	editor.asset_search.release_focus()
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;wheel.position=Vector2(700,300)
	var under_cursor: Vector2=editor._event_world_position(wheel.position)
	editor._unhandled_input(wheel)
	check("zoom_preserves_world_position_under_cursor",under_cursor.distance_to(editor._event_world_position(wheel.position))<.01)
	check("editing_does_not_mutate_the_playable_archive",JSON.stringify(scene.ground.data.roads)==baked_before)
	var output:=FileAccess.open("res://.runtime/native-editor-audit/source.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(editor.bridge._python_typed_source(session.doc)));output.close()
	editor._choose_tool("draw_road");editor._source_click(Vector2(2700,3200)*20)
	editor._discard_draft()
	check("discard_clears_shapes_recovery_and_preview_masks",editor.draft_points.is_empty() and not FileAccess.file_exists(editor.recovery_path) and Roads.editor_hidden.is_empty())
	scene.queue_free();await process_frame
	print("NATIVE EDITOR INTERACTIONS: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
