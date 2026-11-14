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
var layer_flags: Dictionary={"terrain":true,"roads":true,"scenery":true}

func setup(world: Node2D) -> void:
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
	viewport.canvas_transform=Transform2D.IDENTITY.scaled(Vector2(viewport.size)/(extent_m*PPM))
	road_count=full_world.road_batches.size();prop_count=full_world.prop_list.size()
	sprite=Sprite2D.new();sprite.name="WholeMapTexture"
	sprite.texture=viewport.get_texture();sprite.centered=false
	sprite.scale=extent_m*PPM/Vector2(viewport.size)
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.z_index=-7
	add_child(sprite)
	refresh()

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
	layer_flags=flags.duplicate()
	if is_instance_valid(full_world):apply_layers(full_world,flags)
	refresh()

func refresh() -> void:
	if not is_instance_valid(viewport):return
	refresh_count+=1
	if is_instance_valid(full_world):
		full_world.queue_redraw()
		full_world.redraw_bridges()
		full_world.redraw_mountains()
		for child in full_world.get_children():
			if child is CanvasItem:child.queue_redraw()
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
