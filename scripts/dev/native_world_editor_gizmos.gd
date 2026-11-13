extends Node2D
## Dev-only drawing of the ACTUAL baked junction polygons and the existing
## Godot traffic graph. No shadow copy of browser road or lane math.
const PPM := 20.0
const Art = preload("res://scripts/world/coast_art.gd")
var preview_body: StaticBody2D
var preview_collisions_enabled := false

var world
var network
var selected: Dictionary = {}
var draft_doc: Dictionary = {}
var draft_initial: Dictionary = {}
var drag_preview: Dictionary = {}
var selected_source_id := ""
var selected_anchor_index := -1
var pending_shape: Array[Vector2] = []
var pending_tool := ""

func set_draft(source: Dictionary, baseline: Dictionary, preview: Dictionary = {},
		source_id: String = "", point_index: int = -1) -> void:
	draft_doc = source
	draft_initial = baseline
	drag_preview = preview
	selected_source_id = source_id
	selected_anchor_index = point_index
	if preview.is_empty():
		_rebuild_preview_collisions()
	queue_redraw()

func set_pending_shape(points: Array[Vector2], tool: String) -> void:
	pending_shape = points.duplicate()
	pending_tool = tool
	queue_redraw()


func set_preview_collision_enabled(enabled: bool) -> void:
	preview_collisions_enabled = enabled
	if is_instance_valid(preview_body):
		preview_body.collision_layer = 1 if enabled else 0


func _prop_modified(prop: Dictionary) -> bool:
	for previous in draft_initial.get("props",[]):
		if str(previous.get("id","")) == str(prop.get("id","")):
			return JSON.stringify(previous) != JSON.stringify(prop)
	return true


func _prop_size(prop: Dictionary) -> Vector2:
	var base := Vector2(8,8)
	match str(prop.get("type","")):
		"house":base=Vector2(12,17)
		"building":base=Vector2(22,29)
		"warehouse":base=Vector2(28,37)
		"garage":base=Vector2(20,21)
		"gas_station":base=Vector2(18,17)
		"oak","pine":base=Vector2(7,7)
		"palm":base=Vector2(6.5,6.5)
		"rock":base=Vector2(3,2.5)
	if prop.has("assetSize") and prop.assetSize is Array and prop.assetSize.size()==2:
		base=Vector2(float(prop.assetSize[0]),float(prop.assetSize[1]))
	return base * PPM * float(prop.get("scale",1.0))


func _prop_texture(prop: Dictionary) -> Texture2D:
	if prop.has("assetPath"):
		return Art.project_sprite(str(prop.assetPath))
	var kind := str(prop.get("assetId","")).trim_prefix("game-")
	if kind in ["","none"]:
		kind=str(prop.get("type",""))
	if kind=="oak":
		kind="tree"
	return Art.sprite(kind,0)


func _rebuild_preview_collisions() -> void:
	if not is_instance_valid(preview_body):
		preview_body = StaticBody2D.new()
		preview_body.name = "UnsavedAssetCollisionPreview"
		preview_body.process_mode = Node.PROCESS_MODE_ALWAYS
		preview_body.collision_mask = 2
		add_child(preview_body)
	preview_body.collision_layer = 1 if preview_collisions_enabled else 0
	for child in preview_body.get_children():
		preview_body.remove_child(child)
		child.queue_free()
	for prop in draft_doc.get("props",[]):
		if bool(prop.get("hidden",false)) or not _prop_modified(prop):
			continue
		var collider := CollisionShape2D.new()
		var size := _prop_size(prop)
		if str(prop.get("type","")) in ["oak","pine","palm"]:
			var circle := CircleShape2D.new()
			circle.radius = minf(size.x,size.y)*0.32
			collider.shape = circle
		elif str(prop.get("type",""))=="rock":
			var rock := CircleShape2D.new()
			rock.radius = minf(size.x,size.y)*0.45
			collider.shape = rock
		else:
			var rect := RectangleShape2D.new()
			rect.size = size
			collider.shape = rect
		collider.position = Vector2(float(prop.x),float(prop.y))*PPM
		collider.rotation = deg_to_rad(float(prop.get("rotation",0.0)))
		preview_body.add_child(collider)


func _draft_line(road: Dictionary) -> PackedVector2Array:
	var line := PackedVector2Array()
	for i in road.points.size():
		var point: Dictionary = road.points[i]
		var p := Vector2(float(point.x),float(point.y)) * PPM
		if str(road.id)==str(drag_preview.get("id","")) and \
				int(drag_preview.get("index",-1))==i:
			p = drag_preview.get("to",p)
		line.append(p)
	return line

