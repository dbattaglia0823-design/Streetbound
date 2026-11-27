extends SceneTree
## Two independent Godot processes run the full Morrow Coast gameplay world.
## Verifies that the host's new sequenced RPC actually arrives at the guest.
const Police = preload("res://scripts/world/police_pursuit.gd")
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
				var host_vehicle: VehicleController2D = current_scene.get("vehicle") as VehicleController2D
				# Isolate the snapshot seam from map-specific safe-spawn availability.
				# A real model and controller are sent over the existing ENet RPC.
				var police: Node2D = world.get("shared_police")
				check("host_has_authoritative_police", is_instance_valid(police))
				if is_instance_valid(police):
					police.set("wanted_level",3)
					police.set_physics_process(false)
					var model: Dictionary = Police.vehicle_pool(3)[0]
					check("host_creates_real_police_snapshot_fixture", police.call("_attach_responder",model,Transform2D(0.0,host_vehicle.global_position+Vector2(1200,1200))))
					var entries: Array = police.get("units")
					if not entries.is_empty():
						entries[0]["driver"].set_physics_process(false)
				host_vehicle.external_input = true
				host_vehicle.command = Vector4(0.6, 0.0, 0.0, 0.0)
				await create_timer(2.5).timeout
				host_vehicle.command = Vector4.ZERO
			var disconnected: bool = await _poll_until(func() -> bool:
				return session.disconnected_since.size() == 1)
			check("host_reserves_disconnected_driver_car", disconnected and
				session.players.size() == 2 and world.peer_cars.size() == 1)
			for id in session.disconnected_since:
				session.disconnected_since[id] = Time.get_ticks_msec() - \
					session.RECONNECT_GRACE_MS - 1
			session.expire_disconnected_players(Time.get_ticks_msec())
			check("expired_driver_is_cleaned_up", session.players.size() == 1)
		else:
			var received: bool = await _poll_until(func() -> bool:
				return int(world._last_received_sequence) >= 6 and \
					world.targets.has(session.own_id()) and \
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
			var police_received: bool = await _poll_until(func() -> bool:
				for id in world.police_replicas:
					if str(id).begins_with("u"):
						return true
				return false)
			check("guest_receives_host_pursuit_vehicle", police_received)
			if police_received:
				for id in world.police_replicas:
					if not str(id).begins_with("u"):
						continue
					var unit := world.police_replicas[id] as VehicleController2D
					check("guest_police_is_render_only_with_emergency_effects", not unit.is_physics_processing() and unit.collision_layer == 0 and unit.has_node("EmergencyEffects"))
					break
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
