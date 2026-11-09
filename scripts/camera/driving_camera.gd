extends Camera2D
## Telemetry-driven visual framing. No changes to vehicle handling.
@export var target: VehicleController2D
var follow_heading := false
var impact_strength := 0.0
var _impact_time := 0.0
var _surge := 0.0
var _previous_longitudinal := 0.0

func _ready() -> void:
	ignore_rotation = false
	position_smoothing_enabled = false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	global_position = target.global_position
	_previous_longitudinal = target.longitudinal_speed
	target.impacted.connect(_on_impact)

func _on_impact(strength: float) -> void:
	impact_strength = maxf(impact_strength, clampf((strength - 2.0) / 18.0, 0.0, 1.0))
	_impact_time = 0.0

func _physics_process(dt: float) -> void:
	if Input.is_action_just_pressed("camera"):
		follow_heading = not follow_heading
	var transform_now: Transform2D = target.global_transform
	var speed := target.linear_velocity.length()
	var forward_speed := maxf(target.longitudinal_speed, 0.0)
	var acceleration := (forward_speed - maxf(_previous_longitudinal, 0.0)) / maxf(dt, 0.001)
	_previous_longitudinal = target.longitudinal_speed
	_surge = lerpf(_surge, clampf(acceleration / 14.0, 0.0, 1.0), 1.0 - exp(-3.8 * dt))
	var lead := target.linear_velocity * 3.8
	var desired := transform_now.origin + lead.limit_length(230.0)
	global_position = global_position.lerp(desired, 1.0 - exp(-5.0 * dt))
	var desired_rotation := transform_now.get_rotation() if follow_heading else 0.0
	rotation = lerp_angle(rotation, desired_rotation, 1.0 - exp(-4.0 * dt))
	# Widen the view for road reading, with a subtle surge during acceleration.
	var speed_mix := smoothstep(5.0, 57.0, speed)
	var base_zoom := lerpf(1.06, 0.64, speed_mix)
	var target_zoom := base_zoom * (1.0 - _surge * 0.012 + impact_strength * 0.022)
	zoom = zoom.lerp(Vector2.ONE * target_zoom, 1.0 - exp(-2.8 * dt))
	_impact_time += dt
	impact_strength = maxf(0.0, impact_strength - dt * 4.0)
	var shake := impact_strength * 9.0
	offset = Vector2(sin(_impact_time * 73.0), cos(_impact_time * 57.0)) * shake
	if global_position.distance_to(transform_now.origin) > 1600.0:
		global_position = transform_now.origin
		offset = Vector2.ZERO
		impact_strength = 0.0
		_surge = 0.0
		reset_physics_interpolation()
