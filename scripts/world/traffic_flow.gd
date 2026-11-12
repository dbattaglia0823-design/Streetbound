extends Node2D
## Bounded near-player traffic with real car artwork, physical collision,
## directed lane routing and local post-collision path recovery.
const Network = preload("res://scripts/world/traffic_network.gd")
const Car = preload("res://scripts/world/traffic_car.gd")
const PPM := 20.0
const COMFORT_BRAKE := PPM * 9.0
const HARD_BRAKE := PPM * 24.0
const LOOKAHEAD_SECONDS := 2.25
const TURN_RESPONSE := 5.2
const MAX_TURN_RATE := deg_to_rad(95.0)
# Real-world movement is authoritative: zero waypoint progress or a requested
# speed is not proof the chassis is actually moving.
const STUCK_WINDOW_SECONDS := 0.75
const STUCK_DISTANCE_PX := PPM * 0.65
const STUCK_REMOVE_SECONDS := 12.0
const STUCK_RECOVERY_SECONDS := 8.0
const VIEW_MARGIN_PX := 80.0
const VIEWER_PROXIMITY_PX := PPM * 35.0
const PATH_SCAN_STEP_PX := PPM * 3.5
const PATH_SCAN_HORIZON_PX := PPM * 85.0
const PALETTE := [
	Color("7b8b9b"),Color("b5b6aa"),Color("a08f7a"),Color("617a77"),
	Color("a77c6b"),Color("8b94a4"),Color("c9c1ad"),Color("515d67")
]

@export_range(0,30,1) var maximum_vehicles := 16
@export var enabled := true
var world: Node2D
var player: VehicleController2D
var network
var agents: Array[Dictionary] = []
var random := RandomNumberGenerator.new()
var active_junctions: Dictionary = {}
var _id_serial := 0
var _spawn_clock := 0.0
var _simulation_clock := 0.0
var show_routes := false
# Street races do not despawn, freeze or ghost regular cars. Prefer some
# ambient spawns ahead on the active route while all traffic uses the same
# collision, intersections and directional lane rules as free roam.
var street_race_active := false
var street_race_navigation: RefCounted
var street_race_edges: Array[int] = []
var _pre_race_enabled := true
const RACE_TRAFFIC_CAP := 20


func set_street_race_route(route: RefCounted, directed_edges: Array[int],
		active: bool) -> void:
	if active:
		if not street_race_active:
			_pre_race_enabled = enabled
		street_race_active = true
		street_race_navigation = route
		street_race_edges = directed_edges.duplicate()
		# The developer's F5 free-roam toggle cannot silently empty a race.
		enabled = true
	else:
		street_race_active = false
		street_race_navigation = null
		street_race_edges.clear()
		if not _pre_race_enabled:
			enabled = false
			clear_traffic()



func _ready() -> void:
	name = "AmbientTraffic"
	random.seed = 260822
	network = Network.new()
	if world != null:
		network.build(world.data)
	z_index = 1
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _unhandled_input(event: InputEvent) -> void:
	# F6 previews actual routed paths rather than unrelated guessed lines.
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode==KEY_F5:
			if street_race_active:
				# No disabling active traffic during a world street event.
				get_viewport().set_input_as_handled()
				return
			enabled=not enabled
			if not enabled:
				clear_traffic()
			get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and key.keycode==KEY_F6:
			show_routes=not show_routes
			queue_redraw()
			get_viewport().set_input_as_handled()


func clear_traffic() -> void:
	for agent in agents:
		var node: Node2D=agent.node
		if is_instance_valid(node):node.queue_free()
	agents.clear()
	active_junctions.clear()


