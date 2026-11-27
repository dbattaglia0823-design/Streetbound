extends Node2D
## Host-authoritative friend drag, circuit and street races. The host stages, times and
## validates vehicles; network peers can only request a ready/forfeit action.
## No multiplayer awards or client-supplied transforms/results are accepted.
const Grid = preload("res://scripts/world/race_start_grid.gd")
const Standings = preload("res://scripts/network/online_race_standings.gd")
const Rewards = preload("res://scripts/network/online_race_rewards.gd")
const GuidanceScript = preload("res://scripts/world/race_guidance.gd")
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
const CIRCUIT_GATE_SPACING_M := 110.0
const CIRCUIT_GATE_RADIUS_M := 16.0
const CIRCUIT_LANE_SPACING_M := 3.0
const CIRCUIT_TIMEOUT_MS := 480000
const CIRCUIT_MIN_FINISH_MS := 25000
const STREET_GATE_SPACING_M := 80.0
const STREET_GATE_RADIUS_M := 10.0
const STREET_GRID_GAP_M := 9.0
const STREET_TIMEOUT_MS := 300000
const STREET_MIN_FINISH_MS := 18000
const STREET_OFF_ROUTE_LIMIT_M := 16.0
const STREET_OFF_ROUTE_GRACE_S := 3.0

var online_world
var session: Node
var start_m := Vector2.ZERO
var direction := Vector2.UP
var available := false
var drag_available := false
var circuit_available := false
var drag_start_m := Vector2.ZERO
var drag_direction := Vector2.UP
var circuit_start_m := Vector2.ZERO
var circuit_direction := Vector2.UP
var circuit_navigation: RefCounted
var circuit_gates: Array[Dictionary] = []
var circuit_length_m := 0.0
var street_available := false
var street_start_m := Vector2.ZERO
var street_direction := Vector2.UP
var street_navigation: RefCounted
var street_gates: Array[Dictionary] = []
var street_length_m := 0.0
var event_kind := "drag"
var event_id := ""
var race_events: Dictionary = {} # Trusted local world routes, never guest-supplied.
var active_title := ""
var active_laps := 1
var active_grid: Dictionary = {}
var active_reward_settings: Dictionary = {}
var active_stage_radius_m := STAGE_RADIUS_M
var active_gate_radius_m := STREET_GATE_RADIUS_M
var active_time_limit_ms := TIME_LIMIT_MS
var active_off_route_limit_m := STREET_OFF_ROUTE_LIMIT_M
var authored_event := false
var race_guidance: Node2D
var race_id := 0
var state := "idle"
var entries: Dictionary = {} # Int peer ID -> host-owned status/position
var results: Array = []
var standings: Dictionary = {} # Session points, distinct from persistent prizes.
var _last_reward_race_id := 0
var _last_reward_message := ""
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
	drag_available = available
	drag_start_m = start_m
	drag_direction = direction
	# Reuse the real prebuilt, verified 1+ km circuit road/racing line.
	# All server checkpoints use the host's authoritative navigation data.
	var circuit: Node = online_world.get_parent().get("circuit_race") as Node
	if is_instance_valid(circuit) and bool(circuit.get("available")):
		circuit_navigation = circuit.get("navigation") as RefCounted
		if circuit_navigation != null:
			circuit_start_m = circuit.get("start_m") as Vector2
			circuit_direction = circuit.get("heading") as Vector2
			circuit_length_m = float(circuit_navigation.get("length_m"))
			circuit_gates = make_circuit_gates(circuit_navigation,
				CIRCUIT_GATE_SPACING_M)
			circuit_available = circuit_length_m >= 1000.0 and \
				circuit_gates.size() >= 8
	# Use the directed road route from the existing (disabled) solo sprint.
	var street: Node = online_world.get_parent().get("street_race") as Node
	if is_instance_valid(street) and bool(street.get("available")):
		street_navigation = street.get("navigation") as RefCounted
		if street_navigation != null:
			street_start_m = street.get("start_m") as Vector2
			street_direction = street.get("heading") as Vector2
			street_length_m = float(street_navigation.get("length_m"))
			street_gates = make_street_gates(street_navigation)
			street_available = street_length_m >= 600.0 and street_gates.size() >= 8
	# Built-in locations are catalog entries just like published map races.
	if drag_available:
		race_events["drag"] = {"kind":"drag", "title":"ASHFORD / QUARTER MILE",
			"start":drag_start_m, "direction":drag_direction,
			"limit_ms":TIME_LIMIT_MS}
	if circuit_available:
		race_events["circuit"] = {"kind":"circuit",
			"title":"ASHFORD GRAND CIRCUIT / FULL LAP",
			"start":circuit_start_m, "direction":circuit_direction,
			"navigation":circuit_navigation, "gates":circuit_gates,
			"length":circuit_length_m, "limit_ms":CIRCUIT_TIMEOUT_MS}
	if street_available:
		race_events["street"] = {"kind":"street", "title":"LARKSPUR / STREET SPRINT",
			"start":street_start_m, "direction":street_direction,
			"navigation":street_navigation, "gates":street_gates,
			"length":street_length_m, "limit_ms":STREET_TIMEOUT_MS}
	var authored: Variant = online_world.get_parent().get("extra_races")
	if authored is Array:
		for race_node in authored:
			if not is_instance_valid(race_node) or not bool(race_node.get("available")):
				continue
			var definition: Variant = race_node.get("definition")
			if not definition is Dictionary or not str(definition.get("id","")).begins_with("race-"):
				continue
			var record: Dictionary = authored_event_spec(definition,
				race_node.get("navigation") as RefCounted)
			if not record.is_empty() and not race_events.has(str(definition.id)):
				race_events[str(definition.id)] = record
	available = not race_events.is_empty()
	if not available:
		push_warning("Friend race unavailable: supported routes not present")
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
	race_guidance = Node2D.new()
	race_guidance.name = "FriendCircuitGuidance"
	race_guidance.set_script(GuidanceScript)
	add_child(race_guidance)
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


