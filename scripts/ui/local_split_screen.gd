extends CanvasLayer
## Two players, one physics world, two cameras. Desktop first: keyboard/mouse
## + gamepad, or two different gamepads. No network or second world instance.
const VehicleScene = preload("res://scenes/vehicle.tscn")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const SplitCamera = preload("res://scripts/camera/local_split_camera.gd")
const MOVEMENT := ["throttle","brake","left","right","handbrake","nitrous"]
const COMMANDS := ["reset","shift_up","shift_down","transmission"]

var player_one: VehicleController2D
var player_two: VehicleController2D
var world: Node2D
var inventory: RefCounted
var main_camera: Camera2D
var hidden_layers: Array[CanvasLayer] = []
var disabled_systems: Array[Node] = []
var active := false
var controller_ids: Array[int] = []
var player_one_controller := -1 # -1 means keyboard / mouse.
var player_two_controller := -1
var screen_root: Control
var split_row: HBoxContainer
var split_views: Array[SubViewport] = []
var split_cameras: Array[Camera2D] = []
var player_stats: Array[Label] = []
var player_hints: Array[Label] = []
var held: Array[Dictionary] = [{},{}]
var previous_layer_state: Dictionary = {}
var previous_system_state: Dictionary = {}
var previous_camera_state: Dictionary = {}
var warning: String = ""
var _warning_clock := 0.0
var _stream_enabled := false

func _ready() -> void:
	layer = 12
	name = "LocalSplitScreen"
	# The manager is in the running world, not in the always-processing
	# pause layer. This prevents held controls from moving cars in menus.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_physics_process_priority(-80)
	screen_root = Control.new()
	screen_root.name = "SplitScreenRoot"
	screen_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(screen_root)
	split_row = HBoxContainer.new()
	split_row.name = "SplitScreenRow"
	split_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	split_row.add_theme_constant_override("separation",4)
	screen_root.add_child(split_row)
	screen_root.visible = false
	set_process(false)
	set_physics_process(false)
	set_process_input(false)

func _inputs() -> void:
	for state in held:
		state.clear()
		for action in MOVEMENT:
			state[action] = 0.0

func _set_single_player_visible(show: bool) -> void:
	for layer_node in hidden_layers:
		if not is_instance_valid(layer_node):
			continue
		if not previous_layer_state.has(layer_node):
			previous_layer_state[layer_node] = {
				"visible":layer_node.visible,
				"process":layer_node.is_processing(),
				"input":layer_node.is_processing_input(),
				"unhandled":layer_node.is_processing_unhandled_input()
			}
		var original: Dictionary = previous_layer_state[layer_node]
		layer_node.visible = bool(original.visible) if show else false
		layer_node.set_process(bool(original.process) if show else false)
		layer_node.set_process_input(bool(original.input) if show else false)
		layer_node.set_process_unhandled_input(
			bool(original.unhandled) if show else false)
	for system in disabled_systems:
		if not is_instance_valid(system):
			continue
		if not previous_system_state.has(system):
			previous_system_state[system] = {
				"process":system.is_processing(),
				"physics":system.is_physics_processing(),
				"input":system.is_processing_input(),
				"unhandled":system.is_processing_unhandled_input()
			}
		var original: Dictionary = previous_system_state[system]
		system.set_process(bool(original.process) if show else false)
		system.set_physics_process(bool(original.physics) if show else false)
		system.set_process_input(bool(original.input) if show else false)
		system.set_process_unhandled_input(
			bool(original.unhandled) if show else false)
	if show:
		previous_layer_state.clear()
		previous_system_state.clear()

func _set_main_camera(enabled_now: bool) -> void:
	if not is_instance_valid(main_camera):
		return
	if previous_camera_state.is_empty():
		previous_camera_state = {
			"enabled":main_camera.enabled,
			"physics":main_camera.is_physics_processing(),
			"unhandled":main_camera.is_processing_unhandled_input()
		}
	main_camera.enabled = bool(previous_camera_state.enabled) if enabled_now else false
	main_camera.set_physics_process(
		bool(previous_camera_state.physics) if enabled_now else false)
	main_camera.set_process_unhandled_input(
		bool(previous_camera_state.unhandled) if enabled_now else false)
	if enabled_now:
		previous_camera_state.clear()
		main_camera.make_current()

