extends Node2D
## Single-player physical police pursuit. Police NEVER teleport during a chase,
## receive engine/grip boosts, or spawn ahead in the driver's travel corridor.
## Multiplayer host-authoritative officers remain a separate future feature.
signal busted(reason: String)
signal escaped
const PPM := 20.0
const VehicleScene = preload("res://scenes/vehicle.tscn")
const DriverScript = preload("res://scripts/world/race_ai_driver.gd")
const PlannerScript = preload("res://scripts/world/road_route_planner.gd")
const Containment = preload("res://scripts/world/police_containment.gd")
const Tactics = preload("res://scripts/world/police_tactics.gd")
const ROUTE_INTERVAL := 0.75
const SEARCH_SWEEP_INTERVAL := 4.5
const BLOCK_REEVALUATE_M := 100.0
var player: VehicleController2D
var world: Node2D
var traffic: Node2D
var economy: Object
var damage_service: CanvasLayer
var street_races: Array = []
var wanted_level := 0
var units: Array[Dictionary] = []
var planner: RefCounted
var route_clock := 0.0
var next_unit := 0
var search_clock := 0.0
var lost_sight_clock := 0.0
var search_round := 0
var phase := "clear"
var last_seen_position_m := Vector2.ZERO
var last_seen_velocity_mps := Vector2.ZERO
var last_seen_heading := Vector2.UP
var roadblock_position_m := Vector2.INF
var roadblock_reference_m := Vector2.INF
var containment_seconds := 0.0
var bust_timer := 0.0
var bust_reason := ""
var race_active_ids: Dictionary = {}
var message := ""
var message_timer := 0.0
var readout: Label

func _ready() -> void:
	name = "PolicePursuit"
	if not is_instance_valid(player) or not is_instance_valid(world) or not is_instance_valid(traffic):
		return
	planner = PlannerScript.new()
	planner.call("setup", traffic.get("network"), world.get("data"))
	player.vehicle_reset.connect(_on_player_reset)
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 242)
	panel.custom_minimum_size = Vector2(320, 30)
	layer.add_child(panel)
	readout = Label.new()
	readout.add_theme_font_size_override("font_size", 13)
	panel.add_child(readout)
	readout.text = "POLICE / CLEAR"
	# F7 remains a debug-only smoke-test shortcut; ordinary play uses
	# illegal racing and authored crime jobs.

func _unhandled_input(event: InputEvent) -> void:
	if not OS.has_feature("debug") or not event is InputEventKey:
		return
	if event.pressed and not event.echo and event.keycode == KEY_F7 and wanted_level == 0:
		start_pursuit(1)
		get_viewport().set_input_as_handled()

func _on_player_reset() -> void:
	# Reset cannot erase an active pursuit or repair the suspect's car.
	if wanted_level > 0 and bust_timer <= 0.0:
		_bust("VEHICLE RESET DURING PURSUIT")

func _race_trigger() -> void:
	# Each street-race run may alert dispatch once, not once per frame.
	for race in street_races:
		if not is_instance_valid(race):
			continue
		var identity: int = race.get_instance_id()
		var running: bool = str(race.get("state")) == "running"
		if not running:
			race_active_ids.erase(identity)
			continue
		if race_active_ids.has(identity):
			continue
		race_active_ids[identity] = true
		if wanted_level == 0 and bust_timer <= 0.0:
			start_pursuit(1)

func _travel_heading() -> Vector2:
	if player.linear_velocity.length() > 3.0:
		return player.linear_velocity.normalized()
	return Vector2.UP.rotated(player.rotation)

func _camera_sees(position_px: Vector2) -> bool:
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera == null:
		return false
	var center := camera.get_screen_center_position()
	var viewport_px := get_viewport().get_visible_rect().size
	var zoom_x := maxf(0.01,absf(camera.zoom.x))
	var zoom_y := maxf(0.01,absf(camera.zoom.y))
	var delta := position_px - center
	# Conservative margin: never pop cruisers into or just outside the view.
	return absf(delta.x) <= viewport_px.x / (zoom_x * 2.0) + PPM * 12.0 and \
		absf(delta.y) <= viewport_px.y / (zoom_y * 2.0) + PPM * 12.0

