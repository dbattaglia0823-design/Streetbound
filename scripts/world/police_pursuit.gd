extends Node2D
## Single-player physical police pursuit. Police NEVER teleport during a chase,
## receive engine/grip boosts, or spawn ahead in the driver's travel corridor.
## Multiplayer host-authoritative officers remain a separate future feature.
signal busted(reason: String)
signal escaped
const PPM := 20.0
const HudStyle = preload("res://scripts/ui/driving_hud.gd")
const VehicleScene = preload("res://scenes/vehicle.tscn")
const DriverScript = preload("res://scripts/world/race_ai_driver.gd")
const PlannerScript = preload("res://scripts/world/road_route_planner.gd")
const Containment = preload("res://scripts/world/police_containment.gd")
const Tactics = preload("res://scripts/world/police_tactics.gd")
const DamageState = preload("res://scripts/vehicle/vehicle_damage.gd")
const DamageSmoke = preload("res://scripts/visual/engine_damage_smoke.gd")
const VehicleCatalog = preload("res://scripts/vehicle/player_vehicle_catalog.gd")
const EmergencyEffects = preload("res://scripts/visual/police_emergency_effects.gd")
const REPLACEMENT_DELAY := 40.0
const PATROL_ASSIST_M := 140.0
const POLICE_CATALOG_PATH := "res://data/police_vehicle_catalog.json"
static var _police_models: Array[Dictionary] = []
const ROUTE_INTERVAL := 0.75
const SEARCH_SWEEP_INTERVAL := 4.5
const DISPATCH_RETRY_SECONDS := 3.0
const DISPATCH_TIMEOUT_SECONDS := 18.0
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
var dispatch_clock := 0.0
var dispatch_retry_clock := 0.0
var lost_sight_clock := 0.0
var search_round := 0
var phase := "clear"
var last_seen_position_m := Vector2.ZERO
var last_seen_velocity_mps := Vector2.ZERO
var last_seen_heading := Vector2.UP
var last_seen_road_layer := 0
var roadblock_position_m := Vector2.INF
var roadblock_reference_m := Vector2.INF
var containment_seconds := 0.0
var bust_timer := 0.0
var bust_reason := ""
var race_active_ids: Dictionary = {}
var message := ""
var message_timer := 0.0
var readout: Label
var status_host: VBoxContainer
var pursuit_panel: PanelContainer
var wanted_stars: Label
var pursuit_meter: ProgressBar
var replacement_timers: Array[float] = []
var reinforcement_clock := 0.0
var _unit_serial := 0
var shared_session := false
var pit_cooldown := 0.0

func _ready() -> void:
	name = "PolicePursuit"
	add_to_group("streetbound_police")
	if not is_instance_valid(player) or not is_instance_valid(world) or not is_instance_valid(traffic):
		return
	planner = PlannerScript.new()
	planner.call("setup", traffic.get("network"), world.get("data"))
	player.vehicle_reset.connect(_on_player_reset)
	if not shared_session:
		player.police_collision.connect(_on_player_police_collision, CONNECT_DEFERRED)
	# OnlineWorld presents the target-specific network HUD, not a duplicate solo card.
	if not shared_session:
		var parent: Node = status_host
		if not is_instance_valid(parent):
			var layer := CanvasLayer.new()
			layer.layer = 5
			add_child(layer)
			parent = layer
		pursuit_panel = HudStyle.status_card(parent,Color("#ed796c"))
		if not is_instance_valid(status_host):
			pursuit_panel.position = Vector2(16,16)
		var col := VBoxContainer.new()
		pursuit_panel.add_child(col)
		HudStyle.status_text(col,"POLICE PURSUIT",11,Color("#ed796c"))
		wanted_stars = HudStyle.status_text(col,"",22,Color("#ed796c"))
		readout = HudStyle.status_text(col,"",13,Color("#eaf2e8"))
		pursuit_meter = HudStyle.status_bar(col,Color("#ed796c"))
	# Heat originates from race and crime controllers; no player debug shortcut.

func set_shared_target(target: VehicleController2D) -> bool:
	if not shared_session or wanted_level > 0 or not is_instance_valid(target):
		return false
	if is_instance_valid(player) and player.vehicle_reset.is_connected(_on_player_reset):
		player.vehicle_reset.disconnect(_on_player_reset)
	player = target
	player.vehicle_reset.connect(_on_player_reset)
	return true

