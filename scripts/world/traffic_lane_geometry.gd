extends RefCounted
## Road-relative lane positions, shared by traffic routing and road paint.
## Positive offsets are right of the authored centreline in screen coordinates.

static func layout(road: Dictionary) -> Dictionary:
	# A single authored lane is a narrow two-way road; both directions keep right.
	var count:=clampi(int(road.get("lanes",2)),2,6)
	var forward:=maxi(1,count/2)
	var reverse:=count-forward
	var width:=float(road.get("width",10.0))/count
	return {"count":count,"forward":forward,"reverse":reverse,"width":width,
		"divider":float(reverse-forward)*width*.5}

static func lane_offset(road: Dictionary, direction: int, lane: int) -> float:
	var lanes:=layout(road)
	return float(lanes.divider)+direction*float(lanes.width)*(lane+.5)

static func offset_path(points: PackedVector2Array, amount: float) -> PackedVector2Array:
	var result:=PackedVector2Array()
	var closed: bool=points.size()>3 and points[0].distance_to(points[-1])<.001
	for i in points.size():
		var before: Vector2=(points[i]-points[maxi(0,i-1)]).normalized()
		var after: Vector2=(points[mini(i+1,points.size()-1)]-points[i]).normalized()
		if i==0:before=(points[0]-points[-2]).normalized() if closed else after
		if i==points.size()-1:after=(points[1]-points[0]).normalized() if closed else before
		var normal: Vector2=Vector2(-(before+after).y,(before+after).x).normalized()
		var side:=Vector2(-after.y,after.x)
		if normal.length_squared()<.5:normal=side
		# Offset the actual road vertices, using a bounded miter at bends.
		# Re-sampling first used to cut hairpins and produce mismatched end tangents.
		result.append(points[i]+normal*amount/maxf(.55,normal.dot(side)))
	return result

static func slice_path(points: PackedVector2Array, stations: PackedFloat64Array,
		begin: float, end: float) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for i in range(1,points.size()):
		if stations[i]<begin or stations[i-1]>end:continue
		var length:=maxf(.00001,stations[i]-stations[i-1])
		var a:=points[i-1].lerp(points[i],clampf((begin-stations[i-1])/length,0,1))
		var b:=points[i-1].lerp(points[i],clampf((end-stations[i-1])/length,0,1))
		if result.is_empty() or result[-1].distance_squared_to(a)>.000001:result.append(a)
		if result[-1].distance_squared_to(b)>.000001:result.append(b)
	return result
