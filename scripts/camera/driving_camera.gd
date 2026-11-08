extends Camera2D
@export var target: VehicleController2D
var follow_heading := false

func _ready() -> void:
	ignore_rotation = false
	position_smoothing_enabled = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	global_position = target.global_position

func _physics_process(dt: float) -> void:
	if Input.is_action_just_pressed("camera"):
		follow_heading = not follow_heading
	var interpolated: Transform2D = target.global_transform
	var lookahead := target.linear_velocity * 3.8
	var desired := interpolated.origin + lookahead.limit_length(230.0)
	global_position = global_position.lerp(desired, 1.0 - exp(-5.0 * dt))
	var target_angle := interpolated.get_rotation() if follow_heading else 0.0
	rotation = lerp_angle(rotation, target_angle, 1.0 - exp(-4.0 * dt))
	var target_zoom := lerpf(1.05, 0.62, clampf(target.linear_velocity.length() / 65.0, 0, 1))
	zoom = zoom.lerp(Vector2.ONE * target_zoom, 1.0 - exp(-2.5 * dt))
	if global_position.distance_to(interpolated.origin) > 1600:
		global_position = interpolated.origin
