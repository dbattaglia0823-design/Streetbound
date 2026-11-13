extends SceneTree
## Curb geometry remains available to driving physics, but top-down artwork
## stays aligned: no separate per-wheel spring, body hover, or visual lift.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(label: String, passed: bool, detail: Variant = "") -> void:
	print("%s %s: %s" % ["PASS" if passed else "FAIL", label, detail])
	if not passed:
		failures.append(label)


func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await physics_frame
	var car: VehicleController2D = main.vehicle
	car.set_physics_process(false)
	var art: Node2D = car.get_node("Art")
	var rig: Node2D = art.get_node("Wheels")
	var sprite: Sprite2D = art.get_node("Sprite")
	var collider: CollisionShape2D = car.get_node("CollisionShape2D")
	var rest_position := sprite.position
	var rest_rotation := sprite.rotation
	var shape := collider.shape
	var car_transform := car.global_transform
	var collider_transform := collider.global_transform
	check("all_four_wheels_present", rig.get_child_count() == 4)
	check("rear_track_narrower_than_front",
		rig.rear_track_inset < 1.0 and rig.rear_track_inset >= 0.8,
		rig.rear_track_inset)
	# Even legacy callers that attempt to lift the individual tires must not
	# move wheel art independently of its calibrated axle positions.
	rig.set_curb_heights(PackedFloat32Array([1.0, 0.0, 0.7, 0.0]))
	var stationary := true
	for i in 4:
		var wheel: Node2D = rig.get_child(i) as Node2D
		stationary = stationary and wheel.position.is_equal_approx(
			rig.wheel_anchor(i)) and wheel.scale.is_equal_approx(Vector2.ONE)
	check("curb_effect_cannot_lift_any_wheel", stationary)
	for i in 60:
		art._process(1.0 / 60.0)
	check("independent_body_suspension_removed",
		sprite.position.is_equal_approx(rest_position) and
		is_equal_approx(sprite.rotation, rest_rotation),
		[sprite.position, sprite.rotation])
	check("visual_feedback_does_not_move_physical_vehicle",
		car.global_transform.is_equal_approx(car_transform) and
		collider.global_transform.is_equal_approx(collider_transform) and
		collider.shape == shape)
	check("wheel_contact_anchors_remain_stable",
		rig.wheel_anchor(0).is_equal_approx(rig.get_node("FrontLeft").position) and
		rig.wheel_anchor(3).is_equal_approx(rig.get_node("RearRight").position))
	print("STABLE TIRE VISUALS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
