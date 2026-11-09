extends RefCounted
## Build directional driving lanes and explicit junction links FROM the SAME
## baked Morrow Coast roads/intersection approaches used by world rendering.
## Coordinates and stationing are in metres; display uses 20 px per metre.
## Right-hand driving, no U-turns, no dirt/gravel -> paved auto connections.
const SAMPLE_METRES := 9.0
const CELL_METRES := 128.0


static func _v(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))


static func _path(raw: Array, forward: bool) -> PackedVector2Array:
	var path := PackedVector2Array()
	var original := PackedVector2Array()
	for p in raw:
		original.append(_v(p))
	if forward:
		for p in original:
			if path.is_empty() or path[-1].distance_to(p) >= SAMPLE_METRES:
				path.append(p)
		if path.is_empty() or path[-1].distance_to(original[-1]) > 0.1:
			path.append(original[-1])
	else:
		for i in range(original.size() - 1, -1, -1):
			var p: Vector2 = original[i]
			if path.is_empty() or path[-1].distance_to(p) >= SAMPLE_METRES:
				path.append(p)
		if path.is_empty() or path[-1].distance_to(original[0]) > 0.1:
			path.append(original[0])
	return path


static func _offset_lane(path: PackedVector2Array, offset_m: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in path.size():
		var before := path[maxi(0, i - 1)]
		var after := path[mini(path.size() - 1, i + 1)]
		var heading := (after - before).normalized()
		result.append(path[i] + heading.orthogonal() * offset_m)
	return result


static func _cumulative(points: PackedVector2Array) -> PackedFloat32Array:
	var stations := PackedFloat32Array()
	var cursor := 0.0
	for i in points.size():
		if i > 0:
			cursor += points[i].distance_to(points[i - 1])
		stations.append(cursor)
	return stations


static func _index_near(points: PackedVector2Array, p: Vector2) -> int:
	var best := INF
	var index := 0
	for i in points.size():
		var score := p.distance_squared_to(points[i])
		if score < best:
			best = score
			index = i
	return index


static func _key(road: int, direction: int, lane: int) -> String:
	return "%d:%d:%d" % [road, direction, lane]


static func _loose(road: Dictionary) -> bool:
	return str(road.surface) in ["DIRT", "GRAVEL"] or str(road.kind) == "gravel"


static func _speed(road: Dictionary) -> float:
	match str(road.kind):
		"highway": return 23.0
		"arterial": return 15.5
		"local": return 11.5
		"mountain": return 10.5
		"rural": return 16.0
		"gravel": return 7.5
	return 9.0


static func build(data: Dictionary) -> Dictionary:
	var routes: Array[Dictionary] = []
	var routes_by_key := {}
	var lookup := {}
	var cells := {}
	for road in data.roads:
		if road.kind in ["track", "driveway"]:
			continue
		if road.points.size() < 2:
			continue
		var lane_count := maxi(1, int(road.lanes) / 2)
		for direction in [1, -1]:
			var raw_path := _path(road.points, direction == 1)
			for lane in lane_count:
				var offset := minf(float(road.width) * 0.42, 1.75 + float(lane) * 3.1)
				var points := _offset_lane(raw_path, offset)
				var stations := _cumulative(points)
				var id := routes.size()
				var key := _key(int(road.id), direction, lane)
				routes.append({"id": id, "key": key, "road": int(road.id),
					"direction": direction, "lane": lane,
					"points": points, "stations": stations,
					"speed": _speed(road), "loose": _loose(road),
					"links": []})
				routes_by_key[key] = id
				lookup[id] = {"road": int(road.id), "direction": direction}
				# A bounded spatial index for near-player traffic spawning.
				for i in range(0, points.size(), 3):
					var p: Vector2 = points[i]
					var key_cell := Vector2i((p / CELL_METRES).floor())
					if not cells.has(key_cell):
						cells[key_cell] = []
					cells[key_cell].append(Vector2i(id, i))
	var link_count := 0
	for junction_id in data.junctions.size():
		var j: Dictionary = data.junctions[junction_id]
		var arms: Array = j.approaches
		for from_arm in arms:
			var from_road: Dictionary = data.roads[int(from_arm.road)]
			var from_direction := -int(from_arm.side)
			var from_key := _key(int(from_arm.road), from_direction, 0)
			if not routes_by_key.has(from_key):
				continue
			var from_index: int = routes_by_key[from_key]
			var source: Dictionary = routes[from_index]
			var source_path: PackedVector2Array = source.points
			var source_station_index := _index_near(source_path, _v(from_arm.p))
			if source_station_index < 1 or source_station_index >= source_path.size() - 2:
				continue
			for to_arm in arms:
				# No U-turn on the same approach and no auto-joins across
				# the paved/loose road boundary.
				if from_arm == to_arm:
					continue
				var to_road: Dictionary = data.roads[int(to_arm.road)]
				if _loose(from_road) != _loose(to_road):
					continue
				var to_direction := int(to_arm.side)
				var to_key := _key(int(to_arm.road), to_direction, 0)
				if not routes_by_key.has(to_key):
					continue
				var target_index: int = routes_by_key[to_key]
				if target_index == from_index:
					continue
				var target: Dictionary = routes[target_index]
				var target_path: PackedVector2Array = target.points
				var destination_index := _index_near(target_path, _v(to_arm.p))
				if destination_index >= target_path.size() - 2:
					continue
				var heading_in := (source_path[source_station_index] -
					source_path[source_station_index - 1]).normalized()
				var heading_out := (target_path[destination_index + 1] -
					target_path[destination_index]).normalized()
				var dot := heading_in.dot(heading_out)
				if dot < -0.35:
					continue
				var cross := heading_in.cross(heading_out)
				var turn := "straight"
				if cross > 0.27:
					turn = "right"
				elif cross < -0.27:
					turn = "left"
				var link := {"junction": junction_id,
					"at": source_station_index, "to": target_index,
					"target": destination_index, "center": _v(j.p),
					"control": str(from_arm.control), "turn": turn}
				(source.links as Array).append(link)
				link_count += 1
	for i in routes.size():
		var links: Array = routes[i].links
		links.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.at) < int(b.at))
	return {"routes": routes, "by_key": routes_by_key,
		"cells": cells, "link_count": link_count}


static func point_at(route: Dictionary, distance_m: float) -> Vector2:
	var stations: PackedFloat32Array = route.stations
	var points: PackedVector2Array = route.points
	if stations.is_empty():
		return Vector2.ZERO
	if distance_m <= 0.0:
		return points[0]
	if distance_m >= stations[-1]:
		return points[-1]
	var lo := 0
	var hi := stations.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if stations[mid] < distance_m:
			lo = mid
		else:
			hi = mid
	var span := maxf(stations[hi] - stations[lo], 0.001)
	return points[lo].lerp(points[hi], (distance_m - stations[lo]) / span)


static func next_links(route: Dictionary, station: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var stops: PackedFloat32Array = route.stations
	var next_station := INF
	for link in route.links:
		var index := int(link.at)
		if index >= stops.size():
			continue
		var at: float = stops[index]
		if at < station + 0.2:
			continue
		if at < next_station - 0.75:
			next_station = at
			result.clear()
		if absf(at - next_station) < 0.75:
			result.append(link)
	return result
