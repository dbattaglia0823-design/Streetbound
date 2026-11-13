extends Node
## The native editor uses exactly the same authenticated, transactional
## localhost Python rebaker as the browser. No direct file writes, no
## different road/junction implementation, and no app-wide network listener.
signal completed(ok: bool, message: String, new_sha: String)
const PORT := 8765
const BASE := "http://127.0.0.1:%d" % PORT
const BUILDER := "res://tools/map_editor_server.py"
var http: HTTPRequest
var phase := ""
var token := ""
var baked_revision := ""
var requested_doc: Dictionary = {}
var expected_source_hash := ""
var local_baked_sha := ""
var started_pid := -1
var retry_count := 0
var last_error := ""

func _ready() -> void:
	name = "NativeMapBridge"
	process_mode = Node.PROCESS_MODE_ALWAYS
	http = HTTPRequest.new()
	http.process_mode = Node.PROCESS_MODE_ALWAYS
	http.timeout = 255.0
	add_child(http)
	http.request_completed.connect(_received)

func _exit_tree() -> void:
	if started_pid > 0:
		OS.kill(started_pid)
		started_pid = -1

func _fail(message: String) -> void:
	last_error = message
	phase = ""
	requested_doc.clear()
	completed.emit(false,message,"")

func _request(method: HTTPClient.Method, route: String,
		headers: PackedStringArray = PackedStringArray(), payload: String = "") -> bool:
	var error := http.request(BASE+route,headers,method,payload)
	if error != OK:
		_fail("Local map service request failed: %s" % error_string(error))
		return false
	return true

func apply_source(draft: Dictionary, source_hash: String,
		loaded_world_sha: String = "") -> bool:
	if phase != "":
		last_error = "Map service is busy."
		return false
	if source_hash.is_empty() or draft.get("format")!="gdt.racing-world" or \
			draft.get("name")!="Morrow Coast":
		last_error = "Cannot apply an invalid source snapshot."
		return false
	if not FileAccess.file_exists("res://worlds/morrow-coast.world.json"):
		last_error = "The checked-in Morrow Coast world is missing."
		return false
	var current_sha := FileAccess.get_sha256("res://worlds/morrow-coast.world.json")
	local_baked_sha = loaded_world_sha if not loaded_world_sha.is_empty() else current_sha
	if local_baked_sha.length()!=64 or current_sha != local_baked_sha:
		last_error = "The game map changed on disk since the editor opened. Reload before applying."
		return false
	requested_doc = draft.duplicate(true)
	expected_source_hash = source_hash
	retry_count = 0
	phase = "status"
	return _request(HTTPClient.METHOD_GET,"/api/editor-status")

func start_backend() -> bool:
	# Spawn only after deliberate user action. Never open a browser. The
	# process is terminated when the Godot game exits.
	if started_pid > 0:
		return true
	var path := ProjectSettings.globalize_path(BUILDER)
	if not FileAccess.file_exists(path):
		last_error = "Run from a local Streetbound source checkout."
		return false
	var python := "py" if OS.get_name()=="Windows" else "python3"
	var arguments := PackedStringArray(["-3",path,"--no-browser"]) if \
		OS.get_name()=="Windows" else PackedStringArray([path,"--no-browser"])
	started_pid = OS.create_process(python,arguments)
	if started_pid <= 0:
		last_error = "Python 3 is needed. Run map-editor/Start Native Map Backend.cmd."
		started_pid = -1
		return false
	return true

func _received(result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray) -> void:
	var stage := phase
	if stage.is_empty():
		return
	var content := body.get_string_from_utf8()
	# An HTTP 409 may still carry a useful validation/rollback error even
	# when a platform reports an unsuccessful transport result. Read it
	# before treating the service as unreachable.
	if result != HTTPRequest.RESULT_SUCCESS and response_code < 400:
		_fail("Local map backend is unavailable (transport %d, HTTP %d)." % [
			result,response_code])
		return
	var parsed: Variant = JSON.parse_string(content)
	if not parsed is Dictionary:
		_fail("Invalid response from the local map backend.")
		return
	if response_code < 200 or response_code >= 300:
		_fail(str(parsed.get("error","Map service rejected the operation.")))
		return
	match stage:
		"status":
			if not bool(parsed.get("live",false)) or \
					str(parsed.get("worldSha","")) != local_baked_sha or \
					not bool(parsed.get("overlayExists",false)):
				_fail("Map changed on disk or source overlay is missing; restart Godot and reload the source.")
				return
			token = str(parsed.get("token",""))
			baked_revision = str(parsed.get("worldSha",""))
			if token.length() < 16:
				_fail("Map backend did not authorize the native editor.")
				return
			phase = "source"
			_request(HTTPClient.METHOD_GET,"/api/morrow-edits")
		"source":
			# Abort if browser / another game instance updated the map source
			# since the native editor loaded it.
			var remote_hash: String = JSON.stringify(parsed).sha256_text()
			if remote_hash != expected_source_hash:
				_fail("Map source changed outside this editor. Close and reopen F6 before applying.")
				return
			phase = "apply"
			var payload := JSON.stringify({
				"worldSha":baked_revision,
				"world":requested_doc
			})
			if payload.to_utf8_buffer().size() > 8002048:
				_fail("Native map edit exceeds the 8 MB server limit.")
				return
			var headers := PackedStringArray([
				"Content-Type: application/json",
				"Origin: "+BASE,
				"X-Streetbound-Editor-Token: "+token
			])
			_request(HTTPClient.METHOD_POST,"/api/apply-morrow",headers,payload)
		"apply":
			if not bool(parsed.get("ok",false)) or str(parsed.get("worldSha","")).length()!=64:
				_fail("Rebuild returned no valid playable world.")
				return
			phase = ""
			var new_sha := str(parsed.worldSha)
			requested_doc.clear()
			completed.emit(true,
				"Map rebuilt and saved. Reload World to view new roads, junctions and traffic.",
				new_sha)
		_:
			_fail("Unexpected local map server response.")
