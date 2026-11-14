extends RefCounted
## Rebuild draft traffic off the UI thread. Gameplay keeps its saved graph;
## editor lanes use the exact same TrafficNetwork and current road geometry.
const Network=preload("res://scripts/world/traffic_network.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const RANK={"highway":5,"arterial":4,"rural":3,"mountain":3,"local":2}
var wanted_key:=""
var shown_key:=""
var running_key:=""
var job:=-1
var pending: Dictionary={}
var result: Dictionary={}
var network: RefCounted
var data: Dictionary={}

func request(base: Dictionary, doc: Dictionary, baseline: Dictionary) -> void:
	var roads_json:=JSON.stringify(doc.get("roads",[]))
	wanted_key="" if roads_json==JSON.stringify(baseline.get("roads",[])) else roads_json.sha256_text()
	if wanted_key.is_empty():
		shown_key="";network=null;data={}
	elif wanted_key!=shown_key and wanted_key!=running_key:
		pending={"base":base,"roads":doc.roads.duplicate(true),"initial":baseline.roads,
			"width_scale":float(doc.get("morrowRoadWidthScale",1.0))}

func is_current() -> bool:
	return not wanted_key.is_empty() and wanted_key==shown_key and network!=null

func poll() -> bool:
	var updated:=false
	if job>=0 and WorkerThreadPool.is_task_completed(job):
		WorkerThreadPool.wait_for_task_completion(job)
		job=-1
		if running_key==wanted_key:
			network=result.network;data=result.data;shown_key=running_key;updated=true
		result={};running_key=""
	if job<0 and not wanted_key.is_empty() and wanted_key!=shown_key and not pending.is_empty():
		var snapshot:=pending
		pending={};running_key=wanted_key
		job=WorkerThreadPool.add_task(func()->void:
			var fresh:=build_data(snapshot.base,snapshot.roads,snapshot.initial,snapshot.width_scale)
			var graph:=Network.new()
			graph.build(fresh)
			result={"data":fresh,"network":graph})
	return updated

func finish() -> void:
	if job>=0:
		WorkerThreadPool.wait_for_task_completion(job)
		job=-1

static func _point(raw: Array) -> Vector2:return Vector2(raw[0],raw[1])

static func build_data(base: Dictionary, source: Array, initial: Array, width_scale: float=1.0) -> Dictionary:
	var originals: Dictionary={}
	for road in initial:originals[str(road.id)]=road
	var roads: Array=[]
	for item in source:
		var id:=int(str(item.id).trim_prefix("road-"))
		var unchanged: bool=originals.has(str(item.id)) and JSON.stringify(originals[str(item.id)])==JSON.stringify(item)
		var road: Dictionary=base.roads[id].duplicate(true) if id<base.roads.size() else {}
		if not unchanged or road.is_empty():
			var points: Array=[]
			for p in Session.road_path(item):points.append([p.x,p.y])
			road={"id":id,"name":str(item.name),"points":points,
				"width":float(item.width)/width_scale*float(base.get("road_width_scale",1.0)),
				"lanes":int(item.lanes),"surface":str(item.surface).to_upper(),
				"kind":{"city":"local","country":"rural","service":"driveway"}.get(str(item.roadClass),str(item.roadClass))}
		if road.get("surface","") in ["CONCRETE","TRACK"]:road.surface="ASPHALT"
		# Endpoint identity follows geometry, including new/reversed road joins.
		for end in ["start","end"]:
			var p:=_point(road.points[0] if end=="start" else road.points[-1])
			road[end]="%.2f,%.2f"%[p.x,p.y]
		roads.append(road)
	return {"roads":roads,"junctions":_junctions(roads)}

static func _project(road: Dictionary, p: Vector2) -> float:
	var best:=INF
	var station:=0.0
	for i in range(1,road.points.size()):
		var a:=_point(road.points[i-1]);var b:=_point(road.points[i])
		var t:=clampf((p-a).dot(b-a)/maxf(.000001,(b-a).length_squared()),0,1)
		var distance:=p.distance_squared_to(a.lerp(b,t))
		if distance<best:best=distance;station=float(road._stations[i-1])+a.distance_to(b)*t
	return station

static func _sample(road: Dictionary, station: float) -> Vector2:
	var s:=clampf(station,0,road._stations[-1])
	var low:=0;var high: int=road.points.size()-1
	while high-low>1:
		var mid: int=(low+high)/2
		if road._stations[mid]<s:low=mid
		else:high=mid
	return _point(road.points[low]).lerp(_point(road.points[high]),
		(s-float(road._stations[low]))/maxf(.000001,float(road._stations[high])-float(road._stations[low])))

static func _event(events: Array, cells: Dictionary, p: Vector2, a: int, b: int) -> void:
	var cell:=Vector2i((p/8).floor())
	for x in range(cell.x-1,cell.x+2):
		for y in range(cell.y-1,cell.y+2):
			for index in cells.get(Vector2i(x,y),[]):
				if p.distance_to(events[index].point)<3:
					events[index].roads[a]=true;events[index].roads[b]=true;return
	if not cells.has(cell):cells[cell]=[]
	cells[cell].append(events.size())
	events.append({"point":p,"roads":{a:true,b:true}})

static func _junctions(roads: Array) -> Array:
	var grid: Dictionary={}
	var events: Array=[];var cells: Dictionary={};var tested: Dictionary={}
	for id in roads.size():
		var road: Dictionary=roads[id]
		var stations: Array[float]=[0.0]
		for i in range(1,road.points.size()):stations.append(stations[-1]+_point(road.points[i-1]).distance_to(_point(road.points[i])))
		road._stations=stations
		if not RANK.has(str(road.kind)) or road.surface in ["GRAVEL","DIRT"]:continue
		for i in range(1,road.points.size()):
			var a:=_point(road.points[i-1]);var b:=_point(road.points[i])
			var begin:=Vector2i((a.min(b)/32).floor());var end:=Vector2i((a.max(b)/32).floor())
			for x in range(begin.x,end.x+1):
				for y in range(begin.y,end.y+1):
					var key:=Vector2i(x,y)
					if not grid.has(key):grid[key]=[]
					for segment in grid[key]:
						if int(segment.road)==id:continue
						var pair:=Vector4i(id,i,int(segment.road),int(segment.index))
						if tested.has(pair):continue
						tested[pair]=true
						var crossing: Variant=Geometry2D.segment_intersects_segment(a,b,segment.a,segment.b)
						if crossing!=null:_event(events,cells,crossing,id,int(segment.road))
					grid[key].append({"road":id,"index":i,"a":a,"b":b})
	var junctions: Array=[]
	for event in events:
		var center: Vector2=event.point
		var arms: Array=[]
		for identity in event.roads:
			var road: Dictionary=roads[int(identity)]
			var station:=_project(road,center)
			for side in [-1,1]:
				var available: float=station if side<0 else float(road._stations[-1])-station
				if available<.5:continue
				arms.append({"road":int(identity),"side":side,"origin":station,"available":available,
					"direction":(_sample(road,station+side*minf(5,available))-center).normalized(),"width":float(road.width)})
		arms.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.width>b.width)
		var unique: Array=[]
		for arm in arms:
			var duplicate:=false
			for prior in unique:
				if Vector2(arm.direction).dot(prior.direction)>.998:duplicate=true;break
			if not duplicate:unique.append(arm)
		arms=unique
		if arms.size()<2:continue
		if arms.size()==2 and Vector2(arms[0].direction).dot(arms[1].direction)<-.94 and absf(float(arms[0].width)-float(arms[1].width))<.1:continue
		var mouth:=PackedVector2Array()
		for arm in arms:
			var clearance:=float(arm.width)*.5+6
			for other in arms:
				if other==arm:continue
				var cosine:=Vector2(arm.direction).dot(other.direction)
				var sine:=absf(Vector2(arm.direction).cross(other.direction))
				if cosine>0 and sine>.025:clearance=maxf(clearance,(float(other.width)*.5+float(arm.width)*.5*cosine)/sine+3)
			var road: Dictionary=roads[int(arm.road)]
			arm.station=float(arm.origin)+int(arm.side)*minf(40,minf(clearance,float(arm.available)*.7))
			var p:=_sample(road,float(arm.station))
			var direction:=(_sample(road,float(arm.station)+int(arm.side)*.4)-_sample(road,float(arm.station)-int(arm.side)*.4)).normalized()
			var normal:=Vector2(-direction.y,direction.x)*float(arm.width)*.5
			mouth.append(p+normal);mouth.append(p-normal)
			arm.control="stop" if arms.size()>=3 else "none"
			arm.p=[p.x,p.y];arm.direction=direction
			arm.erase("origin");arm.erase("available")
		for arm in arms:
			var direction: Vector2=arm.direction
			arm.direction=[direction.x,direction.y]
		var polygon: Array=[]
		for p in Geometry2D.convex_hull(mouth):polygon.append([p.x,p.y])
		var control:="none"
		if arms.size()>=3:
			var ranks: Array=[]
			for arm in arms:ranks.append(int(RANK[str(roads[int(arm.road)].kind)]))
			var all_way: bool=arms.size()>=4 and ranks.min()==ranks.max() and int(ranks.max())<=4
			var pair: Array=[];var score:=-INF
			for i in arms.size():
				for k in range(i+1,arms.size()):
					var dot:=_point(arms[i].direction).dot(_point(arms[k].direction))
					var same: bool=roads[int(arms[i].road)].name==roads[int(arms[k].road)].name
					if dot<-.45 or (same and dot<.3):
						var rank: float=mini(ranks[i],ranks[k])*100+(25 if same else 0)-dot*10
						if rank>score:score=rank;pair=[i,k]
			control="priority" if not pair.is_empty() and not all_way else "all_way_stop"
			if control=="priority":
				for index in pair:arms[index].control="none"
		junctions.append({"p":[center.x,center.y],"roads":event.roads.keys(),"approaches":arms,
			"polygon":polygon,"control":control,"kind":"draft","curbs":[]})
	for road in roads:road.erase("_stations")
	return junctions
