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


func add_mark(point: Vector2, heading: float, asphalt: bool, track: int = 0) -> void:
	var start := point + Vector2.DOWN.rotated(heading) * 6.0
	if _track_history.has(track):
		var previous: Dictionary = _track_history[track]
		var last: Vector2 = previous.position
		var span := point.distance_to(last)
		# Do not draw an enormous stripe across teleport/reset or across
		# abrupt asphalt -> grass material changes.
		if span > 0.05 and span <= MAX_BRIDGE and bool(previous.asphalt) == asphalt:
			start = last
	_track_history[track] = {"position": point, "asphalt": asphalt}

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
	multimesh.set_instance_transform_2d(next_slot,
		Transform2D(axis_x, axis_y, (a + b) * 0.5))
	multimesh.set_instance_color(next_slot,
		Color(0.06, 0.08, 0.09, 0.50) if asphalt else Color(0.36, 0.28, 0.19, 0.46))
	next_slot = (next_slot + 1) % CAPACITY
	count = mini(count + 1, CAPACITY)
	multimesh.visible_instance_count = count
