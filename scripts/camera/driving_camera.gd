extends Camera2D
## Telemetry-driven visual framing. No changes to vehicle handling.
@export var target: VehicleController2D
var follow_heading := false
var impact_strength := 0.0
var _impact_time := 0.0
var _surge := 0.0
var _previous_longitudinal := 0.0
# The car is allowed to steer inside this angular pocket without rotating the world.
@export_range(0.0, 30.0, 1.0) var heading_deadzone_degrees := 12.0
# Limits screen rotation during hairpins, spins and rapid opposite-lock steering.
@export_range(20.0, 140.0, 5.0) var heading_max_turn_degrees_per_second := 70.0
var _heading_turn_velocity := 0.0

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
	_update_heading_rotation(dt, transform_now.get_rotation(), speed)
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

func _update_heading_rotation(dt: float, car_heading: float, speed: float) -> void:
	# North-up retains its original, predictable return-to-zero behavior.
	if not follow_heading:
		_heading_turn_velocity = 0.0
		rotation = lerp_angle(rotation, 0.0, 1.0 - exp(-3.0 * dt))
		return

	# A dead zone allows the car to turn a little against the fixed world.
	# Work in wrapped angles so crossing +/-180 degrees never spins the camera.
	var heading_error := wrapf(car_heading - rotation, -PI, PI)
	var pocket := deg_to_rad(heading_deadzone_degrees)
	var outside_pocket := signf(heading_error) * maxf(absf(heading_error) - pocket, 0.0)

	# Near parking speeds, don't swing the entire world as the car pivots.
	var movement_factor := smoothstep(1.5, 9.0, speed)
	var max_turn_rate := deg_to_rad(heading_max_turn_degrees_per_second)
	var desired_turn_rate := clampf(outside_pocket * 2.2, -max_turn_rate, max_turn_rate) * movement_factor
	# Damped angular velocity creates soft catch-up rather than a hard heading lock.
	_heading_turn_velocity = lerpf(_heading_turn_velocity, desired_turn_rate, 1.0 - exp(-4.5 * dt))
	var turn_step := _heading_turn_velocity * dt
	# Never overshoot the edge of the pocket or drift once the car settles.
	if absf(turn_step) >= absf(outside_pocket):
		turn_step = outside_pocket
		_heading_turn_velocity = 0.0
	rotation = wrapf(rotation + turn_step, -PI, PI)
