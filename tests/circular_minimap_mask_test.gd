extends SceneTree
## Circular mode must cut out the whole live map, not just add an outline
## above a square viewport. Test both saved-setting display modes.
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("_run")

func check(label: String, success: bool, detail: Variant="") -> void:
	print("%s %s: %s" % ["PASS" if success else "FAIL",label,detail])
	if not success:
		failures.append(label)

func _run() -> void:
	var scene: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var hud: Node=get_first_node_in_group("streetbound_world_map_hud")
	check("map_available",hud!=null)
	if hud==null:
		quit(1);return
	var mini: Control=hud.mini_view
	var atlas: Control=hud.full_view
	var image: TextureRect=hud.mini_image
	var offscreen: SubViewport=hud.mini_render
	var enemy_layer: Node2D=mini.get_node_or_null("MinimapEnemies")
	check("enemy_dots_are_in_the_live_masked_minimap",
		enemy_layer!=null and enemy_layer.z_index>mini.race_overlay.z_index and
		enemy_layer.z_index<mini.cursor.z_index and
		atlas.get_node_or_null("MinimapEnemies")==null)
	if enemy_layer!=null:
		var EnemyMarkers=load("res://scripts/world/map_enemy_overlay.gd")
		check("enemy_dots_are_small_red_circles",
			enemy_layer.get_script()==EnemyMarkers and
			is_equal_approx(EnemyMarkers.DOT_RADIUS,3.0) and
			EnemyMarkers.DOT_COLOR.r>0.8 and
			EnemyMarkers.DOT_COLOR.g<0.4)
		check("no_enemy_dots_outside_races_or_roaming_encounters",
			(enemy_layer.call("visible_enemy_positions") as PackedVector2Array).is_empty())
		# Roaming enemies use one group, without requiring a race or map changes.
		var roaming:=Node2D.new()
		roaming.name="RoamingEnemyMapFixture"
		roaming.add_to_group("minimap_enemy")
		scene.add_child(roaming)
		roaming.global_position=scene.vehicle.global_position+Vector2(200,0)
		hud._process(0.0)
		mini._process(0.0)
		var roaming_dots: PackedVector2Array=enemy_layer.call("visible_enemy_positions")
		check("future_roaming_enemy_group_appears_without_a_race",
			roaming_dots.size()==1)
		if roaming_dots.size()==1:
			var predicted: Vector2=EnemyMarkers.map_position(roaming.global_position,
				mini.center_m,mini.pixels_per_m,mini.custom_minimum_size)
			check("roaming_enemy_dot_uses_live_map_coordinates",
				roaming_dots[0].distance_to(predicted)<0.01)
		roaming.global_position+=Vector2(320,0)
		var moved_dots: PackedVector2Array=enemy_layer.call("visible_enemy_positions")
		check("enemy_dot_tracks_moving_vehicles",
			moved_dots.size()==1 and moved_dots[0].distance_to(roaming_dots[0])>1.0)
		# Race rivals must only appear during their own countdown/race, not
		# while a previous race is idle or showing results.
		var race: Node2D=scene.drag_race
		var rival:=Node2D.new()
		rival.name="RaceEnemyMapFixture"
		rival.add_to_group("race_opponent")
		race.add_child(rival)
		rival.global_position=scene.vehicle.global_position+Vector2(0,200)
		check("idle_race_does_not_show_opponent_dot",
			(enemy_layer.call("visible_enemy_positions") as PackedVector2Array).size()==1)
		var original_state: String=str(race.get("state"))
		race.set("state","countdown")
		check("race_countdown_shows_red_opponent_dot",
			(enemy_layer.call("visible_enemy_positions") as PackedVector2Array).size()==2)
		race.set("state","running")
		check("active_race_keeps_opponent_dot",
			(enemy_layer.call("visible_enemy_positions") as PackedVector2Array).size()==2)
		race.set("state","results")
		check("finished_race_removes_opponent_dot",
			(enemy_layer.call("visible_enemy_positions") as PackedVector2Array).size()==1)
		race.set("state",original_state)
		rival.queue_free()
		roaming.global_position=scene.vehicle.global_position+Vector2(9000,0)
		check("enemy_dots_outside_map_are_hidden",
			(enemy_layer.call("visible_enemy_positions") as PackedVector2Array).is_empty())
		check("circular_enemy_dots_do_not_leak_into_corners",
			not EnemyMarkers.within_map(Vector2(10,10),Vector2(244,244),"circle") and
			EnemyMarkers.within_map(Vector2(122,122),Vector2(244,244),"circle"))
		roaming.queue_free()
	check("live_map_composited_into_correct_square_source",
		mini.get_viewport()==offscreen and offscreen.size==Vector2i(244,244) and
		image.texture==offscreen.get_texture() and
		mini.ink.mirror_enabled and mini.ink.mirror.available)
	check("native_map_layering_unchanged",
		mini.ink.mirror.z_index < mini.ink.z_index and
		mini.ink.z_index < mini.cursor.z_index and
		atlas.get_viewport()!=offscreen and not atlas.miniature)
	check("square_is_default_and_opaque",
		hud.minimap_shape=="square" and
		not bool(hud.mini_mask.get_shader_parameter("circle_mode")) and
		(hud.mini.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a>.9)
	hud.set_minimap_shape("circle")
	check("circle_setting_masks_finished_texture",
		mini.minimap_shape=="circle" and
		bool(hud.mini_mask.get_shader_parameter("circle_mode")) and
		mini.clip_children==CanvasItem.CLIP_CHILDREN_DISABLED and
		(hud.mini.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a<.01)
	check("compass_scale_shift_inside_round_map",
		bool(mini.scale_bar.get("circular")))
	# Verify the final shader alpha through an independent transparent
	# renderer: neither native chunk z-index nor POI overlays can escape it.
	var probe:=SubViewport.new()
	probe.size=Vector2i(244,244)
	probe.disable_3d=true
	probe.transparent_bg=true
	probe.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(probe)
	var surface:=TextureRect.new()
	surface.size=Vector2(244,244)
	surface.texture=offscreen.get_texture()
	surface.material=hud.mini_mask
	surface.stretch_mode=TextureRect.STRETCH_SCALE
	probe.add_child(surface)
	for i in 4:
		await process_frame
	# Fixed headless frames advance the SubViewport without relying on a
	# display-server post-draw signal (not emitted by all CI renderers).
	var image_pixels: Image=probe.get_texture().get_image()
	if image_pixels==null or image_pixels.is_empty():
		check("round_map_render_available",false)
	else:
		check("circle_actual_corners_are_alpha_clipped",
			image_pixels.get_pixel(0,0).a<.04 and
			image_pixels.get_pixel(243,0).a<.04 and
			image_pixels.get_pixel(0,243).a<.04 and
			image_pixels.get_pixel(243,243).a<.04)
		check("circle_keeps_true_map_center",
			image_pixels.get_pixel(122,122).a>.9)
	var pressed:=InputEventMouseButton.new()
	pressed.button_index=MOUSE_BUTTON_LEFT
	pressed.pressed=true
	pressed.position=Vector2(0,0)
	hud.large=false
	hud._minimap_clicked(pressed)
	check("transparent_corner_does_not_open_atlas",not hud.large)
	pressed.position=Vector2(122,122)
	hud._minimap_clicked(pressed)
	check("clicking_circle_still_opens_atlas",hud.large)
	hud._process(0.0)
	check("minimap_does_not_render_under_full_atlas",
		offscreen.render_target_update_mode==SubViewport.UPDATE_DISABLED)
	hud.large=false
	hud._process(0.0)
	check("minimap_gpu_updates_restored_after_atlas",
		offscreen.render_target_update_mode==SubViewport.UPDATE_ALWAYS)
	hud.set_minimap_shape("square")
	for i in 2:
		await process_frame
	# Fixed headless frames advance the SubViewport without relying on a
	# display-server post-draw signal (not emitted by all CI renderers).
	image_pixels=probe.get_texture().get_image()
	var opaque_square: bool=image_pixels!=null and not image_pixels.is_empty()
	if opaque_square:
		opaque_square=image_pixels.get_pixel(0,0).a>.9
	check("square_mode_restores_opaque_corners",
		not bool(hud.mini_mask.get_shader_parameter("circle_mode")) and
		(hud.mini.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a>.9 and
		opaque_square)
	check("atlas_shape_never_changes",
		not atlas.miniature and atlas.minimap_shape=="square")
	print("CIRCULAR MINIMAP MASK: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
