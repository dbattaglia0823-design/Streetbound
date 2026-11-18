extends Control
## Native, pause-safe Streetbound hub. Display values are drawn from the live
## vehicle, saved progression, map and actual race nodes; no invented payouts.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Progression = preload("res://scripts/vehicle/race_progression.gd")
const EventRules=preload("res://scripts/world/authored_event_rules.gd")
const RouteGraphic = preload("res://scripts/ui/race_route_preview.gd")
const DESIGN := Vector2(1440, 800)
const CAR_BATCH_SIZE := 18
const WHITE := Color("#f0f2e9")
const MUTED := Color("#a7bcb9")
const LIME := Color("#bee795")
const TEAL := Color("#77d6cc")
const DARK := Color("#091d22")
var menu
var vehicle: Node2D
var economy
var map_hud: Node
var upgrades: CanvasLayer
var section := "events"
var event_filter := "all"
var nav_buttons: Dictionary = {}
var filter_buttons: Dictionary = {}
var content: Control
var header_level: Label
var header_money: Label
var header_xp: ProgressBar
var driver_level: Label
var driver_xp_text: Label
var driver_xp: ProgressBar
var driver_balance: Label
var driver_district: Label
var car_image: TextureRect
var car_name: Label
var car_level: Label
var car_power: Label
var car_drive: Label
var car_grip: Label
var car_weight: Label
# The 244px driving minimap is too small to enlarge without blur.
var detail_render: SubViewport
var detail_view: Control
var map_image: TextureRect
var map_status: Label
var map_full_preview: TextureRect
var events_list: VBoxContainer
var event_rows: Array[Button] = []
# Rebuilt from the canonical vehicle catalog whenever Cars is opened.
var car_rows: Array[Dictionary] = []
var car_filtered: Array[Dictionary] = []
var car_row_parent: VBoxContainer
var car_load_more: Button
var car_search: LineEdit
var car_scroller: ScrollContainer
var car_count_label: Label
# Small, lazily created previews avoid loading all vehicle art on pause.
var car_thumbnail_cache: Dictionary = {}

func _ready() -> void:
	name = "StreetboundPauseHub"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = DESIGN
	_build_frame()
	# The high-resolution preview has no reason to render at initial startup.
	show_section("events")

func _skin(fill: Color, edge: Color, curve: int = 13) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(1)
	s.set_corner_radius_all(curve)
	return s

func _panel(parent: Control, node_name: String, rect: Rect2,
		fill: Color = Color("#102529"), edge: Color = Color("#54736d")) -> Panel:
	var p := Panel.new()
	p.name = node_name
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := _skin(fill, edge)
	style.shadow_color = Color(0.0, 0.0, 0.0, .25)
	style.shadow_size = 7
	p.add_theme_stylebox_override("panel", style)
	parent.add_child(p)
	return p

func _label(parent: Control, node_name: String, words: String, rect: Rect2,
		font_px: int = 15, tint: Color = WHITE, wrap_text: bool = false) -> Label:
	var l := Label.new()
	l.name = node_name
	l.text = words
	# Godot 4.4's fallback font reports roughly 3 pixels of line height
	# per requested font pixel in this project. Size to the available row
	# BEFORE parenting; later minimum-size changes cannot undo an expansion.
	var effective_px: int = font_px
	if int(Engine.get_version_info().get("minor", 6)) <= 4:
		effective_px = mini(font_px, maxi(5, floori((rect.size.y - 1.0) / 3.0)))
	l.add_theme_font_size_override("font_size", effective_px)
	l.position = rect.position
	l.add_theme_color_override("font_color", tint)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Never let multiline text paint behind the neighboring card.
	l.clip_text = true
	if wrap_text:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	# The fallback font in Godot 4.4 can report 3x the line height of 4.6.
	# A label must fit its allotted row rather than letting its theme
	# minimum paint across the next row or outside its panel.
	var minimum_height: float = l.get_combined_minimum_size().y
	if minimum_height > rect.size.y and rect.size.y > 0.0:
		var fitted_size: int = maxi(5, floori(effective_px * rect.size.y / minimum_height))
		l.add_theme_font_size_override("font_size", mini(effective_px, fitted_size))
	l.size = rect.size
	return l

func _button(parent: Control, node_name: String, title: String, rect: Rect2,
		action: Callable, emphasis: bool = false) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = title
	b.position = rect.position
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", DARK if emphasis else WHITE)
	b.add_theme_color_override("font_hover_color", DARK if emphasis else WHITE)
	b.add_theme_color_override("font_focus_color", DARK if emphasis else WHITE)
	b.add_theme_stylebox_override("normal", _skin(LIME if emphasis else Color("#183337"),
		LIME if emphasis else Color("#537873"), 10))
	b.add_theme_stylebox_override("hover", _skin(Color("#d4f5ab"), LIME, 10))
	b.add_theme_stylebox_override("pressed", _skin(Color("#9ac86a"), LIME, 10))
	var focused := _skin(Color.TRANSPARENT, Color("#f5e4ae"), 10)
	focused.draw_center = false
	focused.set_border_width_all(2)
	b.add_theme_stylebox_override("focus", focused)
	b.pressed.connect(action)
	parent.add_child(b)
	b.size = rect.size
	return b

