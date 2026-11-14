extends RefCounted
## Shortest directed road routes with exact partial first/last lane segments.
## Used by free-roam waypoints and data-authored street events.
const PPM:=20.0
const Lanes=preload("res://scripts/world/traffic_lane_geometry.gd")
var network: RefCounted
var data: Dictionary

func setup(graph: RefCounted, archive: Dictionary) -> void:
	network=graph;data=archive

func road_anchor(name: String, piece: int, fraction: float) -> Vector2:
	var matches: Array=[]
	for road in data.roads:
		if str(road.name)==name:matches.append(road)
	if matches.is_empty():return Vector2.INF
	var road: Dictionary=matches[clampi(piece,0,matches.size()-1)]
	var points:=PackedVector2Array();var stations:=PackedFloat64Array([0.0])
	for p in road.points:
		var point:=Vector2(p[0],p[1])
		if not points.is_empty():stations.append(stations[-1]+points[-1].distance_to(point))
		points.append(point)
	return network._position(points,stations,stations[-1]*clampf(fraction,0,1))

func _candidates(at: Vector2, heading: Vector2, road_name: String) -> Array[Dictionary]:
	var candidates: Array[Dictionary]=[]
	for edge in network.edges:
		if bool(edge.connector):continue
		if not road_name.is_empty() and str(data.roads[int(edge.road)].name)!=road_name:continue
		var best:=INF;var progress:=0.0;var nearest:=Vector2.ZERO;var tangent:=Vector2.ZERO
		for i in range(1,edge.points.size()):
			var a: Vector2=edge.points[i-1];var b: Vector2=edge.points[i]
			var segment:=b-a
			var t:=clampf((at-a).dot(segment)/maxf(.001,segment.length_squared()),0,1)
			var p:=a+segment*t
			var distance:=at.distance_squared_to(p)
			if distance<best:
				best=distance;nearest=p;tangent=segment.normalized()
				progress=float(edge.stations[i-1])+segment.length()*t
		var distance:=sqrt(best)
		if road_name.is_empty() and distance>PPM*250:continue
		var facing:=0.0 if heading==Vector2.ZERO else (1-heading.normalized().dot(tangent))*PPM*4
		candidates.append({"edge":int(edge.id),"progress":progress,"nearest":nearest,
			"distance":distance,"score":distance*3+facing})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return a.score<b.score)
	if candidates.size()>6:candidates.resize(6)
	return candidates

func _push(heap: Array, value: Array) -> void:
	heap.append(value)
	var index:=heap.size()-1
	while index>0:
		var parent: int=(index-1)/2
		if float(heap[parent][0])<=float(value[0]):break
		heap[index]=heap[parent];index=parent
	heap[index]=value

func _pop(heap: Array) -> Array:
	var first: Array=heap[0];var last: Array=heap.pop_back()
	if not heap.is_empty():
		var index:=0
		while index*2+1<heap.size():
			var child:=index*2+1
			if child+1<heap.size() and float(heap[child+1][0])<float(heap[child][0]):child+=1
			if float(last[0])<=float(heap[child][0]):break
			heap[index]=heap[child];index=child
		heap[index]=last
	return first

func plan(from_m: Vector2, target_m: Vector2, heading:=Vector2.ZERO,
		start_road: String="",finish_road: String="") -> Dictionary:
	if network==null or not from_m.is_finite() or not target_m.is_finite():return {}
	var starts:=_candidates(from_m*PPM,heading,start_road)
	var goals:=_candidates(target_m*PPM,Vector2.ZERO,finish_road)
	if starts.is_empty() or goals.is_empty():return {}
	var distances: Dictionary={};var parents: Dictionary={};var roots: Dictionary={};var heap: Array=[]
	var best:=INF;var best_ids: Array[int]=[];var best_start: Dictionary={};var best_goal: Dictionary={}
	for start in starts:
		for goal in goals:
			if int(start.edge)==int(goal.edge) and float(goal.progress)>=float(start.progress):
				var score:=float(goal.progress)-float(start.progress)+float(start.score)+float(goal.score)
				if score<best:best=score;best_ids=[int(start.edge)];best_start=start;best_goal=goal
		var cost:=float(network.edges[int(start.edge)].length_px)-float(start.progress)+float(start.score)
		if cost<float(distances.get(int(start.edge),INF)):
			distances[int(start.edge)]=cost;parents[int(start.edge)]=-1;roots[int(start.edge)]=start
			_push(heap,[cost,int(start.edge)])
	while not heap.is_empty():
		var entry:=_pop(heap);var cost:=float(entry[0]);var id:=int(entry[1])
		if cost>float(distances.get(id,INF))+.001:continue
		if cost>best:break
		for raw_next in network.edges[id].next:
			var next:=int(raw_next)
			for goal in goals:
				if next!=int(goal.edge):continue
				var score:=cost+float(goal.progress)+float(goal.score)
				if score>=best:continue
				var sequence: Array[int]=[next];var cursor:=id
				while cursor>=0:sequence.push_front(cursor);cursor=int(parents[cursor])
				best=score;best_ids=sequence;best_start=roots[id];best_goal=goal
			var proposed:=cost+float(network.edges[next].length_px)
			if proposed<float(distances.get(next,INF)):
				distances[next]=proposed;parents[next]=id;roots[next]=roots[id]
				_push(heap,[proposed,next])
	if best_ids.is_empty():return {}
	var points:=PackedVector2Array();var length:=0.0
	for i in best_ids.size():
		var edge: Dictionary=network.edges[best_ids[i]]
		var begin:=float(best_start.progress) if i==0 else 0.0
		var end:=float(best_goal.progress) if i==best_ids.size()-1 else float(edge.length_px)
		for p in Lanes.slice_path(edge.points,edge.stations,begin,end):
			if not points.is_empty() and points[-1].distance_to(p/PPM)<.01:continue
			if not points.is_empty():length+=points[-1].distance_to(p/PPM)
			points.append(p/PPM)
	if points.size()<2:return {}
	return {"points_m":points,"edges":best_ids,"length_m":length,
		"road_destination_m":Vector2(best_goal.nearest)/PPM,"access_distance_m":float(best_goal.distance)/PPM}
