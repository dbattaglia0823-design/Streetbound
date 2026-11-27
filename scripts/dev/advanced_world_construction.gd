extends RefCounted
## Deterministic editable neighborhoods. All dimensions are metres. The
## existing City planner and Session own clearance and undo transactions.
const City=preload("res://scripts/dev/native_city_construction.gd")
const Session=preload("res://scripts/dev/native_map_edit_session.gd")
const PALETTES: Dictionary={
	"residential":[["house","House.png",12,17],["house","House2.png",12,17],["house","House3.png",13,18]],
	"commercial":[["building","CornerShop.png",22,26],["building","Diner.png",24,24],["building","Office1.png",22,29]],
	"industrial":[["warehouse","Warehouse.png",28,37],["garage","Service Garage.png",20,21]],
	"downtown":[["building","Apartment.png",26,32],["building","Office2.png",26,32],["building","Hotel.png",28,35],["building","Skyscraper.png",29,35]]
}
const ART_ROOT="Map Building Assets/Buildings/"

static func _axis(start: float,count: int,spacing: float,variation: float,rng: RandomNumberGenerator) -> Array[float]:
	var result: Array[float]=[start]
	var weights: Array[float]=[]
	var total:=0.0
	for i in count:
		var weight:=rng.randf_range(1.0-variation,1.0+variation)
		weights.append(weight);total+=weight
	for weight in weights:result.append(result[-1]+weight/total*count*spacing)
	return result

static func _region(name: String,biome: String,rect: Rect2) -> Dictionary:
	return {"name":name,"biome":biome,"points":[City._point(rect.position),City._point(Vector2(rect.end.x,rect.position.y)),City._point(rect.end),City._point(Vector2(rect.position.x,rect.end.y))]}

static func _district(style: String,x: int,y: int,columns: int,rows: int) -> String:
	if style!="mixed use":return style
	if x==columns/2 and y==rows/2:return "downtown"
	if y==rows-1 and x==columns-1:return "industrial"
	if x==columns/2 or y==rows/2:return "commercial"
	return "residential"

static func _building(entry: Array,p: Vector2,rotation: float,scale: float) -> Dictionary:
	var kind:=str(entry[0])
	var relative:=ART_ROOT+str(entry[1])
	var prop:=City._prop(kind,p,rotation,scale)
	prop.name=str(entry[1]).get_basename()
	if FileAccess.file_exists("res://assets/"+relative):
		prop.type=kind;prop.assetPath=relative
		prop.assetId="project-"+relative.sha256_text().substr(0,24)
		prop.assetSize=[float(entry[2]),float(entry[3])]
		prop.assetCollision="solid"
	else:
		if kind=="building":prop=City._prop("shop",p,rotation,scale)
	# Zero degrees faces the upper edge of the sprite.
	prop["roadFacing"]=true;prop["roadFront"]=0
	return prop

static func _reserve(index: Dictionary,prop: Dictionary,pad: float=2.0) -> void:
	var at:=Vector2(prop.x,prop.y)
	var radius:=City._prop_radius(prop)+pad
	for key in City._keys(Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2)):
		if not index.has(key):index[key]=[]
		index[key].append({"p":at,"radius":radius})

static func _build_frontage(doc: Dictionary,index: Dictionary,props: Array,block: Rect2,style: String,settings: Dictionary,rng: RandomNumberGenerator,limit: int,parking: bool) -> int:
	var palette: Array=PALETTES[style]
	var density:=clampf(float(settings.get("density",.7)),0.0,1.0)
	var count:=0
	# Lots line both side streets. The frontage margins protect the
	# intersection approaches and leave the central parking corridor free.
	for side in [0,1]:
		var available:=block.size.y-20.0
		var pitch:=26.0 if style=="residential" else 44.0
		var slots:=maxi(1,floori(available/pitch))
		for i in slots:
			if rng.randf()>density:continue
			var entry: Array=palette[rng.randi_range(0,palette.size()-1)]
			var scale:=rng.randf_range(.82,1.05)
			var radius:=Vector2(float(entry[2]),float(entry[3])).length()*.5*scale+3.0
			var x:=block.position.x+radius+3.0 if side==0 else block.end.x-radius-3.0
			var y:=block.position.y+10.0+(i+.5)*available/slots
			var at:=Vector2(x,y)
			if parking and absf(at.x-block.get_center().x)<radius+24.0:continue
			if not block.encloses(Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2)):continue
			if not City._free(index,at,radius):continue
			if doc.props.size()+props.size()>=limit:return count
			var prop:=_building(entry,at,-90.0 if side==0 else 90.0,scale)
			props.append(prop);_reserve(index,prop);count+=1
	return count

