extends Node2D
## Bounded world-space exhaust sparks, turbo lift-off puffs and nitrous
## plumes. Existing engine audio remains authoritative; this is visual-only.
const MAX_PARTICLES := 32
const MAX_BURST := 3
var vehicle: VehicleController2D
var particles: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _last_throttle := 0.0
var _last_position := Vector2.ZERO
var _shift_pending := false
var _nitrous_clock := 0.0
var emitted_bursts := 0

static func combustion_enabled(config: VehicleConfig) -> bool:
	return not str(config.audio_family).to_lower().contains("electric") and \
		not str(config.audio_induction).to_lower().contains("electric")

static func should_backfire(config: VehicleConfig, rpm: float,
		speed_mps: float, throttle_lift: bool, shift_event: bool) -> bool:
	if not combustion_enabled(config) or speed_mps < 5.0 or \
			rpm < maxf(config.idle_rpm+1300.0,2600.0):
		return false
	return (throttle_lift or shift_event) and \
		(config.boost_max_psi>.05 or config.audio_overrun>.25)


func _ready() -> void:
	vehicle = get_parent() as VehicleController2D
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = 7
	_rng.seed = 18743 + vehicle.get_instance_id()
	_last_position = vehicle.global_position
	_last_throttle = vehicle.throttle
	vehicle.transmission.shifted.connect(_on_shift)
	vehicle.vehicle_reset.connect(_on_reset)


func _on_shift(_gear: int) -> void:
	_shift_pending = true


func _on_reset() -> void:
	particles.clear()
	_shift_pending = false
	_nitrous_clock = 0.0
	_last_throttle = 0.0
	queue_redraw()


func _tip_contacts() -> Array[Vector2]:
	var left := Vector2(-11.0,42.0)
	var right := Vector2(11.0,42.0)
	var rig: Node = vehicle.get_node_or_null("Art/Wheels")
	if is_instance_valid(rig):
		var bounds: Rect2 = rig.get("visible_bounds")
		if bounds.has_area():
			var left_uv := Vector2(.33,.98)
			var right_uv := Vector2(.67,.98)
			var profile: Resource=rig.get("appearance") as Resource
			if profile != null:
				left_uv=profile.get("exhaust_left_uv")
				right_uv=profile.get("exhaust_right_uv")
			left=bounds.position+bounds.size*left_uv
			right=bounds.position+bounds.size*right_uv
	var chosen: Array[Vector2]=[]
	var count := 2
	if is_instance_valid(rig):
		var profile: Resource=rig.get("appearance") as Resource
		if profile != null:
			count=int(profile.get("exhaust_tip_count"))
	if count == 1:
		chosen.append((left+right)*.5)
	else:
		chosen.append(left)
		chosen.append(right)
	for i in chosen.size():
		chosen[i] = vehicle.global_position+chosen[i].rotated(vehicle.rotation)
	return chosen


func _spawn(kind: String) -> void:
	if particles.size() >= MAX_PARTICLES:
		return
	var points: Array[Vector2]=_tip_contacts()
	var origin: Vector2=points[_rng.randi_range(0,points.size()-1)]
	var forward := Vector2.DOWN.rotated(vehicle.rotation)
	var airflow := vehicle.linear_velocity * VehicleController2D.PIXELS_PER_METER
	var pulse: float=140.0 if kind=="nitrous" else 110.0
	var motion := forward * _rng.randf_range(pulse*.65,pulse*1.3)
	motion += airflow * .18
	motion += Vector2(_rng.randf_range(-24.0,24.0),_rng.randf_range(-24.0,24.0))
	particles.append({
		"point":origin,"drift":motion,"kind":kind,"age":0.0,
		"life":_rng.randf_range(.12,.24) if kind=="nitrous" else
			_rng.randf_range(.11,.19) if kind=="flame" else _rng.randf_range(.26,.43),
		"radius":_rng.randf_range(3.0,5.5)
	})


func _emit_burst() -> void:
	emitted_bursts += 1
	for i in mini(MAX_BURST,MAX_PARTICLES-particles.size()):
		_spawn("flame")
	if vehicle.config.boost_max_psi>.05:
		_spawn("haze")


func _process(delta: float) -> void:
	if not is_instance_valid(vehicle):
		return
	var dt := clampf(delta,0.0,.05)
	if vehicle.global_position.distance_to(_last_position)>550.0:
		_on_reset()
	_last_position=vehicle.global_position
	for i in range(particles.size()-1,-1,-1):
		var puff: Dictionary=particles[i]
		puff.age=float(puff.age)+dt
		if float(puff.age)>=float(puff.life):
			particles.remove_at(i)
			continue
		puff.point=Vector2(puff.point)+Vector2(puff.drift)*dt
		particles[i]=puff
	var lift: bool=_last_throttle>.65 and vehicle.throttle<.20
	_last_throttle=vehicle.throttle
	var speed := vehicle.linear_velocity.length()
	if should_backfire(vehicle.config,vehicle.transmission.rpm,speed,
			lift,_shift_pending):
		_emit_burst()
	_shift_pending=false
	# Blue nitrous exhaust is tied to the real installed/active kit, not
	# the N key by itself. Keep per-car emission and particle counts fixed.
	if vehicle.nitrous_active:
		_nitrous_clock += dt*23.0
		while _nitrous_clock>=1.0 and particles.size()<MAX_PARTICLES:
			_nitrous_clock-=1.0
			_spawn("nitrous")
	else:
		_nitrous_clock=0.0
	if not particles.is_empty():
		queue_redraw()


func _draw() -> void:
	for puff in particles:
		var age: float=float(puff.age)/maxf(float(puff.life),.001)
		var fade := pow(1.0-age,1.6)
		var point: Vector2=puff.point
		var size: float=float(puff.radius)*(1.0+age*.6)
		match str(puff.kind):
			"nitrous":
				draw_circle(point,size*1.5,Color(.20,.60,1.0,.22*fade))
				draw_circle(point,size*.72,Color(.78,.94,1.0,.82*fade))
			"flame":
				draw_circle(point,size*1.6,Color(1.0,.26,.05,.22*fade))
				draw_circle(point,size*.8,Color(1.0,.78,.28,.83*fade))
			_:
				draw_circle(point,size*(1.0+age*2.2),
					Color(.55,.65,.71,.19*fade))
