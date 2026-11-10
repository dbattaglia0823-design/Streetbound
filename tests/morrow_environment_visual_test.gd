extends SceneTree
## Runtime smoke: static city dressing, POI facades, planted terrain, traffic
## and map streaming coexist without adding per-furniture physics actors.
const Furnish = preload("res://scripts/world/coast_roadside_details.gd")
const Coast = preload("res://scenes/main.tscn")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, good: bool, info: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL",label,info])
	if not good:
		failures.append(label)

func run() -> void:
	var main: Node = Coast.instantiate()
	root.add_child(main)
	await physics_frame
	var world: MorrowCoast = main.ground
	main.vehicle.set_physics_process(false)
	check("real_coast_loaded",world.data.has("roads") and world.data.roads.size()>80)
	var details_count := 0
	var road_chunk_count := 0
	for chunk in world.chunks.values():
		if chunk.road_batches.is_empty():
			continue
		road_chunk_count += 1
		var details: Node2D = chunk.get_node_or_null("StreetDetails")
		if details != null:
			details_count += 1
			check("details_have_baked_path",details.road_batches.size()>0)
			check("details_have_correct_chunk_size",
				is_equal_approx(details.chunk_size_px,world.chunk_m*20.0))
			check("details_skip_outside_chunk",not details._in_chunk(Vector2(-10,-10)))
			check("details_accept_inside_chunk",details._in_chunk(Vector2(250,250)))
	check("road_chunks_have_furniture_layer",road_chunk_count==details_count,
		[road_chunk_count,details_count])
	var src := FileAccess.get_file_as_string("res://scripts/world/coast_scenery.gd")
	check("landmark_facades_are_shared",src.contains("_landmark_sign"))
	check("parking_driveway_opening_is_visible",src.contains("opening"))
	var utility := FileAccess.get_file_as_string("res://scripts/world/coast_roads.gd")
	check("manhole_and_drain_paint_exists",utility.contains("_street_surface_details"))
	var baked := FileAccess.get_file_as_string("res://tools/morrow_editor_import.py")
	check("authoring_scales_and_types_bake",baked.contains("EDITOR_PROP_STYLES"))
	check("traffic_remains_bounded",world.get_node_or_null("AmbientTraffic")!=null)
	print("MORROW ENVIRONMENT UPGRADES: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
