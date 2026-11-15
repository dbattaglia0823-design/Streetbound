extends SceneTree
const Art=preload("res://scripts/world/coast_art.gd")
const Scenery=preload("res://scripts/world/coast_scenery.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(label: String,ok: bool) -> void:
	print("%s %s"%["PASS" if ok else "FAIL",label])
	if not ok:failures.append(label)
func redraw(world) -> void:
	for chunk in world.chunks.values():
		for node in chunk.get_children():
			if node is CanvasItem:node.queue_redraw()
func run() -> void:
	AudioServer.set_bus_mute(0,true)
	var archive_hash:=FileAccess.get_sha256("res://worlds/morrow-coast.world.json")
	var props: Array=JSON.parse_string(FileAccess.get_file_as_string("res://.runtime/sprite-sheets/baked-props.json"))
	var game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.vehicle_ownership.persist_enabled=false
	game.process_mode=Node.PROCESS_MODE_DISABLED
	var world: MorrowCoast=game.ground
	var cells: Dictionary={}
	# Inject only regression placements into this process. The normal main
	# scene, runtime chunk renderer, sprites, shaders and colliders stay real.
	for prop in props:
		var index: int=world.data.props.size();world.data.props.append(prop)
		var radius:=Vector2(prop.size[0],prop.size[1]).length()*.5
		var p:=Vector2(prop.p[0],prop.p[1])
		var first:=Vector2i(((p-Vector2.ONE*radius)/world.chunk_m).floor())
		var last:=Vector2i(((p+Vector2.ONE*radius)/world.chunk_m).floor())
		for x in range(first.x,last.x+1):
			for y in range(first.y,last.y+1):
				var cell:=Vector2i(x,y);var key:="%d,%d"%[x,y]
				if not world.data.chunks.has(key):world.data.chunks[key]={"segments":[],"props":[],"terrain":[],"walls":[],"junctions":[],"bridges":[],"mountains":[],"relief":[],"rails":[]}
				world.data.chunks[key].props.append(index);cells[cell]=true
	for cell in cells:
		if world.chunks.has(cell):
			var previous=world.chunks[cell];world.remove_child(previous);previous.queue_free();world.chunks.erase(cell)
		world._build_chunk(cell)
	var camera:=Camera2D.new();camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position=Vector2(495,345)*20;camera.zoom=Vector2.ONE*.36;root.add_child(camera);camera.make_current()
	game.vehicle.position=Vector2(495,410)*20
	world.stream_at(game.vehicle.position)
	for i in 10:await process_frame
	for prop in props:
		var texture:=Art.project_sprite(prop.asset_path,prop.asset_region)
		check("game_texture_"+str(prop.editor_name),texture is AtlasTexture and texture.get_size()==Vector2(prop.asset_region[2],prop.asset_region[3]))
		var visible:=false;var collision:=false
		for cell in cells:
			var chunk=world.chunks[cell]
			if chunk.prop_list.any(func(p):return p.get("authoring_id","")==prop.authoring_id) and chunk.is_visible_in_tree():visible=true
			if chunk.collider_body!=null:
				for shape in chunk.collider_body.get_children():
					if str(shape.get_meta("editor_prop_key",""))==Scenery.editor_key(prop):collision=true
		check("game_render_and_collision_"+str(prop.editor_name),visible and collision==bool(prop.solid))
	if DisplayServer.get_name()!="headless":
		# HUD panels legitimately cover some small test props. Hide them only
		# for the before/after world-pixel comparison, without changing the UI.
		for node in game.get_children():
			if node is CanvasLayer:node.visible=false
		for prop in props:Scenery.editor_hidden[Scenery.editor_key(prop)]=true
		redraw(world);await process_frame;await RenderingServer.frame_post_draw
		var before:=root.get_texture().get_image()
		Scenery.editor_hidden={};redraw(world);await process_frame;await RenderingServer.frame_post_draw
		var after:=root.get_texture().get_image()
		for prop in props:
			var center: Vector2=root.canvas_transform*(Vector2(prop.p[0],prop.p[1])*20)
			var size:=Vector2(prop.size[0],prop.size[1])*20*camera.zoom.x
			var changed:=0
			var radius:=maxi(5,ceili(size.length()*.55))
			var step:=1 if radius<10 else 2
			for y in range(maxi(0,int(center.y)-radius),mini(after.get_height(),int(center.y)+radius),step):
				for x in range(maxi(0,int(center.x)-radius),mini(after.get_width(),int(center.x)+radius),step):
					var a:=before.get_pixel(x,y);var b:=after.get_pixel(x,y)
					if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.08:changed+=1
			check("game_pixels_"+str(prop.editor_name),changed>3)
		after.save_png("res://.runtime/sprite-sheets/game.png")
	check("playable_archive_preserved",FileAccess.get_sha256("res://worlds/morrow-coast.world.json")==archive_hash)
	Scenery.editor_hidden={};game.queue_free();camera.queue_free();await process_frame;await process_frame
	print("SPRITE SHEET GAME: ","PASS" if failures.is_empty() else str(failures));quit(0 if failures.is_empty() else 1)
