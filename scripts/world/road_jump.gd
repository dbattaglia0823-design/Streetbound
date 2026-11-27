extends RefCounted
## Ground-road jumps use metre-space ballistics and the ordinary 2D body sweep.
const G := 9.81
const MAX_TIME := 2.0
const MAX_RISE := 4.0
const MAX_RANGE := 62.0
const LATERAL_SPEED := .65
const PPM := 20.0
const FIELDS := {
	"at_m": [12.0,24000.0,80.0,"Takeoff (m from road start)"],
	"length_m": [4.0,20.0,8.0,"Ramp length (m)"],
	"width_m": [3.0,12.0,3.5,"Ramp width (m)"],
	"height_m": [.25,1.5,.55,"Ramp height (m)"],
	"angle_deg": [5.0,18.0,12.0,"Launch angle (degrees)"],
	"min_mps": [8.0,24.0,15.0,"Minimum speed (m/s)"],
	"max_mps": [10.0,26.0,20.0,"Maximum speed (m/s)"],
	"landing_length_m": [6.0,42.0,16.0,"Landing length (m)"],
	"landing_width_m": [4.0,16.0,4.5,"Landing width (m)"],
}


static func flight_time(height: float, upward: float) -> float:
	return (upward + sqrt(upward*upward + 2.0*G*height))/G


static func authoring_preview(road: Dictionary) -> Dictionary:
	var raw: Variant = road.get("jump")
	if not raw is Dictionary or raw.size() != FIELDS.size()+1 or not raw.get("reverse") is bool:
		return {}
	for key in FIELDS:
		var value: Variant = raw.get(key)
		if not (value is float or value is int) or not is_finite(float(value)) \
				or float(value)<float(FIELDS[key][0]) or float(value)>float(FIELDS[key][1]):
			return {}
	if road.points.size() != 2 or road.has("elevation") or str(road.surface) in ["gravel","dirt"]:
		return {}
	var a := Vector2(road.points[0].x,road.points[0].y)
	var b := Vector2(road.points[1].x,road.points[1].y)
	var span := a.distance_to(b)
	var direction := (b-a).normalized()
	var lip := a+direction*float(raw.at_m)
	var before := float(raw.at_m)
	var after := span-before
	if raw.reverse:
		direction = -direction
		before = span-float(raw.at_m)
		after = float(raw.at_m)
	var tangent := tan(deg_to_rad(float(raw.angle_deg)))
	var low := float(raw.min_mps)
	var high := float(raw.max_mps)
	var height := float(raw.height_m)
	var duration := flight_time(height,high*tangent)
	var near_landing := low*flight_time(height,low*tangent)
	var far_landing := high*duration
	var midpoint := (near_landing+far_landing)*.5
	var half_length := float(raw.landing_length_m)*.5
	if low >= high or duration > MAX_TIME or height+pow(high*tangent,2)/(2*G)>MAX_RISE \
			or midpoint-half_length<3 or midpoint-half_length>near_landing-.65 \
			or midpoint+half_length<far_landing+.65 or midpoint+half_length>MAX_RANGE \
			or before<float(raw.length_m)+2.6 or after<midpoint+half_length+2.6 \
			or float(raw.landing_width_m)<float(raw.width_m)+.5 \
			or float(raw.landing_width_m)*.5+2.6>float(road.width)*.5:
		return {}
	return {"lip":lip,"direction":direction,"landing_start_m":midpoint-half_length,
		"landing_end_m":midpoint+half_length}


static func offsets(spec: Dictionary, position_px: Vector2) -> Vector2:
	var delta := position_px/PPM-Vector2(spec.p[0],spec.p[1])
	var direction := Vector2(spec.direction[0],spec.direction[1])
	return Vector2(delta.dot(direction),delta.dot(direction.orthogonal()))


static func in_strip(spec: Dictionary, position_px: Vector2, landing: bool) -> bool:
	var at := offsets(spec,position_px)
	var first := float(spec.landing_start_m) if landing else -.25
	return at.x >= first and at.x <= float(spec.landing_end_m) and absf(at.y)<=float(spec.landing_width_m)*.5


## Derive object-ramp geometry from the same final prop dimensions and
## rotation used by the scenery renderer, including independent axis scales.
static func object_spec(prop: Dictionary) -> Dictionary:
	var size:=Vector2(float(prop.size[0]),float(prop.size[1]))
	var center:=Vector2(float(prop.p[0]),float(prop.p[1]))
	var direction:=Vector2.UP.rotated(float(prop.angle))
	var lip:=center+direction*size.y*.5
	return {"object_ramp":true,"prop_id":str(prop.get("authoring_id","")),"road_id":-1,
		"p":[lip.x,lip.y],"direction":[direction.x,direction.y],
		"width_m":size.x,"length_m":size.y,"height_m":size.y*.15,
		"angle_deg":rad_to_deg(atan(.15))}


