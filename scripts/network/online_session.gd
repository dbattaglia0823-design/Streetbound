extends Node
## Persistent session transport. The host owns admission, roster and car IDs.
## This is direct-IP ENet, not a cloud invite-code or NAT traversal service.
signal session_accepted
signal session_closed(reason: String)
signal status_changed(message: String)
signal roster_changed
signal reconnect_started
signal reconnect_finished
signal peer_connection_suspended(peer_id: int)
signal peer_id_rebound(previous_id: int, current_id: int)

const DEFAULT_PORT := 28163
const MAX_PLAYERS := 4
const PROTOCOL_VERSION := 10  # Host-verified durable friend race rewards.
const RECONNECT_GRACE_MS := 35000
const CLIENT_RECONNECT_WINDOW_MS := 30000
const RECONNECT_RETRY_MS := 5000
const INITIAL_RECONNECT_SETTLE_MS := 350
const INVITE_PREFIX := "SB1-"
const INVITE_TOKEN_HEX_LENGTH := 48
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const WorldPublication = preload("res://scripts/world/world_publication.gd")

var hosting := false
var joining := false
var active := false
var reconnecting := false
var disconnected_since: Dictionary = {}
var _peer_resume_tokens: Dictionary = {}
var _resume_token := ""
var _target_address := ""
var _target_port := DEFAULT_PORT
var _reconnect_started_at := 0
var _last_reconnect_attempt_at := 0
var players: Dictionary = {}
var world_identity: Dictionary = {}
var reward_session_id := "" # Public unique lobby ID; not an auth credential.
var world_ready_peers: Dictionary = {}
var display_name := "Driver"
var last_message := ""
var invite_address := ""
var invite_port := DEFAULT_PORT
var lobby_locked := false
var _invite_secret := ""
var _joining_secret := ""
var _peer: ENetMultiplayerPeer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	if hosting and not disconnected_since.is_empty():
		expire_disconnected_players(now)
	if not reconnecting:
		return
	if now - _reconnect_started_at >= CLIENT_RECONNECT_WINDOW_MS:
		leave_session("Unable to reconnect. The session may have ended.")
		_set_status("Reconnection timed out. Return to multiplayer to rejoin.")
	elif now - _last_reconnect_attempt_at >= RECONNECT_RETRY_MS:
		_attempt_reconnect()

func expire_disconnected_players(now_ms: int) -> void:
	if not hosting:
		return
	var removed := false
	for id in disconnected_since.keys():
		if now_ms - int(disconnected_since[id]) < RECONNECT_GRACE_MS:
			continue
		disconnected_since.erase(id)
		_peer_resume_tokens.erase(id)
		world_ready_peers.erase(id)
		if players.erase(id):
			removed = true
	if removed:
		_broadcast_roster()

func _attempt_reconnect() -> void:
	if not reconnecting:
		return
	_last_reconnect_attempt_at = Time.get_ticks_msec()
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var transport := ENetMultiplayerPeer.new()
	var error := transport.create_client(_target_address, _target_port)
	if error != OK:
		_set_status("Reconnecting: unable to open UDP socket (%s)." % error_string(error))
		return
	_peer = transport
	joining = true
	multiplayer.multiplayer_peer = transport
	_set_status("Reconnecting to your previous driver slot...")

static func valid_port(port: int) -> bool:
	return port >= 1024 and port <= 65535

static func clean_name(value: String) -> String:
	return value.strip_edges().replace("\n", " ").replace("\r", " ").substr(0, 24)

static func valid_address(value: String) -> bool:
	var value_clean := value.strip_edges()
	if value_clean.is_empty() or value_clean.length() > 253:
		return false
	for forbidden in [" ", "\n", "\r", "\t", "/", "\\", "@", "#", "?", "&"]:
		if value_clean.contains(forbidden):
			return false
	return true

static func valid_secret(value: String) -> bool:
	if value.length() != INVITE_TOKEN_HEX_LENGTH:
		return false
	for index in value.length():
		if not "0123456789abcdef".contains(value.substr(index, 1)):
			return false
	return true

static func encode_invite(address: String, port: int, secret: String) -> String:
	if not valid_address(address) or not valid_port(port) or not valid_secret(secret):
		return ""
	var payload := JSON.stringify({
		"host": address.strip_edges(), "port": port, "key": secret})
	var encoded := Marshalls.utf8_to_base64(payload)
	return INVITE_PREFIX + encoded.replace("+", "-").replace("/", "_").replace("=", "")