func start_split(connected_override: Array[int] = []) -> bool:
	if active or not is_instance_valid(player_one) or not is_instance_valid(world):
		return false
	var pads: Array[int] = connected_override.duplicate() if not connected_override.is_empty() else \
		Input.get_connected_joypads()
	pads.sort()
	if pads.is_empty():
		warning = "Connect a controller to start 2-player split-screen."
		return false
	controller_ids = pads
	player_one_controller = pads[0] if pads.size() >= 2 else -1
	player_two_controller = pads[1] if pads.size() >= 2 else pads[0]
	_inputs()
	# A second instance of the same physics scene; the world and tile stream
	# are NOT cloned. Existing single-player inventory is not altered.
	player_two = VehicleScene.instantiate() as VehicleController2D
	player_two.name = "SplitPlayerTwo"
	player_two.position = player_one.position + \
		Vector2(86.0,-35.0).rotated(player_one.rotation)
	player_two.rotation = player_one.rotation
	player_two.surface_provider = world
	player_two.external_input = true
	player_two.z_index = 9
	get_parent().add_child(player_two)
	player_two.add_to_group("local_multiplayer_vehicle")
	var car_id := str(inventory.get("active_id")) if is_instance_valid(inventory) else ""
	var entry: Dictionary = Catalog.find_by_id(car_id)
	if not entry.is_empty():
		Catalog.select(player_two,entry)
	# Equal base performance without sharing mutable resources or career data.
	player_two.config = player_one.config.duplicate(true)
	player_two.transmission.reset(player_two.config)
	# Player 2 is visually distinguishable but shares its real physical model.
	var body := player_two.get_node_or_null("Art/Sprite") as Sprite2D
	if is_instance_valid(body):
		body.modulate = Color(0.69,0.85,1.0)
	player_two.spawn_transform = player_two.transform
	player_two.reset_physics_interpolation()
	player_one.external_input = true
	_build_views()
	_set_single_player_visible(false)
	_set_main_camera(false)
	_stream_enabled = world.has_method("set_secondary_stream_vehicle")
	if _stream_enabled:
		world.call("set_secondary_stream_vehicle",player_two)
	active = true
	screen_root.visible = true
	set_process(true)
	set_physics_process(true)
	set_process_input(true)
	return true

func _build_views() -> void:
	for old in split_row.get_children():
		split_row.remove_child(old)
		old.queue_free()
	split_views.clear()
	split_cameras.clear()
	player_stats.clear()
	player_hints.clear()
	var players: Array[VehicleController2D] = [player_one,player_two]
	for i in 2:
		var view_box := SubViewportContainer.new()
		view_box.name = "Player%dView" % (i+1)
		view_box.stretch = true
		view_box.custom_minimum_size = Vector2(150,120)
		view_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		view_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view_box.size_flags_stretch_ratio = 1.0
		view_box.mouse_filter = Control.MOUSE_FILTER_STOP
		split_row.add_child(view_box)
		var viewport := SubViewport.new()
		viewport.name = "Player%dWorld" % (i+1)
		viewport.disable_3d = true
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.world_2d = get_viewport().world_2d
		viewport.size = Vector2i(720,720)
		view_box.add_child(viewport)
		split_views.append(viewport)
		var camera := Camera2D.new()
		camera.name = "Player%dCamera" % (i+1)
		camera.set_script(SplitCamera)
		camera.target = players[i]
		camera.zoom = Vector2(1.10,1.10)
		viewport.add_child(camera)
		camera.make_current()
		split_cameras.append(camera)
		var hud_layer := CanvasLayer.new()
		hud_layer.layer = 5
		viewport.add_child(hud_layer)
		var header := PanelContainer.new()
		header.name = "Player%dDashboard" % (i+1)
		header.position = Vector2(12,12)
		header.custom_minimum_size = Vector2(265,86)
		var skin := StyleBoxFlat.new()
		skin.bg_color = Color(0.035,0.07,0.085,0.91)
		skin.border_color = Color("#f2ae70") if i==0 else Color("#79b9e9")
		skin.set_border_width_all(2)
		skin.set_corner_radius_all(8)
		skin.content_margin_left = 12
		skin.content_margin_right = 12
		skin.content_margin_top = 9
		skin.content_margin_bottom = 9
		header.add_theme_stylebox_override("panel",skin)
		hud_layer.add_child(header)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation",4)
		header.add_child(box)
		var name_label := Label.new()
		name_label.name = "PlayerLabel"
		name_label.text = "P%d  /  %s" % [i+1,
			"KEYBOARD" if i==0 and player_one_controller == -1 else
			"CONTROLLER %d" % (player_one_controller+1 if i==0 else player_two_controller+1)]
		name_label.add_theme_font_size_override("font_size",14)
		box.add_child(name_label)
		var speed_label := Label.new()
		speed_label.name = "SpeedAndGear"
		speed_label.add_theme_font_size_override("font_size",21)
		box.add_child(speed_label)
		player_stats.append(speed_label)
		var note := Label.new()
		note.name = "InputStatus"
		note.add_theme_font_size_override("font_size",11)
		note.add_theme_color_override("font_color",Color("#bcd1cc"))
		box.add_child(note)
		player_hints.append(note)
	_refresh_stats()

