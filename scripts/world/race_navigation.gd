extends RefCounted
## Shared, metre-space race navigation and conservative physics-based braking
## envelope. The racing line never changes vehicle physics or applies brakes.
const SAMPLE_M := 6.0
const MAX_GUIDE_SPEED_MPS := 95.0
var points_m := PackedVector2Array()
var stations_m := PackedFloat64Array()
var curve_speed_mps := PackedFloat64Array()
var target_speed_mps := PackedFloat64Array()
var closed := false
var length_m := 0.0
var _last_grip := -1.0
var _last_brake := -1.0
var _decel_mps2 := 4.0


func setup(raw: PackedVector2Array, loop := false) -> void:
	points_m.clear()
	stations_m.clear()
	curve_speed_mps.clear()
	target_speed_mps.clear()
	closed = loop
	length_m = 0.0
	_last_grip = -1.0
	_last_brake = -1.0
	if raw.size() < 2:
		return
	var clean := PackedVector2Array([raw[0]])
	for i in range(1, raw.size()):
		if raw[i].distance_to(clean[clean.size() - 1]) > 0.1:
			clean.append(raw[i])
	if clean.size() < 2:
		return
	if closed and clean[0].distance_to(clean[clean.size() - 1]) > 0.1:
		clean.append(clean[0])
	points_m.append(clean[0])
	stations_m.append(0.0)
	for i in range(1, clean.size()):
		var from: Vector2 = clean[i - 1]
		var to: Vector2 = clean[i]
		var steps := maxi(1, ceili(from.distance_to(to) / SAMPLE_M))
		for step in range(1, steps + 1):
			var p := from.lerp(to, float(step) / float(steps))
			length_m += p.distance_to(points_m[points_m.size() - 1])
			points_m.append(p)
			stations_m.append(length_m)


func _index_point(index: int) -> Vector2:
	var n := points_m.size()
	if n < 2:
		return Vector2.ZERO
	if closed:
		return points_m[posmod(index, n - 1)]
	return points_m[clampi(index, 0, n - 1)]


func update_envelope(vehicle: VehicleController2D) -> void:
	if not is_instance_valid(vehicle) or points_m.size() < 2:
		return
	var grip := maxf(0.12, vehicle.config.tire_grip * vehicle.surface_grip)
	var service := maxf(0.2, vehicle.config.brake_force_n / maxf(vehicle.config.mass_kg, 1.0))
	var decel := maxf(0.8, minf(service, grip * 9.81) * 0.76)
	if absf(grip - _last_grip) < 0.01 and absf(decel - _last_brake) < 0.05:
		return
	_last_grip = grip
	_last_brake = decel
	_decel_mps2 = decel
	curve_speed_mps.clear()
	target_speed_mps.clear()
	for i in points_m.size():
		var p0 := _index_point(i - 3)
		var p1 := _index_point(i)
		var p2 := _index_point(i + 3)
		var left := p1 - p0
		var right := p2 - p1
		var cross := absf(left.cross(right))
		var allowed := MAX_GUIDE_SPEED_MPS
		if left.length() > 0.5 and right.length() > 0.5 and cross > 0.01:
			var radius := left.length() * right.length() * p2.distance_to(p0) / (2.0 * cross)
			allowed = minf(MAX_GUIDE_SPEED_MPS, sqrt(grip * 9.81 * maxf(radius, 1.0) * 0.78))
		curve_speed_mps.append(allowed)
		target_speed_mps.append(allowed)
	# Back-propagate realistic stopping distance through every corner. A
	# second pass around closed routes carries last-corner braking to start.
	for pass_index in range(2 if closed else 1):
		for i in range(points_m.size() - 2, -1, -1):
			var distance := maxf(0.0, stations_m[i + 1] - stations_m[i])
			var reachable := sqrt(target_speed_mps[i + 1] * target_speed_mps[i + 1] +
				2.0 * _decel_mps2 * distance)
			target_speed_mps[i] = minf(curve_speed_mps[i], reachable)
		if closed and points_m.size() > 2:
			target_speed_mps[points_m.size() - 1] = target_speed_mps[0]


func station_at(position_m: Vector2) -> float:
	if points_m.size() < 2:
		return 0.0
	var best := INF
	var closest := 0.0
	for i in range(1, points_m.size()):
		var segment := points_m[i] - points_m[i - 1]
		var t := clampf((position_m - points_m[i - 1]).dot(segment) /
			maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
		var projected := points_m[i - 1] + segment * t
		var distance := position_m.distance_squared_to(projected)
		if distance < best:
			best = distance
			closest = lerpf(stations_m[i - 1], stations_m[i], t)
	return closest


func point_at(station: float) -> Vector2:
	if points_m.is_empty():
		return Vector2.ZERO
	if points_m.size() == 1:
		return points_m[0]
	var s := fposmod(station, length_m) if closed and length_m > 0.0 else clampf(station, 0.0, length_m)
	var lo := 0
	var hi := stations_m.size() - 1
	while hi - lo > 1:
		var mid := (hi + lo) / 2
		if stations_m[mid] <= s:
			lo = mid
		else:
			hi = mid
	var gap := maxf(stations_m[hi] - stations_m[lo], 0.0001)
	return points_m[lo].lerp(points_m[hi], (s - stations_m[lo]) / gap)


func allowed_speed_at(station: float) -> float:
	if target_speed_mps.is_empty():
		return MAX_GUIDE_SPEED_MPS
	var s := fposmod(station, length_m) if closed and length_m > 0.0 else clampf(station, 0.0, length_m)
	var lo := 0
	var hi := stations_m.size() - 1
	while hi - lo > 1:
		var mid := (hi + lo) / 2
		if stations_m[mid] <= s:
			lo = mid
		else:
			hi = mid
	var gap := maxf(stations_m[hi] - stations_m[lo], 0.0001)
	return lerpf(target_speed_mps[lo], target_speed_mps[hi], (s - stations_m[lo]) / gap)


func braking_state(station: float, speed_mps: float) -> int:
	# 0 = safe, 1 = lift/prepare, 2 = brake. Remains red until actual car
	# speed falls within the conservative corner approach envelope.
	var allowed := allowed_speed_at(station)
	if speed_mps > allowed + 1.0:
		return 2
	if speed_mps > allowed - 1.8:
		return 1
	return 0


func suggested_braking_distance(speed_mps: float, target_speed: float) -> float:
	# Approximate physical stopping distance, plus human reaction margin.
	var kinetic := maxf(0.0, speed_mps * speed_mps - target_speed * target_speed)
	return kinetic / (2.0 * _decel_mps2) + speed_mps * 0.28
