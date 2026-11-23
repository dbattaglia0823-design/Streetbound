extends SceneTree
## Persistent friend payouts: no guest-defined amounts, no DNF reward,
## bounded part roll and atomic replay protection across save/reload.
const Rewards = preload("res://scripts/network/online_race_rewards.gd")
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Parts = preload("res://scripts/vehicle/upgrade_parts.gd")
const Session = preload("res://scripts/network/online_session.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL",label])
	if not passed:
		failures.append(label)

func _run() -> void:
	check("persistent_prizes_require_protocol_v10",Session.PROTOCOL_VERSION==10)
	check("unrecognized_race_types_or_places_never_pay",
		Rewards.payouts("forged",1).is_empty() and
		Rewards.payouts("street",0).is_empty() and
		Rewards.payouts("street",5).is_empty())
	check("all_podium_places_have_bounded_cash_driver_and_car_xp",
		int(Rewards.payouts("circuit",1).cash)>0 and
		int(Rewards.payouts("drag",4).cash)>0 and
		int(Rewards.payouts("street",1).cash)<=2500 and
		int(Rewards.payouts("street",1).player_xp)<=1200 and
		int(Rewards.payouts("street",1).car_xp)<=900)
	var session_id := "a".repeat(48)
	check("winner_part_drop_guaranteed_and_invalid_placements_rejected",
		Rewards.part_roll(session_id,2,"audi-rs3",1) and
		not Rewards.part_roll(session_id,2,"audi-rs3",5))
	var entries: Dictionary = {1:{"status":"finished","ms":30000,"car_id":"audi-rs3"},
		7:{"status":"finished","ms":34500,"car_id":"audi-rs3"}}
	var finals: Array = [{"id":1,"ms":30000},{"id":7,"ms":34500}]
	var finisher: Dictionary = Rewards.confirmed_finisher(entries,finals,7)
	check("host_result_set_yields_exact_guest_place_and_car",
		int(finisher.get("place",0))==2 and int(finisher.get("ms",0))==34500 and
		str(finisher.get("car_id",""))=="audi-rs3")
	check("unknown_spectator_cannot_claim",
		Rewards.confirmed_finisher(entries,finals,99).is_empty())
	check("dnf_cannot_claim_a_finished_race",
		Rewards.confirmed_finisher({1:entries[1],7:{"status":"dnf","car_id":"audi-rs3"}},
			finals,7).is_empty())
	check("unfinished_peer_blocks_reward_settlement",
		Rewards.confirmed_finisher({1:entries[1],7:{"status":"racing","car_id":"audi-rs3"}},
			[finals[0]],1).is_empty())
	check("duplicate_or_unordered_results_cannot_forge_places",
		Rewards.confirmed_finisher(entries,[finals[0],finals[0]],1).is_empty() and
		Rewards.confirmed_finisher(entries,[finals[1],finals[0]],1).is_empty())
	var economy := Ownership.new(false)
	var old_balance: int = economy.balance
	var winner: Dictionary = economy.record_multiplayer_race(
		session_id,1,1,30000,"street",Ownership.STARTER_ID)
	check("winning_online_race_adds_cash_and_both_xp_tracks",
		winner.get("result","")=="completed" and economy.balance>old_balance and
		economy.player_xp>0 and int(economy.car_xp.get(Ownership.STARTER_ID,0))>0)
	check("winner_part_is_actual_owned_upgrade_template",
		not winner.get("part",{}).is_empty() and
		economy.upgrade_inventory.size()==1 and
		Parts.get_part(str(economy.upgrade_inventory[0].template)) ==
			winner.get("part",{}))
	var before_replay: int = economy.balance
	var inventory_size: int = economy.upgrade_inventory.size()
	check("same_or_prior_host_race_is_never_paid_twice",
		economy.record_multiplayer_race(session_id,1,1,30000,"street",
			Ownership.STARTER_ID).get("result","")=="already_claimed" and
		economy.balance==before_replay and economy.upgrade_inventory.size()==inventory_size)
	check("unsupported_or_invalid_finish_never_changes_career",
		economy.record_multiplayer_race(session_id,2,1,0,"street",
			Ownership.STARTER_ID).get("result","")=="invalid" and
		economy.record_multiplayer_race(session_id,2,1,30000,"forged",
			Ownership.STARTER_ID).get("result","")=="invalid" and
		economy.balance==before_replay)
	economy.owned["dodge-neon"] = true
	var other: Dictionary = economy.record_multiplayer_race(
		session_id,2,2,42000,"drag","dodge-neon")
	check("raced_car_gets_xp_even_if_another_car_is_equipped",
		other.get("result","")=="completed" and
		int(economy.car_xp.get("dodge-neon",0))>0 and
		economy.active_id==Ownership.STARTER_ID)
	var persisted_path := Ownership.SAVE_PATH
	var existing := FileAccess.file_exists(persisted_path)
	var original := FileAccess.get_file_as_bytes(persisted_path) if existing else PackedByteArray()
	var saved := Ownership.new(false)
	saved.persist_enabled = true
	var persistent_id := "b".repeat(48)
	var first: Dictionary = saved.record_multiplayer_race(
		persistent_id,6,1,27000,"circuit",Ownership.STARTER_ID)
	check("persistent_cash_xp_parts_and_claim_save_together",
		first.get("result","")=="completed" and
		first.get("part_uid","")!="" and
		FileAccess.file_exists(persisted_path))
	var restored := Ownership.new()
	var last_total := restored.balance
	check("relaunch_retains_all_multiplayer_rewards_and_part",
		restored.balance==saved.balance and restored.player_xp==saved.player_xp and
		int(restored.car_xp.get(Ownership.STARTER_ID,0)) ==
			int(saved.car_xp.get(Ownership.STARTER_ID,0)) and
		restored.get_upgrade_item(str(first.get("part_uid",""))) != {})
	check("relaunch_replay_of_same_lobby_race_pays_zero",
		restored.record_multiplayer_race(persistent_id,6,1,27000,"circuit",
			Ownership.STARTER_ID).get("result","")=="already_claimed" and
		restored.balance==last_total)
	if existing:
		var backup := FileAccess.open(persisted_path,FileAccess.WRITE)
		if backup!=null:
			backup.store_buffer(original)
			backup.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(persisted_path))
	check("test_restores_original_player_save_file",
		FileAccess.file_exists(persisted_path)==existing and
		(not existing or FileAccess.get_file_as_bytes(persisted_path)==original))
	print("FRIEND CAREER REWARDS: %s" %
		("PASS" if failures.is_empty() else "FAIL "+str(failures)))
	quit(0 if failures.is_empty() else 1)
