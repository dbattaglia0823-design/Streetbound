extends RefCounted
## Road/water intersections in metres. No road names, grades or sampled-vertex
## assumptions: even a two-point road can cross several narrow water bodies.
const WATER=["water","lake","ocean","river"]
const COSMETIC=["foam","riverbank"]
const CELL:=128.0
const APPROACH:=3.0
const VERSION:=1
const Lanes=preload("res://scripts/world/traffic_lane_geometry.gd")
var layers: Array[Dictionary]=[]
var water_bounds: Array[Rect2]=[]
var edges: Array[Dictionary]=[]
var edge_cells: Dictionary={}
var interior_cells: Dictionary={}

static func v(p: Array) -> Vector2:return Vector2(float(p[0]),float(p[1]))

static func bounds(path: PackedVector2Array) -> Rect2:
	if path.is_empty():return Rect2()
	var rect:=Rect2(path[0],Vector2.ZERO)
	for p in path:rect=rect.expand(p)
	return rect

func prepare(terrain: Array) -> void:
	layers.clear();water_bounds.clear();edges.clear();edge_cells.clear();interior_cells.clear()
	var water_seen:=false
	for raw in terrain:
		var kind:=str(raw.get("kind",raw.get("biome","")))
		water_seen=water_seen or kind in WATER
		if not water_seen or kind in COSMETIC:continue
		var path:=PackedVector2Array()
		for p in raw.points:path.append(v(p))
		if path.size()<3:continue
		var index:=layers.size();var rect:=bounds(path)
		layers.append({"path":path,"bounds":rect,"wet":kind in WATER})
		if kind in WATER:water_bounds.append(rect)
		for i in path.size():
			var a:=path[i];var b:=path[(i+1)%path.size()]
			if a.distance_squared_to(b)<.00000001:continue
			var id:=edges.size();edges.append({"a":a,"b":b,"layer":index})
			var first:=Vector2i((a.min(b)/CELL).floor());var last:=Vector2i((a.max(b)/CELL).floor())
			for y in range(first.y,last.y+1):
				for x in range(first.x,last.x+1):
					var key:=Vector2i(x,y)
					if not edge_cells.has(key):edge_cells[key]=[]
					edge_cells[key].append(id)

func _wet_raw(p: Vector2) -> bool:
	for i in range(layers.size()-1,-1,-1):
		var layer: Dictionary=layers[i]
		if not layer.bounds.grow(.0001).has_point(p) or not Geometry2D.is_point_in_polygon(p,layer.path):continue
		if not layer.wet:return false
		# Following a shore exactly is not an over-water crossing.
		for id in edge_cells.get(Vector2i((p/CELL).floor()),[]):
			var edge: Dictionary=edges[id]
			if int(edge.layer)==i and Geometry2D.get_closest_point_to_segment(p,edge.a,edge.b).distance_squared_to(p)<.00000001:return false
		return true
	return false

func is_water(p: Vector2) -> bool:
	var cell:=Vector2i((p/CELL).floor())
	if edge_cells.has(cell):return _wet_raw(p)
	if not interior_cells.has(cell):interior_cells[cell]=_wet_raw((Vector2(cell)+Vector2.ONE*.5)*CELL)
	return bool(interior_cells[cell])

