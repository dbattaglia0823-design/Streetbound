extends RefCounted
## Derived membership and selective replacement of the old outer safety wall.
## An edge mountain becomes the physical boundary along its own footprint.
const Geometry=preload("res://scripts/world/mountain_barrier_geometry.gd")

static func cells(box: Rect2,data: Dictionary) -> Array[String]:
	var result: Array[String]=[];var size_m:=float(data.chunk_size)
	var first:=Vector2i((box.position/size_m).floor()).max(Vector2i.ZERO)
	var last:=Vector2i((box.end/size_m).floor()).min(Vector2i(ceili(float(data.size[0])/size_m),ceili(float(data.size[1])/size_m))-Vector2i.ONE)
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):result.append("%d,%d"%[x,y])
	return result

static func _section_hits(a: Vector2,b: Vector2,polygons: Array[PackedVector2Array]) -> bool:
	for polygon in polygons:
		if Geometry2D.is_point_in_polygon(a,polygon) or Geometry2D.is_point_in_polygon(b,polygon):return true
		for i in polygon.size():
			if Geometry2D.segment_intersects_segment(a,b,polygon[i],polygon[(i+1)%polygon.size()])!=null:return true
	return false

static func trim_outer_walls(data: Dictionary,polygons: Array[PackedVector2Array]) -> int:
	var output: Array=[];var bridge_ids: Dictionary={};var next_bridge_ids: Array=[];var removed:=0
	for id in data.get("bridge_wall_indices",[]):bridge_ids[int(id)]=true
	for index in data.walls.size():
		var wall: Array=data.walls[index];var a:=Vector2(wall[0][0],wall[0][1]);var b:=Vector2(wall[1][0],wall[1][1])
		var axis:=-1;var edge:=0.0
		if not bridge_ids.has(index):
			if absf(a.x-b.x)<.001 and (absf(a.x-25)<.001 or absf(a.x-(float(data.size[0])-25))<.001):axis=0;edge=0 if a.x<50 else float(data.size[0])
			elif absf(a.y-b.y)<.001 and (absf(a.y-25)<.001 or absf(a.y-(float(data.size[1])-25))<.001):axis=1;edge=0 if a.y<50 else float(data.size[1])
		if axis<0:
			if bridge_ids.has(index):next_bridge_ids.append(output.size())
			output.append(wall);continue
		var along:=1-axis;var delta:=b[along]-a[along]
		if absf(delta)<.0001:output.append(wall);continue
		var cuts: Array[float]=[0.0,1.0]
		for polygon in polygons:
			for p in polygon:
				var t: float=(p[along]-a[along])/delta
				if t>0 and t<1:cuts.append(t)
		cuts.sort()
		for i in range(1,cuts.size()):
			if cuts[i]-cuts[i-1]<.00001:continue
			var middle:=a.lerp(b,(cuts[i]+cuts[i-1])*.5);var outside:=middle;outside[axis]=edge
			if _section_hits(outside,middle,polygons):removed+=1;continue
			var p:=a.lerp(b,cuts[i-1]);var q:=a.lerp(b,cuts[i]);output.append([[p.x,p.y],[q.x,q.y]])
	if removed==0:return 0
	data.walls=output
	if data.has("bridge_wall_indices"):data.bridge_wall_indices=next_bridge_ids
	for chunk in data.chunks.values():chunk.walls=[]
	for i in output.size():
		var line:=PackedVector2Array([Vector2(output[i][0][0],output[i][0][1]),Vector2(output[i][1][0],output[i][1][1])])
		for key in cells(Geometry.bounds(line).grow(.15),data):
			if data.chunks.has(key):data.chunks[key].walls.append(i)
	return removed

static func apply(data: Dictionary) -> Dictionary:
	for chunk in data.chunks.values():chunk["mountains"]=[]
	var polygons: Array[PackedVector2Array]=[];var count:=0
	for i in data.terrain.size():
		var region: Dictionary=data.terrain[i]
		if not Geometry.solid(region):continue
		if not region.has("authoring_id"):region["authoring_id"]=Geometry.identity(region,i)
		var polygon:=Geometry.polygon(region)
		if polygon.size()<3 or Geometry2D.triangulate_polygon(polygon).is_empty():continue
		polygons.append(polygon);count+=1
		for key in cells(Geometry.bounds(polygon).grow(40),data):
			if not data.chunks.has(key):data.chunks[key]={"segments":[],"props":[],"walls":[],"terrain":[],"junctions":[],"relief":[],"rails":[],"bridges":[],"mountains":[]}
			data.chunks[key].mountains.append(i)
	var replaced:=trim_outer_walls(data,polygons) if count>0 else 0
	return {"barriers":count,"replaced_boundary_sections":replaced}
