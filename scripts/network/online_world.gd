extends Node2D
@onready var online_session: Node = get_node_or_null("/root/OnlineSession")
## Free-roam online world: host simulates guest physics using the SAME
## VehicleController2D input seam; clients predict their own car and interpolate
## remote cars. Competitive races/progression are deliberately not networked.
const VehicleScene = preload("res://scenes/vehicle.tscn")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const RemoteBuffer = preload("res://scripts/network/remote_snapshot_buffer.gd")
const FriendRaceScript = preload("res://scripts/network/online_friend_race.gd")
const FriendRobberyScript = preload("res://scripts/network/online_friend_robbery.gd")
const Police = preload("res://scripts/world/police_pursuit.gd")
const Emergency = preload("res://scripts/visual/police_emergency_effects.gd")
const DamageSmoke = preload("res://scripts/visual/engine_damage_smoke.gd")
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
# Host-authored cosmetic brake/reverse indicators. These never drive physics
# or reward logic, and older snapshots without the optional field still work.
var peer_light_states: Dictionary = {}
var peer_exhaust_states: Dictionary = {}
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
var _last_rtt_ms := 0.0
var _quality_elapsed := NETWORK_STATS_INTERVAL
var _interpolation_delay_ms := 55
var roster_label: Label
var quality_label: Label
var invitation_toolbar: HBoxContainer
var lock_lobby_button: Button
var friend_race: Node2D
var friend_robbery: Node2D
var shared_police: Node2D
var police_target_peer := 0
var police_target_original_layer := 0
var police_replicas: Dictionary = {}
var police_histories: Dictionary = {}
var police_status: Label
var police_panel: PanelContainer

func _ready() -> void:
	name = "OnlineWorld"
	online_session.roster_changed.connect(_sync_peers)
	online_session.session_closed.connect(_session_closed)
	online_session.reconnect_started.connect(_reconnect_started)
	online_session.reconnect_finished.connect(_reconnect_finished)
	online_session.peer_connection_suspended.connect(_peer_suspended)
	online_session.peer_id_rebound.connect(_rebind_peer_car)
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
	var hud_style = preload("res://scripts/ui/driving_hud.gd")
	police_panel = hud_style.status_card(overlay,Color("#ed796c"))
	police_panel.position = Vector2(20,106)
	police_status = hud_style.status_text(police_panel,"",16,Color("#ed796c"))
	add_child(overlay)
	var traffic: Node2D = world.get_node_or_null("AmbientTraffic") if is_instance_valid(world) else null
	if is_instance_valid(traffic):
		traffic.set("patrol_spawns_enabled", online_session.hosting)
		if online_session.hosting:
			shared_police = Node2D.new()
			shared_police.set_script(Police)
			shared_police.set("shared_session", true)
			shared_police.set("player", local_vehicle)
			shared_police.set("world", world)
			shared_police.set("traffic", traffic)
			add_child(shared_police)
			shared_police.connect("escaped", _release_police_target)
			local_vehicle.police_collision.connect(_on_police_collision.bind(local_vehicle), CONNECT_DEFERRED)
	friend_race = Node2D.new()
	friend_race.name = "FriendDragRace"
	friend_race.set_script(FriendRaceScript)
	add_child(friend_race)
	friend_robbery = Node2D.new()
	friend_robbery.name = "FriendRobbery"
	friend_robbery.set_script(FriendRobberyScript)
	add_child(friend_robbery)
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
			(peer_labels[peer_id] as Label).text = str(record.get("name", "Driver")) + \
			(" (reconnecting)" if online_session.disconnected_since.has(peer_id) else "")
	for id in peer_cars.keys():
		if not online_session.players.has(id):
			_remove_remote(int(id))
	_refresh_roster_label()

func _peer_suspended(peer_id: int) -> void:
	if not online_session.hosting:
		return
	# On disconnect, brake the old control stream immediately rather than
	# applying throttle for the entire 450ms stale-input timeout.
	var car: VehicleController2D = peer_cars.get(peer_id) as VehicleController2D
	if is_instance_valid(car):
		car.command = Vector4.ZERO
		car.nitrous_requested = false

