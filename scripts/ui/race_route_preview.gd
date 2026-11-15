extends Control
## Decorative, data-driven race graphic: harbor-style skyline behind a route
## reconstructed from the event's actual navigation points (never a fake map).
var route_m := PackedVector2Array()
var closed := false

func set_course(points: PackedVector2Array, is_loop: bool = false) -> void:
	route_m = points.duplicate()
	closed = is_loop
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	if size.x < 16.0 or size.y < 16.0:
		return
	draw_rect(rect, Color("#0b1723"))
	# Contrasting skyline/roadway accents make this a race card even offline.
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, size.y * .42)), Color("#1e3449"))
	draw_rect(Rect2(Vector2(0, size.y * .42), Vector2(size.x, size.y * .28)),
		Color("#162a36"))
	draw_rect(Rect2(Vector2(0, size.y * .70), Vector2(size.x, size.y * .30)),
		Color("#0b1b27"))
	draw_line(Vector2(0, size.y * .59), Vector2(size.x, size.y * .59),
		Color("#e38a4e", .26), 2.0, true)
	for i in 14:
		var x: float = i * (size.x / 13.0)
		var h: float = 18.0 + float((i * 31 + 7) % 38)
		draw_rect(Rect2(x, size.y * .62 - h, size.x / 17.0, h),
			Color("#0c1b28"))
		for j in 2:
			draw_rect(Rect2(x + 4 + j * 8, size.y * .62 - h + 7,
				2.0, 2.0), Color("#d2a470", .50))
	# A subtle cartographic grid on the right frames the actual route.
	var map_bounds := Rect2(Vector2(size.x * .50, 10),
		Vector2(size.x * .46, size.y - 20))
	draw_rect(map_bounds, Color("#0b1a25", .83), true)
	for i in 5:
		var xx: float = map_bounds.position.x + i * map_bounds.size.x / 4.0
		draw_line(Vector2(xx, map_bounds.position.y),
			Vector2(xx, map_bounds.end.y), Color("#395467", .24), 1.0, true)
	for j in 5:
		var yy: float = map_bounds.position.y + j * map_bounds.size.y / 4.0
		draw_line(Vector2(map_bounds.position.x, yy),
			Vector2(map_bounds.end.x, yy), Color("#395467", .24), 1.0, true)
	var path: PackedVector2Array = route_m
	if path.size() < 2:
		return
	var bounds := Rect2(path[0], Vector2.ZERO)
	for p in path:
		bounds = bounds.expand(p)
	var span := bounds.size
	var scale_value: float = minf((map_bounds.size.x - 20) / maxf(1.0, span.x),
		(map_bounds.size.y - 22) / maxf(1.0, span.y))
	var middle: Vector2 = bounds.get_center()
	var center: Vector2 = map_bounds.get_center()
	var projected := PackedVector2Array()
	for p in path:
		projected.append(center + (p - middle) * scale_value)
	if closed and projected.size() > 2:
		projected.append(projected[0])
	# Dark route underpainting retains contrast over roads and silhouettes.
	draw_polyline(projected, Color("#07111b", .98), 8.0, true)
	draw_polyline(projected, Color("#ff8e3f", .38), 6.0, true)
	draw_polyline(projected, Color("#ffae5e"), 3.0, true)
	draw_circle(projected[0], 5.6, Color("#e8f6f5"))
	draw_circle(projected[0], 2.7, Color("#3bd9dd"))
	var finish: Vector2 = projected[projected.size() - 1]
	if closed:
		finish = projected[0]
	draw_circle(finish, 5.5, Color("#fcbd67"))
	draw_line(finish, finish + Vector2(0, -14), Color("#f5f0e5"), 2, true)
	draw_colored_polygon(PackedVector2Array([
		finish + Vector2(0, -14), finish + Vector2(12, -11),
		finish + Vector2(0, -7)]), Color("#f5f0e5"))
