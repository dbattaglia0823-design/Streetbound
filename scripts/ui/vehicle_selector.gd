extends CanvasLayer
## Drive-in garage selection. In Morrow Coast the player must park inside
## Laurel Motor House; proving ground keeps unrestricted testing access.
# Explicit script dependency: class_name lookups are not reliable before Godot imports.
const OwnershipModel = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const UpgradesScript = preload("res://scripts/ui/garage_upgrades.gd")
var player: VehicleController2D
var driving_hud: CanvasLayer
var pause_menu: CanvasLayer
var garage: Node2D
var inventory: OwnershipModel
var _access_clock := 0.0
var overlay: Control
var launch_button: Button
var scroll: ScrollContainer
var grid: GridContainer
var search: LineEdit
var title_label: Label
var upgrade_screen: Control
var cars_tab: Button
var upgrades_tab: Button
var active_tab := "cars"
var cards: Array[Dictionary] = []
var _thumb_cache: Dictionary = {}
var _thumb_clock := 0.0
var _paused_by_selector := false


func _ready() -> void:
	name = "VehicleSelector"
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	launch_button = Button.new()
	launch_button.name = "OpenVehicleSelector"
	launch_button.text = "GARAGE  [ G ]"
	launch_button.position = Vector2(410.0, 24.0)
	launch_button.custom_minimum_size = Vector2(330.0, 42.0)
	launch_button.pressed.connect(open_menu)
	add_child(launch_button)
	overlay = Control.new()
	overlay.name = "VehicleCatalogOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.04, 0.05, 0.94)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(backdrop)
	var frame := MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_left", 35)
	frame.add_theme_constant_override("margin_right", 35)
	frame.add_theme_constant_override("margin_top", 25)
	frame.add_theme_constant_override("margin_bottom", 25)
	overlay.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 13)
	frame.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var name_label := Label.new()
	name_label.text = "LAUREL MOTOR HOUSE  /  GARAGE"
	name_label.add_theme_font_size_override("font_size", 27)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(name_label)
	var close := Button.new()
	close.name = "CloseVehicleSelector"
	close.text = "BACK TO DRIVING   [ ESC ]"
	close.pressed.connect(close_menu)
	heading.add_child(close)
	var help := Label.new()
	help.text = "Owned vehicles only. Race to level cars; part rarity unlocks at car LV 10 / 20 / 30 / 40 / 50."
	help.add_theme_font_size_override("font_size", 14)
	column.add_child(help)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",9)
	column.add_child(tabs)
	cars_tab = Button.new()
	cars_tab.name = "CarsTab"
	cars_tab.text = "CARS / OWNED COLLECTION"
	cars_tab.custom_minimum_size = Vector2(230,43)
	cars_tab.pressed.connect(_show_tab.bind("cars"))
	tabs.add_child(cars_tab)
	if is_instance_valid(inventory):
		upgrades_tab = Button.new()
		upgrades_tab.name = "UpgradesTab"
		upgrades_tab.text = "UPGRADES / PART SLOTS"
		upgrades_tab.custom_minimum_size = Vector2(230,43)
		upgrades_tab.pressed.connect(_show_tab.bind("upgrades"))
		tabs.add_child(upgrades_tab)
	search = LineEdit.new()
	search.name = "VehicleSearch"
	search.placeholder_text = "Search manufacturer or model"
	search.custom_minimum_size.y = 39
	search.text_changed.connect(_apply_filter)
	column.add_child(search)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 13)
	column.add_child(title_label)
	scroll = ScrollContainer.new()
	scroll.name = "VehicleScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	grid = GridContainer.new()
	grid.name = "VehicleGrid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	if is_instance_valid(inventory):
		upgrade_screen = Control.new()
		upgrade_screen.set_script(UpgradesScript)
		upgrade_screen.set("economy",inventory)
		upgrade_screen.set("vehicle",player)
		upgrade_screen.set("driving_hud",driving_hud)
		upgrade_screen.visible = false
		column.add_child(upgrade_screen)
	for entry in Catalog.all():
		_create_card(entry)
	overlay.visible = false
	get_viewport().size_changed.connect(_layout_grid)
	_layout_grid()
	_update_garage_access()
	if is_instance_valid(inventory):
		inventory.changed.connect(_refresh_owned_cars)


