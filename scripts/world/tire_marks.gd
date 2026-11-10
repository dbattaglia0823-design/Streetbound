class_name TireMarks2D
extends MultiMeshInstance2D
## A fixed GPU-backed pool of continuous tire-track strips. Each stamp spans
## the distance between successive wheel samples instead of making a box.
const CAPACITY := 1800
const STRIP_WIDTH := 6.0
const END_OVERLAP := 1.4
const MAX_BRIDGE := 220.0
var next_slot := 0
var count := 0
var _track_history: Dictionary = {}
# CPU-side last generated segment, usable for tests and visual debugging even
# with the headless RenderingServer (which does not read back GPU instances).
var last_strip_start := Vector2.ZERO
var last_strip_end := Vector2.ZERO
var last_strip_color := Color.TRANSPARENT
var last_strip_track := -1


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0


func reset_tracks() -> void:
	# Break the path when a drift ends, the car stops or steering is reset.
	# Old marks stay in the bounded GPU pool.
	_track_history.clear()


static func ink_for_surface(surface: String) -> Color:
	match surface:
		"GRAVEL":
			return Color(.33, .28, .22, .40)
		"DIRT":
			return Color(.32, .24, .15, .45)
		"SAND":
			return Color(.48, .40, .27, .27)
		"GRASS":
			return Color(.21, .25, .13, .27)
		_:
			return Color(.06, .08, .09, .50)

func add_mark(point: Vector2, heading: float, asphalt: bool, track: int = 0, surface: String = "") -> void:
	var kind := surface if not surface.is_empty() else ("ASPHALT" if asphalt else "GRASS")
	var start := point + Vector2.DOWN.rotated(heading) * 6.0
	if _track_history.has(track):
		var previous: Dictionary = _track_history[track]
		var last: Vector2 = previous.position
		var span := point.distance_to(last)
		# Do not draw an enormous stripe across teleport/reset or across
		# abrupt asphalt -> grass material changes.
		if span > 0.05 and span <= MAX_BRIDGE and str(previous.kind) == kind:
			start = last
	_track_history[track] = {"position": point, "kind": kind}

	var displacement := point - start
	var length := displacement.length()
	if length < 0.05:
		# Keep the pool and tests deterministic, even with a parked test car.
		displacement = Vector2.UP.rotated(heading) * 1.5
		length = displacement.length()
	var direction := displacement / length
	# Tiny overlap closes hairline gaps between adjacent oriented quads
	# when the tire sweeps around a bend; no isolated rectangle stamps.
	var a := start - direction * END_OVERLAP
	var b := point + direction * END_OVERLAP
	var axis_y := b - a
	var axis_x := direction.orthogonal() * STRIP_WIDTH
	var ink := ink_for_surface(kind)
	last_strip_start = a
	last_strip_end = b
	last_strip_color = ink
	last_strip_track = track
	multimesh.set_instance_transform_2d(next_slot,
		Transform2D(axis_x, axis_y, (a + b) * 0.5))
	multimesh.set_instance_color(next_slot, ink)
	next_slot = (next_slot + 1) % CAPACITY
	count = mini(count + 1, CAPACITY)
	multimesh.visible_instance_count = count
