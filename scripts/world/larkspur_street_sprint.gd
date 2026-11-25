extends Node2D
## Drive-up Larkspur street sprint prototype. Its route uses the actual traffic
## navigation graph; the racing line stays on the legally directed street lane.
## Career-enabled street sprints use the same physical route; sandbox runs remain practice.
const PPM := 20.0
const RacingLine = preload("res://scripts/world/race_line_builder.gd")
const NavigationScript = preload("res://scripts/world/race_navigation.gd")
const GuidanceScript = preload("res://scripts/world/race_guidance.gd")
const StatusStripScript = preload("res://scripts/ui/race_status_strip.gd")
const VehicleScene = preload("res://scenes/vehicle.tscn")
const RacerDriverScript = preload("res://scripts/world/race_ai_driver.gd")
const StartArea=preload("res://scripts/world/race_start_area.gd")
const Grid=preload("res://scripts/world/race_start_grid.gd")
const RoutePlanner=preload("res://scripts/world/road_route_planner.gd")
@export var definition: Resource
var race_title:="Larkspur Street Sprint"
var race_type:="Street Sprint · 1v1"
var start_radius_m:=8.0
var world: MorrowCoast
var player: VehicleController2D
var network: RefCounted
var traffic: Node
var opponent: VehicleController2D
var opponent_driver: Node
var opponent_station_m := 0.0
var opponent_elapsed := -1.0
var opponent_dnf := false
var _opponent_stall_anchor := Vector2.ZERO
var _opponent_stall_age := 0.0
const OPPONENT_STALL_SECONDS := 18.0
const OPPONENT_MOVEMENT_RESET_PX := PPM * 0.65
var navigation: RefCounted
var world_guidance: Node2D
var edge_ids: Array[int] = []
var available := false
var state := "idle"
var _previous_position_m:=Vector2.ZERO
var countdown := 0.0
var elapsed := 0.0
var previous_station := 0.0
var status_timer := 0.0
var start_m := Vector2.ZERO
var rival_grid_m := Vector2.ZERO
var finish_m := Vector2.ZERO
var heading := Vector2.UP
var result := ""
var status_strip: Control
var panel: PanelContainer
var label: Label
var economy: Object
var police: Node2D
var career_awards: Dictionary={}
var career_run_id:=""
var staged_car_id:=""
var awaiting_escape:=false
var escape_remaining:=0.0


func _ready() -> void:
	name = "LarkspurStreetSprint"
	if not is_instance_valid(world) or not is_instance_valid(player) or network == null:
		return
	var planned: Dictionary={}
	if definition!=null:
		race_title=str(definition.title)
		name=str(definition.event_id)
		var planner:=RoutePlanner.new();planner.setup(network,world.data)
		planned=planner.plan(planner.road_anchor(definition.start_road,definition.start_piece,definition.start_fraction),
			planner.road_anchor(definition.finish_road,definition.finish_piece,definition.finish_fraction),
			Vector2.ZERO,definition.start_road,definition.finish_road)
		if not planned.is_empty():edge_ids.assign(planned.edges)
	else:edge_ids = RacingLine.city_sprint_edges(network, world, world.spawn_position())
	if edge_ids.is_empty():
		push_warning("No connected directed lanes for the Larkspur sprint")
		return
	var center_course: PackedVector2Array=planned.points_m if not planned.is_empty() else RacingLine.traffic_line(network,world,edge_ids)
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
	# Spawn behind the start on the ACTUAL curved traffic lane, not by
	# extrapolating a straight vector through the sidewalk at a bend.
	rival_grid_m = center_course[2]
	finish_m = course[course.size() - 1]
	heading = (course[1] - course[0]).normalized()
	available = true
	add_to_group("streetbound_race")
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
	status_strip = Control.new()
	status_strip.set_script(StatusStripScript)
	layer.add_child(status_strip)
	panel = status_strip.get("panel") as PanelContainer
	label = status_strip.get("label") as Label
	status_strip.call("configure_event", self, {
		"title": race_title, "type": race_type, "format": "1v1",
		"distance_m": float(navigation.get("length_m")),
		"route": navigation.get("points_m"),
		"entry": "FREE", "rewards": "PRACTICE",
		"description": "Race a rival along the marked street route. Practice event with no payouts."
	})
	_refresh()


func configure_underground_career(model: Object, pursuit: Node2D) -> void:
	economy=model
	police=pursuit
	if not available:return
	var event_id: String="larkspur-sprint" if definition==null else str(definition.event_id)
	var heat:=1 if definition==null else (3 if event_id=="parkway-express" else 2)
	career_awards={"id":"race-builtin-"+event_id,"category":"street","race_heat":heat,
		"reward_cash":1500+heat*750,"reward_player_xp":180+heat*90,
		"reward_car_xp":120+heat*60,"underground_rep_reward":heat*2,
		"first_win_reward_cash":500,"escape_time_limit":90+heat*15}
	# A real existing route serves as the first high-stakes career event.
	if event_id=="parkway-express":
		career_awards["entry_fee"]=2000
		career_awards["reward_cash"]=7000
		career_awards["required_underground_rep"]=6
	race_type="Underground Sprint · 1v1"
	status_strip.call("configure_event",self,{
		"title":race_title,"type":race_type,"format":"1v1",
		"distance_m":float(navigation.get("length_m")),"route":navigation.get("points_m"),
		"entry":"FREE" if int(career_awards.get("entry_fee",0))==0 else "$%d"%int(career_awards.entry_fee),"rewards":"$%d / DRIVER + CAR XP / +%d STREET REP"%[int(career_awards.reward_cash),int(career_awards.underground_rep_reward)],
		"description":"Win the sprint and lose the police to collect your prize. Wanted level %d."%heat})
	player.vehicle_reset.connect(_on_career_reset)
	_refresh()

