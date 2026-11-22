extends Node2D
@onready var online_session: Node = get_node_or_null("/root/OnlineSession")
## Free-roam online world: host simulates guest physics using the SAME
## VehicleController2D input seam; clients predict their own car and interpolate
## remote cars. Competitive races/progression are deliberately not networked.
const VehicleScene = preload("res://scenes/vehicle.tscn")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const RemoteBuffer = preload("res://scripts/network/remote_snapshot_buffer.gd")
# Client command response: <=16.7 ms scheduling at 120 Hz physics, rather
# than the previous 33.3 ms. Hold-state heartbeat avoids idle bandwidth.
const INPUT_RATE := 1.0 / 60.0
const INPUT_HEARTBEAT := 0.10
# Host authoritative replication: 30 Hz rather than 15 Hz. This does not
# change the game's fixed 120 Hz physics or the player's local input loop.
const SNAPSHOT_RATE := 1.0 / 30.0
const COMMAND_TIMEOUT_MS := 450
const NETWORK_STATS_INTERVAL := 0.5

var local_vehicle: VehicleController2D
var world: Node2D
var peer_cars: Dictionary = {}
var peer_models: Dictionary = {}
var peer_labels: Dictionary = {}
var targets: Dictionary = {}
var histories: Dictionary = {}
var commands_at: Dictionary = {}
var _input_elapsed := 0.0
var _input_heartbeat_elapsed := INPUT_HEARTBEAT
var _last_sent_command := Vector4(-1, -1, -1, -1)
var _last_sent_nitrous := false
var _snapshot_elapsed := 0.0
var _snapshot_sequence := 0
var _last_received_sequence := -1
var _first_authoritative_state := true
var _rtt_variation_ms := 0.0
var _quality_elapsed := NETWORK_STATS_INTERVAL
var _interpolation_delay_ms := 55
var roster_label: Label
var quality_label: Label
var invitation_toolbar: HBoxContainer
var lock_lobby_button: Button

func _ready() -> void:
	name = "OnlineWorld"
	online_session.roster_changed.connect(_sync_peers)
	online_session.session_closed.connect(_session_closed)
	roster_label = Label.new()
	roster_label.name = "OnlineRoster"
	roster_label.position = Vector2(20, 16)
	roster_label.add_theme_font_size_override("font_size", 16)
	roster_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quality_label = Label.new()
	quality_label.name = "NetworkQuality"
	quality_label.position = Vector2(20, 82)
	quality_label.add_theme_font_size_override("font_size", 13)
	quality_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quality_label.text = "NETWORK RTT: measuring..."
	var overlay := CanvasLayer.new()
	overlay.layer = 4
	overlay.add_child(roster_label)
	overlay.add_child(quality_label)
	if online_session.hosting:
		invitation_toolbar = HBoxContainer.new()
		invitation_toolbar.name = "PrivateLobbyActions"
		invitation_toolbar.position = Vector2(20, 44)
		invitation_toolbar.add_theme_constant_override("separation", 6)
		for title in ["COPY INVITE", "NEW CODE", "LOCK LOBBY"]:
			var action := Button.new()
			action.text = title
			action.add_theme_font_size_override("font_size", 13)
			invitation_toolbar.add_child(action)
			match title:
				"COPY INVITE":
					action.pressed.connect(_copy_invite)
				"NEW CODE":
					action.pressed.connect(_new_invite)
				"LOCK LOBBY":
					lock_lobby_button = action
					action.pressed.connect(_toggle_lobby_lock)
		overlay.add_child(invitation_toolbar)
	add_child(overlay)
	_sync_peers()
	online_session.mark_world_ready()

func _copy_invite() -> void:
	if not online_session.hosting:
		return
	var code: String = online_session.get_invite_code()
	if code.is_empty():
		online_session.status_changed.emit("Set a reachable host address to share an invitation.")
		return
	if DisplayServer.get_name() != "headless":
		DisplayServer.clipboard_set(code)
	online_session.status_changed.emit("Private invitation copied. Share it only with trusted friends.")

func _new_invite() -> void:
	if online_session.hosting:
		online_session.rotate_invite()
		_copy_invite()

func _toggle_lobby_lock() -> void:
	if not online_session.hosting:
		return
	online_session.set_lobby_locked(not online_session.lobby_locked)
	if is_instance_valid(lock_lobby_button):
		lock_lobby_button.text = ("UNLOCK LOBBY" if online_session.lobby_locked
			else "LOCK LOBBY")

func _sync_peers() -> void:
	if not online_session.active or not is_instance_valid(local_vehicle):
		return
	var own_id: int = int(online_session.own_id())
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
	histories.erase(id)
	commands_at.erase(id)