static func _park(doc: Dictionary,index: Dictionary,props: Array,area: Rect2,rng: RandomNumberGenerator,limit: int) -> void:
	# Two pedestrian paths cross through the green, with trees kept away
	# from the path centre and the bounding road clearance.
	var center:=area.get_center()
	for ends in [[Vector2(area.position.x+5,center.y),Vector2(area.end.x-5,center.y)],[Vector2(center.x,area.position.y+5),Vector2(center.x,area.end.y-5)]]:
		if doc.props.size()+props.size()>=limit:return
		props.append(City._walk(ends[0],ends[1]))
	for sy in [-1,1]:
		for sx in [-1,1]:
			for i in 3:
				var p:=center+Vector2(sx*area.size.x*rng.randf_range(.15,.34),sy*area.size.y*rng.randf_range(.15,.34))
				City._place(doc,index,props,"tree" if i<2 else "bush",p,0.0,rng.randf_range(.8,1.2),limit)

static func plan_neighborhood(doc: Dictionary,center: Vector2,settings: Dictionary,road_limit: int,prop_limit: int) -> Dictionary:
	var columns:=clampi(int(settings.get("columns",3)),2,8)
	var rows:=clampi(int(settings.get("rows",3)),2,8)
	var spacing:=clampf(float(settings.get("block",160)),120.0,300.0)
	var width:=clampf(float(settings.get("width",12)),10.0,20.0)
	var variation:=clampf(float(settings.get("variation",18))/100.0,0.0,.22)
	var style:=str(settings.get("neighborhood_style","mixed use"))
	if style!="mixed use" and not PALETTES.has(style):return City._error("Unsupported neighborhood style.")
	var extent:=Vector2(columns,rows)*spacing
	var area:=Rect2(center-extent*.5,extent)
	if not City._vacant(doc,area.grow(width+10.0)):return City._error("Neighborhood needs a clear dry area inside the map.")
	if not doc.get("customMap",false) and not bool(settings.get("connect",false)):return City._error("Connect the neighborhood to the existing Morrow road network.")
	var rng:=RandomNumberGenerator.new();rng.seed=int(settings.get("seed",1847))
	var xs:=_axis(area.position.x,columns,spacing,variation,rng)
	var ys:=_axis(area.position.y,rows,spacing,variation,rng)
	var roads: Array=[];var props: Array=[];var regions: Array=[]
	var number:=City._next_road(doc)
	var arterial_width:=maxf(18.0,width)
	for x in xs.size():
		var arterial:=x==columns/2
		var road:=City._road(number,Vector2(xs[x],ys[0]),Vector2(xs[x],ys[-1]),arterial_width if arterial else width,4 if arterial else 2)
		road.name="Neighborhood avenue" if arterial else "Neighborhood street"
		roads.append(road);number+=1
	for y in ys.size():
		var arterial:=y==rows/2
		var road:=City._road(number,Vector2(xs[0],ys[y]),Vector2(xs[-1],ys[y]),arterial_width if arterial else width,4 if arterial else 2)
		road.name="Neighborhood avenue" if arterial else "Neighborhood street"
		roads.append(road);number+=1
	if bool(settings.get("connect",false)):
		var link:=City._grid_link(doc,roads,area,width,2,number)
		if link.is_empty():return City._error("No clear compatible endpoint within 300 m. Move closer to an existing road.")
		roads.append(link);number+=1
	if doc.roads.size()+roads.size()>road_limit:return City._error("Not enough road capacity.")
	if doc.regions.size()+columns*rows>220:return City._error("Not enough terrain region capacity.")
	var draft:=doc.duplicate(false);draft.roads=doc.roads+roads
	var index:=City._index(draft)
	var inset:=arterial_width*.5+7.0
	var stats: Dictionary={"buildings":0,"parking":0,"parks":0,"driveways":0,"districts":{}}
	for y in rows:
		for x in columns:
			var bounds:=Rect2(Vector2(xs[x],ys[y]),Vector2(xs[x+1]-xs[x],ys[y+1]-ys[y])).grow(-inset)
			var district:=_district(style,x,y,columns,rows)
			var park:=bool(settings.get("parks",true)) and ((x==0 and y==rows-1) or (columns>=5 and x==columns-1 and y==0))
			if park:
				regions.append(_region("Neighborhood park","grass",bounds))
				_park(draft,index,props,bounds,rng,prop_limit);stats.parks+=1
				continue
			regions.append(_region(district.capitalize()+" block","grass" if district=="residential" else "city",bounds))
			stats.districts[district]=int(stats.districts.get(district,0))+1
			var parking:=bool(settings.get("parking",true)) and district!="residential" and bounds.size.x>=90 and bounds.size.y>=72
			if parking and doc.roads.size()+roads.size()<road_limit and doc.props.size()+props.size()<prop_limit:
				var lot_at:=Vector2(bounds.get_center().x,bounds.position.y+30)
				var lot:=City._prop("parking",lot_at,0.0,1.0)
				var radius:=City._prop_radius(lot)+2.0
				if City._free(index,lot_at,radius):
					var entrance:=Vector2(lot_at.x,ys[y])
					var drive:=City._road(number,entrance,lot_at,8.0,2)
					drive.roadClass="service";drive.name="Parking access"
					roads.append(drive);number+=1
					props.append(lot);_reserve(index,lot)
					# Reserve the driveway corridor before frontage placement.
					for key in City._keys(Rect2(entrance,lot_at-entrance).abs().grow(7.0)):
						if not index.has(key):index[key]=[]
						index[key].append({"a":entrance,"b":lot_at,"pad":7.0})
					stats.parking+=1;stats.driveways+=1
				else:parking=false
			else:parking=false
			if bool(settings.get("buildings",true)):
				stats.buildings+=_build_frontage(draft,index,props,bounds,district,settings,rng,prop_limit,parking)
			if bool(settings.get("sidewalks",true)):
				for edge in [[bounds.position,Vector2(bounds.end.x,bounds.position.y)],[Vector2(bounds.position.x,bounds.end.y),bounds.end],[bounds.position,Vector2(bounds.position.x,bounds.end.y)],[Vector2(bounds.end.x,bounds.position.y),bounds.end]]:
					# Split the frontage path around the driveway mouth.
					var a: Vector2=edge[0];var c: Vector2=edge[1]
					if parking and a.y==bounds.position.y and c.y==a.y:
						var mid:=bounds.get_center().x
						props.append(City._walk(a,Vector2(mid-5,a.y)))
						props.append(City._walk(Vector2(mid+5,a.y),c))
					else:props.append(City._walk(a,c))
	if doc.props.size()+props.size()>prop_limit:return City._error("Neighborhood exceeds remaining scenery capacity. Reduce size or density.")
	return {"roads":roads,"props":props,"regions":regions,"area":area,"label":"Advanced "+style+" neighborhood","stats":stats}

