extends RefCounted
## Deterministic source-only city construction. The session validates and
## commits the entire plan at once; never mutate the live runtime archive.
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const Height=preload("res://scripts/world/authored_height_field.gd")
const Contracts=preload("res://scripts/world/driving_contract_rules.gd")
const DealerConfig=preload("res://scripts/world/dealership_config.gd")
const PALETTES={"residential":["house","house","coastal_house"],"commercial":["shop","shop","garage"],
	"industrial":["garage","garage","warehouse"],"downtown":["shop","warehouse","shop"]}
const BLOCKED=["ocean","lake","water","river","reservoir","mountain","rock"]
const SIZES={"house":Vector2(12,17),"coastal_house":Vector2(12,17),"shop":Vector2(22,29),
	"garage":Vector2(20,21),"warehouse":Vector2(28,37),"tree":Vector2(7,7),
	"streetlight":Vector2(1.3,1.3),"sign":Vector2(1.6,1.4),"pine":Vector2(7,7),"palm":Vector2(6.5,6.5),"bush":Vector2(2.5,2.5),"parking":Vector2(38,28),"gas_station":Vector2(18,17),"building":Vector2(22,29)}
const CELL:=48.0

static func _point(p: Vector2) -> Dictionary:return {"x":p.x,"y":p.y}
static func _error(message: String) -> Dictionary:return {"error":message}
static func _road(id: int,a: Vector2,b: Vector2,width: float,lanes: int,alley: bool=false) -> Dictionary:
	return {"id":"road-%d"%id,"name":"Generated alley" if alley else "Generated city street",
		"roadClass":"alley" if alley else "city","surface":"asphalt","width":width,
		"lanes":lanes,"shoulder":0 if alley else 2,"smooth":false,"markings":not alley,
		"points":[_point(a),_point(b)]}

static func _prop(kind: String,position: Vector2,rotation: float,scale: float) -> Dictionary:
	var art: Dictionary=Session.ART.get(kind,{})
	return {"name":"Generated "+kind,"type":str(art.get("type",kind)),"assetId":str(art.get("assetId","")),
		"x":position.x,"y":position.y,"rotation":rotation,"scale":scale}

static func _bounds(points: PackedVector2Array) -> Rect2:
	var rect:=Rect2(points[0],Vector2.ZERO)
	for p in points:rect=rect.expand(p)
	return rect

static func _prop_radius(prop: Dictionary) -> float:
	var size:=Vector2(30,40)
	if prop.has("assetSize") and prop.assetSize is Array and prop.assetSize.size()==2:
		size=Vector2(float(prop.assetSize[0]),float(prop.assetSize[1]))
	else:
		for kind in SIZES:
			var art: Dictionary=Session.ART.get(kind,{})
			if str(art.get("type",kind))==str(prop.get("type","")):size=SIZES[kind];break
	return size.length()*.5*absf(float(prop.get("scale",1)))*maxf(absf(float(prop.get("scaleX",1))),absf(float(prop.get("scaleY",1))))

static func _keys(rect: Rect2) -> Array[Vector2i]:
	var keys: Array[Vector2i]=[]
	var first:=Vector2i((rect.position/CELL).floor())
	var last:=Vector2i((rect.end/CELL).floor())
	for x in range(first.x,last.x+1):
		for y in range(first.y,last.y+1):keys.append(Vector2i(x,y))
	return keys

static func _index(doc: Dictionary) -> Dictionary:
	var index: Dictionary={}
	for road in doc.roads:
		var path:=Session.road_path(road)
		var pad:=float(road.width)*.5+float(road.get("shoulder",2))+2.0
		for i in range(1,path.size()):
			var a:=path[i-1];var b:=path[i]
			for key in _keys(Rect2(a,b-a).abs().grow(pad)):
				if not index.has(key):index[key]=[]
				index[key].append({"a":a,"b":b,"pad":pad})
	for prop in doc.props+doc.get("_runtime_blockers",[]):
		if bool(prop.get("hidden",false)):continue
		var p:=Vector2(prop.x,prop.y);var r:=_prop_radius(prop)
		for key in _keys(Rect2(p-Vector2.ONE*r,Vector2.ONE*r*2)):
			if not index.has(key):index[key]=[]
			index[key].append({"p":p,"radius":r})
	return index

