extends Node2D
## Persistent full-world render, independent of the near-camera tile budget.
## Draw once with real CoastChunk artwork/shaders into a bounded texture;
## reuse it at every zoom and re-render only after visibility/draft changes.
const Chunk=preload("res://scripts/world/coast_chunk.gd")
const Scenery=preload("res://scripts/world/coast_scenery.gd")
const Roads=preload("res://scripts/world/coast_roads.gd")
const PPM:=20.0
const MAX_TEXTURE_SIZE:=4096
var viewport: SubViewport
var sprite: Sprite2D
var full_world: Node2D
var extent_m:=Vector2.ZERO
var road_count:=0
var prop_count:=0
var refresh_count:=0
var build_ms:=0.0
var cache_hit:=false
var _cache_key: String=""
static var _last_clean_key: String=""
static var _last_clean_texture: ImageTexture
var layer_flags: Dictionary={"terrain":true,"roads":true,"scenery":true}

func setup(world: Node2D, cache_key: String="") -> void:
	_cache_key=cache_key
	name="PersistentEditorOverview"
	extent_m=Vector2(world.data.size[0],world.data.size[1])
	var ratio:=float(MAX_TEXTURE_SIZE)/maxf(extent_m.x,extent_m.y)
	viewport=SubViewport.new()
	viewport.name="WholeMapRender"
	viewport.size=Vector2i((extent_m*ratio).ceil())
	viewport.disable_3d=true;viewport.transparent_bg=true;viewport.gui_disable_input=true
	viewport.world_2d=World2D.new()
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(viewport)
	viewport.canvas_transform=Transform2D.IDENTITY.scaled(Vector2(viewport.size)/(extent_m*PPM))
	sprite=Sprite2D.new();sprite.name="WholeMapTexture"
	sprite.texture=viewport.get_texture();sprite.centered=false
	if not _cache_key.is_empty() and _cache_key==_last_clean_key and is_instance_valid(_last_clean_texture):
		sprite.texture=_last_clean_texture;cache_hit=true
	sprite.scale=extent_m*PPM/Vector2(viewport.size)
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index=-7
	add_child(sprite)
	# Build after opening the UI instead of blocking the editor's open call.
	# The previous clean atlas is only a temporary visual, never collision data.
	if cache_hit and DisplayServer.get_name()!="headless":
		get_tree().process_frame.connect(_populate.bind(world),CONNECT_ONE_SHOT)
	else:_populate(world)

func _populate(world: Node2D) -> void:
	if not is_instance_valid(world) or not is_inside_tree():return
	var started:=Time.get_ticks_usec()
	var content: Dictionary={"segments":range(world.data.segments.size()),"props":range(world.data.props.size()),
		"terrain":world.data.terrain,"junctions":range(world.data.junctions.size()),"walls":[],
		"bridges":range(world.data.get("bridges",[]).size()),
		"mountains":range(world.data.terrain.size()).filter(func(i: int)->bool:return bool(world.data.terrain[i].get("barrier",false))),
		"relief":range(world.data.get("relief_faces",[]).size()),"rails":range(world.data.get("mountain_rails",[]).size())}
	full_world=Node2D.new();full_world.set_script(Chunk)
	full_world.name="WholeMapArtwork";full_world.map_render_only=true
	full_world.render_extent_m=extent_m
	full_world.setup(world,Vector2i.ZERO,content)
	viewport.add_child(full_world)
	road_count=full_world.road_batches.size();prop_count=full_world.prop_list.size()
	apply_layers(full_world,layer_flags)
	build_ms=(Time.get_ticks_usec()-started)/1000.0
	refresh()
	if DisplayServer.get_name()!="headless":_finish_atlas()
	else:sprite.texture=viewport.get_texture()

func _finish_atlas() -> void:
	await RenderingServer.frame_post_draw
	if not is_instance_valid(sprite) or not is_instance_valid(viewport):return
	sprite.texture=viewport.get_texture()
	# One bounded image survives scene transitions within the application.
	# Never persist draft-masked views or views with hidden layers.
	if _cache_key.is_empty() or not bool(layer_flags.get("terrain",true)) or not bool(layer_flags.get("roads",true)) or not bool(layer_flags.get("scenery",true)):return
	if not Roads.editor_hidden.is_empty() or not Scenery.editor_hidden.is_empty():return
	if not preload("res://scripts/world/coast_bridges.gd").editor_hidden.is_empty() or not preload("res://scripts/world/coast_mountain_barriers.gd").editor_hidden.is_empty():return
	var image:=viewport.get_texture().get_image()
	if image!=null and not image.is_empty():
		_last_clean_texture=ImageTexture.create_from_image(image);_last_clean_key=_cache_key

static func apply_layers(chunk: Node2D, flags: Dictionary) -> void:
	chunk.show_terrain=bool(flags.get("terrain",true))
	chunk.queue_redraw()
	for child in chunk.get_children():
		var script: Script=child.get_script()
		if script==Roads or child.name in ["StreetDetails","BeachBoardwalk","BridgeDeckClip","BridgeRailsClip"]:child.visible=bool(flags.get("roads",true))
		elif script==Scenery or script==preload("res://scripts/world/coast_shadows.gd"):child.visible=bool(flags.get("scenery",true))
		elif child.name=="MountainArtworkClip":child.visible=bool(flags.get("terrain",true))
		elif script==preload("res://scripts/world/coast_relief.gd"):
			child.visible=bool(flags.get("terrain",true)) if child.render_stage==0 else bool(flags.get("roads",true))

func set_layers(flags: Dictionary) -> void:
	if layer_flags==flags:return
	layer_flags=flags.duplicate()
	if cache_hit and not is_instance_valid(full_world) and (not bool(flags.get("terrain",true)) or not bool(flags.get("roads",true)) or not bool(flags.get("scenery",true))):sprite.texture=viewport.get_texture()
	if is_instance_valid(full_world):apply_layers(full_world,flags)
	refresh()

func refresh() -> void:
	if not is_instance_valid(viewport) or not is_instance_valid(full_world):return
	refresh_count+=1
	if is_instance_valid(full_world):
		full_world.queue_redraw()
		full_world.redraw_bridges()
		full_world.redraw_mountains()
		for child in full_world.get_children():
			if child is CanvasItem:child.queue_redraw()
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
