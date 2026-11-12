extends RefCounted
## Racing geometry built from the SAME authored routes used by ambient traffic.
## Streets stay in a legal, directed traffic lane; circuits can use the paved
## course width. Only waypoints change: no tire grip, speed or physics boosts.
const PPM := 20.0
const SAMPLE_M := 4.0
const CAR_HALF_WIDTH_M := 1.05
const SHOULDER_MARGIN_M := 0.70
const CITY_MAX_SWING_M := 0.85
const CIRCUIT_MAX_SWING_M := 3.6


static func _nearest_smoothstep(a: float, b: float, x: float) -> float:
	if b <= a:
		return 1.0 if x >= b else 0.0
	return smoothstep(a, b, x)


static func _corner_influence(s: float, first: float, last: float,
		sign_turn: float, amplitude: float) -> float:
	# An outside -> inside apex -> outside trajectory, with long arcs
	# held toward the inside rather than repeatedly swerving on a sweep.
	var span := maxf(0.0, last - first)
	var inner_padding := minf(10.0, span * 0.5)
	var inside_start := first + inner_padding
	var inside_end := last - inner_padding
	var entry := first - 16.0
	var exit := last + 15.0
	var pre := first - 38.0
	var post := last + 38.0
	if s <= pre or s >= post:
		return 0.0
	var value := 0.0
	if s < entry:
		value = lerpf(0.0, -0.65, _nearest_smoothstep(pre, entry, s))
	elif s < inside_start:
		value = lerpf(-0.65, 0.88,
			_nearest_smoothstep(entry, inside_start, s))
	elif s <= inside_end:
		value = 0.88
	elif s < exit:
		value = lerpf(0.88, -0.52,
			_nearest_smoothstep(inside_end, exit, s))
	else:
		value = lerpf(-0.52, 0.0, _nearest_smoothstep(exit, post, s))
	return value * amplitude * sign_turn


static func _driveable(world: Node, point_m: Vector2,
		tangent: Vector2) -> bool:
	if not is_instance_valid(world) or not world.has_method("surface_at"):
		return true
	var normal := tangent.orthogonal().normalized()
	for side in [-CAR_HALF_WIDTH_M, 0.0, CAR_HALF_WIDTH_M]:
		var hit: Dictionary = world.call("surface_at",
			(point_m + normal * side) * PPM)
		if str(hit.get("name", "")) != "ASPHALT":
			return false
	return true


