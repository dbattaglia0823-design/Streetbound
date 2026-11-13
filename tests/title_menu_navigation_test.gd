extends SceneTree
## Verify the actual ProjectSettings title entry and menu-to-game navigation.
## All existing direct scene tests still load main.tscn explicitly.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, value: bool) -> void:
	print("%s %s" % ["PASS" if value else "FAIL",label])
	if not value:
		failures.append(label)

func step(frames: int = 3) -> void:
	for i in frames:
		await process_frame

func enter_title() -> Node:
	var title: Node = load("res://scenes/title_menu.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await process_frame
	return title

func _run() -> void:
	check("project_boots_into_lightweight_title_scene",
		str(ProjectSettings.get_setting("application/run/main_scene")) ==
		"res://scenes/title_menu.tscn")
	var title: Node = await enter_title()
	check("title_has_play_map_editor_multiplayer_and_quit",
		title.play_button!=null and title.editor_button!=null and
		title.multiplayer_button!=null and title.get_node("StartMenuPanel")!=null)
	check("editor_access_follows_development_build_policy",
		title.editor_button.disabled != GameFlow.supports_native_editor())
	check("title_initially_does_not_load_real_world_or_pause",
		not paused and get_nodes_in_group("player_vehicle").is_empty())
	if Input.get_connected_joypads().is_empty():
		title.multiplayer_button.pressed.emit()
		await process_frame
		check("title_multiplayer_explains_missing_controller",
			current_scene==title and not title.feedback.text.is_empty())
	title.play_button.pressed.emit()
	for i in 7:
		await process_frame
	var game: Node = current_scene
	check("play_button_enters_actual_game_and_original_player",
		game!=null and game!=title and game.get("vehicle")!=null and
		not paused and game.vehicle.is_inside_tree())
	check("normal_play_does_not_start_split_or_native_editor",
		not game.local_split_screen.active and
		(game.native_world_editor == null or not game.native_world_editor.active))
	game.pause_menu.pause_game()
	check("pause_has_both_mode_buttons_plus_main_menu",
		paused and game.pause_menu.pause_screen.controls.has("map_editor") and
		game.pause_menu.pause_screen.controls.has("local_multiplayer") and
		game.pause_menu.pause_screen.controls.has("main_menu"))
	game.pause_menu.pause_screen.controls["main_menu"].pressed.emit()
	for i in 6:
		await process_frame
	title = current_scene
	check("return_to_title_unloads_world_without_leaving_game_paused",
		title!=null and title.name=="StreetboundMainMenu" and not paused and
		get_nodes_in_group("player_vehicle").is_empty())
	if GameFlow.supports_native_editor():
		title.editor_button.pressed.emit()
		for i in 8:
			await process_frame
		game = current_scene
		var editor: Variant = game.native_world_editor
		check("title_map_editor_opens_actual_godot_world",
			editor!=null and editor.active and paused and editor.root_ui.visible and
			not game.pause_menu.overlay.visible)
		editor.close_editor()
		check("test_drive_button_restores_normal_gameplay",
			not paused and not editor.active and
			game.get("vehicle") != null and game.vehicle.is_inside_tree())
		# The F6 shortcut was removed; only title/pause menu buttons open it.
		var f6 := InputEventKey.new()
		f6.keycode = KEY_F6
		f6.physical_keycode = KEY_F6
		f6.pressed = true
		root.push_input(f6)
		await process_frame
		check("f6_no_longer_reopens_native_map_editor",not editor.active)
		game.pause_menu.pause_game()
		game.pause_menu.pause_screen.controls["map_editor"].pressed.emit()
		await process_frame
		check("pause_map_editor_opens_and_restores_pause_visibility",
			editor.active and paused and not game.pause_menu.overlay.visible)
		editor.close_editor()
		check("exiting_editor_resumes_same_vehicle",not paused and
			game.vehicle != null and not game.local_split_screen.active)
		# Validate switching from multiplayer via the pause menu without
		# leaving two cameras active or duplicating the world.
		check("existing_multiplayer_manager_can_start_from_paused_context",
			game.local_split_screen.start_split([7]))
		game.pause_menu.set_split_screen_active(true)
		game.pause_menu.pause_game()
		game.pause_menu.pause_screen.controls["map_editor"].pressed.emit()
		await process_frame
		check("switching_from_split_to_editor_restores_single_camera",
			editor.active and not game.local_split_screen.active and
			get_nodes_in_group("local_multiplayer_vehicle").is_empty())
		editor.close_editor()
		# Returning home from active split-screen must release both car
		# cameras and world streaming before the new title scene loads.
		check("start_split_again_after_editor",game.local_split_screen.start_split([7]))
		game.pause_menu.set_split_screen_active(true)
		game.pause_menu.pause_game()
		game.pause_menu.pause_screen.controls["main_menu"].pressed.emit()
		for i in 6:
			await process_frame
		title = current_scene
		check("return_home_from_split_clears_second_car_and_pause",
			title!=null and title.name=="StreetboundMainMenu" and
			not paused and get_nodes_in_group("local_multiplayer_vehicle").is_empty())
	# The startup flow also handles a gamepad disappearing between title
	# selection and the moment the actual world finishes constructing.
	GameFlow.pending_mode = "multiplayer"
	var launch_game: Node = load("res://scenes/main.tscn").instantiate()
	current_scene.queue_free()
	root.add_child(launch_game)
	current_scene = launch_game
	for i in 7:
		await process_frame
	if Input.get_connected_joypads().is_empty():
		check("missing_controller_after_load_shows_pause_error",
			paused and not launch_game.local_split_screen.active and
			launch_game.pause_menu.overlay.visible and
			launch_game.pause_menu.pause_screen.controls["pause_heading"].text ==
				"CONNECT A GAMEPAD")
	else:
		check("connected_controller_from_title_starts_split",
			launch_game.local_split_screen.active and not paused)
	launch_game.queue_free()
	current_scene = null
	paused = false
	GameFlow.pending_mode = ""
	print("TITLE AND PAUSE NAVIGATION: ",
		"PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
