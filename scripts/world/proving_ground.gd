class_name ProvingGround
extends Node2D
const ROAD_WIDTH := 500.0
var road := PackedVector2Array()
var gravel := Rect2(850, -1850, 1050, 1650)
var skidpad_center := Vector2(1250, 600)
var skidpad_radius := 780.0
const TireMarks = preload("res://scripts/world/tire_marks.gd")
var tire_marks: MultiMeshInstance2D
var mark_clock := 0.0
var vehicle: VehicleController2D

func _ready() -> void:
	# A closed, rounded circuit: long straight, sweepers, technical hairpin.
	var anchors: Array[Vector2] = [Vector2(0, 700), Vector2(0, -3100), Vector2(450, -3950), Vector2(1800, -4200), Vector2(3200, -3450), Vector2(3500, -2200), Vector2(2800, -1450), Vector2(2400, -700), Vector2(2900, -150), Vector2(3650, -600), Vector2(4000, -300), Vector2(3750, 350), Vector2(2800, 1100), Vector2(1300, 1750), Vector2(250, 1500)]
	var curve := Curve2D.new()
	for i in anchors.size():
		var tangent := (anchors[(i + 1) % anchors.size()] - anchors[(i - 1 + anchors.size()) % anchors.size()]).normalized() * minf(anchors[i].distance_to(anchors[(i + 1) % anchors.size()]), anchors[i].distance_to(anchors[(i - 1 + anchors.size()) % anchors.size()])) * 0.3
		curve.add_point(anchors[i], -tangent, tangent)
	curve.add_point(anchors[0], curve.get_point_in(0), curve.get_point_out(0))
	curve.bake_interval = 35.0
	road = curve.get_baked_points()
	# Continuous outer guardrails use the same sampled centerline as the road.
	for i in range(0, road.size() - 1, 3):
		var end := mini(i + 3, road.size() - 1)
		var tangent := (road[end] - road[i]).normalized()
		var normal := tangent.orthogonal()
		for side in [-1.0, 1.0]:
			var midpoint: Vector2 = (road[i] + road[end]) * 0.5 + normal * side * 335.0
			# Open gates connecting circuit, skidpad and gravel run-off.
			if midpoint.x > 150 and midpoint.x < 2100 and midpoint.y > -200 and midpoint.y < 1250:
				continue
			barrier(midpoint, road[i].distance_to(road[end]) + 12.0, tangent.angle())
	for data in [[Vector2(-1000, -1600), 450.0, 0.0], [Vector2(2200, 650), 300.0, 0.0]]:
		barrier(data[0], data[1], data[2])
	# A finite proving ground, with room to test grass and recover from the circuit.
	barrier(Vector2(1600, -5200), 7600, 0)
	barrier(Vector2(1600, 2900), 7600, 0)
	barrier(Vector2(-2200, -1150), 8100, PI / 2)
	barrier(Vector2(5400, -1150), 8100, PI / 2)
	tire_marks = TireMarks.new()
	add_child(tire_marks)
	queue_redraw()

func barrier(point: Vector2, length: float, angle: float) -> void:
	var body := StaticBody2D.new()
	body.position = point
	body.rotation = angle
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(length, 22)
	shape.shape = box
	body.add_child(shape)
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([Vector2(-length / 2, -11), Vector2(length / 2, -11), Vector2(length / 2, 11), Vector2(-length / 2, 11)])
	visual.color = Color("b4c0b6")
	body.add_child(visual)
	add_child(body)

func surface_at(point: Vector2) -> Dictionary:
	if point.distance_to(skidpad_center) < skidpad_radius or Rect2(0, 350, 1250, 500).has_point(point):
		return {"name": "ASPHALT", "grip": 1.0}
	for i in road.size() - 1:
		if Geometry2D.get_closest_point_to_segment(point, road[i], road[i + 1]).distance_squared_to(point) < ROAD_WIDTH * ROAD_WIDTH * 0.25:
			return {"name": "ASPHALT", "grip": 1.0}
	if gravel.has_point(point):
		return {"name": "GRAVEL", "grip": 0.55}
	return {"name": "GRASS", "grip": 0.38}