func _build_frame() -> void:
	# Header, left category rail, central page, and three right-side cards.
	var header := _panel(self, "PauseHeader", Rect2(28, 18, 1382, 61),
		Color("#0b1e24", .89), Color("#465f5d"))
	_label(header, "Brand", "◢  STREETBOUND    /    PAUSED",
		Rect2(21, 4, 535, 53), 27, WHITE)
	var quick := _panel(header, "ProgressHeader", Rect2(934, 6, 426, 48),
		Color("#122d32"), Color("#5d857b"))
	header_level = _label(quick, "HeaderLevel", "DRIVER LV 1",
		Rect2(17, 4, 131, 20), 13)
	header_xp = _progress(quick, Rect2(152, 17, 119, 9))
	header_money = _label(quick, "HeaderMoney", "$ 0",
		Rect2(290, 5, 124, 36), 18, LIME)
	var rail := _panel(self, "Navigation", Rect2(28, 97, 210, 650),
		Color("#092227", .95), Color("#53766b"))
	_label(rail, "BrowseCaption", "EXPLORE", Rect2(18, 16, 177, 23), 12, LIME)
	var definitions := [
		["resume", "▷  Resume"], ["map", "⌖  Map"],
		["events", "⚑  Events"], ["cars", "▣  Cars"],
		["upgrades", "⚒  Upgrades"], ["settings", "⚙  Settings"],
		["quit", "↪  Quit"]
	]
	for i in definitions.size():
		var key: String = str(definitions[i][0])
		var button: Button = _button(rail, "Nav_" + key, str(definitions[i][1]),
			Rect2(13, 47 + i * 72, 184, 59), _navigate.bind(key))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("h_separation", 11)
		button.add_theme_font_size_override("font_size", 21)
		nav_buttons[key] = button
	var more := _button(rail, "NavMore", "•••  More", Rect2(13, 576, 184, 50),
		_navigate.bind("more"))
	more.alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav_buttons["more"] = more
	_panel(self, "ContentPanel", Rect2(250, 97, 781, 650),
		Color("#0a2227", .96), Color("#597971"))
	content = Control.new()
	content.name = "PageContent"
	content.position = Vector2(250, 97)
	content.size = Vector2(781, 650)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content)
	var driver := _panel(self, "DriverCard", Rect2(1043, 97, 367, 160),
		Color("#10292c", .96), Color("#5c7e73"))
	_label(driver, "DriverEyebrow", "DRIVER", Rect2(18, 7, 120, 24), 14, LIME)
	driver_level = _label(driver, "DriverLevel", "DRIVER LV 1",
		Rect2(18, 36, 162, 25), 17)
	driver_xp_text = _label(driver, "DriverXPText", "",
		Rect2(181, 37, 169, 22), 12, MUTED)
	driver_xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	driver_xp = _progress(driver, Rect2(18, 66, 332, 10))
	# ProgressBar has a minimum height greater than 10px; keep money below it.
	_label(driver, "CashCaption", "CASH", Rect2(18, 100, 125, 20), 12, MUTED)
	driver_balance = _label(driver, "DriverCash", "$0",
		Rect2(164, 100, 186, 23), 17, LIME)
	driver_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	driver_district = _label(driver, "DriverDistrict", "MORROW COAST",
		Rect2(18, 131, 332, 21), 13, WHITE)
	var car := _panel(self, "CurrentCarCard", Rect2(1043, 267, 367, 248),
		Color("#10292c", .96), Color("#5c7e73"))
	_label(car, "CurrentCarCaption", "CURRENT CAR", Rect2(18, 8, 194, 25), 14, LIME)
	var photo_background := ColorRect.new()
	photo_background.position = Vector2(18, 35)
	photo_background.size = Vector2(155, 108)
	photo_background.color = Color("#162b2d")
	car.add_child(photo_background)
	car_image = TextureRect.new()
	car_image.name = "EquippedCarImage"
	car_image.position = Vector2(22, 38)
	car_image.size = Vector2(147, 102)
	car_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	car_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	car_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car.add_child(car_image)
	car_name = _label(car, "CarName", "CURRENT VEHICLE",
		Rect2(190, 46, 159, 47), 20, WHITE, true)
	car_level = _label(car, "CarLevel", "CAR LV 1",
		Rect2(190, 106, 160, 25), 14, LIME)
	_label(car, "HorsepowerCaption", "HORSEPOWER", Rect2(18, 151, 150, 19), 12, MUTED)
	car_power = _label(car, "Horsepower", "—", Rect2(180, 151, 169, 19), 14)
	car_power.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(car, "DrivetrainCaption", "DRIVETRAIN", Rect2(18, 177, 150, 20), 12, MUTED)
	car_drive = _label(car, "Drivetrain", "—", Rect2(180, 177, 169, 20), 14)
	car_drive.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label(car, "GripCaption", "TIRE GRIP", Rect2(18, 203, 150, 20), 12, MUTED)
	car_grip = _label(car, "TireGrip", "—", Rect2(180, 203, 169, 20), 14)
	car_grip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	car_weight = _label(car, "Mass", "", Rect2(19, 227, 331, 18), 11, MUTED)
	var area := _panel(self, "AreaMapCard", Rect2(1043, 525, 367, 222),
		Color("#10292c", .96), Color("#5c7e73"))
	_label(area, "MapCaption", "AREA MAP — MORROW COAST",
		Rect2(16, 6, 244, 24), 13, LIME)
	var map_action := _button(area, "OpenMap", "OPEN MAP",
		Rect2(262, 6, 91, 27), _navigate.bind("map"))
	map_action.add_theme_font_size_override("font_size", 11)
	var map_bg := ColorRect.new()
	map_bg.position = Vector2(15, 39)
	map_bg.size = Vector2(337, 153)
	map_bg.color = Color("#1a3439")
	area.add_child(map_bg)
	map_image = TextureRect.new()
	map_image.name = "LiveLocalMap"
	map_image.position = Vector2(15, 39)
	map_image.size = Vector2(337, 153)
	# Crop for this wide slot; do not distort the map's native aspect ratio.
	map_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	map_image.clip_contents = true
	map_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	area.add_child(map_image)
	map_status = _label(area, "MapSource", "Live local streets", Rect2(19, 197, 331, 18),
		11, MUTED)
	_panel(self, "FooterBacking", Rect2(28, 753, 1382, 38),
		Color("#0b1e24", 0.93), Color("#465f5d"))
	_label(self, "FooterInstructions",
		"ESC  Back / Resume     •     ENTER  Select     •     Drive to an event to start",
		Rect2(42, 755, 940, 32), 13, MUTED)
	_label(self, "FooterBrand", "STREETBOUND  •  MORROW COAST",
		Rect2(1096, 755, 292, 32), 12, LIME)