func _on_player_police_collision(closing_speed_mps: float) -> void:
	if shared_session or wanted_level > 0 or bust_timer > 0.0 or not is_physics_processing():
		return
	if not is_finite(closing_speed_mps) or closing_speed_mps < VehicleController2D.POLICE_CRASH_THRESHOLD_MPS:
		return
	if start_pursuit(1):
		message = "POLICE VEHICLE COLLISION"
		message_timer = 3.0

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
		# The race director alone declares heat. Ordinary sanctioned
		# races are not criminal merely because their course uses streets.
		continue

func _travel_heading() -> Vector2:
	if player.linear_velocity.length() > 3.0:
		return player.linear_velocity.normalized()
	return Vector2.UP.rotated(player.rotation)

func _camera_sees(position_px: Vector2) -> bool:
	if is_instance_valid(traffic) and traffic.has_method("_visible_to_any_player") and traffic.call("_visible_to_any_player", position_px):
		return true
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
			if absf(float(sample.get("height_m",0.0)))>.05:continue
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
			if absf(float(sample.get("height_m",0.0)))>.05:continue
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

## Police-only roster; never added to dealership or player saves.
static func vehicle_pool(level: int) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if level <= 0:
		return pool
	if _police_models.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POLICE_CATALOG_PATH))
		if parsed is Dictionary:
			for model in parsed.get("vehicles", []):
				if model is Dictionary:
					_police_models.append(model)
	for model in _police_models:
		if int(model["min_wanted"]) <= level:
			pool.append(model.duplicate(true))
	return pool

## Prefer one newly unlocked responder, then sample the cumulative fleet
## without replacement. At levels 4 and 5 the first responder is armored.
static func response_order(level: int) -> Array[Dictionary]:
	var pool := vehicle_pool(level)
	pool.shuffle()
	var newest := mini(level, 4)
	for index in pool.size():
		if int(pool[index]["min_wanted"]) == newest:
			var priority: Dictionary = pool.pop_at(index)
			pool.push_front(priority)
			break
	return pool

static func apply_police_model(car: VehicleController2D, model: Dictionary) -> bool:
	if model.is_empty() or not ResourceLoader.exists(str(model["texture"]), "Texture2D"):
		return false
	if not VehicleCatalog.select(car, model):
		return false
	# The armored artwork already contains tires; don't draw a second set.
	var wheels := car.get_node_or_null("Art/Wheels") as Node2D
	if wheels != null:
		wheels.visible = not bool(model.get("baked_wheels", false))
	return true

func active_limit() -> int:
	return int(Tactics.profile(wanted_level)["units"]) if wanted_level > 0 else 0

func available_slots() -> int:
	return maxi(0, active_limit() - units.size() - replacement_timers.size())

func _advance_replacements(dt: float) -> void:
	for index in range(replacement_timers.size()-1,-1,-1):
		replacement_timers[index] -= dt
		if replacement_timers[index] <= 0.0:
			replacement_timers.remove_at(index)

func _remove_destroyed_units() -> void:
	for index in range(units.size()-1,-1,-1):
		var entry: Dictionary = units[index]
		var car: VehicleController2D = entry["car"]
		if is_instance_valid(car) and not entry["damage"].call("is_disabled"):
			continue
		if is_instance_valid(entry["driver"]):
			entry["driver"].queue_free()
		if is_instance_valid(car):
			car.queue_free()
		units.remove_at(index)
		replacement_timers.append(REPLACEMENT_DELAY)
	if not units.is_empty():
		next_unit = posmod(next_unit, units.size())

