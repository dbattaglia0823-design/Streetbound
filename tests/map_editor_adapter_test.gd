extends SceneTree
## Smoke check the standalone browser editor's Godot runtime adapter.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, good: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if good else "FAIL",label,detail])
	if not good:
		failures.append(label)

func run() -> void:
	var loader: Variant = Node2D.new()
	loader.set_script(preload("res://map-editor/world_loader.gd"))
	loader.build_collision = false
	root.add_child(loader)
	var source := FileAccess.get_file_as_string("res://map-editor/tests/runtime-priority.world.json")
	check("editor_runtime_loader_imports",loader.load_world_json(source))
	var paths: Array = loader.get_road_paths()
	check("two_road_records",paths.size() == 2)
	if paths.size() == 2:
		var pieces: Array = paths[1].traversable_segments
		check("runtime_has_two_separate_dirt_branches",pieces.size() == 2,pieces.size())
		check("original_dirt_centerline_remains_editable",
			(paths[1].points as PackedVector2Array).size() >= 2)
	var road: Dictionary = loader.road_near(Vector2(800,600))
	check("paved_road_priority_at_crossing",not road.is_empty() and road.surface=="asphalt",
		road.get("surface","none"))
	var trail: Dictionary = loader.road_near(Vector2(800,200))
	check("dirt_is_active_before_crossing",not trail.is_empty() and trail.surface=="dirt",
		trail.get("surface","none"))
	var after: Dictionary = loader.road_near(Vector2(800,900))
	check("dirt_is_active_after_crossing",not after.is_empty() and after.surface=="dirt",
		after.get("surface","none"))
	check("junction_does_not_connect_pavement_and_dirt",
		loader.get_junctions().is_empty(),loader.get_junctions().size())
	print("EDITOR MAP ADAPTER: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
