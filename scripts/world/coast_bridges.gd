extends Node2D
## Original vector bridge artwork. Uses the exact same offset paths as rail
## collision; no per-post nodes, textures or per-frame generation.
const Geometry=preload("res://scripts/world/road_bridge_geometry.gd")
const Roads=preload("res://scripts/world/coast_roads.gd")
const Lanes=preload("res://scripts/world/traffic_lane_geometry.gd")
const PPM:=20.0
static var editor_hidden: Dictionary={}
var world: Node2D
var origin_m:=Vector2.ZERO
var bridge_indices: Array=[]
var render_stage:=0
var extent_m:=Vector2(192,192)

static func _stroke(canvas: CanvasItem,path: PackedVector2Array,color: Color,width: float) -> void:
	if path.size()>1:canvas.draw_polyline(path,color,width,true)

static func _local(path: PackedVector2Array,origin: Vector2) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for p in path:result.append((p-origin)*PPM)
	return result

static func draw_span(canvas: CanvasItem,bridge: Dictionary,origin: Vector2,stage: int,junctions: Array=[],ownership:=Rect2()) -> void:
	var center:=PackedVector2Array()
	for raw in bridge.points:center.append(Geometry.v(raw))
	if center.size()<2:return
	var offset:=Geometry.rail_offset(bridge)
	var deck_width: float=(offset*2+1)*PPM
	var path:=_local(center,origin)
	if stage==0:
		var shadow:=path.duplicate()
		for i in shadow.size():shadow[i]+=Vector2(2.2,3.5)*PPM
		_stroke(canvas,shadow,Color(.06,.15,.19,.28),deck_width+22)
		_stroke(canvas,path,Color("#52676a"),deck_width+12)
		_stroke(canvas,path,Color("#bbc0b2"),deck_width)
		for side in [-1,1]:
			_stroke(canvas,_local(Lanes.offset_path(center,side*(offset-.5)),origin),Color("#dbd9c7"),15)
		# Shore abutments are outside the driving lanes; entrances stay open.
		for i in [0,center.size()-1]:
			var tangent: Vector2=(center[1]-center[0]).normalized() if i==0 else (center[-1]-center[-2]).normalized()
			var normal:=tangent.orthogonal()
			for side in [-1,1]:
				var p: Vector2=path[i]+normal*side*offset*PPM
				canvas.draw_line(p-tangent*28,p+tangent*28,Color("#70817d"),31,true)
		return
	# Rails stop at intersecting road mouths, using identical physics paths.
	for rail in Geometry.rail_paths(bridge,junctions):
		var local:=_local(rail,origin)
		_stroke(canvas,local,Color("#3c5055"),19)
		_stroke(canvas,local,Color("#cdd0c1"),12)
		_stroke(canvas,local,Color("#f0e9d2"),3)
		var traveled:=0.0
		for i in range(1,rail.size()):
			var a:=rail[i-1];var b:=rail[i];var length:=a.distance_to(b)
			if length<.001:continue
			var tangent: Vector2=(b-a)/length;var normal:=tangent.orthogonal()
			var at:=ceilf((traveled+.001)/4.0)*4
			while at<traveled+length:
				var point: Vector2=a+tangent*(at-traveled)
				if not ownership.has_area() or ownership.has_point(point):
					var p: Vector2=(point-origin)*PPM
					canvas.draw_line(p+Vector2(8,12),p+Vector2(18,22),Color(.04,.10,.13,.27),11,true)
					canvas.draw_line(p-normal*8,p+normal*8,Color("#74847f"),12,true)
					canvas.draw_line(p-normal*6-Vector2(2,2),p+normal*6-Vector2(2,2),Color("#ece7d4"),6,true)
				at+=4
			traveled+=length
	# Subtle transverse expansion joints sell the raised deck without a ramp.
	for i in [0,path.size()-1]:
		var tangent: Vector2=(path[1]-path[0]).normalized() if i==0 else (path[-1]-path[-2]).normalized()
		var across:=tangent.orthogonal()*float(bridge.width)*PPM*.49
		canvas.draw_line(path[i]-across,path[i]+across,Color(.10,.16,.18,.24),3,true)

func _draw() -> void:
	var ownership:=Rect2(origin_m,extent_m)
	for id in bridge_indices:
		var bridge: Dictionary=world.data.bridges[int(id)]
		if Roads.editor_hidden.has(int(bridge.road)) or editor_hidden.has(int(bridge.road)):continue
		draw_span(self,bridge,origin_m,render_stage,world.data.junctions,ownership)
