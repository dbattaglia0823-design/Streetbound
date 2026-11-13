extends SceneTree
## Verify two real cars render through independent viewports in one physics
## world, each receives only its own assigned device, and exiting restores
## single-player camera/HUD/streaming. No hardware controller needed in CI.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL",label,str(detail)])
	if not passed:
		failures.append(label)

func key_event(code: int, down: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	return event

func motion_event(device_id: int, axis_id: int, amount: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device_id
	event.axis = axis_id
	event.axis_value = amount
	return event

func button_event(device_id: int, button_index: int, down: bool = true) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device_id
	event.button_index = button_index
	event.pressed = down
	return event

func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var manager: Variant = game.local_split_screen
	var p1: VehicleController2D = game.vehicle
	var world: Node2D = game.ground
	var original_camera: Camera2D = get_first_node_in_group("player_camera") as Camera2D
	check("original_single_player_starts_normally",
		manager != null and p1 != null and original_camera != null and
		not p1.external_input and not manager.active)
	if manager == null:
		quit(1)
		return
	game.pause_menu.pause_game()
	game.pause_menu._handle_action("game.local_multiplayer",{})
	check("menu_requires_a_real_controller",
		not manager.active and paused and
		game.pause_menu.pause_screen.controls["pause_heading"].text == "CONNECT A GAMEPAD")
	# Simulate one connected pad for deterministic CI; normal UI uses the
	# actual Input.get_connected_joypads() hardware list.
	var started: bool = manager.start_split([7])
	check("one_gamepad_and_keyboard_can_start",started and manager.active)
	if not started:
		quit(1)
		return
	game.pause_menu.set_split_screen_active(true)
	game.pause_menu.resume_game()
	var p2: VehicleController2D = manager.player_two
	check("player_two_uses_same_physics_and_world",
		p2 is VehicleController2D and p2.surface_provider == world and
		p2 != p1 and p1.external_input and p2.external_input)
	check("players_start_separated_with_unique_tuning_resources",
		p1.position.distance_to(p2.position) > 70.0 and
		p1.config != p2.config and
		p1.config.engine_power_kw == p2.config.engine_power_kw)
	check("two_independent_shared_world_viewports",
		manager.split_views.size()==2 and manager.split_cameras.size()==2 and
		manager.split_views[0].world_2d == game.get_viewport().world_2d and
		manager.split_views[1].world_2d == manager.split_views[0].world_2d and
		manager.split_cameras[0].target == p1 and manager.split_cameras[1].target == p2)
	check("split_hides_only_single_player_hud_and_camera",
		not original_camera.enabled and not game.quick_upgrades.visible and
		not game.progression_hud.visible and game.pause_menu.visible)
	check("one_pad_assigns_keyboard_p1_and_controller_p2",
		manager.player_one_controller==-1 and manager.player_two_controller==7)
	check("streamer_tracks_both_cars",
		world.secondary_stream_vehicle == p2)
	# Freeze vehicle physics to inspect commands without physical collisions.
	p1.set_physics_process(false)
	p2.set_physics_process(false)
	manager.route_input(key_event(KEY_W,true))
	manager._physics_process(1.0/60.0)
	check("keyboard_only_accelerates_player_one",
		manager.held[0]["throttle"]>0.9 and
		manager.held[1]["throttle"]==0.0 and
		p1.command.x>0.9 and p2.command.x==0.0)
	manager.route_input(motion_event(7,JOY_AXIS_TRIGGER_RIGHT,1.0))
	manager.route_input(motion_event(7,JOY_AXIS_LEFT_X,-0.85))
	manager._physics_process(1.0/60.0)
	check("gamepad_drives_player_two_only",
		p2.command.x>0.9 and p2.command.z < -0.7 and
		p1.command.z==0.0 and p1.command.x>0.9)
	manager.route_input(motion_event(7,JOY_AXIS_LEFT_X,0.0))
	manager.route_input(motion_event(7,JOY_AXIS_TRIGGER_RIGHT,0.0))
	manager.route_input(key_event(KEY_W,false))
	manager._physics_process(1.0/60.0)
	check("releasing_input_neutralizes_independent_cars",
		absf(p2.command.x)<0.01 and absf(p2.command.z)<0.01 and
		absf(p1.command.x)<0.01)
	var old_automatic: bool = p2.transmission.automatic
	manager.route_input(button_event(7,JOY_BUTTON_X))
	check("gear_mode_button_toggles_only_player_two",
		p2.transmission.automatic != old_automatic)
	# Split streaming keeps two 3x3 neighborhoods, including when one
	# player drives more than a chunk from the other.
	p2.position += Vector2(192.0*20.0*3.0,0)
	world.stream_at(p1.global_position)
	var second_cell: Vector2i = Vector2i(
		(p2.global_position/20.0/world.chunk_m).floor())
	check("far_apart_players_keep_both_streaming_centers",
		world.secondary_current_cell == second_cell and
		world.current_cell != second_cell and
		world.pending.has(second_cell))
	# Controller assignment is stable: device 99 cannot drive either car.
	manager._inputs()
	manager.route_input(motion_event(99,JOY_AXIS_TRIGGER_RIGHT,1.0))
	check("unassigned_controller_cannot_steal_vehicle",
		manager.held[0]["throttle"]==0.0 and
		manager.held[1]["throttle"]==0.0)
	game.pause_menu.pause_game()
	game.pause_menu._handle_action("game.local_multiplayer",{})
	await process_frame
	check("exit_restores_original_car_camera_and_huds",
		not manager.active and not p1.external_input and original_camera.enabled and
		game.quick_upgrades.visible and game.progression_hud.visible)
	check("second_car_and_extra_streamer_removed",
		not is_instance_valid(p2) and world.secondary_stream_vehicle==null)
	check("pause_exit_resumes_normal_single_player",
		not paused and not manager.screen_root.visible and
		game.pause_menu.pause_screen.controls["local_multiplayer"].text=="Local Split-Screen")
	# A pair of gamepads must never share one steering input stream.
	var two_pads: bool = manager.start_split([2,3])
	check("two_controller_configuration_starts",
		two_pads and manager.player_one_controller==2 and
		manager.player_two_controller==3)
	if two_pads:
		manager.route_input(motion_event(2,JOY_AXIS_TRIGGER_RIGHT,1.0))
		check("controller_one_cannot_move_player_two",
			manager.held[0]["throttle"]>0.9 and manager.held[1]["throttle"]==0.0)
		manager.stop_split()
	game.queue_free()
	print("LOCAL SPLIT SCREEN: ","PASS" if failures.is_empty() else
		"FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
