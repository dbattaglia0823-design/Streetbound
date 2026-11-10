extends SceneTree
## Verify map chunk display/physics activation, cached edge reuse, boardwalk
## spatial index and image import budgets with the REAL Morrow Coast scene.
const Chunk = preload("res://scripts/world/coast_chunk.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, valid: bool, info: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if valid else "FAIL", label, info])
	if not valid:
		failures.append(label)

func _chunk_body(chunk: Node) -> StaticBody2D:
	for child in chunk.get_children():
		if child is StaticBody2D:
			return child
	return null

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var world: MorrowCoast = main.ground
	main.vehicle.set_physics_process(false)
	await physics_frame
	var start: Vector2 = world.spawn_position()
	var old_cell := Vector2i((start / (world.chunk_m * 20.0)).floor())
	check("spawn_chunk_loaded",world.chunks.has(old_cell))
	var old_chunk: Node = world.chunks[old_cell]
	var old_body := _chunk_body(old_chunk)
	check("player_chunk_active",old_chunk.visible and bool(old_chunk.stream_active))
	check("active_collision_present",old_body != null and old_body.collision_layer == 1)
	# Step two cells east: old chunk stays in the streaming hysteresis cache,
	# but must stop drawing and stop intercepting physical queries.
	var far_cell := old_cell + Vector2i(2,0)
	var far_point := (Vector2(far_cell) + Vector2(.5,.5)) * world.chunk_m * 20.0
	world.stream_at(far_point)
	check("outer_ring_kept_for_reuse",world.chunks.has(old_cell))
	check("dormant_chunk_not_drawn",not old_chunk.visible and not bool(old_chunk.stream_active))
	check("dormant_collision_disabled",old_body == null or old_body.collision_layer == 0)
	world._build_chunk(far_cell)
	check("new_center_is_visible",world.chunks.has(far_cell) and
		world.chunks[far_cell].visible)
	var next_chunk: Node = world.chunks[far_cell]
	var next_body := _chunk_body(next_chunk)
	check("new_center_collision_active",next_body == null or next_body.collision_layer == 1)
	check("no_more_than_nine_active_chunks",world.active_chunk_count() <= 9,
		[world.active_chunk_count(),world.chunks.size()])
	var builds_before := world.chunk_build_count
	world.stream_at(start)
	check("previous_player_chunk_reused",world.chunks[old_cell] == old_chunk and
		world.chunk_build_count == builds_before,[world.chunk_build_count,builds_before])
	check("previous_chunk_reactivated",old_chunk.visible and bool(old_chunk.stream_active))
	check("previous_collision_reactivated",old_body == null or old_body.collision_layer == 1)
	check("outer_ring_now_dormant",not next_chunk.visible and
		(next_body == null or next_body.collision_layer == 0))
	check("streaming_pool_bounded",world.chunks.size() <= 25,world.chunks.size())
	check("shoreline_cell_index_present",world._boardwalk_cells.size() > 4,
		world._boardwalk_cells.size())
	check("shoreline_path_cached",world.boardwalk_path.size() > 2)
	check("spawn_is_not_coastal_boardwalk",not world.boardwalk_near_cell(old_cell))
	var indexed: bool = true
	for cell in world._boardwalk_cells.keys():
		if not world.boardwalk_near_cell(cell):
			indexed = false
			break
	check("boardwalk_lookup_matches_baked_cells",indexed)
	# Empty land/ocean chunk should not instantiate four empty road stages,
	# two empty relief stages, a pair of scenery layers, or an empty physics body.
	var blank := Node2D.new()
	blank.set_script(Chunk)
	blank.setup(world,Vector2i(-20,-20),
		{"segments":[],"terrain":[],"props":[],"junctions":[],"walls":[],
		"relief":[],"rails":[]})
	root.add_child(blank)
	var optimized := true
	for child in blank.get_children():
		if child.get_script() == preload("res://scripts/world/coast_roads.gd") or \
			child.get_script() == preload("res://scripts/world/coast_relief.gd") or \
			child.get_script() == preload("res://scripts/world/coast_scenery.gd") or \
			child is StaticBody2D:
			optimized = false
	check("empty_chunk_skips_art_and_collision_nodes",optimized,blank.get_child_count())
	check("empty_chunk_collision_count_zero",int(blank.collision_shape_count) == 0)

	var road_shader: String = preload("res://scripts/world/road_surface.tres").shader.code
	var ground_shader: String = preload("res://scripts/world/mountain_ground.tres").shader.code
	check("road_weathering_world_aligned",road_shader.contains("world_pixel") and
		road_shader.contains("road_detail") and road_shader.contains("weathering"))
	check("road_high_frequency_anti_alias",road_shader.contains("fwidth"))
	check("terrain_grass_zoom_anti_alias",ground_shader.contains("blade_visibility") and
		ground_shader.contains("fwidth"))
	var art_paths: Array = preload("res://scripts/world/traffic_car.gd").MODEL_PATHS
	var optimized_art := true
	var all_mipmapped := true
	var worst_px := 0
	for path in art_paths:
		var image: Texture2D = load(path)
		if image == null:
			optimized_art = false
			all_mipmapped = false
			continue
		worst_px = maxi(worst_px,maxi(image.get_width(),image.get_height()))
		optimized_art = optimized_art and image.get_width() <= 512 and image.get_height() <= 512
		all_mipmapped = all_mipmapped and image.has_mipmaps()
	check("traffic_10_textures_import_at_gpu_friendly_size",optimized_art and
		art_paths.size() == 10,worst_px)
	check("distant_vehicle_models_have_mipmaps",all_mipmapped)
	print("MORROW MAP STREAM AND VISUAL QUALITY: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
