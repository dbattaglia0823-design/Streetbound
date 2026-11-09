extends SceneTree
## GPU-rendered region inspection and a continuous streaming stress route.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var car: VehicleController2D = main.vehicle
	var world: MorrowCoast = main.ground
	car.set_physics_process(false)
	var destinations := {"spawn":world.spawn_position()/20,"market":Vector2(2880,2810),"coast":Vector2(5270,2830),"mountain":Vector2(650,1530),"hairpin":Vector2(260,1645),"summit":Vector2(1490,720),"country":Vector2(1500,3240),"circuit":Vector2(3490,3870)}
	for name in destinations:
		var desired: Vector2 = destinations[name]
		if name != "spawn":
			var best := INF
			for segment in world.data.segments:
				var a := Vector2(float(segment.a[0]),float(segment.a[1]))
				var b := Vector2(float(segment.b[0]),float(segment.b[1]))
				var candidate := Geometry2D.get_closest_point_to_segment(desired,a,b)
				if candidate.distance_squared_to(destinations[name])<best:
					best=candidate.distance_squared_to(destinations[name])
					desired=candidate
		car.position = desired*20
		car.linear_velocity = Vector2.ZERO
		car.reset_physics_interpolation()
		for i in 28:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.runtime/morrow_%s.png" % name)
	for child in main.get_children():
		if child.get_script()==load("res://scripts/world/world_map_hud.gd"):
			child.large=true
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.runtime/morrow_atlas.png")
			child.full_view.focus_on(Vector2(2800,2800),child.full_view.fit_scale*7)
			for i in 3: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.runtime/morrow_atlas_detail.png")
			child.full_view.focus_on(Vector2(1050,1160),child.full_view.fit_scale*3.2)
			for i in 3: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.runtime/morrow_mountain_atlas.png")
			child.large=false
	var times: Array[float] = []
	var slowest_frame := 0
	var slowest_time := 0.0
	var route: Array = []
	for road in world.data.roads:
		if road.name=="Laurel Avenue" or road.name=="Market Street" or road.name=="Foundry Crescent":
			route.append_array(road.points)
	for frame in 720:
		var started := Time.get_ticks_usec()
		var raw: Array = route[frame%route.size()]
		car.position = Vector2(float(raw[0]),float(raw[1]))*20
		car.linear_velocity = Vector2.UP*35
		car.slip_angle = 0.3 if frame%120<60 else 0.0
		car.handbrake = 1 if frame%120<30 else 0
		car.reset_physics_interpolation()
		await process_frame
		await RenderingServer.frame_post_draw
		var elapsed := (Time.get_ticks_usec()-started)/1000.0
		times.append(elapsed)
		if elapsed>slowest_time:
			slowest_time=elapsed
			slowest_frame=frame
	times.sort()
	var total := 0.0
	for t in times:
		total+=t
	print("WORLD RENDER ms mean=%.2f p95=%.2f p99=%.2f max=%.2f | chunks=%d | max build=%.2f ms" % [total/times.size(),times[int(times.size()*.95)],times[int(times.size()*.99)],times.back(),world.chunks.size(),world.max_chunk_build_usec/1000.0])
	print("Slowest stress-route frame: ",slowest_frame)
	# Mountain-only pass exercises cliff meshes, shadows and rails in dense cells.
	times.clear()
	route.clear()
	for road in world.data.roads:
		if road.name in ["Juniper Pass","Summit Ribbon"]: route.append_array(road.points)
	for frame in 720:
		var started := Time.get_ticks_usec()
		var raw: Array = route[(frame*2)%route.size()]
		car.position=Vector2(float(raw[0]),float(raw[1]))*20
		car.reset_physics_interpolation()
		await process_frame
		await RenderingServer.frame_post_draw
		times.append((Time.get_ticks_usec()-started)/1000.0)
	times.sort()
	total=0
	for t in times: total+=t
	print("MOUNTAIN RENDER ms mean=%.2f p95=%.2f p99=%.2f max=%.2f | max build=%.2f ms" % [total/times.size(),times[int(times.size()*.95)],times[int(times.size()*.99)],times.back(),world.max_chunk_build_usec/1000.0])
	quit()
