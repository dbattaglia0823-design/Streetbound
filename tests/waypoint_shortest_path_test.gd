extends SceneTree
## Directed shortest-distance tests without loading the multi-gigabyte game world.
const Planner=preload("res://scripts/world/road_route_planner.gd")
var failures: Array[String]=[]

class FakeNetwork:
	extends RefCounted
	var edges: Array[Dictionary]=[]

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, ok: bool,detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if ok else "FAIL",label,detail])
	if not ok:failures.append(label)

func add_edge(graph: FakeNetwork, road: int, line: Array[Vector2], following: Array[int]=[]) -> int:
	var path:=PackedVector2Array()
	var stations:=PackedFloat64Array([0.0])
	for point in line:
		var pixel:=point*20.0
		if not path.is_empty():stations.append(stations[-1]+path[-1].distance_to(pixel))
		path.append(pixel)
	var id:=graph.edges.size()
	graph.edges.append({"id":id,"road":road,"connector":false,"points":path,
		"stations":stations,"length_px":stations[-1],"next":following.duplicate()})
	return id

func make_planner(graph: FakeNetwork,road_names: Array[String]) -> Variant:
	var roads: Array=[]
	for title in road_names:roads.append({"name":title})
	var planner:=Planner.new()
	planner.setup(graph,{"roads":roads})
	return planner

func valid_chain(graph: FakeNetwork,result: Dictionary) -> bool:
	if result.is_empty():return false
	var chosen: Array=result.edges
	for i in range(1,chosen.size()):
		if not (graph.edges[int(chosen[i-1])].next as Array).has(int(chosen[i])):
			return false
	return true

func _run() -> void:
	var graph:=FakeNetwork.new()
	# Two alternatives connect the same roads. The longer path occurs first
	# in the adjacency array to prove routing is based on length, not order.
	add_edge(graph,0,[Vector2(0,0),Vector2(20,0)],[2,1])
	add_edge(graph,1,[Vector2(20,0),Vector2(80,0)],[3])
	add_edge(graph,2,[Vector2(20,0),Vector2(20,80),Vector2(80,80),Vector2(80,0)],[3])
	add_edge(graph,3,[Vector2(80,0),Vector2(100,0)])
	var planner:=make_planner(graph,["START","SHORT","DETOUR","FINISH"])
	var shortest: Dictionary=planner.plan(Vector2(5,0),Vector2(95,0),Vector2.RIGHT,"START","FINISH")
	check("chooses_shorter_leg_not_first_junction",shortest.get("edges",[])==[0,1,3],shortest.get("edges",[]))
	check("uses_exact_partial_start_finish_edges",absf(float(shortest.get("length_m",0))-90.0)<.1,shortest.get("length_m",0))
	check("every_turn_is_a_legal_graph_successor",valid_chain(graph,shortest))
	check("lane_only_route_contains_no_cross_country_segment",shortest.get("points_m",PackedVector2Array()).size()>=4)
	# Eight nearer but disconnected lane candidates cannot hide the ninth.
	var many:=FakeNetwork.new()
	for i in 8:add_edge(many,i,[Vector2(0,i),Vector2(25,i)])
	add_edge(many,8,[Vector2(0,8),Vector2(25,8)],[9])
	add_edge(many,9,[Vector2(25,8),Vector2(195,8)],[10])
	add_edge(many,10,[Vector2(195,8),Vector2(215,8)])
	var names: Array[String]=[]
	for i in many.edges.size():names.append("Road %d"%i)
	var multi:=make_planner(many,names)
	var reachable: Dictionary=multi.plan(Vector2(0,0),Vector2(210,8))
	check("searches_past_six_disconnected_nearby_lanes",not reachable.is_empty() and int(reachable.edges[0])==8,reachable.get("edges",[]))
	check("connected_route_follows_authorized_edges",valid_chain(many,reachable))
	# A one-way lane cannot be followed backwards to save distance.
	var one_way:=FakeNetwork.new()
	add_edge(one_way,0,[Vector2(0,0),Vector2(100,0)])
	var single:=make_planner(one_way,["ONE WAY"])
	check("same_directed_lane_traverses_partially_forward",
		single.plan(Vector2(20,0),Vector2(80,0)).get("edges",[])==[0])
	check("no_reverse_drive_or_illegal_u_turn",
		single.plan(Vector2(90,0),Vector2(10,0)).is_empty())
	# Explicitly report the off-road last stretch instead of drawing an
	# invented driving shortcut straight across terrain or structures.
	var offroad: Dictionary=single.plan(Vector2(20,0),Vector2(80,18))
	check("offroad_destination_stays_on_real_road",
		not offroad.is_empty() and (offroad.points_m as PackedVector2Array)[-1].distance_to(Vector2(80,0))<.01)
	check("offroad_leg_distance_is_reported",absf(float(offroad.get("access_distance_m",-1))-18)<.1,
		offroad.get("access_distance_m",-1))
	# When the closest local road is isolated, widen the search but still
	# require legal graph continuity rather than jumping between networks.
	var alternate:=FakeNetwork.new()
	add_edge(alternate,0,[Vector2(0,0),Vector2(20,0)])
	add_edge(alternate,1,[Vector2(0,80),Vector2(200,80)])
	var fallback:=make_planner(alternate,["ISOLATED","CONNECTED"])
	var expanded: Dictionary=fallback.plan(Vector2(0,0),Vector2(190,80))
	check("farther_connected_road_found_after_local_search_fails",
		not expanded.is_empty() and expanded.get("edges",[])==[1],expanded.get("edges",[]))
	check("far_road_access_distance_is_not_hidden",
		absf(float(expanded.get("start_access_distance_m",0))-80)<.1)
	# Do not declare arrival on a disconnected destination road by ending a
	# long way away and pretending the last off-road gap is driveable.
	var remote:=FakeNetwork.new()
	add_edge(remote,0,[Vector2(0,0),Vector2(200,0)])
	add_edge(remote,1,[Vector2(200,100),Vector2(220,100)])
	var remote_planner:=make_planner(remote,["CONNECTED","REMOTE"])
	var unreachable: Dictionary=remote_planner.plan(Vector2(0,0),Vector2(215,100))
	check("no_remote_offroad_finish_disguised_as_a_short_route",unreachable.is_empty())

	print("WAYPOINT SHORTEST PATHS: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
