extends Node2D
## Dev-only drawing of the ACTUAL baked junction polygons and the existing
## Godot traffic graph. No shadow copy of browser road or lane math.
const PPM := 20.0
var world
var network
var selected: Dictionary = {}
var draft_doc: Dictionary = {}
var draft_initial: Dictionary = {}
var drag_preview: Dictionary = {}
var selected_source_id := ""
var selected_anchor_index := -1

func set_draft(source: Dictionary, baseline: Dictionary, preview: Dictionary = {},
		source_id: String = "", point_index: int = -1) -> void:
	draft_doc = source
	draft_initial = baseline
	drag_preview = preview
	selected_source_id = source_id
	selected_anchor_index = point_index
	queue_redraw()

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
		var id := str(prop.id)
		var p := Vector2(float(prop.x),float(prop.y)) * PPM
		if str(drag_preview.get("id",""))==id:
			p = drag_preview.get("to",p)
		if not _visible_point(p):
			continue
		var size := Vector2(8.0,8.0) * PPM * float(prop.get("scale",1.0))
		var kind := str(prop.get("type",""))
		match kind:
			"house": size=Vector2(12,17)*PPM*float(prop.scale)
			"building": size=Vector2(22,29)*PPM*float(prop.scale)
			"garage": size=Vector2(20,21)*PPM*float(prop.scale)
			"oak","pine","palm": size=Vector2(7,7)*PPM*float(prop.scale)
			"rock": size=Vector2(3,2.5)*PPM*float(prop.scale)
		var c := Color(0.38,1.0,0.65,0.90) if id==selected_source_id else \
			Color(0.95,0.86,0.27,0.80)
		var rect := Rect2(p-size*0.5,size)
		draw_rect(rect,c,false,5.0,true)
		draw_circle(p,5.0,c)
	# These are SOURCE PREVIEWS, not new baked junctions or real collisions.
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
	viewport_extents = screen_size * 0.5 / maxf(0.1,zoom_level)
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
