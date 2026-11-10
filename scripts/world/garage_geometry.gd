extends RefCounted
## Shared Laurel Motor House garage geometry. The saved Morrow Coast building
## remains authoritative; only its center bay is cut out of the solid roof.
const POI_NAME := "Laurel Motor House"
const PPM := 20.0
const BAY_WIDTH_M := 13.0
const BACK_WALL_M := 3.0
const GARAGE_STOP_SPEED_MPS := 1.6


static func is_player_garage(prop: Dictionary) -> bool:
	return str(prop.get("kind", "")) == "garage" and \
		str(prop.get("poi", "")) == POI_NAME


static func size_of(prop: Dictionary) -> Vector2:
	return Vector2(float(prop.size[0]), float(prop.size[1]))


static func position_of(prop: Dictionary) -> Vector2:
	return Vector2(float(prop.p[0]), float(prop.p[1]))


static func local_point(prop: Dictionary, point_m: Vector2) -> Vector2:
	return (point_m - position_of(prop)).rotated(-float(prop.angle))


static func bay_rect(size_m: Vector2) -> Rect2:
	var half_width := minf(BAY_WIDTH_M * 0.5, size_m.y * 0.4)
	return Rect2(Vector2(-size_m.x * 0.5, -half_width),
		Vector2(size_m.x - BACK_WALL_M, half_width * 2.0))


static func parking_rect(size_m: Vector2) -> Rect2:
	# Park the entire car *inside* the opening, well away from the masonry
	# edges and the solid rear wall. Includes longer trucks/SUVs.
	var bay := bay_rect(size_m)
	return Rect2(Vector2(bay.position.x + 4.5, -4.7),
		Vector2(maxf(3.0, bay.size.x - 8.0), 9.4))


static func wall_rects(size_m: Vector2) -> Array[Rect2]:
	var door_width := minf(BAY_WIDTH_M, size_m.y * 0.8)
	var wall_width := (size_m.y - door_width) * 0.5
	return [
		Rect2(-size_m * 0.5, Vector2(size_m.x, wall_width)),
		Rect2(Vector2(-size_m.x * 0.5, door_width * 0.5),
			Vector2(size_m.x, wall_width)),
		Rect2(Vector2(size_m.x * 0.5 - BACK_WALL_M, -door_width * 0.5),
			Vector2(BACK_WALL_M, door_width))
	]


static func inside_bay(prop: Dictionary, point_px: Vector2) -> bool:
	return bay_rect(size_of(prop)).has_point(
		local_point(prop, point_px / PPM))


static func is_parked(prop: Dictionary, point_px: Vector2, speed_mps: float) -> bool:
	return absf(speed_mps) <= GARAGE_STOP_SPEED_MPS and \
		parking_rect(size_of(prop)).has_point(
			local_point(prop, point_px / PPM))
