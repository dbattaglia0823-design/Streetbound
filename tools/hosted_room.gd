extends SceneTree
## Cloud VM room process. The Python directory launches this headless Godot
## instance with per-room UDP port and random secret via environment variables.
## This process is the multiplayer authority; no player's machine hosts UDP.
const POLL_FRAMES := 900
var _room_session: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_room_session = root.get_node_or_null("OnlineSession")
	if _room_session == null:
		push_error("Hosted room: OnlineSession autoload is missing.")
		quit(1)
		return
	var port_text := OS.get_environment("STREETBOUND_ROOM_PORT")
	var secret := OS.get_environment("STREETBOUND_ROOM_SECRET")
	var ready_path := OS.get_environment("STREETBOUND_ROOM_READY_FILE")
	if not port_text.is_valid_int() or ready_path.is_empty() or \
			not _room_session.host_dedicated_session(int(port_text), secret):
		push_error("Hosted room: invalid configuration or UDP bind error.")
		quit(1)
		return
	if change_scene_to_file("res://scenes/main.tscn") != OK:
		push_error("Hosted room: failed to launch authoritative Morrow Coast scene.")
		quit(1)
		return
	var world_ready := false
	for index in POLL_FRAMES:
		await process_frame
		var game := current_scene
		if is_instance_valid(game) and is_instance_valid(game.get("online_world")):
			world_ready = true
			break
	if not world_ready:
		push_error("Hosted room: gameplay world did not initialize.")
		quit(1)
		return
	var marker := FileAccess.open(ready_path, FileAccess.WRITE)
	if marker == null:
		push_error("Hosted room: cannot signal readiness.")
		quit(1)
		return
	marker.store_string("READY\n")
	marker.close()
	print("HOSTED ROOM READY (no public credentials in log)")
	# SceneTree stays alive. Exits when process manager reaps or terminates it.