static func _blocked_terrain(doc: Dictionary,area: Rect2) -> bool:
	if str(doc.world.get("base","grass")) in BLOCKED:return true
	for region in doc.regions:
		if str(region.get("biome","")) not in BLOCKED and not bool(region.get("barrier",false)):continue
		var polygon:=PackedVector2Array()
		for p in region.points:polygon.append(Vector2(p.x,p.y))
		if polygon.size()>=3 and _bounds(polygon).intersects(area,true):
			var rectangle:=PackedVector2Array([area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)])
			if not Geometry2D.intersect_polygons(polygon,rectangle).is_empty():return true
	return false

static func _free(index: Dictionary,p: Vector2,r: float) -> bool:
	for key in _keys(Rect2(p-Vector2.ONE*r,Vector2.ONE*r*2)):
		for item in index.get(key,[]):
			if item.has("a"):
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p,item.a,item.b))<r+float(item.pad):return false
			elif p.distance_to(item.p)<r+float(item.radius):return false
	return true

static func _place(doc: Dictionary,index: Dictionary,props: Array,kind: String,p: Vector2,angle: float,scale: float,limit: int) -> bool:
	if doc.props.size()+props.size()>=limit:return false
	var prop:=_prop(kind,p,angle,scale)
	var radius:=_prop_radius(prop)+2.0
	var box:=Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2)
	var world:=Rect2(Vector2(3,3),Vector2(doc.world.width,doc.world.height)-Vector2(6,6))
	if not world.encloses(box) or _blocked_terrain(doc,box) or not _free(index,p,radius):return false
	props.append(prop)
	for key in _keys(box):
		if not index.has(key):index[key]=[]
		index[key].append({"p":p,"radius":radius})
	return true

static func _next_road(doc: Dictionary) -> int:
	var next:=0
	for road in doc.roads:next=maxi(next,int(str(road.id).trim_prefix("road-"))+1)
	return next

