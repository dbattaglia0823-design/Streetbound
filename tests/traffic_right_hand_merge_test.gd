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
	print("RIGHT HAND MERGE LANES: ", "PASS" if failures.is_empty() else
		"FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
