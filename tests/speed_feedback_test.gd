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
	check("streak_pool_fixed", overlay.streaks.size() == 64, overlay.streaks.size())
	check("speed_lines_are_quiet_when_parked",
		overlay.speed_intensity(0.0) == 0.0 and
		overlay.speed_intensity(8.0) < 0.01, overlay.intensity)
	check("speed_lines_are_noticeable_at_racing_speed",
		overlay.speed_intensity(48.0) > 0.95,
		overlay.speed_intensity(48.0))
	check("speed_streaks_stay_away_from_center",
		overlay.edge_strength(Vector2(600, 350), Vector2(1200, 700)) < 0.01 and
		overlay.edge_strength(Vector2(10, 350), Vector2(1200, 700)) > 0.85,
		overlay.edge_strength(Vector2(10, 350), Vector2(1200, 700)))
	check("no_streaks_at_rest", overlay.intensity == 0.0, overlay.intensity)
	# Drive these visual systems deterministically rather than racing their
	# internal frame loops during the scripted telemetry tests.
	car.set_physics_process(false)
	overlay.set_process(false)
	dust.set_process(false)
	body.set_process(false)
	camera.set_physics_process(false)
	var starting_zoom := camera.zoom.x
	car.linear_velocity = Vector2.UP * 45.0
	car.longitudinal_speed = 45.0
	car.throttle = 1.0
	for i in 5:
		overlay._process(0.05)
	camera._physics_process(0.25)
	check("speed_fx_responds_to_velocity", overlay.intensity > 0.35, overlay.intensity)
	check("speed_fx_reacts_to_acceleration",
		overlay.acceleration_pulse > 0.02, overlay.acceleration_pulse)
	check("camera_widens_with_speed", camera.zoom.x < starting_zoom, [starting_zoom, camera.zoom.x])
	car.slip_angle = 0.5
	car.wheel_spin = 0.5
	dust._process(0.05)
	check("skidding_creates_smoke", dust.puffs.size() > 0 and dust.puffs.size() <= dust.MAX_PUFFS, dust.puffs.size())
	check("smoke_emission_tracks_wheelspin_even_before_road_speed",
		dust.tire_smoke_strength(1.5, 0.0, 0.65, 0.0, "ASPHALT") > 0.35,
		dust.tire_smoke_strength(1.5, 0.0, 0.65, 0.0, "ASPHALT"))
	var rig: Node2D = car.get_node("Art/Wheels")
	var rear_left_contact: Vector2 = car.global_position + \
		rig.wheel_anchor(2).rotated(car.rotation)
	check("smoke_uses_rear_tire_hubs_not_fixed_anchors",
		dust._rear_wheel_contacts()[0].distance_to(rear_left_contact) < 0.01,
		dust._rear_wheel_contacts()[0])
	car.global_position += Vector2(0.0, -28.0)
	dust._process(0.05)
	check("asphalt_drifts_create_fading_rubber_tracks",
		dust.skid_marks.size() >= 2, dust.skid_marks.size())
	check("skid_mark_pool_is_bounded",
		dust.skid_marks.size() <= dust.MAX_MARKS, dust.skid_marks.size())
	for i in 70:
		dust._process(0.05)
	check("smoke_pool_bounded", dust.puffs.size() <= dust.MAX_PUFFS, dust.puffs.size())
	car.impacted.emit(15.0)
	check("impact_kicks_camera", camera.impact_strength > 0.0, camera.impact_strength)
	car.reset_vehicle()
	for i in 90:
		overlay._process(0.05)
		camera._physics_process(0.05)
		dust._process(0.05)
	check("speed_fx_fades_at_rest", overlay.intensity < 0.01, overlay.intensity)
	check("smoke_clears_when_stationary", dust.puffs.is_empty(), dust.puffs.size())
	check("rubber_tracks_fade_out",
		dust.skid_marks.is_empty(), dust.skid_marks.size())
	check("camera_shake_resolves", camera.impact_strength < 0.01, camera.impact_strength)
	print("SPEED FEEDBACK TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
