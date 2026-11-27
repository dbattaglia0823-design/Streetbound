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
## Ranks are derived from the saved reputation, never stored independently.
## The actual robbery thresholds remain the single source of truth.
const CAREER_RANKS := [
	{"name":"Unknown","rep":0,"tier":"","future":""},
	{"name":"Street Prospect","rep":5,"tier":"convenience","future":""},
	{"name":"Wheelman","rep":25,"tier":"pawn","future":"Entry-level crew"},
	{"name":"Professional","rep":60,"tier":"jewelry","future":"Basic black-market upgrades"},
	{"name":"Veteran","rep":120,"tier":"warehouse","future":"Veteran crew"},
	{"name":"Mastermind","rep":250,"tier":"bank","future":"Advanced black-market upgrades"},
	{"name":"Underground Legend","rep":500,"tier":"","future":"Elite crew"}
]
## Future consumers use stable IDs; eligibility does not imply implementation.
const CAREER_ACCESS := {"entry_crew":25,"basic_black_market":60,"veteran_crew":120,
	"advanced_black_market":250,"elite_crew":500}

static func rank_threshold(index: int) -> int:
	var row: Dictionary = CAREER_RANKS[clampi(index,0,CAREER_RANKS.size()-1)]
	var tier := str(row["tier"])
	return int(ROBBERY_TIERS[tier]["required_rep"]) if not tier.is_empty() else int(row["rep"])

static func rank_index(reputation: int) -> int:
	var index := 0
	for i in CAREER_RANKS.size():
		if reputation >= rank_threshold(i):
			index = i
	return index

static func rank_name(reputation: int) -> String:
	return str(CAREER_RANKS[rank_index(reputation)]["name"])

static func career_state(reputation: int) -> Dictionary:
	var rep_value := clampi(reputation,0,100000)
	var index := rank_index(rep_value)
	var at_max := index == CAREER_RANKS.size()-1
	var floor_value := rank_threshold(index)
	var next_value := floor_value if at_max else rank_threshold(index+1)
	return {"rank":rank_name(rep_value),"index":index,"rep":rep_value,
		"next_rank":"" if at_max else str(CAREER_RANKS[index+1]["name"]),
		"next_rep":next_value,"remaining":maxi(0,next_value-rep_value),
		"progress":1.0 if at_max else clampf(float(rep_value-floor_value)/float(maxi(1,next_value-floor_value)),0.0,1.0),
		"max_rank":at_max}

static func has_career_access(key: String, reputation: int) -> bool:
	return CAREER_ACCESS.has(key) and reputation >= int(CAREER_ACCESS.get(key,100001))

static func promotion_text(previous: int, current: int) -> String:
	if rank_index(current) <= rank_index(previous):
		return ""
	return "RANK UP / "+rank_name(current).to_upper()

