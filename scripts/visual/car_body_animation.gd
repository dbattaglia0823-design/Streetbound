extends Node2D
## Springy sprite-only movement. Physical car and collision shape do not move.
var vehicle: VehicleController2D
var _last_speed := 0.0
var _last_position := Vector2.ZERO
var _sway := 0.0
var _pitch := 0.0
var _impact := 0.0
var _clock := 0.0

func _ready() -> void:
	vehicle = get_parent() as VehicleController2D
	_last_speed = vehicle.longitudinal_speed
	_last_position = vehicle.global_position
	vehicle.impacted.connect(_on_impact)

func _on_impact(strength: float) -> void:
	_impact = maxf(_impact, clampf(strength / 16.0, 0.0, 1.0))

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if dt <= 0.0:
		return
	_clock += dt
	if vehicle.global_position.distance_to(_last_position) > 550.0:
		_sway = 0.0
		_pitch = 0.0
		_impact = 0.0
		_last_speed = vehicle.longitudinal_speed
	_last_position = vehicle.global_position
	var acceleration := (vehicle.longitudinal_speed - _last_speed) / dt
	_last_speed = vehicle.longitudinal_speed
	var corner_load := clampf(vehicle.yaw_rate * vehicle.longitudinal_speed / 35.0, -1.0, 1.0)
	var slide_load := clampf(vehicle.lateral_speed / 11.0, -1.0, 1.0)
	var target_sway := clampf(corner_load * 0.8 + slide_load * 0.25, -1.0, 1.0)
	var target_pitch := clampf(acceleration / 13.0, -1.0, 1.0)
	_sway = lerpf(_sway, target_sway, 1.0 - exp(-8.0 * dt))
	_pitch = lerpf(_pitch, target_pitch, 1.0 - exp(-7.0 * dt))
	_impact = move_toward(_impact, 0.0, dt * 5.0)
	var speed_mix := smoothstep(10.0, 40.0, vehicle.linear_velocity.length())
	var rumble := sin(_clock * 31.0) * 0.20 * speed_mix
	var jolt := sin(_clock * 48.0) * _impact
	position = Vector2(-_sway * 1.8 + jolt * 1.2, _pitch * 1.4 + rumble + jolt * 2.5)
	rotation = -_sway * 0.015 + jolt * 0.012
	scale = Vector2(1.0 - _pitch * 0.003, 1.0 + _pitch * 0.006)
