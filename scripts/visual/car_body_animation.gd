extends Node2D
## Four-corner, visual-only curb suspension. The physical vehicle, tyre
## contact patches and collision transform are never moved or resized.
## Wheel probes derive from the same road/sidewalk geometry as the map.
const HEIGHT_LIFT_PX := 7.0
const SPRING_STIFFNESS := 115.0
const SPRING_DAMPING := 15.0
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


func _ready() -> void:
	vehicle = get_parent() as VehicleController2D
	_last_speed = vehicle.longitudinal_speed
	_last_position = vehicle.global_position
	vehicle.impacted.connect(_on_impact)


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
		var contact: Vector2 = vehicle.global_position + \
			Vector2(rig.wheel_anchor(i)).rotated(vehicle.rotation)
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
	var acceleration := (vehicle.longitudinal_speed-_last_speed)/dt
	_last_speed = vehicle.longitudinal_speed
	var corner_load := clampf(vehicle.yaw_rate*vehicle.longitudinal_speed/35.0,-1.0,1.0)
	var slide_load := clampf(vehicle.lateral_speed/11.0,-1.0,1.0)
	var target_sway := clampf(corner_load*0.8+slide_load*0.25,-1.0,1.0)
	var target_pitch := clampf(acceleration/13.0,-1.0,1.0)
	_sway = lerpf(_sway,target_sway,1.0-exp(-8.0*dt))
	_pitch = lerpf(_pitch,target_pitch,1.0-exp(-7.0*dt))
	_impact = move_toward(_impact,0.0,dt*5.0)
	var speed_mix := smoothstep(10.0,40.0,vehicle.linear_velocity.length())
	var rumble := sin(_clock*31.0)*0.18*speed_mix
	var jolt := sin(_clock*45.0)*_impact
	# Offset/scale communicate actual ride height while the left-right
	# differential produces a subtle body roll toward the raised wheel.
	# Add existing acceleration squat, cornering sway and crash rebound.
	position = Vector2(-_sway*1.8-curb_heave*3.0-curb_roll*1.1+jolt*1.2,
		_pitch*1.4+rumble+jolt*2.0-curb_heave*HEIGHT_LIFT_PX-
		curb_pitch*1.3)
	rotation = -_sway*0.015-curb_roll*0.018+jolt*0.010
	scale = Vector2(1.0+curb_heave*0.009-_pitch*0.003,
		1.0+curb_heave*0.009+_pitch*0.006+curb_pitch*0.007)
