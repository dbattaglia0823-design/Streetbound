class_name VehicleOwnership
extends RefCounted
## Persistent vehicle collection and funds. No player can equip an unowned car
## in the open world; purchases use one canonical catalog price and ID.
signal changed
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Progression = preload("res://scripts/vehicle/race_progression.gd")
const Parts = preload("res://scripts/vehicle/upgrade_parts.gd")
const EventRules=preload("res://scripts/world/authored_event_rules.gd")
const DrivingContracts=preload("res://scripts/world/driving_contract_rules.gd")
const OnlineRewards=preload("res://scripts/network/online_race_rewards.gd")
const SAVE_PATH := "user://streetbound_vehicle_ownership.cfg"
const OLD_SELECTION_PATH := "user://streetbound_selected_vehicle.cfg"
const STARTER_ID := "audi-rs3"
const STARTING_CASH := 32000

var balance := STARTING_CASH
var owned: Dictionary = {STARTER_ID: true}
var active_id := STARTER_ID
var player_xp := 0
var car_xp: Dictionary = {}
var best_quarter_mile := 0.0
var _claimed_races: Array[String] = []
var completed_events: Dictionary = {}
var multiplayer_claims: Dictionary = {} # session nonce -> highest paid race ID.
var driving_contract_claims: Dictionary = {} # run token -> paid once.
var completed_driving_contracts: Dictionary = {} # world + marker -> count.
var underground_reputation := 0
var hired_crew: Dictionary = {}
var preferred_crew: Array[String] = []
var upgrade_inventory: Array[Dictionary] = []
var upgrade_loadouts: Dictionary = {}
var next_part_uid := 1
var persist_enabled := true


func _init(enable_persistence: bool = true) -> void:
	persist_enabled = enable_persistence
	if not persist_enabled:
		return
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) == OK:
		balance = maxi(0, int(file.get_value("economy", "balance", STARTING_CASH)))
		owned.clear()
		for value in file.get_value("economy", "owned_ids", [STARTER_ID]):
			var id := str(value)
			if not Catalog.find_by_id(id).is_empty():
				owned[id] = true
		if owned.is_empty():
			owned[STARTER_ID] = true
		active_id = str(file.get_value("economy", "active_id", STARTER_ID))
		if not owns(active_id):
			active_id = str(owned.keys()[0])
		# Version 1 saves lack progression; all existing purchases are kept.
		player_xp = clampi(int(file.get_value("progression","player_xp",0)),
			0,Progression.player_threshold(Progression.MAX_PLAYER_LEVEL))
		var loaded_car_xp: Variant = file.get_value("progression","car_xp",{})
		if loaded_car_xp is Dictionary:
			for key in loaded_car_xp:
				if owns(str(key)):
					car_xp[str(key)] = clampi(int(loaded_car_xp[key]),0,
						Progression.car_threshold(Progression.MAX_CAR_LEVEL))
		best_quarter_mile = maxf(0.0,float(file.get_value(
			"progression","best_quarter_mile",0.0)))
		for token in file.get_value("progression","claimed_races",[]):
			if str(token).length() >= 5 and _claimed_races.size() < 50:
				_claimed_races.append(str(token))
		var history: Variant=file.get_value("progression","completed_events",{})
		if history is Dictionary:
			for id in history:
				if str(id).length()<=160 and int(history[id])>0:
					completed_events[str(id)]=clampi(int(history[id]),1,100000)
		# A durable per-session high-water mark prevents replay even after
		# relaunch; solo's bounded _claimed_races history is not sufficient.
		var online_claims: Variant = file.get_value("progression","multiplayer_claims",{})
		if online_claims is Dictionary:
			for token in online_claims:
				var key := str(token)
				if _valid_multiplayer_session_id(key) and int(online_claims[token]) > 0 and multiplayer_claims.size() < 8192:
					multiplayer_claims[key] = maxi(0, int(online_claims[token]))
		var contract_claims: Variant = file.get_value("progression", "driving_contract_claims", {})
		if contract_claims is Dictionary:
			for token in contract_claims:
				var key := str(token)
				if key.length() >= 12 and key.length() <= 150 and bool(contract_claims[token]) and driving_contract_claims.size() < 4096:
					driving_contract_claims[key] = true
		var history_contracts: Variant = file.get_value("progression", "completed_driving_contracts", {})
		if history_contracts is Dictionary:
			for event_id in history_contracts:
				var key := str(event_id)
				if key.length() <= 160 and int(history_contracts[event_id]) > 0 and completed_driving_contracts.size() < 1024:
					completed_driving_contracts[key] = clampi(int(history_contracts[event_id]), 1, 100000)
		underground_reputation = clampi(int(file.get_value("progression", "underground_reputation", 0)), 0, 100000)
		_load_crew(file)
		_load_upgrades(file)
		return
	# Migration: previously all cars could be selected anywhere. Retain the
	# last driven car for existing players without granting every model.
	var old := ConfigFile.new()
	if old.load(OLD_SELECTION_PATH) == OK:
		var prior_id := str(old.get_value("vehicle", "selected_id", ""))
		if not Catalog.find_by_id(prior_id).is_empty():
			owned[prior_id] = true
			active_id = prior_id


