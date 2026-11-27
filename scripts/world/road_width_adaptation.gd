extends RefCounted
## One migration point for the existing 7.5 MB Morrow Coast archive.
## Width is geometric metres, NOT a camera or car sprite scale. Keep all
## centerlines/POIs stable, so routing, terrain, roads and collision agree.
const LEGACY_WIDTH_SCALE := 1.10
const TARGET_WIDTH_SCALE := 1.265
const JUNCTION_APRON_SCALE := 1.2075
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
	# Standalone authored maps retain their explicit metre dimensions.
	if bool(world_data.get("editor_custom_test_drive",false)):return
	var previous:=float(world_data.get("road_width_scale",1.0))
	if is_equal_approx(previous,TARGET_WIDTH_SCALE):return
	var ratio:=TARGET_WIDTH_SCALE/maxf(previous,.01)
	var apron_ratio:=JUNCTION_APRON_SCALE/(1.05 if is_equal_approx(previous,LEGACY_WIDTH_SCALE) else 1.0)
	for road in world_data.get("roads", []):
		road["width"] = roundf(float(road.width) * ratio * 1000.0) / 1000.0
	for bridge in world_data.get("bridges", []):
		bridge["width"] = roundf(float(bridge.width) * ratio * 1000.0) / 1000.0
	# Existing junctions are baked curves; move their exterior apron/curbs
	# outward by a SMALL amount while widening every approach's stop line.
	# This avoids painted old-width corner curbs sticking into new asphalt,
	# without moving junction centers or altering legal traffic topology.
	for junction in world_data.get("junctions", []):
		var center := Vector2(float(junction.p[0]), float(junction.p[1]))
		var outline: Array = junction.polygon
		for i in range(outline.size()):
			var p := Vector2(float(outline[i][0]), float(outline[i][1]))
			var q := center + (p - center) * apron_ratio
			outline[i] = [q.x, q.y]
		for curve in junction.get("curbs", []):
			for i in range(curve.size()):
				var p := Vector2(float(curve[i][0]), float(curve[i][1]))
				var q := center + (p - center) * apron_ratio
				curve[i] = [q.x, q.y]
		for approach in junction.get("approaches", []):
			approach["width"] = roundf(float(approach.width) * ratio * 1000.0) / 1000.0
		junction["radius"] = float(junction.radius) * apron_ratio
	# Buildings and stationary landscape decorations receive a modest
	# footprint reduction so widened roads keep at least their original
	# roadside clearance. Their artwork and physical collision both read
	# the same prop size. Do NOT change parked_car, moving traffic, the
	# player, parking aprons or the functional Laurel garage bay.
	for prop in world_data.get("props", []):
		if previous>=LEGACY_WIDTH_SCALE or prop.has("authoring_id") or prop.has("asset_path"):continue
		var factor: float = float(SCENERY_FACTORS.get(str(prop.kind), 1.0))
		if is_equal_approx(factor, 1.0):
			continue
		if prop.has("size"):
			var old_size: Array = prop.size
			if old_size.size() >= 2:
				prop["size"] = [float(old_size[0]) * factor, float(old_size[1]) * factor]
		if prop.has("radius"):
			prop["radius"] = float(prop.radius) * factor
	_reindex_roads(world_data)
	world_data["road_width_scale"] = TARGET_WIDTH_SCALE


## Widen lookup coverage without altering other chunk memberships or IDs.
static func _reindex_roads(world_data: Dictionary) -> void:
	if not world_data.has("surface_index") or not world_data.has("chunks") or not world_data.has("segments"):return
	var surface: Dictionary=world_data.surface_index
	var chunks: Dictionary=world_data.chunks
	surface.clear()
	for chunk in chunks.values():chunk.segments=[]
	var cell_m:=float(world_data.surface_cell)
	var chunk_m:=float(world_data.chunk_size)
	for index in world_data.segments.size():
		var segment: Dictionary=world_data.segments[index]
		var road: Dictionary=world_data.roads[int(segment.road)]
		var a:=Vector2(float(segment.a[0]),float(segment.a[1]))
		var b:=Vector2(float(segment.b[0]),float(segment.b[1]))
		var radius:=float(road.width)*.5
		for pass_index in 2:
			var size_m:=cell_m if pass_index==0 else chunk_m
			var padding:=radius+(12.0 if pass_index==0 else 8.0)
			var low:=Vector2i(((a.min(b)-Vector2.ONE*padding)/size_m).floor())
			var high:=Vector2i(((a.max(b)+Vector2.ONE*padding)/size_m).floor())
			for x in range(low.x,high.x+1):
				for y in range(low.y,high.y+1):
					var key:="%d,%d"%[x,y]
					if pass_index==0:
						if not surface.has(key):surface[key]=[]
						surface[key].append(index)
					elif chunks.has(key):chunks[key].segments.append(index)
