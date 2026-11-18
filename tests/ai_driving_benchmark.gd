extends SceneTree
## End-to-end AI driving benchmark: real Morrow Coast racing routes,
## stock vehicle configs, live VehicleController2D physics and AI commands.
## Use: godot --headless --path . --fixed-fps 120 --script res://tests/ai_driving_benchmark.gd
## Optional: -- --smoke (one vehicle on each of the three real layouts)
const VehicleScene = preload("res://scenes/vehicle.tscn")
const AIDriver = preload("res://scripts/world/race_ai_driver.gd")
const Catalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const Metrics = preload("res://scripts/world/ai_benchmark_metrics.gd")
const PPM := 20.0
const OUTPUT_DIR := "res://.runtime/ai_benchmark"
const VEHICLES := ["acura-integra", "mclaren-570s", "cadillac-escalade"]
const LAYOUTS := [
	{"id":"ashford_drag", "race":"drag_race", "time_limit_s":45.0},
	{"id":"larkspur_street", "race":"street_race", "time_limit_s":115.0},
	{"id":"ashford_circuit", "race":"circuit_race", "time_limit_s":165.0}
]
const PROGRESS_SAMPLE_STEPS := 12
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		printerr("FAIL ", message)


func _run() -> void:
	seed(20261118)
	var args := OS.get_cmdline_user_args()
	var smoke := "--smoke" in args
	var world_scene: PackedScene = load("res://scenes/main.tscn")
	_check(world_scene != null, "benchmark main scene must load")
	if world_scene == null:
		quit(1)
		return
	var main: Node = world_scene.instantiate()
	root.add_child(main)
	await physics_frame
	var world: Node = main.get("ground")
	var idle_player: VehicleController2D = main.get("vehicle")
	_check(is_instance_valid(world) and is_instance_valid(idle_player),
		"real playable world and player must initialize")
	if not is_instance_valid(world) or not is_instance_valid(idle_player):
		quit(1)
		return
	idle_player.set_physics_process(false)
	idle_player.collision_mask = 0
	var traffic: Node = world.get_node_or_null("AmbientTraffic")
	if is_instance_valid(traffic):
		traffic.set("enabled", false)
		traffic.set_physics_process(false)
		traffic.call("clear_traffic")
	for id in ["drag_race", "street_race", "circuit_race"]:
		var race: Node = main.get(id)
		_check(is_instance_valid(race) and bool(race.get("available")) and
			race.get("navigation") != null, "race route available: " + id)
		if is_instance_valid(race):
			race.set_physics_process(false)
	if not _failures.is_empty():
		quit(1)
		return
	var rows: Array[Dictionary] = []
	# The smoke matrix remains representative of three different real cars
	# and all three actual layouts; the full matrix covers every pairing.
	for i in LAYOUTS.size():
		var layout: Dictionary = LAYOUTS[i]
		for j in VEHICLES.size():
			if smoke and i != j:
				continue
			var vehicle_id: String = VEHICLES[j]
			var result: Dictionary = await _run_case(
				main, world, layout, vehicle_id, false)
			rows.append(result)
	if not smoke:
		# Deliberately blocked physical road: exposes whether an AI stuck
		# behind a real collision can recover without teleporting.
		rows.append(await _run_case(main, world, LAYOUTS[1],
			"acura-integra", true))
	var finished := 0
	for row in rows:
		if bool(row.get("completed", false)):
			finished += 1
	var report := {
		"schema_version": 1,
		"benchmark": "Streetbound AI Driving",
		"mode": "smoke" if smoke else "full",
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"physics_hz": Engine.physics_ticks_per_second,
		"seed": 20261118,
		"real_world": "Morrow Coast",
		"vehicles": VEHICLES,
		"layouts": ["ashford_drag", "larkspur_street", "ashford_circuit"],
		"cases": rows.size(),
		"completions": finished,
		"results": rows
	}
	_check(rows.size() == (3 if smoke else 10), "all benchmark cases recorded")
	_check(_write_reports(report, rows), "JSON and CSV reports saved")
	print("AI DRIVING BENCHMARK: ",
		"PASS" if _failures.is_empty() else "FAIL ",
		" | completed=", finished, "/", rows.size(),
		" | output=.runtime/ai_benchmark/")
	# This is an observational benchmark: poor AI completion is recorded as
	# evidence, not hidden by making CI fail before reports are uploaded.
	quit(0 if _failures.is_empty() else 1)