func owns(id: String) -> bool:
	return bool(owned.get(id, false))


func owned_count() -> int:
	return owned.size()


func owned_cars() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in Catalog.all():
		if owns(str(entry.id)):
			result.append(entry)
	return result


func player_level() -> int:
	return Progression.player_level(player_xp)


func level_for_car(id: String) -> int:
	return Progression.car_level(int(car_xp.get(id,0)))


func active_car_level() -> int:
	return level_for_car(active_id)


func highest_upgrade_rarity(id: String) -> String:
	return Progression.highest_upgrade_rarity(level_for_car(id))


func can_use_upgrade(id: String, rarity: String) -> bool:
	return owns(id) and Progression.can_install_rarity(level_for_car(id),rarity)


func _load_upgrades(file: ConfigFile) -> void:
	# Prior saves do not contain this section. Never accept unknown template IDs
	# or equip items owned by no car; all modifiers come from our catalog.
	next_part_uid = maxi(1,int(file.get_value("upgrades","next_uid",1)))
	var seen_ids: Dictionary = {}
	var raw_items: Variant = file.get_value("upgrades","inventory",[])
	if raw_items is Array:
		for raw in raw_items:
			if not raw is Dictionary or upgrade_inventory.size() >= 2500:
				continue
			var uid := str(raw.get("uid",""))
			var template_id := str(raw.get("template",""))
			if not uid.begins_with("up-") or not uid.substr(3).is_valid_int() or \
				seen_ids.has(uid) or Parts.get_part(template_id).is_empty():
				continue
			seen_ids[uid] = true
			upgrade_inventory.append({"uid":uid,"template":template_id})
			next_part_uid = maxi(next_part_uid,int(uid.substr(3))+1)
	var assigned: Dictionary = {}
	var loadouts: Variant = file.get_value("upgrades","loadouts",{})
	if not loadouts is Dictionary:
		return
	for car_id in loadouts:
		if not owns(str(car_id)) or not loadouts[car_id] is Dictionary:
			continue
		var slots: Dictionary = {}
		for slot in loadouts[car_id]:
			var uid := str(loadouts[car_id][slot])
			var item := get_upgrade_item(uid)
			if Parts.all_slots().has(str(slot)) and not item.is_empty() and \
				not assigned.has(uid):
				var part := Parts.get_part(str(item.template))
				if str(part.slot) == str(slot) and _part_access(str(car_id),part):
					slots[str(slot)] = uid
					assigned[uid] = true
		if not slots.is_empty():
			upgrade_loadouts[str(car_id)] = slots


func get_upgrade_item(uid: String) -> Dictionary:
	for item in upgrade_inventory:
		if str(item.uid) == uid:
			return item
	return {}


func equipped_uid(car_id: String, slot: String) -> String:
	var slots: Dictionary = upgrade_loadouts.get(car_id,{})
	return str(slots.get(slot,""))


func equipped_by(uid: String) -> String:
	for car_id in upgrade_loadouts:
		var slots: Dictionary = upgrade_loadouts[car_id]
		if slots.values().has(uid):
			return str(car_id)
	return ""


