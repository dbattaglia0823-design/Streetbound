extends Node2D
## Cached static illustration and local collision for a 192m square.
const PPM := 20.0
const Elevation = preload("res://scripts/world/road_elevation.gd")
## UV tags identify materials explicitly; authored colors never decide surface type.
const TERRAIN_TAGS := {"grass":2,"meadow":2,"town":2,"forest":3,
	"mountain":4,"rock":5,"beach":6,"sand":6,"ocean":7,"water":8,"lake":8,
	"foam":9,"riverbank":9,"farmland":10,"field":10,"city":11,
	"desert":12,"dirt":13,"gravel":14,"highland":15,"asphalt":11}
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
const Bridges=preload("res://scripts/world/coast_bridges.gd")
const MountainGeometry=preload("res://scripts/world/mountain_barrier_geometry.gd")
const MountainArt=preload("res://scripts/world/coast_mountain_barriers.gd")
const Guardrails=preload("res://scripts/world/guardrail_geometry.gd")
var world: Node2D
var cell := Vector2i.ZERO
var content: Dictionary
var origin_m := Vector2.ZERO
var road_batches: Array[Dictionary] = []
var tunnel_art: Array[Node2D] = []
var excavation_polygons: Array[PackedVector2Array] = []
var excavation_walls: Array[PackedVector2Array] = []
var excavation_body: StaticBody2D
var excavation_caps: Array[PackedVector2Array] = []
var excavation_cap_body: StaticBody2D
var excavation_mask: ImageTexture
var excavation_bounds: Rect2
var excavation_collision_bits := 0
var deck_art: Array[Node2D] = []
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
## A single collision-free editor overview reuses this drawing pipeline for
## the whole archive. Gameplay chunks keep their normal 192m extent.
var render_extent_m:=Vector2.ZERO
var show_terrain:=true
var collider_body: StaticBody2D
var collision_shape_count := 0
var setup_complete := false
var setup_error := ""
var environment_lights: Node2D


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
	_setup_excavation()
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
			if path.size()>1 and (segment_index != previous+1 or path[-1].distance_to(point(segment.a))>.02):
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
	# Draw the raised deck under the existing pavement, and rails above paint.
	# A real clip rect gives neighboring cells one seamless, non-overdrawn span.
	for stage in 2:
		if content.get("bridges",[]).is_empty():break
		var clip:=Control.new()
		clip.name="BridgeDeckClip" if stage==0 else "BridgeRailsClip"
		clip.mouse_filter=Control.MOUSE_FILTER_IGNORE;clip.clip_contents=true
		clip.size=(Vector2.ONE*world.chunk_m if render_extent_m==Vector2.ZERO else render_extent_m)*PPM
		clip.z_index=1 if stage==0 else 5
		add_child(clip)
		var bridges:=Node2D.new();bridges.set_script(Bridges)
		bridges.world=world;bridges.origin_m=origin_m;bridges.render_stage=stage
		bridges.extent_m=clip.size/PPM;bridges.bridge_indices=content.bridges
		clip.add_child(bridges)
	# Each deck still uses the normal pavement, paint and junction passes.
	var batches_by_layer := {}
	for batch in road_batches:
		var layer := Elevation.artwork_layer(batch.road)
		if Elevation.is_open_cut(batch.road):
			layer = 0 # The approach is an open cut, visible from the surface.
		if not batches_by_layer.has(layer):batches_by_layer[layer] = []
		batches_by_layer[layer].append(batch)
	var junctions_by_layer := {}
	for junction in junction_list:
		var layer := int(junction.get("road_layer",0))
		if not junctions_by_layer.has(layer):junctions_by_layer[layer] = []
		junctions_by_layer[layer].append(junction)
	var layers := batches_by_layer.keys()
	for layer in junctions_by_layer:
		if not layers.has(layer):layers.append(layer)
	for layer in layers:
		for stage in 4:
			var roads := Node2D.new()
			roads.set_script(preload("res://scripts/world/coast_roads.gd"))
			roads.world=world
			roads.origin_m=origin_m
			roads.road_batches.assign(batches_by_layer.get(layer,[]))
			roads.junction_list.assign(junctions_by_layer.get(layer,[]))
			roads.render_stage=stage
			roads.extent_px = (Vector2.ONE*world.chunk_m if render_extent_m == Vector2.ZERO else render_extent_m)*PPM
			roads.z_index=stage+1+16*maxi(int(layer),0)
			if int(layer) != 0:
				roads.set_meta("road_layer",layer)
				if int(layer) < 0:
					tunnel_art.append(roads)
				else:
					deck_art.append(roads)
			add_child(roads)
	# Reuse the surface approach geometry in the underground composite so the
	# route stays visible through the portal as the player's layer changes.
	var approaches: Array[Dictionary]=[]
	for batch in road_batches:
		if Elevation.is_open_cut(batch.road):approaches.append(batch)
	if not approaches.is_empty():
		for stage in 3:
			var interior:=Node2D.new()
			interior.set_script(preload("res://scripts/world/coast_roads.gd"))
			interior.world=world
			interior.origin_m=origin_m
			interior.road_batches.assign(approaches)
			interior.render_stage=stage
			interior.extent_px=(Vector2.ONE*world.chunk_m if render_extent_m==Vector2.ZERO else render_extent_m)*PPM
			interior.set_meta("road_layer",-1)
			tunnel_art.append(interior)
			add_child(interior)
	update_grade_visibility(int(world.viewed_road_layer),int(world.overhead_road_layer))
	# Wooden boardwalk is part of the static chunk artwork. Roads at higher
	# stages still render over it where a coastal street reaches the shore.
	if world.boardwalk_near_cell(cell) or render_extent_m!=Vector2.ZERO:
		var boardwalk := Node2D.new()
		boardwalk.name = "BeachBoardwalk"
		boardwalk.set_script(preload("res://scripts/world/coast_boardwalk.gd"))
		boardwalk.world = world
		boardwalk.origin_m = origin_m
		boardwalk.render_extent_m=render_extent_m
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
		relief.excavation_mask=excavation_mask
		relief.excavation_bounds=excavation_bounds
		relief.z_index=5
		add_child(relief)
	if not prop_list.is_empty():
		# Pavement is terrain, not an above-road prop. Previously the scenery
		# batch at z=6 painted entire parking rectangles over roadbed, kerbs
		# and lane markings (z=2..4) near roadside lot entrances.
		var paved_props: Array[Dictionary] = []
		var above_road_props: Array[Dictionary] = []
		var rail_props: Array[Dictionary] = []
		var ordered_props: Dictionary = {}
		var shadow_props: Array[Dictionary] = []
		for prop in prop_list:
			if str(prop.kind)=="sidewalk":continue
			if str(prop.kind)=="guardrail":
				rail_props.append(prop)
				continue
			var is_pavement: bool = str(prop.kind) in ["lot", "forecourt"]
			if not is_pavement:shadow_props.append(prop)
			var order:=int(prop.get("editor_draw_order",0))
			if order!=0:
				if not ordered_props.has(order):
					var batch: Array[Dictionary]=[]
					ordered_props[order]=batch
				ordered_props[order].append(prop)
			elif is_pavement:
				paved_props.append(prop)
			else:
				above_road_props.append(prop)
		var sidewalks: Array[Dictionary]=[]
		for prop in prop_list:
			if str(prop.kind)=="sidewalk":sidewalks.append(prop)
		if not sidewalks.is_empty():
			var clip:=Control.new();clip.name="SidewalkClip";clip.clip_contents=true
			clip.mouse_filter=Control.MOUSE_FILTER_IGNORE;clip.z_index=1
			clip.size=(Vector2.ONE*world.chunk_m if render_extent_m==Vector2.ZERO else render_extent_m)*PPM;add_child(clip)
			var pavement:=Node2D.new();pavement.set_script(Scenery)
			pavement.prop_list=sidewalks;pavement.origin_m=origin_m;clip.add_child(pavement)
		if not paved_props.is_empty():
			var pavement := Node2D.new()
			pavement.name = "ParkingPavement"
			pavement.set_script(preload("res://scripts/world/coast_scenery.gd"))
			pavement.prop_list = paved_props
			pavement.origin_m = origin_m
			pavement.z_index = 1
			add_child(pavement)
		if not rail_props.is_empty():
			# Clip continuous authored paths to their tile. Neighboring chunks
			# share the same artwork without drawing the entire long path twice.
			var rail_clip:=Control.new()
			rail_clip.name="GuardrailClip"
			rail_clip.clip_contents=true
			rail_clip.mouse_filter=Control.MOUSE_FILTER_IGNORE
			rail_clip.z_index=6
			rail_clip.size=(Vector2.ONE*world.chunk_m if render_extent_m==Vector2.ZERO else render_extent_m)*PPM
			add_child(rail_clip)
			var rail_art:=Node2D.new()
			rail_art.set_script(Scenery)
			rail_art.prop_list=rail_props
			rail_art.origin_m=origin_m
			rail_clip.add_child(rail_art)
		if not shadow_props.is_empty():
			var shadows := Node2D.new()
			shadows.set_script(preload("res://scripts/world/coast_shadows.gd"))
			shadows.prop_list = shadow_props
			shadows.origin_m = origin_m
			shadows.z_index = 5
			add_child(shadows)
		if not above_road_props.is_empty():
			var scenery := Node2D.new()
			scenery.set_script(preload("res://scripts/world/coast_scenery.gd"))
			scenery.prop_list = above_road_props
			scenery.origin_m = origin_m
			scenery.z_index = 6
			add_child(scenery)
		# One batch per occupied signed layer per chunk. Canvas Z, rather
		# than only sorting draw calls, orders sprites across chunk boundaries.
		for order in ordered_props:
			var layer_art:=Node2D.new()
			layer_art.name="AssetDrawOrder_%s"%str(order)
			layer_art.set_script(Scenery)
			layer_art.prop_list=ordered_props[order]
			layer_art.origin_m=origin_m
			layer_art.z_index=6+int(order)
			add_child(layer_art)
	# Furnish curb edges in one static draw node per road-bearing chunk.
	# Lamps, benches and signs follow the real spline and avoid junctions;
	# no per-furnishing sprite or physics nodes are created.
	var details: Node2D=null
	if not road_batches.is_empty():
		details = Node2D.new()
		details.name = "StreetDetails"
		details.set_script(preload("res://scripts/world/coast_roadside_details.gd"))
		details.world=world
		details.origin_m = origin_m
		details.chunk_size_px = world.chunk_m * PPM
		details.road_batches = road_batches
		details.junction_list = junction_list
		details.bridge_spans=[]
		for bridge_index in content.get("bridges",[]):details.bridge_spans.append(world.data.bridges[int(bridge_index)])
		details.z_index = 5
		add_child(details)
	# Night lights are cached per physical chunk, never in map mirrors or
	# editor overviews. They allocate no collision or per-lamp scene nodes.
	if not map_render_only and not bool(world.editor_render_only) and render_extent_m==Vector2.ZERO and (not road_batches.is_empty() or not prop_list.is_empty()):
		environment_lights=preload("res://scripts/world/environment_light_batch.gd").new()
		environment_lights.world=world;environment_lights.details=details
		environment_lights.origin_m=origin_m;environment_lights.extent_px=Vector2.ONE*world.chunk_m*PPM
		environment_lights.props=prop_list
		environment_lights.z_index=7
		add_child(environment_lights)
	# Non-gameplay boundary metadata. Lazy: no boundary outlines are generated
	# or submitted to the renderer unless F4 developer mode is explicitly on.
	if not content.get("mountains",[]).is_empty():
		var clip:=Control.new();clip.name="MountainArtworkClip"
		clip.mouse_filter=Control.MOUSE_FILTER_IGNORE;clip.clip_contents=true
		clip.size=(Vector2.ONE*world.chunk_m if render_extent_m==Vector2.ZERO else render_extent_m)*PPM
		clip.z_index=7;add_child(clip)
		var mountain:=Node2D.new();mountain.set_script(MountainArt)
		mountain.world=world;mountain.origin_m=origin_m;mountain.indices=content.mountains
		mountain.excavation_mask=excavation_mask;mountain.excavation_bounds=excavation_bounds
		clip.add_child(mountain)
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
		_build_excavation_walls()
		_build_excavation_caps()
	build_microseconds = Time.get_ticks_usec() - started
	setup_complete=true

