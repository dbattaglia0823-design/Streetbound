extends Node2D
## Camera-bounded map view: reuse the actual CoastChunk draw pipeline, without
## active vehicle streaming, collision bodies, traffic, or gameplay simulation.
const Chunk = preload("res://scripts/world/coast_chunk.gd")
const Overview=preload("res://scripts/dev/editor_world_overview.gd")
const PPM := 20.0
const MAX_TILES := 64
const BUILD_PER_FRAME := 2
const MAX_WARM_TILES := 48
var warm_tiles: Dictionary = {}
var warm_order: Array[Vector2i] = []
var cache_enabled := true
var adaptive_streaming := true
var build_budget_ms := 5.0
var build_count := 0
var cache_hits := 0
var last_build_ms := 0.0
var worst_build_ms := 0.0
var _view_key: Array = []
var _archive_key: Array = []
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
	var archive_key: Array=[world.get_instance_id(),world.data.chunks.size()]
	if archive_key!=_archive_key:
		_clear();_archive_key=archive_key
	var view_key: Array = [first,last,detailed]
	if view_key==_view_key and (ready_to_show or not detailed or not pending.is_empty()):
		visible=ready_to_show
		return detailed
	_view_key=view_key
	ready_to_show=false
	visible = detailed
	if not detailed:
		# Suspend detail chunks; keep only the bounded hidden warm cache.
		_suspend_tiles()
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
			_retire(cell)
	pending.clear()
	for cell in ordered:
		if tiles.has(cell):continue
		if warm_tiles.has(cell) and cache_enabled:
			var cached: Node2D=warm_tiles[cell]
			warm_tiles.erase(cell);warm_order.erase(cell)
			tiles[cell]=cached;cached.visible=true;cache_hits+=1
		else:pending.append(cell)
	set_process(not pending.is_empty())
	ready_to_show=not wanted.is_empty() and pending.is_empty() and tiles.size()==wanted.size()
	visible=ready_to_show
	return true


func _process(_dt: float) -> void:
	var started:=Time.get_ticks_usec()
	for step in mini(BUILD_PER_FRAME,pending.size()):
		if adaptive_streaming and step>0 and (Time.get_ticks_usec()-started)/1000.0>=build_budget_ms:break
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
		build_count+=1
	last_build_ms=(Time.get_ticks_usec()-started)/1000.0
	worst_build_ms=maxf(worst_build_ms,last_build_ms)
	set_process(not pending.is_empty())
	ready_to_show=detailed and not wanted.is_empty() and pending.is_empty() and tiles.size()==wanted.size()
	visible=ready_to_show

func set_layers(flags: Dictionary) -> void:
	layer_flags=flags.duplicate()
	for tile in all_tiles():Overview.apply_layers(tile,flags)


## Dormant tiles retain real draw geometry but are never visible or physical.
func all_tiles() -> Array:
	return tiles.values()+warm_tiles.values()

func _retire(cell: Vector2i) -> void:
	var node: Node2D=tiles[cell]
	tiles.erase(cell)
	if not cache_enabled:
		node.queue_free();return
	node.visible=false
	warm_tiles[cell]=node;warm_order.append(cell)
	while warm_order.size()>MAX_WARM_TILES:
		var oldest: Vector2i=warm_order.pop_front()
		warm_tiles[oldest].queue_free();warm_tiles.erase(oldest)

func _suspend_tiles() -> void:
	for cell in tiles.keys():_retire(cell)
	pending.clear();wanted.clear()
	ready_to_show=false;set_process(false)

func set_cache_enabled(enabled: bool) -> void:
	cache_enabled=enabled
	if not enabled:
		for node in warm_tiles.values():node.queue_free()
		warm_tiles.clear();warm_order.clear()

func _clear() -> void:
	pending.clear()
	wanted.clear()
	for chunk in all_tiles():chunk.queue_free()
	tiles.clear();warm_tiles.clear();warm_order.clear();_view_key=[]
	ready_to_show=false
	set_process(false)


func redraw_scenery() -> void:
	for tile in all_tiles():
		if not is_instance_valid(tile):
			continue
		for node in tile.get_children():
			if node is CanvasItem:
				node.queue_redraw()
