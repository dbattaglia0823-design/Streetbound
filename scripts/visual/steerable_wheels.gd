extends Node2D
## Reusable four-wheel rig for different car silhouettes and display scales.
## Wheels are drawn below the car body and inherit its suspension sway.
const WheelVisual = preload("res://scripts/visual/wheel_visual.gd")
# Explicit class dependency prevents missing global class registration on
# Godot 4.6.x cold starts (and preserves resource inspector type safety).
const AppearanceProfile = preload("res://scripts/vehicle/vehicle_appearance_profile.gd")

@export var appearance: AppearanceProfile
@export var auto_fit_to_body := true
# Legacy/manual defaults when a car does not yet have an appearance resource.
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
var visible_bounds := Rect2()
var _center := Vector2.ZERO
var _fitted := false
var _anchors: Array[Vector2] = []
var _base_points: Array[Vector2] = []
var curb_heights := PackedFloat32Array([0.0,0.0,0.0,0.0])


func _ready() -> void:
	vehicle = get_parent().get_parent() as VehicleController2D
	z_index = -1
	apply_appearance(appearance)


func apply_appearance(profile: AppearanceProfile) -> void:
	# Safe to call when selecting a different vehicle art asset at runtime.
	# It only changes render properties; handling, grip and collision are intact.
	appearance = profile
	var body: Sprite2D = get_parent().get_node_or_null("Sprite") as Sprite2D
	if profile != null and body != null and profile.body_texture != null:
		body.texture = profile.body_texture
		body.scale = profile.sprite_scale
		body.rotation = deg_to_rad(profile.sprite_rotation_degrees)
		body.position = profile.sprite_offset

	_fitted = false
	_anchors.clear()
	if body != null and body.texture != null:
		visible_bounds = _visible_bounds(body)
		if profile != null and visible_bounds.has_area():
			_apply_profile_layout(visible_bounds, profile)
			_fitted = true
		elif auto_fit_to_body and visible_bounds.has_area():
			_fitted = _fit_to_bounds(visible_bounds)
	if not _fitted:
		visible_bounds = Rect2()
	_sync_wheels()


func _apply_profile_layout(bounds: Rect2, profile: AppearanceProfile) -> void:
	var width := bounds.size.x
	var length := bounds.size.y
	var min_width := minf(profile.minimum_tire_px.x, profile.maximum_tire_px.x)
	var max_width := maxf(profile.minimum_tire_px.x, profile.maximum_tire_px.x)
	var min_length := minf(profile.minimum_tire_px.y, profile.maximum_tire_px.y)
	var max_length := maxf(profile.minimum_tire_px.y, profile.maximum_tire_px.y)
	tire_size = Vector2(clampf(width * profile.tire_width_ratio, min_width, max_width),
		clampf(length * profile.tire_length_ratio, min_length, max_length))
	_anchors.assign([
		_anchor(bounds, profile.front_left_uv),
		_anchor(bounds, profile.front_right_uv),
		_anchor(bounds, profile.rear_left_uv),
		_anchor(bounds, profile.rear_right_uv)
	])
	visual_steer_multiplier = profile.steer_multiplier
	max_visual_steer_degrees = profile.max_visual_steer_degrees
	steer_animation_speed = profile.steer_animation_speed


func _anchor(bounds: Rect2, uv: Vector2) -> Vector2:
	return bounds.position + bounds.size * uv


func _fit_to_bounds(bounds: Rect2) -> bool:
	var extent := bounds.size
	# Kept for older car scenes which do not yet provide a profile.
	if extent.x < 23.0 or extent.x > 110.0 or extent.y < 45.0 or extent.y > 150.0:
		return false
	_center = bounds.get_center()
	tire_size = Vector2(clampf(extent.x * 0.21, 8.0, 15.0),
		clampf(extent.y * 0.235, 16.0, 26.0))
	half_track_width = extent.x * 0.5 - tire_size.x * 0.19
	front_axle_distance = extent.y * 0.245
	rear_axle_distance = extent.y * 0.255
	return true