func installed_templates(car_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not owns(car_id):
		return result
	for slot in Parts.all_slots():
		var item := get_upgrade_item(equipped_uid(car_id,slot))
		if not item.is_empty():
			var template := Parts.get_part(str(item.template))
			if not template.is_empty():
				result.append(template)
	return result


func apply_car_upgrades(config: VehicleConfig, car_id: String) -> void:
	Parts.apply_to_config(config,installed_templates(car_id))


func _part_access(car_id: String, template: Dictionary) -> bool:
	if Parts.is_black_market(template):
		return owns(car_id) and underground_reputation >= int(template.get("required_rep",100001))
	return can_use_upgrade(car_id,str(template.get("rarity","")))

func black_market_purchase_status(template_id: String) -> String:
	var part := Parts.get_part(template_id)
	if not Parts.is_black_market(part):
		return "unknown_part"
	if underground_reputation < int(part.required_rep):
		return "rep_locked"
	if upgrade_inventory.size() >= 2500:
		return "inventory_full"
	if balance < int(part.price_usd):
		return "insufficient_funds"
	return "ready"

func purchase_black_market(template_id: String) -> String:
	var status := black_market_purchase_status(template_id)
	if status != "ready":
		return status
	var part := Parts.get_part(template_id)
	var old_balance := balance
	var old_uid := next_part_uid
	balance -= int(part.price_usd)
	upgrade_inventory.append({"uid":"up-%d" % next_part_uid,"template":template_id})
	next_part_uid += 1
	if not save():
		balance = old_balance
		next_part_uid = old_uid
		upgrade_inventory.pop_back()
		return "save_failed"
	changed.emit()
	return "purchased"

func can_install_part(car_id: String, uid: String) -> String:
	if not owns(car_id):
		return "not_owned"
	var item := get_upgrade_item(uid)
	if item.is_empty():
		return "unknown_part"
	var template := Parts.get_part(str(item.template))
	if template.is_empty():
		return "unknown_part"
	if not _part_access(car_id,template):
		return "rep_locked" if Parts.is_black_market(template) else "level_locked"
	var in_car := equipped_by(uid)
	if not in_car.is_empty() and in_car != car_id:
		return "equipped_elsewhere"
	return "ready"


func install_part(car_id: String, uid: String) -> String:
	var allowed := can_install_part(car_id,uid)
	if allowed != "ready":
		return allowed
	var part := Parts.get_part(str(get_upgrade_item(uid).template))
	var slot := str(part.slot)
	if equipped_uid(car_id,slot) == uid:
		return "already_installed"
	var original: Dictionary = upgrade_loadouts.get(car_id,{}).duplicate(true)
	var equipped := original.duplicate(true)
	# Exactly one part in each slot, never two.
	for key in equipped.keys():
		if str(equipped[key]) == uid:
			equipped.erase(key)
	equipped[slot] = uid
	upgrade_loadouts[car_id] = equipped
	if not save():
		if original.is_empty():
			upgrade_loadouts.erase(car_id)
		else:
			upgrade_loadouts[car_id] = original
		return "save_failed"
	changed.emit()
	return "installed"


func unequip_part(car_id: String, slot: String) -> String:
	if not owns(car_id) or not Parts.all_slots().has(slot):
		return "not_owned"
	var original: Dictionary = upgrade_loadouts.get(car_id,{}).duplicate(true)
	if not original.has(slot):
		return "empty"
	var reduced := original.duplicate(true)
	reduced.erase(slot)
	if reduced.is_empty():
		upgrade_loadouts.erase(car_id)
	else:
		upgrade_loadouts[car_id] = reduced
	if not save():
		upgrade_loadouts[car_id] = original
		return "save_failed"
	changed.emit()
	return "removed"


func _award_part_for_race(race_id: String, car_level_after: int) -> Dictionary:
	var part := Parts.reward_template(race_id,car_level_after)
	if part.is_empty():
		return {}
	var uid := "up-%d" % next_part_uid
	next_part_uid += 1
	var item := {"uid":uid,"template":str(part.id)}
	upgrade_inventory.append(item)
	return part


func required_player_level(entry: Dictionary) -> int:
	return clampi(int(entry.get("required_player_level",1)),1,100)


func can_buy_at_level(entry: Dictionary) -> bool:
	return player_level() >= required_player_level(entry)


func can_afford(entry: Dictionary) -> bool:
	return balance >= int(entry.get("price_usd", 0)) and int(entry.get("price_usd", 0)) > 0


func purchase(id: String) -> String:
	var entry: Dictionary = Catalog.find_by_id(id)
	if entry.is_empty():
		return "unknown"
	if owns(id):
		return "owned"
	if not can_buy_at_level(entry):
		return "level_locked"
	var price := int(entry.get("price_usd", 0))
	if price <= 0:
		return "unavailable"
	if price > balance:
		return "insufficient"
	# Save atomically at the data-model level: rollback if storage fails.
	balance -= price
	owned[id] = true
	car_xp[id] = 0
	if not save():
		balance += price
		owned.erase(id)
		car_xp.erase(id)
		return "save_failed"
	changed.emit()
	return "purchased"


func equip(id: String) -> bool:
	if not owns(id) or Catalog.find_by_id(id).is_empty():
		return false
	var previous := active_id
	active_id = id
	if not save():
		active_id = previous
		return false
	changed.emit()
	return true


## No migration needed: career rank and access are derived from the existing saved rep.
func _load_crew(file: ConfigFile) -> void:
	var raw: Variant = file.get_value("crew","hired",{})
	if raw is Dictionary:
		for id in DrivingContracts.CREW_ORDER:
			if raw.has(id) and underground_access(str(DrivingContracts.CREW[id]["gate"])):
				var value: Variant = raw[id]
				if typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)):
					hired_crew[id] = clampi(int(value),0,DrivingContracts.CREW_MAX_XP)
	var selected: Variant = file.get_value("crew","preferred",[])
	if selected is Array:
		for id in selected:
			if id is String and hired_crew.has(id) and not preferred_crew.has(id) and preferred_crew.size()<DrivingContracts.CREW_MAX_ACTIVE:
				preferred_crew.append(id)

