extends SceneTree
## Drive the normal vehicle controller through the production-baked fixture.
const EditSession = preload("res://scripts/dev/native_map_edit_session.gd")
const Elevation = preload("res://scripts/world/road_elevation.gd")
const TerrainArt = preload("res://scripts/world/coast_tunnel_terrain.gd")
const Objectives = preload("res://scripts/world/objective_road_layer.gd")
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

	var point_session := EditSession.new()
	check(point_session.load_source("res://tests/fixtures/road-elevation.world.json"),"Point elevation fixture loads")
	if not point_session.doc.is_empty():
		var road: Dictionary = point_session.doc.roads[0]
		road.points = [{"x":100,"y":700},{"x":200,"y":700},{"x":300,"y":700},{"x":400,"y":700}]
		var before: Dictionary = point_session.doc.duplicate(true)
		var count: int = point_session.doc.roads.size()
		check(not point_session.apply_point_elevations("road-0",[0,2,1,0]) and point_session.doc==before,
			"Invalid point height leaves native draft unchanged")
		check(point_session.apply_point_elevations("road-0",[0,1,1,0]),"Apply native control point heights")
		check(point_session.doc.roads.size()==count and point_session.doc.roads[0].elevation=={"start_layer":0,"end_layer":0,"point_layers":[0,1,1,0]},
			"Native point heights persist on one authored road")
		check(point_session.undo() and point_session.doc==before and point_session.redo(),
			"Point profile is one undoable native edit")

	var world := FixtureWorld.new()
	world.fixture = fixture
	world.editor_render_only = true
	root.add_child(world)
	check(world.initialization_complete and world.has_road_elevation,"Fixture loads through Morrow Coast")
	if not world.initialization_complete:
		quit(1)
		return
	check(world.data.get("terrain_cuts",[]).size()==1,
		"Only the open surface-to-tunnel ramp creates a terrain excavation")
	var all_cuts: Array = world.data.get("terrain_cuts",[])
	var cut: Dictionary = all_cuts[0] if not all_cuts.is_empty() else {}
	if not cut.is_empty():
		var outline: PackedVector2Array = cut.polygon
		check(Geometry2D.is_point_in_polygon(Vector2(500,200),outline)
			and not Geometry2D.is_point_in_polygon(Vector2(500,270),outline),
			"Open trench removes the approach but preserves the covered tunnel roof")
		var subject := PackedVector2Array([Vector2(465,175),Vector2(535,175),Vector2(535,290),Vector2(465,290)])
		var cuts: Array[PackedVector2Array] = [outline]
		var pieces := Elevation.subtract_cutouts(subject,cuts)
		check(not pieces.is_empty() and not pieces.any(func(poly: PackedVector2Array)->bool:return Geometry2D.is_point_in_polygon(Vector2(500,200),poly)),
			"Mountain collision geometry has a genuine hole through the trench")
		check(pieces.any(func(poly: PackedVector2Array)->bool:return Geometry2D.is_point_in_polygon(Vector2(520,200),poly))
			and pieces.any(func(poly: PackedVector2Array)->bool:return Geometry2D.is_point_in_polygon(Vector2(500,270),poly)),
			"Unexcavated mountain and roof remain solid")
		world._build_chunk(Vector2i(2,1))
		var tile: Node2D = world.chunks.get(Vector2i(2,1))
		check(is_instance_valid(tile) and is_instance_valid(tile.get("excavation_body")) and is_instance_valid(tile.get("excavation_cap_body")),
			"Streamed chunk owns physical retaining walls and a surface-only portal cap")
		if is_instance_valid(tile):
			var walls: StaticBody2D = tile.get("excavation_body")
			var cap: StaticBody2D = tile.get("excavation_cap_body")
			if is_instance_valid(walls) and is_instance_valid(cap):
				check(walls.collision_layer== (1 | Elevation.collision_bits(1,-6.0)) and cap.collision_layer==1,
					"Portal cap blocks only surface traffic, not tunnel vehicles")
				tile.set_stream_active(false)
				check(walls.collision_layer==0 and cap.collision_layer==0,"Dormant trench releases physics contacts")
				tile.set_stream_active(true)
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
	check(world.tunnel_terrain_plans.size()==1 and world.tunnel_terrain_plans.has(7),
		"Only the surface approach creates terrain integration art")
	var art_plan: Dictionary=world.tunnel_terrain_plans.get(7,{})
	if not art_plan.is_empty():
		var strips: Array=art_plan.strips
		check(bool(art_plan.connected) and not strips.is_empty() and is_equal_approx(float(strips[-1].depth),1.0),
			"Retaining walls deepen toward the covered mouth")
		var first_strip: Dictionary=strips[0]
		var last_strip: Dictionary=strips[strips.size()-1]
		check(float(first_strip.depth)<float(last_strip.depth),
			"Surface approach banks grow continuously with ramp depth")
		check(art_plan.bounds.has_point(art_plan.mouth) and world.chunks[Vector2i(2,1)].has_node("TunnelTerrainClip"),
			"Portal terrain is indexed and streamed alongside the trench")
		var rock_regions:=TerrainArt.terrain_regions([{"kind":"mountain","points":[[0,0],[1000,0],[1000,1000],[0,1000]]}])
		var rock_plan:=TerrainArt.build(world.data.roads[7],rock_regions,true)
		check(rock_plan.kind=="mountain" and rock_plan.strips[0].kind=="mountain" and TerrainArt.palette("mountain")!=TerrainArt.palette("grass"),
			"Mountain portals use exposed rock rather than grass")
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
	world.editor_render_only=false
	world._update_underground_backdrop()
	check(is_instance_valid(world.underground_backdrop) and world.underground_backdrop.visible and world.underground_backdrop.z_index==41 and world.underground_backdrop.color==Color.BLACK,"Underground backdrop hides the surface below interior art")
	world.editor_render_only=true
	world._update_underground_backdrop()
	check(not world.underground_backdrop.visible,"Editor overview is never blacked out")
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
	check(Objectives.matches(car,1) and not Objectives.matches(car,0) and not Objectives.matches(car,-1),
		"Deck vehicle can reach only the elevated objective at the stacked XY")
	check(Objectives.supported(world,Vector2(500,400),1) and Objectives.supported(world,Vector2(500,400),-1)
		and not Objectives.supported(world,Vector2(500,400),2),
		"Objective placement resolves independent supported deck and tunnel levels")
	check(not car.reconcile_road_contact(2,6.0) and car.road_contact_id()==1,
		"Wrong signed host contact is rejected without changing the current deck")
	check(not car.reconcile_road_contact(999,6.0) and car.road_contact_id()==1,
		"Unknown road identity cannot change contact")
	check(car.reconcile_road_contact(2,-6.0) and car.road_layer==-1
		and car.collision_mask==Elevation.collision_bits(1,-6.0),
		"Guest correction restores tunnel contact at the same XY")
	check(Objectives.matches(car,-1) and not Objectives.matches(car,1) and not Objectives.matches(car,0),
		"Tunnel vehicle cannot satisfy a surface or bridge objective")
	check(car.reconcile_road_contact(-1,0.0) and car.road_layer==0
		and car.collision_mask==1 and car.road_contact_id()==-1,
		"Host ground correction restores original collision mask")

	check(Objectives.matches(car,0) and not Objectives.matches(car,-1) and not Objectives.matches(car,1),
		"Legacy ground objective rejects stacked levels")
	world.queue_free()
	car.queue_free()
	blocker.queue_free()
	await process_frame
	if failures.is_empty():print("ROAD ELEVATION DRIVE: PASS")
	quit(0 if failures.is_empty() else 1)