func _visible_bounds(body: Sprite2D) -> Rect2:
	# One-time/read-on-switch alpha scan. Trim transparent padding and respect
	# actual sprite transform, so 512px and 2048px artwork can use the same UVs.
	var image: Image = body.texture.get_image()
	if image == null or image.is_empty():
		return Rect2()
	var dimensions := image.get_size()
	var stride := maxi(2, ceili(float(maxi(dimensions.x, dimensions.y)) / 270.0))
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for y in range(0, dimensions.y, stride):
		for x in range(0, dimensions.x, stride):
			if image.get_pixel(x, y).a < 0.20:
				continue
			var px := float(dimensions.x - 1 - x) if body.flip_h else float(x)
			var py := float(dimensions.y - 1 - y) if body.flip_v else float(y)
			var source_point := Vector2(px, py)
			if body.centered:
				source_point -= Vector2(dimensions) * 0.5
			source_point += body.offset
			var local := Vector2(source_point.x * body.scale.x,
				source_point.y * body.scale.y).rotated(body.rotation) + body.position
			minimum = minimum.min(local)
			maximum = maximum.max(local)
	if not is_finite(minimum.x):
		return Rect2()
	return Rect2(minimum, maximum - minimum)


func _sync_wheels() -> void:
	var points: Array[Vector2] = _anchors
	if points.size() != 4:
		points = [
			Vector2(_center.x - half_track_width, _center.y - front_axle_distance),
			Vector2(_center.x + half_track_width, _center.y - front_axle_distance),
			Vector2(_center.x - half_track_width, _center.y + rear_axle_distance),
			Vector2(_center.x + half_track_width, _center.y + rear_axle_distance)
		]
	if not is_instance_valid(front_left):
		front_left = _make_wheel("FrontLeft", -1)
		front_right = _make_wheel("FrontRight", 1)
		rear_left = _make_wheel("RearLeft", -1)
		rear_right = _make_wheel("RearRight", 1)
	_base_points = points.duplicate()
	var wheels: Array[Node2D] = [front_left, front_right, rear_left, rear_right]
	for i in 4:
		wheels[i].position = points[i]
		wheels[i].set("tire_size", tire_size)
		wheels[i].rotation = 0.0
		wheels[i].queue_redraw()


## Stable tyre ground-contact anchors, before the purely visual curb rise.
## Skid marks must follow these, not the animating sprite offset.
func wheel_anchor(index: int) -> Vector2:
	if index < 0 or index >= _base_points.size():
		return Vector2.ZERO
	return _base_points[index]


func set_curb_heights(heights: PackedFloat32Array) -> void:
	if heights.size() != 4 or _base_points.size() != 4:
		return
	curb_heights = heights
	var wheels: Array[Node2D] = [front_left,front_right,rear_left,rear_right]
	for i in 4:
		var height := clampf(float(heights[i]),0.0,1.0)
		wheels[i].position = _base_points[i] + Vector2(-2.0,-6.0)*height
		wheels[i].scale = Vector2.ONE*(1.0+height*0.025)


func _make_wheel(wheel_name: String, wheel_side: int) -> Node2D:
	var wheel := Node2D.new()
	wheel.name = wheel_name
	wheel.set_script(WheelVisual)
	wheel.set("side", wheel_side)
	add_child(wheel)
	return wheel


func _process(delta: float) -> void:
	if not is_instance_valid(vehicle) or not is_instance_valid(front_left):
		return
	var dt := minf(delta, 0.05)
	if dt <= 0.0:
		return
	# The physical steering angle already includes speed limits, reversing,
	# self-centering and slip. Visual gain only makes it visible at game zoom.
	var target_angle := clampf(vehicle.steering * visual_steer_multiplier,
		-deg_to_rad(max_visual_steer_degrees), deg_to_rad(max_visual_steer_degrees))
	var ease := 1.0 - exp(-steer_animation_speed * dt)
	front_left.rotation = lerp_angle(front_left.rotation, target_angle, ease)
	front_right.rotation = lerp_angle(front_right.rotation, target_angle, ease)
	rear_left.rotation = 0.0
	rear_right.rotation = 0.0