func _build_detail_map() -> void:
	if is_instance_valid(detail_render):
		return
	if not is_instance_valid(map_hud) or not map_hud.has_method("map_view"):
		return
	# Compose the same live streets/road geometry into one crisp source.
	# 960x880 is about double the main map's display resolution.
	detail_render = SubViewport.new()
	detail_render.name = "PauseMapHighResolution"
	detail_render.size = Vector2i(960, 880)
	detail_render.disable_3d = true
	detail_render.transparent_bg = false
	detail_render.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(detail_render)
	detail_view = map_hud.call("map_view", detail_render, Vector2(960, 880), true) as Control
	if is_instance_valid(detail_view):
		# Map chunk streaming must continue while the game is paused.
		# Stream map chunks only while the pause hub is visible.
		detail_view.process_mode = Node.PROCESS_MODE_DISABLED
		detail_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Labels, navigation markers and the car cursor must stay readable
		# after the 2x map is downsampled into its on-screen cards.
		detail_view.set_meta("pause_render_density", 2.0)
		detail_view.ink.label_scale = 2.0
		detail_view.cursor.scale = Vector2(2.0, 2.0)
		detail_view.scale_bar.visible = false
	map_image.texture = detail_render.get_texture()


func set_render_active(active: bool) -> void:
	if active and not is_instance_valid(detail_render):
		_build_detail_map()
	if is_instance_valid(detail_render):
		detail_render.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED)
	if is_instance_valid(detail_view):
		detail_view.process_mode = (
			Node.PROCESS_MODE_ALWAYS if active else Node.PROCESS_MODE_DISABLED)


func _progress(parent: Control, bounds: Rect2) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = bounds.position
	# Hide the default percentage BEFORE sizing: otherwise Godot 4.4
	# holds its original 52px label-minimum height even for a slim bar.
	b.show_percentage = false
	# The progress label is hidden. A tiny font prevents Godot 4.4 from
	# reserving an invisible 52px text row inside this 10px meter.
	b.add_theme_font_size_override("font_size", 1)
	b.min_value = 0
	b.max_value = 1
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("background", _skin(Color("#354b49"), Color.TRANSPARENT, 3))
	b.add_theme_stylebox_override("fill", _skin(LIME, Color.TRANSPARENT, 3))
	parent.add_child(b)
	b.size = bounds.size
	return b

func _style_navigation() -> void:
	for key in nav_buttons:
		var button: Button = nav_buttons[key]
		var selected: bool = key == section
		button.add_theme_stylebox_override("normal",
			_skin(LIME if selected else Color.TRANSPARENT,
				Color("#e3f9b6") if selected else Color.TRANSPARENT, 11))
		button.add_theme_color_override("font_color", DARK if selected else WHITE)

func _navigate(destination: String) -> void:
	match destination:
		"resume":
			menu.resume_game()
		"settings":
			menu.open_settings()
		"quit":
			menu._handle_action("game.quit", {})
		_:
			show_section(destination)

func show_section(which: String) -> void:
	section = which if which in ["map", "events", "cars", "upgrades", "more"] else "events"
	_style_navigation()
	car_rows.clear()
	car_filtered.clear()
	car_search = null
	car_scroller = null
	car_count_label = null
	car_row_parent = null
	car_load_more = null
	set_process(section == "cars")
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	match section:
		"events":
			_show_events()
		"map":
			_show_map()
		"cars":
			_show_cars()
		"upgrades":
			_show_upgrades()
		"more":
			_show_more()

func refresh_on_open() -> void:
	_refresh_profile()
	_refresh_car()
	_refresh_map()
	show_section("events")

