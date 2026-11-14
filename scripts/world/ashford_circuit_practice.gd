extends Node2D
## Drive-up circuit test lap. No economy payouts in this first guidance pass:
## the player must follow the whole authored course and physically cross start.
const PPM := 20.0
const NavigationScript = preload("res://scripts/world/race_navigation.gd")
const GuidanceScript = preload("res://scripts/world/race_guidance.gd")
const StatusStripScript = preload("res://scripts/ui/race_status_strip.gd")
const RacingLine = preload("res://scripts/world/race_line_builder.gd")
const ROAD_NAME := "Ashford Grand Circuit"
const StartArea=preload("res://scripts/world/race_start_area.gd")
var race_title:="Ashford Circuit"
var race_type:="Circuit · Time Trial"
var start_radius_m:=8.0
var world: MorrowCoast
var player: VehicleController2D
var navigation: RefCounted
var world_guidance: Node2D
var state := "idle"
var available := false
var countdown := 0.0
var elapsed := 0.0
var distance_m := 0.0
var previous_station := 0.0
var status_timer := 0.0
var result := ""
var start_m := Vector2.ZERO
var heading := Vector2.UP
var status_strip: Control
var panel: PanelContainer
var label: Label


func _ready() -> void:
	name = "AshfordCircuitPractice"
	if not is_instance_valid(world) or not is_instance_valid(player):
		return
	var full_path := PackedVector2Array()
	var first_path := PackedVector2Array()
	var track_width_m := 14.0
	# The four track road pieces are baked in connected lap order.
	for road in world.data.roads:
		if str(road.name) != ROAD_NAME:
			continue
		track_width_m = float(road.width)
		var path := PackedVector2Array()
		for raw in road.points:
			path.append(Vector2(float(raw[0]), float(raw[1])))
		if path.size() < 2:
			continue
		if first_path.is_empty():
			first_path = path
			full_path = path
		elif full_path[full_path.size() - 1].distance_to(path[0]) < 3.0:
			for i in range(1, path.size()):
				full_path.append(path[i])
		elif full_path[full_path.size() - 1].distance_to(path[path.size() - 1]) < 3.0:
			path.reverse()
			for i in range(1, path.size()):
				full_path.append(path[i])
		else:
			push_warning("Ashford circuit pieces are disconnected; lap unavailable")
			return
	if first_path.size() < 10 or full_path.size() < 20 or \
			full_path[0].distance_to(full_path[full_path.size() - 1]) > 3.0:
		push_warning("Ashford circuit does not form a closed lap")
		return
	# Place the interaction on the actual painted track start marker,
	# not in the paddock or at an arbitrary road waypoint.
	var start_index := 8
	var ordered := PackedVector2Array()
	for i in range(start_index, full_path.size() - 1):
		ordered.append(full_path[i])
	for i in range(0, start_index + 1):
		ordered.append(full_path[i])
	navigation = NavigationScript.new()
	# Track centerline comes from the actual authored road. Move within the
	# usable baked track pavement for a consistent outside-apex-outside driving line.
	navigation.call("setup", RacingLine.circuit_line(ordered, track_width_m, world), true)
	if float(navigation.get("length_m")) < 1000.0:
		push_warning("Ashford circuit lap is too short")
		return
	start_m = ordered[0]
	heading = (ordered[1] - ordered[0]).normalized()
	available = true
	add_to_group("streetbound_race")
	position=start_m*PPM;z_index=5;queue_redraw()
	world_guidance = Node2D.new()
	world_guidance.name = "CircuitBrakingLine"
	world_guidance.set_script(GuidanceScript)
	world_guidance.set("player", player)
	world_guidance.set("navigation", navigation)
	add_child(world_guidance)
	var layer := CanvasLayer.new()
	layer.name = "CircuitRaceHUD"
	layer.layer = 7
	add_child(layer)
	status_strip = Control.new()
	status_strip.set_script(StatusStripScript)
	layer.add_child(status_strip)
	panel = status_strip.get("panel") as PanelContainer
	label = status_strip.get("label") as Label
	_refresh()


func _station() -> float:
	return float(navigation.call("station_at", player.global_position / PPM))


func _deviation(station: float) -> float:
	var point: Vector2 = navigation.call("point_at", station)
	return player.global_position.distance_to(point * PPM) / PPM


