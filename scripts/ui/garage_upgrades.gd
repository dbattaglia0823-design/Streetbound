extends Control
## A dedicated garage page: eight slots on the left, owned parts for the
## chosen slot on the right. Parts belong to the player; loadouts to each car.
# Explicit script dependency: class_name lookups are not reliable before Godot imports.
const OwnershipModel = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Parts = preload("res://scripts/vehicle/upgrade_parts.gd")
const Progress = preload("res://scripts/vehicle/race_progression.gd")

var economy: OwnershipModel
var vehicle: VehicleController2D
var driving_hud: CanvasLayer
var selected_slot := "engine"
var title_label: Label
var stats_label: Label
var hint_label: Label
var feedback_label: Label
var inventory_label: Label
var slots_box: VBoxContainer
var parts_box: VBoxContainer
var unequip_button: Button
var last_result := ""


func _ready() -> void:
	name = "GarageUpgrades"
	process_mode = Node.PROCESS_MODE_ALWAYS
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation",10)
	add_child(layout)
	var top := VBoxContainer.new()
	layout.add_child(top)
	title_label = _label(top,"ACTIVE VEHICLE  /  UPGRADES",18,Color("#e8f3ed"))
	stats_label = _label(top,"STOCK VEHICLE",12,Color("#bad1c6"))
	hint_label = _label(top,"COMMON LV10   /   UNCOMMON LV20   /   RARE LV30   /   EPIC LV40   /   LEGENDARY LV50",
		12,Color("#e0c79d"))
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation",18)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(main)
	var slot_area := VBoxContainer.new()
	slot_area.custom_minimum_size.x = 265
	slot_area.add_theme_constant_override("separation",7)
	main.add_child(slot_area)
	_label(slot_area,"PART SLOTS",14,Color("#e9e0c7"))
	slots_box = VBoxContainer.new()
	slots_box.add_theme_constant_override("separation",5)
	slot_area.add_child(slots_box)
	unequip_button = Button.new()
	unequip_button.name = "UnequipSelectedSlot"
	unequip_button.text = "REMOVE INSTALLED PART"
	unequip_button.custom_minimum_size.y = 35
	unequip_button.pressed.connect(_unequip_current_slot)
	slot_area.add_child(unequip_button)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation",6)
	main.add_child(right)
	inventory_label = _label(right,"INVENTORY",15,Color("#e9e0c7"))
	feedback_label = _label(right,"Earn parts by finishing races. Installed parts modify handling and performance.",12,
		Color("#a5d5c6"))
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll := ScrollContainer.new()
	scroll.name = "PartInventoryScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	parts_box = VBoxContainer.new()
	parts_box.name = "AvailableParts"
	parts_box.add_theme_constant_override("separation",8)
	parts_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(parts_box)
	if is_instance_valid(economy):
		economy.changed.connect(refresh)
	refresh()


func _label(parent: Node, value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _active_entry() -> Dictionary:
	if not is_instance_valid(economy):
		return {}
	return Catalog.find_by_id(str(economy.active_id))


func _stats_of(config: VehicleConfig) -> String:
	return "%d HP   /   %d LB-FT   /   GRIP %.2f   /   CORNER %.0f   /   BRAKES %.0f lbf" % [
		roundi(config.engine_power_kw*1.34102),
		roundi(config.engine_torque_nm*0.73756),
		config.tire_grip*config.rear_grip_balance,
		config.cornering_stiffness,
		config.brake_force_n*0.22480894]


func refresh() -> void:
	if slots_box == null or not is_instance_valid(economy):
		return
	var entry := _active_entry()
	if entry.is_empty():
		return
	var car_id := str(economy.active_id)
	var level := economy.active_car_level()
	title_label.text = "%s  /  CAR LV %d/50  /  %s ELIGIBLE" % [
		str(entry.display_name).to_upper(),level,
		economy.highest_upgrade_rarity(car_id).to_upper()]
	var stock: VehicleConfig = Catalog.make_configuration(entry)
	var upgraded: VehicleConfig = Catalog.make_configuration(entry)
	economy.apply_car_upgrades(upgraded,car_id)
	stats_label.text = "STOCK  %s\nEQUIPPED  %s" % [
		_stats_of(stock),_stats_of(upgraded)]
	_clear(slots_box)
	for slot in Parts.SLOTS:
		var current_uid := economy.equipped_uid(car_id,slot)
		var installed := Parts.get_part(str(economy.get_upgrade_item(current_uid).get("template","")))
		var button := Button.new()
		button.name = "Slot_" + slot.capitalize()
		button.custom_minimum_size.y = 45
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "%s  /  %s" % [
			Parts.slot_name(slot).to_upper(),
			"STOCK" if installed.is_empty() else \
				"%s  %s" % [str(installed.rarity),str(installed.specialty)]]
		if slot == selected_slot:
			button.add_theme_color_override("font_color",Color("#f3c982"))
		button.pressed.connect(_select_slot.bind(slot))
		slots_box.add_child(button)
	unequip_button.disabled = economy.equipped_uid(car_id,selected_slot).is_empty()
	var matched: Array[Dictionary] = []
	for item in economy.upgrade_inventory:
		var part := Parts.get_part(str(item.template))
		if not part.is_empty() and str(part.slot) == selected_slot:
			matched.append({"item":item,"template":part})
	var rarity_order := {"Common":0,"Uncommon":1,"Rare":2,"Epic":3,"Legendary":4}
	matched.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(rarity_order[str((a.template as Dictionary).rarity)]) > \
			int(rarity_order[str((b.template as Dictionary).rarity)]))
	inventory_label.text = "%s  /  %d OWNED PART%s   /   TOTAL %d" % [
		Parts.slot_name(selected_slot).to_upper(),matched.size(),
		"" if matched.size() == 1 else "S",economy.upgrade_inventory.size()]
	_clear(parts_box)
	if matched.is_empty():
		var no_parts := _label(parts_box,
			"NO PARTS FOR THIS SLOT\nFinish races to earn random parts.\nUnlocked parts can be equipped here.",
			15,Color("#aabfbb"))
		no_parts.custom_minimum_size.y = 92
		return
	for pair in matched:
		_add_part_card(pair.item,pair.template)


