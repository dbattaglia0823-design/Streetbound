extends RefCounted
## Shared selection geometry for the native map editor. Positions are metres.
const LIMIT:=1200
const Session=preload("res://scripts/dev/native_map_edit_session.gd")

static func _path_touches_area(path: PackedVector2Array,area: Rect2) -> bool:
	if path.is_empty():return false
	var p0:=area.position
	var p1:=area.end
	var corners:=PackedVector2Array([p0,Vector2(p1.x,p0.y),p1,Vector2(p0.x,p1.y)])
	for i in path.size():
		if area.has_point(path[i]):return true
		if i==0:continue
		for j in 4:
			if Geometry2D.segment_intersects_segment(path[i-1],path[i],corners[j],corners[(j+1)%4])!=null:
				return true
	return false

static func all_visible(doc: Dictionary,layers: Dictionary) -> Array[String]:
	var found: Array[String]=[]
	for category in ["props","markers","regions","roads"]:
		var layer: String={"props":"scenery","markers":"markers","regions":"terrain","roads":"roads"}[category]
		if not bool(layers.get(layer,true)):continue
		for item in doc.get(category,[]):
			if bool(item.get("hidden",false)):continue
			found.append(str(item.get("id","")))
			if found.size()>=LIMIT:return found
	return found

static func within_rect(doc: Dictionary,area: Rect2,layers: Dictionary) -> Array[String]:
	var found: Array[String]=[]
	for category in ["props","markers","regions","roads"]:
		var layer: String={"props":"scenery","markers":"markers","regions":"terrain","roads":"roads"}[category]
		if not bool(layers.get(layer,true)):continue
		for item in doc.get(category,[]):
			if bool(item.get("hidden",false)):continue
			var matches:=false
			if category=="props":
				var center:=Vector2(float(item.x),float(item.y))
				var half:=Vector2(4,4)
				if item.has("assetSize") and item.assetSize is Array and item.assetSize.size()==2:
					half=Vector2(float(item.assetSize[0]),float(item.assetSize[1]))*.5
				half*=float(item.get("scale",1.0))
				half*=Vector2(float(item.get("scaleX",1.0)),float(item.get("scaleY",1.0)))
				var angle:=deg_to_rad(float(item.get("rotation",0.0)))
				var rotated_half:=Vector2(absf(half.x*cos(angle))+absf(half.y*sin(angle)),
					absf(half.x*sin(angle))+absf(half.y*cos(angle)))
				matches=area.intersects(Rect2(center-rotated_half,rotated_half*2),true)
			elif category=="markers":
				matches=area.has_point(Vector2(float(item.x),float(item.y)))
			else:
				var path:=PackedVector2Array()
				if category=="roads":
					path=Session.road_path(item)
				else:
					for point in item.get("points",[]):path.append(Vector2(float(point.x),float(point.y)))
					if path.size()>=3:path.append(path[0])
				matches=_path_touches_area(path,area)
			if matches:
				found.append(str(item.get("id","")))
				if found.size()>=LIMIT:return found
	return found
