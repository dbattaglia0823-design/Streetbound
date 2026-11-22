extends SceneTree
## Two separate Godot processes exercise actual ENet admission, roster, readiness,
## model identity, and disconnect over loopback. No editor or mock RPCs.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const SessionScript = preload("res://scripts/network/online_session.gd")
const PORT := 28164
const INVITE_FILE := "user://streetbound_ci_private_lobby_invite_28164.txt"
const POLL_SECONDS := 0.05
const MAX_POLLS := 180

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)

func _poll_for(predicate: Callable) -> bool:
	for tick in MAX_POLLS:
		if predicate.call():
			return true
		await create_timer(POLL_SECONDS).timeout
	return predicate.call()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not str(args[0]) in ["host", "guest", "intruder"]:
		push_error("Usage: -- host or -- guest")
		quit(1)
		return
	var role := str(args[0])
	var session: Node = root.get_node_or_null("OnlineSession")
	if session == null:
		push_error("Missing OnlineSession autoload")
		quit(1)
		return
	if role == "host":
		check("host_listens_on_loopback_udp",session.host_session("Host", PORT))
		if not session.active:
			quit(1)
			return
		var code: String = session.get_invite_code()
		check("host_generates_random_private_invitation",
			code.begins_with("SB1-") and
			SessionScript.decode_invite(code).get("host", "") == "127.0.0.1")
		var invite_file := FileAccess.open(INVITE_FILE, FileAccess.WRITE)
		check("host_writes_local_test_invitation", invite_file != null)
		if invite_file:
			invite_file.store_string(code)
			invite_file.close()
		var arrived: bool = await _poll_for(func() -> bool:
			return session.players.size() == 2)
		check("host_admits_guest_through_real_enet",arrived)
		var ready: bool = await _poll_for(func() -> bool:
			return session.world_ready_peers.size() == 1)
		check("guest_world_ready_rpc_reaches_host",ready)
		var car_id := ""
		var entries: Array[Dictionary] = Catalog.all()
		if not entries.is_empty():
			car_id = str(entries[0].get("id",""))
		if not car_id.is_empty():
			session.set_local_car(car_id)
			check("host_car_identity_can_be_selected", str(session.players[1].get("car_id","")) == car_id)
		var reserved: bool = await _poll_for(func() -> bool:
			return session.disconnected_since.size() == 1)
		check("host_holds_disconnected_guest_seat_for_reconnect", reserved and
			session.players.size() == 2)
		for id in session.disconnected_since:
			session.disconnected_since[id] = Time.get_ticks_msec() - \
				session.RECONNECT_GRACE_MS - 1
		session.expire_disconnected_players(Time.get_ticks_msec())
		check("expired_reservation_releases_slot_and_car_id",
			session.players.size() == 1 and session.disconnected_since.is_empty())
		var former_code: String = session.get_invite_code()
		var changed_code: String = session.rotate_invite()
		check("host_can_invalidate_previous_invitations",
			changed_code != former_code and not changed_code.is_empty())
		session.set_lobby_locked(true)
		check("host_can_lock_private_lobby", session.lobby_locked)
		session.leave_session()
		if FileAccess.file_exists(INVITE_FILE):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(INVITE_FILE))
	elif role == "guest":
		check("invalid_or_missing_invite_is_rejected_locally",
			not session.join_invite("wrong", "Guest") and
			not session.join_session("127.0.0.1", "Guest", PORT))
		var found: bool = await _poll_for(func() -> bool:
			return FileAccess.file_exists(INVITE_FILE))
		check("guest_reads_host_generated_code", found)
		if not found:
			quit(1)
			return
		var code: String = FileAccess.get_file_as_string(INVITE_FILE)
		check("guest_opens_real_udp_connection",
			session.join_invite(code, "Guest"))
		if not session.joining:
			quit(1)
			return
		var connected: bool = await _poll_for(func() -> bool:
			return session.active and session.players.size() == 2)
		check("guest_receives_authoritative_roster",connected)
		if connected:
			check("guest_sees_host_and_own_driver",
				session.players.has(1) and session.players.has(session.own_id()))
			session.mark_world_ready()
			var host_car_seen: bool = await _poll_for(func() -> bool:
				return str(session.players[1].get("car_id","")) != "")
			check("guest_receives_host_vehicle_identity", host_car_seen)
			var enet_measurement: bool = await _poll_for(func() -> bool:
				var stats: Dictionary = session.network_stats()
				return stats.has("rtt_ms") and int(stats["rtt_ms"]) > 0)
			check("client_reads_real_enet_rtt_not_estimated_ping", enet_measurement)
			if enet_measurement:
				var metrics: Dictionary = session.network_stats()
				check("enet_exposes_round_trip_variation_and_loss_scope",
					int(metrics.get("variation_ms", -1)) >= 0 and
					metrics.has("reliable_loss_percent"))
		await create_timer(1.5).timeout
		session.leave_session()
	else:
		var found: bool = await _poll_for(func() -> bool:
			return FileAccess.file_exists(INVITE_FILE))
		check("intruder_sees_host_active_test_lobby",found)
		if found:
			var real_code: String = FileAccess.get_file_as_string(INVITE_FILE)
			var data: Dictionary = SessionScript.decode_invite(real_code)
			var original: String = str(data.get("key", ""))
			var forged_secret := "a".repeat(48) if original != "a".repeat(48) else "b".repeat(48)
			var forged_code: String = SessionScript.encode_invite(
				str(data.get("host", "")), int(data.get("port", 0)), forged_secret)
			check("intruder_can_attempt_connection_using_forged_invite",
				session.join_invite(forged_code, "Intruder"))
			var rejected: bool = await _poll_for(func() -> bool:
				return not session.joining)
			check("host_denies_incorrect_invite_over_real_udp",rejected and not session.active)
			session.leave_session()
	paused = false
	print("ONLINE TWO PROCESS %s: %s" % [
		role.to_upper(),"PASS" if failures.is_empty() else "FAIL "+str(failures)])
	quit(0 if failures.is_empty() else 1)
