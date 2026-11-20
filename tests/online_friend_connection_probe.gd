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
	if args.is_empty() or not str(args[0]) in ["host", "guest"]:
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
		var left: bool = await _poll_for(func() -> bool:
			return session.players.size() == 1)
		check("host_clears_disconnected_guest",left)
		var former_code: String = session.get_invite_code()
		var changed_code: String = session.rotate_invite()
		check("host_can_invalidate_previous_invitations",
			changed_code != former_code and not changed_code.is_empty())
		session.set_lobby_locked(true)
		check("host_can_lock_private_lobby", session.lobby_locked)
		session.leave_session()
		if FileAccess.file_exists(INVITE_FILE):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(INVITE_FILE))
	else:
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
		session.leave_session()
	paused = false
	print("ONLINE TWO PROCESS %s: %s" % [
		role.to_upper(),"PASS" if failures.is_empty() else "FAIL "+str(failures)])
	quit(0 if failures.is_empty() else 1)
