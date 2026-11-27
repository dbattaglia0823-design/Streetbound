extends RefCounted
const ObjectiveLayer=preload("res://scripts/world/objective_road_layer.gd")
## Canonical map marker schema. Existing saved landmarks with no properties
## remain valid; playable marker types acquire typed optional links.
const TYPES=["player_spawn","home","garage","dealership","mission","fast_travel",
	"traffic_spawn","fuel","checkpoint","race_start","finish","contract","contract_dropoff","contract_contact","robbery_target","custom"]
const EventRules=preload("res://scripts/world/authored_event_rules.gd")
const Contracts=preload("res://scripts/world/driving_contract_rules.gd")

static func valid(marker: Dictionary) -> bool:
	var kind: String=str(marker.get("type",""))
	if kind not in TYPES:return false
	if str(marker.get("name","")).length()>120:return false
	var properties: Variant=marker.get("properties",{})
	if not properties is Dictionary:return false
	if not ObjectiveLayer.valid_layer(properties.get("road_layer",0)):return false
	if int(properties.get("road_layer",0))!=0 and kind not in ObjectiveLayer.MARKER_TYPES:return false
	if properties.has("description") and (not properties.description is String or str(properties.description).length()>500):return false
	for field in ["race_id","dealer_id","required_race"]:
		if properties.has(field):
			if not properties[field] is String or str(properties[field]).length()>100:return false
	if properties.has("enabled") and typeof(properties.enabled)!=TYPE_BOOL:return false
	if properties.has("contract_kind"):
		if not properties.contract_kind is String or not Contracts.valid_kind(str(properties.contract_kind)):return false
	if properties.has("contact_style") and str(properties.contact_style) not in ["street","business","mechanic","casual","racing"]:return false
	for pair in [["contact_role",60],["contact_greeting",180],["contact_bio",240]]:
		var field: String = str(pair[0])
		if properties.has(field) and (not properties[field] is String or str(properties[field]).length()>int(pair[1])):return false
	if properties.has("offers") and (kind != "contract_contact" or not properties.offers is Array or properties.offers.size()>Contracts.MAX_OFFERS):
		return false
	if properties.has("destination_marker_id"):
		if not properties.destination_marker_id is String or str(properties.destination_marker_id).length()>100:return false
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
	var by_id: Dictionary={}
	for marker in markers:
		if not marker is Dictionary:return false
		var id:=str(marker.get("id",""))
		if id.is_empty() or by_id.has(id):return false
		by_id[id]=marker
	for marker in markers:
		if not marker is Dictionary or not valid(marker):return false
		if str(marker.type)=="player_spawn":spawns+=1
		var info: Dictionary=marker.get("properties",{})
		for name in ["race_id","required_race"]:
			if not str(info.get(name,"")).is_empty() and not event_ids.has(str(info[name])):return false
		if not str(info.get("dealer_id","")).is_empty() and not dealer_ids.has(str(info.dealer_id)):return false
		if str(marker.type)=="contract_contact":
			if not Contracts.valid_contact(marker,by_id):return false
			for offer in info.get("offers",[]):
				var prerequisite:=str(offer.get("required_race_id",""))
				if not prerequisite.is_empty() and not event_ids.has(prerequisite):return false
		if str(marker.type)=="contract":
			var destination_id:=str(info.get("destination_marker_id",""))
			if not destination_id.is_empty():
				if not by_id.has(destination_id) or not Contracts.valid_link(marker,by_id[destination_id]):return false
	return spawns<=1

static func unlocked(marker: Dictionary,economy: Object,world_id: String) -> bool:
	var required: String=str(marker.get("properties",{}).get("required_race",""))
	return required.is_empty() or economy==null or \
		economy.completed_event_count(EventRules.event_key(world_id,required))>0