func _spawn_one() -> bool:
	if not is_instance_valid(player) or network.edges.is_empty():
		return false
	var ids: Array[int] = network.nearby_edges(player.global_position,400.0)
	if ids.is_empty():
		return false
	var preferred: Array[int] = []
	if street_race_active:
		for id in street_race_edges:
			if ids.has(id):
				var candidate: Dictionary = network.edges[id]
				if not bool(candidate.connector) and float(candidate.length_px) >= PPM * 35.0:
					preferred.append(id)
	var player_station := -1.0
	if street_race_active and street_race_navigation != null:
		player_station = float(street_race_navigation.call(
			"station_at", player.global_position / PPM))
	for attempt in 42:
		var on_race_route := not preferred.is_empty() and random.randf() < 0.82
		var candidates: Array[int] = preferred if on_race_route else ids
		var id: int = candidates[random.randi_range(0,candidates.size()-1)]
		var edge: Dictionary = network.edges[id]
		if bool(edge.connector) or float(edge.length_px)<PPM*35.0:
			continue
		var progress := random.randf_range(PPM*7.0,maxf(PPM*8.0,float(edge.length_px)-PPM*8.0))
		var sample: Dictionary=network.point_on_edge(id,progress)
		var p: Vector2=sample.position
		var away := p.distance_to(player.global_position)
		if away<PPM*75.0 or away>PPM*390.0:
			continue
		# Pair off-screen recycling with off-screen spawning: a newly
		# recycled traffic car must not pop into another player's camera.
		if _visible_to_any_player(p):
			continue
		if str(world.surface_at(p).name) != "ASPHALT":
			continue
		if on_race_route and player_station >= 0.0:
			var spawn_station := float(street_race_navigation.call("station_at", p / PPM))
			if spawn_station < player_station + 60.0 or spawn_station > player_station + 370.0:
				continue
		var free := true
		for other in agents:
			if p.distance_to(other.node.global_position)<PPM*35.0:
				free=false
				break
		if not free:
			continue
		var car := CharacterBody2D.new()
		car.set_script(Car)
		car.name = "TrafficCar%02d" % _id_serial
		car.set("model_index", _id_serial % Car.MODEL_PATHS.size())
		car.car_color = PALETTE[_id_serial%PALETTE.size()]
		car.accent_color=Color("d2c4a7")
		car.global_position=p
		car.rotation=float(sample.angle)
		add_child(car)
		var speed := float(edge.speed_px)*random.randf_range(0.72,0.93)
		agents.append({
			"uid":_id_serial,"node":car,"edge":id,
			"progress":progress,"speed":speed*0.65,"cruise":speed,
			"next":-2,"stop_wait":0.0,"stop_done":false,
			"recovery_time":0.0,"recovery_refresh":0.0,"recovery_goal":{},
			"obstacle_scan_clock":0.0,"obstacle_position":Vector2.INF,
			"recovery_stall":0.0,
			"stuck_time":0.0,"stuck_clock":0.0,"stuck_anchor":p,
			"path_scan_clock":0.0,"path_speed_cap":INF
		})
		_id_serial+=1
		return true
	return false


## Pick a continuous, legal *connected* lane rather than the first
## straight choice. Favor long through-edges without hard steer jumps, reject
## turn splines that put a real car outside paved roadway, and keep a small
## deterministic variation so ambient traffic explores different streets.
func _choose_next(edge: Dictionary) -> int:
	var choices: Array = edge.next
	if choices.is_empty():
		return -1
	var best_id := -1
	var best_score := -INF
	var current_points: PackedVector2Array = edge.points
	var incoming := Vector2.UP
	if current_points.size() >= 2:
		incoming = (current_points[-1] - current_points[-2]).normalized()
	for raw_id in choices:
		var id := int(raw_id)
		if id < 0 or id >= network.edges.size():
			continue
		var candidate: Dictionary = network.edges[id]
		var points: PackedVector2Array = candidate.points
		if points.size() < 2:
			continue
		var next_heading := (points[1] - points[0]).normalized()
		# Disallow severe immediate direction reversals unless the legal
		# network offers no other connection (e.g., a cul-de-sac).
		var alignment := incoming.dot(next_heading)
		var score := alignment * 3.0
		match str(candidate.get("turn", "straight")):
			"straight":
				score += 3.0
			"right":
				score += 1.0
			"left":
				score += 0.45
		if candidate.get("next", []).is_empty():
			score -= 3.2
		if not bool(candidate.connector):
			score += minf(float(candidate.length_px) / (PPM * 90.0), 1.0)
		# Graph splines are navigation hints; prefer an actually paved turn.
		if is_instance_valid(world):
			var paved := true
			for fraction in [0.20, 0.50, 0.80]:
				var sample: Dictionary = network.point_on_edge(
					id, float(candidate.length_px) * float(fraction))
				if str(world.surface_at(sample.position).get("name", "")) != "ASPHALT":
					paved = false
					break
			if not paved:
				score -= 25.0
		if alignment < -0.5:
			score -= 7.0
		score += random.randf_range(0.0, 2.6)
		if score > best_score:
			best_score = score
			best_id = id
	return best_id