static func plan_grid(doc: Dictionary,center: Vector2,settings: Dictionary,road_limit: int,prop_limit: int) -> Dictionary:
	if not doc.get("customMap",false) and not bool(settings.get("connect",false)):return _error("Morrow Coast grids must connect to an existing road.")
	var columns:=int(settings.get("columns",3));var rows:=int(settings.get("rows",3))
	var block:=float(settings.get("block",120));var width:=float(settings.get("width",12))
	var lanes:=int(settings.get("lanes",2));var alleys:=bool(settings.get("alleys",false))
	if columns<1 or rows<1 or columns>12 or rows>12 or block<70 or block>300 or width<8 or width>24 or lanes<1 or lanes>4:return _error("Invalid block or street dimensions.")
	var extent:=Vector2(columns,rows)*block
	var area:=Rect2(center-extent*.5,extent)
	var margin:=width*.5+5
	var reserved:=area.grow(margin)
	if not Rect2(Vector2.ZERO,Vector2(doc.world.width,doc.world.height)).encloses(reserved):return _error("Move the city grid farther inside the map.")
	if _blocked_terrain(doc,reserved):return _error("The grid overlaps water, rock or mountain terrain.")
	# Conservative empty-area rule: never erase existing geometry, or create
	# surprise parallel roads through an existing district.
	for road in doc.roads:
		if _bounds(Session.road_path(road)).grow(float(road.width)*.5+3).intersects(reserved,true):return _error("Choose an empty area away from existing roads.")
	for prop in doc.props+doc.get("_runtime_blockers",[]):
		if bool(prop.get("hidden",false)):continue
		var p:=Vector2(prop.x,prop.y);var r:=_prop_radius(prop)
		if Rect2(p-Vector2.ONE*r,Vector2.ONE*r*2).intersects(reserved,true):return _error("Choose an area without existing scenery.")
	var roads: Array=[]
	var id:=_next_road(doc)
	for x in columns+1:
		var at:=area.position+Vector2(x*block,0)
		roads.append(_road(id,at,at+Vector2(0,extent.y),width,lanes));id+=1
	for y in rows+1:
		var at:=area.position+Vector2(0,y*block)
		roads.append(_road(id,at,at+Vector2(extent.x,0),width,lanes));id+=1
	if alleys:
		for y in rows:
			var at:=area.position+Vector2(0,(y+.5)*block)
			roads.append(_road(id,at,at+Vector2(extent.x,0),6,1,true));id+=1
	if doc.roads.size()+roads.size()>road_limit:return _error("Not enough remaining road capacity.")
	if bool(settings.get("connect",false)):
		var link:=_grid_link(doc,roads,area,width,lanes,id)
		if link.is_empty():return _error("No clear, compatible ground road endpoint within 300 m of the grid.")
		roads.append(link)
		if doc.roads.size()+roads.size()>road_limit:return _error("Not enough room for the grid connector.")
	var draft:=doc.duplicate(false)
	draft.roads=doc.roads+roads
	var props: Array=[]
	if bool(settings.get("buildings",true)):
		var index:=_index(draft)
		var rng:=RandomNumberGenerator.new();rng.seed=int(settings.get("seed",1847))
		var palette: Array=PALETTES.get(str(settings.get("district","residential")),PALETTES.residential)
		var density:=clampf(float(settings.get("density",.7)),0,1)
		for y in rows:
			for x in columns:
				var base:=area.position+Vector2(x,y)*block
				var count:=maxi(1,floori((block-30)/38))
				for side in [0,1]:
					for n in count:
						if rng.randf()>density:continue
						var kind: String=palette[rng.randi_range(0,palette.size()-1)]
						var scale:=rng.randf_range(.85,1.1)
						var setback: float=width*.5+8+Vector2(SIZES[kind]).length()*.5*scale
						var p:=base+Vector2((n+.5)*block/count,setback if side==0 else block-setback)
						_place(draft,index,props,kind,p,0.0 if side==0 else 180.0,scale,prop_limit)
	if bool(settings.get("sidewalks",false)):
		for y in rows:
			for x in columns:
				var base:=area.position+Vector2(x,y)*block
				var inset:=width*.5+3.5
				var corner:=width*.5+8.0
				for dy in [inset,block-inset]:
					props.append(_walk(base+Vector2(corner,dy),base+Vector2(block-corner,dy)))
				for dx in [inset,block-inset]:
					if alleys:
						props.append(_walk(base+Vector2(dx,corner),base+Vector2(dx,block*.5-7)))
						props.append(_walk(base+Vector2(dx,block*.5+7),base+Vector2(dx,block-corner)))
					else:props.append(_walk(base+Vector2(dx,corner),base+Vector2(dx,block-corner)))
		if doc.props.size()+props.size()>prop_limit:return _error("Not enough scenery capacity for the sidewalks.")
	var regions: Array=[]
	if bool(settings.get("plots",false)):
		if doc.regions.size()+columns*rows>220:return _error("Building plots exceed terrain region capacity.")
		var inset:=width*.5+6
		for y in rows:
			for x in columns:
				var p:=area.position+Vector2(x,y)*block+Vector2.ONE*inset
				var size:=Vector2.ONE*(block-2*inset)
				regions.append({"name":"Building plot","biome":"city","points":[_point(p),_point(p+Vector2(size.x,0)),_point(p+size),_point(p+Vector2(0,size.y))]})
	return {"roads":roads,"props":props,"regions":regions,"area":area,"label":"City grid"}

