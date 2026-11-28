extends CanvasLayer
## In-game, anywhere-accessible six-slot quick swap overlay.
## This view uses real owned parts and changes live stats in place: no car
## respawn, lost momentum, gear reset or teleport during a hot swap.
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Parts = preload("res://scripts/vehicle/upgrade_parts.gd")
const Progress = preload("res://scripts/vehicle/race_progression.gd")
const RacingStyle = preload("res://scripts/ui/racing_menu_style.gd")
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
const INK := RacingStyle.TEXT
const SUBTLE := RacingStyle.MUTED
const ORANGE := RacingStyle.ACCENT
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
var picker_parts: GridContainer
var slot_captions: Dictionary = {}
var _icon_cache: Dictionary = {}
const TILE_SIZE := 150.0
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
		Color(0.07,0.08,0.10,0.95), RacingStyle.EDGE, 1, 6))
	overlay.add_child(frame)
	_build_layout()
	overlay.visible = false
	get_node("/root/MenuNavigation").register_scope(overlay,18,close_menu)
	get_node("/root/MenuNavigation").register_scope(picker,19,_controller_close_picker)
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
	RacingStyle.button(node,selected,node.get_theme_font_size("font_size"))
	# Multi-line part descriptions retain their existing wrapping/width.
	node.clip_text=false

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


# Authored vector part silhouettes: no font glyph or external artwork dependency.
func _part_icon(slot: String) -> Texture2D:
	if _icon_cache.has(slot):
		return _icon_cache[slot] as Texture2D
	var shapes: Dictionary = {
		"engine": '<path d="M15 26h9l6-9h29l7 9h12v33H65l-7 10H27l-8-10H9V38h6z" fill="#60727b"/><path d="M29 27h29v12H29zM29 44h29v13H29z" fill="#a9b9bf"/><path d="M35 18v-7h19v7M8 39v17M73 32h10v18H73" stroke="#d9e3e5" stroke-width="4"/>',
		"turbo": '<path d="M48 13h28v19H62a26 26 0 1 1-14-19z" fill="#768b94"/><circle cx="43" cy="44" r="19" fill="#26343c"/><circle cx="43" cy="44" r="12" fill="#a7c1c8"/><path d="M43 32v24M31 44h24M35 36l16 16m0-16L35 52" stroke="#44535e" stroke-width="3"/>',
		"transmission": '<path d="M10 25l19-11 17 8 12 13 21 5v12l-21 5-12 13-17 8-19-11z" fill="#73838c"/><path d="M24 17v56M35 19v52M47 27v36M58 35v22M80 40h8v12h-8" stroke="#c7d3d6" stroke-width="4"/>',
		"tires": '<circle cx="44" cy="44" r="33" fill="#283138"/><circle cx="44" cy="44" r="23" fill="#81919a"/><circle cx="44" cy="44" r="16" fill="#293842"/><path d="M44 28v32M28 44h32M33 33l22 22m0-22L33 55" stroke="#ccd8de" stroke-width="4"/><circle cx="44" cy="44" r="5" fill="#b3c5c9"/>',
		"suspension": '<path d="M40 8h8v13h-8zm-7 56h22v15H33z" fill="#acbcc4"/><path d="M44 20v45" stroke="#8298a4" stroke-width="12"/><path d="M29 20h30L29 29l30 9-30 9 30 9-30 9h30" fill="none" stroke="#df9e50" stroke-width="5" stroke-linejoin="round"/>',
		"nitrous": '<rect x="26" y="17" width="36" height="64" rx="17" fill="#387cab"/><path d="M38 17V8h12v9M36 7h22" stroke="#d3dfe3" stroke-width="5"/><path d="M29 36h30v21H29z" fill="#b8dce9"/><path d="M33 47h22" stroke="#32617d" stroke-width="4"/>',
		"chassis": '<path d="M18 13h52l10 16-10 46H18L8 29zM18 13l52 62M70 13L18 75M12 31h64M14 58h60" fill="none" stroke="#adbdc3" stroke-width="6" stroke-linejoin="round"/>',
		"bumpers": '<path d="M9 27q35-13 70 0l-4 28-14 8H27l-14-8z" fill="#899ca5"/><path d="M21 37h46l-5 14H26z" fill="#293944"/><path d="M11 28q33-9 66 0" fill="none" stroke="#d3dfe2" stroke-width="4"/>',
		"protection": '<path d="M44 9l31 12v22q0 22-31 36Q13 65 13 43V21z" fill="#6a8593"/><path d="M44 20l20 8v15q0 15-20 26Q24 58 24 43V28z" fill="#b5c6cb"/><path d="M44 20v49" stroke="#6a8593" stroke-width="4"/>',
		"cargo": '<rect x="9" y="24" width="70" height="48" rx="7" fill="#657780"/><path d="M30 24v-9h28v9M9 43h70" fill="none" stroke="#c3d1d5" stroke-width="5"/><path d="M23 35h8v20h-8zm34 0h8v20h-8z" fill="#e4a252"/>'
	}
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="88" height="88" viewBox="0 0 88 88"><g stroke="#18232a" stroke-width="2" stroke-linejoin="round">'+str(shapes.get(slot,shapes["engine"]))+'</g></svg>'
	var image := Image.new()
	if image.load_svg_from_string(svg) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_icon_cache[slot] = texture
	return texture


