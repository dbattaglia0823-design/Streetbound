extends RefCounted
## Cached metre-space road segments. Pointer updates query nearby cells only;
## placement/rotation never regenerate the road or traffic geometry.
const CELL:=64.0
const TOLERANCE:=3.0
const SETBACK:=.5
const BUILDING_TYPES=["house","building","warehouse","garage","gas_station"]
var cells: Dictionary={}
var stamp:=""
var rebuild_count:=0

static func supports(prop: Dictionary) -> bool:
	return str(prop.get("type","")) in BUILDING_TYPES

static func enabled(prop: Dictionary) -> bool:
	return supports(prop) and bool(prop.get("roadFacing",true))

func rebuild(roads: Array,key: String) -> void:
	if stamp==key:return
	stamp=key;cells.clear();rebuild_count+=1
	var identity:=0
	for road in roads:
		var path: PackedVector2Array=road.path
		var margin: float=float(road.width)*.5+float(road.get("shoulder",2))
		for i in range(1,path.size()):
			var a:=path[i-1];var b:=path[i]
			if a.distance_squared_to(b)<.000001:continue
			var direction: Vector2=(b-a).normalized()
			var segment: Dictionary={"id":identity,"road":str(road.id),"a":a,"b":b,"direction":direction,"margin":margin}
			identity+=1
			# Index the entire paved/shoulder width, not just the centerline.
			var first:=Vector2i(((a.min(b)-Vector2.ONE*margin)/CELL).floor())
			var last:=Vector2i(((a.max(b)+Vector2.ONE*margin)/CELL).floor())
			for x in range(first.x,last.x+1):
				for y in range(first.y,last.y+1):
					var cell:=Vector2i(x,y)
					if not cells.has(cell):cells[cell]=[]
					cells[cell].append(segment)

func nearby(at: Vector2,size: Vector2) -> Array:
	var reach:=size.length()*.5+TOLERANCE+2
	var first:=Vector2i(((at-Vector2.ONE*reach)/CELL).floor())
	var last:=Vector2i(((at+Vector2.ONE*reach)/CELL).floor())
	var found: Dictionary={}
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):
			for segment in cells.get(Vector2i(x,y),[]):found[segment.id]=segment
	return found.values()

static func extent(size: Vector2,angle: float,direction: Vector2) -> float:
	var local:=direction.rotated(-angle).abs()
	return local.dot(size*.5)

func clear_of_roads(at: Vector2,size: Vector2,angle: float) -> bool:
	for segment in nearby(at,size):
		var a: Vector2=(Vector2(segment.a)-at).rotated(-angle)
		var b: Vector2=(Vector2(segment.b)-at).rotated(-angle)
		var half:=size*.5
		var bounds:=Rect2(-half,size)
		if bounds.has_point(a) or bounds.has_point(b):return false
		var gap:=minf((a-a.clamp(-half,half)).length(),(b-b.clamp(-half,half)).length())
		var corners: Array[Vector2]=[-half,Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]
		for i in 4:
			if Geometry2D.segment_intersects_segment(a,b,corners[i],corners[(i+1)%4])!=null:return false
			gap=minf(gap,corners[i].distance_to(Geometry2D.get_closest_point_to_segment(corners[i],a,b)))
		if gap<float(segment.margin)+.2:return false
	return true

func pose(hit: Dictionary,size: Vector2,angle: float) -> Vector2:
	return Vector2(hit.point)+Vector2(hit.outward)*(float(hit.margin)+extent(size,angle,hit.outward)+SETBACK)

func snap(prop: Dictionary,at: Vector2,size: Vector2) -> Dictionary:
	if not enabled(prop):return {}
	var current_angle:=deg_to_rad(float(prop.get("rotation",0)))
	var front:=deg_to_rad(float(prop.get("roadFront",90)))
	var best:=INF
	var result: Dictionary={}
	for segment in nearby(at,size):
		var direction: Vector2=segment.direction
		var along: float=(at-Vector2(segment.a)).dot(direction)
		# Snap to the side, never to an imaginary extension past a road end.
		if along<-.01 or along>Vector2(segment.a).distance_to(segment.b)+.01:continue
		var point:=Geometry2D.get_closest_point_to_segment(at,segment.a,segment.b)
		var normal:=Vector2(-direction.y,direction.x)
		var side:=1.0 if (at-point).dot(normal)>=0 else -1.0
		var outward:=normal*side
		var distance: float=(at-point).dot(outward)
		var angle:=wrapf((-outward).angle()-front,-PI,PI)
		var desired: float=float(segment.margin)+extent(size,angle,outward)+SETBACK
		var previous: float=float(segment.margin)+extent(size,current_angle,outward)+SETBACK
		if minf(absf(distance-desired),absf(distance-previous))>TOLERANCE:continue
		var hit: Dictionary={"road":segment.road,"point":point,"outward":outward,"margin":segment.margin,"angle":angle}
		var candidate:=pose(hit,size,angle)
		# A broad facade on a bend can need slightly more setback. At a
		# junction, reject a snap that would push it onto the crossing road.
		var safe:=false
		for extra in [0.0,.5,1.0,2.0,3.0]:
			var trial: Vector2=candidate+outward*float(extra)
			if clear_of_roads(trial,size,angle):candidate=trial;safe=true;break
		if not safe:continue
		var score:=candidate.distance_to(at)
		if score<best:
			best=score;result=hit;result["position"]=candidate
	return result