func crew_hire_status(id: String) -> String:
	if not DrivingContracts.CREW.has(id):
		return "unknown_member"
	if hired_crew.has(id):
		return "already_hired"
	var member: Dictionary = DrivingContracts.CREW[id]
	if not underground_access(str(member.gate)):
		return "rep_locked"
	if balance < int(member.fee):
		return "insufficient_funds"
	return "ready"

func hire_crew(id: String) -> String:
	var status := crew_hire_status(id)
	if status != "ready":
		return status
	var fee := int(DrivingContracts.CREW[id]["fee"])
	balance -= fee
	hired_crew[id] = 0
	if not save():
		hired_crew.erase(id)
		balance += fee
		return "save_failed"
	changed.emit()
	return "hired"

func toggle_preferred_crew(id: String) -> String:
	if not hired_crew.has(id):
		return "not_hired"
	var previous: Array[String] = preferred_crew.duplicate()
	var result := "assigned"
	if preferred_crew.has(id):
		preferred_crew.erase(id)
		result = "unassigned"
	elif preferred_crew.size() >= DrivingContracts.CREW_MAX_ACTIVE:
		return "crew_full"
	else:
		preferred_crew.append(id)
	if not save():
		preferred_crew = previous
		return "save_failed"
	changed.emit()
	return result

