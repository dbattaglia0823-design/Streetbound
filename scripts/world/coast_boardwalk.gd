extends Node2D
## A chunk-clipped wooden beach promenade, derived from the authored coast.
## No extra physics or props, and no gaps when 192m chunks stream in/out.
const Walkways = preload("res://scripts/world/urban_walkways.gd")
const PPM := 20.0
const DECK_WIDTH := 112.0
var world: Node2D
var origin_m := Vector2.ZERO


func _draw() -> void:
	if world.boardwalk_path.size() < 2:
		return
	# Include extra metres on each side so a deck crossing chunk boundaries
	# retains its full width and parallel rails without visible seams.
	var rectangle := Rect2(origin_m - Vector2.ONE * 8.0,
		Vector2.ONE * (world.chunk_m + 16.0))
	var outline := PackedVector2Array([
		rectangle.position,
		Vector2(rectangle.end.x, rectangle.position.y),
		rectangle.end,
		Vector2(rectangle.position.x, rectangle.end.y)
	])
	var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polyline_with_polygon(
		world.boardwalk_path, outline)
	for piece in clipped:
		if piece.size() < 2:
			continue
		var path := PackedVector2Array()
		for p in piece:
			path.append((p - origin_m) * PPM)
		# Deep footing, warm deck edge, and uninterrupted plank surface.
		draw_polyline(path, Color(0.25, 0.26, 0.21, 0.20), DECK_WIDTH + 32, true)
		draw_polyline(path, Color("866f53"), DECK_WIDTH + 9, true)
		draw_polyline(path, Color("c5a77e"), DECK_WIDTH, true)
		for side in [-1.0, 1.0]:
			var edge := Walkways.offset(path, side * (DECK_WIDTH * 0.5 - 7.0))
			draw_polyline(edge, Color("e0c49a"), 4.0, true)

		# Board seams use global Y (metres), not local chunk distance, so
		# the rhythm continues even as the path is clipped or reloaded.
		for i in range(1, piece.size()):
			var a: Vector2 = piece[i - 1]
			var b: Vector2 = piece[i]
			if absf(b.y - a.y) < 0.001:
				continue
			var tangent := (b - a).normalized()
			var normal := tangent.orthogonal()
			var low := ceili(minf(a.y, b.y) / 2.8)
			var high := floori(maxf(a.y, b.y) / 2.8)
			for k in range(low, high + 1):
				var t := (float(k) * 2.8 - a.y) / (b.y - a.y)
				if t < 0.0 or t > 1.0:
					continue
				var center := (a.lerp(b, t) - origin_m) * PPM
				draw_line(center - normal * (DECK_WIDTH * 0.5 - 10.0),
					center + normal * (DECK_WIDTH * 0.5 - 10.0),
					Color(0.38, 0.29, 0.21, 0.23), 2.0, true)

				# Low-profile safety posts on the ocean-facing rail. The
				# coastline runs north to south, so -normal faces east.
				if k % 4 == 0:
					var seaward := center - normal * (DECK_WIDTH * 0.5 + 2.0)
					draw_circle(seaward + Vector2(5, 7), 6.0, Color(0.13, 0.17, 0.16, 0.22))
					draw_circle(seaward, 4.2, Color("dbc7a4"))
		var rail := Walkways.offset(path, -(DECK_WIDTH * 0.5 + 2.0))
		draw_polyline(rail, Color("695941"), 7.0, true)
		draw_polyline(rail, Color("d9c299"), 3.0, true)
