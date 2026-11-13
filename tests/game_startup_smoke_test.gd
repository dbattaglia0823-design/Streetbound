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
	# On Godot 4.6.3 the wheel resource's registered class was missing on
	# startup. Testing only the car physics would not catch its visual rig.
	var wheel_rig: Node = car.get_node_or_null("Art/Wheels") if car != null else null
	var appearance: Variant = wheel_rig.get("appearance") if wheel_rig != null else null
	check("wheel_rig_script_loaded", wheel_rig != null and
		wheel_rig.get_script() == load("res://scripts/visual/steerable_wheels.gd"))
	check("wheel_profile_resource_loaded", appearance != null and
		appearance.get_script() == load("res://scripts/vehicle/vehicle_appearance_profile.gd"))
	var inventory: RefCounted = main.get("vehicle_ownership") as RefCounted
	check("vehicle_ownership_initialized", inventory != null and inventory.has_method("owns") and
		inventory.has_method("save"))
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
	# The starter parking lot is 42m from the garage and 46m from the first
	# houses. A 1.272x spawn view hid both even when scenery rendered normally.
	check("initial_camera_frames_real_garage_and_nearby_houses",
		camera != null and bool(camera.get("startup_neighborhood_view")) and
		absf(camera.zoom.x - 0.62) < 0.02 and
		float(root.size.x) / camera.zoom.x / 40.0 > 48.0)
	check("map_interface_initialized", map_hud != null and map_hud.get("mini_view") != null)
	check("controls_autoload_available", root.get_node_or_null("Controls") != null)
	check("spawn_chunk_built", world is MorrowCoast and world.chunks.size() > 0)
	# A loaded road graph with zero scenery can look like an empty map.
	# Assert that real production assets survive the world bake and at least
	# one active chunk has its actual scenery Node2D ready to draw.
	var baked_assets := 0
	var visible_assets := 0
	var visible_art_nodes := 0
	if world != null and not world.data.is_empty():
		baked_assets = world.data.props.size()
		for chunk in world.chunks.values():
			if not chunk.visible:
				continue
			for art in chunk.get_children():
				if art.get_script() == load("res://scripts/world/coast_scenery.gd") and art.visible:
					visible_art_nodes += 1
					var scenery: Array = art.get("prop_list")
					visible_assets += scenery.size()
	check("world_archive_contains_baked_map_assets", baked_assets > 1000)
	check("player_neighborhood_has_visible_scenery_assets",
		visible_assets > 0 and visible_art_nodes > 0)
	check("spawn_coordinates_not_zero", car != null and car.global_position.length() > 1000)
	print("REAL GAME STARTUP: ", "PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
