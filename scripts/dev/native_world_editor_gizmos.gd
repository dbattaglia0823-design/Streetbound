extends Node2D
## Dev-only drawing of the ACTUAL baked junction polygons and the existing
## Godot traffic graph. No shadow copy of browser road or lane math.
const PPM := 20.0
var world
var network
var selected: Dictionary = {}
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
			var highlighted := selected.get("kind","") == "road" and \
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
			var chosen := selected.get("kind","")=="junction" and \
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