func _physics_process(dt: float) -> void:
	if not vehicle:
		return
	mark_clock += dt
	if mark_clock > 0.045 and vehicle.linear_velocity.length() > 3.0:
		mark_clock = 0.0
		if absf(vehicle.slip_angle) > 0.13 or vehicle.handbrake > 0.1 or vehicle.surface != "ASPHALT":
			var right := Vector2.RIGHT.rotated(vehicle.rotation)
			var rear := vehicle.position + Vector2.DOWN.rotated(vehicle.rotation) * 25.0
			for side in [-1.0, 1.0]:
				var p: Vector2 = rear + right * side * 16.0
				tire_marks.add_mark(p, vehicle.rotation, vehicle.surface == "ASPHALT")

func text_at(point: Vector2, text: String, size := 30, color := Color("b1bba8")) -> void:
	draw_string(ThemeDB.fallback_font, point, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw() -> void:
	draw_rect(Rect2(-6500, -8500, 16000, 14500), Color("263e31"))
	# Restrained vegetation pattern, deterministic and independent of the simulation.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 1800:
		var p := Vector2(rng.randf_range(-1800, 5500), rng.randf_range(-5300, 2900))
		draw_circle(p, rng.randf_range(2, 7), Color(0.21, 0.3, 0.22, 0.55))
	draw_rect(gravel.grow(25), Color("867c63"))
	draw_rect(gravel, Color("9a8c70"))
	for i in 1100:
		var p := gravel.position + Vector2(rng.randf() * gravel.size.x, rng.randf() * gravel.size.y)
		draw_circle(p, rng.randf_range(1, 3), Color("786e5a"))
	draw_polyline(road, Color("85917f"), ROAD_WIDTH + 50, true)
	draw_polyline(road, Color("30383c"), ROAD_WIDTH, true)
	draw_circle(skidpad_center, skidpad_radius + 18, Color("85917f"))
	draw_circle(skidpad_center, skidpad_radius, Color("30383c"))
	draw_rect(Rect2(0, 350, 1250, 500), Color("30383c"))
	for radius in [260.0, 520.0, 740.0]:
		draw_arc(skidpad_center, radius, 0, TAU, 120, Color("69716d"), 2, true)
	for i in range(1, road.size() - 1):
		var direction := (road[i + 1] - road[i - 1]).normalized()
		var normal := direction.orthogonal()
		for side in [-1.0, 1.0]:
			var color := Color("d9d9c4") if (i / 3) % 2 == 0 else Color("bd583f")
			draw_line(road[i - 1] + normal * side * 244, road[i] + normal * side * 244, color, 13, true)
		if i % 4 == 0:
			draw_line(road[i], road[i] + direction * 35, Color("838b85"), 3, true)
	for row in 2:
		for col in 20:
			draw_rect(Rect2(-240 + col * 24, 80 + row * 24, 24, 24), Color("d6dbca") if (row + col) % 2 == 0 else Color("1e272a"))
	text_at(Vector2(-200, -150), "01 / LAUNCH STRAIGHT", 28)
	text_at(Vector2(-190, 260), "STREETBOUND / TEST FACILITY", 22, Color("828e86"))
	for y in [-700.0, -1400.0, -2100.0]:
		draw_polyline(PackedVector2Array([Vector2(-50, y + 50), Vector2(0, y), Vector2(50, y + 50)]), Color("869084"), 6, true)
	for i in 3:
		var point := Vector2(-290, -2800 - i * 220)
		draw_rect(Rect2(point, Vector2(35, 75)), Color("d8dbc3"))
		text_at(point + Vector2(4, 48), str(3 - i), 24, Color("263e31"))
	text_at(Vector2(900, 520), "02 / SKIDPAD", 38)
	text_at(Vector2(1000, -1050), "03 / GRAVEL", 38, Color("e4d9b8"))
	text_at(Vector2(3200, -800), "04 / HAIRPIN", 32)
	text_at(Vector2(700, -4500), "05 / HIGH-SPEED SWEEP", 34)
