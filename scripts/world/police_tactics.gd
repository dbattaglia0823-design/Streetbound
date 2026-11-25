extends RefCounted
## Conservative, deterministic police tactics. All locations are metres;
## these rules never change a car's physics, velocity, grip or position.
const MAX_RESPONDERS := 4
const SPAWN_MIN_M := 125.0
const SPAWN_MAX_M := 245.0
const SPAWN_SEPARATION_M := 45.0
const SPAWN_FORWARD_DOT_LIMIT := 0.15
const LOST_SIGHT_GRACE_SECONDS := 2.5
const BLOCKADE_MIN_M := 90.0
const BLOCKADE_MAX_M := 170.0

static func profile(wanted: int) -> Dictionary:
	var tier := clampi(wanted, 1, 5)
	var count := [1, 2, 3, 4, 4][tier - 1]
	# Target speeds are requested cruise caps, not magic top-speed boosts.
	# Every officer has the same ordinary vehicle dynamics as other cars.
	return {
		"units": count,
		"throttle": [0.68, 0.72, 0.77, 0.81, 0.85][tier - 1],
		"cruise_mps": [20.0, 22.0, 23.0, 24.0, 25.0][tier - 1],
		"sight_m": [100.0, 110.0, 120.0, 130.0, 140.0][tier - 1],
		"search_seconds": [11.0, 14.0, 17.0, 20.0, 24.0][tier - 1]
	}

static func role(index: int, wanted: int) -> String:
	var roles := ["pursuer", "intercept", "flank_left", "roadblock"]
	if wanted <= 3 and index == 3:
		return "flank_right"
	return roles[clampi(index, 0, roles.size() - 1)]

static func safe_spawn(position_m: Vector2, player_m: Vector2,
		travel_dir: Vector2, prior_units_m: Array[Vector2]) -> bool:
	if not position_m.is_finite() or not player_m.is_finite():
		return false
	var delta := position_m - player_m
	var distance := delta.length()
	if distance < SPAWN_MIN_M or distance > SPAWN_MAX_M:
		return false
	var travel := travel_dir.normalized()
	if travel.length_squared() > 0.5 and delta.normalized().dot(travel) > SPAWN_FORWARD_DOT_LIMIT:
		# No spawning directly in front of a moving player's trajectory.
		return false
	for prior in prior_units_m:
		if prior.distance_to(position_m) < SPAWN_SEPARATION_M:
			return false
	return true

static func visible(distance_m: float, wanted: int, blocked: bool) -> bool:
	return is_finite(distance_m) and not blocked and 		distance_m <= float(profile(wanted)["sight_m"])

static func intercept_target(last_m: Vector2, known_velocity_mps: Vector2,
		heading: Vector2, role_name: String, wanted: int) -> Vector2:
	var direction := known_velocity_mps.normalized() if known_velocity_mps.length() >= 3.0 else heading.normalized()
	if direction.length_squared() < 0.5:
		direction = Vector2.UP
	var right := Vector2(-direction.y, direction.x)
	var predicted := last_m + known_velocity_mps.limit_length(24.0) * 		clampf(0.9 + float(clampi(wanted, 1, 5)) * 0.28, 1.0, 2.3)
	match role_name:
		"intercept":
			return predicted
		"flank_left":
			return predicted - right * 7.0 - direction * 3.0
		"flank_right":
			return predicted + right * 7.0 - direction * 3.0
		_:
			return last_m - direction * 3.0

static func containment_target(known_m: Vector2, heading: Vector2,
		role_name: String) -> Vector2:
	# Three real officers drive to a broad triangular ring (120° apart)
	# only when the suspect has slowed and they are already nearby.
	# Merely targeting these positions is NOT an arrest: the existing
	# collision-based proximity/angle/4-second rules remain mandatory.
	var forward := heading.normalized()
	if forward.length_squared() < 0.5:
		forward = Vector2.UP
	var right := Vector2(-forward.y, forward.x)
	match role_name:
		"intercept":
			return known_m + forward * 5.4
		"flank_left":
			return known_m - forward * 2.7 + right * 4.67
		"flank_right":
			return known_m - forward * 2.7 + right * 4.67
		_:
			return known_m - forward * 2.7 - right * 4.67

static func roadblock_candidate(candidates: Array[Dictionary], last_m: Vector2,
		heading: Vector2) -> Dictionary:
	# Roadblocks are assignments for ALREADY-DRIVING officers, never a
	# newly materialized wall in the driver's projected lane.
	if heading.length_squared() < 0.5:
		return {}
	var heading_unit := heading.normalized()
	var best := INF
	var selected: Dictionary = {}
	for item in candidates:
		var point: Vector2 = item.get("position_m", Vector2.INF)
		if not point.is_finite():
			continue
		var offset := point - last_m
		var ahead := offset.dot(heading_unit)
		var lateral := absf(offset.cross(heading_unit))
		if ahead < BLOCKADE_MIN_M or ahead > BLOCKADE_MAX_M or lateral > 38.0:
			continue
		var score := absf(ahead - 130.0) + lateral * 1.8
		if score < best:
			best = score
			selected = item
	return selected.duplicate(true)

static func search_target(last_m: Vector2, heading: Vector2,
		unit_index: int, search_round: int) -> Vector2:
	# Search only the last OBSERVED location and nearby lanes. No access
	# to the hidden suspect position or their GPS mission destination.
	if search_round <= 0:
		return last_m
	var forward := heading.normalized()
	if forward.length_squared() < 0.5:
		forward = Vector2.UP
	var right := Vector2(-forward.y, forward.x)
	var pattern: Array[Vector2] = [
		right * 24.0, -right * 24.0, forward * 31.0,
		-forward * 24.0, forward * 14.0 + right * 34.0,
		forward * 14.0 - right * 34.0
	]
	var index := posmod(unit_index + search_round - 1, pattern.size())
	return last_m + pattern[index]