func _refresh_profile() -> void:
	if not is_instance_valid(economy):
		return
	var level: int = economy.player_level()
	var xp: int = economy.player_xp
	var start: int = Progression.player_threshold(level)
	var next_value: int = Progression.player_threshold(mini(level + 1, Progression.MAX_PLAYER_LEVEL))
	var current: int = maxi(0, xp - start)
	var total: int = maxi(1, next_value - start)
	var progress: float = Progression.player_level_progress(xp)
	header_level.text = "DRIVER LV %d" % level
	header_xp.value = progress
	header_money.text = "$ %s" % _money(int(economy.balance))
	driver_level.text = "DRIVER LV %d" % level
	driver_xp.value = progress
	driver_xp_text.text = "%d / %d XP" % [current, total] if level < Progression.MAX_PLAYER_LEVEL else "MAX LEVEL"
	driver_balance.text = "$ %s" % _money(int(economy.balance))
	var district_name := "MORROW COAST"
	if is_instance_valid(map_hud) and is_instance_valid(vehicle):
		var world: Node2D = map_hud.get("world") as Node2D
		if is_instance_valid(world) and world.has_method("location_at"):
			var location: Dictionary = world.call("location_at", vehicle.global_position)
			district_name = str(location.get("name", district_name))
	driver_district.text = "DISTRICT   /   " + district_name.to_upper()

func _money(value: int) -> String:
	var amount := str(maxi(0, value))
	var groups := ""
	while amount.length() > 3:
		groups = "," + amount.substr(amount.length() - 3, 3) + groups
		amount = amount.substr(0, amount.length() - 3)
	return amount + groups

func _refresh_car() -> void:
	if not is_instance_valid(vehicle):
		return
	var config: VehicleConfig = vehicle.get("config") as VehicleConfig
	if config == null:
		return
	var id: String = str(economy.active_id) if is_instance_valid(economy) else str(config.audio_sample_id)
	var entry: Dictionary = Catalog.find_by_id(id)
	car_name.text = str(entry.get("display_name", "CURRENT VEHICLE"))
	car_level.text = "CAR LV %d" % economy.active_car_level() if is_instance_valid(economy) else "FREE DRIVE"
	car_power.text = "%.0f HP" % (config.engine_power_kw * 1.341022)
	car_drive.text = ["FWD", "RWD", "AWD"][clampi(int(config.drivetrain), 0, 2)]
	car_grip.text = "%.2f μ" % config.tire_grip
	car_weight.text = "%.0f kg   •   %.0f Nm torque" % [config.mass_kg, config.engine_torque_nm]
	var path: String = str(entry.get("texture", ""))
	car_image.texture = load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path, "Texture2D") else null

func _refresh_map() -> void:
	if is_instance_valid(map_hud):
		if not is_instance_valid(detail_render):
			_build_detail_map()
		if is_instance_valid(detail_render):
			map_image.texture = detail_render.get_texture()
		if is_instance_valid(detail_view) and is_instance_valid(vehicle):
			detail_view.set("player_m", vehicle.global_position / 20.0)
			detail_view.set("player_heading", vehicle.rotation)
			detail_view.set("center_m", vehicle.global_position / 20.0)
			detail_view.call("redraw_map")
			# The HUD updates its normal mini/atlas race guidance separately.
			# Mirror the active race into this independent pause viewport too.
			var race_route: Node2D = detail_view.get("race_overlay") as Node2D
			if is_instance_valid(race_route) and map_hud.has_method("_active_race_navigation"):
				var course: RefCounted = map_hud.call("_active_race_navigation") as RefCounted
				race_route.call("set_guidance", course, vehicle, course != null)
		var waypoint: Node = map_hud.get("waypoints") as Node
		if is_instance_valid(waypoint) and bool(waypoint.get("active")):
			map_status.text = "GPS: " + str(waypoint.get("destination_name"))
		else:
			map_status.text = "Live local roads • select Map for navigation"

func _heading(eyebrow: String, headline: String, subtitle: String) -> void:
	_label(content, "PageEyebrow", eyebrow, Rect2(25, 15, 698, 24), 14, LIME)
	_label(content, "PageHeadline", headline, Rect2(25, 40, 727, 54), 31, WHITE)
	_label(content, "PageSubtitle", subtitle, Rect2(25, 94, 727, 32), 14, MUTED, true)

func _available_events() -> Array[Node]:
	var races: Array[Node] = []
	for race in get_tree().get_nodes_in_group("streetbound_race"):
		if is_instance_valid(race) and bool(race.get("available")):
			races.append(race)
	races.sort_custom(func(a: Node, b: Node) -> bool:
		var da: float = _distance_to_event(a)
		var db: float = _distance_to_event(b)
		return da < db if not is_equal_approx(da, db) else str(a.get("race_title")) < str(b.get("race_title")))
	return races

func _distance_to_event(race: Node) -> float:
	if not is_instance_valid(vehicle):
		return INF
	var location: Vector2 = race.get("start_m")
	return (location - vehicle.global_position / 20.0).length()

func _event_definition(race: Node) -> Dictionary:
	var value: Variant=race.get("definition")
	return value if value is Dictionary else {}

func _is_trial(race: Node) -> bool:
	var details: Dictionary=_event_definition(race)
	if not details.is_empty():
		return str(details.get("category",""))=="time_trial" or str(details.get("race_kind",""))=="time_trial"
	return "time trial" in str(race.get("race_type")).to_lower() or "circuit" in str(race.get("race_type")).to_lower()

func _matches_filter(race: Node) -> bool:
	match event_filter:
		"races":
			return not _is_trial(race) and str(_event_definition(race).get("category","street")) not in ["challenge","championship"]
		"trials":
			return _is_trial(race)
		"challenges":
			return str(_event_definition(race).get("category","")) in ["challenge","championship"]
	return true