func _create_card(entry: Dictionary) -> void:
	var button := Button.new()
	button.name = "Car_" + str(entry.id).replace("-", "_")
	button.custom_minimum_size = Vector2(210, 224)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = "%s  |  %.0f kg  |  %.0f kW  |  %s" % [
		str(entry.display_name), float(entry.mass_kg), float(entry.power_kw),
		str(entry.drivetrain)]
	button.pressed.connect(_choose.bind(entry))
	grid.add_child(button)
	var photo := TextureRect.new()
	photo.name = "Preview"
	photo.position = Vector2(12, 9)
	photo.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	photo.offset_left = 12.0
	photo.offset_right = -12.0
	photo.offset_top = 10.0
	photo.offset_bottom = 143.0
	photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(photo)
	var label := Label.new()
	label.name = "VehicleName"
	label.text = str(entry.display_name)
	label.position = Vector2(12, 151)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_left = 12
	label.offset_right = -12
	label.offset_top = -70
	label.offset_bottom = -38
	label.clip_text = true
	label.add_theme_font_size_override("font_size", 15)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	var note := Label.new()
	note.text = "LV %d/50  /  %s" % [
		inventory.level_for_car(str(entry.id)) if is_instance_valid(inventory) else 1,
		inventory.highest_upgrade_rarity(str(entry.id)).to_upper() if \
			is_instance_valid(inventory) else "UPGRADES LOCKED"]
	note.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	note.offset_left = 12
	note.offset_right = -12
	note.offset_top = -39
	note.offset_bottom = -13
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color("#a8bcab"))
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(note)
	cards.append({"button": button, "preview": photo, "entry": entry,
		"level_note":note})


func _layout_grid() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	grid.columns = maxi(2, floori((viewport_size.x - 90.0) / 232.0))
	launch_button.position = Vector2(minf(410.0, maxf(12.0, viewport_size.x - 350.0)), 24.0)


func _apply_filter(query: String) -> void:
	var needle := query.strip_edges().to_lower()
	var visible_count := 0
	for item in cards:
		var entry: Dictionary = item.entry
		var keep := (needle.is_empty() or needle in str(entry.display_name).to_lower()) and \
			(not is_instance_valid(inventory) or inventory.owns(str(entry.id)))
		(item.button as Button).visible = keep
		if keep:
			visible_count += 1
	title_label.text = "%d OWNED VEHICLES   /   CLICK TO DRIVE" % visible_count if \
		is_instance_valid(inventory) else "%d VEHICLES   /   CLICK TO DRIVE" % visible_count
	scroll.scroll_vertical = 0
	_thumb_clock = 10.0


func _refresh_owned_cars() -> void:
	if search != null:
		_apply_filter(search.text)
	if is_instance_valid(upgrade_screen):
		upgrade_screen.call("refresh")
	if is_instance_valid(inventory):
		for item in cards:
			var entry: Dictionary = item.entry
			(item.level_note as Label).text = "LV %d/50  /  %s" % [
				inventory.level_for_car(str(entry.id)),
				inventory.highest_upgrade_rarity(str(entry.id)).to_upper()]


func _show_tab(tab: String) -> void:
	if tab == "upgrades" and not is_instance_valid(upgrade_screen):
		return
	active_tab = tab
	var cars_visible := tab == "cars"
	search.visible = cars_visible
	title_label.visible = cars_visible
	scroll.visible = cars_visible
	if is_instance_valid(upgrade_screen):
		upgrade_screen.visible = not cars_visible
		if not cars_visible:
			upgrade_screen.call("refresh")
	cars_tab.disabled = cars_visible
	if is_instance_valid(upgrades_tab):
		upgrades_tab.disabled = not cars_visible


func _can_open_garage() -> bool:
	# The developer proving ground has no Morrow Coast building.
	return not is_instance_valid(garage) or garage.can_switch()


func _update_garage_access() -> void:
	if overlay == null or overlay.visible or launch_button == null:
		return
	if not is_instance_valid(garage):
		launch_button.visible = true
		launch_button.disabled = false
		launch_button.text = "VEHICLES  [ G ]"
		return
	var prompt_text: String = garage.prompt()
	launch_button.visible = not prompt_text.is_empty()
	launch_button.disabled = not garage.can_switch()
	if not prompt_text.is_empty():
		launch_button.text = prompt_text


