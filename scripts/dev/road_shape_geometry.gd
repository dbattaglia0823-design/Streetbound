extends RefCounted
## Circle identity comes from the control points, so moving, duplicating,
## saving and manually reshaping roads cannot leave stale shape metadata.
const CIRCLE_STEPS := 32

static func point(raw: Dictionary) -> Vector2:
	return Vector2(float(raw.x),float(raw.y))

static func circle(anchors: Array) -> Dictionary:
	if anchors.size()<9 or point(anchors[0]).distance_to(point(anchors[-1]))>.01:return {}
	var count:=anchors.size()-1
	var a:=point(anchors[0])
	var u:=point(anchors[count/3])-a
	var v:=point(anchors[count*2/3])-a
	var divisor:=2*u.cross(v)
	if absf(divisor)<.01:return {}
	var center:=a+Vector2(v.y*u.length_squared()-u.y*v.length_squared(),u.x*v.length_squared()-v.x*u.length_squared())/divisor
	var radius:=center.distance_to(a)
	if radius<7.98 or not is_finite(radius):return {}
	var direction:=1.0 if (a-center).cross(point(anchors[1])-center)>0 else -1.0
	var total:=0.0
	for i in count:
		if absf(point(anchors[i]).distance_to(center)-radius)>.02:return {}
		var angle:=fposmod(direction*(point(anchors[i+1])-center).angle()-direction*(point(anchors[i])-center).angle(),TAU)
		if angle<.00001 or angle>PI:return {}
		total+=angle
	if absf(total-TAU)>.01:return {}
	return {"center":center,"radius":radius,"direction":direction}

static func circle_points(center: Vector2,radius: float) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	for i in CIRCLE_STEPS:result.append(center+Vector2.from_angle(TAU*i/CIRCLE_STEPS)*radius)
	result.append(result[0])
	return result

static func circle_path(anchors: Array,shape: Dictionary) -> PackedVector2Array:
	var path:=PackedVector2Array()
	var center: Vector2=shape.center
	var radius: float=shape.radius
	var direction: float=shape.direction
	# Same 6 m length / 3.5 cm chord-error limits as the production baker.
	var max_angle:=minf(6/radius,2*acos(clampf(1-.035/radius,-1,1)))
	for i in range(anchors.size()-1):
		var first:=point(anchors[i]);var last:=point(anchors[i+1])
		var angle: float=(first-center).angle()
		var sweep:=fposmod(direction*((last-center).angle()-angle),TAU)
		var steps:=maxi(1,ceili(sweep/max_angle))
		for j in steps:
			path.append(first if j==0 else center+Vector2.from_angle(angle+direction*sweep*j/steps)*radius)
	path.append(point(anchors[-1]))
	return path

static func closest_on_circle(shape: Dictionary,at: Vector2) -> Vector2:
	var offset: Vector2=at-Vector2(shape.center)
	if offset.length_squared()<.0001:offset=Vector2.RIGHT
	return Vector2(shape.center)+offset.normalized()*float(shape.radius)
