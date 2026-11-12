extends RefCounted
## Tactical traffic passing for a *physics-controlled* racing car.
## Reads nearby ambient agents and the player's true position/velocity, then
## selects a paved waypoint corridor. Never writes position, velocity or grip.
const PPM := 20.0
const HALF_BODY_M := 1.2
const EDGE_MARGIN_M := 0.30
const PASS_OFFSETS := [-4.5, 4.5, -5.5, 5.5, -3.5, 3.5]
const SCAN_INTERVAL := 0.12
var car: VehicleController2D
var world: Node2D
var traffic: Node
var navigation: RefCounted
var _clock := 0.0
var _chosen_offset := 0.0
var _pass_id := -1
var _last_plan := {"offset_m": 0.0, "speed_cap_mps": INF, "mode": "clear"}
var scan_count := 0
var passed_count := 0


func setup(vehicle: VehicleController2D, surface: Node2D,
		flow: Node, course: RefCounted) -> void:
	car = vehicle
	world = surface
	traffic = flow
	navigation = course
	_clock = 0.0
	_chosen_offset = 0.0
	_pass_id = -1
	scan_count = 0
	passed_count = 0
	_last_plan = {"offset_m": 0.0, "speed_cap_mps": INF, "mode": "clear"}


func _course_point(station_m: float) -> Vector2:
	return navigation.call("point_at", station_m) as Vector2


func _course_direction(station_m: float) -> Vector2:
	var a := _course_point(maxf(0.0, station_m - 2.5))
	var b := _course_point(minf(float(navigation.get("length_m")), station_m + 2.5))
	return (b - a).normalized()


func _road_safe(station_m: float, offset_m: float) -> bool:
	if not is_instance_valid(world):
		return false
	var direction := _course_direction(station_m)
	if direction.length_squared() < 0.5:
		return false
	var side := direction.orthogonal()
	var center := _course_point(station_m) + side * offset_m
	for spread in [-HALF_BODY_M - EDGE_MARGIN_M, 0.0,
			HALF_BODY_M + EDGE_MARGIN_M]:
		var sample: Dictionary = world.surface_at((center + side * spread) * PPM)
		if str(sample.get("name", "")) != "ASPHALT":
			return false
	return true


func _corridor_safe(station_m: float, current_offset: float,
		candidate_offset: float, speed_mps: float) -> bool:
	var course_end: float = navigation.get("length_m")
	# Avoid starting an overtake approaching the finish or a hard corner.
	if station_m + 80.0 >= course_end:
		return false
	var tangent := _course_direction(station_m + 18.0)
	if tangent.dot(_course_direction(station_m + 55.0)) < 0.91:
		return false
	var shift_m := clampf(speed_mps * 1.85, 35.0, 75.0)
	for d in [6.0, 16.0, 30.0, 48.0, 70.0, 95.0]:
		var fraction := smoothstep(0.0, shift_m, d)
		var offset := lerpf(current_offset, candidate_offset, fraction)
		if not _road_safe(station_m + d, offset):
			return false
	return true


func _obstacle(position_m: Vector2, velocity_mps: Vector2,
		width_m: float, uid: int, station_m: float,
		horizon_m: float) -> Dictionary:
	if position_m.distance_to(car.global_position / PPM) > horizon_m + 30.0:
		return {}
	var other_station: float = navigation.call("station_at", position_m)
	var ahead := other_station - station_m
	if ahead < -35.0 or ahead > horizon_m:
		return {}
	var center := _course_point(other_station)
	var tangent := _course_direction(other_station)
	if tangent.length_squared() < 0.5:
		return {}
	var lateral := (position_m - center).dot(tangent.orthogonal())
	# Adjacent streets or the far side of a loop do not belong to this lane.
	if absf(lateral) > 12.0:
		return {}
	return {"id":uid, "ahead_m":ahead, "lateral_m":lateral,
		"speed_mps":velocity_mps.dot(tangent), "width_m":width_m}


func _traffic_obstacles(station_m: float, horizon_m: float) -> Array[Dictionary]:
	var detected: Array[Dictionary] = []
	if is_instance_valid(traffic):
		var agents: Array = traffic.get("agents")
		for agent in agents:
			var node: Node2D = agent.get("node")
			if not is_instance_valid(node) or node == car:
				continue
			var traffic_speed := 0.0 if bool(node.get("recovering")) \
				else float(agent.get("speed", 0.0)) / PPM
			var heading := Vector2.UP.rotated(node.global_rotation)
			var width := float(node.get("width_px")) / PPM
			var result := _obstacle(node.global_position / PPM,
				heading * traffic_speed, width, int(agent.get("uid", -1)),
				station_m, horizon_m)
			if not result.is_empty():
				detected.append(result)
	# Other racers (including the human player) use their real tyre-physics
	# velocity; they are not kinematic traffic units.
	if is_instance_valid(car):
		for node in car.get_tree().get_nodes_in_group("race_participant"):
			if node == car or not node is VehicleController2D:
				continue
			var competitor := node as VehicleController2D
			var shape := competitor.get_node_or_null("CollisionShape2D") as CollisionShape2D
			var width := 2.1
			if shape != null and shape.shape is CapsuleShape2D:
				width = 2.0 * (shape.shape as CapsuleShape2D).radius / PPM
			var result := _obstacle(competitor.global_position / PPM,
				competitor.linear_velocity, width, competitor.get_instance_id(),
				station_m, horizon_m)
			if not result.is_empty():
				detected.append(result)
	return detected


