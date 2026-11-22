extends Node2D
## Friend-only Ashford drag races. The player host alone stages, times and
## validates vehicles; network peers can only request a ready/forfeit action.
## No multiplayer awards or client-supplied transforms/results are accepted.
const Grid = preload("res://scripts/world/race_start_grid.gd")
const PPM := 20.0
const RACE_LENGTH_M := 402.336
const DRAG_START_OFFSET_M := 60.0
const LANE_HALF_WIDTH_M := 9.5
const STAGE_RADIUS_M := 35.0
const STAGE_MAX_SPEED_PX := 6.0 * PPM
const START_DELAY_MS := 4500
const TIME_LIMIT_MS := 180000
const RESULTS_SECONDS := 18.0
const START_MOVE_TOLERANCE_M := 2.5

var online_world
var session: Node
var start_m := Vector2.ZERO
var direction := Vector2.UP
var available := false
var race_id := 0
var state := "idle"
var entries: Dictionary = {} # Int peer ID -> host-owned status/position
var results: Array = []
var countdown_deadline := 0
var started_ms := 0
var results_until_ms := 0
var _client_countdown_end_ms := 0
var _status := ""
var _progress_elapsed := 0.0
var _sync_elapsed := 0.0
var _ui_elapsed := 0.0
var _host_car_was_external := false
var _client_car_was_external := false
var _countdown_slots: Dictionary = {}
var panel: PanelContainer
var status_label: Label
var ready_button: Button
var host_button: Button
var cancel_button: Button

func _ready() -> void:
	name = "FriendDragRace"
	online_world = get_parent()
	session = get_node_or_null("/root/OnlineSession")
	if session == null or not session.active:
		return
	for road in online_world.world.data.roads:
		if str(road.name) != "Ashford Drag Strip":
			continue
		var points: Array = road.points
		if points.size() < 2:
			break
		start_m = Vector2(float(points[0][0]), float(points[0][1]))
		var last: Array = points[points.size() - 1]
		direction = (Vector2(float(last[0]), float(last[1])) - start_m).normalized()
		start_m += direction * DRAG_START_OFFSET_M
		available = direction.length_squared() > 0.9
		break
	if not available:
		push_warning("Friend drag race unavailable: Ashford track not present")
		return
	session.roster_changed.connect(_on_roster)
	session.peer_connection_suspended.connect(_on_peer_suspended)
	session.peer_id_rebound.connect(_on_peer_rebound)
	session.reconnect_finished.connect(_on_reconnect_finished)
	session.session_closed.connect(_on_session_closed)
	var overlay := CanvasLayer.new()
	overlay.name = "FriendRaceOverlay"
	overlay.layer = 5
	add_child(overlay)
	panel = PanelContainer.new()
	panel.name = "FriendRacePanel"
	panel.position = Vector2(20, 132)
	panel.custom_minimum_size = Vector2(440, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.08, 0.12, 0.89)
	style.border_color = Color(0.85, 0.42, 0.17, 0.90)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	panel.add_child(body)
	status_label = Label.new()
	status_label.name = "FriendRaceStatus"
	status_label.custom_minimum_size = Vector2(415, 72)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 15)
	body.add_child(status_label)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	body.add_child(buttons)
	ready_button = _button("JOIN / READY", buttons)
	host_button = _button("OFFER RACE", buttons)
	cancel_button = _button("CANCEL", buttons)
	ready_button.pressed.connect(_on_ready_pressed)
	host_button.pressed.connect(_on_host_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	_refresh_ui()
	queue_redraw()

func _button(title: String, parent: HBoxContainer) -> Button:
	var b := Button.new()
	b.text = title
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(112, 35)
	parent.add_child(b)
	return b

static func lane_offset_m(count: int, index: int) -> float:
	var safe_count := clampi(count, 2, 4)
	var width := 4.6 if safe_count == 4 else 5.5
	return (float(index) - float(safe_count - 1) * 0.5) * width

static func race_position_m(position_px: Vector2, start: Vector2,
		forward: Vector2) -> Vector2:
	var relative := position_px / PPM - start
	return Vector2(relative.dot(forward), relative.cross(forward))

static func valid_finish(previous_m: Vector2, current_m: Vector2,
		distance_m: float = RACE_LENGTH_M) -> bool:
	return previous_m.x < distance_m and current_m.x >= distance_m and \
		absf(current_m.y) <= LANE_HALF_WIDTH_M

static func legal_step(previous_px: Vector2, current_px: Vector2,
		velocity_px: Vector2, dt: float) -> bool:
	var max_step_m := maxf(5.0, velocity_px.length() / PPM * dt * 2.0 + 3.0)
	return previous_px.distance_to(current_px) / PPM <= max_step_m

static func sorted_finishers(records: Dictionary) -> Array:
	var finished: Array = []
	for id in records:
		var record: Dictionary = records[id]
		if str(record.get("status", "")) == "finished":
			finished.append({"id": int(id),
				"name": str(record.get("name", "Driver")),
				"ms": int(record.get("ms", 0))})
	finished.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.ms) < int(b.ms) or \
			(int(a.ms) == int(b.ms) and int(a.id) < int(b.id)))
	return finished

