extends SceneTree
## Exercise a real directed 4-way stop, two competing approaches, a waiting
## follower and the interpolated connector spline in the Godot physics server.
const Network = preload("res://scripts/world/traffic_network.gd")
const Flow = preload("res://scripts/world/traffic_flow.gd")
const Car = preload("res://scripts/world/traffic_car.gd")
const PlayerScene = preload("res://scenes/vehicle.tscn")
const PPM := 20.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, valid: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if valid else "FAIL", label, detail])
	if not valid:
		failures.append(label)


func synthetic() -> Dictionary:
	var arms := []
	for road_id in 2:
		for side in [-1, 1]:
			arms.append({"road": road_id, "side": side,
				"station": 180.0 if side == -1 else 220.0,
				"control": "stop", "direction": [1, 0], "p": [300.0, 300.0]})
	return {
		"roads": [
			{"name": "West-East", "start": "w", "end": "e", "kind": "local",
				"surface": "ASPHALT", "width": 10.0, "lanes": 2,
				"points": [[100.0, 300.0], [500.0, 300.0]]},
			{"name": "North-South", "start": "n", "end": "s", "kind": "local",
				"surface": "ASPHALT", "width": 10.0, "lanes": 2,
				"points": [[300.0, 100.0], [300.0, 500.0]]}
		],
		"junctions": [{"p": [300.0, 300.0], "approaches": arms,
			"control": "all_way_stop", "roads": [0, 1], "kind": "crossroads"}]
	}


func make_car(at: Vector2, rotation_value: float) -> CharacterBody2D:
	var body := CharacterBody2D.new()
	body.set_script(Car)
	body.position = at
	body.rotation = rotation_value
	root.add_child(body)
	return body


func make_agent(network: RefCounted, edge_id: int, uid: int,
		back_m: float) -> Dictionary:
	var edge: Dictionary = network.edges[edge_id]
	var progress := float(edge.length_px) - PPM * back_m
	var sample: Dictionary = network.point_on_edge(edge_id, progress)
	var body := make_car(sample.position, float(sample.angle))
	return {"uid": uid, "node": body, "edge": edge_id,
		"progress": progress, "speed": PPM * 5.0, "cruise": PPM * 7.5,
		"next": -2, "stop_wait": 0.0, "stop_done": false,
		"recovery_time": 0.0, "recovery_refresh": 0.0, "recovery_goal": {},
		"obstacle_scan_clock": 0.0, "obstacle_position": Vector2.INF}


