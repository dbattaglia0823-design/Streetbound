extends SceneTree
## Full published Map Builder game on two real Godot ENet processes.
## Covers world verification, authored event discovery, stage, green and DNF.
const Grid = preload("res://scripts/world/race_start_grid.gd")
const Publication = preload("res://scripts/world/world_publication.gd")
const PORT := 28431
const INVITE_FILE := "user://streetbound_published_online_28431.txt"
const POLL_SECONDS := 0.06
const MAX_POLLS := 600
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, condition: bool) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL",label])
	if not condition:
		failures.append(label)

func _poll(predicate: Callable) -> bool:
	for _i in MAX_POLLS:
		if predicate.call():
			return true
		await create_timer(POLL_SECONDS).timeout
	return predicate.call()

func _loaded() -> bool:
	return current_scene != null and current_scene.get("online_world") != null

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or str(args[0]) not in ["host","guest"]:
		quit(1)
		return
	var role: String = str(args[0])
	var session: Node = root.get_node_or_null("OnlineSession")
	check("map_builder_world_published_in_game",
		bool(Publication.current().get("published",false)))
	if role == "host":
		check("host_can_open_published_world_private_lobby",
			session.host_session("Published Host",PORT))
		var file := FileAccess.open(INVITE_FILE, FileAccess.WRITE)
		check("published_world_invite_file_created",file!=null)
		if file == null:
			quit(1)
			return
		file.store_string(session.get_invite_code())
		file.close()
	else:
		var invite_exists: bool = await _poll(func()->bool:
			return FileAccess.file_exists(INVITE_FILE))
		check("guest_finds_published_world_lobby",invite_exists)
		if not invite_exists:
			quit(1)
			return
		check("guest_submits_same_published_map_invite",
			session.join_invite(FileAccess.get_file_as_string(INVITE_FILE),"Published Guest"))
		var admitted: bool = await _poll(func()->bool:
			return session.active and session.players.size()==2)
		check("guest_passes_matching_archive_hash_admission",admitted)
		if not admitted:
			quit(1)
			return
	check("session_remembers_published_world_sha256",
		session.world_identity.get("id","")=="published-ci.world.json" and
		str(session.world_identity.get("sha256","")).length()==64)
	check("published_world_enters_real_game",change_scene_to_file("res://scenes/main.tscn")==OK)
	var loaded: bool = await _poll(_loaded)
	check("online_replication_runs_on_published_world",loaded)
	if not loaded:
		quit(1)
		return
	var game: Node = current_scene
	var net = game.get("online_world")
	var race = net.get("friend_race")
	var authored: Array = game.get("extra_races")
	check("map_has_one_authored_race_without_morrow_events",
		game.published_game_world and game.drag_race==null and
		game.circuit_race==null and game.street_race==null and authored.size()==1)
	check("race_catalog_discovers_published_sprint",
		race != null and race.available and race.race_events.has("race-0") and
		race.race_events["race-0"].get("kind","")=="street")
	check("local_payout_race_is_disabled_when_online",
		authored.size()==1 and not authored[0].is_physics_processing() and
		not authored[0].is_processing_unhandled_input())
	if race==null or not race.race_events.has("race-0"):
		quit(1)
		return
	var event: Dictionary = race.race_events["race-0"]
	var start: Vector2 = event["start"]
	var heading: Vector2 = event["direction"]
	if role=="host":
		var joined: bool = await _poll(func()->bool:
			return session.world_ready_peers.size()==1 and net.peer_cars.size()==1)
		check("published_world_host_owns_guest_physics_car",joined)
		if joined:
			var id: int = int(net.peer_cars.keys()[0])
			var local: VehicleController2D = game.get("vehicle")
			var remote: VehicleController2D = net.peer_cars[id]
			Grid.teleport(local,Grid.pose(start,heading))
			Grid.teleport(remote,Grid.pose(start + heading * 3.0,heading))
			race._host_offer()
			check("host_offers_authored_event_by_stable_id",
				race.state=="lobby" and race.event_id=="race-0" and
				race.event_kind=="street")
			var ready: bool = await _poll(func()->bool:
				return race.entries.has(id) and bool(race.entries[id].get("ready",false)))
			check("guest_joins_map_builder_start_zone",ready)
			if ready:
				race._host_start()
				check("map_builder_grid_stages_real_cars",
					race.state=="countdown" and
					race._countdown_slots.get(id,{}) is Dictionary and
					race.input_locked(id))
				var running: bool = await _poll(func()->bool:
					return race.state=="running")
				check("host_transitions_authoritative_authored_green",running)
				if running:
					check("cannot_finish_custom_sprint_without_first_gate",
						race.results.is_empty() and
						int(race.entries[id].get("next_gate",-1))==0)
					await create_timer(1.4).timeout
					race.started_ms = Time.get_ticks_msec() - race.active_time_limit_ms - 1
					var complete: bool = await _poll(func()->bool:
						return race.state=="results")
					check("custom_finish_requires_checkpoint_chain",
						complete and race.results.is_empty() and
						str(race.entries[id].get("status",""))=="dnf")
			await create_timer(2.0).timeout
	else:
		var local: VehicleController2D = game.get("vehicle")
		Grid.teleport(local,Grid.pose(start + heading*3.0,heading))
		await create_timer(1.0).timeout
		var offered: bool = await _poll(func()->bool:
			return race.state=="lobby" and race.event_id=="race-0")
		check("guest_receives_published_event_id",offered)
		if offered:
			race._on_ready_pressed()
			var staged: bool = await _poll(func()->bool:
				return race.state=="countdown")
			check("guest_sees_authored_grid_and_shared_countdown",
				staged and local.external_input)
			if staged:
				var running: bool = await _poll(func()->bool:
					return race.state=="running")
				check("guest_receives_authoritative_start",running)
				var done: bool = await _poll(func()->bool:
					return race.state=="results")
				check("guest_receives_host_validated_custom_results",done and
					race.results.is_empty() and race.entries.size()==2)
	session.leave_session()
	if role=="host" and FileAccess.file_exists(INVITE_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(INVITE_FILE))
	paused=false
	print("PUBLISHED ONLINE WORLD %s: %s" % [role.to_upper(),
		"PASS" if failures.is_empty() else "FAIL "+str(failures)])
	quit(0 if failures.is_empty() else 1)
