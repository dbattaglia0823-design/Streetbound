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
	var hud: Node=get_tree().get_first_node_in_group("streetbound_world_map_hud")
	check("map_available",hud!=null)
	if hud==null:
		quit(1);return
	var mini: Control=hud.mini_view
	var atlas: Control=hud.full_view
	var image: TextureRect=hud.mini_image
	var offscreen: SubViewport=hud.mini_render
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
	await RenderingServer.frame_post_draw
	var image_pixels: Image=probe.get_texture().get_image()
	if image_pixels.is_empty():
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
	hud.large=false
	hud.set_minimap_shape("square")
	for i in 2:
		await process_frame
	await RenderingServer.frame_post_draw
	image_pixels=probe.get_texture().get_image()
	check("square_mode_restores_opaque_corners",
		not bool(hud.mini_mask.get_shader_parameter("circle_mode")) and
		(hud.mini.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a>.9 and
		not image_pixels.is_empty() and image_pixels.get_pixel(0,0).a>.9)
	check("atlas_shape_never_changes",
		not atlas.miniature and atlas.minimap_shape=="square")
	print("CIRCULAR MINIMAP MASK: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