static func decode_invite(value: String) -> Dictionary:
	var code := value.strip_edges()
	if not code.begins_with(INVITE_PREFIX) or code.length() > 600:
		return {}
	var payload := code.substr(INVITE_PREFIX.length())
	if payload.is_empty():
		return {}
	for index in payload.length():
		if not "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".contains(
				payload.substr(index, 1)):
			return {}
	var padded := payload.replace("-", "+").replace("_", "/")
	while padded.length() % 4 != 0:
		padded += "="
	var result: Variant = JSON.parse_string(Marshalls.base64_to_utf8(padded))
	if not result is Dictionary:
		return {}
	var address := str(result.get("host", ""))
	var port := int(result.get("port", 0))
	var secret := str(result.get("key", ""))
	if not valid_address(address) or not valid_port(port) or not valid_secret(secret):
		return {}
	return {"host": address, "port": port, "key": secret}

func get_invite_code() -> String:
	if not hosting:
		return ""
	return encode_invite(invite_address, invite_port, _invite_secret)

func rotate_invite() -> String:
	if not hosting:
		return ""
	_invite_secret = Crypto.new().generate_random_bytes(24).hex_encode()
	_set_status("New invitation created. Older codes are no longer valid.")
	return get_invite_code()

func set_lobby_locked(value: bool) -> void:
	if not hosting:
		return
	lobby_locked = value
	_set_status("Lobby locked: new players cannot join." if value else
		"Lobby unlocked: valid invitations can join.")

func network_stats(peer_id: int = 1) -> Dictionary:
	# ENet reports actual smoothed RTT and RTT variance in milliseconds.
	# "loss" is its RELIABLE packet-loss statistic, not total UDP loss.
	if not active or _peer == null or peer_id == own_id() or \
			not multiplayer.get_peers().has(peer_id):
		return {}
	# Reserved seats remain in players but are no longer connected ENet peers.
	if hosting and disconnected_since.has(peer_id):
		return {}
	var connection: ENetPacketPeer = _peer.get_peer(peer_id)
	if connection == null or not connection.is_active() or \
			connection.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return {}
	var loss_epoch: float = connection.get_statistic(
		ENetPacketPeer.PEER_PACKET_LOSS_EPOCH)
	return {
		"rtt_ms": roundi(connection.get_statistic(
			ENetPacketPeer.PEER_ROUND_TRIP_TIME)),
		"variation_ms": roundi(connection.get_statistic(
			ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)),
		"reliable_loss_percent": 100.0 * connection.get_statistic(
			ENetPacketPeer.PEER_PACKET_LOSS) / float(
				ENetPacketPeer.PACKET_LOSS_SCALE) if loss_epoch > 0.0 else -1.0}

func own_id() -> int:
	return 1 if hosting else multiplayer.get_unique_id()

func host_session(name_value: String, port: int = DEFAULT_PORT,
		advertised_address: String = "127.0.0.1") -> bool:
	leave_session()
	world_identity = WorldPublication.network_identity()
	if world_identity.is_empty():
		_set_status("Cannot host: selected map archive is missing or invalid.")
		return false
	if not valid_port(port) or clean_name(name_value).is_empty() or \
			not valid_address(advertised_address):
		_set_status("Enter a name, host address and UDP port between 1024 and 65535.")
		return false
	var transport := ENetMultiplayerPeer.new()
	var error := transport.create_server(port, MAX_PLAYERS - 1)
	if error != OK:
		_set_status("Could not host: %s" % error_string(error))
		return false
	_peer = transport
	multiplayer.multiplayer_peer = transport
	display_name = clean_name(name_value)
	hosting = true
	active = true
	reconnecting = false
	invite_address = advertised_address.strip_edges()
	invite_port = port
	lobby_locked = false
	reward_session_id = Crypto.new().generate_random_bytes(24).hex_encode()
	_invite_secret = Crypto.new().generate_random_bytes(24).hex_encode()
	players = {1: {"name": display_name, "car_id": ""}}
	_set_status("Private lobby started on UDP %d. Copy an invite code for friends." % port)
	roster_changed.emit()
	return true

