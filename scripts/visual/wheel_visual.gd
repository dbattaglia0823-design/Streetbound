extends Node2D
## A small top-down rubber tire. It is intentionally a separate, swappable
## illustration; wheel pivoting only rotates this node, not the car body.
@export var tire_size := Vector2(10.0, 21.0)
@export_range(-1, 1, 2) var side := 1

func _draw() -> void:
	var box := Rect2(-tire_size * 0.5, tire_size)
	var sidewall := StyleBoxFlat.new()
	sidewall.bg_color = Color("151a1d")
	sidewall.border_color = Color("0a0e10")
	sidewall.set_border_width_all(1)
	sidewall.set_corner_radius_all(3)
	draw_style_box(sidewall, box)

	# Tire face and shoulder highlights read well at driving-camera zoom.
	var face := Rect2(Vector2(-tire_size.x * 0.27, -tire_size.y * 0.44),
		Vector2(tire_size.x * 0.54, tire_size.y * 0.88))
	draw_rect(face, Color("282e30"))
	var outer_x := float(side) * tire_size.x * 0.37
	draw_line(Vector2(outer_x, -tire_size.y * 0.37),
		Vector2(outer_x, tire_size.y * 0.37), Color(0.48, 0.52, 0.51, 0.52), 1.1, true)

	# Short tread interruptions; no 2D in-plane spinning (which would look
	# like the tire was steering rather than rolling down the road).
	for i in 4:
		var at := lerpf(-tire_size.y * 0.28, tire_size.y * 0.28, float(i) / 3.0)
		draw_line(Vector2(-tire_size.x * 0.20, at),
			Vector2(tire_size.x * 0.20, at + 1.0), Color(0.12, 0.16, 0.16, 0.58), 1.0, true)
