extends Node2D
@onready var online_session: Node = get_node_or_null("/root/OnlineSession")
## Free-roam online world: host simulates guest physics using the SAME
## VehicleController2D input seam; clients predict their own car and interpolate
## remote cars. Competitive races/progression are deliberately not networked.
const VehicleScene = preload("res://scenes/vehicle.tscn")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const INPUT_RATE := 1.0 / 30.0
const SNAPSHOT_RATE := 1.0 / 15.0
const COMMAND_TIMEOUT_MS := 450

var local_vehicle: VehicleController2D
var world: Node2D
var peer_cars: Dictionary = {}
var peer_models: Dictionary = {}
var peer_labels: Dictionary = {}
var targets: Dictionary = {}
var commands_at: Dictionary = {}
var _input_elapsed := 0.0
var _snapshot_elapsed := 0.0
var _first_authoritative_state := true
var roster_label: Label

func _ready() -> void:
	name = "OnlineWorld"
	online_session.roster_changed.connect(_sync_peers)
	online_session.session_closed.connect(_session_closed)
	roster_label = Label.new()
	roster_label.name = "OnlineRoster"
	roster_label.position = Vector2(20, 16)
	roster_label.add_theme_font_size_override("font_size", 16)
	roster_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay := CanvasLayer.new()
	overlay.layer = 4
	overlay.add_child(roster_label)
	add_child(overlay)
	_sync_peers()
	online_session.mark_world_ready()

func _sync_peers() -> void:
	if not online_session.active or not is_instance_valid(local_vehicle):
		return
	var own_id := online_session.own_id()
	for id in online_session.players:
		var peer_id := int(id)
		if peer_id == own_id:
			continue
		if not peer_cars.has(peer_id):
			_add_remote(peer_id)
		var record: Dictionary = online_session.players[id]
		var model_id := str(record.get("car_id", ""))
		if peer_models.get(peer_id, "") != model_id and not model_id.is_empty():
			var entry: Dictionary = Catalog.find_by_id(model_id)
			if not entry.is_empty():
				Catalog.select(peer_cars[peer_id] as VehicleController2D, entry)
				peer_models[peer_id] = model_id
		if peer_labels.has(peer_id):
			(peer_labels[peer_id] as Label).text = str(record.get("name", "Driver"))
	for id in peer_cars.keys():
		if not online_session.players.has(id):
			_remove_remote(int(id))
	_refresh_roster_label()

func _add_remote(id: int) -> void:
	var car := VehicleScene.instantiate() as VehicleController2D
	car.name = "Friend_%d" % id
	# Godot assigns large non-sequential peer IDs: use the four-seat roster
	# position, never the raw peer ID, to choose a safe spawn offset.
	var seat := maxi(1, online_session.players.keys().find(id))
	car.position = local_vehicle.global_position + \
		Vector2(85.0 * float(seat), 0).rotated(local_vehicle.rotation)
	car.surface_provider = world
	car.external_input = true
	car.collision_layer = 0  # No vehicle-on-vehicle crashes in this slice.
	car.collision_mask = 1 if online_session.hosting else 0
	car.z_index = 8
	add_child(car)
	# Only the host advances guest cars through the physical controller.
	car.set_physics_process(online_session.hosting)
	peer_cars[id] = car
	var nameplate := Label.new()
	nameplate.name = "Name_%d" % id
	nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nameplate.add_theme_font_size_override("font_size", 14)
	nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(nameplate)
	peer_labels[id] = nameplate

func _remove_remote(id: int) -> void:
	var car: Node = peer_cars.get(id)
	if is_instance_valid(car):
		car.queue_free()
	var nameplate: Node = peer_labels.get(id)
	if is_instance_valid(nameplate):
		nameplate.queue_free()
	peer_cars.erase(id)
	peer_labels.erase(id)
	peer_models.erase(id)
	targets.erase(id)
	commands_at.erase(id)

func _refresh_roster_label() -> void:
	if not is_instance_valid(roster_label):
		return
	roster_label.text = "ONLINE %s   %d/%d DRIVERS" % [
		"HOST" if online_session.hosting else "GUEST",
		online_session.players.size(), online_session.MAX_PLAYERS]

