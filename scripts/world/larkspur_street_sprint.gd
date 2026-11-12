extends Node2D
## Drive-up Larkspur street sprint prototype. Its route uses the actual traffic
## navigation graph; the racing line stays on the legally directed street lane.
## This is a practice run, without AI rewards or a traffic priority exemption.
const PPM := 20.0
const RacingLine = preload("res://scripts/world/race_line_builder.gd")
const NavigationScript = preload("res://scripts/world/race_navigation.gd")
const GuidanceScript = preload("res://scripts/world/race_guidance.gd")
var world: MorrowCoast
var player: VehicleController2D
var network: RefCounted
var navigation: RefCounted
var world_guidance: Node2D
var edge_ids: Array[int] = []
var available := false
var state := "idle"
var countdown := 0.0
var elapsed := 0.0
var previous_station := 0.0
var status_timer := 0.0
var start_m := Vector2.ZERO
var finish_m := Vector2.ZERO
var heading := Vector2.UP
var result := ""
var panel: PanelContainer
var label: Label


func _ready() -> void:
	name = "LarkspurStreetSprint"
	if not is_instance_valid(world) or not is_instance_valid(player) or network == null:
		return
	edge_ids = RacingLine.city_sprint_edges(network, world, world.spawn_position())
	if edge_ids.is_empty():
		push_warning("No connected directed lanes for the Larkspur sprint")
		return
	var center_course: PackedVector2Array = RacingLine.traffic_line(network, world, edge_ids)
	if center_course.size() < 40:
		push_warning("Invalid Larkspur traffic racing line")
		return
	# Start/finish on the road itself, away from busy intersections.
	var course := PackedVector2Array()
	for i in range(5, center_course.size() - 5):
		course.append(center_course[i])
	navigation = NavigationScript.new()
	navigation.call("setup", course, false)
	if float(navigation.get("length_m")) < 600.0:
		return
	start_m = course[0]
	finish_m = course[course.size() - 1]
	heading = (course[1] - course[0]).normalized()
	available = true
	position = start_m * PPM
	rotation = heading.angle() + PI / 2.0
	z_index = 5
	queue_redraw()
	world_guidance = Node2D.new()
	world_guidance.name = "StreetBrakingLine"
	world_guidance.set_script(GuidanceScript)
	world_guidance.set("player", player)
	world_guidance.set("navigation", navigation)
	add_child(world_guidance)
	var layer := CanvasLayer.new()
	layer.layer = 7
	layer.name = "StreetSprintHUD"
	add_child(layer)
	panel = PanelContainer.new()
	panel.name = "StreetSprintStatus"
	panel.position = Vector2(770, 375)
	panel.custom_minimum_size = Vector2(367, 96)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.075, 0.09, 0.94)
	style.border_color = Color("51c8d8")
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	label = Label.new()
	label.name = "SprintInstructions"
	label.add_theme_font_size_override("font_size", 16)
	panel.add_child(label)
	_refresh()


func can_stage() -> bool:
	if not available or not is_instance_valid(player) or state != "idle":
		return false
	return player.global_position.distance_to(start_m * PPM) <= 6.0 * PPM and \
		player.linear_velocity.length() <= 1.5 and \
		Vector2.UP.rotated(player.rotation).dot(heading) >= 0.6


func start_race() -> bool:
	if not can_stage() or get_tree().paused:
		return false
	state = "countdown"
	countdown = 3.0
	elapsed = 0.0
	previous_station = float(navigation.call("station_at", player.global_position / PPM))
	result = ""
	_refresh()
	return true


func _abort(message: String) -> void:
	state = "aborted"
	result = message
	status_timer = 5.0
	_refresh()


func _physics_process(dt: float) -> void:
	if not available or not is_instance_valid(player) or dt <= 0.0:
		return
	if is_instance_valid(world_guidance):
		world_guidance.call("set_guidance", navigation, player,
			state in ["countdown", "running"])
	if state == "countdown":
		if player.linear_velocity.length() > 3.0 or \
				player.global_position.distance_to(start_m * PPM) > 10.0 * PPM:
			_abort("FALSE START / RETURN TO GRID")
			return
		countdown -= dt
		if countdown <= 0.0:
			state = "running"
			previous_station = float(navigation.call("station_at", player.global_position / PPM))
	elif state == "running":
		elapsed += dt
		var station: float = navigation.call("station_at", player.global_position / PPM)
		var on_line: Vector2 = navigation.call("point_at", station)
		var advance := station - previous_station
		var maximum := maxf(3.0, player.linear_velocity.length() * dt * 2.0 + 2.0)
		# Validate actual progress, but allow wider cornering and overtaking.
		if player.global_position.distance_to(on_line * PPM) > 13.0 * PPM or \
				advance > maximum or advance < -8.0:
			_abort("RUN INVALID / FOLLOW ROAD")
			return
		previous_station = maxf(previous_station, station)
		if elapsed > 280.0:
			_abort("SPRINT TIMED OUT")
			return
		var length_m: float = navigation.get("length_m")
		if station >= length_m - 6.0 and \
				player.global_position.distance_to(finish_m * PPM) <= 13.0 * PPM:
			state = "results"
			result = "LARKSPUR SPRINT  %.2f SECONDS\nPRACTICE FINISHED / NO REWARDS" % elapsed
			status_timer = 9.0
	elif state in ["results", "aborted"]:
		status_timer -= dt
		if status_timer <= 0.0:
			state = "idle"
			result = ""
	_refresh()


func _refresh() -> void:
	if not available or label == null:
		return
	var nearby := player.global_position.distance_to(start_m * PPM) < 110.0 * PPM
	panel.visible = nearby or state != "idle"
	if not panel.visible:
		return
	match state:
		"idle":
			label.text = "LARKSPUR STREET SPRINT / PRACTICE\n%s" % (
				"STOP AT START / FACE ROUTE / [ F ]" if can_stage()
				else "DRIVE TO CYAN START LINE ON LAUREL AVENUE")
		"countdown":
			label.text = "STREET SPRINT / 3 SECOND START\nSTART IN %d" % maxi(1, ceili(countdown))
		"running":
			var fraction := previous_station / maxf(1.0, float(navigation.get("length_m")))
			label.text = "STREET SPRINT  /  %.2fs  /  %.0f%%\nFOLLOW CYAN MAP ROUTE / APEX BRAKING LINE" % [
				elapsed, clampf(fraction * 100.0, 0.0, 100.0)]
		_:
			label.text = result


func _unhandled_input(event: InputEvent) -> void:
	if not available or not event is InputEventKey or \
			not event.pressed or event.echo or get_tree().paused:
		return
	var key: InputEventKey = event
	if key.keycode == KEY_F or key.physical_keycode == KEY_F:
		if can_stage() and start_race():
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if not available:
		return
	draw_line(Vector2(-58.0, 0.0), Vector2(58.0, 0.0),
		Color("49eff4"), 6.0, true)
	draw_circle(Vector2.ZERO, 12.0, Color("073f52"))
	draw_circle(Vector2.ZERO, 7.0, Color("5df4fa"))
