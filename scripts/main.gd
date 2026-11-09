extends Node2D
const VehicleScene = preload("res://scenes/vehicle.tscn")
const GroundScript = preload("res://scripts/world/proving_ground.gd")
const CoastScript = preload("res://scripts/world/morrow_coast.gd")
const WorldHudScript = preload("res://scripts/world/world_map_hud.gd")
const CameraScript = preload("res://scripts/camera/driving_camera.gd")
const HudScript = preload("res://scripts/ui/driving_hud.gd")
const AudioScript = preload("res://scripts/audio/vehicle_audio.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
var pause_menu
var vehicle: VehicleController2D
@export var proving_ground := false
var ground: Node2D

func _ready() -> void:
	ground = GroundScript.new() if proving_ground else CoastScript.new()
	add_child(ground)
	vehicle = VehicleScene.instantiate()
	vehicle.position = Vector2(0, 500) if proving_ground else ground.spawn_position()
	vehicle.rotation = 0.0 if proving_ground else ground.spawn_rotation()
	vehicle.surface_provider = ground
	add_child(vehicle)
	ground.vehicle = vehicle
	var camera := Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.set_script(CameraScript)
	camera.target = vehicle
	add_child(camera)
	var audio := Node.new()
	audio.set_script(AudioScript)
	audio.vehicle = vehicle
	add_child(audio)
	var hud := CanvasLayer.new()
	hud.set_script(HudScript)
	hud.vehicle = vehicle
	hud.camera = camera
	if not proving_ground:
		hud.environment_title = "MORROW COAST    /    OPEN ROAD"
		get_window().title = "Streetbound | Morrow Coast"
	add_child(hud)
	if not proving_ground:
		var world_hud := CanvasLayer.new()
		world_hud.set_script(WorldHudScript)
		world_hud.world = ground
		world_hud.vehicle = vehicle
		world_hud.driving_hud = hud
		add_child(world_hud)
	# CanvasLayer 20 uses PROCESS_MODE_ALWAYS so Escape and its buttons work
	# while the vehicle, world, camera, HUD and audio processing are paused.
	pause_menu = PauseMenuScript.new()
	pause_menu.name = "PauseMenu"
	pause_menu.vehicle_audio = audio
	pause_menu.driving_camera = camera
	add_child(pause_menu)
