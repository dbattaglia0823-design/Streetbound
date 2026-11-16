extends RefCounted
## Shared selection geometry for the native map editor. Positions are metres.
const LIMIT:=1200

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
				matches=area.intersects(Rect2(center-half,half*2),true)
			elif category=="markers":
				matches=area.has_point(Vector2(float(item.x),float(item.y)))
			else:
				var points: Array=item.get("points",[])
				if points.size()>0:
					var bounds:=Rect2(Vector2(float(points[0].x),float(points[0].y)),Vector2.ZERO)
					for point in points:bounds=bounds.expand(Vector2(float(point.x),float(point.y)))
					matches=area.intersects(bounds,true)
			if matches:
				found.append(str(item.get("id","")))
				if found.size()>=LIMIT:return found
	return found