func _space_is_free(position_px: Vector2) -> bool:
	# Check physical occupancy on both world and vehicle collision layers.
	# A visually drivable lane may still hold a building or another car.
	var shape := CircleShape2D.new()
	shape.radius = PPM * 3.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, position_px)
	query.collision_mask = 3
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	if not get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	for node in get_tree().get_nodes_in_group("traffic_vehicle"):
		if node is Node2D and (node as Node2D).global_position.distance_to(position_px) < PPM * 18.0:
			return false
	return true

func _spawn_candidates() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if not is_instance_valid(player) or not is_instance_valid(traffic):
		return options
	var network: RefCounted = traffic.get("network")
	if network == null:
		return options
	var edges: Array = network.get("edges")
	var origin_m := player.global_position / PPM
	var direction := _travel_heading()
	var nearby: Array = network.call("nearby_edges", player.global_position, 260.0)
	for raw_id in nearby:
		var edge_id := int(raw_id)
		if edge_id < 0 or edge_id >= edges.size():
			continue
		var edge: Dictionary = edges[edge_id]
		if bool(edge.get("connector",false)) or not bool(edge.get("through_route",true)):
			continue
		var length_px := float(edge.get("length_px",0.0))
		if length_px < PPM * 24.0:
			continue
		for fraction in [0.27,0.50,0.73]:
			var sample: Dictionary = network.call("point_on_edge", edge_id, length_px * fraction)
			var point_px: Vector2 = sample.get("position", Vector2.INF)
			if not point_px.is_finite() or _camera_sees(point_px):
				continue
			var point_m := point_px / PPM
			var unused: Array[Vector2] = []
			if not Tactics.safe_spawn(point_m, origin_m, direction, unused):
				continue
			if is_instance_valid(world) and world.has_method("surface_at") and \
					str(world.call("surface_at",point_px).get("name","")) != "ASPHALT":
				continue
			if not _space_is_free(point_px):
				continue
			var behind := (point_m-origin_m).normalized().dot(direction)
			options.append({"position":point_px,"position_m":point_m,
				"heading":sample.get("tangent",Vector2.UP),
				"score":absf(origin_m.distance_to(point_m)-175.0)+maxf(0.0,behind+0.3)*45.0})
	options.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return float(a["score"])<float(b["score"]))
	return options

func _roadblock_candidates() -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var network: RefCounted = traffic.get("network")
	if network == null:
		return candidates
	var edges: Array = network.get("edges")
	var nearby: Array = network.call("nearby_edges",last_seen_position_m*PPM,210.0)
	for raw_id in nearby:
		var edge_id := int(raw_id)
		if edge_id < 0 or edge_id >= edges.size():
			continue
		var edge: Dictionary=edges[edge_id]
		if bool(edge.get("connector",false)) or not bool(edge.get("through_route",true)):
			continue
		var length_px := float(edge.get("length_px",0.0))
		if length_px < PPM * 22.0:
			continue
		for fraction in [0.25,0.5,0.75]:
			var sample: Dictionary=network.call("point_on_edge",edge_id,length_px*fraction)
			var point_px: Vector2=sample.get("position",Vector2.INF)
			if point_px.is_finite():
				candidates.append({"position_m":point_px/PPM,"edge_id":edge_id})
	return candidates

func _choose_roadblock() -> void:
	roadblock_reference_m = last_seen_position_m
	roadblock_position_m = Vector2.INF
	if wanted_level < 4:
		return
	var chosen: Dictionary=Tactics.roadblock_candidate(_roadblock_candidates(),
		last_seen_position_m,last_seen_heading)
	if not chosen.is_empty():
		roadblock_position_m = chosen["position_m"]

