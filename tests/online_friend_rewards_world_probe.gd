extends SceneTree
## Two full Godot game processes run a published world. The host first
## validates staging with normal rules, then a test-only injected terminal
## result exercises receipt delivery and per-machine career save/reload.
## Physics finish validation is covered by the separate drag/circuit/street
## gate tests; this probes payout replication, not race-lap geometry.
const Grid = preload("res://scripts/world/race_start_grid.gd")
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
const PORT := 28441
const INVITE_FILE := "user://streetbound_friend_rewards_invite.txt"
const TICK := 0.06
const MAX_POLLS := 700
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures.append(label)

func _poll(test: Callable) -> bool:
	for i in MAX_POLLS:
		if test.call():
			return true
		await create_timer(TICK).timeout
	return test.call()

func _world_ready() -> bool:
	return current_scene != null and current_scene.get("online_world")!=null

func _run() -> void:
	var argv := OS.get_cmdline_user_args()
	if argv.is_empty() or str(argv[0]) not in ["host","guest"]:
		quit(1)
		return
	var role: String = str(argv[0])
	var session: Node = root.get_node_or_null("OnlineSession")
	if role=="host":
		check("host_opens_v10_published_world",session.host_session("Prize Host",PORT))
		var invitation := FileAccess.open(INVITE_FILE,FileAccess.WRITE)
		check("host_writes_invite",invitation!=null)
		if invitation == null:
			quit(1)
			return
		invitation.store_string(session.get_invite_code())
		invitation.close()
	else:
		var found: bool = await _poll(func()->bool:
			return FileAccess.file_exists(INVITE_FILE))
		check("guest_reads_reachable_invite",found)
		if not found:
			quit(1)
			return
		check("guest_starts_lobby_join",session.join_invite(
			FileAccess.get_file_as_string(INVITE_FILE),"Prize Guest"))
		var joined: bool = await _poll(func()->bool:
			return session.active and session.players.size()==2)
		check("guest_admitted_to_matching_world",joined)
		if not joined:
			quit(1)
			return
	check("both_drivers_receive_same_48_char_reward_lobby_nonce",
		str(session.reward_session_id).length()==48 and
		session.valid_secret(session.reward_session_id))
	check("game_launches_published_world",change_scene_to_file("res://scenes/main.tscn")==OK)
	var loaded: bool = await _poll(_world_ready)
	check("online_career_game_scene_has_replication",loaded)
	if not loaded:
		quit(1)
		return
	var game: Node = current_scene
	var economy: VehicleOwnership = game.get("vehicle_ownership") as VehicleOwnership
	var network = game.get("online_world")
	var race = network.get("friend_race")
	check("map_authored_event_can_host_prize_race",
		game.published_game_world and race!=null and
		race.race_events.has("race-0"))
	if race==null or not race.race_events.has("race-0"):
		quit(1)
		return
	var track: Dictionary = race.race_events["race-0"]
	var start: Vector2 = track["start"]
	var direction: Vector2 = track["direction"]
	var prior_cash: int = economy.balance
	var prior_driver_xp: int = economy.player_xp
	var prior_car_xp: int = int(economy.car_xp.get(economy.active_id,0))
	var prior_parts: int = economy.upgrade_inventory.size()
	if role=="host":
		var ready: bool = await _poll(func()->bool:
			return session.world_ready_peers.size()==1 and network.peer_cars.size()==1)
		check("host_has_networked_guest_car",ready)
		if ready:
			var guest_id: int = int(network.peer_cars.keys()[0])
			Grid.teleport(game.vehicle,Grid.pose(start,direction))
			Grid.teleport(network.peer_cars[guest_id],
				Grid.pose(start+direction*4.0,direction))
			race._host_offer()
			check("host_offers_authored_sprint_with_valid_event_id",
				race.state=="lobby" and race.event_id=="race-0")
			var opted: bool = await _poll(func()->bool:
				return race.entries.has(guest_id) and
					bool(race.entries[guest_id].get("ready",false)))
			check("guest_ready_is_approved_by_host",opted)
			if opted:
				race._host_start()
				var green: bool = await _poll(func()->bool:
					return race.state=="running")
				check("shared_countdown_reaches_green_before_cash",green)
				if green:
					check("no_rewards_paid_before_race_results",
						economy.balance==prior_cash and
						economy.player_xp==prior_driver_xp)
					# Valid result records are normally filled exclusively
					# by host physics. Inject here to isolate network payout.
					await create_timer(1.0).timeout
					race.entries[1]["status"]="finished"
					race.entries[1]["ms"]=32000
					race.entries[guest_id]["status"]="finished"
					race.entries[guest_id]["ms"]=38000
					race._host_check_done()
					check("host_settles_authoritative_final_result",race.state=="results")
					var credited: bool = await _poll(func()->bool:
						return economy.balance>prior_cash and
							economy.player_xp>prior_driver_xp)
					check("winning_host_earns_real_money_and_driver_xp",credited)
					check("winning_host_earns_car_xp_and_upgrade_item",
						int(economy.car_xp.get(economy.active_id,0))>prior_car_xp and
						economy.upgrade_inventory.size()==prior_parts+1)
					var credited_cash: int = economy.balance
					race._award_own_finish()
					check("replayed_final_result_does_not_pay_host_twice",
						economy.balance==credited_cash)
					var persisted: VehicleOwnership = Ownership.new()
					check("host_career_rewards_survive_reload",
						persisted.balance==economy.balance and
						persisted.player_xp==economy.player_xp and
						persisted.upgrade_inventory.size()==economy.upgrade_inventory.size())
			await create_timer(2.0).timeout
	else:
		Grid.teleport(game.vehicle,Grid.pose(start+direction*4.0,direction))
		await create_timer(0.9).timeout
		var offered: bool = await _poll(func()->bool:
			return race.state=="lobby" and race.event_id=="race-0")
		check("guest_sees_host_owned_authored_race_offer",offered)
		if offered:
			race._on_ready_pressed()
			var staged: bool = await _poll(func()->bool:
				return race.state=="countdown")
			check("guest_receives_staging_and_shared_countdown",staged)
			if staged:
				var results: bool = await _poll(func()->bool:
					return race.state=="results")
				check("guest_receives_host_only_settled_results",results)
				if results:
					var credited: bool = await _poll(func()->bool:
						return economy.balance>prior_cash and
							economy.player_xp>prior_driver_xp)
					check("second_place_guest_receives_cash_and_driver_xp",credited)
					check("guest_receives_correct_raced_car_xp",
						int(economy.car_xp.get(economy.active_id,0))>prior_car_xp)
					var now_cash := economy.balance
					race._award_own_finish()
					check("guest_cannot_collect_duplicate_result",
						economy.balance==now_cash)
					var persisted: VehicleOwnership = Ownership.new()
					check("guest_career_save_reloads_after_network_payout",
						persisted.balance==economy.balance and
						persisted.player_xp==economy.player_xp)
	session.leave_session()
	if role=="host" and FileAccess.file_exists(INVITE_FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(INVITE_FILE))
	paused=false
	print("FRIEND REAL REWARDS WORLD %s: %s" % [role.to_upper(),
		"PASS" if failures.is_empty() else "FAIL "+str(failures)])
	quit(0 if failures.is_empty() else 1)
