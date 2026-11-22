extends SceneTree
## Two independent Godot processes run the full Morrow Coast gameplay world.
## Verifies that the host's new sequenced RPC actually arrives at the guest.
const PORT := 28283
const INVITE_FILE := "user://streetbound_network_world_28283.txt"
const POLL_SECONDS := 0.06
const MAX_POLLS := 380
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		failures.append(label)

func _poll_until(predicate: Callable) -> bool:
	for frame in MAX_POLLS:
		if predicate.call():
			return true
		await create_timer(POLL_SECONDS).timeout
	return predicate.call()

func _world_ready() -> bool:
	return current_scene != null and current_scene.get("online_world") != null

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty() or not str(args[0]) in ["host", "guest"]:
		push_error("Usage: -- host or -- guest")
		quit(1)
		return
	var role := str(args[0])
	var session: Node = root.get_node_or_null("OnlineSession")
	if session == null:
		check("online_session_autoload_exists", false)
		quit(1)
		return
	if role == "host":
		check("hosting_real_authoritative_game_on_loopback",
			session.host_session("Latency Host", PORT))
		if not session.active:
			quit(1)
			return
		var invitation := FileAccess.open(INVITE_FILE, FileAccess.WRITE)
		check("host_provides_one_time_test_invitation", invitation != null)
		if invitation == null:
			quit(1)
			return
		invitation.store_string(session.get_invite_code())
		invitation.close()
	else:
		var available: bool = await _poll_until(func() -> bool:
			return FileAccess.file_exists(INVITE_FILE))
		check("guest_finds_live_temporary_game", available)
		if not available:
			quit(1)
			return
		check("guest_starts_real_enet_session",
			session.join_invite(FileAccess.get_file_as_string(INVITE_FILE),
				"Latency Guest"))
		var accepted: bool = await _poll_until(func() -> bool:
			return session.active and session.players.size() == 2)
		check("guest_accepted_by_player_host", accepted)
		if not accepted:
			quit(1)
			return
	check("real_game_world_scene_loads",
		change_scene_to_file("res://scenes/main.tscn") == OK)
	var initialized: bool = await _poll_until(_world_ready)
	check("real_world_replication_node_exists", initialized)
	if initialized:
		var world: Node = current_scene.get("online_world")
		if role == "host":
			var peer_ready: bool = await _poll_until(func() -> bool:
				return session.world_ready_peers.size() == 1)
			check("host_receives_guest_world_ready", peer_ready)
			if peer_ready:
				# Use the actual input seam and host's 120 Hz car physics.
				var host_vehicle: VehicleController2D = current_scene.get("vehicle")
				host_vehicle.external_input = true
				host_vehicle.command = Vector4(0.6, 0.0, 0.0, 0.0)
				await create_timer(2.5).timeout
				host_vehicle.command = Vector4.ZERO
			var disconnected: bool = await _poll_until(func() -> bool:
				return session.players.size() == 1)
			check("host_observes_guest_disconnect", disconnected)
		else:
			var received: bool = await _poll_until(func() -> bool:
				return int(world._last_received_sequence) >= 6 and
					world.targets.has(session.own_id()) and
					world.peer_cars.has(1))
			check("guest_receives_ordered_authoritative_car_snapshots", received)
			if received:
				var previous: int = int(world._last_received_sequence)
				await create_timer(0.8).timeout
				check("authoritative_snapshot_sequence_increases_over_time",
					int(world._last_received_sequence) > previous + 2)
				check("remote_host_is_smoothed_from_bounded_history",
					world.histories.has(1) and
					(world.histories[1] as Array).size() >= 2 and
					(world.histories[1] as Array).size() <= 7)
			var metrics_present: bool = await _poll_until(func() -> bool:
				return int(session.network_stats().get("rtt_ms", 0)) > 0)
			check("guest_reads_real_network_rtt", metrics_present)
			check("quality_overlay_exposes_live_rtt",
				world.quality_label != null and
				str(world.quality_label.text).contains("RTT"))
	session.leave_session()
	if role == "host" and FileAccess.file_exists(INVITE_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(INVITE_FILE))
	paused = false
	print("LOW LATENCY WORLD %s: %s" % [
		role.to_upper(), "PASS" if failures.is_empty() else
		"FAIL " + str(failures)])
	quit(0 if failures.is_empty() else 1)
