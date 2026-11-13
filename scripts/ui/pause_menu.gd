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
		if not key.pressed or key.echo or (key.keycode != KEY_ESCAPE and key.physical_keycode != KEY_ESCAPE):
			return
		get_viewport().set_input_as_handled()
		# The vehicle selector can also pause the scene. Do not treat its
		# Escape key as an unrelated Pause resume request.
		if get_tree().paused and menu_state.is_empty():
			return
		if not get_tree().paused:
			pause_game()
		elif menu_state == "settings":
			back_to_pause()
		else:
			resume_game()