func run() -> void:
	var network = Network.new()
	network.build(synthetic())
	var entrances: Array[int] = []
	var left_turn_id := -1
	for i in network.edges.size():
		var edge: Dictionary = network.edges[i]
		if bool(edge.connector):
			if str(edge.turn) == "left" and left_turn_id < 0:
				left_turn_id = i
		elif int(edge.end_j) == 0 and int(edge.direction) == 1:
			entrances.append(i)
	check("two_crossing_approaches", entrances.size() == 2, entrances)
	check("left_turn_connector_available", left_turn_id >= 0)
	if entrances.size() < 2 or left_turn_id < 0:
		quit(1)
		return
	var connector: Dictionary = network.edges[left_turn_id]
	var points: PackedVector2Array = connector.points
	check("turn_spline_has_dense_vertices", points.size() >= 25, points.size())
	var max_angle_jump := 0.0
	var last_heading := float(network.point_on_edge(left_turn_id, 0.0).angle)
	for step in 60:
		var distance := float(connector.length_px) * float(step + 1) / 60.0
		var heading := float(network.point_on_edge(left_turn_id, distance).angle)
		max_angle_jump = maxf(max_angle_jump, absf(angle_difference(last_heading, heading)))
		last_heading = heading
	check("turn_heading_changes_smoothly", max_angle_jump < deg_to_rad(15.0),
		rad_to_deg(max_angle_jump))
	var flow := Node2D.new()
	flow.set_script(Flow)
	flow.enabled = false
	root.add_child(flow)
	flow.network = network
	var player := PlayerScene.instantiate()
	player.position = Vector2(300, 300) * PPM + Vector2(4600, 4600)
	root.add_child(player)
	player.set_physics_process(false)
	flow.player = player
	flow.active_junctions = {}
	flow.agents.append(make_agent(network, entrances[0], 1, 15.0))
	flow.agents.append(make_agent(network, entrances[1], 2, 15.0))
	flow.agents.append(make_agent(network, entrances[0], 3, 37.0))
	await physics_frame
	# Stale reservations after a departing/despawned car cannot lock an
	# intersection forever. A live connector owner must retain its claim.
	flow.active_junctions[0] = 9999
	flow._prune_junction_claims()
	check("orphan_intersection_reservation_is_released",
		not flow.active_junctions.has(0))
	var turning_rate_ok := true
	var min_gap := INF
	var max_stopped := 0
	var resumed_after_stop := false
	var stopped_once := false
	var previous_headings: Dictionary = {}
	for frame in 1800:
		await physics_frame
		flow._prune_junction_claims()
		for idx in range(flow.agents.size() - 1, -1, -1):
			var agent: Dictionary = flow.agents[idx]
			var node: CharacterBody2D = agent.node
			var prev_angle := float(previous_headings.get(int(agent.uid), node.rotation))
			var alive: bool = flow._tick_agent(idx, 1.0 / 60.0)
			if not alive:
				continue
			var angle_change := absf(angle_difference(prev_angle, node.rotation))
			if not bool(node.get("recovering")) and angle_change > deg_to_rad(95.0) / 60.0 + 0.02:
				turning_rate_ok = false
			previous_headings[int(agent.uid)] = node.rotation
			if int(agent.uid) == 2 and float(agent.speed) < PPM * 0.5:
				stopped_once = true
			if stopped_once and int(agent.uid) == 2 and float(agent.speed) > PPM * 2.0:
				resumed_after_stop = true
		var stopped := 0
		for agent in flow.agents:
			if float(agent.speed) < PPM * 0.25:
				stopped += 1
		max_stopped = maxi(max_stopped, stopped)
		for i in flow.agents.size():
			for j in range(i+1, flow.agents.size()):
				var a: Vector2 = flow.agents[i].node.position
				var b: Vector2 = flow.agents[j].node.position
				min_gap = minf(min_gap, a.distance_to(b))
	var crossed := []
	for agent in flow.agents:
		crossed.append(int(agent.edge) != entrances[0] and
			int(agent.edge) != entrances[1])
	check("both_intersection_approaches_make_progress", crossed[0] and crossed[1], crossed)
	check("rear_queue_follows_after_leader_clears", crossed[2], crossed)
	check("stop_sign_waiter_restarts", stopped_once and resumed_after_stop,
		[stopped_once, resumed_after_stop, max_stopped])
	check("turning_rate_limited_without_heading_snaps", turning_rate_ok)
	check("intersection_traffic_retains_separation", min_gap > PPM * 2.0,
		min_gap / PPM)
	check("junction_claims_released_after_crossing", flow.active_junctions.is_empty(),
		flow.active_junctions)
	_check_lane_transition_gaps()
	print("INTERSECTION TRAFFIC FLOW: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)



func _check_lane_transition_gaps() -> void:
	var roads: Array=[
		{"name":"Wide","start":"w","end":"join","kind":"highway","surface":"ASPHALT","width":18.0,"lanes":6,"points":[[100,300],[500,300]]},
		{"name":"Narrow reversed","start":"e","end":"join","kind":"highway","surface":"ASPHALT","width":18.0,"lanes":2,"points":[[900,300],[500,300]]}]
	var arms: Array=[
		{"road":0,"side":-1,"station":350.0,"control":"none","p":[450,300],"direction":[-1,0],"width":18},
		{"road":1,"side":-1,"station":350.0,"control":"none","p":[550,300],"direction":[1,0],"width":18}]
	var network:=Network.new()
	network.build({"roads":roads,"junctions":[{"p":[500,300],"roads":[0,1],"approaches":arms,"polygon":[[450,291],[550,291],[550,309],[450,309]],"control":"lane_transition","kind":"lane_transition"}]})
	var merge: Dictionary={}
	var through: Dictionary={}
	var reverse: Dictionary={}
	var merge_source:=-1
	var through_source:=-1
	for edge in network.edges:
		if bool(edge.connector):continue
		for option in edge.next:
			var next: Dictionary=network.edges[int(option)]
			if not bool(next.get("lane_transition",false)):continue
			if int(edge.road)==0 and int(edge.lane)==2:
				merge=next;merge_source=int(edge.id)
			elif int(edge.road)==0 and int(edge.lane)==0:
				through=next;through_source=int(edge.id)
			elif int(edge.road)==1:reverse=next
	check("lane_transition_fixture_has_both_directions",not merge.is_empty() and not through.is_empty() and not reverse.is_empty())
	if merge.is_empty() or through.is_empty() or reverse.is_empty():return
	var flow:=Node2D.new()
	flow.set_script(Flow)
	flow.enabled=false
	root.add_child(flow)
	flow.network=network
	var incoming:=make_agent(network,merge_source,10,8.0)
	var continuing:=make_agent(network,through_source,20,6.0)
	flow.agents.append(incoming);flow.agents.append(continuing)
	check("outer_lane_yields_to_approaching_continuing_lane",flow._transition_blocked(incoming,merge,8.0*PPM))
	check("continuing_lane_is_not_blocked_by_disappearing_lane",not flow._transition_blocked(continuing,through,6.0*PPM))
	continuing.edge=int(through.target_lane);continuing.progress=PPM*2.0
	check("merge_waits_for_occupied_receiving_lane",flow._transition_blocked(incoming,merge,8.0*PPM))
	continuing.progress=PPM*40.0
	check("merge_proceeds_when_receiving_lane_clears",not flow._transition_blocked(incoming,merge,8.0*PPM))
	continuing.edge=int(reverse.id);continuing.progress=0.0
	check("opposing_carriageway_does_not_block_merge",not flow._transition_blocked(incoming,merge,8.0*PPM))
	incoming.node.queue_free();continuing.node.queue_free();flow.queue_free()
