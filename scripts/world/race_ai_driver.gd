extends Node
## Reusable waypoint driver for sanctioned races. It ONLY writes normalized
## commands; VehicleController2D supplies all acceleration, torque, gear shifts,
## grip, braking, drag, collision and surface physics. No distance-based boosts.
const PPM := 20.0
var car: VehicleController2D
var route := PackedVector2Array()
var stations := PackedFloat64Array()
var active := false
var reaction_seconds := 0.55
var reaction_remaining := 0.0
var throttle_limit := 0.90
var cruise_speed_mps := 180.0
var last_station_px := 0.0


func setup(target: VehicleController2D, waypoints: PackedVector2Array) -> void:
	car = target
	route = waypoints.duplicate()
	stations.clear()
	if route.size() < 2:
		return
	stations.append(0.0)
	for i in range(1, route.size()):
		stations.append(stations[i - 1] + route[i - 1].distance_to(route[i]))
	last_station_px = 0.0
	active = false
	if is_instance_valid(car):
		car.command = Vector4.ZERO


func launch() -> void:
	if route.size() < 2 or not is_instance_valid(car):
		return
	reaction_remaining = reaction_seconds
	active = true


func stop() -> void:
	active = false
	if is_instance_valid(car):
		car.command = Vector4.ZERO


func _point_at(distance_px: float) -> Vector2:
	if route.size() < 2:
		return Vector2.ZERO
	var d := clampf(distance_px, 0.0, stations[stations.size() - 1])
	for i in range(1, stations.size()):
		if d <= stations[i]:
			var span := maxf(0.01, stations[i] - stations[i - 1])
			return route[i - 1].lerp(route[i], (d - stations[i - 1]) / span)
	return route[route.size() - 1]


func _nearest_station(point: Vector2) -> float:
	var closest := INF
	var station := 0.0
	for i in range(1, route.size()):
		var section := route[i] - route[i - 1]
		var fraction := clampf((point - route[i - 1]).dot(section) /
			maxf(section.length_squared(), 0.01), 0.0, 1.0)
		var projected := route[i - 1] + section * fraction
		var error := point.distance_squared_to(projected)
		if error < closest:
			closest = error
			station = stations[i - 1] + section.length() * fraction
	return station


func _corner_speed(station_px: float) -> float:
	# A turn's maximum *requested* speed comes from its radius and the
	# same tire/surface grip used by the physics body. This does not grant grip.
	var a := _point_at(station_px)
	var b := _point_at(station_px + 15.0 * PPM)
	var c := _point_at(station_px + 30.0 * PPM)
	var first := b - a
	var second := c - b
	if first.length() < PPM * 2.0 or second.length() < PPM * 2.0:
		return cruise_speed_mps
	var angle := absf(wrapf(second.angle() - first.angle(), -PI, PI))
	if angle < 0.02:
		return cruise_speed_mps
	var radius_m := (first.length() / PPM) / angle
	var grip := maxf(0.20, car.config.tire_grip * car.surface_grip)
	return minf(cruise_speed_mps, sqrt(grip * 9.81 * radius_m * 0.85))


func _physics_process(dt: float) -> void:
	if not active or not is_instance_valid(car) or route.size() < 2:
		return
	if reaction_remaining > 0.0:
		reaction_remaining -= dt
		car.command = Vector4.ZERO
		return
	var speed := car.linear_velocity.length()
	var position_px := car.global_position
	var station_px := _nearest_station(position_px)
	# Keep checkpoint progress monotonic after a collision or wide corner.
	last_station_px = maxf(last_station_px, station_px)
	var lookahead_m := clampf(12.0 + speed * 0.65, 12.0, 65.0)
	var target := _point_at(station_px + lookahead_m * PPM)
	var bearing := target - position_px
	if bearing.length_squared() < 1.0:
		car.command = Vector4.ZERO
		return
	var forward := Vector2.UP.rotated(car.rotation)
	var heading_error := wrapf(bearing.angle() - forward.angle(), -PI, PI)
	var steer := clampf(heading_error * 2.8, -1.0, 1.0)
	var desired_speed := _corner_speed(station_px + 4.0 * PPM)
	# Braking distance is handled by requesting lower speed *before* bends;
	# the vehicle still must physically slow using its configured brakes.
	var near_corner_speed := _corner_speed(station_px + maxf(10.0, speed * 1.2) * PPM)
	desired_speed = minf(desired_speed, sqrt(near_corner_speed * near_corner_speed +
		2.0 * car.config.tire_grip * car.surface_grip * 9.81 * maxf(10.0, speed * 1.2)))
	var throttle_request := throttle_limit * clampf((desired_speed - speed) / 4.0, 0.0, 1.0)
	var brake_request := clampf((speed - desired_speed) / 7.0, 0.0, 1.0)
	# Never override the car's position, velocity, RPM, power or physics stats.
	car.command = Vector4(throttle_request, brake_request, steer, 0.0)
