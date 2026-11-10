extends Node2D
## Playable race-completion source for player/car XP. Drive to Ashford Drag
## Staging, park on the real drag strip, press F, then race the 1/4 mile.
## No idling, driving around town, teleporting, or menu-opening awards XP.
signal race_finished(result: Dictionary)
const PPM := 20.0
const QUARTER_MILE_M := 402.336
const STAGING_DISTANCE_M := 15.0
const LANE_HALF_WIDTH_M := 9.5
const MAX_VALID_SECONDS := 180.0
var world: MorrowCoast
var player: VehicleController2D
var economy: VehicleOwnership
var start_m := Vector2.ZERO
var direction := Vector2.DOWN
var available := false
var state := "idle"
var countdown := 0.0
var elapsed := 0.0
var progress_m := 0.0
var _previous_progress := 0.0
var _run_id := ""
var _status_clock := 0.0
var _result_text := ""
var _race_panel: PanelContainer
var _race_label: Label


func _ready() -> void:
	name = "AshfordQuarterMile"
	if not is_instance_valid(world) or not is_instance_valid(player):
		return
	for road in world.data.roads:
		if str(road.name) != "Ashford Drag Strip":
			continue
		var points: Array = road.points
		if points.size() < 2:
			break
		start_m = _v(points[0])
		direction = (_v(points[points.size()-1])-start_m).normalized()
		available = direction.length_squared() > 0.9
		break
	if not available:
		push_warning("Could not locate the Ashford Drag Strip in the active world")
		return
	position = start_m * PPM
	rotation = direction.angle()
	z_index = 5
	queue_redraw()
	var layer := CanvasLayer.new()
	layer.name = "RaceOverlay"
	layer.layer = 7
	add_child(layer)
	_race_panel = PanelContainer.new()
	_race_panel.name = "RaceStatus"
	_race_panel.position = Vector2(770, 143)
	_race_panel.custom_minimum_size = Vector2(367, 105)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035,0.075,0.09,0.94)
	style.border_color = Color("b39b67")
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_race_panel.add_theme_stylebox_override("panel",style)
	layer.add_child(_race_panel)
	_race_label = Label.new()
	_race_label.name = "RaceInstructions"
	_race_label.add_theme_font_size_override("font_size",16)
	_race_panel.add_child(_race_label)
	_refresh_overlay()


static func _v(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))


func _local_position() -> Vector2:
	var delta := player.global_position/PPM - start_m
	return Vector2(delta.dot(direction),absf(delta.cross(direction)))


func can_stage() -> bool:
	if not available or not is_instance_valid(player) or state != "idle":
		return false
	var p := _local_position()
	var forward := Vector2.UP.rotated(player.rotation)
	return absf(p.x) <= STAGING_DISTANCE_M and p.y <= LANE_HALF_WIDTH_M and \
		player.linear_velocity.length() <= 1.5 and \
		forward.dot(direction) >= 0.5


func start_race() -> bool:
	if not can_stage() or get_tree().paused:
		return false
	state = "countdown"
	countdown = 3.0
	elapsed = 0.0
	progress_m = 0.0
	_previous_progress = 0.0
	_result_text = ""
	_run_id = "quarter-%s-%d-%d" % [str(economy.active_id),
		Time.get_ticks_usec(),randi()]
	_refresh_overlay()
	return true


func _abort(reason: String) -> void:
	state = "aborted"
	_status_clock = 3.0
	_result_text = reason
	_refresh_overlay()


func _complete() -> void:
	# One finish per valid start. The state transition precedes the award.
	state = "results"
	_status_clock = 8.0
	if not is_instance_valid(economy):
		_result_text = "RESULT UNAVAILABLE"
		_refresh_overlay()
		return
	var result: Dictionary = economy.record_completed_race(_run_id, elapsed)
	if str(result.get("result","")) == "completed":
		_result_text = "FINISH  %.2fs\nDRIVER +%d XP  /  CAR +%d XP  /  +%s" % [
			elapsed,int(result.player_xp),int(result.car_xp),
			VehicleOwnership.dollars(int(result.cash))]
		var reward_part: Dictionary = result.get("part",{})
		if not reward_part.is_empty():
			_result_text += "\nPART EARNED  /  %s  /  %s" % [
				str(reward_part.rarity).to_upper(),str(reward_part.name)]
	else:
		_result_text = "RESULT NOT SAVED: " + str(result.get("result","unknown"))
	race_finished.emit(result)
	_refresh_overlay()


