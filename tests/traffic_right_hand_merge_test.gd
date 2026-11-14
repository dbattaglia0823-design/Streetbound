extends SceneTree
## Regression for right-hand lanes and connected roads authored in opposite directions.
const Network = preload("res://scripts/world/traffic_network.gd")
const PPM := 20.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, good: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL", label, str(detail)])
	if not good:
		failures.append(label)


func road(name: String, start_node: String, end_node: String,
		start_x: float, end_x: float) -> Dictionary:
	return {"name": name, "start": start_node, "end": end_node,
		"kind": "local", "surface": "ASPHALT", "width": 12.0,
		"lanes": 2, "points": [[start_x, 300.0], [end_x, 300.0]]}


func find_lane(network: RefCounted, road_id: int, direction: int) -> Dictionary:
	for edge in network.edges:
		if not bool(edge.connector) and int(edge.road) == road_id and \
				int(edge.direction) == direction:
			return edge
	return {}


func _run() -> void:
	_check_cardinal_lanes()
	_check_intersection_lanes()
	var network := Network.new()
	network.build({"roads": [
		road("Eastbound drawn east", "west", "join", 100.0, 300.0),
		road("Eastbound drawn west", "east", "join", 500.0, 300.0)
	], "junctions": []})
	var east_a := find_lane(network, 0, 1)
	var west_a := find_lane(network, 0, -1)
	var east_b := find_lane(network, 1, -1)
	var west_b := find_lane(network, 1, 1)
	check("both_roads_have_two_directions",
		not east_a.is_empty() and not west_a.is_empty() and
		not east_b.is_empty() and not west_b.is_empty())
	if failures.is_empty():
		# In Godot's Y-down coordinate system the right of eastbound is
		# positive Y; the right of westbound is negative Y.
		for edge in [east_a, east_b]:
			var path: PackedVector2Array = edge.points
			check("eastbound_lane_is_on_south_side", path[0].y > 300.0 * PPM,
				path[0])
		for edge in [west_a, west_b]:
			var path: PackedVector2Array = edge.points
			check("westbound_lane_is_on_north_side", path[0].y < 300.0 * PPM,
				path[0])
		var a_end: Vector2 = east_a.points[-1]
		var b_start: Vector2 = east_b.points[0]
		check("reversed_road_join_same_traffic_side",
			a_end.distance_to(b_start) < PPM * 0.15,
			[a_end, b_start])
		var linked := false
		var route_stays_right := false
		for next_id in east_a.next:
			if int(next_id)==int(east_b.id):
				linked=true
				route_stays_right=east_a.points[-1].y>300*PPM and east_b.points[0].y>300*PPM
				continue
			var connector: Dictionary = network.edges[int(next_id)]
			if not bool(connector.connector):
				continue
			if connector.next.has(int(east_b.id)):
				linked = true
				route_stays_right = true
				for p in connector.points:
					if p.y < 300.0 * PPM:
						route_stays_right = false
		check("two_oppositely_drawn_roads_connect_forward", linked)
		check("join_connector_does_not_cross_into_oncoming_lane",
			route_stays_right)
		check("coincident_join_has_no_backtracking_cubic_loop",east_a.next.has(int(east_b.id)))
	print("RIGHT HAND MERGE LANES: ", "PASS" if failures.is_empty() else
		"FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)


func _check_cardinal_lanes() -> void:
	# Absolute compass expectations, independent of Godot's orthogonal().
	for fixture in [
		[Vector2(100,300),Vector2(500,300),Vector2.DOWN,"east"],
		[Vector2(500,300),Vector2(100,300),Vector2.UP,"west"],
		[Vector2(300,100),Vector2(300,500),Vector2.LEFT,"south"],
		[Vector2(300,500),Vector2(300,100),Vector2.RIGHT,"north"]]:
		for count in [2,4,6]:
			var start: Vector2 = fixture[0]
			var finish: Vector2 = fixture[1]
			var right: Vector2 = fixture[2]
			var network := Network.new()
			network.build({"roads":[{"name":"Compass","start":"a","end":"b",
				"kind":"highway","surface":"ASPHALT","width":18.0,"lanes":count,
				"points":[[start.x,start.y],[finish.x,finish.y]]}],"junctions":[]})
			var correct: bool = network.edges.size()==count
			for edge in network.edges:
				var side := right*int(edge.direction)
				var expected := 18.0/float(count)*(float(edge.lane)+0.5)*PPM
				for point in edge.points:
					correct = correct and absf((point-start*PPM).dot(side)-expected)<0.01
				var sample: Dictionary = network.point_on_edge(int(edge.id),float(edge.length_px)*0.5)
				correct = correct and Vector2.UP.rotated(float(sample.angle)).dot(sample.tangent)>0.999
			check("right_hand_%s_%d_lanes" % [fixture[3],count],correct)


func _check_intersection_lanes() -> void:
	var arms := []
	for id in 2:
		for side in [-1,1]:
			arms.append({"road":id,"side":side,"station":180.0 if side<0 else 220.0,
				"control":"stop"})
	var network := Network.new()
	network.build({"roads":[
		{"name":"Across","start":"w","end":"e","kind":"arterial","surface":"ASPHALT",
			"width":16.0,"lanes":4,"points":[[100,300],[500,300]]},
		{"name":"Down","start":"n","end":"s","kind":"arterial","surface":"ASPHALT",
			"width":16.0,"lanes":4,"points":[[300,100],[300,500]]}],
		"junctions":[{"control":"all_way_stop","approaches":arms}]})
	var legal := true
	var right_count := 0
	var left_count := 0
	var straight_count := 0
	for source in network.edges:
		if bool(source.connector):continue
		for id in source.next:
			var turn: Dictionary = network.edges[int(id)]
			var target: Dictionary = network.edges[int(turn.next[0])]
			legal = legal and turn.points[0].distance_to(source.points[-1])<0.01
			legal = legal and turn.points[-1].distance_to(target.points[0])<0.01
			match str(turn.turn):
				"left":
					left_count+=1
					legal = legal and int(source.lane)==0 and int(target.lane)==0
				"straight":
					straight_count+=1
					legal = legal and int(source.lane)==int(target.lane)
				"right":
					right_count+=1
					legal = legal and int(source.lane)==1 and int(target.lane)==1
					var approach: Vector2 = (source.points[-1]-source.points[-2]).normalized()
					var exit: Vector2 = (target.points[1]-target.points[0]).normalized()
					for point in turn.points:
						var relative: Vector2 = point-Vector2(300,300)*PPM
						legal = legal and relative.dot(Vector2(-approach.y,approach.x))>0
						legal = legal and relative.dot(Vector2(-exit.y,exit.x))>0
	check("four_way_turns_use_correct_lanes_and_join_continuously",legal)
	check("all_four_approaches_have_left_right_and_straight",right_count==4 and left_count==4 and straight_count==8,
		[right_count,left_count,straight_count])
