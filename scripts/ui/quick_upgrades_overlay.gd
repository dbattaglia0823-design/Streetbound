extends CanvasLayer
## In-game, anywhere-accessible six-slot quick swap overlay.
## The full eight-slot garage remains available for less common categories.
## This view uses real owned parts and changes live stats in place: no car
## respawn, lost momentum, gear reset or teleport during a hot swap.
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Parts = preload("res://scripts/vehicle/upgrade_parts.gd")
const Progress = preload("res://scripts/vehicle/race_progression.gd")
const DESIGN := Vector2(1180.0, 660.0)
const QUICK_SLOTS := ["engine","turbo","transmission","tires","suspension","nitrous"]
const SLOT_NAMES := {
	"engine":"ENGINE", "turbo":"TURBO", "transmission":"TRANSMISSION",
	"tires":"TIRES", "suspension":"SUSPENSION", "nitrous":"NITROUS"
}
const SLOT_ICONS := {
	"engine":"⚙", "turbo":"◉", "transmission":"⇄",
	"tires":"◎", "suspension":"↕", "nitrous":"✦"
}
const INK := Color("#e8eee9")
const SUBTLE := Color("#a5b8b2")
const ORANGE := Color("#ffa755")
var economy: Ownership
var vehicle: VehicleController2D
var launch_button: Button
var overlay: Control
var frame: Panel
var car_preview: TextureRect
var car_name: Label
var feedback: Label
var slot_buttons: Dictionary = {}
var slot_bars: Dictionary = {}
var picker: Panel
var picker_title: Label
var picker_status: Label
var picker_parts: VBoxContainer
var picker_remove: Button
var selected_slot := "engine"
var last_car_id := ""
var _owns_pause := false
var last_result := ""


func _ready() -> void:
	name = "QuickUpgradesOverlay"
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 18
	launch_button = Button.new()
	launch_button.name = "OpenQuickUpgrades"
	launch_button.text = "UPGRADES  [ U ]"
	launch_button.add_theme_font_size_override("font_size", 13)
	launch_button.custom_minimum_size = Vector2(190.0, 36.0)
	launch_button.pressed.connect(open_menu)
	_style_button(launch_button, false)
	add_child(launch_button)
	overlay = Control.new()
	overlay.name = "QuickUpgradeBackdrop"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var dimmer := ColorRect.new()
	dimmer.name = "WorldDimmer"
	dimmer.color = Color(0.01,0.02,0.025,0.34)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dimmer)
	frame = Panel.new()
	frame.name = "UpgradeFrame"
	frame.size = DESIGN
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.add_theme_stylebox_override("panel", _panel_style(
		Color(0.04,0.055,0.064,0.88), Color(0.45,0.51,0.52,0.92), 1, 16))
	overlay.add_child(frame)
	_build_layout()
	overlay.visible = false
	get_viewport().size_changed.connect(_resize)
	_resize()
	if is_instance_valid(economy):
		economy.changed.connect(refresh)
	refresh()


func _panel_style(background: Color, edge: Color, width: int, rounding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_corner_radius_all(rounding)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _label(parent: Node, value: String, font_size: int, color: Color,
		at: Vector2, dimensions: Vector2) -> Label:
	var node := Label.new()
	node.text = value
	node.position = at
	node.size = dimensions
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",color)
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.clip_text = true
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _style_button(node: Button, selected: bool) -> void:
	var edge := ORANGE if selected else Color(0.55,0.63,0.62,0.65)
	var normal := _panel_style(Color(0.075,0.095,0.105,0.86),edge,
		2 if selected else 1, 9)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16,0.19,0.20,0.95)
	hover.border_color = ORANGE
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.28,0.18,0.12,0.95)
	node.add_theme_stylebox_override("normal",normal)
	node.add_theme_stylebox_override("hover",hover)
	node.add_theme_stylebox_override("pressed",pressed)
	node.add_theme_stylebox_override("focus",hover)
	node.add_theme_color_override("font_color",INK)
	node.add_theme_color_override("font_hover_color",Color.WHITE)
	node.add_theme_color_override("font_pressed_color",INK)
	node.focus_mode = Control.FOCUS_ALL