## The bounds parameter is a *legal displacement from lane/course center*
## in metres at each source point. 0 = follow exactly the traffic centerline.
static func make_line(center: PackedVector2Array,
		bounds: PackedFloat32Array, closed := false,
		world: Node = null) -> PackedVector2Array:
	var result := PackedVector2Array()
	if center.size() < 2 or bounds.size() != center.size():
		return result
	var clean := PackedVector2Array([center[0]])
	var widths := PackedFloat32Array([maxf(0.0, bounds[0])])
	for i in range(1, center.size()):
		if clean[clean.size() - 1].distance_to(center[i]) > 0.05:
			clean.append(center[i])
			widths.append(maxf(0.0, bounds[i]))
	if clean.size() < 2:
		return result
	if closed and clean[0].distance_to(clean[clean.size() - 1]) > 0.1:
		clean.append(clean[0])
		widths.append(widths[0])
	var sampled := PackedVector2Array([clean[0]])
	var caps := PackedFloat32Array([widths[0]])
	var stations := PackedFloat64Array([0.0])
	for i in range(1, clean.size()):
		var leg := clean[i].distance_to(clean[i - 1])
		var steps := maxi(1, ceili(leg / SAMPLE_M))
		for j in range(1, steps + 1):
			var t := float(j) / float(steps)
			var next := clean[i - 1].lerp(clean[i], t)
			stations.append(float(stations[stations.size() - 1]) +
				sampled[sampled.size() - 1].distance_to(next))
			sampled.append(next)
			caps.append(lerpf(widths[i - 1], widths[i], t))
	var n := sampled.size()
	var last_station: float = stations[n - 1]
	var turn := PackedFloat32Array()
	turn.resize(n)
	var range_samples := 4
	for i in range(n):
		var pre := maxi(i - range_samples, 0)
		var post := mini(i + range_samples, n - 1)
		if closed:
			pre = posmod(i - range_samples, n - 1)
			post = posmod(i + range_samples, n - 1)
		var inbound := sampled[i] - sampled[pre]
		var outbound := sampled[post] - sampled[i]
		if closed:
			if pre > i:
				inbound = sampled[i] - sampled[pre]
			if post < i:
				outbound = sampled[post] - sampled[i]
		if inbound.length_squared() > 0.1 and outbound.length_squared() > 0.1:
			turn[i] = atan2(inbound.cross(outbound),
				inbound.dot(outbound))
	# Build coherent turn regions, not one lateral zigzag per 4m of road.
	var corners: Array[Dictionary] = []
	var idx := 2
	while idx < n - 2:
		if absf(turn[idx]) < 0.07:
			idx += 1
			continue
		var sign_turn := signf(turn[idx])
		var first := idx
		var last := idx
		var peak := absf(turn[idx])
		var gaps := 0
		var cursor := idx + 1
		while cursor < n - 2:
			if signf(turn[cursor]) == sign_turn and absf(turn[cursor]) >= 0.07:
				last = cursor
				peak = maxf(peak, absf(turn[cursor]))
				gaps = 0
			else:
				gaps += 1
				if gaps >= 4:
					break
			cursor += 1
		if peak >= 0.13:
			corners.append({"first":float(stations[first]),
				"last":float(stations[last]), "sign":sign_turn,
				"strength":clampf(peak / 0.34, 0.35, 1.0)})
		idx = maxi(cursor, idx + 1)
	# The original start/finish stays fixed, preserving grid alignment,
	# staging, lap completion and legal directed network connections.
	for i in range(n):
		var center_point := sampled[i]
		if i == 0 or i == n - 1:
			result.append(center_point)
			continue
		var tangent := (sampled[mini(i + 1, n - 1)] -
			sampled[maxi(i - 1, 0)]).normalized()
		if tangent.length_squared() < 0.01:
			result.append(center_point)
			continue
		var offset := 0.0
		for corner in corners:
			for wrap in range(-1 if closed else 0, 2 if closed else 1):
				offset += _corner_influence(float(stations[i]) +
					float(wrap) * last_station,
					float(corner.first), float(corner.last),
					float(corner.sign), float(corner.strength))
		offset = clampf(offset, -caps[i], caps[i])
		var proposed := center_point + tangent.orthogonal() * offset
		# Shrink only the offending offset when an apex touches grass,
		# a curb, a sidewalk or a world blocker. The source lane is legal.
		var scale := 1.0
		while scale > 0.04 and not _driveable(world,
			center_point + tangent.orthogonal() * offset * scale, tangent):
			scale *= 0.5
		result.append(center_point + tangent.orthogonal() * offset * scale)
	return result


static func circuit_line(center: PackedVector2Array, road_width_m: float,
		world: Node = null) -> PackedVector2Array:
	var half := minf(CIRCUIT_MAX_SWING_M,
		maxf(0.0, road_width_m * 0.5 - CAR_HALF_WIDTH_M - SHOULDER_MARGIN_M))
	var bounds := PackedFloat32Array()
	bounds.resize(center.size())
	bounds.fill(half)
	return make_line(center, bounds, true, world)


## A city route must be a contiguous series of DIRECTED graph edges.
## It inherits the same intersection splines and legality as traffic.
## No shortcuts through buildings and no swerving into oncoming lanes.
static func traffic_line(network: RefCounted, world: Node,
		edge_ids: Array[int]) -> PackedVector2Array:
	var empty := PackedVector2Array()
	if network == null or not is_instance_valid(world) or edge_ids.is_empty():
		return empty
	var edges: Array = network.get("edges")
	var data: Dictionary = world.get("data")
	var route := PackedVector2Array()
	var caps := PackedFloat32Array()
	for i in range(edge_ids.size()):
		var id: int = edge_ids[i]
		if id < 0 or id >= edges.size():
			return empty
		var edge: Dictionary = edges[id]
		if i > 0:
			var previous: Dictionary = edges[edge_ids[i - 1]]
			if not (previous.get("next", []) as Array).has(id):
				return empty
		var road_id: int = int(edge.get("road", -1))
		if road_id < 0 or road_id >= (data.get("roads", []) as Array).size():
			return empty
		var road: Dictionary = data.roads[road_id]
		var lanes := maxi(2, int(road.get("lanes", 2)))
		var lane_width_m := float(road.get("width", 9.0)) / float(lanes)
		var cap := minf(CITY_MAX_SWING_M,
			maxf(0.0, lane_width_m * 0.5 - CAR_HALF_WIDTH_M - SHOULDER_MARGIN_M))
		if bool(edge.get("connector", false)):
			cap = minf(cap, 0.38)
		var points: PackedVector2Array = edge.points
		for j in range(points.size()):
			var p: Vector2 = points[j] / PPM
			if not route.is_empty() and p.distance_to(route[route.size() - 1]) < 0.08:
				caps[caps.size() - 1] = minf(caps[caps.size() - 1], cap)
				continue
			route.append(p)
			caps.append(cap)
	return make_line(route, caps, false, world)


