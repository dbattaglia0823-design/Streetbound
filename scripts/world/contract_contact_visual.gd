extends Node2D
## Small top-down contact NPC. The player remains in their vehicle; the
## character is a roadside interaction point, not an on-foot controller.
const PALETTE := {
	"racing":Color("#ae5938"),
	"street":Color("#526e9e"),
	"business":Color("#3c4e57"),
	"mechanic":Color("#bb7a35"),
	"casual":Color("#778957")
}
var contact_name := "Contact"
var contact_style := "street"

func _ready() -> void:
	name="ContractContact"
	z_index=11
	queue_redraw()

func _draw() -> void:
	var coat: Color = PALETTE.get(contact_style,PALETTE.street)
	# Soft world-space pad helps readability without obstructing the road.
	draw_circle(Vector2(0,2),16.0,Color(0.04,0.08,0.10,0.55))
	draw_circle(Vector2(0,2),15.0,Color(0.92,0.67,0.28,0.38))
	draw_circle(Vector2(0,2),13.0,Color(0.06,0.10,0.13,0.68))
	# Viewed from directly above: torso/arms, head, feet and shadow.
	draw_ellipse_approx(Vector2(0,7),Vector2(8,6),Color(0.0,0.0,0.0,0.26))
	draw_line(Vector2(-4,4),Vector2(-4,10),Color("#303338"),3.5,true)
	draw_line(Vector2(4,4),Vector2(4,10),Color("#303338"),3.5,true)
	draw_rect(Rect2(-7,-5,14,13),coat)
	draw_line(Vector2(-9,-2),Vector2(-11,5),coat.darkened(0.1),3,true)
	draw_line(Vector2(9,-2),Vector2(11,5),coat.darkened(0.1),3,true)
	draw_circle(Vector2(0,-7),5.0,Color("#c99e78"))
	draw_arc(Vector2(0,-7),5.0,PI,TAU,12,Color("#2b292b"),2,true)
	# Readable interaction beacon; not an imitation of GTA artwork.
	draw_circle(Vector2(12,-18),6.0,Color("#e5b45b"))
	draw_line(Vector2(12,-21),Vector2(12,-17),Color("#242f32"),1.8,true)
	draw_circle(Vector2(12,-15),0.9,Color("#242f32"))

func draw_ellipse_approx(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 13:
		var theta := float(i) * TAU / 12.0
		points.append(center+Vector2(cos(theta)*radii.x,sin(theta)*radii.y))
	draw_colored_polygon(points,color)