static func make_circuit_gates(nav: RefCounted,
		spacing_m: float = CIRCUIT_GATE_SPACING_M, min_length_m: float = 1000.0) -> Array[Dictionary]:
	var gates: Array[Dictionary] = []
	if nav == null:
		return gates
	var length: float = float(nav.get("length_m"))
	if length < min_length_m or not bool(nav.get("closed")):
		return gates
	var count := clampi(ceili(length / maxf(50.0, spacing_m)), 8, 128)
	for index in range(1, count + 1):
		var station := length * float(index) / float(count)
		var center: Vector2 = nav.call("point_at", station)
		var prior: Vector2 = nav.call("point_at", station - 5.0)
		var next: Vector2 = nav.call("point_at", station + 5.0)
		var tangent := (next - prior).normalized()
		if tangent.length_squared() < 0.9:
			return []
		gates.append({"position": center, "forward": tangent})
	return gates

## A street sprint is an open route: each gate must be crossed in order and
## only in the direction of traffic. The final gate is the physical finish.
static func make_street_gates(nav: RefCounted,
		spacing_m: float = STREET_GATE_SPACING_M, min_length_m: float = 600.0) -> Array[Dictionary]:
	var gates: Array[Dictionary] = []
	if nav == null or bool(nav.get("closed")):
		return gates
	var length: float = float(nav.get("length_m"))
	if length < min_length_m:
		return gates
	var count := clampi(ceili(length / maxf(50.0, spacing_m)), 8, 128)
	for index in range(1, count + 1):
		var station := (length - 5.0) * float(index) / float(count)
		var center: Vector2 = nav.call("point_at", station)
		var forward: Vector2 = (nav.call("point_at", minf(length, station + 4.0)) -
			nav.call("point_at", maxf(0.0, station - 4.0))).normalized()
		if forward.length_squared() < 0.9:
			return []
		gates.append({"position": center, "forward": forward})
	return gates

## Convert a map-authored route into a host-verifiable multiplayer event.
## Coordinates are taken from the locally loaded map, never from an RPC.
## Only explicitly authored underground events carry heat. Legal street
## layouts and sanctioned races do not become crimes by road type alone.
static func authored_race_heat(definition: Dictionary) -> int:
	var heat: Variant = definition.get("race_heat", 0)
	if not (heat is int or heat is float) or not is_finite(float(heat)):
		return 0
	if float(heat) != floorf(float(heat)) or float(heat) < 1.0 or float(heat) > 5.0:
		return 0
	return int(heat)

