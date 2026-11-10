class_name RaceProgression
extends RefCounted
## Deterministic total-XP thresholds. Racing is the only source of XP.
## Levels are derived from lifetime XP; UI and purchase validation use the
## same functions, avoiding separate mutable, desynchronizable level saves.
const MAX_PLAYER_LEVEL := 100
const MAX_CAR_LEVEL := 50
const RARITY_THRESHOLDS := {
	"Common": 10, "Uncommon": 20, "Rare": 30,
	"Epic": 40, "Legendary": 50
}


static func player_threshold(level: int) -> int:
	var steps := clampi(level, 1, MAX_PLAYER_LEVEL) - 1
	return 20 * steps * steps + 160 * steps


static func car_threshold(level: int) -> int:
	var steps := clampi(level, 1, MAX_CAR_LEVEL) - 1
	return 25 * steps * steps + 105 * steps


static func player_level(total_xp: int) -> int:
	var xp := maxi(0, total_xp)
	var low := 1
	var high := MAX_PLAYER_LEVEL
	while low < high:
		var mid := (low + high + 1) / 2
		if player_threshold(mid) <= xp:
			low = mid
		else:
			high = mid - 1
	return low


static func car_level(total_xp: int) -> int:
	var xp := maxi(0, total_xp)
	var low := 1
	var high := MAX_CAR_LEVEL
	while low < high:
		var mid := (low + high + 1) / 2
		if car_threshold(mid) <= xp:
			low = mid
		else:
			high = mid - 1
	return low


static func player_xp_remaining(total_xp: int) -> int:
	var level := player_level(total_xp)
	return 0 if level >= MAX_PLAYER_LEVEL else player_threshold(level + 1) - maxi(0, total_xp)


static func car_xp_remaining(total_xp: int) -> int:
	var level := car_level(total_xp)
	return 0 if level >= MAX_CAR_LEVEL else car_threshold(level + 1) - maxi(0, total_xp)


static func player_level_progress(total_xp: int) -> float:
	var level := player_level(total_xp)
	if level == MAX_PLAYER_LEVEL:
		return 1.0
	var start := player_threshold(level)
	var end := player_threshold(level + 1)
	return clampf(float(maxi(0,total_xp) - start)/float(end - start), 0.0, 1.0)


static func car_level_progress(total_xp: int) -> float:
	var level := car_level(total_xp)
	if level == MAX_CAR_LEVEL:
		return 1.0
	var start := car_threshold(level)
	var end := car_threshold(level + 1)
	return clampf(float(maxi(0,total_xp) - start)/float(end - start), 0.0, 1.0)


static func highest_upgrade_rarity(car_level_value: int) -> String:
	var result := "Locked"
	for rarity in ["Common","Uncommon","Rare","Epic","Legendary"]:
		if car_level_value < int(RARITY_THRESHOLDS[rarity]):
			break
		result = rarity
	return result


static func can_install_rarity(car_level_value: int, rarity: String) -> bool:
	return RARITY_THRESHOLDS.has(rarity) and \
		car_level_value >= int(RARITY_THRESHOLDS[rarity])


static func race_rewards(elapsed_seconds: float) -> Dictionary:
	# 1/4-mile elapsed time; completing the course always yields progress.
	# Faster, valid finishes provide modest XP/cash bonuses.
	var bonus := clampf((26.0 - elapsed_seconds) / 18.0, 0.0, 1.0)
	return {
		"player_xp": roundi(440.0 + 460.0 * bonus),
		"car_xp": roundi(300.0 + 350.0 * bonus),
		"cash": roundi(400.0 + 600.0 * bonus)
	}
