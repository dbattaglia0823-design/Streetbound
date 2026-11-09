extends RefCounted
## Stable paired offsets around bends. Urban sidewalks, their kerbs, and the
## seaward boardwalk rail all use the same continuous centreline geometry.
const SIDEWALK_WIDTH_PX := 66.0

static func offset(path: PackedVector2Array, distance_px: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	if path.size() < 2:
		return result
	for i in path.size():
		var before := (path[i] - path[maxi(i - 1, 0)]).normalized()
		var after := (path[mini(i + 1, path.size() - 1)] - path[i]).normalized()
		if i == 0:
			before = after
		elif i == path.size() - 1:
			after = before
		if before.length_squared() < 0.5:
			before = after
		if after.length_squared() < 0.5:
			after = before
		var n_before := before.orthogonal()
		var n_after := after.orthogonal()
		var normal := (n_before + n_after).normalized()
		if normal.length_squared() < 0.5:
			normal = n_after
		var projection := normal.dot(n_after)
		# A bounded miter joins bends cleanly without giant spikes at tight turns.
		var factor := minf(1.85, 1.0 / maxf(projection, 0.54))
		result.append(path[i] + normal * distance_px * factor)
	return result


static func urban_sidewalk_center(path: PackedVector2Array, road_width_px: float, side: float) -> PackedVector2Array:
	return offset(path, side * (road_width_px * 0.5 + SIDEWALK_WIDTH_PX * 0.5 - 1.0))


static func urban_sidewalk_outer(path: PackedVector2Array, road_width_px: float, side: float) -> PackedVector2Array:
	return offset(path, side * (road_width_px * 0.5 + SIDEWALK_WIDTH_PX - 1.0))
