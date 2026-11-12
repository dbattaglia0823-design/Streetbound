extends Node2D
## Four-corner, visual-only curb suspension. The physical vehicle, tyre
## contact patches and collision transform are never moved or resized.
## Wheel probes derive from the same road/sidewalk geometry as the map.
const HEIGHT_LIFT_PX := 12.0
const SPRING_STIFFNESS := 115.0
const SPRING_DAMPING := 15.0
# The body responds on its own softer spring after the tire contact springs.
# These values change only the sprite, never the physical car or axles.
const BODY_SPRING_STIFFNESS := 74.0
const BODY_SPRING_DAMPING := 13.0
var vehicle: VehicleController2D
var _last_speed := 0.0
var _last_position := Vector2.ZERO
var _sway := 0.0
var _pitch := 0.0
var _impact := 0.0
var _clock := 0.0
var _corner_heights := PackedFloat32Array([0.0,0.0,0.0,0.0])
var _corner_speeds := PackedFloat32Array([0.0,0.0,0.0,0.0])
var _visual_curb_heights := PackedFloat32Array([0.0,0.0,0.0,0.0])
var curb_heave := 0.0
var curb_roll := 0.0
var curb_pitch := 0.0
var body_heave := 0.0
var body_roll := 0.0
var body_pitch := 0.0
var _body_heave_velocity := 0.0
var _body_roll_velocity := 0.0
var _body_pitch_velocity := 0.0
var _sprite_rest_position := Vector2.ZERO
var _sprite_rest_rotation := 0.0
var _sprite_rest_scale := Vector2.ONE
var _body_sprite: Sprite2D


func _ready() -> void:
	vehicle = get_parent() as VehicleController2D
	_last_speed = vehicle.longitudinal_speed
	_last_position = vehicle.global_position
	sync_body_rest_pose()
	vehicle.impacted.connect(_on_impact)


## Called on startup and when a different vehicle artwork/profile is equipped.
## Capturing the unanimated pose prevents the effect from accumulating or
## overwriting calibrated model rotation and offset after a vehicle swap.
func sync_body_rest_pose() -> void:
	_body_sprite = get_node_or_null("Sprite") as Sprite2D
	if not is_instance_valid(_body_sprite):
		return
	_sprite_rest_position = _body_sprite.position
	_sprite_rest_rotation = _body_sprite.rotation
	_sprite_rest_scale = _body_sprite.scale
	body_heave = 0.0
	body_roll = 0.0
	body_pitch = 0.0
	_body_heave_velocity = 0.0
	_body_roll_velocity = 0.0
	_body_pitch_velocity = 0.0


func _step_body_suspension(dt: float, snap: bool = false) -> void:
	if snap:
		body_heave = curb_heave
		body_roll = curb_roll
		body_pitch = curb_pitch
		_body_heave_velocity = 0.0
		_body_roll_velocity = 0.0
		_body_pitch_velocity = 0.0
		return
	# The independently damped body lags the wheels when climbing a curb,
	# briefly compresses on the way down, then settles without perpetual bob.
	_body_heave_velocity += ((curb_heave - body_heave) *
		BODY_SPRING_STIFFNESS - _body_heave_velocity *
		BODY_SPRING_DAMPING) * dt
	_body_roll_velocity += ((curb_roll - body_roll) *
		BODY_SPRING_STIFFNESS - _body_roll_velocity *
		BODY_SPRING_DAMPING) * dt
	_body_pitch_velocity += ((curb_pitch - body_pitch) *
		BODY_SPRING_STIFFNESS - _body_pitch_velocity *
		BODY_SPRING_DAMPING) * dt
	body_heave = clampf(body_heave + _body_heave_velocity * dt, -0.16, 1.18)
	body_roll = clampf(body_roll + _body_roll_velocity * dt, -1.2, 1.2)
	body_pitch = clampf(body_pitch + _body_pitch_velocity * dt, -1.2, 1.2)


## Short bounded road texture vibration moves the body independently of
## the tire contact nodes; stronger on gravel/dirt, subdued on clean roads.
static func bump_vibration(speed_mps: float, surface: String,
		clock: float) -> float:
	var roughness := 0.34
	match surface:
		"GRAVEL", "DIRT": roughness = 1.65
		"SAND": roughness = 1.20
		"GRASS": roughness = 1.05
	var moving := smoothstep(4.0, 35.0, speed_mps)
	return (sin(clock * 29.0) * 0.68 +
		sin(clock * 41.0) * 0.34) * moving * roughness


func _apply_body_suspension(surface_bump: float = 0.0) -> void:
	if not is_instance_valid(_body_sprite):
		return
	# The body sprite moves and leans independently from the wheel layer.
	# Its calibrated baseline is always preserved for each selected car.
	_body_sprite.position = _sprite_rest_position + Vector2(
		-body_roll * 3.4,
		-body_heave * HEIGHT_LIFT_PX - body_pitch * 2.3 + surface_bump)
	_body_sprite.rotation = _sprite_rest_rotation - body_roll * 0.032 + \
		body_pitch * 0.008
	_body_sprite.scale = _sprite_rest_scale * Vector2(
		1.0 + body_heave * 0.012 - body_roll * 0.004,
		1.0 + body_heave * 0.010 + body_pitch * 0.010)


