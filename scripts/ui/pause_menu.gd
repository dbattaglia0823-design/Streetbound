extends CanvasLayer
## Streetbound adapter for Game-Dev-Toolkit's Functional UI v2 Pause/Settings
## templates and Godot layout renderer. Lives outside the paused world, so
## buttons, mouse, gamepad focus and Escape continue working when paused.
signal exit_requested

const ToolkitLayout = preload("res://addons/gdt/ui_layout.gd")
const ToolkitSettings = preload("res://addons/gdt/settings_store.gd")
const DESIGN_SIZE := Vector2(800.0, 500.0)

var vehicle_audio
var driving_camera
var allow_quit := true
var menu_state := ""
var settings_store

var overlay: Control
var pause_screen
var settings_screen
var background: ColorRect
var settings_tab := "general"
var general_tab_button: Button
var controls_tab_button: Button
var controls_page: Control
var bindings_list: VBoxContainer
var binding_rows: Dictionary = {}
var capture_action := ""
var capture_device := ""
var binding_feedback: Label
var reset_bindings_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	settings_store = ToolkitSettings.new("user://streetbound_pause_settings.cfg", {
		"sound": true,
		"volume": 80.0,
		"camera_follow": false,
		"minimap_shape": "square"
	})
	overlay = Control.new()
	overlay.name = "PauseOverlay"
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	background = ColorRect.new()
	background.name = "DimmedBackground"
	background.color = Color(0.025, 0.043, 0.053, 0.86)
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(background)

	pause_screen = _load_screen("res://assets/ui/pause-menu.layout.json", "PauseScreen")
	settings_screen = _load_screen("res://assets/ui/pause-settings.layout.json", "SettingsScreen")
	_build_settings_tabs()
	settings_screen.visible = false
	overlay.visible = false
	get_viewport().size_changed.connect(_resize_layout)
	_resize_layout()
	_apply_saved_settings()

func _load_screen(path: String, screen_name: String) -> Variant:
	var screen: Variant = ToolkitLayout.new()
	screen.name = screen_name
	overlay.add_child(screen)
	if not screen.load_from_file(path):
		push_error("Streetbound pause menu template could not be loaded: " + path)
		return screen
	screen.action_requested.connect(_handle_action)
	_style_screen(screen)
	return screen

func _style_screen(screen: Variant) -> void:
	for entry in screen.layout.get("nodes", []):
		if not entry is Dictionary:
			continue
		var id: String = str(entry.get("id", ""))
		var role: String = str(entry.get("role", ""))
		var node: Control = screen.controls.get(id)
		if node == null:
			continue
		if node is Panel:
			var panel_style := StyleBoxFlat.new()
			panel_style.bg_color = Color(0.055, 0.096, 0.109, 0.97)
			panel_style.border_color = Color(0.30, 0.43, 0.43, 0.78)
			panel_style.set_border_width_all(1)
			panel_style.set_corner_radius_all(20)
			node.add_theme_stylebox_override("panel", panel_style)
		elif node is Label:
			var label_node := node as Label
			label_node.add_theme_font_size_override("font_size", 40 if role == "screen_title" else 15)
			label_node.add_theme_color_override("font_color", Color("#eff3e8"))
			label_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		elif node is Button:
			var button := node as Button
			var primary: bool = role == "primary_action"
			var danger: bool = role == "danger_action"
			var normal := StyleBoxFlat.new()
			normal.bg_color = Color("#b3d18f") if primary else Color("#342b2c") if danger else Color("#1b3035")
			normal.border_color = Color("#b3d18f") if primary else Color("#9d686b") if danger else Color("#445c5c")
			normal.set_border_width_all(1)
			normal.set_corner_radius_all(11)
			var hover := normal.duplicate() as StyleBoxFlat
			hover.bg_color = Color("#c7e3a5") if primary else Color("#4d3839") if danger else Color("#29454b")
			var pressed := hover.duplicate() as StyleBoxFlat
			pressed.bg_color = Color("#91b26f") if primary else Color("#624044") if danger else Color("#15292c")
			var focus := StyleBoxFlat.new()
			focus.draw_center = false
			focus.border_color = Color("#e5edca")
			focus.set_border_width_all(2)
			focus.set_corner_radius_all(11)
			button.add_theme_stylebox_override("normal", normal)
			button.add_theme_stylebox_override("hover", hover)
			button.add_theme_stylebox_override("pressed", pressed)
			button.add_theme_stylebox_override("focus", focus)
			button.add_theme_color_override("font_color", Color("#132325") if primary else Color("#f0efe6"))
			button.add_theme_color_override("font_hover_color", Color("#132325") if primary else Color("#ffffff"))
			button.add_theme_color_override("font_pressed_color", Color("#132325") if primary else Color("#ffffff"))
			button.add_theme_font_size_override("font_size", 19)
			button.focus_mode = Control.FOCUS_ALL
		elif node is CheckBox:
			node.add_theme_color_override("font_color", Color("#e8eee4"))
			node.add_theme_font_size_override("font_size", 16)
		elif node is HSlider:
			node.add_theme_stylebox_override("slider", _track_style())
			node.add_theme_stylebox_override("grabber_area", _filled_track_style())

