extends RefCounted
## Streaming-friendly directional road graph for Morrow Coast traffic.
## One directed lane edge per road segment between real junction arms.
## Internal turn links are cubic splines, never straight shortcuts through
## painted intersections. Skips dirt/gravel and racing-track roads.
const PPM := 20.0
const Lanes=preload("res://scripts/world/traffic_lane_geometry.gd")
const SPEEDS := {"local": 36.0, "arterial": 51.0, "highway": 82.0,
	"rural": 60.0, "mountain": 34.0}
const CELL_M := 192.0
var edges: Array[Dictionary] = []
var candidate_grid: Dictionary = {}
var source_road_count := 0
var connector_count := 0
var rejected_connector_count:=0
var junction_geometry: Dictionary={}
var road_geometry: Dictionary={}


func _raw_point(p: Array) -> Vector2:
	return Vector2(float(p[0]),float(p[1]))


func _position(points: PackedVector2Array, stations: PackedFloat64Array, s: float) -> Vector2:
	var target := clampf(s,0.0,stations[stations.size()-1])
	var low := 0
	var high := stations.size()-1
	while high-low > 1:
		var mid := (low+high)/2
		if stations[mid] < target:
			low=mid
		else:
			high=mid
	var d := maxf(stations[high]-stations[low],0.0001)
	return points[low].lerp(points[high],clampf((target-stations[low])/d,0.0,1.0))


func _add_edge(info: Dictionary) -> int:
	var id := edges.size()
	info["id"]=id
	info["next"]=Array()
	var distances := PackedFloat64Array([0.0])
	var path: PackedVector2Array = info.points
	for i in range(1,path.size()):
		distances.append(distances[distances.size()-1]+path[i-1].distance_to(path[i]))
	info["stations"]=distances
	info["length_px"]=float(distances[distances.size()-1])
	var caps:=PackedFloat64Array()
	for i in path.size():
		var cap:=float(info.speed_px)
		if i>0 and i<path.size()-1:
			var a: Vector2=path[i]-path[i-1]
			var b: Vector2=path[i+1]-path[i]
			var denominator:=a.length()*b.length()*(a+b).length()
			var curvature:=2*absf(a.cross(b))/maxf(.001,denominator)
			if curvature>.000001:
				# Comfort grip and yaw limits derive from the actual lane bend.
				cap=minf(cap,minf(sqrt(3.4*PPM/curvature),1.25/curvature))
		caps.append(cap)
	info["curve_caps"]=caps
	edges.append(info)
	return id


func _lane_path(points: PackedVector2Array, stations: PackedFloat64Array,
		begin_m: float, end_m: float, direction: int, offset_m: float) -> PackedVector2Array:
	var base:=Lanes.slice_path(Lanes.offset_path(points,offset_m),stations,begin_m,end_m)
	if direction < 0:
		base.reverse()
	for i in base.size():base[i]*=PPM
	return base


func _road_cuts(data: Dictionary, road: Dictionary, road_id: int, total: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"station":0.0,"junction":-1,"side":0,"node":str(road.start)},
		{"station":total,"junction":-1,"side":0,"node":str(road.end)}
	]
	for j in data.junctions.size():
		# A junction mouth owns the whole road end, including the centre node.
		# Leaving the centre as a second endpoint built short lanes INSIDE the
		# junction, then connected them again: turns cut diagonally over kerbs.
		var junction: Dictionary=data.junctions[j]
		var includes_road:=false
		for identity in junction.get("roads",[]):
			if int(identity)==road_id:includes_road=true;break
		if junction.has("p") and includes_road:
			var center:=_raw_point(junction.p)
			for index in [0,1]:
				var endpoint: Array=road.points[0] if index==0 else road.points[-1]
				if _raw_point(endpoint).distance_to(center)<.5:
					result[index]["junction"]=j
					result[index]["node"]=""
		for arm in data.junctions[j].approaches:
			if int(arm.road)!=road_id:
				continue
			var s := clampf(float(arm.station),0.0,total)
			if s<1.0 or total-s<1.0:
				continue
			result.append({"station":s,"junction":j,"side":int(arm.side),
				"node":"","control":str(arm.control)})
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return float(a.station)<float(b.station))
	# Near-duplicate junction cuts can leave zero-length lanes. Keep one
	# representative and let the junction connector do the turning.
	var clean: Array[Dictionary] = []
	for cut in result:
		if not clean.is_empty() and absf(float(cut.station)-float(clean[-1].station))<0.8:
			if int(cut.junction)>=0:
				clean[clean.size()-1]=cut
		else:
			clean.append(cut)
	return clean


