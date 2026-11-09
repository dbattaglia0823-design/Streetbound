extends SceneTree
## Render every baked junction, including endpoints, crossroads and roundabouts.
func _initialize() -> void:
	call_deferred("run")

func v(p: Array) -> Vector2:
	return Vector2(float(p[0]),float(p[1]))

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.vehicle.set_physics_process(false)
	var camera: Camera2D
	for child in main.get_children():
		if child is Camera2D: camera=child
	camera.set_physics_process(false)
	camera.zoom=Vector2.ONE*.74
	var captures := {"city":Vector2(2500,2870),"village":Vector2(1400,2920),"rural":Vector2(1460,2800),"parkway":Vector2(4160,2800),"roundabout":Vector2(2950,2216),"coast":Vector2(4780,2960),"garage":Vector2(4910,2965)}
	for j in main.ground.data.junctions:
		var center := v(j.p)
		var arm: Dictionary = j.approaches[0]
		for a in j.approaches:
			if a.control=="stop": arm=a; break
		var outward := v(arm.direction)
		var normal := Vector2(-outward.y,outward.x)
		main.vehicle.position=(v(arm.p)+outward*7-normal*float(arm.width)*.25)*20
		main.vehicle.rotation=outward.angle()-PI/2
		main.vehicle.reset_physics_interpolation()
		camera.position=center*20
		camera.reset_physics_interpolation()
		for i in 16: await process_frame
		await RenderingServer.frame_post_draw
		for name in captures:
			if center.distance_to(captures[name])<1:
				root.get_texture().get_image().save_png("res://.runtime/junction_%s.png"%name)
	print("JUNCTION RENDER TOUR: PASS ",main.ground.data.junctions.size())
	quit()
