class_name VehicleOwnership
extends RefCounted
## Persistent vehicle collection and funds. No player can equip an unowned car
## in the open world; purchases use one canonical catalog price and ID.
signal changed
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Progression = preload("res://scripts/vehicle/race_progression.gd")
const Parts = preload("res://scripts/vehicle/upgrade_parts.gd")
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
			if Parts.SLOTS.has(str(slot)) and not item.is_empty() and \
				not assigned.has(uid):
				var part := Parts.get_part(str(item.template))
				if str(part.slot) == str(slot) and can_use_upgrade(str(car_id),str(part.rarity)):
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
	for slot in Parts.SLOTS:
		var item := get_upgrade_item(equipped_uid(car_id,slot))
		if not item.is_empty():
			var template := Parts.get_part(str(item.template))
			if not template.is_empty():
				result.append(template)
	return result


func apply_car_upgrades(config: VehicleConfig, car_id: String) -> void:
	Parts.apply_to_config(config,installed_templates(car_id))


func can_install_part(car_id: String, uid: String) -> String:
	if not owns(car_id):
		return "not_owned"
	var item := get_upgrade_item(uid)
	if item.is_empty():
		return "unknown_part"
	var template := Parts.get_part(str(item.template))
	if template.is_empty():
		return "unknown_part"
	if not can_use_upgrade(car_id,str(template.rarity)):
		return "level_locked"
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
	if not owns(car_id) or not Parts.SLOTS.has(slot):
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
		"part":earned_part,"part_uid":"up-%d" % prior_serial if not earned_part.is_empty() else ""}


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