func _separation(other: Dictionary) -> float:
	var self_shape := car.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var width := 2.2
	if self_shape != null and self_shape.shape is CapsuleShape2D:
		width = 2.0 * (self_shape.shape as CapsuleShape2D).radius / PPM
	return 0.5 * (width + float(other.width_m)) + 0.75


func _lane_clear(candidate: float, obstacles: Array[Dictionary],
		speed_mps: float, intended_distance_m: float) -> bool:
	for other in obstacles:
		var difference := absf(candidate - float(other.lateral_m))
		if difference >= _separation(other):
			continue
		var ahead := float(other.ahead_m)
		var closing := speed_mps - float(other.speed_mps)
		# Adjacent cars, faster cars approaching from behind, and oncoming
		# vehicles must have enough real time/distance for a complete pass.
		if ahead > -15.0 and ahead < intended_distance_m:
			if ahead <= 9.0:
				return false
			if closing > 0.0 and ahead / maxf(closing, 0.1) < 7.5:
				return false
			if float(other.speed_mps) < -1.0 and ahead < 170.0:
				return false
		if ahead <= 0.0 and ahead > -18.0:
			return false
	return true


func _following_cap(lead: Dictionary, speed_mps: float) -> float:
	var distance := float(lead.ahead_m)
	var lead_speed := maxf(0.0, float(lead.speed_mps))
	var grip := maxf(0.25, car.config.tire_grip * car.surface_grip)
	var service := maxf(0.5, car.config.brake_force_n /
		maxf(car.config.mass_kg, 1.0))
	var decel := minf(service, grip * 9.81) * 0.78
	# Account for reaction/steering time and a real longitudinal safety gap.
	var free := maxf(0.0, distance - 7.5 - speed_mps * 0.32)
	return sqrt(lead_speed * lead_speed + 2.0 * decel * free)


func _physical_offset(station_m: float) -> float:
	var tangent := _course_direction(station_m)
	return (car.global_position / PPM - _course_point(station_m)).dot(
		tangent.orthogonal())


func plan(dt: float, station_m: float, speed_mps: float) -> Dictionary:
	if navigation == null or not is_instance_valid(car) or not is_instance_valid(world):
		return {"offset_m": 0.0, "speed_cap_mps": INF, "mode": "clear"}
	_clock -= dt
	if _clock > 0.0:
		return _last_plan
	_clock = SCAN_INTERVAL
	scan_count += 1
	var horizon := clampf(80.0 + speed_mps * 2.1, 95.0, 190.0)
	var objects := _traffic_obstacles(station_m, horizon)
	var my_offset := _physical_offset(station_m)
	var lead := {}
	var lead_distance := INF
	for obj in objects:
		var ahead := float(obj.ahead_m)
		if ahead < 0.0 or ahead > horizon:
			continue
		if absf(float(obj.lateral_m) - my_offset) >= _separation(obj):
			continue
		if speed_mps - float(obj.speed_mps) <= 1.2:
			continue
		if ahead < lead_distance:
			lead_distance = ahead
			lead = obj
	# Lock a chosen pass until safely past the lead vehicle. A fresh scan
	# every 120ms must not swap left/right and cause high-speed oscillation.
	if _pass_id >= 0:
		var tracked := {}
		for obj in objects:
			if int(obj.id) == _pass_id:
				tracked = obj
				break
		if not tracked.is_empty() and float(tracked.ahead_m) >= -17.0 and \
				_corridor_safe(station_m, my_offset, _chosen_offset, speed_mps) and \
				_lane_clear(_chosen_offset, objects, speed_mps, horizon):
			_last_plan = {"offset_m":_chosen_offset,
				"speed_cap_mps":INF,"mode":"passing"}
			return _last_plan
		if tracked.is_empty() or float(tracked.ahead_m) < -17.0:
			passed_count += 1
		_pass_id = -1
		_chosen_offset = 0.0
	if not lead.is_empty() and float(lead_distance) > 18.0:
		for candidate in PASS_OFFSETS:
			var lane := float(candidate)
			if absf(lane - float(lead.lateral_m)) < _separation(lead):
				continue
			if not _corridor_safe(station_m, my_offset, lane, speed_mps):
				continue
			if not _lane_clear(lane, objects, speed_mps, horizon):
				continue
			_pass_id = int(lead.id)
			_chosen_offset = lane
			_last_plan = {"offset_m":lane,"speed_cap_mps":INF,"mode":"passing"}
			return _last_plan
	# If an overtake cannot be completed safely, use only the minimum
	# physically necessary deceleration; never follow at ambient AI pace
	# when a real passing corridor is available.
	var cap := INF
	if not lead.is_empty():
		cap = _following_cap(lead, speed_mps)
	var returning := 0.0
	if not _lane_clear(0.0, objects, speed_mps, 23.0) and \
			absf(my_offset) > 2.0:
		returning = my_offset
	_last_plan = {"offset_m":returning,"speed_cap_mps":cap,
		"mode":"following" if not lead.is_empty() else "clear"}
	return _last_plan
