extends RefCounted
## Shared selection geometry for the native map editor. Positions are metres.
const LIMIT:=1200
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Art=preload("res://scripts/world/coast_art.gd")
const BuildingSelection=preload("res://scripts/dev/building_selection_footprint.gd")

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

## This is an authoring selection filter, not a runtime visibility mask.
## Ramps belong to the levels they touch; a point profile can span several.
static func road_matches_layer(road: Dictionary,layer: int) -> bool:
	if layer==99:return true
	var profile: Dictionary=road.get("elevation",{})
	return layer in profile.get("point_layers",[int(profile.get("start_layer",0)),int(profile.get("end_layer",0))])

static func road_point_matches_layer(road: Dictionary,point: Vector2,layer: int) -> bool:
	if layer==99:return true
	if not road_matches_layer(road,layer):return false
	var profile: Dictionary=road.get("elevation",{})
	var values: Array=profile.get("point_layers",[])
	if values.is_empty():return true
	var best:=INF
	var matched:=false
	for i in range(1,road.points.size()):
		var a:=Vector2(road.points[i-1].x,road.points[i-1].y)
		var b:=Vector2(road.points[i].x,road.points[i].y)
		var distance:=point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))
		if distance<best-.01:
			best=distance;matched=layer in [int(values[i-1]),int(values[i])]
		elif absf(distance-best)<.01:
			matched=matched or layer in [int(values[i-1]),int(values[i])]
	return matched

static func all_visible(doc: Dictionary,layers: Dictionary) -> Array[String]:
	var found: Array[String]=[]
	for category in ["props","markers","regions","roads"]:
		var layer: String={"props":"scenery","markers":"markers","regions":"terrain","roads":"roads"}[category]
		if not bool(layers.get(layer,true)):continue
		for item in doc.get(category,[]):
			if bool(item.get("hidden",false)) or layers.get("workspace_excluded",{}).has(str(item.id)):continue
			var filter_layer:=int(layers.get("road_selection_layer",99))
			if filter_layer!=99 and (category!="roads" or not road_matches_layer(item,filter_layer)):continue
			found.append(str(item.get("id","")))
			if found.size()>=LIMIT:return found
	return found

static func _rotated_bounds(center: Vector2,local_rect: Rect2,angle: float) -> Rect2:
	var corners: Array[Vector2]=[
		local_rect.position,
		Vector2(local_rect.end.x,local_rect.position.y),
		local_rect.end,
		Vector2(local_rect.position.x,local_rect.end.y)]
	var result:=Rect2(center+corners[0].rotated(angle),Vector2.ZERO)
	for corner in corners:
		result=result.expand(center+corner.rotated(angle))
	return result


static func within_rect(doc: Dictionary,area: Rect2,layers: Dictionary) -> Array[String]:
	var found: Array[String]=[]
	for category in ["props","markers","regions","roads"]:
		var layer: String={"props":"scenery","markers":"markers","regions":"terrain","roads":"roads"}[category]
		if not bool(layers.get(layer,true)):continue
		for item in doc.get(category,[]):
			if bool(item.get("hidden",false)) or layers.get("workspace_excluded",{}).has(str(item.id)):continue
			var filter_layer:=int(layers.get("road_selection_layer",99))
			if filter_layer!=99 and (category!="roads" or not road_matches_layer(item,filter_layer)):continue
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
				var broad:=Rect2(center-rotated_half,rotated_half*2)
				matches=area.intersects(broad,true)
				if matches and BuildingSelection.is_building_kind(str(item.get("type",""))):
					var texture: Texture2D=null
					if item.has("assetPath"):
						texture=Art.project_sprite(str(item.assetPath),item.get("assetRegion",[]))
					elif str(item.get("assetId","")).begins_with("game-"):
						texture=Art.sprite(str(item.assetId).trim_prefix("game-"),0)
					var tight:=BuildingSelection.selection_rect(texture,half*2)
					matches=area.intersects(_rotated_bounds(center,tight,angle),true)
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


## The live Morrow Coast starts with many generated (not yet authored) props.
## A marquee must be able to select these as well as already-authored assets.
## Return indices rather than editing the source during pointer motion.
static func baked_indices_in_rect(data: Dictionary,area: Rect2,limit: int=64) -> Array[int]:
	var hits: Array[int]=[]
	var props: Array=data.get("props",[])
	for i in props.size():
		var item: Dictionary=props[i]
		if item.has("poi") or item.has("authoring_id"):continue
		var coords: Array=item.get("p",[])
		var dimensions: Array=item.get("size",[])
		if coords.size()!=2 or dimensions.size()!=2:continue
		var center:=Vector2(float(coords[0]),float(coords[1]))
		var half:=Vector2(float(dimensions[0]),float(dimensions[1]))*.5
		var angle: float=float(item.get("angle",0.0))
		var extents:=Vector2(absf(half.x*cos(angle))+absf(half.y*sin(angle)),
			absf(half.x*sin(angle))+absf(half.y*cos(angle)))
		if area.intersects(Rect2(center-extents,extents*2),true):
			if BuildingSelection.is_building_kind(str(item.get("kind",""))):
				var texture: Texture2D=null
				if item.has("asset_path"):
					texture=Art.project_sprite(str(item.asset_path),item.get("asset_region",[]))
				else:
					texture=Art.sprite(str(item.kind),int(item.get("seed",0)))
				var tight:=BuildingSelection.selection_rect(texture,half*2)
				if not area.intersects(_rotated_bounds(center,tight,angle),true):
					continue
			hits.append(i)
			if hits.size()>=limit:break
	return hits
