extends Control
## Shared, bottom-right race status strip with a touch-friendly restore button.
## The driving view stays clear; closing it never changes race state or physics.
const MAX_WIDTH := 342.0
const STRIP_HEIGHT := 70.0
const EDGE_MARGIN := 18.0

var panel: PanelContainer
var label: Label
var close_button: Button
var restore_button: Button
var dismissed := false
var _available := false
var _status_text := ""


func _ready() -> void:
	name = "CompactRaceStatus"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.name = "RaceStatusPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.075, 0.09, 0.88)
	style.border_color = Color(0.34, 0.77, 0.79, 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 12
	style.content_margin_right = 7
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var content := HBoxContainer.new()
	content.name = "RaceStatusRow"
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	label = Label.new()
	label.name = "RaceStatusText"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.max_lines_visible = 2
	content.add_child(label)
	close_button = Button.new()
	close_button.name = "CloseRaceStatus"
	close_button.text = "×"
	close_button.tooltip_text = "Hide race information (does not cancel the race)"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.flat = true
	close_button.pressed.connect(dismiss)
	content.add_child(close_button)
	restore_button = Button.new()
	restore_button.name = "ShowRaceStatus"
	restore_button.text = "RACE INFO"
	restore_button.tooltip_text = "Show race information"
	restore_button.focus_mode = Control.FOCUS_NONE
	restore_button.custom_minimum_size = Vector2(96, 28)
	restore_button.pressed.connect(restore)
	add_child(restore_button)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh_visibility()


func _layout() -> void:
	if panel == null or restore_button == null:
		return
	var viewport_size := get_viewport_rect().size
	# Dock under the top-right minimap. The car, road apex, central view,
	# driver progression and top map controls all remain unobstructed.
	var width_px := minf(MAX_WIDTH, maxf(170.0, viewport_size.x - 2.0 * EDGE_MARGIN))
	var left := maxf(8.0, viewport_size.x - width_px - EDGE_MARGIN)
	var top := maxf(8.0, viewport_size.y - STRIP_HEIGHT - EDGE_MARGIN)
	panel.position = Vector2(left, top)
	panel.size = Vector2(width_px, STRIP_HEIGHT)
	restore_button.position = Vector2(
		maxf(8.0, viewport_size.x - 96.0 - EDGE_MARGIN),
		maxf(8.0, viewport_size.y - 28.0 - EDGE_MARGIN))
	restore_button.size = Vector2(96, 28)


func set_status(phase: String, in_range: bool, message: String) -> void:
	# If the user closes an idle prompt, do NOT pop back up at the next
	# countdown. Only reset the preference after leaving the event area.
	if phase == "idle" and not in_range:
		dismissed = false
	_available = in_range or phase != "idle"
	if label != null:
		# Keep detailed result text readable in two compact lines.
		var lines := message.split("\n")
		if lines.size() > 2:
			message = lines[0] + "\n" + " / ".join(lines.slice(1))
		if _status_text != message:
			_status_text = message
			label.text = message
	_refresh_visibility()


func dismiss() -> void:
	dismissed = true
	_refresh_visibility()


func restore() -> void:
	dismissed = false
	_refresh_visibility()


func _other_ui_open() -> bool:
	if get_tree().paused:
		return true
	for map_hud in get_tree().get_nodes_in_group("streetbound_world_map_hud"):
		if bool(map_hud.get("large")):
			return true
		var driving: CanvasLayer = map_hud.get("driving_hud") as CanvasLayer
		if is_instance_valid(driving):
			var tuning: Control = driving.get("tuning") as Control
			if is_instance_valid(tuning) and tuning.visible:
				return true
	return false


func _refresh_visibility() -> void:
	if panel == null or restore_button == null:
		return
	var allowed := _available and not _other_ui_open()
	panel.visible = allowed and not dismissed
	restore_button.visible = allowed and dismissed


func _process(_dt: float) -> void:
	# The player can open Tab atlas or F1 settings without any race
	# state change, so suppress the strip and restore chip immediately.
	_refresh_visibility()


func _unhandled_input(event: InputEvent) -> void:
	if not _available or _other_ui_open() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and (key.keycode == KEY_H or
			key.physical_keycode == KEY_H):
		if dismissed:
			restore()
		else:
			dismiss()
		get_viewport().set_input_as_handled()
