extends Node2D
## The mini-map/zoomed atlas reuses the EXACT playable CoastChunk draw code.
## Each chunk is rebuilt from world.data on game launch; no PNG snapshot,
## persistent baked atlas or approximate second building/road renderer.
const Chunk = preload("res://scripts/world/coast_chunk.gd")
const WORLD_PPM := 20.0
const CACHE_PADDING_PX := 85.0
const MAX_CACHED_CELLS := 64
const BUILD_PER_FRAME := 3

var world: MorrowCoast
var chunks: Dictionary = {}
var requested: Dictionary = {}
var pending: Array[Vector2i] = []
var available := false
var built_count := 0


func _ready() -> void:
	# Below cartographic labels, cursor and the race guidance overlay.
	z_index = -20
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


static func region_cells(center_m: Vector2, ppm: float, size_px: Vector2,
		chunk_m: float, extent_m: Vector2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if ppm <= 0.0 or chunk_m <= 0.0:
		return result
	var half_m := (size_px * .5 + Vector2.ONE * CACHE_PADDING_PX) / ppm
	var first := Vector2i(((center_m - half_m) / chunk_m).floor())
	var last := Vector2i(((center_m + half_m) / chunk_m).floor())
	var maximum := Vector2i((extent_m / chunk_m).ceil())
	for y in range(maxi(0, first.y), mini(maximum.y, last.y + 1)):
		for x in range(maxi(0, first.x), mini(maximum.x, last.x + 1)):
			result.append(Vector2i(x, y))
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var c := center_m / chunk_m
		return Vector2(a).distance_squared_to(c) < Vector2(b).distance_squared_to(c))
	return result


## Return false for wide overviews, which use the inexpensive cartographic
## layer from the same data. Detailed views use native game artwork/shaders.
func configure(center_m: Vector2, ppm: float, dimensions: Vector2,
		extent_m: Vector2) -> bool:
	if not is_instance_valid(world):
		_clear()
		available = false
		visible = false
		return false
	var needed := region_cells(center_m, ppm, dimensions,
		world.chunk_m, extent_m)
	available = needed.size() > 0 and needed.size() <= MAX_CACHED_CELLS
	visible = available
	if not available:
		_clear()
		return false
	position = dimensions * .5 - center_m * ppm
	scale = Vector2.ONE * (ppm / WORLD_PPM)
	var desired: Dictionary = {}
	for index in needed:
		desired[index] = true
	requested = desired
	for index in chunks.keys():
		if not requested.has(index):
			chunks[index].queue_free()
			chunks.erase(index)
	pending.clear()
	for index in needed:
		if not chunks.has(index):
			pending.append(index)
	return true


func _clear() -> void:
	pending.clear()
	requested.clear()
	for chunk in chunks.values():
		chunk.queue_free()
	chunks.clear()


func _process(_delta: float) -> void:
	if not available or not is_instance_valid(world):
		return
	# Amortize initial image build over frames; a large region must never
	# synchronously allocate hundreds of copies of the physical world.
	for iteration in mini(BUILD_PER_FRAME, pending.size()):
		var index: Vector2i = pending.pop_front()
		if not requested.has(index) or chunks.has(index):
			continue
		var key := "%d,%d" % [index.x, index.y]
		var section: Dictionary = world.data.chunks.get(key, {
			"segments":[], "terrain":[], "props":[], "junctions":[],
			"walls":[], "relief":[], "rails":[]
		})
		var chunk := Node2D.new()
		chunk.set_script(Chunk)
		chunk.map_render_only = true
		chunk.setup(world, index, section)
		chunks[index] = chunk
		add_child(chunk)
		built_count += 1