func _attach_responder(model: Dictionary, pose: Transform2D, speed_mps: float = 0.0) -> bool:
	var car := VehicleScene.instantiate() as VehicleController2D
	if car == null:
		return false
	car.name = "PoliceUnit%d" % _unit_serial
	_unit_serial += 1
	car.external_input = true
	car.surface_provider = world
	car.collision_layer = 1
	car.collision_mask = 7 if shared_session else 3
	car.transform = pose
	car.z_index = 8
	car.add_to_group("police_vehicle")
	add_child(car)
	if not apply_police_model(car, model):
		remove_child(car)
		car.queue_free()
		return false
	car.linear_velocity = Vector2.UP.rotated(car.rotation) * speed_mps
	car.velocity = car.linear_velocity * PPM
	car.longitudinal_speed = speed_mps
	var health = DamageState.new()
	health.max_health_points = car.config.max_health_points
	var smoke := Node2D.new()
	smoke.set_script(DamageSmoke)
	smoke.set("vehicle", car)
	car.add_child(smoke)
	car.damage_contact.connect(_on_officer_impact.bind(car, health, smoke))
	EmergencyEffects.attach(car, model)
	var identifier := Label.new()
	identifier.text = "POLICE"
	identifier.position = Vector2(-27,-61)
	identifier.add_theme_font_size_override("font_size",12)
	car.add_child(identifier)
	var profile: Dictionary = Tactics.profile(wanted_level)
	var ai := Node.new()
	ai.set_script(DriverScript)
	ai.set("reaction_seconds",0.2)
	ai.set("throttle_limit",float(profile["throttle"]))
	ai.set("cruise_speed_mps",float(profile["cruise_mps"]))
	add_child(ai)
	var role := Tactics.role(units.size(), wanted_level)
	if wanted_level >= 4:
		var has_block := false
		for entry in units:
			if entry["role"] == "roadblock":
				has_block = true
		if units.size() >= 3 and not has_block:
			role = "roadblock"
		elif role == "roadblock" and has_block:
			role = "intercept"
	units.append({"car":car,"driver":ai,"role":role,"blocking":false,
		"label":identifier,"damage":health,"model_id":model["id"],"serial":_unit_serial})
	_refresh_unit_route(units.size()-1)
	return true

func _recruit_patrols() -> void:
	if available_slots() <= 0 or not is_instance_valid(traffic) or not traffic.has_method("release_patrol") or not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("police_patrol"):
		if available_slots() <= 0:
			break
		if not is_instance_valid(node) or node.is_queued_for_deletion() or bool(node.get("recovering")):
			continue
		var model: Dictionary = node.get("patrol_model")
		if model.is_empty() or int(model["min_wanted"]) > wanted_level:
			continue
		var distance_m := (node as Node2D).global_position.distance_to(player.global_position)/PPM
		if distance_m > PATROL_ASSIST_M or absf(float(node.get_meta("traffic_height_m",0.0)))>.05:
			continue
		var patrol := node as CharacterBody2D
		if patrol == null:
			continue
		var excluded: Array[RID] = [player.get_rid(), patrol.get_rid()]
		var ray := PhysicsRayQueryParameters2D.create(patrol.global_position, player.global_position, 1, excluded)
		var visible_now := absf(player.elevation_m)<2.4 and get_world_2d().direct_space_state.intersect_ray(ray).is_empty()
		if not visible_now and (phase != "chase" or patrol.global_position.distance_to(last_seen_position_m*PPM) > 65.0*PPM):
			continue
		var pose: Transform2D = node.global_transform
		var speed := float(node.get("motion_speed_mps"))
		if _attach_responder(model, global_transform.affine_inverse()*pose, speed):
			traffic.call("release_patrol", node)

func _spawn_units() -> void:
	if available_slots() <= 0:
		return
	var options := _spawn_candidates()
	var selected: Array[Vector2] = []
	for entry in units:
		if is_instance_valid(entry["car"]):
			selected.append(entry["car"].global_position/PPM)
	var response := response_order(wanted_level)
	if response.is_empty():
		return
	var model_index := 0
	for option in options:
		if available_slots() <= 0:
			break
		var position_m: Vector2 = option["position_m"]
		if not Tactics.safe_spawn(position_m,player.global_position/PPM,
				_travel_heading(),selected):
			continue
		var model: Dictionary = response[model_index % response.size()]
		model_index += 1
		var pose := Transform2D(Vector2.UP.angle_to(Vector2(option["heading"])), option["position"])
		if _attach_responder(model, pose):
			selected.append(position_m)

func _on_officer_impact(speed_mps: float, _contact: Vector2, _normal: Vector2,
		_velocity: Vector2, car: VehicleController2D, health: RefCounted, smoke: Node2D) -> void:
	if not is_instance_valid(car):
		return
	var applied: float = health.call("register_impact", speed_mps, Time.get_ticks_msec() / 1000.0)
	if applied <= 0.0:
		return
	car.damage_drive_fraction = float(health.call("drive_fraction"))
	if is_instance_valid(smoke):
		smoke.call("set_health_percentage", health.call("health_percentage"))
	DamageState.show_damage_number(car, applied, true)

