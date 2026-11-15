extends SceneTree
const Shapes=preload("res://scripts/dev/road_shape_geometry.gd")
const Library=preload("res://scripts/dev/native_map_library.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func run() -> void:
	var folder:="res://.runtime/road-shapes-test-%d"%Time.get_ticks_usec()
	OS.set_environment("STREETBOUND_MAP_LIBRARY",folder)
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH",folder+"/draft.json")
	var map_hash:=FileAccess.get_sha256("res://worlds/morrow-coast.world.json")
	var scene=load("res://scenes/world_editor.tscn").instantiate();root.add_child(scene)
	for i in 8:await process_frame
	var e=scene.native_world_editor;var switcher=e.map_switcher
	var dealers=scene.editor_dealerships;var dealer_count: int=dealers.shop_nodes.size()
	var original_roads: int=scene.ground.data.roads.size()
	check("original_map_has_its_existing_dealership_layer",dealer_count>0 and dealers.is_visible_in_tree())
	switcher.map_name.text="Road shapes test";switcher.width.value=2400;switcher.height.value=1800;switcher.create_map(e)
	for i in 4:await process_frame
	check("new_map_has_no_inherited_showrooms_or_parking_lots",switcher.custom and e.authoring.doc.props.is_empty() and not dealers.is_visible_in_tree() and dealers.pavement_nodes.all(func(n):return not n.is_visible_in_tree()))
	check("custom_data_cannot_invalidate_cached_morrow_renderers",e.world!=scene.ground and e.world.data.roads.is_empty() and scene.ground.data.roads.size()==original_roads)
	e._set_layer(false,"scenery");e._set_layer(true,"scenery")
	check("scenery_toggle_cannot_restore_foreign_dealerships",not dealers.is_visible_in_tree())
	var minimum_session:=Session.new();minimum_session.doc=Library.create("Minimum circle",2400,1800,"grass")
	var minimum_id: String=minimum_session.add_circle_road(Vector2(2000,1350),8)
	check("minimum_radius_circle_survives_coordinate_precision",not minimum_id.is_empty() and not Shapes.circle(minimum_session.road_at_id(minimum_id).points).is_empty())
	var road: String=e.authoring.add_road(Vector2(300,500),Vector2(800,500))
	var branch: String=e.authoring.add_road(Vector2(550,500),Vector2(550,300))
	e.source_id=road;e._refresh_authoring();e.road_shapes.bend.value=60
	e.road_shapes.left.pressed.emit()
	var changed: Dictionary=e.authoring.road_at_id(road)
	check("curve_left_preserves_endpoints_and_bends_left",changed.points[0]=={"x":300.0,"y":500.0} and changed.points[-1]=={"x":800.0,"y":500.0} and changed.points.any(func(p):return absf(float(p.x)-550)<.01 and absf(float(p.y)-440)<.01))
	check("curved_road_keeps_its_attached_branch",Shapes.point(e.authoring.road_at_id(branch).points[0]).distance_to(Vector2(550,440))<.01)
	e.road_shapes.right.pressed.emit()
	check("curve_right_uses_requested_bend",Shapes.point(e.authoring.road_at_id(branch).points[0]).distance_to(Vector2(550,560))<.01)
	e._undo()
	check("curve_is_one_undo_step_including_junction",Shapes.point(e.authoring.road_at_id(branch).points[0]).distance_to(Vector2(550,440))<.01)
	e.road_shapes.straighten.pressed.emit()
	check("straighten_restores_a_straight_road",e.authoring.road_at_id(road).points.all(func(p):return absf(float(p.y)-500)<.01))
	e.road_shapes.left.pressed.emit()
	e._choose_tool("place_circle_road");e.road_shapes.radius.value=55
	e._source_click(Vector2(1400,950)*20)
	var circle_id: String=e.source_id
	var shape:=Shapes.circle(e.authoring.road_at_id(circle_id).points)
	check("click_places_a_perfect_circle_with_selected_radius",e.tool_name=="move_prop" and not shape.is_empty() and absf(shape.radius-55)<.01 and Vector2(shape.center).distance_to(Vector2(1400,950))<.01)
	e.road_shapes.larger.pressed.emit();e.road_shapes.smaller.pressed.emit()
	e.road_shapes.radius.value=80;e.road_shapes.apply_radius.pressed.emit()
	var circle: Dictionary=e.authoring.road_at_id(circle_id)
	var path:=Session.road_path(circle)
	check("radius_field_resizes_all_points_about_fixed_center",circle.points.all(func(p):return absf(Shapes.point(p).distance_to(Vector2(1400,950))-80)<.01))
	check("circle_render_samples_have_constant_radius",path.size()>64 and Array(path).all(func(p):return absf(p.distance_to(Vector2(1400,950))-80)<.02))
	check("circle_seam_is_closed_and_smooth",path[0]==path[-1] and (path[1]-path[0]).normalized().dot((path[-1]-path[-2]).normalized())>.99)
	var join:=Vector2(1400,950)+Vector2.from_angle(.37)*80
	var entry: String=e.authoring.add_road(join,Vector2(1650,1050))
	check("new_road_connects_to_arbitrary_point_on_circle",not entry.is_empty() and not Shapes.circle(e.authoring.road_at_id(circle_id).points).is_empty() and e.authoring.road_at_id(circle_id).points.size()==34)
	e.source_id=circle_id;e._refresh_authoring();e.road_shapes.radius.value=95;e.road_shapes.apply_radius.pressed.emit()
	check("resizing_keeps_roundabout_entry_attached",absf(Shapes.point(e.authoring.road_at_id(entry).points[0]).distance_to(Vector2(1400,950))-95)<.01)
	e._undo()
	check("radius_undo_restores_entry_and_circle",absf(Shapes.point(e.authoring.road_at_id(entry).points[0]).distance_to(Vector2(1400,950))-80)<.01 and absf(e.road_shapes.radius.value-80)<.01)
	e.inspector_x.value=1420
	shape=Shapes.circle(e.authoring.road_at_id(circle_id).points)
	check("circle_center_inspector_moves_circle_and_attached_entry",not shape.is_empty() and Vector2(shape.center).distance_to(Vector2(1420,950))<.02 and absf(Shapes.point(e.authoring.road_at_id(entry).points[0]).distance_to(Vector2(1420,950))-80)<.02)
	e.inspector_x.value=1400
	var copied: String=e.authoring.duplicate_entity(circle_id)
	check("duplicated_circle_retains_resizable_geometry",not copied.is_empty() and not Shapes.circle(e.authoring.road_at_id(copied).points).is_empty())
	e._undo()
	var raw: Dictionary=e.authoring.road_at_id(circle_id).points[1]
	check("manual_point_edit_returns_circle_to_freeform_road",e.authoring.move_road_point(circle_id,1,Vector2(raw.x,raw.y)+Vector2(0,5),0) and Shapes.circle(e.authoring.road_at_id(circle_id).points).is_empty())
	e._undo()
	var stamp: String=JSON.stringify(e.authoring.doc)
	check("out_of_bounds_circle_is_rejected_without_losing_edits",not e.authoring.resize_circle_road(circle_id,1800) and JSON.stringify(e.authoring.doc)==stamp)
	check("circular_map_saves_and_reloads",switcher.save_current(e) and not Shapes.circle(Library.load_map(switcher.current_file).roads[2].points).is_empty())
	var graph_data:=preload("res://scripts/dev/native_traffic_preview.gd").build_data(e.world.data,e.authoring.doc.roads,[])
	var graph:=preload("res://scripts/world/traffic_network.gd").new();graph.build(graph_data)
	check("roundabout_and_entry_generate_traffic_lanes_and_junction",graph.edges.size()>0 and graph_data.junctions.size()>=2)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime/road-shapes"))
	var out=FileAccess.open("res://.runtime/road-shapes/source.json",FileAccess.WRITE);out.store_string(JSON.stringify(e.authoring.doc));out.close()
	if DisplayServer.get_name()!="headless":
		# Frame the authored roads and the controls used to create them.
		e.editor_camera.position=Vector2(1080,750)*20;e.editor_camera.zoom=Vector2.ONE*.025;e._position_camera_canvas();e._update_view(true)
		for i in 20:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.runtime/road-shapes/editor.png")
	switcher.select(e,0)
	check("returning_to_morrow_restores_only_its_original_dealerships",dealers.is_visible_in_tree() and dealers.shop_nodes.size()==dealer_count and FileAccess.get_sha256("res://worlds/morrow-coast.world.json")==map_hash)
	e._discard_draft();scene.queue_free();await process_frame;await process_frame
	print("ROAD SHAPE TOOLS: ","PASS" if failures.is_empty() else str(failures));quit(0 if failures.is_empty() else 1)
