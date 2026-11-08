extends Node2D
const VehicleScene = preload("res://scenes/vehicle.tscn")
const GroundScript = preload("res://scripts/world/proving_ground.gd")
const CameraScript = preload("res://scripts/camera/driving_camera.gd")
const HudScript = preload("res://scripts/ui/driving_hud.gd")
const AudioScript = preload("res://scripts/audio/vehicle_audio.gd")
var vehicle: VehicleController2D
var ground: ProvingGround

func _ready() -> void:
	ground = GroundScript.new()
	add_child(ground)
	vehicle = VehicleScene.instantiate()
	vehicle.position = Vector2(0, 500)
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
	add_child(hud)