func _refresh_unit_route(index: int) -> void:
	if planner == null or index < 0 or index >= units.size():
		return
	var entry: Dictionary = units[index]
	var car: VehicleController2D = entry["car"]
	var driver: Node = entry["driver"]
	if not is_instance_valid(car) or not is_instance_valid(driver):
		return
	if car.damage_drive_fraction <= 0.0 or bool(entry.get("blocking",false)):
		driver.call("stop")
		car.command = Vector4(0.0,1.0,0.0,0.0)
		return
	var role_name := str(entry.get("role","pursuer"))
	var approach_distance_m := car.global_position.distance_to(last_seen_position_m*PPM)/PPM
	var boxing := phase=="chase" and wanted_level>=3 and role_name!="roadblock" and \
		last_seen_velocity_mps.length()<5.0 and approach_distance_m<28.0
	var profile: Dictionary=Tactics.profile(wanted_level)
	# Search and box-in are careful low-speed maneuvers. Never boost engines.
	driver.set("cruise_speed_mps",5.5 if boxing else \
		(13.0 if phase=="search" else float(profile["cruise_mps"])))
	var goal_m := last_seen_position_m
	var goal_layer := last_seen_road_layer
	driver.set("pit_target", null)
	if car.has_meta("police_pit_target"):
		car.remove_meta("police_pit_target")
	if role_name == "pit" and phase == "chase" and absf(car.elevation_m-player.elevation_m)<1.2 and Tactics.pit_allowed(wanted_level, lost_sight_clock <= 0.0, approach_distance_m, last_seen_velocity_mps.length(), pit_cooldown):
		driver.set("pit_target", player)
		car.set_meta("police_pit_target", player.get_instance_id())
		car.set_meta("police_pit_owner", self)
	if boxing:
		goal_m=Tactics.containment_target(last_seen_position_m,last_seen_heading,role_name)
	elif phase == "search":
		goal_m = Tactics.search_target(last_seen_position_m,last_seen_heading,index,search_round)
	elif str(entry.get("role","pursuer"))=="roadblock":
		if roadblock_position_m.is_finite():
			goal_m = roadblock_position_m
			goal_layer = 0
		else:
			goal_m = Tactics.intercept_target(last_seen_position_m,
				last_seen_velocity_mps,last_seen_heading,"flank_right",wanted_level)
	else:
		goal_m = Tactics.intercept_target(last_seen_position_m,
			last_seen_velocity_mps,last_seen_heading,str(entry.get("role","pursuer")),wanted_level)
	var route: Dictionary=planner.call("plan",car.global_position/PPM,goal_m,
		Vector2.UP.rotated(car.rotation),"","",car.road_layer,goal_layer)
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
		if not is_instance_valid(officer) or officer.damage_drive_fraction <= 0.0:
			continue
		var distance_m:=officer.global_position.distance_to(player.global_position)/PPM
		if distance_m>sight_m or absf(officer.elevation_m-player.elevation_m)>2.4:
			continue
		# Only confirmed unobstructed sightings may update the suspect's
		# last known location. Buildings, walls and traffic can hide the car.
		var params:=PhysicsRayQueryParameters2D.create(
			officer.global_position,player.global_position,officer.collision_mask,exclusion)
		var hit: Dictionary=get_world_2d().direct_space_state.intersect_ray(params)
		if Tactics.visible(distance_m,wanted_level,not hit.is_empty()):
			return true
	return false

