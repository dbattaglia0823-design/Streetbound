extends Node2D
## Single-player, driving-only police pursuit prototype. Police are actual
## VehicleController2D instances obeying road geometry and vehicle physics.
## Host-authoritative multiplayer police are intentionally out of scope.
const PPM := 20.0
const VehicleScene = preload("res://scenes/vehicle.tscn")
const DriverScript = preload("res://scripts/world/race_ai_driver.gd")
const PlannerScript = preload("res://scripts/world/road_route_planner.gd")
const Containment = preload("res://scripts/world/police_containment.gd")
const ROUTE_INTERVAL := 1.4
const LOSE_CONTACT_M := 180.0
const SEARCH_SECONDS := 10.0
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
	# F7 is an explicit developer smoke-test trigger, not a player-facing
	# crime shortcut. Street racing triggers pursuits in ordinary gameplay.

func _unhandled_input(event: InputEvent) -> void:
	if not OS.has_feature("debug") or not event is InputEventKey:
		return
	if event.pressed and not event.echo and event.keycode == KEY_F7 and wanted_level == 0:
		start_pursuit(1)
		get_viewport().set_input_as_handled()

func _on_player_reset() -> void:
	# Reset must never be a free escape from police or a damage repair.
	if wanted_level > 0 and bust_timer <= 0.0:
		_bust("VEHICLE RESET DURING PURSUIT")

func _race_trigger() -> void:
	# Remember each run separately: losing a chase while a race is still
	# active cannot repeatedly relaunch police every physics frame.
	for race in street_races:
		if not is_instance_valid(race):
			continue
		var id: int = race.get_instance_id()
		var running: bool = str(race.get("state")) == "running"
		if not running:
			race_active_ids.erase(id)
			continue
		if race_active_ids.has(id):
			continue
		race_active_ids[id] = true
		if wanted_level == 0 and bust_timer <= 0.0:
			start_pursuit(1)

func _spawn_candidates() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var origin := player.global_position
	var road_network: RefCounted = traffic.get("network")
	if road_network == null:
		return options
	for edge in road_network.get("edges"):
		if bool(edge.get("connector", false)):
			continue
		var points: PackedVector2Array = edge.points
		if points.size() < 2:
			continue
		for endpoint in [0, points.size() - 1]:
			var position: Vector2 = points[endpoint]
			var distance := position.distance_to(origin) / PPM
			if distance < 70.0 or distance > 145.0:
				continue
			var tangent: Vector2 = points[1] - points[0] if endpoint == 0 else points[-1] - points[-2]
			if tangent.length_squared() < 1.0:
				continue
			options.append({"position": position, "heading": tangent.normalized(),
				"distance": distance})
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a.distance) - 100.0) < absf(float(b.distance) - 100.0))
	return options

func _spawn_units() -> void:
	var options := _spawn_candidates()
	var selected: Array[Vector2] = []
	for option in options:
		if units.size() >= 3:
			break
		var point: Vector2 = option.position
		var separated := true
		for prior in selected:
			if prior.distance_to(point) < 30.0 * PPM:
				separated = false
				break
		if not separated:
			continue
		var car: VehicleController2D = VehicleScene.instantiate() as VehicleController2D
		if car == null:
			continue
		car.name = "PoliceUnit%d" % (units.size() + 1)
		car.external_input = true
		car.surface_provider = world
		car.collision_layer = 1
		car.collision_mask = 3
		car.position = point
		car.rotation = Vector2.UP.angle_to(Vector2(option.heading))
		car.z_index = 8
		car.add_to_group("police_vehicle")
		add_child(car)
		var identifier := Label.new()
		identifier.text = "POLICE"
		identifier.position = Vector2(-27, -61)
		identifier.add_theme_font_size_override("font_size", 12)
		car.add_child(identifier)
		var driver := Node.new()
		driver.set_script(DriverScript)
		driver.set("reaction_seconds", 0.0)
		driver.set("throttle_limit", 0.88)
		add_child(driver)
		units.append({"car": car, "driver": driver})
		selected.append(point)
	for index in units.size():
		_refresh_unit_route(index)