func _button_skin(button: Button, selected: bool = false) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#3a5048") if selected else Color("#1b3035")
	normal.border_color = Color("#b3d18f") if selected else Color("#445c5c")
	normal.set_border_width_all(2 if selected else 1)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#345551")
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color("#d6e6b9")
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",hover)
	button.add_theme_stylebox_override("pressed",hover)
	button.add_theme_stylebox_override("focus",focus)
	button.add_theme_color_override("font_color",Color("#f0efe6"))
	button.add_theme_color_override("font_hover_color",Color.WHITE)
	button.add_theme_font_size_override("font_size",13)
	button.focus_mode = Control.FOCUS_ALL
	button.clip_text = true


func _settings_label(parent: Control, text_value: String, at: Vector2,
		dimensions: Vector2, size_px: int = 13) -> Label:
	var node := Label.new()
	node.text = text_value
	node.position = at
	node.size = dimensions
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.add_theme_font_size_override("font_size",size_px)
	node.add_theme_color_override("font_color",Color("#e5efe5"))
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _build_settings_tabs() -> void:
	# Keep the original Toolkit layout as the General tab. The Controls tab
	# is a scrollable native Godot panel so it works with keyboard, mouse,
	# controller focus, and compact windows without a separate screen.
	controls_page = Control.new()
	controls_page.name = "ControlsTabContent"
	controls_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_screen.add_child(controls_page)
	general_tab_button = Button.new()
	general_tab_button.name = "GeneralTab"
	general_tab_button.text = "GENERAL"
	general_tab_button.position = Vector2(185,135)
	general_tab_button.size = Vector2(208,39)
	general_tab_button.pressed.connect(_set_settings_tab.bind("general"))
	settings_screen.add_child(general_tab_button)
	controls_tab_button = Button.new()
	controls_tab_button.name = "ControlsTab"
	controls_tab_button.text = "CONTROLS"
	controls_tab_button.position = Vector2(405,135)
	controls_tab_button.size = Vector2(208,39)
	controls_tab_button.pressed.connect(_set_settings_tab.bind("controls"))
	settings_screen.add_child(controls_tab_button)
	_settings_label(controls_page,"CONTROL",Vector2(171,180),Vector2(130,26),11)
	_settings_label(controls_page,"KEYBOARD / MOUSE",Vector2(307,180),Vector2(161,26),10)
	_settings_label(controls_page,"CONTROLLER",Vector2(476,180),Vector2(146,26),11)
	var scroller := ScrollContainer.new()
	scroller.name = "BindingsScroll"
	scroller.position = Vector2(166,210)
	scroller.size = Vector2(470,185)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroller.mouse_filter = Control.MOUSE_FILTER_STOP
	controls_page.add_child(scroller)
	bindings_list = VBoxContainer.new()
	bindings_list.name = "BindingsList"
	bindings_list.add_theme_constant_override("separation",5)
	bindings_list.custom_minimum_size.x = 440.0
	bindings_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(bindings_list)
	for action in Controls.ACTIONS:
		var row := HBoxContainer.new()
		row.name = "BindingRow_"+action
		row.custom_minimum_size.y = 40
		row.add_theme_constant_override("separation",6)
		bindings_list.add_child(row)
		var action_label := Label.new()
		action_label.text = str(Controls.LABELS.get(action,action.capitalize()))
		action_label.custom_minimum_size.x = 137
		action_label.add_theme_font_size_override("font_size",12)
		action_label.add_theme_color_override("font_color",Color("#e5efe5"))
		action_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		action_label.clip_text = true
		row.add_child(action_label)
		var kb := Button.new()
		kb.name = "Keyboard_"+action
		kb.custom_minimum_size = Vector2(144,36)
		kb.pressed.connect(_start_binding.bind(action,"keyboard"))
		_button_skin(kb)
		row.add_child(kb)
		var pad := Button.new()
		pad.name = "Controller_"+action
		pad.custom_minimum_size = Vector2(143,36)
		pad.pressed.connect(_start_binding.bind(action,"controller"))
		_button_skin(pad)
		row.add_child(pad)
		binding_rows[action] = {"keyboard":kb,"controller":pad}
	binding_feedback = _settings_label(controls_page,
		"Select a binding; Esc cancels, Backspace clears.",
		Vector2(169,396),Vector2(456,23),11)
	binding_feedback.clip_text = true
	reset_bindings_button = Button.new()
	reset_bindings_button.name = "RestoreDefaultBindings"
	reset_bindings_button.text = "RESTORE DEFAULTS"
	reset_bindings_button.position = Vector2(166,423)
	reset_bindings_button.size = Vector2(202,40)
	reset_bindings_button.pressed.connect(_restore_binding_defaults)
	_button_skin(reset_bindings_button)
	controls_page.add_child(reset_bindings_button)
	_set_settings_tab("general")


