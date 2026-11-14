extends SceneTree
## Validate playable geometry against the actual streamed Godot collision space.
var failures: Array[String] = []
var world: MorrowCoast
var car: VehicleController2D

func _initialize() -> void:
	call_deferred("run")

func check(name: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s %s" % ["PASS" if passed else "FAIL",name,detail])
	if not passed:
		failures.append(name)

func vec(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))

func load_at(position_px: Vector2) -> void:
	car.global_position = position_px
	world.stream_at(position_px)
	while not world.pending.is_empty():
		world._build_chunk(world.pending.pop_front())
	car.reset_physics_interpolation()

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	world = main.ground
	car = main.vehicle
	car.set_physics_process(false)
	await physics_frame
	check("default_scene_is_open_world", world is MorrowCoast)
	check("world_scale_matches_vehicle", float(world.data.pixels_per_metre)==car.PIXELS_PER_METER and Engine.physics_ticks_per_second==120)
	check("garage_spawn_is_asphalt",world.surface_at(car.position).name=="ASPHALT",car.position/20)
	var spawn := car.position
	# The parking spawn faces north; the paved driveway leaves to the
	# southeast. Follow its actual tangent instead of driving into the lawn.
	var departure: Dictionary=world.nearest_road_at(spawn,12.0)
	check("garage_has_a_paved_departure",not departure.is_empty() and departure.road_kind=="driveway")
	if not departure.is_empty():car.global_rotation=Vector2(departure.tangent).angle()+PI*.5
	for i in 240:
		await physics_frame
		car.step_vehicle(1.0/120,Vector4(1,0,0,0))
	check("actual_driving_from_garage",car.position.distance_to(spawn)>150 and car.surface=="ASPHALT",car.linear_velocity.length())
	car.reset_vehicle()
	car.set_physics_process(false)
	check("reset_returns_to_garage",car.position==spawn and car.linear_velocity==Vector2.ZERO)
	var atlas: CanvasLayer
	for child in main.get_children():
		if child.get_script()==load("res://scripts/world/world_map_hud.gd"):
			atlas=child
	var tab := InputEventKey.new()
	tab.keycode=KEY_TAB
	tab.physical_keycode=KEY_TAB
	tab.pressed=true
	root.push_input(tab)
	await process_frame
	await process_frame
	check("tab_opens_playable_atlas",atlas!=null and atlas.full.visible and not atlas.mini.visible)
	tab=tab.duplicate()
	root.push_input(tab)
	await process_frame
	check("tab_returns_to_minimap",not atlas.full.visible and atlas.mini.visible)
	# Every centerline sample and junction must resolve to drivable pavement.
	var surface_gaps := 0
	var query_start := Time.get_ticks_usec()
	world.segment_tests = 0
	world.surface_queries = 0
	for road in world.data.roads:
		for raw in road.points:
			if world.surface_at(vec(raw)*20).name=="GRASS":
				surface_gaps+=1
	for junction in world.data.junctions:
		if world.surface_at(vec(junction.p)*20).name=="GRASS":
			surface_gaps+=1
	check("continuous_road_and_junction_surfaces",surface_gaps==0,surface_gaps)
	var average := float(world.segment_tests)/maxi(world.surface_queries,1)
	check("surface_lookup_is_spatially_bounded",average<100,[average,(Time.get_ticks_usec()-query_start)/1000.0])
	# Check connectivity independently of the baker's count.
	var adjacency: Dictionary = {}
	for connection in world.data.road_connections:
		var a := int(connection[0])
		var b := int(connection[1])
		if not adjacency.has(a): adjacency[a]=[]
		if not adjacency.has(b): adjacency[b]=[]
		adjacency[a].append(b)
		adjacency[b].append(a)
	var visited := {0:true}
	var pending := [0]
	while not pending.is_empty():
		var here: int = pending.pop_back()
		for next in adjacency.get(here,[]):
			if not visited.has(next):
				visited[next]=true
				pending.append(next)
	check("all_routes_and_facilities_connected",visited.size()==world.data.roads.size(),visited.size())
	check("five_distinct_regions",world.data.districts.size()==5)
	check("beach_has_sand_traction",world.surface_at(Vector2(5320,400)*20).name=="SAND")
	check("water_bridge_spans_exist",world.data.bridges.size()>=3,world.data.bridges.size())
	# Mountain road and art share elevation data; the cut faces must be convex
	# so tight inside bends never generate invalid/self-crossing render meshes.
	var valid_relief := true
	for face in world.data.relief_faces:
		var polygon := PackedVector2Array([vec(face.toe[0]),vec(face.toe[1]),vec(face.lip[1]),vec(face.lip[0])])
		if Geometry2D.triangulate_polygon(polygon).size()!=6: valid_relief=false
	check("mountain_cut_faces_triangulate",valid_relief,world.data.relief_faces.size())
	check("mountain_has_downhill_guardrails",world.data.mountain_rails.size()>500,world.data.mountain_rails.size())
	var reversals := 0
	var last_direction := 0
	var lower := 0.0
	var upper := 0.0
	for road in world.data.roads:
		if road.name!="Juniper Pass": continue
		if road.start=="mwest": lower=float(road.visual_elevation_m[0])
		if road.end=="overlook": upper=float(road.visual_elevation_m[-1])
		for i in range(1,road.points.size()):
			var dx := vec(road.points[i]).x-vec(road.points[i-1]).x
			if absf(dx)<.1: continue
			var direction := 1 if dx>0 else -1
			if last_direction!=0 and direction!=last_direction: reversals+=1
			last_direction=direction
	check("linked_mountain_switchbacks",reversals>=6,reversals)
	check("pass_climbs_to_overlook",upper-lower>600,[lower,upper])
	# Probe the full vehicle footprint, not just rays, at 5 positions per road.
	var blocked: Array[String] = []
	var shape: Shape2D = car.get_node("CollisionShape2D").shape
	for road in world.data.roads:
		var points: Array = road.points
		for fraction in [0.0,.25,.5,.75,.98]:
			var index := mini(int((points.size()-1)*fraction),points.size()-2)
			var p := vec(points[index])*20
			var q := vec(points[index+1])*20
			load_at(p)
			await physics_frame
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = shape
			query.transform = Transform2D((q-p).angle()+PI/2,p)
			query.collision_mask = 1
			if not root.world_2d.direct_space_state.intersect_shape(query,1).is_empty():
				blocked.append("%s %.2f" % [road.name,fraction])
	check("vehicle_clearance_on_roads_and_bridges",blocked.is_empty(),blocked)
	# A real building must block, and crossing chunk boundaries must unload old
	# districts rather than retaining every building and tree in the whole map.
	var target: Dictionary = {}
	for prop in world.data.props:
		if prop.kind=="garage":
			target=prop
			break
	var center := vec(target.p)*20
	load_at(center)
	await physics_frame
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = 1
	# Laurel Motor House is now a real drive-in garage. The empty center
	# contains the player's parking bay, while its two wings and rear wall
	# must remain collision-solid.
	query.position = center
	check("laurel_garage_bay_is_open",
		root.world_2d.direct_space_state.intersect_point(query,1).is_empty())
	var size := vec(target.size)
	var solid_wall := Vector2(0.0, -size.y * 0.43).rotated(float(target.angle))
	query.position = center + solid_wall * 20.0
	check("building_collision_active",
		not root.world_2d.direct_space_state.intersect_point(query,1).is_empty())
	for district in world.data.districts:
		load_at(vec(district.p)*20)
		await physics_frame
	check("streaming_remains_bounded",world.chunks.size()<=25,world.chunks.size())
	check("world_is_streamed_not_fully_instantiated",world.chunks.size()<world.data.chunks.size()/10,[world.chunks.size(),world.data.chunks.size()])
	print("OPEN WORLD TESTS: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
