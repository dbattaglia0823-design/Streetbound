extends SceneTree
const Network=preload("res://scripts/world/traffic_network.gd")
const Lanes=preload("res://scripts/world/traffic_lane_geometry.gd")
const Preview=preload("res://scripts/dev/native_traffic_preview.gd")
var failures: Array[String]=[]
var junction_grid: Dictionary={}
var archive: Dictionary

func _initialize() -> void:call_deferred("run")
func check(label: String, ok: bool, detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if ok else "FAIL",label,detail])
	if not ok:failures.append(label)
func point(p: Array) -> Vector2:return Vector2(p[0],p[1])

func paved(p: Vector2) -> bool:
	var cell:=Vector2i((p/float(archive.surface_cell)).floor())
	for index in archive.surface_index.get("%d,%d"%[cell.x,cell.y],[]):
		var segment: Dictionary=archive.segments[int(index)]
		var road: Dictionary=archive.roads[int(segment.road)]
		if str(road.surface) in ["DIRT","GRAVEL"]:continue
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p,point(segment.a),point(segment.b)))<=float(road.width)*.5+.05:return true
	for polygon in junction_grid.get(cell,[]):
		if Geometry2D.is_point_in_polygon(p,polygon):return true
	return false

func run() -> void:
	archive=JSON.parse_string(FileAccess.get_file_as_string("res://worlds/morrow-coast.world.json"))
	for junction in archive.junctions:
		var polygon:=PackedVector2Array()
		var bounds:=Rect2(point(junction.p),Vector2.ZERO)
		for p in junction.polygon:polygon.append(point(p));bounds=bounds.expand(point(p))
		var begin:=Vector2i((bounds.position/float(archive.surface_cell)).floor())
		var end:=Vector2i((bounds.end/float(archive.surface_cell)).floor())
		for x in range(begin.x,end.x+1):
			for y in range(begin.y,end.y+1):
				var cell:=Vector2i(x,y)
				if not junction_grid.has(cell):junction_grid[cell]=[]
				junction_grid[cell].append(polygon)
	var network:=Network.new()
	var start:=Time.get_ticks_msec()
	network.build(archive)
	print("NETWORK BUILD ms=",Time.get_ticks_msec()-start)
	var outside: Array=[];var samples:=0;var discontinuities:=0;var inside_stubs:=0
	for edge in network.edges:
		if not bool(edge.connector) and int(edge.start_j)>=0 and int(edge.start_j)==int(edge.end_j):inside_stubs+=1
		for next in edge.next:
			if Vector2(edge.points[-1]).distance_to(network.edges[int(next)].points[0])>.15:discontinuities+=1
		for i in range(1,edge.points.size()):
			var a: Vector2=edge.points[i-1]/20;var b: Vector2=edge.points[i]/20
			var steps:=maxi(1,ceili(a.distance_to(b)/2))
			for step in steps:
				var at:=a.lerp(b,float(step)/steps)
				var side:=Vector2(-(b-a).y,(b-a).x).normalized()*.95
				for p in [at,at+side,at-side]:
					samples+=1
					if not paved(p) and outside.size()<20:outside.append({"edge":edge.id,"point":p,"turn":edge.get("turn","lane")})
	check("all_current_traffic_paths_and_body_width_stay_on_real_pavement",outside.is_empty(),{"samples":samples,"outside":outside})
	check("all_lane_to_turn_connections_are_continuous",discontinuities==0,discontinuities)
	check("all_current_legal_turns_fit_without_dropping_connections",network.rejected_connector_count==0,network.rejected_connector_count)
	check("junction_centers_never_create_duplicate_internal_road_lanes",inside_stubs==0,inside_stubs)
	var terminals_avoided:=true
	for edge in network.edges:
		if edge.next.is_empty():terminals_avoided=terminals_avoided and not bool(edge.through_route)
	check("terminal_branches_are_excluded_from_ambient_through_traffic",terminals_avoided)
	for count in [1,2,3,4,5,6]:
		var road: Dictionary={"lanes":count,"width":18.0}
		var layout:=Lanes.layout(road);var valid:=true
		for direction in [1,-1]:
			for lane in int(layout.forward if direction>0 else layout.reverse):
				valid=valid and absf(Lanes.lane_offset(road,direction,lane))<=9-float(layout.width)*.49
		check("lane_centers_fit_%d_authored_lanes"%count,valid)
	var loop: Array=[]
	for i in 49:
		var p:=Vector2(200,200)+Vector2.from_angle(float(i)/48*TAU)*35
		loop.append([p.x,p.y])
	var circle:=Network.new()
	circle.build({"roads":[{"kind":"local","surface":"ASPHALT","name":"Loop","start":"same","end":"same","width":10,"lanes":2,"points":loop}],"junctions":[]})
	check("closed_road_traffic_continues_without_dead_end_or_fake_turn",circle.edges.size()==2 and circle.edges[0].next.has(0) and circle.edges[1].next.has(1))
	var road_doc: Array=[{"id":"road-0","name":"Main","roadClass":"city","surface":"asphalt","width":12,"lanes":2,"smooth":false,"points":[{"x":100,"y":200},{"x":500,"y":200}]},
		{"id":"road-1","name":"Side","roadClass":"city","surface":"asphalt","width":10,"lanes":2,"smooth":false,"points":[{"x":300,"y":100},{"x":300,"y":200}]}]
	var draft:=Preview.build_data({"roads":[]},road_doc,[])
	var edited:=Network.new();edited.build(draft)
	var lane_count:=0
	for edge in edited.edges:
		if not bool(edge.connector):lane_count+=1
	check("new_t_junction_has_only_external_lanes_and_all_six_turns",lane_count==6 and edited.connector_count==6,[lane_count,edited.connector_count])
	check("json_numeric_ids_keep_the_same_junction_topology",_json_topology(draft)==edited.edges.size())
	var corner:=Network.new()
	corner.build({"roads":[{"name":"Hairpin","kind":"mountain","surface":"ASPHALT","width":10,"lanes":2,"start":"a","end":"b","points":[[100,100],[130,100],[140,110],[140,125],[130,135],[100,135]]}],"junctions":[]})
	check("tight_curves_limit_speed_before_the_corner",corner.curve_speed_limit(0,28*20,35/3.6*20)<35/3.6*20)
	print("TRAFFIC ROAD ALIGNMENT: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)

func _json_topology(data: Dictionary) -> int:
	var graph:=Network.new();graph.build(JSON.parse_string(JSON.stringify(data)))
	return graph.edges.size()