func _set_settings_tab(tab: String) -> void:
	if tab not in ["general","controls"]:
		return
	_cancel_capture(false)
	settings_tab = tab
	var general := tab == "general"
	for id in ["sfx_toggle","volume_label","volume_slider","camera_toggle",
			"minimap_shape_label","minimap_shape_button"]:
		var element: Control = settings_screen.controls.get(id)
		if is_instance_valid(element):
			element.visible = general
	controls_page.visible = not general
	_button_skin(general_tab_button,general)
	_button_skin(controls_tab_button,not general)
	var back: Button = settings_screen.controls.get("back")
	if is_instance_valid(back):
		back.position = Vector2(295,411) if general else Vector2(417,423)
		back.size = Vector2(210,46) if general else Vector2(213,40)
	if not general:
		_refresh_binding_buttons()


func _refresh_binding_buttons() -> void:
	if binding_rows.is_empty():
		return
	for action in Controls.ACTIONS:
		for kind in ["keyboard","controller"]:
			var button: Button = binding_rows[action][kind]
			var listening: bool = capture_action == str(action) and capture_device == kind
			button.text = ("PRESS KEY / MOUSE" if kind=="keyboard" else
				"PRESS CONTROLLER") if listening else Controls.binding_text(action,kind)
			button.tooltip_text = "Press to change the %s binding for %s" % [
				"keyboard/mouse" if kind=="keyboard" else "controller",
				str(Controls.LABELS.get(action,action))]
			_button_skin(button,listening)


func _start_binding(action: String, kind: String) -> void:
	capture_action = action
	capture_device = kind
	binding_feedback.text = "Press input for %s  ·  Esc cancel  ·  Backspace clear" % [
		str(Controls.LABELS.get(action,action))]
	_refresh_binding_buttons()
	get_viewport().gui_release_focus()


