extends RefCounted
## Fixed, bounded, vehicle-only jobs. The map may choose the job kind and
## destination, never its cash/XP values; rewards stay game-authoritative.
const KINDS = ["courier", "smuggling", "getaway"]
const MIN_TRIP_M := 100.0
const MAX_TRIP_M := 15000.0
const ARRIVAL_RADIUS_M := 12.0
const MAX_ARRIVAL_SPEED_MPS := 1.5
const TIME_LIMIT_SECONDS := {"courier": 270.0, "smuggling": 240.0, "getaway": 210.0}
const REWARDS := {
	"courier": {"cash": 550, "player_xp": 180, "car_xp": 120, "underground_rep": 0},
	"smuggling": {"cash": 950, "player_xp": 230, "car_xp": 175, "underground_rep": 3},
	"getaway": {"cash": 1350, "player_xp": 290, "car_xp": 200, "underground_rep": 5}
}
const WANTED := {"courier": 0, "smuggling": 1, "getaway": 2}

static func valid_kind(kind: String) -> bool:
	return kind in KINDS

static func valid_link(source: Dictionary, destination: Dictionary) -> bool:
	if str(source.get("type","")) != "contract" or str(destination.get("type","")) != "contract_dropoff":
		return false
	var props: Dictionary = source.get("properties",{})
	if not valid_kind(str(props.get("contract_kind","courier"))):
		return false
	var id := str(props.get("destination_marker_id",""))
	if id.is_empty() or id != str(destination.get("id","")) or id == str(source.get("id","")):
		return false
	for marker in [source,destination]:
		if not marker.has("x") or not marker.has("y"):
			return false
		if not is_finite(float(marker.x)) or not is_finite(float(marker.y)):
			return false
	var distance_m := Vector2(float(source.x),float(source.y)).distance_to(
		Vector2(float(destination.x),float(destination.y)))
	return distance_m >= MIN_TRIP_M and distance_m <= MAX_TRIP_M

static func arrived(distance_m: float, speed_mps: float) -> bool:
	return is_finite(distance_m) and is_finite(speed_mps) and distance_m <= ARRIVAL_RADIUS_M and 		speed_mps <= MAX_ARRIVAL_SPEED_MPS

static func reward(kind: String) -> Dictionary:
	return REWARDS.get(kind, {}).duplicate()

static func time_limit(kind: String) -> float:
	return float(TIME_LIMIT_SECONDS.get(kind, 0.0))

static func wanted_level(kind: String) -> int:
	return int(WANTED.get(kind, 0))