## Treat a turn as a sequence of connected lane samples. A vehicle on
## the far side of a bend may be invisible to a straight-ahead bumper check.
## Sense the swept route at realistic braking distances and classify actors
## using actual body positions and velocities instead of stale route progress.
func _route_point(agent: Dictionary, distance_px: float) -> Dictionary:
	var id := int(agent.edge)
	if id < 0 or id >= network.edges.size():
		return {}
	var edge: Dictionary = network.edges[id]
	var progress := float(agent.progress) + distance_px
	if progress > float(edge.length_px):
		var next_id := int(agent.get("next", -2))
		if next_id < 0 or next_id >= network.edges.size():
			return {}
		progress -= float(edge.length_px)
		id = next_id
		edge = network.edges[id]
		if progress > float(edge.length_px):
			return {}
	return network.point_on_edge(id, progress)


func _path_aware_speed(agent: Dictionary, desired_px: float) -> float:
	if network == null or desired_px < PPM * 0.7:
		return desired_px
	# The next 3-5-metre road samples don't change significantly within a
	# tenth of a second. Cache only the extra obstruction cap, so changing
	# stop signs and right-of-way controls still take effect immediately.
	if float(agent.get("path_scan_clock", 0.0)) > 0.0:
		return minf(desired_px, float(agent.get("path_speed_cap", INF)))
	agent.path_scan_clock = 0.10
	agent.path_speed_cap = INF
	var node: CharacterBody2D = agent.node
	if not is_instance_valid(node):
		return desired_px
	var horizon := clampf(desired_px * 2.8, PPM * 15.0, PATH_SCAN_HORIZON_PX)
	var candidates: Array[Dictionary] = []
	for other in agents:
		if int(other.uid) == int(agent.uid):
			continue
		var other_node: CharacterBody2D = other.node
		if not is_instance_valid(other_node):
			continue
		if node.global_position.distance_to(other_node.global_position) > horizon + PPM * 15.0:
			continue
		var velocity: Vector2 = Vector2.UP.rotated(other_node.rotation) * float(other.speed)
		velocity += other_node.get("recovery_velocity") as Vector2
		candidates.append({"node": other_node, "velocity": velocity,
			"width_px": float(other_node.get("width_px"))})
	# Player-controlled cars and independent racing rivals are also dynamic
	# blockers; no ambient car may blindly drive through a street race.
	for person in _player_vehicles():
		if node.global_position.distance_to(person.global_position) <= horizon + PPM * 15.0:
			candidates.append({"node": person,
				"velocity": person.linear_velocity * PPM, "width_px": PPM * 2.2})
	var racing_nodes: Array[Node] = []
	if get_tree() != null:
		racing_nodes = get_tree().get_nodes_in_group("race_opponent")
	for other_racer in racing_nodes:
		if other_racer is VehicleController2D:
			var racer := other_racer as VehicleController2D
			if node.global_position.distance_to(racer.global_position) <= horizon + PPM * 15.0:
				candidates.append({"node": racer,
					"velocity": racer.linear_velocity * PPM, "width_px": PPM * 2.2})
	if candidates.is_empty():
		return desired_px
	var best := desired_px
	var car_width := float(node.get("width_px"))
	for other in candidates:
		var other_node: Node2D = other.node
		var closest_path := INF
		var closest_ahead := INF
		var tangent := Vector2.ZERO
		# Find the earliest lane overlap, not simply the nearest distance.
		var d := PPM * 2.0
		while d < horizon:
			var at: Dictionary = _route_point(agent, d)
			if at.is_empty():
				break
			var direction: Vector2 = at.tangent
			var lateral := absf((other_node.global_position -
				Vector2(at.position)).cross(direction))
			if lateral < (car_width + float(other.width_px)) * 0.5 + PPM * 0.50 and \
					lateral < closest_path:
				closest_path = lateral
				closest_ahead = d
				tangent = direction
			d += PATH_SCAN_STEP_PX
		if not is_finite(closest_ahead):
			continue
		var relative_velocity: Vector2 = other.velocity
		var forward_speed := relative_velocity.dot(tangent)
		var approach_speed := maxf(0.0, desired_px - forward_speed)
		var gap_px := PPM * 5.0 + approach_speed * 0.40
		# The road may bend out of the current car's field of view:
		# cap the speed using real distance along that road before contact.
		var available_px := maxf(0.0, closest_ahead - gap_px)
		var target_speed := maxf(0.0, forward_speed)
		var safe := target_speed + sqrt(2.0 * COMFORT_BRAKE * available_px)
		best = minf(best, safe)
	agent.path_speed_cap = best if best < desired_px else INF
	return best


func _player_vehicles() -> Array[VehicleController2D]:
	var people: Array[VehicleController2D] = []
	if is_instance_valid(player):
		people.append(player)
	# Recovery harnesses and editor previews may drive a TrafficFlow that
	# has not entered the active SceneTree. The assigned player is still
	# authoritative in those cases.
	if get_tree() == null:
		return people
	for candidate in get_tree().get_nodes_in_group("player_vehicle"):
		if candidate is VehicleController2D and not people.has(candidate):
			people.append(candidate as VehicleController2D)
	return people


