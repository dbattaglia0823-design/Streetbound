extends SceneTree
## First commercial city block art pilot. Existing authored world data is the
## source of truth; only textures on a tightly bounded cluster may change.
const Pilot = preload("res://scripts/world/downtown_block_pilot.gd")
const Scenery = preload("res://scripts/world/coast_scenery.gd")
const PPM := 20.0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, ok: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		failures.append(label)


func run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://worlds/morrow-coast.world.json"))
	check("world_json_available", parsed is Dictionary)
	if not parsed is Dictionary:
		quit(1)
		return
	var source: Array = parsed.props
	var selected: Array[int] = Pilot.find_block(source)
	check("downtown_block_contains_three_to_eight_authored_buildings",
		selected.size() >= 3 and selected.size() <= Pilot.MAX_BUILDINGS,
		selected.size())
	var one_cell := true
	var one_commercial_block := true
	var footprint_original := true
	var block_cell := Vector2i(-1, -1)
	var originals: Dictionary = {}
	for index in selected:
		var prop: Dictionary = source[index]
		originals[index] = prop.duplicate(true)
		var location: Vector2 = Pilot._position(prop)
		var cell: Vector2i = Pilot._cell(location)
		if block_cell == Vector2i(-1, -1):
			block_cell = cell
		one_cell = one_cell and cell == block_cell
		one_commercial_block = one_commercial_block and \
			str(prop.kind) in Pilot.TYPES and not prop.has("poi") and \
			location.distance_to(Pilot.HOTSPOT_M) <= Pilot.SEARCH_RADIUS_M
	check("pilot_stays_inside_one_downtown_block", one_cell and one_commercial_block,
		block_cell)
	var tagged: Array[int] = Pilot.apply(source)
	check("pilot_selection_deterministic", tagged == selected and \
		Pilot.apply(source) == tagged)
	var tagged_count := 0
	for i in source.size():
		var prop: Dictionary = source[i]
		if prop.has("downtown_pilot_style"):
			tagged_count += 1
			if originals.has(i):
				var copy: Dictionary = prop.duplicate(true)
				copy.erase("downtown_pilot_style")
				footprint_original = footprint_original and copy == originals[i]
			else:
				footprint_original = false
	check("only_selected_prop_metadata_changes",
		footprint_original and tagged_count == selected.size(),
		[tagged_count, selected.size()])
	var valid_textures := true
	for i in Pilot.SPRITES.size():
		var image_texture: Texture2D = Pilot.sprite(i)
		if image_texture == null:
			valid_textures = false
			continue
		var image: Image = image_texture.get_image()
		valid_textures = valid_textures and image.get_size() == Vector2i(512, 512)
		valid_textures = valid_textures and image.get_pixel(0,0).a < 0.05
		valid_textures = valid_textures and image.get_pixel(256,256).a > 0.95
	check("four_independent_transparent_city_building_textures",
		valid_textures and Pilot.SPRITES.size() == 4)
	# A real streamed chunk should contain the decorated authored props
	# without adding extra collision bodies, scenery nodes or map geometry.
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await physics_frame
	game.vehicle.set_physics_process(false)
	var world: MorrowCoast = game.ground
	var real_selected := 0
	for prop in world.data.props:
		if prop.has("downtown_pilot_style"):
			real_selected += 1
	check("production_world_uses_same_single_block",
		real_selected == selected.size(), real_selected)
	if not selected.is_empty():
		var chosen_prop: Dictionary = world.data.props[selected[0]]
		var position_px: Vector2 = Pilot._position(chosen_prop) * PPM
		world.stream_at(position_px)
		while not world.pending.is_empty():
			world._build_chunk(world.pending.pop_front())
		var cell := Vector2i((position_px / (PPM * world.chunk_m)).floor())
		var found := false
		if world.chunks.has(cell):
			var chunk: Node2D = world.chunks[cell]
			for node in chunk.get_children():
				if node.get_script() != Scenery:
					continue
				for prop in node.prop_list:
					if prop.has("downtown_pilot_style"):
						found = found or node.z_index == 6
		check("decorated_buildings_render_in_existing_above_road_scenery_layer", found)
	print("DOWNTOWN PILOT BLOCK: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
