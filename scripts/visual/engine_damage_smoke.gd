extends Node2D
## Lightweight world-space hood smoke for damaged player vehicles.
## Health controls ONLY visuals; VehicleDamage handles drivetrain effects.
## Puffs remain where emitted instead of rotating with the moving car.
const PPM := 20.0
const SMOKE_START_HEALTH := 60.0
const MAX_PUFFS := 32
const MAX_EMISSIONS_PER_SECOND := 10.0

var vehicle: VehicleController2D
var engine_health := 100.0
var puffs: Array[Dictionary] = []
var _accumulator := 0.0
var _last_vehicle_position := Vector2.ZERO
var _rng := RandomNumberGenerator.new()

static func smoke_strength(health: float) -> float:
	if not is_finite(health) or health >= SMOKE_START_HEALTH:
		return 0.0
	return pow(clampf((SMOKE_START_HEALTH - maxf(0.0, health)) /
		SMOKE_START_HEALTH, 0.0, 1.0), 0.75)

func _ready() -> void:
	if not is_instance_valid(vehicle):
		vehicle = get_parent() as VehicleController2D
	if not is_instance_valid(vehicle):
		set_process(false)
		return
	name = "EngineDamageSmoke"
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = 11
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.seed = 82401 + vehicle.get_instance_id()
	_last_vehicle_position = vehicle.global_position
	vehicle.vehicle_reset.connect(clear_puffs)
	set_process(smoke_strength(engine_health) > 0.0)

func set_health(health: float) -> void:
	engine_health = clampf(health, 0.0, 100.0) if is_finite(health) else 100.0
	# Existing smoke fades naturally after repairs. New emissions stop at
	# healthy condition or when changing to a healthy vehicle.
	set_process(smoke_strength(engine_health) > 0.0 or not puffs.is_empty())

func clear_puffs() -> void:
	puffs.clear()
	_accumulator = 0.0
	if is_instance_valid(vehicle):
		_last_vehicle_position = vehicle.global_position
	set_process(smoke_strength(engine_health) > 0.0)
	queue_redraw()

func _hood_position() -> Vector2:
	var hood := Vector2(0.0, -28.0)
	var rig: Node = vehicle.get_node_or_null("Art/Wheels")
	if is_instance_valid(rig):
		var bounds: Rect2 = rig.get("visible_bounds")
		if bounds.has_area():
			# Use the selected car model's actual bounds, not a fixed hood
			# location that works only for the default coupe sprite.
			hood = bounds.position + bounds.size * Vector2(0.5, 0.20)
	return vehicle.global_position + hood.rotated(vehicle.rotation)

func _spawn_puff(strength: float) -> void:
	var point := _hood_position()
	point += Vector2(_rng.randf_range(-5.0, 5.0),
		_rng.randf_range(-4.0, 4.0))
	var airflow := -vehicle.linear_velocity * PPM * 0.13
	airflow = airflow.limit_length(120.0)
	var drift := airflow + Vector2(
		_rng.randf_range(-22.0, 22.0),
		_rng.randf_range(-34.0, -9.0))
	puffs.append({
		"point": point,
		"drift": drift,
		"age": 0.0,
		"life": _rng.randf_range(0.75, 1.30),
		"radius": _rng.randf_range(5.0, 9.0) * (0.75 + strength * 0.5),
		"opacity": 0.12 + strength * 0.19
	})

func _process(delta: float) -> void:
	if not is_instance_valid(vehicle):
		set_process(false)
		return
	var dt := clampf(delta, 0.0, 0.05)
	if dt <= 0.0:
		return
	if vehicle.global_position.distance_to(_last_vehicle_position) > 550.0:
		clear_puffs()
	_last_vehicle_position = vehicle.global_position
	for i in range(puffs.size() - 1, -1, -1):
		var puff: Dictionary = puffs[i]
		puff["age"] = float(puff["age"]) + dt
		if float(puff["age"]) >= float(puff["life"]):
			puffs.remove_at(i)
			continue
		puff["point"] = Vector2(puff["point"]) + Vector2(puff["drift"]) * dt
		puffs[i] = puff
	var strength := smoke_strength(engine_health)
	if strength > 0.0:
		_accumulator = minf(_accumulator + dt * MAX_EMISSIONS_PER_SECOND *
			strength, 2.0)
		while _accumulator >= 1.0 and puffs.size() < MAX_PUFFS:
			_accumulator -= 1.0
			_spawn_puff(strength)
		if puffs.size() >= MAX_PUFFS:
			_accumulator = 0.0
	else:
		_accumulator = 0.0
	if strength <= 0.0 and puffs.is_empty():
		set_process(false)
	queue_redraw()

func _draw() -> void:
	for puff in puffs:
		var progress: float = float(puff["age"]) / float(puff["life"])
		var fade := pow(1.0 - progress, 1.7)
		var radius: float = float(puff["radius"]) * (1.0 + progress * 1.6)
		var alpha: float = float(puff["opacity"]) * fade
		var point: Vector2 = puff["point"]
		# Soft grey smoke, not the bright flames of the exhaust system.
		draw_circle(point, radius, Color(0.25, 0.29, 0.30, alpha))
		draw_circle(point + Vector2(-radius * 0.24, -radius * 0.25),
			radius * 0.64, Color(0.54, 0.57, 0.56, alpha * 0.44))
