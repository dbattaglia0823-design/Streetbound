extends Node2D
## Dynamic race route overlay; paints metres in world or map-local space.
## Does not create physics or mutate steering/brakes.
const PPM := 20.0
const SAFE := Color(0.11, 0.90, 0.63, 0.93)
const PREPARE := Color(1.0, 0.76, 0.18, 0.95)
const BRAKE := Color(1.0, 0.25, 0.17, 0.98)
const ROUTE := Color(0.11, 0.92, 0.97, 0.94)
var navigation: RefCounted
var player: VehicleController2D
var map_view: Control
var on_map := false
var enabled := false
var _clock := 0.0


func _ready() -> void:
	if not on_map:
		top_level = true
		position = Vector2.ZERO
		z_index = 6
		# The physical car always paints over its track guidance.
	visible = false


func set_guidance(course: RefCounted, driver: VehicleController2D, show := true) -> void:
	if navigation != course or player != driver or enabled != show:
		navigation = course
		player = driver
		enabled = show
		visible = enabled and navigation != null and is_instance_valid(player)
		queue_redraw()


func _process(dt: float) -> void:
	if not enabled or navigation == null or not is_instance_valid(player):
		return
	_clock -= dt
	if _clock <= 0.0:
		_clock = 0.09
		navigation.call("update_envelope", player)
		queue_redraw()


func _on_map(point_m: Vector2) -> Vector2:
	return (point_m - map_view.center_m) * map_view.pixels_per_m + map_view.custom_minimum_size * 0.5


func _draw() -> void:
	if not enabled or navigation == null or not is_instance_valid(player):
		return
	var route: PackedVector2Array = navigation.get("points_m")
	if route.size() < 2:
		return
	if on_map:
		if not is_instance_valid(map_view):
			return
		var pixel_scale := map_view.pixels_per_m
		var size: Vector2 = map_view.custom_minimum_size
		var clip := Rect2(Vector2.ZERO, size).grow(12.0)
		var player_station: float = navigation.call("station_at", player.global_position / PPM)
		for i in range(1, route.size()):
			var a := _on_map(route[i - 1])
			var b := _on_map(route[i])
			if not clip.has_point(a) and not clip.has_point(b):
				continue
			var traveled := not bool(navigation.get("closed")) and float(
				navigation.get("stations_m")[i]) < player_station
			var color := Color(0.15, 0.48, 0.53, 0.52) if traveled else ROUTE
			draw_line(a, b, Color(0.02, 0.16, 0.23, 0.98), 6.0 if map_view.miniature else 5.0, true)
			draw_line(a, b, color, 3.2 if map_view.miniature else 2.8, true)
		# Small markers identify the actual start/finish, not nearest road.
		var start := _on_map(route[0])
		if clip.has_point(start):
			draw_circle(start, 5.0, Color(0.02, 0.15, 0.19))
			draw_circle(start, 3.0, Color(1.0, 0.92, 0.67))
		return
	var station: float = navigation.call("station_at", player.global_position / PPM)
	var length: float = navigation.get("length_m")
	var closed: bool = navigation.get("closed")
	var speed := player.linear_velocity.length()
	var lookahead := clampf(90.0 + speed * 2.6, 105.0, 230.0)
	var cursor := station
	var stop := station + (minf(lookahead, length) if closed else minf(lookahead, maxf(0.0, length - station)))
	while cursor < stop:
		var following := minf(cursor + 6.0, stop)
		var a: Vector2 = navigation.call("point_at", cursor)
		var b: Vector2 = navigation.call("point_at", following)
		var stage: int = navigation.call("braking_state", following, speed)
		var color := SAFE if stage == 0 else (PREPARE if stage == 1 else BRAKE)
		draw_line(a * PPM, b * PPM, Color(0.02, 0.12, 0.14, 0.70), 12.0, true)
		draw_line(a * PPM, b * PPM, color, 6.0, true)
		cursor = following