static func robbery_unlocks(reputation: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for tier in ROBBERY_ORDER:
		var profile: Dictionary = ROBBERY_TIERS[tier]
		var threshold := int(profile["required_rep"])
		result.append({"tier":tier,"title":profile["title"],"required_rep":threshold,
			"remaining":maxi(0,threshold-reputation),"eligible":reputation>=threshold})
	return result
const ROBBERY_RISKS := ["quick","standard","maximum"]
const ROBBERY_RISK_RULES := {
	"quick":{"cash_factor":0.6,"hold_factor":0.65,"heat_delta":-1,"rep_factor":0.75},
	"standard":{"cash_factor":1.0,"hold_factor":1.0,"heat_delta":0,"rep_factor":1.0},
	"maximum":{"cash_factor":1.45,"hold_factor":1.5,"heat_delta":1,"rep_factor":1.25}
}
const MAX_PROFILE_CASH := 250000
## Fictional specialists with abstract mission-stat bonuses.
const CREW_ORDER := ["rookie","technician","veteran","specialist","coordinator","elite"]
const CREW := {
	"rookie":{"name":"Jules","role":"Rookie","gate":"entry_crew","fee":1500,"cut":0.03,"speed":0.0,"cash":0.04,"rep":0,"time":0.0},
	"technician":{"name":"Mika","role":"Technician","gate":"entry_crew","fee":4000,"cut":0.05,"speed":0.12,"cash":0.0,"rep":0,"time":0.0},
	"veteran":{"name":"Reed","role":"Veteran","gate":"veteran_crew","fee":12000,"cut":0.07,"speed":0.15,"cash":0.0,"rep":3,"time":0.0},
	"specialist":{"name":"Nova","role":"Specialist","gate":"veteran_crew","fee":18000,"cut":0.07,"speed":0.0,"cash":0.12,"rep":0,"time":0.0},
	"coordinator":{"name":"Sage","role":"Coordinator","gate":"elite_crew","fee":35000,"cut":0.05,"speed":0.0,"cash":0.0,"rep":2,"time":0.15},
	"elite":{"name":"Voss","role":"Elite","gate":"elite_crew","fee":65000,"cut":0.09,"speed":0.20,"cash":0.18,"rep":3,"time":0.0}
}
const CREW_MAX_XP := 400
const CREW_MAX_ACTIVE := 3

static func crew_level(xp: int) -> int:
	return 1 + floori(float(clampi(xp,0,CREW_MAX_XP))/100.0)

static func crew_xp_reward(offer: Dictionary) -> int:
	return int({"quick":15,"standard":25,"maximum":35}.get(robbery_risk(offer),25))

static func crew_ids_valid(offer: Dictionary, ids: Array, roster: Dictionary, reputation: int) -> bool:
	if ids.size() > robbery_payload(offer).x or ids.size() > CREW_MAX_ACTIVE:
		return false
	var seen: Dictionary = {}
	for id in ids:
		if not id is String or not CREW.has(id) or not roster.has(id) or seen.has(id):
			return false
		if not has_career_access(str(CREW[id]["gate"]),reputation):
			return false
		seen[id] = true
	return true

static func crew_quote(offer: Dictionary, ids: Array, roster: Dictionary) -> Dictionary:
	var rewards := configured_reward("robbery",offer)
	var speed := 0.0
	var extra_cash := 0.0
	var extra_rep := 0
	var extra_time := 0.0
	var share := 0.0
	var names: PackedStringArray = []
	for id in ids:
		if not CREW.has(id) or not roster.has(id):
			continue
		var member: Dictionary = CREW[id]
		var scale := 1.0+0.10*float(crew_level(int(roster[id]))-1)
		speed += float(member.speed)*scale
		extra_cash += float(member.cash)*scale
		extra_rep += roundi(float(member.rep)*scale)
		extra_time += float(member.time)*scale
		share += float(member.cut)
		names.append(str(member.name))
	var gross := mini(MAX_PROFILE_CASH,roundi(float(rewards.cash)*(1.0+minf(extra_cash,0.35))))
	var cut := roundi(float(gross)*minf(share,0.30))
	return {"gross":gross,"cut":cut,"cash":gross-cut,
		"underground_rep":mini(int(REWARD_LIMITS["underground_rep"]),int(rewards.underground_rep)+extra_rep),
		"hold_factor":1.0-minf(speed,0.35),"time_factor":1.0+minf(extra_time,0.25),
		"names":", ".join(names),"share":share}
## Crew count excludes the driver. Cargo is a fictional mission load in kg.
const ROBBERY_PAYLOADS := {
	"convenience":Vector2i(1,25),"pawn":Vector2i(1,75),
	"jewelry":Vector2i(2,120),"warehouse":Vector2i(3,350),"bank":Vector2i(3,500)}
const CARGO_FACTORS := {"quick":0.65,"standard":1.0,"maximum":1.35}

static func robbery_payload(offer: Dictionary) -> Vector2i:
	var payload: Vector2i = ROBBERY_PAYLOADS.get(str(offer.get("robbery_tier","")),Vector2i.ZERO)
	return Vector2i(payload.x,ceili(float(payload.y)*float(CARGO_FACTORS.get(robbery_risk(offer),1.0))))

static func capacity_reason(offer: Dictionary, seats: int, cargo_capacity: int) -> String:
	var payload := robbery_payload(offer)
	if payload == Vector2i.ZERO:
		return ""
	if seats < payload.x+1:
		return "NEEDS %d SEATS (INCLUDING DRIVER)" % (payload.x+1)
	if cargo_capacity < payload.y:
		return "NEEDS %d KG CARGO CAPACITY" % payload.y
	return ""

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
static func completed_lower_risk(offer: Dictionary, progress: float, hold_factor: float = 1.0) -> String:
	if robbery_profile(offer).is_empty() or not is_finite(progress):
		return ""
	var selected_index := ROBBERY_RISKS.find(robbery_risk(offer))
	for i in range(selected_index-1,-1,-1):
		var candidate: String = ROBBERY_RISKS[i]
		if progress >= maxf(3.0,configured_robbery_hold(with_robbery_risk(offer,candidate))*clampf(hold_factor,0.65,1.0)):
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