## A grade-separated diamond with distinct one-way entry and exit roads.
## Each entrance terminates at an interior highway merge on the right.
## Exit junctions are conventional T connections, not dedicated diverge rules.
static func plan_diamond(doc: Dictionary,center: Vector2,settings: Dictionary,limit: int) -> Dictionary:
	if not doc.get("customMap",false):return City._error("Directional diamond generation currently supports custom maps.")
	var span:=clampf(float(settings.get("interchange_span",240)),180,500)
	var area:=Rect2(center-Vector2(span*1.5+40,span+40),Vector2(span*3+80,span*2+80))
	if not City._vacant(doc,area):return City._error("Choose a clear dry interchange area.")
	if doc.roads.size()+6>limit:return City._error("Not enough remaining road capacity.")
	var n:=City._next_road(doc)
	var highway:=City._grade_road(n,center+Vector2(-span*1.5,0),center+Vector2(span*1.5,0),24,4,1,1,"Directional diamond highway")
	highway.roadClass="highway"
	var cross:=City._grade_road(n+1,center+Vector2(0,-span),center+Vector2(0,span),14,2,0,0,"Diamond cross street")
	var roads: Array=[highway,cross]
	n+=2
	for side in [-1,1]:
		var local:=center+Vector2(0,side*span*.56)
		var exit_at:=center+Vector2(-side*span*.9,0)
		var entry_at:=center+Vector2(side*span*.9,0)
		var exit:=City._grade_road(n,exit_at,local,8,1,1,0,"One-way highway exit")
		exit.roadClass="onramp";exit.junctionStart="intersection";exit.junctionEnd="intersection"
		roads.append(exit);n+=1
		var entry:=City._grade_road(n,local,entry_at,8,1,0,1,"One-way highway entrance")
		entry.roadClass="onramp";entry.junctionStart="intersection";entry.junctionEnd="merge"
		roads.append(entry);n+=1
	return {"roads":roads,"props":[],"regions":[],"area":area,"label":"Directional diamond interchange","stats":{"entrances":2,"exits":2,"grade_separated":true}}

