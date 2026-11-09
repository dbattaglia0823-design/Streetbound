extends Node2D
## Lightweight streamed ambient traffic: right-hand directed lanes, legal turns,
## real stop/yield pauses, simple car-following and player-avoidance.
## AI paths reuse road and junction metadata from the CURRENT playable bake.
const Network = preload("res://scripts/world/traffic_network.gd")
const Car = preload("res://scripts/world/traffic_car.gd")
const PPM := 20.0
const MAX_ACTIVE := 18
const SPAWN_MIN_M := 85.0
const SPAWN_MAX_M := 245.0
const DESPAWN_M := 305.0
var world: Node2D
var player: VehicleController2D
var network := {}
var cars: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var spawn_clock := 0.0
var active := true
var debug_lanes := false
var _debug_anchor := Vector2.INF
var spawned_total := 0
var rejected_spawns := 0


func _ready() -> void:
	name = "TrafficWorld"
	rng.seed = 92319
	if world == null or not world.data.has("roads"):
		active = false
		return
	network = Network.build(world.data)
	z_index = 4


func _route(id: int) -> Dictionary:
	return network.routes[id]


func _make_car(road_id: int, lane_id: int, pos: Vector2) -> Node2D:
	var npc := AnimatableBody2D.new()
	npc.set_script(Car)
	npc.name = "Traffic_%d" % spawned_total
	npc.set("type_index", road_id % 3)
	npc.set("color", [
		Color("809ca2"), Color("b9a28b"), Color("a97662"),
		Color("a7b2a5"), Color("647d91"), Color("c1bcae")
	][(road_id + lane_id) % 6])
	npc.position = pos * PPM
	add_child(npc)
	return npc


func _spawn_one() -> bool:
	if player == null or not network.has("cells"):
		return false
	var center := player.global_position / PPM
	var cell := Vector2i((center / 128.0).floor())
	var candidates: Array = []
	for x in range(cell.x - 2, cell.x + 3):
		for y in range(cell.y - 2, cell.y + 3):
			candidates.append_array(network.cells.get(Vector2i(x, y), []))
	if candidates.is_empty():
		return false
	for attempt in 50:
		var sample: Vector2i = candidates[rng.randi_range(0, candidates.size() - 1)]
		var route_id: int = sample.x
		var lane: Dictionary = _route(route_id)
		var stations: PackedFloat32Array = lane.stations
		var points: PackedVector2Array = lane.points
		var index: int = sample.y
		if index >= points.size() - 4:
			continue
		var p: Vector2 = points[index]
		var radius := p.distance_to(center)
		if radius < SPAWN_MIN_M or radius > SPAWN_MAX_M:
			continue
		if bool(lane.loose) and rng.randf() < 0.87:
			continue
		var busy := false
		for other in cars:
			var other_p: Vector2 = other.car.global_position / PPM
			if other_p.distance_to(p) < 16.0:
				busy = true
				break
		if busy:
			continue
		var car := _make_car(int(lane.road), route_id, p)
		var a := {"car":car,"route":route_id,"station":float(stations[index]),
			"speed":rng.randf_range(4.0,8.0),"cruise":rng.randf_range(0.80,1.04),
			"turn":{},"turn_station":0.0,"turn_distance":0.0,
			"wait":0.0,"waited_junction":-1}
		cars.append(a)
		spawned_total += 1
		return true
	rejected_spawns += 1
	return false


func _choose_link(options: Array[Dictionary]) -> Dictionary:
	if options.is_empty():
		return {}
	# Most traffic continues straight; some cars turn, but never U-turn or
	# teleport to a dirt road disconnected from the paved road network.
	var total := 0.0
	var weights: Array[float] = []
	for link in options:
		var weight := 5.0 if link.turn == "straight" else 2.0 if link.turn == "right" else 1.25
		weights.append(weight)
		total += weight
	var pick := rng.randf() * total
	for i in options.size():
		pick -= weights[i]
		if pick <= 0.0:
			return options[i]
	return options[-1]


