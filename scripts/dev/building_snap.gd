extends RefCounted
## Exact building edge and corner snapping in world metres. Authoring permits
## intentional overlaps; snapping never performs collision separation.
const EDGE_SNAP_RADIUS_M:=3.5
const CORNER_ALIGN_RADIUS_M:=1.5

static func _consider(at: Vector2,candidate: Vector2,tolerance: float,
		alignment: bool,best: Dictionary) -> Dictionary:
	var distance: float=at.distance_to(candidate)
	if distance>tolerance+0.000001:return best
	# Prefer an exact corner/centre join to a slightly closer edge-only join
	# only when the two corrections are very similar.
	var score: float=distance-(0.9 if alignment else 0.0)
	if score<float(best.get("score",INF)):
		return {"position":candidate,"score":score,"distance":distance}
	return best

## Returns an exact snapped position, not rounded to the editor's metre grid.
## Empty means no nearby edge or corner; callers may then use ordinary grid snap.
static func match(at: Vector2,size: Vector2,angle: float,neighbors: Array,
		tolerance: float=EDGE_SNAP_RADIUS_M) -> Dictionary:
	var best: Dictionary={}
	var own_half: Vector2=size*.5
	for other in neighbors:
		var center: Vector2=other.p
		var remote_size: Vector2=other.size
		var remote_angle: float=float(other.angle)
		var remote_half: Vector2=remote_size*.5
		# Rotate-correct corner anchors also work for dissimilar roof angles.
		for own_x in [-1.0,1.0]:
			for own_y in [-1.0,1.0]:
				var own_corner:=Vector2(own_half.x*own_x,own_half.y*own_y).rotated(angle)
				for other_x in [-1.0,1.0]:
					for other_y in [-1.0,1.0]:
						var remote_corner:=Vector2(remote_half.x*other_x,remote_half.y*other_y).rotated(remote_angle)
						var candidate: Vector2=center+remote_corner-own_corner
						# Coincident/internal corners are not exterior joins. Leave
						# overlapping footprints exactly where the author placed them.
						var min_extent: float=minf(minf(size.x,size.y),minf(remote_size.x,remote_size.y))
						if candidate.distance_to(center)>=min_extent*.8:
							best=_consider(at,candidate,tolerance,true,best)
		# A parallel pair can share a wall without requiring their corners to
		# match. Include two-axis centre/corner anchors as precise alternatives.
		var turn: float=wrapf(angle-remote_angle,-PI,PI)
		if absf(sin(turn*2.0))>.01:continue
		var own: Vector2=size if absf(cos(turn))>.5 else Vector2(size.y,size.x)
		var half: Vector2=(own+remote_size)*.5
		var local: Vector2=(at-center).rotated(-remote_angle)
		for axis in 2:
			var across: int=1-axis
			for side in [-1.0,1.0]:
				var face: float=side*half[axis]
				# The closest point on the wall is allowed to slide along it.
				# Do not pull to a corner when farther than the corner radius.
				var plain: Vector2=local
				plain[axis]=face
				if absf(local[across])<=half[across]+tolerance:
					best=_consider(at,center+plain.rotated(remote_angle),tolerance,false,best)
				var centre_offset: float=(remote_size[across]-own[across])*.5
				for anchor in [0.0,centre_offset,-centre_offset,
						half[across],-half[across]]:
					if absf(local[across]-anchor)>CORNER_ALIGN_RADIUS_M:continue
					var aligned: Vector2=plain
					aligned[across]=anchor
					best=_consider(at,center+aligned.rotated(remote_angle),tolerance,true,best)
	return best

static func position(at: Vector2,size: Vector2,angle: float,neighbors: Array,
		tolerance: float=EDGE_SNAP_RADIUS_M,clearance: float=0.0) -> Vector2:
	var found: Dictionary=match(at,size,angle,neighbors,tolerance)
	return Vector2(found.position) if not found.is_empty() else at