func update_grade_visibility(layer: int, overhead: int) -> void:
	for node in deck_art:
		node.modulate.a = .55 if int(node.get_meta("road_layer")) == overhead else 1.0
	for node in tunnel_art:
		node.visible = int(node.get_meta("road_layer")) == layer
		# Interior is composited above surface pavement but below the car.
		node.z_index = 42 + int(node.render_stage)


func redraw_bridges() -> void:
	for name in ["BridgeDeckClip","BridgeRailsClip"]:
		var clip:=get_node_or_null(name)
		if clip!=null:
			for child in clip.get_children():child.queue_redraw()

func redraw_mountains() -> void:
	var clip:=get_node_or_null("MountainArtworkClip")
	if clip!=null:
		for child in clip.get_children():child.queue_redraw()

## Called once when a cached chunk enters/exits the active play ring,
## never per render frame. Dormant collisions keep their shapes for reuse.
func set_environment_night(amount: float) -> void:
	if is_instance_valid(environment_lights):environment_lights.call("set_night",amount if stream_active else 0.0)

func set_stream_active(active: bool) -> void:
	stream_active = active
	visible = active
	if not active:set_environment_night(0.0)
	if is_instance_valid(collider_body):
		collider_body.collision_layer = 1 if active else 0
	if is_instance_valid(excavation_body):
		excavation_body.collision_layer = excavation_collision_bits if active else 0
	if is_instance_valid(excavation_cap_body):
		excavation_cap_body.collision_layer = 1 if active else 0