static func authored_event_spec(definition: Dictionary, nav: RefCounted) -> Dictionary:
	if not Rewards.valid_settings(definition):
		return {}
	if nav == null or not str(definition.get("id","")).begins_with("race-"):
		return {}
	var mode: String = str(definition.get("mode",""))
	if mode not in ["circuit","sprint"] or bool(nav.get("closed")) != (mode=="circuit"):
		return {}
	var length: float = float(nav.get("length_m"))
	if not is_finite(length) or length < 120.0:
		return {}
	var kind := "circuit" if mode == "circuit" else "street"
	var gates: Array[Dictionary] = make_circuit_gates(nav, CIRCUIT_GATE_SPACING_M,
		120.0) if mode == "circuit" else make_street_gates(nav,
		STREET_GATE_SPACING_M, 120.0)
	if gates.size() < 8:
		return {}
	var grid: Dictionary = definition.duplicate(true)
	var start_pose: Dictionary = Grid.player_slot(grid)
	var start: Vector2 = Grid.point(start_pose)
	var direction: Vector2 = Vector2.UP.rotated(Grid.angle(start_pose))
	if not start.is_finite() or direction.length_squared() < 0.9:
		return {}
	var laps: int = clampi(int(definition.get("laps",1)), 1, 20) if mode=="circuit" else 1
	var requested_limit: float = float(definition.get("time_limit",0))
	var allowed_limit_ms: int = clampi(roundi(requested_limit * 1000.0),
		30000, 7200000) if requested_limit > 0.0 else clampi(
		roundi(length * float(laps) / 12.0 * 1000.0), 90000, 7200000)
	var checkpoint_radius: float = clampf(
		float(definition.get("checkpoint_radius",16)), 4.0, 60.0)
	return {"kind":kind, "title":str(definition.get("name","Custom Race")).left(80),
		"start":start, "direction":direction, "navigation":nav, "gates":gates,
		"length":length, "grid":grid, "laps":laps,
		"reward_settings": definition.duplicate(true),
		"race_heat": authored_race_heat(definition),
		"stage_radius":maxf(STAGE_RADIUS_M, float(definition.get("start_radius",8))),
		"gate_radius":checkpoint_radius,
		"off_route_limit":maxf(STREET_OFF_ROUTE_LIMIT_M, checkpoint_radius * 1.35),
		"limit_ms":allowed_limit_ms}

## Prefer player/enemy start poses authored in the map. Fill absent AI
## positions with the editor's formation rules for time-trial friend races.
static func authored_grid_pose(definition: Dictionary, index: int) -> Dictionary:
	var player_pose: Dictionary = Grid.player_slot(definition)
	if index == 0:
		return player_pose
	var opponents: Array = definition.get("enemy_starts",[])
	if index - 1 < opponents.size() and opponents[index - 1] is Dictionary:
		return opponents[index - 1]
	return Grid.default_enemy(player_pose, index - 1,
		str(definition.get("formation","single_file")))

## Centerline-only safe stagger, never four cars abreast on narrow streets.
static func street_grid_pose(nav: RefCounted, index: int, count: int) -> Dictionary:
	if nav == null or index < 0 or count < 2 or count > 4 or index >= count:
		return {}
	if float(nav.get("length_m")) < 600.0:
		return {}
	var station := 2.0 + float(index) * STREET_GRID_GAP_M
	var center: Vector2 = nav.call("point_at", station)
	var tangent: Vector2 = (nav.call("point_at", station + 2.0) -
		nav.call("point_at", station - 1.5)).normalized()
	if tangent.length_squared() < 0.9:
		return {}
	return Grid.pose(center, tangent)

