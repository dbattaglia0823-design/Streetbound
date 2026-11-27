extends SceneTree
const Rules=preload("res://scripts/world/living_world_rules.gd")
const Ownership=preload("res://scripts/vehicle/vehicle_ownership.gd")
const Contracts=preload("res://scripts/world/driving_contract_rules.gd")
const MarkerRules=preload("res://scripts/world/authored_marker_rules.gd")
var failed:=0

func check(ok: bool,label: String) -> void:
	if not ok:failed+=1;printerr("FAIL ",label)

func _initialize() -> void:
	check(Rules.hour(90000)==1.0 and Rules.day(90000)==2,"day rollover")
	check(Rules.until_hour(23*3600,6)==7*3600 and Rules.until_hour(6*3600,6)==86400,"next morning")
	check(Rules.open_at(8*3600,"dealership") and not Rules.open_at(20*3600,"dealership"),"business opening boundaries")
	check(Rules.open_at(2*3600,"fuel"),"fuel remains 24h")
	check(Rules.traffic_factor(8*3600)>Rules.traffic_factor(12*3600) and Rules.traffic_factor(2*3600)<1.0,"rush and night traffic")
	check(Rules.tint(0).r<Rules.tint(43200).r,"day night lighting")
	var rain:=Rules.rain(43200,Vector2(100,200),1847)
	check(rain==Rules.rain(43200,Vector2(100,200),1847) and rain>=0 and rain<=1,"deterministic bounded weather")
	check(Rules.rain(43200,Vector2(100,200),1847,.8)>=.8,"authored rain floor")
	check(Rules.can_rest(true,true,false,false) and not Rules.can_rest(true,true,true,false) and not Rules.can_rest(true,true,false,true) and not Rules.can_rest(false,true,false,false),"rest safety")
	check(MarkerRules.valid({"type":"home","properties":{"radius_m":15}}) and not MarkerRules.valid({"type":"home","properties":{"road_layer":1}}),"home marker ground level")
	var economy:=Ownership.new(false)
	var offer:=Contracts.make_robbery_offer("convenience","target","dropoff")
	var now:=10000
	var key:=Contracts.location_key("test",offer)
	economy.robbery_cooldowns[key]=now+100
	var before:=economy.robbery_availability("test",offer,now,0)
	var after:=economy.robbery_availability("test",offer,now,600)
	check(before.cooldown==100 and after.cooldown==100 and not after.available,"time skip does not erase UTC cooldown")
	if failed==0:print("LIVING WORLD: PASS")
	quit(0 if failed==0 else 1)