## Actual cameras define what a player can see. Being far from the main
## player is NOT enough: a zoomed-out view or a second player's camera can
## still show a stranded vehicle. Never remove any car in a live view.
func _visible_to_any_player(position_px: Vector2) -> bool:
	for person in _player_vehicles():
		if person.global_position.distance_to(position_px) <= VIEWER_PROXIMITY_PX:
			return true
	var seen_cameras := {}
	var camera_list: Array[Camera2D] = []
	var local_camera := get_viewport().get_camera_2d()
	if is_instance_valid(local_camera):
		camera_list.append(local_camera)
	for camera_node in get_tree().get_nodes_in_group("player_camera"):
		if camera_node is Camera2D and not camera_list.has(camera_node):
			camera_list.append(camera_node as Camera2D)
	for camera in camera_list:
		if not is_instance_valid(camera) or not camera.is_current():
			continue
		var viewport: Viewport = camera.get_viewport()
		if viewport == null or seen_cameras.has(viewport.get_instance_id()):
			continue
		seen_cameras[viewport.get_instance_id()] = true
		# Bound the camera's *world-space* footprint instead of relying on
		# a canvas transform that may still be one frame behind physics or
		# interpolation when a player moves or teleports the view. A bounding
		# circle intentionally protects a little outside rotated view corners.
		var zoom_x := maxf(absf(camera.zoom.x), 0.01)
		var zoom_y := maxf(absf(camera.zoom.y), 0.01)
		var size_px := viewport.get_visible_rect().size
		var radius_px := Vector2(size_px.x / zoom_x, size_px.y / zoom_y).length() * 0.5
		radius_px += VIEW_MARGIN_PX / minf(zoom_x, zoom_y) + camera.offset.length()
		if camera.global_position.distance_to(position_px) <= radius_px:
			return true
	return false


func _stalled_offscreen(agent: Dictionary, dt: float) -> bool:
	var node: CharacterBody2D = agent.node
	if not is_instance_valid(node):
		return true
	var clock := float(agent.get("stuck_clock", 0.0)) + dt
	if clock < STUCK_WINDOW_SECONDS:
		agent.stuck_clock = clock
		return false
	var anchor: Vector2 = agent.get("stuck_anchor", node.global_position)
	if node.global_position.distance_to(anchor) >= STUCK_DISTANCE_PX:
		agent.stuck_time = 0.0
	else:
		agent.stuck_time = float(agent.get("stuck_time", 0.0)) + clock
	agent.stuck_anchor = node.global_position
	agent.stuck_clock = 0.0
	var recovery := bool(node.get("recovering"))
	var threshold := STUCK_RECOVERY_SECONDS if recovery else STUCK_REMOVE_SECONDS
	if float(agent.stuck_time) < threshold:
		return false
	if _visible_to_any_player(node.global_position):
		# Keep the car visible and give it another chance to recover; do not
		# repeatedly run full-visibility tests every frame for a stopped queue.
		return false
	return true


# Kinematic safety envelope shared by players, moving AI and stopped AI.
# It uses the current body centers, so stale waypoint progress after a crash
# cannot make the car drive into another vehicle.
func _safe_follow_speed(agent: Dictionary, desired_px: float,
		obstacle_position: Vector2, obstacle_velocity: Vector2,
		direction: Vector2 = Vector2.ZERO) -> float:
	if desired_px <= 0.0:
		return desired_px
	var node: CharacterBody2D = agent.node
	var heading := direction.normalized() if direction.length_squared() > 0.001 \
		else Vector2.UP.rotated(node.rotation)
	var offset := obstacle_position - node.global_position
	var ahead := offset.dot(heading)
	var lateral := absf(heading.cross(offset))
	# The half-widths of both cars plus a small clearance. Adjacent lanes do
	# not count as obstacles unless their collision paths really intersect.
	if ahead < -PPM * 0.5 or lateral > PPM * 2.85:
		return desired_px
	var lead_speed := maxf(0.0, obstacle_velocity.dot(heading))
	var closing_speed := maxf(0.0, desired_px - lead_speed)
	var minimum_gap := PPM * 5.4 + closing_speed * 0.48
	var available := maxf(0.0, ahead - minimum_gap)
	return minf(desired_px, lead_speed + sqrt(2.0 * COMFORT_BRAKE * available))


