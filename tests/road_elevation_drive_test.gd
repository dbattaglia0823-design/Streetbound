extends SceneTree
## Drive the normal vehicle controller through the production-baked fixture.
const EditSession = preload("res://scripts/dev/native_map_edit_session.gd")
const Elevation = preload("res://scripts/world/road_elevation.gd")
const TrafficCar = preload("res://scripts/world/traffic_car.gd")
const WorldScene = preload("res://scenes/vehicle.tscn")
var failures: Array[String] = []


class FixtureWorld extends MorrowCoast:
	var fixture: Dictionary

	func _ready() -> void:
		_initialize_archive(fixture,true,false)


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(1)
		return
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not fixture is Dictionary:
		push_error("Missing baked elevation fixture")
		quit(1)
		return
	var session := EditSession.new()
	check(session.load_source(),"Native editor loads the existing Morrow source")
	var original: Dictionary = session.road_at_id("road-0").duplicate(true)
	if not original.is_empty():
		var settings := {"elevation":{"start_layer":1,"end_layer":1}}
		check(session.set_road_settings("road-0",settings),"Native road elevations use the edit transaction")
		check(session.road_at_id("road-0").get("elevation") == settings.elevation,
			"Native edit retains the requested profile")
		check(session.undo() and session.road_at_id("road-0")==original and session.redo(),
			"Native road elevations support undo and redo")

	var world := FixtureWorld.new()
	world.fixture = fixture
	world.editor_render_only = true
	root.add_child(world)
	check(world.initialization_complete and world.has_road_elevation,"Fixture loads through Morrow Coast")
	if not world.initialization_complete:
		quit(1)
		return
	var over := world.elevation_at(Vector2(500,400)*20,1,6.0)
	var under := world.elevation_at(Vector2(500,400)*20,2,-6.0)
	check(float(over.get("height_m",0)) == 6.0 and float(under.get("height_m",0)) == -6.0,
		"Indexed support resolves two independently selected decks at one XY")
	check(world.elevation_at(Vector2(500,400)*20,-1,0.0).is_empty(),
		"A ground-level car cannot enter from the middle of a tunnel or overpass")
	check(world.surface_at(Vector2(495,580)*20).name == "GRASS",
		"A deck does not paint a second physical road at ground level")
	check(world.tunnel_portals.get(7) == false and world.tunnel_portals.size() == 1,
		"Only the connected underground ramp end owns a portal")
	check(world._overhead_layer_at(Vector2(500,400)*20,0.0) == 1 and
		world._overhead_layer_at(Vector2(500,400)*20,6.0) == 0,
		"Only the driver beneath the deck needs the occlusion fade")
	var car: VehicleController2D = WorldScene.instantiate()
	car.position = Vector2(500,708)*20
	car.z_index = 8
	car.external_input = true
	car.surface_provider = world
	root.add_child(car)
	world.vehicle = car

	var blocker := StaticBody2D.new()
	blocker.position = Vector2(500,400)*20
	blocker.collision_layer = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(55,55)
	shape.shape = box
	blocker.add_child(shape)
	root.add_child(blocker)

	car.command = Vector4(1,0,0,0)
	var last_height := 0.0
	var climbed := false
	var max_tick_change := 0.0
	for i in 1900:
		await physics_frame
		max_tick_change = maxf(max_tick_change,absf(car.elevation_m-last_height))
		last_height = car.elevation_m
		if car.elevation_m > 1.0 and car.elevation_m < 5.0:climbed = true
		if car.position.y < 390*20:break
	check(climbed and max_tick_change < .25,"Normal vehicle physics follows the ramp continuously")
	check(car.position.y < 390*20 and car.road_layer == 1 and is_equal_approx(car.elevation_m,6.0),
		"Overpass car clears a solid ground collider at the same XY")
	check(car.collision_mask == Elevation.collision_bits(1,6.0),"Deck uses only its own collision band")
	check(not car.can_reach_ground_marker(),"Deck does not grant access to a ground objective")
	check(car._elevation_motion(Vector2(240,0)).length() < 120.0,
		"A lateral sweep cannot leave the elevated pavement")
	# The same physical obstacle must block travel when placed on the deck.
	blocker.position = Vector2(500,345)*20
	blocker.collision_layer = Elevation.collision_bits(1,6.0)
	var impacts := [0]
	car.impacted.connect(func(_strength: float) -> void: impacts[0] += 1)
	for i in 240:
		await physics_frame
		if impacts[0] > 0:break
	check(impacts[0] > 0 and car.position.y > 345*20,"Same-deck obstacle still collides")
	car.reset_vehicle()
	check(car.road_layer == 0 and car.collision_mask == 1 and car.can_reach_ground_marker(),
		"Reset restores ground-layer collision and ground marker access")
	blocker.position = Vector2(500,400)*20
	blocker.collision_layer = 1

	car.global_position = Vector2(500,142)*20
	car.rotation = PI
	car.command = Vector4(1,0,0,0)
	for i in 1900:
		await physics_frame
		if car.position.y > 410*20:break
	check(car.position.y > 410*20 and car.road_layer == -1 and is_equal_approx(car.elevation_m,-6.0),
		"Tunnel supports travel beneath the same ground obstacle")
	check(world.viewed_road_layer == -1,"The world reveals its tunnel art when the driver descends")
	# Start from rest facing the exit, then climb using the same real controls.
	car.linear_velocity = Vector2.ZERO
	car.rotation = 0.0
	for i in 1900:
		await physics_frame
		if car.position.y < 142*20:break
	check(car.position.y < 142*20 and car.road_layer == 0 and
		car.can_reach_ground_marker() and world.viewed_road_layer == 0,
		"Leaving the same physical portal restores ground contact and terrain visibility")
	# Ambient chassis retain the layer their lane supplies and collide
	# with a blocker only on that physical level.
	var traffic := TrafficCar.new()
	traffic.position = Vector2(501.8,405)*20
	traffic.rotation = 0.0
	root.add_child(traffic)
	traffic.set_lane_grade(world,1,6.0,true)
	await physics_frame
	check(traffic.move_traffic(Vector2(0,-120.0),.1)==null and traffic.position.y<400*20,
		"Ambient deck traffic crosses the ground obstacle without contact")
	blocker.collision_layer = Elevation.collision_bits(1,6.0)
	await physics_frame
	check(traffic.move_traffic(Vector2(0,120.0),.1)!=null,
		"Ambient deck traffic still collides with a same-layer obstacle")
	traffic.receive_impact(Vector2(4000,0))
	await physics_frame
	var before_slide := traffic.global_position
	traffic.move_traffic(Vector2(400.0,0),.1)
	check(traffic.global_position.distance_to(before_slide)<1.0,
		"Elevated ambient recoil is contained on its supported deck")
	traffic.queue_free()

	# Simulate host-owned contact after reconnect or a large position correction.
	# Identical XY can represent three distinct supported physical surfaces.
	car.reset_vehicle()
	car.global_position = Vector2(500,400)*20
	check(car.reconcile_road_contact(1,6.0) and car.road_contact_id()==1
		and car.road_layer==1 and car.collision_mask==Elevation.collision_bits(1,6.0),
		"Guest correction restores the host's deck and collision band")
	check(not car.reconcile_road_contact(2,6.0) and car.road_contact_id()==1,
		"Wrong signed host contact is rejected without changing the current deck")
	check(not car.reconcile_road_contact(999,6.0) and car.road_contact_id()==1,
		"Unknown road identity cannot change contact")
	check(car.reconcile_road_contact(2,-6.0) and car.road_layer==-1
		and car.collision_mask==Elevation.collision_bits(1,-6.0),
		"Guest correction restores tunnel contact at the same XY")
	check(car.reconcile_road_contact(-1,0.0) and car.road_layer==0
		and car.collision_mask==1 and car.road_contact_id()==-1,
		"Host ground correction restores original collision mask")

	world.queue_free()
	car.queue_free()
	blocker.queue_free()
	await process_frame
	if failures.is_empty():print("ROAD ELEVATION DRIVE: PASS")
	quit(0 if failures.is_empty() else 1)