func _tile_icon(parent: Control, slot: String, at: Vector2, extent: float) -> void:
	var art := TextureRect.new()
	art.name = "PartIcon"
	art.texture = _part_icon(slot)
	art.position = at
	art.size = Vector2.ONE*extent
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art)


func _center_label(parent: Control, value: String, font_size: int, color: Color, at: Vector2, dimensions: Vector2) -> Label:
	var node := _label(parent,value,font_size,color,at,dimensions)
	node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return node


func _part_tile(button: Button, template: Dictionary, state: String, detail: String) -> void:
	button.custom_minimum_size = Vector2.ONE*TILE_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.text = ""
	_style_button(button,state == "INSTALLED")
	var rarity := str(template.get("rarity","Common"))
	var tint := Parts.rarity_color(rarity)
	var normal := button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	normal.border_color = ORANGE if state == "INSTALLED" else tint
	button.add_theme_stylebox_override("normal",normal)
	var disabled_style := normal.duplicate() as StyleBoxFlat
	disabled_style.bg_color = Color(0.065,0.085,0.095,0.96)
	button.add_theme_stylebox_override("disabled",disabled_style)
	_tile_icon(button,selected_slot,Vector2(47,5),56)
	var title := _center_label(button,str(template.get("name","PART")),12,INK,Vector2(5,62),Vector2(140,34))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_center_label(button,rarity.to_upper(),10,tint,Vector2(5,96),Vector2(140,15))
	_center_label(button,detail,10,SUBTLE,Vector2(5,111),Vector2(140,15))
	_center_label(button,state,10,ORANGE if state == "INSTALLED" or state == "BUY" else SUBTLE,Vector2(5,128),Vector2(140,17))
	picker_parts.add_child(button)