func _spawn_units() -> void:
	var options := _spawn_candidates()
	var selected: Array[Vector2] = []
	var profile: Dictionary = Tactics.profile(wanted_level)
	var limit: int = mini(Tactics.MAX_RESPONDERS,int(profile["units"]))
	for option in options:
		if units.size() >= limit:
			break
		var point_px: Vector2=option["position"]
		var position_m: Vector2=option["position_m"]
		if not Tactics.safe_spawn(position_m,player.global_position/PPM,
				_travel_heading(),selected):
			continue
		var car: VehicleController2D = VehicleScene.instantiate() as VehicleController2D
		if car == null:
			continue
		car.name = "PoliceUnit%d" % (units.size()+1)
		car.external_input = true
		car.surface_provider = world
		car.collision_layer = 1
		car.collision_mask = 3
		car.position = point_px
		car.rotation = Vector2.UP.angle_to(Vector2(option["heading"]))
		car.z_index = 8
		car.add_to_group("police_vehicle")
		add_child(car)
		var identifier := Label.new()
		identifier.text = "POLICE"
		identifier.position = Vector2(-27,-61)
		identifier.add_theme_font_size_override("font_size",12)
		car.add_child(identifier)
		var driver := Node.new()
		driver.set_script(DriverScript)
		driver.set("reaction_seconds",0.2)
		driver.set("throttle_limit",float(profile["throttle"]))
		driver.set("cruise_speed_mps",float(profile["cruise_mps"]))
		add_child(driver)
		units.append({"car":car,"driver":driver,
			"role":Tactics.role(units.size(),wanted_level),
			"blocking":false,"label":identifier})
		selected.append(position_m)
	for index in units.size():
		_refresh_unit_route(index)

func _refresh_unit_route(index: int) -> void:
	if planner == null or index < 0 or index >= units.size():
		return
	var entry: Dictionary = units[index]
	var car: VehicleController2D = entry["car"]
	var driver: Node = entry["driver"]
	if not is_instance_valid(car) or not is_instance_valid(driver):
		return
	if bool(entry.get("blocking",false)):
		driver.call("stop")
		car.command = Vector4(0.0,1.0,0.0,0.0)
		return
	var goal_m := last_seen_position_m
	if phase == "search":
		goal_m = Tactics.search_target(last_seen_position_m,last_seen_heading,index,search_round)
	elif str(entry.get("role","pursuer"))=="roadblock":
		if roadblock_position_m.is_finite():
			goal_m = roadblock_position_m
		else:
			goal_m = Tactics.intercept_target(last_seen_position_m,
				last_seen_velocity_mps,last_seen_heading,"flank_right",wanted_level)
	else:
		goal_m = Tactics.intercept_target(last_seen_position_m,
			last_seen_velocity_mps,last_seen_heading,str(entry.get("role","pursuer")),wanted_level)
	var route: Dictionary=planner.call("plan",car.global_position/PPM,goal_m,
		Vector2.UP.rotated(car.rotation))
	if route.is_empty() or float(route.get("access_distance_m",INF))>22.0:
		# Never use a cross-country straight line when the legal road route fails.
		driver.call("stop")
		car.command=Vector4(0.0,1.0,0.0,0.0)
		return
	var points: PackedVector2Array=route.get("points_m",PackedVector2Array())
	var points_px:=PackedVector2Array()
	for p in points:
		points_px.append(p*PPM)
	driver.call("setup",car,points_px)
	driver.call("launch")

func _line_of_sight() -> bool:
	var sight_m: float=float(Tactics.profile(wanted_level)["sight_m"])
	var exclusion: Array[RID]=[player.get_rid()]
	for item in units:
		var officer: VehicleController2D=item["car"]
		if is_instance_valid(officer):
			exclusion.append(officer.get_rid())
	for item in units:
		var officer: VehicleController2D=item["car"]
		if not is_instance_valid(officer):
			continue
		var distance_m:=officer.global_position.distance_to(player.global_position)/PPM
		if distance_m>sight_m:
			continue
		# Only confirmed unobstructed sightings may update the suspect's
		# last known location. Buildings, walls and traffic can hide the car.
		var params:=PhysicsRayQueryParameters2D.create(
			officer.global_position,player.global_position,1,exclusion)
		var hit: Dictionary=get_world_2d().direct_space_state.intersect_ray(params)
		if Tactics.visible(distance_m,wanted_level,not hit.is_empty()):
			return true
	return false

