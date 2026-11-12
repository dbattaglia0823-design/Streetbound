extends RefCounted
## One-time, idempotent runtime dimensional upgrade for the legacy baked map.
## Roads, shoulders, traffic lanes, sidewalks, map lines and vehicle surfaces
## all consume the SAME world.data roads. Vehicle sizes/physics are untouched.
const ROAD_SCALE := 1.10
const BUILDING_SCALE := 0.97
const ROADSIDE_DECOR_SCALE := 0.97
const SEARCH_RADIUS_M := 28.0
const SCENERY_KINDS := [
	"house", "coastal_house", "building", "shop", "warehouse", "lodge",
	"cafe", "hotel", "office", "showroom"
]
const DECOR_KINDS := ["tree", "pine", "palm", "rock", "planter"]
const PPM := 20.0


static func _vector(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))


static func _chunk_key(point: Vector2, chunk_m: float) -> String:
	return "%d,%d" % [floori(point.x / chunk_m), floori(point.y / chunk_m)]


static func apply(world: Node2D) -> Dictionary:
	var data: Dictionary = world.get("data")
	if data.is_empty():
		return {}
	# Do not multiply dimensions repeatedly when Godot reloads a scene or
	# an editor script reuses the same dictionary.
	if bool(data.get("_wider_roads_applied", false)):
		return data.get("_road_widening_stats", {})
	var road_count := 0
	for road in data.roads:
		road["width"] = snappedf(float(road.width) * ROAD_SCALE, 0.001)
		road_count += 1
	# Bridges use separate deck/guardrail widths, not an unrelated scaled
	# sprite. Keep guardrails just outside the new actual road edge.
	for bridge in data.get("bridges", []):
		bridge["width"] = snappedf(float(bridge.width) * ROAD_SCALE, 0.001)
	# A junction's road segments expand naturally. Avoid scaling its baked
	# polygon around an arbitrary center, which would cause corner triangles.
	# The 64m surface grid already provides a >=12m margin around roads.
	var resized := 0
	var shifted := 0
	var chunk_m := float(data.chunk_size)
	for index in data.props.size():
		var prop: Dictionary = data.props[index]
		var kind := str(prop.get("kind", ""))
		if not kind in SCENERY_KINDS and not kind in DECOR_KINDS:
			continue
		# Garages, named destinations, imported editor-authored landmarks,
		# parking lots and parked/racing cars keep their functional geometry.
		if prop.has("poi") or prop.has("source_replacement") or \
				prop.has("editor_id") or prop.has("editor_prop_id"):
			continue
		var center := _vector(prop.p)
		var nearby: Dictionary = world.call("nearest_road_at", center * PPM, SEARCH_RADIUS_M)
		if nearby.is_empty():
			continue
		var radius := float(prop.get("radius", 0.0))
		var half_width := float(nearby.road_width_m) * 0.5
		if float(nearby.distance_to_center_m) > half_width + maxf(radius, 5.0) + 8.0:
			continue
		var scale := BUILDING_SCALE if kind in SCENERY_KINDS else ROADSIDE_DECOR_SCALE
		var size: Array = prop.size
		prop["size"] = [snappedf(float(size[0]) * scale, 0.001),
			snappedf(float(size[1]) * scale, 0.001)]
		if radius > 0.0:
			prop["radius"] = snappedf(radius * scale, 0.001)
		resized += 1
		if not bool(prop.get("solid", false)):
			continue
		# A wider road is more useful only if old physical scenery doesn't
		# occupy the added driving strip. Recede encroaching obstacles along
		# the real road normal; preserve all original vehicle dimensions.
		var new_radius := float(prop.get("radius", 0.0))
		var clearance := half_width + new_radius + 1.2
		var road_distance := float(nearby.distance_to_center_m)
		if road_distance >= clearance:
			continue
		var road_center: Vector2 = nearby.closest_point_px / PPM
		var outward := (center - road_center).normalized()
		if outward.length_squared() < 0.1:
			continue
		# Original generated objects were placed outside the OLD pavement.
		# Cap relocation to the added half-width + 0.6m.
		var delta := minf(clearance - road_distance,
			half_width * (1.0 - 1.0 / ROAD_SCALE) + 0.6)
		var target := center + outward * delta
		prop["p"] = [snappedf(target.x, 0.001), snappedf(target.y, 0.001)]
		shifted += 1
		# Chunks are baked with prop indices. Correct the few assets that
		# cross a 192m streaming boundary due to their new setback.
		var prior_key := _chunk_key(center, chunk_m)
		var new_key := _chunk_key(target, chunk_m)
		if prior_key != new_key and data.chunks.has(prior_key) and data.chunks.has(new_key):
			var before: Dictionary = data.chunks[prior_key]
			var after: Dictionary = data.chunks[new_key]
			var list_before: Array = before.props
			var list_after: Array = after.props
			list_before.erase(index)
			if not list_after.has(index):
				list_after.append(index)
	var stats := {"roads": road_count, "scale": ROAD_SCALE,
		"resized_roadside_props": resized, "moved_roadside_props": shifted}
	data["_wider_roads_applied"] = true
	data["_road_widening_stats"] = stats
	return stats
