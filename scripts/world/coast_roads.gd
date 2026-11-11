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

func _dashes(path: PackedVector2Array, width: float, color: Color, dash := 55.0, gap := 85.0, station := 0.0, weathered := false) -> void:
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
				var ink := color
				if weathered:
					var dash_index := floori((cursor + pos) / (dash + gap))
					ink.a *= .62 if posmod(dash_index, 11) in [2, 7] else .88
				draw_line(a.lerp(b,pos/length),a.lerp(b,(pos+step)/length),ink,width,true)
			pos += maxf(step,0.01)
		cursor += length

## Compact world-stationed road wear. Every position is derived from the
## baked road phase, so neighboring streamed chunks produce the same rhythm.
## One cached drawing pass per road chunk; no decals, textures or physics nodes.
static func wear_stations(start: float, length: float, spacing: float = 480.0) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	if length <= 0.0 or spacing <= 0.0:
		return result
	var at := ceilf((start - .01) / spacing) * spacing
	while at < start + length - .01:
		result.append(at)
		at += spacing
	return result

func _road_wear(path: PackedVector2Array, road: Dictionary, width: float, station: float) -> void:
	# Race circuits stay pristine; gravel is already given its own aggregate.
	if str(road.surface) == "GRAVEL" or str(road.kind) == "track" or width < 140.0:
		return
	var passed := station
	for i in range(1, path.size()):
		var start := path[i - 1]
		var span := path[i] - start
		var length := span.length()
		if length <= .01:
			continue
		var tangent := span / length
		var normal := tangent.orthogonal()
		for sample in wear_stations(passed, length):
			var center := start + tangent * (sample - passed)
			# Assign the mark to one chunk even if its strokes cross that
			# chunk's edge; the neighboring chunk must not draw it twice.
			var edge: float = float(world.chunk_m) * PPM
			if center.x < 0.0 or center.y < 0.0 or center.x >= edge or center.y >= edge:
				continue
			var index := int(round(sample / 480.0))
			var side := -1.0 if index % 2 == 0 else 1.0
			var lane_center := center + normal * side * width * .22
			if index % 4 == 0:
				# Slightly irregular resurfaced rectangle, kept in a travel lane.
				var half_long := 35.0 + float(posmod(index, 4)) * 7.0
				var half_wide := minf(34.0, width * .12)
				var corners := PackedVector2Array([
					lane_center - tangent * half_long - normal * half_wide,
					lane_center + tangent * half_long - normal * (half_wide - 4.0),
					lane_center + tangent * (half_long - 5.0) + normal * half_wide,
					lane_center - tangent * (half_long + 3.0) + normal * half_wide
				])
				draw_colored_polygon(corners, Color(.16, .22, .25, .21))
				draw_line(corners[0], corners[1], Color(.60, .61, .56, .18), 1.7, true)
			elif index % 3 == 0:
				# Short sealed cracks follow the wheel-worn portion of the lane.
				var p := lane_center - tangent * 27.0
				var q := lane_center + tangent * 9.0 + normal * 6.0
				var finish := lane_center + tangent * 33.0 - normal * 4.0
				draw_line(p, q, Color(.13, .18, .21, .32), 1.9, true)
				draw_line(q, finish, Color(.13, .18, .21, .25), 1.4, true)
			if index % 5 == 0 and str(road.kind) not in ["local", "arterial"]:
				# Faint edge unraveling on rural/highland roads, inside the
				# actual pavement so the shoulder collision remains untouched.
				var shoulder := center + normal * side * (width * .5 - 10.0)
				draw_line(shoulder - tangent * 28.0, shoulder + tangent * 23.0,
					Color(.30, .28, .24, .24), 6.0, true)
		passed += length

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
			elif r.kind == "track":
				# Genuine circuits require a runoff/verge between the race line
				# and barriers; the drag strip instead has a graded safety shoulder.
				var strip := str(r.name).contains("Drag Strip")
				draw_polyline(path,Color("777e79") if strip else Color("788879"),
					width+(90.0 if strip else 225.0),true)
				draw_polyline(path,Color("b5b59b") if strip else Color("a7b4a7"),
					width+(44.0 if strip else 135.0),true)
			else:
				draw_polyline(path,Color("c0bea5"),width+35,true)
		elif stage == 1:
			draw_polyline(path,Color("a1947d") if gravel else Color("58656c"),width,true)
			if not gravel:
				_road_wear(path, r, width, float(batch.phase))
				if str(r.kind) == "track":
					# Rubbered-in racing line and drag burnout grooves follow the
					# actual spline, not disconnected pavement decals.
					for side in [-0.245,0.245]:
						draw_polyline(_offset(path,width*side),
							Color(.13,.17,.18,.19),16.0,true)
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

