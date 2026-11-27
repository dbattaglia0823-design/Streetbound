extends RefCounted
## Source-based authoring estimates, not measured frame times.
const KINDS := ["fuel","garage","race","contract"]

static func _cell(at: Vector2, size: float) -> Vector2i:
	return Vector2i(floori(at.x/size),floori(at.y/size))

static func _point(raw: Dictionary) -> Vector2:
	return Vector2(float(raw.get("x",0)),float(raw.get("y",0)))

static func _entry(cells: Dictionary,key: Vector2i) -> Dictionary:
	if not cells.has(key):
		cells[key]={"road_m":0.0,"props":0,"junctions":0,"missing":[],"score":0.0}
	return cells[key]

static func analyze(doc: Dictionary,size: float=400.0,coverage_m: float=800.0,junctions: Array=[]) -> Dictionary:
	size=maxf(100.0,size)
	var bounds:=Vector2(float(doc.world.width),float(doc.world.height))
	var cells: Dictionary={}
	var facilities: Dictionary={"fuel":[],"garage":[],"race":[],"contract":[]}
	for marker in doc.get("markers",[]):
		if not bool(marker.get("properties",{}).get("enabled",true)):continue
		var kind:=str(marker.get("type",""))
		if kind in ["fuel","garage"]:facilities[kind].append(_point(marker))
		elif kind=="contract_contact" and not marker.get("properties",{}).get("offers",[]).is_empty():facilities.contract.append(_point(marker))
		elif kind=="contract" and not str(marker.get("properties",{}).get("destination_marker_id","")).is_empty():facilities.contract.append(_point(marker))
	for race in doc.get("races",[]):
		if not race.get("points",[]).is_empty():facilities.race.append(_point(race.points[0]))
	for road in doc.get("roads",[]):
		var points: Array=road.get("points",[])
		for i in range(1,points.size()):
			var a:=_point(points[i-1]);var b:=_point(points[i])
			var length:=a.distance_to(b)
			var steps:=maxi(1,ceili(length/(size*.25)))
			for j in steps:
				var key:=_cell(a.lerp(b,(float(j)+.5)/steps),size)
				_entry(cells,key).road_m+=length/steps
	for prop in doc.get("props",[]):
		if not bool(prop.get("hidden",false)):
			_entry(cells,_cell(_point(prop),size)).props+=1
	for junction in junctions:
		var p: Array=junction.get("p",[])
		if p.size()==2:
			_entry(cells,_cell(Vector2(float(p[0]),float(p[1])),size)).junctions+=maxi(1,junction.get("approaches",[]).size())
	for key in cells:
		var row: Dictionary=cells[key]
		var center:=Vector2(key)*size+Vector2.ONE*size*.5
		center=center.clamp(Vector2.ZERO,bounds)
		if float(row.road_m)>0.0:
			for kind in KINDS:
				var covered:=false
				for at in facilities[kind]:
					if center.distance_to(at)<=coverage_m:covered=true;break
				if not covered:row.missing.append(kind)
		row.score=float(row.props)+float(row.road_m)/50.0+float(row.junctions)*4.0
	return {"cells":cells,"size":size,"bounds":bounds,"coverage_m":coverage_m}

## A conservative time-trial route. Reject disconnected or non-local endpoints,
## and reject mixed-height routes until checkpoint grades can be assigned safely.
static func checkpoints(route: Dictionary,graph: RefCounted,layer: int) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	if route.is_empty() or float(route.get("start_access_distance_m",INF))>15.0 or float(route.get("access_distance_m",INF))>15.0:return result
	for id in route.get("edges",[]):
		var edge: Dictionary=graph.edges[int(id)]
		if absf(float(edge.get("start_height_m",0))-layer*6.0)>.1 or absf(float(edge.get("end_height_m",0))-layer*6.0)>.1:return result
	var path: PackedVector2Array=route.get("points_m",PackedVector2Array())
	if path.size()<2 or float(route.get("length_m",0))<20.0:return result
	var interval:=maxf(25.0,float(route.length_m)/90.0)
	result.append(path[0])
	var travel:=0.0
	for i in range(1,path.size()):
		travel+=path[i-1].distance_to(path[i])
		if travel>=interval and result[-1].distance_to(path[i])>=5.0:
			result.append(path[i]);travel=0.0
	if result[-1].distance_to(path[-1])>=5.0:result.append(path[-1])
	elif result.size()>1:result[-1]=path[-1]
	if result.size()<2 or result.size()>100:result.clear()
	return result


## Use the exact directed graph spans, not nearest-XY guesses at stacked roads.
## Intermediate gates are placed only on supported, essentially level pavement.
static func graded_checkpoints(route: Dictionary,graph: RefCounted,start_layer: int,finish_layer: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if graph==null or route.is_empty() or float(route.get("length_m",0))<20.0:return result
	if float(route.get("start_access_distance_m",INF))>15.0 or float(route.get("access_distance_m",INF))>15.0:return result
	var spans: Array=route.get("spans",[])
	if spans.is_empty():return result
	var first: Dictionary=spans[0]
	var last: Dictionary=spans[-1]
	var start: Dictionary=graph.point_on_edge(int(first.edge),float(first.begin))
	var finish: Dictionary=graph.point_on_edge(int(last.edge),float(last.end))
	if absf(float(start.height_m)-start_layer*6.0)>.2 or absf(float(finish.height_m)-finish_layer*6.0)>.2:return result
	var interval:=maxf(25.0,float(route.length_m)/80.0)
	var start_m: Vector2=start.position/20.0
	var finish_m: Vector2=finish.position/20.0
	result.append({"position":start_m,"layer":start_layer})
	var distance:=0.0
	var last_gate_station:=0.0
	for span in spans:
		var edge: Dictionary=graph.edges[int(span.edge)]
		var span_m:=maxf(0.0,float(span.end)-float(span.begin))/20.0
		var steps:=maxi(1,ceili(span_m/5.0))
		for i in range(1,steps+1):
			var fraction:=float(i)/steps
			var station:=distance+span_m*fraction
			if station-last_gate_station<interval or float(route.length_m)-station<8.0 or bool(edge.connector):continue
			var sample: Dictionary=graph.point_on_edge(int(span.edge),lerpf(float(span.begin),float(span.end),fraction))
			var layer:=int(sample.road_layer)
			if absf(float(sample.height_m)-layer*6.0)>.2:continue
			var point: Vector2=sample.position/20.0
			if point.distance_to(result[-1].position)<5.0 or point.distance_to(finish_m)<5.0:continue
			result.append({"position":point,"layer":layer})
			last_gate_station=station
		distance+=span_m
	if finish_m.distance_to(result[-1].position)<5.0 or result.size()>=100:return []
	result.append({"position":finish_m,"layer":finish_layer})
	return result
