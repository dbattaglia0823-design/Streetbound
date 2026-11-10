class_name MorrowCoast
extends Node2D
## Metre-authored world; cached 192m chunks, a 64m surface index and local blockers.
const Chunk = preload("res://scripts/world/coast_chunk.gd")
const TireMarks = preload("res://scripts/world/tire_marks.gd")
const MapGeometry = preload("res://scripts/world/map_geometry.gd")
const GarageGeometry = preload("res://scripts/world/garage_geometry.gd")
const PPM := 20.0
var data: Dictionary
var player_garage_prop: Dictionary = {}
var dealerships: Node2D
var chunk_m := 192.0
var vehicle: VehicleController2D
var tire_marks: TireMarks2D
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
## Cached boardwalk coverage avoids expensive shoreline clipping in inland
## streamed cells; coverage is expanded to include planks and rail overhang.
var _boardwalk_cells: Dictionary = {}
var chunk_build_count := 0
var cached_chunk_reuses := 0
## Optional developer-only diagnostics; no label or per-frame monitors
## are created or sampled until F7 is requested.
var performance_debug_enabled := false
var performance_hud: CanvasLayer
var performance_label: Label
var _performance_clock := 0.0
var debug_geometry_enabled := false
var debug_hud: CanvasLayer
var debug_label: Label
var _debug_clock := 0.0

func _ready() -> void:
	data = JSON.parse_string(FileAccess.get_file_as_string("res://worlds/morrow-coast.world.json"))
	for prop in data.props:
		if GarageGeometry.is_player_garage(prop):
			player_garage_prop = prop
			break
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
	# The boardwalk is long, but touches only a handful of 192-metre cells.
	# Index its segment AABBs once instead of intersecting the full
	# shoreline against every inland chunk when driving through the city.
	for i in range(1, boardwalk_path.size()):
		var a: Vector2 = boardwalk_path[i - 1]
		var b: Vector2 = boardwalk_path[i]
		var first := Vector2i(((a.min(b) - Vector2.ONE * 12.0) / chunk_m).floor())
		var last := Vector2i(((a.max(b) + Vector2.ONE * 12.0) / chunk_m).floor())
		for x in range(first.x,last.x + 1):
			for y in range(first.y,last.y + 1):
				_boardwalk_cells[Vector2i(x,y)] = true
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
	_create_geometry_inspector()

## Read-only map/physics tooling, all inputs/outputs in WORLD pixels except
## explicitly named metre fields. Physics continues using surface_at().
func geometry_at(position_px: Vector2) -> Dictionary:
	return MapGeometry.inspect(self, position_px)


func nearest_road_at(position_px: Vector2, radius_m := 12.0) -> Dictionary:
	return MapGeometry.nearest_road(self, position_px, radius_m)


func can_place_at(position_px: Vector2, radius_m := 2.0, margin_m := 1.0) -> Dictionary:
	return MapGeometry.placement_check(self, position_px, radius_m, margin_m)


func _create_geometry_inspector() -> void:
	debug_hud = CanvasLayer.new()
	debug_hud.name = "MapGeometryHUD"
	debug_hud.layer = 12
	debug_hud.visible = false
	add_child(debug_hud)
	debug_label = Label.new()
	debug_label.position = Vector2(16, 112)
	debug_label.add_theme_font_size_override("font_size", 13)
	debug_label.add_theme_color_override("font_color", Color("edf5f4"))
	debug_label.add_theme_color_override("font_shadow_color", Color(0.0,0.0,0.0,0.9))
	debug_label.add_theme_constant_override("shadow_offset_x", 2)
	debug_label.add_theme_constant_override("shadow_offset_y", 2)
	debug_label.text = "F4 / MAP GEOMETRY\nCYAN road    AMBER sidewalk    PINK junction\nGREEN boardwalk    RED obstacle    GRAY terrain"
	debug_hud.add_child(debug_label)


func set_geometry_debug(enabled: bool) -> void:
	debug_geometry_enabled = enabled
	if is_instance_valid(debug_hud):
		debug_hud.visible = enabled
	for index in chunks:
		var overlay: Node2D = chunks[index].get_node_or_null("GeometryOverlay")
		if overlay != null:
			overlay.set_enabled(enabled)