## Manhole covers, faded utility repairs and compact rain drains. Derived
## from the global road station so marks continue across streamed chunk seams.
## Excludes junction mouths because _paint receives clipped marking spans.
func _street_surface_details(path: PackedVector2Array, road: Dictionary, width: float, station: float) -> void:
	if road.kind not in ["local", "arterial"] or path.size() < 2:
		return
	var spacing := 1260.0
	var passed := station
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var segment := b - a
		var length := segment.length()
		if length <= .01:
			continue
		var tangent := segment / length
		var normal := tangent.orthogonal()
		var sample := ceilf((passed + .05) / spacing) * spacing
		while sample < passed + length - .05:
			var center := a + tangent * (sample - passed)
			# Side gutters and utility fittings must stay within this chunk.
			if center.x >= 12.0 and center.y >= 12.0 and \
				center.x < world.chunk_m * PPM - 12.0 and \
				center.y < world.chunk_m * PPM - 12.0:
				var n := int(sample / spacing)
				var cover := center + normal * (width * (.26 if n % 2 == 0 else -.26))
				draw_circle(cover, 15.0, Color(.15,.21,.23,.30))
				draw_arc(cover, 11.0, 0.0, TAU, 12, Color(.53,.56,.53,.34), 2.1, true)
				for side in [-1.0, 1.0]:
					var drain: Vector2 = center + normal * float(side) * (width * .5 - 18.0)
					draw_line(drain - tangent * 13.0, drain + tangent * 13.0,
						Color(.13,.18,.20,.44), 7.0, true)
			sample += spacing
		passed += length


func _paint(path: PackedVector2Array,r: Dictionary,width: float,station: float) -> void:
	var urban: bool = r.kind in ["local","arterial"]
	var gravel: bool = r.surface=="GRAVEL"
	if urban:
		_paver_joints(path,width,station)
		_street_surface_details(path,r,width,station)
	if gravel or r.kind == "driveway":
		return
	var edge := Color("dcd9c4")
	if r.kind == "track":
		if str(r.name).contains("Drag Strip"):
			# Two equal dedicated lanes, a narrow median, staging approach,
			# white boundary beams and clear 402 m measured racing surface.
			draw_polyline(path,Color("e5e5d8"),5.5,true)
			for side in [-1.0,1.0]:
				draw_polyline(_offset(path,side*(width*.5-8.0)),
					Color("f1eee0"),6.0,true)
		else:
			# Circuit kerbing alternates white/red over curved entries and
			# exits, with a stable world-stationed pattern between chunks.
			for side in [-1.0,1.0]:
				var curb := _offset(path,side*(width*.5-6.0))
				_dashes(curb,12.0,Color("eee9d8"),58.0,58.0,station,true)
				_dashes(curb,12.0,Color("bc655b"),58.0,58.0,station+58.0,true)
	elif r.kind == "highway":
		draw_polyline(_offset(path,-8),Color("d7c696"),3,true)
		draw_polyline(_offset(path,8),Color("d7c696"),3,true)
		_dashes(_offset(path,width/4),3.5,edge,60,100,station,true)
		_dashes(_offset(path,-width/4),3.5,edge,60,100,station,true)
	elif r.kind in ["arterial","mountain"]:
		draw_polyline(_offset(path,-5),Color("d8c69a"),3,true)
		draw_polyline(_offset(path,5),Color("d8c69a"),3,true)
	else:
		_dashes(path,3,Color("ddd2a7"),55,85,station,true)
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
