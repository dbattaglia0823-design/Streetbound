extends RefCounted
## Fixed, bounded persistent rewards for player-hosted friend races.
## Host confirms results; each player's own save computes its cash/XP/loot.
## Do not accept payout amounts or upgrade templates from network packets.
const Cash := [1800, 1100, 700, 400]
const DriverXp := [780, 490, 310, 190]
const CarXp := [560, 360, 220, 130]
const Types := ["drag","circuit","street"]
const MAX_CUSTOM_CASH := 20000
const MAX_CUSTOM_XP := 5000
const PART_PLACE_PERCENT := [100, 70, 40, 20]

## Optional, published Map Builder fields. Legacy maps and built-in tracks
## preserve their original payouts unless the author explicitly opts in.
## All fields are validated again at runtime before local career saves.
static func valid_settings(settings: Dictionary) -> bool:
	if settings.has("multiplayer_reward_custom") and \
			typeof(settings["multiplayer_reward_custom"]) != TYPE_BOOL:
		return false
	for rule in [["multiplayer_reward_cash", MAX_CUSTOM_CASH],
			["multiplayer_reward_player_xp", MAX_CUSTOM_XP],
			["multiplayer_reward_car_xp", MAX_CUSTOM_XP],
			["multiplayer_reward_part_chance", 100]]:
		var key: String = str(rule[0])
		if not settings.has(key):
			if bool(settings.get("multiplayer_reward_custom", false)):
				return false
			continue
		var value: Variant = settings[key]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or \
				not is_finite(float(value)) or float(value) != floorf(float(value)) or \
				float(value) < 0 or float(value) > float(rule[1]):
			return false
	return true

static func payouts(kind: String, place: int, settings: Dictionary = {}) -> Dictionary:
	if not Types.has(kind) or place < 1 or place > 4 or not valid_settings(settings):
		return {}
	var i := place - 1
	if bool(settings.get("multiplayer_reward_custom", false)):
		# The author configures first-place prizes. Other places use the
		# established individual cash/driver XP/car XP finishing ratios.
		return {
			"cash": roundi(float(settings["multiplayer_reward_cash"]) *
				float(Cash[i]) / float(Cash[0])),
			"player_xp": roundi(float(settings["multiplayer_reward_player_xp"]) *
				float(DriverXp[i]) / float(DriverXp[0])),
			"car_xp": roundi(float(settings["multiplayer_reward_car_xp"]) *
				float(CarXp[i]) / float(CarXp[0]))}
	var multiplier := 1.25 if kind == "circuit" else (1.10 if kind == "street" else 1.0)
	return {"cash":roundi(float(Cash[i])*multiplier),
		"player_xp":roundi(float(DriverXp[i])*multiplier),
		"car_xp":roundi(float(CarXp[i])*multiplier)}

static func part_chance(place: int, settings: Dictionary = {}) -> int:
	if place < 1 or place > 4 or not valid_settings(settings):
		return 0
	var first: int = int(settings["multiplayer_reward_part_chance"]) if \
		bool(settings.get("multiplayer_reward_custom", false)) else 100
	return roundi(float(first) * float(PART_PLACE_PERCENT[place - 1]) / 100.0)

static func part_roll(session_id: String, race_id: int, car_id: String,
		place: int, settings: Dictionary = {}) -> bool:
	var chance := part_chance(place, settings)
	if chance <= 0:
		return false
	if chance >= 100:
		return true
	var token := "%s/%d/%s/%d" % [session_id,race_id,car_id,place]
	return (int(token.hash()) & 0x7fffffff) % 100 < chance

## Validate the *entire* final result set, not only our own placement:
## all entries terminal, each finisher once and in chronological order.
## This method never decides who won; the host's physical race logic does.
static func confirmed_finisher(entries: Dictionary, results: Array,
		peer_id: int) -> Dictionary:
	if entries.size() < 2 or entries.size() > 4 or not entries.has(peer_id):
		return {}
	var finished: Dictionary = {}
	var previous_ms := 0
	var last_id := 0
	var mine: Dictionary = {}
	for i in results.size():
		if not results[i] is Dictionary:
			return {}
		var record: Dictionary = results[i]
		var id := int(record.get("id",0))
		var ms := int(record.get("ms",0))
		if finished.has(id) or not entries.has(id) or \
				str(entries[id].get("status","")) != "finished" or ms <= 0 or \
				ms > 7200000 or int(entries[id].get("ms",0)) != ms or \
				ms < previous_ms or (ms == previous_ms and id <= last_id):
			return {}
		finished[id] = true
		previous_ms = ms
		last_id = id
		if id == peer_id:
			mine = {"place":i+1, "ms":ms, "car_id":str(entries[id].get("car_id",""))}
	for id in entries:
		var status := str(entries[id].get("status",""))
		if status not in ["finished","dnf"] or \
				(status == "finished") != finished.has(id):
			return {}
	if mine.is_empty() or str(mine.get("car_id","")).is_empty():
		return {}
	return mine
