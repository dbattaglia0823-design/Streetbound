extends SceneTree
## Fixed gameplay rewards, authored marker links and anti-duplicate payouts.
const Contracts = preload("res://scripts/world/driving_contract_rules.gd")
const MarkerRules = preload("res://scripts/world/authored_marker_rules.gd")
const Ownership = preload("res://scripts/vehicle/vehicle_ownership.gd")
const Session = preload("res://scripts/dev/native_map_edit_session.gd")
const ContractRuntime = preload("res://scripts/world/driving_contracts.gd")
const MarkerRuntime = preload("res://scripts/world/authored_map_markers.gd")
const PoliceRuntime = preload("res://scripts/world/police_pursuit.gd")
const PlayerScene = preload("res://scenes/vehicle.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(name: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL",name])
	if not ok:
		failures.append(name)

func marker(id: String, kind: String, x: float, y: float, props: Dictionary = {}) -> Dictionary:
	return {"id":id,"name":id,"type":kind,"x":x,"y":y,
		"rotation":0.0,"properties":props}

func run() -> void:
	var source := marker("marker-2","contract",100.0,100.0,
		{"contract_kind":"getaway","destination_marker_id":"marker-3"})
	var destination := marker("marker-3","contract_dropoff",350.0,100.0)
	check("valid_getaway_source_destination", Contracts.valid_link(source,destination))
	check("getaway_requires_two_wanted_stars",Contracts.wanted_level("getaway")==2)
	check("courier_is_legal",Contracts.wanted_level("courier")==0)
	check("smuggling_requires_police",Contracts.wanted_level("smuggling")==1)
	check("invalid_kind_rejected",not Contracts.valid_kind("on_foot"))
	check("arrival_requires_slow_car",Contracts.arrived(10.0,0.1)
		and not Contracts.arrived(10.0,5.0)
		and not Contracts.arrived(25.0,0.1))
	var close := marker("marker-3","contract_dropoff",130.0,100.0)
	check("short_delivery_cannot_be_rewarded",not Contracts.valid_link(source,close))
	var wrong_kind := marker("marker-3","garage",350.0,100.0)
	check("contract_must_target_dropoff",not Contracts.valid_link(source,wrong_kind))
	check("valid_authoring_links",MarkerRules.valid_links([source,destination],[],[]))
	check("missing_link_rejected",not MarkerRules.valid_links([source],[],[]))
	check("wrong_destination_kind_rejected",not MarkerRules.valid_links([source,wrong_kind],[],[]))
	var corrupted := source.duplicate(true)
	corrupted.properties.contract_kind="walk"
	check("invalid_authored_contract_kind_rejected",not MarkerRules.valid(corrupted))
	var draft := source.duplicate(true)
	draft.properties.erase("destination_marker_id")
	check("incomplete_marker_allowed_until_linked",MarkerRules.valid_links([draft,destination],[],[]))

	var economy := Ownership.new(false)
	var balance_before: int = economy.balance
	var rep_before: int = economy.underground_reputation
	var payout: Dictionary = economy.record_driving_contract(
		"contract-test-run-0001","test-world::marker-2","getaway")
	check("fixed_game_owned_rewards",payout.get("result","")=="completed" and
		economy.balance==balance_before+1350 and
		economy.player_xp==290 and
		economy.underground_reputation==rep_before+5)
	check("contract_records_per_world",int(economy.completed_driving_contracts.get(
		"test-world::marker-2",0))==1)
	var before_duplicate: int = economy.balance
	check("cannot_double_claim_run",economy.record_driving_contract(
		"contract-test-run-0001","test-world::marker-2","getaway").get("result","")=="invalid_or_duplicate"
		and economy.balance==before_duplicate)
	check("invalid_reward_kind_rejected",economy.record_driving_contract(
		"contract-test-run-0002","test-world::marker-2","arbitrary").get("result","")=="invalid_or_duplicate"
		and economy.balance==before_duplicate)
	var courier: Dictionary = economy.record_driving_contract(
		"contract-test-run-0003","test-world::marker-2","courier")
	check("courier_pays_without_criminal_reputation",courier.get("result","")=="completed"
		and int(courier.get("underground_rep",-1))==0 and economy.underground_reputation==rep_before+5)
	check("repeat_contract_safely_counts",int(economy.completed_driving_contracts.get(
		"test-world::marker-2",0))==2)
	check("cross_map_counts_independent",int(economy.completed_driving_contracts.get(
		"another-world::marker-2",0))==0)

	# Real native-editor source validation and undo support for contract links.
	var session := Session.new()
	session.doc = {"format":"gdt.racing-world","version":2,"customMap":true,
		"name":"Contracts Test World","world":{"width":1000,"height":1000,"base":"grass"},
		"roads":[],"regions":[],"props":[],"markers":[source,destination],
		"assets":[],"races":[],"dealerships":[]}
	check("contract_editor_accepts_source",session._valid_source(session.doc))
	check("edit_undo_contract_type",session.update_marker("marker-2",
		{"properties":{"contract_kind":"smuggling","destination_marker_id":"marker-3"}})
		and str(session.marker_at_id("marker-2").properties.contract_kind)=="smuggling"
		and session.undo()
		and str(session.marker_at_id("marker-2").properties.contract_kind)=="getaway")
	# Execute the actual reward completion seam with an in-world car
	# rather than relying only on the pure rules.
	var vehicle: VehicleController2D = PlayerScene.instantiate()
	vehicle.external_input = true
	root.add_child(vehicle)
	await physics_frame
	var police: Node2D = Node2D.new()
	police.set_script(PoliceRuntime)
	var source_markers: Node2D = Node2D.new()
	source_markers.set_script(MarkerRuntime)
	source_markers.set("world_id","test-world")
	var runtime: Node2D = Node2D.new()
	runtime.set_script(ContractRuntime)
	runtime.set("player",vehicle)
	runtime.set("police",police)
	runtime.set("marker_source",source_markers)
	runtime.set("economy",economy)
	runtime.set("active",source.duplicate(true))
	runtime.set("destination",destination.duplicate(true))
	runtime.set("remaining_seconds",60.0)
	runtime.set("run_token","contract-runtime-completed-0005")
	runtime.set("started_car_id",str(economy.active_id))
	vehicle.position = Vector2(float(destination.x),float(destination.y))*20.0
	vehicle.linear_velocity = Vector2.ZERO
	var before_completion: int = economy.balance
	runtime.call("_physics_process",0.02)
	check("real_vehicle_dropoff_pays_once",economy.balance==before_completion+1350
		and (runtime.get("active") as Dictionary).is_empty())
	runtime.call("_physics_process",0.02)
	check("completed_job_cannot_pay_second_time",economy.balance==before_completion+1350)
	runtime.set("active",source.duplicate(true))
	runtime.set("destination",destination.duplicate(true))
	runtime.set("remaining_seconds",60.0)
	runtime.set("run_token","contract-runtime-busted-0006")
	runtime.set("started_car_id",str(economy.active_id))
	runtime.call("_on_police_busted","BOXED IN")
	var after_busted: int = economy.balance
	runtime.call("_physics_process",0.02)
	check("busted_job_cannot_pay",economy.balance==after_busted and
		(runtime.get("active") as Dictionary).is_empty())
	runtime.free()
	source_markers.free()
	police.free()
	vehicle.queue_free()
	print("DRIVING CONTRACTS: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)