static func plan_district(doc: Dictionary,center: Vector2,settings: Dictionary,prop_limit: int) -> Dictionary:
	var size:=Vector2(clampi(int(settings.get("columns",3)),1,12),clampi(int(settings.get("rows",3)),1,12))*clampf(float(settings.get("block",120)),70,300)
	var area:=Rect2(center-size*.5,size)
	if not Rect2(Vector2.ZERO,Vector2(doc.world.width,doc.world.height)).encloses(area):return _error("District area crosses map bounds.")
	var index:=_index(doc)
	var props: Array=[]
	var rng:=RandomNumberGenerator.new();rng.seed=int(settings.get("seed",1847))
	var palette: Array=PALETTES.get(str(settings.get("district","residential")),PALETTES.residential)
	var density:=clampf(float(settings.get("density",.7)),0,1)
	var step:=30.0 if str(settings.get("district",""))=="residential" else 48.0
	for y in range(floori(size.y/step)):
		for x in range(floori(size.x/step)):
			if rng.randf()>density:continue
			var kind: String=palette[rng.randi_range(0,palette.size()-1)]
			var p:=area.position+Vector2(x+.5,y+.5)*step
			_place(doc,index,props,kind,p,float(rng.randi_range(0,3)*90),rng.randf_range(.85,1.1),prop_limit)
	return {"roads":[],"props":props,"area":area,"label":"District"}

static func plan_roadside(doc: Dictionary,road_id: String,settings: Dictionary,prop_limit: int) -> Dictionary:
	var road: Dictionary={}
	for item in doc.roads:
		if str(item.id)==road_id:road=item;break
	if road.is_empty():return _error("Select one road before opening roadside construction.")
	if road.has("elevation") or road.has("jump"):return _error("Roadside generation currently requires a ground-level road without jumps.")
	var index:=_index(doc);var props: Array=[]
	var path:=Session.road_path(road)
	var spacing:=clampf(float(settings.get("spacing",40)),15,150)
	var kind:=str(settings.get("decoration","streetlight"))
	if kind not in ["streetlight","tree","sign"]:return _error("Unsupported decoration.")
	var offset: float=float(road.width)*.5+float(road.get("shoulder",2))+Vector2(SIZES[kind]).length()*.5+5.0
	var station:=spacing*.5;var travelled:=0.0
	for i in range(1,path.size()):
		var a:=path[i-1];var b:=path[i]
		var span:=a.distance_to(b)
		if span<.001:continue
		var tangent: Vector2=(b-a)/span
		while station<=travelled+span:
			var p:=a+tangent*(station-travelled)
			for side in [-1,1]:
				_place(doc,index,props,kind,p+tangent.orthogonal()*offset*side,rad_to_deg(tangent.angle()),1.0,prop_limit)
			station+=spacing
		travelled+=span
	return {"roads":[],"props":props,"area":_bounds(path),"label":"Roadside decoration"}

static func _walk(a: Vector2,b: Vector2) -> Dictionary:
	var center: Vector2=(a+b)*.5
	var extent: Vector2=(b-a).abs()+Vector2.ONE*2.0
	return {"name":"Block sidewalk","type":"sidewalk","assetId":"","x":center.x,"y":center.y,
		"rotation":0.0,"scale":1.0,"assetSize":[extent.x,extent.y],"sidewalkWidth":2.0,
		"sidewalkPoints":[[a.x-center.x,a.y-center.y],[b.x-center.x,b.y-center.y]]}

