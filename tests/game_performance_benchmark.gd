extends SceneTree
## Opt-in repeatable wall-clock benchmark. Run with real GL rendering for FPS;
## headless runs measure CPU/load behavior only. Use an isolated test profile.
var failures: Array[String]=[]
var report: Dictionary={"format":"streetbound.game-performance.v1","runs":[]}

func _initialize() -> void:
	call_deferred("_run")

func _measure_frames(game: Node,label: String,count: int,drive: bool=false) -> Dictionary:
	var world: MorrowCoast=game.ground
	world.profile_enabled=true
	world._frame_times.clear();world._frame_cursor=0;world._last_frame_usec=0
	var begin:=Time.get_ticks_usec()
	var origin: Vector2=game.vehicle.global_position
	var draw_peak:=0
	var memory_peak:=0.0
	if drive:Input.action_press("throttle")
	for i in count:
		await process_frame
		draw_peak=maxi(draw_peak,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		memory_peak=maxf(memory_peak,Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	if drive:Input.action_release("throttle")
	var elapsed:=float(Time.get_ticks_usec()-begin)/1000000.0
	var stats:=world.frame_statistics()
	return {"scenario":label,"frames":count,"elapsed_seconds":elapsed,
		"observed_fps":count/maxf(.001,elapsed),"p95_ms":stats.p95_ms,
		"one_percent_low_fps":stats.one_percent_low,"samples":stats.samples,
		"draw_calls_peak":draw_peak,"texture_mb_peak":memory_peak/1048576.0,
		"static_memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,
		"distance_m":game.vehicle.global_position.distance_to(origin)/20.0,
		"traffic":world.get_node("AmbientTraffic").agents.size(),
		"chunk_builds":world.chunk_build_count,"chunk_reuses":world.cached_chunk_reuses,
		"worst_chunk_ms":float(world.max_chunk_build_usec)/1000.0}

func _run() -> void:
	report["renderer"]=DisplayServer.get_name()
	report["physics_hz"]=Engine.physics_ticks_per_second
	report["max_fps"]=Engine.max_fps
	report["note"]="Headless throughput is not gameplay FPS. Cold means first scene in this process, not cold OS disk cache."
	for pass_index in 2:
		var start:=Time.get_ticks_usec()
		var packed:=load("res://scenes/main.tscn") as PackedScene
		if packed==null:failures.append("game scene missing");break
		var game:=packed.instantiate()
		root.add_child(game);current_scene=game
		await process_frame
		if not is_instance_valid(game.ground) or not game.ground.initialization_complete or not is_instance_valid(game.vehicle):
			failures.append("game initialization failed");break
		var startup:=float(Time.get_ticks_usec()-start)/1000.0
		# Do not persist earnings or tuning during the measurement.
		game.vehicle_ownership.persist_enabled=false
		if is_instance_valid(game.get("living_world")):game.living_world.persist=false
		var run: Dictionary={"label":"first" if pass_index==0 else "repeat","startup_ms":startup,
			"main_ready_ms":game.startup_ms,"world_init_ms":game.ground.world_init_ms,
			"archive_parse_ms":game.ground.archive_parse_ms,"scenarios":[]}
		for i in 30:await process_frame
		run.scenarios.append(await _measure_frames(game,"initial neighborhood",120))
		game.ground.rain_intensity=1.0
		run.scenarios.append(await _measure_frames(game,"wet throttle workload",240,true))
		var menu_started:=Time.get_ticks_usec()
		game.pause_menu.pause_game()
		await process_frame
		run["first_pause_ms"]=float(Time.get_ticks_usec()-menu_started)/1000.0
		game.pause_menu.resume_game()
		menu_started=Time.get_ticks_usec()
		game.pause_menu.pause_game()
		await process_frame
		run["second_pause_ms"]=float(Time.get_ticks_usec()-menu_started)/1000.0
		game.pause_menu.resume_game()
		report.runs.append(run)
		current_scene=null
		game.queue_free()
		await process_frame;await process_frame
	if Engine.physics_ticks_per_second!=120:failures.append("physics tick rate changed")
	report["failures"]=failures
	print("STREETBOUND PERFORMANCE REPORT ",JSON.stringify(report))
	print("GAME PERFORMANCE BENCHMARK: ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
