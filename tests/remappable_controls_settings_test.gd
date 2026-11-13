extends SceneTree
## End-to-end settings binding UI, input capture, persistent profiles and
## reserved Escape fallback. Test process has isolated user:// settings.
const ControlBindings = preload("res://scripts/input/controls.gd")
var controls: Variant
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, valid: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if valid else "FAIL",label,str(detail)])
	if not valid:
		failures.append(label)

func key_input(key_code: int) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = key_code
	event.physical_keycode = key_code
	root.push_input(event)

func mouse_input(button_index: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	event.position = Vector2.ZERO
	root.push_input(event)

func controller_button(button_index: int) -> void:
	var event := InputEventJoypadButton.new()
	event.pressed = true
	event.button_index = button_index
	event.device = 0
	root.push_input(event)

func controller_axis(index: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = index
	event.axis_value = value
	event.device = 0
	root.push_input(event)

func _run() -> void:
	controls = root.get_node_or_null("Controls")
	if controls == null:
		controls = ControlBindings.new()
		controls.name = "Controls"
		root.add_child(controls)
	controls.restore_defaults()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var menu: Variant = main.pause_menu
	check("original_driving_bindings_initialized",
		controls.binding_text("throttle","keyboard")=="W" and
		controls.binding("throttle","controller") is InputEventJoypadMotion)
	check("world_shortcuts_registered_as_real_actions",
		controls.ACTIONS.has("map") and controls.ACTIONS.has("garage") and
		controls.ACTIONS.has("upgrades") and controls.ACTIONS.has("pause"))
	menu.pause_game()
	menu.open_settings()
	check("settings_have_general_and_controls_tabs",
		menu.general_tab_button != null and menu.controls_tab_button != null and
		menu.settings_tab == "general" and
		menu.settings_screen.controls["sfx_toggle"].visible)
	menu.controls_tab_button.pressed.emit()
	check("controls_tab_replaces_general_settings",
		menu.settings_tab=="controls" and menu.controls_page.visible and
		not menu.settings_screen.controls["volume_slider"].visible and
		menu.binding_rows.size()==controls.ACTIONS.size())
	var brake_kb: Button = menu.binding_rows["brake"]["keyboard"]
	var brake_pad: InputEvent = controls.binding("brake","controller")
	brake_kb.pressed.emit()
	check("capture_prompt_appears",menu.capture_action=="brake" and
		menu.capture_device=="keyboard" and brake_kb.text.contains("PRESS KEY"))
	key_input(KEY_K)
	await process_frame
	check("keyboard_binding_captured_from_real_input",
		menu.capture_action=="" and controls.binding_text("brake","keyboard")=="K")
	check("changing_keyboard_preserves_brake_controller_axis",
		controls.binding("brake","controller") is InputEventJoypadMotion and
		(controls.binding("brake","controller") as InputEventJoypadMotion).axis ==
		(brake_pad as InputEventJoypadMotion).axis)
	var nitrous_pad: Button = menu.binding_rows["nitrous"]["controller"]
	nitrous_pad.pressed.emit()
	controller_button(JOY_BUTTON_RIGHT_STICK)
	await process_frame
	check("controller_button_can_be_remapped_independently",
		controls.binding("nitrous","controller") is InputEventJoypadButton and
		(controls.binding("nitrous","controller") as InputEventJoypadButton).button_index ==
		JOY_BUTTON_RIGHT_STICK and controls.binding_text("nitrous","keyboard")=="N")
	menu.binding_rows["left"]["controller"].pressed.emit()
	controller_axis(JOY_AXIS_RIGHT_X,-1.0)
	await process_frame
	check("controller_axis_and_direction_captured",
		controls.binding("left","controller") is InputEventJoypadMotion and
		(controls.binding("left","controller") as InputEventJoypadMotion).axis ==
		JOY_AXIS_RIGHT_X and
		(controls.binding("left","controller") as InputEventJoypadMotion).axis_value < 0.0)
	menu.binding_rows["throttle"]["keyboard"].pressed.emit()
	mouse_input(MOUSE_BUTTON_RIGHT)
	await process_frame
	check("mouse_button_can_replace_keyboard_input",
		controls.binding_text("throttle","keyboard")=="Mouse Right")
	# Restore W on throttle, then reassign Brake to W; this swaps Brake's
	# old K binding to Throttle instead of creating duplicate actions.
	menu.binding_rows["throttle"]["keyboard"].pressed.emit()
	key_input(KEY_W)
	await process_frame
	menu.binding_rows["brake"]["keyboard"].pressed.emit()
	key_input(KEY_W)
	await process_frame
	check("key_conflicts_swap_bindings_without_duplicate",
		controls.binding_text("brake","keyboard")=="W" and
		controls.binding_text("throttle","keyboard")=="K")
	var saved := ConfigFile.new()
	check("all_binding_categories_persisted_to_controls_config",
		saved.load("user://controls.cfg")==OK and
		saved.has_section_key("bindings","brake") and
		saved.has_section_key("bindings","nitrous") and
		(saved.get_value("bindings","nitrous") as Array).size()>=2)
	menu.binding_rows["mute"]["controller"].pressed.emit()
	key_input(KEY_BACKSPACE)
	await process_frame
	check("backspace_can_clear_controller_without_erasing_keyboard",
		controls.binding("mute","controller")==null and
		controls.binding_text("mute","keyboard")=="V")
	menu.binding_rows["mute"]["keyboard"].pressed.emit()
	key_input(KEY_BACKSPACE)
	await process_frame
	check("backspace_clears_only_selected_binding",
		controls.binding("mute","keyboard")==null and
		controls.binding("mute","controller")==null)
	menu.binding_rows["map"]["keyboard"].pressed.emit()
	key_input(KEY_ESCAPE)
	await process_frame
	check("escape_cancels_input_capture_without_unpausing",
		menu.capture_action=="" and menu.menu_state=="settings" and
		menu.settings_tab=="controls" and paused)
	menu.reset_bindings_button.pressed.emit()
	await process_frame
	check("restore_defaults_recovers_both_device_columns",
		controls.binding_text("throttle","keyboard")=="W" and
		controls.binding_text("brake","keyboard")=="S" and
		controls.binding("nitrous","controller") is InputEventJoypadButton and
		(controls.binding("nitrous","controller") as InputEventJoypadButton).button_index ==
		JOY_BUTTON_B)
	key_input(KEY_ESCAPE)
	await process_frame
	check("escape_from_controls_returns_to_general",
		menu.settings_tab=="general" and menu.menu_state=="settings" and paused)
	key_input(KEY_ESCAPE)
	await process_frame
	check("escape_from_general_returns_to_pause",
		menu.menu_state=="paused" and paused)
	menu.resume_game()
	check("pause_menu_resumes_and_does_not_leave_capture",
		not paused and menu.capture_action=="")
	main.queue_free()
	controls.restore_defaults()
	paused = false
	print("REMAP SETTINGS CONTROLS: ",
		"PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
