extends Control
## Native, pause-safe Streetbound hub. Display values are drawn from the live
## vehicle, saved progression, map and actual race nodes; no invented payouts.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Progression = preload("res://scripts/vehicle/race_progression.gd")
const RouteGraphic = preload("res://scripts/ui/race_route_preview.gd")
const DESIGN := Vector2(1440, 800)
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

func _ready() -> void:
	name = "StreetboundPauseHub"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	size = DESIGN
	_build_frame()
	_build_detail_map()
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
	l.position = rect.position
	l.size = rect.size
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", tint)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Never let multiline text paint behind the neighboring card.
	l.clip_text = true
	if wrap_text:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l

func _button(parent: Control, node_name: String, title: String, rect: Rect2,
		action: Callable, emphasis: bool = false) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = title
	b.position = rect.position
	b.size = rect.size
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
		detail_view.process_mode = Node.PROCESS_MODE_ALWAYS
		detail_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Labels, navigation markers and the car cursor must stay readable
		# after the 2x map is downsampled into its on-screen cards.
		detail_view.set_meta("pause_render_density", 2.0)
		detail_view.ink.label_scale = 2.0
		detail_view.cursor.scale = Vector2(2.0, 2.0)
		detail_view.scale_bar.visible = false
	map_image.texture = detail_render.get_texture()


func set_render_active(active: bool) -> void:
	if is_instance_valid(detail_render):
		detail_render.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED)


func _progress(parent: Control, bounds: Rect2) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = bounds.position
	b.size = bounds.size
	b.min_value = 0
	b.max_value = 1
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("background", _skin(Color("#354b49"), Color.TRANSPARENT, 3))
	b.add_theme_stylebox_override("fill", _skin(LIME, Color.TRANSPARENT, 3))
	parent.add_child(b)
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
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	match section:
		"events":
			_show_events()
		"map":
			_show_map()
		"cars":
			_show_cars_wip()
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
		if is_instance_valid(detail_render):
			map_image.texture = detail_render.get_texture()
		if is_instance_valid(detail_view) and is_instance_valid(vehicle):
			detail_view.set("player_m", vehicle.global_position / 20.0)
			detail_view.set("player_heading", vehicle.rotation)
			detail_view.set("center_m", vehicle.global_position / 20.0)
			detail_view.call("redraw_map")
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

func _is_trial(race: Node) -> bool:
	return "time trial" in str(race.get("race_type")).to_lower() or "circuit" in str(race.get("race_type")).to_lower()

func _matches_filter(race: Node) -> bool:
	match event_filter:
		"races":
			return not _is_trial(race)
		"trials":
			return _is_trial(race)
		"challenges":
			return false # No authored challenge events yet.
	return true

func _show_events() -> void:
	filter_buttons.clear()
	_heading("EVENTS", "Race, Earn, and Build Your Rep",
		"Discover real races and time trials across Morrow Coast. Select an event to set GPS.")
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
	_label(row, "EventType", str(race.get("race_type")).to_upper(),
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
	_label(row, "PayoutValue", rewards, Rect2(579, 56, 127, 28), 14, LIME)
	_label(row, "PayoutExplanation", "VARIABLE" if is_rewarded else "NO PAYOUT",
		Rect2(579, 87, 127, 20), 11, MUTED)

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
	preview.size = Vector2(471, 435)
	preview.texture = map_image.texture
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

func _show_cars_wip() -> void:
	_heading("CARS", "Cars", "A dedicated vehicle collection is planned for a future update.")
	var shell := _panel(content, "CarsWorkInProgress", Rect2(46, 171, 687, 396),
		Color("#10282d"), Color("#60776c"))
	_label(shell, "WIPTitle", "WORK IN PROGRESS",
		Rect2(35, 120, 622, 74), 33, LIME)
	_label(shell, "WIPCopy", "The Cars tab is reserved for a future update.\nNo car management features are available here yet.",
		Rect2(35, 210, 610, 90), 17, WHITE, true)

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