func start_pursuit(level: int = 1) -> bool:
	if wanted_level > 0 or not is_instance_valid(player) or not is_instance_valid(traffic):
		return false
	wanted_level = clampi(level,1,5)
	phase = "chase"
	last_seen_position_m = player.global_position / PPM
	last_seen_velocity_mps = player.linear_velocity
	last_seen_heading = _travel_heading()
	lost_sight_clock = 0.0
	search_clock = 0.0
	search_round = 0
	containment_seconds = 0.0
	route_clock = 0.0
	next_unit = 0
	roadblock_position_m = Vector2.INF
	roadblock_reference_m = Vector2.INF
	_choose_roadblock()
	_spawn_units()
	if units.is_empty():
		wanted_level = 0
		phase = "clear"
		message = "NO SAFE POLICE SPAWN AVAILABLE"
		message_timer = 3.0
		return false
	return true

func _despawn_units() -> void:
	for entry in units:
		var driver: Node = entry["driver"]
		var car: VehicleController2D = entry["car"]
		if is_instance_valid(driver):
			driver.queue_free()
		if is_instance_valid(car):
			car.queue_free()
	units.clear()

func _escape() -> void:
	wanted_level = 0
	phase = "clear"
	containment_seconds = 0.0
	search_clock = 0.0
	lost_sight_clock = 0.0
	message = "ESCAPED / POLICE LOST CONTACT"
	message_timer = 3.0
	escaped.emit()
	_despawn_units()

func _bust(reason: String) -> void:
	if wanted_level <= 0 or bust_timer > 0.0:
		return
	bust_reason = reason
	for race in street_races:
		if is_instance_valid(race) and str(race.get("state")) in ["countdown","running"] and \
				race.has_method("quit_race"):
			race.call("quit_race")
	bust_timer = 2.0
	busted.emit(reason)
	message = "BUSTED / "+reason
	message_timer = 4.0
	for entry in units:
		if is_instance_valid(entry["driver"]):
			entry["driver"].call("stop")
	player.damage_drive_fraction = 0.0

func _recover_busted() -> void:
	var prior_level := wanted_level
	wanted_level = 0
	phase = "clear"
	_despawn_units()
	if is_instance_valid(economy):
		var fee := mini(int(economy.balance),1500*prior_level)
		if fee > 0:
			economy.balance -= fee
			if economy.save():
				economy.changed.emit()
			else:
				economy.balance += fee
	player.reset_vehicle()
	if is_instance_valid(damage_service):
		damage_service.impound_recovery()
	containment_seconds = 0.0
	search_clock = 0.0
	lost_sight_clock = 0.0

func _update_search_state(dt: float, seen: bool) -> void:
	if seen:
		# Confirmed police sighting; only here can dispatch refresh its
		# knowledge of the suspect's position, speed and travel direction.
		last_seen_position_m = player.global_position / PPM
		last_seen_velocity_mps = player.linear_velocity
		last_seen_heading = _travel_heading()
		lost_sight_clock = 0.0
		if phase == "search":
			phase = "chase"
			search_clock = 0.0
			search_round = 0
			roadblock_position_m = Vector2.INF
			_choose_roadblock()
			route_clock = 0.0
	else:
		lost_sight_clock += dt
		if phase == "chase" and lost_sight_clock >= Tactics.LOST_SIGHT_GRACE_SECONDS:
			phase = "search"
			search_clock = 0.0
			search_round = 0
			containment_seconds = 0.0
			route_clock = 0.0
		if phase == "search":
			search_clock += dt
			var next_round := int(floorf(search_clock/SEARCH_SWEEP_INTERVAL))
			if next_round != search_round:
				search_round = next_round
				route_clock = 0.0