func _build_layout() -> void:
	_label(frame,"╱╱  UPGRADES",31,INK,Vector2(38,24),Vector2(295,50))
	_label(frame,"BLACK MARKET",12,ORANGE,Vector2(342,10),Vector2(540,20))
	for i in Parts.BLACK_MARKET_SLOTS.size():
		var slot: String = Parts.BLACK_MARKET_SLOTS[i]
		var market_button := _make_button(frame,slot.to_upper(),Vector2(342+i*160,32),Vector2(150,38),_open_slot.bind(slot))
		market_button.name = "BlackMarket_"+slot
		market_button.add_theme_font_size_override("font_size",12)
		market_button.icon = _part_icon(slot)
		market_button.add_theme_constant_override("icon_max_width",24)
	_make_button(frame,"CLOSE  ✕",Vector2(1014,28),Vector2(128,38),close_menu)
	var divider := ColorRect.new()
	divider.position = Vector2(35,91)
	divider.size = Vector2(1110,1)
	divider.color = Color(0.61,0.67,0.67,0.20)
	frame.add_child(divider)
	for index in 3:
		var row_y := 120.0 + float(index)*150.0
		for side in 2:
			var from_x := 294.0 if side == 0 else 886.0
			var to_x := 470.0 if side == 0 else 710.0
			var link := Line2D.new()
			link.name = "PartConnector_%d_%d" % [side,index]
			link.points = PackedVector2Array([
				Vector2(from_x,row_y+71.0),
				Vector2(437.0 if side == 0 else 743.0,row_y+71.0),
				Vector2(to_x,row_y+71.0)
			])
			link.default_color = Color(0.72,0.79,0.78,0.62)
			link.width = 2.0
			frame.add_child(link)
			var dot := Panel.new()
			dot.position = Vector2(to_x-5.0,row_y+66.0)
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
		var x := 148.0 if side == 0 else 886.0
		var y := 120.0+float(row)*150.0
		var slot_button := _make_button(frame,"",
			Vector2(x,y),Vector2(142,142),_open_slot.bind(slot))
		slot_button.name = "QuickSlot_"+slot.capitalize()
		slot_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		slot_button.add_theme_font_size_override("font_size",16)
		slot_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		slot_buttons[slot] = slot_button
		_tile_icon(slot_button,slot,Vector2(38,8),66)
		_center_label(slot_button,str(SLOT_NAMES[slot]),13,INK,Vector2(5,80),Vector2(132,24))
		slot_captions[slot] = _center_label(slot_button,"STOCK",11,SUBTLE,Vector2(5,105),Vector2(132,24))
		var bar := ColorRect.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.position = Vector2(8,132)
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
	picker.position = Vector2(316,99)
	picker.size = Vector2(550,480)
	picker.add_theme_stylebox_override("panel",_panel_style(
		RacingStyle.PANEL,ORANGE,2,6))
	frame.add_child(picker)
	picker_title = _label(picker,"EQUIPPED PARTS",21,INK,
		Vector2(24,15),Vector2(415,41))
	_make_button(picker,"✕",Vector2(485,18),Vector2(43,38),_close_picker)
	picker_status = _label(picker,"SELECT AN OWNED PART",12,SUBTLE,
		Vector2(24,64),Vector2(490,38))
	var scroll := ScrollContainer.new()
	scroll.name = "OwnedPartScroll"
	scroll.position = Vector2(22,115)
	scroll.size = Vector2(506,312)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	picker.add_child(scroll)
	picker_parts = GridContainer.new()
	picker_parts.columns = 3
	picker_parts.name = "OwnedParts"
	picker_parts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_parts.add_theme_constant_override("h_separation",8)
	picker_parts.add_theme_constant_override("v_separation",8)
	scroll.add_child(picker_parts)
	picker_remove = _make_button(picker,"REMOVE INSTALLED PART",
		Vector2(22,435),Vector2(506,32),_unequip_selected)
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
	var close := event.is_action_pressed("pause") or (
		event is InputEventKey and (event as InputEventKey).pressed and
		((event as InputEventKey).keycode == KEY_ESCAPE or
		(event as InputEventKey).physical_keycode == KEY_ESCAPE))
	var toggle := event.is_action_pressed("upgrades")
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
		var button: Button = slot_buttons[slot]
		var caption_label: Label = slot_captions[slot]
		caption_label.text = caption
		button.tooltip_text = "%s — %s\nClick to browse and swap owned parts." % [
			title,caption]
		_style_button(button,slot==selected_slot and overlay.visible)
		var bar: ColorRect = slot_bars[slot]
		bar.size.x = 0.0 if part.is_empty() else \
			25.0+float(Parts.RARITIES.find(str(part.rarity)))*23.0
		bar.color = Parts.rarity_color(str(part.get("rarity","Common")))
	feedback.text = last_result if not last_result.is_empty() else \
		"SELECT A SLOT  ·  EQUIP OWNED PARTS WITHOUT RETURNING TO THE GARAGE"
	if picker.visible:
		_refresh_picker()


func _open_slot(slot: String) -> void:
	if not QUICK_SLOTS.has(slot) and not Parts.BLACK_MARKET_SLOTS.has(slot):
		return
	selected_slot = slot
	picker.visible = true
	refresh()


func _controller_close_picker() -> void:
	_close_picker()
	var selected: Button=slot_buttons.get(selected_slot) as Button
	if is_instance_valid(selected):selected.grab_focus()

func _close_picker() -> void:
	if is_instance_valid(picker):
		picker.visible = false


