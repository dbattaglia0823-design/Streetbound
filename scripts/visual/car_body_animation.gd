extends Node2D
## Lightweight visual handling response. The old independent four-corner
## suspension/curb springs were removed: in a top-down view they separated the
## rear tires from the calibrated fenders without improving actual handling.
## All vehicle physics, tyre grip and collision stay in VehicleController2D.
var vehicle: VehicleController2D
var _last_speed := 0.0
var _last_position := Vector2.ZERO
var _sway := 0.0
var _pitch := 0.0
var _impact := 0.0
var _clock := 0.0
var _body_sprite: Sprite2D
var _sprite_rest_position := Vector2.ZERO
var _sprite_rest_rotation := 0.0
var _sprite_rest_scale := Vector2.ONE


func _ready() -> void:
	vehicle = get_parent() as VehicleController2D
	_last_speed = vehicle.longitudinal_speed
	_last_position = vehicle.global_position
	sync_body_rest_pose()
	vehicle.impacted.connect(_on_impact)


func sync_body_rest_pose() -> void:
	# Recalibrate on vehicle changes without allowing animated offsets to
	# accumulate from the previous body sprite.
	_body_sprite = get_node_or_null("Sprite") as Sprite2D
	if is_instance_valid(_body_sprite):
		_sprite_rest_position = _body_sprite.position
		_sprite_rest_rotation = _body_sprite.rotation
		_sprite_rest_scale = _body_sprite.scale
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	_sway = 0.0
	_pitch = 0.0
	_impact = 0.0
	var rig := get_node_or_null("Wheels")
	if is_instance_valid(rig) and rig.has_method("set_curb_heights"):
		rig.set_curb_heights(PackedFloat32Array([0.0,0.0,0.0,0.0]))


func _on_impact(strength: float) -> void:
	_impact = maxf(_impact,clampf(strength/16.0,0.0,1.0))


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
	var acceleration := (vehicle.longitudinal_speed-_last_speed)/dt
	_last_speed = vehicle.longitudinal_speed
	var corner_load := clampf(vehicle.yaw_rate*vehicle.longitudinal_speed/35.0,-1.0,1.0)
	var slide_load := clampf(vehicle.lateral_speed/11.0,-1.0,1.0)
	var target_sway := clampf(corner_load * 0.85 + slide_load * 0.38,-1.0,1.0)
	var target_pitch := clampf(acceleration / 11.0,-1.0,1.0)
	_sway = lerpf(_sway,target_sway,1.0-exp(-7.0*dt))
	_pitch = lerpf(_pitch,target_pitch,1.0-exp(-6.0*dt))
	_impact = move_toward(_impact,0.0,dt*5.0)
	var jolt := sin(_clock*45.0)*_impact
	# Small shared movement keeps steering/impact readable without ever
	# lifting individual tires or moving the body independently of its wheels.
	position = Vector2(-_sway*1.6+jolt*1.2,_pitch*1.3+jolt*1.4)
	rotation = -_sway*0.012+jolt*0.006
	scale = Vector2.ONE
