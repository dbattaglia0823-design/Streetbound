extends CanvasLayer
## Location-gated dealership storefront. Browse only while parked at the
## relevant real shop; purchases unlock vehicles in the Laurel garage.
# Explicit script dependency: class_name lookups are not reliable before Godot imports.
const OwnershipModel = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const DealerConfig = preload("res://scripts/world/dealership_config.gd")
const PPM := 20.0
var manager: Node2D
var player: VehicleController2D
var economy: OwnershipModel
var overlay: Control
var launch_button: Button
var heading: Label
var wallet: Label
var search: LineEdit
var count_label: Label
var feedback: Label
var grid: GridContainer
var scroll: ScrollContainer
var cards: Array[Dictionary] = []
var _thumb_cache: Dictionary = {}
var _clock := 0.0
var _active_shop: Dictionary = {}
var _paused_here := false
var _marker_access: Callable
var _marker_shop:=false


func _ready() -> void:
	name = "DealershipMenu"
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	launch_button = Button.new()
	launch_button.name = "OpenDealership"
	launch_button.position = Vector2(410,72)
	launch_button.custom_minimum_size = Vector2(345,42)
	launch_button.text = "DEALERSHIP [ F ]"
	launch_button.pressed.connect(open_menu)
	add_child(launch_button)
	overlay = Control.new()
	overlay.name = "DealershipOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var background := ColorRect.new()
	background.color = Color(0.027,0.042,0.048,0.97)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(background)
	var margins := MarginContainer.new()
	margins.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margins.add_theme_constant_override("margin_" + side, 28)
	overlay.add_child(margins)
	var vertical := VBoxContainer.new()
	vertical.add_theme_constant_override("separation",12)
	margins.add_child(vertical)
	var top := HBoxContainer.new()
	vertical.add_child(top)
	heading = Label.new()
	heading.name = "DealerTitle"
	heading.text = "STREETBOUND / DEALERSHIP"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_font_size_override("font_size",26)
	top.add_child(heading)
	var close := Button.new()
	close.text = "BACK TO DRIVING [ESC]"
	close.pressed.connect(close_menu)
	top.add_child(close)
	var finance := HBoxContainer.new()
	vertical.add_child(finance)
	wallet = Label.new()
	wallet.name = "Wallet"
	wallet.add_theme_font_size_override("font_size",19)
	wallet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	finance.add_child(wallet)
	count_label = Label.new()
	count_label.add_theme_font_size_override("font_size",13)
	finance.add_child(count_label)
	var note := Label.new()
	note.text = "Prices use labeled MSRP/market estimates or clearly identified game-only values. Purchases go to Laurel Motor House."
	note.add_theme_font_size_override("font_size",13)
	vertical.add_child(note)
	search = LineEdit.new()
	search.placeholder_text = "Search models in this dealership"
	search.custom_minimum_size.y = 38
	search.text_changed.connect(_filter)
	vertical.add_child(search)
	feedback = Label.new()
	feedback.name = "PurchaseFeedback"
	feedback.text = "Select a vehicle to purchase."
	feedback.add_theme_font_size_override("font_size",13)
	feedback.add_theme_color_override("font_color",Color("b9d7be"))
	vertical.add_child(feedback)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical.add_child(scroll)
	grid = GridContainer.new()
	grid.name = "StockGrid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	scroll.add_child(grid)
	overlay.visible = false
	get_node("/root/MenuNavigation").register_scope(overlay,18,close_menu)
	if is_instance_valid(economy):
		economy.changed.connect(_refresh_cards)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_update_access()


func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	grid.columns = maxi(2, floori((viewport.x - 80.0) / 288.0))
	launch_button.position = Vector2(minf(410.0,maxf(12.0,viewport.x-360.0)),72.0)


func _update_access() -> void:
	if overlay == null or overlay.visible or not is_instance_valid(manager):
		return
	var site: Dictionary = manager.nearby_shop()
	var prompt_text: String = manager.parking_prompt()
	launch_button.visible = not site.is_empty()
	launch_button.disabled = not manager.can_browse(site)
	if not prompt_text.is_empty():
		launch_button.text = prompt_text


func open_menu() -> void:
	if overlay.visible or get_tree().paused or not is_instance_valid(manager):
		return
	var site: Dictionary = manager.nearby_shop()
	if not manager.can_browse(site):
		return
	_marker_access=Callable()
	_marker_shop=false
	_show_shop(site)

## Marker-only showrooms retain the same cards, prices, levels, purchases,
## and ownership save; their access is rechecked by the marker controller.
func open_marker_menu(site: Dictionary,access: Callable) -> void:
	if overlay.visible or get_tree().paused or not access.is_valid() or not bool(access.call()):return
	_marker_access=access
	_marker_shop=true
	_show_shop(site)