func _setup_excavation() -> void:
	var all_cuts: Array = world.data.get("terrain_cuts",[])
	if all_cuts.is_empty():
		return
	var indices: Array = content.get("terrain_cuts",[])
	if render_extent_m != Vector2.ZERO:
		indices = range(all_cuts.size())
	excavation_bounds = Rect2(origin_m,Vector2.ONE*world.chunk_m if render_extent_m==Vector2.ZERO else render_extent_m)
	for index in indices:
		var cut: Dictionary = all_cuts[int(index)]
		var polygon: PackedVector2Array = cut.polygon
		if Elevation.polygon_bounds(polygon).intersects(excavation_bounds.grow(5.0)):
			excavation_polygons.append(polygon)
			excavation_walls.append_array(cut.walls)
			excavation_caps.append(cut.cap)
	if not excavation_polygons.is_empty():
		excavation_mask = Elevation.cutout_mask(excavation_polygons,excavation_bounds)


func _build_excavation_walls() -> void:
	if excavation_walls.is_empty():
		return
	var body := StaticBody2D.new()
	body.name = "ExcavationRetainingWalls"
	# The open cut spans the surface and the first underground layer.
	# Deeper tunnels and elevated decks must not collide with its walls.
	excavation_collision_bits = 1 | Elevation.collision_bits(1,-6.0)
	body.collision_layer = excavation_collision_bits
	body.collision_mask = 0
	add_child(body)
	var made := 0
	for wall in excavation_walls:
		made += Guardrails.collision_shapes(body,wall,.5,origin_m,excavation_bounds)
	if made == 0:
		body.queue_free()
		return
	excavation_body = body
	collision_shape_count += made


