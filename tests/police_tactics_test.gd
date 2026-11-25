extends SceneTree
## Deterministic police tactics plus the real pursuit state transition seam.
const Tactics = preload("res://scripts/world/police_tactics.gd")
const Police = preload("res://scripts/world/police_pursuit.gd")
const Containment = preload("res://scripts/world/police_containment.gd")
const PlayerScene = preload("res://scenes/vehicle.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, success: bool) -> void:
	print("%s %s" % ["PASS" if success else "FAIL",label])
	if not success:
		failures.append(label)

func run() -> void:
	var low: Dictionary=Tactics.profile(1)
	var mid: Dictionary=Tactics.profile(3)
	var high: Dictionary=Tactics.profile(5)
	check("wanted_level_one_uses_one_officer",int(low["units"])==1)
	check("wanted_level_three_uses_three_officers",int(mid["units"])==3)
	check("highest_wanted_level_max_four",int(high["units"])==4
		and int(high["units"])<=Tactics.MAX_RESPONDERS)
	check("police_do_not_gain_arcade_speed_or_throttle",float(high["cruise_mps"])<=25.0
		and float(high["throttle"])<=0.85 and
		float(low["cruise_mps"])<float(high["cruise_mps"]))
	check("search_longer_at_higher_heat",float(high["search_seconds"])>float(low["search_seconds"]))
	check("wanted_level_four_has_real_roadblock_driver",Tactics.role(3,4)=="roadblock"
		and Tactics.role(0,1)=="pursuer")
	var selected: Array[Vector2] = []
	check("safe_rear_spawn_permitted",Tactics.safe_spawn(Vector2(-175,0),
		Vector2.ZERO,Vector2.RIGHT,selected))
	check("spawn_on_players_predicted_path_denied",not Tactics.safe_spawn(Vector2(175,0),
		Vector2.ZERO,Vector2.RIGHT,selected))
	check("spawn_too_close_denied",not Tactics.safe_spawn(Vector2(-25,0),
		Vector2.ZERO,Vector2.RIGHT,selected))
	check("spawn_too_far_denied",not Tactics.safe_spawn(Vector2(-300,0),
		Vector2.ZERO,Vector2.RIGHT,selected))
	selected.append(Vector2(-175,0))
	check("spawn_cluster_denied",not Tactics.safe_spawn(Vector2(-195,12),
		Vector2.ZERO,Vector2.RIGHT,selected))
	check("separated_side_unit_permitted",Tactics.safe_spawn(Vector2(-165,65),
		Vector2.ZERO,Vector2.RIGHT,selected))
	check("invalid_spawn_coordinates_denied",not Tactics.safe_spawn(Vector2.INF,
		Vector2.ZERO,Vector2.RIGHT,selected))
	var options: Array[Dictionary] = [
		{"position_m":Vector2(-125,5)},
		{"position_m":Vector2(140,75)},
		{"position_m":Vector2(130,5)},
		{"position_m":Vector2(155,10)}
	]
	var blockade: Dictionary=Tactics.roadblock_candidate(options,Vector2.ZERO,Vector2.RIGHT)
	check("roadblock_chooses_authored_road_not_arbitrary_teleport",
		not blockade.is_empty() and blockade["position_m"]==Vector2(130,5))
	var behind: Array[Dictionary] = [{"position_m":Vector2(-150,0)}]
	check("no_legal_roadblock_prevents_fake_roadblock",
		Tactics.roadblock_candidate(behind,Vector2.ZERO,Vector2.RIGHT).is_empty())
	check("occluded_cars_are_invisible",
		not Tactics.visible(30.0,5,true) and Tactics.visible(30.0,1,false))
	check("out_of_visual_range_is_not_live_tracking",
		not Tactics.visible(170.0,5,false))
	var ring: Array[Vector2]=[
		Tactics.containment_target(Vector2.ZERO,Vector2.RIGHT,"pursuer"),
		Tactics.containment_target(Vector2.ZERO,Vector2.RIGHT,"intercept"),
		Tactics.containment_target(Vector2.ZERO,Vector2.RIGHT,"flank_left")]
	var progress: float=Containment.progress(0.0,1.0,Vector2.ZERO,0.0,0.0,ring)
	check("three_target_positions_form_real_box_in_geometry",
		progress>0.0 and ring[0].distance_to(ring[2])>7.0)
	check("target_coordinates_alone_cannot_instantly_arrest",
		not Containment.is_busted(progress))
	var suspect_m:=Vector2(500,200)
	var velocity_mps:=Vector2(18,0)
	var chase: Vector2=Tactics.intercept_target(suspect_m,velocity_mps,
		Vector2.RIGHT,"intercept",5)
	check("interception_uses_short_bounded_trajectory_prediction",
		chase.x>suspect_m.x and chase.x<suspect_m.x+55.0
		and is_equal_approx(chase.y,suspect_m.y))
	var left: Vector2=Tactics.intercept_target(suspect_m,velocity_mps,
		Vector2.RIGHT,"flank_left",5)
	var right: Vector2=Tactics.intercept_target(suspect_m,velocity_mps,
		Vector2.RIGHT,"flank_right",5)
	check("flank_units_have_separate_roles",left.distance_to(right)>=13.0)
	check("first_search_destination_last_known_position",
		Tactics.search_target(suspect_m,Vector2.RIGHT,0,0)==suspect_m)
	check("search_sweeps_distinct_locations_without_live_player_position",
		Tactics.search_target(suspect_m,Vector2.RIGHT,0,1)!=suspect_m
		and Tactics.search_target(suspect_m,Vector2.RIGHT,1,1)!=
			Tactics.search_target(suspect_m,Vector2.RIGHT,0,1))
	var car: VehicleController2D = PlayerScene.instantiate()
	car.external_input = true
	root.add_child(car)
	await physics_frame
	var police: Node2D=Police.new()
	police.set("player",car)
	police.set("wanted_level",2)
	police.set("phase","chase")
	police.set("last_seen_position_m",suspect_m)
	police.set("last_seen_heading",Vector2.RIGHT)
	police.call("_update_search_state",Tactics.LOST_SIGHT_GRACE_SECONDS+0.1,false)
	check("losing_sight_transitions_to_last_known_search",
		str(police.get("phase"))=="search" and
		(police.get("last_seen_position_m") as Vector2)==suspect_m)
	police.call("_update_search_state",3.0,false)
	check("search_timer_uses_real_elapsed_seconds",
		float(police.get("search_clock"))>3.0)
	car.global_position=Vector2(900,900)
	check("search_does_not_know_hidden_suspect_location",
		(police.get("last_seen_position_m") as Vector2)==suspect_m)
	police.call("_update_search_state",0.1,true)
	check("sighting_reacquires_and_resets_search",
		str(police.get("phase"))=="chase"
		and is_equal_approx(float(police.get("search_clock")),0.0)
		and (police.get("last_seen_position_m") as Vector2)==Vector2(45,45))
	police.free()
	car.queue_free()
	print("POLICE TACTICS: %d failures" % failures.size())
	quit(1 if not failures.is_empty() else 0)