func crew_for_offer(offer: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var seats := DrivingContracts.robbery_payload(offer).x
	for id in preferred_crew:
		if ids.size() >= seats:
			break
		if hired_crew.has(id) and DrivingContracts.CREW.has(id) and underground_access(str(DrivingContracts.CREW[id]["gate"])):
			ids.append(id)
	return ids

func quote_crew(offer: Dictionary, ids: Array) -> Dictionary:
	if ids.is_empty() or not DrivingContracts.crew_ids_valid(offer,ids,hired_crew,underground_reputation):
		return {}
	return DrivingContracts.crew_quote(offer,ids,hired_crew)

func underground_career() -> Dictionary:
	return DrivingContracts.career_state(underground_reputation)

func underground_access(key: String) -> bool:
	return DrivingContracts.has_career_access(key,underground_reputation)

func record_completed_race(race_id: String, elapsed_seconds: float) -> Dictionary:
	# The race coordinator calls this only after a timed, completed 1/4-mile
	# run. Race tokens are saved to prevent double payout, even on restart.
	if race_id.length() < 5 or _claimed_races.has(race_id) or \
		is_nan(elapsed_seconds) or is_inf(elapsed_seconds) or elapsed_seconds < 7.0 or \
		elapsed_seconds > 180.0 or not owns(active_id):
		return {"result":"invalid_or_duplicate"}
	var old_player_level := player_level()
	var old_car_level := active_car_level()
	var prior_player_xp := player_xp
	var prior_car_xp := int(car_xp.get(active_id,0))
	var prior_balance := balance
	var prior_rep := underground_reputation
	var prior_best := best_quarter_mile
	var prior_serial := next_part_uid
	var prior_inventory_size := upgrade_inventory.size()
	var prior_claims: Array[String] = _claimed_races.duplicate()
	var rewards: Dictionary = Progression.race_rewards(elapsed_seconds)
	player_xp = mini(Progression.player_threshold(Progression.MAX_PLAYER_LEVEL),
		player_xp + int(rewards.player_xp))
	car_xp[active_id] = mini(Progression.car_threshold(Progression.MAX_CAR_LEVEL),
		prior_car_xp + int(rewards.car_xp))
	balance += int(rewards.cash)
	underground_reputation = mini(100000,underground_reputation + DrivingContracts.RACE_REPUTATION)
	if best_quarter_mile <= 0.0 or elapsed_seconds < best_quarter_mile:
		best_quarter_mile = elapsed_seconds
	var earned_part: Dictionary = _award_part_for_race(race_id,active_car_level())
	_claimed_races.append(race_id)
	if _claimed_races.size() > 50:
		_claimed_races.pop_front()
	if not save():
		player_xp = prior_player_xp
		car_xp[active_id] = prior_car_xp
		balance = prior_balance
		underground_reputation = prior_rep
		best_quarter_mile = prior_best
		_claimed_races = prior_claims
		upgrade_inventory.resize(prior_inventory_size)
		next_part_uid = prior_serial
		return {"result":"save_failed"}
	changed.emit()
	return {"result":"completed","player_xp":int(rewards.player_xp),
		"car_xp":int(rewards.car_xp),"cash":int(rewards.cash),
		"player_level_before":old_player_level,"player_level_after":player_level(),
		"car_level_before":old_car_level,"car_level_after":active_car_level(),
		"car_id":active_id,"seconds":elapsed_seconds,
		"underground_rep":underground_reputation-prior_rep,
		"rank_up":DrivingContracts.promotion_text(prior_rep,underground_reputation),
		"part":earned_part,"part_uid":"up-%d" % prior_serial if not earned_part.is_empty() else ""}


## Career completion is keyed by stable map+event ID, not by run token.
## Each valid completed run may pay repeat rewards. First-win extras are
## atomically committed exactly once, even across restart and retry.
func completed_event_count(event_key: String) -> int:
	return int(completed_events.get(event_key,0))

func record_authored_race(run_id: String,elapsed_seconds: float,awards: Dictionary,
		event_key: String="", police_cleared: bool=false) -> Dictionary:
	if run_id.length()<8 or run_id.length()>150 or _claimed_races.has(run_id) or \
			not is_finite(elapsed_seconds) or elapsed_seconds<0.1 or elapsed_seconds>7200.0 or not owns(active_id):
		return {"result":"invalid_or_duplicate"}
	if not EventRules.valid_event(awards):
		return {"result":"invalid_event"}
	if int(awards.get("race_heat",0))>0 and not police_cleared:
		return {"result":"escape_required"}
	if event_key.is_empty():event_key="morrow-coast::"+str(awards.get("id","legacy"))
	var reason: String=EventRules.lock_reason(awards,self,
		event_key.get_slice("::",0)) if event_key.contains("::") else ""
	if not reason.is_empty():return {"result":"locked","reason":reason}
	var first_win:=completed_event_count(event_key)==0
	var values: Array[int]=[]
	for field in ["reward_cash","reward_player_xp","reward_car_xp"]:
		var amount: Variant=awards.get(field,0)
		var max_reward:=1000000 if field=="reward_cash" else 100000
		if typeof(amount) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(amount)) or \
				float(amount)!=floorf(float(amount)) or float(amount)<0 or float(amount)>max_reward:
			return {"result":"invalid_reward"}
		var extra_field: String="first_win_"+field
		var extra: Variant=awards.get(extra_field,0) if first_win else 0
		var total:=int(amount)+int(extra)
		values.append(total)
	var cash:=values[0]
	var driver_xp:=values[1]
	var vehicle_xp:=values[2]
	var previous_balance:=balance
	var previous_player_xp:=player_xp
	var previous_car_xp:=int(car_xp.get(active_id,0))
	var previous_claims: Array[String]=_claimed_races.duplicate()
	var previous_events: Dictionary=completed_events.duplicate()
	var previous_rep:=underground_reputation
	# A completed race builds driver recognition; underground author rewards
	# remain the stronger configured reward and still require evading heat.
	var street_rep:=maxi(DrivingContracts.RACE_REPUTATION,int(awards.get("underground_rep_reward",0)))
	underground_reputation=mini(100000,underground_reputation+street_rep)
	balance+=cash
	player_xp=mini(Progression.player_threshold(Progression.MAX_PLAYER_LEVEL),player_xp+driver_xp)
	car_xp[active_id]=mini(Progression.car_threshold(Progression.MAX_CAR_LEVEL),previous_car_xp+vehicle_xp)
	_claimed_races.append(run_id)
	if _claimed_races.size()>50:_claimed_races.pop_front()
	completed_events[event_key]=completed_event_count(event_key)+1
	if not save():
		balance=previous_balance
		player_xp=previous_player_xp
		car_xp[active_id]=previous_car_xp
		_claimed_races=previous_claims
		completed_events=previous_events
		underground_reputation=previous_rep
		return {"result":"save_failed"}
	changed.emit()
	return {"result":"completed","cash":cash,"player_xp":driver_xp,
		"car_xp":vehicle_xp,"first_win":first_win,"win_count":completed_event_count(event_key),
		"underground_rep":underground_reputation-previous_rep,
		"rank_up":DrivingContracts.promotion_text(previous_rep,underground_reputation)}