func _cancel_capture(reset_feedback: bool = true) -> void:
	capture_action = ""
	capture_device = ""
	if reset_feedback and is_instance_valid(binding_feedback):
		binding_feedback.text = "Select a binding; Esc cancels, Backspace clears."
	_refresh_binding_buttons()


func _restore_binding_defaults() -> void:
	_cancel_capture(false)
	if Controls.restore_defaults():
		binding_feedback.text = "Restored all keyboard, mouse and controller defaults."
	else:
		binding_feedback.text = "Could not save default bindings."
	_refresh_binding_buttons()


func _input(event: InputEvent) -> void:
	if menu_state != "settings" or settings_tab != "controls" or capture_action.is_empty():
		return
	var candidate: InputEvent
	if event is InputEventKey:
		var key: InputEventKey = event
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			_cancel_capture()
			get_viewport().set_input_as_handled()
			return
		if key.keycode in [KEY_BACKSPACE,KEY_DELETE] and capture_device == "keyboard":
			var cleared := Controls.clear_binding(capture_action,capture_device)
			binding_feedback.text = "Binding cleared." if cleared else "Could not clear binding."
			_cancel_capture(false)
			get_viewport().set_input_as_handled()
			return
		if capture_device == "keyboard":
			candidate = key
	elif event is InputEventMouseButton and capture_device == "keyboard":
		var mouse: InputEventMouseButton = event
		if mouse.pressed and mouse.button_index < MOUSE_BUTTON_WHEEL_UP:
			candidate = mouse
	elif event is InputEventJoypadButton and capture_device == "controller":
		var button_event: InputEventJoypadButton = event
		if button_event.pressed:
			candidate = button_event
	elif event is InputEventJoypadMotion and capture_device == "controller":
		var motion_event: InputEventJoypadMotion = event
		if absf(motion_event.axis_value) >= 0.7:
			candidate = motion_event
	if candidate == null:
		return
	var action := capture_action
	var result: Dictionary = Controls.rebind(action,capture_device,candidate)
	if str(result.get("status","")) == "bound":
		var exchanged := str(result.get("swapped_action",""))
		binding_feedback.text = ("Saved %s. Swapped with %s." % [
			str(Controls.LABELS.get(action,action)),
			str(Controls.LABELS.get(exchanged,exchanged))]) if exchanged != "" else (
			"Saved binding for %s." % str(Controls.LABELS.get(action,action)))
		_cancel_capture(false)
	else:
		binding_feedback.text = "Cannot assign that input. Try another button."
	_refresh_binding_buttons()
	get_viewport().set_input_as_handled()


func _track_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#283f42")
	style.set_corner_radius_all(7)
	return style

func _filled_track_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#aac987")
	style.set_corner_radius_all(7)
	return style

func _resize_layout() -> void:
	if overlay == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var available: Vector2 = Vector2(maxf(viewport_size.x - 20.0, 100.0), maxf(viewport_size.y - 20.0, 100.0))
	var factor: float = clampf(minf(available.x / DESIGN_SIZE.x, available.y / DESIGN_SIZE.y), 0.36, 1.45)
	var screen_position: Vector2 = (viewport_size - DESIGN_SIZE * factor) * 0.5
	for screen in [pause_screen, settings_screen]:
		if screen != null:
			screen.position = screen_position
			screen.scale = Vector2.ONE * factor

func _apply_saved_settings() -> void:
	var volume: float = clampf(float(settings_store.get_setting("volume")), 0.0, 100.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume / 100.0, 0.0001)))
	if is_instance_valid(vehicle_audio):
		vehicle_audio.muted = not bool(settings_store.get_setting("sound"))
	if is_instance_valid(driving_camera):
		driving_camera.follow_heading = bool(settings_store.get_setting("camera_follow"))
	_apply_minimap_shape()