func _refresh_roster_label() -> void:
	if not is_instance_valid(roster_label):
		return
	roster_label.text = "PRIVATE %s   %d/%d DRIVERS%s" % [
		"HOST" if online_session.hosting else "GUEST",
		online_session.players.size(), online_session.MAX_PLAYERS,
		"  /  LOCKED" if online_session.lobby_locked and online_session.hosting else ""]

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
			_snapshot_sequence += 1
			var states: Dictionary = {1: _car_state(local_vehicle)}
			for id in peer_cars:
				states[id] = _car_state(peer_cars[id] as VehicleController2D)
			for id in online_session.world_ready_peers:
				if online_session.players.has(id):
					_receive_states.rpc_id(int(id), _snapshot_sequence, states)
	else:
		_input_elapsed += dt
		_input_heartbeat_elapsed += dt
		if _input_elapsed >= INPUT_RATE:
			_input_elapsed = fmod(_input_elapsed, INPUT_RATE)
			var latest_command: Vector4 = local_vehicle.command
			var latest_nitrous: bool = local_vehicle.nitrous_requested
			if latest_command != _last_sent_command or \
					latest_nitrous != _last_sent_nitrous or \
					_input_heartbeat_elapsed >= INPUT_HEARTBEAT:
				_submit_controls.rpc_id(1, latest_command, latest_nitrous)
				_last_sent_command = latest_command
				_last_sent_nitrous = latest_nitrous
				_input_heartbeat_elapsed = 0.0
		var my_state: Array = targets.get(online_session.own_id(), [])
		if my_state.size() >= 3:
			var error_px: float = local_vehicle.global_position.distance_to(my_state[0])
			if error_px > 700.0:
				# Spawn, reset and large divergence should converge immediately.
				local_vehicle.global_position = my_state[0]
				local_vehicle.rotation = my_state[1]
				local_vehicle.linear_velocity = my_state[2]
				local_vehicle.reset_physics_interpolation()
			elif error_px > 20.0:
				# Local input is predicted immediately; only recover the error
				# softly. Small errors do not fight the player's steering.
				var correction := clampf((error_px - 20.0) / 280.0, 0.0, 1.0)
				var blend := clampf(dt * (2.0 + correction * 8.0), 0.0, 0.15)
				local_vehicle.global_position = local_vehicle.global_position.lerp(
					my_state[0], blend)

func _process(dt: float) -> void:
	if not online_session.active:
		return
	_quality_elapsed += dt
	if _quality_elapsed >= NETWORK_STATS_INTERVAL:
		_quality_elapsed = fmod(_quality_elapsed, NETWORK_STATS_INTERVAL)
		_update_network_quality()
	var now_ms := Time.get_ticks_msec()
	for id in peer_cars:
		var car := peer_cars[id] as VehicleController2D
		if not online_session.hosting:
			var samples: Array = histories.get(id, [])
			var state: Array = RemoteBuffer.sample(
				samples, now_ms, _interpolation_delay_ms)
			if state.size() == 6:
				# Only remote visuals are interpolated. Never client-drive another
				# player's authoritative physics or position via RPC.
				car.global_position = state[0]
				car.rotation = state[1]
				car.linear_velocity = state[2]
				car.steering = float(state[3])
				car.longitudinal_speed = float(state[4])
				car.yaw_rate = float(state[5])
		if peer_labels.has(id):
			var tag := peer_labels[id] as Label
			tag.position = car.global_position + Vector2(-90, -115)
			tag.size = Vector2(180, 25)

func _update_network_quality() -> void:
	if not is_instance_valid(quality_label):
		return
	var observed: Dictionary = {}
	if online_session.hosting:
		for id in online_session.players:
			if int(id) == 1:
				continue
			var one: Dictionary = online_session.network_stats(int(id))
			if not one.is_empty() and int(one.get("rtt_ms", 0)) > \
					int(observed.get("rtt_ms", -1)):
				observed = one
	else:
		observed = online_session.network_stats()
	if observed.is_empty() or int(observed.get("rtt_ms", 0)) <= 0:
		quality_label.text = "NETWORK RTT: measuring..." if not online_session.hosting else \
			"PEER RTT: no samples"
		return
	_rtt_variation_ms = float(observed.get("variation_ms", 0))
	_interpolation_delay_ms = RemoteBuffer.interpolation_delay_ms(
		SNAPSHOT_RATE * 1000.0, _rtt_variation_ms)
	var loss: float = float(observed.get("reliable_loss_percent", -1.0))
	var loss_text := "%.1f%%" % loss if loss >= 0.0 else "measuring"
	quality_label.text = "%s %d ms  |  RTT VAR %d ms  |  REL-LOSS %s" % [
		"MAX PEER RTT" if online_session.hosting else "RTT",
		int(observed.get("rtt_ms", 0)),
		int(observed.get("variation_ms", 0)), loss_text]

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
func _receive_states(sequence: int, states: Dictionary) -> void:
	if online_session.hosting or not online_session.active or \
			sequence <= _last_received_sequence:
		return
	_last_received_sequence = sequence
	var now_ms := Time.get_ticks_msec()
	for id in states:
		if not online_session.players.has(id) or not states[id] is Array or \
				(states[id] as Array).size() != 6:
			continue
		var state: Array = states[id]
		# Reject malformed transforms before touching the render-only cars.
		if not (state[0] is Vector2) or not (state[2] is Vector2):
			continue
		targets[int(id)] = state
		if int(id) != online_session.own_id():
			var samples: Array = histories.get(int(id), [])
			RemoteBuffer.add_snapshot(samples, now_ms, state)
			histories[int(id)] = samples
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
