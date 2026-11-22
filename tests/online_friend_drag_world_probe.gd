extends SceneTree
## Two real Godot processes; hosts create race at real Ashford strip and \
## guests join with an admitted ENet peer ID. Never fakes a race winner.
const Grid = preload("res://scripts/world/race_start_grid.gd")
const PORT := 28409
const INVITE_FILE := "user://streetbound_friend_drag_28409.txt"
const POLL_SECONDS := 0.06
const MAX_POLLS := 550
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, good: bool) -> void:
	print("%s %s" % ["PASS" if good else "FAIL", label])
	if not good:
		failures.append(label)

func _poll(predicate: Callable) -> bool:
	for _i in MAX_POLLS:
		if predicate.call():
			return true
		await create_timer(POLL_SECONDS).timeout
	return predicate.call()

func _game_ready() -> bool:
	return current_scene != null and current_scene.get("online_world") != null

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or str(args[0]) not in ["host", "guest"]:
		quit(1)
		return
	var role := str(args[0])
	var session: Node = root.get_node_or_null("OnlineSession")
	if role == "host":
		check("host_starts_actual_player_hosted_race_session",
			session.host_session("Drag Host", PORT))
		var file := FileAccess.open(INVITE_FILE, FileAccess.WRITE)
		check("host_publishes_private_test_invite", file != null)
		if file == null:
			quit(1)
			return
		file.store_string(session.get_invite_code())
		file.close()
	else:
		var discovered: bool = await _poll(func() -> bool:
			return FileAccess.file_exists(INVITE_FILE))
		check("guest_finds_temporary_invite", discovered)
		if not discovered:
			quit(1)
			return
		check("guest_joins_private_room",
			session.join_invite(FileAccess.get_file_as_string(INVITE_FILE),
				"Drag Guest"))
		var joined: bool = await _poll(func() -> bool:
			return session.active and session.players.size() == 2)
		check("guest_is_authorized_for_friend_race", joined)
		if not joined:
			quit(1)
			return
	check("full_morrow_coast_scene_starts",
		change_scene_to_file("res://scenes/main.tscn") == OK)
	var live: bool = await _poll(_game_ready)
	check("full_world_has_multiplayer_controller", live)
	if not live:
		quit(1)
		return
	var game: Node = current_scene
	var online: Node = game.get("online_world")
	var race = online.get("friend_race")
	check("friend_race_controller_exists_on_both_game_processes",
		race != null and race.available)
	check("solo_race_is_disabled_during_online_friend_event",
		not game.get("drag_race").is_physics_processing())
	if race == null or not race.available:
		quit(1)
		return
	if role == "host":
		var guest_world: bool = await _poll(func() -> bool:
			return session.world_ready_peers.size() == 1 and \
				online.peer_cars.size() == 1)
		check("host_has_one_real_ready_guest", guest_world)
		if guest_world:
			var guest_id: int = int(online.peer_cars.keys()[0])
			var host_car: VehicleController2D = game.get("vehicle")
			var guest_car: VehicleController2D = online.peer_cars[guest_id]
			Grid.teleport(host_car, Grid.pose(
				race.start_m + race.direction.orthogonal() * -3.0,
				race.direction))
			Grid.teleport(guest_car, Grid.pose(
				race.start_m + race.direction.orthogonal() * 3.0,
				race.direction))
			check("host_can_offer_real_ashford_drag_event",
				race.state == "idle")
			race._host_offer()
			check("host_opens_invite_only_ready_lobby",
				race.state == "lobby" and race.entries.has(1))
			var ready: bool = await _poll(func() -> bool:
				return race.entries.has(guest_id) and \
					bool(race.entries[guest_id].get("ready", false)))
			check("host_validates_guest_ready_at_strip_not_client_position",
				ready and race._ready_count() == 2)
			if ready:
				race._host_start()
				check("host_stages_both_original_physical_cars",
					race.state == "countdown" and \
					race._countdown_slots.size() == 2 and \
					race.input_locked(guest_id))
				var running: bool = await _poll(func() -> bool:
					return race.state == "running")
				check("host_countdown_advances_to_authoritative_green",
					running)
				if running:
					# Only advance the HOST clock to test the time-limit DNF
					# path. No fake physics, car motion or awarded winner.
					race.started_ms = Time.get_ticks_msec() - race.TIME_LIMIT_MS - 1
					var finalized: bool = await _poll(func() -> bool:
						return race.state == "results")
					check("host_rejects_undriven_finish_and_marks_DNF",
						finalized and race.results.is_empty() and \
						str(race.entries[guest_id].get("status", "")) == "dnf")
			await create_timer(2.0).timeout
	else:
		# The CI guest starts at the garage but a real player would drive to
		# Ashford first. Stage the local TEST fixture at the same track and
		# permit the streamed world to load before the live race starts.
		var guest_car: VehicleController2D = game.get("vehicle")
		Grid.teleport(guest_car, Grid.pose(
			race.start_m + race.direction.orthogonal() * 3.0,
			race.direction))
		await create_timer(1.0).timeout
		var offered: bool = await _poll(func() -> bool:
			return race.state == "lobby")
		check("guest_receives_host_offered_race", offered)
		if offered:
			race._on_ready_pressed()
			var staged: bool = await _poll(func() -> bool:
				return race.state == "countdown")
			check("guest_receives_synchronized_staged_grid_and_countdown",
				staged and race.entries.size() == 2 and \
				race._client_countdown_end_ms > Time.get_ticks_msec())
			if staged:
				check("guest_driving_inputs_are_frozen_until_green",
					game.get("vehicle").external_input)
				var started: bool = await _poll(func() -> bool:
					return race.state == "running")
				check("guest_receives_host_authoritative_green", started)
				if started:
					check("guest_input_returns_after_green",
						not game.get("vehicle").external_input)
				var finished: bool = await _poll(func() -> bool:
					return race.state == "results")
				check("guest_receives_host_validated_results_and_no_rewards",
					finished and race.results.is_empty() and \
					race.entries.size() == 2)
	session.leave_session()
	if role == "host" and FileAccess.file_exists(INVITE_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(INVITE_FILE))
	paused = false
	print("FRIEND DRAG WORLD %s: %s" % [
		role.to_upper(), "PASS" if failures.is_empty() else
		"FAIL " + str(failures)])
	quit(0 if failures.is_empty() else 1)