static func passed_directional_gate(previous_m: Vector2, current_m: Vector2,
		gate: Dictionary, radius_m: float = CIRCUIT_GATE_RADIUS_M) -> bool:
	if not (gate.get("position") is Vector2) or not \
			(gate.get("forward") is Vector2):
		return false
	var center: Vector2 = gate["position"]
	var forward: Vector2 = gate["forward"]
	if forward.length_squared() < 0.9:
		return false
	if (current_m - previous_m).dot(forward) <= 0.01:
		return false
	if (previous_m - center).dot(forward) >= 0.0 or \
			(current_m - center).dot(forward) < 0.0:
		return false
	return Geometry2D.get_closest_point_to_segment(
		center, previous_m, current_m).distance_to(center) <= radius_m

static func next_circuit_gate_index(current_gate: int, previous_m: Vector2,
		current_m: Vector2, gates: Array[Dictionary]) -> int:
	if current_gate < 0 or current_gate >= gates.size():
		return current_gate
	return current_gate + 1 if passed_directional_gate(previous_m, current_m,
		gates[current_gate]) else current_gate

func _nearest_available_event(car: VehicleController2D) -> String:
	if not is_instance_valid(car):
		return ""
	var nearest := ""
	var distance := INF
	for key in race_events:
		var record: Dictionary = race_events[key]
		var stage_radius: float = float(record.get("stage_radius",STAGE_RADIUS_M))
		var gap: float = car.global_position.distance_to(
			(record["start"] as Vector2) * PPM)
		if gap <= stage_radius * PPM and gap < distance:
			nearest = str(key)
			distance = gap
	return nearest

func _configure_event(key: String) -> bool:
	if not race_events.has(key):
		return false
	var record: Dictionary = race_events[key]
	event_id = key
	event_kind = str(record["kind"])
	active_title = str(record["title"])
	start_m = record["start"]
	direction = record["direction"]
	active_laps = int(record.get("laps",1))
	active_grid = record.get("grid",{})
	active_reward_settings = record.get("reward_settings",{})
	authored_event = not active_grid.is_empty()
	active_stage_radius_m = float(record.get("stage_radius",STAGE_RADIUS_M))
	active_gate_radius_m = float(record.get("gate_radius",
		CIRCUIT_GATE_RADIUS_M if event_kind=="circuit" else STREET_GATE_RADIUS_M))
	active_off_route_limit_m = float(record.get("off_route_limit",STREET_OFF_ROUTE_LIMIT_M))
	active_time_limit_ms = int(record.get("limit_ms",TIME_LIMIT_MS))
	if event_kind == "circuit":
		circuit_navigation = record["navigation"]
		circuit_gates = record["gates"]
		circuit_length_m = float(record["length"])
	elif event_kind == "street":
		street_navigation = record["navigation"]
		street_gates = record["gates"]
		street_length_m = float(record["length"])
	queue_redraw()
	return true

func _event_title(key: String) -> String:
	return str(race_events.get(key,{}).get("title","FRIEND RACE"))

func _time_limit_ms() -> int:
	return active_time_limit_ms

func _minimum_finish_ms() -> int:
	if not authored_event:
		return CIRCUIT_MIN_FINISH_MS if event_kind=="circuit" else STREET_MIN_FINISH_MS
	var length: float = circuit_length_m if event_kind=="circuit" else street_length_m
	return maxi(1200, roundi(length * float(active_laps) / 150.0 * 1000.0))

func _car_for(id: int) -> VehicleController2D:
	if id == 1:
		return online_world.local_vehicle as VehicleController2D
	return online_world.peer_cars.get(id) as VehicleController2D

