extends RefCounted
## Authoritative, non-rendering boundaries for map authoring / simulation tools.
## Coordinates in a chunk feature are LOCAL PIXELS; queries use WORLD PIXELS.
## In normal gameplay no boundary meshes or collision objects are created.
const Walkways = preload("res://scripts/world/urban_walkways.gd")
const PPM := 20.0
const DECK_WIDTH_PX := 112.0


static func _feature(out: Array[Dictionary], kind: String, points: PackedVector2Array,
		closed := false, source_id := -1, side := 0) -> void:
	if points.size() < 2:
		return
	out.append({"kind": kind, "points": points, "closed": closed,
		"source_id": source_id, "side": side})


static func _raw_path(chunk: Node2D, raw: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in raw:
		points.append(chunk.point(p))
	return points


static func _prop_outline(chunk: Node2D, prop: Dictionary) -> PackedVector2Array:
	var center: Vector2 = chunk.point(prop.p)
	var angle := float(prop.angle)
	if prop.kind in ["tree", "pine", "palm", "island", "rock"]:
		var radius := maxf(1.0, float(prop.radius)) * PPM
		var circle := PackedVector2Array()
		for i in 16:
			circle.append(center + Vector2.from_angle(float(i) * TAU / 16.0) * radius)
		return circle
	var size := Vector2(float(prop.size[0]), float(prop.size[1])) * PPM * 0.5
	var corners := PackedVector2Array()
	for p in [Vector2(-size.x, -size.y), Vector2(size.x, -size.y),
			Vector2(size.x, size.y), Vector2(-size.x, size.y)]:
		corners.append(center + p.rotated(angle))
	return corners


static func boardwalk_pieces(chunk: Node2D, world: Node2D) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if world.boardwalk_path.size() < 2:
		return result
	# The same expanded per-chunk clip rectangle as coast_boardwalk.gd.
	var rect := Rect2(chunk.origin_m - Vector2.ONE * 8.0,
		Vector2.ONE * (world.chunk_m + 16.0))
	var polygon := PackedVector2Array([rect.position,
		Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)])
	for portion in Geometry2D.intersect_polyline_with_polygon(world.boardwalk_path, polygon):
		if portion.size() < 2:
			continue
		var local := PackedVector2Array()
		for p in portion:
			local.append((p - chunk.origin_m) * PPM)
		result.append(local)
	return result


static func chunk_features(chunk: Node2D, world: Node2D) -> Array[Dictionary]:
	# Only invoked by a developer preview or an explicit map-building request.
	# The road drawing stays the single source for path, width and offsets.
	var out: Array[Dictionary] = []
	for batch in chunk.road_batches:
		var path: PackedVector2Array = batch.path
		var road: Dictionary = batch.road
		var width := float(road.width) * PPM
		var id := int(road.id)
		_feature(out, "road_center", path, false, id)
		for side in [-1, 1]:
			var amount := float(side) * width * 0.5
			_feature(out, "road_edge", Walkways.offset(path, amount), false, id, side)
			if road.kind in ["local", "arterial"]:
				# Concrete centerline is exactly the one used by road artwork.
				_feature(out, "sidewalk_center",
					Walkways.urban_sidewalk_center(path, width, float(side)),
					false, id, side)
				_feature(out, "sidewalk_outer",
					Walkways.urban_sidewalk_outer(path, width, float(side)),
					false, id, side)
	for junction in chunk.junction_list:
		var id: int = world.data.junctions.find(junction)
		_feature(out, "junction", _raw_path(chunk, junction.polygon), true, id)
		for fillet in junction.curbs:
			_feature(out, "corner_curb", _raw_path(chunk, fillet), false, id)
	for deck in boardwalk_pieces(chunk, world):
		_feature(out, "boardwalk_center", deck)
		for side in [-1, 1]:
			_feature(out, "boardwalk_edge", Walkways.offset(deck,
				float(side) * DECK_WIDTH_PX * 0.5), false, -1, side)
	for polygon in chunk.ground_polys:
		_feature(out, "terrain_" + str(polygon.kind), polygon.points, true)
	for prop in chunk.prop_list:
		if bool(prop.solid):
			_feature(out, "obstacle", _prop_outline(chunk, prop), true)
		elif prop.kind in ["lot", "forecourt", "field"]:
			_feature(out, "parcel", _prop_outline(chunk, prop), true)
	for index in chunk.content.get("walls", []):
		var wall: Array = world.data.walls[int(index)]
		_feature(out, "wall", PackedVector2Array([chunk.point(wall[0]), chunk.point(wall[1])]))
	return out