func _refresh_unit_route(index: int) -> void:
	if planner == null or index < 0 or index >= units.size():
		return
	var car: VehicleController2D = units[index].car
	var driver: Node = units[index].driver
	if not is_instance_valid(car) or not is_instance_valid(driver):
		return
	var forward := Vector2.UP.rotated(player.rotation)
	var right := Vector2.RIGHT.rotated(player.rotation)
	# Different pursuit positions encourage a real physical containment,
	# not teleporting or a scripted instant-arrest radius.
	var offset := -forward * 5.0 if index == 0 else forward * 5.0 + right * (-5.0 if index == 1 else 5.0)
	var target_m := player.global_position / PPM + offset
	var route: Dictionary = planner.call("plan", car.global_position / PPM, target_m,
		Vector2.UP.rotated(car.rotation))
	if route.is_empty():
		# A failed road route means stop, never cut across solid buildings.
		driver.call("stop")
		return
	var points: PackedVector2Array = route.points_m
	var route_px := PackedVector2Array()
	for p in points:
		route_px.append(p * PPM)
	driver.call("setup", car, route_px)
	driver.call("launch")

func start_pursuit(level: int = 1) -> bool:
	if wanted_level > 0 or not is_instance_valid(player) or not is_instance_valid(traffic):
		return false
	wanted_level = clampi(level, 1, 5)
	search_clock = 0.0
	containment_seconds = 0.0
	route_clock = 0.0
	next_unit = 0
	_spawn_units()
	if units.is_empty():
		wanted_level = 0
		message = "NO POLICE ROUTE AVAILABLE"
		message_timer = 3.0
		return false
	return true

func _despawn_units() -> void:
	for entry in units:
		var driver: Node = entry.driver
		var car: VehicleController2D = entry.car
		if is_instance_valid(driver):
			driver.queue_free()
		if is_instance_valid(car):
			car.queue_free()
	units.clear()

func _escape() -> void:
	wanted_level = 0
	containment_seconds = 0.0
	message = "ESCAPED"
	message_timer = 3.0
	_despawn_units()

func _bust(reason: String) -> void:
	if wanted_level <= 0 or bust_timer > 0.0:
		return
	bust_reason = reason
	bust_timer = 2.0
	message = "BUSTED / " + reason
	message_timer = 4.0
	for entry in units:
		if is_instance_valid(entry.driver):
			entry.driver.call("stop")
	player.damage_drive_fraction = 0.0

func _recover_busted() -> void:
	var prior_level := wanted_level
	wanted_level = 0
	_despawn_units()
	if is_instance_valid(economy):
		var fee := mini(int(economy.balance), 1500 * prior_level)
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

func _physics_process(dt: float) -> void:
	if not is_instance_valid(player):
		return
	_race_trigger()
	if bust_timer > 0.0:
		bust_timer -= dt
		if bust_timer <= 0.0:
			_recover_busted()
		return
	if wanted_level <= 0:
		return
	if is_instance_valid(damage_service) and bool(damage_service.get("damage").call("is_disabled")):
		_bust("VEHICLE DISABLED")
		return
	if units.is_empty():
		_escape()
		return
	route_clock -= dt
	if route_clock <= 0.0:
		route_clock = ROUTE_INTERVAL
		_refresh_unit_route(next_unit)
		next_unit = (next_unit + 1) % units.size()
	var nearest := INF
	var officers: Array[Vector2] = []
	for entry in units:
		var officer: VehicleController2D = entry.car
		if not is_instance_valid(officer):
			continue
		var distance_m := officer.global_position.distance_to(player.global_position) / PPM
		nearest = minf(nearest, distance_m)
		officers.append(officer.global_position / PPM)
	containment_seconds = Containment.progress(containment_seconds, dt,
		player.global_position / PPM, player.linear_velocity.length(),
		maxf(player.command.x, player.command.y), officers)
	if Containment.is_busted(containment_seconds):
		_bust("BOXED IN")
		return
	if nearest > LOSE_CONTACT_M:
		search_clock += dt
		if search_clock >= SEARCH_SECONDS:
			_escape()
	else:
		search_clock = 0.0

func _process(dt: float) -> void:
	message_timer = maxf(0.0, message_timer - dt)
	if not is_instance_valid(readout):
		return
	if bust_timer > 0.0:
		readout.text = message
	elif wanted_level > 0:
		readout.text = "WANTED %d  /  %d POLICE  /  BOX-IN %.1f / %.0fs" % [
			wanted_level, units.size(), containment_seconds, Containment.CAPTURE_SECONDS]
	elif message_timer > 0.0:
		readout.text = "POLICE / " + message
	else:
		readout.text = "POLICE / CLEAR"
