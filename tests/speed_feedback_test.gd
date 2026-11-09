extends SceneTree
## Basic checks of camera, speed-line, body, smoke and reset feedback.
var failures: Array[String] = []

func check(label: String, condition: bool, detail: Variant) -> void:
	print("%s %s: %s" % ["PASS" if condition else "FAIL", label, detail])
	if not condition:
		failures.append(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var main: Node = load("res://scenes/proving_ground.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var car: VehicleController2D = main.vehicle
	var camera: Camera2D
	for node in main.get_children():
		if node is Camera2D:
			camera = node
	var overlay = main.get_node("SpeedFXLayer/SpeedOverlay")
	var dust = main.get_node("DrivingDust")
	var body = car.get_node("Art")
	check("vfx_nodes_present", camera != null and overlay != null and dust != null and body != null, main.get_child_count())
	check("streak_pool_fixed", overlay.streaks.size() == 50, overlay.streaks.size())
	check("no_streaks_at_rest", overlay.intensity == 0.0, overlay.intensity)
	var starting_zoom := camera.zoom.x
	car.linear_velocity = Vector2.UP * 45.0
	car.longitudinal_speed = 45.0
	car.throttle = 1.0
	for i in 5:
		overlay._process(0.05)
	camera._physics_process(0.25)
	check("speed_fx_responds_to_velocity", overlay.intensity > 0.25, overlay.intensity)
	check("camera_widens_with_speed", camera.zoom.x < starting_zoom, [starting_zoom, camera.zoom.x])
	car.slip_angle = 0.5
	car.wheel_spin = 0.5
	dust._process(0.05)
	check("skidding_creates_smoke", dust.puffs.size() > 0 and dust.puffs.size() <= dust.MAX_PUFFS, dust.puffs.size())
	for i in 70:
		dust._process(0.05)
	check("smoke_pool_bounded", dust.puffs.size() <= dust.MAX_PUFFS, dust.puffs.size())
	car.impacted.emit(15.0)
	check("impact_kicks_camera", camera.impact_strength > 0.0, camera.impact_strength)
	car.reset_vehicle()
	for i in 50:
		overlay._process(0.05)
		camera._physics_process(0.05)
		dust._process(0.05)
	check("speed_fx_fades_at_rest", overlay.intensity < 0.01, overlay.intensity)
	check("smoke_clears_when_stationary", dust.puffs.is_empty(), dust.puffs.size())
	check("camera_shake_resolves", camera.impact_strength < 0.01, camera.impact_strength)
	print("SPEED FEEDBACK TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
