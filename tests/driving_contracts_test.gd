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
const ContactEditor = preload("res://scripts/dev/native_contract_contact_editor.gd")
const ContactVisual = preload("res://scripts/world/contract_contact_visual.gd")

class PoliceStub extends Node2D:
	signal busted(reason: String)
	var wanted_level := 0
	var bust_timer := 0.0
	func start_pursuit(level: int) -> bool:
		wanted_level=level
		return true
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

	# Stock phase-one robbery progression uses game-owned presets and actual
	# marker validation, not arbitrary increased map reward bounds.
	var board: Array[Dictionary] = Contracts.morrow_robbery_board()
	check("stock_robbery_board_links_validate", MarkerRules.valid_links(board,[],[]))
	var board_contact: Dictionary = board.back()
	var tiers: Array = board_contact.properties.offers
	check("five_stock_robbery_tiers", tiers.size()==5)
	var progression := Ownership.new(false)
	var first_tier: Dictionary = tiers[0]
	var last_tier: Dictionary = tiers[4]
	check("starter_robbery_locked_until_racing", progression.record_driving_contract("tier-locked-run-0001","morrow-coast::starter","robbery",first_tier).get("result")=="locked")
	var race_reward: Dictionary = progression.record_completed_race("rep-race-run-0001",14.0)
	check("valid_race_earns_reputation", race_reward.get("underground_rep")==5 and progression.underground_reputation==5)
	progression.record_completed_race("rep-race-run-0001",14.0)
	check("duplicate_race_cannot_earn_more_rep", progression.underground_reputation==5)
	var actual_tier: Dictionary = progression.record_driving_contract("tier-starter-run-0002","morrow-coast::starter","robbery",first_tier)
	check("starter_robbery_pays_after_unlock", actual_tier.get("cash")==2500 and progression.underground_reputation==13)
	check("bank_remains_locked", progression.record_driving_contract("tier-bank-run-0003","morrow-coast::bank","robbery",last_tier).get("result")=="locked")
	progression.underground_reputation=250
	var bank: Dictionary = progression.record_driving_contract("tier-bank-run-0004","morrow-coast::bank","robbery",last_tier)
	check("bank_pays_fixed_game_owned_reward", bank.get("cash")==175000 and Contracts.configured_wanted("robbery",last_tier)==5)
	var altered: Dictionary = last_tier.duplicate(true)
	altered["cash"]=999999
	check("tier_cannot_override_game_owned_rewards", not Contracts.valid_robbery_profile("robbery",altered) and progression.record_driving_contract("tier-bank-run-0005","morrow-coast::bank","robbery",altered).get("result")=="invalid_reward")
	for i in tiers.size():
		var offer: Dictionary = tiers[i]
		check("robbery_tier_heat_%d" % i, Contracts.configured_wanted("robbery",offer)==i+1)
		if i>0:
			check("robbery_tier_rep_rises_%d" % i, Contracts.required_rep(offer)>Contracts.required_rep(tiers[i-1]))

	# A visible roadside person has multiple individually configured jobs.
	var robbery_offer: Dictionary = {"id":"job_1","title":"Harbor Bank Pickup",
		"kind":"robbery","difficulty":"pro","destination_marker_id":"marker-12",
		"robbery_marker_id":"marker-11","cash":4000,"player_xp":650,
		"car_xp":420,"underground_rep":12,"wanted_level":3,
		"time_limit_seconds":540,"required_player_level":1,
		"required_underground_rep":0,"repeatable":false}
	var courier_offer: Dictionary = {"id":"job_2","title":"Safe Parcel Delivery",
		"kind":"courier","difficulty":"rookie","destination_marker_id":"marker-12",
		"repeatable":true}
	var contact := marker("marker-10","contract_contact",100.0,100.0,
		{"contact_style":"business","description":"Dispatch agent",
		 "offers":[robbery_offer,courier_offer]})
	var robbery_site := marker("marker-11","robbery_target",320.0,200.0)
	var contact_dropoff := marker("marker-12","contract_dropoff",550.0,350.0)
	var contact_markers: Array=[contact,robbery_site,contact_dropoff]
	var by_id := {"marker-10":contact,"marker-11":robbery_site,
		"marker-12":contact_dropoff}
	check("npc_contact_multiple_offers_validate",Contracts.valid_contact(contact,by_id)
		and MarkerRules.valid_links(contact_markers,[],[]))
	var bad_offer: Dictionary=robbery_offer.duplicate(true)
	bad_offer.robbery_marker_id="marker-404"
	check("robbery_requires_real_location",not Contracts.valid_offer(bad_offer,contact,by_id))
	bad_offer=robbery_offer.duplicate(true)
	bad_offer.cash=999999
	check("payout_above_cap_rejected",not Contracts.valid_offer(bad_offer,contact,by_id))
	var duplicated: Dictionary=contact.duplicate(true)
	duplicated.properties.offers=[robbery_offer,robbery_offer]
	check("duplicate_job_ids_rejected",not Contracts.valid_contact(duplicated,by_id))
	var invalid_type: Dictionary=robbery_offer.duplicate(true)
	invalid_type.kind="on_foot"
	check("no_on_foot_job_type",not Contracts.valid_offer(invalid_type,contact,by_id))
	check("configured_reward_remains_bounded",int(Contracts.configured_reward("robbery",robbery_offer).cash)==4000)
	var custom_economy := Ownership.new(false)
	var first_custom := custom_economy.record_driving_contract(
		"person-job-test-run-001","world-a::marker-10_job_1","robbery",robbery_offer)
	check("configured_robbery_pays_and_gives_rep",
		first_custom.get("result","")=="completed" and
		custom_economy.balance==Ownership.STARTING_CASH+4000 and
		custom_economy.underground_reputation==12)
	check("one_shot_robbery_cannot_pay_twice",custom_economy.record_driving_contract(
		"person-job-test-run-002","world-a::marker-10_job_1","robbery",robbery_offer).get("result","")=="already_completed")
	bad_offer=robbery_offer.duplicate(true)
	bad_offer.cash=20000
	check("economy_rejects_untrusted_over_cap_rewards",
		custom_economy.record_driving_contract("person-job-test-run-003",
			"world-b::marker-10_job_1","robbery",bad_offer).get("result","")=="invalid_reward")

	# Real native-editor source validation and undo support for contract links.
	var session := Session.new()
	session.doc = {"format":"gdt.racing-world","version":2,"customMap":true,
		"name":"Contracts Test World","world":{"width":1000,"height":1000,"base":"grass"},
		"roads":[],"regions":[],"props":[],"markers":[source,destination],
		"assets":[],"races":[],"dealerships":[]}
	check("contract_editor_accepts_source",session._valid_source(session.doc))
	var contact_session:=Session.new()
	contact_session.doc=session.doc.duplicate(true)
	contact_session.doc.markers=contact_markers.duplicate(true)
	check("native_editor_accepts_contact_with_robbery",contact_session._valid_source(contact_session.doc))
	var changed_contact: Dictionary=contact.duplicate(true)
	changed_contact.properties.contact_style="street"
	check("native_editor_undo_restores_contact",contact_session.update_marker("marker-10",
		{"properties":changed_contact.properties}) and contact_session.undo() and
		str(contact_session.marker_at_id("marker-10").properties.contact_style)=="business")
	var editor: RefCounted=ContactEditor.new()
	var host:=Control.new()
	root.add_child(host)
	editor.call("build",host)
	editor.call("open_for",{"authoring":contact_session},contact)
	check("npc_contract_editor_loads_two_jobs",(editor.get("offers") as Array).size()==2)
	editor.call("_duplicate_job")
	var after_copy: Array=editor.get("offers").duplicate(true)
	check("duplicating_native_contract_assigns_new_id", after_copy.size()==3 and
		str(after_copy[1].get("id",""))!="job_1" and str(after_copy[0].get("id",""))=="job_1")
	editor.call("_move_job",1)
	var reordered: Array=editor.get("offers").duplicate(true)
	check("native_job_ordering_preserves_save_ids",str(reordered[2].get("id",""))==str(after_copy[1].get("id","")))
	editor.call("_apply_difficulty_preset")
	check("native_preset_keeps_current_job_identity",
		str((editor.get("offers") as Array)[2].get("id",""))==str(reordered[2].get("id","")))
	editor.call("_delete_job")
	var errors: Array=editor.call("validation_errors",contact,contact_markers)
	check("native_authoring_links_still_validate",errors.is_empty())
	check("robbery_wait_and_radius_have_valid_defaults",
		is_equal_approx(Contracts.configured_robbery_hold({}),7.0)
		and is_equal_approx(Contracts.configured_arrival_radius({}),12.0)
		and Contracts.arrived(20.0,0.0,22.0)
		and not Contracts.arrived(25.0,0.0,22.0))
	var custom_robbing: Dictionary=robbery_offer.duplicate(true)
	custom_robbing["robbery_hold_seconds"]=18
	custom_robbing["arrival_radius_m"]=22
	check("configurable_robbery_duration_and_stop_radius",
		Contracts.valid_offer(custom_robbing,contact,by_id)
		and Contracts.configured_robbery_hold(custom_robbing)==18.0
		and Contracts.configured_arrival_radius(custom_robbing)==22.0)
	var invalid_robbing: Dictionary=custom_robbing.duplicate(true)
	invalid_robbing["robbery_hold_seconds"]=99
	check("unsafe_wait_rejected",not Contracts.valid_offer(invalid_robbing,contact,by_id))
	var visual:=Node2D.new()
	visual.set_script(ContactVisual)
	root.add_child(visual)
	await process_frame
	check("roadside_person_visual_created",is_instance_valid(visual) and
		visual.get_script()!=null)
	visual.queue_free()
	host.queue_free()
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
	# Staged robbery requires waiting at the real target, evading police
	# and stopping at the final dropoff. No reward before those conditions.
	var test_officer: Node2D=PoliceStub.new()
	var staged: Node2D=Node2D.new()
	staged.set_script(ContractRuntime)
	staged.set("player",vehicle)
	staged.set("police",test_officer)
	staged.set("marker_source",source_markers)
	staged.set("economy",economy)
	var synthetic:=marker("marker-10_job_1","contract",100.0,100.0,
		{"contract_kind":"robbery","destination_marker_id":"marker-12",
		 "robbery_marker_id":"marker-11"})
	staged.set("active",synthetic)
	staged.set("destination",contact_dropoff)
	staged.set("robbery_target",robbery_site)
	staged.set("offer_settings",robbery_offer)
	staged.set("stage","robbery")
	staged.set("remaining_seconds",540.0)
	staged.set("run_token","person-robbery-stage-run-004")
	staged.set("started_car_id",str(economy.active_id))
	vehicle.position=Vector2(robbery_site.x,robbery_site.y)*20.0
	vehicle.linear_velocity=Vector2.ZERO
	var balance_before_robbery:int=economy.balance
	staged.call("_physics_process",3.0)
	check("waiting_for_offscreen_crew_has_no_payout",economy.balance==balance_before_robbery
		and str(staged.get("stage"))=="robbery")
	staged.call("_physics_process",5.0)
	check("robbery_handoff_triggers_police",str(staged.get("stage"))=="delivery"
		and int(test_officer.get("wanted_level"))==3)
	vehicle.position=Vector2(contact_dropoff.x,contact_dropoff.y)*20.0
	staged.call("_physics_process",0.02)
	check("police_chase_blocks_robbery_payout",economy.balance==balance_before_robbery)
	test_officer.set("wanted_level",0)
	staged.call("_physics_process",0.02)
	check("evade_and_dropoff_completes_robbery",economy.balance==balance_before_robbery+4000
		and (staged.get("active") as Dictionary).is_empty())
	staged.free()
	test_officer.free()
	runtime.free()
	source_markers.free()
	police.free()
	vehicle.queue_free()
	print("DRIVING CONTRACTS: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)
