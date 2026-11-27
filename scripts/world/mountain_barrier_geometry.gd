extends RefCounted
## Metre-authored mountain footprints. One cached mesh per shape/height, reused
## across streamed cells, editor previews, the atlas and the full-map overview.
const PPM:=20.0
const DETAIL_SPACING_M:=12.0
const DETAIL_SAMPLE_BUDGET:=4200.0
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
	var erosion:=1.0-absf(noise.get_noise_2d(p.x*3.7+41.0,p.y*3.7-16.0))
	return minf(height_m,edge*3.2)*(.34+.53*ridge*ridge+.13*erosion*erosion)

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
	noise.frequency=1.0/115.0;noise.fractal_octaves=4
	var points:=local.duplicate();var heights:=PackedFloat32Array()
	for p in local:heights.append(0)
	var spacing:=maxf(DETAIL_SPACING_M,sqrt(maxf(1,box.size.x*box.size.y)/DETAIL_SAMPLE_BUDGET))
	var nx:=clampi(ceili(box.size.x/spacing),2,140);var ny:=clampi(ceili(box.size.y/spacing),2,140)
	# Very narrow/long polygons still obey a hard candidate budget.
	while nx*ny>int(DETAIL_SAMPLE_BUDGET):
		if nx>=ny:nx-=1
		else:ny-=1
	var rng:=RandomNumberGenerator.new();rng.seed=noise.seed
	for y in ny:
		for x in nx:
			var p:=Vector2((x+rng.randf_range(.18,.82))*box.size.x/nx,(y+rng.randf_range(.18,.82))*box.size.y/ny)
			if Geometry2D.is_point_in_polygon(p,local):points.append(p);heights.append(_height(p,local,height_m,noise))
	var triangles:=Geometry2D.triangulate_delaunay(points)
	var vertices:=PackedVector2Array();var colors:=PackedColorArray();var uvs:=PackedVector2Array()
	var sun:=Vector3(-.55,-.70,.65).normalized()
	var stone:=Color("#899080") if kind=="mountain" else Color("#96968c")
	var normals:=PackedVector3Array();normals.resize(points.size())
	# Area-weighted shared normals remove obvious low-poly lighting seams.
	for i in range(0,triangles.size(),3):
		var ia:=triangles[i];var ib:=triangles[i+1];var ic:=triangles[i+2]
		var a:=points[ia];var b:=points[ib];var c:=points[ic]
		var n:=Vector3(b.x-a.x,b.y-a.y,heights[ib]-heights[ia]).cross(Vector3(c.x-a.x,c.y-a.y,heights[ic]-heights[ia]))
		if n.z<0:n=-n
		for index in [ia,ib,ic]:normals[index]+=n
	var shades:=PackedColorArray();shades.resize(points.size())
	for i in points.size():
		var n:=normals[i].normalized() if normals[i].length_squared()>.00001 else Vector3.UP
		if normals[i].length_squared()<=.00001:n=Vector3(0,0,1)
		var light:=clampf(n.dot(sun),0,1)
		var local_stone:=stone.lerp(Color("#aba79a"),clampf(heights[i]/height_m,0,1)*.36)
		shades[i]=local_stone.darkened(.50*(1-light)).lightened(.22*maxf(0,light-.5))
	for i in range(0,triangles.size(),3):
		var a:=points[triangles[i]];var b:=points[triangles[i+1]];var c:=points[triangles[i+2]]
		var ab:=b-a;var ac:=c-a
		var area:=ab.cross(ac)
		if absf(area)<.00001:continue
		var triangle:=PackedVector2Array([a,b,c])
		for clipped in Geometry2D.intersect_polygons(triangle,local):
			var indices:=Geometry2D.triangulate_polygon(clipped)
			for index in indices:
				var p: Vector2=clipped[index]
				var v: float=(p-a).cross(ac)/area
				var w: float=ab.cross(p-a)/area
				var u: float=1.0-v-w
				var tint: Color=shades[triangles[i]]*u+shades[triangles[i+1]]*v+shades[triangles[i+2]]*w
				tint.a=1.0
				vertices.append(p*PPM);colors.append(tint);uvs.append(p*.045)
	var mesh:=ArrayMesh.new()
	if not vertices.is_empty():
		var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_TEX_UV]=uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var result: Dictionary={"key":key,"origin":box.position,"outline":local,"mesh":mesh,"height":height_m,"triangles":vertices.size()/3,"samples":points.size(),"grid_samples":nx*ny}
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
