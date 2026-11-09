extends Node2D
const PPM := 20.0
const Walkways = preload("res://scripts/world/urban_walkways.gd")
var render_stage := 0
var world: Node2D
var origin_m := Vector2.ZERO
var road_batches: Array[Dictionary] = []
var junction_list: Array[Dictionary] = []
func point(raw: Array) -> Vector2:
	return (Vector2(float(raw[0]),float(raw[1]))-origin_m)*PPM
func _ready() -> void:
	material=preload("res://scripts/world/road_surface.tres")

func _offset(path: PackedVector2Array, amount: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in path.size():
		var tangent := (path[mini(i+1,path.size()-1)] - path[maxi(i-1,0)]).normalized()
		result.append(path[i] + Vector2(-tangent.y, tangent.x) * amount)
	return result

func _dashes(path: PackedVector2Array, width: float, color: Color, dash := 55.0, gap := 85.0, station := 0.0) -> void:
	var cursor := station
	for i in range(1,path.size()):
		var a := path[i-1]
		var b := path[i]
		var length := a.distance_to(b)
		var pos := 0.0
		while pos < length:
			var phase := fposmod(cursor+pos, dash+gap)
			var step := minf(length-pos, dash-phase if phase<dash else dash+gap-phase)
			if phase<dash:
				draw_line(a.lerp(b,pos/length),a.lerp(b,(pos+step)/length),color,width,true)
			pos += maxf(step,0.01)
		cursor += length

func _paver_joints(path: PackedVector2Array, width: float, station: float) -> void:
	var cursor := station
	for i in range(1,path.size()):
		var a := path[i-1]
		var b := path[i]
		var length := a.distance_to(b)
		if length<.001: continue
		var direction := (b-a)/length
		var normal := Vector2(-direction.y,direction.x)
		var at := 100.0-fposmod(cursor,100.0)
		while at<length:
			var p := a+direction*at
			for side in [-1.0,1.0]:
				draw_line(p+normal*side*(width*.5+9),p+normal*side*(width*.5+35),Color(.48,.49,.44,.24),1.3,true)
			at+=100
		cursor+=length

func _roads(stage: int) -> void:
	for batch in road_batches:
		var path: PackedVector2Array = batch.path
		var r: Dictionary = batch.road
		var width := float(r.width) * PPM
		var urban: bool = r.kind in ["local", "arterial"]
		var gravel: bool = r.surface == "GRAVEL"
		if stage == 0:
			if urban:
				# Both sides are real road-relative paths, not disconnected
				# rectangles. Their mitered offsets follow every road bend.
				for side in [-1.0, 1.0]:
					var walkway := Walkways.urban_sidewalk_center(path, width, side)
					draw_polyline(walkway, Color("99a49b"), Walkways.SIDEWALK_WIDTH_PX + 16.0, true)
					draw_polyline(walkway, Color("dedbcc"), Walkways.SIDEWALK_WIDTH_PX + 2.0, true)
					var outside := Walkways.urban_sidewalk_outer(path, width, side)
					draw_polyline(outside, Color("b5b8a9"), 3.0, true)
			else:
				draw_polyline(path,Color("c0bea5"),width+35,true)
		elif stage == 1:
			draw_polyline(path,Color("a1947d") if gravel else Color("58656c"),width,true)
			if not gravel:
				var lanes: Array = [-width*.375,-width*.125,width*.125,width*.375] if r.kind=="highway" else [-width*.25,width*.25]
				for lane in lanes:
					for wheel in [-13.0,13.0]:
						draw_polyline(_offset(path,float(lane)+wheel),Color(.18,.23,.25,.065),10,true)
		elif stage == 2:
			if urban:
				for side in [-1.0, 1.0]:
					# Bright continuous road-edge kerb on both sides.
					draw_polyline(Walkways.offset(path, side * (width * 0.5 + 1.5)),
						Color("f0ebdc"), 5.0, true)
			for piece in batch.markings:
				_paint(piece.path,r,width,float(piece.phase))

func _paint(path: PackedVector2Array,r: Dictionary,width: float,station: float) -> void:
	var urban: bool = r.kind in ["local","arterial"]
	var gravel: bool = r.surface=="GRAVEL"
	if urban: _paver_joints(path,width,station)
	if gravel or r.kind == "driveway":
		return
	var edge := Color("dcd9c4")
	if r.kind == "track":
		_dashes(_offset(path,width/2-5),8,Color("e1d8bf"),65,65,station)
		_dashes(_offset(path,-width/2+5),8,Color("c98675"),65,65,station)
	elif r.kind == "highway":
		draw_polyline(_offset(path,-8),Color("d7c696"),3,true)
		draw_polyline(_offset(path,8),Color("d7c696"),3,true)
		_dashes(_offset(path,width/4),3.5,edge,60,100,station)
		_dashes(_offset(path,-width/4),3.5,edge,60,100,station)
	elif r.kind in ["arterial","mountain"]:
		draw_polyline(_offset(path,-5),Color("d8c69a"),3,true)
		draw_polyline(_offset(path,5),Color("d8c69a"),3,true)
	else:
		_dashes(path,3,Color("ddd2a7"),55,85,station)
	draw_polyline(_offset(path,width/2-10),edge,3,true)
	draw_polyline(_offset(path,-width/2+10),edge,3,true)
func _draw() -> void:
	if render_stage < 3:
		_roads(render_stage)
		return
	# Bridge rails sit outside the usable deck, matching the bank collision gates.
	for bridge in world.data.bridges:
		var path := PackedVector2Array()
		for p in bridge.points:
			path.append(point(p))
		if path.is_empty() or not Rect2(Vector2(-500,-500),Vector2.ONE*(world.chunk_m*PPM+1000)).has_point(path[0]):
			continue
		for side in [-1.0,1.0]:
			draw_polyline(_offset(path,side*(float(bridge.width)*.5+1.0)*PPM),Color("d1c7b0"),12,true)
			draw_polyline(_offset(path,side*(float(bridge.width)*.5+1.3)*PPM),Color("9ca99d"),4,true)
		for i in range(2,path.size()-1,3):
			var direction := (path[i+1]-path[i-1]).normalized()
			var normal := Vector2(-direction.y,direction.x)*float(bridge.width)*PPM*.45
			draw_line(path[i]-normal,path[i]+normal,Color(.67,.72,.70,.26),2,true)
	for j in junction_list:
		var polygon := PackedVector2Array()
		for p in j.polygon: polygon.append(point(p))
		# The baker provides only OUTSIDE corner fillets, never a line across
		# a street approach. Extend each eligible corner into a sidewalk
		# apron, then mask the inside with the actual junction asphalt.
		for i in j.curbs.size():
			if j.approaches.is_empty():
				continue
			var first: Dictionary = j.approaches[i % j.approaches.size()]
			var second: Dictionary = j.approaches[(i + 1) % j.approaches.size()]
			var a_urban: bool = world.data.roads[int(first.road)].kind in ["local", "arterial"]
			var b_urban: bool = world.data.roads[int(second.road)].kind in ["local", "arterial"]
			if not (a_urban or b_urban):
				continue
			var corner := PackedVector2Array()
			for p in j.curbs[i]: corner.append(point(p))
			if corner.size() < 2:
				continue
			draw_polyline(corner, Color("9ba89f"),
				Walkways.SIDEWALK_WIDTH_PX * 2.0 + 21.0, true)
			draw_polyline(corner, Color("dedbcc"),
				Walkways.SIDEWALK_WIDTH_PX * 2.0 + 3.0, true)
		draw_colored_polygon(polygon,Color("58656c"))
		# Rounded curb fillets leave vehicle mouths and marked crosswalks open.
		for curve in j.curbs:
			var path := PackedVector2Array()
			for p in curve: path.append(point(p))
			draw_polyline(path,Color("eee7d5"),6,true)
		for arm in j.approaches:
			var r: Dictionary = world.data.roads[int(arm.road)]
			var p := point(arm.p)
			var direction := Vector2(float(arm.direction[0]),float(arm.direction[1]))
			var normal := Vector2(-direction.y,direction.x)
			var width := float(arm.width)*PPM
			if arm.control=="stop":
				var bar := p+direction*20
				draw_line(bar-normal*6,bar-normal*(width*.5-8),Color("e9e0cb"),8,true)
				_sign(p+direction*30-normal*(width*.5+32),direction,false)
			elif arm.control=="yield":
				_dashes(PackedVector2Array([p-normal*6,p-normal*(width*.5-8)]),7,Color("e9e0cb"),9,8)
				_sign(p+direction*30-normal*(width*.5+32),direction,true)
			if r.kind in ["local","arterial"] and j.control!="roundabout" and j.approaches.size()>=3:
				# Crossings are beyond the clear turning area and before the stop bar.
				var stripes := maxi(3,int(width/23)-1)
				for stripe in stripes:
					var cross := p-direction*26+normal*(stripe-float(stripes-1)*.5)*23
					draw_line(cross,cross+direction*21,Color("dfdac6"),9,true)
	draw_set_transform(Vector2.ZERO)

func _sign(p: Vector2,outward: Vector2,yield_sign: bool) -> void:
	draw_line(p+Vector2(5,7),p+Vector2(16,21),Color(.08,.14,.15,.3),8,true)
	draw_circle(p+Vector2(0,5),3,Color("b3bbb1"))
	draw_set_transform(p,outward.angle()+PI/2)
	var shape := PackedVector2Array()
	if yield_sign:
		shape=PackedVector2Array([Vector2(-14,-10),Vector2(14,-10),Vector2(0,14)])
	else:
		for i in 8: shape.append(Vector2.from_angle(PI/8+i*TAU/8)*14)
	draw_colored_polygon(shape,Color("f2e8d4"))
	var inset := PackedVector2Array()
	for v in shape: inset.append(v*.86)
	draw_colored_polygon(inset,Color("ae493c"))
	if yield_sign:
		var middle := PackedVector2Array()
		for v in shape: middle.append(v*.56)
		draw_colored_polygon(middle,Color("eee5cf"))
	else:
		draw_string(ThemeDB.fallback_font,Vector2(-11,3),"STOP",HORIZONTAL_ALIGNMENT_LEFT,-1,8,Color("fff4dd"))
	draw_set_transform(Vector2.ZERO)
