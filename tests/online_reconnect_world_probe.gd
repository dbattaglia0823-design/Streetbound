extends SceneTree
## Two real Godot game processes: transient ENet loss must reclaim the exact
## host-owned car and selection, even when the host locks and rotates invites.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const PORT := 28384
const INVITE_FILE := "user://streetbound_reconnect_probe_28384.txt"
const POLL_SECONDS := 0.06
const MAX_POLLS := 460
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, success: bool) -> void:
	print("%s %s" % ["PASS" if success else "FAIL", label])
	if not success:
		failures.append(label)

func _poll(predicate: Callable) -> bool:
	for _tick in MAX_POLLS:
		if predicate.call():
			return true
		await create_timer(POLL_SECONDS).timeout
	return predicate.call()

func _world_live() -> bool:
	return current_scene != null and current_scene.get("online_world") != null

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not str(args[0]) in ["host", "guest"]:
		push_error("Expected host or guest")
		quit(1)
		return
	var role := str(args[0])
	var session: Node = root.get_node_or_null("OnlineSession")
	if role == "host":
		check("host_starts_temporary_invite_session",
			session.host_session("Recover Host", PORT))
		var invite := FileAccess.open(INVITE_FILE, FileAccess.WRITE)
		check("host_publishes_loopback_test_invitation", invite != null)
		if invite == null:
			quit(1)
			return
		invite.store_string(session.get_invite_code())
		invite.close()
	else:
		var ready: bool = await _poll(func() -> bool:
			return FileAccess.file_exists(INVITE_FILE))
		check("guest_finds_temporary_private_room", ready)
		if not ready:
			quit(1)
			return
		check("guest_joins_using_original_invite",
			session.join_invite(FileAccess.get_file_as_string(INVITE_FILE),
				"Recover Guest"))
		var admitted: bool = await _poll(func() -> bool:
			return session.active and session.players.size() == 2 and \
				not str(session.get("_resume_token")).is_empty())
		check("guest_gets_distinct_host_issued_resume_secret", admitted and \
			str(session.get("_resume_token")) != \
			str(session.get("_joining_secret")))
		if not admitted:
			quit(1)
			return
	check("main_world_starts_without_duplicate_scene",
		change_scene_to_file("res://scenes/main.tscn") == OK)
	var initialized: bool = await _poll(_world_live)
	check("full_world_is_available_for_reconnect", initialized)
	if not initialized:
		quit(1)
		return
	var game: Node = current_scene
	var world: Node = game.get("online_world")
	var car: VehicleController2D = game.get("vehicle") as VehicleController2D
	if role == "host":
		var observed_guest: bool = await _poll(func() -> bool:
			return session.players.size() == 2 and \
				session.world_ready_peers.size() == 1 and \
				world.peer_cars.size() == 1 and \
				str(session.players[world.peer_cars.keys()[0]].get("car_id", "")) != "")
		check("host_sees_guest_world_and_selected_car", observed_guest)
		if observed_guest:
			var old_id: int = int(world.peer_cars.keys()[0])
			var hosted_car: VehicleController2D = world.peer_cars[old_id]
			var preserved_car_id: String = str(session.players[old_id].get("car_id", ""))
			session.set_lobby_locked(true)
			session.rotate_invite()
			var dropped: bool = await _poll(func() -> bool:
				return session.disconnected_since.has(old_id))
			check("lost_guest_is_reserved_without_freeing_car", dropped and \
				session.players.has(old_id) and \
				world.peer_cars.get(old_id) == hosted_car)
			check("disconnect_cancels_hosted_guest_throttle_and_nitrous",
				hosted_car.command == Vector4.ZERO and \
				not hosted_car.nitrous_requested)
			var back: bool = await _poll(func() -> bool:
				return session.disconnected_since.is_empty() and \
					session.players.size() == 2 and \
					session.world_ready_peers.size() == 1 and \
					world.peer_cars.size() == 1)
			check("guest_rejoins_locked_rotated_room_with_personal_secret", back)
			if back:
				var new_id: int = int(world.peer_cars.keys()[0])
				check("same_host_physics_car_was_rebound_without_respawn",
					world.peer_cars[new_id] == hosted_car and \
					is_instance_valid(hosted_car))
				check("selected_vehicle_model_survives_reconnect",
					str(session.players[new_id].get("car_id", "")) == \
					preserved_car_id)
				check("rejoined_guest_has_no_duplicate_host_player",
					session.players.size() == 2 and world.peer_cars.size() == 1 and \
					(new_id == old_id or not world.peer_cars.has(old_id)))
		var finally_left: bool = await _poll(func() -> bool:
			return session.disconnected_since.size() == 1)
		check("guest_eventually_leaves_without_new_ghost_player", finally_left)
		for id in session.disconnected_since:
			session.disconnected_since[id] = Time.get_ticks_msec() - \
				session.RECONNECT_GRACE_MS - 1
		session.expire_disconnected_players(Time.get_ticks_msec())
		check("expired_reserved_driver_releases_original_seat",
			session.players.size() == 1 and \
			session.disconnected_since.is_empty())
	else:
		var local_car_id := ""
		var available: Array[Dictionary] = Catalog.all()
		if not available.is_empty():
			local_car_id = str(available[0].get("id", ""))
		check("guest_has_valid_car_id_for_host_to_preserve",
			not local_car_id.is_empty())
		if not local_car_id.is_empty():
			session.set_local_car(local_car_id)
		var snapshots: bool = await _poll(func() -> bool:
			return world._last_received_sequence >= 4 and \
				str(session.players.get(session.own_id(), {}).get(
					"car_id", "")) == local_car_id)
		check("guest_drives_in_real_world_before_network_loss", snapshots)
		await create_timer(1.6).timeout
		var original_vehicle: VehicleController2D = car
		session._on_server_disconnected()
		check("brief_network_loss_starts_recovery_not_title_transition",
			session.reconnecting and not session.active and \
			world.local_vehicle.external_input)
		var resumed: bool = await _poll(func() -> bool:
			return session.active and not session.reconnecting and \
				session.players.has(session.own_id()) and \
				world._last_received_sequence >= 5 and \
				world.targets.has(session.own_id()))
		check("guest_recovers_same_live_scene_and_receives_new_snapshots",
			resumed and game == current_scene and \
			world.local_vehicle == original_vehicle)
		if resumed:
			check("guest_regains_original_car_selection",
				str(session.players[session.own_id()].get("car_id", "")) == \
				local_car_id)
			check("guest_resumes_own_normal_gameplay_controls",
				not original_vehicle.external_input)
			check("reconnect_is_not_reinterpreted_as_fresh_title_join",
				current_scene == game)
		# Keep the resumed connection alive long enough for the host to
		# observe a new world-ready signal and verify identical car identity.
		await create_timer(1.5).timeout
		session.leave_session()
	session.leave_session()
	if role == "host" and FileAccess.file_exists(INVITE_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(INVITE_FILE))
	paused = false
	print("RECONNECT REAL WORLD %s: %s" % [
		role.to_upper(), "PASS" if failures.is_empty() else
		"FAIL " + str(failures)])
	quit(0 if failures.is_empty() else 1)