func _quadratic(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	return a * (1.0 - t) * (1.0 - t) + b * (2.0 * t * (1.0 - t)) + c * t * t


func _try_turn(agent: Dictionary, options: Array[Dictionary]) -> void:
	var link := _choose_link(options)
	if link.is_empty():
		return
	var route: Dictionary = _route(int(agent.route))
	var target: Dictionary = _route(int(link.to))
	var from_path: PackedVector2Array = route.points
	var target_path: PackedVector2Array = target.points
	var a: Vector2 = from_path[int(link.at)]
	var c: Vector2 = target_path[int(link.target)]
	var midpoint: Vector2 = link.center
	# Approximate a smooth Bezier connector; no hard snapping between roads.
	var length := maxf(4.0, a.distance_to(midpoint) + midpoint.distance_to(c))
	agent.turn = {"a":a,"b":midpoint,"c":c,"to":int(link.to),
		"target_station":float(target.stations[int(link.target)])}
	agent.turn_station = 0.0
	agent.turn_distance = length
	agent.wait = 0.0


func _blocking_speed(agent: Dictionary, p: Vector2, heading: Vector2) -> float:
	var limit := INF
	for other in cars:
		if other == agent:
			continue
		var to: Vector2 = other.car.global_position / PPM - p
		var ahead := to.dot(heading)
		var sideways := absf(to.cross(heading))
		if ahead > 0.0 and ahead < 22.0 and sideways < 2.4:
			limit = minf(limit, maxf(0.0, (ahead - 6.5) * 1.7))
	if is_instance_valid(player):
		var gap: Vector2 = player.global_position / PPM - p
		var forward := gap.dot(heading)
		if forward > -2.0 and forward < 21.0 and absf(gap.cross(heading)) < 3.4:
			limit = minf(limit, maxf(0.0, (forward - 7.0) * 1.6))
	return limit


func _step_car(agent: Dictionary, dt: float) -> bool:
	var route: Dictionary = _route(int(agent.route))
	var car: Node2D = agent.car
	var point := Vector2.ZERO
	var tangent := Vector2.UP
	var target_speed := float(route.speed) * float(agent.cruise)
	var turning: Dictionary = agent.turn
	if not turning.is_empty():
		var t := clampf(float(agent.turn_station) / maxf(float(agent.turn_distance), 0.01), 0.0, 1.0)
		point = _quadratic(turning.a, turning.b, turning.c, t)
		tangent = (_quadratic(turning.a, turning.b, turning.c, minf(t + 0.012, 1.0)) -
			_quadratic(turning.a, turning.b, turning.c, maxf(0.0, t - 0.012))).normalized()
		target_speed = minf(target_speed, 6.0)
	else:
		var points: PackedVector2Array = route.points
		var stations: PackedFloat32Array = route.stations
		var progress := float(agent.station)
		if progress > stations[-1] - 3.0:
			return false # end of road, recycle instead of reversing in place
		point = Network.point_at(route, progress)
		var next := Network.point_at(route, minf(stations[-1], progress + 2.0))
		tangent = (next - point).normalized()
		if tangent.length_squared() < 0.5:
			tangent = Vector2.UP
		var connectors: Array[Dictionary] = Network.next_links(route, progress)
		if not connectors.is_empty():
			var link: Dictionary = connectors[0]
			var to_stop: float = stations[int(link.at)] - progress
			if to_stop < 22.0:
				var speed_limit := 7.0 if link.turn != "straight" else 10.0
				target_speed = minf(target_speed, speed_limit)
				if str(link.control) == "stop":
					if int(agent.waited_junction) != int(link.junction):
						target_speed = minf(target_speed, maxf(0.0, (to_stop - 1.0) * 1.5))
						if to_stop < 2.0 and float(agent.speed) < 1.2:
							agent.waited_junction = int(link.junction)
							agent.wait = rng.randf_range(0.8, 1.5)
				elif str(link.control) == "yield":
					target_speed = minf(target_speed, 3.5 if to_stop < 10.0 else 7.0)
			if to_stop <= 1.6 and float(agent.wait) <= 0.0:
				_try_turn(agent, connectors)
				turning = agent.turn
	if float(agent.wait) > 0.0:
		agent.wait = maxf(0.0, float(agent.wait) - dt)
		target_speed = 0.0
	if tangent.length_squared() < 0.5:
		tangent = Vector2.UP
	target_speed = minf(target_speed, _blocking_speed(agent, point, tangent))
	var speed := move_toward(float(agent.speed), maxf(0.0, target_speed),
		(10.0 if target_speed < float(agent.speed) else 3.5) * dt)
	agent.speed = speed
	if not agent.turn.is_empty():
		agent.turn_station = float(agent.turn_station) + speed * dt
		var info: Dictionary = agent.turn
		var frac := minf(1.0, float(agent.turn_station) / maxf(float(agent.turn_distance), 0.01))
		point = _quadratic(info.a, info.b, info.c, frac)
		var from: Vector2 = _quadratic(info.a, info.b, info.c, maxf(0.0, frac - 0.015))
		var to: Vector2 = _quadratic(info.a, info.b, info.c, minf(1.0, frac + 0.015))
		tangent = (to - from).normalized()
		if frac >= 1.0:
			agent.route = int(info.to)
			agent.station = float(info.target_station) + 0.2
			agent.turn = {}
	else:
		agent.station = float(agent.station) + speed * dt
		point = Network.point_at(route, float(agent.station))
	car.global_position = point * PPM
	car.rotation = tangent.angle() + PI / 2.0
	car.call("set_braking", speed < target_speed - 1.0 or speed < 2.0)
	return true


func _physics_process(dt: float) -> void:
	if not active or player == null or network.is_empty():
		return
	var player_m := player.global_position / PPM
	for i in range(cars.size() - 1, -1, -1):
		var agent: Dictionary = cars[i]
		var car: Node2D = agent.car
		if not is_instance_valid(car) or car.global_position.distance_to(player.global_position) > DESPAWN_M * PPM:
			if is_instance_valid(car):
				car.queue_free()
			cars.remove_at(i)
			continue
		if not _step_car(agent, dt):
			car.queue_free()
			cars.remove_at(i)
	spawn_clock += dt
	if spawn_clock >= 0.6 and cars.size() < MAX_ACTIVE:
		spawn_clock = 0.0
		_spawn_one()
	if debug_lanes and _debug_anchor.distance_to(player_m) > 50.0:
		_debug_anchor = player_m
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and (key.keycode == KEY_F5 or key.physical_keycode == KEY_F5):
			debug_lanes = not debug_lanes
			_debug_anchor = Vector2.INF
			queue_redraw()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if not debug_lanes or not is_instance_valid(player):
		return
	var center := player.global_position / PPM
	for route in network.routes:
		var path: PackedVector2Array = route.points
		var tint := Color(0.55, 0.80, 0.96, 0.44) if int(route.direction) == 1 else Color(1.0, 0.75, 0.35, 0.44)
		var previous := Vector2.INF
		for p in path:
			if p.distance_to(center) > 230.0:
				previous = Vector2.INF
				continue
			if previous != Vector2.INF:
				draw_line(previous * PPM, p * PPM, tint, 3.0, true)
			previous = p
