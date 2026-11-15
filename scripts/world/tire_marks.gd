class_name TireMarks2D
extends Node2D
## Connected tyre-contact paths with proper round joins, not overlapping quads.
## Path coordinates live in world space and do not depend on streamed chunks.
## At most CAPACITY total vertices / MAX_TRAILS lines are kept; older marks
## are recycled, including when a long drift crosses the chunk boundaries.
## Each section stays fully visible for 20 seconds from its last contact,
## then fades over four seconds before its Line2D node is released.
const CAPACITY := 1800
const MAX_TRAILS := 30
const POINTS_PER_TRAIL := 80
const STRIP_WIDTH := 7.0
const MIN_SAMPLE_DISTANCE := 1.4
const MAX_SAMPLE_SPACING := 20.0
const MAX_BRIDGE := 220.0
const VISIBLE_SECONDS := 20.0
const FADE_SECONDS := 4.0

var count := 0
var _points_used := 0
var _trails: Array[Line2D] = []
var _active: Dictionary = {}
var _elapsed_seconds := 0.0
var _last_contact_seconds: Dictionary = {}
# Public diagnostics retained for the driving/visual integration tests.
var last_strip_start := Vector2.ZERO
var last_strip_end := Vector2.ZERO
var last_strip_color := Color.TRANSPARENT
var last_strip_track := -1


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Road layers render at z=1..3; tyre ink must sit ON the pavement.
	z_index = 4


func _process(delta: float) -> void:
	# Normal world pause semantics stop the clock while the game is paused.
	_elapsed_seconds += maxf(0.0, delta)
	for index in range(_trails.size() - 1, -1, -1):
		var line: Line2D = _trails[index]
		var age := _elapsed_seconds - float(_last_contact_seconds.get(line, _elapsed_seconds))
		if age >= VISIBLE_SECONDS + FADE_SECONDS:
			_remove_trail(line)
			continue
		var opacity := 1.0 - clampf((age - VISIBLE_SECONDS) / FADE_SECONDS, 0.0, 1.0)
		if not is_equal_approx(line.modulate.a, opacity):
			var tint := line.modulate
			tint.a = opacity
			line.modulate = tint


func reset_tracks() -> void:
	# Break current paths without erasing already drawn, bounded marks.
	_active.clear()


static func ink_for_surface(surface: String) -> Color:
	match surface:
		"GRAVEL":
			return Color(.31, .27, .20, .39)
		"DIRT":
			return Color(.30, .22, .14, .43)
		"SAND":
			return Color(.43, .36, .24, .29)
		"GRASS":
			return Color(.21, .25, .13, .29)
		_:
			return Color(.055, .064, .067, .67)


func _new_trail(point: Vector2, kind: String, track: int, strength: float) -> Line2D:
	var line := Line2D.new()
	line.name = "Tire_%d_%d" % [track, count]
	line.width = STRIP_WIDTH
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.round_precision = 7
	# Bounded to 30 short lines so 2D AA draw overhead stays predictable.
	line.antialiased = true
	var ink := ink_for_surface(kind)
	ink.a *= lerpf(0.66, 1.0, clampf(strength, 0.0, 1.0))
	line.default_color = ink
	line.add_point(point)
	add_child(line)
	_trails.append(line)
	_last_contact_seconds[line] = _elapsed_seconds
	_points_used += 1
	_active[track] = {"line": line, "position": point, "kind": kind}
	last_strip_start = point
	last_strip_end = point
	last_strip_color = ink
	last_strip_track = track
	count += 1
	_evict_old_trails()
	return line


func _remove_trail(line: Line2D) -> void:
	_trails.erase(line)
	_last_contact_seconds.erase(line)
	_points_used -= line.get_point_count()
	for track in _active.keys():
		if _active[track].line == line:
			_active.erase(track)
	remove_child(line)
	line.queue_free()


func _evict_old_trails() -> void:
	while _trails.size() > MAX_TRAILS or _points_used > CAPACITY:
		_remove_trail(_trails[0])


func add_mark(point: Vector2, heading: float, asphalt: bool, track: int = 0,
		surface: String = "", strength: float = 1.0) -> void:
	var kind := surface if not surface.is_empty() else ("ASPHALT" if asphalt else "GRASS")
	last_strip_track = track
	# Never reconnect to an old section that has begun fading.
	if _active.has(track):
		var previous: Line2D = _active[track].line
		if _elapsed_seconds - float(_last_contact_seconds.get(previous, _elapsed_seconds)) >= VISIBLE_SECONDS:
			_active.erase(track)
	if not _active.has(track) or str(_active[track].kind) != kind:
		_new_trail(point,kind,track,strength)
		return
	var history: Dictionary = _active[track]
	var from: Vector2 = history.position
	var span := point.distance_to(from)
	if span > MAX_BRIDGE:
		_new_trail(point,kind,track,strength)
		return
	if span < MIN_SAMPLE_DISTANCE:
		return
	var line: Line2D = history.line
	# Continuity across sharp bends is guaranteed by the Line2D mesh join.
	# Sample dense enough to represent a real tyre path rather than an
	# angular approximation of the car's physics pivot.
	var steps := maxi(1, ceili(span/MAX_SAMPLE_SPACING))
	for i in range(1,steps+1):
		var sample: Vector2 = from.lerp(point,float(i)/float(steps))
		if line.get_point_count() >= POINTS_PER_TRAIL:
			# Carry the exact previous endpoint into the next bounded line.
			# Round caps close the join with no visible seam.
			line = _new_trail(line.get_point_position(
				line.get_point_count()-1),kind,track,strength)
		line.add_point(sample)
		_last_contact_seconds[line] = _elapsed_seconds
		_points_used += 1
		_evict_old_trails()
	last_strip_start = from
	last_strip_end = point
	last_strip_color = line.default_color
	_active[track] = {"line":line,"position":point,"kind":kind}


func trail_count() -> int:
	return _trails.size()


func point_count() -> int:
	return _points_used


func active_line(track: int) -> Line2D:
	return _active.get(track,{}).get("line",null) as Line2D
