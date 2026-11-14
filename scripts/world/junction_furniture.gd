extends RefCounted
## Static junction artwork. All lenses are neutral/unlit; no signal phases,
## timers, collision or traffic permissions are introduced by these fixtures.
static func draw_junction(canvas: CanvasItem,junction: Dictionary,origin:=Vector2.ZERO,ppm: float=20) -> void:
	var arms: Array=junction.get("approaches",[])
	for arm in arms:
		var raw=arm.direction
		var outward: Vector2=(raw if raw is Vector2 else Vector2(raw[0],raw[1])).normalized()
		var normal:=Vector2(-outward.y,outward.x)
		var p:=Vector2(arm.p[0],arm.p[1])-origin
		var width:=float(arm.width)
		if str(junction.get("control",""))!="roundabout":
			# Incoming half of a right-hand road; outgoing traffic stays open.
			canvas.draw_line((p+outward*.8-normal*.3)*ppm,(p+outward*.8-normal*(width*.5-.4))*ppm,Color("#e5e1d1"),.32*ppm,true)
			if arms.size()>=3:
				for i in maxi(3,floori((width-1)/1.2)):
					var across: float=lerpf(-width*.5+.6,width*.5-.6,float(i)/maxf(1,floori((width-1)/1.2)-1))
					var at:=p-outward*1.8+normal*across
					canvas.draw_line((at-outward*.45)*ppm,(at+outward*.45)*ppm,Color("#dddacb"),.4*ppm,true)
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
