extends Node
## Optional HTTPS room-directory client. Uses a dedicated public game server,
## not a home-hosted ENet listen socket. No cloud endpoint is bundled in builds.
signal status_changed(message: String)
signal room_created(code: String)

const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const SERVICE_SETTINGS := "user://streetbound_hosted_room.cfg"

@onready var online_session: Node = get_node_or_null("/root/OnlineSession")

var service_url := ""
var room_code := ""
var is_owner := false
var busy := false
var last_message := ""
var _owner_token := ""
var _driver_name := ""
var _request_node: HTTPRequest

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var config := ConfigFile.new()
	if config.load(SERVICE_SETTINGS) == OK:
		var saved := str(config.get_value("rooms", "service_url", ""))
		if valid_service_url(saved):
			service_url = saved.trim_suffix("/")
	if online_session != null:
		online_session.session_closed.connect(_session_closed)

static func valid_service_url(value: String) -> bool:
	var url := value.strip_edges().trim_suffix("/")
	if url.is_empty() or url.length() > 240:
		return false
	if not url.begins_with("https://") and not (url.begins_with("http://127.0.0.1:") or
			url.begins_with("http://localhost:")):
		return false
	var host_part := url.split("://", false, 1)
	if host_part.size() != 2 or host_part[1].is_empty():
		return false
	for character in [" ", "\n", "\r", "\t", "@", "?", "#", "\\"]:
		if url.contains(character):
			return false
	return not host_part[1].contains("/")

static func valid_room_code(value: String) -> bool:
	if value.length() != 12:
		return false
	for index in value.length():
		if not CODE_ALPHABET.contains(value.substr(index, 1)):
			return false
	return true

func save_url(value: String) -> bool:
	if not valid_service_url(value):
		_set_status("Enter the HTTPS address of a configured room service.")
		return false
	service_url = value.strip_edges().trim_suffix("/")
	var config := ConfigFile.new()
	config.set_value("rooms", "service_url", service_url)
	config.save(SERVICE_SETTINGS)
	return true

func create_room(url: String, driver: String) -> bool:
	if not _begin_request(url, driver):
		return false
	var error := _request_node.request(service_url + "/rooms",
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST, "{}")
	if error != OK:
		_finish_error("Could not contact room service.")
		return false
	_set_status("Creating your private dedicated game server...")
	return true

func join_room(url: String, code: String, driver: String) -> bool:
	if not _begin_request(url, driver):
		return false
	var room := code.strip_edges().to_upper()
	if not valid_room_code(room):
		_finish_error("Enter a valid 12-character room code.")
		return false
	room_code = room
	var error := _request_node.request(service_url + "/rooms/" + room)
	if error != OK:
		_finish_error("Could not reach the room directory.")
		return false
	_set_status("Finding private room...")
	return true

func _begin_request(url: String, driver: String) -> bool:
	if busy or (online_session != null and
			(bool(online_session.active) or bool(online_session.joining))):
		_set_status("Leave the current session before joining another room.")
		return false
	if not save_url(url):
		return false
	if driver.strip_edges().is_empty():
		_set_status("Enter a driver name.")
		return false
	_driver_name = driver
	busy = true
	_request_node = HTTPRequest.new()
	_request_node.timeout = 55.0
	add_child(_request_node)
	_request_node.request_completed.connect(_request_done)
	return true

func _finish_error(message: String) -> void:
	busy = false
	_set_status(message)
	if is_instance_valid(_request_node):
		_request_node.queue_free()
	_request_node = null

func _request_done(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if is_instance_valid(_request_node):
		_request_node.queue_free()
	_request_node = null
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("Room service unavailable. Check HTTPS connectivity.")
		return
	var response: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not response is Dictionary:
		_set_status("Room service returned an invalid response.")
		return
	if response_code != 200 and response_code != 201:
		_set_status(str(response.get("error", "Room service request failed.")).substr(0, 140))
		return
	var data: Dictionary = response
	var code := str(data.get("code", ""))
	var host := str(data.get("host", ""))
	var port := int(data.get("port", 0))
	var secret := str(data.get("secret", ""))
	var session_script = preload("res://scripts/network/online_session.gd")
	if not valid_room_code(code) or not session_script.valid_address(host) or \
			not session_script.valid_port(port) or not session_script.valid_secret(secret):
		_set_status("Room service returned invalid connection details.")
		return
	var created := response_code == 201
	if created:
		var token := str(data.get("owner_token", ""))
		if token.length() < 32 or token.length() > 128:
			_set_status("Room service did not provide owner credentials.")
			return
		_owner_token = token
		is_owner = true
	room_code = code
	if created:
		room_created.emit(room_code)
	_set_status("Joining dedicated room %s..." % room_code)
	if not online_session.join_session(host, _driver_name, port, secret):
		_close_owned_room()
		_set_status("Could not connect to the dedicated game server.")

func _set_status(message: String) -> void:
	last_message = message
	status_changed.emit(message)

func _session_closed(_reason: String) -> void:
	_close_owned_room()
	room_code = ""

func _close_owned_room() -> void:
	if not is_owner or room_code.is_empty() or _owner_token.is_empty():
		return
	var code := room_code
	var owner := _owner_token
	is_owner = false
	_owner_token = ""
	# Separate HTTPRequest so scene changes cannot interrupt owner cleanup.
	var request := HTTPRequest.new()
	request.timeout = 10.0
	add_child(request)
	request.request_completed.connect(func(_r: int, _s: int,
			_h: PackedStringArray, _b: PackedByteArray) -> void:
		request.queue_free()
	)
	var error := request.request(service_url + "/rooms/" + code,
		PackedStringArray(["X-Room-Owner: " + owner]), HTTPClient.METHOD_DELETE)
	if error != OK:
		request.queue_free()
