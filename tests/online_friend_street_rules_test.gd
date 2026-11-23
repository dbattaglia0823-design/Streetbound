extends SceneTree
## Ordered one-way street gates and physically separated narrow-road start grid.
const Race = preload("res://scripts/network/online_friend_race.gd")
const Navigation = preload("res://scripts/world/race_navigation.gd")
const Grid = preload("res://scripts/world/race_start_grid.gd")
const Session = preload("res://scripts/network/online_session.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures.append(label)

func _run() -> void:
	check("street_grid_protocol_v9", Session.PROTOCOL_VERSION == 9)
	var nav := Navigation.new()
	nav.setup(PackedVector2Array([
		Vector2(0,0),Vector2(350,0),Vector2(350,350),
		Vector2(700,350)]),false)
	var gates: Array[Dictionary] = Race.make_street_gates(nav)
	check("open_road_has_many_directional_gates", gates.size() >= 8)
	check("finish_gate_on_real_open_route_not_start",
		gates.size() >= 8 and (gates.back()["position"] as Vector2).distance_to(
			Vector2(700,350)) < 7.0)
	var first: Dictionary = gates[0]
	var p: Vector2 = first["position"]
	var dir: Vector2 = first["forward"]
	check("forward_crossing_counts", Race.passed_directional_gate(
		p-dir*3,p+dir*3,first,Race.STREET_GATE_RADIUS_M))
	check("backwards_crossing_rejected", not Race.passed_directional_gate(
		p+dir*3,p-dir*3,first,Race.STREET_GATE_RADIUS_M))
	check("wide_shortcuts_fail", not Race.passed_directional_gate(
		p-dir*3+dir.orthogonal()*30,p+dir*3+dir.orthogonal()*30,
		first,Race.STREET_GATE_RADIUS_M))
	var last: Dictionary = gates.back()
	var last_p: Vector2 = last["position"]
	var last_dir: Vector2 = last["forward"]
	check("last_gate_cannot_skip_first", Race.next_circuit_gate_index(
		0,last_p-last_dir*3,last_p+last_dir*3,gates)==0)
	var poses: Array[Dictionary] = []
	for i in 4:
		var pose: Dictionary = Race.street_grid_pose(nav,i,4)
		check("street_grid_%d_has_valid_road_pose"%i,not pose.is_empty() and
			(Grid.point(pose)-nav.point_at(2.0+i*Race.STREET_GRID_GAP_M)).length()<0.1)
		if not pose.is_empty():
			for existing in poses:
				check("street_grid_slots_are_separated_%d"%i,
					Grid.separated(existing,pose))
			poses.append(pose)
	var loop := Navigation.new()
	loop.setup(PackedVector2Array([Vector2.ZERO,Vector2(400,0),
		Vector2(400,400),Vector2(0,400)]),true)
	check("closed_circuit_not_an_open_street_sprint",
		Race.make_street_gates(loop).is_empty())
	print("FRIEND STREET RULES: %s" % (
		"PASS" if failures.is_empty() else "FAIL "+str(failures)))
	quit(0 if failures.is_empty() else 1)