func _on_career_reset() -> void:
	if state in ["countdown","running"]:quit_race()

func manages_race_heat() -> bool:
	return true

func _award_career() -> String:
	if career_awards.is_empty() or not is_instance_valid(economy):
		return "STREET PRACTICE / NO REWARDS"
	if not is_instance_valid(police) or int(police.get("wanted_level"))>0 or float(police.get("bust_timer"))>0.0:
		return "ESCAPE REQUIRED / NO REWARD"
	var key: String=str(world.data.get("editor_world_id","morrow-coast"))+"::"+str(career_awards.id)
	var award: Dictionary=economy.call("record_authored_race",career_run_id,elapsed,career_awards,key,true)
	if str(award.get("result",""))!="completed":return "REWARDS NOT SAVED"
	return "$%d / +%d DRIVER XP / +%d CAR XP / +%d STREET REP"%[
		int(award.cash),int(award.player_xp),int(award.car_xp),int(award.underground_rep)]

func _lock_reason() -> String:
	if career_awards.is_empty():return ""
	if not is_instance_valid(economy):return "CAREER UNAVAILABLE"
	if int(economy.get("balance"))<int(career_awards.get("entry_fee",0)):
		return "REQUIRES ENTRY FEE $%d"%int(career_awards.get("entry_fee",0))
	if int(economy.get("underground_reputation"))<int(career_awards.get("required_underground_rep",0)):
		return "REQUIRES STREET REP %d"%int(career_awards.get("required_underground_rep",0))
	return ""

func can_stage() -> bool:
	if not _lock_reason().is_empty():return false
	if not available or not is_instance_valid(player) or state != "idle":
		return false
	return not StartArea.busy(self) and player.global_position.distance_to(start_m * PPM) <= start_radius_m * PPM and \
		StartArea.can_stage_at_speed(player.linear_velocity.length()) and \
		Vector2.UP.rotated(player.rotation).dot(heading) >= 0.6


func start_race() -> bool:
	if not can_stage() or get_tree().paused:
		return false
	if not _spawn_opponent():
		return false
	if int(career_awards.get("entry_fee",0))>0 and not bool(economy.call("pay_race_entry",career_awards)):
		_clear_opponent()
		return false
	awaiting_escape=false;escape_remaining=0.0
	staged_car_id=str(economy.get("active_id")) if is_instance_valid(economy) else ""
	career_run_id="builtin-%s-%s-%d"%[str(career_awards.get("id","practice")),staged_car_id,Time.get_ticks_usec()]
	Grid.teleport(player,Grid.pose(start_m,heading))
	if is_instance_valid(traffic):
		traffic.call("set_street_race_route", navigation, edge_ids, true)
	player.add_to_group("race_participant")
	state = "countdown"
	countdown = 3.0
	elapsed = 0.0
	previous_station = float(navigation.call("station_at", player.global_position / PPM))
	_previous_position_m=player.global_position/PPM
	opponent_station_m = 0.0
	opponent_elapsed = -1.0
	opponent_dnf = false
	_opponent_stall_age = 0.0
	_opponent_stall_anchor = opponent.global_position
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
	var start_px := rival_grid_m * PPM
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
		var no_edges: Array[int] = []
		traffic.call("set_street_race_route", null, no_edges, false)
	if is_instance_valid(player):
		player.remove_from_group("race_participant")


## Street-race rivals are not ambient traffic; keep real finish/DNF state.
## A physically immobilized rival can retire *only* after it is no longer
## visible in any player's camera. No vanishing rivals in the driving view.
func _update_opponent(dt: float = 0.01667) -> void:
	if not is_instance_valid(opponent) or opponent_elapsed >= 0.0:
		return
	var position_px := opponent.global_position
	if position_px.distance_to(_opponent_stall_anchor) >= OPPONENT_MOVEMENT_RESET_PX:
		_opponent_stall_anchor = position_px
		_opponent_stall_age = 0.0
	else:
		_opponent_stall_age += dt
	if _opponent_stall_age >= OPPONENT_STALL_SECONDS and \
			is_instance_valid(traffic) and \
			not bool(traffic.call("_visible_to_any_player", position_px)):
		opponent_dnf = true
		_clear_opponent()
		return
	var position_m := position_px / PPM
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
	awaiting_escape=false
	result = message
	status_timer = 5.0
	_refresh()