func build(data: Dictionary, for_navigation: bool=false) -> void:
	edges.clear()
	candidate_grid.clear()
	connector_count=0
	rejected_connector_count=0
	junction_geometry.clear();road_geometry.clear()
	source_road_count=data.roads.size()
	for i in data.roads.size():
		var path:=PackedVector2Array()
		for p in data.roads[i].points:path.append(_raw_point(p)*PPM)
		road_geometry[i]={"points":path,"half_width":float(data.roads[i].width)*PPM*.5}
	for i in data.junctions.size():
		var junction: Dictionary=data.junctions[i]
		if not junction.has("polygon"):continue
		var polygon:=PackedVector2Array()
		for p in junction.polygon:polygon.append(_raw_point(p)*PPM)
		var segments: Array=[]
		var center:=_raw_point(junction.get("p",[0,0]))*PPM
		var radius:=0.0
		for p in polygon:radius=maxf(radius,center.distance_to(p))
		for identity in junction.get("roads",[]):
			var road: Dictionary=road_geometry[int(identity)]
			for k in range(1,road.points.size()):
				var a: Vector2=road.points[k-1];var b: Vector2=road.points[k]
				if center.distance_to(Geometry2D.get_closest_point_to_segment(center,a,b))<=radius+road.half_width+PPM*3:
					segments.append({"a":a,"b":b,"half_width":road.half_width})
		junction_geometry[i]={"polygon":polygon,"segments":segments}
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	var incoming_ends: Dictionary = {}
	var outgoing_ends: Dictionary = {}
	for road_id in data.roads.size():
		var road: Dictionary = data.roads[road_id]
		var kind := str(road.kind)
		if not SPEEDS.has(kind) and not (for_navigation and kind in ["driveway","track","gravel"]):
			continue
		if not for_navigation and str(road.get("surface","ASPHALT")) in ["GRAVEL","DIRT"]:
			continue
		var raw: Array = road.points
		if raw.size()<2:
			continue
		var points := PackedVector2Array()
		var stations := PackedFloat64Array()
		for p in raw:
			var point := _raw_point(p)
			if not points.is_empty() and point.distance_to(points[points.size()-1])<0.2:
				continue
			stations.append(0.0 if stations.is_empty() else
				stations[stations.size()-1]+points[points.size()-1].distance_to(point))
			points.append(point)
		if points.size()<2:
			continue
		var total := float(stations[stations.size()-1])
		var cuts := _road_cuts(data,road,road_id,total)
		var layout:=Lanes.layout(road)
		var forward_count:=int(layout.forward)
		var reverse_count:=int(layout.reverse)
		for i in range(1,cuts.size()):
			var a: Dictionary = cuts[i-1]
			var b: Dictionary = cuts[i]
			var span := float(b.station)-float(a.station)
			if span<4.0 or (int(a.junction)>=0 and a.junction==b.junction):
				continue
			for direction in [1,-1]:
				var lane_count: int = forward_count if direction>0 else reverse_count
				for lane in lane_count:
					var offset_m:=Lanes.lane_offset(road,direction,lane)
					var path := _lane_path(points,stations,float(a.station),float(b.station),
						direction,offset_m)
					if path.size()<2:
						continue
					var start: Dictionary = a if direction>0 else b
					var ending: Dictionary = b if direction>0 else a
					var edge_id := _add_edge({
						"road":road_id,"direction":direction,"lane":lane,
						"lanes_in_direction":lane_count,"connector":false,
						"points":path,"speed_px":float(SPEEDS.get(kind,25.0))/3.6*PPM,
						"start_j":int(start.junction),"end_j":int(ending.junction),
						"start_side":int(start.side),"end_side":int(ending.side),
						"start_node":str(start.node),"end_node":str(ending.node),
						"control":str(ending.get("control","none")),
						"kind":kind,"width_m":float(road.width)
					})
					if int(ending.junction)>=0:
						var j_key := int(ending.junction)
						if not incoming.has(j_key):incoming[j_key]=[]
						incoming[j_key].append(edge_id)
					elif str(ending.node)!="":
						if not incoming_ends.has(ending.node):incoming_ends[ending.node]=[]
						incoming_ends[ending.node].append(edge_id)
					if int(start.junction)>=0:
						var j_key := int(start.junction)
						if not outgoing.has(j_key):outgoing[j_key]=[]
						outgoing[j_key].append(edge_id)
					elif str(start.node)!="":
						if not outgoing_ends.has(start.node):outgoing_ends[start.node]=[]
						outgoing_ends[start.node].append(edge_id)
					_index_candidate(edge_id)

	for junction in incoming:
		_link_turns(incoming[junction],outgoing.get(junction,[]),int(junction),
			str(data.junctions[int(junction)].control))
	for endpoint in incoming_ends:
		if outgoing_ends.has(endpoint):
			_link_turns(incoming_ends[endpoint],outgoing_ends[endpoint],-1,"none")
	_mark_through_routes()

