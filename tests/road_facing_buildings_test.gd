extends SceneTree
const Library=preload("res://scripts/dev/native_map_library.gd")
const Snap=preload("res://scripts/dev/road_building_snap.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func pos(prop: Dictionary) -> Vector2:return Vector2(prop.x,prop.y)
func place(e,where: Vector2) -> String:
	e._choose_tool("place:house");e._source_click(where*20);return e.source_id
func select(e,id: String) -> void:
	e._choose_tool("move_prop");e.source_id=id;e._refresh_authoring()
func drag(e,id: String,to: Vector2) -> void:
	select(e,id)
	var origin: Vector2=pos(e.authoring.prop_at_id(id))*20
	e.pending_drag={"kind":"prop","id":id,"from":origin,"to":origin,"grab":origin};e._refresh_authoring()
	e._update_drag_preview(to*20);e._finish_source_drag(to*20)
func run() -> void:
	var folder:="res://.runtime/road-facing-test-%d"%Time.get_ticks_usec()
	OS.set_environment("STREETBOUND_MAP_LIBRARY",folder);OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH",folder+"/draft.json")
	var hash:=FileAccess.get_sha256("res://worlds/morrow-coast.world.json")
	var scene=load("res://scenes/world_editor.tscn").instantiate();root.add_child(scene)
	for i in 8:await process_frame
	var e=scene.native_world_editor;var switcher=e.map_switcher
	switcher.map_name.text="Road-facing blocks";switcher.width.value=1800;switcher.height.value=1200;switcher.create_map(e)
	var straight: Array[Vector2]=[Vector2(200,450),Vector2(1100,450)]
	e.authoring.add_road_path(straight,{"width":12.0})
	var first: String=place(e,Vector2(450,431))
	var house: Dictionary=e.authoring.prop_at_id(first)
	check("north_curb_front_faces_road_with_half_metre_clearance",pos(house).distance_to(Vector2(450,433))<.01 and absf(float(house.rotation))<.01)
	e._undo();check("placement_and_alignment_are_one_undo_step",e.authoring.prop_at_id(first).is_empty());e._redo()
	var second: String=place(e,Vector2(463,431))
	house=e.authoring.prop_at_id(second)
	check("road_alignment_and_building_walls_form_a_city_row",pos(house).distance_to(Vector2(462.25,433))<.01 and absf(float(house.rotation))<.01)
	check("per_asset_alignment_control_is_available",e.inspector_road_facing.visible and e.inspector_road_facing.button_pressed)
	# Adjacent facades have only 0.25 m of clearance. Rotating the
	# second house in place would overlap the first, and must be rejected.
	e.inspector_road_facing.button_pressed=false
	e.inspector_rotation.value=37
	house=e.authoring.prop_at_id(second)
	check("adjacent_house_rotation_rejects_overlap",
		not house.roadFacing and absf(float(house.rotation))<.01 and
		pos(house).distance_to(Vector2(462.25,433))<.01)
	# Moving the house into open space permits the same manual rotation.
	drag(e,second,Vector2(500,431))
	e.inspector_rotation.value=37
	house=e.authoring.prop_at_id(second)
	check("disabled_asset_retains_manual_rotation_and_position",
		not house.roadFacing and absf(float(house.rotation)-37)<.01 and
		pos(house).distance_to(Vector2(500,431))<.01)
	check("disabling_one_asset_keeps_others_enabled",Snap.enabled(e.authoring.prop_at_id(first)))
	e.inspector_road_facing.button_pressed=true
	check("enabling_near_road_aligns_in_one_edit",Snap.enabled(e.authoring.prop_at_id(second)) and pos(e.authoring.prop_at_id(second)).distance_to(Vector2(500,433))<.01 and absf(float(e.authoring.prop_at_id(second).rotation))<.01)
	e._undo();house=e.authoring.prop_at_id(second)
	check("toggle_undo_restores_preference_and_transform",not house.roadFacing and absf(float(house.rotation)-37)<.01 and pos(house).distance_to(Vector2(500,431))<.01)
	# Edge snapping remains available when road-facing is off.
	e.authoring.edit_entity(second,{"rotation":0.0},Vector2(500,431));e._refresh_authoring()
	drag(e,second,Vector2(463,433))
	check("disabled_road_facing_still_allows_building_edge_snap",not e.authoring.prop_at_id(second).roadFacing and pos(e.authoring.prop_at_id(second)).distance_to(Vector2(462.25,433))<.01)
	var south: String=place(e,Vector2(700,468));house=e.authoring.prop_at_id(south)
	check("opposite_side_faces_back_toward_road",pos(house).distance_to(Vector2(700,467))<.01 and Vector2.DOWN.rotated(deg_to_rad(float(house.rotation))).dot(Vector2.UP)>.999)
	e.inspector_road_front.select(2);e.inspector_road_front.item_selected.emit(2)
	house=e.authoring.prop_at_id(south)
	check("artwork_front_option_supports_other_model_orientations",house.roadFront==270 and absf(float(house.rotation))<.01)
	var diagonal: Array[Vector2]=[Vector2(300,700),Vector2(900,850)]
	e.authoring.add_road_path(diagonal,{"width":12.0});e._refresh_authoring()
	var tangent:=Vector2(600,150).normalized();var outward:=Vector2(tangent.y,-tangent.x)
	var diagonal_first: String=place(e,Vector2(600,775)+outward*18)
	var diagonal_second: String=place(e,pos(e.authoring.prop_at_id(diagonal_first))+tangent*13)
	var p: Dictionary=e.authoring.prop_at_id(diagonal_first);var q: Dictionary=e.authoring.prop_at_id(diagonal_second)
	check("diagonal_street_aligns_facades_and_shared_walls",absf(wrapf(deg_to_rad(float(p.rotation))-tangent.angle(),-PI,PI))<.001 and (pos(q)-pos(p)).distance_to(tangent*12.25)<.03)
	# Scaled footprints, not a fixed house radius, determine curb clearance.
	select(e,south);e.authoring.edit_entity(south,{"scaleX":2.0,"scaleY":.7},pos(house));e._refresh_authoring()
	var scaled: Dictionary=e._snap_building_transform(e.authoring.prop_at_id(south),Vector2(700,467))
	check("nonuniform_size_uses_actual_facade_clearance",Vector2(scaled.position).distance_to(Vector2(700,464.45))<.02)
	# New circles use their rendered path for frontage, including seam-adjacent queries.
	e.authoring.add_circle_road(Vector2(1400,300),85);e._refresh_authoring()
	var curved: String=place(e,Vector2(1400,300)+Vector2.from_angle(.42)*101)
	house=e.authoring.prop_at_id(curved)
	var inward: Vector2=(Vector2(1400,300)-pos(house)).normalized()
	check("curved_road_front_follows_local_tangent",Vector2.DOWN.rotated(deg_to_rad(float(house.rotation))).dot(inward)>.998 and pos(house).distance_to(Vector2(1400,300))>100)
	var far: Dictionary=e._snap_building_transform(house,Vector2(1650,1000))
	check("distant_houses_do_not_jump_or_rotate",Vector2(far.position)==Vector2(1650,1000) and absf(float(far.rotation)-float(house.rotation))<.001)
	var alt:=InputEventKey.new();alt.keycode=KEY_ALT;alt.physical_keycode=KEY_ALT;alt.alt_pressed=true;alt.pressed=true;Input.parse_input_event(alt)
	await process_frame
	var bypass: Dictionary=e._snap_building_transform(house,Vector2(800,431))
	check("alt_temporarily_bypasses_road_and_building_snaps",Vector2(bypass.position)==Vector2(800,431) and absf(float(bypass.rotation)-float(house.rotation))<.001)
	var release:=alt.duplicate();release.pressed=false;release.alt_pressed=false;Input.parse_input_event(release)
	await process_frame
	# Rotation and collider must follow the fast single-object drag preview.
	select(e,curved)
	var origin: Vector2=pos(house)*20
	e.pending_drag={"kind":"prop","id":curved,"from":origin,"to":origin,"grab":origin};e._refresh_authoring()
	e._update_drag_preview((Vector2(1400,300)+Vector2.from_angle(.65)*101)*20)
	var index: int=e.gizmos.preview_indices[curved]
	var shown: Dictionary=e.gizmos.preview_scenery.prop_list[index]
	var collider: CollisionShape2D
	for node in e.gizmos.preview_body.get_children():
		if str(node.get_meta("draft_prop_id",""))==curved:collider=node
	check("drag_art_outline_and_collision_share_snapped_rotation",absf(float(shown.angle)-deg_to_rad(float(e.pending_drag.rotation)))<.001 and collider!=null and absf(collider.rotation-float(shown.angle))<.001 and collider.position.distance_to(e.pending_drag.to)<.01)
	if DisplayServer.get_name()!="headless":
		for i in 16:await process_frame
	var rebuilds: int=e.road_building_snap.rebuild_count
	var canvas_redraws: int=e.gizmos.static_redraw_count
	var times: Array[float]=[]
	for i in 100:
		var start:=Time.get_ticks_usec()
		e._update_drag_preview((Vector2(1400,300)+Vector2.from_angle(.65+i*.001)*101)*20)
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw;times.append((Time.get_ticks_usec()-start)/1000.0);await process_frame
	check("drag_reuses_road_index_and_single_house_canvas",e.road_building_snap.rebuild_count==rebuilds and (DisplayServer.get_name()=="headless" or e.gizmos.static_redraw_count==canvas_redraws))
	if not times.is_empty():times.sort();print("ROAD-FACING RENDERED DRAG ms median=",times[50]," p95=",times[95])
	e._finish_source_drag((Vector2(1400,300)+Vector2.from_angle(.75)*101)*20)
	check("custom_map_persists_per_asset_road_facing_settings",switcher.save_current(e) and Library.load_map(switcher.current_file).props.any(func(item):return item.id==second and item.roadFacing==false))
	var duplicate: String=e.authoring.duplicate_entity(second)
	check("duplicate_keeps_its_own_alignment_preference",not duplicate.is_empty() and e.authoring.prop_at_id(duplicate).roadFacing==false)
	e._undo()
	# Export actual editor output for the production bake regression.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/road-facing"))
	var output=FileAccess.open("res://.runtime/road-facing/source.json",FileAccess.WRITE);output.store_string(JSON.stringify(e.bridge._python_typed_source(e.authoring.doc)));output.close()
	if DisplayServer.get_name()!="headless":
		select(e,first);e.editor_camera.position=Vector2(600,455)*20;e.editor_camera.zoom=Vector2.ONE*.09;e._position_camera_canvas();e._update_view(true)
		for i in 15:await process_frame
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://.runtime/road-facing/editor.png")
	check("playable_world_archive_is_unchanged",FileAccess.get_sha256("res://worlds/morrow-coast.world.json")==hash)
	switcher.save_current(e);switcher.restore(e);e._discard_draft();scene.queue_free();await process_frame;await process_frame
	print("ROAD-FACING BUILDINGS: ","PASS" if failures.is_empty() else str(failures));quit(0 if failures.is_empty() else 1)