func _draw_draft() -> void:
	if draft_doc.is_empty():
		return
	for road in draft_doc.get("roads",[]):
		var id := str(road.id)
		var original: Dictionary = {}
		for before in draft_initial.get("roads",[]):
			if str(before.id)==id:
				original = before
				break
		var changed: bool = original.is_empty() or \
			JSON.stringify(road.points)!=JSON.stringify(original.get("points",[]))
		var focused: bool = selected_source_id == id
		if not changed and not focused:
			continue
		var line := _draft_line(road)
		if line.size()<2 or not _visible_point(line[0]) and not \
				_visible_point(line[line.size()-1]):
			continue
		draw_polyline(line,Color(1.0,0.86,0.27,0.96) if focused else \
			Color(1.0,0.76,0.32,0.85),5.0,true)
		if focused:
			for i in line.size():
				draw_circle(line[i],12.0 if i==selected_anchor_index else 7.0,
					Color(1.0,0.93,0.45,1.0) if i==selected_anchor_index else
					Color(1.0,0.67,0.24,1.0))
	for prop in draft_doc.get("props",[]):
		if bool(prop.get("hidden",false)) or not _prop_modified(prop):
			continue
		var id := str(prop.id)
		var p := Vector2(float(prop.x),float(prop.y)) * PPM
		if str(drag_preview.get("id",""))==id:
			p = drag_preview.get("to",p)
		if not _visible_point(p):
			continue
		var size := _prop_size(prop)
		var angle := deg_to_rad(float(prop.get("rotation",0.0)))
		var texture := _prop_texture(prop)
		draw_set_transform(p,angle)
		if texture != null:
			draw_texture_rect(texture,Rect2(-size*0.5,size),false)
		else:
			draw_rect(Rect2(-size*0.5,size),Color(0.35,0.65,0.52,0.6),true)
		var c := Color("#8effbf") if id==selected_source_id else Color("#ffcf73")
		draw_rect(Rect2(-size*0.5,size),c,false,3.0,true)
		draw_set_transform(Vector2.ZERO)
		draw_circle(p,4.0,c)
	# Native draft sprites and collision footprints update before Save to Game.
var show_junctions := true
var show_lanes := true
var camera_center := Vector2.ZERO
var viewport_extents := Vector2(1100,700)

func _ready() -> void:
	name = "NativeWorldEditorGizmos"
	z_index = 20
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

func set_view(center: Vector2, screen_size: Vector2, zoom_level: float) -> void:
	camera_center = center
	viewport_extents = screen_size * 0.5 / maxf(0.003,zoom_level)
	queue_redraw()

func set_selection(info: Dictionary) -> void:
	selected = info.duplicate()
	queue_redraw()

func _visible_point(p: Vector2) -> bool:
	return absf(p.x-camera_center.x) < viewport_extents.x + PPM*75.0 and \
		absf(p.y-camera_center.y) < viewport_extents.y + PPM*75.0

func _draw() -> void:
	if not is_instance_valid(world) or world.data.is_empty():
		return
	if show_lanes and is_instance_valid(network):
		for edge in network.edges:
			var points: PackedVector2Array = edge.points
			if points.size()<2:
				continue
			var middle := points[points.size()/2]
			if not _visible_point(middle) and not _visible_point(points[0]) and \
					not _visible_point(points[points.size()-1]):
				continue
			var connector := bool(edge.connector)
			var highlighted: bool = selected.get("kind","") == "road" and \
				int(selected.get("index",-1)) == int(edge.road)
			var color := Color(1.0,0.60,0.19,0.91) if connector else \
				(Color(0.27,1.0,0.95,0.95) if highlighted else
				Color(0.35,0.83,0.94,0.70))
			draw_polyline(points,color,5.0 if highlighted else 2.8,true)
			var middle_idx := points.size()/2
			var tangent := (points[mini(middle_idx+1,points.size()-1)]-
				points[maxi(0,middle_idx-1)]).normalized()
			if tangent.length_squared()>0.25:
				var side := tangent.orthogonal()
				draw_line(middle-tangent*13.0+side*9.0,middle,color,3.0,true)
				draw_line(middle-tangent*13.0-side*9.0,middle,color,3.0,true)
	if show_junctions:
		for index in world.data.junctions.size():
			var j: Dictionary = world.data.junctions[index]
			var center := Vector2(float(j.p[0]),float(j.p[1]))*PPM
			if not _visible_point(center):
				continue
			var chosen: bool = selected.get("kind","")=="junction" and \
				int(selected.get("index",-1))==index
			var color := Color(1.0,0.92,0.25,1.0) if chosen else \
				Color(1.0,0.43,0.64,0.76)
			var outline := PackedVector2Array()
			for vertex in j.polygon:
				outline.append(Vector2(float(vertex[0]),float(vertex[1]))*PPM)
			if outline.size()>=3:
				draw_polyline(outline,color,7.0 if chosen else 2.5,true)
				draw_line(outline[outline.size()-1],outline[0],color,
					7.0 if chosen else 2.5,true)
			draw_circle(center,9.0 if chosen else 4.5,color)
	if selected.get("kind","")=="road":
		var index := int(selected.get("index",-1))
		if index>=0 and index<world.data.roads.size():
			var path := PackedVector2Array()
			for raw in world.data.roads[index].points:
				path.append(Vector2(float(raw[0]),float(raw[1]))*PPM)
			if path.size()>=2:
				draw_polyline(path,Color(1.0,0.92,0.28,0.91),6.0,true)
	_draw_draft()
	if not pending_shape.is_empty():
		var path := PackedVector2Array()
		for item in pending_shape:
			path.append(item*PPM)
			draw_circle(item*PPM,7,Color("#ffb653"))
		if path.size() >= 2:
			draw_polyline(path,Color("#ffb653"),4,true)
		if pending_tool == "draw_terrain" and path.size() >= 3:
			draw_line(path[path.size()-1],path[0],Color("#ffb653"),2,true)
	if selected.get("kind","")=="prop":
		var index := int(selected.get("index",-1))
		if index>=0 and index<world.data.props.size():
			var prop: Dictionary = world.data.props[index]
			var center := Vector2(float(prop.p[0]),float(prop.p[1]))*PPM
			var half := Vector2(float(prop.size[0]),float(prop.size[1]))*PPM*0.5
			var angle := float(prop.get("angle",0.0))
			var points := PackedVector2Array()
			for v in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),
					Vector2(half.x,half.y),Vector2(-half.x,half.y)]:
				points.append(center+v.rotated(angle))
			draw_polyline(points,Color(1.0,0.9,0.25,1.0),5.0,true)
			draw_line(points[3],points[0],Color(1.0,0.9,0.25,1.0),5.0,true)