func _mark_through_routes() -> void:
	# Keep terminal lanes for inspection/recovery, but don't send ambient
	# traffic into a race-course entrance or a branch with no legal exit.
	var parents: Dictionary={};var remaining: Array[int]=[];var dead: Array[int]=[]
	for edge in edges:
		remaining.append(edge.next.size())
		edge["through_route"]=true
		if edge.next.is_empty():dead.append(int(edge.id))
		for next in edge.next:
			if not parents.has(int(next)):parents[int(next)]=[]
			parents[int(next)].append(int(edge.id))
	while not dead.is_empty():
		var id: int=dead.pop_back()
		edges[id].through_route=false
		for prior in parents.get(id,[]):
			remaining[int(prior)]-=1
			if remaining[int(prior)]==0:dead.append(int(prior))


func _index_candidate(id: int) -> void:
	var edge: Dictionary = edges[id]
	var length_px := float(edge.length_px)
	if length_px<PPM*24:
		return
	var steps := maxi(1,ceili(length_px/(CELL_M*0.65*PPM)))
	for i in range(steps+1):
		var location: Vector2 = point_on_edge(id,length_px*float(i)/float(steps)).position
		var cell := Vector2i((location/(CELL_M*PPM)).floor())
		var key := "%d,%d" % [cell.x,cell.y]
		if not candidate_grid.has(key):
			candidate_grid[key]=[]
		if not candidate_grid[key].has(id):
			candidate_grid[key].append(id)


func _turn_kind(from: Dictionary,into: Dictionary) -> String:
	var p: PackedVector2Array=from.points
	var q: PackedVector2Array=into.points
	var approach := (p[p.size()-1]-p[p.size()-2]).normalized()
	var exit := (q[1]-q[0]).normalized()
	var bend := approach.cross(exit)
	var dot := approach.dot(exit)
	if dot < -0.82:
		return "u_turn"
	if bend>0.25:
		return "right"
	if bend< -0.25:
		return "left"
	return "straight"


