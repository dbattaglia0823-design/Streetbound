extends RefCounted
## Host-owned, session-scoped friend race progression. This is deliberately
## separate from VehicleOwnership/career cash, XP, parts and save files.
## No server or durable authenticated player identity exists for these lobbies.
const PLACE_POINTS := [10, 7, 5, 3]
const SUPPORTED := ["drag", "circuit", "street"]

static func points_for_finish(place: int) -> int:
	return PLACE_POINTS[place - 1] if place >= 1 and place <= PLACE_POINTS.size() else 0

static func settle(before: Dictionary, entries: Dictionary, results: Array,
		event: String, race_id: int) -> Dictionary:
	var next: Dictionary = before.duplicate(true)
	if not SUPPORTED.has(event) or race_id <= 0 or entries.size() < 2 or entries.size() > 4:
		return next
	var placements: Dictionary = {}
	for i in results.size():
		var finisher: Variant = results[i]
		if not finisher is Dictionary:
			return next
		var peer: int = int(finisher.get("id", 0))
		if not entries.has(peer) or placements.has(peer) or (
				str(entries[peer].get("status", "")) != "finished"):
			return next
		var elapsed := int(finisher.get("ms", 0))
		if elapsed <= 0 or elapsed > 480000:
			return next
		placements[peer] = i + 1
	# Every entry must be a completed validated finish or recorded DNF.
	for id in entries:
		if str(entries[id].get("status", "")) not in ["finished", "dnf"]:
			return next
	for id in entries:
		var peer := int(id)
		var state: String = str(entries[id].get("status", ""))
		var stats: Dictionary = next.get(peer, {}).duplicate(true)
		if int(stats.get("last_race", 0)) >= race_id:
			continue
		var place := int(placements.get(peer, 0))
		if state == "finished" and place == 0:
			return before.duplicate(true)
		if state == "dnf" and place != 0:
			return before.duplicate(true)
		var earned := points_for_finish(place) if state == "finished" else 0
		stats["name"] = str(entries[id].get("name", "Driver")).substr(0, 32)
		stats["races"] = int(stats.get("races", 0)) + 1
		stats["finishes"] = int(stats.get("finishes", 0)) + (1 if state == "finished" else 0)
		stats["wins"] = int(stats.get("wins", 0)) + (1 if place == 1 else 0)
		stats["podiums"] = int(stats.get("podiums", 0)) + (1 if place in [1, 2, 3] else 0)
		stats["dnfs"] = int(stats.get("dnfs", 0)) + (1 if state == "dnf" else 0)
		stats["points"] = int(stats.get("points", 0)) + earned
		stats["last_points"] = earned
		stats["last_race"] = race_id
		var best: Dictionary = stats.get("best_ms", {}).duplicate(true)
		if state == "finished":
			var duration := int(entries[id].get("ms", 0))
			if duration > 0 and (not best.has(event) or duration < int(best[event])):
				best[event] = duration
		stats["best_ms"] = best
		next[peer] = stats
	return next

static func ranked(standings: Dictionary) -> Array:
	var ordered: Array = []
	for id in standings:
		var item: Dictionary = standings[id]
		ordered.append({"id": int(id), "name": str(item.get("name", "Driver")),
			"points": int(item.get("points", 0)),
			"wins": int(item.get("wins", 0)),
			"races": int(item.get("races", 0))})
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["points"]) != int(b["points"]):
			return int(a["points"]) > int(b["points"])
		if int(a["wins"]) != int(b["wins"]):
			return int(a["wins"]) > int(b["wins"])
		return int(a["id"]) < int(b["id"]))
	return ordered
