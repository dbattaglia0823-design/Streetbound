extends Node2D
## Cached static illustration and local collision for a 192m square.
const PPM := 20.0
var world: Node2D
var cell := Vector2i.ZERO
var content: Dictionary
var origin_m := Vector2.ZERO
var road_batches: Array[Dictionary] = []
var prop_list: Array[Dictionary] = []
var ground_polys: Array[Dictionary] = []
var junction_list: Array[Dictionary] = []
var build_microseconds := 0

func point(raw: Array) -> Vector2:
	return (Vector2(float(raw[0]), float(raw[1])) - origin_m) * PPM

func setup(owner_world: Node2D, index: Vector2i, data: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	world = owner_world
	cell = index
	content = data
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
		ground_polys.append({"points": polygon, "color": Color(terrain.color),"kind":terrain.kind})
	for prop_index in data.get("props", []):
		prop_list.append(world.data.props[int(prop_index)])
	prop_list.sort_custom(func(a: Dictionary,b: Dictionary): return _prop_order(a)<_prop_order(b))
	for junction_index in data.get("junctions", []):
		junction_list.append(world.data.junctions[int(junction_index)])
	# Global stage ordering prevents neighboring shoulders painting over asphalt.
	for stage in 4:
		var roads := Node2D.new()
		roads.set_script(preload("res://scripts/world/coast_roads.gd"))
		roads.world=world
		roads.origin_m=origin_m
		roads.road_batches=road_batches
		roads.junction_list=junction_list
		roads.render_stage=stage
		roads.z_index=stage+1
		add_child(roads)
	for stage in 2:
		var relief := Node2D.new()
		relief.set_script(preload("res://scripts/world/coast_relief.gd"))
		relief.world=world
		relief.origin_m=origin_m
		relief.content=content
		relief.render_stage=stage
		relief.z_index=5
		add_child(relief)
	var shadows := Node2D.new()
	shadows.set_script(preload("res://scripts/world/coast_shadows.gd"))
	shadows.prop_list=prop_list
	shadows.origin_m=origin_m
	shadows.z_index=5
	add_child(shadows)
	var scenery := Node2D.new()
	scenery.set_script(preload("res://scripts/world/coast_scenery.gd"))
	scenery.prop_list = prop_list
	scenery.origin_m = origin_m
	scenery.z_index = 6
	add_child(scenery)
	_build_collisions()
	build_microseconds = Time.get_ticks_usec() - started

func _ready() -> void:
	material=preload("res://scripts/world/mountain_ground.tres")

func _prop_order(prop: Dictionary) -> int:
	if prop.kind in ["field","garden","lot","forecourt","start_line","finish_line"]:
		return 0
	if prop.kind in ["tree","pine","palm","lamp","planter"]:
		return 2
	return 1

func _build_collisions() -> void:
	var body := StaticBody2D.new()
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
		else:
			var box := RectangleShape2D.new()
			box.size = Vector2(float(prop.size[0]), float(prop.size[1])) * PPM
			collider.shape = box
		collider.position = point(prop.p)
		collider.rotation = float(prop.angle)
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
	draw_rect(Rect2(Vector2.ZERO,Vector2.ONE*world.chunk_m*PPM),Color("a3b789"))
	for terrain in ground_polys:
		if terrain.points.size()>=3:
			draw_colored_polygon(terrain.points,terrain.color)
			if terrain.kind in ["ocean","water"]:
				for x in range(0,int(world.chunk_m*PPM),450):
					for y in range(0,int(world.chunk_m*PPM),470):
						var p := Vector2(x+100+sin(float(y)) * 80,y+140)
						if Geometry2D.is_point_in_polygon(p,terrain.points):
							draw_arc(p,55,.15,2.7,12,Color(.8,.91,.86,.18),2,true)
	# Quiet grass texture, baked in the chunk draw cache rather than per-frame.
	var rng := RandomNumberGenerator.new()
	rng.seed = cell.x * 9387 + cell.y * 14731 + 41
	for i in 55:
		var p: Vector2 = Vector2(rng.randf(),rng.randf())*world.chunk_m*PPM
		draw_line(p,p+Vector2(4,0),Color(0.42,0.53,0.35,0.13),2)