func wet_intervals(path: PackedVector2Array) -> Array[Vector2]:
	var result: Array[Vector2]=[];var station:=0.0
	for i in range(1,path.size()):
		var a:=path[i-1];var b:=path[i];var delta:=b-a;var length:=delta.length()
		if length<.00001:continue
		var rect:=bounds(PackedVector2Array([a,b])).grow(.0001)
		var possible:=false
		for water in water_bounds:
			if water.intersects(rect,true):possible=true;break
		if not possible:station+=length;continue
		var candidates: Dictionary={}
		var first:=Vector2i((a.min(b)/CELL).floor());var last:=Vector2i((a.max(b)/CELL).floor())
		for y in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				for id in edge_cells.get(Vector2i(x,y),[]):candidates[id]=true
		var cuts: Array[float]=[0.0,1.0]
		for id in candidates:
			var edge: Dictionary=edges[id];var direction: Vector2=edge.b-edge.a
			var denominator:=delta.cross(direction)
			if absf(denominator)<.00000001:continue
			var relative: Vector2=edge.a-a
			var t:=relative.cross(direction)/denominator;var u:=relative.cross(delta)/denominator
			if t>0 and t<1 and u>=-.000001 and u<=1.000001:cuts.append(t)
		cuts.sort()
		for j in range(1,cuts.size()):
			var start:=cuts[j-1];var finish:=cuts[j]
			if (finish-start)*length<.0001 or not is_water(a+delta*((start+finish)*.5)):continue
			var span:=Vector2(station+start*length,station+finish*length)
			if not result.is_empty() and span.x-result[-1].y<.001:result[-1].y=span.y
			else:result.append(span)
		station+=length
	return result

static func slice_path(path: PackedVector2Array,start: float,finish: float) -> PackedVector2Array:
	var output:=PackedVector2Array();var station:=0.0
	for i in range(1,path.size()):
		var a:=path[i-1];var b:=path[i];var length:=a.distance_to(b)
		if length>.00001 and station+length>start+.00001 and station<finish-.00001:
			var p:=a.lerp(b,clampf((start-station)/length,0,1))
			var q:=a.lerp(b,clampf((finish-station)/length,0,1))
			if output.is_empty():output.append(p)
			if output[-1].distance_to(q)>.00001:output.append(q)
		station+=length
	return output

func spans_for_road(road: Dictionary) -> Array[Dictionary]:
	var path:=PackedVector2Array()
	for raw in road.points:path.append(v(raw))
	var length:=0.0
	for i in range(1,path.size()):length+=path[i-1].distance_to(path[i])
	var runs: Array[Dictionary]=[]
	for wet in wet_intervals(path):
		if wet.y-wet.x<.25:continue
		var start:=maxf(0,wet.x-APPROACH);var finish:=minf(length,wet.y+APPROACH)
		if not runs.is_empty() and start<=float(runs[-1].end)+.001:
			runs[-1].end=finish;runs[-1].wet_end=wet.y
		else:runs.append({"start":start,"end":finish,"wet_start":wet.x,"wet_end":wet.y})
	for run in runs:
		run.road=int(road.id);run.width=float(road.width);run.kind=str(road.get("kind","rural"))
		run.points=[]
		for p in slice_path(path,float(run.start),float(run.end)):run.points.append([p.x,p.y])
	return runs

func build(roads: Array) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for road in roads:result.append_array(spans_for_road(road))
	return result

static func rail_offset(bridge: Dictionary) -> float:
	return float(bridge.width)*.5+(3.8 if str(bridge.get("kind","")) in ["local","arterial"] else 1.4)

static func rail_paths(bridge: Dictionary,junctions: Array=[]) -> Array[PackedVector2Array]:
	var path:=PackedVector2Array()
	for raw in bridge.points:path.append(v(raw))
	var result: Array[PackedVector2Array]=[]
	for side in [-1,1]:
		var pieces: Array[PackedVector2Array]=[Lanes.offset_path(path,rail_offset(bridge)*side)]
		for junction in junctions:
			var polygon:=PackedVector2Array()
			for raw in junction.polygon:polygon.append(v(raw))
			if not bounds(path).grow(rail_offset(bridge)+3).intersects(bounds(polygon),true):continue
			var masks: Array[PackedVector2Array]=[polygon]
			for mask in masks:
				var next: Array[PackedVector2Array]=[]
				for piece in pieces:next.append_array(Geometry2D.clip_polyline_with_polygon(piece,mask))
				pieces=next
		result.append_array(pieces)
	return result
