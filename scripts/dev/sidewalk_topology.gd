extends RefCounted
## Sidewalks are independent source props, not traffic roads. Joined end points
## and crossing anchors preserve every branch and remain compatible with v2 maps.
const MIN_GAP_M := 0.5
const SNAP_RADIUS_M := 5.0
const MAX_POINTS := 100


static func _scale(prop: Dictionary) -> Vector2:
	var factor := float(prop.get("scale", 1.0))
	return Vector2(factor * float(prop.get("scaleX", 1.0)),
		factor * float(prop.get("scaleY", 1.0)))


static func world_points(prop: Dictionary) -> Array[Vector2]:
	var output: Array[Vector2] = []
	var center := Vector2(float(prop.get("x", 0)), float(prop.get("y", 0)))
	var angle := deg_to_rad(float(prop.get("rotation", 0)))
	var axes := _scale(prop)
	for raw in prop.get("sidewalkPoints", []):
		output.append(center + (Vector2(float(raw[0]), float(raw[1])) * axes).rotated(angle))
	return output


static func write_world_points(prop: Dictionary, points: Array[Vector2]) -> void:
	if points.size() < 2:
		return
	var bounds := Rect2(points[0], Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	var center := bounds.get_center()
	var axes := _scale(prop)
	var angle := -deg_to_rad(float(prop.get("rotation", 0)))
	var local: Array = []
	var local_bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
	for i in points.size():
		var p := (points[i] - center).rotated(angle)
		p = Vector2(p.x / maxf(axes.x, 0.001), p.y / maxf(axes.y, 0.001))
		local.append([p.x, p.y])
		if i == 0:
			local_bounds = Rect2(p, Vector2.ZERO)
		else:
			local_bounds = local_bounds.expand(p)
	var width := float(prop.get("sidewalkWidth", 3.0))
	prop["x"] = center.x
	prop["y"] = center.y
	prop["sidewalkPoints"] = local
	prop["assetSize"] = [local_bounds.size.x + width, local_bounds.size.y + width]


static func valid_points(points: Array[Vector2], width: float,
		limits: Rect2) -> bool:
	if points.size() < 2 or points.size() > MAX_POINTS or width < 0.8 or width > 12.0:
		return false
	for i in points.size():
		var p := points[i]
		if not is_finite(p.x) or not is_finite(p.y) or not limits.has_point(p):
			return false
		if i > 0 and p.distance_to(points[i - 1]) < MIN_GAP_M:
			return false
	return true


## Closest authored sidewalk centerline. Endpoint and authored junction
## vertices get first priority at equal distances, to avoid tiny seam slivers.
static func snap(props: Array, at: Vector2, radius: float = SNAP_RADIUS_M,
		exclude: String = "") -> Dictionary:
	var best := radius
	var result: Dictionary = {}
	for raw in props:
		var prop: Dictionary = raw
		if str(prop.get("type", "")) != "sidewalk" or bool(prop.get("hidden", false)) or str(prop.get("id", "")) == exclude:
			continue
		var path := world_points(prop)
		for i in path.size():
			var distance := at.distance_to(path[i])
			if distance <= best + 0.0001:
				best = distance
				result = {"point": path[i], "id": str(prop.id),
					"segment": maxi(0, i - 1), "vertex": i, "distance": distance}
		for i in range(1, path.size()):
			var projected := Geometry2D.get_closest_point_to_segment(at, path[i - 1], path[i])
			var distance := at.distance_to(projected)
			if distance < best - 0.0001:
				best = distance
				result = {"point": projected, "id": str(prop.id),
					"segment": i - 1, "vertex": -1, "distance": distance}
	return result


static func _insert_on_segment(prop: Dictionary, at: Vector2, segment: int) -> bool:
	var path := world_points(prop)
	if segment < 0 or segment >= path.size() - 1:
		return false
	if at.distance_to(path[segment]) < MIN_GAP_M or at.distance_to(path[segment + 1]) < MIN_GAP_M:
		return true
	if path.size() >= MAX_POINTS:
		return false
	path.insert(segment + 1, at)
	write_world_points(prop, path)
	return true


## Snap the free tips of a newly drawn path to existing sidewalk centerlines.
## Insert an anchor on the receiving trunk; never collapse/de-duplicate a
## branch into its parent. The entire edit is committed as one undo step.
static func connect_tips(props: Array, new_id: String, radius: float = SNAP_RADIUS_M) -> int:
	var new_prop: Dictionary = {}
	for raw in props:
		if str(raw.get("id", "")) == new_id:
			new_prop = raw
			break
	if new_prop.is_empty():
		return 0
	var connected := 0
	for end in [0, -1]:
		var path := world_points(new_prop)
		var idx := 0 if end == 0 else path.size() - 1
		var match_info := snap(props, path[idx], radius, new_id)
		if match_info.is_empty():
			continue
		var location: Vector2 = match_info.point
		if location.distance_to(path[1 if idx == 0 else idx - 1]) < MIN_GAP_M:
			continue
		var other: Dictionary = {}
		for raw in props:
			if str(raw.get("id", "")) == str(match_info.id):
				other = raw
				break
		if other.is_empty():
			continue
		if int(match_info.vertex) < 0 and not _insert_on_segment(other, location, int(match_info.segment)):
			continue
		path[idx] = location
		write_world_points(new_prop, path)
		connected += 1
	return connected


static func _crosses(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Variant:
	return Geometry2D.segment_intersects_segment(a, b, c, d)


static func _add_intersections(path: Array[Vector2], intersections: Array[Dictionary]) -> Array[Vector2]:
	intersections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.segment) != int(b.segment):
			return int(a.segment) > int(b.segment)
		return float(a.t) > float(b.t))
	for crossing in intersections:
		if path.size() >= MAX_POINTS:
			break
		var segment := int(crossing.segment)
		var p: Vector2 = crossing.point
		if p.distance_to(path[segment]) >= MIN_GAP_M and p.distance_to(path[segment + 1]) >= MIN_GAP_M:
			path.insert(segment + 1, p)
	return path


