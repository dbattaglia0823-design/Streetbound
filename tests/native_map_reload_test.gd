extends SceneTree
## Explicit Apply -> Reload World path must create a fresh live scene and
## restore developer editor focus rather than showing stale intersections.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, okay: bool) -> void:
	print("%s %s" % ["PASS" if okay else "FAIL",label])
	if not okay:
		failures.append(label)

func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var game: Node = scene.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	var editor: Variant = game.native_world_editor
	if editor==null:
		editor = load("res://scripts/dev/native_world_editor.gd").new()
		editor.world = game.ground
		editor.player = game.vehicle
		editor.driving_camera = get_first_node_in_group("player_camera")
		editor.traffic_network = game.ground.get_node("AmbientTraffic").get("network")
		game.add_child(editor)
		await process_frame
	check("native_editor_enters_before_reload",editor.open_editor())
	var original: Node = game
	var focus: Vector2 = game.vehicle.global_position + Vector2(220,-160)
	editor.editor_camera.global_position = focus
	# Simulate a successful Apply without editing repository map files.
	editor.source_revision = "0000000000000000000000000000000000000000000000000000000000000000"
	editor._reload_world()
	for _i in 8:
		await process_frame
	var fresh: Node = current_scene
	check("reload_replaces_the_entire_running_world",is_instance_valid(fresh) and
		fresh != original and fresh.ground.initialization_complete)
	var fresh_editor: Variant = fresh.native_world_editor if is_instance_valid(fresh) else null
	check("native_editor_reopens_after_full_real_world_reload",
		fresh_editor != null and fresh_editor.active and paused)
	if fresh_editor!=null and fresh_editor.active:
		check("reload_restores_previous_map_camera_location",
			fresh_editor.editor_camera.global_position.distance_to(focus)<0.01)
		check("reload_editor_uses_fresh_traffic_network",
			fresh_editor.traffic_network == fresh.ground.get_node("AmbientTraffic").get("network") and
			not fresh_editor.traffic_network.edges.is_empty())
		fresh_editor.close_editor()
	check("reload_can_return_to_ordinary_free_roam",
		not paused and fresh.vehicle != null and not fresh.vehicle.external_input)
	paused = false
	print("NATIVE MAP WORLD RELOAD: ",
		"PASS" if failures.is_empty() else "FAIL "+str(failures))
	quit(0 if failures.is_empty() else 1)