func _run_case(main: Node, world: Node, layout: Dictionary,
		vehicle_id: String, obstructed: bool) -> Dictionary:
	var race: Node = main.get(str(layout["race"]))
	var navigation: RefCounted = race.get("navigation") as RefCounted
	var entry: Dictionary = Catalog.find_by_id(vehicle_id)
	if entry.is_empty() or navigation == null:
		_failures.append("missing stock vehicle or race route: " + vehicle_id)
		return {"vehicle_id":vehicle_id, "layout":layout["id"],
			"completed":false, "error":"missing stock vehicle or route"}
	var route: PackedVector2Array = navigation.get("points_m")
	var length_m: float = float(navigation.get("length_m"))
	var closed: bool = bool(navigation.get("closed"))
	if route.size() < 2 or length_m < 100.0:
		_failures.append("invalid benchmark route: " + str(layout["id"]))
		return {"vehicle_id":vehicle_id, "layout":layout["id"],
			"completed":false, "error":"invalid racing route"}
	var start_m: Vector2 = route[0]
	var forward: Vector2 = (route[1] - route[0]).normalized()
	var car: VehicleController2D = VehicleScene.instantiate() as VehicleController2D
	car.external_input = true
	car.surface_provider = world
	car.config = Catalog.make_configuration(entry)
	main.add_child(car)
	car.global_position = start_m * PPM
	car.global_rotation = forward.angle() + PI * 0.5
	car.linear_velocity = Vector2.ZERO
	car.velocity = Vector2.ZERO
	car.reset_physics_interpolation()

	var metrics := Metrics.new()
	car.crash_contact.connect(func(_speed: float, _point: Vector2,
			_normal: Vector2, _before: Vector2) -> void:
		metrics.collision())
	var driver: Node = AIDriver.new()
	driver.set("reaction_seconds", 0.0)
	driver.set("throttle_limit", 0.90)
	main.add_child(driver)
	driver.call("setup_navigation", car, navigation)
	driver.call("launch")
	var obstacle: StaticBody2D
	if obstructed:
		obstacle = StaticBody2D.new()
		obstacle.collision_layer = 1
		obstacle.collision_mask = 0
		var obstacle_shape := CollisionShape2D.new()
		var disk := CircleShape2D.new()
		disk.radius = 35.0
		obstacle_shape.shape = disk
		obstacle.add_child(obstacle_shape)
		main.add_child(obstacle)
		var obstacle_at: Vector2 = navigation.call("point_at", 48.0)
		obstacle.global_position = obstacle_at * PPM

	var timestep := 1.0 / float(Engine.physics_ticks_per_second)
	var max_frames := ceili(float(layout["time_limit_s"]) / timestep)
	var last_progress: float = float(navigation.call(
		"station_at", car.global_position / PPM))
	var forward_travel_m := 0.0
	var completed := false
	var best_cross_track_m := 0.0
	var wall_start_ms := Time.get_ticks_msec()
	for frame in max_frames:
		await physics_frame
		metrics.sample(timestep, car.global_position, car.linear_velocity.length(),
			car.command, str(car.surface))
		if frame % PROGRESS_SAMPLE_STEPS == 0:
			var station: float = float(navigation.call(
				"station_at", car.global_position / PPM))
			var delta: float = station - last_progress
			if closed:
				if delta < -0.5 * length_m:
					delta += length_m
				elif delta > 0.5 * length_m:
					delta -= length_m
			var max_step := maxf(3.0,
				car.linear_velocity.length() * timestep * PROGRESS_SAMPLE_STEPS * 2.0 + 2.0)
			if delta >= 0.0 and delta <= max_step:
				forward_travel_m += delta
			last_progress = station
			var projected: Vector2 = navigation.call("point_at", station)
			best_cross_track_m = maxf(best_cross_track_m,
				projected.distance_to(car.global_position / PPM))
			var end_distance: float = (car.global_position / PPM).distance_to(
				start_m if closed else route[route.size() - 1])
			if closed:
				completed = (forward_travel_m >= length_m - 10.0 and
					end_distance <= 15.0 and car.linear_velocity.dot(forward) > 0.5)
			else:
				completed = (forward_travel_m >= length_m * 0.90 and
					station >= length_m - 18.0 and end_distance <= 20.0)
			if completed:
				break
			# Detect a car that has irretrievably left the playable track.
			if best_cross_track_m > 180.0:
				break
	var wall_ms := Time.get_ticks_msec() - wall_start_ms
	driver.call("stop")
	var record: Dictionary = metrics.summary()
	record["vehicle_id"] = vehicle_id
	record["vehicle_name"] = str(entry.get("model",vehicle_id))
	record["vehicle_kind"] = str(entry.get("kind","unknown"))
	record["layout"] = layout["id"]
	record["obstructed"] = obstructed
	record["route_length_m"] = snappedf(length_m, 0.01)
	record["closed_circuit"] = closed
	record["completed"] = completed
	record["laps_completed"] = 1 if completed and closed else 0
	record["lap_times_s"] = [record["elapsed_s"]] if completed and closed else []
	record["run_time_s"] = record["elapsed_s"] if completed else null
	record["forward_route_distance_m"] = snappedf(forward_travel_m, 0.01)
	record["max_cross_track_error_m"] = snappedf(best_cross_track_m, 0.01)
	record["wall_time_ms"] = wall_ms
	record["status"] = "completed" if completed else "dnf_or_timeout"
	print("AI BENCH CASE ", str(layout["id"]), " / ", vehicle_id,
		" / ", "blocked" if obstructed else "clear", ": ",
		record["status"], " t=", record["elapsed_s"],
		" collisions=", record["collisions"],
		" offroad_s=", record["offroad_time_s"],
		" recoveries=", record["stuck_recoveries"])
	driver.queue_free()
	car.queue_free()
	if obstacle != null and is_instance_valid(obstacle):
		obstacle.queue_free()
	await physics_frame
	return record


