extends Node2D
## Native world-authoring scene. No vehicle, traffic AI, race, gameplay HUD,
## or live physical chunks are instantiated here.
const Coast = preload("res://scripts/world/morrow_coast.gd")
const Editor = preload("res://scripts/dev/native_world_editor.gd")
const Tiles = preload("res://scripts/dev/editor_render_tiles.gd")
const Dealers = preload("res://scripts/world/dealership_world.gd")
const Network = preload("res://scripts/world/traffic_network.gd")
var ground: MorrowCoast
var native_world_editor: CanvasLayer
var map_tiles: Node2D
var editor_origin_camera: Camera2D
var editor_dealerships: Node2D
var lane_geometry: RefCounted


func _ready() -> void:
	if not (OS.has_feature("debug") or OS.has_feature("editor")):
		get_tree().call_deferred("change_scene_to_file","res://scenes/title_menu.tscn")
		return
	name = "StreetboundStandaloneWorldEditor"
	ground = Coast.new()
	ground.editor_render_only = true
	add_child(ground)
	if not ground.initialization_complete:
		push_error("Standalone map failed to load baked world data.")
		return
	editor_dealerships = Node2D.new()
	editor_dealerships.set_script(Dealers)
	editor_dealerships.world = ground
	editor_dealerships.editor_render_only = true
	ground.dealerships = editor_dealerships
	add_child(editor_dealerships)
	map_tiles = Node2D.new()
	map_tiles.name = "CameraBoundEditorTiles"
	map_tiles.set_script(Tiles)
	map_tiles.world = ground
	add_child(map_tiles)
	editor_origin_camera = Camera2D.new()
	editor_origin_camera.name = "EditorOriginCamera"
	editor_origin_camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	editor_origin_camera.position = ground.spawn_position()
	if get_tree().has_meta("streetbound_editor_return_position"):
		var saved: Variant = get_tree().get_meta("streetbound_editor_return_position")
		if saved is Vector2:
			editor_origin_camera.position = saved
		get_tree().remove_meta("streetbound_editor_return_position")
	editor_origin_camera.zoom = Vector2(0.35,0.35)
	add_child(editor_origin_camera)
	editor_origin_camera.make_current()
	native_world_editor = CanvasLayer.new()
	native_world_editor.set_script(Editor)
	native_world_editor.world = ground
	native_world_editor.driving_camera = editor_origin_camera
	# Static lane and junction geometry only; no AI or traffic vehicles.
	lane_geometry = Network.new()
	lane_geometry.build(ground.data)
	native_world_editor.traffic_network = lane_geometry
	native_world_editor.standalone_mode = true
	native_world_editor.render_tiles = map_tiles
	add_child(native_world_editor)
	native_world_editor.call_deferred("open_editor")