func _near_start(car: VehicleController2D) -> bool:
	return is_instance_valid(car) and \
		car.global_position.distance_to(start_m * PPM) <= active_stage_radius_m * PPM and \
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
			state not in ["idle", "results", "aborted"]:
		return
	var chosen := _nearest_available_event(_car_for(1))
	if chosen.is_empty() or not _configure_event(chosen) or \
			not _near_start(_car_for(1)):
		return
	race_id += 1
	state = "lobby"
	entries = {1: {"name": str(session.players[1].get("name", "Host")),
		"ready": true, "status": "ready"}}
	results.clear()
	_last_reward_message = ""
	_status = "%s opened. Park nearby and select JOIN / READY." % \
		_event_title(event_id)
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
			_status = "All racers must be parked at the event start, ready, and connected."
			_publish()
			return
	var ids: Array = entries.keys()
	ids.sort()
	_countdown_slots.clear()
	for index in ids.size():
		var id := int(ids[index])
		var car := _car_for(id)
		if authored_event or event_kind == "street":
			var spawn_pose: Dictionary = authored_grid_pose(active_grid, index) if (
				authored_event) else street_grid_pose(street_navigation, index, ids.size())
			if spawn_pose.is_empty():
				_host_cancel()
				return
			_countdown_slots[id] = spawn_pose
			Grid.teleport(car, spawn_pose)
		else:
			var offset := (float(index) - float(ids.size() - 1) * 0.5) * (
				CIRCUIT_LANE_SPACING_M if event_kind == "circuit" else
				lane_offset_m(ids.size(), index))
			var slot_m := start_m + direction.orthogonal().normalized() * offset
			_countdown_slots[id] = slot_m
			Grid.teleport(car, Grid.pose(slot_m, direction))
		entries[id]["status"] = "staged"
		entries[id]["car_id"] = str(session.players.get(id,{}).get("car_id",""))
		entries[id]["prev_position"] = car.global_position
		entries[id]["prev_progress"] = 0.0
		entries[id]["next_gate"] = 0
		entries[id]["lap"] = 1
		entries[id]["off_route_seconds"] = 0.0
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
	if session.hosting and online_world.has_method("on_illegal_race_started"):
		online_world.call("on_illegal_race_started")
	match event_kind:
		"circuit": _status = "GREEN! Complete every circuit checkpoint!"
		"street": _status = "GREEN! Follow the streets and cross every checkpoint!"
		_: _status = "GREEN! Quarter-mile sprint to the finish."
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
	var world_id: String = str(session.world_identity.get("id","unknown"))
	var world_digest: String = str(session.world_identity.get("sha256","")).substr(0,12)
	standings = Standings.settle(standings, entries, results, event_kind, race_id,
		"%s/%s/%s" % [world_id, world_digest, event_id])
	results_until_ms = Time.get_ticks_msec() + roundi(RESULTS_SECONDS * 1000)
	_status = "RACE COMPLETE - host results verified. Career prizes available."
	_award_own_finish()
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
	if event_kind == "circuit":
		_host_evaluate_circuit(dt)
		return
	if event_kind == "street":
		_host_evaluate_street(dt)
		return
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


func _host_evaluate_circuit(dt: float) -> void:
	if circuit_navigation == null or circuit_gates.is_empty():
		_host_cancel()
		return
	var now := Time.get_ticks_msec()
	for id in entries.keys():
		var record: Dictionary = entries[id]
		if str(record.get("status", "")) != "racing":
			continue
		var car := _car_for(int(id))
		if not is_instance_valid(car):
			_host_forfeit(int(id), "Vehicle unavailable")
			continue
		var previous_px: Vector2 = record.get("prev_position", car.global_position)
		var current_px: Vector2 = car.global_position
		if not legal_step(previous_px, current_px, car.linear_velocity, dt):
			_host_forfeit(int(id), "Invalid position jump")
			continue
		record["prev_position"] = current_px
		var next_gate := int(record.get("next_gate", 0))
		if next_gate < 0 or next_gate >= circuit_gates.size():
			_host_forfeit(int(id), "Invalid checkpoint progress")
			continue
		var current_m := current_px / PPM
		var previous_m := previous_px / PPM
		var station := float(circuit_navigation.call("station_at", current_m))
		var nearest: Vector2 = circuit_navigation.call("point_at", station)
		# Route gates, not shortcut-prone station projection, determine
		# completion. Leaving the track cannot silently award a checkpoint.
		if current_m.distance_to(nearest) > active_gate_radius_m:
			continue
		var new_gate := next_circuit_gate_index(next_gate, previous_m,
			current_m, circuit_gates)
		if new_gate == next_gate:
			continue
		record["next_gate"] = new_gate
		var lap: int = int(record.get("lap",1))
		record["prev_progress"] = circuit_length_m * (
			float(lap-1) + float(next_gate + 1) / float(circuit_gates.size()))
		if next_gate != circuit_gates.size() - 1:
			continue
		if lap < active_laps:
			record["lap"] = lap + 1
			record["next_gate"] = 0
			continue
		var elapsed_ms := now - started_ms
		if elapsed_ms < _minimum_finish_ms():
			_host_forfeit(int(id), "Impossible circuit lap time")
			continue
		var center: Vector2 = circuit_gates[next_gate]["position"]
		var tangent: Vector2 = circuit_gates[next_gate]["forward"]
		var moved := current_m - previous_m
		var crossing_fraction := clampf(-(previous_m - center).dot(tangent) / \
			maxf(0.0001, moved.dot(tangent)), 0.0, 1.0)
		record["status"] = "finished"
		record["ms"] = maxi(0, elapsed_ms - roundi((1.0 - crossing_fraction) * \
			dt * 1000.0))
		_publish()
	_host_check_done()

