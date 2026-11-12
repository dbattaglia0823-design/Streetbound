extends RefCounted
## Shared geometry for authored parking-lot entrances. Baked lot placement,
## collisions and the road graph remain unchanged: the nearest existing road
## determines only the visible curb break and its drivable asphalt connector.
const PPM := 20.0
const MAX_CONNECTION_M := 26.0


static func v(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))


static func _road_local(prop: Dictionary, road_position_px: Vector2) -> Vector2:
	return (road_position_px / PPM - v(prop.p)).rotated(-float(prop.angle))


## Side 0=-X, 1=+X, 2=-Y, 3=+Y. Choose the nearest actual side of the
## rotated rectangle, rather than assuming every lot has an entrance on -X.
static func access_for(prop: Dictionary, road_position_px: Vector2) -> Dictionary:
	var half := v(prop.size) * 0.5
	var target := _road_local(prop, road_position_px)
	var edges := [
		[Vector2(-half.x, -half.y), Vector2(-half.x, half.y)],
		[Vector2(half.x, -half.y), Vector2(half.x, half.y)],
		[Vector2(-half.x, -half.y), Vector2(half.x, -half.y)],
		[Vector2(-half.x, half.y), Vector2(half.x, half.y)]
	]
	var best := INF
	var chosen := -1
	for i in edges.size():
		var closest := Geometry2D.get_closest_point_to_segment(
			target, edges[i][0], edges[i][1])
		var distance := target.distance_to(closest)
		if distance < best:
			best = distance
			chosen = i
	if chosen < 0:
		return {}
	var entry := Vector2.ZERO
	var outward := Vector2.ZERO
	match chosen:
		0:
			entry = Vector2(-half.x, clampf(target.y, -half.y * .55, half.y * .55))
			outward = Vector2.LEFT
		1:
			entry = Vector2(half.x, clampf(target.y, -half.y * .55, half.y * .55))
			outward = Vector2.RIGHT
		2:
			entry = Vector2(clampf(target.x, -half.x * .55, half.x * .55), -half.y)
			outward = Vector2.UP
		3:
			entry = Vector2(clampf(target.x, -half.x * .55, half.x * .55), half.y)
			outward = Vector2.DOWN
	var gap := entry.distance_to(target)
	if gap > MAX_CONNECTION_M or gap < .01:
		return {}
	return {"side": chosen, "entry": [entry.x, entry.y],
		"road": [target.x, target.y], "gap_m": gap,
		"outward": [outward.x, outward.y]}


static func width_m(prop: Dictionary) -> float:
	return clampf(float(prop.get("entrance_width", 8.0)), 5.5, 10.0)


## Four corners of the painted driveway (local metres). Both asphalt paint
## and traction use exactly this polygon.
static func polygon(prop: Dictionary) -> PackedVector2Array:
	var access: Dictionary = prop.get("road_access", {})
	if access.is_empty():
		return PackedVector2Array()
	var entry := v(access.entry)
	var target := v(access.road)
	var outward := v(access.outward)
	var tangent := outward.orthogonal()
	var half := width_m(prop) * .5
	var inside := entry - outward * 2.0
	return PackedVector2Array([
		inside - tangent * half,
		inside + tangent * half,
		target + tangent * half,
		target - tangent * half
	])


static func contains_pavement(prop: Dictionary, local_metres: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(local_metres, polygon(prop))


static func paints_access(prop: Dictionary) -> bool:
	return not polygon(prop).is_empty()