func start_pursuit(level: int = 1) -> bool:
	if wanted_level > 0 or not is_instance_valid(player) or not is_instance_valid(traffic):
		return false
	wanted_level = clampi(level,1,5)
	replacement_timers.clear()
	reinforcement_clock = DISPATCH_RETRY_SECONDS
	pit_cooldown = 0.0
	phase = "chase"
	last_seen_position_m = player.global_position / PPM
	last_seen_road_layer = player.road_layer
	last_seen_velocity_mps = player.linear_velocity
	last_seen_heading = _travel_heading()
	lost_sight_clock = 0.0
	search_clock = 0.0
	dispatch_clock = 0.0
	dispatch_retry_clock = DISPATCH_RETRY_SECONDS
	search_round = 0
	containment_seconds = 0.0
	route_clock = 0.0
	next_unit = 0
	roadblock_position_m = Vector2.INF
	roadblock_reference_m = Vector2.INF
	_choose_roadblock()
	_recruit_patrols()
	_spawn_units()
	if units.is_empty():
		# Do not cancel a robbery or materialize an ambush simply because
		# the local roads/camera offer no safe initial response lane.
		phase = "dispatch"
		message = "POLICE DISPATCH / UNITS RESPONDING"
		message_timer = 3.0
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
	replacement_timers.clear()

func _escape() -> void:
	wanted_level = 0
	phase = "clear"
	containment_seconds = 0.0
	search_clock = 0.0
	lost_sight_clock = 0.0
	dispatch_clock = 0.0
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
	if shared_session:
		player.damage_drive_fraction = 1.0
	if is_instance_valid(damage_service):
		damage_service.impound_recovery()
	containment_seconds = 0.0
	search_clock = 0.0
	lost_sight_clock = 0.0
	dispatch_clock = 0.0

func _update_search_state(dt: float, seen: bool) -> void:
	if seen:
		# Confirmed police sighting; only here can dispatch refresh its
		# knowledge of the suspect's position, speed and travel direction.
		last_seen_position_m = player.global_position / PPM
		last_seen_road_layer = player.road_layer
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
	_advance_replacements(dt)
	_remove_destroyed_units()
	pit_cooldown = maxf(0.0, pit_cooldown-dt)
	if units.is_empty() and not replacement_timers.is_empty() and available_slots() <= 0:
		phase = "dispatch"
		dispatch_clock = 0.0
		return
	if units.is_empty() and phase != "dispatch":
		phase = "dispatch"
		dispatch_clock = 0.0
		dispatch_retry_clock = 0.0
	if units.is_empty():
		if phase == "dispatch":
			dispatch_clock += dt
			dispatch_retry_clock -= dt
			if dispatch_retry_clock <= 0.0:
				dispatch_retry_clock = DISPATCH_RETRY_SECONDS
				_recruit_patrols()
				_spawn_units()
				if not units.is_empty():
					phase = "chase"
					lost_sight_clock = 0.0
			if units.is_empty() and dispatch_clock >= DISPATCH_TIMEOUT_SECONDS:
				_escape()
			return
		_escape()
		return
	var seen := _line_of_sight()
	_update_search_state(dt,seen)
	reinforcement_clock -= dt
	if reinforcement_clock <= 0.0 and phase == "chase":
		reinforcement_clock = DISPATCH_RETRY_SECONDS
		_recruit_patrols()
		_spawn_units()
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
		if officer.damage_drive_fraction <= 0.0:
			entry["driver"].call("stop")
			officer.command = Vector4(0.0, 1.0, 0.0, 0.0)
			continue
		var distance_m:=officer.global_position.distance_to(player.global_position)/PPM
		if absf(officer.elevation_m-player.elevation_m)<=1.2:
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
	pursuit_panel.visible = wanted_level>0
	if wanted_level<=0:
		return
	var heat := clampi(wanted_level,0,5)
	wanted_stars.text = "★".repeat(heat)+"☆".repeat(5-heat)
	pursuit_meter.visible = false
	if bust_timer > 0.0:
		readout.text = message
	elif phase == "dispatch":
		readout.text = "DISPATCHING RESPONDERS"
	elif phase == "search":
		var duration := maxf(0.1,float(Tactics.profile(wanted_level)["search_seconds"]))
		readout.text = "EVADING  /  %ds REMAINING\n%d RESPONDERS" % [ceili(maxf(0.0,duration-search_clock)),units.size()]
		pursuit_meter.visible = true
		pursuit_meter.value = clampf(search_clock/duration*100.0,0.0,100.0)
	else:
		readout.text = "PURSUIT ACTIVE  /  %d RESPONDERS" % units.size()
		if containment_seconds>0.0:
			readout.text += "\nBOXED IN  /  BREAK FREE"
			pursuit_meter.visible = true
			pursuit_meter.value = clampf(containment_seconds/Containment.CAPTURE_SECONDS*100.0,0.0,100.0)
