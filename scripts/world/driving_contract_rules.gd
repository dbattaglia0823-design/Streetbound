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
## Game-owned campaign presets. Legacy authored offers retain their old caps.
## Standard payouts remain the original phase-one balance.
const ROBBERY_TIERS := {
	"convenience": {"title":"Convenience Store Robbery","difficulty":"rookie","cash":2500,"player_xp":450,"car_xp":300,"underground_rep":8,"required_rep":5,"wanted":1,"seconds":300,"hold":7},
	"pawn": {"title":"Pawn Shop Robbery","difficulty":"amateur","cash":8500,"player_xp":650,"car_xp":450,"underground_rep":12,"required_rep":25,"wanted":2,"seconds":360,"hold":9},
	"jewelry": {"title":"Jewelry Store Heist","difficulty":"pro","cash":25000,"player_xp":900,"car_xp":650,"underground_rep":18,"required_rep":60,"wanted":3,"seconds":420,"hold":12},
	"warehouse": {"title":"Warehouse Heist","difficulty":"elite","cash":60000,"player_xp":1200,"car_xp":900,"underground_rep":24,"required_rep":120,"wanted":4,"seconds":480,"hold":16},
	"bank": {"title":"Bank Heist","difficulty":"elite","cash":175000,"player_xp":1500,"car_xp":1200,"underground_rep":30,"required_rep":250,"wanted":5,"seconds":600,"hold":20}
}
const ROBBERY_ORDER := ["convenience","pawn","jewelry","warehouse","bank"]
const RACE_REPUTATION := 5
const ROBBERY_RISKS := ["quick","standard","maximum"]
const ROBBERY_RISK_RULES := {
	"quick":{"cash_factor":0.6,"hold_factor":0.65,"heat_delta":-1,"rep_factor":0.75},
	"standard":{"cash_factor":1.0,"hold_factor":1.0,"heat_delta":0,"rep_factor":1.0},
	"maximum":{"cash_factor":1.45,"hold_factor":1.5,"heat_delta":1,"rep_factor":1.25}
}
const MAX_PROFILE_CASH := 250000

static func robbery_profile(offer: Dictionary) -> Dictionary:
	return ROBBERY_TIERS.get(str(offer.get("robbery_tier","")),{}).duplicate(true)

static func robbery_risk(offer: Dictionary) -> String:
	return str(offer.get("robbery_risk","standard"))

static func with_robbery_risk(offer: Dictionary, risk: String) -> Dictionary:
	if robbery_profile(offer).is_empty() or risk not in ROBBERY_RISKS:
		return {}
	var selected := offer.duplicate(true)
	selected["robbery_risk"] = risk
	return selected

static func _risk_rule(offer: Dictionary) -> Dictionary:
	return ROBBERY_RISK_RULES.get(robbery_risk(offer), ROBBERY_RISK_RULES["standard"])

static func valid_robbery_profile(kind: String, offer: Dictionary) -> bool:
	if not offer.has("robbery_tier"):
		return not offer.has("robbery_risk")
	if offer.has("robbery_risk") and (not offer["robbery_risk"] is String or robbery_risk(offer) not in ROBBERY_RISKS):
		return false
	if kind != "robbery" or not offer["robbery_tier"] is String or robbery_profile(offer).is_empty():
		return false
	# Do not let a preset bypass the legacy authoring/economy caps.
	for field in ["cash","player_xp","car_xp","underground_rep","wanted_level","time_limit_seconds","robbery_hold_seconds"]:
		if offer.has(field):
			return false
	return true

static func required_rep(offer: Dictionary) -> int:
	return maxi(int(offer.get("required_underground_rep",0)),int(robbery_profile(offer).get("required_rep",0)))

static func make_robbery_offer(tier: String, target_id: String, dropoff_id: String) -> Dictionary:
	var profile: Dictionary = ROBBERY_TIERS.get(tier,{})
	if profile.is_empty():
		return {}
	return {"id":"job_"+tier,"title":profile["title"],"kind":"robbery",
		"robbery_tier":tier,"difficulty":profile["difficulty"],
		"robbery_marker_id":target_id,"destination_marker_id":dropoff_id,
		"repeatable":true}