func _show_shop(site: Dictionary) -> void:
	_active_shop = site
	heading.text = str(site.name).to_upper() + "  /  " + str(site.tier)
	feedback.text = "Select a vehicle to purchase."
	_paused_here = true
	get_tree().paused = true
	overlay.visible = true
	launch_button.visible = false
	search.clear()
	_rebuild_cards()
	_refresh_cards()
	search.grab_focus()


func close_menu() -> void:
	if not overlay.visible:
		return
	overlay.visible = false
	_active_shop = {}
	_marker_access=Callable()
	_marker_shop=false
	get_viewport().gui_release_focus()
	if _paused_here:
		get_tree().paused = false
	_paused_here = false
	_update_access()


## Dealerships list their own vehicles from the cheapest to the most
## expensive. Equal prices use a consistent name/ID tie-breaker.
static func _stock_price_less(a: Dictionary, b: Dictionary) -> bool:
	var price_a := int(a.get("price_usd", 0))
	var price_b := int(b.get("price_usd", 0))
	if price_a != price_b:
		return price_a < price_b
	var name_a := str(a.get("display_name", "")).to_lower()
	var name_b := str(b.get("display_name", "")).to_lower()
	if name_a != name_b:
		return name_a < name_b
	return str(a.get("id", "")) < str(b.get("id", ""))


func _rebuild_cards() -> void:
	for item in cards:
		var previous_panel: Control = item.panel
		# Remove immediately so a close/reopen in one frame cannot leave
		# queued-for-deletion cards ahead of the new price-sorted stock.
		if previous_panel.get_parent() == grid:
			grid.remove_child(previous_panel)
		previous_panel.queue_free()
	cards.clear()
	var stock: Array[Dictionary] = DealerConfig.available_inventory(_active_shop)
	stock.sort_custom(_stock_price_less)
	for entry in stock:
		_add_card(entry)
	_layout()
	_filter(search.text)