func _build_excavation_caps() -> void:
	if excavation_caps.is_empty():
		return
	var body := StaticBody2D.new()
	body.name = "SurfacePortalEdge"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var made := 0
	for cap in excavation_caps:
		made += Guardrails.collision_shapes(body,cap,.35,origin_m,excavation_bounds)
	if made == 0:
		body.queue_free()
		return
	excavation_cap_body = body
	collision_shape_count += made


func _ready() -> void:
	var base: ShaderMaterial = preload("res://scripts/world/mountain_ground.tres")
	var height_tex: Texture2D=world.get("authored_height_texture")
	if height_tex!=null:
		base=base.duplicate() as ShaderMaterial
		preload("res://scripts/world/authored_height_field.gd").bind_material(base,height_tex,Vector2(world.data.size[0],world.data.size[1]))
	material = Elevation.masked_material(base,excavation_mask,excavation_bounds) if excavation_mask != null else base

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
		if bool(prop.solid) or str(prop.kind)=="guardrail":
			solids += 1
	if solids == 0 and content.get("walls", []).is_empty() and content.get("mountains",[]).is_empty():
		return
	var body := StaticBody2D.new()
	collider_body = body
	collision_shape_count = solids + content.get("walls", []).size()
	body.collision_layer = 1
	body.collision_mask = 2
	add_child(body)
	for prop in prop_list:
		if str(prop.kind)=="guardrail":
			var path_m: PackedVector2Array=Guardrails.runtime_path_m(prop)
			var bounds:=Rect2(origin_m,Vector2.ONE*world.chunk_m)
			var rail_scale: Array=prop.get("guardrail_scale",[1.0,1.0])
			var rail_width: float=float(prop.get("guardrail_width",.65))*maxf(
				float(rail_scale[0]),float(rail_scale[1]))
			var made: int=Guardrails.collision_shapes(body,path_m,
				rail_width,origin_m,bounds,
				str(prop.get("authoring_id","")))
			collision_shape_count+=made-1
			continue
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
	var rect:=PackedVector2Array([origin_m,origin_m+Vector2(world.chunk_m,0),origin_m+Vector2.ONE*world.chunk_m,origin_m+Vector2(0,world.chunk_m)])
	for terrain_index in content.get("mountains",[]):
		var region: Dictionary=world.data.terrain[int(terrain_index)]
		for piece in Geometry2D.intersect_polygons(MountainGeometry.polygon(region),rect):
			if piece.size()<3:continue
			for fragment in Elevation.subtract_cutouts(piece,excavation_polygons):
				var collider:=CollisionPolygon2D.new()
				var local:=PackedVector2Array()
				for p in fragment:local.append((p-origin_m)*PPM)
				if Geometry2D.triangulate_polygon(local).is_empty():continue
				collider.polygon=local;collider.set_meta("editor_terrain_key",MountainGeometry.identity(region,int(terrain_index)))
				body.add_child(collider);collision_shape_count+=1

func _rounded(rect: Rect2, color: Color, radius := 12.0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	draw_style_box(style, rect)

func _draw() -> void:
	if not show_terrain:return
	var extent: Vector2=(Vector2.ONE*world.chunk_m if render_extent_m==Vector2.ZERO else render_extent_m)*PPM
	var base := PackedVector2Array([Vector2.ZERO,Vector2(extent.x,0),extent,Vector2(0,extent.y)])
	draw_polygon(base,PackedColorArray([Color("a3b789")]),terrain_uvs(4,"grass"),terrain_texture())
	for terrain in ground_polys:
		if terrain.points.size()>=3:
			draw_polygon(terrain.points,PackedColorArray([terrain.color]),terrain.uvs,terrain_texture())
	# Decorative strokes are cached with the chunk draw list, never spawned as
	# nodes or moved each frame. Roads are painted in the later stages.
	if render_extent_m==Vector2.ZERO:_draw_ground_foliage()


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