func _on_impact(strength: float) -> void:
	_impact = maxf(_impact,clampf(strength/16.0,0.0,1.0))


func _wheel_targets() -> PackedFloat32Array:
	var targets := PackedFloat32Array([0.0,0.0,0.0,0.0])
	if not is_instance_valid(vehicle) or not is_instance_valid(vehicle.surface_provider):
		return targets
	if not vehicle.surface_provider.has_method("curb_height_at"):
		return targets
	var rig := get_node_or_null("Wheels")
	if not is_instance_valid(rig) or not rig.has_method("wheel_anchor"):
		return targets
	for i in 4:
		# Deliberately do not use wheel.global_position or body offsets here.
		# Those are animated and would feed back into surface detection.
		var anchor: Vector2 = rig.wheel_anchor(i)
		var contact: Vector2 = vehicle.global_position + anchor.rotated(vehicle.rotation)
		targets[i] = clampf(float(vehicle.surface_provider.curb_height_at(contact)),0.0,1.0)
	return targets


func _step_suspension(dt: float, targets: PackedFloat32Array, snap := false) -> void:
	if targets.size() != 4:
		return
	for i in 4:
		var target := float(targets[i])
		if snap:
			_corner_heights[i] = target
			_corner_speeds[i] = 0.0
		else:
			var velocity := float(_corner_speeds[i]) + \
				(target-float(_corner_heights[i]))*SPRING_STIFFNESS*dt
			velocity *= exp(-SPRING_DAMPING*dt)
			_corner_speeds[i] = velocity
			_corner_heights[i] = clampf(float(_corner_heights[i]) + velocity*dt,
				-0.12,1.15)
		_visual_curb_heights[i] = clampf(float(_corner_heights[i]),0.0,1.0)
	curb_heave = (float(_visual_curb_heights[0])+float(_visual_curb_heights[1])
		+float(_visual_curb_heights[2])+float(_visual_curb_heights[3]))*0.25
	curb_roll = ((float(_visual_curb_heights[0])+float(_visual_curb_heights[2]))-
		(float(_visual_curb_heights[1])+float(_visual_curb_heights[3])))*0.5
	curb_pitch = ((float(_visual_curb_heights[0])+float(_visual_curb_heights[1]))-
		(float(_visual_curb_heights[2])+float(_visual_curb_heights[3])))*0.5
	var rig := get_node_or_null("Wheels")
	if is_instance_valid(rig) and rig.has_method("set_curb_heights"):
		rig.set_curb_heights(_visual_curb_heights)


func _process(delta: float) -> void:
	var dt := minf(delta,0.05)
	if dt <= 0.0 or not is_instance_valid(vehicle):
		return
	_clock += dt
	var teleported := vehicle.global_position.distance_to(_last_position) > 550.0
	if teleported:
		_sway = 0.0
		_pitch = 0.0
		_impact = 0.0
		_last_speed = vehicle.longitudinal_speed
	_last_position = vehicle.global_position
	_step_suspension(dt,_wheel_targets(),teleported)
	_step_body_suspension(dt, teleported)
	var acceleration := (vehicle.longitudinal_speed-_last_speed)/dt
	_last_speed = vehicle.longitudinal_speed
	var corner_load := clampf(vehicle.yaw_rate*vehicle.longitudinal_speed/35.0,-1.0,1.0)
	var slide_load := clampf(vehicle.lateral_speed/11.0,-1.0,1.0)
	# Readable body weight transfer from actual G-forces. A slide visibly
	# leans the body without ever changing the collision shape or wheel hubs.
	var target_sway := clampf(corner_load * 0.85 + slide_load * 0.38,
		-1.0, 1.0)
	var target_pitch := clampf(acceleration / 11.0, -1.0, 1.0)
	_sway = lerpf(_sway, target_sway, 1.0 - exp(-7.0 * dt))
	_pitch = lerpf(_pitch, target_pitch, 1.0 - exp(-6.0 * dt))
	_impact = move_toward(_impact,0.0,dt*5.0)
	_apply_body_suspension(bump_vibration(
		vehicle.linear_velocity.length(), vehicle.surface, _clock))
	var jolt := sin(_clock * 45.0) * _impact
	# Parent Art retains mild acceleration, cornering and impact feedback,
	# but curb rise is applied to Sprite ONLY. The wheel rig has its own
	# four-corner lift, so the body no longer follows tires rigidly.
	position = Vector2(-_sway * 2.8 + jolt * 1.8,
		_pitch * 2.6 + jolt * 2.6)
	rotation = -_sway * 0.024 + jolt * 0.012
	scale = Vector2(1.0 - _pitch * 0.004,
		1.0 + _pitch * 0.010)