func input_locked(peer_id: int) -> bool:
	return state == "countdown" and entries.has(peer_id) and \
		str(entries[peer_id].get("status", "")) == "staged"

func _car_for(id: int) -> VehicleController2D:
	if id == 1:
		return online_world.local_vehicle as VehicleController2D
	return online_world.peer_cars.get(id) as VehicleController2D

func _near_start(car: VehicleController2D) -> bool:
	return is_instance_valid(car) and \
		car.global_position.distance_to(start_m * PPM) <= STAGE_RADIUS_M * PPM and \
		car.linear_velocity.length() <= STAGE_MAX_SPEED_PX

func _is_connected(id: int) -> bool:
	return session.players.has(id) and not session.disconnected_since.has(id) and \
		(id == 1 or session.world_ready_peers.has(id))

func _on_ready_pressed() -> void:
	if not available or not session.active or state != "lobby":
		return
	var me := int(session.own_id())
	var currently_ready := entries.has(me) and bool(entries[me].get("ready", false))
	if session.hosting:
		_host_set_ready(1, not currently_ready)
	else:
		_request_ready.rpc_id(1, race_id, not currently_ready)

func _on_host_pressed() -> void:
	if not session.hosting or not available:
		return
	if state in ["idle", "results", "aborted"]:
		_host_offer()
	elif state == "lobby":
		_host_start()

func _on_cancel_pressed() -> void:
	if session.hosting:
		_host_cancel()
	elif state == "running":
		_request_forfeit.rpc_id(1, race_id)

func _host_offer() -> void:
	if not session.hosting or not session.active or not available or \
			state not in ["idle", "results", "aborted"] or \
			not _near_start(_car_for(1)):
		return
	race_id += 1
	state = "lobby"
	entries = {1: {"name": str(session.players[1].get("name", "Host")),
		"ready": true, "status": "ready"}}
	results.clear()
	_status = "Friend race opened. Park near Ashford and select JOIN / READY."
	_publish()

func _host_set_ready(id: int, ready: bool) -> void:
	if state != "lobby" or not _is_connected(id) or \
			(ready and not _near_start(_car_for(id))):
		return
	if ready:
		if not entries.has(id) and entries.size() >= session.MAX_PLAYERS:
			return
		entries[id] = {"name": str(session.players[id].get("name", "Driver")),
			"ready": true, "status": "ready"}
	else:
		if id == 1:
			entries[1] = {"name": str(session.players[1].get("name", "Host")),
				"ready": false, "status": "waiting"}
		else:
			entries.erase(id)
	_status = "Drivers ready: %d / %d" % [_ready_count(), session.players.size()]
	_publish()

@rpc("any_peer", "reliable")
func _request_ready(requested_race: int, ready: bool) -> void:
	if not session.hosting or requested_race != race_id:
		return
	var sender := multiplayer.get_remote_sender_id()
	_host_set_ready(sender, ready)

func _ready_count() -> int:
	var n := 0
	for id in entries:
		if bool(entries[id].get("ready", false)):
			n += 1
	return n

func _host_start() -> void:
	if not session.hosting or state != "lobby" or entries.size() < 2 or \
			not bool(entries.get(1, {}).get("ready", false)):
		return
	for id in entries:
		if not bool(entries[id].get("ready", false)) or \
				not _is_connected(int(id)) or not _near_start(_car_for(int(id))):
			_status = "All racers must be parked at the strip, ready, and connected."
			_publish()
			return
	var ids: Array = entries.keys()
	ids.sort()
	_countdown_slots.clear()
	for index in ids.size():
		var id := int(ids[index])
		var car := _car_for(id)
		var slot_m := start_m + direction.orthogonal().normalized() * \
			lane_offset_m(ids.size(), index)
		_countdown_slots[id] = slot_m
		Grid.teleport(car, Grid.pose(slot_m, direction))
		entries[id]["status"] = "staged"
		entries[id]["prev_position"] = car.global_position
		entries[id]["prev_progress"] = 0.0
		entries[id]["ms"] = 0
	_host_car_was_external = online_world.local_vehicle.external_input
	online_world.local_vehicle.external_input = true
	countdown_deadline = Time.get_ticks_msec() + START_DELAY_MS
	state = "countdown"
	_status = "All cars staged. Race starts in 4.5 seconds."
	_publish()