func _physics_process(dt: float) -> void:
	if not is_instance_valid(player):
		return
	_race_trigger()
	if bust_timer > 0.0:
		bust_timer -= dt
		if bust_timer <= 0.0:
			_recover_busted()
		return
	if wanted_level <= 0 or dt <= 0.0:
		return
	if units.is_empty():
		_escape()
		return
	var seen := _line_of_sight()
	_update_search_state(dt,seen)
	if phase == "search" and search_clock >= float(Tactics.profile(wanted_level)["search_seconds"]):
		_escape()
		return
	if phase == "chase" and wanted_level >= 4 and seen and \
			last_seen_position_m.distance_to(roadblock_reference_m)>BLOCK_REEVALUATE_M:
		# Existing roadblock unit must physically reroute to the new location.
		# Never spawn a substitute ahead of the player.
		_choose_roadblock()
		route_clock = 0.0
	route_clock -= dt
	if route_clock <= 0.0:
		route_clock = ROUTE_INTERVAL
		_refresh_unit_route(next_unit)
		next_unit = (next_unit+1)%units.size()
	var officers: Array[Vector2] = []
	var nearest := INF
	for index in units.size():
		var entry: Dictionary=units[index]
		var officer: VehicleController2D=entry["car"]
		if not is_instance_valid(officer):
			continue
		var distance_m:=officer.global_position.distance_to(player.global_position)/PPM
		nearest = minf(nearest,distance_m)
		officers.append(officer.global_position/PPM)
		if phase == "chase" and str(entry.get("role",""))=="roadblock" and \
				roadblock_position_m.is_finite():
			var to_block:=officer.global_position.distance_to(roadblock_position_m*PPM)/PPM
			if to_block<20.0 and officer.linear_velocity.length()>5.0:
				entry["driver"].call("stop")
				officer.command=Vector4(0.0,1.0,0.0,0.0)
			if to_block<11.0 and officer.linear_velocity.length()<3.0:
				units[index]["blocking"]=true
		if bool(entry.get("blocking",false)) and phase=="chase":
			entry["driver"].call("stop")
			officer.command=Vector4(0.0,1.0,0.0,0.0)
		elif bool(entry.get("blocking",false)) and phase=="search":
			units[index]["blocking"]=false
	if phase == "chase" and seen:
		containment_seconds = Containment.progress(containment_seconds,dt,
			player.global_position/PPM,player.linear_velocity.length(),
			maxf(player.command.x,player.command.y),officers)
	else:
		containment_seconds = 0.0
	if Containment.is_busted(containment_seconds):
		_bust("BOXED IN")
		return
	# A disabled vehicle is only captured when police physically reach it
	# and actually see it, rather than through a map-wide psychic arrest.
	if seen and nearest <= 24.0 and is_instance_valid(damage_service) and \
			bool(damage_service.get("damage").call("is_disabled")):
		_bust("VEHICLE DISABLED")

func _process(dt: float) -> void:
	message_timer = maxf(0.0,message_timer-dt)
	if not is_instance_valid(readout):
		return
	if bust_timer > 0.0:
		readout.text = message
	elif wanted_level > 0 and phase == "search":
		var duration := float(Tactics.profile(wanted_level)["search_seconds"])
		readout.text = "WANTED %d / SEARCHING LAST SIGHTING / %ds / %d OFFICERS" % [
			wanted_level,ceili(maxf(0.0,duration-search_clock)),units.size()]
	elif wanted_level > 0:
		readout.text = "WANTED %d / %d OFFICERS / BOX-IN %.1f / %.0fs" % [
			wanted_level,units.size(),containment_seconds,Containment.CAPTURE_SECONDS]
	elif message_timer > 0.0:
		readout.text = "POLICE / "+message
	else:
		readout.text = "POLICE / CLEAR"
