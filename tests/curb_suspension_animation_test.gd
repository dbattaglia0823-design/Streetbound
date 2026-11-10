extends SceneTree
## Verify 4-corner visual suspension against actual urban sidewalk metadata.
## No collision shape / physics transform is ever moved for curb animation.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL",label,detail])
	if not passed:
		failures.append(label)


func vec(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))


func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var world: MorrowCoast = main.ground
	var car: VehicleController2D = main.vehicle
	car.set_physics_process(false)
	var art: Node2D = car.get_node("Art")
	var rig: Node2D = car.get_node("Art/Wheels")
	var shadow: Node2D = car.get_node_or_null("GroundShadow")
	var collider: CollisionShape2D = car.get_node("CollisionShape2D")
	var original_shape := collider.shape
	check("road_anchored_contact_shadow_exists",
		shadow != null and shadow.z_index < art.z_index)
	check("all_four_contacts_have_baseline_anchors",
		rig.get_child_count() == 4 and \
		rig.wheel_anchor(0).x < rig.wheel_anchor(1).x and \
		rig.wheel_anchor(0).y < rig.wheel_anchor(2).y)
	var urban_found := false
	var chosen_center := Vector2.ZERO
	var chosen_normal := Vector2.ZERO
	var chosen_tangent := Vector2.ZERO
	var urban_width := 0.0
	for segment in world.data.segments:
		var road: Dictionary = world.data.roads[int(segment.road)]
		if str(road.kind) not in ["local","arterial"]:
			continue
		var a := vec(segment.a)
		var b := vec(segment.b)
		if a.distance_to(b) < 3.0:
			continue
		var tangent := (b-a).normalized()
		var normal := tangent.orthogonal()
		var center := (a+b)*0.5
		var half_width := float(road.width)*0.5
		var road_sample := (center+normal*(half_width-1.0))*20.0
		var curb_sample := (center+normal*(half_width+1.2))*20.0
		var grass_sample := (center+normal*(half_width+5.5))*20.0
		if world.curb_height_at(road_sample) > 0.001 or \
			world.curb_height_at(curb_sample) < 0.7 or \
			world.curb_height_at(grass_sample) > 0.001:
			continue
		urban_found = true
		chosen_center = center
		chosen_normal = normal
		chosen_tangent = tangent
		urban_width = half_width
		break
	check("road_to_sidewalk_to_terrain_has_a_real_curb_transition",
		urban_found)
	if urban_found:
		var inside := (chosen_center+chosen_normal*(urban_width-1.0))*20.0
		var sidewalk := (chosen_center+chosen_normal*(urban_width+1.2))*20.0
		var exterior := (chosen_center+chosen_normal*(urban_width+5.5))*20.0
		check("asphalt_lane_has_zero_curb_lift",world.curb_height_at(inside) < 0.01)
		check("sidewalk_raises_wheel",world.curb_height_at(sidewalk) > 0.7)
		check("off_sidewalk_returns_to_ground",world.curb_height_at(exterior) < 0.01)
		# Face parallel to road: right tyres cross curb, left tyres remain on
		# road; used actual wheel anchors and drivable map coordinates.
		car.global_position = (chosen_center+chosen_normal*urban_width)*20.0
		car.rotation = chosen_tangent.angle()+PI/2.0
		car.linear_velocity = Vector2.ZERO
		car.velocity = Vector2.ZERO
		car.reset_physics_interpolation()
		var targets: PackedFloat32Array = art._wheel_targets()
		var left := (float(targets[0])+float(targets[2]))*0.5
		var right := (float(targets[1])+float(targets[3]))*0.5
		check("correct_lateral_pair_detects_raised_side",
			right > left + 0.35,[targets,left,right])
		for i in 75:
			art._process(1.0/60.0)
		check("curb_roll_responds_to_individual_wheel_height",
			absf(float(art.curb_roll)) > 0.25,[art.curb_roll,art.curb_heave])
		var raised_wheel: Node2D = rig.get_node("RearRight")
		check("raised_tyre_visually_lifts_from_own_anchor",
			raised_wheel.position.y < rig.wheel_anchor(3).y - 1.0)
		var before_transform := car.global_transform
		var before_collision := collider.global_transform
		for i in 20:
			art._process(1.0/60.0)
		check("suspension_cannot_move_actual_car_or_collision",
			car.global_transform.is_equal_approx(before_transform) and \
			collider.global_transform.is_equal_approx(before_collision) and \
			collider.shape == original_shape)
		# Drive away from sidewalk and allow the spring to settle.
		car.global_position = (chosen_center+chosen_normal*(urban_width-3.5))*20.0
		for i in 150:
			art._process(1.0/60.0)
		check("exiting_curb_restores_four_wheel_contact",
			float(art.curb_heave) < 0.025 and \
			absf(float(art.curb_roll)) < 0.035,art.curb_heave)
	# Deterministic component isolation: front-left tyre bumps before
	# the others, causing positive front pitch and left roll.
	art._step_suspension(1.0/60.0,PackedFloat32Array([1.0,0.0,0.0,0.0]),true)
	check("single_front_left_contact_raises_correct_quarter",
		float(art.curb_pitch) > 0.4 and float(art.curb_roll) > 0.4 and \
		float(art.curb_heave) > 0.2)
	check("other_wheels_do_not_lift_before_contact",
		rig.get_node("FrontRight").position.is_equal_approx(rig.wheel_anchor(1))
		and rig.get_node("RearLeft").position.is_equal_approx(rig.wheel_anchor(2)))
	art._step_suspension(1.0/60.0,PackedFloat32Array([0.0,0.0,0.0,0.0]),true)
	check("suspension_resets_to_level",
		float(art.curb_heave) < 0.01 and \
		is_zero_approx(float(art.curb_pitch)) and \
		is_zero_approx(float(art.curb_roll)))
	# Keep wheel contact anchors independent of visual lift for skid trails.
	check("ground_contact_anchors_remain_constant_after_animation",
		rig.wheel_anchor(0).is_equal_approx(rig.get_node("FrontLeft").position) and \
		rig.wheel_anchor(3).is_equal_approx(rig.get_node("RearRight").position))
	print("CURB SUSPENSION ANIMATIONS: ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