func join_session(address: String, name_value: String, port: int = DEFAULT_PORT,
		invite_secret: String = "") -> bool:
	leave_session()
	world_identity = WorldPublication.network_identity()
	if world_identity.is_empty():
		_set_status("Cannot join: selected map archive is missing or invalid.")
		return false
	var target := address.strip_edges()
	if not valid_address(target) or not valid_port(port) or \
			clean_name(name_value).is_empty() or not valid_secret(invite_secret):
		_set_status("A valid private lobby invitation is required.")
		return false
	var transport := ENetMultiplayerPeer.new()
	var error := transport.create_client(target, port)
	if error != OK:
		_set_status("Could not connect: %s" % error_string(error))
		return false
	_peer = transport
	display_name = clean_name(name_value)
	_joining_secret = invite_secret
	_target_address = target
	_target_port = port
	joining = true
	multiplayer.multiplayer_peer = transport
	_set_status("Connecting to %s:%d..." % [target, port])
	return true

func join_invite(code: String, name_value: String) -> bool:
	var data := decode_invite(code)
	if data.is_empty():
		_set_status("Invalid invitation. Ask the host for a new lobby code.")
		return false
	return join_session(str(data.host), name_value, int(data.port), str(data.key))

func leave_session(reason: String = "Left online session.") -> void:
	var was_connected := active or joining or reconnecting
	active = false
	joining = false
	hosting = false
	reconnecting = false
	players.clear()
	world_identity.clear()
	reward_session_id = ""
	world_ready_peers.clear()
	disconnected_since.clear()
	_peer_resume_tokens.clear()
	_resume_token = ""
	_target_address = ""
	_target_port = DEFAULT_PORT
	_reconnect_started_at = 0
	_last_reconnect_attempt_at = 0
	invite_address = ""
	_invite_secret = ""
	_joining_secret = ""
	lobby_locked = false
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if was_connected:
		session_closed.emit(reason)
		roster_changed.emit()

func _set_status(message: String) -> void:
	last_message = message
	status_changed.emit(message)

func _on_connected() -> void:
	if joining:
		_request_admission.rpc_id(1, PROTOCOL_VERSION, display_name,
			_joining_secret, _resume_token if reconnecting else "", world_identity)

func _on_connection_failed() -> void:
	if reconnecting:
		_set_status("Connection attempt failed; retrying your previous slot.")
	elif joining:
		leave_session("Connection failed. Check the host address, UDP port and firewall.")
		_set_status("Connection failed. Check the host address, port and firewall.")

func _on_server_disconnected() -> void:
	if reconnecting:
		return
	if active and not hosting and valid_secret(_resume_token) and \
			valid_address(_target_address):
		reconnecting = true
		active = false
		joining = true
		_reconnect_started_at = Time.get_ticks_msec()
		# Close the old ENet transport now. Give the host a short chance to
		# observe the release before the next peer attempts to claim the seat.
		_last_reconnect_attempt_at = _reconnect_started_at - \
			RECONNECT_RETRY_MS + INITIAL_RECONNECT_SETTLE_MS
		reconnect_started.emit()
		if _peer != null:
			_peer.close()
			_peer = null
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		_set_status("Connection interrupted. Attempting to restore your car...")
	elif active or joining:
		leave_session("Host disconnected.")
		_set_status("Host disconnected.")

func _on_peer_disconnected(peer_id: int) -> void:
	if not hosting:
		if peer_id == 1 and (active or joining):
			_on_server_disconnected()
		return
	if not players.has(peer_id):
		return
	world_ready_peers.erase(peer_id)
	if _peer_resume_tokens.has(peer_id):
		# Keep the existing authenticated driver's seat and car for 35 seconds.
		# A new guest cannot steal a reserved seat with the shared invite.
		disconnected_since[peer_id] = Time.get_ticks_msec()
		peer_connection_suspended.emit(peer_id)
	else:
		players.erase(peer_id)
	_broadcast_roster()

func _reject_peer(peer_id: int, reason: String) -> void:
	_admission_denied.rpc_id(peer_id, reason)
	# Give the reliable denial packet a chance to leave before disconnecting.
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if hosting and not players.has(peer_id) and \
				multiplayer.get_peers().has(peer_id):
			multiplayer.multiplayer_peer.disconnect_peer(peer_id)
	)

