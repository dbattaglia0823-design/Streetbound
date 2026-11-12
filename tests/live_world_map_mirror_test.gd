extends SceneTree
## Verify map and minimap reuse current playable drawing geometry, not a
## saved image or approximate second building/road representation.
const Mirror = preload("res://scripts/world/coast_map_world_mirror.gd")
const Chunk = preload("res://scripts/world/coast_chunk.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(name: String, good: bool, info: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL", name, info])
	if not good:
		failures.append(name)


func run() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.vehicle.set_physics_process(false)
	await process_frame
	var hud: Node
	for node in scene.get_children():
		if node.get_script() == load("res://scripts/world/world_map_hud.gd"):
			hud = node
			break
	check("map_hud_available", hud != null)
	if hud == null:
		quit(1)
		return
	var mini: Control = hud.mini_view
	var atlas: Control = hud.full_view
	var real: MorrowCoast = scene.ground
	var live_mirror: Node2D = mini.ink.mirror
	check("same_current_world_data_for_both_maps",
		hud.model.data == real.data and mini.ink.world == real and
		atlas.ink.world == real)
	check("minimap_uses_native_world_art", mini.ink.mirror_enabled and
		live_mirror.available)
	check("no_persistent_png_cache_required", not FileAccess.file_exists(
		"user://streetbound-map-cache.png"))
	var first := Mirror.region_cells(mini.player_m, mini.pixels_per_m,
		mini.custom_minimum_size, real.chunk_m, hud.model.extent)
	check("bounded_minimap_cell_selection",
		first.size() > 0 and first.size() <= Mirror.MAX_CACHED_CELLS,
		first.size())
	for i in 15:
		await process_frame
	check("real_world_chunks_drawn_in_mini",
		live_mirror.chunks.size() > 0 and live_mirror.built_count > 0,
		live_mirror.chunks.size())
	var render_only := true
	var same_sources := true
	for chunk in live_mirror.chunks.values():
		render_only = render_only and chunk.get_script() == Chunk and \
			bool(chunk.map_render_only) and chunk.collider_body == null
		for batch in chunk.road_batches:
			same_sources = same_sources and real.data.roads.has(batch.road)
		for prop in chunk.prop_list:
			same_sources = same_sources and real.data.props.has(prop)
	check("map_chunks_do_not_allocate_collision_bodies", render_only)
	check("native_map_road_and_building_sources", same_sources)
	# Full atlas opens on a broad low-cost overview, but zoomed-in images
	# switch to the same native renderer and update from the same world.
	check("full_region_overview_remains_bounded",
		not atlas.ink.mirror_enabled and
		atlas.ink.mirror.chunks.is_empty())
	atlas.focus_on(Vector2(3240.0, 2808.0), atlas.fit_scale * 18.0)
	check("downtown_atlas_switches_to_native_chunk_art",
		atlas.ink.mirror_enabled and atlas.ink.mirror.available,
		atlas.pixels_per_m)
	for i in 15:
		await process_frame
	var downtown_count := 0
	var physical_collision_count := 0
	for chunk in atlas.ink.mirror.chunks.values():
		for prop in chunk.prop_list:
			if prop.has("downtown_pilot_style"):
				downtown_count += 1
		if chunk.collider_body != null:
			physical_collision_count += 1
	check("edited_downtown_assets_appear_in_rebuilt_atlas",
		downtown_count > 0, downtown_count)
	check("atlas_does_not_duplicate_world_physics",
		physical_collision_count == 0)
	# A second view reconfiguration after panning reuses cached chunk
	# illustrations, without writing PNGs or requiring a rebuild on disk.
	var prior := atlas.ink.mirror.built_count
	atlas.ink.mirror.configure(atlas.center_m, atlas.pixels_per_m,
		atlas.custom_minimum_size, hud.model.extent)
	check("same_view_reuses_loaded_visual_chunks",
		atlas.ink.mirror.built_count == prior)
	atlas.fit_region()
	check("zooming_out_releases_high_detail_world_mirror",
		not atlas.ink.mirror_enabled and atlas.ink.mirror.chunks.is_empty())
	print("LIVE WORLD MAP MIRROR: ",
		"PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
