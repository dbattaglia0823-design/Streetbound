extends AnimatableBody2D
## Cozy top-down AI traffic vehicle with a physical collision silhouette.
## Cars are driven by TrafficWorld on the physics tick, not by player input.
var color := Color("8193a1")
var accent := Color("dee4e3")
var brake_light := false
var type_index := 0

func _ready() -> void:
	collision_layer = 1 # Player CharacterBody collision_mask=1
	collision_mask = 0
	sync_to_physics = false
	z_index = 5
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(31, 65)
	collision.shape = shape
	add_child(collision)
	queue_redraw()


func set_braking(braking: bool) -> void:
	if brake_light != braking:
		brake_light = braking
		queue_redraw()


func _draw() -> void:
	var length := 74.0
	var width := 36.0
	if type_index == 1:
		length = 84.0
		width = 39.0
	elif type_index == 2:
		length = 63.0
		width = 32.0
	# Low-profile shadow and black rubber peek just outside the wheel wells.
	draw_rect(Rect2(-width * .54 + 3.0, -length * .48 + 6.0,
		width * 1.08, length * .96), Color(0.04, 0.07, 0.08, 0.23), true)
	for side in [-1.0, 1.0]:
		for y in [-length * .28, length * .31]:
			draw_rect(Rect2(side * width * .46 - 3.0, y - 11.0, 6.0, 22.0),
				Color("222b31"), true)
	# Rounded silhouettes with simple layered reflections.
	draw_rect(Rect2(-width*.5,-length*.5,width,length),Color("293940"),true)
	draw_rect(Rect2(-width*.5+2,-length*.5+2,width-4,length-4),
		color,true)
	draw_rect(Rect2(-width*.43,-length*.35,width*.86,length*.22),
		Color("334c57"),true)
	draw_rect(Rect2(-width*.41,length*.08,width*.82,length*.20),
		Color("415e68"),true)
	draw_line(Vector2(-width*.35,-length*.47),Vector2(width*.35,-length*.47),
		accent,2.0,true)
	draw_line(Vector2(-width*.40,-length*.05),Vector2(width*.40,-length*.05),
		color.lightened(.25),1.3,true)
	for side in [-1.0,1.0]:
		draw_rect(Rect2(side*width*.38-4.0,-length*.47,8,4),
			Color("f7eee0"),true)
		draw_rect(Rect2(side*width*.38-4.0,length*.42,8,4),
			Color("ff4e46") if brake_light else Color("a4403c"),true)
