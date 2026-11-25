extends RefCounted
## Author-time and runtime rules for the world race career graph.
## Optional fields keep older authored races compatible.
const Catalog=preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const CATEGORIES=["street","circuit","time_trial","championship","challenge"]
const DIFFICULTIES=["rookie","amateur","pro","elite"]
const MAX_CASH=1000000
const MAX_XP=100000
const MAX_ENTRY_FEE=50000

static func valid_event(race: Dictionary) -> bool:
	if str(race.get("category","street")) not in CATEGORIES:return false
	if str(race.get("difficulty","rookie")) not in DIFFICULTIES:return false
	if typeof(race.get("repeatable",true))!=TYPE_BOOL:return false
	for spec in [["required_player_level",1,100],["required_car_level",1,50],
		["first_win_reward_cash",0,MAX_CASH],["first_win_reward_player_xp",0,MAX_XP],
		["first_win_reward_car_xp",0,MAX_XP],["race_heat",0,5],
		["escape_time_limit",30,300],["entry_fee",0,MAX_ENTRY_FEE],
		["underground_rep_reward",0,30],["required_underground_rep",0,100000]]:
		var value: Variant=race.get(spec[0],spec[1])
		if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or \
				float(value)!=floorf(float(value)) or float(value)<spec[1] or float(value)>spec[2]:return false
	if int(race.get("race_heat",0))==0 and int(race.get("underground_rep_reward",0))>0:return false
	var predecessors: Variant=race.get("prerequisite_races",[])
	if not predecessors is Array or predecessors.size()>16:return false
	var seen: Dictionary={}
	for id in predecessors:
		if not id is String or not id.begins_with("race-") or seen.has(id) or id==race.get("id",""):return false
		seen[id]=true
	var vehicles: Variant=race.get("required_vehicle_ids",[])
	if not vehicles is Array or vehicles.size()>128:return false
	seen.clear()
	for id in vehicles:
		if not id is String or seen.has(id) or Catalog.find_by_id(id).is_empty():return false
		seen[id]=true
	return true

static func valid_graph(races: Array) -> bool:
	var events: Dictionary={}
	for event in races:
		if not event is Dictionary or not valid_event(event):return false
		var id: String=str(event.get("id",""))
		if not id.begins_with("race-") or events.has(id):return false
		events[id]=event
	var visited: Dictionary={}
	for id in events:
		if not _walk(id,events,visited):return false
	return true

static func _walk(id: String,events: Dictionary,marks: Dictionary) -> bool:
	if not events.has(id):return false
	if int(marks.get(id,0))==1:return false
	if int(marks.get(id,0))==2:return true
	marks[id]=1
	for prereq in events[id].get("prerequisite_races",[]):
		if not _walk(str(prereq),events,marks):return false
	marks[id]=2
	return true

static func event_key(world_id: String,race_id: String) -> String:
	return world_id+"::"+race_id

static func lock_reason(race: Dictionary,economy: Object,world_id: String="morrow-coast") -> String:
	if economy==null:return ""
	var event_id:=event_key(world_id,str(race.get("id","")))
	if not bool(race.get("repeatable",true)) and economy.completed_event_count(event_id)>0:
		return "EVENT COMPLETED"
	if economy.player_level()<int(race.get("required_player_level",1)):
		return "REQUIRES DRIVER LEVEL %d"%int(race.required_player_level)
	if economy.active_car_level()<int(race.get("required_car_level",1)):
		return "REQUIRES VEHICLE LEVEL %d"%int(race.required_car_level)
	if int(race.get("required_underground_rep",0))>0 and int(economy.get("underground_reputation"))<int(race.get("required_underground_rep",0)):
		return "REQUIRES UNDERGROUND REP %d"%int(race.get("required_underground_rep",0))
	var allowed: Array=race.get("required_vehicle_ids",[])
	if not allowed.is_empty() and not allowed.has(str(economy.active_id)):
		return "CURRENT VEHICLE IS NOT ELIGIBLE"
	for prerequisite in race.get("prerequisite_races",[]):
		if economy.completed_event_count(event_key(world_id,str(prerequisite)))==0:
			return "COMPLETE EVENT %s FIRST"%str(prerequisite)
	return ""
