extends Node2D
## Live race starts and user waypoint route, above the cached map artwork.
const GPS_COLOR=Color("ffc866")
var map_view: Control
var waypoints: Node
var races: Array[Node2D]=[]
var on_map:=true
var _clock:=0.0

func _process(dt: float) -> void:
	_clock-=dt
	if _clock<=0:_clock=.08;queue_redraw()

func mapped(p: Vector2) -> Vector2:
	return (p-map_view.center_m)*map_view.pixels_per_m+map_view.custom_minimum_size*.5

func race_at(local_point: Vector2) -> Node2D:
	var best: Node2D;var distance:=18.0
	for race in races:
		if not is_instance_valid(race) or not bool(race.get("available")):continue
		var at: Vector2=mapped(race.get("start_m"))
		if at.distance_to(local_point)<distance:distance=at.distance_to(local_point);best=race
	return best

func _draw() -> void:
	if not is_instance_valid(waypoints):return
	var nav: RefCounted=waypoints.navigation
	if not on_map:
		if not waypoints.active or waypoints.suspended or nav==null:return
		var station:=float(nav.station_at(waypoints.player.global_position/20))
		var end:=minf(float(nav.length_m),station+160)
		while station<end:
			var next:=minf(end,station+6)
			var a: Vector2=nav.point_at(station)*20;var b: Vector2=nav.point_at(next)*20
			draw_line(a,b,Color(.08,.09,.05,.65),12,true);draw_line(a,b,GPS_COLOR,5,true)
			station=next
		return
	if not is_instance_valid(map_view):return
	# Only the high-DPI pause map opts into larger screen-space glyphs.
	var density: float = maxf(1.0, float(map_view.get_meta("pause_render_density", 1.0)))
	var clip:=Rect2(Vector2.ZERO,map_view.custom_minimum_size).grow(20)
	if waypoints.active and nav!=null and not waypoints.suspended:
		var points: PackedVector2Array=nav.points_m
		for i in range(1,points.size()):
			var a:=mapped(points[i-1]);var b:=mapped(points[i])
			if not clip.has_point(a) and not clip.has_point(b) and not Rect2(a,b-a).abs().intersects(clip):continue
			draw_line(a,b,Color("443522"),5.5*density,true);draw_line(a,b,GPS_COLOR,3*density,true)
	for race in races:
		if not is_instance_valid(race) or not bool(race.get("available")):continue
		var p:=mapped(race.get("start_m"))
		if not clip.has_point(p):continue
		var radius: float=(6.0 if map_view.miniature else 10.0)*density
		draw_circle(p,radius+2*density,Color("103c43"));draw_circle(p,radius,Color("4edee4"))
		draw_line(p+Vector2(-3,4)*density,p+Vector2(-3,-5)*density,Color("15373c"),1.5*density,true)
		for x in 3:
			for y in 2:
				if (x+y)%2==0:draw_rect(Rect2(p+Vector2(-2+x*2,-5+y*2)*density,Vector2(2,2)*density),Color("15373c"))
		if not map_view.miniature:
			var font:=ThemeDB.fallback_font
			var title:=str(race.get("race_title"))
			# Text must scale with the map source, not shrink when the
			# high-resolution pause texture is downsampled to a card.
			var font_size := maxi(1, roundi(12.0 * density))
			var at:=p+Vector2(14,4)*density
			draw_string_outline(font,at,title,HORIZONTAL_ALIGNMENT_LEFT,-1,
				font_size,maxi(1,roundi(3.0*density)),Color("15373c"))
			draw_string(font,at,title,HORIZONTAL_ALIGNMENT_LEFT,-1,
				font_size,Color("eaffed"))
	if waypoints.active:
		var p:=mapped(waypoints.destination_m)
		if clip.has_point(p):
			draw_circle(p,10*density,Color("443522"));draw_circle(p,7*density,GPS_COLOR)
			draw_arc(p,12*density,0,TAU,32,GPS_COLOR,2*density,true)
