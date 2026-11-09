extends SceneTree
## Navigation invariants and cache bounds for the playable atlas/minimap.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(name: String, passed: bool) -> void:
	print("%s %s" % ["PASS" if passed else "FAIL",name])
	if not passed: failures.append(name)

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.vehicle.set_physics_process(false)
	await process_frame
	var hud: Node
	for child in main.get_children():
		if child.get_script()==load("res://scripts/world/world_map_hud.gd"): hud=child
	check("atlas_attached_to_playable_world",hud!=null)
	if hud==null:
		quit(1)
		return
	var atlas: Control = hud.full_view
	var mini: Control = hud.mini_view
	hud.large=true
	await process_frame
	atlas.focus_on(Vector2(2800,2800),atlas.fit_scale*8)
	var pointer := Vector2(620,300)
	var before: Vector2 = atlas.center_m+(pointer-atlas.custom_minimum_size*.5)/atlas.pixels_per_m
	atlas.zoom_at(1.3,pointer)
	var after: Vector2 = atlas.center_m+(pointer-atlas.custom_minimum_size*.5)/atlas.pixels_per_m
	check("zoom_preserves_place_under_pointer",before.distance_to(after)<.01)
	var prior: Vector2 = atlas.center_m
	var press := InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true
	atlas._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative=Vector2(30,-20)
	atlas._gui_input(motion)
	check("drag_pans_map_in_world_units",atlas.center_m.distance_to(prior-motion.relative/atlas.pixels_per_m)<.01)
	press.pressed=false
	atlas._gui_input(press)
	check("drag_releases",not atlas.dragging)
	atlas.zoom_at(1000,atlas.custom_minimum_size*.5)
	check("zoom_is_bounded",is_equal_approx(atlas.pixels_per_m,atlas.fit_scale*18))
	atlas.focus_on(Vector2(2800,2800),atlas.fit_scale*8)
	atlas._update_translation()
	var cached: Vector2 = atlas.ink.center
	atlas.center_m+=Vector2(10,0)/atlas.pixels_per_m
	atlas._update_translation()
	check("small_pan_reuses_static_geometry",atlas.ink.center==cached)
	atlas.center_m+=Vector2(90,0)/atlas.pixels_per_m
	atlas._update_translation()
	check("large_pan_refreshes_padded_detail",atlas.ink.center==atlas.center_m)
	atlas.follow_car=true
	atlas.focus_on(Vector2(1800,2200))
	check("destination_focus_leaves_car_tracking",not atlas.follow_car and atlas.center_m==Vector2(1800,2200))
	check("neighborhood_has_building_footprints",hud.model.props_in(Rect2(Vector2(2500,2500),Vector2(500,500))).size()>30)
	atlas.fit_region()
	check("fit_restores_whole_region",atlas.center_m==hud.model.extent*.5 and is_equal_approx(atlas.pixels_per_m,atlas.fit_scale))
	hud.large=false
	main.vehicle.position=Vector2(2800,2800)*20
	for i in 3: await process_frame
	check("minimap_tracks_car_at_local_scale",mini.center_m.distance_to(main.vehicle.position/20)<.01 and mini.pixels_per_m>atlas.fit_scale*3)
	check("minimap_cursor_stays_centered",mini.cursor.position.distance_to(mini.custom_minimum_size*.5)<.01)
	check("local_street_lookup",not hud.model.nearest_road(Vector2(2800,2800)).is_empty())
	print("MAP DETAIL TESTS: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