func _csv_field(value: Variant) -> String:
	var text_value := str(value)
	if value == null:
		text_value = ""
	if text_value.contains(",") or text_value.contains("\n") or text_value.contains("\""):
		text_value = "\"" + text_value.replace("\"", "\"\"") + "\""
	return text_value


func _write_reports(report: Dictionary, rows: Array[Dictionary]) -> bool:
	var folder := ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return false
	var json_path := folder.path_join("ai_driving_benchmark.json")
	var csv_path := folder.path_join("ai_driving_benchmark.csv")
	var json_file := FileAccess.open(json_path, FileAccess.WRITE)
	if json_file == null:
		return false
	json_file.store_string(JSON.stringify(report, "\t") + "\n")
	json_file.close()
	var columns := [
		"vehicle_id", "layout", "obstructed", "status", "completed",
		"laps_completed", "run_time_s", "elapsed_s", "route_length_m",
		"forward_route_distance_m", "steering_corrections", "offroad_time_s",
		"offroad_fraction", "collisions", "stuck_events",
		"stuck_recoveries", "unresolved_stuck_events",
		"max_cross_track_error_m", "peak_speed_mps", "wall_time_ms"
	]
	var csv_file := FileAccess.open(csv_path, FileAccess.WRITE)
	if csv_file == null:
		return false
	csv_file.store_line(",".join(columns))
	for row in rows:
		var cells := PackedStringArray()
		for column in columns:
			cells.append(_csv_field(row.get(column)))
		csv_file.store_line(",".join(cells))
	csv_file.close()
	return FileAccess.file_exists(json_path) and FileAccess.file_exists(csv_path)
