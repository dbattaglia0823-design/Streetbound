extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String, ok: bool, detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if ok else "FAIL",label,detail])
	if not ok:failures.append(label)
func mouse(at: Vector2,pressed: bool,button: int=MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var event:=InputEventMouseButton.new();event.position=at;event.pressed=pressed;event.button_index=button
	return event
func run() -> void:
	var game: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.vehicle.set_physics_process(false)
	var flow: Node=game.ground.get_node("AmbientTraffic")
	flow.set_physics_process(false);flow.clear_traffic()
	for race in get_nodes_in_group("streetbound_race"):race.set_physics_process(false)
	var map: Node=get_first_node_in_group("streetbound_world_map_hud")
	var action:=InputEventAction.new();action.action="map";action.pressed=true
	map._input(action);map._process(.01)
	check("map_action_opens_atlas_above_driving_UI",map.large and map.full.visible and map.layer==19)
	paused=true;map._process(.01)
	check("pause_menus_are_not_hidden_behind_the_atlas",not map.full.visible)
	paused=false;map._input(action);map._process(.01)
	map.mini_view._gui_input(mouse(Vector2(20,20),true));map._process(.01)
	check("clicking_minimap_opens_atlas",map.large and map.full.visible)
	map.large=false
	check("four_new_races_join_existing_three",game.extra_races.size()==4 and map.races.size()==7)
	var starts: Array[Vector2]=[]
	for event in game.extra_races:
		check(str(event.race_title)+"_available",event.available)
		if not event.available:continue
		var nav: RefCounted=event.navigation
		var paved:=true
		for p in nav.points_m:
			if str(game.ground.surface_at(p*20).name)!="ASPHALT":paved=false;break
		check(str(event.race_title)+"_continuous_real_road_course",nav.length_m>=600 and paved,nav.length_m)
		var separate:=true
		for start in starts:separate=separate and Vector2(event.start_m).distance_to(start)>100
		starts.append(event.start_m)
		check(str(event.race_title)+"_distinct_start_circle",separate and event.start_radius_m>0)
		game.vehicle.position=event.start_m*20;game.vehicle.rotation=event.heading.angle()+PI/2
		game.vehicle.linear_velocity=Vector2.ZERO;game.vehicle.reset_physics_interpolation()
		check(str(event.race_title)+"_can_stage_inside_circle",event.can_stage())
		var start_key:=InputEventKey.new();start_key.keycode=KEY_F;start_key.physical_keycode=KEY_F;start_key.pressed=true
		event._unhandled_input(start_key)
		check(str(event.race_title)+"_F_starts_race",event.state=="countdown")
		check(str(event.race_title)+"_physical_rival_and_countdown",event.state=="countdown" and is_instance_valid(event.opponent))
		check("another_event_cannot_stage_during_active_race",not game.street_race.can_stage())
		event._clear_opponent();event.countdown=.01;event._physics_process(.02)
		var distance:=0.0
		while distance<float(nav.length_m) and event.state=="running":
			distance=minf(float(nav.length_m),distance+3)
			game.vehicle.position=nav.point_at(distance)*20
			game.vehicle.linear_velocity=event.heading*30
			event._physics_process(.1)
		check(str(event.race_title)+"_finishes_after_full_course",event.state=="results",event.result)
		event.state="idle";game.vehicle.position=event.start_m*20;game.vehicle.linear_velocity=Vector2.ZERO
		check(str(event.race_title)+"_replayable",event.start_race())
		event._clear_opponent();event.countdown=.01;event._physics_process(.02)
		game.vehicle.position=event.finish_m*20;event._physics_process(.1)
		check(str(event.race_title)+"_rejects_finish_teleport",event.state=="aborted")
		event.state="idle"
		await process_frame
	game.vehicle.position=game.ground.spawn_position();game.vehicle.linear_velocity=Vector2.ZERO
	var gps: Node=map.waypoints
	var target: Vector2=game.extra_races[0].start_m
	check("player_can_set_a_race_waypoint",gps.set_destination(target,"Juniper Ascent") and gps.navigation!=null)
	check("waypoint_has_road_route_and_distance",gps.active and gps.remaining_m>500,[gps.remaining_m,gps.status])
	var waypoint_paved:=true
	if gps.navigation!=null:
		for p in gps.navigation.points_m:
			if str(game.ground.surface_at(p*20).name) not in ["ASPHALT","GRAVEL","DIRT"]:waypoint_paved=false;break
	check("GPS_does_not_draw_cross_country_shortcuts",waypoint_paved)
	var revision:=int(gps.route_revision)
	game.vehicle.position=game.extra_races[2].start_m*20
	gps._clock=0;gps._retry_clock=0;gps._process(.4)
	check("GPS_reroutes_after_leaving_the_route",gps.route_revision>revision and gps.active and gps.navigation!=null)
	if gps.navigation!=null and float(gps.navigation.length_m)>200:
		game.vehicle.position=gps.navigation.point_at(150)*20
		gps._clock=0;gps._retry_clock=5;gps._process(.4)
		revision=int(gps.route_revision)
		game.vehicle.position=gps.navigation.point_at(100)*20
		gps._clock=0;gps._retry_clock=0;gps._process(.4)
		check("GPS_reroutes_after_sustained_backtracking",gps.route_revision>revision)
	game.vehicle.position=target*20;gps._clock=0;gps._process(.4)
	check("arrival_clears_route",not gps.active and gps.navigation==null and gps.status.begins_with("Arrived"))
	map._select_race(game.extra_races[1])
	check("atlas_race_selection_routes_to_actual_start",gps.active and gps.destination_name==game.extra_races[1].race_title and gps.destination_m==game.extra_races[1].start_m)
	check("race_markers_exist_on_atlas_and_minimap",map.full_view.activity_overlay.races.size()==7 and map.mini_view.activity_overlay.races.size()==7)
	var view: Control=map.full_view
	var old_target: Vector2=gps.destination_m
	view._gui_input(mouse(Vector2(400,300),true))
	var move:=InputEventMouseMotion.new();move.position=Vector2(440,300);move.relative=Vector2(40,0)
	view._gui_input(move);view._gui_input(mouse(move.position,false))
	check("panning_atlas_does_not_set_waypoint",gps.destination_m==old_target)
	view._gui_input(mouse(Vector2(400,300),true));view._gui_input(mouse(Vector2(400,300),false))
	check("clicking_atlas_sets_waypoint",gps.active and gps.destination_m!=old_target)
	view._gui_input(mouse(Vector2(400,300),true,MOUSE_BUTTON_RIGHT))
	check("right_click_clears_waypoint",not gps.active and gps.navigation==null)
	check("invalid_destination_preserves_existing_state",not gps.set_destination(Vector2.INF) and not gps.active)
	game.queue_free();await process_frame
	print("RACES AND WAYPOINTS: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
