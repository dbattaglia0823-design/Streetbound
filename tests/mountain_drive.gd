extends SceneTree
## Actual-controller mountain climb, including all linked hairpins.
var world: MorrowCoast
var car: VehicleController2D
var route := PackedVector2Array()

func _initialize() -> void:
	call_deferred("run")

func vec(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	world = main.ground
	car = main.vehicle
	# These legacy deterministic world-drive scripts test ROAD geometry.
	# With new real traffic collision they otherwise hit a random moving car
	# instead of testing the authored drivable route. Traffic collisions and
	# route recovery have their own dedicated regression suite.
	var traffic: Node2D = world.get_node_or_null("AmbientTraffic")
	if traffic != null:
		traffic.set("enabled",false)
		traffic.call("clear_traffic")
	car.set_physics_process(false)
	var hops := ["mwest","mstart","hairpin","overlook","summit"]
	for i in hops.size()-1:
		for road in world.data.roads:
			if road.start==hops[i] and road.end==hops[i+1]:
				for raw in road.points: route.append(vec(raw))
				break
			elif road.end==hops[i] and road.start==hops[i+1]:
				var points: Array = road.points.duplicate()
				points.reverse()
				for raw in points: route.append(vec(raw))
				break
	car.position=route[0]*20
	car.rotation=(route[1]-route[0]).angle()+PI/2
	car.linear_velocity=Vector2.ZERO
	world.stream_at(car.position)
	while not world.pending.is_empty(): world._build_chunk(world.pending.pop_front())
	car.reset_physics_interpolation()
	await physics_frame
	var progress := 0
	var grass_frames := 0
	var impacts := [0]
	car.impacted.connect(func(strength: float):
		if strength>1.0: impacts[0]+=1)
	var finished := false
	var ticks := 0
	for frame in 120000:
		await physics_frame
		ticks = frame+1
		var p := car.position/20
		var closest := INF
		for i in range(maxi(0,progress-2),mini(route.size(),progress+24)):
			var d := p.distance_squared_to(route[i])
			if d<closest:
				closest=d
				progress=i
		var speed := car.linear_velocity.length()
		var target_index := progress
		var reach := 0.0
		while target_index<route.size()-1 and reach<maxf(5.0,speed*.65):
			reach+=route[target_index].distance_to(route[target_index+1])
			target_index+=1
		var to_target := route[target_index]-p
		var forward := Vector2.UP.rotated(car.rotation)
		var error := forward.angle_to(to_target)
		var turn := absf(error)
		var desired_speed := 9.0 if turn<.15 else (6.5 if turn<.45 else 4.5)
		var steer := clampf(error*3.0+car.slip_angle*.4-car.yaw_rate*.12,-1,1)
		var throttle := clampf((desired_speed-speed)*.5,0,1)
		var brake := clampf((speed-desired_speed)*.3,0,.75)
		car.step_vehicle(1.0/120,Vector4(throttle,brake,steer,0))
		if car.surface=="GRASS": grass_frames+=1
		if progress>=route.size()-5 and p.distance_to(route[-1])<15:
			finished=true
			break
	print("MOUNTAIN DRIVE: arrived=%s time=%.1fs impacts=%d grass=%.2f%% progress=%d/%d" % [finished,ticks/120.0,impacts[0],100.0*grass_frames/maxi(1,ticks),progress,route.size()])
	quit(0 if finished and impacts[0]==0 and float(grass_frames)/ticks<.05 else 1)