## Deterministic city-sprint seed near Laurel Motor House. The graph picks
## real forward lane edges, then legal connectors, never fabricated shortcuts.
static func city_sprint_edges(network: RefCounted, world: Node,
		origin_px: Vector2) -> Array[int]:
	var empty: Array[int] = []
	if network == null or not is_instance_valid(world):
		return empty
	var edges: Array = network.get("edges")
	var data: Dictionary = world.get("data")
	var seeds: Array[Dictionary] = []
	for i in range(edges.size()):
		var edge: Dictionary = edges[i]
		if bool(edge.get("connector", false)) or float(edge.length_px) < 45.0 * PPM:
			continue
		if str(data.roads[int(edge.road)].name) != "Laurel Avenue":
			continue
		var path: PackedVector2Array = edge.points
		var heading := (path[path.size() - 1] - path[0]).normalized()
		if heading.dot(Vector2.UP) < 0.25:
			continue
		var distance := path[0].distance_to(origin_px) / PPM
		if distance < 450.0:
			seeds.append({"id":i,"proximity":distance})
	seeds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.proximity) < float(b.proximity))
	var beam: Array[Dictionary] = []
	for j in range(mini(5, seeds.size())):
		var start_id := int(seeds[j].id)
		var visited := {start_id:true}
		var sequence: Array[int] = [start_id]
		beam.append({"ids":sequence, "seen":visited,
			"metres":float(edges[start_id].length_px) / PPM,
			"turns":0, "score":0.0})
	var best_ids: Array[int] = []
	var best_value := -INF
	# Bounded, deterministic beam search instead of greedy next-edge choice:
	# junctions can have dead ends, unexpected one-ways and multiple lanes.
	# Every hop still MUST use the directed ambient-traffic network's 'next'.
	for step in range(26):
		if beam.is_empty():
			break
		var candidates: Array[Dictionary] = []
		for entry in beam:
			var sequence: Array[int] = entry.ids
			var current_id: int = sequence[sequence.size() - 1]
			var last_edge: Dictionary = edges[current_id]
			var metres: float = float(entry.metres)
			var turns: int = int(entry.turns)
			if metres >= 650.0 and turns >= 1 and not bool(last_edge.connector):
				var quality := minf(metres, 1300.0) / 170.0 + \
					float(turns) * 2.5 - absf(metres - 1250.0) / 400.0
				if quality > best_value:
					best_value = quality
					best_ids = sequence.duplicate()
			if metres > 1700.0 or sequence.size() >= 25:
				continue
			var next_options: Array = last_edge.get("next", [])
			for option in next_options:
				var next_id := int(option)
				if (entry.seen as Dictionary).has(next_id):
					continue
				var next_edge: Dictionary = edges[next_id]
				var kind := str(next_edge.get("kind", ""))
				if kind in ["highway", "mountain", "rural"]:
					continue
				var path: PackedVector2Array = next_edge.points
				var location: Vector2 = path[mini(1, path.size() - 1)] / PPM
				if location.x < 2100.0 or location.x > 4120.0 or \
						location.y < 2080.0 or location.y > 3580.0:
					continue
				var new_ids: Array[int] = sequence.duplicate()
				new_ids.append(next_id)
				var new_seen: Dictionary = (entry.seen as Dictionary).duplicate()
				new_seen[next_id] = true
				var new_metres := metres + float(next_edge.length_px) / PPM
				var is_turn := bool(next_edge.get("connector", false)) and \
					str(next_edge.get("turn", "straight")) in ["left", "right"]
				var new_turns := turns + (1 if is_turn else 0)
				var score := minf(new_metres, 1300.0) / 170.0 + \
					minf(float(new_turns), 3.0) * 2.6
				if new_metres > 1450.0:
					score -= (new_metres - 1450.0) / 70.0
				candidates.append({"ids":new_ids,"seen":new_seen,
					"metres":new_metres, "turns":new_turns,"score":score})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.score) > float(b.score))
		beam.clear()
		for k in range(mini(24, candidates.size())):
			beam.append(candidates[k])
	return best_ids