func _show_events() -> void:
	filter_buttons.clear()
	_heading("EVENTS", "Race, Earn, and Build Your Rep",
		"Discover races, trials and career challenges. Select an event to set GPS.")
	var tabs := [["all", "All Events"], ["races", "Races"], ["trials", "Time Trials"], ["challenges", "Challenges"]]
	for i in tabs.size():
		var key: String = tabs[i][0]
		var button := _button(content, "Filter_" + key, str(tabs[i][1]),
			Rect2(24 + i * 136, 145, 130, 37), _set_event_filter.bind(key))
		button.add_theme_font_size_override("font_size", 14)
		filter_buttons[key] = button
	_label(content, "EventCount", "%d AVAILABLE" % _available_events().size(),
		Rect2(614, 151, 138, 27), 12, MUTED)
	var scroller := ScrollContainer.new()
	scroller.name = "EventScroller"
	scroller.position = Vector2(23, 198)
	scroller.size = Vector2(736, 422)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroller.mouse_filter = Control.MOUSE_FILTER_STOP
	content.add_child(scroller)
	events_list = VBoxContainer.new()
	events_list.name = "EventRows"
	events_list.custom_minimum_size.x = 714
	events_list.add_theme_constant_override("separation", 12)
	scroller.add_child(events_list)
	_populate_event_rows()

func _set_event_filter(value: String) -> void:
	event_filter = value
	_populate_event_rows()

func _populate_event_rows() -> void:
	if not is_instance_valid(events_list):
		return
	for child in events_list.get_children():
		events_list.remove_child(child)
		child.queue_free()
	event_rows.clear()
	for key in filter_buttons:
		var tab: Button = filter_buttons[key]
		var active: bool = str(key) == event_filter
		tab.add_theme_stylebox_override("normal", _skin(
			LIME if active else Color("#173137"),
			LIME if active else Color("#53766b"), 10))
		tab.add_theme_color_override("font_color", DARK if active else WHITE)
	var filtered: Array[Node] = []
	for race in _available_events():
		if _matches_filter(race):
			filtered.append(race)
	if filtered.is_empty():
		_label(events_list, "NoEvents",
			"No events in this category yet. Try another filter.",
			Rect2(14, 32, 694, 100), 18, MUTED, true)
		return
	for race in filtered:
		_event_card(race)

func _race_route(race: Node) -> PackedVector2Array:
	var navigator: RefCounted = race.get("navigation") as RefCounted
	if is_instance_valid(navigator):
		var data: Variant = navigator.get("points_m")
		if data is PackedVector2Array:
			return data
	var origin: Vector2 = race.get("start_m")
	var direction: Vector2 = race.get("direction")
	if direction.length_squared() > 0.5:
		return PackedVector2Array([origin, origin + direction * 402.336])
	return PackedVector2Array()

func _event_card(race: Node) -> void:
	var row := _button(events_list, "Event_" + str(race.get_instance_id()), "",
		Rect2(Vector2.ZERO, Vector2(714, 133)), _route_event.bind(race))
	row.custom_minimum_size = Vector2(714, 133)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.tooltip_text = "Set GPS to " + str(race.get("race_title"))
	row.add_theme_stylebox_override("normal", _skin(Color("#142e34"), Color("#608680"), 12))
	row.add_theme_stylebox_override("hover", _skin(Color("#244b4d"), LIME, 12))
	event_rows.append(row)
	var thumb := Control.new()
	thumb.name = "ActualRaceRouteGraphic"
	thumb.set_script(RouteGraphic)
	thumb.position = Vector2(8, 8)
	thumb.size = Vector2(205, 117)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(thumb)
	thumb.call("set_course", _race_route(race), _is_trial(race))
	var heading := str(race.get("race_title"))
	_label(row, "EventName", heading, Rect2(233, 12, 332, 31), 20)
	var definition: Dictionary=_event_definition(race)
	var label_type: String=str(race.get("race_type")).to_upper()
	if not definition.is_empty():
		label_type=str(definition.get("category","street")).to_upper()+"  /  "+str(definition.get("difficulty","rookie")).to_upper()
	_label(row, "EventType",label_type,
		Rect2(233, 43, 321, 20), 12, LIME)
	var navigator: RefCounted = race.get("navigation") as RefCounted
	var length_m := 402.336 if navigator == null else float(navigator.get("length_m"))
	var distance := _distance_to_event(race)
	_label(row, "EventDetails", "COURSE %.2f MI   •   %.1f MI AWAY" %
		[length_m / 1609.344, distance / 1609.344],
		Rect2(233, 70, 349, 23), 12, MUTED)
	_label(row, "SetDestination", "SELECT TO SET GPS",
		Rect2(233, 100, 335, 22), 12, TEAL)
	var is_rewarded: bool = race.get_script().resource_path.ends_with("/ashford_drag_race.gd")
	_label(row, "PayoutTitle", "REWARDS", Rect2(589, 30, 115, 19), 11, MUTED)
	var rewards := "XP + CASH" if is_rewarded else "PRACTICE"
	var note: String="VARIABLE" if is_rewarded else "NO PAYOUT"
	if not definition.is_empty():
		var wallet: Object=economy
		var world_id: String=str(race.get("world_id"))
		var wins: int=int(wallet.completed_event_count(EventRules.event_key(world_id,str(definition.id)))) if wallet!=null else 0
		var restriction: String=str(race.call("_lock_reason")) if race.has_method("_lock_reason") else ""
		rewards="LOCKED" if not restriction.is_empty() else "COMPLETED" if wins>0 and not bool(definition.get("repeatable",true)) else "CASH + XP"
		note="WIN %d"%wins if restriction.is_empty() else "SEE REQUIREMENTS"
		if not restriction.is_empty():
			row.tooltip_text=restriction+" / "+row.tooltip_text
		elif wins==0 and (int(definition.get("first_win_reward_cash",0))>0 or int(definition.get("first_win_reward_player_xp",0))>0):
			note="FIRST WIN BONUS"
	_label(row, "PayoutValue",rewards,Rect2(579, 56, 127, 28), 14, LIME)
	_label(row, "PayoutExplanation",note,Rect2(579, 87, 127, 20), 11, MUTED)

