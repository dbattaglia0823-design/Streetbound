extends CanvasLayer
## Temporary garage: browse every authored model, click once to drive it.
## Catalog membership is independent of ownership; economy comes later.
const Catalog = preload("res://scripts/vehicle/vehicle_catalog.gd")
const GAP := 12
const CARD_HEIGHT := 218.0
var vehicle: VehicleController2D
var driving_hud: CanvasLayer
var overlay: Control
var window: PanelContainer
var scroll: ScrollContainer
var grid: GridContainer
var counter: Label
var cards: Array[Dictionary] = []
var entries: Array[Dictionary] = []
var _owns_pause := false
var _cols := 4


func _panel_style(color: Color, stroke: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = stroke
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	entries = Catalog.all_vehicles()
	overlay = Control.new()
	overlay.name = "VehicleGridOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var shade := ColorRect.new()
	shade.name = "DimBackground"
	shade.color = Color(0.015, 0.026, 0.034, 0.87)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(shade)
	window = PanelContainer.new()
	window.name = "VehicleGridWindow"
	window.add_theme_stylebox_override("panel",
		_panel_style(Color(0.055, 0.091, 0.106, 0.99), Color("52706b"), 16))
	overlay.add_child(window)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	window.add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	var title := Label.new()
	title.text = "SELECT VEHICLE"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("edf4eb"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close_button := Button.new()
	close_button.name = "Close"
	close_button.text = "Close  [G]"
	close_button.custom_minimum_size = Vector2(120.0, 40.0)
	close_button.pressed.connect(close_menu)
	heading.add_child(close_button)
	counter = Label.new()
	counter.text = "%d vehicles  •  Click any car to drive it. Selection is free during testing." % entries.size()
	counter.add_theme_font_size_override("font_size", 14)
	counter.add_theme_color_override("font_color", Color("b3c6bc"))
	layout.add_child(counter)
	scroll = ScrollContainer.new()
	scroll.name = "VehicleScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layout.add_child(scroll)
	grid = GridContainer.new()
	grid.name = "VehicleGrid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	scroll.add_child(grid)
	for i in entries.size():
		_make_card(i)
	overlay.visible = false
	get_viewport().size_changed.connect(_layout)
	call_deferred("_layout")


func _make_card(index: int) -> void:
	var entry := entries[index]
	var button := Button.new()
	button.name = str(entry.id)
	button.clip_contents = true
	button.custom_minimum_size = Vector2(180.0, CARD_HEIGHT)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal",
		_panel_style(Color("14282e"), Color("415a59"), 9))
	button.add_theme_stylebox_override("hover",
		_panel_style(Color("223b42"), Color("b2d08b"), 9))
	button.add_theme_stylebox_override("pressed",
		_panel_style(Color("315046"), Color("c7e2ac"), 9))
	button.add_theme_stylebox_override("focus",
		_panel_style(Color("172f36"), Color("f1e8c7"), 9))
	button.pressed.connect(_select.bind(index))
	grid.add_child(button)
	var vertical := VBoxContainer.new()
	vertical.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vertical.add_theme_constant_override("separation", 3)
	vertical.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vertical.offset_left = 10
	vertical.offset_right = -10
	vertical.offset_top = 7
	vertical.offset_bottom = -7
	button.add_child(vertical)
	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(0, 133)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vertical.add_child(preview)
	var model := Label.new()
	model.name = "ModelName"
	model.text = "%s %s" % [str(entry.brand), str(entry.model)]
	model.add_theme_font_size_override("font_size", 14)
	model.add_theme_color_override("font_color", Color("f1f4ee"))
	model.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	model.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	model.custom_minimum_size.y = 36
	model.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vertical.add_child(model)
	var specs := Label.new()
	specs.text = "%d hp   •   %s" % [roundi(float(entry.engine_power_kw) * 1.34102),
		str(entry.drivetrain)]
	specs.add_theme_font_size_override("font_size", 12)
	specs.add_theme_color_override("font_color", Color("b4c8b5"))
	specs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	specs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vertical.add_child(specs)
	if not bool(entry.get("verified_model", false)):
		var pending := Label.new()
		pending.text = "Model name provisional"
		pending.add_theme_font_size_override("font_size", 10)
		pending.add_theme_color_override("font_color", Color("e4c68d"))
		pending.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pending.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vertical.add_child(pending)
	cards.append({"button": button, "preview": preview, "index": index})


func _layout() -> void:
	if not is_instance_valid(window):
		return
	var size := get_viewport().get_visible_rect().size
	var width := minf(1120.0, maxf(260.0, size.x - 32.0))
	var height := minf(780.0, maxf(220.0, size.y - 32.0))
	window.size = Vector2(width, height)
	window.position = (size - window.size) * 0.5
	_cols = clampi(floori((width - 35.0) / 212.0), 1, 5)
	grid.columns = _cols
	var cell_width := (width - 24.0 - float(_cols - 1) * GAP -
		float(25.0)) / float(_cols)
	for item in cards:
		(item.button as Button).custom_minimum_size.x = maxf(130.0, cell_width)


func _update_thumbnails() -> void:
	# Load at most one visible texture per frame. A 88-car gallery must not
	# force all full-resolution PNGs into GPU memory on opening.
	if not overlay.visible:
		return
	var top := float(scroll.scroll_vertical) - CARD_HEIGHT
	var bottom := float(scroll.scroll_vertical) + scroll.size.y + CARD_HEIGHT
	var loaded := false
	for item in cards:
		var button: Button = item.button
		var picture: TextureRect = item.preview
		var row_visible := button.position.y + button.size.y >= top and \
			button.position.y <= bottom
		if not row_visible and picture.texture != null:
			picture.texture = null
		elif row_visible and picture.texture == null and not loaded:
			picture.texture = load(str(entries[int(item.index)].texture)) as Texture2D
			loaded = true


func _process(_dt: float) -> void:
	_update_thumbnails()


func open_menu() -> void:
	if overlay.visible or get_tree().paused:
		return
	_owns_pause = true
	get_tree().paused = true
	overlay.visible = true
	_layout()
	_update_thumbnails()
	if not cards.is_empty():
		(cards[0].button as Button).grab_focus()


func close_menu() -> void:
	if not overlay.visible:
		return
	overlay.visible = false
	for item in cards:
		(item.preview as TextureRect).texture = null
	get_viewport().gui_release_focus()
	if _owns_pause:
		get_tree().paused = false
	_owns_pause = false


func toggle_menu() -> void:
	if overlay.visible:
		close_menu()
	else:
		open_menu()


func _select(index: int) -> void:
	if index < 0 or index >= entries.size():
		return
	if is_instance_valid(driving_hud) and driving_hud.has_method("_save_tuning_now"):
		driving_hud.call("_save_tuning_now")
	if is_instance_valid(vehicle) and vehicle.select_catalog_vehicle(entries[index]):
		close_menu()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_G or key.physical_keycode == KEY_G:
		if overlay.visible or not get_tree().paused:
			toggle_menu()
			get_viewport().set_input_as_handled()
	elif overlay.visible and (key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE):
		close_menu()
		get_viewport().set_input_as_handled()
