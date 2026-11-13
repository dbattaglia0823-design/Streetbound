extends SceneTree
## First native Map Editor milestone: the actual Morrow Coast render/road
## archive + Godot traffic network, not a JavaScript canvas or second world.
const NativeEditor = preload("res://scripts/dev/native_world_editor.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, valid: bool, evidence: Variant = "") -> void:
	print("%s %s %s" % ["PASS" if valid else "FAIL",label,str(evidence)])
	if not valid:
		failures.append(label)

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var world: Node = game.ground
	var player: VehicleController2D = game.vehicle
	var camera: Camera2D = get_first_node_in_group("player_camera") as Camera2D
	var editor: Variant = game.native_world_editor
	var real_network: Variant = world.get_node("AmbientTraffic").get("network")
	if editor == null:
		# Official non-editor headless binaries may not advertise debug mode.
		# Instantiate directly to exercise the same development-only script.
		editor = NativeEditor.new()
		editor.world = world
		editor.player = player
		editor.driving_camera = camera
		editor.traffic_network = real_network
		game.add_child(editor)
		await process_frame
	check("development_editor_is_available",editor!=null)
	check("editor_reuses_real_world_and_real_traffic_network",
		editor.world == world and editor.traffic_network == real_network and
		not real_network.edges.is_empty())
	var original_position := player.global_position
	var original_velocity := player.linear_velocity
	var original_gear := player.transmission.gear
	var original_camera_enabled := camera.enabled
	var source_roads: int = world.data.roads.size()
	var source_props: int = world.data.props.size()
	var original_physics := player.is_physics_processing()
	check("can_enter_from_unpaused_free_roam",editor.open_editor())
	check("dev_editor_pauses_real_game_and_shows_original_renderer",
		editor.active and paused and editor.root_ui.visible and
		editor.gizmos.visible and editor.editor_camera.is_current())
	check("editor_does_not_spawn_duplicate_game_world",
		get_nodes_in_group("player_vehicle").size()==1 and
		editor.gizmos.world == world and
		editor.editor_camera.get_viewport().world_2d == world.get_viewport().world_2d)
	check("driving_camera_inactive_during_inspection",
		not camera.enabled and not camera.is_physics_processing())
	check("native_editor_hides_player_overlay_without_touching_world_render",
		not game.quick_upgrades.visible and not game.progression_hud.visible and
		editor.gizmos.visible and editor.root_ui.visible)
	check("visualize_baked_junctions_and_real_turn_lane_connectors",
		editor.gizmos.show_junctions and editor.gizmos.show_lanes and
		editor.gizmos.network.connector_count>0)
	check("browser_map_files_remain_read_only_during_inspection",
		world.data.roads.size()==source_roads and
		world.data.props.size()==source_props)
	# Select a real collision/pavement polygon by its authoritative center.
	var target := -1
	for i in world.data.junctions.size():
		var j: Dictionary = world.data.junctions[i]
		var center := Vector2(float(j.p[0]),float(j.p[1]))
		if Geometry2D.is_point_in_polygon(center,world._junction_polygons[i]):
			target = i
			break
	check("baked_world_has_selectable_intersections",target>=0)
	if target >= 0:
		var junction: Dictionary = world.data.junctions[target]
		var pos := Vector2(float(junction.p[0]),float(junction.p[1]))*20.0
		var result: Dictionary = editor.select_at(pos)
		check("picking_finds_actual_baked_junction_index",
			result.get("kind","")=="junction" and int(result.get("index",-1))==target)
		check("junction_inspector_uses_real_connection_data",
			editor.details.text.contains("INTERSECTION") and
			editor.details.text.contains("Legal turn connectors"))
		editor.editor_camera.global_position = pos
		editor._update_view(true)
		check("editor_camera_streams_actual_morrow_coast_cells",
			world.current_cell == Vector2i((pos/20.0/float(world.chunk_m)).floor()))
	# Prop geometry comes from the same baked asset record used by game art.
	var prop_index := -1
	for i in world.data.props.size():
		var p: Dictionary = world.data.props[i]
		if p.has("size") and p.has("p") and p.has("kind"):
			prop_index = i
			break
	if prop_index>=0:
		editor._update_selection({"kind":"prop","index":prop_index})
		check("inspector_exposes_real_building_prop_assets",
			editor.details.text.contains("WORLD OBJECT") and
			editor.details.text.contains(str(world.data.props[prop_index].kind)))
	else:
		check("inspector_exposes_real_building_prop_assets",false)
	editor.lane_button.pressed.emit()
	editor.junction_button.pressed.emit()
	check("visual_lanes_and_junction_layers_independently_toggle",
		not editor.gizmos.show_lanes and not editor.gizmos.show_junctions)
	editor._recenter()
	check("center_on_car_restores_original_world_focus",
		editor.editor_camera.global_position.is_equal_approx(original_position))
	editor.close_editor()
	check("test_drive_restores_camera_and_unpauses_game",
		not editor.active and not paused and not editor.root_ui.visible and
		not editor.gizmos.visible and camera.enabled==original_camera_enabled)
	check("test_drive_restores_original_single_player_hud_visibility",
		game.quick_upgrades.visible and game.progression_hud.visible)
	check("test_drive_preserves_player_position_velocity_gear_and_simulation",
		player.global_position.is_equal_approx(original_position) and
		player.linear_velocity.is_equal_approx(original_velocity) and
		player.transmission.gear==original_gear and
		player.is_physics_processing()==original_physics)
	game.local_split_screen.active = true
	check("native_editor_refuses_to_interrupt_split_screen",
		not editor.open_editor() and not editor.active)
	game.local_split_screen.active = false
	check("editor_reentry_still_works_without_duplicate_cameras",editor.open_editor())
	editor.close_editor()
	check("editor_exit_does_not_change_source_archive_geometry",
		world.data.roads.size()==source_roads and
		world.data.props.size()==source_props)
	game.queue_free()
	paused = false
	print("NATIVE WORLD EDITOR FOUNDATION: ",
		"PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
