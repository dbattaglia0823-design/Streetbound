extends Node2D
## Bounded translucent tire smoke and loose-surface dust in world coordinates.
const MAX_PUFFS := 72
var vehicle: VehicleController2D
var puffs: Array[Dictionary] = []
var _emission := 0.0
var _last_position := Vector2.ZERO
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 60491
	_last_position = vehicle.global_position
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _process(delta: float) -> void:
	if not is_instance_valid(vehicle):
		return
	var dt := minf(delta, 0.05)
	if dt <= 0.0:
		return
	if vehicle.global_position.distance_to(_last_position) > 550.0:
		puffs.clear()
		_emission = 0.0
	_last_position = vehicle.global_position
	for i in range(puffs.size() - 1, -1, -1):
		var puff: Dictionary = puffs[i]
		puff["age"] = float(puff["age"]) + dt
		if float(puff["age"]) >= float(puff["life"]):
			puffs.remove_at(i)
			continue
		puff["point"] = Vector2(puff["point"]) + Vector2(puff["drift"]) * dt
		puffs[i] = puff
	var speed := vehicle.linear_velocity.length()
	var moving := smoothstep(3.0, 14.0, speed)
	var slide := smoothstep(0.10, 0.38, absf(vehicle.slip_angle))
	var tire_loss := maxf(slide, maxf(vehicle.wheel_spin * 1.7, vehicle.handbrake_grip_loss))
	var loose := 0.0 if vehicle.surface == "ASPHALT" else 0.55
	var strength := maxf(tire_loss, loose) * moving
	if strength < 0.03:
		_emission = 0.0
	else:
		_emission = minf(_emission + dt * strength * 35.0, 4.0)
		while _emission >= 1.0 and puffs.size() < MAX_PUFFS:
			_emission -= 1.0
			_spawn_puff(vehicle.surface != "ASPHALT")
		if puffs.size() >= MAX_PUFFS:
			_emission = 0.0
	queue_redraw()

func _spawn_puff(dust: bool) -> void:
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var right := Vector2.RIGHT.rotated(vehicle.rotation)
	var rear := Vector2.DOWN.rotated(vehicle.rotation)
	var point := vehicle.global_position + rear * 31.0 + right * (side * 16.0)
	point += Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0))
	var drift := vehicle.linear_velocity * VehicleController2D.PIXELS_PER_METER * 0.11
	drift += Vector2(_rng.randf_range(-25.0, 25.0), _rng.randf_range(-25.0, 25.0))
	puffs.append({
		"point": point,
		"drift": drift,
		"age": 0.0,
		"life": _rng.randf_range(0.42, 0.82),
		"radius": _rng.randf_range(5.0, 9.0),
		"color": Color(0.79, 0.73, 0.59, 1.0) if dust else Color(0.76, 0.81, 0.82, 1.0)
	})

func _draw() -> void:
	for puff in puffs:
		var progress := float(puff["age"]) / float(puff["life"])
		var fade := (1.0 - progress) * (1.0 - progress)
		var point: Vector2 = puff["point"]
		var radius := float(puff["radius"]) * (1.0 + progress * 1.8)
		var tint: Color = puff["color"]
		tint.a = 0.16 * fade
		draw_circle(point, radius, tint)
		tint.a = 0.11 * fade
		draw_circle(point + Vector2(radius * 0.28, -radius * 0.20), radius * 0.62, tint)