func open_menu() -> void:
	if overlay.visible or get_tree().paused or not _can_open_garage():
		return
	_paused_by_selector = true
	get_tree().paused = true
	overlay.visible = true
	launch_button.visible = false
	search.clear()
	_apply_filter("")
	_refresh_owned_cars()
	_show_tab("cars")
	search.grab_focus()


func close_menu() -> void:
	if not overlay.visible:
		return
	overlay.visible = false
	_show_tab("cars")
	launch_button.visible = true
	get_viewport().gui_release_focus()
	_update_garage_access()
	if _paused_by_selector:
		get_tree().paused = false
	_paused_by_selector = false


func _choose(entry: Dictionary) -> void:
	if not _can_open_garage():
		return
	if is_instance_valid(inventory) and not inventory.owns(str(entry.id)):
		return
	if not Catalog.select(player, entry):
		return
	if is_instance_valid(inventory) and not inventory.equip(str(entry.id)):
		return
	if is_instance_valid(inventory):
		inventory.apply_car_upgrades(player.config,str(entry.id))
		player.on_upgrade_config_changed(0.0)
	var saved := ConfigFile.new()
	saved.set_value("vehicle", "selected_id", str(entry.id))
	saved.save("user://streetbound_selected_vehicle.cfg")
	if is_instance_valid(driving_hud) and driving_hud.has_method("on_vehicle_selected"):
		driving_hud.on_vehicle_selected(entry)
	close_menu()


func restore_selection() -> void:
	# Called after HUD initialization, so its stock tuning resources remain
	# valid and the selected car replaces only the active runtime instance.
	var selected_id := ""
	if is_instance_valid(inventory):
		selected_id = str(inventory.active_id)
	else:
		var file := ConfigFile.new()
		if file.load("user://streetbound_selected_vehicle.cfg") != OK:
			return
		selected_id = str(file.get_value("vehicle", "selected_id", ""))
	var entry := Catalog.find_by_id(selected_id)
	if not entry.is_empty() and Catalog.select(player, entry):
		if is_instance_valid(inventory):
			inventory.apply_car_upgrades(player.config,selected_id)
			player.on_upgrade_config_changed(0.0)
		if is_instance_valid(driving_hud) and driving_hud.has_method("on_vehicle_selected"):
			driving_hud.on_vehicle_selected(entry, true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("garage"):
		if overlay.visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()
	elif overlay.visible and (event.is_action_pressed("pause") or
			(event is InputEventKey and (event as InputEventKey).pressed and
			((event as InputEventKey).keycode == KEY_ESCAPE or
			(event as InputEventKey).physical_keycode == KEY_ESCAPE))):
		close_menu()
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if not overlay.visible:
		_access_clock -= dt
		if _access_clock <= 0.0:
			_access_clock = 0.12
			_update_garage_access()
		return
	if active_tab != "cars":
		return
	_thumb_clock += dt
	if _thumb_clock < 0.08:
		return
	_thumb_clock = 0.0
	var viewport_rect := scroll.get_global_rect().grow(250.0)
	var budget := 3
	for item in cards:
		var button: Button = item.button
		var preview: TextureRect = item.preview
		if not button.visible:
			preview.texture = null
			continue
		if not viewport_rect.intersects(button.get_global_rect()):
			preview.texture = null
			continue
		if preview.texture != null or budget <= 0:
			continue
		var path := str((item.entry as Dictionary).texture)
		if not _thumb_cache.has(path):
			var source := load(path) as Texture2D
			if source == null:
				continue
			var pixels := source.get_image()
			var rect := Catalog.alpha_bounds(pixels)
			if rect.size.x <= 4 or rect.size.y <= 4:
				continue
			var cropped := pixels.get_region(rect)
			var ratio := minf(200.0 / cropped.get_width(), 137.0 / cropped.get_height())
			cropped.resize(maxi(1, roundi(cropped.get_width() * ratio)),
				maxi(1, roundi(cropped.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
			_thumb_cache[path] = ImageTexture.create_from_image(cropped)
		preview.texture = _thumb_cache[path]
		budget -= 1
