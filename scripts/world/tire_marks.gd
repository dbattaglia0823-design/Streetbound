class_name TireMarks2D
extends MultiMeshInstance2D
## A fixed GPU instance pool: two O(1) writes per sample, no world redraws,
## array slicing, per-mark nodes or draw-command rebuilding as tracks accumulate.
const CAPACITY := 1800
var next_slot := 0
var count := 0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(6, 18)
	multimesh.mesh = quad
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0

func add_mark(point: Vector2, heading: float, asphalt: bool) -> void:
	var center := point + Vector2.UP.rotated(heading) * 9
	multimesh.set_instance_transform_2d(next_slot, Transform2D(heading, center))
	multimesh.set_instance_color(next_slot, Color(0.06, 0.08, 0.09, 0.5) if asphalt else Color(0.59, 0.52, 0.36, 0.45))
	next_slot = (next_slot + 1) % CAPACITY
	count = mini(count + 1, CAPACITY)
	multimesh.visible_instance_count = count
