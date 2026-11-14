extends RefCounted
## Upgrade old archives in memory and index derived spans for every renderer.
## Only derived bridge rails change; road geometry, traffic and save data do not.
const Geometry=preload("res://scripts/world/road_bridge_geometry.gd")

static func _legacy_edges(bridges: Array) -> Array:
	var result: Array=[]
	for bridge in bridges:
		var points: Array=bridge.points
		for side in [-1,1]:
			var edge: Array[Vector2]=[]
			for i in points.size():
				var a:=Geometry.v(points[maxi(0,i-1)]);var b:=Geometry.v(points[mini(points.size()-1,i+1)])
				edge.append(Geometry.v(points[i])+(b-a).normalized().orthogonal()*side*(float(bridge.width)*.5+1))
			for i in range(1,edge.size()):
				var pieces:=maxi(1,ceili(edge[i-1].distance_to(edge[i])/24.0))
				for j in pieces:result.append([edge[i-1].lerp(edge[i],float(j)/pieces),edge[i-1].lerp(edge[i],float(j+1)/pieces)])
	return result

static func _old_wall_ids(data: Dictionary,legacy: Array) -> Dictionary:
	var removed: Dictionary={}
	if int(data.get("bridge_generation",0))>=Geometry.VERSION:
		for id in data.get("bridge_wall_indices",[]):removed[int(id)]=true
		return removed
	var grid: Dictionary={}
	for edge in _legacy_edges(legacy):
		var cell:=Vector2i(((Vector2(edge[0])+Vector2(edge[1]))*.5/8).floor())
		if not grid.has(cell):grid[cell]=[]
		grid[cell].append(edge)
	for i in data.walls.size():
		var a:=Geometry.v(data.walls[i][0]);var b:=Geometry.v(data.walls[i][1])
		var cell:=Vector2i(((a+b)*.5/8).floor())
		for y in range(cell.y-1,cell.y+2):
			for x in range(cell.x-1,cell.x+2):
				for edge in grid.get(Vector2i(x,y),[]):
					if (a.distance_to(edge[0])<.025 and b.distance_to(edge[1])<.025) or (b.distance_to(edge[0])<.025 and a.distance_to(edge[1])<.025):removed[i]=true;break
	return removed

static func _cells(rect: Rect2,chunk_m: float,extent: Vector2) -> Array[String]:
	var result: Array[String]=[]
	var first:=Vector2i((rect.position/chunk_m).floor()).max(Vector2i.ZERO)
	var last:=Vector2i((rect.end/chunk_m).floor()).min(Vector2i((extent/chunk_m).ceil())-Vector2i.ONE)
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):result.append("%d,%d"%[x,y])
	return result

static func _chunk(data: Dictionary,key: String) -> Dictionary:
	if not data.chunks.has(key):data.chunks[key]={"segments":[],"props":[],"walls":[],"terrain":[],"junctions":[],"relief":[],"rails":[],"bridges":[]}
	return data.chunks[key]

static func apply(data: Dictionary,legacy: Array) -> Dictionary:
	var started:=Time.get_ticks_usec()
	var mask:=Geometry.new();mask.prepare(data.terrain)
	var spans:=mask.build(data.roads)
	var removed:=_old_wall_ids(data,legacy)
	var remap: Dictionary={};var walls: Array=[]
	for i in data.walls.size():
		if removed.has(i):continue
		remap[i]=walls.size();walls.append(data.walls[i])
	for chunk in data.chunks.values():
		var kept: Array=[]
		for id in chunk.walls:
			if remap.has(int(id)):kept.append(remap[int(id)])
		chunk.walls=kept;chunk["bridges"]=[]
	data.walls=walls;data.bridges=spans;data["bridge_wall_indices"]=[]
	var extent:=Vector2(data.size[0],data.size[1]);var size_m:=float(data.chunk_size)
	for id in spans.size():
		var bridge: Dictionary=spans[id]
		var path:=PackedVector2Array()
		for p in bridge.points:path.append(Geometry.v(p))
		for key in _cells(Geometry.bounds(path).grow(Geometry.rail_offset(bridge)+7),size_m,extent):_chunk(data,key).bridges.append(id)
		for rail in Geometry.rail_paths(bridge,data.junctions):
			for i in range(1,rail.size()):
				var a:=rail[i-1];var b:=rail[i]
				var count:=maxi(1,ceili(a.distance_to(b)/12.0))
				for j in count:
					var p:=a.lerp(b,float(j)/count);var q:=a.lerp(b,float(j+1)/count)
					var index: int=data.walls.size()
					data.walls.append([[p.x,p.y],[q.x,q.y]]);data.bridge_wall_indices.append(index)
					for key in _cells(Geometry.bounds(PackedVector2Array([p,q])).grow(.15),size_m,extent):_chunk(data,key).walls.append(index)
	data["bridge_generation"]=Geometry.VERSION
	return {"spans":spans.size(),"removed_legacy_rails":removed.size(),"rail_segments":data.bridge_wall_indices.size(),"build_usec":Time.get_ticks_usec()-started}
