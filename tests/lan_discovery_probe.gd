extends SceneTree
## Real localhost two-process LAN advertisement -> discovery -> ENet join.
const SessionScript = preload("res://scripts/network/online_session.gd")
const DiscoveryScript = preload("res://scripts/network/lan_discovery.gd")
const PORT := 28279
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, pass: bool) -> void:
	print("%s %s" % ["PASS" if pass else "FAIL", label])
	if not pass:
		failures.append(label)

func _poll_for(predicate: Callable, max_ticks: int = 200) -> bool:
	for tick in max_ticks:
		if predicate.call():
			return true
		await create_timer(0.05).timeout
	return predicate.call()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not str(args[0]) in ["host", "guest"]:
		push_error("Usage: -- host or -- guest")
		quit(1)
		return
	var role := str(args[0])
	var session: Node = root.get_node_or_null("OnlineSession")
	var discovery: Node = root.get_node_or_null("LanDiscovery")
	check("lan_autoloads_exist", session != null and discovery != null)
	if session == null or discovery == null:
		quit(1)
		return
	var fake := JSON.stringify({
		"type": DiscoveryScript.RESPONSE_TYPE,
		"protocol": SessionScript.PROTOCOL_VERSION, "name": "Found Host",
		"port": PORT, "key": "f".repeat(48), "players": 1
	}).to_utf8_buffer()
	check("lan_packets_use_received_source_not_spoofed_host_address",
		DiscoveryScript.parse_reply(fake, "192.168.5.25").get("ip", "") == "192.168.5.25")
	check("lan_parser_rejects_invalid_credentials_protocol_and_large_packets",
		DiscoveryScript.parse_reply("invalid".to_utf8_buffer(), "192.168.5.25").is_empty() and
		DiscoveryScript.parse_reply("x".repeat(1100).to_utf8_buffer(), "192.168.5.25").is_empty())
	if role == "host":
		check("host_starts_only_while_player_is_online",
			session.host_session("LAN Host", PORT, "127.0.0.1"))
		check("host_explicitly_advertises_lan",
			discovery.start_advertising() and discovery.advertising)
		var guest_seen: bool = await _poll_for(func() -> bool:
			return session.players.size() == 2)
		check("host_authorizes_actual_lan_client", guest_seen)
		var guest_left: bool = await _poll_for(func() -> bool:
			return guest_seen and session.players.size() == 1)
		check("host_recovers_after_guest_disconnect", guest_left)
		session.leave_session()
		check("advertisement_stops_with_host",
			not discovery.advertising and not session.active)
	else:
		check("guest_broadcasts_lan_discovery", discovery.scan())
		var found: bool = await _poll_for(func() -> bool:
			return discovery.rooms.size() > 0)
		check("guest_receives_host_broadcast_reply", found)
		if found:
			var first: Dictionary = discovery.rooms.values()[0]
			check("lan_reply_contains_usable_ip_and_invitation",
				str(first.ip) != "" and
				SessionScript.decode_invite(str(first.invite)).get("host", "") == str(first.ip) and
				str(first.name) == "LAN Host" and
				SessionScript.decode_invite(str(first.invite)).get("port", 0) == PORT)
			check("guest_connects_using_lan_invitation",
				session.join_invite(str(first.invite), "LAN Guest"))
			var connected: bool = await _poll_for(func() -> bool:
				return session.active and session.players.size() == 2)
			check("real_enet_host_accepts_lan_browser_guest", connected)
			await create_timer(0.4).timeout
			session.leave_session()
		discovery.cancel_scan()
	print("LAN DISCOVERY %s: %s" % [
		role.to_upper(), "PASS" if failures.is_empty() else "FAIL " + str(failures)])
	quit(0 if failures.is_empty() else 1)