func _refresh_picker() -> void:
	var car_id := str(economy.active_id)
	var part := _part_in_slot(selected_slot)
	var market := selected_slot in Parts.BLACK_MARKET_SLOTS
	picker_title.text = "BLACK MARKET / "+selected_slot.to_upper() if market else str(SLOT_NAMES[selected_slot])+"  /  OWNED PARTS"
	picker_status.text = "EQUIPPED: "+(
		"STOCK" if part.is_empty() else str(part.get("name","UPGRADE")))
	picker_remove.disabled = economy.equipped_uid(car_id,selected_slot).is_empty() or (market and not _market_service_allowed())
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
		var summary := Parts.summary(template)
		var short_summary := summary.split("   /   ")[0]
		if owned_items.is_empty() or market:
			var preview := Button.new()
			preview.name = "Unowned_"+str(template.id).replace("-","_")
			if market:
				var purchase_status := economy.black_market_purchase_status(str(template.id))
				var state := "BUY" if purchase_status=="ready" else purchase_status.to_upper().replace("_"," ")
				preview.disabled = purchase_status!="ready" or not _market_service_allowed()
				preview.pressed.connect(_purchase_market.bind(str(template.id)))
				preview.tooltip_text = "%s\n%s\n%d REP · %s" % [str(template.name),summary,int(template.required_rep),state]
				_part_tile(preview,template,state,Ownership.dollars(int(template.price_usd)))
			else:
				var source := "EVENT REWARD" if not bool(template.get("race_drop_enabled",true)) else "NOT OWNED"
				preview.tooltip_text = "%s\n%s\n%s" % [str(template.name),summary,source]
				preview.disabled = true
				_part_tile(preview,template,source,short_summary)
				continue
		for item in owned_items:
			var uid := str(item.get("uid",""))
			var status := economy.can_install_part(car_id,uid)
			var currently := economy.equipped_uid(car_id,selected_slot)==uid
			var state := "INSTALLED" if currently else ("OWNED" if status=="ready" else status.to_upper().replace("_"," "))
			var option := Button.new()
			option.name = "Part_"+uid.replace("-","_")
			option.tooltip_text = "%s\n%s\n%s" % [str(template.name),summary,state]
			option.disabled = currently or status!="ready" or (market and not _market_service_allowed())
			option.pressed.connect(_install_uid.bind(uid))
			_part_tile(option,template,state,short_summary)

func _market_service_allowed() -> bool:
	if not is_instance_valid(vehicle) or vehicle.linear_velocity.length() > 1.5:
		return false
	for police in get_tree().get_nodes_in_group("streetbound_police"):
		if int(police.get("wanted_level")) > 0:
			return false
	for contracts in get_tree().get_nodes_in_group("streetbound_contracts"):
		if not (contracts.get("active") as Dictionary).is_empty():
			return false
	for race in get_tree().get_nodes_in_group("streetbound_race"):
		if str(race.get("state")) in ["countdown","running"]:
			return false
	return true

func _purchase_market(template_id: String) -> void:
	if not _market_service_allowed():
		last_result = "BLACK MARKET / STOP IN FREE ROAM FIRST"
		refresh()
		return
	var result := economy.purchase_black_market(template_id)
	last_result = "BLACK MARKET / "+result.to_upper().replace("_"," ")
	refresh()

func _install_uid(uid: String) -> void:
	_change_equipment(uid,false)


func _unequip_selected() -> void:
	_change_equipment("",true)


func _change_equipment(uid: String,remove: bool) -> void:
	if not is_instance_valid(economy) or not is_instance_valid(vehicle):
		return
	if selected_slot in Parts.BLACK_MARKET_SLOTS and not _market_service_allowed():
		last_result = "BLACK MARKET / STOP IN FREE ROAM FIRST"
		refresh()
		return
	var car_id := str(economy.active_id)
	var entry := Catalog.find_by_id(car_id)
	if entry.is_empty():
		return
	# Snapshot both complete, stock-derived upgrade loadouts. Applying the
	# DIFFERENCE to the active car preserves speed, steering, RPM,
	# transmission gear, position, collision state, and non-upgrade stats.
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
			var live: Variant = vehicle.config.get(property)
			if typeof(live)==TYPE_INT:
				vehicle.config.set(property,roundi(float(live)+delta))
			else:
				vehicle.config.set(property,float(live)+delta)
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
