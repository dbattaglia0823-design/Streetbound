extends Node2D
const VehicleScene = preload("res://scenes/vehicle.tscn")
const GroundScript = preload("res://scripts/world/proving_ground.gd")
const CoastScript = preload("res://scripts/world/morrow_coast.gd")
const TrafficFlowScript = preload("res://scripts/world/traffic_flow.gd")
const WorldHudScript = preload("res://scripts/world/world_map_hud.gd")
const CameraScript = preload("res://scripts/camera/driving_camera.gd")
const HudScript = preload("res://scripts/ui/driving_hud.gd")
const VehicleSelectorScript = preload("res://scripts/ui/vehicle_selector.gd")
const PlayerGarageScript = preload("res://scripts/world/player_garage.gd")
const DealerWorldScript = preload("res://scripts/world/dealership_world.gd")
const DealerMenuScript = preload("res://scripts/ui/dealership_menu.gd")
const OwnershipScript = preload("res://scripts/vehicle/vehicle_ownership.gd")
const DragRaceScript = preload("res://scripts/world/ashford_ai_race.gd")
const CircuitPracticeScript = preload("res://scripts/world/ashford_circuit_practice.gd")
const StreetSprintScript = preload("res://scripts/world/larkspur_street_sprint.gd")
const ProgressHudScript = preload("res://scripts/ui/driver_car_progress_hud.gd")
const AudioScript = preload("res://scripts/audio/vehicle_audio.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
const DustScript = preload("res://scripts/visual/driving_dust.gd")
const SpeedOverlayScript = preload("res://scripts/visual/speed_overlay.gd")
var pause_menu
var player_garage: Node2D
var dealership_world: Node2D
var dealership_menu: CanvasLayer
# Use the already-preloaded ownership class instead of relying on the
# editor's global class cache during startup on Godot 4.6.x.
var vehicle_ownership: OwnershipScript
var drag_race: Node2D
var circuit_race: Node2D
var street_race: Node2D
var progression_hud: CanvasLayer
var vehicle: VehicleController2D
@export var proving_ground := false
var ground: Node2D

func _ready() -> void:
	ground = GroundScript.new() if proving_ground else CoastScript.new()
	add_child(ground)
	if not proving_ground:
		vehicle_ownership = OwnershipScript.new()
	vehicle = VehicleScene.instantiate()
	vehicle.position = Vector2(0, 500) if proving_ground else ground.spawn_position()
	vehicle.rotation = 0.0 if proving_ground else ground.spawn_rotation()
	vehicle.surface_provider = ground
	add_child(vehicle)
	vehicle.add_to_group("player_vehicle")
	ground.vehicle = vehicle
	if not proving_ground:
		# Traffic uses the same baked Morrow road curves/intersections as roads
		# and the map editor. It has no influence on the player's handling.
		var traffic := Node2D.new()
		traffic.name = "AmbientTraffic"
		traffic.set_script(TrafficFlowScript)
		traffic.world = ground
		traffic.player = vehicle
		ground.add_child(traffic)
		# World roads/traffic stay below the player in the 2D draw stack.
		vehicle.z_index = 8
		# The existing Laurel Motor House building is a real drive-in garage.
		player_garage = Node2D.new()
		player_garage.set_script(PlayerGarageScript)
		player_garage.world = ground
		player_garage.player = vehicle
		ground.add_child(player_garage)
		# Curated storefronts reuse the existing dealer-building PNGs and roads.
		dealership_world = Node2D.new()
		dealership_world.set_script(DealerWorldScript)
		dealership_world.world = ground
		dealership_world.player = vehicle
		ground.dealerships = dealership_world
		ground.add_child(dealership_world)
		# Timed quarter-mile racing awards XP to the driver and ONLY the
		# vehicle equipped when the race begins.
		drag_race = Node2D.new()
		drag_race.set_script(DragRaceScript)
		drag_race.world = ground
		drag_race.player = vehicle
		drag_race.economy = vehicle_ownership
		ground.add_child(drag_race)
		# A real closed-course practice lap exercises curvature-based braking
		# guidance before additional circuit race formats and AI are added.
		circuit_race = Node2D.new()
		circuit_race.set_script(CircuitPracticeScript)
		circuit_race.world = ground
		circuit_race.player = vehicle
		ground.add_child(circuit_race)
		# Prototype a street sprint from legal connected ambient-traffic
		# directions. Racing-line guidance uses the same directed lane graph.
		street_race = Node2D.new()
		street_race.set_script(StreetSprintScript)
		street_race.world = ground
		street_race.player = vehicle
		street_race.network = traffic.get("network") as RefCounted
		street_race.traffic = traffic
		ground.add_child(street_race)
	var dust := Node2D.new()
	dust.name = "DrivingDust"
	dust.set_script(DustScript)
	dust.vehicle = vehicle
	add_child(dust)
	# World-space particles should draw behind the car, never over the sprite.
	move_child(dust, vehicle.get_index())
	var camera := Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.set_script(CameraScript)
	camera.target = vehicle
	add_child(camera)
	camera.add_to_group("player_camera")
	var speed_layer := CanvasLayer.new()
	speed_layer.name = "SpeedFXLayer"
	speed_layer.layer = 1
	var overlay := Node2D.new()
	overlay.name = "SpeedOverlay"
	overlay.set_script(SpeedOverlayScript)
	overlay.vehicle = vehicle
	overlay.camera = camera
	speed_layer.add_child(overlay)
	add_child(speed_layer)
	var audio := Node.new()
	audio.set_script(AudioScript)
	audio.vehicle = vehicle
	add_child(audio)
	var hud := CanvasLayer.new()
	hud.layer = 2
	hud.set_script(HudScript)
	hud.vehicle = vehicle
	hud.camera = camera
	hud.race = drag_race
	if not proving_ground:
		hud.environment_title = "MORROW COAST    /    OPEN ROAD"
		get_window().title = "Streetbound | Morrow Coast"
	add_child(hud)
	if not proving_ground:
		progression_hud = CanvasLayer.new()
		progression_hud.set_script(ProgressHudScript)
		progression_hud.economy = vehicle_ownership
		add_child(progression_hud)
	if not proving_ground:
		var world_hud := CanvasLayer.new()
		world_hud.layer = 3
		world_hud.set_script(WorldHudScript)
		world_hud.world = ground
		world_hud.vehicle = vehicle
		world_hud.races.append(drag_race)
		world_hud.races.append(circuit_race)
		world_hud.races.append(street_race)
		world_hud.driving_hud = hud
		add_child(world_hud)
	# CanvasLayer 20 is PROCESS_MODE_ALWAYS; menu controls work while paused.
	pause_menu = PauseMenuScript.new()
	pause_menu.name = "PauseMenu"
	pause_menu.vehicle_audio = audio
	pause_menu.driving_camera = camera
	add_child(pause_menu)
	var selector := CanvasLayer.new()
	selector.set_script(VehicleSelectorScript)
	selector.player = vehicle
	selector.driving_hud = hud
	selector.pause_menu = pause_menu
	selector.garage = player_garage
	selector.inventory = vehicle_ownership
	add_child(selector)
	selector.restore_selection()
	if not proving_ground:
		dealership_menu = CanvasLayer.new()
		dealership_menu.set_script(DealerMenuScript)
		dealership_menu.manager = dealership_world
		dealership_menu.player = vehicle
		dealership_menu.economy = vehicle_ownership
		add_child(dealership_menu)
