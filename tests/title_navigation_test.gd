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
	check("title_uses_new_streetbound_visuals_without_old_buttons",
		title.get_node_or_null("MenuBackground") != null and
		title.get_node_or_null("MenuShell/FeaturedVehicle") != null and
		not title.actions.has("garage") and
		not title.actions.has("customization") and
		title.actions["single_player"].text.contains("PLAY") and
		title.actions["map_editor"].text.contains("MAP BUILDER"))
	check("multiplayer_is_separate_page_not_direct_local_launch",
		title.main_page.visible and not title.multiplayer_page.visible)
	title.actions["multiplayer"].pressed.emit()
	check("multiplayer_page_has_local_and_friends_online",
		current_scene == title and title.multiplayer_page.visible and
		not title.main_page.visible and
		title.actions["local_multiplayer"].visible and
		title.actions["online_multiplayer"].visible and
		not title.actions["online_multiplayer"].disabled and
		title.actions["online_multiplayer"].text.contains("FRIENDS"))
	check("local_network_lobby_browser_offered_alongside_direct_friends",
		title.actions.has("lan_multiplayer") and
		not title.actions["lan_multiplayer"].disabled)
	title._activate("lan_multiplayer")
	check("lan_page_has_host_scan_join_and_back",
		title.lan_page.visible and not title.multiplayer_page.visible and
		title.actions.has("host_lan_game") and
		title.actions.has("scan_lan_games") and
		title.actions.has("join_lan_game") and title.lan_games != null)
	title._activate("lan_back")
	check("lan_back_restores_multiplayer_menu",
		title.multiplayer_page.visible and not title.lan_page.visible)
	title._activate("online_multiplayer")
	check("friends_online_page_can_host_or_join_without_auto_launch",
		current_scene == title and title.friends_page.visible and
		not title.multiplayer_page.visible and
		title.actions["host_friend_session"].visible and
		title.actions["join_friend_session"].visible and
		title.friend_port.text == str(OnlineSession.DEFAULT_PORT))
	title._activate("friends_back")
	if Input.get_connected_joypads().is_empty():
		title.actions["local_multiplayer"].pressed.emit()
		check("local_multiplayer_requires_controller_without_changing_scenes",
			current_scene == title and
			title.multiplayer_message.text.contains("controller"))
	title.actions["back"].pressed.emit()
	check("multiplayer_back_restores_main_menu",
		title.main_page.visible and not title.multiplayer_page.visible and
		title.actions["multiplayer"].has_focus())
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
	check("racing_settings_use_left_rail_and_context_panel",
		title.settings_adapter.general_tab_button.position.x < title.settings_adapter.settings_screen.controls["sfx_toggle"].position.x and
		title.settings_adapter.controls_tab_button.position.y > title.settings_adapter.general_tab_button.position.y and
		title.settings_adapter.settings_context.visible and title.settings_adapter.volume_readout.text.ends_with("%"))
	title.settings_adapter.settings_screen.controls["volume_slider"].focus_entered.emit()
	check("settings_context_tracks_focused_control",title.settings_adapter.context_title.text=="VOLUME")
	title.settings_adapter.controls_tab_button.pressed.emit()
	check("title_controls_tab_has_customizable_bindings",
		title.settings_adapter.settings_tab=="controls" and
		title.settings_adapter.binding_rows.size()>0)
	title.settings_adapter.back_to_pause()
	await process_frame
	check("title_settings_back_resumes_without_opening_game_pause_menu",
		not paused and title.settings_adapter.menu_state=="" and
		not title.settings_adapter.overlay.visible and title.visible)
	# Main-menu world editing now uses an isolated scene with no player,
	# racing AI, or game-physics chunks. Gameplay pause controls are separately
	# exercised by launching an ordinary game after leaving this scene.
	if dev:
		title.actions["map_editor"].pressed.emit()
		for frame in 4:
			await process_frame
		var standalone: Node = current_scene
		check("map_editor_title_launches_standalone_world_scene",
			standalone != null and standalone != title and
			standalone.has_method("_ready") and
			standalone.get("map_tiles") != null and
			standalone.ground.initialization_complete)
		var editor: CanvasLayer = standalone.native_world_editor
		check("title_map_editor_enters_native_editor_without_gameplay",
			editor != null and editor.active and not paused and
			standalone.ground.vehicle == null and
			standalone.get_node_or_null("Vehicle") == null and
			standalone.map_tiles.tiles.size() <= 64)
		for frame in 12:
			await process_frame
		var collision_free := true
		for tile in standalone.map_tiles.tiles.values():
			if not bool(tile.map_render_only) or is_instance_valid(tile.collider_body):
				collision_free = false
		check("camera_tiles_render_real_art_without_gameplay_collision",
			standalone.map_tiles.tiles.size() > 0 and collision_free)
		editor._fit_map()
		check("full_map_zoom_uses_whole_viewport_overview_without_detail_island",
			not standalone.map_tiles.detailed and
			standalone.map_tiles.tiles.is_empty() and
			editor.overview_sprite.visible)
		editor.close_editor()
		for frame in 3:
			await process_frame
		var returned_title: Control = current_scene
		check("standalone_editor_exits_to_title",
			returned_title != null and returned_title != standalone and
			returned_title.actions.has("single_player"))
		returned_title.actions["single_player"].pressed.emit()
		# The title now polls real asynchronous IO; fixed-fps tests can
		# advance thousands of simulation frames before the worker finishes.
		var deadline:=Time.get_ticks_msec()+30000
		while current_scene==returned_title and Time.get_ticks_msec()<deadline:
			await process_frame
			OS.delay_msec(1)
		for frame in 2:await process_frame
		var game: Variant = current_scene
		check("ordinary_gameplay_launches_after_standalone_editor",
			game != null and game != standalone and game!=returned_title and
			game.vehicle != null and game.ground.initialization_complete)
		if game != null and game != standalone and game!=returned_title:
			check("title_launch_consumes_exact_prepared_archive_once",bool(game.ground.prepared_archive_used) and bool(game.ground.prepared_geometry_used) and not has_meta("streetbound_prepared_archive"))
			game.pause_menu.pause_game()
			await process_frame
			check("pause_has_multiplayer_editor_main_menu_and_quit",
				game.pause_menu.pause_screen.controls.has("local_multiplayer") and
				game.pause_menu.pause_screen.controls.has("map_editor") and
				game.pause_menu.pause_screen.controls.has("main_menu") and
				game.pause_menu.pause_screen.controls.has("quit"))
			check("native_pause_map_editor_available_outside_split_screen",
				not game.pause_menu.pause_screen.controls["map_editor"].disabled)
			game.pause_menu.pause_screen.controls["main_menu"].pressed.emit()
			for frame in 3:
				await process_frame
			check("pause_main_menu_returns_to_title_without_quitting",
				current_scene != game and not paused and
				current_scene != null and current_scene.has_method("_activate") and
				current_scene.actions.has("multiplayer"))
	else:
		check("map_editor_in_release_build_is_intentionally_disabled",
			title.actions["map_editor"].disabled)
		print("Release test excludes native map editing by design.")
		if is_instance_valid(title):title.queue_free()
	paused = false
	print("TITLE AND PAUSE NAVIGATION: ",
		"PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
