extends StaticBody2D
## Lightweight cozy top-down traffic vehicle, sized like a 2m x 4m car.
## Uses no player car texture duplication, keeping AI traffic replaceable.
var car_color := Color("718899")
var accent_color := Color("e4d5b9")
var length_px := 74.0
var width_px := 35.0

func _ready() -> void:
	# Traffic collision can be enabled later without altering lane motion or
	# changing existing deterministic vehicle physics tests. The agent already
	# uses player spacing and vehicle-to-vehicle headway.
	collision_layer = 0
	collision_mask = 0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = 2
	queue_redraw()


func _draw() -> void:
	var w := width_px*0.5
	var h := length_px*0.5
	var shadow := Rect2(-w-4,-h+3,width_px+8,length_px+7)
	draw_rect(shadow,Color(0.09,0.11,0.12,0.23),true)
	# Wheels are recessed under the chassis, consistent with player wheel rig.
	for side in [-1.0,1.0]:
		draw_rect(Rect2(side*(w-2)-4,-h+10,8,17),Color("24282a"),true)
		draw_rect(Rect2(side*(w-2)-4,h-27,8,17),Color("24282a"),true)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-w+6,-h),Vector2(w-6,-h),Vector2(w,-h+9),
		Vector2(w,h-9),Vector2(w-6,h),Vector2(-w+6,h),
		Vector2(-w,h-9),Vector2(-w,-h+9)]),car_color)
	draw_rect(Rect2(-w+6,-h+17,width_px-12,20),Color("293f4a"),true)
	draw_rect(Rect2(-w+6,h-27,width_px-12,12),Color("455e68"),true)
	draw_line(Vector2(-w+4,-h+11),Vector2(w-4,-h+11),
		car_color.lightened(0.26),3.0,true)
	draw_rect(Rect2(-w+3,-h+3,7,4),Color("e9e7cf"),true)
	draw_rect(Rect2(w-10,-h+3,7,4),Color("e9e7cf"),true)
	draw_rect(Rect2(-w+3,h-6,7,4),Color("aa4040"),true)
	draw_rect(Rect2(w-10,h-6,7,4),Color("aa4040"),true)
	draw_line(Vector2(-w+5,h-12),Vector2(w-5,h-12),accent_color.darkened(0.4),2.0)
