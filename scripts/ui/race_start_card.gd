extends PanelContainer
## Compact on-location race entry. The production race remains the only owner
## of can_stage/start_race; this view never bypasses game or speed conditions.
signal hide_requested
const Preview = preload("res://scripts/ui/race_route_preview.gd")
const WIDTH := 338.0
var host: Node
var data: Dictionary = {}
var start_button: Button
var name_label: Label
var kind_label: Label
var distance_label: Label
var format_label: Label
var entry_label: Label
var rewards_label: Label
var best_label: Label
var description_label: Label
var hint_label: Label
var route_preview: Control
var close_button: Button

func _ready() -> void:
	name = "RaceStartSidePanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var skin := _style(Color("#091723", .96), Color("#f49a4d", .88))
	skin.content_margin_left = 12
	skin.content_margin_right = 12
	skin.content_margin_top = 10
	skin.content_margin_bottom = 10
	skin.shadow_color = Color(0, 0, 0, .34)
	skin.shadow_size = 11
	add_theme_stylebox_override("panel", skin)
	var body := VBoxContainer.new()
	body.name = "EventContent"
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	var title_row := HBoxContainer.new()
	title_row.name = "Header"
	body.add_child(title_row)
	var title := _label(title_row, "▦  RACE START", 17, Color("#ff9e53"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button = Button.new()
	close_button.name = "CloseRaceCard"
	close_button.text = "×"
	close_button.tooltip_text = "Hide event details (press H to restore)"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.custom_minimum_size = Vector2(28, 26)
	close_button.pressed.connect(func() -> void: hide_requested.emit())
	title_row.add_child(close_button)
	var hero := Control.new()
	hero.name = "RaceHeroGraphic"
	hero.clip_contents = true
	hero.custom_minimum_size = Vector2(0, 146)
	body.add_child(hero)
	route_preview = Control.new()
	route_preview.name = "LiveRaceRoute"
	route_preview.set_script(Preview)
	route_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(route_preview)
	# Apply full-rect anchors after parenting: otherwise the preview can
	# inherit viewport-sized offsets instead of the 146px hero frame.
	route_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.name = "TextLegibility"
	shade.color = Color("#06131d", .42)
	shade.position = Vector2.ZERO
	shade.size = Vector2(175, 146)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(shade)
	name_label = _label(hero, "STREET RACE", 20, Color("#f8f8f4"))
	name_label.position = Vector2(11, 11)
	name_label.size = Vector2(173, 84)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 3
	kind_label = _label(hero, "EVENT", 11, Color("#ffb879"))
	kind_label.position = Vector2(11, 109)
	kind_label.size = Vector2(173, 27)
	var facts := GridContainer.new()
	facts.columns = 2
	facts.name = "RaceFacts"
	facts.add_theme_constant_override("h_separation", 11)
	facts.add_theme_constant_override("v_separation", 4)
	body.add_child(facts)
	distance_label = _fact(facts, "DISTANCE")
	format_label = _fact(facts, "FORMAT")
	entry_label = _fact(facts, "ENTRY")
	rewards_label = _fact(facts, "REWARDS")
	best_label = _label(body, "BEST  —", 11, Color("#b8cad5"))
	best_label.custom_minimum_size.y = 17
	description_label = _label(body, "", 12, Color("#ced9dd"))
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.max_lines_visible = 2
	description_label.custom_minimum_size.y = 36
	description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	start_button = Button.new()
	start_button.name = "StartRaceButton"
	start_button.text = "START RACE   [F]"
	start_button.custom_minimum_size.y = 44
	start_button.add_theme_font_size_override("font_size", 16)
	start_button.add_theme_color_override("font_color", Color.WHITE)
	start_button.add_theme_color_override("font_disabled_color", Color("#b2bdc0"))
	start_button.add_theme_stylebox_override("normal", _style(Color("#ba531f"), Color("#ffa256")))
	start_button.add_theme_stylebox_override("hover", _style(Color("#da732a"), Color("#ffd092")))
	start_button.add_theme_stylebox_override("pressed", _style(Color("#87401d"), Color("#f6a66c")))
	start_button.add_theme_stylebox_override("disabled", _style(Color("#253441"), Color("#4b5f6c")))
	start_button.pressed.connect(_on_start)
	body.add_child(start_button)
	hint_label = _label(body, "F START   •   H HIDE", 10, Color("#9fb3c1"))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.custom_minimum_size.y = 19
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	visible = false

func _style(background: Color, outline: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = outline
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style

func _label(parent: Node, value: String, font_size: int, color: Color) -> Label:
	var item := Label.new()
	item.text = value
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_theme_color_override("font_color", color)
	item.add_theme_font_size_override("font_size", font_size)
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(item)
	return item

func _fact(parent: GridContainer, title: String) -> Label:
	var slot := VBoxContainer.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.add_theme_constant_override("separation", 0)
	parent.add_child(slot)
	_label(slot, title, 10, Color("#8fa8b8"))
	var value := _label(slot, "—", 14, Color("#ffffff"))
	value.custom_minimum_size.y = 23
	return value

func configure_event(race: Node, info: Dictionary) -> void:
	host = race
	data = info.duplicate(true)
	name_label.text = str(data.get("title", "Street Race"))
	kind_label.text = str(data.get("type", "Street Event")).to_upper()
	var distance: float = maxf(0.0, float(data.get("distance_m", 0.0)))
	distance_label.text = "%.2f MI" % (distance / 1609.344) if distance > 0.0 else "—"
	format_label.text = str(data.get("format", "Time Trial"))
	entry_label.text = str(data.get("entry", "FREE"))
	rewards_label.text = str(data.get("rewards", "PRACTICE"))
	description_label.text = str(data.get("description", "Complete the course."))
	var best: float = float(data.get("best_seconds", 0.0))
	best_label.text = "BEST  %.2fs" % best if best > 0.0 else "BEST  —"
	start_button.text = "START LAP   [F]" if bool(data.get("lap", false)) else "START RACE   [F]"
	var course: PackedVector2Array = data.get("route", PackedVector2Array())
	route_preview.call("set_course", course, bool(data.get("closed", false)))
	update_eligibility()

func update_eligibility() -> void:
	if not is_instance_valid(start_button):
		return
	# The one supported stored best is the persistent quarter-mile record.
	# Update it on revisiting the start instead of freezing the launch value.
	if data.has("best_seconds") and is_instance_valid(host):
		var economy: Object = host.get("economy") as Object
		if is_instance_valid(economy):
			var best_seconds: float = float(economy.get("best_quarter_mile"))
			best_label.text = "BEST  %.2fs" % best_seconds if best_seconds > 0.0 else "BEST  —"
	var can_start: bool = is_instance_valid(host) and host.has_method("can_stage") and not get_tree().paused
	if can_start:
		can_start = bool(host.call("can_stage"))
	start_button.disabled = not can_start
	hint_label.text = "F START   •   H HIDE" if can_start else "START ZONE  •  FACE ROUTE  •  15 MPH MAX"

func _on_start() -> void:
	if not is_instance_valid(host) or get_tree().paused:
		return
	if host.has_method("can_stage") and host.has_method("start_race"):
		if bool(host.call("can_stage")):
			host.call("start_race")
