extends Node2D
@onready var online_session: Node = get_node_or_null("/root/OnlineSession")
const VehicleScene = preload("res://scenes/vehicle.tscn")
const GroundScript = preload("res://scripts/world/proving_ground.gd")
const CoastScript = preload("res://scripts/world/morrow_coast.gd")
const WorldPublication=preload("res://scripts/world/world_publication.gd")
const TrafficFlowScript = preload("res://scripts/world/traffic_flow.gd")
const WorldHudScript = preload("res://scripts/world/world_map_hud.gd")
const CameraScript = preload("res://scripts/camera/driving_camera.gd")
const RainVisuals = preload("res://scripts/visual/wet_road_effects.gd")
const HudScript = preload("res://scripts/ui/driving_hud.gd")
const VehicleAwarenessScript = preload("res://scripts/ui/offscreen_vehicle_awareness.gd")
const VehicleSelectorScript = preload("res://scripts/ui/vehicle_selector.gd")
const PlayerGarageScript = preload("res://scripts/world/player_garage.gd")
const DealerWorldScript = preload("res://scripts/world/dealership_world.gd")
const DealerMenuScript = preload("res://scripts/ui/dealership_menu.gd")
const OwnershipScript = preload("res://scripts/vehicle/vehicle_ownership.gd")
const DragRaceScript = preload("res://scripts/world/ashford_ai_race.gd")
const CircuitPracticeScript = preload("res://scripts/world/ashford_circuit_practice.gd")
const StreetSprintScript = preload("res://scripts/world/larkspur_street_sprint.gd")
const AuthoredRaceScript=preload("res://scripts/world/authored_race.gd")
const AuthoredMarkersScript=preload("res://scripts/world/authored_map_markers.gd")
const ProgressHudScript = preload("res://scripts/ui/driver_car_progress_hud.gd")
const AudioScript = preload("res://scripts/audio/vehicle_audio.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
const QuickUpgradesScript = preload("res://scripts/ui/quick_upgrades_overlay.gd")
const LocalSplitScript = preload("res://scripts/ui/local_split_screen.gd")
const OnlineWorldScript = preload("res://scripts/network/online_world.gd")
const NativeWorldEditorScript = preload("res://scripts/dev/native_world_editor.gd")
const SpeedOverlayScript = preload("res://scripts/visual/speed_overlay.gd")
const VehicleDamageServiceScript = preload("res://scripts/world/vehicle_damage_service.gd")
const PolicePursuitScript = preload("res://scripts/world/police_pursuit.gd")
static var pending_launch_mode := ""
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
var extra_races: Array[Node2D]=[]
var authored_map_markers: Node2D
var progression_hud: CanvasLayer
var quick_upgrades: CanvasLayer
var offscreen_vehicle_awareness: Control
var local_split_screen
var online_world: Node2D
var native_world_editor: CanvasLayer
var vehicle: VehicleController2D
var vehicle_damage_service: CanvasLayer
var police_pursuit: Node2D
@export var proving_ground := false
var ground: Node2D
var custom_test_drive:=false
var published_game_world:=false
var test_drive_file: String=""

func _ready() -> void:
	# Custom-map Test Drive is a real gameplay launch, not a separate mini-game.
	# The editor compiled its map to a user:// streamed archive before entry.
	custom_test_drive=not proving_ground and (OS.has_feature("debug") or OS.has_feature("editor")) and \
		get_tree().has_meta("streetbound_test_drive_archive")
	test_drive_file=str(get_tree().get_meta("streetbound_test_drive_map","")) if custom_test_drive else ""
	ground = GroundScript.new() if proving_ground else CoastScript.new()
	if custom_test_drive:
		ground.archive_override_path=str(get_tree().get_meta("streetbound_test_drive_archive"))
	elif not proving_ground:
		var active_world: Dictionary=WorldPublication.current()
		if bool(active_world.get("published",false)):
			ground.archive_override_path=str(active_world.archive)
	add_child(ground)
	# An invalid/missing compiled package gracefully loads the original
	# Morrow Coast data without changing a player's progress or map assets.
	published_game_world=not proving_ground and bool(ground.data.get("editor_published_world",false))
	var custom_game_world: bool=custom_test_drive or published_game_world
	if not proving_ground and not ground.initialization_complete:
		# Do not run a broken/partial Test Drive as Morrow Coast.
		if custom_test_drive:
			get_tree().set_meta("streetbound_test_drive_error","Custom map failed gameplay world validation.")
			call_deferred("_return_from_test_drive")
			return
		ground.set_performance_debug(true)
		return
	if not proving_ground:
		# Read the player's real owned car, tuning and progression for parity,
		# then turn off writes before any Test Drive gameplay can earn/spend.
		vehicle_ownership = OwnershipScript.new()
		if custom_test_drive:vehicle_ownership.persist_enabled=false
	vehicle = VehicleScene.instantiate()
	vehicle.position = Vector2(0, 500) if proving_ground else ground.spawn_position()
	vehicle.rotation = 0.0 if proving_ground else ground.spawn_rotation()
	vehicle.surface_provider = ground
	add_child(vehicle)
	vehicle.add_to_group("player_vehicle")
	ground.vehicle = vehicle
	# The weather layer uses the active provider, so authored/published maps
	# get the same visual response without a map-specific scene.
	var rain_fx := Node2D.new()
	rain_fx.name = "WetRoadEffects"
	rain_fx.set_script(RainVisuals)
	rain_fx.world = ground
	rain_fx.focus_vehicle = vehicle
	ground.add_child(rain_fx)
	var traffic: Node2D = null
	if not proving_ground:
		# Traffic uses the same baked Morrow road curves/intersections as roads
		# and the map editor. It has no influence on the player's handling.
		traffic = Node2D.new()
		traffic.name = "AmbientTraffic"
		traffic.set_script(TrafficFlowScript)
		traffic.world = ground
		traffic.player = vehicle
		ground.add_child(traffic)
		# World roads/traffic stay below the player in the 2D draw stack.
		vehicle.z_index = 8
		# Morrow-only facilities are not spawned off the edges of a custom map.
		# The vehicle menu remains usable anywhere in Test Drive.
		if not custom_game_world:
			player_garage = Node2D.new()
			player_garage.set_script(PlayerGarageScript)
			player_garage.world = ground
			player_garage.player = vehicle
			ground.add_child(player_garage)
		if not custom_game_world or not ground.data.get("editor_dealerships",[]).is_empty():
			dealership_world = Node2D.new()
			dealership_world.set_script(DealerWorldScript)
			dealership_world.world = ground
			dealership_world.player = vehicle
			ground.dealerships = dealership_world
			ground.add_child(dealership_world)
		# Named Morrow Coast events are only valid on their original circuit
		# and drag-strip locations; custom maps load their own placed races.
		if not custom_game_world:
			drag_race = Node2D.new()
			drag_race.set_script(DragRaceScript)
			drag_race.world=ground;drag_race.player=vehicle;drag_race.economy=vehicle_ownership
			ground.add_child(drag_race)
			circuit_race = Node2D.new()
			circuit_race.set_script(CircuitPracticeScript)
			circuit_race.world=ground;circuit_race.player=vehicle
			ground.add_child(circuit_race)
			street_race = Node2D.new()
			street_race.set_script(StreetSprintScript)
			street_race.world=ground;street_race.player=vehicle;street_race.network=traffic.network;street_race.traffic=traffic
			ground.add_child(street_race)
			for resource in ["juniper_ascent","coastline_dash","harvest_run","parkway_express"]:
				var event:=Node2D.new()
				event.set_script(StreetSprintScript)
				event.definition=load("res://resources/races/"+resource+".tres")
				event.world=ground;event.player=vehicle;event.network=traffic.network;event.traffic=traffic
				ground.add_child(event)
				extra_races.append(event)
		for definition in ground.data.get("editor_races",[]):
			var event:=Node2D.new()
			event.set_script(AuthoredRaceScript)
			event.definition=definition;event.world=ground;event.player=vehicle
			event.network=traffic.network;event.economy=vehicle_ownership
			ground.add_child(event)
			extra_races.append(event)
	var camera := Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.set_script(CameraScript)
	camera.target = vehicle
	# On Morrow Coast, the spawn is a parking lot roughly 42m from its
	# garage building and 46m from the nearest houses. Show that neighborhood
	# before accelerating, then return to normal driver-controlled zoom.
	camera.startup_neighborhood_view = not proving_ground and not custom_game_world
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
		var world_name: String=str(ground.data.get("name","Morrow Coast"))
		hud.environment_title=("TEST DRIVE    /    "+world_name.to_upper()) if custom_test_drive else world_name.to_upper()+"    /    OPEN ROAD"
		get_window().title="Streetbound | Test Drive" if custom_test_drive else "Streetbound | "+world_name
	add_child(hud)
	if not proving_ground:
		offscreen_vehicle_awareness = Control.new()
		offscreen_vehicle_awareness.set_script(VehicleAwarenessScript)
		offscreen_vehicle_awareness.set("player",vehicle)
		offscreen_vehicle_awareness.set("camera",camera)
		offscreen_vehicle_awareness.set("traffic",traffic)
		hud.add_child(offscreen_vehicle_awareness)
	if not proving_ground:
		progression_hud = CanvasLayer.new()
		progression_hud.set_script(ProgressHudScript)
		progression_hud.economy = vehicle_ownership
		progression_hud.host = hud.progression_slot
		add_child(progression_hud)
		hud.show_unified_progression()
	var world_hud_ref: CanvasLayer
	if not proving_ground:
		var world_hud := CanvasLayer.new()
		world_hud.layer = 3
		world_hud.set_script(WorldHudScript)
		world_hud.world = ground
		world_hud.vehicle = vehicle
		# Solo event menus must not start locally timed/rewarded races
		# during a shared player-hosted friend session.
		if not online_session.active:
			world_hud.races.append(drag_race)
			world_hud.races.append(circuit_race)
			world_hud.races.append(street_race)
			world_hud.races.append_array(extra_races)
		world_hud.driving_hud = hud
		add_child(world_hud)
		world_hud_ref=world_hud
	# CanvasLayer 20 is PROCESS_MODE_ALWAYS; menu controls work while paused.
	pause_menu = PauseMenuScript.new()
	pause_menu.name = "PauseMenu"
	pause_menu.vehicle_audio = audio
	pause_menu.driving_camera = camera
	pause_menu.player_vehicle = vehicle
	pause_menu.vehicle_ownership = vehicle_ownership
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
	if online_session.active and not proving_ground:
		online_session.set_local_car(str(vehicle_ownership.active_id))
	if not proving_ground:
		# Accessible from anywhere, not restricted to the physical garage.
		# The live world remains visible behind a pause-safe transparent HUD.
		quick_upgrades = CanvasLayer.new()
		quick_upgrades.set_script(QuickUpgradesScript)
		quick_upgrades.economy = vehicle_ownership
		quick_upgrades.vehicle = vehicle
		add_child(quick_upgrades)
		pause_menu.quick_upgrades = quick_upgrades
		if is_instance_valid(pause_menu.dashboard):
			pause_menu.dashboard.upgrades = quick_upgrades
	if not proving_ground and is_instance_valid(dealership_world):
		dealership_menu = CanvasLayer.new()
		dealership_menu.set_script(DealerMenuScript)
		dealership_menu.manager = dealership_world
		dealership_menu.player = vehicle
		dealership_menu.economy = vehicle_ownership
		add_child(dealership_menu)
	if not proving_ground:
		authored_map_markers=Node2D.new()
		authored_map_markers.set_script(AuthoredMarkersScript)
		authored_map_markers.world=ground
		authored_map_markers.player=vehicle
		authored_map_markers.economy=vehicle_ownership
		authored_map_markers.selector=selector
		authored_map_markers.dealer_menu=dealership_menu
		authored_map_markers.quick_upgrades=quick_upgrades
		authored_map_markers.traffic=traffic
		authored_map_markers.map_hud=world_hud_ref
		# Keep the script's typed Array[Node2D] intact: assigning []
		# directly coerces it to an untyped Array and breaks world startup.
		authored_map_markers.races = extra_races.duplicate()
		if online_session.active:
			authored_map_markers.races.clear()
		else:
			for builtin_race in [drag_race, circuit_race, street_race]:
				if is_instance_valid(builtin_race):
					authored_map_markers.races.append(builtin_race)
		add_child(authored_map_markers)
	# Single-player only: host-authoritative multiplayer damage/police requires
	# its own synchronized state and is excluded from this first vertical slice.
	if not proving_ground and not custom_test_drive and not online_session.active:
		vehicle_damage_service = CanvasLayer.new()
		vehicle_damage_service.set_script(VehicleDamageServiceScript)
		vehicle_damage_service.set("player", vehicle)
		vehicle_damage_service.set("economy", vehicle_ownership)
		vehicle_damage_service.set("garage", player_garage)
		vehicle_damage_service.set("authored_markers", authored_map_markers)
		add_child(vehicle_damage_service)
		police_pursuit = Node2D.new()
		police_pursuit.set_script(PolicePursuitScript)
		police_pursuit.set("player", vehicle)
		police_pursuit.set("world", ground)
		police_pursuit.set("traffic", traffic)
		police_pursuit.set("economy", vehicle_ownership)
		police_pursuit.set("damage_service", vehicle_damage_service)
		var illegal_races: Array = []
		if is_instance_valid(street_race):illegal_races.append(street_race)
		for race in extra_races:
			if str(race.get("race_type")).to_lower().contains("street"):
				illegal_races.append(race)
		police_pursuit.set("street_races", illegal_races)
		add_child(police_pursuit)
		vehicle_damage_service.set("police", police_pursuit)
		authored_map_markers.set("resources", vehicle_damage_service)
	# One world, two cars, two cameras. This manager never creates a second
	# Morrow Coast instance or touches the single-player career save.
	local_split_screen = CanvasLayer.new()
	local_split_screen.set_script(LocalSplitScript)
	local_split_screen.player_one = vehicle
	local_split_screen.world = ground
	local_split_screen.traffic = traffic
	local_split_screen.inventory = vehicle_ownership
	local_split_screen.main_camera = camera
	var hidden: Array[CanvasLayer] = []
	for node in get_children():
		if node is CanvasLayer and node != pause_menu:
			hidden.append(node)
	local_split_screen.hidden_layers = hidden
	var disabled: Array[Node] = []
	for system in [player_garage,dealership_world,drag_race,circuit_race,street_race,
			police_pursuit,vehicle_damage_service]:
		if is_instance_valid(system):
			disabled.append(system)
	disabled.append_array(extra_races)
	local_split_screen.disabled_systems = disabled
	add_child(local_split_screen)
	pause_menu.split_screen_requested.connect(_toggle_local_split_screen)
	pause_menu.main_menu_requested.connect(_return_to_main_menu)
	if custom_test_drive:
		pause_menu.map_editor_requested.connect(_return_from_test_drive)
		pause_menu.exit_requested.connect(_return_from_test_drive)
		pause_menu.allow_quit=false
	else:
		pause_menu.map_editor_requested.connect(_open_native_map_editor)
	# This is a developer-only transition workspace. It renders the EXISTING
	# Morrow Coast scene and visualizes the traffic network already built by
	# the game. Release players cannot open it, and it never writes map files.
	if not proving_ground and not custom_game_world and (OS.has_feature("debug") or OS.has_feature("editor")):
		native_world_editor = CanvasLayer.new()
		native_world_editor.set_script(NativeWorldEditorScript)
		native_world_editor.world = ground
		native_world_editor.player = vehicle
		native_world_editor.driving_camera = camera
		var ambient_traffic: Node = ground.get_node_or_null("AmbientTraffic")
		if is_instance_valid(ambient_traffic):
			native_world_editor.traffic_network = ambient_traffic.get("network")
		add_child(native_world_editor)
	# The title screen supplies one explicit launch target. Tests that
	# instantiate main.tscn directly still start in normal single-player.
	pause_menu.set_map_editor_available(is_instance_valid(native_world_editor) or custom_test_drive)
	if custom_test_drive:
		_add_test_drive_return_button()
	if online_session.active and not proving_ground and not custom_test_drive:
		# Race controllers supply navigation to the host-authoritative
		# online event catalog on both bundled and published maps. Local
		# payouts must never run during a shared multiplayer session.
		var solo_events: Array = [drag_race, circuit_race, street_race]
		solo_events.append_array(extra_races)
		for solo in solo_events:
			if not is_instance_valid(solo):
				continue
			solo.set_process_unhandled_input(false)
			solo.set_physics_process(false)
			solo.hide()
			# HUD CanvasLayers are separate nodes; hiding the race world
			# marker alone does not hide their on-screen race prompts.
			for child in solo.get_children():
				if child is CanvasLayer:
					child.hide()
		online_world = Node2D.new()
		online_world.name = "OnlineWorld"
		online_world.set_script(OnlineWorldScript)
		online_world.local_vehicle = vehicle
		online_world.world = ground
		add_child(online_world)
	if not pending_launch_mode.is_empty():
		call_deferred("_apply_title_launch_mode")


func _apply_title_launch_mode() -> void:
	var mode := pending_launch_mode
	pending_launch_mode = ""
	match mode:
		"multiplayer":
			if is_instance_valid(local_split_screen) and local_split_screen.start_split():
				pause_menu.set_split_screen_active(true)
			else:
				pause_menu.pause_game()
				pause_menu.show_split_screen_error(
					local_split_screen.warning if is_instance_valid(local_split_screen) else
					"Local split-screen is unavailable.")
		"map_editor":
			_begin_native_map_editor()


func _open_native_map_editor() -> void:
	if not is_instance_valid(native_world_editor) or \
			(is_instance_valid(local_split_screen) and local_split_screen.active):
		return
	# The pause-menu editor uses the same isolated authoring scene as title.
	# Do not leave simulation objects running behind the editor interface.
	pause_menu.resume_game()
	get_tree().call_deferred("change_scene_to_file","res://scenes/world_editor.tscn")


func _begin_native_map_editor() -> void:
	if is_instance_valid(native_world_editor):
		native_world_editor.open_editor()


func _return_to_main_menu() -> void:
	if custom_test_drive:
		_return_from_test_drive()
		return
	# Restore the single player state, including its camera and HUD, before
	# destroying the gameplay scene. Career data stays in the normal save.
	if is_instance_valid(local_split_screen) and local_split_screen.active:
		local_split_screen.stop_split()
	pause_menu.resume_game()
	pending_launch_mode = ""
	if online_session.active or online_session.joining:
		online_session.leave_session()
	get_tree().change_scene_to_file("res://scenes/title_menu.tscn")


func _toggle_local_split_screen() -> void:
	if online_session.active:
		pause_menu.show_split_screen_error("Leave the online session before starting local split-screen.")
		return
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


func _add_test_drive_return_button() -> void:
	# The full main HUD, menus and map remain active. Only this developer
	# shortcut distinguishes a temporary map playtest from normal gameplay.
	var layer_node:=CanvasLayer.new()
	layer_node.name="TestDriveReturn"
	layer_node.layer=4
	add_child(layer_node)
	var button:=Button.new()
	button.name="ReturnToMapEditor"
	button.text="Return to Map Editor   F6"
	# Keep the return control away from the active top-right minimap and
	# from the left-side speed and upgrade HUD.
	button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	button.position=Vector2(-125,12)
	button.size=Vector2(250,38)
	button.pressed.connect(_return_from_test_drive)
	layer_node.add_child(button)


func _input(event: InputEvent) -> void:
	# F6 normally opens tooling; while test driving it always returns to the
	# authoring session. Escape retains the normal pause/settings behavior.
	if not custom_test_drive or not event is InputEventKey:return
	var key: InputEventKey=event
	if key.pressed and not key.echo and (key.keycode==KEY_F6 or key.physical_keycode==KEY_F6):
		get_viewport().set_input_as_handled()
		call_deferred("_return_from_test_drive")


func _return_from_test_drive() -> void:
	if not custom_test_drive:return
	custom_test_drive=false
	if is_instance_valid(pause_menu):
		pause_menu.resume_game()
	if is_instance_valid(local_split_screen) and local_split_screen.active:
		local_split_screen.stop_split()
	get_tree().paused=false
	if not test_drive_file.is_empty():
		get_tree().set_meta("streetbound_editor_resume_map",test_drive_file)
	# The original map builder saved its camera before launching Test Drive.
	# Never write the temporary world into the production source archive.
	for marker in ["streetbound_test_drive_archive","streetbound_test_drive_map"]:
		if get_tree().has_meta(marker):get_tree().remove_meta(marker)
	get_tree().change_scene_to_file("res://scenes/world_editor.tscn")
