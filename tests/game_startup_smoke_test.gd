extends SceneTree
## Prevent the blank/green-screen regression: a HUD script compilation failure
## previously left the real main scene only half-initialized. Most world tests
## still passed because they checked map data rather than UI/camera readiness.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	check("main_scene_loads", scene != null)
	if scene == null:
		quit(1)
		return
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var world: MorrowCoast = main.get("ground") as MorrowCoast
	var car: VehicleController2D = main.get("vehicle") as VehicleController2D
	check("actual_morrow_coast_initialized", world is MorrowCoast)
	check("player_vehicle_spawned", car is VehicleController2D and is_instance_valid(car))
	var hud: CanvasLayer = null
	var camera: Camera2D = null
	var map_hud: CanvasLayer = null
	for child in main.get_children():
		if child is Camera2D:
			camera = child
		elif child is CanvasLayer and child.get_script() == load("res://scripts/ui/driving_hud.gd"):
			hud = child
		elif child is CanvasLayer and child.get_script() == load("res://scripts/world/world_map_hud.gd"):
			map_hud = child
	check("driving_hud_script_compiled_and_attached", hud != null)
	check("driving_hud_dashboard_built", hud != null and hud.get("dashboard") != null)
	check("driving_hud_tuning_menu_built", hud != null and hud.get("tuning") != null)
	check("camera_created_and_current", camera != null and camera.is_current())
	check("map_interface_initialized", map_hud != null and map_hud.get("mini_view") != null)
	check("controls_autoload_available", root.get_node_or_null("Controls") != null)
	check("spawn_chunk_built", world is MorrowCoast and world.chunks.size() > 0)
	check("spawn_coordinates_not_zero", car != null and car.global_position.length() > 1000)
	print("REAL GAME STARTUP: ", "PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