# Predict an intersection crossing before either vehicle occupies the same
# collision footprint. Controlled right-of-way prevents AI/AI deadlocks.
func _crossing_speed(agent: Dictionary, desired_px: float,
		other_position: Vector2, other_velocity: Vector2,
		must_yield: bool, direction: Vector2 = Vector2.ZERO) -> float:
	if not must_yield or desired_px <= 0.0:
		return desired_px
	var node: CharacterBody2D = agent.node
	var heading := direction.normalized() if direction.length_squared() > 0.001 \
		else Vector2.UP.rotated(node.rotation)
	var offset := other_position - node.global_position
	if offset.length_squared() > pow(PPM * 45.0, 2.0):
		return desired_px
	var velocity_delta := other_velocity - heading * maxf(float(agent.speed), desired_px)
	if velocity_delta.length_squared() < 10.0:
		return desired_px
	var closest_time := -offset.dot(velocity_delta) / velocity_delta.length_squared()
	if closest_time < 0.10 or closest_time > LOOKAHEAD_SECONDS:
		return desired_px
	var closest_offset := offset + velocity_delta * closest_time
	if closest_offset.length() > PPM * 4.7:
		return desired_px
	# Avoid applying a cross-lane prediction to a car already safely ahead.
	if offset.dot(heading) < -PPM * 2.0:
		return desired_px
	var remaining := offset.length() - PPM * 5.5
	return minf(desired_px, maxf(0.0, remaining) / LOOKAHEAD_SECONDS)


# Only cars on the same junction's incoming roads or inside its connector
# compete for crossing priority. A queued car at another intersection must
# not indefinitely hold up the current one.
func _junction_for(agent: Dictionary) -> int:
	if network == null or not network.edges is Array or \
		int(agent.edge) < 0 or int(agent.edge) >= network.edges.size():
		return -1
	var edge: Dictionary = network.edges[int(agent.edge)]
	if bool(edge.connector):
		return int(edge.start_j)
	var next_id := int(agent.get("next", -2))
	if next_id < 0 or next_id >= network.edges.size():
		return -1
	var upcoming: Dictionary = network.edges[next_id]
	return int(upcoming.start_j) if bool(upcoming.connector) else -1


func _car_following(index: int, desired_px: float) -> float:
	var agent: Dictionary = agents[index]
	var heading := Vector2.UP.rotated((agent.node as Node2D).rotation)
	var my_junction := _junction_for(agent)
	for i in agents.size():
		if i == index:
			continue
		var other: Dictionary = agents[i]
		var other_node: CharacterBody2D = other.node
		if not is_instance_valid(other_node):
			continue
		var other_direction := Vector2.UP.rotated(other_node.rotation)
		var other_speed := float(other.speed) if not bool(other_node.get("recovering")) else 0.0
		var other_velocity := other_direction * other_speed + (other_node.get("recovery_velocity") as Vector2)
		var distance := (other_node.global_position - (agent.node as Node2D).global_position).length()
		# Cars traveling together form a moving queue. At crossing angles
		# only respect a *nearby physical blocker*; do not wait for an
		# unrelated stopped car with its nose pointed across this lane.
		if heading.dot(other_direction) > 0.62 or distance < PPM * 6.2:
			desired_px = _safe_follow_speed(agent, desired_px,
				other_node.global_position, other_velocity, heading)
		var other_junction := _junction_for(other)
		if my_junction >= 0 and my_junction == other_junction:
			var other_inside := bool(network.edges[int(other.edge)].connector)
			var must_yield := other_inside or int(agent.uid) > int(other.uid)
			desired_px = _crossing_speed(agent, desired_px,
				other_node.global_position, other_velocity, must_yield, heading)
	return desired_px


## Yield to every human-controlled car, not merely the primary player.
## Crossing prediction uses real velocity and applies to racing participants.
func _player_awareness(agent: Dictionary, desired_px: float,
		travel_direction: Vector2 = Vector2.ZERO) -> float:
	var heading := travel_direction if travel_direction.length_squared() > 0.001 \
		else Vector2.UP.rotated((agent.node as Node2D).rotation)
	var safe := desired_px
	for person in _player_vehicles():
		var player_velocity: Vector2 = person.linear_velocity * PPM
		safe = _safe_follow_speed(agent, safe,
			person.global_position, player_velocity, heading)
		safe = _crossing_speed(agent, safe, person.global_position,
			player_velocity, true, heading)
	return safe