static func _grid_link(doc: Dictionary,roads: Array,area: Rect2,width: float,lanes: int,id: int) -> Dictionary:
	var index:=_index(doc)
	var best:=300.0
	var result: Dictionary={}
	for old in doc.roads:
		if old.has("elevation") or old.has("jump") or str(old.surface) in ["gravel","dirt"]:continue
		for end in [0,old.points.size()-1]:
			var p:=Vector2(old.points[end].x,old.points[end].y)
			var neighbour: int=1 if end==0 else old.points.size()-2
			var outward: Vector2=(p-Vector2(old.points[neighbour].x,old.points[neighbour].y)).normalized()
			for road in roads:
				if road.roadClass=="alley":continue
				for raw in road.points:
					var q:=Vector2(raw.x,raw.y)
					var delta:=q-p
					var distance:=delta.length()
					if distance<30 or distance>=best or delta.normalized().dot(outward)<.8:continue
					var entry: Vector2=q-delta.normalized()*15
					if area.has_point(entry):continue
					var clear:=true
					var steps:=ceili(distance/5.0)
					for i in range(1,steps):
						var at:=p.lerp(q,float(i)/steps)
						if at.distance_to(p)<maxf(width,float(old.width))+8:continue
						if not _free(index,at,width*.5+2) or _blocked_terrain(doc,Rect2(at-Vector2.ONE*width*.5,Vector2.ONE*width)):
							clear=false;break
					if clear:
						best=distance;result=_road(id,p,q,width,lanes)
	return result

static func _vacant(doc: Dictionary,area: Rect2) -> bool:
	if not Rect2(Vector2.ZERO,Vector2(doc.world.width,doc.world.height)).encloses(area) or _blocked_terrain(doc,area):return false
	for road in doc.roads:
		if _bounds(Session.road_path(road)).grow(float(road.width)*.5+4).intersects(area,true):return false
	for prop in doc.props+doc.get("_runtime_blockers",[]):
		if bool(prop.get("hidden",false)):continue
		var p:=Vector2(prop.x,prop.y);var radius:=_prop_radius(prop)
		if Rect2(p-Vector2.ONE*radius,Vector2.ONE*radius*2).intersects(area,true):return false
	return true

static func _grade_road(id: int,a: Vector2,b: Vector2,width: float,lanes: int,start: int,end: int,name: String) -> Dictionary:
	var road:=_road(id,a,b,width,lanes)
	road.name=name
	if start!=0 or end!=0:road.elevation={"start_layer":start,"end_layer":end}
	return road

static func plan_interchange(doc: Dictionary,center: Vector2,settings: Dictionary,limit: int) -> Dictionary:
	if not doc.get("customMap",false):return _error("Use a custom map for interchange generation.")
	var span:=clampf(float(settings.get("interchange_span",240)),180,500)
	var style:=str(settings.get("interchange","diamond"))
	if style not in ["diamond","half diamond","three way","cloverleaf foundation","trumpet foundation","directional foundation"]:return _error("Unknown interchange template.")
	var area:=Rect2(center-Vector2.ONE*(span+35),Vector2.ONE*(span+35)*2)
	if not _vacant(doc,area):return _error("Interchange needs a clear area inside the map.")
	var roads: Array=[]
	var id:=_next_road(doc)
	var left:=center+Vector2(-span,0);var right:=center+Vector2(span,0)
	var main:=_grade_road(id,left,right,24,4,1,1,"Elevated highway")
	main.roadClass="highway";roads.append(main);id+=1
	var north:=center+Vector2(0,-span);var south:=center+Vector2(0,span)
	var local_end:=center if style in ["three way","trumpet foundation"] else south
	roads.append(_grade_road(id,north,local_end,12,2,0,0,"Cross street"));id+=1
	var ends: Array=[north] if style in ["half diamond","three way","trumpet foundation"] else [north,south]
	for target in ends:
		for origin in [left,right]:
			var connector:=_grade_road(id,origin,target,8,2,1,0,"Grade connector")
			var sx: float=signf(Vector2(origin-center).x);var sy: float=signf(Vector2(target-center).y)
			if style in ["cloverleaf foundation","directional foundation","trumpet foundation"]:
				connector.points=[_point(origin),_point(center+Vector2(sx*.83,sy*.48)*span),
					_point(center+Vector2(sx*.48,sy*.83)*span),_point(target)]
				connector.smooth=true
			roads.append(connector);id+=1
			if style=="cloverleaf foundation" or (style=="trumpet foundation" and sx>0):
				var loop_start:=center+Vector2(sx*.42,0)*span
				var loop_end:=center+Vector2(0,sy*.42)*span
				var loop:=_grade_road(id,loop_start,loop_end,8,2,1,0,"Loop grade connector")
				loop.points=[_point(loop_start),_point(center+Vector2(sx*.62,sy*.14)*span),
					_point(center+Vector2(sx*.60,sy*.36)*span),_point(center+Vector2(sx*.35,sy*.58)*span),
					_point(center+Vector2(sx*.12,sy*.58)*span),_point(loop_end)]
				loop.smooth=true;roads.append(loop);id+=1
	if doc.roads.size()+roads.size()>limit:return _error("Not enough remaining road capacity.")
	return {"roads":roads,"props":[],"area":area,"label":style.capitalize()+" interchange"}

