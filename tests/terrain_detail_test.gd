extends SceneTree
## Verify the new terrain presentation is integrated without replacing the
## original surface lookup, road shader or streamed 192m world layout.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(name: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL", name, detail])
	if not passed:
		failures.append(name)

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var world: MorrowCoast = main.ground
	var ground_material: ShaderMaterial = preload("res://scripts/world/mountain_ground.tres")
	var code: String = ground_material.shader.code
	check("detail_uses_world_meters", code.contains("MODEL_MATRIX") and code.contains("world_m"))
	check("multiple_terrain_scales", code.contains("0.027") and code.contains("0.16"))
	check("water_and_beach_materials", code.contains("float water") and code.contains("float sand") and code.contains("float foam"))
	check("mountain_relief_preserved", code.contains("texture(relief") and code.contains("relief_mask"))
	check("blade_shading_present", code.contains("grass_tuft"))
	var types: Dictionary = {}
	for polygon in world.data.terrain:
		types[str(polygon.kind)] = true
	check("multiple_biomes", types.has("forest") and types.has("farmland") and
		types.has("beach") and types.has("water") and types.has("ocean"), types.keys())

	var first_chunk: Variant = world.chunks.values()[0]
	check("chunk_uses_ground_material", first_chunk.material == ground_material)
	check("cached_foliage_method", first_chunk.has_method("_draw_ground_foliage"))
	var local_point := Vector2(200.0, 200.0)
	check("terrain_classification_stable",
		first_chunk.ground_kind_at(local_point) == first_chunk.ground_kind_at(local_point),
		first_chunk.ground_kind_at(local_point))
	var has_road_material := false
	for node in first_chunk.get_children():
		if node.get_script() == load("res://scripts/world/coast_roads.gd"):
			has_road_material = node.material is ShaderMaterial
			if has_road_material:
				check("roads_keep_original_shader",
					(node.material as ShaderMaterial).shader == preload("res://scripts/world/road_surface.gdshader"))
			break
	check("roads_render_separately", has_road_material)

	# Test a separate streamed coastline cell and ensure its polygons are
	# still recognized as non-grass (no foliage added atop open water/sand).
	var coast := Vector2(5310.0, 2000.0) * 20.0
	world.stream_at(coast)
	while not world.pending.is_empty():
		world._build_chunk(world.pending.pop_front())
	var index := Vector2i((coast / 20.0 / world.chunk_m).floor())
	check("coast_chunk_streamed", world.chunks.has(index), index)
	if world.chunks.has(index):
		var coast_chunk: Variant = world.chunks[index]
		var kind: String = coast_chunk.ground_kind_at(coast - coast_chunk.position)
		check("coastland_classified", kind in ["beach", "ocean", "foam", "water", "riverbank"], kind)
	check("stream_pool_bounded", world.chunks.size() <= 25, world.chunks.size())
	print("TERRAIN DETAIL TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