func _make_button(parent: Node, title: String, at: Vector2,
		dimensions: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.position = at
	button.size = dimensions
	button.pressed.connect(action)
	_style_button(button,false)
	parent.add_child(button)
	return button


func _build_layout() -> void:
	_label(frame,"╱╱  UPGRADES",31,INK,Vector2(38,24),Vector2(295,50))
	_label(frame,"↔  HOT SWAP OWNED PARTS ANYWHERE",14,
		SUBTLE,Vector2(342,30),Vector2(540,40))
	_make_button(frame,"CLOSE  ✕",Vector2(1014,28),Vector2(128,38),close_menu)
	var divider := ColorRect.new()
	divider.position = Vector2(35,91)
	divider.size = Vector2(1110,1)
	divider.color = Color(0.61,0.67,0.67,0.20)
	frame.add_child(divider)
	for index in 3:
		var row_y := 133.0 + float(index)*136.0
		for side in 2:
			var from_x := 393.0 if side == 0 else 786.0
			var to_x := 470.0 if side == 0 else 710.0
			var link := Line2D.new()
			link.name = "PartConnector_%d_%d" % [side,index]
			link.points = PackedVector2Array([
				Vector2(from_x,row_y+51.0),
				Vector2(437.0 if side == 0 else 743.0,row_y+51.0),
				Vector2(to_x,row_y+51.0)
			])
			link.default_color = Color(0.72,0.79,0.78,0.62)
			link.width = 2.0
			frame.add_child(link)
			var dot := Panel.new()
			dot.position = Vector2(to_x-5.0,row_y+46.0)
			dot.size = Vector2(10,10)
			dot.add_theme_stylebox_override("panel",_panel_style(
				ORANGE,Color(1,0.84,0.56),1,10))
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.add_child(dot)
	car_preview = TextureRect.new()
	car_preview.name = "EquippedCarPreview"
	car_preview.position = Vector2(467,115)
	car_preview.size = Vector2(246,424)
	car_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	car_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	car_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(car_preview)
	for i in QUICK_SLOTS.size():
		var slot := str(QUICK_SLOTS[i])
		var side := 0 if i < 3 else 1
		var row := i if side == 0 else i-3
		var x := 40.0 if side == 0 else 792.0
		var y := 133.0+float(row)*136.0
		var slot_button := _make_button(frame,"",
			Vector2(x,y),Vector2(350,104),_open_slot.bind(slot))
		slot_button.name = "QuickSlot_"+slot.capitalize()
		slot_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		slot_button.add_theme_font_size_override("font_size",16)
		slot_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		slot_buttons[slot] = slot_button
		var bar := ColorRect.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.position = Vector2(27,90)
		bar.size = Vector2(0,4)
		bar.color = ORANGE
		slot_button.add_child(bar)
		slot_bars[slot] = bar
	car_name = _label(frame,"CURRENT VEHICLE",15,INK,
		Vector2(415,536),Vector2(350,36))
	car_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var separator := ColorRect.new()
	separator.position = Vector2(35,584)
	separator.size = Vector2(1110,1)
	separator.color = Color(0.61,0.67,0.67,0.23)
	frame.add_child(separator)
	feedback = _label(frame,"SELECT A SLOT TO SWAP INSTALLED PARTS",
		12,SUBTLE,Vector2(48,600),Vector2(750,43))
	_make_button(frame,"ESC / U  CLOSE",Vector2(955,604),
		Vector2(186,37),close_menu)
	_build_picker()


func _build_picker() -> void:
	picker = Panel.new()
	picker.name = "PartPicker"
	picker.position = Vector2(316,110)
	picker.size = Vector2(550,456)
	picker.add_theme_stylebox_override("panel",_panel_style(
		Color(0.038,0.068,0.076,0.98),ORANGE,2,12))
	frame.add_child(picker)
	picker_title = _label(picker,"EQUIPPED PARTS",21,INK,
		Vector2(24,15),Vector2(415,41))
	_make_button(picker,"✕",Vector2(485,18),Vector2(43,38),_close_picker)
	picker_status = _label(picker,"SELECT AN OWNED PART",12,SUBTLE,
		Vector2(24,64),Vector2(490,38))
	var scroll := ScrollContainer.new()
	scroll.name = "OwnedPartScroll"
	scroll.position = Vector2(22,115)
	scroll.size = Vector2(506,277)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	picker.add_child(scroll)
	picker_parts = VBoxContainer.new()
	picker_parts.name = "OwnedParts"
	picker_parts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_parts.add_theme_constant_override("separation",7)
	scroll.add_child(picker_parts)
	picker_remove = _make_button(picker,"REMOVE INSTALLED PART",
		Vector2(22,406),Vector2(506,36),_unequip_selected)
	picker.visible = false


func _resize() -> void:
	if not is_instance_valid(frame):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var zoom := minf((viewport_size.x-18.0)/DESIGN.x,
		(viewport_size.y-18.0)/DESIGN.y)
	zoom = clampf(zoom,0.30,1.12)
	frame.scale = Vector2.ONE*zoom
	frame.position = (viewport_size-DESIGN*zoom)*0.5
	# Use the gap to the right of the garage shortcut on desktop; on
	# small/mobile viewports put the action below the normal HUD row.
	launch_button.position = Vector2(760,25) if viewport_size.x>=1180 else \
		Vector2(maxf(12.0,viewport_size.x-207.0),85.0)
	launch_button.visible = not overlay.visible and is_instance_valid(economy)


func open_menu() -> void:
	if not is_instance_valid(economy) or not is_instance_valid(vehicle):
		return
	if overlay.visible or get_tree().paused:
		return
	_owns_pause = true
	get_tree().paused = true
	overlay.visible = true
	launch_button.visible = false
	last_result = ""
	_close_picker()
	refresh()
	_resize()


func close_menu() -> void:
	if not overlay.visible:
		return
	_close_picker()
	overlay.visible = false
	get_viewport().gui_release_focus()
	if _owns_pause:
		get_tree().paused = false
	_owns_pause = false
	_resize()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var close := key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE
	var toggle := key.keycode == KEY_U or key.physical_keycode == KEY_U
	if overlay.visible and (close or toggle):
		close_menu()
		get_viewport().set_input_as_handled()
	elif toggle and not get_tree().paused:
		open_menu()
		get_viewport().set_input_as_handled()


func _process(_dt: float) -> void:
	# The shortcut belongs to free-roam gameplay, not above the existing
	# garage, pause/settings, dealership or other modal menus.
	if not overlay.visible and is_instance_valid(launch_button):
		launch_button.visible = not get_tree().paused and is_instance_valid(economy)
	if overlay.visible and is_instance_valid(economy) and \
			last_car_id != str(economy.active_id):
		refresh()


func _part_in_slot(slot: String) -> Dictionary:
	var uid := economy.equipped_uid(str(economy.active_id),slot)
	if uid.is_empty():
		return {}
	return Parts.get_part(str(economy.get_upgrade_item(uid).get("template","")))


func _load_car_preview() -> void:
	if not is_instance_valid(vehicle):
		return
	var sprite := vehicle.get_node_or_null("Art/Sprite") as Sprite2D
	if not is_instance_valid(sprite) or sprite.texture == null:
		return
	var pixels := sprite.texture.get_image()
	if pixels == null or pixels.is_empty():
		return
	var bounds: Rect2i = Catalog.alpha_bounds(pixels)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return
	var cropped := pixels.get_region(bounds)
	if absf(wrapf(sprite.rotation,-PI,PI))>PI*0.5:
		cropped.rotate_180()
	var ratio := minf(225.0/float(cropped.get_width()),
		403.0/float(cropped.get_height()))
	cropped.resize(maxi(1,roundi(float(cropped.get_width())*ratio)),
		maxi(1,roundi(float(cropped.get_height())*ratio)),
		Image.INTERPOLATE_LANCZOS)
	car_preview.texture = ImageTexture.create_from_image(cropped)


func refresh() -> void:
	if not is_instance_valid(economy) or slot_buttons.is_empty():
		return
	var entry := Catalog.find_by_id(str(economy.active_id))
	if entry.is_empty():
		return
	if last_car_id != str(economy.active_id):
		last_car_id = str(economy.active_id)
		_load_car_preview()
	car_name.text = "%s   /   CAR LV %d" % [
		str(entry.get("display_name","CAR")).to_upper(),economy.active_car_level()]
	for slot in QUICK_SLOTS:
		var part := _part_in_slot(slot)
		var caption := "STOCK" if part.is_empty() else str(part.get("name","UPGRADE"))
		var title := str(SLOT_NAMES[slot])
		var icon := str(SLOT_ICONS[slot])
		var button: Button = slot_buttons[slot]
		button.text = "   %s  %s                      ↔\n\n        %s" % [
			icon,title,caption]
		button.tooltip_text = "%s — %s\nClick to browse and swap owned parts." % [
			title,caption]
		_style_button(button,slot==selected_slot and overlay.visible)
		var bar: ColorRect = slot_bars[slot]
		bar.size.x = 0.0 if part.is_empty() else \
			33.0+float(Parts.RARITIES.find(str(part.rarity)))*22.0
		bar.color = Parts.rarity_color(str(part.get("rarity","Common")))
	feedback.text = last_result if not last_result.is_empty() else \
		"SELECT A SLOT  ·  EQUIP OWNED PARTS WITHOUT RETURNING TO THE GARAGE"
	if picker.visible:
		_refresh_picker()


func _open_slot(slot: String) -> void:
	if not QUICK_SLOTS.has(slot):
		return
	selected_slot = slot
	picker.visible = true
	refresh()


func _close_picker() -> void:
	if is_instance_valid(picker):
		picker.visible = false


func _refresh_picker() -> void:
	var car_id := str(economy.active_id)
	var part := _part_in_slot(selected_slot)
	picker_title.text = str(SLOT_NAMES[selected_slot])+"  /  OWNED PARTS"
	picker_status.text = "EQUIPPED: "+(
		"STOCK" if part.is_empty() else str(part.get("name","UPGRADE")))
	picker_remove.disabled = economy.equipped_uid(car_id,selected_slot).is_empty()
	for child in picker_parts.get_children():
		picker_parts.remove_child(child)
		child.queue_free()
	# Browse the entire catalog even without inventory. New templates are
	# visible but non-interactive until future race rewards grant physical
	# upgrade items; installation continues to require an owned UID.
	var variants: Array[Dictionary] = Parts.in_slot(selected_slot)
	variants.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var order_a := Parts.RARITIES.find(str(a.rarity))
		var order_b := Parts.RARITIES.find(str(b.rarity))
		return order_a < order_b if order_a != order_b else \
			str(a.specialty) < str(b.specialty))
	for template in variants:
		var owned_items: Array[Dictionary] = []
		for item in economy.upgrade_inventory:
			if str(item.get("template","")) == str(template.id):
				owned_items.append(item)
		if owned_items.is_empty():
			var preview := Button.new()
			preview.name = "Unowned_"+str(template.id).replace("-","_")
			preview.custom_minimum_size.y = 69
			preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			preview.alignment = HORIZONTAL_ALIGNMENT_LEFT
			preview.add_theme_font_size_override("font_size",12)
			var source := "FUTURE RACE REWARD" if not \
				bool(template.get("race_drop_enabled",true)) else "NOT OWNED"
			preview.text = "%s  /  %s\n%s  ·  %s" % [
				str(template.name),str(template.rarity),Parts.summary(template),
				source]
			preview.tooltip_text = "Part not owned. %s" % source
			preview.disabled = true
			_style_button(preview,false)
			picker_parts.add_child(preview)
			continue
		for item in owned_items:
			var uid := str(item.get("uid",""))
			var status := economy.can_install_part(car_id,uid)
			var currently := economy.equipped_uid(car_id,selected_slot)==uid
			var label := "%s  /  %s\n%s" % [
				str(template.get("name","PART")),str(template.get("rarity","")),
				Parts.summary(template)]
			if currently:
				label += "   ·  INSTALLED"
			elif status == "level_locked":
				label += "   ·  CAR LEVEL LOCKED"
			elif status == "equipped_elsewhere":
				label += "   ·  EQUIPPED ON ANOTHER CAR"
			var option := Button.new()
			option.name = "Part_"+uid.replace("-","_")
			option.text = label
			option.custom_minimum_size.y = 69
			option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			option.alignment = HORIZONTAL_ALIGNMENT_LEFT
			option.add_theme_font_size_override("font_size",12)
			option.disabled = currently or status!="ready"
			option.pressed.connect(_install_uid.bind(uid))
			_style_button(option,false)
			picker_parts.add_child(option)

