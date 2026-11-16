extends RefCounted
## Selection geometry and atomic bulk edits for source-authored map objects.
## No generated/baked object is implicitly adopted by a marquee gesture.
const Sidewalks=preload("res://scripts/dev/sidewalk_topology.gd")
const Roads=preload("res://scripts/dev/road_shape_geometry.gd")
const CATEGORIES=["roads","regions","props","markers","races"]

static func _crosses_box(area: Rect2, a: Vector2, b: Vector2) -> bool:
	if area.has_point(a) or area.has_point(b):return true
	var corners: Array[Vector2]=[area.position,Vector2(area.end.x,area.position.y),
		area.end,Vector2(area.position.x,area.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a,b,corners[i],corners[(i+1)%4]) is Vector2:
			return true
	return false

static func _path_touches(area: Rect2, path: PackedVector2Array, closed: bool) -> bool:
	if path.is_empty():return false
	for p in path:
		if area.has_point(p):return true
	for i in range(1,path.size()):
		if _crosses_box(area,path[i-1],path[i]):return true
	if closed:
		if _crosses_box(area,path[-1],path[0]):return true
		if path.size()>=3 and Geometry2D.is_point_in_polygon(area.get_center(),path):return true
	return false

static func _raw_points(item: Dictionary) -> PackedVector2Array:
	var points:=PackedVector2Array()
	for p in item.get("points",[]):points.append(Vector2(float(p.x),float(p.y)))
	return points

static func collect(doc: Dictionary, area: Rect2, layers: Dictionary,
		prop_size: Callable, road_path: Callable) -> Array[String]:
	# Called once on release, not during every mouse-motion event.
	var result: Array[String]=[]
	if not area.has_area():return result
	if bool(layers.get("scenery",true)):
		for prop in doc.get("props",[]):
			if bool(prop.get("hidden",false)):continue
			var center:=Vector2(float(prop.x),float(prop.y))
			var size: Vector2=prop_size.call(prop)
			var angle:=deg_to_rad(float(prop.get("rotation",0.0)))
			var half:=size*.5
			var aabb_half:=Vector2(absf(cos(angle))*half.x+absf(sin(angle))*half.y,
				absf(sin(angle))*half.x+absf(cos(angle))*half.y)
			if area.intersects(Rect2(center-aabb_half,aabb_half*2),true):
				result.append(str(prop.id))
	if bool(layers.get("markers",true)):
		for marker in doc.get("markers",[]):
			if bool(marker.get("hidden",false)):continue
			if area.grow(0.5).has_point(Vector2(float(marker.x),float(marker.y))):
				result.append(str(marker.id))
	if bool(layers.get("roads",true)):
		for road in doc.get("roads",[]):
			if bool(road.get("hidden",false)):continue
			var path: PackedVector2Array=road_path.call(road)
			if _path_touches(area,path,false):result.append(str(road.id))
	if bool(layers.get("terrain",true)):
		for region in doc.get("regions",[]):
			if bool(region.get("hidden",false)):continue
			if _path_touches(area,_raw_points(region),true):result.append(str(region.id))
	if bool(layers.get("markers",true)):
		for race in doc.get("races",[]):
			if bool(race.get("hidden",false)):continue
			if _path_touches(area,_raw_points(race),str(race.get("mode",""))=="circuit"):
				result.append(str(race.id))
	return result

static func _categories(doc: Dictionary, ids: Array[String]) -> Dictionary:
	var selection: Dictionary={}
	for id in ids:
		if id.is_empty() or selection.has(id):continue
		for category in CATEGORIES:
			for item in doc.get(category,[]):
				if str(item.get("id",""))==id and not bool(item.get("hidden",false)):
					selection[id]=category
					break
			if selection.has(id):break
		if not selection.has(id):return {}
	return selection

static func move(session, ids: Array[String], delta: Vector2) -> bool:
	if ids.is_empty() or not delta.is_finite() or delta.length()>350.0:
		session.last_error="Move exceeds 350 m or has no selected objects."
		return false
	var original: Dictionary=session.doc
	var picked: Dictionary=_categories(original,ids)
	if picked.size()!=ids.size():
		session.last_error="Selection contains an unavailable or hidden object."
		return false
	var next: Dictionary=original.duplicate(true)
	var moved_road_ends: Array[Dictionary]=[]
	var moved_sidewalk_nodes: Array[Vector2]=[]
	for category in CATEGORIES:
		for item in next.get(category,[]):
			var id:=str(item.id)
			if not picked.has(id):continue
			if category=="roads":
				var previous: Dictionary={}
				for source in original.roads:
					if str(source.id)==id:previous=source;break
				if not bool(item.get("independentEnds",false)):
					var ends: Array=previous.points
					var circle: Dictionary=Roads.circle(ends)
					if not circle.is_empty():
						for p in ends:moved_road_ends.append({"point":Vector2(p.x,p.y),"road":previous})
					else:
						for point in [ends[0],ends[-1]]:
							moved_road_ends.append({"point":Vector2(point.x,point.y),"road":previous})
			if category=="props" and str(item.get("type",""))=="sidewalk":
				for p in Sidewalks.world_points(item):moved_sidewalk_nodes.append(p)
			if item.has("points"):
				for p in item.points:
					p.x=float(p.x)+delta.x;p.y=float(p.y)+delta.y
			else:
				item.x=float(item.x)+delta.x;item.y=float(item.y)+delta.y
	# Keep linked endpoints of unselected neighboring roads attached once,
	# including when two or more selected roads share the same junction.
	for road in next.roads:
		if picked.has(str(road.id)) or bool(road.get("independentEnds",false)):continue
		for index in [0,road.points.size()-1]:
			var p: Dictionary=road.points[index]
			var current:=Vector2(float(p.x),float(p.y))
			for target in moved_road_ends:
				if session._same_network(target.road,road) and current.distance_to(target.point)<.05:
					p.x=float(p.x)+delta.x;p.y=float(p.y)+delta.y
					break
	# The sidewalk path is stored relative to its center; moving the prop
	# already moves all its points. Weld unselected branches at shared nodes.
	for prop in next.props:
		if picked.has(str(prop.id)) or bool(prop.get("hidden",false)) or str(prop.get("type",""))!="sidewalk":
			continue
		var path: Array[Vector2]=Sidewalks.world_points(prop)
		var joined:=false
		for i in path.size():
			for old in moved_sidewalk_nodes:
				if path[i].distance_to(old)<.05:
					path[i]+=delta;joined=true;break
		if joined:Sidewalks.write_world_points(prop,path)
	if not session._commit(next):
		return false
	return true

static func duplicate(session, ids: Array[String]) -> Array[String]:
	var created: Array[String]=[]
	var picked: Dictionary=_categories(session.doc,ids)
	if ids.is_empty() or picked.size()!=ids.size():
		session.last_error="Select existing editable objects before duplication."
		return created
	var next: Dictionary=session.doc.duplicate(true)
	var used: Dictionary={}
	for category in CATEGORIES:
		used[category]={}
		for item in next.get(category,[]):used[category][str(item.id)]=true
	for category in CATEGORIES:
		var sources: Array=session.doc.get(category,[])
		for item in sources:
			if not picked.has(str(item.id)):continue
			if category=="markers" and str(item.get("type","")) not in ["checkpoint","race_start","finish","traffic_spawn"]:
				session.last_error="This gameplay marker cannot be duplicated."
				return []
			var prefix: String={"roads":"road","regions":"region","props":"prop","markers":"marker","races":"race"}[category]
			var counter:=0
			while used[category].has("%s-%d"%[prefix,counter]):counter+=1
			var new_id: String="%s-%d"%[prefix,counter]
			used[category][new_id]=true
			var copy: Dictionary=item.duplicate(true)
			copy.id=new_id
			copy.name=str(item.get("name",prefix))+" copy"
			copy.erase("replaces")
			copy.erase("hidden")
			if copy.has("points"):
				for p in copy.points:
					p.x=float(p.x)+12.0;p.y=float(p.y)+12.0
			else:
				copy.x=float(copy.x)+12.0;copy.y=float(copy.y)+12.0
			next[category].append(copy)
			created.append(new_id)
	if not session._commit(next):return []
	return created

static func delete(session, ids: Array[String]) -> bool:
	var picked: Dictionary=_categories(session.doc,ids)
	if ids.is_empty() or picked.size()!=ids.size():
		session.last_error="No editable objects selected."
		return false
	var next: Dictionary=session.doc.duplicate(true)
	for category in CATEGORIES:
		if not bool(session.doc.get("customMap",false)) and category in ["roads","regions","markers"]:
			for item in session.initial.get(category,[]):
				if picked.has(str(item.id)):
					session.last_error="Original roads, terrain and gameplay markers are protected."
					return false
		var remaining: Array=[]
		for item in next.get(category,[]):
			if not picked.has(str(item.id)):
				remaining.append(item)
			elif category=="props" and item.has("replaces"):
				item.hidden=true
				remaining.append(item)
		next[category]=remaining
	for i in next.roads.size():next.roads[i].id="road-%d"%i
	return session._commit(next)

static func arrange_props(session, ids: Array[String], mode: String) -> bool:
	if ids.size()<2 or mode not in ["left","top","horizontal"]:
		session.last_error="Select two or more scenery assets."
		return false
	var picked: Dictionary=_categories(session.doc,ids)
	if picked.size()!=ids.size():
		session.last_error="Some selected assets are unavailable."
		return false
	for category in picked.values():
		if category!="props":
			session.last_error="Alignment applies to scenery props only."
			return false
	var next: Dictionary=session.doc.duplicate(true)
	var selected: Array[Dictionary]=[]
	for item in next.props:
		if picked.has(str(item.id)):
			if str(item.get("type",""))=="sidewalk":
				session.last_error="Align buildings/scenery, not joined sidewalks."
				return false
			selected.append(item)
	if selected.size()<2:return false
	if mode in ["left","top"]:
		var axis:= "x" if mode=="left" else "y"
		var minimum:=INF
		for item in selected:minimum=minf(minimum,float(item[axis]))
		for item in selected:item[axis]=minimum
	else:
		if selected.size()<3:
			session.last_error="Distribute horizontally needs three or more objects."
			return false
		selected.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a.x)<float(b.x))
		var start:=float(selected[0].x)
		var gap: float=(float(selected[-1].x)-start)/float(selected.size()-1)
		for i in range(1,selected.size()-1):selected[i].x=start+gap*i
	return session._commit(next)