func _host_evaluate_street(dt: float) -> void:
	if street_navigation == null or street_gates.is_empty():
		_host_cancel()
		return
	var now := Time.get_ticks_msec()
	for id in entries.keys():
		var record: Dictionary = entries[id]
		if str(record.get("status", "")) != "racing":
			continue
		var car := _car_for(int(id))
		if not is_instance_valid(car):
			_host_forfeit(int(id), "Vehicle unavailable")
			continue
		var prior_px: Vector2 = record.get("prev_position", car.global_position)
		var current_px: Vector2 = car.global_position
		if not legal_step(prior_px, current_px, car.linear_velocity, dt):
			_host_forfeit(int(id), "Invalid position jump")
			continue
		record["prev_position"] = current_px
		var current_m := current_px / PPM
		var prior_m := prior_px / PPM
		var station := float(street_navigation.call("station_at", current_m))
		var nearest: Vector2 = street_navigation.call("point_at", station)
		if current_m.distance_to(nearest) > active_off_route_limit_m:
			record["off_route_seconds"] = float(record.get("off_route_seconds", 0.0)) + dt
			if float(record["off_route_seconds"]) >= STREET_OFF_ROUTE_GRACE_S:
				_host_forfeit(int(id), "Left street race route")
			continue
		record["off_route_seconds"] = 0.0
		var next_gate := int(record.get("next_gate", 0))
		if next_gate < 0 or next_gate >= street_gates.size():
			_host_forfeit(int(id), "Invalid checkpoint state")
			continue
		if not passed_directional_gate(prior_m, current_m, street_gates[next_gate],
				active_gate_radius_m):
			continue
		record["next_gate"] = next_gate + 1
		record["prev_progress"] = street_length_m * float(next_gate + 1) / float(street_gates.size())
		if next_gate < street_gates.size() - 1:
			continue
		var elapsed_ms := now - started_ms
		if elapsed_ms < _minimum_finish_ms():
			_host_forfeit(int(id), "Impossible street race finish")
			continue
		var center: Vector2 = street_gates[next_gate]["position"]
		var forward: Vector2 = street_gates[next_gate]["forward"]
		var crossed := current_m - prior_m
		var fraction := clampf(-(prior_m - center).dot(forward) /
			maxf(0.0001, crossed.dot(forward)), 0.0, 1.0)
		record["status"] = "finished"
		record["ms"] = maxi(0, elapsed_ms - roundi((1.0 - fraction) * dt * 1000.0))
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
							(Grid.point(_countdown_slots[id]) if
							_countdown_slots[id] is Dictionary else
							_countdown_slots.get(id, car.global_position)) * PPM) > \
							START_MOVE_TOLERANCE_M * PPM:
						_host_cancel()
						return
				if Time.get_ticks_msec() >= countdown_deadline:
					_host_green()
			"running":
				_host_evaluate(dt)
				if state == "running" and Time.get_ticks_msec() - started_ms >= \
						_time_limit_ms():
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
	if is_instance_valid(race_guidance):
		race_guidance.call("set_guidance",
			street_navigation if event_kind == "street" else circuit_navigation,
			online_world.local_vehicle, event_kind in ["circuit", "street"] and
			state in ["countdown", "running"])
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
			entries[id]["prev_progress"] = clampi(int(progress[id]), 0, ceili(maxf(500.0, maxf(street_length_m, circuit_length_m))))