func _rebind_peer_car(previous_id: int, current_id: int) -> void:
	if not online_session.hosting or previous_id == current_id:
		return
	# Server remains authoritative: transfer the SAME physics object rather
	# than instantiating a replacement car at the default spawn location.
	for mapping in [peer_cars, peer_models, peer_labels, commands_at]:
		if mapping.has(previous_id):
			mapping[current_id] = mapping[previous_id]
			mapping.erase(previous_id)
	if peer_cars.has(current_id):
		(peer_cars[current_id] as VehicleController2D).name = \
			"Friend_%d" % current_id
	if peer_labels.has(current_id):
		(peer_labels[current_id] as Label).name = "Name_%d" % current_id
	commands_at.erase(current_id)
	if police_target_peer == previous_id:
		police_target_peer = current_id
	_peer_suspended(current_id)

func _reconnect_started() -> void:
	if online_session.hosting:
		return
	if is_instance_valid(local_vehicle):
		local_vehicle.command = Vector4.ZERO
		local_vehicle.nitrous_requested = false
		local_vehicle.external_input = true
	if is_instance_valid(quality_label):
		quality_label.text = "CONNECTION LOST - trying to rejoin (30 seconds)"

func _reconnect_finished() -> void:
	if online_session.hosting:
		return
	# Existing game scene stays loaded. The new ENet ID is authenticated by
	# the host, which has retained the same original car and its state.
	targets.clear()
	histories.clear()
	_clear_police_replicas()
	_last_received_sequence = -1
	_first_authoritative_state = true
	_last_sent_command = Vector4(-1, -1, -1, -1)
	_last_sent_nitrous = false
	_input_heartbeat_elapsed = INPUT_HEARTBEAT
	_last_rtt_ms = 0.0
	_interpolation_delay_ms = 55
	if is_instance_valid(local_vehicle):
		local_vehicle.command = Vector4.ZERO
		local_vehicle.nitrous_requested = false
		local_vehicle.external_input = get_tree().paused
	if is_instance_valid(quality_label):
		quality_label.text = "RECONNECTED - syncing vehicle position..."
	online_session.mark_world_ready()

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
	if online_session.hosting:
		car.police_collision.connect(_on_police_collision.bind(car), CONNECT_DEFERRED)
	var nameplate := Label.new()
	nameplate.name = "Name_%d" % id
	nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nameplate.add_theme_font_size_override("font_size", 14)
	nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(nameplate)
	peer_labels[id] = nameplate

func _remove_remote(id: int) -> void:
	if online_session.hosting and police_target_peer == id and is_instance_valid(shared_police):
		shared_police.call("_escape")
	var car: Node = peer_cars.get(id)
	if is_instance_valid(car):
		car.queue_free()
	var nameplate: Node = peer_labels.get(id)
	if is_instance_valid(nameplate):
		nameplate.queue_free()
	peer_cars.erase(id)
	peer_labels.erase(id)
	peer_models.erase(id)
	peer_light_states.erase(id)
	peer_exhaust_states.erase(id)
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
			var lamps: Dictionary = {1: _lamp_state(local_vehicle)}
			var exhaust: Dictionary = {1: _exhaust_state(local_vehicle)}
			for id in peer_cars:
				var remote: VehicleController2D=peer_cars[id] as VehicleController2D
				states[id] = _car_state(remote)
				lamps[id] = _lamp_state(remote)
				exhaust[id] = _exhaust_state(remote)
			# Reserved negative key: existing six-value movement snapshots and
			# protocol stay compatible; no vehicle may have a negative peer ID.
			states[-1] = lamps
			states[-2] = exhaust # Optional cosmetic metadata, never physics.
			states[-3] = _police_snapshot()
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
			var authority_now: Vector2 = RemoteBuffer.projected_local_authority(
				my_state, _last_rtt_ms)
			var error_px: float = local_vehicle.global_position.distance_to(
				authority_now)
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
					authority_now, blend)