func _add_card(entry: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "Stock_" + str(entry.id).replace("-","_")
	panel.custom_minimum_size = Vector2(256,356)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("14272b")
	style.border_color = Color("3b5757")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel",style)
	grid.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	panel.add_child(column)
	var picture := TextureRect.new()
	picture.name = "VehiclePhoto"
	picture.custom_minimum_size.y = 124
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(picture)
	var name := Label.new()
	name.text = str(entry.display_name)
	name.add_theme_font_size_override("font_size",17)
	name.clip_text = true
	column.add_child(name)
	var reference := Label.new()
	reference.name = "ReferenceTrim"
	reference.text = Catalog.reference_label(entry)
	reference.add_theme_font_size_override("font_size",11)
	reference.add_theme_color_override("font_color",Color("a6c0b6"))
	reference.clip_text = true
	column.add_child(reference)
	var specs := Label.new()
	specs.text = "%.0f HP  /  %.0f LB-FT  /  %s\n%.0f LB  /  %s  /  GRIP %.2f\nHEALTH %d" % [
		float(entry.power_kw)*1.34102, float(entry.torque_nm)*0.73756,
		str(entry.drivetrain),float(entry.mass_kg)*2.20462,
		str(entry.reference_transmission),float(entry.tire_grip),int(entry.get("max_health_points",2000))]
	specs.text += "\n" + Catalog.capacity_label(entry)
	specs.add_theme_font_size_override("font_size",12)
	specs.add_theme_color_override("font_color",Color("c0ccc9"))
	column.add_child(specs)
	var price := Label.new()
	price.text = OwnershipModel.dollars(int(entry.price_usd))
	price.add_theme_font_size_override("font_size",19)
	price.add_theme_color_override("font_color",Color("ecd29b"))
	column.add_child(price)
	var price_basis := Label.new()
	price_basis.name = "PriceBasis"
	price_basis.text = Catalog.price_basis_label(entry)
	price_basis.add_theme_font_size_override("font_size",11)
	price_basis.add_theme_color_override("font_color",Color("adb9b4"))
	column.add_child(price_basis)
	var requirement := Label.new()
	requirement.name = "RequiredLevel"
	requirement.text = "DRIVER LV %d REQUIRED" % int(entry.get("required_player_level",1))
	requirement.add_theme_font_size_override("font_size",12)
	requirement.add_theme_color_override("font_color",Color("b9cfb8"))
	column.add_child(requirement)
	var action := Button.new()
	action.name = "Buy_" + str(entry.id).replace("-","_")
	action.custom_minimum_size.y = 35
	action.pressed.connect(_purchase.bind(str(entry.id)))
	column.add_child(action)
	panel.tooltip_text = "%s\n%s\n%s" % [
		Catalog.reference_label(entry),
		str(entry.get("reference_price_note","")),
		"Factory source: "+str(entry.get("source_spec_url","")) if
			not str(entry.get("source_spec_url","")).is_empty() else
			"Representative trim figures pending individual source check"]
	if not str(entry.get("source_price_url","")).is_empty():
		panel.tooltip_text += "\nPricing reference: " + str(entry.source_price_url)
	if bool(entry.source_model_unverified):
		panel.tooltip_text += "\nArtwork association remains provisional"
	cards.append({"panel":panel,"picture":picture,"entry":entry,"action":action})


func _refresh_cards() -> void:
	if not is_instance_valid(economy) or wallet == null:
		return
	wallet.text = "BALANCE  " + OwnershipModel.dollars(economy.balance) + \
		"  /  DRIVER LV %d/100  /  OWNED %d" % [economy.player_level(),economy.owned_count()]
	for item in cards:
		var entry: Dictionary = item.entry
		var action: Button = item.action
		if economy.owns(str(entry.id)):
			action.text = "OWNED  /  IN GARAGE"
			action.disabled = true
		elif not economy.can_buy_at_level(entry):
			action.text = "LOCKED  /  DRIVER LV %d" % economy.required_player_level(entry)
			action.disabled = true
		elif economy.can_afford(entry):
			action.text = "BUY  " + OwnershipModel.dollars(int(entry.price_usd))
			action.disabled = false
		else:
			action.text = "INSUFFICIENT FUNDS"
			action.disabled = true


func _purchase(id: String) -> void:
	if _active_shop.is_empty():return
	if _marker_shop:
		if not _marker_access.is_valid() or not bool(_marker_access.call()):return
	elif not is_instance_valid(manager) or not manager.can_browse(_active_shop):return
	var entry := Catalog.find_by_id(id)
	if entry.is_empty() or not DealerConfig.sells(_active_shop,id):
		return
	var result := economy.purchase(id)
	match result:
		"purchased":
			feedback.text = "PURCHASED: %s. Drive to Laurel Motor House to equip it." % str(entry.display_name)
		"insufficient":
			feedback.text = "Not enough funds for " + str(entry.display_name)
		"level_locked":
			feedback.text = "Requires driver level %d to buy %s." % [
				economy.required_player_level(entry),str(entry.display_name)]
		"owned":
			feedback.text = "Already owned."
		_:
			feedback.text = "Unable to complete purchase: " + result
	_refresh_cards()


func _filter(query: String) -> void:
	var needle := query.strip_edges().to_lower()
	var shown := 0
	for item in cards:
		var entry: Dictionary = item.entry
		var matches := needle.is_empty() or needle in str(entry.display_name).to_lower()
		(item.panel as Control).visible = matches
		if matches:
			shown += 1
	count_label.text = "%d VEHICLES  /  %s" % [shown,str(_active_shop.get("region",""))]
	scroll.scroll_vertical = 0
	_clock = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (not event.pressed or event.echo):return
	if event.is_action_pressed("interact"):
		# Let the Ashford staging area handle F when no dealership is near.
		if overlay.visible:
			close_menu()
			get_viewport().set_input_as_handled()
		elif is_instance_valid(manager) and manager.can_browse(manager.nearby_shop()):
			open_menu()
			get_viewport().set_input_as_handled()
	elif overlay.visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		close_menu()
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	_clock += dt
	if not overlay.visible:
		if _clock >= 0.13:
			_clock = 0.0
			_update_access()
		return
	if _clock < 0.1:
		return
	_clock = 0.0
	var viewport_rect := scroll.get_global_rect().grow(160.0)
	var budget := 2
	for item in cards:
		var panel: Control = item.panel
		var picture: TextureRect = item.picture
		if not panel.visible or not viewport_rect.intersects(panel.get_global_rect()):
			picture.texture = null
			continue
		if picture.texture != null or budget <= 0:
			continue
		var path := str((item.entry as Dictionary).texture)
		if not _thumb_cache.has(path):
			var source := load(path) as Texture2D
			if source == null:
				continue
			var pixels := source.get_image()
			var bounds := Catalog.alpha_bounds(pixels)
			if bounds.size.x <= 4 or bounds.size.y <= 4:
				continue
			var cropped := pixels.get_region(bounds)
			var ratio := minf(235.0 / cropped.get_width(),124.0 / cropped.get_height())
			cropped.resize(maxi(1, roundi(cropped.get_width()*ratio)),
				maxi(1, roundi(cropped.get_height()*ratio)),
				Image.INTERPOLATE_LANCZOS)
			_thumb_cache[path] = ImageTexture.create_from_image(cropped)
		picture.texture = _thumb_cache[path]
		budget -= 1
