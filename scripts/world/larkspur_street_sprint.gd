extends Node2D
## Drive-up Larkspur street sprint prototype. Its route uses the actual traffic
## navigation graph; the racing line stays on the legally directed street lane.
## This is a practice run, without AI rewards or a traffic priority exemption.
const PPM := 20.0
const RacingLine = preload("res://scripts/world/race_line_builder.gd")
const NavigationScript = preload("res://scripts/world/race_navigation.gd")
const GuidanceScript = preload("res://scripts/world/race_guidance.gd")
const VehicleScene = preload("res://scenes/vehicle.tscn")
const RacerDriverScript = preload("res://scripts/world/race_ai_driver.gd")
var world: MorrowCoast
var player: VehicleController2D
var network: RefCounted
var traffic: Node
var opponent: VehicleController2D
var opponent_driver: Node
var opponent_station_m := 0.0
var opponent_elapsed := -1.0
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
	if not _spawn_opponent():
		return false
	if is_instance_valid(traffic):
		traffic.call("set_street_race_route", navigation, edge_ids, true)
	player.add_to_group("race_participant")
	state = "countdown"
	countdown = 3.0
	elapsed = 0.0
	previous_station = float(navigation.call("station_at", player.global_position / PPM))
	opponent_station_m = 0.0
	opponent_elapsed = -1.0
	result = ""
	_refresh()
	return true



## Spawn the same configured/tuned physical car as the player. The AI starts
## behind the grid on a real street instead of appearing alongside on the
## oncoming lane; passing is earned on pavement after the countdown.
func _spawn_opponent() -> bool:
	_clear_opponent()
	if not is_instance_valid(player) or not is_instance_valid(world):
		return false
	var start_px := (start_m - heading * 12.0) * PPM
	if str(world.surface_at(start_px).name) != "ASPHALT":
		return false
	if is_instance_valid(traffic):
		var traffic_agents: Array = traffic.get("agents")
		for agent in traffic_agents:
			var node: Node2D = agent.get("node")
			if is_instance_valid(node) and node.global_position.distance_to(start_px) < 5.5 * PPM:
				return false
	opponent = VehicleScene.instantiate() as VehicleController2D
	if opponent == null:
		return false
	opponent.name = "LarkspurRaceRival"
	opponent.external_input = true
	opponent.surface_provider = world
	opponent.config = player.config.duplicate(true)
	opponent.collision_layer = 1
	opponent.collision_mask = 3
	opponent.z_index = 8
	opponent.add_to_group("race_opponent")
	opponent.add_to_group("race_participant")
	add_child(opponent)
	opponent.global_position = start_px
	opponent.global_rotation = heading.angle() + PI * 0.5
	opponent.reset_physics_interpolation()
	var source_wheels := player.get_node_or_null("Art/Wheels")
	var rival_wheels := opponent.get_node_or_null("Art/Wheels")
	if source_wheels != null and rival_wheels != null:
		var profile := source_wheels.get("appearance") as Resource
		if profile != null:
			rival_wheels.call("apply_appearance", profile.duplicate(true))
	var source_shape := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var rival_shape := opponent.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if source_shape != null and rival_shape != null and source_shape.shape != null:
		rival_shape.shape = source_shape.shape.duplicate(true)
	var sprite := opponent.get_node_or_null("Art/Sprite") as Sprite2D
	if sprite != null:
		sprite.modulate = Color(0.83, 0.66, 1.0)
	opponent_driver = Node.new()
	opponent_driver.name = "CityRaceDriver"
	opponent_driver.set_script(RacerDriverScript)
	add_child(opponent_driver)
	opponent_driver.call("setup_navigation", opponent, navigation)
	opponent_driver.call("enable_race_traffic", world, traffic)
	opponent_driver.set("reaction_seconds", 0.40)
	opponent_driver.set("throttle_limit", 0.96)
	move_child(opponent_driver, 0)
	return true


func _clear_opponent() -> void:
	if is_instance_valid(opponent_driver):
		opponent_driver.call("stop")
		opponent_driver.queue_free()
	if is_instance_valid(opponent):
		opponent.collision_layer = 0
		opponent.collision_mask = 0
		opponent.hide()
		opponent.queue_free()
	opponent = null
	opponent_driver = null


func _finish_race() -> void:
	if is_instance_valid(opponent_driver):
		opponent_driver.call("stop")
	if is_instance_valid(traffic):
		traffic.call("set_street_race_route", null, Array[int](), false)
	if is_instance_valid(player):
		player.remove_from_group("race_participant")


func _update_opponent() -> void:
	if not is_instance_valid(opponent) or opponent_elapsed >= 0.0:
		return
	var position_m := opponent.global_position / PPM
	var station: float = navigation.call("station_at", position_m)
	var on_line: Vector2 = navigation.call("point_at", station)
	if position_m.distance_to(on_line) > 15.0:
		return
	opponent_station_m = maxf(opponent_station_m, station)
	if station >= float(navigation.get("length_m")) - 6.0 and \
			position_m.distance_to(finish_m) <= 13.0:
		opponent_elapsed = elapsed
		if is_instance_valid(opponent_driver):
			opponent_driver.call("stop")


func _abort(message: String) -> void:
	_finish_race()
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
			if is_instance_valid(opponent_driver):
				opponent_driver.call("launch")
			previous_station = float(navigation.call("station_at", player.global_position / PPM))
	elif state == "running":
		elapsed += dt
		_update_opponent()
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
			_finish_race()
			state = "results"
			if opponent_elapsed >= 0.0 and opponent_elapsed <= elapsed:
				result = "RIVAL WINS / %.2f s  |  YOU %.2f s\nSTREET PRACTICE / NO REWARDS" % [opponent_elapsed,elapsed]
			else:
				result = "YOU WIN / %.2f s  |  RIVAL %s\nSTREET PRACTICE / NO REWARDS" % [
					elapsed, "%.2f s" % opponent_elapsed if opponent_elapsed >= 0.0 else "DNF"]
			status_timer = 9.0
	elif state in ["results", "aborted"]:
		status_timer -= dt
		if status_timer <= 0.0:
			_clear_opponent()
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
			var rival := opponent_station_m / maxf(1.0, float(navigation.get("length_m")))
			var maneuver := str(opponent_driver.get("traffic_mode")) if is_instance_valid(opponent_driver) else "clear"
			label.text = "STREET SPRINT  %.2fs  /  YOU %.0f%%  AI %.0f%%\nTRAFFIC ACTIVE / AI %s / FOLLOW CYAN ROUTE" % [
				elapsed,clampf(fraction * 100.0, 0.0, 100.0),
				clampf(rival * 100.0, 0.0, 100.0),maneuver.to_upper()]
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
