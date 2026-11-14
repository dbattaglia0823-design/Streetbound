extends RefCounted
## One circular interaction shape for race staging and its visible world marker.
static func busy(race: Node) -> bool:
	if race.get_tree()==null:return false
	for other in race.get_tree().get_nodes_in_group("streetbound_race"):
		if other!=race and str(other.get("state")) in ["countdown","running"]:return true
	return false

static func draw_zone(canvas: Node2D, radius_m: float, color: Color=Color("4de6e9")) -> void:
	var radius:=radius_m*20.0
	canvas.draw_circle(Vector2.ZERO,radius,Color(color,.09))
	canvas.draw_arc(Vector2.ZERO,radius,0,TAU,80,Color(.02,.12,.16,.7),10,true)
	canvas.draw_arc(Vector2.ZERO,radius,0,TAU,80,color,4,true)
	canvas.draw_circle(Vector2.ZERO,9,color)
