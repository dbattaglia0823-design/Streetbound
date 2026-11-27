extends RefCounted
## Signed layers are spaced six metres apart. Ramps interpolate by road station.
const HEIGHT_M := 6.0
const MAX_LAYER := 2


static func endpoint_layer(road: Dictionary, first: bool) -> int:
	var profile: Dictionary = road.get("elevation", {})
	return int(profile.get("start_layer" if first else "end_layer", 0))


static func authoring_error(road: Dictionary) -> String:
	if not road.has("elevation"):
		return ""
	var raw: Variant = road.elevation
	if not raw is Dictionary or raw.size() != 2:
		return "Road elevation needs start and end layers."
	for key in ["start_layer", "end_layer"]:
		var value: Variant = raw.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) \
				or absf(float(value)) > MAX_LAYER or float(value) != floorf(float(value)):
			return "Road layers must be integers from -2 to 2."
	var delta := absi(endpoint_layer(road, true) - endpoint_layer(road, false))
	if delta > 1:
		return "A ramp can connect only adjacent layers."
	var points: Array = road.points
	var length_m := 0.0
	for i in range(1, points.size()):
		length_m += Vector2(points[i-1].x,points[i-1].y).distance_to(Vector2(points[i].x,points[i].y))
	if delta > 0:
		if Vector2(points[0].x,points[0].y).distance_to(Vector2(points[-1].x,points[-1].y)) < .12:
			return "An elevation ramp must have distinct endpoints."
		if length_m < 50.0:
			return "A ramp needs at least 50 m per layer."
	elif length_m < 4.0 and endpoint_layer(road, true) != 0:
		return "An elevated road needs at least 4 m of pavement."
	return ""


static func height_at(road: Dictionary, fraction: float) -> float:
	var profile: Dictionary = road.get("elevation", {})
	return HEIGHT_M * lerpf(float(profile.get("start_layer", 0)),
		float(profile.get("end_layer", 0)), clampf(fraction, 0.0, 1.0))


## Preserve existing semantics for obstacle, player, and police target
## bits, reserving a private copy of those three bits per non-ground level.
static func collision_bits(ground_bits: int, height_m: float) -> int:
	var layer := layer_for_height(height_m)
	var result := ground_bits << _collision_shift(layer)
	# Share contact across the band boundary so cars on the same grade ramp
	# do not ghost through each other when one crosses the midpoint first.
	var adjacent := layer + signi(roundi((height_m-layer*HEIGHT_M)*10.0))
	if adjacent != layer and absi(adjacent) <= MAX_LAYER \
			and absf(height_m-layer*HEIGHT_M) >= HEIGHT_M*.5-.4:
		result |= ground_bits << _collision_shift(adjacent)
	return result


static func _collision_shift(layer: int) -> int:
	return 0 if layer == 0 else (layer + MAX_LAYER + (1 if layer < 0 else 0))*3


static func artwork_layer(road: Dictionary) -> int:
	var first := endpoint_layer(road,true)
	var last := endpoint_layer(road,false)
	return first if absi(first) >= absi(last) else last


static func layer_for_height(height_m: float) -> int:
	return clampi(roundi(height_m / HEIGHT_M), -MAX_LAYER, MAX_LAYER)


static func edge_height_at(edge: Dictionary, progress_px: float) -> float:
	return lerpf(float(edge.get("start_height_m",0)),float(edge.get("end_height_m",0)),
		clampf(progress_px / maxf(float(edge.length_px),1.0),0.0,1.0))
