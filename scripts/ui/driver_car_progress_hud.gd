extends CanvasLayer
## Compact, always-current player + currently equipped vehicle progression.
## The dealership and garage share this exact economy/XP data model.
const Progress = preload("res://scripts/vehicle/race_progression.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
var economy: VehicleOwnership
var player_label: Label
var car_label: Label
var player_bar: ProgressBar
var car_bar: ProgressBar
var rarity_label: Label


func _ready() -> void:
	name = "DriverCarProgressHUD"
	layer = 4
	var shell := PanelContainer.new()
	shell.name = "ProgressionPanel"
	shell.position = Vector2(766,24)
	shell.custom_minimum_size = Vector2(325,108)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035,0.07,0.082,0.92)
	style.border_color = Color("52685f")
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 13
	style.content_margin_top = 8
	style.content_margin_right = 13
	style.content_margin_bottom = 9
	shell.add_theme_stylebox_override("panel",style)
	add_child(shell)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",4)
	shell.add_child(col)
	player_label = _label(col,"DRIVER LV 1/100  /  0 XP",13)
	player_bar = _bar(col)
	car_label = _label(col,"CAR LV 1/50  /  0 XP",13)
	car_bar = _bar(col)
	rarity_label = _label(col,"NEXT UPGRADE RARITY  /  COMMON LV 10",11)
	rarity_label.add_theme_color_override("font_color",Color("c2d0c0"))
	if is_instance_valid(economy):
		economy.changed.connect(refresh)
	refresh()


func _label(parent: VBoxContainer, value: String, size: int) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size",size)
	parent.add_child(node)
	return node


func _bar(parent: VBoxContainer) -> ProgressBar:
	var node := ProgressBar.new()
	node.max_value = 100.0
	node.show_percentage = false
	node.custom_minimum_size.y = 6.0
	parent.add_child(node)
	return node


func refresh() -> void:
	if not is_instance_valid(economy) or player_label == null:
		return
	var player_level := economy.player_level()
	var car_level := economy.active_car_level()
	var car_id := str(economy.active_id)
	var entry := Catalog.find_by_id(car_id)
	player_label.text = "DRIVER LV %d/100  /  %s" % [
		player_level, "MAX LEVEL" if player_level >= 100 else \
		"%d XP TO NEXT" % Progress.player_xp_remaining(economy.player_xp)]
	car_label.text = "%s  /  CAR LV %d/50" % [
		str(entry.get("display_name","CAR")).to_upper(),car_level]
	player_bar.value = Progress.player_level_progress(economy.player_xp)*100.0
	car_bar.value = Progress.car_level_progress(int(economy.car_xp.get(car_id,0)))*100.0
	if car_level == 50:
		rarity_label.text = "MAX CAR LEVEL  /  LEGENDARY PARTS UNLOCKED"
	else:
		var tier := Progress.highest_upgrade_rarity(car_level)
		var next_tier := "Common"
		var next_level := 10
		for rarity in ["Common","Uncommon","Rare","Epic","Legendary"]:
			if car_level < int(Progress.RARITY_THRESHOLDS[rarity]):
				next_tier = rarity
				next_level = int(Progress.RARITY_THRESHOLDS[rarity])
				break
		rarity_label.text = "UPGRADE %s  /  %s AT LV %d  /  %d XP NEXT" % [
			tier.to_upper(),next_tier.to_upper(),next_level,
			Progress.car_xp_remaining(int(economy.car_xp.get(car_id,0)))]