static func nearest_road(world: Node2D, position_px: Vector2,
		search_radius_m := 12.0) -> Dictionary:
	# Uses the SAME 64m spatial index as actual surface physics.
	var p := position_px / PPM
	var radius := clampf(search_radius_m, 0.0, 256.0)
	var cell_size := float(world.data.surface_cell)
	var begin := Vector2i(((p - Vector2.ONE * radius) / cell_size).floor())
	var finish := Vector2i(((p + Vector2.ONE * radius) / cell_size).floor())
	var inspected := {}
	var best_sq := radius * radius
	var best: Dictionary = {}
	for x in range(begin.x, finish.x + 1):
		for y in range(begin.y, finish.y + 1):
			var key := "%d,%d" % [x, y]
			for item in world.data.surface_index.get(key, []):
				var index := int(item)
				if inspected.has(index):
					continue
				inspected[index] = true
				var segment: Dictionary = world.data.segments[index]
				var a := Vector2(float(segment.a[0]), float(segment.a[1]))
				var b := Vector2(float(segment.b[0]), float(segment.b[1]))
				var closest := Geometry2D.get_closest_point_to_segment(p, a, b)
				var distance_sq := p.distance_squared_to(closest)
				if distance_sq > best_sq:
					continue
				var tangent := (b-a).normalized()
				if tangent.length_squared() < 0.5:
					continue
				var road: Dictionary = world.data.roads[int(segment.road)]
				best_sq = distance_sq
				best = {"found": true, "road_id": int(segment.road),
					"road_name": str(road.name), "road_kind": str(road.kind),
					"road_surface": str(road.surface), "road_width_m": float(road.width),
					"closest_point_px": closest * PPM,
					"tangent": tangent, "normal": tangent.orthogonal(),
					"lateral_offset_m": (p-closest).dot(tangent.orthogonal()),
					"distance_to_center_m": sqrt(distance_sq),
					"distance_to_road_edge_m": sqrt(distance_sq) - float(road.width) * 0.5}
	return best


static func _near_path_m(path: PackedVector2Array, p: Vector2) -> float:
	var closest := INF
	for i in range(1, path.size()):
		closest = minf(closest, p.distance_to(
			Geometry2D.get_closest_point_to_segment(p, path[i-1], path[i])))
	return closest


static func inspect(world: Node2D, position_px: Vector2) -> Dictionary:
	# Opt-in metadata, not used in hot-path physics; still honors the physical
	# surface query so dev tools cannot invent different traction values.
	var surface: Dictionary = world.surface_at(position_px)
	var p := position_px / PPM
	var region := "terrain"
	var detail := ""
	var road := nearest_road(world, position_px, 12.0)
	if not road.is_empty():
		var distance := float(road.distance_to_center_m)
		var half := float(road.road_width_m) * 0.5
		if distance <= half:
			region = "road"
		elif road.road_kind in ["local", "arterial"] and distance <= half + 3.3:
			region = "sidewalk"
	for j in world._junction_grid.get("%d,%d" % [
			floori(p.x / float(world.data.surface_cell)),
			floori(p.y / float(world.data.surface_cell))], []):
		if Geometry2D.is_point_in_polygon(p, world._junction_polygons[int(j)]):
			region = "intersection"
			detail = "Junction %d" % int(j)
			break
	if region == "terrain":
		if world.boardwalk_path.size() >= 2 and _near_path_m(world.boardwalk_path, p) <= DECK_WIDTH_PX / PPM * 0.5:
			region = "boardwalk"
		else:
			for terrain in world.data.terrain:
				if terrain.kind not in ["water", "ocean", "beach", "farmland", "forest", "city", "town", "mountain", "highland"]:
					continue
				var polygon := PackedVector2Array()
				for raw in terrain.points:
					polygon.append(Vector2(float(raw[0]), float(raw[1])))
				if Geometry2D.is_point_in_polygon(p, polygon):
					region = str(terrain.kind)
	var result := {"region": region, "surface": str(surface.name),
		"grip": float(surface.grip), "position_m": p, "detail": detail}
	for key in road:
		result[key] = road[key]
	return result


static func placement_check(world: Node2D, position_px: Vector2,
		radius_m := 2.0, margin_m := 1.0) -> Dictionary:
	# A future map placement tool can query this before adding objects.
	# No physics collider or rendering is registered by this method.
	var p := position_px / PPM
	var pad := maxf(0.0, radius_m) + maxf(0.0, margin_m)
	var road := nearest_road(world, position_px, pad + 24.0)
	if not road.is_empty():
		var reserved := float(road.road_width_m) * 0.5 + pad
		if road.road_kind in ["local", "arterial"]:
			reserved += Walkways.SIDEWALK_WIDTH_PX / PPM
		if float(road.distance_to_center_m) <= reserved:
			return {"clear": false, "reason": "road_or_sidewalk", "road_id": int(road.road_id)}
	if world.boardwalk_path.size() >= 2 and _near_path_m(world.boardwalk_path, p) <= DECK_WIDTH_PX / PPM * 0.5 + pad:
		return {"clear": false, "reason": "boardwalk"}
	for polygon in world._junction_polygons:
		if Geometry2D.is_point_in_polygon(p, polygon):
			return {"clear": false, "reason": "junction"}
		for i in polygon.size():
			var gap := p.distance_to(Geometry2D.get_closest_point_to_segment(
				p, polygon[i], polygon[(i+1)%polygon.size()]))
			if gap < pad:
				return {"clear": false, "reason": "junction"}
	for prop in world.data.props:
		if not bool(prop.solid):
			continue
		var center := Vector2(float(prop.p[0]), float(prop.p[1]))
		var radius := maxf(float(prop.radius),
			Vector2(float(prop.size[0]),float(prop.size[1])).length() * 0.5)
		if center.distance_to(p) < radius + pad:
			return {"clear": false, "reason": "obstacle", "kind": str(prop.kind)}
	for terrain in world.data.terrain:
		if terrain.kind not in ["ocean", "water"]:
			continue
		var polygon := PackedVector2Array()
		for raw in terrain.points:
			polygon.append(Vector2(float(raw[0]), float(raw[1])))
		if Geometry2D.is_point_in_polygon(p, polygon):
			return {"clear": false, "reason": str(terrain.kind)}
	return {"clear": true, "reason": ""}
