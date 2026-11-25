extends SceneTree
const Economy=preload("res://scripts/vehicle/vehicle_ownership.gd")
const Rules=preload("res://scripts/world/authored_event_rules.gd")
const Markers=preload("res://scripts/world/authored_marker_rules.gd")
const Race=preload("res://scripts/world/authored_race.gd")
const Contracts=preload("res://scripts/world/driving_contracts.gd")
const PlayerScene=preload("res://scenes/vehicle.tscn")
var failures:Array[String]=[]

class PoliceStub extends Node2D:
	var wanted_level:=3
	var bust_timer:=0.0

class GuidanceStub extends Node2D:
	func set_guidance(_route: Variant,_car: Variant,_enabled: bool) -> void:
		pass

class MarkerStub extends Node2D:
	var world_id:="underground-test"
	var races:Array=[]

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	print("%s %s"%["PASS" if passed else "FAIL",label])
	if not passed:failures.append(label)

func run() -> void:
	var economy:=Economy.new(false)
	var event:Dictionary={"id":"race-underground","race_heat":3,"escape_time_limit":90,
		"entry_fee":2000,"reward_cash":7000,"reward_player_xp":500,"reward_car_xp":300,
		"underground_rep_reward":6,"first_win_reward_cash":500}
	var key:="underground-test::race-underground"
	check("legacy_legal_event_still_valid",Rules.valid_event({"id":"race-legal"}))
	check("underground_event_valid",Rules.valid_event(event))
	for patch in [{"race_heat":6},{"entry_fee":50001},{"escape_time_limit":301},
			{"underground_rep_reward":31},{"race_heat":0}]:
		var invalid:Dictionary=event.duplicate()
		invalid.merge(patch,true)
		check("invalid_underground_field_"+str(patch),not Rules.valid_event(invalid))
	var initial:int=economy.balance
	check("entry_fee_debited_once",economy.pay_race_entry(event) and economy.balance==initial-2000)
	var before:int=economy.balance
	check("no_illegal_race_prize_during_pursuit",economy.record_authored_race(
		"underground-test-run",60.0,event,key,false).get("result")=="escape_required"
		and economy.balance==before and economy.underground_reputation==0)
	var car:VehicleController2D=PlayerScene.instantiate()
	car.external_input=true
	root.add_child(car)
	await physics_frame
	var police:=PoliceStub.new()
	var guidance:=GuidanceStub.new()
	var race:Node2D=Race.new()
	race.set("player",car)
	race.set("police",police)
	race.set("world_guidance",guidance)
	race.set("definition",event)
	race.set("economy",economy)
	race.set("world_id","underground-test")
	race.set("_run_id","underground-test-run")
	race.set("staged_car_id",economy.active_id)
	race.set("state","running")
	race.set("available",true)
	race.set("elapsed",60.0)
	race.call("_complete_course")
	check("finishing_route_creates_escape_phase",bool(race.get("awaiting_escape"))
		and economy.balance==before)
	race.call("_physics_process",1.0)
	check("heat_keeps_prize_pending",economy.balance==before)
	police.wanted_level=0
	race.call("_physics_process",1.0)
	check("escape_settles_cash_xp_rep_once",economy.balance==before+7500
		and economy.player_xp==500 and economy.underground_reputation==6
		and economy.completed_event_count(key)==1)
	check("duplicate_race_reward_rejected",economy.record_authored_race(
		"underground-test-run",60.0,event,key,true).get("result")=="invalid_or_duplicate")
	var marker_source:=MarkerStub.new()
	var contracts:Node2D=Contracts.new()
	contracts.set("economy",economy)
	contracts.set("marker_source",marker_source)
	var contact:Dictionary={"id":"marker-contact"}
	var offer:Dictionary={"id":"job_1","required_race_id":"race-underground"}
	check("race_win_unlocks_contact_offer",str(contracts.call("offer_lock_reason",contact,offer)).is_empty())
	offer.required_race_id="race-unwon"
	check("unwon_race_locks_contact_offer",str(contracts.call("offer_lock_reason",contact,offer)).contains("WIN"))
	economy.balance=0
	check("cannot_pay_unaffordable_entry",not economy.pay_race_entry(event) and economy.balance==0)
	contracts.free()
	marker_source.free()
	race.free()
	guidance.free()
	police.free()
	car.queue_free()
	print("UNDERGROUND RACING: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