func _route_event(race: Node) -> void:
	if not is_instance_valid(race) or not is_instance_valid(map_hud):
		return
	var waypoints: Node = map_hud.get("waypoints") as Node
	if is_instance_valid(waypoints):
		waypoints.call("set_destination", race.get("start_m"), str(race.get("race_title")))
	_refresh_map()
	show_section("map")

func _show_map() -> void:
	_heading("MAP", "Explore Morrow Coast",
		"Preview the live road network. Choose an event to navigate to its starting marker.")
	_panel(content, "MapPreviewPanel", Rect2(24, 147, 493, 458),
		Color("#102b30"), Color("#577c73"))
	var preview := TextureRect.new()
	preview.name = "InteractiveAreaPreview"
	preview.position = Vector2(35, 157)
	# Without IGNORE_SIZE, TextureRect grows to the 960x880 source
	# texture's minimum size and spills outside the central map panel.
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.texture = map_image.texture
	preview.size = Vector2(471, 435)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	preview.clip_contents = true
	map_full_preview = preview
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(preview)
	_label(content, "MapOrientation", "N ↑   /   LIVE LOCAL STREETS",
		Rect2(45, 560, 280, 22), 12, LIME)
	_label(content, "MapHelp", "GPS DESTINATION", Rect2(534, 156, 207, 26), 13, LIME)
	var waypoint: Node = map_hud.get("waypoints") as Node if is_instance_valid(map_hud) else null
	var destination := "No waypoint selected"
	if is_instance_valid(waypoint) and bool(waypoint.get("active")):
		destination = str(waypoint.get("destination_name"))
	_label(content, "DestinationName", destination,
		Rect2(535, 187, 210, 56), 16, WHITE, true)
	_label(content, "DestinationHelp",
		"Choose an event to set GPS.\nResume to follow the route.",
		Rect2(535, 264, 204, 72), 13, MUTED, true)
	_button(content, "MapShowEvents", "BROWSE EVENTS",
		Rect2(535, 351, 207, 49), _navigate.bind("events"), true)
	var clear := _button(content, "ClearWaypoint", "CLEAR WAYPOINT",
		Rect2(535, 414, 207, 44), _clear_destination)
	clear.disabled = not is_instance_valid(waypoint) or not bool(waypoint.get("active"))
	_button(content, "FullAtlas", "OPEN FULL ATLAS",
		Rect2(535, 480, 207, 46), _open_full_atlas)

func _clear_destination() -> void:
	if is_instance_valid(map_hud):
		var waypoint: Node = map_hud.get("waypoints") as Node
		if is_instance_valid(waypoint):
			waypoint.call("clear_destination")
	_refresh_map()
	show_section("map")

func _open_full_atlas() -> void:
	if is_instance_valid(map_hud):
		menu.resume_game()
		map_hud.set("large", true)

## The same catalog and price keys used by the real dealership menu.
## No static car or dealership list is maintained by the pause UI.
static func _car_price_less(a: Dictionary, b: Dictionary) -> bool:
	var price_a := int(a.get("price_usd", 0))
	var price_b := int(b.get("price_usd", 0))
	if price_a != price_b:
		return price_a < price_b
	var name_a := str(a.get("display_name", "")).to_lower()
	var name_b := str(b.get("display_name", "")).to_lower()
	if name_a != name_b:
		return name_a < name_b
	return str(a.get("id", "")) < str(b.get("id", ""))


func _sorted_cars() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for entry in Catalog.all():
		entries.append(entry)
	entries.sort_custom(_car_price_less)
	return entries


func _car_dealership_site(entry: Dictionary) -> Dictionary:
	if not is_instance_valid(map_hud):
		return {}
	var world: Node2D = map_hud.get("world") as Node2D
	if not is_instance_valid(world):
		return {}
	var manager: Node2D = world.get("dealerships") as Node2D
	if not is_instance_valid(manager) or not manager.has_method("get_site"):
		return {}
	var dealer_id := str(entry.get("dealership_id", ""))
	if dealer_id.is_empty():
		return {}
	var site: Dictionary = manager.call("get_site", dealer_id)
	var parking: Variant = site.get("parking_m", [])
	return site if parking is Array and parking.size() == 2 else {}


