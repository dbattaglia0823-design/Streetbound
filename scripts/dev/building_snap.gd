extends RefCounted
## Snap parallel building footprints edge-to-edge without changing rotation.
const CLEARANCE_M:=0.02
const MAX_CORRECTION_M:=3.0
const EDGE_SNAP_RADIUS_M:=3.5

static func position(at: Vector2,size: Vector2,angle: float,neighbors: Array,tolerance:=2.0,clearance:=0.0) -> Vector2:
	var best:=tolerance
	var result:=at
	for other in neighbors:
		var turn: float=wrapf(angle-float(other.angle),-PI,PI)
		if absf(sin(turn*2))>.01:continue
		var own: Vector2=size if absf(cos(turn))>.5 else Vector2(size.y,size.x)
		var half: Vector2=(own+Vector2(other.size))*.5+Vector2.ONE*clearance
		var local: Vector2=(at-Vector2(other.p)).rotated(-float(other.angle))
		for axis in 2:
			var across:=1-axis
			if absf(local[across])>half[across]-.05:continue
			for side in [-1,1]:
				var candidate:=local;candidate[axis]=side*half[axis]
				var align: float=(Vector2(other.size)[across]-own[across])*.5
				for offset in [0.0,align,-align]:
					if absf(candidate[across]-offset)<.5:candidate[across]=offset;break
				var distance:=candidate.distance_to(local)
				if distance<best:
					best=distance;result=Vector2(other.p)+candidate.rotated(float(other.angle))
	return result


## Separating-axis test for rotated rectangular building footprints, in metres.
## The clearance extends BOTH touching walls by the specified total gap;
## nearest grid coordinates are not assumed to be safe.
static func separation(at: Vector2,size: Vector2,angle: float,other: Dictionary,
		clearance: float=CLEARANCE_M) -> Vector2:
	var other_center: Vector2=other.p
	var other_size: Vector2=other.size
	var other_angle: float=float(other.angle)
	var heading:=Vector2.RIGHT.rotated(angle)
	var side:=heading.orthogonal()
	var remote_heading:=Vector2.RIGHT.rotated(other_angle)
	var remote_side:=remote_heading.orthogonal()
	var between:=at-other_center
	var best:=INF
	var displacement:=Vector2.ZERO
	for axis in [heading,side,remote_heading,remote_side]:
		var own_span: float=absf(axis.dot(heading))*size.x*.5+absf(axis.dot(side))*size.y*.5
		var other_span: float=absf(axis.dot(remote_heading))*other_size.x*.5+absf(axis.dot(remote_side))*other_size.y*.5
		var signed: float=axis.dot(between)
		var overlap: float=own_span+other_span+clearance-absf(signed)
		if overlap<=0.00001:return Vector2.ZERO
		if overlap<best:
			best=overlap
			displacement=axis*(overlap+0.0005)*(1.0 if signed>=0.0 else -1.0)
	return displacement

static func has_clearance(at: Vector2,size: Vector2,angle: float,neighbors: Array,
		clearance: float=CLEARANCE_M) -> bool:
	for other in neighbors:
		var reach: float=(size.length()+Vector2(other.size).length())*.5+clearance
		if at.distance_squared_to(Vector2(other.p))>reach*reach:continue
		if separation(at,size,angle,other,clearance)!=Vector2.ZERO:return false
	return true

## Repeated minimum translations fix small grid-induced overlaps. Reject
## overcrowded locations instead of shoving buildings several metres away.
static func resolve(at: Vector2,size: Vector2,angle: float,neighbors: Array,
		limit: float=MAX_CORRECTION_M) -> Dictionary:
	var adjusted:=at
	for iteration in 12:
		var changed:=false
		for other in neighbors:
			var reach: float=(size.length()+Vector2(other.size).length())*.5+CLEARANCE_M
			if adjusted.distance_squared_to(Vector2(other.p))>reach*reach:continue
			var correction:=separation(adjusted,size,angle,other)
			if correction==Vector2.ZERO:continue
			adjusted+=correction
			if adjusted.distance_to(at)>limit:
				return {"valid":false,"position":at}
			changed=true
		if not changed:return {"valid":true,"position":adjusted}
	return {"valid":false,"position":at}
