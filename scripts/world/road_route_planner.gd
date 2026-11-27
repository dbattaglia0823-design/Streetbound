extends RefCounted
## Shortest directed road routes with exact partial first/last lane segments.
## Used by free-roam waypoints and data-authored street events.
const Elevation=preload("res://scripts/world/road_elevation.gd")
const PPM:=20.0
const MAX_ACCESS_M:=250.0
# Prefer nearby driveable access points, widening only if disconnected.
const LOCAL_ACCESS_MARGIN_M:=10.0
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

func _candidates(at: Vector2, heading: Vector2, road_name: String, road_layer: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary]=[]
	for edge in network.edges:
		if bool(edge.connector):continue
		if not road_name.is_empty() and str(data.roads[int(edge.road)].name)!=road_name:continue
		var best:=INF;var progress:=0.0;var nearest:=Vector2.ZERO;var tangent:=Vector2.ZERO
		for i in range(1,edge.points.size()):
			var a: Vector2=edge.points[i-1];var b: Vector2=edge.points[i]
			var segment:=b-a
			if segment.length_squared()<.0001:continue
			var t:=clampf((at-a).dot(segment)/segment.length_squared(),0,1)
			var p:=a+segment*t
			var distance:=at.distance_squared_to(p)
			if distance<best:
				best=distance;nearest=p;tangent=segment.normalized()
				progress=float(edge.stations[i-1])+segment.length()*t
		if best==INF or Elevation.layer_for_height(Elevation.edge_height_at(edge,progress))!=road_layer:continue
		var distance:=sqrt(best)
		if road_name.is_empty() and distance>PPM*MAX_ACCESS_M:continue
		# A lane's cost is distance actually traveled, not road rank, speed or
		# direction penalties. Heading only resolves ties when equally close.
		var facing:=0.0 if heading==Vector2.ZERO else heading.normalized().dot(tangent)
		candidates.append({"edge":int(edge.id),"progress":progress,"nearest":nearest,
			"distance":distance,"score":distance,"facing":facing})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		if float(a.distance)==float(b.distance):
			return float(a.facing)>float(b.facing)
		return float(a.distance)<float(b.distance))
	# Never truncate to the six nearest lanes: they may all be disconnected.
	return candidates

func _local_candidates(candidates: Array[Dictionary],margin_m: float=LOCAL_ACCESS_MARGIN_M) -> Array[Dictionary]:
	var nearby: Array[Dictionary]=[]
	if candidates.is_empty():return nearby
	var radius:=float(candidates[0].distance)+margin_m*PPM
	for item in candidates:
		if float(item.distance)>radius:break
		nearby.append(item)
	return nearby

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
		start_road: String="",finish_road: String="", start_layer: int=0, finish_layer: int=0) -> Dictionary:
	if network==null or not from_m.is_finite() or not target_m.is_finite():return {}
	var starts:=_candidates(from_m*PPM,heading,start_road,start_layer)
	var goals:=_candidates(target_m*PPM,Vector2.ZERO,finish_road,finish_layer)
	if starts.is_empty() or goals.is_empty():return {}
	# Keep both endpoints close to the real nearby road system so the GPS
	# cannot choose a huge off-road jump as a shortcut. If that neighborhood
	# is isolated, expand to any legal connection within the access radius.
	var local_goals:=_local_candidates(goals)
	var direct:=_shortest(_local_candidates(starts),local_goals)
	if not direct.is_empty():return direct
	# A disconnected neighborhood may require another nearby entry road.
	# Do NOT widen access all the way to 250 m: otherwise the solver could
	# "finish" hundreds of metres from the pin across undrivable terrain.
	var extended_starts:=_local_candidates(starts,100.0)
	var connected:=_shortest(extended_starts,local_goals)
	if not connected.is_empty():return connected
	return _shortest(extended_starts,_local_candidates(goals,60.0))

func _shortest(starts: Array[Dictionary],goals: Array[Dictionary]) -> Dictionary:
	var goal_edges: Dictionary={}
	for goal in goals:
		var key:=int(goal.edge)
		if not goal_edges.has(key):goal_edges[key]=[]
		goal_edges[key].append(goal)
	var distances: Dictionary={};var parents: Dictionary={};var roots: Dictionary={};var heap: Array=[]
	var best:=INF;var best_ids: Array[int]=[];var best_start: Dictionary={};var best_goal: Dictionary={}
	for start in starts:
		for goal in goal_edges.get(int(start.edge),[]):
			# No backwards travel on a directed lane, even when reversing
			# would be geometrically shorter. A legal loop can still reach it.
			if float(goal.progress)<float(start.progress):continue
			var score:=float(goal.progress)-float(start.progress)+float(start.score)+float(goal.score)
			if score<best:
				best=score;best_ids=[int(start.edge)];best_start=start;best_goal=goal
		var cost:=float(network.edges[int(start.edge)].length_px)-float(start.progress)+float(start.score)
		if cost<float(distances.get(int(start.edge),INF)):
			distances[int(start.edge)]=cost;parents[int(start.edge)]=-1;roots[int(start.edge)]=start
			_push(heap,[cost,int(start.edge)])
	# Multi-source Dijkstra minimizes measured lane and junction-connector
	# length. Nonnegative costs and a min-heap guarantee the shortest legal
	# path; every successor comes from the runtime directed traffic graph.
	while not heap.is_empty():
		var entry:=_pop(heap);var cost:=float(entry[0]);var id:=int(entry[1])
		if cost>float(distances.get(id,INF))+.001:continue
		if cost>best:break
		for raw_next in network.edges[id].next:
			var next:=int(raw_next)
			for goal in goal_edges.get(next,[]):
				var score:=cost+float(goal.progress)+float(goal.score)
				if score>=best:continue
				var sequence: Array[int]=[next];var cursor:=id
				while cursor>=0:
					sequence.push_front(cursor)
					cursor=int(parents[cursor])
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
		"start_access_distance_m":float(best_start.distance)/PPM,
		"road_destination_m":Vector2(best_goal.nearest)/PPM,
		"access_distance_m":float(best_goal.distance)/PPM}