static func footprint_reach(car: Node2D, axis: Vector2) -> float:
	# The capsule's projected extent in metres. A car overlapping the edge
	# of a ramp can launch even if its center is just outside the orange lip.
	var body:=car.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not is_instance_valid(body) or not body.shape is CapsuleShape2D:return 0.0
	var capsule:=body.shape as CapsuleShape2D
	var normal:=axis.normalized()
	var longitudinal:=Vector2.UP.rotated(body.global_rotation)
	return (capsule.radius+maxf(0.0,capsule.height*.5-capsule.radius)*absf(longitudinal.dot(normal)))/PPM


static func accepts_launch(spec: Dictionary, previous: Vector2, present: Vector2,
		momentum: Vector2, facing: Vector2, lateral_reach_m: float=0.0) -> bool:
	var direction := Vector2(spec.direction[0],spec.direction[1])
	var start := offsets(spec,previous)
	var finish := offsets(spec,present)
	var speed := momentum.dot(direction)
	if bool(spec.get("object_ramp",false)):
		# Cross the actual uphill lip in the positive direction. No required
		# facing, speed window or forecast landing strip: momentum is decisive.
		if start.x>=0.0 or finish.x<0.0 or speed<=0.01:return false
		var fraction: float=-start.x/(finish.x-start.x)
		return absf(lerpf(start.y,finish.y,fraction))<=float(spec.width_m)*.5+maxf(0.0,lateral_reach_m)+.001
	if start.x >= 0.0 or finish.x < 0.0 or speed < float(spec.min_mps) or speed > float(spec.max_mps) \
			or absf(momentum.dot(direction.orthogonal())) > LATERAL_SPEED or facing.dot(direction)<.98:
		return false
	var lip_fraction := -start.x/(finish.x-start.x)
	if absf(lerpf(start.y,finish.y,lip_fraction)) > float(spec.width_m)*.5:
		return false
	var duration := flight_time(float(spec.height_m),speed*tan(deg_to_rad(float(spec.angle_deg))))
	return in_strip(spec,present+momentum*PPM*duration,true)


static func visual_height(vehicle: Node) -> float:
	# Some physics parity checks load the original controller against current assets.
	return float(vehicle.get("jump_height_m")) if vehicle.has_method("is_airborne") else 0.0


static func draw_footprint(canvas: Node2D, spec: Dictionary, lip: Vector2, direction: Vector2,
		preview: bool) -> void:
	var ramp_length := float(spec.length_m)*PPM
	var ramp_width := float(spec.width_m)*PPM
	var landing_a := lip+direction*float(spec.landing_start_m)*PPM
	var landing_b := lip+direction*float(spec.landing_end_m)*PPM
	var start := lip-ramp_length*direction
	var flank := direction.orthogonal()*ramp_width*.5
	var deck := PackedVector2Array([start-flank,lip-flank,lip+flank,start+flank])
	var shadow := PackedVector2Array()
	for point in deck:shadow.append(point+Vector2(7,10))
	canvas.draw_colored_polygon(shadow,Color(.04,.06,.08,.35))
	canvas.draw_polygon(deck,PackedColorArray([Color("657577"),Color("b6bcae"),
		Color("a2a99e"),Color("56656a")]))
	for side in [-1.0,1.0]:
		canvas.draw_line(start+flank*side,lip+flank*side,Color("39474a"),4.0,true)
	for step in range(1,6):
		var rib := start.lerp(lip,float(step)/6.0)
		canvas.draw_line(rib-flank*.91,rib+flank*.91,Color(.08,.13,.16,.24),2.5,true)
		var chevron := PackedVector2Array([rib-direction*7.0-flank*.24,rib+direction*5.0,
			rib-direction*7.0+flank*.24])
		canvas.draw_polyline(chevron,Color(.94,.90,.72,.70),2.2,true)
	canvas.draw_line(lip-flank,lip+flank,Color("f1ae5b"),7.0,true)
	if preview:
		canvas.draw_dashed_line(lip,landing_a,Color("ffc670"),3.0,16.0)
		canvas.draw_line(landing_a,landing_b,Color(.25,.72,.50,.23),float(spec.landing_width_m)*PPM,true)
	var landing_edge := direction.orthogonal()*float(spec.landing_width_m)*PPM*.5
	for side in [-1.0,1.0]:
		var a := landing_a+landing_edge*float(side)
		var b := landing_b+landing_edge*float(side)
		canvas.draw_dashed_line(a,b,Color(.51,.87,.65,.9),3.0,15.0)
