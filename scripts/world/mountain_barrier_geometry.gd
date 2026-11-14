extends RefCounted
## Metre-authored mountain footprints. One cached mesh per shape/height, reused
## across streamed cells, editor previews, the atlas and the full-map overview.
const PPM:=20.0
static var material: ShaderMaterial

static func polygon(region: Dictionary) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for raw in region.get("points",[]):
		result.append(Vector2(raw.x,raw.y) if raw is Dictionary else Vector2(raw[0],raw[1]))
	return result

static func identity(region: Dictionary,index: int=-1) -> String:
	return str(region.get("authoring_id",region.get("id","region-%d"%index)))

static func solid(region: Dictionary) -> bool:
	return bool(region.get("barrier",false)) and str(region.get("kind",region.get("biome",""))) in ["mountain","rock"]

static func bounds(path: PackedVector2Array) -> Rect2:
	if path.is_empty():return Rect2()
	var box:=Rect2(path[0],Vector2.ZERO)
	for p in path:box=box.expand(p)
	return box

static func _height(p: Vector2,outline: PackedVector2Array,height_m: float,noise: FastNoiseLite) -> float:
	var edge:=INF
	for i in outline.size():edge=minf(edge,p.distance_to(Geometry2D.get_closest_point_to_segment(p,outline[i],outline[(i+1)%outline.size()])))
	var ridge:=1.0-absf(noise.get_noise_2d(p.x,p.y))
	return minf(height_m,edge*3.2)*(.40+.60*ridge*ridge)

static func bundle(region: Dictionary,cache: Dictionary) -> Dictionary:
	var outline:=polygon(region);var box:=bounds(outline)
	var local:=PackedVector2Array()
	for p in outline:local.append(p-box.position)
	var height_m:=clampf(float(region.get("elevation",80)),5,2000)
	var kind:=str(region.get("kind",region.get("biome","mountain")))
	var id:=identity(region)
	var key:=str(local)+"/"+str(height_m)+"/"+kind
	if cache.has(id) and cache[id].key==key:
		var reused: Dictionary=cache[id].duplicate();reused.origin=box.position;return reused
	var noise:=FastNoiseLite.new();noise.seed=int(id.hash()&0x7fffffff)
	noise.frequency=1.0/115.0;noise.fractal_octaves=3
	var points:=local.duplicate();var heights:=PackedFloat32Array()
	for p in local:heights.append(0)
	var spacing:=maxf(24.0,sqrt(maxf(1,box.size.x*box.size.y)/2100.0))
	var nx:=clampi(ceili(box.size.x/spacing),2,140);var ny:=clampi(ceili(box.size.y/spacing),2,140)
	var rng:=RandomNumberGenerator.new();rng.seed=noise.seed
	for y in ny:
		for x in nx:
			var p:=Vector2((x+rng.randf_range(.18,.82))*box.size.x/nx,(y+rng.randf_range(.18,.82))*box.size.y/ny)
			if Geometry2D.is_point_in_polygon(p,local):points.append(p);heights.append(_height(p,local,height_m,noise))
	var triangles:=Geometry2D.triangulate_delaunay(points)
	var vertices:=PackedVector2Array();var colors:=PackedColorArray();var uvs:=PackedVector2Array()
	var sun:=Vector3(-.55,-.70,.65).normalized()
	var stone:=Color("#899080") if kind=="mountain" else Color("#96968c")
	for i in range(0,triangles.size(),3):
		var a:=points[triangles[i]];var b:=points[triangles[i+1]];var c:=points[triangles[i+2]]
		var ha:=heights[triangles[i]];var hb:=heights[triangles[i+1]];var hc:=heights[triangles[i+2]]
		var normal:=Vector3(b.x-a.x,b.y-a.y,hb-ha).cross(Vector3(c.x-a.x,c.y-a.y,hc-ha)).normalized()
		if normal.z<0:normal=-normal
		var light:=clampf(normal.dot(sun),0,1)
		var tint:=stone.darkened(.49*(1-light)).lightened(.18*maxf(0,light-.5))
		var triangle:=PackedVector2Array([a,b,c])
		for clipped in Geometry2D.intersect_polygons(triangle,local):
			var indices:=Geometry2D.triangulate_polygon(clipped)
			for index in indices:
				var p: Vector2=clipped[index]
				vertices.append(p*PPM);colors.append(tint);uvs.append(p*.045)
	var mesh:=ArrayMesh.new()
	if not vertices.is_empty():
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_TEX_UV]=uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var result: Dictionary={"key":key,"origin":box.position,"outline":local,"mesh":mesh,"height":height_m,"triangles":vertices.size()/3}
	cache[id]=result
	return result

static func shared_material() -> ShaderMaterial:
	if material==null:
		material=ShaderMaterial.new();material.shader=preload("res://scripts/world/mountain_barrier.gdshader")
	return material

static func draw_art(canvas: CanvasItem,region: Dictionary,cache: Dictionary,origin_m:=Vector2.ZERO,pixels_per_m: float=PPM,offset_px:=Vector2.ZERO) -> void:
	var art:=bundle(region,cache)
	var outline:=PackedVector2Array()
	for p in art.outline:outline.append(p*PPM)
	var base: Vector2=(Vector2(art.origin)-origin_m)*pixels_per_m+offset_px
	var scale:=Vector2.ONE*pixels_per_m/PPM
	var cast:=Vector2(1,1.4)*clampf(float(art.height)*.13,4,24)*PPM
	for spread in [1.0,.65]:
		canvas.draw_set_transform(base+cast*spread*scale,0,scale)
		canvas.draw_colored_polygon(outline,Color(.045,.09,.09,.12))
	canvas.draw_set_transform(base,0,scale)
	canvas.draw_colored_polygon(outline,Color("#65705c"))
	var closed:=outline.duplicate();closed.append(closed[0])
	canvas.draw_polyline(closed,Color("#424f43"),16,true)
	canvas.draw_mesh(art.mesh,null)
	canvas.draw_polyline(closed,Color(.65,.66,.53,.38),3,true)
	canvas.draw_set_transform(Vector2.ZERO)