func _unhandled_input(event: InputEvent) -> void:
	# Explicit developer tool: no persistent player setting or normal-game
	# rendering overhead. This key is not used by current driving controls.
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and (key.keycode == KEY_F4 or key.physical_keycode == KEY_F4):
			set_geometry_debug(not debug_geometry_enabled)
			get_viewport().set_input_as_handled()
		elif key.pressed and not key.echo and (key.keycode == KEY_F7 or key.physical_keycode == KEY_F7):
			set_performance_debug(not performance_debug_enabled)
			get_viewport().set_input_as_handled()


## Useful when comparing visual changes or new map props: counts and timings
## are measured by Godot, not theoretical speedup claims. Sampling is throttled.
func set_performance_debug(enabled: bool) -> void:
	performance_debug_enabled = enabled
	if enabled and not is_instance_valid(performance_hud):
		performance_hud = CanvasLayer.new()
		performance_hud.name = "PerformanceHUD"
		performance_hud.layer = 100
		add_child(performance_hud)
		performance_label = Label.new()
		performance_label.name = "PerformanceStats"
		performance_label.position = Vector2(16, 16)
		performance_label.add_theme_font_size_override("font_size", 13)
		performance_label.add_theme_color_override("font_color", Color("e9f1ed"))
		performance_label.add_theme_color_override("font_shadow_color", Color(0,0,0,.9))
		performance_label.add_theme_constant_override("shadow_offset_x", 2)
		performance_label.add_theme_constant_override("shadow_offset_y", 2)
		performance_hud.add_child(performance_label)
	if is_instance_valid(performance_hud):
		performance_hud.visible = enabled
	if enabled:
		_performance_clock = 10.0


func _update_performance_display() -> void:
	if not is_instance_valid(performance_label):
		return
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var texture_mb := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / (1024.0 * 1024.0)
	var traffic_count := get_tree().get_nodes_in_group("traffic_vehicle").size()
	performance_label.text = "F7 / MORROW PERFORMANCE (toggle)\n" + \
		"FPS %.0f | CPU frame %.2f ms | Physics %.2f ms\n" % [fps,frame_ms,physics_ms] + \
		"Draw calls %d | Texture memory %.1f MB\n" % [draws,texture_mb] + \
		"Active/cached chunks %d/%d | Traffic %d\n" % [
			active_chunk_count(),chunks.size(),traffic_count] + \
		"Chunk builds %d | Cached reuses %d | Max build %.2f ms" % [
			chunk_build_count,cached_chunk_reuses,float(max_chunk_build_usec)/1000.0]


func spawn_position() -> Vector2:
	return Vector2(float(data.spawn.position[0]),float(data.spawn.position[1]))*PPM

func spawn_rotation() -> float:
	return float(data.spawn.rotation)

## Only active chunks draw or participate in physics. The larger 5x5
## resident ring exists to prevent repeated construction near cell boundaries.
func boardwalk_near_cell(index: Vector2i) -> bool:
	return _boardwalk_cells.has(index)


func active_chunk_count() -> int:
	var total := 0
	for chunk in chunks.values():
		if bool(chunk.stream_active):
			total += 1
	return total


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
	# An initial synchronous spawn chunk is active even before stream_at()
	# establishes current_cell; later preloads obey the live 3x3 radius.
	var active_center: Vector2i = index if current_cell.x == -999 else current_cell
	instance.set_stream_active(maxi(absi(index.x - active_center.x),
		absi(index.y - active_center.y)) <= 1)
	chunks[index] = instance
	chunk_build_count += 1
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
			else:
				cached_chunk_reuses += 1
	pending.sort_custom(func(a: Vector2i,b: Vector2i): return a.distance_squared_to(center)<b.distance_squared_to(center))
	for index in chunks.keys():
		var cell_delta := maxi(absi(index.x-center.x),absi(index.y-center.y))
		if cell_delta > 2:
			chunks[index].queue_free()
			chunks.erase(index)
		else:
			# One toggle per cell crossing, not per frame. The dormant outer
			# ring stores geometry but contributes zero draw/collision layer.
			chunks[index].set_stream_active(cell_delta <= 1)