func _host_green() -> void:
	if state != "countdown":
		return
	state = "running"
	started_ms = Time.get_ticks_msec()
	online_world.local_vehicle.external_input = _host_car_was_external
	for id in entries:
		if str(entries[id].get("status", "")) != "staged":
			continue
		var car := _car_for(int(id))
		entries[id]["status"] = "racing"
		entries[id]["prev_position"] = car.global_position
		entries[id]["prev_progress"] = 0.0
	_status = "GREEN! Quarter-mile sprint to the finish."
	_publish()

func _host_forfeit(id: int, reason: String) -> void:
	if state not in ["countdown", "running"] or not entries.has(id):
		return
	if str(entries[id].get("status", "")) in ["finished", "dnf"]:
		return
	entries[id]["status"] = "dnf"
	entries[id]["reason"] = reason
	_publish()
	_host_check_done()

@rpc("any_peer", "reliable")
func _request_forfeit(requested_race: int) -> void:
	if session.hosting and requested_race == race_id:
		var sender := multiplayer.get_remote_sender_id()
		if _is_connected(sender):
			_host_forfeit(sender, "Forfeit")

func _host_check_done() -> void:
	if state != "running":
		return
	for id in entries:
		if str(entries[id].get("status", "")) not in ["finished", "dnf"]:
			return
	state = "results"
	results = sorted_finishers(entries)
	results_until_ms = Time.get_ticks_msec() + roundi(RESULTS_SECONDS * 1000)
	_status = "RACE COMPLETE - results are practice only; no career payouts."
	_publish()

func _host_cancel() -> void:
	if not session.hosting or state == "idle":
		return
	if state == "countdown":
		online_world.local_vehicle.external_input = _host_car_was_external
	state = "aborted"
	_status = "Friend race cancelled. No rewards were granted."
	results_until_ms = Time.get_ticks_msec() + 6000
	_publish()

func _host_evaluate(dt: float) -> void:
	var now := Time.get_ticks_msec()
	for id in entries.keys():
		var record: Dictionary = entries[id]
		if str(record.get("status", "")) != "racing":
			continue
		var car := _car_for(int(id))
		if not is_instance_valid(car):
			_host_forfeit(int(id), "Vehicle unavailable")
			continue
		var prior: Vector2 = record["prev_position"]
		var current: Vector2 = car.global_position
		if not legal_step(prior, current, car.linear_velocity, dt):
			_host_forfeit(int(id), "Invalid vehicle position jump")
			continue
		var previous_m := race_position_m(prior, start_m, direction)
		var current_m := race_position_m(current, start_m, direction)
		record["prev_position"] = current
		record["prev_progress"] = maxf(float(record.get("prev_progress", 0.0)),
			current_m.x)
		if not valid_finish(previous_m, current_m):
			continue
		var current_elapsed := now - started_ms
		if current_elapsed < 7000:
			_host_forfeit(int(id), "Invalid early finish")
			continue
		var covered := current_m.x - previous_m.x
		var fraction := clampf((RACE_LENGTH_M - previous_m.x) / \
			maxf(0.0001, covered), 0.0, 1.0)
		record["status"] = "finished"
		record["ms"] = maxi(0, current_elapsed - roundi((1.0 - fraction) * \
			dt * 1000.0))
		_publish()
	_host_check_done()

func _physics_process(dt: float) -> void:
	if not available or session == null or not session.active:
		return
	if session.hosting:
		match state:
			"countdown":
				for id in entries:
					var car := _car_for(int(id))
					if not is_instance_valid(car):
						continue
					car.command = Vector4.ZERO
					car.nitrous_requested = false
					if car.global_position.distance_to(
							_countdown_slots.get(id, car.global_position) * PPM) > \
							START_MOVE_TOLERANCE_M * PPM:
						_host_cancel()
						return
				if Time.get_ticks_msec() >= countdown_deadline:
					_host_green()
			"running":
				_host_evaluate(dt)
				if state == "running" and Time.get_ticks_msec() - started_ms >= \
						TIME_LIMIT_MS:
					for id in entries.keys():
						if str(entries[id].get("status", "")) == "racing":
							entries[id]["status"] = "dnf"
							entries[id]["reason"] = "Time limit"
					_host_check_done()
			"results", "aborted":
				if results_until_ms > 0 and \
						Time.get_ticks_msec() >= results_until_ms:
					state = "idle"
					entries.clear()
					_status = ""
					_publish()
		_progress_elapsed += dt
		_sync_elapsed += dt
		if state == "running" and _progress_elapsed >= 0.5:
			_progress_elapsed = 0.0
			_send_progress()
		if state in ["lobby", "countdown", "running", "results"] and \
				_sync_elapsed >= 2.0:
			_sync_elapsed = 0.0
			_publish()
	_ui_elapsed += dt
	if _ui_elapsed >= 0.16:
		_ui_elapsed = 0.0
		_refresh_ui()