# Only static obstacles are sensed here; traffic and player awareness are
# handled above. Cache raycasts to avoid querying physics every frame.
func _world_obstacle_speed(agent: Dictionary, desired_px: float, dt: float) -> float:
	var node: CharacterBody2D = agent.node
	agent.obstacle_scan_clock = float(agent.get("obstacle_scan_clock", 0.0)) - dt
	if float(agent.obstacle_scan_clock) <= 0.0:
		agent.obstacle_scan_clock = 0.12
		agent.obstacle_position = Vector2.INF
		var edge_id := int(agent.edge)
		if network == null or edge_id < 0 or edge_id >= network.edges.size():
			return desired_px
		var edge: Dictionary = network.edges[edge_id]
		var progress := float(agent.progress)
		var lookahead := clampf(desired_px * desired_px / (2.0 * COMFORT_BRAKE) +
			PPM * 6.0, PPM * 8.0, PPM * 28.0)
		var checked := 0.0
		var start: Vector2 = node.global_position
		# Follow the actual lane and connector spline in 3-metre pieces.
		# Straight rays into intersection corners are not lane blockers.
		while checked < lookahead:
			var advance := minf(PPM * 3.0, lookahead - checked)
			checked += advance
			progress += advance
			if progress >= float(edge.length_px):
				var next_id := int(agent.get("next", -2))
				if next_id < 0 or next_id >= network.edges.size():
					break
				progress -= float(edge.length_px)
				edge_id = next_id
				edge = network.edges[edge_id]
			var finish: Vector2 = network.point_on_edge(edge_id, progress).position
			var query := PhysicsRayQueryParameters2D.create(start, finish, 1,
				[node.get_rid()])
			var hit := node.get_world_2d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				var collider: Object = hit.collider
				var dynamic_obstacle := false
				if collider is Node:
					dynamic_obstacle = collider.is_in_group("traffic_vehicle") or \
						collider is VehicleController2D
				if not dynamic_obstacle:
					agent.obstacle_position = hit.position
					break
			start = finish
	var target: Vector2 = agent.get("obstacle_position", Vector2.INF)
	if not target.is_finite():
		return desired_px
	# Stop at a static obstacle on the lane; the stored route-distance is
	# more useful than a straight-line curb distance on a tight turn.
	var ahead := (target - node.global_position).length()
	return minf(desired_px, sqrt(2.0 * COMFORT_BRAKE * maxf(0.0, ahead - PPM * 3.5)))


func _next_target(agent: Dictionary,edge: Dictionary) -> int:
	if int(agent.next)==-2:
		agent.next=_choose_next(edge)
	return int(agent.next)