func _process(dt: float) -> void:
	if vehicle:
		stream_at(vehicle.global_position)
	# At most one fresh chunk per render frame; the ring is ~200m ahead.
	if not pending.is_empty():
		_build_chunk(pending.pop_front())
	if performance_debug_enabled:
		_performance_clock += dt
		if _performance_clock >= 0.45:
			_performance_clock = 0.0
			_update_performance_display()
	if debug_geometry_enabled and is_instance_valid(debug_label) and is_instance_valid(vehicle):
		_debug_clock += dt
		if _debug_clock >= 0.18:
			_debug_clock = 0.0
			var info := geometry_at(vehicle.global_position)
			var road_text := "none"
			if info.has("road_name"):
				road_text = "%s / %.1fm to edge" % [str(info.road_name), float(info.distance_to_road_edge_m)]
			var can_build := can_place_at(vehicle.global_position, 2.0, 1.0)
			debug_label.text = "F4 / MAP GEOMETRY (toggle)\n" + \
				"CYAN road  AMBER sidewalks  PINK junction  GREEN boardwalk\n" + \
				"RED obstacles  GRAY terrain / parcels\n" + \
				"Region: %s | Surface: %s | Grip: %.2f\n" % [
					str(info.region), str(info.surface), float(info.grip)] + \
				"Road: %s\n" % road_text + \
				"Placement: %s (%s)" % [
					"clear" if bool(can_build.clear) else "blocked", str(can_build.reason)]

func surface_at(position_px: Vector2) -> Dictionary:
	surface_queries += 1
	var point := position_px/PPM
	# Dealership forecourts and access driveways are part of the driving surface.
	if is_instance_valid(dealerships) and dealerships.is_paved_forecourt(position_px):
		return {"name":"ASPHALT","grip":1.0}
	# The physical opening replaces the solid center of the existing garage,
	# so its interior must be a grippy, paved surface rather than grass.
	if not player_garage_prop.is_empty() and GarageGeometry.inside_bay(
		player_garage_prop, position_px):
		return {"name": "ASPHALT", "grip": 1.0}
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

## Lightweight wheel-contact elevation for visuals. The paved sidewalk is
## physically traversable and 0.93-grip; a 12 cm curb is represented only by
## a normalized art offset. This intentionally does not modify car collision.
func curb_height_at(position_px: Vector2) -> float:
	var contact: Dictionary = surface_at(position_px)
	if str(contact.name) != "ASPHALT" or absf(float(contact.grip)-0.93) > 0.015:
		return 0.0
	var road: Dictionary = nearest_road_at(position_px,24.0)
	if road.is_empty() or str(road.road_kind) not in ["local","arterial"]:
		return 0.0
	var edge: float = float(road.distance_to_road_edge_m)
	if edge < -0.1 or edge > 3.3:
		return 0.0
	return smoothstep(0.0,0.45,edge)


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
	if mark_clock < 0.035:
		return
	mark_clock = 0.0
	var slide := smoothstep(0.08,0.34,absf(vehicle.slip_angle))
	var loss := maxf(slide,maxf(vehicle.handbrake,maxf(vehicle.handbrake_grip_loss,vehicle.wheel_spin*1.8)))
	if loss < 0.13 and vehicle.surface == "ASPHALT":
		tire_marks.reset_tracks()
		return
	# Sample the actual fitted rear wheel anchors (not a generic 16px offset),
	# even for long trucks and narrow sports cars. Visual curb lift never
	# changes these true contact coordinates.
	var rig := vehicle.get_node_or_null("Art/Wheels")
	for track in 2:
		var wheel: Vector2 = Vector2(-16.0,25.0) if track == 0 else Vector2(16.0,25.0)
		if is_instance_valid(rig) and rig.has_method("wheel_anchor"):
			wheel = rig.wheel_anchor(2+track)
		var contact := vehicle.global_position + wheel.rotated(vehicle.rotation)
		var contact_surface: Dictionary = surface_at(contact)
		tire_marks.add_mark(contact,vehicle.rotation,
			str(contact_surface.name) == "ASPHALT",track,
			str(contact_surface.name),loss)
