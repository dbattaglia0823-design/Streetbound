extends Node2D
## Cached static illustration and local collision for a 192m square.
const PPM := 20.0
## UV tags identify materials explicitly; authored colors never decide surface type.
const TERRAIN_TAGS := {"grass":2,"meadow":2,"town":2,"forest":3,
	"mountain":4,"rock":5,"beach":6,"sand":6,"ocean":7,"water":8,"lake":8,
	"foam":9,"riverbank":9,"farmland":10,"field":10,"city":11,
	"desert":12,"dirt":13,"gravel":14,"highland":15}
static var _terrain_texture: Texture2D

static func terrain_texture() -> Texture2D:
	# Canvas polygons discard UVs without a texture. One shared white texel
	# preserves material tags without adding per-chunk texture allocations.
	if _terrain_texture==null:
		var image:=Image.create(1,1,false,Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_terrain_texture=ImageTexture.create_from_image(image)
	return _terrain_texture

static func terrain_uvs(count: int, kind: String) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(count)
	result.fill(Vector2(float(TERRAIN_TAGS.get(kind,2)),0.0))
	return result
const GarageGeometry = preload("res://scripts/world/garage_geometry.gd")
const Scenery = preload("res://scripts/world/coast_scenery.gd")
var world: Node2D
var cell := Vector2i.ZERO
var content: Dictionary
var origin_m := Vector2.ZERO
var road_batches: Array[Dictionary] = []
var prop_list: Array[Dictionary] = []
var ground_polys: Array[Dictionary] = []
var junction_list: Array[Dictionary] = []
var build_microseconds := 0
## Retained streaming cells keep prebuilt geometry but aren't submitted to
## the renderer or queried by physics until they enter the playable 3x3 ring.
var stream_active := true
## True only for the read-only map's duplicate render chunks. Never allocate
## physics bodies in a map viewport: the real world already owns collisions.
var map_render_only := false
var collider_body: StaticBody2D
var collision_shape_count := 0
var setup_complete := false
var setup_error := ""


func point(raw: Array) -> Vector2:
	return (Vector2(float(raw[0]), float(raw[1])) - origin_m) * PPM

func setup(owner_world: Node2D, index: Vector2i, data: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	world = owner_world
	cell = index
	content = data
	# Reject incomplete world initialization before constructing a terrain-only
	# cell that would otherwise be cached as a successful populated chunk.
	if world.segment_stations.size()!=world.data.get("segments",[]).size():
		setup_error="Road stations not initialized"
		return
	for field in ["segments","props","junctions","walls"]:
		for entry in content.get(field,[]):
			if int(entry)<0 or int(entry)>=world.data.get(field,[]).size():
				setup_error="Invalid %s assignment in %s"%[field,cell]
				return
	origin_m = Vector2(cell) * world.chunk_m
	position = origin_m * PPM
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Merge successive samples into polylines to avoid a draw call per segment.
	var batches: Dictionary = {}
	for segment_index in data.get("segments", []):
		var segment: Dictionary = world.data.segments[int(segment_index)]
		var road_id := int(segment.road)
		if not batches.has(road_id):
			batches[road_id] = []
		batches[road_id].append(int(segment_index))
	for road_id in batches:
		var indices: Array = batches[road_id]
		indices.sort()
		var path := PackedVector2Array()
		var previous := -2
		var phase := 0.0
		for segment_index in indices:
			var segment: Dictionary = world.data.segments[segment_index]
			if segment_index != previous + 1 and path.size() > 1:
				road_batches.append({"path": path, "road": world.data.roads[road_id],"phase":phase})
				path = PackedVector2Array()
			if path.is_empty():
				phase=float(world.segment_stations[segment_index])*PPM
				path.append(point(segment.a))
			path.append(point(segment.b))
			previous = segment_index
		if path.size() > 1:
			road_batches.append({"path": path, "road": world.data.roads[road_id],"phase":phase})
	for batch in road_batches:
		batch["markings"]=preload("res://scripts/world/road_marking_clip.gd").parts(batch.path,float(batch.phase),batch.road.get("marking_gaps",[]))
	for terrain in data.get("terrain", []):
		var polygon := PackedVector2Array()
		for p in terrain.points:
			polygon.append(point(p))
		ground_polys.append({"points": polygon, "color": Color(terrain.color),"kind":terrain.kind,
			"uvs":terrain_uvs(polygon.size(),str(terrain.kind))})
	for prop_index in data.get("props", []):
		prop_list.append(world.data.props[int(prop_index)])
	prop_list.sort_custom(func(a: Dictionary,b: Dictionary): return _prop_order(a)<_prop_order(b))
	for junction_index in data.get("junctions", []):
		junction_list.append(world.data.junctions[int(junction_index)])
	# Global stage ordering prevents neighboring shoulders painting over asphalt.
	for stage in 4:
		# Preserve the four-stage paint order only where roads/junctions exist.
		if road_batches.is_empty() and junction_list.is_empty():
			break
		var roads := Node2D.new()
		roads.set_script(preload("res://scripts/world/coast_roads.gd"))
		roads.world=world
		roads.origin_m=origin_m
		roads.road_batches=road_batches
		roads.junction_list=junction_list
		roads.render_stage=stage
		roads.z_index=stage+1
		add_child(roads)
	# Wooden boardwalk is part of the static chunk artwork. Roads at higher
	# stages still render over it where a coastal street reaches the shore.
	if world.boardwalk_near_cell(cell):
		var boardwalk := Node2D.new()
		boardwalk.name = "BeachBoardwalk"
		boardwalk.set_script(preload("res://scripts/world/coast_boardwalk.gd"))
		boardwalk.world = world
		boardwalk.origin_m = origin_m
		boardwalk.z_index = 1
		add_child(boardwalk)
	for stage in 2:
		if content.get("relief", []).is_empty() and content.get("rails", []).is_empty():
			break
		var relief := Node2D.new()
		relief.set_script(preload("res://scripts/world/coast_relief.gd"))
		relief.world=world
		relief.origin_m=origin_m
		relief.content=content
		relief.render_stage=stage
		relief.z_index=5
		add_child(relief)
	if not prop_list.is_empty():
		# Pavement is terrain, not an above-road prop. Previously the scenery
		# batch at z=6 painted entire parking rectangles over roadbed, kerbs
		# and lane markings (z=2..4) near roadside lot entrances.
		var paved_props: Array[Dictionary] = []
		var above_road_props: Array[Dictionary] = []
		for prop in prop_list:
			if str(prop.kind) in ["lot", "forecourt"]:
				paved_props.append(prop)
			else:
				above_road_props.append(prop)
		if not paved_props.is_empty():
			var pavement := Node2D.new()
			pavement.name = "ParkingPavement"
			pavement.set_script(preload("res://scripts/world/coast_scenery.gd"))
			pavement.prop_list = paved_props
			pavement.origin_m = origin_m
			pavement.z_index = 1
			add_child(pavement)
		if not above_road_props.is_empty():
			var shadows := Node2D.new()
			shadows.set_script(preload("res://scripts/world/coast_shadows.gd"))
			shadows.prop_list = above_road_props
			shadows.origin_m = origin_m
			shadows.z_index = 5
			add_child(shadows)
			var scenery := Node2D.new()
			scenery.set_script(preload("res://scripts/world/coast_scenery.gd"))
			scenery.prop_list = above_road_props
			scenery.origin_m = origin_m
			scenery.z_index = 6
			add_child(scenery)
	# Furnish curb edges in one static draw node per road-bearing chunk.
	# Lamps, benches and signs follow the real spline and avoid junctions;
	# no per-furnishing sprite or physics nodes are created.
	if not road_batches.is_empty():
		var details := Node2D.new()
		details.name = "StreetDetails"
		details.set_script(preload("res://scripts/world/coast_roadside_details.gd"))
		details.origin_m = origin_m
		details.chunk_size_px = world.chunk_m * PPM
		details.road_batches = road_batches
		details.junction_list = junction_list
		details.z_index = 5
		add_child(details)
	# Non-gameplay boundary metadata. Lazy: no boundary outlines are generated
	# or submitted to the renderer unless F4 developer mode is explicitly on.
	var geometry_overlay := Node2D.new()
	geometry_overlay.name = "GeometryOverlay"
	geometry_overlay.set_script(preload("res://scripts/world/map_geometry_overlay.gd"))
	geometry_overlay.world = world
	geometry_overlay.chunk = self
	geometry_overlay.z_index = 45
	geometry_overlay.visible = bool(world.debug_geometry_enabled)
	add_child(geometry_overlay)
	if not map_render_only:
		_build_collisions()
	build_microseconds = Time.get_ticks_usec() - started
	setup_complete=true

## Called once when a cached chunk enters/exits the active play ring,
## never per render frame. Dormant collisions keep their shapes for reuse.
func set_stream_active(active: bool) -> void:
	stream_active = active
	visible = active
	if is_instance_valid(collider_body):
		collider_body.collision_layer = 1 if active else 0


func _ready() -> void:
	material=preload("res://scripts/world/mountain_ground.tres")

func _prop_order(prop: Dictionary) -> int:
	if prop.kind in ["field","garden","lot","forecourt","start_line","finish_line"]:
		return 0
	if prop.kind in ["tree","pine","palm","lamp","planter"]:
		return 2
	return 1

func _build_collisions() -> void:
	# Empty ocean/terrain cells should not allocate an invisible physics body.
	var solids := 0
	for prop in prop_list:
		if bool(prop.solid):
			solids += 1
	if solids == 0 and content.get("walls", []).is_empty():
		return
	var body := StaticBody2D.new()
	collider_body = body
	collision_shape_count = solids + content.get("walls", []).size()
	body.collision_layer = 1
	body.collision_mask = 2
	add_child(body)
	for prop in prop_list:
		if not prop.solid:
			continue
		var collider := CollisionShape2D.new()
		if prop.kind in ["tree", "pine", "palm", "island"]:
			var circle := CircleShape2D.new()
			circle.radius = float(prop.radius) * PPM
			collider.shape = circle
		elif GarageGeometry.is_player_garage(prop):
			# The starter garage has three solid walls but a physically open
			# front bay. The car must actually drive through the entrance.
			collider.queue_free()
			for wall: Rect2 in GarageGeometry.wall_rects(
				GarageGeometry.size_of(prop)):
				var wall_collider := CollisionShape2D.new()
				var wall_shape := RectangleShape2D.new()
				wall_shape.size = wall.size * PPM
				wall_collider.shape = wall_shape
				wall_collider.position = point(prop.p) + \
					wall.get_center().rotated(float(prop.angle)) * PPM
				wall_collider.rotation = float(prop.angle)
				body.add_child(wall_collider)
			collision_shape_count += 2
			continue
		else:
			var box := RectangleShape2D.new()
			box.size = Vector2(float(prop.size[0]), float(prop.size[1])) * PPM
			collider.shape = box
		collider.position = point(prop.p)
		collider.rotation = float(prop.angle)
		collider.set_meta("editor_prop_key",Scenery.editor_key(prop))
		body.add_child(collider)
	for wall_index in content.get("walls", []):
		var wall: Array = world.data.walls[int(wall_index)]
		var a := point(wall[0])
		var b := point(wall[1])
		var collider := CollisionShape2D.new()
		var shape := SegmentShape2D.new()
		shape.a = a
		shape.b = b
		collider.shape = shape
		body.add_child(collider)

func _rounded(rect: Rect2, color: Color, radius := 12.0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	draw_style_box(style, rect)

func _draw() -> void:
	var extent: float = world.chunk_m*PPM
	var base := PackedVector2Array([Vector2.ZERO,Vector2(extent,0),Vector2.ONE*extent,Vector2(0,extent)])
	draw_polygon(base,PackedColorArray([Color("a3b789")]),terrain_uvs(4,"grass"),terrain_texture())
	for terrain in ground_polys:
		if terrain.points.size()>=3:
			draw_polygon(terrain.points,PackedColorArray([terrain.color]),terrain.uvs,terrain_texture())
	# Decorative strokes are cached with the chunk draw list, never spawned as
	# nodes or moved each frame. Roads are painted in the later stages.
	_draw_ground_foliage()


func ground_kind_at(local_point: Vector2) -> String:
	var kind := "grass"
	# Last clipped polygon wins, matching the order in _draw().
	for terrain in ground_polys:
		if Geometry2D.is_point_in_polygon(local_point, terrain.points):
			kind = str(terrain.kind)
	return kind


func _draw_ground_foliage() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = cell.x * 9387 + cell.y * 14731 + 41
	# 192m chunks are divisible by 12m, keeping the distribution world-aligned.
	var rows := int(world.chunk_m / 12.0)
	for y in rows:
		for x in rows:
			if rng.randf() > 0.66:
				continue
			var p := Vector2(float(x) * 12.0 + rng.randf_range(1.0, 11.0),
				float(y) * 12.0 + rng.randf_range(1.0, 11.0)) * PPM
			var kind := ground_kind_at(p)
			if kind not in ["grass","meadow","forest","farmland","field","highland"]:
				continue
			if kind in ["city", "town"] and rng.randf() > 0.40:
				continue
			var extent := rng.randf_range(6.0, 13.0)
			var shade := Color(.18,.33,.24,.27) if kind == "forest" else 				Color(.44,.42,.30,.24) if kind in ["farmland","field"] else 				Color(.36,.46,.28,.21)
			var highlight := Color(.54,.66,.43,.27) if kind == "forest" else 				Color(.69,.67,.43,.23)
			draw_line(p + Vector2(-extent * 0.55, extent * 0.12), p + Vector2(-extent * 0.15, -extent * 0.75), shade, 2.0, true)
			draw_line(p + Vector2(extent * 0.50, extent * 0.16), p + Vector2(extent * 0.05, -extent), highlight, 2.3, true)
			draw_line(p + Vector2(-extent * 0.10, extent * 0.32), p + Vector2(extent * 0.06, -extent * 0.63), shade, 2.0, true)
			if rng.randf() < 0.08 and kind not in ["mountain", "highland"]:
				draw_circle(p + Vector2(3.0, -extent), 2.4,Color(.91,.83,.58,.45))
			# Small warm soil breaks and wildflowers make open spaces
			# legible without additional foliage nodes or collisions.
			if rng.randf() < (0.23 if kind in ["farmland","field"] else 0.12):
				draw_circle(p+Vector2(13,14),rng.randf_range(3.0,12.0),
					Color(.43,.34,.23,.10 if kind=="forest" else .19))
			elif rng.randf() < .045 and kind in ["grass","forest","meadow","city"]:
				for f in 3:
					var offset := Vector2.from_angle(float(f)*TAU/3.0)*5.0
					draw_circle(p+offset,2.2,Color(.79,.78,.63,.58))
