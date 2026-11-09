extends Node2D
## F4-only render of the invisible road/sidewalk/boardwalk/parcel boundaries.
## Hidden means no draw pass or geometry-generation work in normal gameplay.
const Geometry = preload("res://scripts/world/map_geometry.gd")
var world: Node2D
var chunk: Node2D
var cached_features: Array[Dictionary] = []


func set_enabled(enabled: bool) -> void:
	visible = enabled
	if enabled:
		queue_redraw()


func features() -> Array[Dictionary]:
	if cached_features.is_empty():
		cached_features = Geometry.chunk_features(chunk, world)
	return cached_features


func _draw() -> void:
	for feature in features():
		var kind: String = feature.kind
		var points: PackedVector2Array = feature.points
		var tint := Color(0.78, 0.81, 0.82, 0.76)
		var width := 3.0
		if kind == "road_edge":
			tint = Color(0.20, 0.92, 0.95, 0.93)
			width = 4.0
		elif kind == "road_center":
			tint = Color(0.22, 0.79, 0.94, 0.37)
		elif kind.begins_with("sidewalk"):
			tint = Color(1.0, 0.81, 0.30, 0.92) if kind.ends_with("outer") else Color(0.94, 0.65, 0.24, 0.37)
			width = 3.5
		elif kind == "junction":
			tint = Color(1.0, 0.29, 0.68, 0.9)
			width = 4.0
		elif kind == "corner_curb":
			tint = Color(1.0, 0.50, 0.74, 0.70)
		elif kind.begins_with("boardwalk"):
			tint = Color(0.42, 0.95, 0.39, 0.9)
		elif kind == "obstacle" or kind == "wall":
			tint = Color(1.0, 0.31, 0.22, 0.84)
		elif kind == "parcel":
			tint = Color(0.93, 0.82, 0.34, 0.58)
		elif kind.begins_with("terrain"):
			tint = Color(0.67, 0.68, 0.76, 0.33)
			width = 2.0
		if points.size() < 2:
			continue
		draw_polyline(points, tint, width, true)
		if bool(feature.closed):
			draw_line(points[points.size()-1], points[0], tint, width, true)