func _show_cars() -> void:
	_heading("CARS", "Browse Every Car",
		"All showroom vehicles, cheapest first. Select a car to get GPS directions to its dealer.")
	car_search = LineEdit.new()
	car_search.name = "CarSearch"
	car_search.placeholder_text = "Search by car or dealership"
	car_search.position = Vector2(25, 150)
	car_search.size = Vector2(521, 42)
	car_search.add_theme_font_size_override("font_size", 16)
	content.add_child(car_search)
	car_count_label = _label(content, "CarCount", "",
		Rect2(562, 153, 190, 34), 12, LIME)
	car_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	car_scroller = ScrollContainer.new()
	car_scroller.name = "CarScroller"
	car_scroller.position = Vector2(24, 207)
	car_scroller.size = Vector2(735, 416)
	car_scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	car_scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	car_scroller.mouse_filter = Control.MOUSE_FILTER_STOP
	content.add_child(car_scroller)
	var rows := VBoxContainer.new()
	rows.name = "CarRows"
	rows.custom_minimum_size.x = 712
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 9)
	car_scroller.add_child(rows)
	car_row_parent = rows
	car_load_more = _button(rows, "CarLoadMore", "SHOW MORE CARS",
		Rect2(Vector2.ZERO, Vector2(710, 45)), _append_car_batch)
	car_load_more.custom_minimum_size = Vector2(710, 45)
	car_load_more.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	car_search.text_changed.connect(_filter_cars)
	_filter_cars("")


func _add_car_row(parent: VBoxContainer, entry: Dictionary) -> void:
	var site := _car_dealership_site(entry)
	var row := _button(parent, "Car_" + str(entry.get("id", "")).replace("-", "_"), "",
		Rect2(Vector2.ZERO, Vector2(710, 94)),
		_route_to_car_dealership.bind(str(entry.get("id", ""))))
	row.custom_minimum_size = Vector2(710, 94)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("normal", _skin(Color("#142e34"), Color("#608680"), 11))
	row.add_theme_stylebox_override("hover", _skin(Color("#244b4d"), LIME, 11))
	var thumbnail_back := ColorRect.new()
	thumbnail_back.position = Vector2(10, 9)
	thumbnail_back.size = Vector2(102, 76)
	thumbnail_back.color = Color("#203d42")
	thumbnail_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(thumbnail_back)
	var picture := TextureRect.new()
	picture.name = "CarPreview"
	picture.position = Vector2(13, 11)
	picture.size = Vector2(96, 72)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(picture)
	_label(row, "CarName", str(entry.get("display_name", "Unknown vehicle")),
		Rect2(122, 8, 375, 28), 18, WHITE)
	_label(row, "CarSpecs", "%.0f HP  •  %s  •  %s" % [
		float(entry.get("power_kw", 0.0)) * 1.341022,
		str(entry.get("drivetrain", "—")),
		str(entry.get("kind", "car")).to_upper()],
		Rect2(122, 36, 372, 21), 12, MUTED)
	var dealer_name := str(site.get("name", "Dealership unavailable"))
	_label(row, "CarDealer", dealer_name,
		Rect2(122, 61, 372, 23), 13, TEAL if not site.is_empty() else MUTED)
	var price := _label(row, "CarPrice", "$" + _money(int(entry.get("price_usd", 0))),
		Rect2(507, 8, 180, 30), 20, LIME)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var status := "AVAILABLE"
	if is_instance_valid(economy):
		if economy.owns(str(entry.get("id", ""))):
			status = "OWNED"
		elif not economy.can_buy_at_level(entry):
			status = "UNLOCK AT LV %d" % economy.required_player_level(entry)
		elif not economy.can_afford(entry):
			status = "SAVE UP TO BUY"
	var status_label := _label(row, "CarStatus", status,
		Rect2(501, 43, 186, 18), 12, MUTED)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var action := _label(row, "CarAction",
		"SET GPS TO DEALER" if not site.is_empty() else "NO DEALER FOUND",
		Rect2(503, 67, 184, 19), 12, TEAL)
	action.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.disabled = site.is_empty() or not is_instance_valid(map_hud) or \
		not is_instance_valid(map_hud.get("waypoints") as Node)
	row.tooltip_text = "Route to %s to find %s" % [
		dealer_name, str(entry.get("display_name", ""))] if not row.disabled else \
		"No active dealership location for this car"
	car_rows.append({"row": row, "entry": entry, "site": site,
		"photo": picture, "thumb_loaded": false})


func _filter_cars(query: String) -> void:
	if not is_instance_valid(car_count_label) or not is_instance_valid(car_row_parent):
		return
	var needle := query.strip_edges().to_lower()
	for item in car_rows:
		var old_row: Button = item.row
		car_row_parent.remove_child(old_row)
		old_row.queue_free()
	car_rows.clear()
	car_filtered.clear()
	for entry in _sorted_cars():
		var site := _car_dealership_site(entry)
		if needle.is_empty() or needle in str(entry.get("display_name", "")).to_lower() or \
				needle in str(site.get("name", "")).to_lower():
			car_filtered.append(entry)
	car_count_label.text = "%d / %d CARS" % [car_filtered.size(), Catalog.all().size()]
	car_scroller.scroll_vertical = 0
	_append_car_batch()


func _append_car_batch() -> void:
	if not is_instance_valid(car_row_parent) or not is_instance_valid(car_load_more):
		return
	var start := car_rows.size()
	var finish := mini(start + CAR_BATCH_SIZE, car_filtered.size())
	for index in range(start, finish):
		_add_car_row(car_row_parent, car_filtered[index])
	car_row_parent.move_child(car_load_more, car_row_parent.get_child_count() - 1)
	car_load_more.visible = finish < car_filtered.size()
	car_load_more.text = "SHOW MORE CARS  /  %d REMAINING" % (car_filtered.size() - finish)