func can_stage() -> bool:
	if not available or state != "idle" or not is_instance_valid(player):
		return false
	var tangent: Vector2 = heading
	return not StartArea.busy(self) and player.global_position.distance_to(start_m * PPM) <= start_radius_m * PPM and \
		player.linear_velocity.length() <= 1.5 and \
		Vector2.UP.rotated(player.rotation).dot(tangent) >= 0.55


func start_race() -> bool:
	if not can_stage() or get_tree().paused:
		return false
	state = "countdown"
	countdown = 3.0
	elapsed = 0.0
	distance_m = 0.0
	previous_station = _station()
	result = ""
	_refresh()
	return true


func _abort(reason: String) -> void:
	state = "aborted"
	result = reason
	status_timer = 5.0
	_refresh()


func _physics_process(dt: float) -> void:
	if not available or not is_instance_valid(player) or dt <= 0.0:
		return
	if is_instance_valid(world_guidance):
		world_guidance.call("set_guidance", navigation, player, state in ["countdown", "running"])
	if state == "countdown":
		if player.linear_velocity.length() > 3.0 or not can_remain_on_grid():
			_abort("FALSE START / RETURN TO GRID")
			return
		countdown -= dt
		if countdown <= 0.0:
			state = "running"
			previous_station = _station()
	elif state == "running":
		elapsed += dt
		var station := _station()
		var advance := station - previous_station
		var lap_length: float = navigation.get("length_m")
		if advance < -lap_length * 0.5:
			advance += lap_length
		elif advance > lap_length * 0.5:
			advance -= lap_length
		var maximum := maxf(3.0, player.linear_velocity.length() * dt * 2.0 + 2.0)
		if _deviation(station) > 12.0 or advance > maximum or advance < -10.0:
			_abort("LAP INVALID / FOLLOW THE CIRCUIT")
			return
		distance_m += maxf(0.0, advance)
		previous_station = station
		if elapsed > 480.0:
			_abort("LAP TIMED OUT")
			return
		if distance_m >= lap_length - 7.0 and station <= 12.0 and \
				player.linear_velocity.dot(heading) > 1.0:
			state = "results"
			result = "CIRCUIT LAP  %.2f SECONDS\nPRACTICE COMPLETE / NO XP AWARDED" % elapsed
			status_timer = 9.0
	elif state in ["results", "aborted"]:
		status_timer -= dt
		if status_timer <= 0.0:
			state = "idle"
			result = ""
	_refresh()


func can_remain_on_grid() -> bool:
	return player.global_position.distance_to(start_m * PPM) <= 9.0 * PPM


func _refresh() -> void:
	if not available or label == null:
		return
	var nearby := player.global_position.distance_to(start_m * PPM) < 110.0 * PPM
	# A small staging prompt appears only close to the start, rather than
	# occupying the driving view whenever a race is nearby.
	nearby = nearby and player.global_position.distance_to(start_m * PPM) < 30.0 * PPM and \
		player.linear_velocity.length() <= 5.0
	match state:
		"idle":
			label.text = "ASHFORD CIRCUIT / PRACTICE LAP\n%s" % (
				"STOP AT CHECKERED LINE / [ F ] START" if can_stage()
				else "STOP INSIDE THE CIRCLE / FACE THE COURSE")
		"countdown":
			label.text = "ASHFORD CIRCUIT / PRACTICE LAP\nSTART IN %d" % maxi(1, ceili(countdown))
		"running":
			var total: float = navigation.get("length_m")
			label.text = "CIRCUIT  /  %.2fs  /  %.0f%% LAP\nGREEN = GO   YELLOW = LIFT   RED = BRAKE" % [
				elapsed, clampf(distance_m / total * 100.0, 0.0, 100.0)]
		_:
			label.text = result

	status_strip.call("set_status", state, nearby, label.text)

func _unhandled_input(event: InputEvent) -> void:
	if not available or not event is InputEventKey or \
			not event.pressed or event.echo or get_tree().paused:
		return
	var key: InputEventKey = event
	if key.keycode in [KEY_F] or key.physical_keycode == KEY_F:
		if can_stage() and start_race():
			get_viewport().set_input_as_handled()

func _draw() -> void:
	if available:StartArea.draw_zone(self,start_radius_m,Color("efb961"))
