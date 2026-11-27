extends SceneTree
## Race career prerequisites, persistence in memory, first/repeat rewards,
## and marker cross-links use the exact runtime rules and editor schema.
const Rules=preload("res://scripts/world/authored_event_rules.gd")
const MarkerRules=preload("res://scripts/world/authored_marker_rules.gd")
const Economy=preload("res://scripts/vehicle/vehicle_ownership.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("_run")

func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)

func base_race(id: String) -> Dictionary:
	return {"id":id,"name":"Career Race","mode":"sprint",
		"points":[{"x":100.0,"y":100.0},{"x":300.0,"y":100.0}],
		"laps":1,"reward_cash":500,"reward_player_xp":200,"reward_car_xp":100,
		"first_win_reward_cash":3000,"first_win_reward_player_xp":1000,
		"first_win_reward_car_xp":500,"category":"street","difficulty":"amateur",
		"repeatable":true,"required_player_level":1,"required_car_level":1,
		"prerequisite_races":[],"required_vehicle_ids":[]}

func marker(id: String,kind: String,props: Dictionary={}) -> Dictionary:
	return {"id":id,"name":id,"type":kind,"x":100.0,"y":100.0,
		"rotation":0.0,"properties":props}

func _run() -> void:
	var first:=base_race("race-1")
	var next:=base_race("race-2")
	next.prerequisite_races=["race-1"]
	next.required_player_level=3
	next.required_vehicle_ids=["audi-rs3"]
	check("career_chain_valid",Rules.valid_graph([first,next]))
	var bad: Dictionary=first.duplicate(true)
	bad.prerequisite_races=["race-2"]
	check("cyclic_prerequisites_rejected",not Rules.valid_graph([bad,next]))
	check("unknown_prerequisites_rejected",not Rules.valid_graph([next]))
	var economy:=Economy.new(false)
	check("prerequisite_blocks_uncompleted_event",
		Rules.lock_reason(next,economy,"map-a")!="")
	var cash_before: int=economy.balance
	var win: Dictionary=economy.record_authored_race("authored-career-test-run-0001",42.0,first,"map-a::race-1")
	check("first_win_pays_regular_and_bonus",
		win.get("result","")=="completed" and bool(win.get("first_win",false)) and
		economy.balance==cash_before+3500 and
		economy.completed_event_count("map-a::race-1")==1 and
		economy.player_xp==1200)
	var repeated: Dictionary=economy.record_authored_race("authored-career-test-run-0002",40.0,first,"map-a::race-1")
	check("repeat_win_pays_only_repeat_reward",
		repeated.get("result","")=="completed" and not bool(repeated.get("first_win",true)) and
		economy.balance==cash_before+4000 and economy.completed_event_count("map-a::race-1")==2)
	var prior: int=economy.balance
	check("same_run_id_does_not_reaward",
		economy.record_authored_race("authored-career-test-run-0002",40.0,first,"map-a::race-1").get("result","")=="invalid_or_duplicate"
		and economy.balance==prior)
	check("different_world_same_race_id_keeps_separate_progress",
		economy.completed_event_count("map-b::race-1")==0)
	next.required_player_level=1
	next.required_car_level=1
	check("prerequisite_unlocks_after_first_win",Rules.lock_reason(next,economy,"map-a").is_empty())
	next.repeatable=false
	var second: Dictionary=economy.record_authored_race("authored-career-test-run-0003",39.0,next,"map-a::race-2")
	check("one_shot_event_records_completion",second.get("result","")=="completed")
	check("one_shot_reentry_blocked",not Rules.lock_reason(next,economy,"map-a").is_empty() and
		economy.record_authored_race("authored-career-test-run-0004",39.0,next,"map-a::race-2").get("result","")=="locked")
	var invalid:=base_race("race-3")
	invalid.required_vehicle_ids=["unknown-model"]
	check("invalid_player_vehicle_id_rejected",not Rules.valid_event(invalid))
	var markers: Array=[marker("marker-0","player_spawn"),
		marker("marker-1","mission",{"race_id":"race-1"}),
		marker("marker-2","fast_travel",{"required_race":"race-1"}),
		marker("marker-3","garage"),
		marker("marker-4","dealership",{"dealer_id":"dealer-1"}),
		marker("marker-5","traffic_spawn",{"traffic_weight":7})]
	check("linked_gameplay_markers_validate",
		MarkerRules.valid_links(markers,[first,next],[{"id":"dealer-1"}]))
	check("mission_link_to_missing_race_rejected",
		not MarkerRules.valid_links([marker("marker-1","mission",{"race_id":"race-404"})],[first],[]))
	check("marker_duplicate_player_spawns_rejected",
		not MarkerRules.valid_links([marker("marker-1","player_spawn"),
		marker("marker-2","player_spawn")],[first],[]))
	var session:=Session.new()
	session.doc={"format":"gdt.racing-world","version":2,"customMap":true,
		"name":"Career Test World","world":{"width":1000,"height":1000,"base":"grass"},
		"roads":[],"regions":[],"props":[],"markers":markers,"assets":[],
		"races":[first,next],"dealerships":[{"id":"dealer-1"}]}
	check("source_validation_checks_career_graph_and_links",session._valid_source(session.doc))
	var edited: bool=session.update_marker("marker-1",{"name":"Mission One",
		"properties":{"race_id":"race-2","enabled":true,"radius_m":12,"traffic_weight":3}})
	check("marker_editor_writes_undoable_source",edited and
		session.marker_at_id("marker-1").name=="Mission One")
	check("undo_restores_original_marker",session.undo() and
		session.marker_at_id("marker-1").name=="marker-1")
	var stock_id:=str(preload("res://scripts/vehicle/player_vehicle_catalog.gd").all()[0].id)
	check("linked_stock_updates_real_custom_shop",session.set_marker_dealer_stock("marker-4",[stock_id]) and session.dealership_at_id("dealer-1").inventory==[stock_id])
	var standalone:=session.add_marker(Vector2(300,300),"dealership")
	check("unlinked_marker_stock_persists",not standalone.is_empty() and session.set_marker_dealer_stock(standalone,[stock_id]) and session.marker_at_id(standalone).properties.dealer_inventory==[stock_id])
	check("marker_stock_rejects_unknown_and_duplicate_ids",not session.set_marker_dealer_stock(standalone,["missing-car"]) and not session.set_marker_dealer_stock(standalone,[stock_id,stock_id]))
	check("custom_dealers_exclude_morrow_defaults",session.dealership_list().size()==1)
	check("marker_stock_undo_restores_previous_state",session.undo() and not session.marker_at_id(standalone).properties.has("dealer_inventory"))
	print("AUTHORED CAREER & MARKERS: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
