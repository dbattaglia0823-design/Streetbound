extends Node
## Persistent session transport. The host owns admission, roster and car IDs.
## This is direct-IP ENet, not a cloud invite-code or NAT traversal service.
signal session_accepted
signal session_closed(reason: String)
signal status_changed(message: String)
signal roster_changed

const DEFAULT_PORT := 28163
const MAX_PLAYERS := 4
const PROTOCOL_VERSION := 1
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")

var hosting := false
var joining := false
var active := false
var players: Dictionary = {}
var world_ready_peers: Dictionary = {}
var display_name := "Driver"
var last_message := ""
var _peer: ENetMultiplayerPeer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

static func valid_port(port: int) -> bool:
	return port >= 1024 and port <= 65535

static func clean_name(value: String) -> String:
	return value.strip_edges().replace("\n", " ").replace("\r", " ").substr(0, 24)

func own_id() -> int:
	return 1 if hosting else multiplayer.get_unique_id()

func host_session(name_value: String, port: int = DEFAULT_PORT) -> bool:
	leave_session()
	if not valid_port(port) or clean_name(name_value).is_empty():
		_set_status("Enter a driver name and UDP port between 1024 and 65535.")
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
	players = {1: {"name": display_name, "car_id": ""}}
	_set_status("Hosting on UDP %d. Share your address and port with friends." % port)
	roster_changed.emit()
	return true

func join_session(address: String, name_value: String, port: int = DEFAULT_PORT) -> bool:
	leave_session()
	var target := address.strip_edges()
	if target.is_empty() or target.length() > 253 or not valid_port(port) or \
			clean_name(name_value).is_empty():
		_set_status("Enter your name, the host address, and a valid UDP port.")
		return false
	var transport := ENetMultiplayerPeer.new()
	var error := transport.create_client(target, port)
	if error != OK:
		_set_status("Could not connect: %s" % error_string(error))
		return false
	_peer = transport
	display_name = clean_name(name_value)
	joining = true
	multiplayer.multiplayer_peer = transport
	_set_status("Connecting to %s:%d..." % [target, port])
	return true

func leave_session(reason: String = "Left online session.") -> void:
	var was_connected := active or joining
	active = false
	joining = false
	hosting = false
	players.clear()
	world_ready_peers.clear()
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
		_request_admission.rpc_id(1, PROTOCOL_VERSION, display_name)

func _on_connection_failed() -> void:
	if joining:
		leave_session("Connection failed. Check the host address, UDP port and firewall.")
		_set_status("Connection failed. Check the host address, port and firewall.")

func _on_server_disconnected() -> void:
	if active or joining:
		leave_session("Host disconnected.")
		_set_status("Host disconnected.")

func _on_peer_disconnected(peer_id: int) -> void:
	if not hosting:
		if peer_id == 1 and (active or joining):
			_on_server_disconnected()
		return
	if players.erase(peer_id):
		world_ready_peers.erase(peer_id)
		_broadcast_roster()

@rpc("any_peer", "reliable")
func _request_admission(version: int, name_value: String) -> void:
	if not hosting:
		return
	var sender := multiplayer.get_remote_sender_id()
	if version != PROTOCOL_VERSION:
		_admission_denied.rpc_id(sender, "Game versions are incompatible.")
		return
	if players.size() >= MAX_PLAYERS:
		_admission_denied.rpc_id(sender, "Session is full (4 players maximum).")
		return
	var sanitized := clean_name(name_value)
	if sanitized.is_empty():
		_admission_denied.rpc_id(sender, "Driver name is required.")
		return
	if players.has(sender):
		return
	players[sender] = {"name": sanitized, "car_id": ""}
	_broadcast_roster()

@rpc("authority", "reliable")
func _admission_denied(reason: String) -> void:
	if joining:
		leave_session(reason)
		_set_status(reason)

@rpc("authority", "reliable")
func _receive_roster(incoming: Dictionary) -> void:
	if hosting or not (joining or active):
		return
	# Only the authority (peer 1) can replace this list.
	var was_joining := joining
	players = incoming.duplicate(true)
	active = true
	joining = false
	roster_changed.emit()
	if was_joining:
		_set_status("Joined %s's session." % str(players.get(1, {}).get("name", "host")))
		session_accepted.emit()

func _broadcast_roster() -> void:
	if not hosting:
		return
	roster_changed.emit()
	for id in players:
		if int(id) != 1:
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
