extends SceneTree
## Exercise the production compiler's jump data through real car collision.
const RoadJump = preload("res://scripts/world/road_jump.gd")
const Vehicle = preload("res://scenes/vehicle.tscn")
const EditSession = preload("res://scripts/dev/native_map_edit_session.gd")
var failures: Array[String] = []
var results: Array[bool] = []


class TestWorld extends MorrowCoast:
	var archive: Dictionary
	var deny_landing := false

	func jump_position_allowed(spec: Dictionary, at: Vector2, landing: bool) -> bool:
		return (not landing or not deny_landing) and super.jump_position_allowed(spec,at,landing)

	func _ready() -> void:
		_initialize_archive(archive,true,false)


class ActiveRace extends Node:
	var state := "running"


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func place(car: VehicleController2D, at: Vector2, rotation_value: float, momentum: Vector2) -> void:
	car.reset_vehicle()
	car.position = at*20
	car.rotation = rotation_value
	car.linear_velocity = momentum
	car.reset_physics_interpolation()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1:
		quit(1)
		return
	var archive: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not archive is Dictionary or archive.get("jumps",[]).size()!=1:
		push_error("Missing compiled single-jump test map")
		quit(1)
		return
	var edit_session := EditSession.new()
	check(edit_session.load_source("res://tests/fixtures/road-jumps.world.json"),
		"Native editor loads the jump fixture")
	var draft := edit_session.road_at_id("road-0")
	if not draft.is_empty():
		var reverse: Dictionary = draft.jump.duplicate()
		reverse.reverse = true
		check(edit_session.set_road_settings("road-0",{"jump":reverse}),"Native editor can reverse a jump")
		check(edit_session.undo() and not bool(edit_session.road_at_id("road-0").jump.reverse),
			"Native jump changes undo through the ordinary map history")
		check(not edit_session.set_road_settings("road-0",{"jump":reverse.merged({"max_mps":80},true)}),
			"Native editor rejects unsafe launch speeds")
	var world := TestWorld.new()
	world.archive = archive
	root.add_child(world)
	var spec: Dictionary = archive.jumps[0]
	check(world.initialization_complete and world.jumps_by_road.size()==1,"Baked jumps load into the streamed world")

	var car: VehicleController2D = Vehicle.instantiate()
	car.external_input = true
	car.surface_provider = world
	root.add_child(car)
	car.set_physics_process(false)
	car.jump_finished.connect(func(success: bool) -> void: results.append(success))
	world.vehicle = car
	await physics_frame

	var facing := Vector2.RIGHT
	var before := Vector2(199.9,400)*20
	var after := Vector2(200.1,400)*20
	check(RoadJump.accepts_launch(spec,before,after,Vector2(17.5,0),facing),"Legal forward launch")
	check(not RoadJump.accepts_launch(spec,before,after,Vector2(70,0),facing),"High-power overspeed rejected")
	check(not RoadJump.accepts_launch(spec,before,after,Vector2(7,0),facing),"Underspeed rejected")
	check(not RoadJump.accepts_launch(spec,after,before,Vector2(-17.5,0),-facing),"Reverse crossing rejected")
	check(not RoadJump.accepts_launch(spec,before,after,Vector2(17.5,2.5),Vector2.DOWN),"Sideways approach rejected")
	check(not world.jump_position_allowed(spec,Vector2(200,410)*20,true),"Nearby surface outside the designated landing is rejected")
	check(not world.jump_position_allowed(spec,Vector2(1040,400)*20,false),"Off-map endpoint rejected")
	var active_race := ActiveRace.new()
	root.add_child(active_race)
	active_race.add_to_group("streetbound_race")
	car.linear_velocity = Vector2(17.5,0)
	car.rotation = PI*.5
	check(world.jump_at_motion(car,before,after).is_empty(),"A running race owns its route and suppresses stunt launches")
	active_race.free()

	place(car,Vector2(198,400),PI*.5,Vector2(18.2,0))
	var high_point := 0.0
	var launch_momentum := Vector2.ZERO
	var restrictions_held := true
	var tried_reset := false
	for i in 240:
		await physics_frame
		var active := car.is_airborne()
		if active and not tried_reset:
			tried_reset = true
			car.external_input = false
			Input.action_press("reset")
			car._physics_process(1.0/120)
			Input.action_release("reset")
			car.external_input = true
			check(car.is_airborne(),"Reset key cannot reposition an airborne car")
		else:
			car.step_vehicle(1.0/120,Vector4(1,1,1,1) if active else Vector4.ZERO)
		if car.is_airborne():
			if launch_momentum==Vector2.ZERO:launch_momentum=car.linear_velocity
			high_point = maxf(high_point,car.jump_height_m)
			restrictions_held = restrictions_held and car.linear_velocity==launch_momentum \
				and car.surface_grip==0.0 and not car.can_reach_ground_marker()
		if not results.is_empty():break
	check(results==[true],"A correctly approached ramp produces one valid landing")
	check(high_point>.65 and high_point<RoadJump.MAX_RISE and restrictions_held,
		"Airborne inertia, traction lock and ground objective protection hold throughout flight")
	check(world.jump_position_allowed(spec,car.position,true),"Successful touchdown is on the authored runway")
	check(car.can_reach_ground_marker(),"Ground interactions resume after a successful landing")

	# A collider arriving after baking must still stop the live sweep.
	results.clear()
	var wall := StaticBody2D.new()
	wall.position = Vector2(209,400)*20
	wall.collision_layer = 1
	var collider := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(25,100)
	collider.shape = box
	wall.add_child(collider)
	root.add_child(wall)
	place(car,Vector2(198,400),PI*.5,Vector2(18.2,0))
	for i in 150:
		await physics_frame
		car.step_vehicle(1.0/120,Vector4.ZERO)
		if not results.is_empty():break
	check(results==[false],"A mid-flight swept collision invalidates the landing")
	check(car.position.x<200*20 and car.position.x>198*20 and not car.is_airborne() and car.linear_velocity==Vector2.ZERO,
		"Invalid flight returns to the last safe approach without crossing the blocker")

	# Landing rules are re-checked at touchdown, even after a good forecast.
	wall.queue_free()
	await process_frame
	world.deny_landing = true
	results.clear()
	place(car,Vector2(198,400),PI*.5,Vector2(18.2,0))
	for i in 240:
		await physics_frame
		car.step_vehicle(1.0/120,Vector4.ZERO)
		if not results.is_empty():break
	check(results==[false] and car.position.x<200*20,"A newly invalid landing recovers without awarding a success")

	world.queue_free()
	car.queue_free()
	await process_frame
	if failures.is_empty():print("ROAD JUMP DRIVE: PASS")
	quit(0 if failures.is_empty() else 1)
