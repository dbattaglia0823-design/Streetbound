extends RefCounted
## Road-linked rails use normalized stations and the direction of the stored road.
## The production compiler recomputes actual collision paths from baked splines.
const WIDTH:=.65
const CLEARANCE:=3.0

static func ground(road: Dictionary) -> bool:
	var elevation: Dictionary=road.get("elevation",{})
	for layer in elevation.get("point_layers",[elevation.get("start_layer",0),elevation.get("end_layer",0)]):
		if int(layer)!=0:return false
	return true

static func valid(road: Dictionary) -> bool:
	if not road.has("autoGuardrails"):return true
	var settings: Variant=road.autoGuardrails
	if not settings is Dictionary or settings.size()>2 or not ground(road):return false
	for side in settings:
		if side not in ["left","right"]:return false
		var interval: Variant=settings[side]
		if not interval is Array or interval.size()!=2:return false
		for n in interval:
			if not (n is int or n is float) or not is_finite(float(n)) or float(n)<0 or float(n)>100:return false
		if float(interval[1])<=float(interval[0]):return false
	return true

static func point_at(path: PackedVector2Array, stations: PackedFloat64Array, at: float) -> Vector2:
	var lo:=0
	var hi:=stations.size()-1
	while hi-lo>1:
		var mid: int=(lo+hi)/2
		if stations[mid]<at:lo=mid
		else:hi=mid
	return path[lo].lerp(path[hi],clampf((at-stations[lo])/maxf(.001,stations[hi]-stations[lo]),0,1))

static func preview(roads: Array, paths: Dictionary, bounds: Rect2, width_scale: float) -> Array[PackedVector2Array]:
	var output: Array[PackedVector2Array]=[]
	var grid: Dictionary={}
	const CELL:=64.0
	for road in roads:
		var id:=str(road.id)
		var path: PackedVector2Array=paths[id]
		var elevation: Dictionary=road.get("elevation",{})
		var layers: Array=elevation.get("point_layers",[elevation.get("start_layer",0),elevation.get("end_layer",0)])
		if layers.all(func(v: Variant)->bool:return int(v)>0) or layers.all(func(v: Variant)->bool:return int(v)<0):continue
		var pad:=float(road.width)*width_scale*.5+CLEARANCE+WIDTH
		for i in range(1,path.size()):
			var a:=path[i-1];var b:=path[i]
			var rect:=Rect2(a,Vector2.ZERO).expand(b).grow(pad)
			for x in range(floori(rect.position.x/CELL),floori(rect.end.x/CELL)+1):
				for y in range(floori(rect.position.y/CELL),floori(rect.end.y/CELL)+1):
					var key:=Vector2i(x,y)
					if not grid.has(key):grid[key]=[]
					grid[key].append([id,a,b,pad])
	for road in roads:
		if not road.has("autoGuardrails") or not valid(road):continue
		var id:=str(road.id)
		var path: PackedVector2Array=paths[id]
		if path.size()<2:continue
		var stations:=PackedFloat64Array([0.0])
		for i in range(1,path.size()):stations.append(stations[-1]+path[i].distance_to(path[i-1]))
		var length:=stations[-1]
		if length<1:continue
		for side in road.autoGuardrails:
			var interval: Array=road.autoGuardrails[side]
			var start:=length*float(interval[0])/100.0
			var end:=length*float(interval[1])/100.0
			var count:=maxi(1,ceili((end-start)/2.0))
			var run:=PackedVector2Array()
			for i in range(count+1):
				var at:=lerpf(start,end,float(i)/count)
				var center:=point_at(path,stations,at)
				var tangent:=(point_at(path,stations,minf(length,at+.5))-point_at(path,stations,maxf(0,at-.5))).normalized()
				var offset:=float(road.width)*width_scale*.5+1.5
				var p:=center+Vector2(tangent.y,-tangent.x)*offset*(1.0 if side=="left" else -1.0)
				var safe:=bounds.has_point(p)
				for segment in grid.get(Vector2i(floori(p.x/CELL),floori(p.y/CELL)),[]):
					if segment[0]==id:continue
					if p.distance_to(Geometry2D.get_closest_point_to_segment(p,segment[1],segment[2]))<float(segment[3])+1.0:
						safe=false;break
				if safe:
					if run.is_empty() or p.distance_to(run[-1])>=.5:run.append(p)
				else:
					if run.size()>1:output.append(run)
					run=PackedVector2Array()
			if run.size()>1:output.append(run)
	return output
