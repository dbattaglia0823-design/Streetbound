extends SceneTree

## Atlas Coast is archived; the Driving Lab stays the default scene.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_check")

func expect_test(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _check() -> void:
	var adapter: Script = load("res://worlds/world_loader.gd")
	expect_test(adapter != null, "Archived Godot world loader should parse")
	if adapter == null:
		quit(1)
		return
	var world: Node2D = adapter.new()
	world.set("build_collision", false)
	root.add_child(world)
	var ok: bool = world.call("load_world", "res://worlds/atlas-coast.world.json")
	expect_test(ok, "Atlas Coast v2 map should load unchanged")
	if ok:
		expect_test(world.call("get_world_size") == Vector2(22000, 18000), "World dimensions unchanged")
		expect_test((world.call("get_road_paths") as Array).size() == 132, "All 132 roads preserved")
		expect_test((world.call("get_intersections") as Array).size() > 70, "Automatic road junctions preserved")
		expect_test((world.call("get_markers", "dealership") as Array).size() == 11, "All 11 dealers preserved")
		expect_test((world.call("get_markers", "fuel") as Array).size() == 18, "All 18 fuel stops preserved")
		expect_test((world.call("get_markers", "race_start") as Array).size() == 7, "All seven race starts preserved")
	world.queue_free()
	if failures.is_empty():
		print("STREETBOUND_ATLAS_ARCHIVE_PASS")
		quit(0)
	else:
		print("STREETBOUND_ATLAS_ARCHIVE_FAIL ",failures.size())
		quit(1)
