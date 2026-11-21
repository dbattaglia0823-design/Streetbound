extends SceneTree
## Smoke-test dedicated 4-player server authority and separate hosted-room menu.
const HostedScript = preload("res://scripts/network/hosted_lobby.gd")
const SessionScript = preload("res://scripts/network/online_session.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		failures.append(label)

func _run() -> void:
	var session: Node = root.get_node_or_null("OnlineSession")
	var hosted: Node = root.get_node_or_null("HostedLobby")
	check("hosted_autoloads_exist", session != null and hosted != null)
	check("remote_room_requires_https_and_rejects_embedded_credentials",
		HostedScript.valid_service_url("https://rooms.example.org") and
		HostedScript.valid_service_url("http://127.0.0.1:8090") and
		not HostedScript.valid_service_url("http://untrusted.example.org") and
		not HostedScript.valid_service_url("https://user:pass@rooms.example.org"))
	check("short_room_codes_reject_missing_or_malformed_values",
		HostedScript.valid_room_code("ABCD2345EFGH") and
		not HostedScript.valid_room_code("ABCD2345EFG1") and
		not HostedScript.valid_room_code("FOO"))
	var title: Control = load("res://scenes/title_menu.tscn").instantiate()
	root.add_child(title)
	current_scene = title
	await process_frame
	title._activate("multiplayer")
	check("hosted_mode_offered_alongside_direct_invites",
		title.actions.has("hosted_multiplayer") and
		title.actions.has("online_multiplayer") and
		title.actions["hosted_multiplayer"].visible)
	title._activate("hosted_multiplayer")
	check("hosted_room_page_exposes_create_join_and_endpoint",
		title.hosted_page.visible and not title.friends_page.visible and
		title.actions.has("create_hosted_room") and
		title.actions.has("join_hosted_room") and
		title.hosted_url != null and title.hosted_code != null)
	check("missing_cloud_endpoint_does_not_launch_gameplay",
		not hosted.create_room("", "Driver") and current_scene == title)
	title._activate("hosted_back")
	check("hosted_back_returns_to_multiplayer_selection",
		title.multiplayer_page.visible and not title.hosted_page.visible)
	title.queue_free()
	current_scene = null
	await process_frame
	var secret := "a".repeat(48)
	check("dedicated_server_accepts_exactly_four_human_seats",
		session.host_dedicated_session(28265, secret) and
		session.dedicated and session.hosting and
		session.players.is_empty() and session._invite_secret == secret)
	if session.active:
		var launch_error := change_scene_to_file("res://scenes/main.tscn")
		check("dedicated_scene_launches",launch_error == OK)
		var game: Node = null
		for frame in 100:
			await process_frame
			game = current_scene
			if game != null and game.get("online_world") != null:
				break
		check("dedicated_authority_uses_existing_morrow_world_and_physics",
			game != null and game.get("ground") != null and
			game.get("vehicle") != null and game.get("online_world") != null and
			game.online_world.local_vehicle == game.vehicle)
		check("dedicated_roster_has_no_fake_host_driver",
			session.players.is_empty())
	session.leave_session()
	paused = false
	print("HOSTED ROOM SERVER: %s" % (
		"PASS" if failures.is_empty() else "FAIL " + str(failures)))
	quit(0 if failures.is_empty() else 1)
