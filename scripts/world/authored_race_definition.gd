extends RefCounted
const ObjectiveLayer=preload("res://scripts/world/objective_road_layer.gd")
## Metre-space authoring contract shared by editor and race runtime.
const Grid=preload("res://scripts/world/race_start_grid.gd")
const Catalog=preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const EventRules=preload("res://scripts/world/authored_event_rules.gd")
const OnlineRewards=preload("res://scripts/network/online_race_rewards.gd")
const MAX_REWARD_CASH:=1000000
const MAX_REWARD_XP:=100000
static func valid_rewards_and_opponents(race: Dictionary) -> bool:
	var pool: Variant=race.get("opponent_pool",[])
	if not pool is Array or pool.size()>128:return false
	var seen: Dictionary={}
	for vehicle_id in pool:
		if not vehicle_id is String or str(vehicle_id).is_empty() or seen.has(vehicle_id):return false
		if Catalog.find_by_id(vehicle_id).is_empty():return false
		seen[vehicle_id]=true
	for setting in [["reward_cash",MAX_REWARD_CASH],["reward_player_xp",MAX_REWARD_XP],["reward_car_xp",MAX_REWARD_XP]]:
		var amount: Variant=race.get(setting[0],0)
		if typeof(amount) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(amount)):return false
		if float(amount)!=floorf(float(amount)) or float(amount)<0 or float(amount)>setting[1]:return false
	return OnlineRewards.valid_settings(race)
static func valid(race: Dictionary,width: float,height: float) -> bool:
	if not str(race.get("id","")).begins_with("race-") or str(race.get("name","")).strip_edges().is_empty() or str(race.get("name","")).length()>80:return false
	if race.get("mode","") not in ["sprint","circuit"]:return false
	var kind: String=str(race.get("race_kind",""))
	if not kind.is_empty():
		if kind not in ["point_to_point","circuit","time_trial"]:return false
		if (kind=="circuit")!=(str(race.mode)=="circuit"):return false
		if kind=="time_trial" and not race.get("enemy_starts",[]).is_empty():return false
	var points= race.get("points")
	if not points is Array or points.size()<(3 if race.mode=="circuit" else 2) or points.size()>100:return false
	for i in points.size():
		if not points[i] is Dictionary:return false
		if not ObjectiveLayer.valid_layer(points[i].get("road_layer",0)):return false
		var p:=Vector2(float(points[i].get("x",-1)),float(points[i].get("y",-1)))
		if not p.is_finite() or p.x<0 or p.y<0 or p.x>width or p.y>height:return false
		if i>0 and p.distance_to(Vector2(points[i-1].x,points[i-1].y))<5:return false
	for spec in [["laps",1,20],["checkpoint_radius",4,60],["start_radius",3,30],["time_limit",0,7200]]:
		var number= race.get(spec[0],{"laps":1,"checkpoint_radius":16,"start_radius":8,"time_limit":0}[spec[0]])
		if not typeof(number) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)) or float(number)<spec[1] or float(number)>spec[2]:return false
	var laps: float=float(race.get("laps",1))
	return laps==floorf(laps) and Grid.valid_grid(race,width,height) and valid_rewards_and_opponents(race) and EventRules.valid_event(race)