func _apply_minimap_shape() -> void:
	var map_hud: Node = get_tree().get_first_node_in_group("streetbound_world_map_hud")
	if is_instance_valid(map_hud) and map_hud.has_method("set_minimap_shape"):
		map_hud.call("set_minimap_shape", str(settings_store.get_setting("minimap_shape")))


func _sync_settings() -> void:
	var sound: bool = bool(settings_store.get_setting("sound"))
	var camera_follow: bool = bool(settings_store.get_setting("camera_follow"))
	if is_instance_valid(vehicle_audio):
		sound = not vehicle_audio.muted
	if is_instance_valid(driving_camera):
		camera_follow = driving_camera.follow_heading
	settings_screen.set_data({"settings": {
		"sound": sound,
		"volume": float(settings_store.get_setting("volume")),
		"camera_follow": camera_follow,
		"minimap_shape": "Circle" if str(settings_store.get_setting("minimap_shape")) == "circle" else "Square"
	}})

func _show_page(page: String) -> void:
	menu_state = page
	overlay.visible = true
	pause_screen.visible = page == "paused"
	settings_screen.visible = page == "settings"
	if page == "settings":
		_sync_settings()
		_set_settings_tab("general")
	var active: Variant = pause_screen if page == "paused" else settings_screen
	var primary_id: String = "resume" if page == "paused" else "back"
	var focused: Button = active.controls.get(primary_id)
	if focused != null:
		focused.grab_focus()

func pause_game() -> void:
	if get_tree().paused:
		return
	get_tree().paused = true
	_show_page("paused")

func resume_game() -> void:
	overlay.visible = false
	menu_state = ""
	_cancel_capture()
	get_viewport().gui_release_focus()
	get_tree().paused = false

func open_settings() -> void:
	if not get_tree().paused:
		pause_game()
	_show_page("settings")

func back_to_pause() -> void:
	_show_page("paused")

func _request_quit() -> void:
	exit_requested.emit()
	if allow_quit:
		get_tree().quit()

func _handle_action(action_id: String, payload: Dictionary) -> void:
	match action_id:
		"game.resume":
			resume_game()
		"nav.settings":
			open_settings()
		"nav.back":
			back_to_pause()
		"game.quit":
			_request_quit()
		"settings.sfx_changed":
			var sound: bool = bool(payload.get("value", true))
			settings_store.set_setting("sound", sound)
			if is_instance_valid(vehicle_audio):
				vehicle_audio.muted = not sound
		"settings.volume_changed":
			var volume: float = clampf(float(payload.get("value", 80.0)), 0.0, 100.0)
			settings_store.set_setting("volume", volume)
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume / 100.0, 0.0001)))
		"settings.camera_changed":
			var enabled: bool = bool(payload.get("value", false))
			settings_store.set_setting("camera_follow", enabled)
			if is_instance_valid(driving_camera):
				driving_camera.follow_heading = enabled
		"settings.minimap_shape_toggle":
			var current: String = str(settings_store.get_setting("minimap_shape"))
			settings_store.set_setting("minimap_shape",
				"square" if current == "circle" else "circle")
			_apply_minimap_shape()
			_sync_settings()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
	var emergency_escape := event is InputEventKey and (
		(event as InputEventKey).keycode == KEY_ESCAPE or
		(event as InputEventKey).physical_keycode == KEY_ESCAPE)
	if not event.is_action_pressed("pause") and not emergency_escape:
		return
	get_viewport().set_input_as_handled()
	# A remapped Pause/Menu button also works on gamepads. Escape always
	# remains the fail-safe to reach the settings menu again.
	if get_tree().paused and menu_state.is_empty():
		return
	if not get_tree().paused:
		pause_game()
	elif menu_state == "settings" and settings_tab == "controls":
		_set_settings_tab("general")
	elif menu_state == "settings":
		back_to_pause()
	else:
		resume_game()