func _route_to_car_dealership(id: String) -> void:
	var entry: Dictionary = Catalog.find_by_id(id)
	if entry.is_empty() or not is_instance_valid(map_hud):
		return
	var site := _car_dealership_site(entry)
	if site.is_empty():
		return
	var waypoints: Node = map_hud.get("waypoints") as Node
	if not is_instance_valid(waypoints):
		return
	var parking: Array = site.get("parking_m", [])
	var destination := Vector2(float(parking[0]), float(parking[1]))
	# Target the actual computed parking spot, not the authored approximate
	# location or the physical building center.
	if bool(waypoints.call("set_destination", destination, str(site.get("name", "")))):
		_refresh_map()
		show_section("map")


func _process(_dt: float) -> void:
	if section != "cars" or not is_visible_in_tree() or not is_instance_valid(car_scroller):
		return
	# Extend the row window when the player scrolls toward its end.
	if is_instance_valid(car_load_more) and car_load_more.visible:
		var bar: VScrollBar = car_scroller.get_v_scroll_bar()
		if bar.value + bar.page >= bar.max_value - 100.0:
			_append_car_batch()
	var visible_area := car_scroller.get_global_rect().grow(45.0)
	var budget := 2
	for item in car_rows:
		if budget <= 0:
			break
		var row: Button = item.row
		if not row.visible or not visible_area.intersects(row.get_global_rect()) or \
				bool(item.get("thumb_loaded", false)):
			continue
		item["thumb_loaded"] = true
		var entry: Dictionary = item.entry
		var path := str(entry.get("texture", ""))
		if path.is_empty() or not FileAccess.file_exists(path) or \
				not ResourceLoader.exists(path, "Texture2D"):
			continue
		if not car_thumbnail_cache.has(path):
			var source: Texture2D = load(path) as Texture2D
			if source == null:
				continue
			var image: Image = source.get_image()
			var bounds := Catalog.alpha_bounds(image)
			if bounds.size.x < 4 or bounds.size.y < 4:
				continue
			var cropped := image.get_region(bounds)
			var factor := minf(96.0 / float(cropped.get_width()),
				72.0 / float(cropped.get_height()))
			cropped.resize(maxi(1, roundi(cropped.get_width() * factor)),
				maxi(1, roundi(cropped.get_height() * factor)), Image.INTERPOLATE_LANCZOS)
			car_thumbnail_cache[path] = ImageTexture.create_from_image(cropped)
		(item.photo as TextureRect).texture = car_thumbnail_cache.get(path) as Texture2D
		budget -= 1


func _show_upgrades() -> void:
	_heading("UPGRADES", "Upgrade Your Ride",
		"Installed parts affect your active car. The existing upgrades screen remains available.")
	var card := _panel(content, "UpgradeInfo", Rect2(26, 161, 726, 356),
		Color("#10282d"), Color("#60776c"))
	_label(card, "UpgradeName", car_name.text,
		Rect2(24, 22, 657, 38), 26)
	_label(card, "UpgradePower", "POWER     " + car_power.text,
		Rect2(25, 75, 648, 32), 19, LIME)
	_label(card, "UpgradeGrip", "GRIP         " + car_grip.text,
		Rect2(25, 118, 648, 31), 18, MUTED)
	_label(card, "UpgradeTip", "Manage available performance parts in the workshop.\nChanges apply to the equipped vehicle.",
		Rect2(25, 183, 655, 62), 16, WHITE, true)
	var launch := _button(card, "LaunchUpgrades", "OPEN UPGRADES",
		Rect2(25, 280, 656, 50), _open_upgrades, true)
	launch.disabled = not is_instance_valid(upgrades)
	if launch.disabled:
		launch.tooltip_text = "The upgrade overlay is unavailable in this mode."

func _open_upgrades() -> void:
	if is_instance_valid(upgrades):
		menu.resume_game()
		upgrades.call("open_menu")

func _show_more() -> void:
	_heading("MORE", "Game Options",
		"Existing game modes and tools remain available from the pause hub.")
	var actions := [
		["MULTIPLAYER", "Local split-screen and online multiplayer status", "nav.multiplayer"],
		["MAP BUILDER", "Edit and test your world (development builds)", "game.map_editor"],
		["MAIN MENU", "Return to the Streetbound title screen", "nav.main_menu"]
	]
	for i in actions.size():
		var action: String = actions[i][2]
		var card := _panel(content, "MoreRow_%d" % i,
			Rect2(29, 164 + i * 113, 721, 98),
			Color("#143038"), Color("#5b7f77"))
		_label(card, "Description", str(actions[i][1]),
			Rect2(22, 54, 485, 29), 13, MUTED)
		var button := _button(card, "MoreAction", str(actions[i][0]),
			Rect2(20, 11, 674, 42), _more_action.bind(action))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if action == "game.map_editor":
			button.disabled = not bool(menu.map_editor_available) or bool(menu.split_screen_active)
	if is_instance_valid(menu.active_race()):
		var end_race := _button(content, "QuitRace", "QUIT CURRENT RACE",
			Rect2(30, 529, 713, 49), menu._quit_active_race)
		end_race.add_theme_color_override("font_color", Color("#f5bda6"))

func _more_action(action: String) -> void:
	menu._handle_action(action, {})
