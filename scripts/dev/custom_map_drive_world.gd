extends Node2D
## Isolated, development-only driving surface for an authored custom map.
## Reuses the native builder's metre-scaled terrain, road and scenery renderers.
const EditSession = preload("res://scripts/dev/native_map_edit_session.gd")
const Terrain = preload("res://scripts/dev/custom_map_terrain.gd")
const Gizmos = preload("res://scripts/dev/native_world_editor_gizmos.gd")
const PPM := 20.0
const INDEX_CELL := 64.0

var doc: Dictionary = {}
# The source-only renderer expects the same minimal world fields as the editor.
var data: Dictionary = {}
var _road_cells: Dictionary = {}
var _terrain_regions: Array[Dictionary] = []

func configure(source: Dictionary) -> bool:
	var validator := EditSession.new()
	if not bool(source.get("customMap",false)) or not validator._valid_source(source):
		return false
	doc = source.duplicate(true)
	data = {"size":[doc.world.width,doc.world.height],
		"roads":[],"props":[],"junctions":[],"segments":[]}
	_index_surfaces()
	return true

func _ready() -> void:
	if doc.is_empty():
		return
	var terrain := Terrain.new()
	terrain.z_index = -10
	add_child(terrain)
	terrain.update_map(doc)

	# With an empty comparison baseline all saved roads and props are drawn.
	# Runtime mode removes selection outlines, handles and lane guides.
	var drawing := Gizmos.new()
	drawing.world = self
	drawing.custom_terrain = true
	drawing.runtime_playtest = true
	drawing.show_lanes = false
	drawing.show_junctions = false
	drawing.layer_flags = {"terrain":false,"roads":true,"scenery":true,
		"markers":false,"grid":false}
	add_child(drawing)
	drawing.z_index = -7
	drawing.set_draft(doc,{})
	drawing.set_preview_collision_enabled(true)
	drawing.visible = true
	if is_instance_valid(drawing.preview_scenery):
		drawing.preview_scenery.z_index = 8
	_add_map_boundary()

func _index_surfaces() -> void:
	_road_cells.clear()
	_terrain_regions.clear()
	for raw in doc.get("regions",[]):
		var polygon := PackedVector2Array()
		for point in raw.get("points",[]):
			polygon.append(Vector2(float(point.x),float(point.y)))
		_terrain_regions.append({"shape":polygon,"biome":str(raw.get("biome","grass"))})
	for road in doc.get("roads",[]):
		var path: PackedVector2Array = EditSession.road_path(road)
		var radius: float = float(road.get("width",10.0)) * 0.5
		var road_surface: String = str(road.get("surface","asphalt")).to_lower()
		for i in range(1,path.size()):
			var a: Vector2 = path[i-1]
			var b: Vector2 = path[i]
			if a.distance_squared_to(b) < 0.0001:
				continue
			var min_corner := a.min(b) - Vector2.ONE * radius
			var max_corner := a.max(b) + Vector2.ONE * radius
			var first := Vector2i((min_corner / INDEX_CELL).floor())
			var last := Vector2i((max_corner / INDEX_CELL).floor())
			var segment := {"a":a,"b":b,"radius_sq":radius*radius,"surface":road_surface}
			for x in range(first.x,last.x+1):
				for y in range(first.y,last.y+1):
					var key := "%d,%d" % [x,y]
					if not _road_cells.has(key):
						_road_cells[key] = []
					_road_cells[key].append(segment)

func surface_at(position_px: Vector2) -> Dictionary:
	var p := position_px / PPM
	var key := "%d,%d" % [floori(p.x/INDEX_CELL),floori(p.y/INDEX_CELL)]
	var loose_surface := ""
	# Asphalt wins over overlapping dirt/gravel regardless of road order.
	for segment in _road_cells.get(key,[]):
		var closest := Geometry2D.get_closest_point_to_segment(p,segment.a,segment.b)
		if closest.distance_squared_to(p) > float(segment.radius_sq):
			continue
		var material: String = segment.surface
		if material in ["gravel","dirt"]:
			loose_surface = material
		else:
			return {"name":"ASPHALT","grip":1.0}
	if not loose_surface.is_empty():
		return {"name":"GRAVEL","grip":0.75}
	# Authoring regions are painted in order: the most recent polygon wins.
	for i in range(_terrain_regions.size()-1,-1,-1):
		var region: Dictionary = _terrain_regions[i]
		if Geometry2D.is_point_in_polygon(p,region.shape):
			return _terrain_grip(str(region.biome))
	return _terrain_grip(str(doc.world.get("base","grass")))

func _terrain_grip(biome: String) -> Dictionary:
	match biome:
		"beach","desert":
			return {"name":"SAND","grip":0.60}
		"lake","ocean":
			return {"name":"WATER","grip":0.20}
		"rock","mountain":
			return {"name":"GRAVEL","grip":0.75}
		"city":
			return {"name":"ASPHALT","grip":0.93}
		_:
			return {"name":"GRASS","grip":0.68}

func test_spawn() -> Dictionary:
	for marker in doc.get("markers",[]):
		if str(marker.get("type","")) == "player_spawn":
			return {"position":Vector2(float(marker.x),float(marker.y))*PPM,
				"rotation":deg_to_rad(float(marker.get("rotation",0.0)))}
	# Blank maps are drivable, and a road-only map starts on a paved segment.
	var center := Vector2(float(doc.world.width),float(doc.world.height)) * 0.5
	var best := INF
	var result := {"position":center*PPM,"rotation":0.0}
	for road in doc.get("roads",[]):
		var path: PackedVector2Array = EditSession.road_path(road)
		if path.size()<2:
			continue
		var index := clampi(int(path.size()/2),1,path.size()-1)
		var at: Vector2 = (path[index-1]+path[index])*0.5
		var distance := at.distance_squared_to(center)
		if distance < best:
			best = distance
			var direction: Vector2 = (path[index]-path[index-1]).normalized()
			result = {"position":at*PPM,"rotation":Vector2.UP.angle_to(direction)}
	return result

func _add_map_boundary() -> void:
	var width_px := float(doc.world.width)*PPM
	var height_px := float(doc.world.height)*PPM
	var corners := [Vector2.ZERO,Vector2(width_px,0),
		Vector2(width_px,height_px),Vector2(0,height_px)]
	var walls := StaticBody2D.new()
	walls.name = "MapBoundary"
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	for i in corners.size():
		var collider := CollisionShape2D.new()
		var segment := SegmentShape2D.new()
		segment.a = corners[i]
		segment.b = corners[(i+1)%corners.size()]
		collider.shape = segment
		walls.add_child(collider)