func _link_turns(from_ids: Array,to_ids: Array,junction: int,control: String) -> void:
	for from_id in from_ids:
		var source: Dictionary = edges[int(from_id)]
		for to_id in to_ids:
			var target: Dictionary = edges[int(to_id)]
			if junction>=0 and int(source.road)==int(target.road) and int(source.end_side)==int(target.start_side):
				continue
			if int(source.road)==int(target.road) and int(source.direction)!=int(target.direction):
				continue
			var turn := _turn_kind(source,target)
			if turn=="u_turn":
				continue
			var first_lane := int(source.lane)
			var first_count := int(source.lanes_in_direction)
			var target_lane := int(target.lane)
			var target_count := int(target.lanes_in_direction)
			# The outside lane turns right, inside lane turns left; a single
			# lane accepts all legal approaches.
			if turn=="left" and (first_lane!=0 or target_lane!=0):
				continue
			if turn=="right" and (first_lane!=first_count-1 or target_lane!=target_count-1):
				continue
			if turn=="straight" and target_lane!=mini(first_lane,target_count-1):
				continue
			var from_path: PackedVector2Array=source.points
			var to_path: PackedVector2Array=target.points
			var p0 := from_path[from_path.size()-1]
			var p1 := to_path[0]
			if junction<0 and p0.distance_to(p1)>PPM*(float(source.width_m)+float(target.width_m)):
				continue # A stale shared node name must never create an off-road shortcut.
			var t0 := (p0-from_path[from_path.size()-2]).normalized()
			var t1 := (to_path[1]-p1).normalized()
			if p0.distance_to(p1)<.1 and t0.dot(t1)>.98:
				# Coincident continuations need no artificial cubic loop.
				edges[int(from_id)]["next"].append(int(to_id))
				continue
			var path:=_fit_turn(p0,p1,t0,t1,junction)
			if path.is_empty():
				rejected_connector_count+=1
				continue
			var approach_control := str(source.control) if junction>=0 else "none"
			var turn_kph := 17.0 if turn in ["left","right"] else 29.0
			var id := _add_edge({
				"road":int(source.road),"direction":int(source.direction),"lane":first_lane,
				"lanes_in_direction":first_count,"connector":true,
				"points":path,"speed_px":minf(minf(float(source.speed_px),float(target.speed_px)),turn_kph/3.6*PPM),
				"start_j":junction,"end_j":junction,"start_side":int(source.end_side),
				"end_side":int(target.start_side),"start_node":"","end_node":"",
				"control":approach_control,"junction_control":control,
				"kind":"connector","turn":turn
			})
			edges[id]["next"]=[int(to_id)]
			edges[int(from_id)]["next"].append(id)
			connector_count+=1

func _paved(point: Vector2, domain: Dictionary) -> bool:
	if Geometry2D.is_point_in_polygon(point,domain.polygon):return true
	for segment in domain.segments:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,segment.a,segment.b))<=float(segment.half_width)+.5:return true
	return false

func _turn_fits(path: PackedVector2Array, domain: Dictionary) -> bool:
	for i in range(1,path.size()):
		var a:=path[i-1];var b:=path[i]
		var side:=Vector2(-(b-a).y,(b-a).x).normalized()*PPM*.98
		var steps:=maxi(1,ceili(a.distance_to(b)/PPM))
		for step in range(steps+1):
			var point:=a.lerp(b,float(step)/steps)
			if not _paved(point,domain) or not _paved(point+side,domain) or not _paved(point-side,domain):return false
	return true

func _fit_turn(p0: Vector2,p1: Vector2,t0: Vector2,t1: Vector2,junction: int) -> PackedVector2Array:
	var domain: Dictionary=junction_geometry.get(junction,{})
	for scale in [.45,.6,.8,.3,.15,.05]:
		var handle:=clampf(p0.distance_to(p1)*float(scale),PPM*.1,PPM*18)
		var c0:=p0+t0*handle;var c1:=p1-t1*handle
		var path:=PackedVector2Array()
		var steps:=maxi(24,ceili(p0.distance_to(p1)/(PPM*1.5)))
		for i in range(steps+1):
			var t:=float(i)/steps
			path.append(p0*pow(1-t,3)+c0*3*pow(1-t,2)*t+c1*3*(1-t)*t*t+p1*t*t*t)
		if domain.is_empty() or _turn_fits(path,domain):return path
	return PackedVector2Array()


func point_on_edge(edge_id: int, progress_px: float) -> Dictionary:
	var edge: Dictionary=edges[edge_id]
	var stations: PackedFloat64Array=edge.stations
	var points: PackedVector2Array=edge.points
	var offset := clampf(progress_px,0.0,float(edge.length_px))
	var low := 0
	var high := stations.size()-1
	while high-low>1:
		var middle := (low+high)/2
		if stations[middle] < offset:
			low=middle
		else:
			high=middle
	var delta := maxf(float(stations[high]-stations[low]),0.0001)
	var t := clampf((offset-stations[low])/delta,0.0,1.0)
	var p := points[low].lerp(points[high],t)
	# Blend adjacent route segments over a short travel interval. The old
	# per-segment tangent jumped visibly at every connector control point.
	var before: Vector2 = _position(points, stations, offset - PPM * 1.6)
	var after: Vector2 = _position(points, stations, offset + PPM * 1.6)
	var tangent := (after - before).normalized()
	if tangent.length_squared() < 0.1:
		tangent = (points[high] - points[low]).normalized()
	return {"position":p,"tangent":tangent,"angle":tangent.angle()+PI*0.5}


