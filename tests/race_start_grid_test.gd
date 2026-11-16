extends SceneTree
## Editor-defined player/AI grids must validate, bake, teleport and launch safely.
const Grid=preload("res://scripts/world/race_start_grid.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Definition=preload("res://scripts/world/authored_race_definition.gd")
const Authored=preload("res://scripts/world/authored_race.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("_run")
func check(label: String,ok: bool,detail: Variant="") -> void:
	print("%s %s: %s"%["PASS" if ok else "FAIL",label,str(detail)])
	if not ok:failures.append(label)

func _run() -> void:
	var points: Array=[{"x":2400.0,"y":3200.0},{"x":2460.0,"y":3200.0},{"x":2520.0,"y":3200.0}]
	var grid: Dictionary=Grid.layout(points,3,"staggered")
	var race: Dictionary={"id":"race-grid-audit","name":"Starting grid audit","mode":"sprint","points":points,
		"laps":1,"start_radius":8,"checkpoint_radius":16,"time_limit":0}
	race.merge(grid,true)
	check("three_distinct_ai_grid_slots",race.enemy_starts.size()==3 and Grid.valid_grid(race,5000,6000))
	check("all_rivals_face_first_checkpoint",
		race.enemy_starts.all(func(slot):return Vector2.UP.rotated(Grid.angle(slot)).dot(Vector2.RIGHT)>.999))
	var collision: Dictionary=race.duplicate(true)
	collision.enemy_starts[0]=race.player_start.duplicate(true)
	check("overlapping_start_slots_cannot_be_saved",not Grid.valid_grid(collision,5000,6000))
	var escaped: Dictionary=race.duplicate(true)
	escaped.enemy_starts[0].x=6001.0
	check("out_of_bounds_ai_start_is_rejected",not Definition.valid(escaped,5000,6000))
	var invalid_heading: Dictionary=race.duplicate(true)
	invalid_heading.player_start.rotation=999.0
	check("illegal_grid_heading_is_rejected",not Definition.valid(invalid_heading,5000,6000))
	var legacy: Dictionary=race.duplicate(true)
	legacy.erase("player_start");legacy.erase("enemy_starts");legacy.erase("formation")
	check("old_time_trial_without_grid_still_loads",Definition.valid(legacy,5000,6000))

	var session: Variant=Session.new()
	check("authoring_source_loaded",session.load_source())
	var route: Array[Vector2]=[Vector2(2400,3200),Vector2(2460,3200),Vector2(2520,3200)]
	var id: String=session.save_race(route,{"name":"Native grid","mode":"sprint",
		"laps":1,"start_radius":8,"checkpoint_radius":16,"time_limit":0,
		"opponent_count":2,"formation":"single_file"})
	var saved: Dictionary=session.race_at_id(id)
	check("editor_creates_two_rivals_and_player_slot",
		not id.is_empty() and saved.enemy_starts.size()==2 and saved.has("player_start"))
	var old_position:=Grid.point(saved.enemy_starts[0])
	var history: int=session.history.size()
	check("moving_single_ai_slot_succeeds",session.set_race_grid_slot(id,0,old_position+Vector2(1,0)))
	check("grid_slot_move_is_one_undo_entry",session.history.size()==history+1)
	check("undo_restores_only_moved_slot",session.undo() and Grid.point(session.race_at_id(id).enemy_starts[0])==old_position)
	var no_change:=JSON.stringify(session.doc)
	check("overlapping_manual_move_is_rejected",not session.set_race_grid_slot(id,0,Grid.point(session.race_at_id(id).player_start)))
	check("invalid_manual_slot_move_does_not_change_document",JSON.stringify(session.doc)==no_change)
	check("reset_grid_layout_is_undoable",session.reset_race_grid(id,"staggered") and session.undo())

	var game: Variant=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	for i in 8:await process_frame
	var car: VehicleController2D=game.vehicle
	car.set_physics_process(false)
	var event: Variant=Authored.new()
	event.world=game.ground
	event.player=car
	event.definition=race.duplicate(true)
	game.ground.add_child(event)
	event.set_physics_process(false)
	# Stage five metres away, then require teleportation to the saved slot.
	car.global_position=Vector2(2395,3200)*Grid.PPM
	car.global_rotation=PI/2.0
	car.linear_velocity=Vector2(3,1)
	check("race_can_stage_from_staging_circle",event.available and event.can_stage())
	check("staging_location_differs_from_grid_spawn",car.global_position.distance_to(Grid.point(race.player_start)*Grid.PPM)>4.9*Grid.PPM)
	check("race_starts_from_saved_positions",event.start_race() and
		car.global_position.distance_to(Grid.point(race.player_start)*Grid.PPM)<.01)
	check("player_is_stationary_and_facing_route",
		car.linear_velocity.is_zero_approx() and car.velocity.is_zero_approx() and
		Vector2.UP.rotated(car.rotation).dot(Vector2.RIGHT)>.99)
	check("ai_cars_spawn_in_every_configured_slot",event.rivals.size()==3)
	var positioned:=event.rivals.size()==3
	if positioned:
		for i in event.rivals.size():
			positioned=positioned and event.rivals[i].global_position.distance_to(Grid.point(race.enemy_starts[i])*Grid.PPM)<.01
			positioned=positioned and event.rivals[i].linear_velocity.is_zero_approx()
	check("ai_slots_are_exact_and_nonmoving_before_countdown",positioned)
	event._physics_process(3.1)
	check("rival_drivers_launch_after_lights",event.state=="running" and
		event.rival_drivers.size()==3 and bool(event.rival_drivers[0].get("active")))
	check("quitting_releases_all_ai",event.quit_race() and event.rivals.is_empty() and event.rival_drivers.is_empty())
	check("grid_race_can_restart_after_quit",event.start_race() and event.rivals.size()==3)
	event.quit_race()
	# Existing street/circuit/drag events also move a nearby staged player
	# to one exact, stationary starting location, regardless of entry offset.
	var builtin: Array=[game.drag_race,game.circuit_race,game.street_race]
	for existing in builtin:
		existing.set_physics_process(false)
		var start: Vector2=existing.start_m
		var forward: Vector2=existing.direction if existing==game.drag_race else existing.heading
		car.global_position=(start-forward*3.0)*Grid.PPM
		car.global_rotation=forward.angle()+PI*.5
		car.linear_velocity=Vector2.ZERO
		if not existing.can_stage():
			check(str(existing.race_title)+"_approach_is_stageable",false)
			continue
		var staged: bool=existing.start_race()
		var expected: Vector2=(start+existing.direction.orthogonal().normalized()*4.1)*Grid.PPM if existing==game.drag_race else start*Grid.PPM
		check(str(existing.race_title)+"_uses_fixed_grid_teleport",staged and car.global_position.distance_to(expected)<.05)
		check(str(existing.race_title)+"_starts_stationary",car.linear_velocity.is_zero_approx())
		existing.quit_race()
	game.queue_free()
	await process_frame
	await process_frame
	print("RACE START GRID: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
