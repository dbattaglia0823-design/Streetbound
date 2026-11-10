extends Node2D
## Drive-in garage interaction at the existing Laurel Motor House POI.
## World-space sign is rendered with the current chunk artwork; opening
## the collection requires the player's real car to be parked in the bay.
const Geometry = preload("res://scripts/world/garage_geometry.gd")
const PPM := 20.0
const SIGN_DISTANCE_M := 70.0

var world: MorrowCoast
var player: VehicleController2D
var garage_prop: Dictionary = {}
var available := false


func _ready() -> void:
	name = "PlayerGarage"
	if is_instance_valid(world):
		garage_prop = world.player_garage_prop
	if garage_prop.is_empty():
		push_warning("Laurel Motor House garage was not found in Morrow Coast")
		return
	available = true
	position = Geometry.position_of(garage_prop) * PPM
	rotation = float(garage_prop.angle)
	z_index = 7
	queue_redraw()


func distance_m() -> float:
	if not available or not is_instance_valid(player):
		return INF
	return global_position.distance_to(player.global_position) / PPM


func inside_bay() -> bool:
	return available and is_instance_valid(player) and \
		Geometry.inside_bay(garage_prop, player.global_position)


func can_switch() -> bool:
	return available and is_instance_valid(player) and \
		Geometry.is_parked(garage_prop, player.global_position,
			player.linear_velocity.length())


func prompt() -> String:
	if not available or not is_instance_valid(player):
		return ""
	if can_switch():
		return "OPEN GARAGE  [ G ]"
	if inside_bay():
		return "STOP INSIDE GARAGE TO SWITCH"
	var distance := distance_m()
	if distance < 75.0:
		return "DRIVE INTO LAUREL GARAGE  /  %dm" % roundi(distance)
	return ""


func _draw() -> void:
	if not available:
		return
	# Permanent wayfinding paint just outside the open door. It occupies
	# world space rather than blocking the player's camera or interface.
	var size_m: Vector2 = Geometry.size_of(garage_prop)
	var entrance_x := -size_m.x * PPM * 0.5
	var arrow_origin := Vector2(entrance_x - PPM * 12.0, 0.0)
	var arrow_tip := Vector2(entrance_x - PPM * 2.0, 0.0)
	draw_line(arrow_origin, arrow_tip, Color("dec08b"), 9.0, true)
	for side in [-1.0, 1.0]:
		draw_line(arrow_tip, arrow_tip + Vector2(-PPM * 3.0, side * PPM * 2.4),
			Color("dec08b"), 8.0, true)
		for step in 4:
			var x := entrance_x - PPM * (11.0 - float(step) * 3.0)
			draw_line(Vector2(x, side * PPM * 5.8),
				Vector2(x + PPM * 1.5, side * PPM * 5.8),
				Color("ecdeb6"), 4.0, true)
	var label_pos := Vector2(entrance_x - PPM * 11.0, -PPM * 8.0)
	draw_rect(Rect2(label_pos - Vector2(16.0, 40.0),
		Vector2(PPM * 16.0, 70.0)), Color("1e383b"), true)
	draw_string(ThemeDB.fallback_font, label_pos, "GARAGE  /  DRIVE IN",
		HORIZONTAL_ALIGNMENT_LEFT, int(PPM * 14.0), 23, Color("efdcaf"))