## A new path can also cross an existing path with neither endpoint on it.
## Store a common anchor in both polylines so X junctions are editable.
static func connect_crossings(props: Array, new_id: String) -> int:
	var new_prop: Dictionary = {}
	for raw in props:
		if str(raw.get("id", "")) == new_id:
			new_prop = raw
			break
	if new_prop.is_empty():
		return 0
	var made := 0
	for raw in props:
		var other: Dictionary = raw
		if other == new_prop or str(other.get("type", "")) != "sidewalk" or bool(other.get("hidden", false)):
			continue
		var new_path := world_points(new_prop)
		var old_path := world_points(other)
		var new_intersections: Array[Dictionary] = []
		var old_intersections: Array[Dictionary] = []
		for i in range(new_path.size() - 1):
			for j in range(old_path.size() - 1):
				var hit: Variant = _crosses(new_path[i], new_path[i + 1],
					old_path[j], old_path[j + 1])
				if not hit is Vector2:
					continue
				var p: Vector2 = hit
				var near_new := p.distance_to(new_path[i]) < MIN_GAP_M or p.distance_to(new_path[i + 1]) < MIN_GAP_M
				var near_old := p.distance_to(old_path[j]) < MIN_GAP_M or p.distance_to(old_path[j + 1]) < MIN_GAP_M
				if new_path.size() + new_intersections.size() >= MAX_POINTS or old_path.size() + old_intersections.size() >= MAX_POINTS:
					continue
				if not near_new:
					new_intersections.append({"point": p, "segment": i,
						"t": new_path[i].distance_to(p) / maxf(.001, new_path[i].distance_to(new_path[i + 1]))})
				if not near_old:
					old_intersections.append({"point": p, "segment": j,
						"t": old_path[j].distance_to(p) / maxf(.001, old_path[j].distance_to(old_path[j + 1]))})
				made += 1
		if not new_intersections.is_empty():
			write_world_points(new_prop, _add_intersections(new_path, new_intersections))
		if not old_intersections.is_empty():
			write_world_points(other, _add_intersections(old_path, old_intersections))
	return made


## Keep branches welded when an authored junction anchor is moved. Alt-drag
## can explicitly detach a branch without moving the other paths.
static func move_anchor(props: Array, identity: String, index: int,
		destination: Vector2, preserve_joint: bool = true) -> bool:
	var selected: Dictionary = {}
	for raw in props:
		if str(raw.get("id", "")) == identity:
			selected = raw
			break
	if selected.is_empty():
		return false
	var path := world_points(selected)
	if index < 0 or index >= path.size():
		return false
	var original := path[index]
	var neighbors := [index - 1, index + 1]
	for other_index in neighbors:
		if other_index >= 0 and other_index < path.size() and path[other_index].distance_to(destination) < MIN_GAP_M:
			return false
	var attached: Array[Dictionary] = []
	if preserve_joint:
		for raw in props:
			var prop: Dictionary = raw
			if prop == selected or str(prop.get("type", "")) != "sidewalk" or bool(prop.get("hidden", false)):
				continue
			var points := world_points(prop)
			for j in points.size():
				if points[j].distance_to(original) < .05:
					if (j > 0 and points[j - 1].distance_to(destination) < MIN_GAP_M) or (j < points.size() - 1 and points[j + 1].distance_to(destination) < MIN_GAP_M):
						return false
					attached.append({"prop": prop, "index": j})
	path[index] = destination
	write_world_points(selected, path)
	for branch in attached:
		var prop: Dictionary = branch.prop
		var points := world_points(prop)
		points[int(branch.index)] = destination
		write_world_points(prop, points)
	return true


static func junctions(props: Array, tolerance: float = .05) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	for raw in props:
		var prop: Dictionary = raw
		if str(prop.get("type", "")) != "sidewalk" or bool(prop.get("hidden", false)):
			continue
		for p in world_points(prop):
			var same: Dictionary = {}
			for node in nodes:
				if Vector2(node.position).distance_to(p) <= tolerance:
					same = node
					break
			if same.is_empty():
				nodes.append({"position": p, "paths": [str(prop.id)]})
			elif not same.paths.has(str(prop.id)):
				same.paths.append(str(prop.id))
	return nodes.filter(func(node: Dictionary) -> bool: return node.paths.size() >= 2)
