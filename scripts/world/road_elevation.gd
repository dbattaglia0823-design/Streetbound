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


## Only the surface-to-underground approach is excavated. Covered tunnels
## and deeper underground ramps retain their surface roof.
static func is_open_cut(road: Dictionary) -> bool:
	var first := endpoint_layer(road,true)
	var last := endpoint_layer(road,false)
	return mini(first,last) == -1 and maxi(first,last) == 0


## One continuous metre-space trench, including curved approaches. The same
## outline is used by artwork masking, mountain subtraction and side walls.
static func cutout_polygons(road: Dictionary) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if not is_open_cut(road):
		return result
	var path := PackedVector2Array()
	for raw in road.points:
		var p := Vector2(float(raw[0]),float(raw[1]))
		if path.is_empty() or path[-1].distance_to(p) > .01:
			path.append(p)
	if path.size() < 2:
		return result
	var origin := path[0]
	for i in path.size():
		path[i] -= origin
	for outline in Geometry2D.offset_polyline(path,float(road.width)*.5+1.2,Geometry2D.JOIN_ROUND,Geometry2D.END_BUTT):
		if outline.size() < 3 or Geometry2D.is_polygon_clockwise(outline):
			continue
		for i in outline.size():
			outline[i] += origin
		result.append(outline)
	return result


static func cutout_walls(road: Dictionary, outline: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var start := Vector2(road.points[0][0],road.points[0][1])
	var finish := Vector2(road.points[-1][0],road.points[-1][1])
	var forward := (Vector2(road.points[1][0],road.points[1][1])-start).normalized()
	var backward := (Vector2(road.points[-2][0],road.points[-2][1])-finish).normalized()
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		# Keep both end planes open; no invisible barrier across the portal.
		if absf((a-start).dot(forward)) < .08 and absf((b-start).dot(forward)) < .08:
			continue
		if absf((a-finish).dot(backward)) < .08 and absf((b-finish).dot(backward)) < .08:
			continue
		if a.distance_to(b) > .05:
			result.append(PackedVector2Array([a,b]))
	return result


static func polygon_bounds(poly: PackedVector2Array) -> Rect2:
	var box := Rect2(poly[0],Vector2.ZERO)
	for p in poly:
		box = box.expand(p)
	return box


static func _half_plane(poly: PackedVector2Array, a: Vector2, b: Vector2, inside: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	if poly.is_empty():
		return result
	var sign_value := 1.0 if inside else -1.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i+1)%poly.size()]
		var dp := (b-a).cross(p-a)*sign_value
		var dq := (b-a).cross(q-a)*sign_value
		if dp >= 0.0:
			result.append(p)
		if (dp >= 0.0) != (dq >= 0.0):
			result.append(p.lerp(q,dp/(dp-dq)))
	return result


static func _valid_piece(poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	var area := 0.0
	for i in range(1,poly.size()-1):
		area += (poly[i]-poly[0]).cross(poly[i+1]-poly[0])
	return absf(area) > .0001


## Subtract convex triangles from triangulated terrain. Unlike treating
## Geometry2D.clip_polygons' hole contours as filled collision polygons,
## this also handles an excavation completely enclosed by a mountain.
static func subtract_cutouts(subject: PackedVector2Array, cuts: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if subject.size() < 3:
		return result
	var relevant: Array[PackedVector2Array] = []
	var box := polygon_bounds(subject)
	for cut in cuts:
		if cut.size() >= 3 and box.intersects(polygon_bounds(cut)):
			relevant.append(cut)
	if relevant.is_empty():
		result.append(subject)
		return result
	var subject_indices := Geometry2D.triangulate_polygon(subject)
	for i in range(0,subject_indices.size(),3):
		result.append(PackedVector2Array([subject[subject_indices[i]],subject[subject_indices[i+1]],subject[subject_indices[i+2]]]))
	for cut in relevant:
		var indices := Geometry2D.triangulate_polygon(cut)
		for i in range(0,indices.size(),3):
			var triangle := PackedVector2Array([cut[indices[i]],cut[indices[i+1]],cut[indices[i+2]]])
			if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]) < 0.0:
				triangle.reverse()
			var next: Array[PackedVector2Array] = []
			for piece in result:
				if not polygon_bounds(piece).intersects(polygon_bounds(triangle)):
					next.append(piece)
					continue
				var remainder := piece
				for edge in 3:
					var outside := _half_plane(remainder,triangle[edge],triangle[(edge+1)%3],false)
					if _valid_piece(outside):
						next.append(outside)
					remainder = _half_plane(remainder,triangle[edge],triangle[(edge+1)%3],true)
					if not _valid_piece(remainder):
						break
			result = next
	return result


## Scanline mask uses exactly the same continuous polygon as physics.
## Per-chunk texture only exists for excavated cells; ordinary maps pay nothing.
static func cutout_mask(cuts: Array[PackedVector2Array], bounds: Rect2) -> ImageTexture:
	var resolution := minf(4.0,2048.0/maxf(bounds.size.x,bounds.size.y))
	var size := Vector2i(maxi(1,ceili(bounds.size.x*resolution)),maxi(1,ceili(bounds.size.y*resolution)))
	var image := Image.create(size.x,size.y,false,Image.FORMAT_L8)
	image.fill(Color.BLACK)
	for cut in cuts:
		var box := polygon_bounds(cut).intersection(bounds)
		if not box.has_area():
			continue
		var first := maxi(0,floori((box.position.y-bounds.position.y)*resolution))
		var last := mini(size.y,ceili((box.end.y-bounds.position.y)*resolution))
		for y in range(first,last):
			var at := bounds.position.y+(float(y)+.5)/resolution
			var hits: Array[float] = []
			for i in cut.size():
				var a := cut[i]
				var b := cut[(i+1)%cut.size()]
				if (a.y > at) != (b.y > at):
					hits.append(a.x+(b.x-a.x)*(at-a.y)/(b.y-a.y))
			hits.sort()
			for i in range(0,hits.size()-1,2):
				var left := clampi(ceili((hits[i]-bounds.position.x)*resolution-.5),0,size.x)
				var right := clampi(ceili((hits[i+1]-bounds.position.x)*resolution-.5),0,size.x)
				if right > left:
					image.fill_rect(Rect2i(left,y,right-left,1),Color.WHITE)
	return ImageTexture.create_from_image(image)


static func masked_material(base: ShaderMaterial, mask: Texture2D, bounds: Rect2) -> ShaderMaterial:
	var instance := base.duplicate() as ShaderMaterial
	instance.set_shader_parameter("terrain_cut_enabled",true)
	instance.set_shader_parameter("terrain_cut_mask",mask)
	instance.set_shader_parameter("terrain_cut_rect",Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y))
	return instance
