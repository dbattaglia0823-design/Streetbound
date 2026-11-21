extends Node
## Opt-in LAN browser for friend-hosted sessions. No backend, relay or
## permanent server. Broadcasts never leave the local subnet.
signal room_found(room: Dictionary)
signal scan_finished
signal status_changed(message: String)

const SESSION_SCRIPT = preload("res://scripts/network/online_session.gd")
const DISCOVERY_PORT := 28164
const QUERY := "STREETBOUND_LAN_FIND_V1"
const RESPONSE_TYPE := "streetbound_lan_room_v1"
const TIMEOUT_MS := 3500
const MAX_PACKET_BYTES := 1024

@onready var online_session: Node = get_node_or_null("/root/OnlineSession")
var advertising := false
var searching := false
var rooms: Dictionary = {}
var last_message := ""
var _server_socket: PacketPeerUDP
var _client_socket: PacketPeerUDP
var _search_started_ms := 0
var _reply_last_ms: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if online_session != null:
		online_session.session_closed.connect(_on_session_closed)

static func local_ipv4() -> String:
	var alternatives: PackedStringArray = []
	for address in IP.get_local_addresses():
		if address.contains(":") or address.begins_with("127.") or address == "0.0.0.0":
			continue
		if address.begins_with("192.168.") or address.begins_with("10.") or \
				address.begins_with("172.") or address.begins_with("100."):
			return address
		alternatives.append(address)
	return alternatives[0] if not alternatives.is_empty() else "127.0.0.1"

static func parse_reply(bytes: PackedByteArray, sender: String) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_PACKET_BYTES or \
			not SESSION_SCRIPT.valid_address(sender):
		return {}
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not parsed is Dictionary:
		return {}
	if str(parsed.get("type", "")) != RESPONSE_TYPE or \
			int(parsed.get("protocol", 0)) != SESSION_SCRIPT.PROTOCOL_VERSION:
		return {}
	var port: int = int(parsed.get("port", 0))
	var secret := str(parsed.get("key", ""))
	var name := SESSION_SCRIPT.clean_name(str(parsed.get("name", "")))
	var count: int = int(parsed.get("players", 0))
	if not SESSION_SCRIPT.valid_port(port) or \
			not SESSION_SCRIPT.valid_secret(secret) or name.is_empty() or \
			count < 1 or count > SESSION_SCRIPT.MAX_PLAYERS:
		return {}
	var invite: String = SESSION_SCRIPT.encode_invite(sender, port, secret)
	if invite.is_empty():
		return {}
	return {"name": name, "players": count, "port": port,
		"ip": sender, "invite": invite}

func start_advertising() -> bool:
	stop_advertising()
	if online_session == null or not bool(online_session.hosting) or \
			not bool(online_session.active):
		_set_status("Start a LAN host session before advertising.")
		return false
	var socket := PacketPeerUDP.new()
	var err := socket.bind(DISCOVERY_PORT, "0.0.0.0")
	if err != OK:
		_set_status("Could not advertise the LAN room (UDP %d is busy)." % DISCOVERY_PORT)
		return false
	_server_socket = socket
	advertising = true
	_set_status("LAN room visible to devices on this network.")
	return true

func stop_advertising() -> void:
	advertising = false
	_reply_last_ms.clear()
	if _server_socket != null:
		_server_socket.close()
		_server_socket = null

func scan() -> bool:
	cancel_scan()
	rooms.clear()
	var socket := PacketPeerUDP.new()
	var err := socket.bind(0, "0.0.0.0")
	if err != OK:
		_set_status("Could not open the LAN discovery socket.")
		return false
	_client_socket = socket
	_client_socket.set_broadcast_enabled(true)
	searching = true
	_search_started_ms = Time.get_ticks_msec()
	if _client_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT) != OK or \
			_client_socket.put_packet(QUERY.to_utf8_buffer()) != OK:
		cancel_scan()
		_set_status("LAN discovery broadcast could not be sent.")
		return false
	# Loopback also supports one-PC host/guest smoke tests.
	_client_socket.set_dest_address("127.0.0.1", DISCOVERY_PORT)
	_client_socket.put_packet(QUERY.to_utf8_buffer())
	_set_status("Looking for local network games...")
	return true

func cancel_scan() -> void:
	searching = false
	if _client_socket != null:
		_client_socket.close()
		_client_socket = null

func _process(_dt: float) -> void:
	if advertising and _server_socket != null:
		var packets := 0
		while _server_socket.get_available_packet_count() > 0 and packets < 20:
			packets += 1
			var data := _server_socket.get_packet()
			if data.size() > 64 or data.get_string_from_utf8() != QUERY:
				continue
			var sender := _server_socket.get_packet_ip()
			var source_port := _server_socket.get_packet_port()
			var now := Time.get_ticks_msec()
			if now - int(_reply_last_ms.get(sender, -100000)) < 250:
				continue
			_reply_last_ms[sender] = now
			# Broadcasts include the admission key, so this mode is deliberately
			# visible/joinable to anyone on the same subnet (opt-in only).
			var payload := JSON.stringify({
				"type": RESPONSE_TYPE,
				"protocol": SESSION_SCRIPT.PROTOCOL_VERSION,
				"name": str(online_session.display_name),
				"players": online_session.players.size(),
				"port": int(online_session.invite_port),
				"key": online_session._invite_secret
			})
			if _server_socket.set_dest_address(sender, source_port) == OK:
				_server_socket.put_packet(payload.to_utf8_buffer())
	if searching and _client_socket != null:
		var count := 0
		while _client_socket.get_available_packet_count() > 0 and count < 20:
			count += 1
			var payload := _client_socket.get_packet()
			var source := _client_socket.get_packet_ip()
			var record := parse_reply(payload, source)
			if record.is_empty():
				continue
			var identity := str(record.ip) + ":" + str(record.port)
			if not rooms.has(identity):
				rooms[identity] = record
				room_found.emit(record)
		if Time.get_ticks_msec() - _search_started_ms >= TIMEOUT_MS:
			cancel_scan()
			scan_finished.emit()
			_set_status("Found %d LAN game(s)." % rooms.size())

func _set_status(message: String) -> void:
	last_message = message
	status_changed.emit(message)

func _on_session_closed(_reason: String) -> void:
	stop_advertising()