func _send_progress() -> void:
	var progress: Dictionary = {}
	for id in entries:
		if not entries[id].has("prev_progress"):
			continue
		progress[id] = roundi(maxf(0.0,
			float(entries[id]["prev_progress"])))
	for id in session.world_ready_peers:
		if _is_connected(int(id)):
			_race_progress.rpc_id(int(id), race_id, progress)

@rpc("authority", "unreliable_ordered")
func _race_progress(received_race: int, progress: Dictionary) -> void:
	if session.hosting or received_race != race_id or state != "running":
		return
	for id in progress:
		if entries.has(id) and typeof(progress[id]) == TYPE_INT:
			entries[id]["prev_progress"] = clampi(int(progress[id]), 0, 500)

func _public_entries() -> Dictionary:
	var safe: Dictionary = {}
	for id in entries:
		var data: Dictionary = entries[id]
		safe[id] = {"name": str(data.get("name", "Driver")),
			"ready": bool(data.get("ready", false)),
			"status": str(data.get("status", "waiting")),
			"ms": int(data.get("ms", 0)),
			"reason": str(data.get("reason", "")),
			"prev_progress": roundi(float(data.get("prev_progress", 0.0)))}
	return safe

func _publish() -> void:
	if not session.hosting or not session.active:
		return
	var payload := {
		"race": race_id,
		"state": state,
		"entries": _public_entries(),
		"results": results.duplicate(true),
		"slots": _countdown_slots.duplicate(true) if state == "countdown" else {},
		"remaining_ms": maxi(0, countdown_deadline - Time.get_ticks_msec())
			if state == "countdown" else 0,
		"status": _status}
	for id in session.world_ready_peers:
		if _is_connected(int(id)):
			_race_state.rpc_id(int(id), payload)
	_refresh_ui()

@rpc("authority", "reliable")
func _race_state(payload: Dictionary) -> void:
	if session.hosting or not session.active or payload.size() > 12:
		return
	# Applying a grid teleport, input mode and HUD during ENet's RPC poll
	# can re-enter physics/scene updates. Defer all mutations to the main
	# SceneTree phase while preserving reliable host packet ordering.
	call_deferred("_apply_race_state", payload.duplicate(true))

func _apply_race_state(payload: Dictionary) -> void:
	if session == null or session.hosting or not session.active:
		return
	var new_race := int(payload.get("race", -1))
	if new_race < race_id:
		return
	var next_state := str(payload.get("state", ""))
	if next_state not in ["idle", "lobby", "countdown", "running",
			"results", "aborted"]:
		return
	var previous := state
	var old_race := race_id
	race_id = new_race
	state = next_state
	entries = (payload.get("entries", {}) as Dictionary).duplicate(true)
	results = (payload.get("results", []) as Array).duplicate(true)
	_status = str(payload.get("status", "")).substr(0, 220)
	if next_state == "countdown":
		if previous != "countdown" or old_race != race_id:
			# Position only the local visual/client simulation; the host
			# already teleported and owns the authoritative physical car.
			_client_car_was_external = online_world.local_vehicle.external_input
			var slots: Dictionary = payload.get("slots", {})
			var my_slot: Variant = slots.get(int(session.own_id()))
			if my_slot is Vector2:
				Grid.teleport(online_world.local_vehicle,
					Grid.pose(my_slot, direction))
			online_world.local_vehicle.external_input = true
		var half_rtt := clampi(
			int(session.network_stats().get("rtt_ms", 0)) / 2, 0, 200)
		_client_countdown_end_ms = Time.get_ticks_msec() + \
			maxi(0, int(payload.get("remaining_ms", 0)) - half_rtt)
	elif previous == "countdown":
		online_world.local_vehicle.external_input = \
			_client_car_was_external or get_tree().paused or session.reconnecting
	_refresh_ui()