## A player may earn career rewards only for a completed, host-verified
## multiplayer finish. The network layer validates the final standings and
## supplies only the place, duration and staged car; amounts/templates are
## calculated exclusively here from bundled, bounded rules.
static func _valid_multiplayer_session_id(value: String) -> bool:
	if value.length() != 48:
		return false
	for c in value:
		if not "0123456789abcdef".contains(c):
			return false
	return true

func record_multiplayer_race(session_id: String, race_id: int, place: int,
		elapsed_ms: int, kind: String, car_id: String,
		race_settings: Dictionary = {}) -> Dictionary:
	if not _valid_multiplayer_session_id(session_id) or race_id < 1 or \
			race_id > 1000000000 or elapsed_ms < 1200 or elapsed_ms > 7200000 or \
			not owns(car_id) or Catalog.find_by_id(car_id).is_empty():
		return {"result":"invalid"}
	var previous_race: int = int(multiplayer_claims.get(session_id,0))
	if race_id <= previous_race:
		return {"result":"already_claimed"}
	if multiplayer_claims.size() >= 8192 and not multiplayer_claims.has(session_id):
		return {"result":"claim_history_full"}
	# Reward configuration comes from the locally loaded, SHA-256-matched
	# published world, not an RPC amount supplied by another player.
	var payout: Dictionary = OnlineRewards.payouts(kind,place,race_settings)
	if payout.is_empty():
		return {"result":"invalid"}
	# Even without gameplay payout caps, never wrap the native 64-bit
	# balance if an extremely large authored prize is earned repeatedly.
	if balance > 9223372036854775807 - int(payout.cash):
		return {"result":"balance_overflow"}
	var prior_balance := balance
	var prior_player_xp := player_xp
	var prior_car_xp: int = int(car_xp.get(car_id,0))
	var previous_inventory_count := upgrade_inventory.size()
	var previous_part_uid := next_part_uid
	var old_claims := multiplayer_claims.duplicate()
	var prior_car_level := level_for_car(car_id)
	balance += int(payout.cash)
	player_xp = mini(Progression.player_threshold(Progression.MAX_PLAYER_LEVEL),
		player_xp + int(payout.player_xp))
	car_xp[car_id] = mini(Progression.car_threshold(Progression.MAX_CAR_LEVEL),
		prior_car_xp + int(payout.car_xp))
	var part: Dictionary = {}
	var part_uid := ""
	var receipt_key := "%s/%d/%s" % [session_id,race_id,car_id]
	if upgrade_inventory.size() < 2500 and \
			OnlineRewards.part_roll(session_id,race_id,car_id,place,race_settings):
		part = Parts.reward_template(receipt_key,level_for_car(car_id),kind)
		if not part.is_empty():
			part_uid = "up-%d" % next_part_uid
			upgrade_inventory.append({"uid":part_uid,"template":str(part.id)})
			next_part_uid += 1
	multiplayer_claims[session_id] = race_id
	if not save():
		balance = prior_balance
		player_xp = prior_player_xp
		car_xp[car_id] = prior_car_xp
		upgrade_inventory.resize(previous_inventory_count)
		next_part_uid = previous_part_uid
		multiplayer_claims = old_claims
		return {"result":"save_failed"}
	changed.emit()
	return {"result":"completed", "cash":int(payout.cash),
		"player_xp":int(payout.player_xp), "car_xp":int(payout.car_xp),
		"car_id":car_id, "car_level_before":prior_car_level,
		"car_level_after":level_for_car(car_id),
		"part":part, "part_uid":part_uid}

