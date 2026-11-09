extends RefCounted
## Shared metre-space geometry. Built once; both map views reuse these paths.
var data: Dictionary
var roads: Array[Dictionary] = []
var terrain: Array[Dictionary] = []
var chunk_terrain: Dictionary = {}
var extent := Vector2.ZERO

func _init(source: Dictionary) -> void:
	data = source
	extent = v(data.size)
	for r in data.roads:
		var path := path_of(r.points)
		roads.append({"source":r,"path":path,"bounds":bounds_of(path).grow(float(r.width)),"length":length_of(path)})
	for t in data.terrain:
		var path := path_of(t.points)
		terrain.append({"kind":str(t.kind),"color":Color(t.color),"path":path,"bounds":bounds_of(path)})

func v(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))

func path_of(raw: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p in raw: result.append(v(p))
	return result

func bounds_of(path: PackedVector2Array) -> Rect2:
	var result := Rect2(path[0],Vector2.ZERO)
	for p in path: result=result.expand(p)
	return result

func length_of(path: PackedVector2Array) -> float:
	var result := 0.0
	for i in range(1,path.size()): result+=path[i-1].distance_to(path[i])
	return result

func props_in(area: Rect2) -> Array[int]:
	var result: Array[int] = []
	var cell := float(data.chunk_size)
	for x in range(maxi(0,floori(area.position.x/cell)),mini(ceil(extent.x/cell),floori(area.end.x/cell)+1)):
		for y in range(maxi(0,floori(area.position.y/cell)),mini(ceil(extent.y/cell),floori(area.end.y/cell)+1)):
			var key := "%d,%d" % [x,y]
			for index in data.chunks.get(key,{}).get("props",[]): result.append(int(index))
	return result

func terrain_in(area: Rect2, overview: bool) -> Array[Dictionary]:
	if overview: return terrain
	var result: Array[Dictionary] = []
	var cell := float(data.chunk_size)
	for x in range(maxi(0,floori(area.position.x/cell)),mini(ceil(extent.x/cell),floori(area.end.x/cell)+1)):
		for y in range(maxi(0,floori(area.position.y/cell)),mini(ceil(extent.y/cell),floori(area.end.y/cell)+1)):
			var key := "%d,%d" % [x,y]
			if not chunk_terrain.has(key):
				var entries: Array[Dictionary] = []
				for t in data.chunks.get(key,{}).get("terrain",[]):
					entries.append({"kind":str(t.kind),"color":Color(t.color),"path":path_of(t.points)})
				chunk_terrain[key]=entries
			result.append_array(chunk_terrain[key])
	return result

func nearest_road(point: Vector2) -> String:
	var cell := float(data.surface_cell)
	var center := Vector2i((point/cell).floor())
	var best := 100.0
	var name := "Open countryside"
	for x in range(center.x-1,center.x+2):
		for y in range(center.y-1,center.y+2):
			for index in data.surface_index.get("%d,%d"%[x,y],[]):
				var segment: Dictionary = data.segments[int(index)]
				var distance := Geometry2D.get_closest_point_to_segment(point,v(segment.a),v(segment.b)).distance_to(point)
				if distance<best:
					best=distance
					name=str(data.roads[int(segment.road)].name)
	return name

func poi_type(poi: Dictionary) -> String:
	var category := str(poi.category)
	if category.contains("FUEL"): return "fuel"
	if category.contains("RACE") or category.contains("DRAG") or category.contains("RALLY"): return "race"
	if category.contains("CUSTOM"): return "workshop"
	if category.contains("DEALER"): return "dealer"
	if category.contains("GARAGE"): return "garage"
	if category.contains("MARINA"): return "marina"
	return "view"
