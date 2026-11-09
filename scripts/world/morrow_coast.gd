class_name MorrowCoast
extends Node2D
## Metre-authored world; cached 192m chunks, a 64m surface index and local blockers.
const Chunk = preload("res://scripts/world/coast_chunk.gd")
const TireMarks = preload("res://scripts/world/tire_marks.gd")
const PPM := 20.0
var data: Dictionary
var chunk_m := 192.0
var vehicle: VehicleController2D
var tire_marks: MultiMeshInstance2D
var chunks: Dictionary = {}
var pending: Array[Vector2i] = []
var current_cell := Vector2i(-999,-999)
var surface_queries := 0
var segment_tests := 0
var segment_stations := PackedFloat64Array()
var max_chunk_build_usec := 0
var stream_build_usec := 0
var mark_clock := 0.0
var _junction_grid: Dictionary = {}
var _junction_polygons: Array[PackedVector2Array] = []
var _apron_grid: Dictionary = {}
var _sand_polygons: Dictionary = {}
var boardwalk_path := PackedVector2Array()

func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/morrow-coast.world.json"))
	chunk_m = float(data.chunk_size)
	# Derive a continuous promenade from the original smoothed coastline.
	# Beach polygons extend 65m inland; the deck sits 35m inland, never
	# over open water. No rebake of the multi-megabyte world data required.
	for terrain in data.terrain:
		if terrain.kind != "ocean":
			continue
		var shore: Array = terrain.points
		for i in range(maxi(0, shore.size() - 2)):
			var p := Vector2(float(shore[i][0]), float(shore[i][1]))
			if p.y >= 2100.0 and p.y <= 3700.0:
				boardwalk_path.append(p + Vector2(-35.0, 0.0))
		break
	var station := 0.0
	var last_road := -1
	for segment in data.segments:
		if int(segment.road)!=last_road:
			station=0.0
			last_road=int(segment.road)
		segment_stations.append(station)
		station+=Vector2(float(segment.a[0]),float(segment.a[1])).distance_to(Vector2(float(segment.b[0]),float(segment.b[1])))
	for key in data.chunks:
		for terrain in data.chunks[key].terrain:
			if terrain.kind=="beach":
				var polygon := PackedVector2Array()
				for raw in terrain.points:
					polygon.append(Vector2(float(raw[0]),float(raw[1])))
				_sand_polygons[key]=polygon
	for prop in data.props:
		if not prop.kind in ["lot","forecourt"]:
			continue
		var p := Vector2(float(prop.p[0]),float(prop.p[1]))
		var radius := Vector2(float(prop.size[0]),float(prop.size[1])).length()*.5
		var first := Vector2i(((p-Vector2.ONE*radius)/float(data.surface_cell)).floor())
		var last := Vector2i(((p+Vector2.ONE*radius)/float(data.surface_cell)).floor())
		for x in range(first.x,last.x+1):
			for y in range(first.y,last.y+1):
				var key := "%d,%d" % [x,y]
				if not _apron_grid.has(key):
					_apron_grid[key] = []
				_apron_grid[key].append(prop)
	for i in data.junctions.size():
		var j: Dictionary = data.junctions[i]
		var polygon := PackedVector2Array()
		for raw in j.polygon:
			polygon.append(Vector2(float(raw[0]),float(raw[1])))
		_junction_polygons.append(polygon)
		var p := Vector2(float(j.p[0]),float(j.p[1]))
		var cell := Vector2i(((p-Vector2.ONE*float(j.radius))/float(data.surface_cell)).floor())
		var last := Vector2i(((p+Vector2.ONE*float(j.radius))/float(data.surface_cell)).floor())
		for x in range(cell.x,last.x+1):
			for y in range(cell.y,last.y+1):
				var key := "%d,%d" % [x,y]
				if not _junction_grid.has(key):
					_junction_grid[key] = []
				_junction_grid[key].append(i)
	tire_marks = TireMarks.new()
	tire_marks.z_index = 0
	add_child(tire_marks)
	# Spawn collision is built synchronously; neighbor loading is incremental.
	var spawn := spawn_position()
	var first := Vector2i((spawn/PPM/chunk_m).floor())
	_build_chunk(first)
	stream_at(spawn)

func spawn_position() -> Vector2:
	return Vector2(float(data.spawn.position[0]),float(data.spawn.position[1]))*PPM

func spawn_rotation() -> float:
	return float(data.spawn.rotation)

func _build_chunk(index: Vector2i) -> void:
	var key := "%d,%d" % [index.x,index.y]
	if chunks.has(index) or not data.chunks.has(key):
		return
	var started := Time.get_ticks_usec()
	var instance := Node2D.new()
	instance.set_script(Chunk)
	instance.z_index = -6
	instance.setup(self,index,data.chunks[key])
	add_child(instance)
	chunks[index] = instance
	instance.build_microseconds=Time.get_ticks_usec()-started
	max_chunk_build_usec = maxi(max_chunk_build_usec,instance.build_microseconds)
	stream_build_usec += instance.build_microseconds

