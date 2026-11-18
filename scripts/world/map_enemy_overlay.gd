extends Node2D
## Small live enemy dots in the circular/square driving minimap.
## Race cars already belong to "race_opponent" and are shown only while
## their owning race is running or counting down. Future roaming enemies
## opt in by joining the "minimap_enemy" group (no HUD changes required).
const PPM := 20.0
const DOT_RADIUS := 3.0
const BORDER_RADIUS := 4.0
const DOT_COLOR := Color("#f14950")
const BORDER_COLOR := Color("#3b1119")

var map_view: Control
var races: Array[Node2D] = []
var _was_visible := false


static func map_position(world_position_px: Vector2, map_center_m: Vector2,
		pixels_per_m: float, dimensions: Vector2) -> Vector2:
	return (world_position_px / PPM - map_center_m) * pixels_per_m + dimensions * 0.5


static func within_map(point: Vector2, dimensions: Vector2, shape: String) -> bool:
	# Keep the entire dot inside the rectangular map or circular alpha mask.
	var padding := BORDER_RADIUS + 1.0
	if not Rect2(Vector2.ONE * padding,
			dimensions - Vector2.ONE * (padding * 2.0)).has_point(point):
		return false
	if shape == "circle":
		return point.distance_to(dimensions * 0.5) <= minf(
			dimensions.x, dimensions.y) * 0.5 - padding
	return true


func _active_race_opponent(target: Node2D) -> bool:
	for race in races:
		if not is_instance_valid(race) or race.is_queued_for_deletion():
			continue
		# Do not show unrelated rivals waiting in another race's results state.
		if race.is_ancestor_of(target) and str(race.get("state")) in [
				"countdown", "running"]:
			return true
	return false


func visible_enemy_positions() -> PackedVector2Array:
	var positions := PackedVector2Array()
	if not is_instance_valid(map_view) or not bool(map_view.get("miniature")):
		return positions
	var dimensions: Vector2 = map_view.custom_minimum_size
	var center: Vector2 = map_view.get("center_m")
	var scale: float = float(map_view.get("pixels_per_m"))
	var shape: String = str(map_view.get("minimap_shape"))
	var seen := {}
	# Race opponents are already tagged by the race systems. The second group
	# is the public registration point for future roaming/hostile vehicles.
	for group_name in ["race_opponent", "minimap_enemy"]:
		for candidate in get_tree().get_nodes_in_group(group_name):
			if not candidate is Node2D:
				continue
			var enemy := candidate as Node2D
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or \
					not enemy.is_inside_tree() or not enemy.is_visible_in_tree():
				continue
			var id := enemy.get_instance_id()
			if seen.has(id):
				continue
			seen[id] = true
			if not enemy.is_in_group("minimap_enemy") and \
					not _active_race_opponent(enemy):
				continue
			var at := map_position(enemy.global_position, center, scale, dimensions)
			if within_map(at, dimensions, shape):
				positions.append(at)
	return positions


func _process(_dt: float) -> void:
	if not is_instance_valid(map_view):
		return
	var has_dots := not visible_enemy_positions().is_empty()
	# Redraw while enemies are on the map, and once more as the last one
	# disappears. Moving dots therefore track every rendered frame.
	if has_dots or _was_visible:
		queue_redraw()
	_was_visible = has_dots


func _draw() -> void:
	for at in visible_enemy_positions():
		draw_circle(at, BORDER_RADIUS, BORDER_COLOR)
		draw_circle(at, DOT_RADIUS, DOT_COLOR)
