extends SceneTree
## Full-scene smoke test: actual physics callbacks, input, UI, audio and camera.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(name: String, condition: bool) -> void:
	print("%s %s" % ["PASS" if condition else "FAIL", name])
	if not condition:
		failures.append(name)

func run() -> void:
	var main: Node = load("res://scenes/proving_ground.tscn").instantiate()
	root.add_child(main)
	var car: VehicleController2D = main.vehicle
	await physics_frame
	Input.action_press("throttle")
	for i in 240:
		await physics_frame
	Input.action_release("throttle")
	check("live_input_drives_vehicle", car.linear_velocity.length() > 10)
	var camera: Camera2D
	var hud: CanvasLayer
	var audio: Node
	for child in main.get_children():
		if child is Camera2D:
			camera = child
		elif child is CanvasLayer and child.get_script() == load("res://scripts/ui/driving_hud.gd"):
			hud = child
		elif child.get_script() == load("res://scripts/audio/vehicle_audio.gd"):
			audio = child
	check("audio_layers_playing", audio.engine.playing and audio.tires.playing)
	Input.action_press("camera")
	await physics_frame
	await physics_frame
	Input.action_release("camera")
	check("camera_toggle", camera.follow_heading)
	car.transmission.automatic = false
	car.transmission.shift_timer = 0.0
	var old_gear := car.transmission.gear
	car.transmission.shift(1, car.config)
	check("manual_shift", car.transmission.gear == old_gear + 1)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F1
	event.keycode = KEY_F1
	event.pressed = true
	root.push_input(event)
	await process_frame
	await process_frame
	check("tuning_panel_toggle", hud.tuning.visible)
	var controls: Node = root.get_node("Controls")
	# Tests use isolated user data; start and finish with the documented throttle key.
	controls.bind_key("throttle", KEY_W)
	var previous := InputMap.action_get_events("throttle")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_B
	controls.bind_event("throttle", pad)
	check("controller_rebind", InputMap.action_has_event("throttle", pad))
	controls.bind_key("throttle", KEY_UP)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_UP
	check("keyboard_rebind", InputMap.action_has_event("throttle", key))
	var saved := ConfigFile.new()
	check("bindings_persist", saved.load("user://controls.cfg") == OK and saved.has_section_key("bindings", "throttle"))
	InputMap.action_erase_events("throttle")
	for binding in previous:
		InputMap.action_add_event("throttle", binding)
	# Save restored bindings so the test does not change the user's defaults.
	for binding in previous:
		if binding is InputEventKey:
			controls.bind_key("throttle", binding.physical_keycode)
	car.linear_velocity = Vector2.UP * 20
	car.handbrake = 1
	for i in 1000:
		# Simulate the real rear contact moving; stationary contact produces
		# no visible mark and must not use an artificial quad stamp.
		car.global_position += Vector2(0,-8)
		main.ground._physics_process(0.05)
	var marks: TireMarks2D = main.ground.tire_marks
	check("mark_pool_bounded",marks.point_count() <= marks.CAPACITY and
		marks.trail_count() <= marks.MAX_TRAILS and marks.point_count() > 250)
	check("mark_pool_recycles_complete_connected_trails",
		marks.count > marks.MAX_TRAILS and marks.trail_count() <= marks.MAX_TRAILS)
	car.reset_vehicle()
	check("live_reset", car.linear_velocity == Vector2.ZERO and car.global_position == Vector2(0, 500))
	print("RUNTIME TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
