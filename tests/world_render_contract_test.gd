extends SceneTree
## Main-scene regression for source assignments -> chunk setup -> render layers.
## Run without --headless for GPU district captures and framebuffer checks.
const Health = preload("res://scripts/world/world_render_health.gd")
const Chunk = preload("res://scripts/world/coast_chunk.gd")
const Dock = preload("res://scripts/ui/diagnostics_dock.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s %s"%["PASS" if passed else "FAIL",label,str(detail)])
	if not passed: failures.append(label)

func run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/morrow-coast.world.json"))
	check("archive_coordinates_and_assignments_compatible",Health.audit(source).compatible)
	var broken := source.duplicate(true)
	broken.chunks["12,15"].segments.clear()
	broken.chunks["12,15"].props.clear()
	var missing := Health.audit(broken)
	check("populated_source_with_missing_assignments_is_rejected",not missing.compatible and missing.status=="CHUNK ASSIGNMENT ERROR")
	broken=source.duplicate(false)
	broken.version=999
	check("incompatible_archive_version_is_reported",Health.audit(broken).status=="INCOMPATIBLE ARCHIVE")
	check("missing_archive_data_is_reported",not Health.audit({}).compatible)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var world: MorrowCoast = game.ground
	check("world_initialization_completed",world.initialization_complete)
	if not world.initialization_complete:
		quit(1)
		return
	game.vehicle.set_physics_process(false)
	var camera: Camera2D
	var hud: CanvasLayer
	for node in game.get_children():
		if node is Camera2D: camera=node
		if node.get_script()==load("res://scripts/ui/driving_hud.gd"): hud=node
	check("station_cache_complete_before_streaming",world.segment_stations.size()==source.segments.size())
	# Reproduce the original cascade: an empty station cache must not become
	# a successful green chunk even when source assignments are nonempty.
	var incomplete := Node2D.new()
	incomplete.set_script(load("res://scripts/world/morrow_coast.gd"))
	incomplete.data=world.data
	var rejected := Node2D.new()
	rejected.set_script(Chunk)
	rejected.setup(incomplete,Vector2i(12,15),world.data.chunks["12,15"])
	check("incomplete_chunk_build_is_explicitly_rejected",not rejected.setup_complete and rejected.setup_error=="Road stations not initialized")
	rejected.free()
	incomplete.free()
	camera.set_physics_process(false)
	camera.zoom=Vector2.ONE*.62
	var districts := {"spawn":world.spawn_position()/20,"downtown":Vector2(3070,2790),"coast":Vector2(4790,2670),"village":Vector2(1400,2920),"mountain":Vector2(1600,710),"circuit":Vector2(3490,3770)}
	var gpu := DisplayServer.get_name()!="headless"
	if gpu: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.runtime"))
	for name in districts:
		var point: Vector2 = districts[name]
		game.vehicle.position=point*20
		game.vehicle.linear_velocity=Vector2.ZERO
		game.vehicle.reset_physics_interpolation()
		camera.position=point*20
		camera.reset_physics_interpolation()
		world.stream_at(game.vehicle.position)
		for frame in 26: await process_frame
		var health := Health.snapshot(world)
		check(name+"_has_real_road_and_scenery_layers",health.status=="READY" and health.segments>0 and health.batches>0 and health.props>0 and health.visible_road_nodes>=4 and health.visible_scenery_nodes>0,health)
		var cell := Vector2i((point/world.chunk_m).floor())
		var chunk: Node2D = world.chunks[cell]
		check(name+"_world_pixel_conversion",chunk.global_position.is_equal_approx(Vector2(cell)*world.chunk_m*20))
		check(name+"_built_source_content",chunk.setup_complete and chunk.prop_list.size()==chunk.content.props.size())
		# Check a visible solid building's actual physical center. The open
		# player-garage bay intentionally has no center collider.
		var building: Dictionary = {}
		for loaded in world.chunks.values():
			if not loaded.stream_active: continue
			for prop in loaded.prop_list:
				if prop.solid and prop.kind in ["house","shop","warehouse","lodge"]:
					building=prop
					break
			if not building.is_empty(): break
		if not building.is_empty():
			await physics_frame
			var query := PhysicsPointQueryParameters2D.new()
			query.position=Vector2(float(building.p[0]),float(building.p[1]))*20
			query.collision_mask=1
			check(name+"_visible_building_has_collision",not root.world_2d.direct_space_state.intersect_point(query,1).is_empty())
		if gpu:
			await RenderingServer.frame_post_draw
			var shot := root.get_texture().get_image()
			shot.save_png("res://.runtime/renderfix_%s.png"%name)
			# Sample a real road point near the car but outside its artwork and
			# HUD. In the broken scene every sample is grass instead of asphalt.
			var asphalt := 0
			for dy in [-12.0,-8.0,8.0,12.0]:
				for dx in [-12.0,-8.0,8.0,12.0]:
					var sample_m := point+Vector2(dx,dy)
					if str(world.surface_at(sample_m*20).name)!="ASPHALT": continue
					var pixel: Vector2 = root.canvas_transform*(sample_m*20)
					pixel*=Vector2(shot.get_width(),shot.get_height())/Vector2(1440,900)
					if not Rect2(Vector2.ZERO,Vector2(shot.get_width(),shot.get_height())).has_point(pixel): continue
					var color := shot.get_pixelv(Vector2i(pixel))
					if color.b>color.r+.025 and color.r<.55: asphalt+=1
			check(name+"_asphalt_visible_in_actual_framebuffer",asphalt>0,asphalt)
	# Distinguish populated chunk data from missing data on an actual renderer.
	var active_cell := Vector2i((game.vehicle.position/20/world.chunk_m).floor())
	for node in world.chunks[active_cell].get_children():
		if node.get_script()==load("res://scripts/world/coast_roads.gd") and node.render_stage==1:
			var saved: Array[Dictionary] = node.road_batches
			var empty: Array[Dictionary] = []
			node.road_batches=empty
			check("renderer_handoff_failure_is_identified",Health.snapshot(world).status=="RENDER CONTENT MISSING")
			node.road_batches=saved
			break
	world.set_performance_debug(true)
	hud.tuning.visible=true
	world.set_geometry_debug(true)
	for frame in 3: await process_frame
	world._update_performance_display()
	check("F7_remains_available_with_F1_and_F4",world.performance_panel.visible)
	var overlaps := 0
	for rect in Dock.obstacles(root,world.performance_hud):
		if world.performance_panel.get_global_rect().intersects(rect): overlaps+=1
	check("F7_never_covers_other_HUD_controls",overlaps==0,overlaps)
	if gpu:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.runtime/renderfix_diagnostics.png")
	hud.tuning.visible=false
	world.set_geometry_debug(false)
	var map_hud: Node = get_first_node_in_group("streetbound_world_map_hud")
	map_hud.large=true
	for frame in 3: await process_frame
	check("F7_suspends_when_fullscreen_atlas_has_no_free_space",not world.performance_panel.visible)
	map_hud.large=false
	for frame in 3: await process_frame
	check("F7_returns_after_atlas_closes",world.performance_panel.visible)
	check("all_chunk_construction_succeeded",world.failed_chunks.is_empty())
	check("cache_reuse_still_works",world.cached_chunk_reuses>0,world.cached_chunk_reuses)
	print("WORLD RENDER CONTRACT: ","PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
