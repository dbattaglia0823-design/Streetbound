extends Node2D
## Soft contact shadow stays grounded beneath the vehicle.
## Independent visual curb suspension was removed; do not read body_heave.
var vehicle: VehicleController2D
var _clock := 0.0


func _ready() -> void:
	name = "GroundShadow"
	vehicle = get_parent() as VehicleController2D
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
	var width := capsule.radius*1.2
	var length := capsule.height*0.56
	for layer in 3:
		var fade := 0.075-float(layer)*0.018
		var rx := width+float(2-layer)*5.0
		var ry := length+float(2-layer)*7.0
		var outline := PackedVector2Array()
		var offset := Vector2(6.0,9.0)
		for step in 32:
			var angle := TAU*float(step)/32.0
			outline.append(offset+Vector2(cos(angle)*rx,sin(angle)*ry))
		draw_colored_polygon(outline,Color(0.01,0.03,0.04,fade))