func _process(dt: float) -> void:
	if not online_session.active:
		return
	_quality_elapsed += dt
	if _quality_elapsed >= NETWORK_STATS_INTERVAL:
		_quality_elapsed = fmod(_quality_elapsed, NETWORK_STATS_INTERVAL)
		_update_network_quality()
	var now_ms := Time.get_ticks_msec()
	if online_session.hosting:
		if is_instance_valid(shared_police) and int(shared_police.get("wanted_level")) == 0:
			_release_police_target()
		if is_instance_valid(police_status) and is_instance_valid(shared_police):
			var heat := int(shared_police.get("wanted_level"))
			_update_police_status(heat,police_target_peer)
	else:
		_render_police_replicas(now_ms)
	for id in peer_cars:
		var car := peer_cars[id] as VehicleController2D
		if not online_session.hosting:
			var samples: Array = histories.get(id, [])
			var state: Array = RemoteBuffer.sample(
				samples, now_ms, _interpolation_delay_ms)
			if state.size() == 6:
				var lamp: Array=peer_light_states.get(id,[])
				if lamp.size()==2:
					car.brake=1.0 if bool(lamp[0]) else 0.0
					car.handbrake=0.0
					car.reversing=bool(lamp[1])
				var exhaust_state: Array=peer_exhaust_states.get(id,[])
				if exhaust_state.size()==5:
					# Host-driven cosmetics for render-only remote cars.
					car.nitrous_active=bool(exhaust_state[0])
					car.boost_psi=float(exhaust_state[1])
					car.throttle=float(exhaust_state[2])
					car.transmission.rpm=float(exhaust_state[3])
					var rendered_gear: int=int(exhaust_state[4])
					if rendered_gear != car.transmission.gear:
						car.transmission.gear=rendered_gear
						car.transmission.shifted.emit(rendered_gear)
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
	_last_rtt_ms = float(observed.get("rtt_ms", 0))
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

static func _lamp_state(car: VehicleController2D) -> Array:
	return [not car.reversing and maxf(car.brake,car.handbrake*.65)>.12,
		car.reversing]

static func _exhaust_state(car: VehicleController2D) -> Array:
	return [car.nitrous_active,car.boost_psi,car.throttle,
		car.transmission.rpm,car.transmission.gear]

static func valid_exhaust_state(value: Variant) -> bool:
	if not value is Array or value.size()!=5 or typeof(value[0])!=TYPE_BOOL:
		return false
	for i in [1,2,3]:
		if not (value[i] is float or value[i] is int) or \
				not is_finite(float(value[i])):
			return false
	return value[1]>=0.0 and value[1]<=150.0 and \
		value[2]>=0.0 and value[2]<=1.0 and \
		value[3]>=0.0 and value[3]<=30000.0 and \
		value[4] is int and value[4]>=1 and value[4]<=12

@rpc("any_peer", "unreliable_ordered")
func _submit_controls(input_command: Vector4, nitrous: bool) -> void:
	if not online_session.hosting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not online_session.players.has(sender) or \
			not online_session.world_ready_peers.has(sender) or not peer_cars.has(sender):
		return
	var car := peer_cars[sender] as VehicleController2D
	if is_instance_valid(friend_race) and friend_race.has_method("input_locked") and \
			friend_race.call("input_locked", sender):
		car.command = Vector4.ZERO
		car.nitrous_requested = false
		commands_at[sender] = Time.get_ticks_msec()
		return
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
	var police_payload: Variant = states.get(-3, {})
	if police_payload is Dictionary and police_payload.has("vehicles"):
		_receive_police_snapshot(police_payload, now_ms)
	var lamp_payload: Variant=states.get(-1,{})
	if lamp_payload is Dictionary:
		for peer_id in lamp_payload:
			if not peer_id is int or not online_session.players.has(peer_id):
				continue
			var value: Variant=lamp_payload[peer_id]
			if value is Array and value.size()==2 and \
					typeof(value[0])==TYPE_BOOL and typeof(value[1])==TYPE_BOOL:
				peer_light_states[int(peer_id)]=value.duplicate()
	var exhaust_payload: Variant=states.get(-2,{})
	if exhaust_payload is Dictionary:
		for peer_id in exhaust_payload:
			if not peer_id is int or not online_session.players.has(peer_id):
				continue
			var value: Variant=exhaust_payload[peer_id]
			if valid_exhaust_state(value):
				peer_exhaust_states[int(peer_id)]=value.duplicate()
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
	if is_instance_valid(friend_race) and friend_race.has_method("input_locked") and \
			friend_race.call("input_locked", sender) and action == "reset":
		return
	match action:
		"reset":
			car.reset_vehicle()
		"transmission":
			car.transmission.automatic = not car.transmission.automatic
		"shift_up":
			car.transmission.shift(1, car.config)
		"shift_down":
			car.transmission.shift(-1, car.config)