func _tick_agent(index: int,dt: float) -> bool:
	var agent: Dictionary=agents[index]
	var edge: Dictionary=network.edges[int(agent.edge)]
	var node: CharacterBody2D=agent.node
	if not is_instance_valid(node):
		return false
	if node.global_position.distance_to(player.global_position) > PPM * 530.0 and \
			not _visible_to_any_player(node.global_position):
		return false
	if bool(node.get("recovering")):
		return _recover_agent(agent,dt)
	var previous_progress := float(agent.progress)
	var remaining := float(edge.length_px)-float(agent.progress)
	var desired := minf(float(edge.speed_px),float(agent.cruise))
	var next_id := -2
	# Determine upcoming connector before computing right-of-way and sensing.
	# Waiting cars can otherwise appear to have no destination at all.
	if remaining < maxf(PPM * 75.0, float(agent.speed) * 2.5):
		next_id=_next_target(agent,edge)
	agent.path_scan_clock = float(agent.get("path_scan_clock", 0.0)) - dt
	desired=_car_following(index,desired)
	desired=_player_awareness(agent,desired)
	desired=_path_aware_speed(agent,desired)
	desired=_world_obstacle_speed(agent,desired,dt)
	if next_id>=0:
		var next: Dictionary=network.edges[next_id]
		if bool(next.connector):
			desired=minf(desired,maxf(float(next.speed_px),remaining*0.8))
			var junction := int(next.start_j)
			var owner := int(active_junctions.get(junction,-1))
			var control := str(next.control)
			var should_yield := junction>=0 and owner>=0 and owner!=int(agent.uid)
			if control=="stop" and not bool(agent.stop_done) and remaining<PPM*8.0:
				desired=minf(desired,maxf(0.0,(remaining-PPM*1.3)*0.5))
				if float(agent.speed)<PPM*0.9 and remaining<PPM*2.5:
					agent.stop_wait=float(agent.stop_wait)+dt
					if float(agent.stop_wait)>=0.85:
						agent.stop_done=true
			if control=="yield" and remaining<PPM*13.0:
				desired=minf(desired,PPM*4.0)
			if should_yield and remaining<PPM*7.0:
				desired=0.0
			if control=="stop" and not bool(agent.stop_done) and remaining<PPM*2.4:
				desired=0.0

	var previous := float(agent.speed)
	# Brake decisively when the player is immediately ahead, including
	# when we have only just switched from a crash back to lane following.
	var rate := PPM*5.5 if desired>previous else (HARD_BRAKE if desired<PPM*0.2 else COMFORT_BRAKE)
	agent.speed=move_toward(previous,desired,rate*dt)
	agent.progress=float(agent.progress)+float(agent.speed)*dt
	if float(agent.progress)>=float(edge.length_px):
		var chosen := _next_target(agent,edge)
		if chosen<0:
			return false
		if bool(edge.connector):
			var old_j := int(edge.end_j)
			if int(active_junctions.get(old_j,-1))==int(agent.uid):
				active_junctions.erase(old_j)
		var next_edge: Dictionary=network.edges[chosen]
		if bool(next_edge.connector) and int(next_edge.start_j)>=0:
			active_junctions[int(next_edge.start_j)]=int(agent.uid)
		var excess := float(agent.progress)-float(edge.length_px)
		agent.edge=chosen
		agent.progress=minf(excess,float(next_edge.length_px)*0.7)
		agent.next=-2
		agent.stop_wait=0.0
		agent.stop_done=false
	var sample: Dictionary=network.point_on_edge(int(agent.edge),float(agent.progress))
	# Move through the physics server, not by teleporting a sprite. A
	# collision marks the agent for local lane rejoining next tick.
	var motion: Vector2 = sample.position - node.global_position
	var collision: Variant = node.call("move_traffic", motion, dt)
	# Follow the spline's *smoothed* tangent with a rate-limited yaw.
	# Do not snap heading at each polyline vertex in a corner.
	var angle_delta := angle_difference(node.rotation, float(sample.angle))
	var eased := angle_delta * (1.0 - exp(-TURN_RESPONSE * dt))
	node.rotation += clampf(eased, -MAX_TURN_RATE * dt, MAX_TURN_RATE * dt)
	if collision != null or bool(node.get("recovering")):
		agent.progress=previous_progress
		agent.speed=minf(float(agent.speed),PPM*3.0)
		agent.recovery_time=0.0
		agent.recovery_refresh=0.0
		agent.recovery_goal={}
	return true



