extends SceneTree
## Rendered stress run with a saturated mark pool. Use -- --silent to isolate audio.
var samples: Array[float] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var car: VehicleController2D = scene.vehicle
	var ground: ProvingGround = scene.ground
	var ground_draws := [0]
	ground.draw.connect(func(): ground_draws[0] += 1)
	car.set_physics_process(false)
	ground.set_physics_process(false)
	for child in scene.get_children():
		if child.get_script() == load("res://scripts/audio/vehicle_audio.gd") and "--silent" in OS.get_cmdline_user_args():
			child.set_process(false)
			for player in child.get_children():
				if player is AudioStreamPlayer:
					player.stop()
	# Seed marks along the skidpad, then continuously drift over the same area.
	for i in 1000:
		pose(car, ground, i * 0.04)
		ground._physics_process(0.05)
	for frame in 660:
		var started := Time.get_ticks_usec()
		pose(car, ground, frame * 0.025)
		ground._physics_process(1.0 / 60.0)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame >= 60:
			samples.append((Time.get_ticks_usec() - started) / 1000.0)
	samples.sort()
	var sum := 0.0
	for sample in samples:
		sum += sample
	print("DRIFT BENCHMARK (ms): mean=%.3f p95=%.3f p99=%.3f max=%.3f" % [sum / samples.size(), samples[int(samples.size() * 0.95)], samples[int(samples.size() * 0.99)], samples.back()])
	print("Ground drawing rebuilds: ", ground_draws[0], " | mark instances: ", ground.tire_marks.count)
	root.get_texture().get_image().save_png("res://.runtime/drift_benchmark.png")
	quit(0 if ground_draws[0] <= 1 and ground.tire_marks.count == 1800 else 1)

func pose(car: VehicleController2D, ground: ProvingGround, angle: float) -> void:
	car.position = ground.skidpad_center + Vector2.from_angle(angle) * 380
	car.rotation = angle + PI * 0.5
	car.linear_velocity = Vector2.UP.rotated(car.rotation) * 22
	car.slip_angle = 0.6
	car.handbrake = 1
	car.throttle = 0.5
	car.surface = "ASPHALT"
