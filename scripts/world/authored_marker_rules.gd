extends RefCounted
## Canonical map marker schema. Existing saved landmarks with no properties
## remain valid; playable marker types acquire typed optional links.
const TYPES=["player_spawn","garage","dealership","mission","fast_travel",
	"traffic_spawn","fuel","checkpoint","race_start","finish","custom"]
const EventRules=preload("res://scripts/world/authored_event_rules.gd")

static func valid(marker: Dictionary) -> bool:
	var kind: String=str(marker.get("type",""))
	if kind not in TYPES:return false
	if str(marker.get("name","")).length()>120:return false
	var properties: Variant=marker.get("properties",{})
	if not properties is Dictionary:return false
	for field in ["race_id","dealer_id","required_race"]:
		if properties.has(field):
			if not properties[field] is String or str(properties[field]).length()>100:return false
	if properties.has("enabled") and typeof(properties.enabled)!=TYPE_BOOL:return false
	if properties.has("radius_m"):
		var distance: Variant=properties.radius_m
		if typeof(distance) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(distance)) or \
				float(distance)<4.0 or float(distance)>50.0:return false
	if properties.has("traffic_weight"):
		var weight: Variant=properties.traffic_weight
		if typeof(weight) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(weight)) or \
				float(weight)!=floorf(float(weight)) or float(weight)<1 or float(weight)>10:return false
	return true

static func valid_links(markers: Array,races: Array,dealers: Array) -> bool:
	var event_ids: Dictionary={}
	for race in races:event_ids[str(race.get("id",""))]=true
	var dealer_ids: Dictionary={}
	for dealer in dealers:dealer_ids[str(dealer.get("id",""))]=true
	var spawns:=0
	for marker in markers:
		if not marker is Dictionary or not valid(marker):return false
		if str(marker.type)=="player_spawn":spawns+=1
		var info: Dictionary=marker.get("properties",{})
		for name in ["race_id","required_race"]:
			if not str(info.get(name,"")).is_empty() and not event_ids.has(str(info[name])):return false
		if not str(info.get("dealer_id","")).is_empty() and not dealer_ids.has(str(info.dealer_id)):return false
	return spawns<=1

static func unlocked(marker: Dictionary,economy: Object,world_id: String) -> bool:
	var required: String=str(marker.get("properties",{}).get("required_race",""))
	return required.is_empty() or economy==null or \
		economy.completed_event_count(EventRules.event_key(world_id,required))>0