## Bake a temporary copy through the real custom-world compiler. The session
## validates the source and allocates IDs exactly as the normal Apply does.
static func preflight(doc: Dictionary,plan: Dictionary) -> Dictionary:
	if not doc.get("customMap",false):return {"ok":false,"message":"Production scratch bake supports custom maps only. Use the normal Morrow rebake after applying."}
	var session:=Session.new()
	session.doc=doc.duplicate(true)
	if session.apply_construction(plan).is_empty():return {"ok":false,"message":session.last_error}
	var root:=ProjectSettings.globalize_path("user://construction-preflight-%d"%OS.get_process_id())
	var source:=root+".world.json";var output:=root+".stream.json"
	var file:=FileAccess.open(source,FileAccess.WRITE)
	if file==null:return {"ok":false,"message":"Unable to create scratch source."}
	file.store_string(JSON.stringify(session.doc));file.close()
	if FileAccess.file_exists(output):DirAccess.remove_absolute(output)
	var python: String="py" if OS.get_name()=="Windows" else "python3"
	var args:=PackedStringArray([ProjectSettings.globalize_path("res://tools/build_custom_test_world.py"),"--source",source,"--output",output])
	if OS.get_name()=="Windows":args.insert(0,"-3")
	var logs: Array=[]
	var code:=OS.execute(python,args,logs,true)
	DirAccess.remove_absolute(source)
	if code!=0 or not FileAccess.file_exists(output):
		if FileAccess.file_exists(output):DirAccess.remove_absolute(output)
		return {"ok":false,"message":str(logs).right(650)}
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(output))
	DirAccess.remove_absolute(output)
	if not raw is Dictionary:return {"ok":false,"message":"Invalid scratch archive."}
	var merges:=0
	for junction in raw.get("junctions",[]):
		if junction.get("kind","")=="merge":merges+=1
	if plan.label=="Directional diamond interchange" and merges<2:return {"ok":false,"message":"Compiler did not create both entry merges."}
	return {"ok":true,"message":"Production bake passed: %d roads, %d junctions, %d merges."%[raw.roads.size(),raw.junctions.size(),merges],"merges":merges}
