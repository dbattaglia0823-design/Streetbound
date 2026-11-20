extends SceneTree
## Two separate Godot processes exercise actual ENet admission, roster, readiness,
## model identity, and disconnect over loopback. No editor or mock RPCs.
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const PORT := 28164
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
		session.leave_session()
	else:
		# Allow the host process to bind UDP before the join attempt.
		await create_timer(0.35).timeout
		check("guest_opens_real_udp_connection",
			session.join_session("127.0.0.1", "Guest", PORT))
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
