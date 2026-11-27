extends Node2D
## Playable race-completion source for player/car XP. Drive to Ashford Drag
## Staging, park on the real drag strip, press F, then race the 1/4 mile.
## No idling, driving around town, teleporting, or menu-opening awards XP.
# Explicit script dependency: class_name lookups are not reliable before Godot imports.
const OwnershipModel = preload("res://scripts/vehicle/vehicle_ownership.gd")
const StatusStripScript = preload("res://scripts/ui/race_status_strip.gd")
const StartArea=preload("res://scripts/world/race_start_area.gd")
const Grid=preload("res://scripts/world/race_start_grid.gd")
signal race_finished(result: Dictionary)
const PPM := 20.0
const QUARTER_MILE_M := 402.336
const DRAG_START_OFFSET_M := 60.0
const STAGING_DISTANCE_M := 15.0
const LANE_HALF_WIDTH_M := 9.5
const MAX_VALID_SECONDS := 180.0
var world: MorrowCoast
var player: VehicleController2D
var economy: OwnershipModel
var start_m := Vector2.ZERO
var player_grid_m:=Vector2.INF
var direction := Vector2.DOWN
var available := false
var state := "idle"
var _previous_position_m:=Vector2.ZERO
var race_title:="Ashford Quarter Mile"
var race_type:="Drag · 1v1"
var countdown := 0.0
var elapsed := 0.0
var progress_m := 0.0
var _previous_progress := 0.0
var _run_id := ""
var _status_clock := 0.0
var _result_text := ""
var _race_panel: PanelContainer
var _race_label: Label
var _status_strip: Control


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
		start_m += direction * DRAG_START_OFFSET_M
		available = direction.length_squared() > 0.9
		break
	if not available:
		push_warning("Could not locate the Ashford Drag Strip in the active world")
		return
	position = start_m * PPM
	add_to_group("streetbound_race")
	rotation = direction.angle()
	z_index = 5
	queue_redraw()
	var layer := CanvasLayer.new()
	layer.name = "RaceOverlay"
	layer.layer = 7
	add_child(layer)
	_status_strip = Control.new()
	_status_strip.set_script(StatusStripScript)
	layer.add_child(_status_strip)
	_race_panel = _status_strip.get("panel") as PanelContainer
	_race_label = _status_strip.get("label") as Label
	_status_strip.call("configure_event", self, {
		"title": race_title, "type": race_type, "format": "Timed Drag",
		"distance_m": QUARTER_MILE_M,
		"route": PackedVector2Array([start_m, start_m + direction * QUARTER_MILE_M]),
		"entry": "FREE", "rewards": "XP + CASH",
		"description": "Time your quarter-mile launch and finish to earn driver and car progression.",
		"best_seconds": economy.best_quarter_mile if is_instance_valid(economy) else 0.0
	})
	_refresh_overlay()


static func _v(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))


func _local_position() -> Vector2:
	var delta := player.global_position/PPM - start_m
	return Vector2(delta.dot(direction),absf(delta.cross(direction)))


func can_stage() -> bool:
	if not available or not is_instance_valid(player) or state != "idle":
		return false
	var forward := Vector2.UP.rotated(player.rotation)
	return not StartArea.busy(self) and player.global_position.distance_to(start_m*PPM)<=start_radius_m()*PPM and \
		StartArea.can_stage_at_speed(player.linear_velocity.length()) and \
		forward.dot(direction) >= 0.5

func start_radius_m() -> float:return 8.0


func start_race() -> bool:
	if not can_stage() or get_tree().paused:
		return false
	Grid.teleport(player,Grid.pose(start_m if player_grid_m==Vector2.INF else player_grid_m,direction))
	state = "countdown"
	countdown = 3.0
	elapsed = 0.0
	progress_m = 0.0
	_previous_progress = 0.0
	_previous_position_m=player.global_position/PPM
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

func quit_race() -> bool:
	if state not in ["countdown","running"]:return false
	state="idle";countdown=0;elapsed=0;progress_m=0;_result_text=""
	_refresh_overlay()
	return true


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
			OwnershipModel.dollars(int(result.cash))]
		_result_text += "  /  +%d STREET REP" % int(result.get("underground_rep",0))
		if not str(result.get("rank_up","")).is_empty():
			_result_text += "\n"+str(result["rank_up"])
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
			_previous_position_m=player.global_position/PPM
			_refresh_overlay()
	elif state == "running":
		elapsed += dt
		var p := _local_position()
		progress_m = p.x
		# Leaving the racing line never cancels a run. Reject only an actual
		# implausible position jump; route projections can jump at junctions.
		var max_step := maxf(5.0,player.linear_velocity.length() * dt * 2.0 + 3.0)
		var position_m:=player.global_position/PPM
		if position_m.distance_to(_previous_position_m)>max_step:
			_abort("RUN INVALID / POSITION JUMP")
			return
		_previous_position_m=position_m
		if elapsed > MAX_VALID_SECONDS:
			_abort("RUN TIMED OUT")
			return
		if progress_m >= QUARTER_MILE_M and p.y<=LANE_HALF_WIDTH_M:
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
	var show_prompt := distance <= 30.0 and \
		StartArea.can_stage_at_speed(player.linear_velocity.length())
	match state:
		"idle":
			_race_label.text = "ASHFORD QUARTER-MILE\n%s" % (
				"[ F ] START RACE" if can_stage() else
				"SLOW TO 15 MPH / FACE STRIP" if not StartArea.can_stage_at_speed(player.linear_velocity.length()) else
				"ENTER START CIRCLE / FACE STRIP")
		"countdown":
			_race_label.text = "ASHFORD DRAG RACE  /  READY\nSTART IN %d" % maxi(1,ceili(countdown))
		"running":
			_race_label.text = "ASHFORD DRAG RACE  /  %.2fs\n%.0f / %.0f m  TO FINISH" % [
				elapsed,maxf(0.0,progress_m),QUARTER_MILE_M]
		"results","aborted":
			_race_label.text = _result_text

	_status_strip.call("set_status", state, show_prompt, _race_label.text)

func _unhandled_input(event: InputEvent) -> void:
	if not available or get_tree().paused:return
	if event is InputEventKey and (not event.pressed or event.echo):return
	if event.is_action_pressed("interact") and can_stage():
		if start_race():get_viewport().set_input_as_handled()

func _draw() -> void:
	if not available:
		return
	StartArea.draw_zone(self,start_radius_m(),Color("efb961"))
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
