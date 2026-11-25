extends RefCounted
## Fixed, bounded, vehicle-only jobs. The map may choose the job kind and
## destination, never its cash/XP values; rewards stay game-authoritative.
const KINDS = ["courier", "smuggling", "getaway", "robbery"]
const MIN_TRIP_M := 100.0
const MAX_TRIP_M := 15000.0
const ARRIVAL_RADIUS_M := 12.0
const MAX_ARRIVAL_SPEED_MPS := 1.5
const TIME_LIMIT_SECONDS := {"courier": 270.0, "smuggling": 240.0, "getaway": 210.0, "robbery": 360.0}
const REWARDS := {
	"courier": {"cash": 550, "player_xp": 180, "car_xp": 120, "underground_rep": 0},
	"smuggling": {"cash": 950, "player_xp": 230, "car_xp": 175, "underground_rep": 3},
	"getaway": {"cash": 1350, "player_xp": 290, "car_xp": 200, "underground_rep": 5},
	"robbery": {"cash": 2500, "player_xp": 450, "car_xp": 300, "underground_rep": 8}
}
const WANTED := {"courier": 0, "smuggling": 1, "getaway": 2, "robbery": 3}

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

## Authored contact jobs are deliberately bounded. Unlike the legacy contract
## markers, a contact may offer up to eight named jobs with specific rewards.
const MAX_OFFERS := 8
const DIFFICULTIES := ["rookie", "amateur", "pro", "elite"]
const ROBBERY_HOLD_SECONDS := 7.0
const REWARD_LIMITS := {"cash": 10000, "player_xp": 1500,
	"car_xp": 1200, "underground_rep": 30}
const MAX_DURATION := 900

static func valid_offer(offer: Dictionary, contact: Dictionary, markers_by_id: Dictionary) -> bool:
	if str(contact.get("type","")) != "contract_contact":
		return false
	var id := str(offer.get("id",""))
	if id.is_empty() or id.length() > 56 or not id.is_valid_identifier():
		return false
	var title := str(offer.get("title",""))
	if title.strip_edges().is_empty() or title.length() > 80:
		return false
	if offer.has("description") and (not offer.description is String or str(offer.description).length()>400):
		return false
	var kind := str(offer.get("kind",""))
	if not valid_kind(kind) or str(offer.get("difficulty","rookie")) not in DIFFICULTIES:
		return false
	if typeof(offer.get("repeatable",true)) != TYPE_BOOL:
		return false
	for field in ["required_player_level","required_underground_rep",
			"time_limit_seconds","wanted_level"]:
		if not offer.has(field):
			continue
		var value: Variant = offer[field]
		var lowest := 1 if field == "required_player_level" else 60 if field == "time_limit_seconds" else 0
		var highest := 100 if field == "required_player_level" else 100000 if field == "required_underground_rep" else 			MAX_DURATION if field == "time_limit_seconds" else 5
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or 				float(value) != floorf(float(value)) or int(value) < lowest or int(value) > highest:
			return false
	for field in REWARD_LIMITS:
		if not offer.has(field):
			continue
		var value: Variant = offer[field]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or 				float(value) != floorf(float(value)) or int(value) < 0 or int(value) > int(REWARD_LIMITS[field]):
			return false
	var dropoff_id := str(offer.get("destination_marker_id",""))
	if not markers_by_id.has(dropoff_id):
		return false
	var dropoff: Dictionary = markers_by_id[dropoff_id]
	if str(dropoff.get("type","")) != "contract_dropoff":
		return false
	var contact_pos := Vector2(float(contact.get("x",INF)),float(contact.get("y",INF)))
	var dropoff_pos := Vector2(float(dropoff.get("x",INF)),float(dropoff.get("y",INF)))
	if not contact_pos.is_finite() or not dropoff_pos.is_finite() or 			contact_pos.distance_to(dropoff_pos) < MIN_TRIP_M or 			contact_pos.distance_to(dropoff_pos) > MAX_TRIP_M:
		return false
	if kind == "robbery":
		var target_id := str(offer.get("robbery_marker_id",""))
		if not markers_by_id.has(target_id):
			return false
		var target: Dictionary = markers_by_id[target_id]
		if str(target.get("type","")) != "robbery_target" or target_id == dropoff_id:
			return false
		var target_pos := Vector2(float(target.get("x",INF)),float(target.get("y",INF)))
		if not target_pos.is_finite() or contact_pos.distance_to(target_pos) < MIN_TRIP_M or 				target_pos.distance_to(dropoff_pos) < MIN_TRIP_M:
			return false
	elif offer.has("robbery_marker_id") and not str(offer.robbery_marker_id).is_empty():
		return false
	return true

static func valid_contact(contact: Dictionary, markers_by_id: Dictionary) -> bool:
	if str(contact.get("type","")) != "contract_contact":
		return false
	var offers: Variant = contact.get("properties",{}).get("offers",[])
	if not offers is Array or offers.size() > MAX_OFFERS:
		return false
	var seen: Dictionary = {}
	for offer in offers:
		if not offer is Dictionary or not valid_offer(offer,contact,markers_by_id):
			return false
		if seen.has(str(offer.id)):
			return false
		seen[str(offer.id)] = true
	return true

static func configured_reward(kind: String, offer: Dictionary) -> Dictionary:
	var result := reward(kind)
	for field in REWARD_LIMITS:
		if offer.has(field):
			result[field] = int(offer[field])
	return result

static func configured_wanted(kind: String, offer: Dictionary) -> int:
	return clampi(int(offer.get("wanted_level",wanted_level(kind))),0,5)

static func configured_time(kind: String, offer: Dictionary) -> float:
	return clampf(float(offer.get("time_limit_seconds",time_limit(kind))),60.0,float(MAX_DURATION))

static func arrived(distance_m: float, speed_mps: float) -> bool:
	return is_finite(distance_m) and is_finite(speed_mps) and distance_m <= ARRIVAL_RADIUS_M and 		speed_mps <= MAX_ARRIVAL_SPEED_MPS

static func reward(kind: String) -> Dictionary:
	return REWARDS.get(kind, {}).duplicate()

static func time_limit(kind: String) -> float:
	return float(TIME_LIMIT_SECONDS.get(kind, 0.0))

static func wanted_level(kind: String) -> int:
	return int(WANTED.get(kind, 0))
