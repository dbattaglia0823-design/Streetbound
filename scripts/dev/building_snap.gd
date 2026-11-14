extends RefCounted
## Snap parallel building footprints edge-to-edge without changing rotation.
static func position(at: Vector2,size: Vector2,angle: float,neighbors: Array,tolerance:=2.0) -> Vector2:
	var best:=tolerance
	var result:=at
	for other in neighbors:
		var turn: float=wrapf(angle-float(other.angle),-PI,PI)
		if absf(sin(turn*2))>.01:continue
		var own: Vector2=size if absf(cos(turn))>.5 else Vector2(size.y,size.x)
		var half: Vector2=(own+Vector2(other.size))*.5
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