func _public_entries() -> Dictionary:
	var safe: Dictionary = {}
	for id in entries:
		var data: Dictionary = entries[id]
		safe[id] = {"name": str(data.get("name", "Driver")),
			"ready": bool(data.get("ready", false)),
			"status": str(data.get("status", "waiting")),
			"ms": int(data.get("ms", 0)),
			"reason": str(data.get("reason", "")),
			"car_id": str(data.get("car_id", "")),
			"prev_progress": roundi(float(data.get("prev_progress", 0.0)))}
	return safe

func _publish() -> void:
	if not session.hosting or not session.active:
		return
	var payload := {
		"race": race_id,
		"event": event_id,
		"state": state,
		"entries": _public_entries(),
		"results": results.duplicate(true),
		"standings": standings.duplicate(true),
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
	var incoming_event := str(payload.get("event", ""))
	if not _configure_event(incoming_event):
		return
	var previous := state
	var old_race := race_id
	race_id = new_race
	state = next_state
	entries = (payload.get("entries", {}) as Dictionary).duplicate(true)
	results = (payload.get("results", []) as Array).duplicate(true)
	if payload.get("standings", {}) is Dictionary:
		standings = (payload.get("standings", {}) as Dictionary).duplicate(true)
	if new_race != old_race:
		_last_reward_message = ""
	_status = str(payload.get("status", "")).substr(0, 220)
	if next_state == "results":
		# The authority RPC settles the final results. All reward values
		# are recomputed on each driver's own installation, never trusted
		# from network payout numbers.
		_award_own_finish()
	if next_state == "countdown":
		if previous != "countdown" or old_race != race_id:
			# Position only the local visual/client simulation; the host
			# already teleported and owns the authoritative physical car.
			_client_car_was_external = online_world.local_vehicle.external_input
			var slots: Dictionary = payload.get("slots", {})
			var my_slot: Variant = slots.get(int(session.own_id()))
			if my_slot is Dictionary:
				Grid.teleport(online_world.local_vehicle, my_slot)
			elif my_slot is Vector2:
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

## Exactly one local, durable career prize for each host-verified finish.
## Results are replicated reliably and can be retried after a save failure.
func _award_own_finish() -> void:
	if state != "results" or session == null or not session.active or \
			not session.valid_secret(session.reward_session_id):
		return
	if _last_reward_race_id == race_id and not _last_reward_message.is_empty() and \
			not _last_reward_message.begins_with("REWARD SAVE FAILED"):
		return
	var personal_id: int = int(session.own_id())
	var finisher: Dictionary = Rewards.confirmed_finisher(entries,results,personal_id)
	if finisher.is_empty():
		return # DNF, spectator, or malformed/incomplete official finish set.
	var game: Node = online_world.get_parent()
	var owned: VehicleOwnership = game.get("vehicle_ownership") as VehicleOwnership
	if not is_instance_valid(owned):
		return
	var receipt: Dictionary = owned.record_multiplayer_race(
		session.reward_session_id,race_id,int(finisher.place),int(finisher.ms),
		event_kind,str(finisher.car_id),active_reward_settings)
	_last_reward_race_id = race_id
	match str(receipt.get("result","")):
		"completed":
			var part: Dictionary = receipt.get("part",{})
			_last_reward_message = "CAREER +%s  +%d DRIVER XP  +%d CAR XP" % [
				VehicleOwnership.dollars(int(receipt.get("cash",0))),
				int(receipt.get("player_xp",0)),int(receipt.get("car_xp",0))]
			if not part.is_empty():
				_last_reward_message += "  /  PART: %s" % str(part.get("name","UPGRADE"))
		"already_claimed":
			_last_reward_message = "CAREER REWARD ALREADY COLLECTED"
		"save_failed":
			_last_reward_message = "REWARD SAVE FAILED - RETRYING"
		_:
			_last_reward_message = "REWARD NOT PAID: " + str(receipt.get("result","invalid"))

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
	elif state == "countdown" and entries.has(id):
		# Do not go green with a racer who vanished before the start.
		_host_cancel()
	elif state == "running":
		_host_forfeit(id, "Connection lost")

func _on_peer_rebound(previous_id: int, new_id: int) -> void:
	if not session.hosting or not entries.has(previous_id):
		return
	var record: Dictionary = entries[previous_id]
	entries.erase(previous_id)
	entries[new_id] = record
	if standings.has(previous_id):
		standings[new_id] = standings[previous_id]
		standings.erase(previous_id)
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

## Show the prizes actually active on this route, including authored
## overrides. Every peer calculates this from its installed world archive.
func _reward_preview(key: String) -> String:
	var event: Dictionary = race_events.get(key,{})
	if event.is_empty():
		return ""
	var rules: Dictionary = event.get("reward_settings",{})
	var kind: String = str(event.get("kind",""))
	var top: Dictionary = Rewards.payouts(kind,1,rules)
	if top.is_empty():
		return ""
	return "1st: %s / %d DRIVER XP / %d CAR XP / %d%% PART" % [
		VehicleOwnership.dollars(int(top.get("cash",0))),
		int(top.get("player_xp",0)),int(top.get("car_xp",0)),
		Rewards.part_chance(1,rules)]

func _session_standings_line() -> String:
	var ranked: Array = Standings.ranked(standings)
	if ranked.is_empty():
		return "FRIEND POINTS: 10 / 7 / 5 / 3 by finishing position."
	var lines: Array[String] = []
	for i in mini(4, ranked.size()):
		var item: Dictionary = ranked[i]
		lines.append("%s %d pts" % [
			str(item.get("name", "Driver")), int(item.get("points", 0))])
	return "SESSION STANDINGS: " + " / ".join(lines)

func _refresh_ui() -> void:
	if not available or not is_instance_valid(panel) or session == null:
		return
	var me := int(session.own_id())
	var car := _car_for(1 if session.hosting else me)
	var nearby_event := _nearest_available_event(car) if state == "idle" else event_id
	var can_stage := not nearby_event.is_empty() if state == "idle" else \
		_near_start(car)
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
	var header := "%s / %d-%d FRIENDS" % [
		_event_title(nearby_event), 2, session.MAX_PLAYERS]
	match state:
		"idle":
			status_label.text = header + \
				"\nPark by the race start. Host: NEW FRIEND RACE." + \
				"\nDrag, circuit or street sprint. " + _session_standings_line() + \
				"\n" + _reward_preview(nearby_event)
		"lobby":
			var listed := []
			for id in entries:
				listed.append("%s: %s" % [str(entries[id].get("name", "Driver")),
					"READY" if bool(entries[id].get("ready", false)) else "WAITING"])
			status_label.text = header + "\n" + ", ".join(listed) + \
				"\n" + _status + "\n" + _reward_preview(event_id)
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
				", ".join(listing) + \
				("\nAll circuit checkpoints required." if event_kind in \
				["circuit", "street"] else "\nHost validates each finish.")
		"results":
			var lines := []
			for i in results.size():
				var finish: Dictionary = results[i]
				var earned := int(standings.get(int(finish.get("id", 0)), {}).get("last_points", 0))
				lines.append("%d. %s - %.3fs  +%d pts" % [i + 1,
					str(finish.get("name", "Driver")),
					float(finish.get("ms", 0)) / 1000.0, earned])
			for id in entries:
				if str(entries[id].get("status", "")) == "dnf":
					lines.append("%s - DNF" % str(entries[id].get("name", "Driver")))
			status_label.text = header + "\n" + ", ".join(lines) + \
				"\n" + _session_standings_line() + \
				("\n" + _last_reward_message if not _last_reward_message.is_empty() else
				"\nDNF / spectators receive no career payouts.")
		_:
			status_label.text = header + "\n" + _status

func _draw() -> void:
	if not available:
		return
	# Every placed Map Builder race becomes visible in the shared world.
	var starts: Array[Vector2] = []
	for key in race_events:
		starts.append(race_events[key]["start"])
	for anchor in starts:
		var x := anchor * PPM
		draw_circle(x, STAGE_RADIUS_M * PPM, Color(0.98, 0.48, 0.16, 0.04))
		draw_arc(x, STAGE_RADIUS_M * PPM, 0, TAU, 72,
			Color(0.92, 0.44, 0.16, 0.65), 2.0, true)
