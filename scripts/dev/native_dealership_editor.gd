extends RefCounted
## Native builder panel for real, location-based dealerships. The source file
## stores lightweight overrides; the game catalog owns every vehicle stat.
const Config = preload("res://scripts/world/dealership_config.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const PPM := 20.0

var editor
var dialog: AcceptDialog
var dealers: ItemList
var name_edit: LineEdit
var tier_edit: LineEdit
var x_spin: SpinBox
var y_spin: SpinBox
var width_spin: SpinBox
var depth_spin: SpinBox
var style: OptionButton
var stock_mode: OptionButton
var stock_search: LineEdit
var stock: ItemList
var count: Label
var selected_id := ""
var placing_new := false
var _syncing := false

func _label(parent: Node, text_value: String) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size",12)
	parent.add_child(label)
	return label

func _column(parent: Node) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.add_theme_constant_override("separation",5)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(result)
	return result

func build(e) -> void:
	editor = e
	dialog = AcceptDialog.new()
	dialog.name = "DealershipManager"
	dialog.title = "Dealership areas and inventory"
	dialog.ok_button_text = "Close"
	dialog.min_size = Vector2i(920,680)
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	e.add_child(dialog)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",12)
	columns.custom_minimum_size = Vector2(895,615)
	dialog.add_child(columns)
	var left := _column(columns)
	left.custom_minimum_size.x = 225
	_label(left,"MAP DEALERSHIPS")
	dealers = ItemList.new()
	dealers.custom_minimum_size.y = 300
	dealers.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(dealers)
	dealers.item_selected.connect(_selected)
	e._btn("Place new dealership",left,_start_new)
	e._btn("Move selected on map",left,_start_move)
	e._btn("Reset / remove selected",left,_delete)
	var help := _label(left,"Choose a shop, then click Move to place its center 35–100 m from a road. The shaded driveway connects to the road. Save to Game to apply.")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var right := _column(columns)
	right.custom_minimum_size.x = 270
	_label(right,"PROPERTY AND DRIVE-IN AREA")
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Dealership name"
	right.add_child(name_edit)
	name_edit.text_submitted.connect(func(_text: String) -> void: _save_text())
	name_edit.focus_exited.connect(_save_text)
	tier_edit = LineEdit.new()
	tier_edit.placeholder_text = "Type / tier"
	right.add_child(tier_edit)
	tier_edit.text_submitted.connect(func(_text: String) -> void: _save_text())
	tier_edit.focus_exited.connect(_save_text)
	_label(right,"Building artwork")
	style = OptionButton.new()
	for entry in Config.defaults():
		style.add_item(str(entry.name))
		style.set_item_metadata(style.item_count-1,str(entry.texture))
	right.add_child(style)
	style.item_selected.connect(_style_changed)
	var coords := HBoxContainer.new()
	right.add_child(coords)
	x_spin = e._number(coords,"Center X m",0,24000,0)
	y_spin = e._number(coords,"Center Y m",0,24000,0)
	var dims := HBoxContainer.new()
	right.add_child(dims)
	width_spin = e._number(dims,"Lot width m",18,70,32)
	depth_spin = e._number(dims,"Lot depth m",14,60,20)
	for spin in [x_spin,y_spin,width_spin,depth_spin]:
		spin.step = 1.0
		spin.value_changed.connect(func(_value: float) -> void: _save_geometry())
	var stock_panel := _column(columns)
	stock_panel.custom_minimum_size.x = 345
	_label(stock_panel,"VEHICLE INVENTORY")
	stock_mode = OptionButton.new()
	stock_mode.add_item("Automatic — vehicle catalog assignments")
	stock_mode.add_item("Custom — select vehicles below")
	stock_panel.add_child(stock_mode)
	stock_mode.item_selected.connect(_mode_changed)
	stock_search = LineEdit.new()
	stock_search.placeholder_text = "Search all cars in the catalog..."
	stock_search.text_changed.connect(func(_value: String) -> void: _refresh_stock())
	stock_panel.add_child(stock_search)
	stock = ItemList.new()
	stock.select_mode = ItemList.SELECT_MULTI
	stock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stock_panel.add_child(stock)
	stock.multi_selected.connect(_stock_changed)
	count = _label(stock_panel,"")
	var note := _label(stock_panel,"Custom: Ctrl-click to add/remove models. Prices, stats, artwork and new models are loaded from the car catalog, not copied here.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func open() -> void:
	if not editor.source_ready:
		editor._notice("Open a map to edit its dealerships.")
		return
	placing_new = false
	_refresh_dealers()
	_show_selection()
	dialog.popup_centered(Vector2i(920,680))

func open_for(identity: String) -> void:
	selected_id = identity
	open()

func _source() -> Dictionary:
	return editor.authoring.dealership_at_id(selected_id) if editor.source_ready else {}

func _position(dealer: Dictionary) -> Vector2:
	if dealer.has("x") and dealer.has("y"):
		return Vector2(float(dealer.x),float(dealer.y))
	if is_instance_valid(editor.world) and is_instance_valid(editor.world.dealerships):
		var actual: Dictionary = editor.world.dealerships.get_site(str(dealer.id))
		if not actual.is_empty():
			return Vector2(float(actual.center_m[0]),float(actual.center_m[1]))
	var near: Array = dealer.get("near_m",[0,0])
	return Vector2(float(near[0]),float(near[1]))

func _refresh_dealers() -> void:
	_syncing = true
	dealers.clear()
	for dealer in editor.authoring.dealership_list():
		var id := str(dealer.id)
		dealers.add_item(str(dealer.get("name",id)))
		dealers.set_item_metadata(dealers.item_count-1,id)
		if id==selected_id:
			dealers.select(dealers.item_count-1)
	if _source().is_empty() and dealers.item_count>0:
		selected_id = str(dealers.get_item_metadata(0))
		dealers.select(0)
	_syncing = false
	_refresh_fields()

func _selected(index: int) -> void:
	if _syncing:
		return
	selected_id = str(dealers.get_item_metadata(index))
	_refresh_fields()
	_show_selection()

func _show_selection() -> void:
	var dealer := _source()
	if not dealer.is_empty():
		editor.editor_camera.global_position = _position(dealer)*PPM
		editor._update_view(true)
		editor.gizmos.focused_dealer_id = selected_id
		editor.gizmos.queue_redraw()

func _refresh_fields() -> void:
	_syncing = true
	var dealer := _source()
	var exists := not dealer.is_empty()
	for control in [name_edit,tier_edit,x_spin,y_spin,width_spin,depth_spin,stock_search]:
		control.editable = exists
	stock_mode.disabled = not exists
	style.disabled = not exists
	name_edit.text = str(dealer.get("name",""))
	tier_edit.text = str(dealer.get("tier",""))
	var at := _position(dealer) if exists else Vector2.ZERO
	x_spin.max_value = float(editor.authoring.doc.world.width) if editor.source_ready else 24000
	y_spin.max_value = float(editor.authoring.doc.world.height) if editor.source_ready else 24000
	x_spin.value = at.x
	y_spin.value = at.y
	width_spin.value = float(dealer.get("lot_width_m",32))
	depth_spin.value = float(dealer.get("lot_depth_m",20))
	var texture := str(dealer.get("texture",""))
	for i in style.item_count:
		if str(style.get_item_metadata(i))==texture:
			style.select(i)
			break
	stock_mode.select(1 if str(dealer.get("inventory_mode","automatic"))=="manual" else 0)
	_syncing = false
	_refresh_stock()

func _save(values: Dictionary) -> void:
	if _syncing or selected_id.is_empty() or editor._editing_locked():
		return
	if editor.authoring.update_dealership(selected_id,values):
		editor._refresh_authoring()
		_refresh_dealers()
	else:
		editor._notice(editor.authoring.last_error)

func _save_text() -> void:
	if _syncing or selected_id.is_empty():
		return
	_save({"name":name_edit.text.strip_edges().left(100),
		"tier":tier_edit.text.strip_edges().left(80)})

func _save_geometry() -> void:
	if _syncing or selected_id.is_empty():
		return
	_save({"x":x_spin.value,"y":y_spin.value,
		"lot_width_m":width_spin.value,"lot_depth_m":depth_spin.value})

func _style_changed(_index: int) -> void:
	if _syncing:
		return
	_save({"texture":str(style.get_item_metadata(style.selected))})

func _mode_changed(index: int) -> void:
	if _syncing:
		return
	var values: Dictionary={"inventory_mode":"manual" if index==1 else "automatic"}
	if index==1:
		var shop := _source()
		if str(shop.get("inventory_mode","automatic"))!="manual":
			var ids: Array=[]
			for vehicle in Config.available_inventory(shop):
				ids.append(str(vehicle.id))
			values["inventory"]=ids
	_save(values)

func _refresh_stock() -> void:
	if not is_instance_valid(stock):
		return
	_syncing = true
	stock.clear()
	var shop := _source()
	var manual := str(shop.get("inventory_mode","automatic"))=="manual"
	stock.mouse_filter = Control.MOUSE_FILTER_STOP if manual else Control.MOUSE_FILTER_IGNORE
	var selected_ids: Array = shop.get("inventory",[]) if manual else []
	var count_total := 0
	for car in Catalog.all():
		var id := str(car.get("id",""))
		var title := str(car.get("display_name",id))
		if not stock_search.text.is_empty() and stock_search.text.to_lower() not in (title+" "+id).to_lower():
			continue
		stock.add_item("%s  |  $%s"%[title,str(car.get("price_usd",0))])
		stock.set_item_metadata(stock.item_count-1,id)
		if id in selected_ids:
			stock.select(stock.item_count-1,false)
		count_total += 1
	count.text=("%d visible models  ·  %d selected"%[count_total,selected_ids.size()]) if manual else 		("%d catalog models; automatic assignment by dealership ID"%count_total)
	_syncing = false

func _stock_changed(_index: int,_selected_now: bool) -> void:
	if _syncing:
		return
	var existing: Array = _source().get("inventory",[]).duplicate()
	for i in stock.item_count:
		var id := str(stock.get_item_metadata(i))
		var included := stock.is_selected(i)
		if included and id not in existing:
			existing.append(id)
		elif not included and id in existing:
			existing.erase(id)
	_save({"inventory":existing})

func _start_new() -> void:
	placing_new = true
	_place_mode()

func _start_move() -> void:
	if selected_id.is_empty():
		return
	placing_new = false
	_place_mode()

func _place_mode() -> void:
	if editor.map_switcher.custom:
		editor._notice("Use a dealership marker for custom-map stock, or edit an existing placed shop.");return
	dialog.hide()
	editor._choose_tool("place_dealership")
	editor._notice("Click on the map for the dealership center. Keep at least 35 m from a road, with room for the forecourt.")

func pick(point_px: Vector2) -> String:
	var best := 18.0
	var result := ""
	for dealer in editor.authoring.dealership_list():
		var distance := _position(dealer).distance_to(point_px/PPM)
		if distance < best:
			best = distance
			result = str(dealer.id)
	return result

func place_at(position_m: Vector2) -> void:
	if not editor.source_ready or editor.map_switcher.custom:
		return
	var depth := 20.0 if placing_new else float(_source().get("lot_depth_m",20))
	var nearest: Dictionary=editor.world.nearest_road_at(position_m*PPM,110.0)
	if nearest.is_empty():
		editor._notice("No road within 110 m. Choose a roadside location.")
		return
	var distance := position_m.distance_to(Vector2(nearest.closest_point_px)/PPM)
	if distance < maxf(28.0,depth+14.5) or distance>105.0:
		editor._notice("Place the center farther from the road, leaving space for the entire drive-in lot.")
		return
	if not bool(editor.world.can_place_at(position_m*PPM,15.0,1.0).clear):
		editor._notice("The dealership building overlaps existing scenery or a road.")
		return
	var outward: Vector2=(position_m-Vector2(nearest.closest_point_px)/PPM).normalized()
	var parking: Vector2=position_m-outward*17.0
	if not bool(editor.world.can_place_at(parking*PPM,4.0,0.0).clear):
		editor._notice("The dealership parking area is obstructed. Choose a clearer roadside location.")
		return
	var ok := false
	if placing_new:
		var id: String = str(editor.authoring.add_dealership(position_m))
		ok = not id.is_empty()
		if ok:
			selected_id = id
	else:
		ok = editor.authoring.update_dealership(selected_id,{"x":position_m.x,"y":position_m.y})
	if not ok:
		editor._notice(editor.authoring.last_error)
		return
	placing_new = false
	editor._choose_tool("move_prop")
	editor._refresh_authoring()
	editor._notice("Dealership area placed. Save to Game, then Reload World to drive into it.")
	open_for(selected_id)

func _delete() -> void:
	if selected_id.is_empty():
		return
	if editor.authoring.delete_dealership(selected_id):
		selected_id = ""
		editor._refresh_authoring()
		_refresh_dealers()
		editor._notice("Custom dealership removed or default shop reset. Undo is available.")
	else:
		editor._notice("Default dealerships cannot be removed until overridden; use this to reset saved changes.")