func _add_part_card(item: Dictionary, part: Dictionary) -> void:
	var box := PanelContainer.new()
	box.name = "Part_" + str(item.uid).replace("-","_")
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color("#152b31")
	sty.border_color = Parts.rarity_color(str(part.rarity))
	sty.set_border_width_all(1)
	sty.set_corner_radius_all(8)
	sty.set_content_margin_all(9)
	box.add_theme_stylebox_override("panel",sty)
	parts_box.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",3)
	box.add_child(col)
	var name := _label(col,str(part.name),16,Parts.rarity_color(str(part.rarity)))
	name.clip_text = true
	var mode_description := ""
	if str(part.specialty) == "Grip":
		mode_description = "GRIP / TRACK  —  stronger cornering stability"
	elif str(part.specialty) == "Drift":
		mode_description = "DRIFT  —  rotation and slide control"
	else:
		mode_description = "STREET / PERFORMANCE"
	_label(col,mode_description,11,Color("#b6c8c0"))
	var bonus := _label(col,Parts.summary(part),12,Color("#e8e0ce"))
	bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	col.add_child(actions)
	var requirement := int(Progress.RARITY_THRESHOLDS[str(part.rarity)])
	var required := _label(actions,"CAR LV %d REQUIRED" % requirement,11,Color("#adbeae"))
	required.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var use := Button.new()
	use.custom_minimum_size = Vector2(177,35)
	use.name = "Install_" + str(item.uid).replace("-","_")
	actions.add_child(use)
	var car_id := str(economy.active_id)
	var status := economy.can_install_part(car_id,str(item.uid))
	if economy.equipped_uid(car_id,str(part.slot)) == str(item.uid):
		use.text = "INSTALLED"
		use.disabled = true
	elif status == "level_locked":
		use.text = "LOCKED / LV %d" % requirement
		use.disabled = true
	elif status == "equipped_elsewhere":
		use.text = "ON ANOTHER CAR"
		use.disabled = true
	elif status == "ready":
		use.text = "INSTALL"
		use.pressed.connect(_equip.bind(str(item.uid)))
	else:
		use.text = "UNAVAILABLE"
		use.disabled = true


func _select_slot(slot: String) -> void:
	if not Parts.SLOTS.has(slot):
		return
	selected_slot = slot
	refresh()


func _equip(uid: String) -> void:
	var result := economy.install_part(str(economy.active_id),uid)
	if result == "installed":
		var part := Parts.get_part(str(economy.get_upgrade_item(uid).template))
		last_result = "INSTALLED: " + str(part.name)
		_apply_updated_configuration()
	else:
		last_result = "COULD NOT INSTALL: " + result
	feedback_label.text = last_result
	refresh()


func _unequip_current_slot() -> void:
	var result := economy.unequip_part(str(economy.active_id),selected_slot)
	if result == "removed":
		last_result = "RETURNED PART TO INVENTORY."
		_apply_updated_configuration()
	else:
		last_result = "COULD NOT REMOVE: " + result
	feedback_label.text = last_result
	refresh()


func _apply_updated_configuration() -> void:
	# This page only exists inside the stopped, paused garage. Rebuild from
	# stock + equipped parts; never compound a bonus on an already upgraded car.
	var entry := _active_entry()
	if entry.is_empty() or not is_instance_valid(vehicle):
		return
	if Catalog.select(vehicle,entry):
		economy.apply_car_upgrades(vehicle.config,str(economy.active_id))
		if is_instance_valid(driving_hud):
			driving_hud.on_vehicle_selected(entry)
