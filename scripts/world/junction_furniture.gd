extends RefCounted
## Static junction artwork. All lenses are neutral/unlit; no signal phases,
## timers, collision or traffic permissions are introduced by these fixtures.
## Build paint around a local origin: triangulating tiny triangles at large
## absolute canvas coordinates loses precision in Godot's polygon renderer.
static func yield_triangle(outward: Vector2, half_width_m: float, ppm: float) -> PackedVector2Array:
	if not outward.is_finite() or outward.length_squared()<.5 or not is_finite(half_width_m) or half_width_m<=0.0 or not is_finite(ppm) or ppm<=0.0:
		return PackedVector2Array()
	var direction:=outward.normalized()
	var normal:=Vector2(-direction.y,direction.x)
	var points:=PackedVector2Array([(-direction*.25-normal*half_width_m)*ppm,(-direction*.25+normal*half_width_m)*ppm,direction*.35*ppm])
	if Geometry2D.triangulate_polygon(points).size()!=3:return PackedVector2Array()
	return points

static func draw_junction(canvas: CanvasItem,junction: Dictionary,origin:=Vector2.ZERO,ppm: float=20,roads: Array=[]) -> void:
	var junction_control := str(junction.get("control",""))
	if junction_control=="lane_transition":return
	var merge := junction_control=="merge"
	var arms: Array=junction.get("approaches",[])
	for arm in arms:
		var raw=arm.direction
		var outward: Vector2=(raw if raw is Vector2 else Vector2(raw[0],raw[1])).normalized()
		var normal:=Vector2(-outward.y,outward.x)
		var p:=Vector2(arm.p[0],arm.p[1])-origin
		var width:=float(arm.width)
		if not outward.is_finite() or outward.length_squared()<.5 or not p.is_finite() or not is_finite(width) or width<=0.0:continue
		var control := str(arm.get("control","none"))
		var road_id := int(arm.get("road",-1))
		var kind := str(roads[road_id].get("kind","")) if road_id>=0 and road_id<roads.size() else ""
		# Keep the alley mouth free of stop bars, yield triangles and fixtures.
		if kind=="alley":continue
		var urban := kind in ["local","arterial"]
		var paint := Color("#eeeae0")
		var one_way_ramp := kind=="onramp" and int(roads[road_id].get("lanes",1))==1
		var incoming_width := width if one_way_ramp else width*.5
		if control in ["stop","signal"] and not merge and incoming_width>1.0:
			canvas.draw_line((p+outward*.8+normal*(width*.5-incoming_width-.25))*ppm,(p+outward*.8-normal*(width*.5-.35))*ppm,paint,.3*ppm,true)
		elif control=="yield" and incoming_width>1.0:
			var count := maxi(1,floori((incoming_width-.7)/.85))
			for i in count:
				var across := -width*.5+.35+(float(i)+.5)*(incoming_width-.7)/float(count)
				var at := p+outward*.8+normal*across
				var half := minf(.27,(incoming_width-.7)/float(count)*.35)
				var triangle:=yield_triangle(outward,half,ppm)
				if triangle.size()!=3:continue
				canvas.draw_set_transform(at*ppm)
				canvas.draw_colored_polygon(triangle,paint)
				canvas.draw_set_transform(Vector2.ZERO)
		if urban and arms.size()>=3 and not merge and junction_control!="roundabout" and width>3.0:
			var count := maxi(2,floori((width-.9)/.85))
			for i in count:
				var across := -width*.5+.45+(float(i)+.5)*(width-.9)/float(count)
				var at := p-outward*1.25+normal*across
				canvas.draw_line((at-outward*.9)*ppm,(at+outward*.9)*ppm,paint,.38*ppm,true)
		if merge:continue
		var pole: Vector2=p+outward*1.5-normal*(width*.5+2.1)
		canvas.draw_line((pole+Vector2(.3,.4))*ppm,(pole+Vector2(1.7,2.2))*ppm,Color(.04,.09,.10,.28),.45*ppm,true)
		canvas.draw_circle(pole*ppm,.22*ppm,Color("#b4beb1"))
		canvas.draw_line(pole*ppm,(pole+normal*1.4)*ppm,Color("#586a69"),.18*ppm,true)
		canvas.draw_set_transform((pole+normal*1.4)*ppm,outward.angle())
		canvas.draw_rect(Rect2(Vector2(-.45,-1.15)*ppm,Vector2(.9,2.3)*ppm),Color("#273435"))
		for i in 3:
			var lens:=Vector2(0,(i-1)*.65)*ppm
			canvas.draw_circle(lens,.25*ppm,Color("#101a1c"))
			canvas.draw_arc(lens,.25*ppm,PI,TAU,8,Color("#637171"),.045*ppm,true)
		canvas.draw_set_transform(Vector2.ZERO)
