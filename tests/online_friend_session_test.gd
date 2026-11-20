extends SceneTree
## Regression for friend-session host startup, isolated remote cars, and cleanup.
## This smoke test does not replace a real two-machine network test.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, good: bool) -> void:
	print("%s %s" % ["PASS" if good else "FAIL", label])
	if not good:
		failures.append(label)

func _run() -> void:
	check("ports_have_unambiguous_udp_range",
		OnlineSession.valid_port(28163) and
		not OnlineSession.valid_port(0) and not OnlineSession.valid_port(65536))
	check("driver_names_are_sanitized",
		OnlineSession.clean_name(" A\nB ") == "A B" and
		OnlineSession.clean_name(" ").is_empty())
	var title: Control = load("res://scenes/title_menu.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await process_frame
	title._activate("multiplayer")
	title._activate("online_multiplayer")
	check("friends_page_exposes_host_and_join",
		title.friends_page.visible and
		title.actions["host_friend_session"].disabled == false and
		title.actions["join_friend_session"].disabled == false)
	title.friend_name.text = "Test Driver"
	title.friend_port.text = "28163"
	title._activate("host_friend_session")
	for frame in 6:
		await process_frame
	var game: Node = current_scene
	check("host_transitions_to_real_morrow_coast",
		game != null and game != title and game.get("ground") != null and
		game.get("vehicle") != null)
	check("host_session_persists_across_scene_transition",
		OnlineSession.active and OnlineSession.hosting and
		OnlineSession.players.size() == 1 and
		OnlineSession.players.has(1))
	if game != null and game != title:
		var network: Node = game.get("online_world")
		check("real_driving_world_has_online_replication",
			network != null and network.name == "OnlineWorld" and
			network.local_vehicle == game.vehicle)
		if network != null:
			check("online_world_uses_no_duplicate_local_vehicle",
				network.peer_cars.is_empty() and not game.vehicle.external_input)
			# Inject an admitted peer into the roster. In production only the
			# server's admission RPC can make this change.
			OnlineSession.players[2] = {"name": "Friend", "car_id": ""}
			network._sync_peers()
			var remote: VehicleController2D = network.peer_cars.get(2)
			check("friend_is_real_vehicle_in_same_world",
				remote != null and remote.surface_provider == game.ground and
				remote.external_input and remote.is_physics_processing())
			check("friend_has_visible_nameplate_and_no_car_collision",
				network.peer_labels.has(2) and remote.collision_layer == 0 and
				remote.collision_mask == 1)
			if remote != null:
				check("untrusted_direct_rpc_does_not_move_unadmitted_sender",
					remote.command == Vector4.ZERO)
			OnlineSession.players.erase(2)
			network._sync_peers()
			check("departing_friend_is_removed",network.peer_cars.is_empty())
		game._return_to_main_menu()
		for frame in 4:
			await process_frame
		check("return_to_title_closes_udp_session_without_save_mutation",
			not OnlineSession.active and not OnlineSession.joining and
			not OnlineSession.hosting and OnlineSession.players.is_empty() and
			current_scene != game)
	OnlineSession.leave_session()
	paused = false
	print("ONLINE FRIEND SESSION: ", "PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