func quit_race() -> bool:
	if state not in ["countdown","running"]:return false
	_finish_race();_clear_opponent()
	state="idle";countdown=0;elapsed=0;result="";awaiting_escape=false
	if is_instance_valid(world_guidance):world_guidance.call("set_guidance",navigation,player,false)
	_refresh();return true


func _physics_process(dt: float) -> void:
	if not available or not is_instance_valid(player) or dt <= 0.0:
		return
	if not career_awards.is_empty() and state in ["countdown","running"]:
		if player.damage_drive_fraction<=0.0 or player.fuel_drive_fraction<=0.0 or str(economy.get("active_id"))!=staged_car_id or not is_instance_valid(police) or float(police.get("bust_timer"))>0.0:
			_abort("RUN FAILED / VEHICLE DISABLED, CHANGED OR BUSTED")
			return
	if awaiting_escape:
		escape_remaining-=dt
		if escape_remaining<=0.0:
			_abort("ESCAPE FAILED / NO REWARD")
		elif int(police.get("wanted_level"))==0:
			awaiting_escape=false
			_finish_race()
			state="results";status_timer=9.0
			result="ESCAPE COMPLETE / "+_award_career()
		_refresh()
		return
	if is_instance_valid(world_guidance):
		world_guidance.call("set_guidance", navigation, player,
			state in ["countdown", "running"] and not awaiting_escape)
	if state == "countdown":
		if player.linear_velocity.length() > 3.0 or \
				player.global_position.distance_to(start_m * PPM) > 10.0 * PPM:
			_abort("FALSE START / RETURN TO GRID")
			return
		countdown -= dt
		if countdown <= 0.0:
			if not career_awards.is_empty() and not bool(police.call("start_pursuit",int(career_awards.race_heat))):
				_abort("DISPATCH UNAVAILABLE / RUN FAILED");return
			state = "running"
			if is_instance_valid(opponent_driver):
				opponent_driver.call("launch")
			previous_station = float(navigation.call("station_at", player.global_position / PPM))
			_previous_position_m=player.global_position/PPM
	elif state == "running":
		elapsed += dt
		_update_opponent(dt)
		var station: float = navigation.call("station_at", player.global_position / PPM)
		var maximum := maxf(3.0, player.linear_velocity.length() * dt * 2.0 + 2.0)
		var position_m:=player.global_position/PPM
		if position_m.distance_to(_previous_position_m)>maximum:
			_abort("RUN INVALID / POSITION JUMP")
			return
		_previous_position_m=position_m
		previous_station = maxf(previous_station, station)
		if elapsed > (float(definition.time_limit_seconds) if definition!=null else 280.0):
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
				if not career_awards.is_empty() and int(police.get("wanted_level"))>0:
					awaiting_escape=true
					escape_remaining=float(career_awards.escape_time_limit)
					state="running"
					_clear_opponent()
					if is_instance_valid(world_guidance):world_guidance.call("set_guidance",navigation,player,false)
					player.add_to_group("race_participant")
				else:
					result = "YOU WIN / %.2f s\n%s"%[elapsed,_award_career()]
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
	# A small staging prompt appears only close to the start, rather than
	# occupying the driving view whenever a race is nearby.
	nearby = nearby and player.global_position.distance_to(start_m * PPM) < 30.0 * PPM and \
		StartArea.can_stage_at_speed(player.linear_velocity.length())
	if awaiting_escape:
		status_strip.call("set_status","running",false,"%s / FINISH COMPLETE\nLOSE POLICE / %ds / REWARDS PENDING"%[race_title,ceili(escape_remaining)])
		return
	match state:
		"idle":
			label.text = "%s / 1v1\n%s" % [race_title.to_upper(),
				"[ F ] START RACE" if can_stage() else
				"SLOW TO 15 MPH / FACE ROUTE" if not StartArea.can_stage_at_speed(player.linear_velocity.length()) else
				"ENTER START CIRCLE / FACE ROUTE"]
		"countdown":
			label.text = "%s\nSTART IN %d" % [race_title.to_upper(),maxi(1, ceili(countdown))]
		"running":
			var fraction := previous_station / maxf(1.0, float(navigation.get("length_m")))
			var rival := opponent_station_m / maxf(1.0, float(navigation.get("length_m")))
			var maneuver := "DNF" if opponent_dnf else str(opponent_driver.get("traffic_mode")) if is_instance_valid(opponent_driver) else "clear"
			label.text = "%s / %.1fs\nYOU %.0f%% · RIVAL %.0f%% · %s" % [
				race_title.to_upper(),elapsed,clampf(fraction * 100.0, 0.0, 100.0),
				clampf(rival * 100.0, 0.0, 100.0),maneuver.to_upper()]
		_:
			label.text = result

	status_strip.call("set_status", state, nearby, label.text)

func _unhandled_input(event: InputEvent) -> void:
	if not available or get_tree().paused:return
	if event is InputEventKey and (not event.pressed or event.echo):return
	if event.is_action_pressed("interact") and can_stage():
		if start_race():get_viewport().set_input_as_handled()

func _draw() -> void:
	if not available:
		return
	StartArea.draw_zone(self,start_radius_m)
