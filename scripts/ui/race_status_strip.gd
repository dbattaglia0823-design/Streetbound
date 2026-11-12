extends Control
## Shared small race status strip. The driving view stays clear, and dismissing
## the strip never cancels a race or reopens it on the next physics frame.
const MAX_WIDTH := 432.0
const STRIP_HEIGHT := 54.0
const TOP_MARGIN := 12.0

var panel: PanelContainer
var label: Label
var close_button: Button
var restore_button: Button
var dismissed := false
var _last_phase := "idle"
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
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
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
	# Keep between left dashboard and right minimap at desktop widths.
	# Scale to a narrow viewport without relying on 1440x900 coordinates.
	var width_px := minf(MAX_WIDTH, maxf(170.0, viewport_size.x - 24.0))
	var left := maxf(8.0, (viewport_size.x - width_px) * 0.5)
	panel.position = Vector2(left, TOP_MARGIN)
	panel.size = Vector2(width_px, STRIP_HEIGHT)
	restore_button.position = Vector2(
		maxf(8.0, (viewport_size.x - 96.0) * 0.5), TOP_MARGIN)
	restore_button.size = Vector2(96, 28)


func set_status(phase: String, in_range: bool, message: String) -> void:
	# A NEW race may reopen the strip; a dismissed current race stays hidden.
	if phase == "countdown" and _last_phase != "countdown":
		dismissed = false
	_last_phase = phase
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


func _refresh_visibility() -> void:
	if panel == null or restore_button == null:
		return
	panel.visible = _available and not dismissed
	restore_button.visible = _available and dismissed
