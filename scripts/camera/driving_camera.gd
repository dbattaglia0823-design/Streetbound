extends Camera2D
## Telemetry-driven visual framing. No changes to vehicle handling.
@export var target: VehicleController2D
# World-only magnification: CanvasLayer HUD and minimap sizes stay unchanged.
# Preserve the original speed-follow camera at the default player setting.
# Mouse-wheel zoom is multiplied around it, rather than replacing it.
@export_range(0.8, 1.6, 0.01) var world_zoom_multiplier := 1.20
## Main-world only: show the actual garage and first row of houses before
## moving. The default driving camera and user-selected zoom are unchanged.
var startup_neighborhood_view := false
const STARTUP_NEIGHBORHOOD_ZOOM := 0.62
var _neighborhood_view_active := false
var _neighborhood_start_position := Vector2.ZERO
# Player zoom is proportional (8% per notch) so the step feels natural at
# every distance. Hard camera bounds prevent excessive close-ups / far views.
const PLAYER_ZOOM_MIN := 0.72
const PLAYER_ZOOM_MAX := 1.45
const WHEEL_ZOOM_FACTOR := 1.08
const ABSOLUTE_ZOOM_MIN := 0.62
const ABSOLUTE_ZOOM_MAX := 1.76
const WHEEL_RESPONSE := 9.0
const CAMERA_RESPONSE := 3.8
var player_zoom_multiplier := 1.0
var _smoothed_player_zoom := 1.0
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
	_neighborhood_start_position = global_position
	_neighborhood_view_active = startup_neighborhood_view
	# The Laurel spawn sits in a large parking lot. The former 1.272x
	# opening hid both the garage (42m west) and houses (46m east), creating
	# the impression of a roadless, empty world. Show both at first launch.
	zoom = Vector2.ONE * (STARTUP_NEIGHBORHOOD_ZOOM if
		_neighborhood_view_active else 1.06 * world_zoom_multiplier)
	_previous_longitudinal = target.longitudinal_speed
	target.impacted.connect(_on_impact)

## Wheel up brings the camera closer; wheel down pulls it back. This is
## intentionally handled only for unconsumed viewport input: scrolling the
## full-screen map or a UI panel still belongs to that panel.
func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	var wheel := event as InputEventMouseButton
	if wheel == null or not wheel.pressed:
		return
	var direction := 0
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = 1
	elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = -1
	if direction == 0:
		return
	_neighborhood_view_active = false
	player_zoom_multiplier = stepped_player_zoom(player_zoom_multiplier, direction)
	get_viewport().set_input_as_handled()


## Pure helpers keep wheel limits and speed compensation testable.
static func stepped_player_zoom(current: float, direction: int) -> float:
	return clampf(current * pow(WHEEL_ZOOM_FACTOR, float(direction)),
		PLAYER_ZOOM_MIN, PLAYER_ZOOM_MAX)


static func speed_zoom_weight(player_magnification: float) -> float:
	# Reduce automatic speed zoom at extreme manual settings. This keeps
	# acceleration from producing a second huge framing change after the
	# player has deliberately chosen a close-up or wide view.
	if player_magnification < 1.0:
		return lerpf(0.75, 1.0,
			clampf(inverse_lerp(PLAYER_ZOOM_MIN, 1.0,
				player_magnification), 0.0, 1.0))
	return lerpf(1.0, 0.55,
		clampf(inverse_lerp(1.0, PLAYER_ZOOM_MAX,
			player_magnification), 0.0, 1.0))


static func target_zoom_for(speed: float, player_magnification: float,
		world_magnification: float, acceleration_surge: float = 0.0,
		collision_impact: float = 0.0) -> float:
	var user_factor := clampf(player_magnification,
		PLAYER_ZOOM_MIN, PLAYER_ZOOM_MAX)
	var speed_mix := smoothstep(5.0, 57.0, speed)
	var base := lerpf(1.06, 0.64,
		speed_mix * speed_zoom_weight(user_factor))
	var effects := 1.0 - acceleration_surge * 0.012 + collision_impact * 0.022
	return clampf(base * world_magnification * user_factor * effects,
		ABSOLUTE_ZOOM_MIN, ABSOLUTE_ZOOM_MAX)


func _on_impact(strength: float) -> void:
	impact_strength = maxf(impact_strength, clampf((strength - 2.0) / 18.0, 0.0, 1.0))
	_impact_time = 0.0

func _physics_process(dt: float) -> void:
	if Input.is_action_just_pressed("camera"):
		follow_heading = not follow_heading
	var transform_now: Transform2D = target.global_transform
	var speed := target.linear_velocity.length()
	# The overview is an initial composition, not a persistent handling or
	# zoom change. Driving away, steering into traffic, or manual wheel zoom
	# restores the player's original 20%-magnified follow camera.
	if _neighborhood_view_active and (speed >= 1.5 or
			transform_now.origin.distance_to(_neighborhood_start_position) >= 32.0):
		_neighborhood_view_active = false
	var forward_speed := maxf(target.longitudinal_speed, 0.0)
	var acceleration := (forward_speed - maxf(_previous_longitudinal, 0.0)) / maxf(dt, 0.001)
	_previous_longitudinal = target.longitudinal_speed
	_surge = lerpf(_surge, clampf(acceleration / 14.0, 0.0, 1.0), 1.0 - exp(-3.8 * dt))
	var lead := target.linear_velocity * 3.8
	var desired := transform_now.origin + lead.limit_length(230.0)
	global_position = global_position.lerp(desired, 1.0 - exp(-5.0 * dt))
	_update_heading_rotation(dt, transform_now.get_rotation(), speed)
	# Manual zoom eases independently from speed-based framing. The speed
	# response is tempered by the player's chosen distance, and the total
	# remains bounded even during hard acceleration or an impact.
	_smoothed_player_zoom = lerpf(_smoothed_player_zoom,
		player_zoom_multiplier, 1.0 - exp(-WHEEL_RESPONSE * dt))
	var target_zoom := target_zoom_for(speed, _smoothed_player_zoom,
		world_zoom_multiplier, _surge, impact_strength)
	if _neighborhood_view_active:
		target_zoom = minf(target_zoom, STARTUP_NEIGHBORHOOD_ZOOM)
	zoom = zoom.lerp(Vector2.ONE * target_zoom,
		1.0 - exp(-CAMERA_RESPONSE * dt))
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