## Called only by the host's validated race director on GREEN. There is no
## guest police RPC or manual wanted selector. Physical police impacts use a separate host-local signal.
func on_illegal_race_started() -> bool:
	if not online_session.hosting or not is_instance_valid(shared_police) or not is_instance_valid(friend_race):
		return false
	if int(shared_police.get("wanted_level")) > 0 or str(friend_race.get("state")) != "running":
		return false
	var events: Dictionary = friend_race.get("race_events")
	var event: Dictionary = events.get(str(friend_race.get("event_id")), {})
	var level := int(event.get("race_heat", 0))
	if level < 1 or level > 5:
		return false
	var entries: Dictionary = friend_race.get("entries")
	var suspects: Array[int] = []
	for id in entries:
		if str(entries[id].get("status", "")) != "racing" or not online_session.players.has(id):
			continue
		if id != 1 and (not online_session.world_ready_peers.has(id) or online_session.disconnected_since.has(id) or not peer_cars.has(id)):
			continue
		suspects.append(int(id))
	if suspects.is_empty():
		return false
	suspects.shuffle()
	return _start_verified_police_pursuit(suspects[0], level)

## This is a host-local physical collision signal, never a guest RPC.
func _on_police_collision(closing_speed_mps: float, driver: VehicleController2D) -> void:
	if not online_session.active or not online_session.hosting or not is_instance_valid(driver):
		return
	if not is_finite(closing_speed_mps) or closing_speed_mps < VehicleController2D.POLICE_CRASH_THRESHOLD_MPS:
		return
	if driver == local_vehicle:
		_start_verified_police_pursuit(1, 1)
		return
	for id in peer_cars:
		if peer_cars[id] == driver and online_session.world_ready_peers.has(id) and not online_session.disconnected_since.has(id):
			_start_verified_police_pursuit(int(id), 1)
			return

func _start_verified_police_pursuit(peer_id: int, level: int) -> bool:
	if not online_session.hosting or not is_instance_valid(shared_police) or int(shared_police.get("wanted_level")) > 0 or not online_session.players.has(peer_id):
		return false
	var target: VehicleController2D = local_vehicle if peer_id == 1 else peer_cars.get(peer_id) as VehicleController2D
	if not is_instance_valid(target) or not shared_police.call("set_shared_target", target):
		return false
	police_target_peer = peer_id
	police_target_original_layer = target.collision_layer
	# Dedicated bit lets police contact a guest without enabling collisions
	# between normal friend cars or changing the existing roster contract.
	if peer_id != 1:
		target.collision_layer = 4
	if not shared_police.call("start_pursuit", clampi(level,1,5)):
		_release_police_target()
		return false
	return true

func _release_police_target() -> void:
	if police_target_peer > 1:
		var target := peer_cars.get(police_target_peer) as VehicleController2D
		if is_instance_valid(target):
			target.collision_layer = police_target_original_layer
	police_target_peer = 0

func _police_snapshot() -> Dictionary:
	var vehicles: Dictionary = {}
	var level := 0
	if is_instance_valid(shared_police):
		level = int(shared_police.get("wanted_level"))
		for entry in shared_police.get("units"):
			var car := entry.get("car") as VehicleController2D
			if is_instance_valid(car) and not car.is_queued_for_deletion():
				vehicles["u%d" % int(entry["serial"])] = [str(entry["model_id"]), _car_state(car), true, float(entry["damage"].call("health_percentage"))]
	var traffic: Node = world.get_node_or_null("AmbientTraffic") if is_instance_valid(world) else null
	if is_instance_valid(traffic):
		for agent in traffic.get("agents"):
			var patrol := agent.get("node") as CharacterBody2D
			if not is_instance_valid(patrol) or not patrol.is_in_group("police_patrol") or patrol.is_queued_for_deletion():
				continue
			var speed := float(patrol.get("motion_speed_mps"))
			var model: Dictionary = patrol.get("patrol_model")
			var state := [patrol.global_position,patrol.rotation,Vector2.UP.rotated(patrol.rotation)*speed,0.0,speed,0.0]
			vehicles["p%d" % int(agent["uid"])] = [str(model["id"]),state,false,100.0]
	return {"wanted":level,"target":police_target_peer,"vehicles":vehicles}

