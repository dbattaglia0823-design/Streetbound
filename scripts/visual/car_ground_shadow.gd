extends Node2D
## Soft contact shadow is anchored to the road, not the lifted Art subtree.
## Height and impact only change its subtle offset/opacity; no light nodes.
var vehicle: VehicleController2D
var art: Node2D
var _clock := 0.0


func _ready() -> void:
	name = "GroundShadow"
	vehicle = get_parent() as VehicleController2D
	art = vehicle.get_node_or_null("Art")
	z_index = -2


func _process(dt: float) -> void:
	_clock += maxf(0.0,dt)
	if _clock >= 0.035:
		_clock = 0.0
		queue_redraw()


func _draw() -> void:
	if not is_instance_valid(vehicle):
		return
	var body: CollisionShape2D = vehicle.get_node_or_null("CollisionShape2D")
	if not is_instance_valid(body) or not body.shape is CapsuleShape2D:
		return
	var capsule := body.shape as CapsuleShape2D
	# The shadow follows the damped CHASSIS height, not the instant wheel
	# height. A high curb compresses the wheels before the body catches up.
	var height := clampf(float(art.get("body_heave")) if is_instance_valid(art) else 0.0, 0.0, 1.0)
	var width := capsule.radius*1.2
	var length := capsule.height*0.56
	for layer in 3:
		var fade := (1.0-height*0.40)*(0.075-float(layer)*0.018)
		var rx := width+float(2-layer)*5.0
		var ry := length+float(2-layer)*7.0
		var outline := PackedVector2Array()
		var offset := Vector2(6.0+height*4.0,9.0+height*6.0)
		for step in 32:
			var angle := TAU*float(step)/32.0
			outline.append(offset+Vector2(cos(angle)*rx,sin(angle)*ry))
		draw_colored_polygon(outline,Color(0.01,0.03,0.04,fade))