## Fixed game-authored cash/XP/underground reputation, saved with a unique run token.
## A map marker cannot alter payouts or claim a run twice.
func record_driving_contract(run_id: String, event_key: String, kind: String, offer: Dictionary = {}, crew_ids: Array = []) -> Dictionary:
	if run_id.length() < 12 or run_id.length() > 150:
		return {"result":"invalid_or_duplicate"}
	if event_key.length() < 5 or event_key.length() > 160:
		return {"result":"invalid_or_duplicate"}
	if driving_contract_claims.has(run_id) or not owns(active_id):
		return {"result":"invalid_or_duplicate"}
	if not DrivingContracts.valid_kind(kind) or driving_contract_claims.size() >= 4096:
		return {"result":"invalid_or_duplicate"}
	if not DrivingContracts.valid_robbery_profile(kind,offer):
		return {"result":"invalid_reward"}
	if not DrivingContracts.robbery_profile(offer).is_empty() and underground_reputation < DrivingContracts.required_rep(offer):
		return {"result":"locked"}
	# Never trust arbitrary map JSON reward amounts: reject out-of-range values
	# even when a caller bypasses the editor's schema validation.
	for field in DrivingContracts.REWARD_LIMITS:
		if not offer.has(field):
			continue
		var amount: Variant = offer[field]
		if typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(amount)) or \
				float(amount) != floorf(float(amount)) or int(amount) < 0 or \
				int(amount) > int(DrivingContracts.REWARD_LIMITS[field]):
			return {"result":"invalid_reward"}
	if offer.has("repeatable") and typeof(offer.repeatable) != TYPE_BOOL:
		return {"result":"invalid_offer"}
	if not bool(offer.get("repeatable",true)) and int(completed_driving_contracts.get(event_key,0)) > 0:
		return {"result":"already_completed"}
	if not DrivingContracts.crew_ids_valid(offer,crew_ids,hired_crew,underground_reputation) or (not crew_ids.is_empty() and kind!="robbery"):
		return {"result":"invalid_crew"}
	var rewards: Dictionary = DrivingContracts.configured_reward(kind,offer)
	var cash: int = int(rewards.get("cash",0))
	var driver_xp: int = int(rewards.get("player_xp",0))
	var vehicle_xp: int = int(rewards.get("car_xp",0))
	var reputation: int = int(rewards.get("underground_rep",0))
	var crew_cut := 0
	var crew_xp := 0
	var previous_crew: Dictionary = hired_crew.duplicate(true)
	if not crew_ids.is_empty():
		var quote := quote_crew(offer,crew_ids)
		cash = int(quote.cash)
		crew_cut = int(quote.cut)
		reputation = int(quote.underground_rep)
		crew_xp = DrivingContracts.crew_xp_reward(offer)
	var prior_balance := balance
	var prior_player_xp := player_xp
	var prior_car_xp := int(car_xp.get(active_id,0))
	var prior_rep := underground_reputation
	var prior_completed := int(completed_driving_contracts.get(event_key,0))
	balance += cash
	player_xp = mini(Progression.player_threshold(Progression.MAX_PLAYER_LEVEL), player_xp + driver_xp)
	car_xp[active_id] = mini(Progression.car_threshold(Progression.MAX_CAR_LEVEL), prior_car_xp + vehicle_xp)
	underground_reputation = mini(100000, underground_reputation + reputation)
	for id in crew_ids:
		hired_crew[id] = mini(DrivingContracts.CREW_MAX_XP,int(hired_crew[id])+crew_xp)
	driving_contract_claims[run_id] = true
	completed_driving_contracts[event_key] = mini(100000, prior_completed + 1)
	if not save():
		balance = prior_balance
		player_xp = prior_player_xp
		car_xp[active_id] = prior_car_xp
		underground_reputation = prior_rep
		hired_crew = previous_crew
		driving_contract_claims.erase(run_id)
		if prior_completed == 0:
			completed_driving_contracts.erase(event_key)
		else:
			completed_driving_contracts[event_key] = prior_completed
		return {"result":"save_failed"}
	changed.emit()
	return {"result":"completed","cash":cash,"player_xp":driver_xp,
		"car_xp":vehicle_xp,"underground_rep":underground_reputation-prior_rep,
		"crew_cut":crew_cut,"crew_xp":crew_xp,"crew_count":crew_ids.size(),
		"rank_up":DrivingContracts.promotion_text(prior_rep,underground_reputation)}

