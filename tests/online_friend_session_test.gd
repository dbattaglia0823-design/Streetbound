extends SceneTree
const SessionScript = preload("res://scripts/network/online_session.gd")
const LANScript = preload("res://scripts/network/lan_discovery.gd")
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
	var session: Node = root.get_node_or_null("OnlineSession")
	if session == null:
		check("online_session_autoload_exists", false)
		quit(1)
		return
	check("ports_have_unambiguous_udp_range",
		SessionScript.valid_port(28163) and
		not SessionScript.valid_port(0) and not SessionScript.valid_port(65536))
	check("driver_names_are_sanitized",
		SessionScript.clean_name(" A\nB ") == "A B" and
		SessionScript.clean_name(" ").is_empty())
	var title: Control = load("res://scenes/title_menu.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await process_frame
	title._activate("multiplayer")
	title._activate("online_multiplayer")
	check("private_code_input_exists", title.friend_code != null and
		title.friend_code.max_length >= 500)
	check("friends_page_exposes_host_and_join",
		title.friends_page.visible and
		title.actions["host_friend_session"].disabled == false and
		title.actions["join_friend_session"].disabled == false)
	title.friend_name.text = "Test Driver"
	title.friend_port.text = "28163"
	title._activate("host_friend_session")
	# Wait for the actual threaded archive/scene handoff, not simulated frames.
	var deadline:=Time.get_ticks_msec()+30000
	while (current_scene==title or current_scene==null) and Time.get_ticks_msec()<deadline:
		await process_frame
		OS.delay_msec(1)
	for frame in 2:await process_frame
	var game: Node = current_scene
	check("host_transitions_to_real_morrow_coast",
		game != null and game != title and game.get("ground") != null and
		game.get("vehicle") != null)
	check("host_session_persists_across_scene_transition",
		session.active and session.hosting and
		session.players.size() == 1 and
		session.players.has(1))
	var first_code: String = session.get_invite_code()
	var invite_data: Dictionary = SessionScript.decode_invite(first_code)
	check("private_code_is_unpredictable_and_contains_reachable_endpoint",
		first_code.begins_with("SB1-") and
		str(invite_data.get("host", "")) == LANScript.local_ipv4() and
		int(invite_data.get("port", 0)) == 28163 and
		SessionScript.valid_secret(str(invite_data.get("key", ""))))
	check("malformed_and_short_codes_are_rejected",
		SessionScript.decode_invite("SB1-bad/contents").is_empty() and
		SessionScript.decode_invite("nope").is_empty())
	if game != null and game != title:
		var network: Node = game.get("online_world")
		check("real_driving_world_has_online_replication",
			network != null and network.name == "OnlineWorld" and
			network.local_vehicle == game.vehicle)
		if network != null:
			game.pause_menu.pause_game()
			check("online_menu_does_not_freeze_host_or_drive_through_ui",
				not paused and game.vehicle.external_input and
				network.is_physics_processing() and
				game.vehicle.command == Vector4.ZERO)
			game.pause_menu.resume_game()
			check("online_resume_restores_local_player_input",
				not game.vehicle.external_input)
			check("host_has_cooperative_robbery_director",is_instance_valid(network.friend_robbery) and not bool(network.friend_robbery.call("busy")))
			check("host_owns_shared_police_controller", is_instance_valid(network.shared_police) and network.shared_police.get("shared_session"))
			check("host_police_snapshot_has_bounded_fleet", network.call("_police_snapshot").get("vehicles", {}).size() <= 12)
			check("no_manual_police_challenge_or_rpc", not network.has_method("_request_police_chase") and not network.has_method("_request_police_challenge") and not network.has_method("start_shared_pursuit"))
			check("free_roam_cannot_start_illegal_race_heat", not bool(network.call("on_illegal_race_started")) and int(network.shared_police.get("wanted_level")) == 0)
			network.call("_on_police_collision", 0.5, game.vehicle)
			check("minor_police_contact_does_not_trigger_heat", int(network.shared_police.get("wanted_level")) == 0)
			network.call("_on_police_collision", 8.0, game.vehicle)
			check("host_validated_police_impact_starts_level_one", int(network.shared_police.get("wanted_level")) == 1 and network.police_target_peer == 1)
			network.call("_on_police_collision", 8.0, game.vehicle)
			check("repeated_police_contact_does_not_escalate_heat", int(network.shared_police.get("wanted_level")) == 1)
			network.shared_police.call("_escape")
			check("host_has_private_lobby_controls",
				network.invitation_toolbar != null and
				network.lock_lobby_button != null)
			check("online_world_uses_no_duplicate_local_vehicle",
				network.peer_cars.is_empty() and not game.vehicle.external_input)
			# Inject an admitted peer into the roster. In production only the
			# server's admission RPC can make this change.
			session.players[2] = {"name": "Friend", "car_id": ""}
			network._sync_peers()
			var remote: VehicleController2D = network.peer_cars.get(2) as VehicleController2D
			check("friend_is_real_vehicle_in_same_world",
				remote != null and remote.surface_provider == game.ground and
				remote.external_input and remote.is_physics_processing())
			check("friend_has_visible_nameplate_and_no_car_collision",
				network.peer_labels.has(2) and remote.collision_layer == 0 and
				remote.collision_mask == 1)
			if remote != null:
				check("untrusted_direct_rpc_does_not_move_unadmitted_sender",
					remote.command == Vector4.ZERO)
			session.players.erase(2)
			network._sync_peers()
			check("departing_friend_is_removed",network.peer_cars.is_empty())
		var refreshed_code: String = session.rotate_invite()
		check("host_can_replace_a_leaked_code_without_dropping_players",
			refreshed_code != first_code and
			SessionScript.decode_invite(refreshed_code).has("key"))
		session.set_lobby_locked(true)
		check("host_lobby_can_refuse_new_arrivals", session.lobby_locked)
		game._return_to_main_menu()
		for frame in 4:
			await process_frame
		check("return_to_title_closes_udp_session_without_save_mutation",
			not session.active and not session.joining and
			not session.hosting and session.players.is_empty() and
			current_scene != game)
	session.leave_session()
	paused = false
	print("ONLINE FRIEND SESSION: ", "PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
