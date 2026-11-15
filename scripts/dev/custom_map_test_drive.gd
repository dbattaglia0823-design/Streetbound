extends Node2D
## Playtest a saved custom map without loading career, traffic or Morrow Coast.
const Library = preload("res://scripts/dev/native_map_library.gd")
const World = preload("res://scripts/dev/custom_map_drive_world.gd")
const Vehicle = preload("res://scenes/vehicle.tscn")
const Camera = preload("res://scripts/camera/driving_camera.gd")
const Audio = preload("res://scripts/audio/vehicle_audio.gd")

var source_file := ""
var player: VehicleController2D
var speed_label: Label
var returning := false

func _ready() -> void:
	if not (OS.has_feature("debug") or OS.has_feature("editor")):
		get_tree().call_deferred("change_scene_to_file","res://scenes/title_menu.tscn")
		return
	source_file = str(get_tree().get_meta("streetbound_test_drive_map",""))
	if get_tree().has_meta("streetbound_test_drive_map"):
		get_tree().remove_meta("streetbound_test_drive_map")
	if source_file.is_empty() or source_file.get_file()!=source_file or not source_file.ends_with(".world.json"):
		push_error("No valid custom map selected for Test Drive.")
		get_tree().call_deferred("change_scene_to_file","res://scenes/world_editor.tscn")
		return
	var doc := Library.load_map(source_file)
	var world := World.new()
	if not world.configure(doc):
		world.free()
		get_tree().set_meta("streetbound_editor_resume_map",source_file)
		push_error("Custom map Test Drive failed validation: "+source_file)
		get_tree().call_deferred("change_scene_to_file","res://scenes/world_editor.tscn")
		return
	add_child(world)
	var start: Dictionary = world.test_spawn()
	player = Vehicle.instantiate()
	player.position = start.position
	player.rotation = float(start.rotation)
	player.surface_provider = world
	player.z_index = 8
	add_child(player)
	player.add_to_group("player_vehicle")

	var camera := Camera.new()
	camera.target = player
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(camera)
	camera.add_to_group("player_camera")
	var audio := Audio.new()
	audio.vehicle = player
	add_child(audio)
	_build_hud(str(doc.get("name","Custom map")))
	get_window().title = "Streetbound | Test Drive: "+str(doc.get("name","Custom map"))

func _build_hud(map_name: String) -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 15
	add_child(canvas)
	var header := PanelContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 16
	header.offset_right = -16
	header.offset_top = 16
	header.offset_bottom = 70
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	canvas.add_child(header)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	header.add_child(row)
	var title := Label.new()
	title.text = "TEST DRIVE  /  "+map_name.to_upper()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	speed_label = Label.new()
	row.add_child(speed_label)
	var help := Label.new()
	help.text = "R reset  ·  F6 / Esc return"
	row.add_child(help)
	var button := Button.new()
	button.text = "Return to Map Editor  F6"
	button.pressed.connect(_return_to_editor)
	row.add_child(button)

func _process(_delta: float) -> void:
	if is_instance_valid(player) and is_instance_valid(speed_label):
		speed_label.text = "%d MPH  /  %s  /  G%d" % [
			roundi(player.linear_velocity.length()*2.236936),
			player.surface,player.transmission.gear]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and \
			(event.keycode in [KEY_F6,KEY_ESCAPE] or event.physical_keycode==KEY_F6):
		_return_to_editor()
		get_viewport().set_input_as_handled()

func _return_to_editor() -> void:
	if returning:
		return
	returning = true
	get_tree().set_meta("streetbound_editor_resume_map",source_file)
	if not get_tree().has_meta("streetbound_editor_return_position") and is_instance_valid(player):
		get_tree().set_meta("streetbound_editor_return_position",player.global_position)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/world_editor.tscn")