func stream_at(position_px: Vector2) -> void:
	var center := Vector2i((position_px/PPM/chunk_m).floor())
	if center == current_cell:
		return
	current_cell = center
	pending.clear()
	# 3x3 active, plus a one-cell hysteresis band to avoid boundary churn.
	for x in range(center.x-1,center.x+2):
		for y in range(center.y-1,center.y+2):
			var index := Vector2i(x,y)
			if not chunks.has(index):
				pending.append(index)
	pending.sort_custom(func(a: Vector2i,b: Vector2i): return a.distance_squared_to(center)<b.distance_squared_to(center))
	for index in chunks.keys():
		if absi(index.x-center.x)>2 or absi(index.y-center.y)>2:
			chunks[index].queue_free()
			chunks.erase(index)

func _process(_dt: float) -> void:
	if vehicle:
		stream_at(vehicle.global_position)
	# At most one fresh chunk per render frame; the ring is ~200m ahead.
	if not pending.is_empty():
		_build_chunk(pending.pop_front())

func surface_at(position_px: Vector2) -> Dictionary:
	surface_queries += 1
	var point := position_px/PPM
	var key := "%d,%d" % [floori(point.x/float(data.surface_cell)),floori(point.y/float(data.surface_cell))]
	# Facilities are concrete parking aprons connected to the road graph.
	for prop in _apron_grid.get(key,[]):
		var center := Vector2(float(prop.p[0]),float(prop.p[1]))
		var local := (point-center).rotated(-float(prop.angle))
		if absf(local.x)<=float(prop.size[0])*.5 and absf(local.y)<=float(prop.size[1])*.5:
			return {"name":"ASPHALT","grip":1.0}
	for index in _junction_grid.get(key,[]):
		var j: Dictionary = data.junctions[index]
		if Geometry2D.is_point_in_polygon(point,_junction_polygons[index]):
			return {"name":"ASPHALT","grip":1.0}
	for index in data.surface_index.get(key,[]):
		segment_tests += 1
		var segment: Dictionary = data.segments[int(index)]
		var a := Vector2(float(segment.a[0]),float(segment.a[1]))
		var b := Vector2(float(segment.b[0]),float(segment.b[1]))
		var r: Dictionary = data.roads[int(segment.road)]
		var distance_sq := Geometry2D.get_closest_point_to_segment(point,a,b).distance_squared_to(point)
		var road_radius := float(r.width) * 0.5
		if distance_sq <= road_radius * road_radius:
			return {"name":str(r.surface),"grip":0.55 if r.surface=="GRAVEL" else 1.0}
		# Sidewalks are actual hard ground beside BOTH sides of urban roads,
		# rather than a pretty strip incorrectly treated as slippery grass.
		# The baked 12m road-index margin already covers this extra 3.3m.
		if r.kind in ["local", "arterial"]:
			var walk_radius := road_radius + 3.3
			if distance_sq <= walk_radius * walk_radius:
				return {"name":"ASPHALT","grip":0.93}
	var chunk_key := "%d,%d" % [floori(point.x/chunk_m),floori(point.y/chunk_m)]
	if _sand_polygons.has(chunk_key) and Geometry2D.is_point_in_polygon(point,_sand_polygons[chunk_key]):
		return {"name":"SAND","grip":0.32}
	return {"name":"GRASS","grip":0.38}

func location_at(position_px: Vector2) -> Dictionary:
	var p := position_px/PPM
	var best := INF
	var result := {"name":"MORROW COAST","subtitle":"The long way home"}
	for district in data.districts:
		var score := p.distance_to(Vector2(float(district.p[0]),float(district.p[1])))/float(district.radius)
		if score<best:
			best = score
			result = district
	return result

func _physics_process(dt: float) -> void:
	if not vehicle:
		return
	if vehicle.linear_velocity.length() < 3.0:
		tire_marks.reset_tracks()
		return
	mark_clock += dt
	if mark_clock < 0.045:
		return
	mark_clock = 0.0
	if absf(vehicle.slip_angle) <= 0.13 and vehicle.handbrake <= 0.1 and vehicle.wheel_spin <= 0.15 and vehicle.surface == "ASPHALT":
		tire_marks.reset_tracks()
		return
	var right := Vector2.RIGHT.rotated(vehicle.rotation)
	var rear := vehicle.position + Vector2.DOWN.rotated(vehicle.rotation) * 25.0
	for track in 2:
		var side := -1.0 if track == 0 else 1.0
		tire_marks.add_mark(rear + right * side * 16.0,
			vehicle.rotation, vehicle.surface == "ASPHALT", track)