## Stock campaign objectives only; no changes to published map geometry or
## authoring archives. Anchors come from named Morrow Coast roads. Runtime
## verifies proximity to drivable roads before exposing the entire board.
static func morrow_robbery_board() -> Array[Dictionary]:
	var board: Array[Dictionary] = []
	var targets := [Vector2(2640,2845),Vector2(2925,2805),Vector2(3235,2810),Vector2(3510,3105),Vector2(3085,2600)]
	var names := ["Market Street Convenience Store","Market Street Pawn Shop",
		"Market Street Jewelry Store","Warehouse Way","Civic Crescent Bank"]
	var offers: Array[Dictionary] = []
	var dropoff_id := "marker-campaign-robbery-dropoff"
	for i in ROBBERY_ORDER.size():
		var tier: String = ROBBERY_ORDER[i]
		var target_id := "marker-campaign-robbery-"+tier
		var point: Vector2 = targets[i]
		board.append({"id":target_id,"type":"robbery_target","name":names[i],
			"x":point.x,"y":point.y,"rotation":0.0,"properties":{}})
		offers.append(make_robbery_offer(tier,target_id,dropoff_id))
	board.append({"id":dropoff_id,"type":"contract_dropoff","name":"Foundry Crew Drop-off",
		"x":3310.0,"y":3290.0,"rotation":0.0,"properties":{}})
	board.append({"id":"marker-campaign-robbery-contact","type":"contract_contact",
		"name":"Laurel Underground Fixer","x":2499.0,"y":2975.0,"rotation":0.0,
		"properties":{"contact_style":"street","radius_m":16.0,"offers":offers,
			"contact_greeting":"Build your reputation on the track. Higher-paying jobs unlock as your name gets around."}})
	return board

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
	if offer.has("required_race_id") and (not offer.required_race_id is String or str(offer.required_race_id).length()>100 or (not str(offer.required_race_id).is_empty() and not str(offer.required_race_id).begins_with("race-"))):
		return false
	var kind := str(offer.get("kind",""))
	if not valid_kind(kind) or not valid_robbery_profile(kind,offer) or str(offer.get("difficulty","rookie")) not in DIFFICULTIES:
		return false
	if typeof(offer.get("repeatable",true)) != TYPE_BOOL:
		return false
	for field in ["required_player_level","required_underground_rep",
			"time_limit_seconds","wanted_level","robbery_hold_seconds",
			"arrival_radius_m"]:
		if not offer.has(field):
			continue
		var value: Variant = offer[field]

		var lowest := 1 if field == "required_player_level" else 60 if field == "time_limit_seconds" else 3 if field == "robbery_hold_seconds" else 6 if field == "arrival_radius_m" else 0
		var highest := 100 if field == "required_player_level" else 100000 if field == "required_underground_rep" else MAX_DURATION if field == "time_limit_seconds" else 30 if field == "robbery_hold_seconds" else 30 if field == "arrival_radius_m" else 5
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
	var profile := robbery_profile(offer) if kind == "robbery" else {}
	if not profile.is_empty() and valid_robbery_profile(kind,offer):
		var risk := _risk_rule(offer)
		return {"cash":mini(MAX_PROFILE_CASH,roundi(float(profile["cash"])*float(risk["cash_factor"]))),
			"player_xp":profile["player_xp"],"car_xp":profile["car_xp"],
			"underground_rep":mini(int(REWARD_LIMITS["underground_rep"]),roundi(float(profile["underground_rep"])*float(risk["rep_factor"])))}
	var result := reward(kind)
	for field in REWARD_LIMITS:
		if offer.has(field):
			result[field] = int(offer[field])
	return result

static func configured_wanted(kind: String, offer: Dictionary) -> int:
	var profile := robbery_profile(offer)
	if kind == "robbery" and not profile.is_empty():
		return clampi(int(profile["wanted"])+int(_risk_rule(offer)["heat_delta"]),1,5)
	return clampi(int(offer.get("wanted_level",wanted_level(kind))),0,5)

static func configured_time(kind: String, offer: Dictionary) -> float:
	return float(robbery_profile(offer)["seconds"]) if kind == "robbery" and not robbery_profile(offer).is_empty() else clampf(float(offer.get("time_limit_seconds",time_limit(kind))),60.0,float(MAX_DURATION))

static func configured_robbery_hold(offer: Dictionary) -> float:
	var profile := robbery_profile(offer)
	if not profile.is_empty():
		return clampf(ceilf(float(profile["hold"])*float(_risk_rule(offer)["hold_factor"])),3.0,30.0)
	return clampf(float(offer.get("robbery_hold_seconds", ROBBERY_HOLD_SECONDS)), 3.0, 30.0)

## Only an already completed lower checkpoint may replace the planned mode.
static func completed_lower_risk(offer: Dictionary, progress: float) -> String:
	if robbery_profile(offer).is_empty() or not is_finite(progress):
		return ""
	var selected_index := ROBBERY_RISKS.find(robbery_risk(offer))
	for i in range(selected_index-1,-1,-1):
		var candidate: String = ROBBERY_RISKS[i]
		if progress >= configured_robbery_hold(with_robbery_risk(offer,candidate)):
			return candidate
	return ""

static func configured_arrival_radius(offer: Dictionary) -> float:
	return clampf(float(offer.get("arrival_radius_m", ARRIVAL_RADIUS_M)), 6.0, 30.0)

static func arrived(distance_m: float, speed_mps: float, radius_m: float = ARRIVAL_RADIUS_M) -> bool:
	return is_finite(distance_m) and is_finite(speed_mps) and distance_m <= clampf(radius_m, 6.0, 30.0) and \
		speed_mps <= MAX_ARRIVAL_SPEED_MPS

static func reward(kind: String) -> Dictionary:
	return REWARDS.get(kind, {}).duplicate()

static func time_limit(kind: String) -> float:
	return float(TIME_LIMIT_SECONDS.get(kind, 0.0))

static func wanted_level(kind: String) -> int:
	return int(WANTED.get(kind, 0))
