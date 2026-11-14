extends Node2D
## Camera-bounded map view: reuse the actual CoastChunk draw pipeline, without
## active vehicle streaming, collision bodies, traffic, or gameplay simulation.
const Chunk = preload("res://scripts/world/coast_chunk.gd")
const Overview=preload("res://scripts/dev/editor_world_overview.gd")
const PPM := 20.0
const MAX_TILES := 64
const BUILD_PER_FRAME := 2
var world: MorrowCoast
var tiles: Dictionary = {}
var wanted: Dictionary = {}
var pending: Array[Vector2i] = []
var detailed := false
var total_visible := 0
var layer_flags: Dictionary={"terrain":true,"roads":true,"scenery":true}
var ready_to_show:=false

func _ready() -> void:process_mode=Node.PROCESS_MODE_ALWAYS


func configure(center_px: Vector2, screen_px: Vector2, zoom: float) -> bool:
	if not is_instance_valid(world) or zoom <= 0.0:
		_clear()
		return false
	var half_m := screen_px * 0.5 / (zoom * PPM)
	var center_m := center_px / PPM
	var first := Vector2i(((center_m-half_m)/world.chunk_m).floor())
	var last := Vector2i(((center_m+half_m)/world.chunk_m).floor())
	var world_size: Array = world.data.get("size",[6400,4800])
	var maximum := Vector2i(ceili(float(world_size[0])/world.chunk_m),
		ceili(float(world_size[1])/world.chunk_m))
	first = first.max(Vector2i.ZERO)
	last = last.min(maximum-Vector2i.ONE)
	var count := maxi(0,last.x-first.x+1)*maxi(0,last.y-first.y+1)
	total_visible = count
	# A single consistent LOD across the entire camera avoids rectangular
	# high-detail islands surrounded by a mismatched low-res map.
	detailed = count > 0 and count <= MAX_TILES
	ready_to_show=false
	visible = detailed
	if not detailed:
		pending.clear();wanted.clear();set_process(false)
		visible=false
		return false
	var requested: Dictionary = {}
	var ordered: Array[Vector2i] = []
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var cell := Vector2i(x,y)
			if world.data.chunks.has("%d,%d" % [x,y]):
				requested[cell] = true
				ordered.append(cell)
	ordered.sort_custom(func(a: Vector2i,b: Vector2i) -> bool:
		var da: float = Vector2(a).distance_squared_to(center_m/world.chunk_m)
		var db: float = Vector2(b).distance_squared_to(center_m/world.chunk_m)
		return da < db)
	wanted = requested
	for cell in tiles.keys():
		if not wanted.has(cell):
			tiles[cell].queue_free()
			tiles.erase(cell)
	pending.clear()
	for cell in ordered:
		if not tiles.has(cell):
			pending.append(cell)
	set_process(not pending.is_empty())
	ready_to_show=not wanted.is_empty() and pending.is_empty() and tiles.size()==wanted.size()
	visible=ready_to_show
	return true


func _process(_dt: float) -> void:
	for step in mini(BUILD_PER_FRAME,pending.size()):
		var cell: Vector2i = pending.pop_front()
		if not wanted.has(cell) or tiles.has(cell):
			continue
		var id := "%d,%d" % [cell.x,cell.y]
		var node := Node2D.new()
		node.set_script(Chunk)
		node.map_render_only = true
		node.setup(world,cell,world.data.chunks[id])
		if not node.setup_complete:
			push_error("Editor render tile failed: "+id+" "+node.setup_error)
			node.free()
			continue
		node.z_index = -6
		Overview.apply_layers(node,layer_flags)
		add_child(node)
		tiles[cell] = node
	set_process(not pending.is_empty())
	ready_to_show=detailed and not wanted.is_empty() and pending.is_empty() and tiles.size()==wanted.size()
	visible=ready_to_show

func set_layers(flags: Dictionary) -> void:
	layer_flags=flags.duplicate()
	for tile in tiles.values():Overview.apply_layers(tile,flags)


func _clear() -> void:
	pending.clear()
	wanted.clear()
	for chunk in tiles.values():
		chunk.queue_free()
	tiles.clear()
	set_process(false)


func redraw_scenery() -> void:
	for tile in tiles.values():
		if not is_instance_valid(tile):
			continue
		for node in tile.get_children():
			if node is CanvasItem:
				node.queue_redraw()