func _physics_process(dt: float) -> void:
	if not available or not is_instance_valid(player) or dt <= 0.0:
		return
	if state == "countdown":
		var p := _local_position()
		if absf(p.x) > STAGING_DISTANCE_M + 4.0 or \
			p.y > LANE_HALF_WIDTH_M or player.linear_velocity.length() > 4.0:
			_abort("FALSE START / RETURN TO STAGING")
			return
		countdown -= dt
		if countdown <= 0.0:
			state = "running"
			countdown = 0.0
			_previous_progress = maxf(0.0,p.x)
			_refresh_overlay()
	elif state == "running":
		elapsed += dt
		var p := _local_position()
		progress_m = p.x
		# Physically remain on the drag strip, continuously travel forward,
		# and finish in a plausible time. No finish-line teleport awards XP.
		var max_step := maxf(5.0,player.linear_velocity.length() * dt * 2.0 + 3.0)
		if p.y > LANE_HALF_WIDTH_M or p.x < -20.0 or \
			progress_m < _previous_progress - 12.0 or \
			progress_m - _previous_progress > max_step:
			_abort("RUN INVALID / STAY ON THE DRAG STRIP")
			return
		if elapsed > MAX_VALID_SECONDS:
			_abort("RUN TIMED OUT")
			return
		if progress_m >= QUARTER_MILE_M:
			if elapsed < 7.0:
				_abort("RUN TOO SHORT TO COUNT")
			else:
				_complete()
			return
		_previous_progress = maxf(_previous_progress,progress_m)
	elif state in ["results","aborted"]:
		_status_clock -= dt
		if _status_clock <= 0.0:
			state = "idle"
			_result_text = ""
	_refresh_overlay()


func _refresh_overlay() -> void:
	if _race_label == null or not available:
		return
	var distance := player.global_position.distance_to(start_m * PPM)/PPM
	_race_panel.visible = state != "idle" or distance <= 100.0
	if not _race_panel.visible:
		return
	match state:
		"idle":
			_race_label.text = "ASHFORD QUARTER-MILE\n%s" % (
				"PARK ON START LINE / FACE DOWN STRIP / [ F ]" if can_stage()
				else "DRIVE TO STAGING / STOP / FACE THE STRIP")
		"countdown":
			_race_label.text = "ASHFORD DRAG RACE  /  READY\nSTART IN %d" % maxi(1,ceili(countdown))
		"running":
			_race_label.text = "ASHFORD DRAG RACE  /  %.2fs\n%.0f / %.0f m  TO FINISH" % [
				elapsed,maxf(0.0,progress_m),QUARTER_MILE_M]
		"results","aborted":
			_race_label.text = _result_text


func _unhandled_input(event: InputEvent) -> void:
	if not available or not event is InputEventKey or \
		not event.pressed or event.echo or get_tree().paused:
		return
	var key: InputEventKey = event
	if key.keycode == KEY_F or key.physical_keycode == KEY_F:
		if can_stage():
			start_race()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	if not available:
		return
	# Local X is down-strip and local Y is across the road.
	for x in [0.0, QUARTER_MILE_M * PPM]:
		var finish: bool = float(x) > 0.0
		draw_line(Vector2(x,-LANE_HALF_WIDTH_M*PPM),
			Vector2(x,LANE_HALF_WIDTH_M*PPM),
			Color("eee5d3") if not finish else Color("f3e6ce"),
			9.0 if not finish else 14.0,true)
		if finish:
			for i in 18:
				var y := (float(i)-9.0)*PPM
				draw_rect(Rect2(Vector2(x-12.0,y),Vector2(24.0,PPM)),
					Color("26383b") if i%2 == 0 else Color("f3ecdf"),true)
	for side in [-1.0,1.0]:
		draw_line(Vector2(0,side*LANE_HALF_WIDTH_M*PPM),
			Vector2(QUARTER_MILE_M*PPM,side*LANE_HALF_WIDTH_M*PPM),
			Color("e6d2ae"),3.0,true)
	draw_set_transform(Vector2(0,-PPM*12.5),-rotation)
	draw_string(ThemeDB.fallback_font,Vector2.ZERO,"ASHFORD  /  QUARTER-MILE START",
		HORIZONTAL_ALIGNMENT_LEFT,int(PPM*34),28,Color("f1deb0"))
	draw_set_transform(Vector2.ZERO)
