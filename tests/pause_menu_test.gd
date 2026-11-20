extends SceneTree
## Exercises the real Game-Dev-Toolkit layout adapter and Streetbound callbacks.
## User settings are stored in the test process's isolated user:// folder.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(name: String, valid: bool) -> void:
	print("%s %s" % ["PASS" if valid else "FAIL", name])
	if not valid:
		failures.append(name)

func press_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	root.push_input(event)

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var pause = main.pause_menu
	check("pause_menu_instantiated", pause != null)
	if pause == null:
		quit(1)
		return
	check("unpaused_initially", not paused and not pause.overlay.visible)
	var map_hud: Variant = get_first_node_in_group("streetbound_world_map_hud")
	check("world_map_hud_available_without_f1_menu", map_hud != null)
	check("layout_source_from_toolkit", pause.pause_screen.controls.has("resume")
		and pause.pause_screen.controls.has("settings") and pause.pause_screen.controls.has("main_menu")
		and pause.pause_screen.controls.has("local_multiplayer")
		and pause.pause_screen.controls.has("map_editor") and pause.pause_screen.controls.has("quit")
		and pause.pause_screen.controls["resume"].get_meta("ui_action") == "game.resume"
		and pause.pause_screen.controls["main_menu"].get_meta("ui_action") == "nav.main_menu"
		and pause.pause_screen.controls["map_editor"].get_meta("ui_action") == "game.map_editor"
		and pause.pause_screen.controls["quit"].get_meta("ui_action") == "game.quit")
	# Regression for removed F1 input capture: the map's InputEventAction
	# must still toggle the atlas without reading HUD.waiting_action.
	var map_action := InputEventAction.new()
	map_action.action = "map"
	map_action.pressed = true
	if map_hud != null:
		root.push_input(map_action)
		await process_frame
		check("map_open_still_works_after_f1_removal", bool(map_hud.large))
		root.push_input(map_action)
		await process_frame
		check("map_close_still_works_after_f1_removal", not bool(map_hud.large))
	# Escape must travel through Godot's normal input system, not a direct method call.
	press_escape()
	await process_frame
	check("escape_pauses", paused and pause.overlay.visible and pause.menu_state == "paused")
	check("vehicle_frozen_while_paused", not main.vehicle.can_process())
	if map_hud != null:
		root.push_input(map_action)
		await process_frame
		check("map_toggle_is_blocked_while_paused", not bool(map_hud.large))
	check("pause_uses_left_menu_and_live_vehicle_panel",
		pause.pause_screen.controls["resume"].position.x < 100.0 and
		pause.vehicle_panel.visible and
		pause.vehicle_panel.get_node_or_null("EquippedCarPreview") == pause.vehicle_preview and
		pause.vehicle_name_label.text.length() > 0 and
		pause.vehicle_power_label.text.contains("HP") and
		pause.vehicle_drivetrain_label.text in ["FWD", "RWD", "AWD"] and
		pause.vehicle_level_label.text.contains("CAR LV"))
	var multiplayer_button: Button = pause.pause_screen.controls["local_multiplayer"]
	multiplayer_button.pressed.emit()
	await process_frame
	var online_button: Button = pause.multiplayer_screen.get_node("MultiplayerPanel/OnlineComingSoon")
	check("pause_multiplayer_has_local_and_disabled_online",
		paused and pause.menu_state == "multiplayer" and
		pause.local_split_button.visible and online_button.disabled and
		online_button.text.contains("COMING SOON"))
	press_escape()
	await process_frame
	check("multiplayer_escape_returns_to_pause_not_game",
		paused and pause.menu_state == "paused" and pause.pause_screen.visible)
	check("pause_menu_still_processes", pause.can_process())
	var settings_button: Button = pause.pause_screen.controls["settings"]
	settings_button.pressed.emit()
	await process_frame
	check("settings_open", paused and pause.menu_state == "settings"
		and pause.settings_screen.visible and not pause.pause_screen.visible)
	var volume: HSlider = pause.settings_screen.controls["volume_slider"]
	volume.value = 37.0
	await process_frame
	check("volume_applied_and_persisted", is_equal_approx(float(pause.settings_store.get_setting("volume")),37.0)
		and absf(AudioServer.get_bus_volume_db(0)-linear_to_db(0.37))<0.03)
	var sound: CheckBox = pause.settings_screen.controls["sfx_toggle"]
	sound.button_pressed = false
	await process_frame
	check("sound_toggle_applied", main.get_children().any(func(child: Node) -> bool:
		return child.get_script() == load("res://scripts/audio/vehicle_audio.gd") and bool(child.get("muted"))))
	var follow: CheckBox = pause.settings_screen.controls["camera_toggle"]
	follow.button_pressed = true
	await process_frame
	check("camera_toggle_applied", bool(pause.settings_store.get_setting("camera_follow")))
	# The one shape button shows the active value, applies immediately and
	# persists in the same settings store as volume and camera follow.
	var shape_button: Button = pause.settings_screen.controls["minimap_shape_button"]
	check("minimap_shape_setting_starts_square",
		shape_button.text == "Square" and
		str(pause.settings_store.get_setting("minimap_shape")) == "square" and
		map_hud != null and map_hud.mini_view.minimap_shape == "square")
	shape_button.pressed.emit()
	await process_frame
	check("shape_button_switches_to_circle_live",
		shape_button.text == "Circle" and
		str(pause.settings_store.get_setting("minimap_shape")) == "circle" and
		bool(map_hud.mini_mask.get_shader_parameter("circle_mode")) and
		(map_hud.mini.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a < .01 and
		map_hud.mini_view.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED)
	check("full_atlas_remains_rectangular",
		map_hud.full_view.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED)
	check("widescreen_stretch_expands_to_viewport",
		str(ProjectSettings.get_setting("display/window/stretch/aspect"))=="expand")
	var display: OptionButton=pause.display_mode_select
	check("settings_expose_three_display_modes",
		display.item_count==3 and display.visible and
		str(display.get_item_metadata(0))=="windowed" and
		str(display.get_item_metadata(1))=="borderless" and
		str(display.get_item_metadata(2))=="fullscreen")
	display.select(1);display.item_selected.emit(1)
	check("borderless_mode_is_applied_to_shared_settings",
		str(pause.settings_store.get_setting("display_mode"))=="borderless" and
		display.selected==1)
	display.select(2);display.item_selected.emit(2)
	var video_config:=ConfigFile.new()
	check("fullscreen_mode_persisted",
		str(pause.settings_store.get_setting("display_mode"))=="fullscreen" and
		video_config.load(pause.settings_store.path)==OK and
		str(video_config.get_value("settings","display_mode",""))=="fullscreen")
	pause._set_settings_tab("controls")
	check("display_options_hidden_on_controls_tab",
		not display.visible and not pause.display_mode_label.visible)
	pause._set_settings_tab("general")
	check("display_options_return_on_general_tab",display.visible and pause.display_mode_label.visible)
	display.select(0);display.item_selected.emit(0)
	check("windowed_mode_restored",
		str(pause.settings_store.get_setting("display_mode"))=="windowed" and display.selected==0)
	var stored := ConfigFile.new()
	check("circle_preference_saved_to_config",
		stored.load(pause.settings_store.path) == OK and
		str(stored.get_value("settings", "minimap_shape", "")) == "circle")
	shape_button.pressed.emit()
	await process_frame
	check("shape_button_switches_back_to_square",
		shape_button.text == "Square" and
		not bool(map_hud.mini_mask.get_shader_parameter("circle_mode")) and
		(map_hud.mini.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a > .9 and
		map_hud.mini_view.clip_children == CanvasItem.CLIP_CHILDREN_DISABLED)
	# Escape in Settings should go back to Pause, not unpause gameplay.
	press_escape()
	await process_frame
	check("escape_settings_back", paused and pause.menu_state == "paused" and pause.pause_screen.visible)
	pause.allow_quit = false # Prevent shutting down test runner when testing Quit.
	var exits := [0]
	pause.exit_requested.connect(func(): exits[0] += 1)
	var quit_button: Button = pause.pause_screen.controls["quit"]
	quit_button.pressed.emit()
	check("quit_action_connected", exits[0] == 1 and paused)
	var resume_button: Button = pause.pause_screen.controls["resume"]
	resume_button.pressed.emit()
	await process_frame
	check("resume_button_unpauses", not paused and pause.menu_state == "" and not pause.overlay.visible)
	press_escape()
	await process_frame
	check("escape_reopens_pause", paused and pause.menu_state == "paused")
	press_escape()
	await process_frame
	check("escape_resumes", not paused and not pause.overlay.visible)
	# Restore persistent defaults for the next local run.
	pause._handle_action("settings.volume_changed", {"value":80.0})
	pause._handle_action("settings.sfx_changed", {"value":true})
	pause._handle_action("settings.camera_changed", {"value":false})
	pause.settings_store.set_setting("minimap_shape", "square")
	pause._apply_minimap_shape()
	main.queue_free()
	paused = false
	print("PAUSE MENU TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