@rpc("any_peer", "reliable")
func _request_admission(version: int, name_value: String, invite_secret: String,
		resume_token: String, client_world: Dictionary) -> void:
	if not hosting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if version != PROTOCOL_VERSION:
		_reject_peer(sender, "Game versions are incompatible.")
		return
	if not WorldPublication.same_network_identity(world_identity, client_world):
		_reject_peer(sender, "Map mismatch: install the same published world build as the host.")
		return
	if players.has(sender) and not disconnected_since.has(sender):
		# Duplicate admission attempts cannot rewrite an already-owned slot.
		return
	# Resumes require their own host-issued random credential, not the shared
	# invitation. Check this BEFORE lobby lock/capacity so saved seats survive.
	if not resume_token.is_empty():
		if not valid_secret(resume_token):
			_reject_peer(sender, "Invalid reconnect credential.")
			return
		for previous_id in disconnected_since.keys():
			if str(_peer_resume_tokens.get(previous_id, "")) != resume_token:
				continue
			if Time.get_ticks_msec() - int(disconnected_since[previous_id]) >= \
					RECONNECT_GRACE_MS:
				break
			var previous: Dictionary = players.get(previous_id, {})
			if previous.is_empty() or clean_name(name_value) != \
					str(previous.get("name", "")):
				break
			disconnected_since.erase(previous_id)
			world_ready_peers.erase(previous_id)
			if int(previous_id) != sender:
				players.erase(previous_id)
				players[sender] = previous
				_peer_resume_tokens.erase(previous_id)
				_peer_resume_tokens[sender] = resume_token
				peer_id_rebound.emit(int(previous_id), sender)
			_admission_granted.rpc_id(sender, resume_token, reward_session_id)
			_broadcast_roster()
			return
		_reject_peer(sender, "Reconnect token expired or driver unavailable.")
		return
	if lobby_locked or not valid_secret(invite_secret) or invite_secret != _invite_secret:
		_reject_peer(sender, "Private lobby invite was rejected or expired.")
		return
	if players.size() >= MAX_PLAYERS:
		_reject_peer(sender, "Session is full (4 players maximum).")
		return
	var sanitized := clean_name(name_value)
	if sanitized.is_empty():
		_reject_peer(sender, "Driver name is required.")
		return
	if players.has(sender):
		return
	players[sender] = {"name": sanitized, "car_id": ""}
	var personal_token := Crypto.new().generate_random_bytes(24).hex_encode()
	_peer_resume_tokens[sender] = personal_token
	_admission_granted.rpc_id(sender, personal_token, reward_session_id)
	_broadcast_roster()

@rpc("authority", "reliable")
func _admission_granted(personal_token: String, lobby_id: String) -> void:
	if not hosting and (joining or active) and valid_secret(personal_token) and valid_secret(lobby_id):
		_resume_token = personal_token
		reward_session_id = lobby_id

@rpc("authority", "reliable")
func _admission_denied(reason: String) -> void:
	if reconnecting:
		# A fresh ENet connection may arrive before the old connection's
		# disconnect event. Keep retrying until the bounded deadline.
		_set_status("%s Retrying while the previous slot is reserved." % reason)
	elif joining:
		leave_session(reason)
		_set_status(reason)

@rpc("authority", "reliable")
func _receive_roster(incoming: Dictionary) -> void:
	if hosting or not (joining or active):
		return
	# Only the authority (peer 1) can replace this list.
	if not valid_secret(reward_session_id):
		# A client without a host-issued lobby ID cannot receive rewards.
		return
	var was_joining := joining
	var was_reconnecting := reconnecting
	players = incoming.duplicate(true)
	active = true
	joining = false
	reconnecting = false
	roster_changed.emit()
	if was_reconnecting:
		_set_status("Connection restored. Rejoined your previous car.")
		reconnect_finished.emit()
	elif was_joining:
		_set_status("Joined %s's session." % str(players.get(1, {}).get("name", "host")))
		session_accepted.emit()

func _broadcast_roster() -> void:
	if not hosting:
		return
	roster_changed.emit()
	for id in players:
		if int(id) != 1 and not disconnected_since.has(id):
			_receive_roster.rpc_id(int(id), players)

func mark_world_ready() -> void:
	if active and not hosting:
		_world_ready.rpc_id(1)

@rpc("any_peer", "reliable")
func _world_ready() -> void:
	if not hosting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if players.has(sender):
		world_ready_peers[sender] = true

func set_local_car(car_id: String) -> void:
	if not active or Catalog.find_by_id(car_id).is_empty():
		return
	if hosting:
		players[1]["car_id"] = car_id
		_broadcast_roster()
	else:
		_request_car.rpc_id(1, car_id)

@rpc("any_peer", "reliable")
func _request_car(car_id: String) -> void:
	if not hosting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not players.has(sender) or Catalog.find_by_id(car_id).is_empty():
		return
	players[sender]["car_id"] = car_id
	_broadcast_roster()
