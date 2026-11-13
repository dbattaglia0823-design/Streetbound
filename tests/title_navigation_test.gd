extends SceneTree
## End-to-end player navigation: startup screen, shared settings, dev map
## editor, local multiplayer entry point, and return-to-title while paused.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL",label])
	if not passed:
		failures.append(label)

func _run() -> void:
	var launch_scene: PackedScene = load("res://scenes/title_menu.tscn")
	var title: Variant = launch_scene.instantiate()
	root.add_child(title)
	current_scene = title
	await process_frame
	check("project_starts_on_streetbound_title_menu",
		ProjectSettings.get_setting("application/run/main_scene") ==
			"res://scenes/title_menu.tscn" and
		title.actions.has("single_player") and title.actions.has("multiplayer") and
		title.actions.has("map_editor") and title.actions.has("settings") and
		title.actions.has("quit"))
	check("keyboard_and_controller_menu_buttons_focus",
		title.actions["single_player"].focus_mode==Control.FOCUS_ALL and
		title.actions["multiplayer"].focus_mode==Control.FOCUS_ALL)
	var dev: bool = OS.has_feature("debug") or OS.has_feature("editor")
	check("map_editor_is_dev_only_but_visible_at_startup",
		title.actions["map_editor"].visible and
		title.actions["map_editor"].disabled == not dev)
	title.actions["settings"].pressed.emit()
	await process_frame
	check("title_settings_use_existing_general_and_controls_tabs",
		paused and title.settings_adapter.menu_state=="settings" and
		title.settings_adapter.controls_tab_button != null and
		title.settings_adapter.settings_screen.visible)
	title.settings_adapter.controls_tab_button.pressed.emit()
	check("title_controls_tab_has_customizable_bindings",
		title.settings_adapter.settings_tab=="controls" and
		title.settings_adapter.binding_rows.size()>0)
	title.settings_adapter.back_to_pause()
	await process_frame
	check("title_settings_back_resumes_without_opening_game_pause_menu",
		not paused and title.settings_adapter.menu_state=="" and
		not title.settings_adapter.overlay.visible and title.visible)
	if Input.get_connected_joypads().is_empty():
		title.actions["multiplayer"].pressed.emit()
		check("multiplayer_requires_controller_without_changing_scenes",
			current_scene == title and
			title.message.text.contains("controller"))
	# Select Map Editor from the startup menu; this must enter the real
	# Morrow Coast runtime, not the browser or a disconnected preview.
	if dev:
		title.actions["map_editor"].pressed.emit()
		await process_frame
		await process_frame
		await process_frame
		var game: Variant = current_scene
		check("map_editor_title_launches_real_game_scene",
			game != null and game != title and game.has_method("_begin_native_map_editor") and
			game.ground.initialization_complete)
		if game != null and game != title:
			check("title_map_editor_button_enters_native_inspection_mode",
				game.native_world_editor != null and game.native_world_editor.active and paused)
			game.native_world_editor.close_editor()
			check("native_editor_exit_restores_gameplay",
				not paused and not game.native_world_editor.active)
			game.pause_menu.pause_game()
			await process_frame
			check("pause_has_multiplayer_editor_main_menu_and_quit",
				game.pause_menu.pause_screen.controls.has("local_multiplayer") and
				game.pause_menu.pause_screen.controls.has("map_editor") and
				game.pause_menu.pause_screen.controls.has("main_menu") and
				game.pause_menu.pause_screen.controls.has("quit"))
			check("native_pause_map_editor_available_outside_split_screen",
				not game.pause_menu.pause_screen.controls["map_editor"].disabled)
			game.pause_menu.pause_screen.controls["map_editor"].pressed.emit()
			await process_frame
			await process_frame
			check("pause_map_editor_enters_same_native_world_editor",
				game.native_world_editor.active and paused and
				not game.pause_menu.overlay.visible)
			game.native_world_editor.close_editor()
			game.pause_menu.pause_game()
			game.pause_menu.pause_screen.controls["main_menu"].pressed.emit()
			await process_frame
			await process_frame
			check("pause_main_menu_returns_to_title_without_quitting",
				current_scene != game and not paused and
				current_scene != null and current_scene.has_method("_activate") and
				current_scene.actions.has("multiplayer"))
	else:
		check("map_editor_in_release_build_is_intentionally_disabled",
			title.actions["map_editor"].disabled)
		print("Release test excludes native map editing by design.")
		title.queue_free()
	paused = false
	print("TITLE AND PAUSE NAVIGATION: ",
		"PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
