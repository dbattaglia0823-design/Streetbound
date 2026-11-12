extends Node2D
## Arcade-grade speed feedback, deliberately confined to the screen perimeter.
## A fixed pool of streaks and four feathered edge bands avoid expensive
## full-screen blur, GPU particles and distractions over the car or road.
const STREAK_COUNT := 64
const MAX_SPEED_ALPHA := 0.58
var vehicle: VehicleController2D
var camera: Camera2D
var intensity := 0.0
var acceleration_pulse := 0.0
var streaks: Array[Vector2] = []
var _last_speed := 0.0
var _rng := RandomNumberGenerator.new()


static func speed_intensity(speed_mps: float) -> float:
	# Begins during quick street driving, becomes dramatic at race speed.
	return smoothstep(10.0, 50.0, maxf(0.0, speed_mps))


static func edge_strength(point: Vector2, viewport_size: Vector2) -> float:
	# The middle 60% of the view stays fully clear for traffic/racing lines.
	var center := viewport_size * 0.5
	var horizontal := absf(point.x - center.x) / maxf(center.x, 1.0)
	var vertical := absf(point.y - center.y) / maxf(center.y, 1.0)
	return smoothstep(0.58, 0.98, maxf(horizontal, vertical))


func _ready() -> void:
	_rng.seed = 90442
	var viewport_size := get_viewport_rect().size
	for i in STREAK_COUNT:
		streaks.append(Vector2(_rng.randf_range(0.0, viewport_size.x),
			_rng.randf_range(0.0, viewport_size.y)))
	if is_instance_valid(vehicle):
		_last_speed = vehicle.linear_velocity.length()


func _process(delta: float) -> void:
	if not is_instance_valid(vehicle) or not is_instance_valid(camera):
		return
	var dt := clampf(delta, 0.0, 0.05)
	var speed := vehicle.linear_velocity.length()
	var target_intensity := speed_intensity(speed)
	intensity = lerpf(intensity, target_intensity, 1.0 - exp(-5.2 * dt))
	var acceleration := (speed - _last_speed) / maxf(dt, 0.001)
	_last_speed = speed
	var punch := clampf((acceleration - 3.5) / 11.0, 0.0, 1.0)
	acceleration_pulse = lerpf(acceleration_pulse, punch,
		1.0 - exp(-(10.0 if punch > acceleration_pulse else 3.0) * dt))
	if intensity < 0.015 or speed < 0.1:
		queue_redraw()
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x < 1.0 or viewport_size.y < 1.0:
		return
	var direction := -vehicle.linear_velocity.rotated(-camera.global_rotation).normalized()
	var travel := direction * (240.0 + speed * 24.0) * dt
	for i in streaks.size():
		streaks[i] += travel
		var p := streaks[i]
		if p.x < -150.0 or p.x > viewport_size.x + 150.0 or \
				p.y < -150.0 or p.y > viewport_size.y + 150.0:
			streaks[i] = _spawn_upstream(viewport_size, direction)
	queue_redraw()


func _spawn_upstream(size: Vector2, direction: Vector2) -> Vector2:
	if absf(direction.x) > absf(direction.y):
		return Vector2(-35.0 if direction.x > 0.0 else size.x + 35.0,
			_rng.randf_range(0.0, size.y))
	return Vector2(_rng.randf_range(0.0, size.x),
		-35.0 if direction.y > 0.0 else size.y + 35.0)


func _draw() -> void:
	if intensity < 0.025 or not is_instance_valid(vehicle) or \
			not is_instance_valid(camera):
		return
	var size := get_viewport_rect().size
	if size.x < 1.0 or size.y < 1.0 or \
			vehicle.linear_velocity.length_squared() < 1.0:
		return
	var direction := -vehicle.linear_velocity.rotated(
		-camera.global_rotation).normalized()
	var visual_strength := clampf(intensity * (1.0 + acceleration_pulse * 0.25),
		0.0, 1.0)
	# Atmospheric blue-grey light bleed along the extreme viewport borders.
	# It remains below the HUD and never paints a central screen overlay.
	var edge_alpha := visual_strength * 0.075
	var edge_w := minf(size.x * 0.055, 55.0)
	var edge_h := minf(size.y * 0.085, 50.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(edge_w, size.y)),
		Color(0.30, 0.56, 0.60, edge_alpha))
	draw_rect(Rect2(Vector2(size.x - edge_w, 0), Vector2(edge_w, size.y)),
		Color(0.30, 0.56, 0.60, edge_alpha))
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, edge_h)),
		Color(0.30, 0.56, 0.60, edge_alpha * 0.65))
	draw_rect(Rect2(Vector2(0, size.y - edge_h), Vector2(size.x, edge_h)),
		Color(0.30, 0.56, 0.60, edge_alpha * 0.65))
	for i in streaks.size():
		var point := streaks[i]
		var edge := edge_strength(point, size)
		if edge <= 0.001:
			continue
		var variance := 0.65 + float((i * 13) % 11) / 21.0
		var alpha := minf(MAX_SPEED_ALPHA,
			visual_strength * edge * variance * 0.39)
		var length := (25.0 + 92.0 * visual_strength) * \
			(0.66 + float(i % 5) * 0.12)
		var tip := point
		var tail := point - direction * length
		draw_line(tail, tip, Color(0.67, 0.86, 0.90, alpha * 0.48),
			2.6 if i % 4 == 0 else 1.6, true)
		draw_line(tip - direction * minf(length * 0.32, 28.0), tip,
			Color(0.92, 0.97, 0.95, alpha), 1.2, true)
