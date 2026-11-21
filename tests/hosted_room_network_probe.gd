extends SceneTree
## Actual HTTPS-directory -> Godot ENet -> dedicated OnlineWorld smoke client.
## The Python integration test launches this in a separate Godot process.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, okay: bool) -> void:
	print("%s %s" % ["PASS" if okay else "FAIL", label])
	if not okay:
		failures.append(label)

func _poll_until(predicate: Callable, count: int = 250) -> bool:
	for tick in count:
		if predicate.call():
			return true
		await create_timer(0.08).timeout
	return predicate.call()

func _run() -> void:
	var hosted: Node = root.get_node_or_null("HostedLobby")
	var session: Node = root.get_node_or_null("OnlineSession")
	if hosted == null or session == null:
		check("required_network_autoloads_exist", false)
		quit(1)
		return
	var base := OS.get_environment("STREETBOUND_TEST_DIRECTORY")
	var code := OS.get_environment("STREETBOUND_TEST_ROOM_CODE")
	check("guest_starts_directory_lookup_using_real_http",
		hosted.join_room(base, code, "Dedicated Guest"))
	var joined: bool = await _poll_until(func() -> bool:
		return bool(session.active))
	check("guest_admitted_by_real_dedicated_room", joined and not session.hosting)
	if joined:
		check("only_real_human_in_dedicated_roster",
			session.players.size() == 1 and session.players.has(session.own_id()) and
			not session.players.has(1))
		var catalog: Array[Dictionary] = Catalog.all()
		if not catalog.is_empty():
			session.set_local_car(str(catalog[0].get("id", "")))
		check("guest_launches_authoritative_shared_world",
			change_scene_to_file("res://scenes/main.tscn") == OK)
		var world_ready: bool = await _poll_until(func() -> bool:
			return current_scene != null and current_scene.get("online_world") != null)
		check("guest_morrow_world_online_manager_exists", world_ready)
		if world_ready:
			var network: Node = current_scene.get("online_world")
			var received: bool = await _poll_until(func() -> bool:
				return network.targets.has(session.own_id()))
			check("dedicated_server_sends_authoritative_physics_snapshots", received)
			check("no_fake_dedicated_host_car_in_world_snapshots",
				not network.targets.has(1))
			check("room_code_is_retained_for_guest",str(hosted.room_code) == code)
		session.leave_session()
	print("HOSTED ROOM NETWORK GUEST: ",
		"PASS" if failures.is_empty() else "FAIL " + str(failures))
	quit(0 if failures.is_empty() else 1)
