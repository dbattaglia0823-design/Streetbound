extends RefCounted
## One migration point for the existing 7.5 MB Morrow Coast archive.
## Width is geometric metres, NOT a camera or car sprite scale. Keep all
## centerlines/POIs stable, so routing, terrain, roads and collision agree.
const TARGET_WIDTH_SCALE := 1.10
const JUNCTION_APRON_SCALE := 1.05
const SCENERY_FACTORS := {
	"house": 0.94, "coastal_house": 0.94, "building": 0.94,
	"shop": 0.94, "warehouse": 0.94, "lodge": 0.94,
	"office": 0.94, "hotel": 0.94, "cafe": 0.94,
	"showroom": 0.94,
	"tree": 0.92, "pine": 0.92, "palm": 0.92,
	"bush": 0.92, "rock": 0.92, "planter": 0.92,
	"garden": 0.95
}


static func adapt(world_data: Dictionary) -> void:
	# A future source rebake will carry this marker and identical geometry.
	# Do not grow already-widened roads another 10% at every game start.
	if is_equal_approx(float(world_data.get("road_width_scale", 1.0)),
			TARGET_WIDTH_SCALE):
		return
	for road in world_data.get("roads", []):
		road["width"] = roundf(float(road.width) * TARGET_WIDTH_SCALE * 1000.0) / 1000.0
	for bridge in world_data.get("bridges", []):
		bridge["width"] = roundf(float(bridge.width) * TARGET_WIDTH_SCALE * 1000.0) / 1000.0
	# Existing junctions are baked curves; move their exterior apron/curbs
	# outward by a SMALL amount while widening every approach's stop line.
	# This avoids painted old-width corner curbs sticking into new asphalt,
	# without moving junction centers or altering legal traffic topology.
	for junction in world_data.get("junctions", []):
		var center := Vector2(float(junction.p[0]), float(junction.p[1]))
		var outline: Array = junction.polygon
		for i in range(outline.size()):
			var p := Vector2(float(outline[i][0]), float(outline[i][1]))
			var q := center + (p - center) * JUNCTION_APRON_SCALE
			outline[i] = [q.x, q.y]
		for curve in junction.get("curbs", []):
			for i in range(curve.size()):
				var p := Vector2(float(curve[i][0]), float(curve[i][1]))
				var q := center + (p - center) * JUNCTION_APRON_SCALE
				curve[i] = [q.x, q.y]
		for approach in junction.get("approaches", []):
			approach["width"] = float(approach.width) * TARGET_WIDTH_SCALE
		junction["radius"] = float(junction.radius) * JUNCTION_APRON_SCALE
	# Buildings and stationary landscape decorations receive a modest
	# footprint reduction so widened roads keep at least their original
	# roadside clearance. Their artwork and physical collision both read
	# the same prop size. Do NOT change parked_car, moving traffic, the
	# player, parking aprons or the functional Laurel garage bay.
	for prop in world_data.get("props", []):
		var factor: float = float(SCENERY_FACTORS.get(str(prop.kind), 1.0))
		if is_equal_approx(factor, 1.0):
			continue
		if prop.has("size"):
			var old_size: Array = prop.size
			if old_size.size() >= 2:
				prop["size"] = [float(old_size[0]) * factor, float(old_size[1]) * factor]
		if prop.has("radius"):
			prop["radius"] = float(prop.radius) * factor
	world_data["road_width_scale"] = TARGET_WIDTH_SCALE