func _physics_process(dt: float) -> void:
	if not online_session.active:
		return
	if online_session.hosting:
		for id in peer_cars:
			var car := peer_cars[id] as VehicleController2D
			if Time.get_ticks_msec() - int(commands_at.get(id, 0)) > COMMAND_TIMEOUT_MS:
				car.command = Vector4.ZERO
				car.nitrous_requested = false
		_snapshot_elapsed += dt
		if _snapshot_elapsed >= SNAPSHOT_RATE:
			_snapshot_elapsed = fmod(_snapshot_elapsed, SNAPSHOT_RATE)
			var states: Dictionary = {1: _car_state(local_vehicle)}
			for id in peer_cars:
				states[id] = _car_state(peer_cars[id] as VehicleController2D)
			for id in online_session.world_ready_peers:
				if online_session.players.has(id):
					_receive_states.rpc_id(int(id), states)
	else:
		_input_elapsed += dt
		if _input_elapsed >= INPUT_RATE:
			_input_elapsed = fmod(_input_elapsed, INPUT_RATE)
			_submit_controls.rpc_id(1, local_vehicle.command,
				local_vehicle.nitrous_requested)
		var my_state: Array = targets.get(online_session.own_id(), [])
		if my_state.size() >= 3:
			var error_px: float = local_vehicle.global_position.distance_to(my_state[0])
			if error_px > 700.0:
				local_vehicle.global_position = my_state[0]
				local_vehicle.rotation = my_state[1]
				local_vehicle.linear_velocity = my_state[2]
				local_vehicle.reset_physics_interpolation()
			elif error_px > 90.0:
				# Small corrections keep local handling responsive. There is
				# no forced per-tick teleport or client-authoritative position.
				local_vehicle.global_position = local_vehicle.global_position.lerp(
					my_state[0], 0.045)

func _process(dt: float) -> void:
	for id in peer_cars:
		var car := peer_cars[id] as VehicleController2D
		if not online_session.hosting:
			var state: Array = targets.get(id, [])
			if state.size() >= 6:
				var fraction := clampf(dt * 11.0, 0.0, 1.0)
				car.global_position = car.global_position.lerp(state[0], fraction)
				car.rotation = lerp_angle(car.rotation, state[1], fraction)
				car.linear_velocity = state[2]
				car.steering = lerpf(car.steering, float(state[3]), fraction)
				car.longitudinal_speed = float(state[4])
				car.yaw_rate = float(state[5])
		if peer_labels.has(id):
			var tag := peer_labels[id] as Label
			tag.position = car.global_position + Vector2(-90, -115)
			tag.size = Vector2(180, 25)

static func _car_state(car: VehicleController2D) -> Array:
	return [car.global_position, car.rotation, car.linear_velocity,
		car.steering, car.longitudinal_speed, car.yaw_rate]

@rpc("any_peer", "unreliable_ordered")
func _submit_controls(input_command: Vector4, nitrous: bool) -> void:
	if not online_session.hosting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not online_session.players.has(sender) or \
			not online_session.world_ready_peers.has(sender) or not peer_cars.has(sender):
		return
	var car := peer_cars[sender] as VehicleController2D
	# Treat all client data as untrusted. Clients cannot set transforms,
	# money, upgrades or another player's controls through this RPC.
	car.command = Vector4(
		clampf(input_command.x, 0.0, 1.0), clampf(input_command.y, 0.0, 1.0),
		clampf(input_command.z, -1.0, 1.0), clampf(input_command.w, 0.0, 1.0))
	car.nitrous_requested = nitrous
	commands_at[sender] = Time.get_ticks_msec()

@rpc("authority", "unreliable_ordered")
func _receive_states(states: Dictionary) -> void:
	if online_session.hosting or not online_session.active:
		return
	for id in states:
		if states[id] is Array and (states[id] as Array).size() == 6:
			targets[int(id)] = states[id]
	var my_state: Array = targets.get(online_session.own_id(), [])
	if _first_authoritative_state and my_state.size() >= 3:
		_first_authoritative_state = false
		local_vehicle.global_position = my_state[0]
		local_vehicle.rotation = my_state[1]
		local_vehicle.linear_velocity = my_state[2]
		local_vehicle.reset_physics_interpolation()

func _unhandled_input(event: InputEvent) -> void:
	if not online_session.active or online_session.hosting or get_tree().paused:
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	for action in ["reset", "transmission", "shift_up", "shift_down"]:
		if event.is_action_pressed(action):
			_submit_action.rpc_id(1, action)
			break

@rpc("any_peer", "reliable")
func _submit_action(action: String) -> void:
	if not online_session.hosting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not online_session.players.has(sender) or not peer_cars.has(sender):
		return
	var car := peer_cars[sender] as VehicleController2D
	match action:
		"reset":
			car.reset_vehicle()
		"transmission":
			car.transmission.automatic = not car.transmission.automatic
		"shift_up":
			car.transmission.shift(1, car.config)
		"shift_down":
			car.transmission.shift(-1, car.config)

func _session_closed(reason: String) -> void:
	if reason != "Left online session." and get_parent().has_method("_return_to_main_menu"):
		get_parent().call_deferred("_return_to_main_menu")
