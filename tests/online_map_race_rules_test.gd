extends SceneTree
## Map archive handshake and map-authored friend race rule regression.
const Publication = preload("res://scripts/world/world_publication.gd")
const Race = preload("res://scripts/network/online_friend_race.gd")
const Navigation = preload("res://scripts/world/race_navigation.gd")
const Grid = preload("res://scripts/world/race_start_grid.gd")
const Standings = preload("res://scripts/network/online_race_standings.gd")
const Session = preload("res://scripts/network/online_session.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures.append(label)

func _run() -> void:
	check("published_map_network_protocol_v9", Session.PROTOCOL_VERSION == 9)
	var local: Dictionary = Publication.network_identity()
	check("default_world_has_real_sha256", local.has("id") and
		str(local.get("sha256","")).length() == 64)
	check("same_world_content_is_admitted", Publication.same_network_identity(local,local))
	var modified: Dictionary = local.duplicate(true)
	modified["sha256"] = "0".repeat(64)
	check("same_name_different_compiled_map_rejected",
		not Publication.same_network_identity(local, modified))
	modified = local.duplicate(true)
	modified["id"] = "different-map.world.json"
	check("different_published_map_id_rejected",
		not Publication.same_network_identity(local, modified))
	check("incomplete_world_identity_denied",
		not Publication.same_network_identity(local, {}) and
		not Publication.same_network_identity({}, {}))
	var nav := Navigation.new()
	nav.setup(PackedVector2Array([Vector2(100,500),Vector2(600,500)]),false)
	var sprint: Dictionary = {"id":"race-main-street","name":"Downtown Sprint",
		"mode":"sprint","points":[{"x":100.0,"y":500.0},{"x":600.0,"y":500.0}],
		"formation":"single_file","enemy_starts":[],"laps":1,"checkpoint_radius":12}
	var record: Dictionary = Race.authored_event_spec(sprint,nav)
	check("custom_sprint_has_world_route_and_gate_sequence",record.get("kind","")=="street" and
		record.get("length",0.0) >= 500.0 and record.get("gates",[]).size() >= 8)
	check("custom_sprint_uses_map_builder_title_and_radius",
		record.get("title","") == "Downtown Sprint" and
		float(record.get("gate_radius",0)) == 12.0)
	var player: Dictionary = Race.authored_grid_pose(sprint,0)
	var second: Dictionary = Race.authored_grid_pose(sprint,1)
	var fourth: Dictionary = Race.authored_grid_pose(sprint,3)
	check("single_file_grid_extends_without_authored_AI_slots",
		Grid.separated(player,second) and Grid.separated(second,fourth))
	var closed := Navigation.new()
	closed.setup(PackedVector2Array([Vector2(250,250),Vector2(475,250),
		Vector2(475,475),Vector2(250,475)]),true)
	var circuit: Dictionary = {"id":"race-main-circuit","name":"Uptown Ring",
		"mode":"circuit","points":[{"x":250.0,"y":250.0},{"x":475.0,"y":250.0},
			{"x":475.0,"y":475.0},{"x":250.0,"y":475.0}],
		"laps":3,"enemy_starts":[]}
	var lap: Dictionary = Race.authored_event_spec(circuit,closed)
	check("map_builder_circuit_supports_three_validated_laps",
		lap.get("kind","")=="circuit" and lap.get("laps",0)==3 and
		lap.get("gates",[]).size()>=8)
	check("author_does_not_register_open_track_as_circuit",
		Race.authored_event_spec(circuit,nav).is_empty())
	check("author_does_not_register_tiny_route",
		Race.authored_event_spec(sprint, Navigation.new()).is_empty())
	var entries: Dictionary = {1:{"name":"Host","status":"finished","ms":25000},
		2:{"name":"Friend","status":"dnf"}}
	var finishes: Array = [{"id":1,"name":"Host","ms":25000}]
	var key := "published-ci.world.json/abcdef123456/race-main-street"
	var settled: Dictionary = Standings.settle({},entries,finishes,"street",1,key)
	check("personal_best_is_stored_under_published_event_identity",
		settled.has(1) and settled[1].get("best_ms",{}).get(key,0)==25000)
	check("same_race_cannot_double_award_custom_points",
		Standings.settle(settled,entries,finishes,"street",1,key)==settled)
	print("MAP-INDEPENDENT FRIEND RACING: %s" %
		("PASS" if failures.is_empty() else "FAIL " + str(failures)))
	quit(0 if failures.is_empty() else 1)