func _recover_agent(agent: Dictionary, dt: float) -> bool:
	# The vehicle stays where the collision left it, including on grass or a
	# shoulder. Reproject onto a FORWARD legal lane only, and drive toward a
	# point ahead of the projection. Never reset to the original waypoint.
	var node: CharacterBody2D = agent.node
	var age: float = float(agent.get("recovery_time",0.0)) + dt
	agent.recovery_time=age
	# Release previous junction claims when a crash blocks the intersection.
	if age <= dt + 0.0001:
		for key in active_junctions.keys():
			if int(active_junctions[key]) == int(agent.uid):
				active_junctions.erase(key)
	agent.recovery_refresh=float(agent.get("recovery_refresh",0.0))-dt
	if float(agent.recovery_refresh) <= 0.0:
		var forward := Vector2.UP.rotated(node.rotation)
		var goal: Dictionary = network.recovery_target(node.global_position,
			forward,int(agent.edge))
		agent.recovery_goal=goal
		agent.recovery_refresh=0.24
	var target: Dictionary = agent.recovery_goal
	if target.is_empty():
		agent.speed=0.0
		node.call("move_traffic", Vector2.ZERO, dt)
		# Recovery failures are handled by the shared physical-stall tracker.
		# Only a car that is genuinely stationary AND outside every player's
		# camera may be recycled, so nothing disappears in front of anyone.
		return true
	var intended: Vector2 = target.lookahead
	var delta: Vector2 = intended - node.global_position
	var desired_angle := delta.angle() + PI * 0.5
	# Gentle low-speed steering makes a recovery visible rather than an
	# impossible sideways slide. Knockback fades in move_traffic().
	node.rotation=lerp_angle(node.rotation,desired_angle,minf(1.0,dt*2.65))
	var direction := Vector2.UP.rotated(node.rotation)
	var goal_speed := clampf(delta.length() * 0.75,PPM*1.0,PPM*6.0)
	# Recovery does not get to ignore stopped vehicles or intersection traffic.
	for other_agent in agents:
		if int(other_agent.uid) == int(agent.uid):
			continue
		var other_node: CharacterBody2D = other_agent.node
		if is_instance_valid(other_node):
			var other_velocity := Vector2.UP.rotated(other_node.rotation) * float(other_agent.speed)
			goal_speed = _safe_follow_speed(agent, goal_speed,
				other_node.global_position, other_velocity, direction)
	# Recovery must also yield. It previously drove blindly toward its lane
	# and repeatedly pushed a player who was already in front of the car.
	goal_speed = _player_awareness(agent, goal_speed, direction)
	var blocked_by_player := goal_speed <= 0.01
	var speed := 0.0 if blocked_by_player else move_toward(
		float(agent.speed), goal_speed, PPM*5.5*dt)
	if blocked_by_player:
		# Remove residual crash momentum aimed at the player while waiting.
		var toward_player := (player.global_position - node.global_position).normalized()
		var recoil: Vector2 = node.get("recovery_velocity") as Vector2
		if recoil.dot(toward_player) > 0.0:
			node.set("recovery_velocity", recoil.slide(toward_player))
	agent.speed=speed
	var hit: Variant = node.call("move_traffic", direction*speed*dt,dt)
	if hit != null:
		agent.speed=0.0
		# Steer gently away from the contact surface while continuing to
		# search the legal lane. No snapping or obstacle tunneling.
		var escape_heading: Vector2 = (direction + (hit as KinematicCollision2D).get_normal() * 0.9).normalized()
		node.rotation = lerp_angle(node.rotation, escape_heading.angle() + PI * 0.5,
			minf(1.0, dt * 2.2))
		agent.recovery_refresh = 0.0
	# Once aligned with a real sampled lane, switch back to the existing
	# lane-following and intersection decision logic. The nearest station is
	# computed afresh so the NPC never warps back to its pre-crash progress.
	if node.global_position.distance_to(target.nearest) < PPM*1.25 and \
		direction.dot(Vector2(target.heading)) > 0.77 and \
		(node.get("recovery_velocity") as Vector2).length() < PPM*1.2:
		var found: Dictionary = network.recovery_target(node.global_position,
			direction,int(target.edge),PPM*6.0)
		if not found.is_empty() and float(found.distance_px) < PPM*1.4:
			agent.edge=int(found.edge)
			agent.progress=float(found.progress)
			agent.next=-2
			agent.stop_wait=0.0
			agent.stop_done=false
			agent.recovery_time=0.0
			agent.recovery_refresh=0.0
			agent.recovery_goal={}
			node.set("recovering",false)
	return true

func _prune_junction_claims() -> void:
	for junction in active_junctions.keys():
		var owner_id := int(active_junctions[junction])
		var found := false
		for agent in agents:
			if int(agent.uid) != owner_id:
				continue
			var node: CharacterBody2D = agent.node
			if not is_instance_valid(node) or bool(node.get("recovering")):
				break
			var edge_id := int(agent.edge)
			if edge_id >= 0 and edge_id < network.edges.size():
				var edge: Dictionary = network.edges[edge_id]
				found = bool(edge.connector) and int(edge.start_j) == int(junction)
			break
		if not found:
			active_junctions.erase(junction)


func _physics_process(dt: float) -> void:
	if not enabled or not is_instance_valid(player) or network==null:
		return
	var step := minf(dt,0.05)
	_simulation_clock+=step
	_prune_junction_claims()
	for i in range(agents.size()-1,-1,-1):
		var alive := _tick_agent(i,step)
		if alive:
			alive = not _stalled_offscreen(agents[i],step)
		if not alive:
			var node: Node2D=agents[i].node
			if is_instance_valid(node):node.queue_free()
			var agent_id := int(agents[i].uid)
			for j in active_junctions.keys():
				if int(active_junctions[j])==agent_id:active_junctions.erase(j)
			agents.remove_at(i)
	_spawn_clock+=step
	var limit := maxi(maximum_vehicles, RACE_TRAFFIC_CAP) if street_race_active else maximum_vehicles
	if _spawn_clock>0.6 and agents.size()<limit:
		_spawn_clock=0.0
		_spawn_one()
	if show_routes and int(_simulation_clock*3.0)!=int((_simulation_clock-step)*3.0):
		queue_redraw()


func _draw() -> void:
	if not show_routes or not is_instance_valid(player) or network==null:
		return
	var mid := player.global_position
	var painted := 0
	for edge in network.edges:
		if painted>140:
			break
		var path: PackedVector2Array=edge.points
		if path.is_empty() or path[0].distance_to(mid)>PPM*350.0:
			continue
		draw_polyline(path,Color(0.96,0.67,0.30,0.52) if bool(edge.connector)
			else Color(0.17,0.94,0.91,0.40),2.0,true)
		painted+=1
