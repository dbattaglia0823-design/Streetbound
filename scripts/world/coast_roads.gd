extends Node2D
const PPM := 20.0
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
		var station := float(batch.phase)
		if stage == 0:
			if urban:
				draw_polyline(path,Color("adb3a5"),width+100,true)
				draw_polyline(path,Color("d9d4c2"),width+88,true)
				draw_polyline(path,Color("bec4b6"),width+11,true)
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
			if urban: _paver_joints(path,width,station)
			if gravel or r.kind == "driveway":
				continue
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
	# Broad pavement covers converging markings; each approach gets a stop bar
	# and crossing only at urban junctions, never on track/highway approaches.
	for j in junction_list:
		var center := point(j.p)
		var radius := float(j.radius)*PPM
		var polygon := PackedVector2Array()
		for p in j.polygon:
			polygon.append(point(p))
		var outline := polygon.duplicate()
		outline.append(polygon[0])
		draw_polyline(outline,Color("c5c2ae"),14,true)
		draw_colored_polygon(polygon,Color("58656c"))
		for road_index in j.roads:
			var r: Dictionary = world.data.roads[int(road_index)]
			if not r.kind in ["local","arterial"]:
				continue
			var nearest := Vector2.ZERO
			var best := INF
			for raw in [r.points[0],r.points[-1]]:
				var p := point(raw)
				if p.distance_squared_to(center)<best:
					best=p.distance_squared_to(center)
					nearest=p
			# Endpoint approaches have an unambiguous tangent.
			if best>100:
				continue
			var first: bool = point(r.points[0]).distance_squared_to(center)<100
			var direction := (point(r.points[mini(3,r.points.size()-1)])-center).normalized() if first else (point(r.points[maxi(0,r.points.size()-4)])-center).normalized()
			var normal := Vector2(-direction.y,direction.x)
			var bar := center+direction*(radius+24)
			draw_line(bar,bar-normal*float(r.width)*PPM*.4,Color("e9e0cb"),7,true)
			var stripes := maxi(3,int(float(r.width)*PPM/20)-1)
			for stripe in stripes:
				var cross := center+direction*(radius+48)+normal*(stripe-float(stripes-1)*.5)*20
				draw_line(cross,cross+direction*24,Color("dfdac6"),9,true)
			if j.roads.size()>=4:
				var arrow := center+direction*(radius+155)-normal*float(r.width)*PPM*.25
				var head := arrow-direction*20
				draw_line(arrow+direction*22,head,Color("d9d8c3"),3.5,true)
				draw_polyline(PackedVector2Array([head+direction*13+normal*11,head,head+direction*13-normal*11]),Color("d9d8c3"),3.5,true)
	draw_set_transform(Vector2.ZERO)

