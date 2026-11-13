extends SceneTree
## Temporary/GPU-aware diagnostic for the ACTUAL game canvas. Headless scene
## checks only verify objects were instantiated, not that pixels were drawn.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")


func expect(label: String, condition: bool, value: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if condition else "FAIL", label, value])
	if not condition:
		failures.append(label)


func _run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.vehicle.set_physics_process(false)
	for frame in 55:
		await process_frame
	var ground: MorrowCoast = game.ground
	var car: VehicleController2D = game.vehicle
	var cam: Camera2D
	for node in game.get_children():
		if node is Camera2D:
			cam = node
	var first: Vector2i = Vector2i((ground.spawn_position() / (ground.chunk_m * 20.0)).floor())
	var chunk: Node2D = ground.chunks.get(first)
	expect("spawn_chunk_active", chunk != null and chunk.is_visible_in_tree(),
		[chunk, first, ground.chunks.size()])
	var roads := 0
	var buildings := 0
	if chunk != null:
		for child in chunk.get_children():
			if child.get_script() == load("res://scripts/world/coast_roads.gd"):
				roads += 1
			if child.get_script() == load("res://scripts/world/coast_scenery.gd"):
				buildings += 1
	print("GAME RENDER DIAG: spawn=", ground.spawn_position(),
		" car=",car.global_position," camera=",cam.global_position,
		" zoom=",cam.zoom," canvas=",root.canvas_transform,
		" chunk=",chunk.global_position," chunk_z=",chunk.z_index,
		" child_roads=",roads," child_scenery=",buildings,
		" source_segments=",ground.data.chunks["12,15"].segments.size(),
		" source_props=",ground.data.chunks["12,15"].props.size())
	expect("spawn_world_render_nodes_ready", roads >= 3 and buildings >= 1)
	expect("first_driving_frame_shows_entire_neighborhood",
		is_equal_approx(cam.zoom.x,cam.STARTUP_NEIGHBORHOOD_ZOOM) and
		bool(cam._neighborhood_view_active),cam.zoom)
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	print("GAME RENDER DIAG: driver=",DisplayServer.get_name(),
		" rendering=",RenderingServer.get_rendering_device(),
		" screenshot=",shot.get_width(),"x",shot.get_height())
	if shot.get_width() > 0 and shot.get_height() > 0:
		shot.convert(Image.FORMAT_RGB8)
		var corners := []
		for py in [shot.get_height() / 4,shot.get_height()/2,shot.get_height()*3/4]:
			for px in [shot.get_width()/4,shot.get_width()/2,shot.get_width()*3/4]:
				corners.append(shot.get_pixel(int(px),int(py)).to_html(false))
		print("GAME RENDER PIXELS 9: ",corners)
		# Read back the ACTUAL displayed pixel colors at stable, named source
		# positions. Simply checking that scripts and texture objects loaded is
		# not sufficient to prove the player can see a street or a building.
		for item in [
			{"name":"garage_roof","metres":Vector2(2378.0,3035.0)},
			{"name":"nearby_house","metres":Vector2(2466.0,3039.5)},
			{"name":"driveway_asphalt","metres":Vector2(2428.5,3038.5)},
			{"name":"background_grass","metres":Vector2(2448.0,3003.0)}
		]:
			# canvas_transform operates in the logical 1440x900 design
			# viewport. The GL capture may be a 1280x800 override window, so
			# convert logical screen coordinates to real framebuffer pixels.
			var pixel: Vector2 = root.canvas_transform * (item.metres * 20.0)
			var logical_size := Vector2(float(ProjectSettings.get_setting(
				"display/window/size/viewport_width", 1440)), float(ProjectSettings.get_setting(
				"display/window/size/viewport_height", 900)))
			pixel *= Vector2(float(shot.get_width()) / logical_size.x,
				float(shot.get_height()) / logical_size.y)
			var valid := (pixel.x >= 0.0 and pixel.y >= 0.0 and
				pixel.x < float(shot.get_width()) and pixel.y < float(shot.get_height()))
			print("GAME WORLD PIXEL ",item.name," at ",pixel," visible=",valid,
				" color=",shot.get_pixel(int(pixel.x),int(pixel.y)).to_html(false)
				if valid else "offscreen")
			expect("game_camera_contains_"+str(item.name),valid)
		var image_bytes := shot.save_jpg_to_buffer(0.7)
		var encoded := Marshalls.raw_to_base64(image_bytes)
		print("GAME_SCREENSHOT_BEGIN")
		for i in ceili(float(encoded.length())/900.0):
			print("IMAGECHUNK:",encoded.substr(i*900,900))
		print("GAME_SCREENSHOT_END")
	else:
		expect("actual_image_available",false)
	print("ACTUAL GAME RENDER DIAGNOSTIC: ",
		"PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