func _install_uid(uid: String) -> void:
	_change_equipment(uid,false)


func _unequip_selected() -> void:
	_change_equipment("",true)


func _change_equipment(uid: String,remove: bool) -> void:
	if not is_instance_valid(economy) or not is_instance_valid(vehicle):
		return
	var car_id := str(economy.active_id)
	var entry := Catalog.find_by_id(car_id)
	if entry.is_empty():
		return
	# Snapshot both complete, stock-derived upgrade loadouts. Applying the
	# DIFFERENCE to the running config preserves current F1 tune, velocity,
	# steering, RPM, transmission gear, position, and collision state.
	var before: VehicleConfig = Catalog.make_configuration(entry)
	economy.apply_car_upgrades(before,car_id)
	var result := economy.unequip_part(car_id,selected_slot) if remove else \
		economy.install_part(car_id,uid)
	if result != ("removed" if remove else "installed"):
		last_result = "COULD NOT SWAP: "+result.to_upper().replace("_"," ")
		refresh()
		return
	var after: VehicleConfig = Catalog.make_configuration(entry)
	economy.apply_car_upgrades(after,car_id)
	var affected: Array[String] = []
	for raw_key in Parts.FIELD_LABELS.keys():
		affected.append(str(raw_key))
	affected.append("audio_aggression")
	affected.append("audio_exhaust_roughness")
	affected.append("audio_turbo_presence")
	affected.append("audio_flutter")
	for property in affected:
		var prior: Variant = before.get(property)
		var latest: Variant = after.get(property)
		if (typeof(prior)!=TYPE_FLOAT and typeof(prior)!=TYPE_INT) or \
				(typeof(latest)!=TYPE_FLOAT and typeof(latest)!=TYPE_INT):
			continue
		var delta := float(latest)-float(prior)
		if absf(delta)>0.000001:
			vehicle.config.set(property,float(vehicle.config.get(property))+delta)
	# Audio induction is a string, not a numeric modifier. Switch to turbo
	# sound on a newly boosted N/A car and back to its authored stock voice
	# when removing the turbo. Other engine-specific profiles remain intact.
	if before.audio_induction != after.audio_induction and \
			vehicle.config.audio_induction == before.audio_induction:
		vehicle.config.audio_induction = after.audio_induction
	if vehicle.has_method("on_upgrade_config_changed"):
		vehicle.on_upgrade_config_changed(before.nitrous_capacity_seconds)
	last_result = "PART REMOVED  /  VEHICLE UPDATED" if remove else \
		"UPGRADE INSTALLED  /  VEHICLE UPDATED"
	refresh()
