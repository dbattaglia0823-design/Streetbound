extends SceneTree
## A conservative test driver uses the actual controller to cross the city and
## reach the marina. It is a regression harness, not an AI traffic system.
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
	route.append(car.position/20)
	var hops := ["start","wm","dw","dc","de","em","he","tw","tc","te","marina","tse","saltair_entry","ts"]
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
	var progress := 0
	var grass_frames := 0
	var impacts := [0]
	car.impacted.connect(func(strength: float):
		if strength>1.0:
			impacts[0]+=1
			print("DRIVE IMPACT: position=",car.position/20," strength=",strength))
	var finished := false
	var ticks := 0
	for frame in 54000:
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
		while target_index<route.size()-1 and reach<maxf(7.0,speed*.7):
			reach+=route[target_index].distance_to(route[target_index+1])
			target_index+=1
		var to_target := route[target_index]-p
		var forward := Vector2.UP.rotated(car.rotation)
		var error := forward.angle_to(to_target)
		var turn := absf(error)
		var desired_speed := 16.0 if turn<.15 else (10.0 if turn<.45 else 5.0)
		# Brake before a sharp junction turn, rather than beginning a fast turn
		# from the driveway and cutting through the off-road corner buildings.
		var preview := progress
		var ahead := 0.0
		var upcoming_turn := 0.0
		while preview<route.size()-2 and ahead<maxf(16,speed*1.4):
			var segment := route[preview+1]-route[preview]
			if segment.length()>.05: upcoming_turn=maxf(upcoming_turn,absf(forward.angle_to(segment)))
			ahead+=segment.length()
			preview+=1
		if upcoming_turn>.9: desired_speed=minf(desired_speed,4.5)
		elif upcoming_turn>.45: desired_speed=minf(desired_speed,7.0)
		var steer := clampf(error*3.0+car.slip_angle*.4-car.yaw_rate*.12,-1,1)
		var throttle := clampf((desired_speed-speed)*.5,0,1)
		var brake := clampf((speed-desired_speed)*.3,0,.75)
		car.step_vehicle(1.0/120,Vector4(throttle,brake,steer,0))
		if car.surface=="GRASS": grass_frames+=1
		if progress>=route.size()-5 and p.distance_to(route[-1])<15:
			finished=true
			break
	print("WORLD DRIVE: arrived=%s time=%.1fs impacts=%d grass=%.2f%% progress=%d/%d" % [finished,ticks/120.0,impacts[0],100.0*grass_frames/maxi(1,ticks),progress,route.size()])
	quit(0 if finished and impacts[0]==0 and float(grass_frames)/ticks<.05 else 1)
