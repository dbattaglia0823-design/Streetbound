extends Node2D
## Lightweight world-space raindrops and wet-pavement light glints.
## This is purely cosmetic: the shared vehicle controller owns grip.
const Weather = preload("res://scripts/world/weather_conditions.gd")
const Lights = preload("res://scripts/visual/vehicle_lights.gd")
const MAX_DROPS := 80
const MAX_REFLECTION_CARS := 18
const RAIN_VIEW_RADIUS := 1150.0

var world: Node2D
var focus_vehicle: VehicleController2D
var drops: Array[Dictionary] = []
var _budget := 0.0
var _last_focus := Vector2.ZERO
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	top_level = true
	global_transform = Transform2D.IDENTITY
	z_as_relative = false
	z_index = 5
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.seed = 70391
	if is_instance_valid(focus_vehicle):
		_last_focus = focus_vehicle.global_position

static func reflection_opacity(rain: float, pavement: String) -> float:
	return clampf(rain, 0.0, 1.0) * 0.22 if pavement == "ASPHALT" else 0.0

func _process(delta: float) -> void:
	if not is_instance_valid(focus_vehicle):
		return
	var wet: float = Weather.rain_at(world,focus_vehicle.global_position)
	if wet <= 0.01:
		if not drops.is_empty():
			drops.clear()
			queue_redraw()
		_budget = 0.0
		return
	var dt := clampf(delta, 0.0, 0.05)
	if dt <= 0.0:
		return
	var focus: Vector2 = focus_vehicle.global_position
	if focus.distance_to(_last_focus) > 1800.0:
		drops.clear()
		_budget = 0.0
	_last_focus = focus
	for i in range(drops.size() - 1, -1, -1):
		var drop: Dictionary = drops[i]
		drop.age = float(drop.age) + dt
		if float(drop.age) >= float(drop.life):
			drops.remove_at(i)
			continue
		drop.point = Vector2(drop.point) + Vector2(35.0, 115.0) * dt
		drops[i] = drop
	_budget = minf(_budget + dt * wet * 105.0, 8.0)
	while _budget >= 1.0 and drops.size() < MAX_DROPS:
		_budget -= 1.0
		drops.append({
			"point": focus + Vector2(_rng.randf_range(-RAIN_VIEW_RADIUS, RAIN_VIEW_RADIUS),
				_rng.randf_range(-RAIN_VIEW_RADIUS, RAIN_VIEW_RADIUS)),
			"age": 0.0, "life": _rng.randf_range(0.17, 0.36),
			"length": _rng.randf_range(9.0, 23.0)
		})
	if drops.size() >= MAX_DROPS:
		_budget = 0.0
	queue_redraw()

func _draw_reflections(car: Node2D, wet: float) -> void:
	var points: Array[Vector2] = Lights.points_for(car)
	if points.size() != 2:
		return
	var rear := Vector2.DOWN.rotated(car.global_rotation)
	var front := -rear
	var brightness := wet * 0.19
	for anchor in points:
		var pos: Vector2 = car.global_position + anchor.rotated(car.global_rotation)
		draw_line(pos + rear * 5.0, pos + rear * 48.0,
			Color(1.0, 0.10, 0.07, brightness), 6.0, true)
		draw_line(pos + rear * 9.0, pos + rear * 27.0,
			Color(1.0, 0.42, 0.27, brightness * 0.65), 2.0, true)
	var span: float = 16.0
	if car.is_in_group("traffic_vehicle"):
		span = float(car.get("width_px")) * 0.28
	for side in [-1.0, 1.0]:
		var head := car.global_position + Vector2(side * span, -32.0).rotated(car.global_rotation)
		draw_line(head + front * 4.0, head + front * 78.0,
			Color(0.72, 0.86, 1.0, brightness * 0.9), 8.0, true)
		draw_line(head + front * 8.0, head + front * 43.0,
			Color(0.95, 0.97, 1.0, brightness), 3.0, true)

func _draw() -> void:
	var wet: float = Weather.rain_at(world,focus_vehicle.global_position)
	if wet <= 0.01 or not is_instance_valid(focus_vehicle):
		return
	for drop in drops:
		var fade := 1.0 - float(drop.age) / float(drop.life)
		var p: Vector2 = drop.point
		draw_line(p, p + Vector2(4.0, float(drop.length)),
			Color(0.65, 0.78, 0.88, fade * wet * 0.20), 1.25, true)
	var drawn := 0
	for group in ["skidmark_vehicle", "traffic_vehicle"]:
		for node in get_tree().get_nodes_in_group(group):
			if drawn >= MAX_REFLECTION_CARS:
				return
			if not node is Node2D:
				continue
			var car: Node2D = node
			if car.global_position.distance_squared_to(focus_vehicle.global_position) > 					RAIN_VIEW_RADIUS * RAIN_VIEW_RADIUS:
				continue
			if car is VehicleController2D and (car as VehicleController2D).surface_provider != world:
				continue
			var material: String = str(world.surface_at(car.global_position).get("name", "GRASS"))
			var alpha := reflection_opacity(wet, material)
			if alpha <= 0.0:
				continue
			_draw_reflections(car, alpha / 0.22)
			drawn += 1
