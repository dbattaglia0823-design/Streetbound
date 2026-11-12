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
	# On the original regression, mirror z=-20 put all colored road/roof
	# artwork BEHIND the field atlas background (z=0). Labels still drew.
	check("actual_map_world_is_above_panel_background_below_labels",
		not live_mirror.z_as_relative and live_mirror.z_index > 0 and
		live_mirror.z_index + 7 < mini.ink.z_index and
		mini.ink.z_index < mini.cursor.z_index,
		[live_mirror.z_index, mini.ink.z_index, mini.cursor.z_index])
	check("atlas_layer_stack_renders_road_then_labels_then_cursor",
		atlas.ink.z_index > atlas.ink.mirror.z_index + 7 and
		atlas.cursor.z_index > atlas.ink.z_index and
		atlas.race_overlay.z_index > atlas.ink.z_index and
		atlas.scale_bar.z_index > atlas.cursor.z_index)
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
	var visible_roads := 0
	var visible_props := 0
	for chunk in live_mirror.chunks.values():
		visible_roads += chunk.road_batches.size()
		visible_props += chunk.prop_list.size()
	check("mini_contains_real_road_and_building_content_not_only_labels",
		visible_roads > 0 and visible_props > 0,
		[visible_roads, visible_props])
	var render_only := true
	var same_sources := true
	for chunk in live_mirror.chunks.values():
		render_only = render_only and chunk.get_script() == Chunk and \
			bool(chunk.map_render_only) and chunk.collider_body == null
		for batch in chunk.road_batches:
			var road_id: int = int(batch.road.get("id", -1))
			same_sources = same_sources and road_id >= 0 and \
				road_id < real.data.roads.size() and \
				real.data.roads[road_id] == batch.road
		same_sources = same_sources and chunk.prop_list.size() <= \
			chunk.content.get("props", []).size()
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
	# All fifteen archive landmarks use a 42m driveway-to-facility offset.
	# Player start stays on actual drivable access while atlas pins sit on
	# the real buildings, rather than looking like shifted architecture.
	var anchored := 0
	for poi in real.data.pois:
		var actual: Vector2 = hud.model.poi_marker_position(poi)
		var access: Vector2 = hud.model.v(poi.position)
		if actual.distance_to(access) > 35.0 and \
				actual.distance_to(access) < 49.0:
			anchored += 1
	check("landmark_map_pins_resolve_actual_building_footprints",
		anchored >= 15, anchored)
	var spawn_m: Vector2 = real.spawn_position() / 20.0
	check("player_start_matches_real_access_road_not_facade",
		spawn_m.distance_to(hud.model.v(real.data.spawn.position)) < 0.01
		and spawn_m.distance_to(hud.model.poi_marker_position(
			real.data.pois[0])) > 35.0, spawn_m)
	check("map_vehicle_cursor_uses_same_metres_as_world",
		mini.player_m.distance_to(scene.vehicle.global_position / 20.0) < 0.01,
		[mini.player_m, scene.vehicle.global_position / 20.0])
	# Independent dealership art is not baked inside CoastChunk. Both
	# original facade and its real asphalt throat are mirrored as render-only
	# nodes and must be free of the showroom's physical collider.
	var dealer_sites: Array[Dictionary] = real.dealerships.sites
	if not dealer_sites.is_empty():
		var site: Dictionary = dealer_sites[0]
		var p := Vector2(float(site.center_m[0]), float(site.center_m[1]))
		atlas.focus_on(p, atlas.fit_scale * 18.0)
		await process_frame
		var pair: Array = atlas.ink.mirror.dealers.get(str(site.id), [])
		check("live_map_includes_real_dealership_and_forecourt",
			pair.size() == 2)
		if pair.size() == 2:
			check("mirrored_dealership_has_no_duplicate_collision",
				bool(pair[1].map_render_only) and
				pair[1].get_node_or_null("DealershipArtwork") != null and
				pair[1].get_node_or_null("BuildingCollision") == null)
	# Player movement across streamed cells must update the actual art,
	# instead of retaining an empty snapshot or leaving drawn roads behind.
	var previously_built: int = live_mirror.built_count
	scene.vehicle.global_position = Vector2(3200.0, 2900.0) * 20.0
	scene.vehicle.reset_physics_interpolation()
	for i in 30:
		await process_frame
	var active_roads := 0
	for chunk in live_mirror.chunks.values():
		active_roads += chunk.road_batches.size()
	check("minimap_rebuilds_visible_road_chunks_after_driving",
		live_mirror.available and
		live_mirror.built_count > previously_built and active_roads > 0 and
		mini.center_m.distance_to(scene.vehicle.global_position / 20.0) < 0.01,
		[previously_built, live_mirror.built_count, active_roads])
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
	# The full atlas should cover the vehicle status panel at top center.
	# Its ordinary minimap layer is restored when the atlas closes.
	hud.large = true
	hud._process(0.0)
	check("full_atlas_does_not_hide_under_progression_panel",
		hud.layer > 2, hud.layer)
	hud.large = false
	hud._process(0.0)
	check("small_map_returns_to_normal_hud_layer", hud.layer == 2, hud.layer)
	print("LIVE WORLD MAP MIRROR: ",
		"PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
