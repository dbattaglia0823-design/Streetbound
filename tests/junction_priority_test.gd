extends SceneTree
const Priority = preload("res://scripts/world/junction_priority.gd")

var failed := false

func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		failed = true

func _initialize() -> void:
	var roads := [
		{"name": "Main Avenue", "kind": "arterial"},
		{"name": "Side Street", "kind": "local"},
		{"name": "Morrow Parkway", "kind": "highway"},
		{"name": "Westgate Slip Road", "kind": "arterial"}
	]
	var t := {"control": "all_way_stop", "approaches": [
		{"road": 0, "side": -1, "control": "stop"},
		{"road": 0, "side": 1, "control": "stop"},
		{"road": 1, "side": 1, "control": "stop"}
	]}
	var c: Dictionary = Priority.controls(t, roads)
	check("main_road_both_approaches_keep_priority",
		c["0:-1"] == "none" and c["0:1"] == "none")
	check("side_street_stops", c["1:1"] == "stop")
	var ramp := {"control": "all_way_stop", "approaches": [
		{"road": 2, "side": -1, "control": "stop"},
		{"road": 2, "side": 1, "control": "stop"},
		{"road": 3, "side": -1, "control": "stop"}
	]}
	c = Priority.controls(ramp, roads)
	check("freeway_traffic_continues", c["2:-1"] == "none" and c["2:1"] == "none")
	check("on_ramp_yields", c["3:-1"] == "yield")
	var equal := {"control": "all_way_stop", "approaches": [
		{"road": 1, "side": -1, "control": "stop"},
		{"road": 1, "side": 1, "control": "stop"},
		{"road": 1, "side": 2, "control": "stop"}
	]}
	# All branches of the same named street qualify as one through road,
	# so the legacy stop control is not erroneously applied to its trunk.
	c = Priority.controls(equal, roads)
	check("named_road_keeps_priority", c["1:-1"] == "none")
	var roundabout := t.duplicate(true)
	roundabout.control = "roundabout"
	c = Priority.controls(roundabout, roads)
	check("roundabout_rules_preserved", c["0:-1"] == "stop")
	print("JUNCTION PRIORITY: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