# Entry fee is paid once when a validated race is staged, after the grid
# has been prepared. Loss, false start, quit or arrest does not refund it.
func pay_race_entry(awards: Dictionary) -> bool:
	if not EventRules.valid_event(awards):return false
	var fee:=int(awards.get("entry_fee",0))
	if fee==0:return true
	if fee>balance:return false
	balance-=fee
	if not save():
		balance+=fee
		return false
	changed.emit()
	return true

func credit(amount: int) -> bool:
	if amount <= 0:
		return false
	balance += amount
	if not save():
		balance -= amount
		return false
	changed.emit()
	return true


func save() -> bool:
	if not persist_enabled:
		return true
	var file := ConfigFile.new()
	file.set_value("economy", "balance", balance)
	file.set_value("economy", "owned_ids", owned.keys())
	file.set_value("economy", "active_id", active_id)
	file.set_value("progression","player_xp",player_xp)
	file.set_value("progression","car_xp",car_xp)
	file.set_value("progression","best_quarter_mile",best_quarter_mile)
	file.set_value("progression","claimed_races",_claimed_races)
	file.set_value("progression","completed_events",completed_events)
	file.set_value("progression","multiplayer_claims",multiplayer_claims)
	file.set_value("progression","driving_contract_claims",driving_contract_claims)
	file.set_value("progression","completed_driving_contracts",completed_driving_contracts)
	file.set_value("progression","underground_reputation",underground_reputation)
	file.set_value("crew","hired",hired_crew)
	file.set_value("crew","preferred",preferred_crew)
	file.set_value("upgrades","inventory",upgrade_inventory)
	file.set_value("upgrades","loadouts",upgrade_loadouts)
	file.set_value("upgrades","next_uid",next_part_uid)
	return file.save(SAVE_PATH) == OK


static func dollars(value: int) -> String:
	var digits := str(absi(value))
	var formatted := ""
	while digits.length() > 3:
		formatted = "," + digits.substr(digits.length() - 3) + formatted
		digits = digits.substr(0, digits.length() - 3)
	return ("-$" if value < 0 else "$") + digits + formatted
