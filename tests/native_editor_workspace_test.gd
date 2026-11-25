extends SceneTree
## Exercise the real standalone workspace and F6 workspace at both map LODs.
const Native=preload("res://scripts/dev/native_world_editor.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool,detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if ok else "FAIL",label,detail])
	if not ok:failures.append(label)

func gpu_overview(e) -> void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	var overview=e.overview_renderer
	var image: Image=overview.viewport.get_texture().get_image()
	var opaque:=0
	for y in range(16,image.get_height(),64):
		for x in range(16,image.get_width(),64):
			if image.get_pixel(x,y).a>.95:opaque+=1
	check("gpu_overview_contains_opaque_world_across_entire_texture",opaque>float(image.get_width()*image.get_height())/(64*64)*.90,opaque)
	e._set_layer(false,"roads")
	await process_frame;await RenderingServer.frame_post_draw
	var hidden: Image=overview.viewport.get_texture().get_image()
	var changed:=0
	var samples:=0
	for i in range(0,e.world.data.segments.size(),31):
		var segment: Dictionary=e.world.data.segments[i]
		var pos: Vector2=(Vector2(segment.a[0],segment.a[1])+Vector2(segment.b[0],segment.b[1]))*.5
		var pixel: Vector2i=Vector2i(pos/overview.extent_m*Vector2(image.get_size()))
		pixel=pixel.clamp(Vector2i.ZERO,image.get_size()-Vector2i.ONE)
		var a:=image.get_pixelv(pixel);var b:=hidden.get_pixelv(pixel)
		if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.04:changed+=1
		samples+=1
	check("gpu_overview_draws_roads_at_authored_world_positions",changed>samples*.40,[changed,samples])
	e._set_layer(true,"roads")
	await process_frame;await RenderingServer.frame_post_draw
func run() -> void:
	var world_hash:=FileAccess.get_sha256("res://worlds/morrow-coast.world.json")
	var source_hash:=FileAccess.get_sha256("res://map-editor/maps/morrow-coast.edits.world.json")
	OS.set_environment("STREETBOUND_EDITOR_RECOVERY_PATH","res://.runtime/editor-workspace-recovery.json")
	var scene: Node=load("res://scenes/world_editor.tscn").instantiate();root.add_child(scene)
	for i in 6:await process_frame
	var e=scene.native_world_editor
	check("browser_style_workspace_opens",e.active and e.source_ready and e.mode_buttons.size()>=8 and e.mode_buttons.has("select_box") and e.mode_buttons.has("move_prop"))
	# Transform spinner arrows must be coarse on left click and precise on
	# right click, while keeping fractional text entry and disabled controls.
	var arrows_script=preload("res://scripts/dev/native_transform_arrows.gd")
	var transform_fields: Array[SpinBox]=[e.inspector_x,e.inspector_y,e.inspector_rotation,
		e.inspector_scale,e.inspector_scale_x,e.inspector_scale_y]
	var all_have_arrow_targets:=true
	var coarse_and_fine:=true
	for spin in transform_fields:
		all_have_arrow_targets=all_have_arrow_targets and spin.has_node("TransformArrowHitArea")
		# Without a selected object, the inspector is intentionally read-only.
		# Test the arrow behavior with editability enabled explicitly.
		spin.editable=true
		spin.value=2.25
		arrows_script.nudge(spin,MOUSE_BUTTON_LEFT,true)
		coarse_and_fine=coarse_and_fine and is_equal_approx(spin.value,3.25)
		arrows_script.nudge(spin,MOUSE_BUTTON_RIGHT,false)
		coarse_and_fine=coarse_and_fine and is_equal_approx(spin.value,3.15)
	check("all_transform_fields_have_mouse_arrow_targets",all_have_arrow_targets)
	check("left_arrow_one_right_arrow_point_one_for_position_size_and_rotation",coarse_and_fine)
	var x_spin: SpinBox=e.inspector_x
	var hit: Control=x_spin.get_node("TransformArrowHitArea") as Control
	x_spin.value=100.0
	var pointer_up:=InputEventMouseButton.new()
	pointer_up.button_index=MOUSE_BUTTON_LEFT;pointer_up.pressed=true
	pointer_up.position=Vector2(5,hit.size.y*.25)
	hit.gui_input.emit(pointer_up)
	check("arrow_ui_left_click_increases_position_by_one",is_equal_approx(x_spin.value,101.0))
	var pointer_down:=InputEventMouseButton.new()
	pointer_down.button_index=MOUSE_BUTTON_RIGHT;pointer_down.pressed=true
	pointer_down.position=Vector2(5,hit.size.y*.75)
	hit.gui_input.emit(pointer_down)
	check("arrow_ui_right_click_decreases_position_by_point_one",is_equal_approx(x_spin.value,100.9))
	x_spin.editable=false
	arrows_script.nudge(x_spin,MOUSE_BUTTON_LEFT,true)
	check("read_only_transform_arrow_does_not_change_value",is_equal_approx(x_spin.value,100.9))
	x_spin.editable=true
	e._refresh_inspector()
	check("settings_inspector_and_map_have_separate_space",e.settings_panel.get_rect().end.x<=e.canvas_rect.position.x and e.canvas_rect.end.x<=e.inspector_panel.position.x and e.canvas_bar.get_rect().end.y<=e.canvas_rect.position.y)
	check("editor_actions_are_accessible_with_horizontal_scroll",
		e.canvas_bar.find_child("CanvasEditActionsScroll",true,false) is ScrollContainer and
		e.inspector_panel.size.x>=330.0 and
		e.canvas_rect.end.x<=e.inspector_panel.position.x)
	check("all_editor_panels_stay_within_viewport",
		e.inspector_panel.get_rect().end.x<=get_root().get_visible_rect().size.x+0.01 and
		e.settings_panel.get_rect().position.x>=0.0,
		{"inspector_end":e.inspector_panel.get_rect().end.x,
		 "inspector_width":e.inspector_panel.size.x,
		 "inspector_min":e.inspector_panel.get_combined_minimum_size(),
		 "viewport_width":get_root().get_visible_rect().size.x,
		 "inspector_scroll_min":e.inspector_panel.get_child(0).get_combined_minimum_size()})
	check("library_is_integrated_with_tool_settings",e.settings_panel.is_ancestor_of(e.asset_dock))
	check("tool_and_world_settings_are_separate_tabs",
		e.settings_panel.find_child("ToolAndWorldTabs",true,false) is TabContainer)
	check("inspector_layers_objects_are_separate_tabs",
		e.inspector_tabs.get_tab_count()==3 and e.inspector_tabs.get_tab_title(0)=="Inspector"
		and e.inspector_tabs.get_tab_title(1)=="Layers" and e.inspector_tabs.get_tab_title(2)=="Objects")
	for tool in ["draw_road","draw_terrain","place:house","place_marker","pan","draw_sidewalk",
			"draw_guardrail","place_circle_road","draw_race","move_prop"]:
		e._choose_tool(tool)
		check("tool_"+tool,e.tool_name==tool and e.settings_panel.visible and e.inspector_panel.visible)
		check("context_only_"+tool,
			e.road_settings.visible==(tool in ["draw_road","place_circle_road"])
			and e.terrain_settings.visible==(tool=="draw_terrain")
			and e.marker_settings.visible==(tool=="place_marker")
			and e.asset_dock.visible==(tool=="place:house")
			and e.sidewalk_settings.visible==(tool=="draw_sidewalk")
			and e.guardrail_settings.visible==(tool=="draw_guardrail")
			and e.race_settings.visible==(tool=="draw_race"))
		check("empty_inspector_"+tool,not e.selection_fields.visible and not e.prop_transforms.visible)
	check("empty_selection_hides_object_actions",not e.edit_actions.visible)
	e.source_id="road-0";e.source_anchor=-1;e._refresh_authoring()
	check("selected_road_only_exposes_road_settings",e.road_settings.visible and
		not e.terrain_settings.visible and not e.race_settings.visible and e.selection_fields.visible
		and e.point_picker.visible and not e.prop_transforms.visible)
	var original_road: Dictionary=e.authoring.road_at_id("road-0").duplicate(true)
	check("placed_road_has_visible_type_selector",e.inspector_road_type_fields.visible)
	e._change_inspector_road_type(5)
	var converted: Dictionary=e.authoring.road_at_id("road-0")
	check("existing_road_converts_to_track_without_geometry_changes",
		converted.roadClass=="track" and converted.surface=="track"
		and converted.points==original_road.points and converted.width==original_road.width
		and converted.lanes==original_road.lanes)
	check("road_type_controls_remain_synchronized",e.road_class.selected==5 and e.inspector_road_type.selected==5)
	e._change_inspector_road_type(0)
	check("track_can_be_converted_back_to_city",
		e.authoring.road_at_id("road-0").roadClass=="city" and e.authoring.road_at_id("road-0").surface=="asphalt")
	e._undo();e._undo()
	check("road_type_changes_are_undoable",e.authoring.road_at_id("road-0")==original_road)
	e._choose_tool("pan")
	check("pan_hides_previous_road_settings",not e.road_settings.visible and not e.selection_fields.visible)
	e._choose_tool("move_prop")
	e._set_layer(false,"roads")
	check("hidden_road_layer_hides_road_debug_controls",not e.road_layer_settings.visible)
	e._set_layer(true,"roads")
	check("enabled_road_layer_restores_road_debug_controls",e.road_layer_settings.visible)
	e.marker_editor.type_input.select(e.marker_editor.type_input.item_count-1)
	e.marker_editor._refresh_type_fields()
	check("nontraffic_marker_hides_spawn_priority",not e.marker_editor.weight_input.visible)
	var contains_contacts:=false
	for i in e.marker_kind.item_count:
		if str(e.marker_kind.get_item_metadata(i))=="contract_contact":contains_contacts=true
	check("marker_tool_includes_contract_contacts",contains_contacts)
	e._fit_map();await process_frame
	var overview=e.overview_renderer
	check("full_map_uses_real_archive_artwork",overview.full_world.content.segments.size()==scene.ground.data.segments.size() and overview.prop_count==scene.ground.data.props.size() and overview.road_count>=scene.ground.data.roads.size())
	check("overview_is_bounded_and_collision_free",maxi(overview.viewport.size.x,overview.viewport.size.y)<=4096 and overview.full_world.collider_body==null)
	var extent:=Vector2(scene.ground.data.size[0],scene.ground.data.size[1])*20.0
	var a: Vector2=root.canvas_transform*Vector2.ZERO;var b: Vector2=root.canvas_transform*extent
	check("fit_contains_entire_map_in_unobscured_canvas",e.canvas_rect.has_point(a) and e.canvas_rect.has_point(b),[a,b,e.canvas_rect])
	check("map_remains_rendered_beyond_old_tile_limit",e.render_tiles.total_visible>64 and e.overview_sprite.visible and not e.render_tiles.visible)
	await gpu_overview(e)
	var renders: int=overview.refresh_count
	for i in 4:e._update_view(true)
	check("unchanged_overview_is_cached",overview.refresh_count==renders)
	e._set_zoom(.15,e.canvas_rect.get_center())
	check("overview_covers_detail_build_transition",e.render_tiles.ready_to_show or e.overview_sprite.visible)
	for i in 60:
		await process_frame
		if e.render_tiles.ready_to_show:break
	check("near_view_switches_to_completed_real_render_tiles",e.render_tiles.ready_to_show and e.render_tiles.tiles.size()<=64)
	# A draft edit made in detail mode invalidates the overview, but does
	# not need an expensive atlas render until the next overview transition.
	e._update_overview_mask()
	var detail_renders: int=overview.refresh_count
	e._update_view(true)
	check("detail_view_defers_dirty_overview",e._overview_dirty and overview.refresh_count==detail_renders)
	e._fit_map()
	check("zoom_out_refreshes_dirty_overview_immediately",
		not e._overview_dirty and overview.refresh_count==detail_renders+1)
	await process_frame
	check("zoom_out_preserves_every_district_again",e.overview_sprite.visible and overview.prop_count==scene.ground.data.props.size())
	var cached_renders: int=overview.refresh_count
	for i in 4:e._update_view(true)
	check("overview_stays_cached_after_detail_transition",overview.refresh_count==cached_renders)
	e.minimap.navigate(e.minimap.map_rect().position+e.minimap.map_rect().size*Vector2(.25,.35))
	check("minimap_moves_to_clicked_world_location",e.editor_camera.position.distance_to(extent*Vector2(.25,.35))<1.0)
	var cursor: Vector2=e.canvas_rect.get_center()+Vector2(25,20)
	var before: Vector2=e._event_world_position(cursor)
	e._set_zoom(e.editor_camera.zoom.x*1.4,cursor)
	check("zoom_stays_anchored_with_side_panels",e._event_world_position(cursor).distance_to(before)<.1)
	e._set_layer(false,"scenery")
	var scenery_nodes: Array=overview.full_world.get_children().filter(func(node: Node)->bool:return node.get_script()==preload("res://scripts/world/coast_scenery.gd"))
	check("scenery_layer_applies_to_full_map_and_detail",not scenery_nodes.is_empty() and scenery_nodes.all(func(node: Node)->bool:return not node.visible) and not scene.ground.dealerships.visible)
	e._set_layer(true,"scenery");e._set_layer(false,"roads")
	check("hidden_roads_cannot_be_picked",e._pick_source_road(Vector2(3000,2800)*20).is_empty())
	e._set_layer(true,"roads");e._set_layer(true,"grid")
	check("grid_layer_is_available",e.gizmos.layer_flags.grid)
	e.source_id="road-0";e.source_anchor=1;e._refresh_authoring()
	var road: Dictionary=e.authoring.road_at_id("road-0").duplicate(true)
	var point:=Vector2(road.points[1].x,road.points[1].y)
	e.inspector_x.value=point.x+3
	check("inspector_moves_selected_road_point",is_equal_approx(float(e.authoring.road_at_id("road-0").points[1].x),point.x+3))
	e._undo()
	e.source_anchor=-1;e._refresh_authoring();e._nudge_selected(Vector2.RIGHT,true)
	check("nudge_moves_whole_road",is_equal_approx(float(e.authoring.road_at_id("road-0").points[0].x),float(road.points[0].x)+10))
	e._undo();e._duplicate_selected()
	check("duplicate_is_editable_and_undoable",e.authoring.doc.roads.size()==scene.ground.data.roads.size()+1 and e.source_id!="road-0")
	e._undo();e.source_id="road-0";e.source_anchor=-1;e._refresh_authoring()
	e.inspector_name.text="Workspace regression road";e._commit_inspector()
	check("name_property_commits_to_source_draft",e.authoring.road_at_id("road-0").name=="Workspace regression road")
	e._undo();e._discard_draft()
	e.entity_search.text="Foundry";e._refresh_entity_list(true)
	check("object_search_filters_authored_entities",e.entity_list.item_count>0 and e.entity_list.item_count<e.authoring.doc.roads.size())
	e._select_entity(0)
	check("object_list_selects_and_centers_the_map",not e.source_id.is_empty() and e.editor_camera.position.distance_to(e._record_position(e._selected_record())*20)<.01)
	var focus: Control=root.gui_get_focus_owner()
	if focus!=null:focus.release_focus()
	var space:=InputEventKey.new();space.keycode=KEY_SPACE;space.physical_keycode=KEY_SPACE;space.pressed=true
	Input.parse_input_event(space)
	await process_frame
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=e.canvas_rect.get_center()
	e._unhandled_input(click)
	check("space_drag_temporarily_pans_without_changing_tool",e._right_drag and e._space_pan and e.tool_name=="move_prop")
	click.pressed=false;e._input(click)
	var release: InputEventKey=space.duplicate();release.pressed=false;Input.parse_input_event(release)
	check("pan_capture_releases_over_ui",not e._right_drag and not e._space_pan)
	# Empty/missing archive assignments must keep the full-map fallback visible.
	var chunks: Dictionary=scene.ground.data.chunks
	scene.ground.data.chunks={};e.render_tiles.configure(extent*.5,Vector2(1280,720),.2)
	check("missing_detail_assignments_never_replace_overview_with_empty_view",not e.render_tiles.ready_to_show)
	scene.ground.data.chunks=chunks
	scene.queue_free();await process_frame;await process_frame
	OS.unset_environment("STREETBOUND_EDITOR_RECOVERY_PATH")
	var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	for i in 3:await process_frame
	e=game.native_world_editor
	if e==null:
		e=Native.new();e.world=game.ground;e.player=game.vehicle
		e.driving_camera=get_first_node_in_group("player_camera");e.traffic_network=game.ground.get_node("AmbientTraffic").network
		game.add_child(e)
	check("in_game_f6_editor_opens",e.open_editor())
	e._fit_map();await process_frame
	check("in_game_editor_also_keeps_full_map_rendered",e.overview_sprite.visible and e.overview_renderer.prop_count==game.ground.data.props.size())
	var original_chunks: Array=game.ground.chunks.values()
	check("gameplay_chunks_are_hidden_while_editor_renders",original_chunks.all(func(node: Node)->bool:return not node.visible))
	e._set_layer(false,"scenery");e.close_editor()
	check("leaving_editor_restores_gameplay_and_landmarks",not paused and game.ground.dealerships.visible and original_chunks.any(func(node: Node)->bool:return is_instance_valid(node) and node.visible))
	e.open_editor()
	check("reopening_editor_preserves_layer_selection",not game.ground.dealerships.visible and not e.overview_renderer.layer_flags.scenery)
	e.close_editor()
	check("real_map_and_source_files_are_unchanged",FileAccess.get_sha256("res://worlds/morrow-coast.world.json")==world_hash and FileAccess.get_sha256("res://map-editor/maps/morrow-coast.edits.world.json")==source_hash)
	game.queue_free();await process_frame;await process_frame
	print("NATIVE EDITOR WORKSPACE: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
