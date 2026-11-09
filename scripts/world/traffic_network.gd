extends RefCounted
## Streaming-friendly directional road graph for Morrow Coast traffic.
## One directed lane edge per road segment between real junction arms.
## Internal turn links are cubic splines, never straight shortcuts through
## painted intersections. Skips dirt/gravel and racing-track roads.
const PPM := 20.0
const SPEEDS := {"local": 36.0, "arterial": 51.0, "highway": 82.0,
	"rural": 60.0, "mountain": 34.0}
const CELL_M := 192.0
var edges: Array[Dictionary] = []
var candidate_grid: Dictionary = {}
var source_road_count := 0
var connector_count := 0


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
	edges.append(info)
	return id


func _lane_path(points: PackedVector2Array, stations: PackedFloat64Array,
		begin_m: float, end_m: float, direction: int, offset_m: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var distance_m := absf(end_m-begin_m)
	var steps := maxi(2,ceili(distance_m / 8.0))
	var base := PackedVector2Array()
	for i in range(steps+1):
		var station := lerpf(begin_m,end_m,float(i)/float(steps))
		base.append(_position(points,stations,station))
	if direction < 0:
		base.reverse()
	for i in base.size():
		var forward := (base[mini(i+1,base.size()-1)]-base[maxi(i-1,0)]).normalized()
		if forward.length_squared()<0.5:
			forward=Vector2.UP
		result.append((base[i]-forward.orthogonal()*offset_m)*PPM)
	return result


func _road_cuts(data: Dictionary, road: Dictionary, road_id: int, total: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = [
		{"station":0.0,"junction":-1,"side":0,"node":str(road.start)},
		{"station":total,"junction":-1,"side":0,"node":str(road.end)}
	]
	for j in data.junctions.size():
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


func build(data: Dictionary) -> void:
	edges.clear()
	candidate_grid.clear()
	connector_count=0
	source_road_count=data.roads.size()
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	var incoming_ends: Dictionary = {}
	var outgoing_ends: Dictionary = {}
	for road_id in data.roads.size():
		var road: Dictionary = data.roads[road_id]
		var kind := str(road.kind)
		if not SPEEDS.has(kind):
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
		var count := maxi(2,int(road.lanes))
		var forward_count := maxi(1,count/2)
		var reverse_count := maxi(1,count-forward_count)
		for i in range(1,cuts.size()):
			var a: Dictionary = cuts[i-1]
			var b: Dictionary = cuts[i]
			var span := float(b.station)-float(a.station)
			if span<4.0 or (int(a.junction)>=0 and a.junction==b.junction):
				continue
			for direction in [1,-1]:
				var lane_count: int = forward_count if direction>0 else reverse_count
				for lane in lane_count:
					var offset_m := float(road.width)/float(count)*(float(lane)+0.5)
					var path := _lane_path(points,stations,float(a.station),float(b.station),
						direction,offset_m)
					if path.size()<2:
						continue
					var start: Dictionary = a if direction>0 else b
					var ending: Dictionary = b if direction>0 else a
					var edge_id := _add_edge({
						"road":road_id,"direction":direction,"lane":lane,
						"lanes_in_direction":lane_count,"connector":false,
						"points":path,"speed_px":float(SPEEDS[kind])/3.6*PPM,
						"start_j":int(start.junction),"end_j":int(ending.junction),
						"start_side":int(start.side),"end_side":int(ending.side),
						"start_node":str(start.node),"end_node":str(ending.node),
						"control":str(ending.get("control","none")),
						"kind":kind
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
			if int(source.road)==int(target.road) and int(source.end_side)==int(target.start_side):
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
			var t0 := (p0-from_path[from_path.size()-2]).normalized()
			var t1 := (to_path[1]-p1).normalized()
			var handle := clampf(p0.distance_to(p1)*0.45,PPM*2.0,PPM*13.0)
			var c0 := p0+t0*handle
			var c1 := p1-t1*handle
			var path := PackedVector2Array()
			for i in 9:
				var t := float(i)/8.0
				var point := p0*pow(1.0-t,3.0)+c0*3.0*pow(1.0-t,2.0)*t+ \
					c1*3.0*(1.0-t)*t*t+p1*t*t*t
				path.append(point)
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
	var tangent := (points[high]-points[low]).normalized()
	return {"position":p,"tangent":tangent,"angle":tangent.angle()+PI*0.5}


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
