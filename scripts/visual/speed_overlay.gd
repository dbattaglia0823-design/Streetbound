extends Node2D
## Pooled peripheral speed lines in screen space; no full-screen blur shader.
const STREAK_COUNT := 50
var vehicle: VehicleController2D
var camera: Camera2D
var intensity := 0.0
var streaks: Array[Vector2] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 90442
	var viewport_size := get_viewport_rect().size
	for i in STREAK_COUNT:
		streaks.append(Vector2(_rng.randf_range(0, viewport_size.x), _rng.randf_range(0, viewport_size.y)))

func _process(delta: float) -> void:
	if not is_instance_valid(vehicle) or not is_instance_valid(camera):
		return
	var dt := minf(delta, 0.05)
	var speed := vehicle.linear_velocity.length()
	var target_intensity := smoothstep(15.0, 46.0, speed)
	intensity = lerpf(intensity, target_intensity, 1.0 - exp(-4.0 * dt))
	if intensity < 0.015 or speed < 0.1:
		queue_redraw()
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x < 1 or viewport_size.y < 1:
		return
	var direction := -vehicle.linear_velocity.rotated(-camera.global_rotation).normalized()
	var travel := direction * (180.0 + speed * 20.0) * dt
	for i in streaks.size():
		streaks[i] += travel
		var p := streaks[i]
		if p.x < -130.0 or p.x > viewport_size.x + 130.0 or p.y < -130.0 or p.y > viewport_size.y + 130.0:
			streaks[i] = _spawn_upstream(viewport_size, direction)
	queue_redraw()

func _spawn_upstream(size: Vector2, direction: Vector2) -> Vector2:
	if absf(direction.x) > absf(direction.y):
		return Vector2(-35.0 if direction.x > 0.0 else size.x + 35.0, _rng.randf_range(0.0, size.y))
	return Vector2(_rng.randf_range(0.0, size.x), -35.0 if direction.y > 0.0 else size.y + 35.0)

func _draw() -> void:
	if intensity < 0.025 or not is_instance_valid(vehicle) or not is_instance_valid(camera):
		return
	var size := get_viewport_rect().size
	if size.x < 1.0 or size.y < 1.0 or vehicle.linear_velocity.length_squared() < 1.0:
		return
	var center := size * 0.5
	var direction := -vehicle.linear_velocity.rotated(-camera.global_rotation).normalized()
	for i in streaks.size():
		var point := streaks[i]
		var across := absf(point.x - center.x) / maxf(center.x, 1.0)
		var down := absf(point.y - center.y) / maxf(center.y, 1.0)
		if across < 0.60 and down < 0.69:
			continue
		var edge := smoothstep(0.48, 0.98, maxf(across, down))
		var variance := 0.60 + float((i * 13) % 11) / 26.0
		var alpha := intensity * edge * variance * 0.23
		var line_length := (14.0 + 46.0 * intensity) * (0.7 + float(i % 5) * 0.1)
		draw_line(point - direction * line_length, point, Color(0.77, 0.86, 0.85, alpha), 1.0, true)
