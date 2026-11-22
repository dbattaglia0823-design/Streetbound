extends SceneTree
## Two actual Godot game instances enter the same authoritative Ashford
## street practice event. Validate street selection, staging, shared green,
## strict host-only laps and no solo career rewards.
const Grid = preload("res://scripts/world/race_start_grid.gd")
const PORT := 28411
const INVITE_FILE := "user://streetbound_friend_street_28411.txt"
const POLL_SECONDS := 0.06
const MAX_POLLS := 580
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL", label])
	if not passed:
		failures.append(label)

func _poll(condition: Callable) -> bool:
	for _i in MAX_POLLS:
		if condition.call():
			return true
		await create_timer(POLL_SECONDS).timeout
	return condition.call()

func _world_live() -> bool:
	return current_scene != null and current_scene.get("online_world") != null

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty() or str(arguments[0]) not in ["host", "guest"]:
		quit(1)
		return
	var role := str(arguments[0])
	var session: Node = root.get_node_or_null("OnlineSession")
	if role == "host":
		check("host_starts_street_private_friend_session",
			session.host_session("Street Host", PORT))
		var invite := FileAccess.open(INVITE_FILE, FileAccess.WRITE)
		check("host_creates_street_integration_invitation", invite != null)
		if invite == null:
			quit(1)
			return
		invite.store_string(session.get_invite_code())
		invite.close()
	else:
		var ready: bool = await _poll(func() -> bool:
			return FileAccess.file_exists(INVITE_FILE))
		check("guest_finds_street_invite", ready)
		if not ready:
			quit(1)
			return
		check("guest_submits_valid_street_private_invite",
			session.join_invite(FileAccess.get_file_as_string(INVITE_FILE),
				"Street Guest"))
		var authorized: bool = await _poll(func() -> bool:
			return session.active and session.players.size() == 2)
		check("guest_is_admitted_by_same_host", authorized)
		if not authorized:
			quit(1)
			return
	check("morrow_coast_loads_for_street_multiplayer",
		change_scene_to_file("res://scenes/main.tscn") == OK)
	var game_loaded: bool = await _poll(_world_live)
	check("same_full_game_world_has_multiplayer", game_loaded)
	if not game_loaded:
		quit(1)
		return
	var game: Node = current_scene
	var net = game.get("online_world")
	var race = net.get("friend_race")
	var solo_street = game.get("street_race")
	check("friend_controller_finds_verified_closed_street",
		race != null and race.street_available and \
			race.street_gates.size() >= 8)
	check("solo_street_is_disabled_in_online_game",
		is_instance_valid(solo_street) and \
			not solo_street.is_physics_processing() and \
			not solo_street.is_processing_unhandled_input())
	if race == null or not race.street_available:
		quit(1)
		return
	if role == "host":
		var guest_ready: bool = await _poll(func() -> bool:
			return session.world_ready_peers.size() == 1 and \
				net.peer_cars.size() == 1)
		check("host_has_real_street_guest_physics_car", guest_ready)
		if guest_ready:
			var guest_id: int = int(net.peer_cars.keys()[0])
			var host_car: VehicleController2D = game.get("vehicle")
			var guest_car: VehicleController2D = net.peer_cars[guest_id]
			Grid.teleport(host_car, Grid.pose(race.street_start_m +
				race.street_direction * 2.0,
				race.street_direction))
			Grid.teleport(guest_car, Grid.pose(race.street_start_m +
				race.street_direction * 5.0,
				race.street_direction))
			race._host_offer()
			check("host_selects_street_event_not_drag",
				race.state == "lobby" and race.event_kind == "street" and \
					race.street_length_m >= 600.0)
			var opted: bool = await _poll(func() -> bool:
				return race.entries.has(guest_id) and \
					bool(race.entries[guest_id].get("ready", false)))
			check("guest_ready_is_authorized_by_host_position", opted)
			if opted:
				race._host_start()
				check("host_stages_original_cars_in_street_lanes",
					race.state == "countdown" and \
						race.input_locked(guest_id) and \
						race.entries[guest_id].get("next_gate", -1) == 0)
				var started: bool = await _poll(func() -> bool:
					return race.state == "running")
				check("street_countdown_reaches_host_green", started)
				if started:
					check("no_street_finish_without_checkpoints",
						race.results.is_empty() and \
							int(race.entries[guest_id].get("next_gate", -1)) == 0)
					# Let the guest observe green and enter live driving before
					# simulating the long time-limit rule without fake progress.
					await create_timer(1.4).timeout
					race.started_ms = Time.get_ticks_msec() - \
						race.STREET_TIMEOUT_MS - 1
					var complete: bool = await _poll(func() -> bool:
						return race.state == "results")
					check("host_denies_unearned_street_laps_on_timeout",
						complete and race.results.is_empty() and \
							str(race.entries[guest_id].get("status", "")) == "dnf")
			await create_timer(2.0).timeout
	else:
		# Tests can teleport directly to the course. Normal players drive
		# there, so the guest client needs a loaded track before green.
		var local_car: VehicleController2D = game.get("vehicle")
		Grid.teleport(local_car, Grid.pose(race.street_start_m +
			race.street_direction * 5.0,
			race.street_direction))
		await create_timer(1.0).timeout
		var offered: bool = await _poll(func() -> bool:
			return is_instance_valid(race) and race.state == "lobby" and \
				race.event_kind == "street")
		check("guest_receives_explicit_street_event_type", offered)
		if offered:
			race._on_ready_pressed()
			var staged: bool = await _poll(func() -> bool:
				return is_instance_valid(race) and race.state == "countdown")
			check("guest_receives_shared_street_grid_and_countdown",
				staged and local_car.external_input and \
					race.entries.size() == 2)
			if staged:
				var green: bool = await _poll(func() -> bool:
					return is_instance_valid(race) and race.state == "running")
				check("guest_observes_authoritative_street_green", green)
				if green:
					check("guest_releases_input_without_respawn",
						not local_car.external_input)
				var done: bool = await _poll(func() -> bool:
					return is_instance_valid(race) and race.state == "results")
				check("guest_gets_host_verified_street_DNFs_without_rewards",
					done and race.results.is_empty() and \
						race.entries.size() == 2)
	session.leave_session()
	if role == "host" and FileAccess.file_exists(INVITE_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(INVITE_FILE))
	paused = false
	print("FRIEND STREET WORLD %s: %s" % [
		role.to_upper(), "PASS" if failures.is_empty() else
		"FAIL " + str(failures)])
	quit(0 if failures.is_empty() else 1)
