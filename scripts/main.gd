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
const QuickUpgradesScript = preload("res://scripts/ui/quick_upgrades_overlay.gd")
const LocalSplitScript = preload("res://scripts/ui/local_split_screen.gd")
const NativeWorldEditorScript = preload("res://scripts/dev/native_world_editor.gd")
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
var quick_upgrades: CanvasLayer
var local_split_screen
var native_world_editor: CanvasLayer
var vehicle: VehicleController2D
@export var proving_ground := false
var ground: Node2D

func _ready() -> void:
	ground = GroundScript.new() if proving_ground else CoastScript.new()
	add_child(ground)
	if not proving_ground and not ground.initialization_complete:
		# Do not start traffic/garages against incomplete spatial indices.
		ground.set_performance_debug(true)
		return
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
	# On Morrow Coast, the spawn is a parking lot roughly 42m from its
	# garage building and 46m from the nearest houses. Show that neighborhood
	# before accelerating, then return to normal driver-controlled zoom.
	camera.startup_neighborhood_view = not proving_ground
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
		progression_hud.host = hud.progression_slot
		add_child(progression_hud)
		hud.show_unified_progression()
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
		# Accessible from anywhere, not restricted to the physical garage.
		# The live world remains visible behind a pause-safe transparent HUD.
		quick_upgrades = CanvasLayer.new()
		quick_upgrades.set_script(QuickUpgradesScript)
		quick_upgrades.economy = vehicle_ownership
		quick_upgrades.vehicle = vehicle
		add_child(quick_upgrades)
	if not proving_ground:
		dealership_menu = CanvasLayer.new()
		dealership_menu.set_script(DealerMenuScript)
		dealership_menu.manager = dealership_world
		dealership_menu.player = vehicle
		dealership_menu.economy = vehicle_ownership
		add_child(dealership_menu)
	# One world, two cars, two cameras. This manager never creates a second
	# Morrow Coast instance or touches the single-player career save.
	local_split_screen = CanvasLayer.new()
	local_split_screen.set_script(LocalSplitScript)
	local_split_screen.player_one = vehicle
	local_split_screen.world = ground
	local_split_screen.inventory = vehicle_ownership
	local_split_screen.main_camera = camera
	var hidden: Array[CanvasLayer] = []
	for node in get_children():
		if node is CanvasLayer and node != pause_menu:
			hidden.append(node)
	local_split_screen.hidden_layers = hidden
	var disabled: Array[Node] = []
	for system in [player_garage,dealership_world,drag_race,circuit_race,street_race]:
		if is_instance_valid(system):
			disabled.append(system)
	local_split_screen.disabled_systems = disabled
	add_child(local_split_screen)
	pause_menu.split_screen_requested.connect(_toggle_local_split_screen)
	# This is a developer-only transition workspace. It renders the EXISTING
	# Morrow Coast scene and visualizes the traffic network already built by
	# the game. Release players cannot open it, and it never writes map files.
	if not proving_ground and (OS.has_feature("debug") or OS.has_feature("editor")):
		native_world_editor = CanvasLayer.new()
		native_world_editor.set_script(NativeWorldEditorScript)
		native_world_editor.world = ground
		native_world_editor.player = vehicle
		native_world_editor.driving_camera = camera
		var ambient_traffic: Node = ground.get_node_or_null("AmbientTraffic")
		if is_instance_valid(ambient_traffic):
			native_world_editor.traffic_network = ambient_traffic.get("network")
		add_child(native_world_editor)


func _toggle_local_split_screen() -> void:
	if not is_instance_valid(local_split_screen):
		return
	if local_split_screen.active:
		local_split_screen.stop_split()
		pause_menu.set_split_screen_active(false)
		pause_menu.resume_game()
	elif local_split_screen.start_split():
		pause_menu.set_split_screen_active(true)
		pause_menu.resume_game()
	else:
		pause_menu.show_split_screen_error(local_split_screen.warning)