const PROPERTY_ART={"convenience store":"Map Building Assets/Robbery Buildings/Convenience Stores/Convenience1.png",
	"pawn shop":"Map Building Assets/Robbery Buildings/Pawn Shops/PawnShop1.png",
	"jewelry store":"Map Building Assets/Robbery Buildings/Jewelry store/Jewelry Store1.png",
	"bank":"Map Building Assets/Robbery Buildings/Banks/Bank1.png"}
const PROPERTY_TIERS={"convenience store":"convenience","pawn shop":"pawn","jewelry store":"jewelry","bank":"bank"}

static func _marker(id: String,kind: String,name: String,p: Vector2,properties: Dictionary={}) -> Dictionary:
	return {"id":id,"type":kind,"name":name,"x":p.x,"y":p.y,"rotation":0.0,"properties":properties}

static func _next_marker(doc: Dictionary) -> int:
	var next:=0
	for marker in doc.markers:
		var suffix:=str(marker.id).trim_prefix("marker-")
		if suffix.is_valid_int():next=maxi(next,int(suffix)+1)
	return next

## A complete roadside site, anchored to an existing straight ground street.
## A generous setback keeps building, lot and driveway out of the roadway.
static func plan_property(doc: Dictionary,road_id: String,center: Vector2,settings: Dictionary,road_limit: int,prop_limit: int) -> Dictionary:
	var kind:=str(settings.get("property","fuel station"))
	if kind not in ["fuel station","garage","shopping center","convenience store","pawn shop","jewelry store","bank","dealership"]:
		return _error("Unknown property kit.")
	var road: Dictionary={}
	for item in doc.roads:
		if str(item.id)==road_id:road=item;break
	if road.is_empty() or road.has("elevation") or road.has("jump") or str(road.get("surface","")) in ["gravel","dirt"] or road.points.size()!=2:
		return _error("Select a straight paved ground-level road before placing a property kit.")
	var a:=Vector2(road.points[0].x,road.points[0].y)
	var b:=Vector2(road.points[1].x,road.points[1].y)
	var length:=a.distance_to(b)
	var robbery:=PROPERTY_TIERS.has(kind)
	var margin:=160.0 if robbery else 45.0
	if length<margin*2+10:return _error("Select a longer road to fit this property and its objectives.")
	var tangent: Vector2=(b-a)/length
	var station:=clampf((center-a).dot(tangent),margin,length-margin)
	var access: Vector2=a+tangent*station
	var normal: Vector2=tangent.orthogonal()
	if (center-access).dot(normal)<0:normal=-normal
	var road_edge:=float(road.width)*.5+float(road.get("shoulder",2))
	var lot_center:=access+normal*(road_edge+34.0)
	var building_center:=access+normal*(road_edge+82.0)
	var angle:=rad_to_deg(normal.angle())+90.0
	angle=wrapf(angle,-180,180)
	var props: Array=[]
	var index:=_index(doc)
	var lot:=_prop("parking",lot_center,wrapf(rad_to_deg(normal.angle()),-180,180),1.0)
	lot.name=kind.capitalize()+" parking"
	var building_type: String={"fuel station":"gas_station","garage":"garage","shopping center":"building","dealership":"building"}.get(kind,"building")
	var building:=_prop(building_type,building_center,angle,1.0)
	building.name=kind.capitalize()
	# Use actual shipped robbery-building artwork, with canonical project
	# identifiers. A missing file falls back to ordinary shop art.
	if PROPERTY_ART.has(kind):
		var relative: String=PROPERTY_ART[kind]
		if FileAccess.file_exists("res://assets/"+relative):
			building.assetPath=relative
			building.assetId="project-"+relative.sha256_text().substr(0,24)
			building.assetSize=[22.0,29.0]
			building.assetCollision="solid"
			building.type="building"
	var extent:=Rect2(access,Vector2.ZERO).expand(lot_center).expand(building_center).grow(25)
	var bounds:=Rect2(Vector2(3,3),Vector2(doc.world.width,doc.world.height)-Vector2(6,6))
	if not bounds.encloses(extent) or _blocked_terrain(doc,extent):return _error("Property footprint crosses map bounds or restricted terrain.")
	# Check actual intended footprints rather than the entire site rectangle
	# against the frontage road, where a driveway is supposed to connect.
	for candidate in [lot,building]:
		var p:=Vector2(candidate.x,candidate.y)
		if not _free(index,p,_prop_radius(candidate)+2):return _error("Property overlaps existing roads or scenery.")
	var end: Vector2=lot_center+normal*8.0
	var span:=access.distance_to(end)
	for i in range(1,ceili(span/3.0)+1):
		var p:=access.lerp(end,minf(1.0,float(i)*3.0/span))
		if p.distance_to(access)>road_edge+10 and not _free(index,p,4):return _error("Driveway is obstructed.")
	props.append(lot)
	if kind!="dealership":props.append(building)
	for side in [-1,1]:
		var lamp: Vector2=lot_center+tangent*float(side)*24.0
		_place(doc,index,props,"streetlight",lamp,angle,1.0,prop_limit)
	var roads: Array=[_road(_next_road(doc),access,end,8,1)]
	roads[0].roadClass="service";roads[0].name=kind.capitalize()+" access"
	var markers: Array=[]
	var dealers: Array=[]
	var number:=_next_marker(doc)
	var marker_id: String="marker-%d"%number
	if robbery:
		var target_id:=marker_id
		var contact_id: String="marker-%d"%(number+1)
		var drop_id: String="marker-%d"%(number+2)
		var contact:=access-tangent*150.0
		var drop:=access+tangent*150.0
		markers.append(_marker(target_id,"robbery_target",kind.capitalize(),end))
		markers.append(_marker(drop_id,"contract_dropoff","Getaway drop-off",drop))
		markers.append(_marker(contact_id,"contract_contact",kind.capitalize()+" contact",contact,
			{"contact_style":"street","offers":[Contracts.make_robbery_offer(str(PROPERTY_TIERS[kind]),target_id,drop_id)]}))
	elif kind=="fuel station":
		markers.append(_marker(marker_id,"fuel","Fuel station",end))
	elif kind=="garage":
		markers.append(_marker(marker_id,"garage","Garage",end))
	elif kind=="dealership":
		var used: Dictionary={}
		for dealer in DealerConfig.combined(doc):used[str(dealer.id)]=true
		if used.size()>=DealerConfig.MAX_SHOPS:return _error("Dealership limit reached.")
		var n:=1
		while used.has("custom-dealer-%d"%n):n+=1
		var dealer_id: String="custom-dealer-%d"%n
		var defaults:=DealerConfig.defaults()
		if defaults.size()<4:return _error("Dealership artwork configuration is missing.")
		var inventory: Array=[]
		for car in DealerConfig.available_inventory(defaults[3]):inventory.append(str(car.id))
		dealers.append({"id":dealer_id,"name":"Generated dealership","tier":"CUSTOM SHOWROOM","region":"Custom location",
			"texture":str(defaults[3].texture),"x":building_center.x,"y":building_center.y,
			"lot_width_m":32.0,"lot_depth_m":20.0,"inventory_mode":"manual","inventory":inventory})
		markers.append(_marker(marker_id,"dealership","Dealership",end,{"dealer_id":dealer_id}))
	else:
		markers.append(_marker(marker_id,"custom","Shopping center",end))
	if doc.roads.size()+roads.size()>road_limit or doc.props.size()+props.size()>prop_limit or doc.markers.size()+markers.size()>400:
		return _error("Property kit exceeds map capacity.")
	return {"roads":roads,"props":props,"markers":markers,"dealerships":dealers,"area":extent,"label":kind.capitalize()+" kit"}