func _on_roster() -> void:
	if session.hosting and state != "idle":
		for id in entries.keys():
			if not session.players.has(id) and state == "lobby":
				entries.erase(id)
		_publish()

func _on_peer_suspended(id: int) -> void:
	if not session.hosting:
		return
	if state == "lobby" and entries.erase(id):
		_publish()
	elif state == "running":
		_host_forfeit(id, "Connection lost")

func _on_peer_rebound(previous_id: int, new_id: int) -> void:
	if not session.hosting or not entries.has(previous_id):
		return
	var record: Dictionary = entries[previous_id]
	entries.erase(previous_id)
	entries[new_id] = record
	_publish()

func _on_reconnect_finished() -> void:
	# The host repeats race state periodically; the reconnecting guest is
	# never permitted to resume a forfeited run or fabricate a finish time.
	if not session.hosting:
		_refresh_ui()

func _on_session_closed(_reason: String) -> void:
	if online_world != null and is_instance_valid(online_world.local_vehicle) and \
			state == "countdown":
		online_world.local_vehicle.external_input = false
	state = "idle"
	entries.clear()

func _refresh_ui() -> void:
	if not available or not is_instance_valid(panel) or session == null:
		return
	var me := int(session.own_id())
	var can_stage := _near_start(_car_for(1 if session.hosting else me))
	panel.visible = can_stage or state != "idle"
	if not panel.visible:
		return
	host_button.visible = session.hosting
	ready_button.visible = state == "lobby"
	cancel_button.visible = session.hosting and state in ["lobby", "countdown",
		"running"] or not session.hosting and state == "running" and entries.has(me)
	host_button.text = "START RACE" if state == "lobby" else "NEW FRIEND RACE"
	host_button.disabled = (state not in ["idle", "lobby", "results", "aborted"]) or \
		(state == "lobby" and (_ready_count() < 2 or not can_stage)) or \
		(state != "lobby" and not can_stage)
	ready_button.disabled = session.reconnecting or (not can_stage and \
		not entries.has(me))
	ready_button.text = "LEAVE GRID" if entries.has(me) else "JOIN / READY"
	cancel_button.text = "CANCEL" if session.hosting else "FORFEIT"
	var header := "ASHFORD / FRIENDS QUARTER MILE / %d-%d DRIVERS" % [
		2, session.MAX_PLAYERS]
	match state:
		"idle":
			status_label.text = header + "\nPark near the drag-strip start. Host: NEW FRIEND RACE.\nNo cash, XP or career result changes."
		"lobby":
			var listed := []
			for id in entries:
				listed.append("%s: %s" % [str(entries[id].get("name", "Driver")),
					"READY" if bool(entries[id].get("ready", false)) else "WAITING"])
			status_label.text = header + "\n" + ", ".join(listed) + \
				"\n" + _status
		"countdown":
			var remaining := maxi(0, countdown_deadline - Time.get_ticks_msec()) \
				if session.hosting else maxi(0, _client_countdown_end_ms - Time.get_ticks_msec())
			status_label.text = header + "\nSTART IN %.1f SECONDS" % [
				float(remaining) / 1000.0] + "\nAll cars held until green."
		"running":
			var listing := []
			for id in entries:
				var driver: Dictionary = entries[id]
				listing.append("%s: %s" % [str(driver.get("name", "Driver")),
					"%.0f m" % float(driver.get("prev_progress", 0))
					if str(driver.get("status", "")) == "racing" else
					str(driver.get("status", "")).to_upper()])
			status_label.text = header + "\nRACE LIVE / " + \
				", ".join(listing) + "\nHost validates each finish."
		"results":
			var lines := []
			for i in results.size():
				var finish: Dictionary = results[i]
				lines.append("%d. %s - %.3fs" % [i + 1,
					str(finish.get("name", "Driver")),
					float(finish.get("ms", 0)) / 1000.0])
			for id in entries:
				if str(entries[id].get("status", "")) == "dnf":
					lines.append("%s - DNF" % str(entries[id].get("name", "Driver")))
			status_label.text = header + "\n" + ", ".join(lines) + \
				"\nPractice race - no rewards."
		_:
			status_label.text = header + "\n" + _status

func _draw() -> void:
	if not available:
		return
	# Race line and staging location in the same physical Ashford world.
	var x := start_m * PPM
	draw_circle(x, STAGE_RADIUS_M * PPM, Color(0.98, 0.48, 0.16, 0.04))
	draw_arc(x, STAGE_RADIUS_M * PPM, 0, TAU, 72,
		Color(0.92, 0.44, 0.16, 0.65), 2.0, true)
