extends RefCounted
## Authoring-only metadata and deterministic resize calculations.
const CATEGORIES=["roads","regions","props","markers","races"]
static func valid_layers(raw: Variant) -> bool:
	if not raw is Array or raw.size()>64:return false
	var names: Dictionary={}
	var ids: Dictionary={}
	for layer in raw:
		if not layer is Dictionary or not layer.get("name") is String or layer.name.strip_edges().is_empty() or layer.name.length()>60 or names.has(layer.name):return false
		if not layer.get("visible") is bool or not layer.get("locked") is bool or not layer.get("ids") is Array or layer.ids.size()>10000:return false
		names[layer.name]=true
		for id in layer.ids:
			if not id is String or id.length()>120 or ids.has(id):return false
			ids[id]=true
	return true

static func excluded(doc: Dictionary,include_locked: bool=false) -> Dictionary:
	var result: Dictionary={}
	for layer in doc.get("editorLayers",[]):
		if not bool(layer.visible) or (include_locked and bool(layer.locked)):
			for id in layer.ids:result[str(id)]=true
	return result

static func preview(doc: Dictionary) -> Dictionary:
	var hidden:=excluded(doc)
	if hidden.is_empty():return doc
	var result:=doc.duplicate(false)
	for category in CATEGORIES:
		result[category]=doc.get(category,[]).filter(func(item: Dictionary)->bool:return not hidden.has(str(item.id)))
	return result

static func records(doc: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for category in CATEGORIES:
		for item in doc.get(category,[]):result[str(item.id)]=item
	return result

static func locks_unchanged(before: Dictionary,after: Dictionary) -> bool:
	if not before.get("editorLayers",[]).any(func(layer: Dictionary)->bool:return layer.locked):return true
	var old:=records(before)
	var next:=records(after)
	for layer in before.get("editorLayers",[]):
		if not bool(layer.locked):continue
		for id in layer.ids:
			if old.get(id,{})!=next.get(id,{}):return false
	return true

static func resize(doc: Dictionary,width: int,height: int) -> Dictionary:
	if not doc.get("customMap",false) or width<600 or width>24000 or height<600 or height>24000:return {}
	var result:=doc.duplicate(true)
	# Keep coordinates anchored at the northwest origin; never rescale roads.
	var old_extent:=Vector2(doc.world.width,doc.world.height)
	result.world.width=width;result.world.height=height
	if doc.has("terrainHeight"):
		var src: Array=doc.terrainHeight.values
		var samples: Array=[]
		samples.resize(129*129)
		for y in 129:
			for x in 129:
				var p:=Vector2(float(x)*width/128.0,float(y)*height/128.0)/old_extent*128.0
				var h:=0.0
				if p.x<=128 and p.y<=128:
					var ix:=floori(p.x);var iy:=floori(p.y)
					var nx:=mini(ix+1,128);var ny:=mini(iy+1,128)
					h=lerpf(lerpf(float(src[iy*129+ix]),float(src[iy*129+nx]),p.x-ix),
						lerpf(float(src[ny*129+ix]),float(src[ny*129+nx]),p.x-ix),p.y-iy)
				samples[y*129+x]=snappedf(h,.1)
		result.terrainHeight={"size":129,"values":samples}
	return result

static func matches(item: Dictionary,_category: String,kind: String,query: String,region: Dictionary={}) -> bool:
	if kind!="all" and str(item.get("roadClass",item.get("type",item.get("biome",""))))!=kind:return false
	if not query.is_empty() and query.to_lower() not in (str(item.get("name",""))+" "+str(item.id)).to_lower():return false
	if not region.is_empty():
		var poly:=PackedVector2Array()
		for p in region.points:poly.append(Vector2(p.x,p.y))
		if item.has("points"):
			for p in item.points:
				if Geometry2D.is_point_in_polygon(Vector2(p.x,p.y),poly):return true
			return false
		return Geometry2D.is_point_in_polygon(Vector2(item.get("x",0),item.get("y",0)),poly)
	return true

static func measure(points: Array[Vector2]) -> Dictionary:
	var length:=0.0
	var area:=0.0
	for i in points.size():
		if i>0:length+=points[i].distance_to(points[i-1])
		if points.size()>2:area+=points[i].cross(points[(i+1)%points.size()])
	var angle:=0.0
	if points.size()>=3:angle=absf(rad_to_deg((points[0]-points[1]).angle_to(points[2]-points[1])))
	return {"length":length,"area":absf(area)*.5,"angle":angle}

static func road_metrics(road: Dictionary) -> Dictionary:
	var points: Array=road.points
	var profile: Dictionary=road.get("elevation",{})
	var layers: Array=profile.get("point_layers",[])
	var length:=0.0;var grade:=0.0
	for i in range(1,points.size()):
		var span:=Vector2(points[i-1].x,points[i-1].y).distance_to(Vector2(points[i].x,points[i].y))
		length+=span
		if layers.size()==points.size():grade=maxf(grade,absf(float(layers[i])-float(layers[i-1]))*600.0/maxf(.001,span))
	if layers.is_empty():grade=absf(float(profile.get("end_layer",0))-float(profile.get("start_layer",0)))*600.0/maxf(.001,length)
	return {"length":length,"grade":grade}

static func _segment_height(road: Dictionary,index: int,t: float) -> float:
	var profile: Dictionary=road.get("elevation",{})
	var layers: Array=profile.get("point_layers",[])
	if layers.size()==road.points.size():return lerpf(float(layers[index-1]),float(layers[index]),t)*6.0
	var total:=0.0;var station:=0.0
	for i in range(1,road.points.size()):
		var length:=Vector2(road.points[i-1].x,road.points[i-1].y).distance_to(Vector2(road.points[i].x,road.points[i].y))
		total+=length
		if i<index:station+=length
		elif i==index:station+=length*t
	return lerpf(float(profile.get("start_layer",0)),float(profile.get("end_layer",0)),station/maxf(.001,total))*6.0

static func crossing_clearance(a: Dictionary,b: Dictionary) -> float:
	var best:=-1.0
	for i in range(1,a.points.size()):
		var p:=Vector2(a.points[i-1].x,a.points[i-1].y);var q:=Vector2(a.points[i].x,a.points[i].y)
		for j in range(1,b.points.size()):
			var r:=Vector2(b.points[j-1].x,b.points[j-1].y);var s:=Vector2(b.points[j].x,b.points[j].y)
			var hit: Variant=Geometry2D.segment_intersects_segment(p,q,r,s)
			if hit==null:continue
			var h:=absf(_segment_height(a,i,p.distance_to(hit)/maxf(.001,p.distance_to(q)))-_segment_height(b,j,r.distance_to(hit)/maxf(.001,r.distance_to(s))))
			best=h if best<0 else minf(best,h)
	return best