func curve_speed_limit(edge_id: int, progress_px: float, desired_px: float) -> float:
	var edge: Dictionary=edges[edge_id]
	var caps: PackedFloat64Array=edge.get("curve_caps",PackedFloat64Array())
	var stations: PackedFloat64Array=edge.stations
	var horizon:=maxf(PPM*12,desired_px*desired_px/(2*PPM*5.5)+PPM*5)
	var limit:=desired_px
	for i in range(stations.bsearch(progress_px-PPM*2),caps.size()):
		var ahead:=float(stations[i])-progress_px
		if ahead < -PPM*2:continue
		if ahead > horizon:break
		limit=minf(limit,sqrt(caps[i]*caps[i]+2*PPM*5.5*maxf(0,ahead-PPM*3)))
	return limit


func nearby_edges(position_px: Vector2,range_m := 350.0) -> Array[int]:
	var radius_cells := maxi(1,ceili(range_m/CELL_M))
	var center := Vector2i((position_px/(CELL_M*PPM)).floor())
	var found := {}
	for x in range(center.x-radius_cells,center.x+radius_cells+1):
		for y in range(center.y-radius_cells,center.y+radius_cells+1):
			var key := "%d,%d" % [x,y]
			for id in candidate_grid.get(key,[]):
				found[int(id)]=true
	var result: Array[int]=[]
	for id in found:
		result.append(int(id))
	return result


## Select a legal, forward-direction lane around a displaced traffic car.
## Nearest point + forward lookahead is computed on the baked directed graph,
## so recovery also works after crossing a junction or leaving the current
## road entirely. The vehicle physically steers to the lane, never teleports.
func recovery_target(position_px: Vector2, travel_heading: Vector2,
		preferred_edge: int = -1, lookahead_px: float = PPM * 9.0) -> Dictionary:
	var nearby: Array[int] = nearby_edges(position_px, 110.0)
	if preferred_edge >= 0 and preferred_edge < edges.size() and not nearby.has(preferred_edge):
		nearby.append(preferred_edge)
	var best_score := INF
	var best := {}
	var direction := travel_heading.normalized()
	for id in nearby:
		var edge: Dictionary = edges[id]
		if bool(edge.connector):
			continue
		var points: PackedVector2Array = edge.points
		var stations: PackedFloat64Array = edge.stations
		for i in range(1, points.size()):
			var a: Vector2 = points[i - 1]
			var b: Vector2 = points[i]
			var segment := b - a
			var len_sq := segment.length_squared()
			if len_sq < 0.01:
				continue
			var t := clampf((position_px - a).dot(segment) / len_sq, 0.0, 1.0)
			var p := a + segment * t
			var dist := position_px.distance_to(p)
			if dist > PPM * 55.0:
				continue
			var tangent := segment.normalized()
			var facing := tangent.dot(direction)
			# Never turn around into oncoming traffic just to choose a
			# closer sample. A current-edge exception allows side impacts
			# to temporarily rotate the car without losing its lane ID.
			if facing < -0.25 and id != preferred_edge:
				continue
			var score := dist + (1.0 - facing) * PPM * 2.0
			if id == preferred_edge:
				score -= PPM * 4.0
			if score < best_score:
				best_score = score
				var progress := float(stations[i - 1]) + sqrt(len_sq) * t
				best = {"edge":id,"progress":progress,"distance_px":dist,
					"nearest":p,"heading":tangent}
	if best.is_empty():
		return {}
	var chosen: Dictionary = edges[int(best.edge)]
	best.lookahead = point_on_edge(int(best.edge),minf(
		float(chosen.length_px) - 1.0,float(best.progress) + lookahead_px)).position
	return best
