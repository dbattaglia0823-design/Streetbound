extends SceneTree
## Regression: different artwork sizes/resolutions and normalized axle layouts
## use the same four wheel nodes, without changing physics or collisions.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, ok: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		failures.append(label)

func make_texture(canvas_size: Vector2i, opaque_area: Rect2i) -> ImageTexture:
	var image := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(opaque_area, Color.WHITE)
	return ImageTexture.create_from_image(image)

func run() -> void:
	var main: Node = load("res://scenes/proving_ground.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var car: VehicleController2D = main.vehicle
	car.set_physics_process(false)
	var rig: Node2D = car.get_node("Art/Wheels")
	var body: Sprite2D = car.get_node("Art/Sprite")
	var original_config: VehicleConfig = car.config
	var original_collision: Shape2D = car.get_node("CollisionShape2D").shape
	check("porsche_profile_attached", rig.appearance is VehicleAppearanceProfile and
		rig.appearance.body_texture == body.texture)
	check("porsche_default_four_wheels", rig.get_child_count() == 4)

	var category_profiles := [
		"res://resources/appearance/templates/compact_template.tres",
		"res://resources/appearance/templates/sedan_template.tres",
		"res://resources/appearance/templates/suv_template.tres",
		"res://resources/appearance/templates/pickup_template.tres"
	]
	for path in category_profiles:
		var profile: Resource = load(path)
		check("template_loads_" + path.get_file(), profile is VehicleAppearanceProfile)
		if profile is VehicleAppearanceProfile:
			check("template_has_separate_axles_" + path.get_file(),
				profile.front_left_uv.y < profile.rear_left_uv.y and
				profile.front_left_uv.x < profile.front_right_uv.x)

	var compact := VehicleAppearanceProfile.new()
	compact.body_texture = make_texture(Vector2i(128, 256),
		Rect2i(24, 28, 80, 192))
	compact.sprite_scale = Vector2(0.7, 0.7)
	compact.sprite_rotation_degrees = 180.0
	compact.front_left_uv = Vector2(0.11, 0.22)
	compact.front_right_uv = Vector2(0.89, 0.22)
	compact.rear_left_uv = Vector2(0.11, 0.77)
	compact.rear_right_uv = Vector2(0.89, 0.77)
	compact.tire_width_ratio = 0.18
	compact.tire_length_ratio = 0.22
	compact.minimum_tire_px = Vector2(4.0, 10.0)
	compact.maximum_tire_px = Vector2(26.0, 48.0)
	rig.apply_appearance(compact)
	var compact_bounds: Rect2 = rig.visible_bounds
	var fl: Node2D = rig.get_node("FrontLeft")
	var fr: Node2D = rig.get_node("FrontRight")
	var rl: Node2D = rig.get_node("RearLeft")
	var rr: Node2D = rig.get_node("RearRight")
	var compact_width: float = rig.tire_size.x
	check("trimmed_alpha_bounds",
		compact_bounds.size.x < 65.0 and compact_bounds.size.x > 49.0 and
		compact_bounds.size.y > 120.0 and compact_bounds.size.y < 143.0, compact_bounds)
	check("normalized_front_axle_exact",
		fl.position.distance_to(compact_bounds.position +
			compact_bounds.size * compact.front_left_uv) < 0.01, fl.position)
	check("normalized_rear_axle_exact",
		rr.position.distance_to(compact_bounds.position +
			compact_bounds.size * compact.rear_right_uv) < 0.01, rr.position)
	check("four_wheels_reused_on_swap", rig.get_child_count() == 4)
	check("small_car_tires_scale_with_silhouette", compact_width > 8.0 and compact_width < 12.0, compact_width)

	var suv: VehicleAppearanceProfile = compact.duplicate(true) as VehicleAppearanceProfile
	suv.body_texture = make_texture(Vector2i(256, 384),
		Rect2i(45, 40, 160, 280))
	suv.sprite_scale = Vector2(0.8, 0.62)
	suv.front_left_uv = Vector2(0.05, 0.25)
	suv.front_right_uv = Vector2(0.95, 0.25)
	suv.rear_left_uv = Vector2(0.06, 0.79)
	suv.rear_right_uv = Vector2(0.94, 0.79)
	suv.tire_width_ratio = 0.23
	suv.tire_length_ratio = 0.20
	rig.apply_appearance(suv)
	var suv_bounds: Rect2 = rig.visible_bounds
	check("larger_model_has_larger_visual_width",
		suv_bounds.size.x > compact_bounds.size.x, [compact_bounds.size, suv_bounds.size])
	check("tire_size_recalculated_per_model", rig.tire_size.x > compact_width * 1.5,
		[compact_width, rig.tire_size.x])
	check("asymmetric_front_rear_anchors_supported",
		not is_equal_approx(fl.position.x, rl.position.x) and
		not is_equal_approx(fr.position.x, rr.position.x),
		[fl.position, rl.position])
	check("updated_front_anchor_exact", fl.position.distance_to(
		suv_bounds.position + suv_bounds.size * suv.front_left_uv) < 0.01,
		fl.position)
	check("no_duplicate_wheels_after_runtime_swap", rig.get_child_count() == 4)
	check("car_appearance_does_not_change_physics",
		car.config == original_config and car.get_node("CollisionShape2D").shape == original_collision)

	car.steering = deg_to_rad(15)
	for i in 15:
		rig._process(1.0 / 60.0)
	check("steering_animates_after_model_swap",
		fl.rotation > deg_to_rad(9) and is_equal_approx(fl.rotation, fr.rotation),
		rad_to_deg(fl.rotation))
	check("rear_wheels_still_straight", is_zero_approx(rl.rotation) and is_zero_approx(rr.rotation))
	car.reset_vehicle()
	for i in 30:
		rig._process(1.0 / 60.0)
	check("reset_centers_new_car_wheels",
		absf(fl.rotation) < deg_to_rad(0.05) and absf(fr.rotation) < deg_to_rad(0.05))

	print("MULTI-MODEL WHEEL TESTS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
