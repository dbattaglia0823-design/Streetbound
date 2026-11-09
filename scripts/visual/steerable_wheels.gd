extends Node2D
## Four independent wheel pivots, drawn behind the existing top-down car art.
## The physical wheel angles and tire grip still belong to VehicleController2D.
const WheelVisual = preload("res://scripts/visual/wheel_visual.gd")

@export var auto_fit_to_body := true
@export_range(8.0, 42.0, 0.5) var front_axle_distance := 27.0
@export_range(8.0, 42.0, 0.5) var rear_axle_distance := 27.0
@export_range(10.0, 45.0, 0.5) var half_track_width := 21.0
@export var tire_size := Vector2(10.0, 21.0)
@export_range(0.5, 2.0, 0.05) var visual_steer_multiplier := 1.35
@export_range(10.0, 45.0, 1.0) var max_visual_steer_degrees := 38.0
@export_range(5.0, 40.0, 1.0) var steer_animation_speed := 20.0

var vehicle: VehicleController2D
var front_left: Node2D
var front_right: Node2D
var rear_left: Node2D
var rear_right: Node2D
var _center := Vector2.ZERO
var _fitted := false

func _ready() -> void:
	vehicle = get_parent().get_parent() as VehicleController2D
	z_index = -1
	var body: Sprite2D = get_parent().get_node_or_null("Sprite") as Sprite2D
	if auto_fit_to_body and body != null:
		_fitted = _fit_to_sprite(body)
	front_left = _make_wheel("FrontLeft", Vector2(_center.x - half_track_width, _center.y - front_axle_distance), -1)
	front_right = _make_wheel("FrontRight", Vector2(_center.x + half_track_width, _center.y - front_axle_distance), 1)
	rear_left = _make_wheel("RearLeft", Vector2(_center.x - half_track_width, _center.y + rear_axle_distance), -1)
	rear_right = _make_wheel("RearRight", Vector2(_center.x + half_track_width, _center.y + rear_axle_distance), 1)


func _make_wheel(wheel_name: String, axle: Vector2, wheel_side: int) -> Node2D:
	var wheel := Node2D.new()
	wheel.name = wheel_name
	wheel.set_script(WheelVisual)
	wheel.set("tire_size", tire_size)
	wheel.set("side", wheel_side)
	wheel.position = axle
	add_child(wheel)
	return wheel


func _fit_to_sprite(body: Sprite2D) -> bool:
	if body.texture == null:
		return false
	# This scan is a one-time setup cost. Transparencies are important: most
	# imported vehicle PNGs have wide unused margins around the actual body.
	var image: Image = body.texture.get_image()
	if image == null or image.is_empty():
		return false
	var dimensions := image.get_size()
	var stride := maxi(2, maxi(dimensions.x, dimensions.y) / 270)
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for y in range(0, dimensions.y, stride):
		for x in range(0, dimensions.x, stride):
			if image.get_pixel(x, y).a < 0.20:
				continue
			var image_point := Vector2(float(x) - float(dimensions.x) * 0.5,
				float(y) - float(dimensions.y) * 0.5)
			var local := Vector2(image_point.x * body.scale.x,
				image_point.y * body.scale.y).rotated(body.rotation) + body.position
			minimum = minimum.min(local)
			maximum = maximum.max(local)
	if not is_finite(minimum.x):
		return false

	var extent := maximum - minimum
	# Reject fully opaque source canvases or wildly mismatched sprites; the
	# editor-exposed manual anchors remain a safe fallback.
	if extent.x < 23.0 or extent.x > 110.0 or extent.y < 45.0 or extent.y > 150.0:
		return false
	_center = (minimum + maximum) * 0.5
	tire_size = Vector2(clampf(extent.x * 0.21, 8.0, 15.0),
		clampf(extent.y * 0.235, 16.0, 26.0))
	# Slight overlap is deliberate: the body occludes the inside of each tire.
	half_track_width = extent.x * 0.5 - tire_size.x * 0.19
	front_axle_distance = extent.y * 0.245
	rear_axle_distance = extent.y * 0.255
	return true


func _process(delta: float) -> void:
	if not is_instance_valid(vehicle):
		return
	var dt := minf(delta, 0.05)
	if dt <= 0.0:
		return
	# The physical steering angle already handles self-centering, reversing,
	# grip and speed. A restrained amplification simply helps tiny tire edges
	# remain visible once the body hides most of the wheel.
	var target_angle := clampf(vehicle.steering * visual_steer_multiplier,
		-deg_to_rad(max_visual_steer_degrees), deg_to_rad(max_visual_steer_degrees))
	var ease := 1.0 - exp(-steer_animation_speed * dt)
	front_left.rotation = lerp_angle(front_left.rotation, target_angle, ease)
	front_right.rotation = lerp_angle(front_right.rotation, target_angle, ease)
	# The rear wheels are intentionally fixed (no four-wheel-steering illusion).
	rear_left.rotation = 0.0
	rear_right.rotation = 0.0
