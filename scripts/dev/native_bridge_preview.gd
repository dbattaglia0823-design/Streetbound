extends RefCounted
## Incremental preview: retain the real high-resolution shore until edited,
## and regenerate only changed roads. No archive writes or physics changes.
const Geometry=preload("res://scripts/world/road_bridge_geometry.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
var mask:=Geometry.new()
var water_key:=""
var cache: Dictionary={}
var by_road: Dictionary={}
var hidden: Dictionary={}
var redraw_roads: Dictionary={}
var generation_count:=0

static func terrain_for_source(base: Array,doc: Dictionary,initial: Dictionary) -> Array:
	var originals: Dictionary={};var current: Dictionary={}
	for item in initial.get("regions",[]):originals[str(item.id)]=item
	for item in doc.get("regions",[]):current[str(item.id)]=item
	var result: Array=[]
	for i in base.size():
		var id: String=str(base[i].get("authoring_id","region-%d"%i))
		if current.has(id) and originals.has(id) and JSON.stringify(current[id])!=JSON.stringify(originals[id]):
			var region: Dictionary=current[id];var points: Array=[]
			for p in region.points:points.append([p.x,p.y])
			result.append({"kind":str(region.biome),"points":points})
		else:result.append(base[i])
	for region in doc.get("regions",[]):
		if originals.has(str(region.id)):continue
		var points: Array=[]
		for p in region.points:points.append([p.x,p.y])
		result.append({"kind":str(region.biome),"points":points})
	return result

static func _same(a: Array,b: Array) -> bool:
	if a.size()!=b.size():return false
	for i in a.size():
		if a[i].points.size()!=b[i].points.size() or absf(float(a[i].width)-float(b[i].width))>.002:return false
		for j in a[i].points.size():
			if Geometry.v(a[i].points[j]).distance_to(Geometry.v(b[i].points[j]))>.01:return false
	return true

func update(base: Dictionary,doc: Dictionary,initial: Dictionary) -> void:
	var next_water:=JSON.stringify(doc.get("regions",[])).sha256_text()
	if next_water!=water_key:
		water_key=next_water;mask.prepare(terrain_for_source(base.terrain,doc,initial));cache.clear()
	var terrain_changed: bool=JSON.stringify(doc.get("regions",[]))!=JSON.stringify(initial.get("regions",[]))
	var originals: Dictionary={}
	for road in initial.get("roads",[]):originals[str(road.id)]=road
	by_road={};hidden={};redraw_roads={}
	for item in doc.get("roads",[]):
		var id:=int(str(item.id).trim_prefix("road-"))
		var changed: bool=not originals.has(str(item.id)) or JSON.stringify(item)!=JSON.stringify(originals[str(item.id)])
		if not changed and not terrain_changed:continue
		var key:=JSON.stringify(item).sha256_text()
		if not cache.has(id) or cache[id].key!=key:
			var road: Dictionary={}
			if not changed and id<base.roads.size():road=base.roads[id]
			else:
				var points: Array=[]
				for p in Session.road_path(item):points.append([p.x,p.y])
				road={"id":id,"points":points,"width":float(item.width)/float(doc.get("morrowRoadWidthScale",1))*float(base.get("road_width_scale",1)),
					"kind":{"city":"local","country":"rural","service":"driveway"}.get(str(item.roadClass),str(item.roadClass))}
			cache[id]={"key":key,"spans":mask.spans_for_road(road)};generation_count+=1
		var spans: Array=cache[id].spans
		var original_spans: Array=[]
		for bridge in base.bridges:
			if int(bridge.road)==id:original_spans.append(bridge)
		if changed or not _same(spans,original_spans):
			by_road[id]=spans;hidden[id]=true
			if not changed:redraw_roads[id]=true
