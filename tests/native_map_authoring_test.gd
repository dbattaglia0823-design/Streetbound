extends SceneTree
## Native editor editing uses the authoring overlay, never the baked map.
## The production Python bridge handles actual generation and rollback.
const Session = preload("res://scripts/dev/native_map_edit_session.gd")
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, valid: bool) -> void:
	print("%s %s" % ["PASS" if valid else "FAIL",label])
	if not valid:
		errors.append(label)

func _run() -> void:
	var session = Session.new()
	check("authored_source_loads",session.load_source())
	if session.doc.is_empty():
		quit(1)
		return
	check("authoring_doc_is_world_forge_v2",
		session.doc.format=="gdt.racing-world" and
		int(session.doc.version)==2 and session.doc.roads.size()>=120)
	var original_hash: String = session.baseline_hash
	var origin_road: Dictionary = session.road_at_id("road-0")
	check("stable_source_road_id",not origin_road.is_empty())
	var old_end := Vector2(float(origin_road.points[origin_road.points.size()-1].x),
		float(origin_road.points[origin_road.points.size()-1].y))
	var new_end := old_end + Vector2(4,3)
	check("moving_real_road_anchor_is_atomic",
		session.move_road_point("road-0",origin_road.points.size()-1,new_end,0.0))
	var joined: Dictionary = session.road_at_id("road-1")
	check("shared_endpoint_stays_connected_without_browser_approximation",
		Vector2(float(joined.points[0].x),float(joined.points[0].y)).distance_to(new_end)<0.01)
	check("road_edit_can_be_undone",session.undo() and
		Vector2(float(session.road_at_id("road-0").points[
			origin_road.points.size()-1].x),
			float(session.road_at_id("road-0").points[
			origin_road.points.size()-1].y)).distance_to(old_end)<0.01)
	check("redo_restores_both_joined_road_endpoints",session.redo() and
		Vector2(float(session.road_at_id("road-1").points[0].x),
			float(session.road_at_id("road-1").points[0].y)).distance_to(new_end)<0.01)
	check("reject_unsafe_road_teleport",
		not session.move_road_point("road-0",0,old_end+Vector2(2000,0)))
	check("reject_out_of_bounds_edits",
		not session.move_road_point("road-0",0,Vector2(-20,0)))
	var before_count: int = session.doc.props.size()
	var id: String = session.add_prop("house",Vector2(2300,3200))
	check("new_game_asset_has_stable_source_id",
		id.begins_with("prop-native-") and
		session.doc.props.size()==before_count+1 and
		session.prop_at_id(id).assetId=="game-house")
	check("placement_does_not_move_other_objects",
		session.doc.roads.size()>=120 and
		session.doc.props.size()==before_count+1)
	check("authored_asset_moves_rotates_and_resizes",
		session.move_prop(id,Vector2(2320,3210)) and
		session.rotate_prop(id,15) and
		session.resize_prop(id,1.15) and
		absf(float(session.prop_at_id(id).rotation)-15)<0.01 and
		absf(float(session.prop_at_id(id).scale)-1.15)<0.01)
	check("authored_asset_deletion_undo_and_redo",
		session.delete_prop(id) and session.prop_at_id(id).is_empty() and
		session.undo() and not session.prop_at_id(id).is_empty() and
		session.redo() and session.prop_at_id(id).is_empty())
	check("dirty_state_and_unchanged_source_revision",
		session.dirty and session.baseline_hash==original_hash)
	session.discard_changes()
	check("discard_restores_clean_source_and_ids",
		not session.dirty and session.baseline_hash==original_hash and
		session.doc.props.size()==before_count and
		session.road_at_id("road-0").points==origin_road.points)
	check("runtime_procedural_assets_are_never_editable_by_position",
		session.index_of_runtime_prop({"kind":"tree","p":[2300,3200]})=="")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var editor: Variant = game.native_world_editor
	if editor == null:
		editor = load("res://scripts/dev/native_world_editor.gd").new()
		editor.world = game.ground
		editor.player = game.vehicle
		editor.driving_camera = get_first_node_in_group("player_camera")
		editor.traffic_network = game.ground.get_node("AmbientTraffic").get("network")
		game.add_child(editor)
		await process_frame
	check("actual_native_editor_opens_in_game",editor.open_editor())
	var runtime_road_count: int = game.ground.data.roads.size()
	var runtime_prop_count: int = game.ground.data.props.size()
	editor._choose_tool("place:house")
	editor._source_click(Vector2(2300,3200)*20.0)
	check("editor_placement_creates_undoable_source_preview",
		editor.authoring.dirty and editor.authoring.doc.props.size()==before_count+1 and
		editor.gizmos.draft_doc.props.size()==before_count+1)
	check("runtime_map_and_traffic_unchanged_before_rebake",
		game.ground.data.roads.size()==runtime_road_count and
		game.ground.data.props.size()==runtime_prop_count and
		editor.traffic_network.connector_count>0)
	editor._undo()
	check("native_undo_returns_to_original_authoring_source",
		not editor.authoring.dirty and
		editor.authoring.doc.props.size()==before_count)
	editor._redo()
	check("native_redo_restores_pending_asset",editor.authoring.dirty)
	editor.close_editor()
	check("test_drive_does_not_discard_unsaved_draft",
		not editor.active and editor.authoring.dirty and not paused)
	check("reopen_retains_editable_draft",editor.open_editor() and editor.authoring.dirty)
	editor._discard_draft()
	check("discard_removes_ghosts_and_disables_apply",
		not editor.authoring.dirty and editor.apply_button.disabled and
		editor.authoring.doc.props.size()==before_count)
	editor.close_editor()
	game.queue_free()
	paused = false
	print("NATIVE MAP AUTHORING: ","PASS" if errors.is_empty() else
		"FAIL "+str(errors))
	quit(0 if errors.is_empty() else 1)