func _event_device(event: InputEvent) -> int:
	if event is InputEventKey or event is InputEventMouseButton:
		return -1
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return event.device
	return -100

func _player_for_event(event: InputEvent) -> int:
	var device := _event_device(event)
	if device == -100:
		return -1
	if device == player_one_controller:
		return 0
	if device == player_two_controller:
		return 1
	return -1

func route_input(event: InputEvent) -> void:
	if not active or get_tree().paused:
		return
	var index := _player_for_event(event)
	if index < 0:
		return
	var car := player_one if index==0 else player_two
	if not is_instance_valid(car):
		return
	for action in MOVEMENT:
		if event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			# Read the matching axis and sign directly, including a return
			# to neutral. Global Input strengths would blend both players.
			for binding in InputMap.action_get_events(action):
				if binding is InputEventJoypadMotion and \
						(binding as InputEventJoypadMotion).axis == motion.axis:
					var direction := signf((binding as InputEventJoypadMotion).axis_value)
					var raw := motion.axis_value * direction
					held[index][action] = clampf(
						(raw-0.15)/0.85,0.0,1.0)
					break
		elif event.is_action_pressed(action):
			held[index][action] = 1.0
		elif event.is_action_released(action):
			held[index][action] = 0.0
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event is InputEventJoypadMotion:
		return
	if not event.is_pressed():
		return
	if event.is_action_pressed("reset"):
		car.reset_vehicle()
	elif event.is_action_pressed("transmission"):
		car.transmission.automatic = not car.transmission.automatic
	elif event.is_action_pressed("shift_up"):
		car.transmission.shift(1,car.config)
	elif event.is_action_pressed("shift_down"):
		car.transmission.shift(-1,car.config)

func _input(event: InputEvent) -> void:
	route_input(event)

func _physics_process(_dt: float) -> void:
	if not active:
		return
	var players: Array[VehicleController2D] = [player_one,player_two]
	for i in 2:
		var p := players[i]
		if not is_instance_valid(p):
			continue
		var state: Dictionary = held[i]
		p.command = Vector4(
			float(state.get("throttle",0.0)),
			float(state.get("brake",0.0)),
			float(state.get("right",0.0))-float(state.get("left",0.0)),
			float(state.get("handbrake",0.0))
		)
		p.nitrous_requested = float(state.get("nitrous",0.0))>0.5

func _process(dt: float) -> void:
	if not active:
		return
	_warning_clock -= dt
	if _warning_clock<=0.0:
		_warning_clock = 0.25
		_refresh_stats()

func _refresh_stats() -> void:
	for i in mini(2,player_stats.size()):
		var p: VehicleController2D = player_one if i==0 else player_two
		if not is_instance_valid(p):
			continue
		var mph := int(roundf(p.linear_velocity.length()*2.236936))
		var gear := "R" if p.reversing else \
			"AUTO" if p.transmission.automatic else "MANUAL"
		player_stats[i].text = "%d MPH  •  %s" % [mph,gear]
		var pad_id := player_one_controller if i==0 else player_two_controller
		var disconnected := pad_id >= 0 and not Input.get_connected_joypads().has(pad_id)
		player_hints[i].text = "CONTROLLER DISCONNECTED" if disconnected else \
			"FREE ROAM  •  PAUSE TO EXIT"
		if disconnected:
			for action in MOVEMENT:
				held[i][action] = 0.0

func stop_split() -> void:
	if not active:
		return
	active = false
	screen_root.visible = false
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	_inputs()
	if _stream_enabled and is_instance_valid(world):
		world.call("set_secondary_stream_vehicle",null)
	_stream_enabled = false
	for viewport in split_views:
		if is_instance_valid(viewport):
			viewport.get_parent().queue_free()
	split_views.clear()
	split_cameras.clear()
	player_stats.clear()
	player_hints.clear()
	if is_instance_valid(player_two):
		player_two.queue_free()
	player_two = null
	player_one.external_input = false
	player_one.command = Vector4.ZERO
	player_one.nitrous_requested = false
	_set_main_camera(true)
	_set_single_player_visible(true)
	controller_ids.clear()
	player_one_controller = -1
	player_two_controller = -1
