extends RefCounted
## Common right-of-way policy for baked Morrow Coast junctions. Works with
## existing world JSON, so map geometry and saved positions are untouched.
const RANKS := {"highway": 5, "arterial": 4, "rural": 3, "mountain": 3,
	"local": 2, "gravel": 1, "driveway": 0}

static func controls(junction: Dictionary, roads: Array) -> Dictionary:
	var result := {}
	var arms: Array = junction.get("approaches", [])
	for arm in arms:
		result["%d:%d" % [int(arm.road), int(arm.side)]] = str(arm.get("control", "none"))
	if arms.size() < 3 or str(junction.get("control", "")) == "roundabout":
		return result
	var best_rank := -1
	var candidates := []
	for arm in arms:
		var road: Dictionary = roads[int(arm.road)]
		var rank: int = RANKS.get(str(road.kind), 0)
		if rank > best_rank:
			best_rank = rank
			candidates.clear()
		if rank == best_rank:
			candidates.append(arm)
	# Prefer continuous approaches from a dominant named road; a secondary
	# road with similar width should not force a main-road four-way stop.
	var winner_name := ""
	var count := 0
	for arm in candidates:
		var name: String = str(roads[int(arm.road)].name)
		var matches := 0
		for other in candidates:
			if str(roads[int(other.road)].name) == name:
				matches += 1
		if matches > count:
			count = matches
			winner_name = name
	var main := []
	for arm in candidates:
		if str(roads[int(arm.road)].name) == winner_name:
			main.append(arm)
	# Preserve equal-priority all-way stops unless we find an unambiguous
	# through road with two approaches.
	if main.size() < 2:
		return result
	for arm in arms:
		var key := "%d:%d" % [int(arm.road), int(arm.side)]
		if main.has(arm):
			result[key] = "none"
		else:
			var road: Dictionary = roads[int(arm.road)]
			var ramp := str(road.name).to_lower().contains("slip road") or \
				str(road.name).to_lower().contains("on ramp")
			result[key] = "yield" if best_rank == 5 and ramp else "stop"
	return result

static func arm_control(junction: Dictionary, roads: Array, arm: Dictionary) -> String:
	var key := "%d:%d" % [int(arm.road), int(arm.side)]
	return str(controls(junction, roads).get(key, arm.get("control", "none")))