func _clear_police_replicas() -> void:
	for id in police_replicas:
		var car: Node = police_replicas[id]
		if is_instance_valid(car):
			car.queue_free()
	police_replicas.clear()
	police_histories.clear()

func _update_police_status(level: int, target: int) -> void:
	if not is_instance_valid(police_panel):
		return
	var heat := clampi(level,0,5)
	police_panel.visible = heat>0 and target==int(online_session.own_id())
	police_status.text = "WANTED  "+"★".repeat(heat)+"☆".repeat(5-heat) if police_panel.visible else ""

func _receive_police_snapshot(payload: Dictionary, now_ms: int) -> void:
	var raw: Variant = payload.get("vehicles", {})
	if not raw is Dictionary or raw.size() > 12:
		return
	var level := clampi(int(payload.get("wanted",0)),0,5)
	var target := int(payload.get("target",0))
	if is_instance_valid(police_status):
		_update_police_status(level,target)
	var retained: Dictionary = {}
	for id in raw:
		var row: Variant = raw[id]
		if not id is String or not row is Array or row.size() != 4 or not row[1] is Array or row[1].size() != 6 or not row[2] is bool:
			continue
		var state: Array = row[1]
		if not state[0] is Vector2 or not state[2] is Vector2 or not state[0].is_finite() or not state[2].is_finite():
			continue
		var car := police_replicas.get(id) as VehicleController2D
		if not is_instance_valid(car):
			var model: Dictionary = {}
			for candidate in Police.vehicle_pool(5):
				if str(candidate["id"]) == str(row[0]):
					model = candidate
					break
			if model.is_empty():
				continue
			car = VehicleScene.instantiate() as VehicleController2D
			car.external_input = true
			car.z_index = 8
			car.collision_layer = 0
			car.collision_mask = 0
			car.position = state[0]
			car.rotation = float(state[1])
			car.add_to_group("remote_police")
			add_child(car)
			car.set_physics_process(false)
			if not Police.apply_police_model(car, model):
				car.queue_free()
				continue
			if bool(row[2]):
				Emergency.attach(car,model)
				var smoke := Node2D.new()
				smoke.name = "RemoteDamageSmoke"
				smoke.set_script(DamageSmoke)
				smoke.set("vehicle", car)
				car.add_child(smoke)
			police_replicas[id] = car
		var smoke_node := car.get_node_or_null("RemoteDamageSmoke")
		if is_instance_valid(smoke_node):
			smoke_node.call("set_health_percentage",clampf(float(row[3]),0.0,100.0))
		var history: Array = police_histories.get(id, [])
		RemoteBuffer.add_snapshot(history,now_ms,state)
		police_histories[id] = history
		retained[id] = true
	for id in police_replicas.keys():
		if not retained.has(id):
			police_replicas[id].queue_free()
			police_replicas.erase(id)
			police_histories.erase(id)

func _render_police_replicas(now_ms: int) -> void:
	for id in police_replicas:
		var car := police_replicas[id] as VehicleController2D
		var state: Array = RemoteBuffer.sample(police_histories.get(id, []),now_ms,_interpolation_delay_ms)
		if not is_instance_valid(car) or state.size() != 6:
			continue
		car.global_position = state[0]
		car.rotation = float(state[1])
		car.linear_velocity = state[2]
		car.steering = float(state[3])
		car.longitudinal_speed = float(state[4])
		car.yaw_rate = float(state[5])

func _session_closed(reason: String) -> void:
	if reason != "Left online session." and get_parent().has_method("_return_to_main_menu"):
		get_parent().call_deferred("_return_to_main_menu")