## Landscaping tools use the existing spatial clearance index and source
## transactions. No generated plant can occupy a road or an exclusion region.
static func plan_vegetation(doc: Dictionary,center: Vector2,radius: float,density: float,kind: String,seed: int,limit: int) -> Dictionary:
	if kind not in ["tree","pine","palm","bush"]:return _error("Choose a vegetation asset.")
	radius=clampf(radius,5,500)
	var count:=mini(800,roundi(PI*radius*radius/100.0*clampf(density,0,1)))
	var rng:=RandomNumberGenerator.new();rng.seed=seed
	var index:=_index(doc)
	var props: Array=[]
	for i in count:
		var p:=center+Vector2.RIGHT.rotated(rng.randf_range(0,TAU))*radius*sqrt(rng.randf())
		_place(doc,index,props,kind,p,rng.randf_range(-180,180),rng.randf_range(.65,1.3),limit)
	return {"roads":[],"props":props,"label":"Vegetation brush"}

static func plan_river(doc: Dictionary,points: Array[Vector2],width: float,bank: float,depth: float) -> Dictionary:
	if points.size()<2 or points.size()>60:return _error("River needs 2–60 centreline points.")
	width=clampf(width,6,160);bank=clampf(bank,2,80)
	for i in range(1,points.size()):
		if points[i].distance_to(points[i-1])<width*.5:return _error("Spread river points farther apart.")
	var line:=PackedVector2Array(points)
	var outer:=Geometry2D.offset_polyline(line,width*.5+bank,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND)
	var inner:=Geometry2D.offset_polyline(line,width*.5,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND)
	if outer.size()!=1 or inner.size()!=1 or outer[0].size()>180 or inner[0].size()>180:return _error("River shape is too complex; shorten or simplify its centreline.")
	var area:=_bounds(outer[0])
	# A conservative initial rule: prevent flooded pavement, scenery or existing
	# restricted terrain. Bridges must be separately authored and validated.
	if not _vacant(doc,area):return _error("River corridor overlaps existing roads, scenery, restricted terrain or map boundary.")
	var regions: Array=[]
	for i in 2:
		var polygon: PackedVector2Array=outer[0] if i==0 else inner[0]
		if Geometry2D.triangulate_polygon(polygon).is_empty():return _error("River polygon is invalid.")
		var vertices: Array=[]
		for p in polygon:vertices.append(_point(p))
		regions.append({"name":"River bank" if i==0 else "River channel","biome":"beach" if i==0 else "lake","points":vertices,"elevation":0})
	var field: Dictionary=doc.get("terrainHeight",Height.blank()).duplicate(true)
	var extent:=Vector2(doc.world.width,doc.world.height)
	# Carve visual banks and channel with a continuous falloff.
	var step:=extent/float(Height.N-1)
	for y in Height.N:
		for x in Height.N:
			var p:=Vector2(x,y)*step
			var d:=width*.5+bank
			for i in range(1,line.size()):d=minf(d,p.distance_to(Geometry2D.get_closest_point_to_segment(p,line[i-1],line[i])))
			var weight:=1.0-smoothstep(width*.5,width*.5+bank,d)
			if weight<=0:continue
			var n:=y*Height.N+x
			field.values[n]=snappedf(lerpf(float(field.values[n]),-absf(depth),weight),.1)
	return {"roads":[],"props":[],"regions":regions,"terrainHeight":field,"area":area,"label":"River"}
